#pragma once

#include <windows.h>
#include <shellapi.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include <d2d1.h>
#include <dwrite.h>
#include <wincodec.h>

#include "core/common.h"
#include "game/game.h"

namespace rs {

void RunManualUpdate(HWND owner, const AppData& app, const Translation& translation);
bool EnsureFullShaderPack(HWND owner, const AppData& app,
                          const Translation& translation,
                          bool confirm_download = true);
bool DownloadGitHubAsset(HWND owner, const Translation& translation,
                         std::wstring_view title, std::string_view url,
                         std::uint64_t expected_size,
                         std::string_view expected_sha256,
                         const std::filesystem::path& destination,
                         std::string* error, bool* cancelled = nullptr);

class MainWindow {
public:
    explicit MainWindow(HINSTANCE instance);
    ~MainWindow();

    bool Create(std::optional<std::string> startup_config = std::nullopt);
    int Run();

private:
    enum class Action {
        None,
        SelectConfig,
        Launch,
        FixShadow,
        AddGame,
        ReshadeToggle,
        ForceClose,
        Help,
        ChangeBackground,
        SaveModPreset,
        ModsFolder,
        ShaderToggle,
        Update,
        ConfigRefresh,
        CancelXXMIScan,
        ConfigEdit,
        ConfigShortcut,
        XXMIGame,
        ModeXXMI,
        ModeBuiltin,
        ModeGame,
        ModeCustom,
    };

    struct HitArea {
        RECT rect{};
        Action action = Action::None;
        int index = -1;
    };

    struct LaunchPayload {
        std::uint64_t launch_id = 0;
        bool ok = false;
        std::string error;
        std::string config_name;
        std::string game_exe_name;
        LaunchSession session;
    };

    struct ModPresetPayload {
        size_t updated_files = 0;
        size_t scanned_files = 0;
        size_t failed_files = 0;
        std::string error;
        std::filesystem::path target;
        std::filesystem::path log_path;
        std::vector<std::string> log;
    };

    struct XXMIGameOption {
        std::string exe;
        std::string name_key;
    };

    struct XXMIScanPayload {
        std::filesystem::path xxmi_exe;
        std::filesystem::path game_exe;
        std::string game_exe_name;
        std::string display_name;
    };

    static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                       LPARAM lparam);
    LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
    void InitializeGraphics();
    void DiscardGraphics();
    void ResizeGraphics(UINT width, UINT height);
    void LoadBackground();
    void RebuildProfileIcons();
    void Draw();
    void DrawButton(const HitArea& area, std::wstring_view label, bool active = false,
                    bool icon = false, ID2D1Bitmap* bitmap = nullptr,
                    bool allow_hover = true);
    void DrawPictureIcon(const RECT& rect);
    void DrawTooltip();
    void DrawShaderSwitch(const RECT& rect, ShaderPackManager::Mode mode,
                          bool allow_hover = true);
    void DrawConfigMenu();
    void DrawModeMenu();
    void DrawXXMIGameMenu();
    void AddHitArea(Action action, RECT rect, int index = -1);
    Action HitTest(POINT point, int* index = nullptr, RECT* rect = nullptr) const;
    void UpdateTooltip(Action action, int index, const RECT& anchor);
    void HideTooltip();
    void OnClick(POINT point);
    void RefreshProfiles(bool preserve_selection = true);
    void SelectProfile(int index);
    void StartLaunch(bool shortcut = false);
    void ToggleShadowFix();
    void SetStatus(std::string text);
    void OpenAddMode();
    void HandleMode(Action mode);
    void CompleteProfileCreation(const LaunchProfile& profile,
                                 std::string_view success_message_key,
                                 std::wstring_view fallback_message,
                                 bool show_success = true);
    void OpenXXMIGameSelection(const std::filesystem::path& xxmi_exe);
    void BeginXXMIScan(const XXMIGameOption& game);
    void OnXXMIScanFinished(XXMIScanPayload* payload);
    void EditSelectedProfile();
    void ToggleShaderMode();
    void StartModPreset(const std::filesystem::path& mods_directory = {});
    void StartModPresetSelect();
    void OnModPresetFinished(ModPresetPayload* payload);
    void ResolveAndOpenMods();
    void ChooseBackground();
    void ShowConfigMenu();
    void AdvanceBackgroundFrame();
    void UpdateWindowIcons();
    void ShowNotification(std::wstring_view title, std::wstring_view message);
    void StopActiveSession();
    void UpdateTrayIcon();
    void HideToTray();
    void ShowFromTray();
    void OnLaunchFinished(LaunchPayload* payload);
    void OnGameExited(std::uint64_t launch_id);
    void CheckGameWindow();
    void OnDpiChanged(UINT dpi, const RECT* suggested);
    SIZE PreferredWindowClientSize() const;
    void ApplyPreferredWindowClientSize(bool preserve_position);
    void SaveWindowClientSize();
    RECT ScaledRect(float x, float y, float width, float height) const;
    float Scale() const;
    bool IsBusy() const { return busy_; }
    std::wstring CurrentDisplayName() const;
    std::filesystem::path CurrentGameExecutable() const;
    std::filesystem::path ResolveModsFolder() const;
    std::filesystem::path ResolveD3dxUserIni() const;

    HINSTANCE instance_ = nullptr;
    HWND hwnd_ = nullptr;
    UINT dpi_ = 96;
    UINT taskbar_created_message_ = 0;
    AppData app_;
    Translation translation_;
    ConfigManager configs_;
    ProcessManager processes_;
    ModLoaderManager mod_loaders_;
    ShaderPackManager shaders_;
    ShaderPackManager::Mode shader_mode_ = ShaderPackManager::Mode::Unknown;
    std::vector<LaunchProfile> profiles_;
    std::vector<XXMIGameOption> xxmi_games_;
    std::filesystem::path pending_xxmi_exe_;
    int selected_index_ = -1;
    bool config_menu_open_ = false;
    bool mode_menu_open_ = false;
    bool xxmi_menu_open_ = false;
    bool mode_reshade_enabled_ = true;
    bool busy_ = false;
    bool mod_preset_running_ = false;
    bool xxmi_scanning_ = false;
    bool launched_by_shortcut_ = false;
    std::optional<std::string> startup_config_;
    std::string status_ = "Ready";
    std::vector<HitArea> hit_areas_;
    int keyboard_focus_ = -1;
    RECT keyboard_focus_rect_{};
    bool keyboard_focus_visible_ = false;
    POINT mouse_{};
    Action hover_action_ = Action::None;
    int hover_index_ = -1;
    RECT tooltip_anchor_{};
    std::wstring tooltip_text_;
    std::wstring background_path_;
    std::atomic_bool center_stop_{false};
    std::atomic_bool xxmi_scan_cancel_{false};
    std::thread center_thread_;
    std::thread xxmi_scan_thread_;
    std::optional<LaunchSession> active_session_;
    std::thread wait_thread_;
    bool poll_target_exit_ = false;
    bool game_window_seen_ = false;
    bool initial_window_resized_ = false;
    bool config_dir_time_valid_ = false;
    std::filesystem::file_time_type config_dir_time_{};
    std::uint64_t next_launch_id_ = 1;
    std::uint64_t active_launch_id_ = 0;
    NOTIFYICONDATAW tray_{};
    bool tray_visible_ = false;
    HICON window_icon_large_ = nullptr;
    HICON window_icon_small_ = nullptr;
    HICON tray_icon_ = nullptr;
    size_t config_menu_offset_ = 0;

    ID2D1Factory* d2d_factory_ = nullptr;
    IDWriteFactory* dwrite_factory_ = nullptr;
    IWICImagingFactory* wic_factory_ = nullptr;
    ID2D1HwndRenderTarget* render_target_ = nullptr;
    ID2D1SolidColorBrush* brush_ = nullptr;
    std::vector<ID2D1Bitmap*> background_frames_;
    std::vector<ID2D1Bitmap*> profile_icons_;
    std::vector<UINT> background_frame_delays_ms_;
    size_t background_frame_index_ = 0;
    IDWriteTextFormat* title_format_ = nullptr;
    IDWriteTextFormat* text_format_ = nullptr;
    IDWriteTextFormat* small_format_ = nullptr;
    IDWriteTextFormat* button_format_ = nullptr;
    IDWriteTextFormat* icon_format_ = nullptr;
};

}  // namespace rs
