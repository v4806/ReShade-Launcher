#pragma once

#include <windows.h>

#include <atomic>
#include <chrono>
#include <filesystem>
#include <functional>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "core/common.h"

namespace rs {

struct InjectionPlan {
    std::wstring method = L"direct";
    std::filesystem::path hook_dll;
    std::vector<std::filesystem::path> direct_dlls;
};

struct LaunchSession {
    HANDLE process = nullptr;
    DWORD root_pid = 0;
    DWORD target_pid = 0;
    std::vector<DWORD> extra_pids;

    LaunchSession() = default;
    LaunchSession(HANDLE process_handle, DWORD root, DWORD target,
                  std::vector<DWORD> extra = {})
        : process(process_handle), root_pid(root), target_pid(target),
          extra_pids(std::move(extra)) {}
    LaunchSession(const LaunchSession&) = delete;
    LaunchSession& operator=(const LaunchSession&) = delete;
    LaunchSession(LaunchSession&& other) noexcept;
    LaunchSession& operator=(LaunchSession&& other) noexcept;
    ~LaunchSession();

    bool Valid() const { return process != nullptr && root_pid != 0; }
    void Close();
};

struct LaunchResult {
    LaunchSession session;
    std::string error;
    bool ok() const { return session.Valid() && error.empty(); }
};

class Injector {
public:
    explicit Injector(const std::filesystem::path& dll);
    ~Injector();
    Injector(const Injector&) = delete;
    Injector& operator=(const Injector&) = delete;

    bool valid() const { return module_ != nullptr; }
    bool Inject(DWORD pid, const std::filesystem::path& dll, int timeout_seconds = 15,
                std::string* error = nullptr);
    bool Hook(DWORD pid, const std::filesystem::path& dll, std::string* error = nullptr);
    void Unhook();

private:
    using InjectFn = int (*)(DWORD, LPCWSTR, int);
    using HookFn = int (*)(LPCWSTR, DWORD, HHOOK*, HANDLE*);
    using UnhookFn = int (*)(HHOOK*, HANDLE*);

    HMODULE module_ = nullptr;
    InjectFn inject_ = nullptr;
    HookFn hook_ = nullptr;
    UnhookFn unhook_ = nullptr;
    HHOOK hook_handle_ = nullptr;
    HANDLE mutex_ = nullptr;
};

class ProcessManager {
public:
    using LogCallback = std::function<void(const std::string&)>;

    explicit ProcessManager(const AppData& app);

    InjectionPlan BuildInjectionPlan(const Json& config, std::string* error) const;
    LaunchResult Launch(const Json& config, LogCallback log = {});
    bool Terminate(DWORD pid);
    bool IsRunning(DWORD pid) const;
    static bool IsExecutableRunning(std::wstring_view exe_name);
    static bool IsProcessIdPresent(DWORD pid);
    static std::vector<DWORD> FindProcessIdsByName(std::wstring_view exe_name);
    static DWORD FindProcessIdByName(std::wstring_view exe_name);
    static DWORD FindProcessIdByPath(const std::filesystem::path& executable);
    static DWORD FindMainWindowPid(DWORD pid);
    static void CenterWindowsForPid(DWORD pid, int duration_seconds,
                                   std::atomic_bool* stop);

private:
    enum class ModuleState {
        NotLoaded,
        Loaded,
        Unknown,
    };

    std::filesystem::path ResolveRuntimeFile(std::wstring_view relative) const;
    std::optional<DWORD> WaitForTargetPid(
        DWORD root_pid, const std::filesystem::path& target_program,
        const std::string& game_exe_name, int timeout_seconds,
        const std::set<DWORD>& baseline, LogCallback log,
        std::string* error) const;
    bool InjectAndVerify(Injector& injector, DWORD pid,
                         const std::vector<std::filesystem::path>& dlls,
                         std::string* error, LogCallback log);
    ModuleState WaitForModule(DWORD pid, const std::filesystem::path& dll,
                              int timeout_seconds) const;
    bool RunPreLaunch(const Json& config,
                      const std::filesystem::path& launch_program,
                      std::vector<DWORD>* process_tree,
                      LogCallback log) const;

    const AppData& app_;
};

class ModLoaderManager {
public:
    explicit ModLoaderManager(const AppData& app) : app_(app) {}

    bool InstallArchive(const std::filesystem::path& archive,
                        std::string_view folder_name,
                        std::string* error) const;

private:
    const AppData& app_;
};

class ShortcutService {
public:
    static bool Create(std::string_view display_name, std::string_view config_file,
                       const std::filesystem::path& game_exe);
};

struct ModPresetResult {
    size_t updated_files = 0;
    size_t scanned_files = 0;
    size_t failed_files = 0;
    std::string fatal_error;
    std::vector<std::string> log;
};

class ModPresetService {
public:
    static ModPresetResult Apply(const std::filesystem::path& d3dx_user_ini,
                                 const std::filesystem::path& mods_directory,
                                 std::function<void(const std::string&)> progress = {});
};

class XXMIScanner {
public:
    // Fast, bounded candidate scan. Safe to call from the UI thread.
    static std::optional<std::filesystem::path> FindGame(std::wstring_view exe_name,
                                                         std::wstring_view xxmi_exe,
                                                         std::atomic_bool* cancel);
    // Explicit exhaustive scan for worker threads only. Never call from the UI thread.
    static std::optional<std::filesystem::path> FindGameDeep(std::wstring_view exe_name,
                                                             std::wstring_view xxmi_exe,
                                                             std::atomic_bool* cancel);
};

class ShaderPackManager {
public:
    enum class Mode { Lite, Full, Unknown };

    explicit ShaderPackManager(const AppData& app);
    Mode CurrentMode() const;
    bool Recover();
    bool SetMode(Mode mode, bool replace_custom, std::string* error,
                 std::function<void(int)> progress = {});
    std::string StateError() const { return state_error_; }

private:
    const AppData& app_;
    mutable std::string state_error_;
};

bool OpenInExplorer(const std::filesystem::path& path);

}  // namespace rs
