#include "core/common.h"

#include <bcrypt.h>
#include <shlobj.h>
#include <winver.h>

#include <algorithm>
#include <array>
#include <fstream>
#include <sstream>

namespace rs {
namespace {

constexpr const wchar_t kMainExecutableName[] = L"ReShade Launcher Build.exe";

std::string Trim(std::string value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

}  // namespace

std::string WideToUtf8(std::wstring_view value) {
    if (value.empty()) {
        return {};
    }
    const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0,
                                         nullptr, nullptr);
    if (size <= 0) {
        return {};
    }
    std::string result(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        result.data(), size, nullptr, nullptr);
    return result;
}

std::wstring Utf8ToWide(std::string_view value) {
    if (value.empty()) {
        return {};
    }
    const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0);
    if (size <= 0) {
        return {};
    }
    std::wstring result(static_cast<size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), size);
    return result;
}

std::wstring ToLower(std::wstring_view value) {
    std::wstring result(value);
    std::transform(result.begin(), result.end(), result.begin(),
                   [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
    return result;
}

std::string ToLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return static_cast<char>(tolower(c)); });
    return value;
}

bool EndsWithInsensitive(std::wstring_view value, std::wstring_view suffix) {
    if (suffix.size() > value.size()) {
        return false;
    }
    return _wcsnicmp(value.data() + value.size() - suffix.size(), suffix.data(),
                     suffix.size()) == 0;
}

bool FileExists(const std::filesystem::path& path) {
    std::error_code ec;
    return std::filesystem::is_regular_file(path, ec);
}

bool DirectoryExists(const std::filesystem::path& path) {
    std::error_code ec;
    return std::filesystem::is_directory(path, ec);
}

std::optional<std::string> ReadUtf8(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        return std::nullopt;
    }
    std::ostringstream stream;
    stream << input.rdbuf();
    return stream.str();
}

bool WriteUtf8Atomic(const std::filesystem::path& path, std::string_view contents) {
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    if (ec) {
        return false;
    }
    const auto temp = path.wstring() + L".tmp";
    {
        std::ofstream output(temp, std::ios::binary | std::ios::trunc);
        if (!output) {
            return false;
        }
        output.write(contents.data(), static_cast<std::streamsize>(contents.size()));
        output.flush();
        if (!output) {
            return false;
        }
    }
    if (!MoveFileExW(temp.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temp.c_str());
        return false;
    }
    return true;
}

std::optional<Json> ReadJson(const std::filesystem::path& path) {
    const auto contents = ReadUtf8(path);
    if (!contents) {
        return std::nullopt;
    }
    try {
        return Json::parse(*contents);
    } catch (...) {
        return std::nullopt;
    }
}

bool WriteJsonAtomic(const std::filesystem::path& path, const Json& value) {
    return WriteUtf8Atomic(path, value.dump(4));
}

std::string Sha256File(const std::filesystem::path& path) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return {};
    }
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    DWORD hash_size = 0;
    DWORD result_size = 0;
    DWORD object_size = 0;
    std::string digest;
    std::vector<BYTE> hash_object;
    std::vector<BYTE> hash_bytes;

    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0 ||
        BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                          reinterpret_cast<PUCHAR>(&object_size), sizeof(object_size),
                          &result_size, 0) < 0) {
        CloseHandle(file);
        return {};
    }
    hash_object.resize(object_size);
    if (BCryptGetProperty(algorithm, BCRYPT_HASH_LENGTH,
                          reinterpret_cast<PUCHAR>(&hash_size), sizeof(hash_size),
                          &result_size, 0) < 0) {
        BCryptCloseAlgorithmProvider(algorithm, 0);
        CloseHandle(file);
        return {};
    }
    hash_bytes.resize(hash_size);
    if (BCryptCreateHash(algorithm, &hash, hash_object.data(),
                         static_cast<ULONG>(hash_object.size()), nullptr, 0, 0) < 0) {
        BCryptCloseAlgorithmProvider(algorithm, 0);
        CloseHandle(file);
        return {};
    }

    std::array<BYTE, 64 * 1024> buffer{};
    DWORD read = 0;
    bool ok = true;
    while (ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) {
        if (read == 0) {
            break;
        }
        if (BCryptHashData(hash, buffer.data(), read, 0) < 0) {
            ok = false;
            break;
        }
    }
    if (ok) {
        ok = BCryptFinishHash(hash, hash_bytes.data(), hash_size, 0) >= 0;
    }

    if (ok) {
        static constexpr char hex[] = "0123456789abcdef";
        digest.reserve(hash_bytes.size() * 2);
        for (BYTE byte : hash_bytes) {
            digest.push_back(hex[byte >> 4]);
            digest.push_back(hex[byte & 0x0F]);
        }
    }

    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    CloseHandle(file);
    return digest;
}

std::wstring ExecutableVersionString(const std::filesystem::path& path) {
    DWORD ignored = 0;
    DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
    if (size == 0) {
        return {};
    }
    std::vector<BYTE> data(size);
    if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
        return {};
    }
    VS_FIXEDFILEINFO* info = nullptr;
    UINT info_size = 0;
    if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info), &info_size) ||
        info == nullptr) {
        return {};
    }
    wchar_t buffer[64]{};
    swprintf_s(buffer, L"%u.%u.%u.%u",
               HIWORD(info->dwFileVersionMS), LOWORD(info->dwFileVersionMS),
               HIWORD(info->dwFileVersionLS), LOWORD(info->dwFileVersionLS));
    return buffer;
}

std::wstring FormatLastError(DWORD error) {
    wchar_t* buffer = nullptr;
    FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                       FORMAT_MESSAGE_IGNORE_INSERTS,
                   nullptr, error, 0, reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
    std::wstring result = buffer ? buffer : L"Unknown error";
    if (buffer) {
        LocalFree(buffer);
    }
    while (!result.empty() && (result.back() == L'\r' || result.back() == L'\n')) {
        result.pop_back();
    }
    return result;
}

std::filesystem::path ExecutablePath() {
    std::wstring buffer(32768, L'\0');
    const DWORD length =
        GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    buffer.resize(length);
    return buffer;
}

std::filesystem::path ExecutableDirectory() {
    return ExecutablePath().parent_path();
}

Translation::Translation(const std::filesystem::path& root) {
    const auto candidates = {
        root / L"translations.json",
        root / L"_internal" / L"translations.json",
    };
    for (const auto& candidate : candidates) {
        if (auto parsed = ReadJson(candidate)) {
            translations_ = std::move(*parsed);
            break;
        }
    }
    DetectLanguage();
}

void Translation::DetectLanguage() {
    const LANGID lang = GetUserDefaultUILanguage();
    switch (PRIMARYLANGID(lang)) {
        case LANG_CHINESE: {
            const WORD sublang = SUBLANGID(lang);
            language_ = sublang == SUBLANG_CHINESE_TRADITIONAL ||
                                sublang == SUBLANG_CHINESE_HONGKONG ||
                                sublang == SUBLANG_CHINESE_MACAU
                            ? "zh_TW"
                            : "zh_CN";
            break;
        }
        case LANG_ENGLISH: language_ = "en_US"; break;
        case LANG_JAPANESE: language_ = "ja"; break;
        case LANG_KOREAN: language_ = "ko"; break;
        case LANG_FRENCH: language_ = "fr"; break;
        case LANG_GERMAN: language_ = "de"; break;
        case LANG_RUSSIAN: language_ = "ru"; break;
        case LANG_SPANISH: language_ = "es"; break;
        case LANG_PORTUGUESE: language_ = "pt"; break;
        default: language_ = "en_US"; break;
    }
    if (!translations_.contains(language_)) {
        language_ = translations_.contains("en_US") ? "en_US" : "zh_CN";
    }
}

std::string Translation::Get(std::string_view key, std::string_view fallback) const {
    auto lookup = [&](const char* language) -> std::optional<std::string> {
        if (!translations_.contains(language)) {
            return std::nullopt;
        }
        const auto& table = translations_.at(language);
        const auto it = table.find(std::string(key));
        if (it != table.end() && it->is_string()) {
            return it->get<std::string>();
        }
        return std::nullopt;
    };
    if (const auto text = lookup(language_.c_str())) {
        return *text;
    }
    if (const auto text = lookup("en_US")) {
        return *text;
    }
    if (const auto text = lookup("zh_CN")) {
        return *text;
    }
    return fallback.empty() ? std::string(key) : std::string(fallback);
}

std::wstring Translation::GetW(std::string_view key, std::wstring_view fallback) const {
    return Utf8ToWide(Get(key, WideToUtf8(fallback)));
}

AppData::AppData(std::filesystem::path root) : root_(std::move(root)) {}

std::filesystem::path AppData::launch_config_dir() const {
    return root_ / L"launch_config";
}

std::filesystem::path AppData::custom_data_dir() const {
    return root_ / L"custom_data";
}

std::filesystem::path AppData::reshade_dir() const {
    return root_ / L"ReShade";
}

std::filesystem::path AppData::mod_loader_dir() const {
    return root_ / L"MOD_loader";
}

std::filesystem::path AppData::config_path(std::string_view name) const {
    return launch_config_dir() / (Utf8ToWide(name) + L".json");
}

std::filesystem::path AppData::resource_path(std::wstring_view relative) const {
    const auto direct = root_ / relative;
    if (FileExists(direct)) {
        return direct;
    }
    const auto internal = root_ / L"_internal" / relative;
    return FileExists(internal) ? internal : direct;
}

bool AppData::Load() {
    std::error_code ec;
    std::filesystem::create_directories(launch_config_dir(), ec);
    std::filesystem::create_directories(custom_data_dir(), ec);
    std::filesystem::create_directories(mod_loader_dir(), ec);

    globals_ = ReadJson(custom_data_dir() / L"global_settings.json").value_or(Json::object());
    custom_configs_ =
        ReadJson(custom_data_dir() / L"custom_configs.json").value_or(Json::object());
    if (!globals_.contains("reshade_enabled")) {
        globals_["reshade_enabled"] = true;
    }
    return true;
}

bool AppData::SaveGlobals() const {
    return WriteJsonAtomic(custom_data_dir() / L"global_settings.json", globals_);
}

bool AppData::SaveCustomConfigs() const {
    return WriteJsonAtomic(custom_data_dir() / L"custom_configs.json", custom_configs_);
}

std::string AppData::LastSelectedConfig() const {
    if (globals_.contains("last_selected_config") &&
        globals_["last_selected_config"].is_string()) {
        return globals_["last_selected_config"].get<std::string>();
    }
    return {};
}

void AppData::SetLastSelectedConfig(std::string_view name) {
    globals_["last_selected_config"] = name;
    SaveGlobals();
}

std::string AppData::BackgroundImage() const {
    if (globals_.contains("background_image") &&
        globals_["background_image"].is_string()) {
        return globals_["background_image"].get<std::string>();
    }
    return {};
}

void AppData::SetBackgroundImage(const std::filesystem::path& path) {
    globals_["background_image"] = WideToUtf8(path.wstring());
    SaveGlobals();
}

std::optional<SIZE> AppData::WindowClientSize() const {
    if (!globals_.contains("window_size") ||
        !globals_["window_size"].is_object()) {
        return std::nullopt;
    }
    const auto& size = globals_["window_size"];
    if (!size.contains("width") || !size["width"].is_number_integer() ||
        !size.contains("height") || !size["height"].is_number_integer()) {
        return std::nullopt;
    }
    const int width = size["width"].get<int>();
    const int height = size["height"].get<int>();
    if (width <= 0 || height <= 0) return std::nullopt;
    return SIZE{width, height};
}

bool AppData::SetWindowClientSize(SIZE size) {
    if (size.cx <= 0 || size.cy <= 0) return false;
    globals_["window_size"] = {
        {"width", size.cx},
        {"height", size.cy},
    };
    return SaveGlobals();
}

std::string AppData::DisplayName(std::string_view config_name) const {
    const auto it = custom_configs_.find(std::string(config_name));
    if (it != custom_configs_.end() && it->contains("display_name") &&
        (*it)["display_name"].is_string()) {
        return (*it)["display_name"].get<std::string>();
    }
    return std::string(config_name);
}

std::string AppData::CustomIcon(std::string_view config_name) const {
    const auto it = custom_configs_.find(std::string(config_name));
    if (it != custom_configs_.end() && it->contains("custom_icon_path") &&
        (*it)["custom_icon_path"].is_string()) {
        return (*it)["custom_icon_path"].get<std::string>();
    }
    return {};
}

bool AppData::SetCustomData(std::string_view config_name,
                            std::string_view display_name,
                            std::string_view custom_icon) {
    custom_configs_[std::string(config_name)] = {
        {"display_name", display_name},
        {"custom_icon_path", custom_icon.empty() ? Json(nullptr) : Json(custom_icon)},
    };
    return SaveCustomConfigs();
}

bool AppData::RemoveCustomData(std::string_view config_name) {
    custom_configs_.erase(std::string(config_name));
    return SaveCustomConfigs();
}

ConfigManager::ConfigManager(const AppData& app) : app_(app) {}

std::vector<LaunchProfile> ConfigManager::ListProfiles() const {
    std::vector<LaunchProfile> profiles;
    std::error_code ec;
    if (!DirectoryExists(app_.launch_config_dir())) {
        return profiles;
    }
    for (const auto& entry : std::filesystem::directory_iterator(app_.launch_config_dir(), ec)) {
        if (ec || !entry.is_regular_file() || entry.path().extension() != L".json") {
            continue;
        }
        auto profile = Load(WideToUtf8(entry.path().stem().wstring()));
        if (profile) {
            profiles.push_back(std::move(*profile));
        }
    }
    std::sort(profiles.begin(), profiles.end(), [](const auto& left, const auto& right) {
        return _wcsicmp(Utf8ToWide(left.display_name).c_str(),
                        Utf8ToWide(right.display_name).c_str()) < 0;
    });
    return profiles;
}

std::optional<LaunchProfile> ConfigManager::Load(std::string_view config_name) const {
    const auto data = ReadJson(app_.config_path(config_name));
    if (!data || !data->is_object()) {
        return std::nullopt;
    }
    LaunchProfile profile;
    profile.config_name = std::string(config_name);
    profile.display_name = app_.DisplayName(config_name);
    profile.custom_icon = app_.CustomIcon(config_name);
    if (data->contains("mode")) {
        if (!(*data)["mode"].is_string()) return std::nullopt;
        profile.mode = (*data)["mode"].get<std::string>();
    }
    for (const char* key : {"game_dir", "launch_program", "target_program"}) {
        if (!data->contains(key) || !(*data)[key].is_string()) continue;
        profile.game_exe =
            Utf8ToWide((*data)[key].get<std::string>());
        if (!profile.game_exe.empty()) break;
    }
    profile.data = *data;
    return profile;
}

bool ConfigManager::Save(std::string_view config_name, const Json& data) const {
    return WriteJsonAtomic(app_.config_path(config_name), data);
}

bool ConfigManager::Delete(std::string_view config_name) const {
    return DeleteFileW(app_.config_path(config_name).c_str()) != FALSE;
}

std::string ConfigManager::GameName(const std::filesystem::path& exe) const {
    return WideToUtf8(exe.stem().wstring());
}

std::string ConfigManager::BuiltinDisplayName(const std::filesystem::path& exe) const {
    return ToLower(GameName(exe)) == "azurpromilia" ? "蓝色星原" : std::string{};
}

Json ConfigManager::ReadVersionConfig() const {
    return ReadJson(app_.resource_path(L"version.json")).value_or(Json::object());
}

BuiltinModLoaderInfo ConfigManager::ResolveBuiltinModLoader(
    const std::filesystem::path& game_exe) const {
    BuiltinModLoaderInfo info;
    info.folder_name = GameName(game_exe);
    info.display_name = BuiltinDisplayName(game_exe);

    const Json version = ReadVersionConfig();
    if (!version.contains("builtin_mod_loaders") ||
        !version["builtin_mod_loaders"].is_array()) {
        return info;
    }

    const std::string executable =
        ToLower(WideToUtf8(game_exe.filename().wstring()));
    for (const auto& item : version["builtin_mod_loaders"]) {
        if (!item.is_object() || !item.contains("exe_names") ||
            !item["exe_names"].is_array()) {
            continue;
        }
        bool matches = false;
        for (const auto& name : item["exe_names"]) {
            if (name.is_string() &&
                ToLower(name.get<std::string>()) == executable) {
                matches = true;
                break;
            }
        }
        if (!matches) continue;

        info.folder_name =
            item.value("folder_name", info.folder_name);
        info.display_name =
            item.value("display_name", info.display_name);
        info.download_url =
            item.value("download_url", std::string{});
        info.download_size =
            item.value("size", std::uint64_t{0});
        info.sha256 = ToLower(item.value("sha256", std::string{}));
        return info;
    }
    return info;
}

std::string ConfigManager::DetermineXXMIModule(
    const std::filesystem::path& game_exe) const {
    const auto game = ToLower(GameName(game_exe));
    const Json version = ReadVersionConfig();
    const std::string wanted_key = "xxmi_launch_args_" + game;
    for (auto it = version.begin(); it != version.end(); ++it) {
        if (ToLower(it.key()) != wanted_key || !it.value().is_array()) {
            continue;
        }
        const auto& args = it.value();
        for (size_t index = 0; index + 1 < args.size(); ++index) {
            if (args[index].is_string() &&
                args[index].get<std::string>() == "--xxmi") {
                return args[index + 1].get<std::string>();
            }
        }
    }
    if (game == "yuanshen" || game == "genshinimpact") return "GIMI";
    if (game == "bh3") return "HIMI";
    if (game == "starrail") return "SRMI";
    if (game == "zenlesszonezero" || game == "zenlesszonezerobeta") {
        return "ZZMI";
    }
    if (game == "client-win64-shipping") return "WWMI";
    if (game == "endfield") return "EFMI";
    return {};
}

std::pair<std::filesystem::path, std::filesystem::path>
ConfigManager::DeterminePrograms(const std::filesystem::path& game_exe,
                                 std::wstring_view) const {
    const auto name = ToLower(game_exe.filename().wstring());
    if (name == L"client-win64-shipping.exe") {
        auto launcher = game_exe.parent_path() / L".." / L".." / L".." / L"Wuthering Waves.exe";
        launcher = std::filesystem::weakly_canonical(launcher);
        if (!FileExists(launcher)) {
            launcher = game_exe.parent_path() / L"Wuthering Waves.exe";
        }
        return {FileExists(launcher) ? launcher : game_exe, game_exe};
    }
    if (name == L"wuthering waves.exe") {
        auto target = game_exe.parent_path() / L"Client" / L"Binaries" / L"Win64" /
                      L"Client-Win64-Shipping.exe";
        return {game_exe, FileExists(target) ? target : game_exe};
    }
    return {game_exe, game_exe};
}

std::wstring ConfigManager::DefaultLaunchArguments(
    const std::filesystem::path& game_exe) const {
    const auto name = ToLower(game_exe.filename().wstring());
    if (name == L"client-win64-shipping.exe" ||
        name == L"wuthering waves.exe") {
        return L"-dx11";
    }
    return L"-force-d3d11";
}

std::filesystem::path ConfigManager::FindXXMIDll(
    const std::filesystem::path& xxmi_exe, std::string_view module) const {
    const auto root = xxmi_exe.parent_path().parent_path().parent_path();
    const auto config_path = root / L"XXMI Launcher Config.json";
    if (const auto config = ReadJson(config_path)) {
        const auto module_name = std::string(module);
        if (config->contains("Importers") && (*config)["Importers"].contains(module_name)) {
            const auto& importer = (*config)["Importers"][module_name]["Importer"];
            const auto libraries = importer.value("extra_libraries", "");
            std::istringstream lines(libraries);
            std::string line;
            while (std::getline(lines, line)) {
                if (EndsWithInsensitive(Utf8ToWide(ToLower(Trim(line))), L"d3d11.dll")) {
                    const auto path = Utf8ToWide(Trim(line));
                    if (FileExists(path)) {
                        return path;
                    }
                }
            }
        }
    }
    return root / Utf8ToWide(std::string(module)) / L"d3d11.dll";
}

LaunchProfile PersistCreatedProfile(const AppData& app,
                                    const ConfigManager& configs,
                                    LaunchProfile profile) {
    if (!configs.Save(profile.config_name, profile.data)) {
        profile.save_error =
            "Cannot save configuration: " +
            WideToUtf8(app.config_path(profile.config_name).wstring());
        return profile;
    }
    auto& mutable_app = const_cast<AppData&>(app);
    if (!mutable_app.SetCustomData(profile.config_name, profile.display_name,
                                   profile.custom_icon)) {
        configs.Delete(profile.config_name);
        profile.save_error =
            "Cannot save custom configuration data: " +
            WideToUtf8(
                (app.custom_data_dir() / L"custom_configs.json").wstring());
    }
    return profile;
}

LaunchProfile ConfigManager::CreateXXMI(const std::filesystem::path& game_exe,
                                        const std::filesystem::path& xxmi_exe,
                                        bool enable_reshade) const {
    const auto game_name = GameName(game_exe);
    const auto config_name = game_name + "_xxmi";
    const auto module = DetermineXXMIModule(game_exe);
    if (module.empty()) {
        LaunchProfile profile{
            config_name, config_name, "", game_exe, "xxmi", Json::object(), {}};
        profile.save_error =
            "Cannot determine the XXMI module for " +
            WideToUtf8(game_exe.filename().wstring());
        return profile;
    }
    const auto [launch, target] = DeterminePrograms(game_exe, L"xxmi");
    const auto dll = FindXXMIDll(xxmi_exe, module);
    if (!FileExists(dll)) {
        LaunchProfile profile{
            config_name, config_name, "", game_exe, "xxmi", Json::object(), {}};
        profile.save_error =
            "Cannot find the XXMI module DLL: " + WideToUtf8(dll.wstring());
        return profile;
    }
    Json data = {
        {"launch_program", WideToUtf8(launch.wstring())},
        {"target_program", WideToUtf8(target.wstring())},
        {"launch_args", WideToUtf8(DefaultLaunchArguments(game_exe))},
        {"game_dir", WideToUtf8(game_exe.wstring())},
        {"game_exe_name", WideToUtf8(game_exe.filename().wstring())},
        {"dll_files", Json::array({WideToUtf8(dll.wstring())})},
        {"xxmi_launcher_path", WideToUtf8(xxmi_exe.wstring())},
        {"xxmi_exe_name", WideToUtf8(xxmi_exe.filename().wstring())},
        {"xxmi_module", module},
        {"mode", "xxmi"},
        {"injection_method", "direct"},
        {"pre_launch_command", ""},
        {"pre_launch_wait_seconds", 0},
    };
    if (enable_reshade) {
        data["reshade_dll"] = "ReShade64.dll";
    }
    return PersistCreatedProfile(
        app_, *this,
        LaunchProfile{config_name, config_name, "", game_exe, "xxmi",
                      std::move(data), {}});
}

LaunchProfile ConfigManager::CreateBuiltin(const std::filesystem::path& game_exe,
                                           bool enable_reshade) const {
    const auto game_name = GameName(game_exe);
    const auto config_name = game_name + "_builtin";
    const auto [launch, target] = DeterminePrograms(game_exe, L"builtin");
    const auto loader_info = ResolveBuiltinModLoader(game_exe);
    const auto loader =
        app_.mod_loader_dir() / Utf8ToWide(loader_info.folder_name);
    const auto d3d11 = loader / L"d3d11.dll";
    Json data = {
        {"launch_program", WideToUtf8(launch.wstring())},
        {"target_program", WideToUtf8(target.wstring())},
        {"launch_args", ToLower(game_name) == "azurpromilia"
                            ? "-start=azurpromilia_launcher"
                            : WideToUtf8(DefaultLaunchArguments(game_exe))},
        {"game_dir", WideToUtf8(game_exe.wstring())},
        {"game_exe_name", WideToUtf8(game_exe.filename().wstring())},
        {"mod_loader_dir", WideToUtf8(loader.wstring())},
        {"d3d11_path", WideToUtf8(d3d11.wstring())},
        {"d3d11_exists", FileExists(d3d11)},
        {"mode", "builtin"},
        {"injection_method", "direct"},
        {"pre_launch_command", ""},
        {"pre_launch_wait_seconds", 0},
    };
    if (enable_reshade) {
        data["reshade_dll"] = "ReShade64.dll";
    }
    const auto display = loader_info.display_name;
    return PersistCreatedProfile(
        app_, *this,
        LaunchProfile{config_name,
                      display.empty() ? config_name : display, "", game_exe,
                      "builtin", std::move(data), {}});
}

LaunchProfile ConfigManager::CreateGame(const std::filesystem::path& game_exe,
                                        bool enable_reshade) const {
    const auto game_name = GameName(game_exe);
    const auto config_name = game_name + "_reshade";
    const auto [launch, target] = DeterminePrograms(game_exe, L"game");
    Json data = {
        {"launch_program", WideToUtf8(launch.wstring())},
        {"target_program", WideToUtf8(target.wstring())},
        {"launch_args", WideToUtf8(DefaultLaunchArguments(game_exe))},
        {"game_dir", WideToUtf8(game_exe.wstring())},
        {"game_exe_name", WideToUtf8(game_exe.filename().wstring())},
        {"mode", "game"},
        {"injection_method", "direct"},
        {"pre_launch_command", ""},
        {"pre_launch_wait_seconds", 0},
    };
    if (enable_reshade) {
        data["reshade_dll"] = "ReShade64.dll";
    }
    return PersistCreatedProfile(
        app_, *this,
        LaunchProfile{config_name, config_name, "", game_exe, "game",
                      std::move(data), {}});
}

LaunchProfile ConfigManager::CreateCustom(
    const std::filesystem::path& game_exe,
    const std::vector<std::filesystem::path>& dlls,
    bool enable_reshade) const {
    const auto game_name = GameName(game_exe);
    const auto config_name = game_name + "_custom";
    const auto [launch, target] = DeterminePrograms(game_exe, L"custom");
    Json dll_array = Json::array();
    bool include_reshade = enable_reshade;
    std::vector<std::wstring> seen;
    for (const auto& dll : dlls) {
        if (_wcsicmp(dll.filename().c_str(), L"ReShade64.dll") == 0) {
            include_reshade = true;
            continue;
        }
        const std::wstring key = ToLower(dll.wstring());
        if (std::find(seen.begin(), seen.end(), key) != seen.end()) {
            continue;
        }
        seen.push_back(key);
        dll_array.push_back(WideToUtf8(dll.wstring()));
    }
    Json data = {
        {"launch_program", WideToUtf8(launch.wstring())},
        {"target_program", WideToUtf8(target.wstring())},
        {"launch_args", WideToUtf8(DefaultLaunchArguments(game_exe))},
        {"game_dir", WideToUtf8(game_exe.wstring())},
        {"game_exe_name", WideToUtf8(game_exe.filename().wstring())},
        {"dll_files", std::move(dll_array)},
        {"mode", "custom"},
        {"injection_method", "direct"},
        {"pre_launch_command", ""},
        {"pre_launch_wait_seconds", 0},
    };
    if (include_reshade) {
        data["reshade_dll"] = "ReShade64.dll";
    }
    return PersistCreatedProfile(
        app_, *this,
        LaunchProfile{config_name, config_name, "", game_exe, "custom",
                      std::move(data), {}});
}

}  // namespace rs
