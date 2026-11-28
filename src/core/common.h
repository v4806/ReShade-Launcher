#pragma once

#include <windows.h>

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "nlohmann/json.hpp"

namespace rs {

using Json = nlohmann::ordered_json;

std::string WideToUtf8(std::wstring_view value);
std::wstring Utf8ToWide(std::string_view value);
std::wstring ToLower(std::wstring_view value);
std::string ToLower(std::string value);
bool EndsWithInsensitive(std::wstring_view value, std::wstring_view suffix);
bool FileExists(const std::filesystem::path& path);
bool DirectoryExists(const std::filesystem::path& path);
std::optional<std::string> ReadUtf8(const std::filesystem::path& path);
bool WriteUtf8Atomic(const std::filesystem::path& path, std::string_view contents);
std::optional<Json> ReadJson(const std::filesystem::path& path);
bool WriteJsonAtomic(const std::filesystem::path& path, const Json& value);
std::string Sha256File(const std::filesystem::path& path);
std::wstring ExecutableVersionString(const std::filesystem::path& path);
std::wstring FormatLastError(DWORD error = GetLastError());
std::filesystem::path ExecutableDirectory();
std::filesystem::path ExecutablePath();

class Translation {
public:
    explicit Translation(const std::filesystem::path& root);

    std::string Get(std::string_view key, std::string_view fallback = {}) const;
    std::wstring GetW(std::string_view key, std::wstring_view fallback = {}) const;
    const std::string& language() const { return language_; }

private:
    void DetectLanguage();

    Json translations_;
    std::string language_ = "zh_CN";
};

class AppData {
public:
    explicit AppData(std::filesystem::path root);

    const std::filesystem::path& root() const { return root_; }
    std::filesystem::path launch_config_dir() const;
    std::filesystem::path custom_data_dir() const;
    std::filesystem::path reshade_dir() const;
    std::filesystem::path mod_loader_dir() const;
    std::filesystem::path config_path(std::string_view name) const;
    std::filesystem::path resource_path(std::wstring_view relative) const;

    Json& globals() { return globals_; }
    const Json& globals() const { return globals_; }
    Json& custom_configs() { return custom_configs_; }
    const Json& custom_configs() const { return custom_configs_; }

    bool Load();
    bool SaveGlobals() const;
    bool SaveCustomConfigs() const;
    std::string LastSelectedConfig() const;
    void SetLastSelectedConfig(std::string_view name);
    std::string BackgroundImage() const;
    void SetBackgroundImage(const std::filesystem::path& path);
    std::optional<SIZE> WindowClientSize() const;
    bool SetWindowClientSize(SIZE size);
    std::string DisplayName(std::string_view config_name) const;
    std::string CustomIcon(std::string_view config_name) const;
    bool SetCustomData(std::string_view config_name, std::string_view display_name,
                       std::string_view custom_icon);
    bool RemoveCustomData(std::string_view config_name);

private:
    std::filesystem::path root_;
    Json globals_ = Json::object();
    Json custom_configs_ = Json::object();
};

struct LaunchProfile {
    std::string config_name;
    std::string display_name;
    std::string custom_icon;
    std::filesystem::path game_exe;
    std::string mode;
    Json data;
    std::string save_error;
};

struct BuiltinModLoaderInfo {
    std::string folder_name;
    std::string display_name;
    std::string download_url;
    std::uint64_t download_size = 0;
    std::string sha256;

    bool downloadable() const {
        return !folder_name.empty() && !download_url.empty() &&
               download_size > 0 && sha256.size() == 64;
    }
};

class ConfigManager {
public:
    explicit ConfigManager(const AppData& app);

    std::vector<LaunchProfile> ListProfiles() const;
    std::optional<LaunchProfile> Load(std::string_view config_name) const;
    bool Save(std::string_view config_name, const Json& data) const;
    bool Delete(std::string_view config_name) const;

    LaunchProfile CreateXXMI(const std::filesystem::path& game_exe,
                             const std::filesystem::path& xxmi_exe,
                             bool enable_reshade) const;
    LaunchProfile CreateBuiltin(const std::filesystem::path& game_exe,
                                bool enable_reshade) const;
    LaunchProfile CreateGame(const std::filesystem::path& game_exe,
                             bool enable_reshade) const;
    LaunchProfile CreateCustom(const std::filesystem::path& game_exe,
                               const std::vector<std::filesystem::path>& dlls,
                               bool enable_reshade) const;

    std::string GameName(const std::filesystem::path& exe) const;
    std::string BuiltinDisplayName(const std::filesystem::path& exe) const;
    std::string DetermineXXMIModule(const std::filesystem::path& game_exe) const;
    BuiltinModLoaderInfo ResolveBuiltinModLoader(
        const std::filesystem::path& game_exe) const;

private:
    Json ReadVersionConfig() const;
    std::pair<std::filesystem::path, std::filesystem::path> DeterminePrograms(
        const std::filesystem::path& game_exe, std::wstring_view mode) const;
    std::wstring DefaultLaunchArguments(
        const std::filesystem::path& game_exe) const;
    std::filesystem::path FindXXMIDll(const std::filesystem::path& xxmi_exe,
                                      std::string_view module) const;

    const AppData& app_;
};

}  // namespace rs
