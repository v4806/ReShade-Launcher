#include "game/game.h"

#include <tlhelp32.h>
#include <shlobj.h>
#include <shellapi.h>
#include <shobjidl.h>

#include <algorithm>
#include <charconv>
#include <fstream>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <unordered_map>

#include "miniz.h"

namespace rs {
namespace {

constexpr DWORD kCreateSuspended = 0x00000004;
constexpr DWORD kCreateUnicodeEnvironment = 0x00000400;
constexpr DWORD kCreateNoWindow = 0x08000000;

std::vector<DWORD> SnapshotPids() {
    std::vector<DWORD> pids;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return pids;
    }
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry)) {
        do {
            pids.push_back(entry.th32ProcessID);
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return pids;
}

std::filesystem::path ProcessPath(HANDLE process) {
    std::wstring buffer(32768, L'\0');
    DWORD size = static_cast<DWORD>(buffer.size());
    if (!QueryFullProcessImageNameW(process, 0, buffer.data(), &size)) {
        return {};
    }
    buffer.resize(size);
    return buffer;
}

bool IsDescendant(DWORD child, DWORD parent) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return false;
    }
    std::unordered_map<DWORD, DWORD> parents;
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry)) {
        do {
            parents[entry.th32ProcessID] = entry.th32ParentProcessID;
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    for (int depth = 0; depth < 64 && child != 0; ++depth) {
        if (child == parent) {
            return true;
        }
        const auto it = parents.find(child);
        if (it == parents.end()) {
            break;
        }
        child = it->second;
    }
    return false;
}

std::vector<DWORD> SnapshotProcessTree(DWORD root) {
    std::vector<DWORD> result;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return result;
    }
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (entry.th32ProcessID == root || IsDescendant(entry.th32ProcessID, root)) {
                result.push_back(entry.th32ProcessID);
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return result;
}

enum class ModuleVisibility {
    NotLoaded,
    Loaded,
    Unknown,
};

ModuleVisibility QueryModule(DWORD pid, const std::filesystem::path& file) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return ModuleVisibility::Unknown;
    }
    MODULEENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    std::error_code ec;
    auto expected_path = std::filesystem::weakly_canonical(file, ec);
    if (ec) expected_path = std::filesystem::absolute(file, ec);
    const auto expected = ToLower(expected_path.wstring());
    if (Module32FirstW(snapshot, &entry)) {
        do {
            if (ToLower(entry.szExePath) == expected) {
                CloseHandle(snapshot);
                return ModuleVisibility::Loaded;
            }
        } while (Module32NextW(snapshot, &entry));
    }
    const DWORD enumeration_error = GetLastError();
    CloseHandle(snapshot);
    return enumeration_error == ERROR_NO_MORE_FILES
               ? ModuleVisibility::NotLoaded
               : ModuleVisibility::Unknown;
}

bool ReplaceD3dxTarget(const std::filesystem::path& dll_path,
                       std::wstring_view target_exe,
                       std::vector<std::pair<std::filesystem::path, std::string>>* backups) {
    const auto d3dx = dll_path.parent_path() / L"d3dx.ini";
    auto contents = ReadUtf8(d3dx);
    if (!contents) {
        return true;
    }
    const std::regex target_re(
        R"((^|[\r\n])([ \t]*target[ \t]*=[ \t]*)([^\r\n]*))",
        std::regex_constants::ECMAScript | std::regex_constants::icase);
    std::smatch match;
    if (!std::regex_search(*contents, match, target_re)) {
        return true;
    }
    backups->emplace_back(d3dx, *contents);
    const std::string replacement =
        match.str(1) + match.str(2) + WideToUtf8(target_exe);
    contents->replace(static_cast<size_t>(match.position()),
                      static_cast<size_t>(match.length()), replacement);
    return WriteUtf8Atomic(d3dx, *contents);
}

void RestoreBackups(
    const std::vector<std::pair<std::filesystem::path, std::string>>& backups) {
    for (const auto& [path, contents] : backups) {
        WriteUtf8Atomic(path, contents);
    }
}

std::string EscapeCommand(std::wstring_view value) {
    return WideToUtf8(value);
}

std::filesystem::path KnownFolder(REFKNOWNFOLDERID id) {
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(id, 0, nullptr, &raw))) {
        return {};
    }
    std::filesystem::path result(raw);
    CoTaskMemFree(raw);
    return result;
}

bool PathContainsInsensitive(std::wstring_view needle, std::wstring_view haystack) {
    return ToLower(haystack).find(ToLower(needle)) != std::wstring::npos;
}

std::optional<std::pair<std::string, std::string>> ParseIniAssignment(
    std::string_view line) {
    const auto equal = line.find('=');
    if (equal == std::string_view::npos) {
        return std::nullopt;
    }
    std::string key(line.substr(0, equal));
    std::string value(line.substr(equal + 1));
    const auto first = key.find_first_not_of(" \t");
    const auto last = key.find_last_not_of(" \t");
    if (first == std::string::npos) {
        return std::nullopt;
    }
    key = key.substr(first, last - first + 1);
    const auto value_first = value.find_first_not_of(" \t\r\n");
    const auto value_last = value.find_last_not_of(" \t\r\n");
    value = value_first == std::string::npos
                ? std::string{}
                : value.substr(value_first, value_last - value_first + 1);
    return std::make_pair(std::move(key), std::move(value));
}

std::string LastPathComponent(std::string value) {
    std::replace(value.begin(), value.end(), '/', '\\');
    const auto pos = value.rfind('\\');
    return pos == std::string::npos ? value : value.substr(pos + 1);
}

std::string Lower(std::string value) {
    return ToLower(value);
}

std::wstring PathKey(const std::filesystem::path& path) {
    std::error_code ec;
    auto normalized = std::filesystem::weakly_canonical(path, ec);
    if (ec) normalized = path.lexically_normal();
    return ToLower(normalized.wstring());
}

void AppendUniquePath(std::vector<std::filesystem::path>* paths,
                      const std::filesystem::path& path) {
    const auto key = PathKey(path);
    const auto existing =
        std::find_if(paths->begin(), paths->end(),
                     [&](const auto& item) { return PathKey(item) == key; });
    if (existing == paths->end()) paths->push_back(path);
}

void TerminateProcessTrees(const std::vector<DWORD>& pids) {
    for (DWORD pid : pids) {
        if (pid == 0 || pid == GetCurrentProcessId()) continue;
        const auto tree = SnapshotProcessTree(pid);
        for (auto it = tree.rbegin(); it != tree.rend(); ++it) {
            if (*it == GetCurrentProcessId()) continue;
            HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, *it);
            if (process) {
                TerminateProcess(process, 1);
                CloseHandle(process);
            }
        }
    }
}

}  // namespace

LaunchSession::LaunchSession(LaunchSession&& other) noexcept
    : process(other.process), root_pid(other.root_pid), target_pid(other.target_pid),
      extra_pids(std::move(other.extra_pids)) {
    other.process = nullptr;
}

LaunchSession& LaunchSession::operator=(LaunchSession&& other) noexcept {
    if (this != &other) {
        Close();
        process = other.process;
        root_pid = other.root_pid;
        target_pid = other.target_pid;
        extra_pids = std::move(other.extra_pids);
        other.process = nullptr;
    }
    return *this;
}

LaunchSession::~LaunchSession() { Close(); }

void LaunchSession::Close() {
    if (process) {
        CloseHandle(process);
        process = nullptr;
    }
}

Injector::Injector(const std::filesystem::path& dll) {
    module_ = LoadLibraryW(dll.c_str());
    if (!module_) {
        return;
    }
    inject_ = reinterpret_cast<InjectFn>(GetProcAddress(module_, "Inject"));
    hook_ = reinterpret_cast<HookFn>(GetProcAddress(module_, "HookLibraryByPid"));
    unhook_ = reinterpret_cast<UnhookFn>(GetProcAddress(module_, "UnhookLibraryByPid"));
    if (!inject_) {
        FreeLibrary(module_);
        module_ = nullptr;
    }
}

Injector::~Injector() {
    Unhook();
    if (module_) {
        FreeLibrary(module_);
    }
}

bool Injector::Inject(DWORD pid, const std::filesystem::path& dll, int timeout_seconds,
                      std::string* error) {
    if (!inject_) {
        if (error) *error = "3dmloader.dll missing Inject export";
        return false;
    }
    if (inject_(pid, dll.c_str(), timeout_seconds) == 0) {
        return true;
    }
    if (error) *error = "native Inject failed";
    return false;
}

bool Injector::Hook(DWORD pid, const std::filesystem::path& dll, std::string* error) {
    if (!hook_) {
        if (error) *error = "3dmloader.dll missing HookLibraryByPid export";
        return false;
    }
    if (hook_(dll.c_str(), pid, &hook_handle_, &mutex_) == 0) {
        return true;
    }
    if (error) *error = "native HookLibraryByPid failed";
    return false;
}

void Injector::Unhook() {
    if (hook_ && unhook_ && hook_handle_) {
        unhook_(&hook_handle_, &mutex_);
    }
    hook_handle_ = nullptr;
    mutex_ = nullptr;
}

ProcessManager::ProcessManager(const AppData& app) : app_(app) {}

std::filesystem::path ProcessManager::ResolveRuntimeFile(std::wstring_view relative) const {
    return app_.resource_path(relative);
}

InjectionPlan ProcessManager::BuildInjectionPlan(const Json& config,
                                                 std::string* error) const {
    InjectionPlan plan;
    plan.method = Utf8ToWide(ToLower(config.value("injection_method", "direct")));
    if (plan.method != L"direct" && plan.method != L"hook") {
        if (error) *error = "unsupported injection_method";
        return {};
    }
    if (config.contains("reshade_dll") &&
        config["reshade_dll"].is_string() &&
        !config["reshade_dll"].get<std::string>().empty()) {
        AppendUniquePath(&plan.direct_dlls,
                         ResolveRuntimeFile(L"ReShade/ReShade64.dll"));
    }
    if (config.contains("d3d11_path") && config["d3d11_path"].is_string()) {
        AppendUniquePath(
            &plan.direct_dlls,
            Utf8ToWide(config["d3d11_path"].get<std::string>()));
    } else if (config.value("mode", "") == "builtin" &&
               config.contains("mod_loader_dir") &&
               config["mod_loader_dir"].is_string()) {
        const std::filesystem::path loader_dir =
            Utf8ToWide(config["mod_loader_dir"].get<std::string>());
        const auto fallback = loader_dir / L"d3d11.dll";
        if (!FileExists(fallback)) {
            if (error) {
                *error = "Built-in Mod loader not found: " +
                         WideToUtf8(fallback.wstring());
            }
            return {};
        }
        AppendUniquePath(&plan.direct_dlls, fallback);
    }
    if (config.contains("dll_files") && config["dll_files"].is_array()) {
        for (const auto& path : config["dll_files"]) {
            if (path.is_string()) {
                AppendUniquePath(&plan.direct_dlls,
                                 Utf8ToWide(path.get<std::string>()));
            }
        }
    }
    for (const auto& dll : plan.direct_dlls) {
        if (!FileExists(dll)) {
            if (error) *error = "DLL not found: " + WideToUtf8(dll.wstring());
            return {};
        }
    }
    if (plan.method == L"hook") {
        if (config.contains("d3d11_path") && config["d3d11_path"].is_string()) {
            plan.hook_dll = Utf8ToWide(config["d3d11_path"].get<std::string>());
        } else {
            const auto candidate =
                std::find_if(plan.direct_dlls.begin(), plan.direct_dlls.end(),
                             [](const auto& path) {
                                 return _wcsicmp(path.filename().c_str(),
                                                 L"d3d11.dll") == 0;
                             });
            if (candidate != plan.direct_dlls.end()) plan.hook_dll = *candidate;
        }
        if (plan.hook_dll.empty()) {
            if (error) *error = "HOOK requires d3d11.dll";
            return {};
        }
        if (!FileExists(plan.hook_dll)) {
            if (error) *error = "HOOK DLL not found";
            return {};
        }
        const auto launch = std::filesystem::weakly_canonical(
            Utf8ToWide(config.value("launch_program", "")));
        const auto target = std::filesystem::weakly_canonical(
            Utf8ToWide(config.value("target_program", "")));
        if (ToLower(launch.wstring()) != ToLower(target.wstring())) {
            if (error) *error = "HOOK requires launch_program == target_program";
            return {};
        }
        const auto hook_key = PathKey(plan.hook_dll);
        plan.direct_dlls.erase(
            std::remove_if(plan.direct_dlls.begin(), plan.direct_dlls.end(),
                           [&](const auto& value) {
                               return PathKey(value) == hook_key;
                           }),
            plan.direct_dlls.end());
    }
    return plan;
}

ProcessManager::ModuleState ProcessManager::WaitForModule(
    DWORD pid, const std::filesystem::path& dll, int timeout_seconds) const {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(timeout_seconds);
    ModuleState last = ModuleState::Unknown;
    while (std::chrono::steady_clock::now() < deadline) {
        switch (QueryModule(pid, dll)) {
            case ModuleVisibility::Loaded:
                return ModuleState::Loaded;
            case ModuleVisibility::NotLoaded:
                last = ModuleState::NotLoaded;
                break;
            case ModuleVisibility::Unknown:
                break;
        }
        Sleep(50);
    }
    switch (QueryModule(pid, dll)) {
        case ModuleVisibility::Loaded:
            return ModuleState::Loaded;
        case ModuleVisibility::NotLoaded:
            return ModuleState::NotLoaded;
        case ModuleVisibility::Unknown:
            return last;
    }
    return last;
}

bool ProcessManager::InjectAndVerify(
    Injector& injector, DWORD pid, const std::vector<std::filesystem::path>& dlls,
    std::string* error, LogCallback log) {
    std::vector<std::filesystem::path> injected;
    for (const auto& dll : dlls) {
        std::string inject_error;
        if (injector.Inject(pid, dll, 15, &inject_error)) {
            injected.push_back(dll);
            if (log) log("Injected: " + WideToUtf8(dll.filename().wstring()));
        } else {
            if (log) log("Injection failed: " + WideToUtf8(dll.wstring()) + " " + inject_error);
            if (error && error->empty()) *error = inject_error;
        }
    }
    for (const auto& dll : injected) {
        const ModuleState state = WaitForModule(pid, dll, 5);
        if (state == ModuleState::Unknown) {
            if (log) {
                log("Module enumeration unavailable after injection: " +
                    WideToUtf8(dll.filename().wstring()));
            }
        } else if (state == ModuleState::NotLoaded) {
            if (error && error->empty()) {
                *error = "module verification failed: " +
                         WideToUtf8(dll.filename().wstring());
            }
        }
    }
    return error == nullptr || error->empty();
}

bool ProcessManager::RunPreLaunch(const Json& config,
                                  const std::filesystem::path& launch_program,
                                  std::vector<DWORD>* process_tree,
                                  LogCallback log) const {
    if (process_tree) process_tree->clear();
    const auto command = config.value("pre_launch_command", "");
    if (command.empty()) {
        return true;
    }
    const auto wait = std::clamp(config.value("pre_launch_wait_seconds", 0), 0, 300);
    std::wstring command_line = L"cmd.exe /c " + Utf8ToWide(command);
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(nullptr, command_line.data(), nullptr, nullptr, FALSE,
                        kCreateNoWindow | kCreateUnicodeEnvironment, nullptr,
                        launch_program.parent_path().c_str(), &startup, &process)) {
        if (log) log("Pre-launch command failed: " + WideToUtf8(FormatLastError()));
        return false;
    }

    std::set<DWORD> related;
    const auto collect_until = std::chrono::steady_clock::now() +
                               std::chrono::milliseconds(
                                   std::max(300, wait * 1000));
    while (std::chrono::steady_clock::now() < collect_until) {
        for (DWORD pid : SnapshotProcessTree(process.dwProcessId)) {
            related.insert(pid);
        }
        Sleep(50);
    }

    DWORD exit_code = 0;
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    if (process_tree) {
        process_tree->assign(related.begin(), related.end());
    }
    if (exit_code != 0 && exit_code != STILL_ACTIVE) {
        if (log) {
            log("Pre-launch command exited with code " +
                std::to_string(exit_code));
        }
        return false;
    }
    return true;
}

std::optional<DWORD> ProcessManager::WaitForTargetPid(
    DWORD root_pid, const std::filesystem::path& target_program,
    const std::string& game_exe_name, int timeout_seconds,
    const std::set<DWORD>& baseline, LogCallback log,
    std::string* error) const {
    if (error) error->clear();
    const std::wstring target_exe_name = target_program.filename().wstring();
    const std::wstring target_key = PathKey(target_program);
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(std::max(1, timeout_seconds));
    while (std::chrono::steady_clock::now() < deadline) {
        std::vector<std::pair<DWORD, bool>> exact_candidates;
        std::vector<DWORD> descendant_candidates;
        std::vector<DWORD> name_candidates;
        HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshot != INVALID_HANDLE_VALUE) {
            PROCESSENTRY32W entry{};
            entry.dwSize = sizeof(entry);
            if (Process32FirstW(snapshot, &entry)) {
                do {
                    if (baseline.contains(entry.th32ProcessID)) {
                        continue;
                    }
                    const bool name_match =
                        _wcsicmp(entry.szExeFile, target_exe_name.c_str()) == 0 ||
                        (!game_exe_name.empty() &&
                         _wcsicmp(entry.szExeFile, Utf8ToWide(game_exe_name).c_str()) == 0);
                    if (!name_match) continue;

                    HANDLE candidate = OpenProcess(
                        PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                        entry.th32ProcessID);
                    std::filesystem::path candidate_path;
                    if (candidate) {
                        candidate_path = ProcessPath(candidate);
                        CloseHandle(candidate);
                    }
                    const bool exact_match =
                        !candidate_path.empty() &&
                        PathKey(candidate_path) == target_key;
                    const bool descendant =
                        IsDescendant(entry.th32ProcessID, root_pid);
                    name_candidates.push_back(entry.th32ProcessID);
                    if (exact_match) {
                        exact_candidates.emplace_back(entry.th32ProcessID,
                                                      descendant);
                    } else if (descendant) {
                        descendant_candidates.push_back(entry.th32ProcessID);
                    }
                } while (Process32NextW(snapshot, &entry));
            }
            CloseHandle(snapshot);
        }

        if (exact_candidates.size() == 1) {
            return exact_candidates.front().first;
        }
        if (descendant_candidates.size() == 1) {
            return descendant_candidates.front();
        }
        if (name_candidates.size() == 1) {
            return name_candidates.front();
        }
        if (exact_candidates.size() > 1 || descendant_candidates.size() > 1 ||
            name_candidates.size() > 1) {
            if (error) {
                *error = "Multiple target processes found for PID chain " +
                         std::to_string(root_pid);
            }
            return std::nullopt;
        }
        if (log) log("Waiting for target process...");
        Sleep(200);
    }
    if (error) *error = "Target process did not start in time";
    return std::nullopt;
}

LaunchResult ProcessManager::Launch(const Json& config, LogCallback log) {
    std::string plan_error;
    const auto plan = BuildInjectionPlan(config, &plan_error);
    if (!plan_error.empty()) {
        return {LaunchSession{}, plan_error};
    }
    const auto injector_path = ResolveRuntimeFile(L"3dmloader.dll");
    if (!FileExists(injector_path)) {
        return {LaunchSession{}, "3dmloader.dll not found"};
    }

    const std::filesystem::path launch_program =
        Utf8ToWide(config.value("launch_program", config.value("game_dir", "")));
    const std::filesystem::path target_program =
        Utf8ToWide(config.value("target_program", config.value("game_dir", "")));
    if (!FileExists(launch_program)) {
        return {LaunchSession{}, "launch_program not found: " +
                                     WideToUtf8(launch_program.wstring())};
    }
    std::vector<DWORD> pre_launch_pids;
    if (!RunPreLaunch(config, launch_program, &pre_launch_pids, log)) {
        TerminateProcessTrees(pre_launch_pids);
        return {LaunchSession{}, "pre-launch command failed"};
    }

    const auto baseline_vector = SnapshotPids();
    const std::set<DWORD> baseline(baseline_vector.begin(), baseline_vector.end());

    std::wstring command = L"\"" + launch_program.wstring() + L"\"";
    const auto args = Utf8ToWide(config.value("launch_args", ""));
    if (!args.empty()) {
        command += L" " + args;
    }
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_SHOWNORMAL;
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(launch_program.c_str(), command.data(), nullptr, nullptr, FALSE,
                        kCreateSuspended | kCreateUnicodeEnvironment, nullptr,
                        launch_program.parent_path().c_str(), &startup, &process)) {
        TerminateProcessTrees(pre_launch_pids);
        return {LaunchSession{}, "CreateProcessW failed: " +
                                     WideToUtf8(FormatLastError())};
    }

    Injector injector(injector_path);
    if (!injector.valid()) {
        TerminateProcess(process.hProcess, 1);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        TerminateProcessTrees(pre_launch_pids);
        return {LaunchSession{}, "failed to load 3dmloader.dll"};
    }

    std::vector<std::pair<std::filesystem::path, std::string>> d3dx_backups;
    std::string injection_error;
    const bool same_exe =
        PathKey(launch_program) == PathKey(target_program);
    std::vector<std::filesystem::path> temporary_target_dlls = plan.direct_dlls;
    if (!plan.hook_dll.empty()) {
        temporary_target_dlls.insert(temporary_target_dlls.begin(), plan.hook_dll);
    }
    for (const auto& dll : temporary_target_dlls) {
        if (_wcsicmp(dll.filename().c_str(), L"d3d11.dll") == 0) {
            if (!ReplaceD3dxTarget(
                    dll, target_program.filename().wstring(),
                    &d3dx_backups)) {
                RestoreBackups(d3dx_backups);
                TerminateProcess(process.hProcess, 1);
                CloseHandle(process.hThread);
                CloseHandle(process.hProcess);
                TerminateProcessTrees(pre_launch_pids);
                return {LaunchSession{}, "Cannot update d3dx.ini for the target game"};
            }
            break;
        }
    }

    DWORD target_pid = process.dwProcessId;
    if (plan.method == L"hook") {
        if (!same_exe || !injector.Hook(process.dwProcessId, plan.hook_dll, &injection_error)) {
            TerminateProcess(process.hProcess, 1);
            injection_error = injection_error.empty() ? "HOOK requires same executable"
                                                      : injection_error;
        } else {
            ResumeThread(process.hThread);
            const ModuleState hook_state =
                WaitForModule(process.dwProcessId, plan.hook_dll, 10);
            if (hook_state == ModuleState::NotLoaded) {
                injection_error = "Hook module was not loaded";
            } else if (hook_state == ModuleState::Unknown) {
                if (log) {
                    log("Hook module enumeration unavailable after injection: " +
                        WideToUtf8(plan.hook_dll.filename().wstring()));
                }
                InjectAndVerify(injector, process.dwProcessId, plan.direct_dlls,
                                &injection_error, log);
            } else {
                InjectAndVerify(injector, process.dwProcessId, plan.direct_dlls,
                                &injection_error, log);
            }
        }
    } else if (same_exe) {
        ResumeThread(process.hThread);
        InjectAndVerify(injector, process.dwProcessId, plan.direct_dlls,
                        &injection_error, log);
    } else {
        ResumeThread(process.hThread);
        std::string target_error;
        const auto target = WaitForTargetPid(
            process.dwProcessId, target_program,
            config.value("game_exe_name", ""), config.value("process_timeout", 30),
            baseline, log, &target_error);
        if (!target) {
            injection_error = target_error.empty()
                                  ? "target process not found"
                                  : target_error;
        } else {
            target_pid = *target;
            InjectAndVerify(injector, target_pid, plan.direct_dlls, &injection_error, log);
        }
    }

    RestoreBackups(d3dx_backups);
    CloseHandle(process.hThread);
    if (!injection_error.empty()) {
        TerminateProcess(process.hProcess, 1);
        CloseHandle(process.hProcess);
        if (target_pid != process.dwProcessId) {
            TerminateProcessTrees({target_pid});
        }
        TerminateProcessTrees(pre_launch_pids);
        return {LaunchSession{}, injection_error};
    }
    return {LaunchSession(process.hProcess, process.dwProcessId, target_pid,
                          std::move(pre_launch_pids)),
            {}};
}

bool ProcessManager::IsRunning(DWORD pid) const {
    if (pid == 0) return false;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return false;
    DWORD code = 0;
    const bool running = GetExitCodeProcess(process, &code) && code == STILL_ACTIVE;
    CloseHandle(process);
    return running;
}

bool ProcessManager::IsExecutableRunning(std::wstring_view exe_name) {
    return !FindProcessIdsByName(exe_name).empty();
}

bool ProcessManager::IsProcessIdPresent(DWORD pid) {
    if (pid == 0) return false;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return false;
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    bool found = false;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (entry.th32ProcessID == pid) {
                found = true;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return found;
}

std::vector<DWORD> ProcessManager::FindProcessIdsByName(
    std::wstring_view exe_name) {
    std::vector<DWORD> found;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return found;
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szExeFile, exe_name.data()) == 0) {
                found.push_back(entry.th32ProcessID);
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return found;
}

DWORD ProcessManager::FindProcessIdByName(std::wstring_view exe_name) {
    const auto matches = FindProcessIdsByName(exe_name);
    return matches.empty() ? 0 : matches.front();
}

DWORD ProcessManager::FindProcessIdByPath(
    const std::filesystem::path& executable) {
    const auto expected = PathKey(executable);
    DWORD found = 0;
    for (DWORD pid : FindProcessIdsByName(
             executable.filename().wstring())) {
        HANDLE process =
            OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (!process) continue;
        const auto path = ProcessPath(process);
        CloseHandle(process);
        if (path.empty() || PathKey(path) != expected) continue;
        if (found != 0) return 0;
        found = pid;
    }
    return found;
}

bool ProcessManager::Terminate(DWORD pid) {
    const auto pids = SnapshotProcessTree(pid);
    bool ok = true;
    for (auto it = pids.rbegin(); it != pids.rend(); ++it) {
        if (*it == GetCurrentProcessId()) continue;
        HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, *it);
        if (process) {
            ok = TerminateProcess(process, 1) != FALSE && ok;
            CloseHandle(process);
        }
    }
    return ok;
}

struct WindowSearch {
    DWORD pid;
    HWND window;
};

BOOL CALLBACK EnumWindowProc(HWND window, LPARAM param) {
    auto* search = reinterpret_cast<WindowSearch*>(param);
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid == search->pid && IsWindowVisible(window) && GetWindow(window, GW_OWNER) == nullptr) {
        search->window = window;
        return FALSE;
    }
    return TRUE;
}

DWORD ProcessManager::FindMainWindowPid(DWORD pid) {
    WindowSearch search{pid, nullptr};
    EnumWindows(EnumWindowProc, reinterpret_cast<LPARAM>(&search));
    return search.window ? pid : 0;
}

void ProcessManager::CenterWindowsForPid(DWORD pid, int duration_seconds,
                                         std::atomic_bool* stop) {
    const auto end = std::chrono::steady_clock::now() +
                     std::chrono::seconds(std::clamp(duration_seconds, 5, 120));
    while (std::chrono::steady_clock::now() < end && !(stop && stop->load())) {
        WindowSearch search{pid, nullptr};
        EnumWindows(EnumWindowProc, reinterpret_cast<LPARAM>(&search));
        if (search.window) {
            RECT rect{};
            if (GetWindowRect(search.window, &rect)) {
                const RECT work = [] {
                    MONITORINFO info{sizeof(info)};
                    GetMonitorInfoW(MonitorFromWindow(GetForegroundWindow(),
                                                       MONITOR_DEFAULTTOPRIMARY),
                                    &info);
                    return info.rcWork;
                }();
                const int width = rect.right - rect.left;
                const int height = rect.bottom - rect.top;
                const int x = work.left + (work.right - work.left - width) / 2;
                const int y = work.top + (work.bottom - work.top - height) / 2;
                SetWindowPos(search.window, nullptr, x, y, 0, 0,
                             SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
        }
        Sleep(500);
    }
}

namespace {

bool SafeArchivePath(std::string_view raw, std::filesystem::path* relative) {
    if (!relative || raw.empty() || raw.find('\0') != std::string_view::npos) {
        return false;
    }
    const std::wstring wide = Utf8ToWide(raw);
    if (wide.empty()) return false;
    std::filesystem::path value(wide);
    if (value.is_absolute() || value.has_root_name() ||
        value.has_root_directory()) {
        return false;
    }
    value = value.lexically_normal();
    if (value.empty() || value == L".") return false;
    for (const auto& part : value) {
        if (part == L"..") return false;
    }
    *relative = std::move(value);
    return true;
}

}  // namespace

bool ModLoaderManager::InstallArchive(const std::filesystem::path& archive_path,
                                      std::string_view folder_name,
                                      std::string* error) const {
    if (error) error->clear();
    if (!FileExists(archive_path) || folder_name.empty()) {
        if (error) *error = "Mod loader archive is missing.";
        return false;
    }

    const auto target =
        app_.mod_loader_dir() / Utf8ToWide(std::string(folder_name));
    const auto staging =
        app_.mod_loader_dir() /
        Utf8ToWide(std::string(folder_name) + "-stage-" +
                   std::to_string(GetCurrentProcessId()));
    std::error_code ec;
    std::filesystem::remove_all(staging, ec);
    std::filesystem::create_directories(staging, ec);
    if (ec) {
        if (error) *error = "Cannot create the Mod loader staging directory.";
        return false;
    }

    mz_zip_archive zip{};
    bool ok = mz_zip_reader_init_file(
        &zip, WideToUtf8(archive_path.wstring()).c_str(), 0);
    if (!ok) {
        std::filesystem::remove_all(staging, ec);
        if (error) *error = "Cannot open the Mod loader archive.";
        return false;
    }

    const mz_uint file_count = mz_zip_reader_get_num_files(&zip);
    for (mz_uint index = 0; index < file_count; ++index) {
        mz_zip_archive_file_stat stat{};
        if (!mz_zip_reader_file_stat(&zip, index, &stat)) {
            ok = false;
            break;
        }
        std::filesystem::path relative;
        if (!SafeArchivePath(stat.m_filename, &relative)) {
            ok = false;
            break;
        }
        if (mz_zip_reader_is_file_a_directory(&zip, index)) {
            std::filesystem::create_directories(staging / relative, ec);
            if (ec) {
                ok = false;
                break;
            }
            continue;
        }
        const auto destination = staging / relative;
        std::filesystem::create_directories(destination.parent_path(), ec);
        if (ec ||
            !mz_zip_reader_extract_to_file(
                &zip, index, WideToUtf8(destination.wstring()).c_str(), 0)) {
            ok = false;
            break;
        }
    }
    mz_zip_reader_end(&zip);
    if (!ok || !FileExists(staging / L"d3d11.dll")) {
        std::filesystem::remove_all(staging, ec);
        if (error) {
            *error = "The Mod loader archive is invalid or incomplete.";
        }
        return false;
    }

    std::filesystem::create_directories(target, ec);
    if (!ec) {
        std::filesystem::copy(
            staging, target,
            std::filesystem::copy_options::recursive |
                std::filesystem::copy_options::overwrite_existing,
            ec);
    }
    std::filesystem::remove_all(staging, ec);
    if (ec || !FileExists(target / L"d3d11.dll")) {
        if (error) *error = "Cannot install the downloaded Mod loader.";
        return false;
    }
    return true;
}

bool ShortcutService::Create(std::string_view display_name, std::string_view config_file,
                             const std::filesystem::path& game_exe) {
    const auto desktop = KnownFolder(FOLDERID_Desktop);
    if (desktop.empty()) return false;
    const auto shortcut_path =
        desktop / (L"ReShade " + Utf8ToWide(display_name) + L".lnk");
    IShellLinkW* shell_link = nullptr;
    IPersistFile* persist = nullptr;
    bool ok = false;
    if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&shell_link)))) {
        shell_link->SetPath(ExecutablePath().c_str());
        shell_link->SetArguments((L"\"" + Utf8ToWide(config_file) + L".json\"").c_str());
        shell_link->SetWorkingDirectory(ExecutableDirectory().c_str());
        if (FileExists(game_exe)) {
            shell_link->SetIconLocation(game_exe.c_str(), 0);
        }
        ok = SUCCEEDED(shell_link->QueryInterface(IID_PPV_ARGS(&persist))) &&
             SUCCEEDED(persist->Save(shortcut_path.c_str(), TRUE));
    }
    if (persist) persist->Release();
    if (shell_link) shell_link->Release();
    return ok;
}

ModPresetResult ModPresetService::Apply(
    const std::filesystem::path& d3dx_user_ini,
    const std::filesystem::path& mods_directory,
    std::function<void(const std::string&)> progress) {
    ModPresetResult result;
    auto add_log = [&](const std::string& text) {
        result.log.push_back(text);
        if (progress) {
            try {
                progress(text);
            } catch (...) {
                // A progress sink must not abort the file transaction.
            }
        }
    };
    add_log("d3dx_user.ini: " + WideToUtf8(d3dx_user_ini.wstring()));
    add_log("Mods: " + WideToUtf8(mods_directory.wstring()));
    if (!DirectoryExists(mods_directory)) {
        result.fatal_error = "Mods folder does not exist";
        add_log(result.fatal_error);
        return result;
    }
    const auto d3dx_contents = ReadUtf8(d3dx_user_ini);
    if (!d3dx_contents) {
        result.fatal_error = "d3dx_user.ini not found";
        add_log(result.fatal_error);
        return result;
    }
    std::vector<std::string> d3dx_lines;
    std::istringstream d3dx_stream(*d3dx_contents);
    std::string line;
    while (std::getline(d3dx_stream, line)) {
        d3dx_lines.push_back(line);
    }
    std::unordered_map<std::string, std::vector<std::pair<std::string, std::string>>> index;
    for (const auto& source : d3dx_lines) {
        const auto parsed = ParseIniAssignment(source);
        if (!parsed) continue;
        auto path = parsed->first;
        std::replace(path.begin(), path.end(), '/', '\\');
        const auto ini_end = Lower(path).rfind(".ini");
        if (ini_end == std::string::npos) continue;
        const std::string ini_path = path.substr(0, ini_end + 4);
        std::vector<std::string> parts;
        std::istringstream path_stream(ini_path);
        std::string part;
        while (std::getline(path_stream, part, '\\')) {
            if (!part.empty()) parts.push_back(part);
        }
        for (size_t count = 1; count <= parts.size() && count <= 4; ++count) {
            std::string suffix;
            for (size_t i = parts.size() - count; i < parts.size(); ++i) {
                if (!suffix.empty()) suffix += '\\';
                suffix += parts[i];
            }
            index[Lower(suffix)].push_back(*parsed);
        }
    }
    add_log("d3dx parameter keys: " + std::to_string(index.size()));

    std::error_code ec;
    std::filesystem::recursive_directory_iterator iterator(
        mods_directory, std::filesystem::directory_options::skip_permission_denied,
        ec);
    if (ec) {
        result.fatal_error = "Cannot scan Mods folder: " + ec.message();
        add_log(result.fatal_error);
        return result;
    }
    while (iterator != std::filesystem::recursive_directory_iterator()) {
        if (ec) {
            add_log("Directory scan warning: " + ec.message());
            ++result.failed_files;
            ec.clear();
        }
        const auto entry = *iterator;
        const auto next = [&] {
            iterator.increment(ec);
        };
        if (!entry.is_regular_file(ec) ||
            ToLower(entry.path().extension().string()) != ".ini") {
            if (ec) {
                add_log(
                    "Cannot inspect " +
                    WideToUtf8(entry.path().filename().wstring()) + ": " +
                    ec.message());
                ++result.failed_files;
                ec.clear();
            }
            next();
            continue;
        }
        ++result.scanned_files;
        auto contents = ReadUtf8(entry.path());
        if (!contents) {
            ++result.failed_files;
            add_log("Cannot read " +
                    WideToUtf8(entry.path().filename().wstring()));
            next();
            continue;
        }
        std::string namespace_value;
        {
            std::istringstream stream(*contents);
            while (std::getline(stream, line)) {
                const auto parsed = ParseIniAssignment(line);
                if (parsed && Lower(parsed->first) == "namespace") {
                    namespace_value = parsed->second;
                    break;
                }
            }
        }
        std::string keyword = namespace_value;
        if (keyword.empty()) {
            std::error_code relative_error;
            const auto relative =
                std::filesystem::relative(entry.path(), mods_directory, relative_error);
            keyword = relative_error ? entry.path().filename().string()
                                     : relative.generic_string();
        }
        std::replace(keyword.begin(), keyword.end(), '/', '\\');
        const std::string normalized_keyword = Lower(keyword);
        std::unordered_map<std::string, std::pair<std::string, std::string>> params;
        auto index_it = index.end();
        std::vector<std::string> keyword_parts;
        {
            std::istringstream keyword_stream(keyword);
            std::string part;
            while (std::getline(keyword_stream, part, '\\')) {
                if (!part.empty()) keyword_parts.push_back(part);
            }
        }
        for (size_t count = keyword_parts.size(); count > 0; --count) {
            std::string suffix;
            for (size_t i = keyword_parts.size() - count; i < keyword_parts.size(); ++i) {
                if (!suffix.empty()) suffix += '\\';
                suffix += keyword_parts[i];
            }
            index_it = index.find(Lower(suffix));
            if (index_it != index.end()) break;
        }
        if (index_it != index.end()) {
            for (const auto& [path, value] : index_it->second) {
                params[Lower(LastPathComponent(path))] =
                    {LastPathComponent(path), value};
            }
        } else {
            for (const auto& source : d3dx_lines) {
                if (Lower(source).find(normalized_keyword) != std::string::npos) {
                    if (const auto parsed = ParseIniAssignment(source)) {
                        params[Lower(LastPathComponent(parsed->first))] =
                            {LastPathComponent(parsed->first), parsed->second};
                    }
                }
            }
        }
        if (params.empty()) {
            ++result.failed_files;
            add_log(
                "No matching d3dx parameters: " +
                WideToUtf8(entry.path().filename().wstring()));
            next();
            continue;
        }

        std::istringstream input(*contents);
        std::ostringstream output;
        bool in_constants = false;
        size_t changed = 0;
        while (std::getline(input, line)) {
            std::string stripped = line;
            const auto first = stripped.find_first_not_of(" \t");
            const auto last = stripped.find_last_not_of(" \t\r");
            stripped = first == std::string::npos ? "" : stripped.substr(first, last - first + 1);
            if (!stripped.empty() && stripped.front() == '[' && stripped.back() == ']') {
                in_constants = Lower(stripped.substr(1, stripped.size() - 2)) == "constants";
            }
            std::regex variable(R"(\$(\w+))");
            std::smatch match;
            if (in_constants && std::regex_search(line, match, variable)) {
                const std::string name = Lower(match[1].str());
                auto param_it = params.find(name);
                if (param_it == params.end()) {
                    for (const auto& [key, value] : params) {
                        if (key.find(name) != std::string::npos ||
                            name.find(key) != std::string::npos) {
                            param_it = params.find(key);
                            break;
                        }
                    }
                }
                if (param_it != params.end()) {
                    const auto parameter_equals =
                        line.find('=', match.position() + match.length());
                    std::string old_value;
                    if (parameter_equals != std::string::npos) {
                        const auto value_begin =
                            line.find_first_not_of(" \t", parameter_equals + 1);
                        const auto comment_begin =
                            line.find(';', parameter_equals + 1);
                        if (value_begin != std::string::npos &&
                            (comment_begin == std::string::npos ||
                             value_begin < comment_begin)) {
                            const auto value_end =
                                comment_begin == std::string::npos
                                    ? line.find_last_not_of(" \t\r")
                                    : line.find_last_not_of(
                                          " \t\r", comment_begin - 1);
                            if (value_end != std::string::npos &&
                                value_begin <= value_end) {
                                old_value = line.substr(
                                    value_begin, value_end - value_begin + 1);
                            }
                        }
                    }
                    const auto equals = line.find('=', match.position() + match.length());
                    const auto comment = equals == std::string::npos
                                             ? std::string{}
                                             : [&] {
                                                   const auto semi = line.find(';', equals + 1);
                                                   return semi == std::string::npos
                                                              ? std::string{}
                                                              : line.substr(semi);
                                               }();
                    line = line.substr(0, match.position() + match.length()) + " = " +
                           param_it->second.second + comment;
                    add_log(
                        WideToUtf8(entry.path().filename().wstring()) + ": $" +
                        match[1].str() + " \"" + old_value + "\" -> \"" +
                        param_it->second.second + "\"");
                    ++changed;
                }
            }
            output << line << '\n';
        }
        if (changed == 0) {
                    add_log(
                WideToUtf8(entry.path().filename().wstring()) +
                ": no changes");
        } else if (WriteUtf8Atomic(entry.path(), output.str())) {
            ++result.updated_files;
            add_log(
                WideToUtf8(entry.path().filename().wstring()) + ": " +
                std::to_string(changed) + " values");
        } else {
            ++result.failed_files;
            add_log(
                "Cannot write " +
                WideToUtf8(entry.path().filename().wstring()));
        }
        next();
    }
    add_log(
        "Completed: updated=" + std::to_string(result.updated_files) +
        ", scanned=" + std::to_string(result.scanned_files) +
        ", failed=" + std::to_string(result.failed_files));
    return result;
}

namespace {

constexpr auto kQuickScanBudget = std::chrono::milliseconds(300);
constexpr size_t kQuickScanMaxEntries = 4096;
constexpr int kQuickGamesMaxDepth = 2;

struct QuickScanContext {
    explicit QuickScanContext(std::atomic_bool* stop)
        : deadline(std::chrono::steady_clock::now() + kQuickScanBudget), cancel(stop) {}

    bool Continue() {
        if (cancel && cancel->load()) return false;
        if (visited >= kQuickScanMaxEntries) return false;
        return std::chrono::steady_clock::now() < deadline;
    }

    std::chrono::steady_clock::time_point deadline;
    std::atomic_bool* cancel = nullptr;
    size_t visited = 0;
};

bool IsSkippedDirectory(const std::filesystem::path& path) {
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
        return true;
    }

    const std::wstring name = ToLower(path.filename().wstring());
    static constexpr std::wstring_view kSkippedNames[] = {
        L"$recycle.bin",       L"system volume information", L"windows",
        L"programdata",        L"recovery",                 L"boot",
        L"system32",           L"syswow64",                 L"winsxs",
        L"appdata",            L"application data",          L"local settings",
        L"temp",               L"tmp",                       L"node_modules",
        L".git",               L".svn",                      L"cache",
        L"logs",               L"backups",                   L"shadercache",
        L"mods",
    };
    for (const auto skipped : kSkippedNames) {
        if (name == skipped) return true;
    }
    return name.starts_with(L"frameanalysis-");
}

std::optional<std::filesystem::path> CheckTargetFile(
    const std::filesystem::path& candidate, const std::wstring& target_exe) {
    if (!FileExists(candidate) ||
        _wcsicmp(candidate.filename().c_str(), target_exe.c_str()) != 0) {
        return std::nullopt;
    }
    return candidate;
}

std::optional<std::filesystem::path> CheckTargetFolder(
    const std::filesystem::path& folder, const std::wstring& target_exe) {
    if (folder.empty()) return std::nullopt;
    if (_wcsicmp(folder.filename().c_str(), target_exe.c_str()) == 0) {
        return CheckTargetFile(folder, target_exe);
    }
    return CheckTargetFile(folder / target_exe, target_exe);
}

std::filesystem::path XxmiRootFromExe(const std::filesystem::path& xxmi_exe) {
    if (xxmi_exe.empty()) return {};
    auto current = xxmi_exe.parent_path();
    for (int depth = 0; depth < 5 && !current.empty(); ++depth) {
        if (FileExists(current / L"XXMI Launcher Config.json") ||
            DirectoryExists(current / L"Resources")) {
            return current;
        }
        const auto parent = current.parent_path();
        if (parent == current) break;
        current = parent;
    }
    return xxmi_exe.parent_path().parent_path().parent_path();
}

std::optional<std::filesystem::path> FindD3dxLaunch(
    const std::filesystem::path& ini_path, const std::wstring& target_exe) {
    const auto contents = ReadUtf8(ini_path);
    if (!contents) return std::nullopt;

    std::istringstream stream(*contents);
    std::string line;
    while (std::getline(stream, line)) {
        const auto parsed = ParseIniAssignment(line);
        if (!parsed || Lower(parsed->first) != "launch") continue;

        std::string value = parsed->second;
        if (value.size() >= 2 &&
            ((value.front() == '"' && value.back() == '"') ||
             (value.front() == '\'' && value.back() == '\''))) {
            value = value.substr(1, value.size() - 2);
        }
        if (value.empty() || value.find('%') != std::string::npos ||
            value.find('$') != std::string::npos) {
            continue;
        }

        std::filesystem::path launch = Utf8ToWide(value);
        if (launch.is_relative()) launch = ini_path.parent_path() / launch;
        if (auto found = CheckTargetFile(launch.lexically_normal(), target_exe)) {
            return found;
        }
    }
    return std::nullopt;
}

std::optional<std::filesystem::path> FindInBoundedDirectory(
    const std::filesystem::path& directory, const std::wstring& target_exe, int depth,
    QuickScanContext* scan) {
    if (!scan->Continue() || depth > kQuickGamesMaxDepth ||
        IsSkippedDirectory(directory)) {
        return std::nullopt;
    }
    if (auto found = CheckTargetFolder(directory, target_exe)) return found;

    std::error_code ec;
    for (std::filesystem::directory_iterator it(
             directory, std::filesystem::directory_options::skip_permission_denied, ec);
         !ec && it != std::filesystem::directory_iterator(); it.increment(ec)) {
        if (!scan->Continue()) return std::nullopt;
        ++scan->visited;

        if (it->is_regular_file(ec)) {
            if (_wcsicmp(it->path().filename().c_str(), target_exe.c_str()) == 0) {
                return it->path();
            }
        } else if (it->is_directory(ec)) {
            if (depth < kQuickGamesMaxDepth) {
                if (auto found =
                        FindInBoundedDirectory(it->path(), target_exe, depth + 1, scan)) {
                    return found;
                }
            }
        }
        if (ec) ec.clear();
    }
    return std::nullopt;
}

void AppendKnownRelativeDirectories(const std::wstring& target_exe,
                                    std::vector<std::wstring>* directories) {
    const std::wstring stem = std::filesystem::path(target_exe).stem().wstring();
    if (_wcsicmp(target_exe.c_str(), L"ZenlessZoneZero.exe") == 0) {
        directories->insert(directories->end(), {
            L"Program Files\\HoYoPlay\\games\\ZenlessZoneZero\\Game",
            L"Program Files (x86)\\HoYoPlay\\games\\ZenlessZoneZero\\Game",
            L"Program Files\\miHoYo Launcher\\games\\ZenlessZoneZero Game",
            L"game\\ZenlessZoneZero Game",
            L"Games\\ZenlessZoneZero Game",
            L"Games\\ZenlessZoneZero\\Game",
            L"ZenlessZoneZero Game",
            L"ZenlessZoneZero\\Game",
        });
    } else if (_wcsicmp(target_exe.c_str(), L"GenshinImpact.exe") == 0 ||
               _wcsicmp(target_exe.c_str(), L"YuanShen.exe") == 0) {
        directories->insert(directories->end(), {
            L"Program Files\\Genshin Impact\\Genshin Impact Game",
            L"Program Files (x86)\\Genshin Impact\\Genshin Impact Game",
            L"Program Files\\HoYoverse\\Genshin Impact\\Genshin Impact Game",
            L"Program Files\\miHoYo Launcher\\games\\Genshin Impact Game",
            L"game\\Genshin Impact Game",
            L"Games\\Genshin Impact\\Genshin Impact Game",
            L"Genshin Impact\\Genshin Impact Game",
        });
    } else if (_wcsicmp(target_exe.c_str(), L"StarRail.exe") == 0) {
        directories->insert(directories->end(), {
            L"Program Files\\Star Rail\\Game",
            L"Program Files (x86)\\Star Rail\\Game",
            L"Program Files\\HoYoverse\\Star Rail\\Game",
            L"Program Files\\miHoYo Launcher\\games\\Star Rail Game",
            L"game\\Star Rail Game",
            L"Games\\Star Rail\\Game",
            L"Star Rail Game",
        });
    } else if (_wcsicmp(target_exe.c_str(), L"BH3.exe") == 0) {
        directories->insert(directories->end(), {
            L"Program Files\\崩坏3\\Games",
            L"Program Files\\Honkai Impact 3\\Games",
            L"Program Files\\miHoYo Launcher\\games\\Honkai Impact 3rd Game",
            L"game\\Honkai Impact 3rd Game",
            L"Games\\崩坏3\\Games",
        });
    } else if (_wcsicmp(target_exe.c_str(), L"Client-Win64-Shipping.exe") == 0) {
        directories->insert(directories->end(), {
            L"Program Files\\Wuthering Waves\\Wuthering Waves Game\\Client\\Binaries\\Win64",
            L"Program Files (x86)\\Wuthering Waves\\Wuthering Waves Game\\Client\\Binaries\\Win64",
            L"game\\Wuthering Waves\\Wuthering Waves Game\\Client\\Binaries\\Win64",
            L"Games\\Wuthering Waves\\Wuthering Waves Game\\Client\\Binaries\\Win64",
        });
    } else if (_wcsicmp(target_exe.c_str(), L"Endfield.exe") == 0) {
        directories->insert(directories->end(), {
            L"Program Files\\ArknightsEndfield",
            L"Program Files\\Hypergryph Launcher\\games\\Endfield Game",
            L"game\\Endfield Game",
            L"Games\\ArknightsEndfield",
            L"明日方舟终末地",
        });
    }

    if (!stem.empty()) {
        directories->push_back(L"game\\" + stem);
        directories->push_back(L"Games\\" + stem);
        directories->push_back(stem);
    }
}

std::optional<std::filesystem::path> FindQuickCandidates(
    std::wstring_view exe_name, std::wstring_view xxmi_exe, std::atomic_bool* cancel) {
    if (exe_name.empty() || exe_name.find_first_of(L"\\/") != std::wstring_view::npos) {
        return std::nullopt;
    }

    const std::wstring target_exe(exe_name);
    QuickScanContext scan(cancel);
    const std::filesystem::path xxmi_root =
        xxmi_exe.empty() ? std::filesystem::path{} : XxmiRootFromExe(std::filesystem::path(xxmi_exe));

    if (!xxmi_root.empty() && scan.Continue()) {
        if (const auto config = ReadJson(xxmi_root / L"XXMI Launcher Config.json");
            config && config->contains("Importers") && (*config)["Importers"].is_object()) {
            for (const auto& [name, importer_entry] : (*config)["Importers"].items()) {
                (void)name;
                if (!scan.Continue() || !importer_entry.is_object() ||
                    !importer_entry.contains("Importer") ||
                    !importer_entry["Importer"].is_object()) {
                    continue;
                }
                const auto& importer = importer_entry["Importer"];
                for (const char* key : {"game_folder", "launcher_folder"}) {
                    if (!importer.contains(key) || !importer[key].is_string()) continue;
                    const std::string value = importer[key].get<std::string>();
                    if (value.empty()) continue;
                    if (auto found =
                            CheckTargetFolder(Utf8ToWide(value), target_exe)) {
                        return found;
                    }
                }
            }
        }

        static constexpr std::wstring_view kKnownModules[] = {
            L"ZZMI", L"GIMI", L"SRMI", L"WWMI", L"EFMI", L"HIMI", L"APMI", L"JASM",
        };
        for (const auto module : kKnownModules) {
            if (!scan.Continue()) return std::nullopt;
            if (auto found = FindD3dxLaunch(
                    xxmi_root / module / L"d3dx.ini", target_exe)) {
                return found;
            }
        }
    }

    std::vector<std::filesystem::path> drive_roots;
    const DWORD drives = GetLogicalDrives();
    for (wchar_t letter = L'A'; letter <= L'Z'; ++letter) {
        if ((drives & (1u << (letter - L'A'))) == 0 || !scan.Continue()) continue;
        std::wstring root_text = {letter, L':', L'\\'};
        const UINT type = GetDriveTypeW(root_text.c_str());
        if (type != DRIVE_FIXED && type != DRIVE_REMOVABLE) continue;
        drive_roots.emplace_back(root_text);
    }

    std::vector<std::wstring> relative_directories;
    AppendKnownRelativeDirectories(target_exe, &relative_directories);
    for (const auto& drive : drive_roots) {
        for (const auto& relative : relative_directories) {
            if (!scan.Continue()) return std::nullopt;
            if (auto found = CheckTargetFolder(drive / relative, target_exe)) {
                return found;
            }
        }
    }

    std::vector<std::filesystem::path> data_roots = {
        KnownFolder(FOLDERID_Profile),
        KnownFolder(FOLDERID_Public),
        KnownFolder(FOLDERID_LocalAppData),
    };
    for (const auto& root : data_roots) {
        if (root.empty() || !scan.Continue()) continue;
        for (const auto& relative : relative_directories) {
            if (!scan.Continue()) return std::nullopt;
            if (auto found = CheckTargetFolder(root / relative, target_exe)) {
                return found;
            }
        }
    }

    std::vector<std::filesystem::path> games_roots;
    for (const auto& drive : drive_roots) {
        games_roots.push_back(drive / L"Games");
        games_roots.push_back(drive / L"Game");
        games_roots.push_back(drive / L"game");
        games_roots.push_back(drive / L"游戏");
    }
    const auto profile = KnownFolder(FOLDERID_Profile);
    const auto public_documents = KnownFolder(FOLDERID_Public);
    if (!profile.empty()) games_roots.push_back(profile / L"Games");
    if (!public_documents.empty()) games_roots.push_back(public_documents / L"Games");

    if (!xxmi_root.empty()) {
        const auto sibling_root = xxmi_root.parent_path();
        const std::wstring sibling_name = ToLower(sibling_root.filename().wstring());
        if (sibling_name == L"game" || sibling_name == L"games" ||
            sibling_name == L"游戏") {
            games_roots.push_back(sibling_root);
        }
    }

    std::set<std::wstring> scanned_roots;
    for (const auto& root : games_roots) {
        if (!scan.Continue()) return std::nullopt;
        const std::wstring key = ToLower(root.lexically_normal().wstring());
        if (key.empty() || !scanned_roots.insert(key).second) continue;
        if (auto found =
                FindInBoundedDirectory(root, target_exe, 0, &scan)) {
            return found;
        }
    }
    return std::nullopt;
}

}  // namespace

std::optional<std::filesystem::path> XXMIScanner::FindGame(
    std::wstring_view exe_name, std::wstring_view xxmi_exe, std::atomic_bool* cancel) {
    return FindQuickCandidates(exe_name, xxmi_exe, cancel);
}

std::optional<std::filesystem::path> XXMIScanner::FindGameDeep(
    std::wstring_view exe_name, std::wstring_view xxmi_exe, std::atomic_bool* cancel) {
    if (auto found = FindGame(exe_name, xxmi_exe, cancel)) return found;

    const std::wstring target_exe(exe_name);
    std::vector<std::filesystem::path> roots = {
        KnownFolder(FOLDERID_ProgramFiles),
        KnownFolder(FOLDERID_ProgramFilesX86),
        KnownFolder(FOLDERID_LocalAppData),
        KnownFolder(FOLDERID_RoamingAppData),
    };
    if (!xxmi_exe.empty()) {
        roots.push_back(XxmiRootFromExe(std::filesystem::path(xxmi_exe)));
    }
    const DWORD drives = GetLogicalDrives();
    for (wchar_t letter = L'A'; letter <= L'Z'; ++letter) {
        if ((drives & (1u << (letter - L'A'))) == 0) continue;
        std::wstring drive_text = {letter, L':', L'\\'};
        const UINT type = GetDriveTypeW(drive_text.c_str());
        if (type == DRIVE_FIXED || type == DRIVE_REMOVABLE) {
            roots.emplace_back(drive_text);
        }
    }

    std::set<std::wstring> scanned_roots;
    for (const auto& root : roots) {
        if (root.empty() || (cancel && cancel->load())) continue;
        const std::wstring key = ToLower(root.lexically_normal().wstring());
        if (!scanned_roots.insert(key).second) continue;

        std::error_code ec;
        for (auto it = std::filesystem::recursive_directory_iterator(
                 root, std::filesystem::directory_options::skip_permission_denied, ec);
             it != std::filesystem::recursive_directory_iterator(); it.increment(ec)) {
            if (ec) {
                ec.clear();
                continue;
            }
            if (cancel && cancel->load()) return std::nullopt;
            if (it.depth() > 6) {
                it.disable_recursion_pending();
                continue;
            }
            if (it->is_directory(ec) && IsSkippedDirectory(it->path())) {
                it.disable_recursion_pending();
                if (ec) ec.clear();
                continue;
            }
            if (it->is_regular_file(ec) &&
                _wcsicmp(it->path().filename().c_str(), target_exe.c_str()) == 0) {
                return it->path();
            }
            if (ec) ec.clear();
        }
    }
    return std::nullopt;
}

namespace {

std::filesystem::path FullShaderPackPath() {
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &raw))) {
        return {};
    }
    std::filesystem::path result =
        std::filesystem::path(raw) / L"ReShade-Launcher" / L"shader-packs" /
        L"full.zip";
    CoTaskMemFree(raw);
    return result;
}

Json ReadPackManifest(const std::filesystem::path& pack_path) {
    if (!FileExists(pack_path)) return {};
    mz_zip_archive archive{};
    if (!mz_zip_reader_init_file(
            &archive, WideToUtf8(pack_path.wstring()).c_str(), 0)) {
        return {};
    }
    Json manifest;
    const int index =
        mz_zip_reader_locate_file(&archive, "pack.json", nullptr, 0);
    if (index >= 0) {
        size_t size = 0;
        void* data = mz_zip_reader_extract_to_heap(
            &archive, static_cast<mz_uint>(index), &size, 0);
        if (data) {
            try {
                manifest = Json::parse(std::string_view(
                    static_cast<const char*>(data), size));
            } catch (...) {
                manifest = {};
            }
            mz_free(data);
        }
    }
    mz_zip_reader_end(&archive);
    return manifest;
}

void AddManifestHashes(
    const Json& manifest,
    std::unordered_map<std::string, std::string>* hashes) {
    if (!hashes || !manifest.is_object() || !manifest.contains("files") ||
        !manifest["files"].is_array()) {
        return;
    }
    for (const auto& item : manifest["files"]) {
        if (!item.is_object() || !item.contains("path") ||
            !item.contains("sha256") || !item["path"].is_string() ||
            !item["sha256"].is_string()) {
            continue;
        }
        (*hashes)[ToLower(item["path"].get<std::string>())] =
            ToLower(item["sha256"].get<std::string>());
    }
}

void RestoreOptionalText(const std::filesystem::path& path,
                         const std::optional<std::string>& contents) {
    if (contents) {
        WriteUtf8Atomic(path, *contents);
    } else {
        DeleteFileW(path.c_str());
    }
}

}  // namespace

ShaderPackManager::ShaderPackManager(const AppData& app) : app_(app) {}

ShaderPackManager::Mode ShaderPackManager::CurrentMode() const {
    const auto state = ReadJson(app_.custom_data_dir() / L"shader_pack_state.json");
    if (!state) return Mode::Unknown;
    const auto mode = ToLower(state->value("mode", ""));
    if (mode == "lite") return Mode::Lite;
    if (mode == "full") return Mode::Full;
    return Mode::Unknown;
}

bool ShaderPackManager::Recover() {
    const auto state_path = app_.custom_data_dir() / L"shader_pack_state.json";
    const auto state = ReadJson(state_path);
    if (!state) {
        const auto active = app_.reshade_dir() / L"reshade_shaders";
        size_t file_count = 0;
        std::error_code count_ec;
        if (DirectoryExists(active)) {
            for (auto it = std::filesystem::recursive_directory_iterator(
                     active, std::filesystem::directory_options::skip_permission_denied,
                     count_ec);
                 !count_ec && it != std::filesystem::recursive_directory_iterator();
                 it.increment(count_ec)) {
                if (it->is_regular_file(count_ec)) ++file_count;
            }
        }
        const char* mode = file_count > 200 ? "full" : "lite";
        Json initial = {
            {"mode", mode},
            {"pack_id", file_count > 200 ? "legacy-full" : "lite"},
            {"transaction", false},
            {"legacy_migration", file_count > 0},
        };
        if (file_count == 0) {
            std::string error;
            return SetMode(Mode::Lite, true, &error);
        }
        return WriteJsonAtomic(state_path, initial);
    }
    if (!state->value("transaction", false)) return true;
    const auto active = app_.reshade_dir() / L"reshade_shaders";
    const auto backup = app_.reshade_dir() / L"reshade_shaders.rollback";
    const auto staging = app_.reshade_dir() / L"reshade_shaders.stage";
    std::error_code ec;
    if (DirectoryExists(backup)) {
        std::filesystem::remove_all(active, ec);
        ec.clear();
        std::filesystem::rename(backup, active, ec);
    } else if (!DirectoryExists(active) && DirectoryExists(staging)) {
        std::filesystem::rename(staging, active, ec);
    }
    Json recovered = *state;
    recovered["transaction"] = false;
    recovered["backup_active"] = false;
    WriteJsonAtomic(state_path, recovered);
    std::filesystem::remove_all(staging, ec);
    return DirectoryExists(active);
}

bool ShaderPackManager::SetMode(Mode mode, bool replace_custom, std::string* error,
                                std::function<void(int)> progress) {
    if (mode == Mode::Unknown) {
        if (error) *error = "Unknown shader mode";
        return false;
    }
    const auto pack_path =
        mode == Mode::Lite
            ? app_.resource_path(L"shader-packs/lite.zip")
            : FullShaderPackPath();
    if (!FileExists(pack_path)) {
        if (error) *error = mode == Mode::Full ? "Full shader pack is not downloaded"
                                               : "Bundled lite shader pack is missing";
        return false;
    }
    const auto reshade = app_.reshade_dir();
    const auto active = reshade / L"reshade_shaders";
    const auto staging = reshade / L"reshade_shaders.stage";
    const auto rollback = reshade / L"reshade_shaders.rollback";
    std::error_code ec;
    std::filesystem::remove_all(staging, ec);
    std::filesystem::create_directories(staging, ec);

    mz_zip_archive archive{};
    if (!mz_zip_reader_init_file(&archive, WideToUtf8(pack_path.wstring()).c_str(), 0)) {
        if (error) *error = "Cannot open shader pack";
        return false;
    }
    Json pack_manifest;
    const int manifest_index = mz_zip_reader_locate_file(&archive, "pack.json", nullptr, 0);
    if (manifest_index >= 0) {
        size_t manifest_size = 0;
        void* manifest_data =
            mz_zip_reader_extract_to_heap(&archive, static_cast<mz_uint>(manifest_index),
                                          &manifest_size, 0);
        if (manifest_data) {
            try {
                pack_manifest = Json::parse(std::string_view(
                    static_cast<const char*>(manifest_data), manifest_size));
            } catch (...) {
                pack_manifest = Json::object();
            }
            mz_free(manifest_data);
        }
    }
    if (!pack_manifest.is_object() || !pack_manifest.contains("files")) {
        mz_zip_reader_end(&archive);
        if (error) *error = "Shader pack manifest is missing";
        return false;
    }
    const mz_uint count = mz_zip_reader_get_num_files(&archive);
    bool ok = true;
    for (mz_uint index = 0; index < count; ++index) {
        mz_zip_archive_file_stat stat{};
        if (!mz_zip_reader_file_stat(&archive, index, &stat) || stat.m_is_directory) continue;
        const std::string name = stat.m_filename;
        if (name == "pack.json") continue;
        if (name.empty() || name[0] == '/' || name.find('\\') != std::string::npos ||
            name.find("..") != std::string::npos) {
            ok = false;
            break;
        }
        const auto target = staging / Utf8ToWide(name);
        std::filesystem::create_directories(target.parent_path(), ec);
        size_t size = 0;
        void* data = mz_zip_reader_extract_to_heap(&archive, index, &size, 0);
        if (!data) {
            ok = false;
            break;
        }
        std::ofstream output(target, std::ios::binary | std::ios::trunc);
        output.write(static_cast<const char*>(data), static_cast<std::streamsize>(size));
        mz_free(data);
        if (!output) {
            ok = false;
            break;
        }
        if (progress && count) {
            progress(static_cast<int>((index + 1) * 80 / count));
        }
    }
    mz_zip_reader_end(&archive);
    if (!ok) {
        std::filesystem::remove_all(staging, ec);
        if (error) *error = "Shader pack extraction failed";
        return false;
    }

    if (!replace_custom && DirectoryExists(active)) {
        std::unordered_map<std::string, std::string> current_hashes;
        if (const auto current =
                ReadJson(app_.custom_data_dir() / L"shader_pack_manifest.json")) {
            AddManifestHashes(*current, &current_hashes);
        }
        if (mode == Mode::Lite) {
            AddManifestHashes(ReadPackManifest(FullShaderPackPath()),
                              &current_hashes);
        }
        for (auto it = std::filesystem::recursive_directory_iterator(
                 active, std::filesystem::directory_options::skip_permission_denied, ec);
             !ec && it != std::filesystem::recursive_directory_iterator(); it.increment(ec)) {
            if (!it->is_regular_file(ec)) continue;
            const auto relative =
                std::filesystem::relative(it->path(), active, ec).generic_string();
            if (ec || relative.empty() || FileExists(staging / Utf8ToWide(relative))) continue;
            bool preserve = true;
            const auto hash_it = current_hashes.find(ToLower(relative));
            if (hash_it != current_hashes.end()) {
                preserve = ToLower(Sha256File(it->path())) != hash_it->second;
            }
            if (!preserve) continue;
            const auto destination = staging / Utf8ToWide(relative);
            std::filesystem::create_directories(destination.parent_path(), ec);
            std::filesystem::copy_file(it->path(), destination,
                                       std::filesystem::copy_options::overwrite_existing,
                                       ec);
        }
    }
    const auto state_path = app_.custom_data_dir() / L"shader_pack_state.json";
    const auto manifest_path =
        app_.custom_data_dir() / L"shader_pack_manifest.json";
    const auto previous_state = ReadUtf8(state_path);
    const auto previous_manifest = ReadUtf8(manifest_path);
    Json transaction_state = ReadJson(state_path).value_or(Json::object());
    transaction_state["transaction"] = true;
    transaction_state["backup_active"] = DirectoryExists(active);
    if (!WriteJsonAtomic(state_path, transaction_state)) {
        std::filesystem::remove_all(staging, ec);
        if (error) *error = "Cannot write shader transaction state";
        return false;
    }

    std::filesystem::remove_all(rollback, ec);
    if (DirectoryExists(active)) {
        std::filesystem::rename(active, rollback, ec);
        if (ec) {
            std::filesystem::remove_all(staging, ec);
            RestoreOptionalText(state_path, previous_state);
            if (error) *error = "Cannot move current shader directory";
            return false;
        }
    }
    std::filesystem::rename(staging, active, ec);
    if (ec) {
        std::error_code rollback_error;
        std::filesystem::remove_all(active, rollback_error);
        if (DirectoryExists(rollback)) {
            std::filesystem::rename(rollback, active, rollback_error);
        }
        RestoreOptionalText(state_path, previous_state);
        if (error) {
            *error = rollback_error ? "Cannot activate or restore shader pack"
                                    : "Cannot activate shader pack";
        }
        return false;
    }

    Json state = {
        {"mode", mode == Mode::Lite ? "lite" : "full"},
        {"pack_id", pack_manifest.value("pack_id", mode == Mode::Lite ? "lite" : "full")},
        {"installed_at", WideToUtf8([] {
             SYSTEMTIME time{};
             GetSystemTime(&time);
             wchar_t buffer[64]{};
             swprintf_s(buffer, L"%04u-%02u-%02uT%02u:%02u:%02uZ", time.wYear,
                        time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond);
             return std::wstring(buffer);
         }())},
        {"transaction", false},
    };
    auto rollback_activation = [&]() {
        std::error_code rollback_error;
        std::filesystem::remove_all(active, rollback_error);
        rollback_error.clear();
        if (DirectoryExists(rollback)) {
            std::filesystem::rename(rollback, active, rollback_error);
        }
        RestoreOptionalText(manifest_path, previous_manifest);
        RestoreOptionalText(state_path, previous_state);
        return !rollback_error;
    };
    if (!WriteJsonAtomic(manifest_path, pack_manifest)) {
        if (!rollback_activation()) {
            if (error) *error = "Cannot write shader manifest or roll back";
        } else if (error) {
            *error = "Cannot write shader manifest";
        }
        return false;
    }
    if (!WriteJsonAtomic(state_path, state)) {
        if (!rollback_activation()) {
            if (error) *error = "Cannot write shader state or roll back";
        } else if (error) {
            *error = "Cannot write shader state";
        }
        return false;
    }
    std::filesystem::remove_all(rollback, ec);
    if (progress) progress(100);
    return true;
}

bool OpenInExplorer(const std::filesystem::path& path) {
    if (!DirectoryExists(path)) {
        std::error_code ec;
        std::filesystem::create_directories(path, ec);
    }
    return reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", path.c_str(),
                                                  nullptr, nullptr, SW_SHOWNORMAL)) > 32;
}

}  // namespace rs
