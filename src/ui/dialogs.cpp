#include "ui/dialogs.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <richedit.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wincodec.h>
#include <windowsx.h>

#include "ui/overlay_window.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <cwctype>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace rs {
namespace {

std::wstring GetControlText(HWND control) {
    const int length = GetWindowTextLengthW(control);
    std::wstring value(static_cast<size_t>(std::max(0, length)) + 1, L'\0');
    GetWindowTextW(control, value.data(), static_cast<int>(value.size()));
    value.resize(static_cast<size_t>(std::max(0, length)));
    return value;
}

void SetControlText(HWND control, std::wstring_view value) {
    SetWindowTextW(control, std::wstring(value).c_str());
}

constexpr int kDialogWidth = 760;
constexpr int kContentHeight = 860;
constexpr int kBrowseIcon = 1001;
constexpr int kBrowseLaunch = 1002;
constexpr int kBrowseTarget = 1003;
constexpr int kBrowseDlls = 1004;
constexpr int kDelete = 1005;
constexpr int kRemoveDll = 1006;
constexpr int kMoveDllUp = 1007;
constexpr int kMoveDllDown = 1008;
constexpr int kResetIcon = 1009;
constexpr int kToggleReshade = 1010;
constexpr int kHelpTabBase = 1100;
constexpr int kIconPreview = 1110;
constexpr UINT_PTR kProfileCheckboxSubclass = 1;
constexpr UINT_PTR kHoverTrackingSubclass = 9001;
constexpr wchar_t kHoverProperty[] = L"ReShadeLauncher.Hovered";

COLORREF ColorBackground() { return RGB(8, 13, 26); }
COLORREF ColorPanel() { return RGB(23, 31, 56); }
COLORREF ColorPanelHover() { return RGB(26, 66, 115); }
COLORREF ColorControl() { return RGB(31, 44, 78); }
COLORREF ColorInput() { return RGB(9, 17, 31); }
COLORREF ColorBorder() { return RGB(42, 56, 86); }
COLORREF ColorText() { return RGB(242, 246, 255); }
COLORREF ColorMuted() { return RGB(173, 184, 217); }
COLORREF ColorAccent() { return RGB(92, 255, 72); }

struct BackgroundImage {
    HBITMAP bitmap = nullptr;
    UINT width = 0;
    UINT height = 0;

    void Clear() {
        if (bitmap) DeleteObject(bitmap);
        bitmap = nullptr;
        width = 0;
        height = 0;
    }
};

void LoadBackgroundImage(const std::filesystem::path& path,
                         BackgroundImage* background) {
    if (!background) return;
    background->Clear();
    if (!FileExists(path)) return;

    IWICImagingFactory* factory = nullptr;
    IWICBitmapDecoder* decoder = nullptr;
    IWICBitmapFrameDecode* frame = nullptr;
    IWICFormatConverter* converter = nullptr;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
        return;
    }
    if (SUCCEEDED(factory->CreateDecoderFromFilename(
            path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad,
            &decoder)) &&
        SUCCEEDED(decoder->GetFrame(0, &frame)) &&
        SUCCEEDED(factory->CreateFormatConverter(&converter)) &&
        SUCCEEDED(converter->Initialize(
            frame, GUID_WICPixelFormat32bppPBGRA,
            WICBitmapDitherTypeNone, nullptr, 0.0,
            WICBitmapPaletteTypeCustom))) {
        UINT width = 0;
        UINT height = 0;
        if (SUCCEEDED(frame->GetSize(&width, &height)) && width && height) {
            BITMAPINFO info{};
            info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
            info.bmiHeader.biWidth = static_cast<LONG>(width);
            info.bmiHeader.biHeight = -static_cast<LONG>(height);
            info.bmiHeader.biPlanes = 1;
            info.bmiHeader.biBitCount = 32;
            info.bmiHeader.biCompression = BI_RGB;
            void* pixels = nullptr;
            HBITMAP bitmap =
                CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels,
                                 nullptr, 0);
            const UINT stride = width * 4;
            if (bitmap && pixels &&
                SUCCEEDED(converter->CopyPixels(
                    nullptr, stride, stride * height,
                    static_cast<BYTE*>(pixels)))) {
                background->bitmap = bitmap;
                background->width = width;
                background->height = height;
            } else if (bitmap) {
                DeleteObject(bitmap);
            }
        }
    }
    if (converter) converter->Release();
    if (frame) frame->Release();
    if (decoder) decoder->Release();
    if (factory) factory->Release();
}

std::filesystem::path DefaultDialogBackground() {
    const auto executable_dir = ExecutableDirectory();
    const std::array candidates = {
        executable_dir / L"b.jpg",
        executable_dir / L"_internal" / L"b.jpg",
    };
    for (const auto& path : candidates) {
        if (FileExists(path)) return path;
    }
    std::error_code error;
    const auto working_dir = std::filesystem::current_path(error);
    if (!error && FileExists(working_dir / L"b.jpg")) {
        return working_dir / L"b.jpg";
    }
    return candidates.front();
}

void DrawBackgroundCover(HDC dc, const RECT& target,
                         const BackgroundImage& background,
                         BYTE opacity = 165) {
    if (!dc || !background.bitmap || !background.width || !background.height) {
        return;
    }
    const int target_width = target.right - target.left;
    const int target_height = target.bottom - target.top;
    if (target_width <= 0 || target_height <= 0) return;

    double scale = std::max(
        static_cast<double>(target_width) / background.width,
        static_cast<double>(target_height) / background.height);
    int source_width = std::min<int>(
        background.width, static_cast<int>(target_width / scale));
    int source_height = std::min<int>(
        background.height, static_cast<int>(target_height / scale));
    const int source_x = (background.width - source_width) / 2;
    const int source_y = (background.height - source_height) / 2;

    HDC memory = CreateCompatibleDC(dc);
    if (!memory) return;
    const HGDIOBJ previous = SelectObject(memory, background.bitmap);
    BLENDFUNCTION blend{AC_SRC_OVER, 0, opacity, AC_SRC_ALPHA};
    AlphaBlend(dc, target.left, target.top, target_width, target_height,
               memory, source_x, source_y, source_width, source_height,
               blend);
    SelectObject(memory, previous);
    DeleteDC(memory);
}

void FillBackgroundSegment(HDC dc, RECT target, RECT control_in_parent,
                           const RECT& parent_client,
                           const BackgroundImage& background) {
    const int width = target.right - target.left;
    const int height = target.bottom - target.top;
    if (width <= 0 || height <= 0) return;

    HDC memory = CreateCompatibleDC(dc);
    HBITMAP bitmap = memory ? CreateCompatibleBitmap(dc, width, height) : nullptr;
    if (!memory || !bitmap) {
        if (bitmap) DeleteObject(bitmap);
        if (memory) DeleteDC(memory);
        HBRUSH fallback = CreateSolidBrush(ColorBackground());
        FillRect(dc, &target, fallback);
        DeleteObject(fallback);
        return;
    }

    const HGDIOBJ old_bitmap = SelectObject(memory, bitmap);
    RECT local{0, 0, width, height};
    HBRUSH background_brush = CreateSolidBrush(ColorBackground());
    FillRect(memory, &local, background_brush);
    DeleteObject(background_brush);

    POINT old_origin{};
    SetViewportOrgEx(memory, -control_in_parent.left, -control_in_parent.top,
                     &old_origin);
    DrawBackgroundCover(memory, parent_client, background);
    SetViewportOrgEx(memory, old_origin.x, old_origin.y, nullptr);
    BitBlt(dc, target.left, target.top, width, height, memory, 0, 0, SRCCOPY);

    SelectObject(memory, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory);
}

int Dip(UINT dpi, int value) {
    return MulDiv(value, static_cast<int>(dpi), 96);
}

void DrawRoundedSurface(HDC dc, RECT rect, COLORREF fill, COLORREF border,
                        UINT dpi, int radius_dip, bool draw_border = true) {
    HBRUSH fill_brush = CreateSolidBrush(fill);
    HPEN border_pen =
        draw_border ? CreatePen(PS_SOLID, std::max(1, Dip(dpi, 1)), border)
                    : static_cast<HPEN>(GetStockObject(NULL_PEN));
    const HGDIOBJ old_brush = SelectObject(dc, fill_brush);
    const HGDIOBJ old_pen = SelectObject(dc, border_pen);
    const int diameter = Dip(dpi, radius_dip * 2);
    RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, diameter,
              diameter);
    SelectObject(dc, old_pen);
    SelectObject(dc, old_brush);
    if (draw_border) DeleteObject(border_pen);
    DeleteObject(fill_brush);
}

void DrawRoundedOutline(HDC dc, RECT rect, COLORREF border, UINT dpi,
                        int radius_dip) {
    HPEN pen = CreatePen(PS_SOLID, std::max(1, Dip(dpi, 1)), border);
    const HGDIOBJ old_brush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
    const HGDIOBJ old_pen = SelectObject(dc, pen);
    const int diameter = Dip(dpi, radius_dip * 2);
    RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, diameter,
              diameter);
    SelectObject(dc, old_pen);
    SelectObject(dc, old_brush);
    DeleteObject(pen);
}

std::wstring ReplaceToken(std::wstring value, std::wstring_view token,
                          std::wstring_view replacement) {
    size_t offset = 0;
    while ((offset = value.find(token, offset)) != std::wstring::npos) {
        value.replace(offset, token.size(), replacement);
        offset += replacement.size();
    }
    return value;
}

std::wstring Tr(const Translation& translation, std::string_view key,
                std::wstring_view fallback) {
    std::wstring value = translation.GetW(key, L"");
    return value.empty() ? std::wstring(fallback) : value;
}

std::wstring NormalizePathSeparators(std::wstring value) {
    std::replace(value.begin(), value.end(), L'\\', L'/');
    return value;
}

std::wstring ProfileTitle(const Translation& translation,
                          std::string_view config_name) {
    return ReplaceToken(
        Tr(translation, "cxx.edit_config.title", L"编辑配置: {name}"), L"{name}",
        Utf8ToWide(config_name));
}

void SetFont(HWND control, HFONT font) {
    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}

void SetEditMargins(HWND control) {
    SendMessageW(control, EM_SETMARGINS, EC_LEFTMARGIN | EC_RIGHTMARGIN,
                 MAKELPARAM(8, 8));
}

HWND CreateChild(HWND parent, const wchar_t* cls, const wchar_t* text, DWORD style,
                 int id = 0, DWORD extended_style = 0) {
    return CreateWindowExW(
        extended_style, cls, text, WS_CHILD | WS_VISIBLE | style, 0, 0, 10, 10,
        parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
        GetModuleHandleW(nullptr), nullptr);
}

HFONT CreateUiFont(UINT dpi, int points, int weight) {
    return CreateFontW(-MulDiv(points, static_cast<int>(dpi), 72), 0, 0, 0, weight,
                       FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                       CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH,
                       L"Segoe UI");
}

void SetDarkWindowFrame(HWND window) {
    const BOOL enabled = TRUE;
    DwmSetWindowAttribute(window, 20, &enabled, sizeof(enabled));
    const COLORREF background = ColorBackground();
    const COLORREF text = ColorText();
    DwmSetWindowAttribute(window, 35, &background, sizeof(background));
    DwmSetWindowAttribute(window, 36, &text, sizeof(text));
}

void ApplyDarkTheme(HWND control) {
    using SetWindowThemeFn = HRESULT(WINAPI*)(HWND, LPCWSTR, LPCWSTR);
    static HMODULE uxtheme = LoadLibraryW(L"uxtheme.dll");
    static auto set_theme =
        uxtheme ? reinterpret_cast<SetWindowThemeFn>(
                      GetProcAddress(uxtheme, "SetWindowTheme"))
                : nullptr;
    if (set_theme) {
        set_theme(control, L"DarkMode_Explorer", nullptr);
    }
}

bool IsHovered(HWND control, UINT draw_state) {
    return (draw_state & ODS_HOTLIGHT) != 0 ||
           GetPropW(control, kHoverProperty) != nullptr;
}

LRESULT CALLBACK HoverTrackingProc(HWND control, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR subclass_id,
                                   DWORD_PTR) {
    if (message == WM_MOUSEMOVE && !GetPropW(control, kHoverProperty)) {
        SetPropW(control, kHoverProperty, reinterpret_cast<HANDLE>(1));
        TRACKMOUSEEVENT tracking{};
        tracking.cbSize = sizeof(tracking);
        tracking.dwFlags = TME_LEAVE;
        tracking.hwndTrack = control;
        TrackMouseEvent(&tracking);
        InvalidateRect(control, nullptr, FALSE);
    } else if (message == WM_MOUSELEAVE) {
        RemovePropW(control, kHoverProperty);
        InvalidateRect(control, nullptr, FALSE);
    } else if (message == WM_NCDESTROY) {
        RemovePropW(control, kHoverProperty);
        RemoveWindowSubclass(control, HoverTrackingProc, subclass_id);
    }
    return DefSubclassProc(control, message, wparam, lparam);
}

void EnableHoverTracking(HWND control) {
    SetWindowSubclass(control, HoverTrackingProc, kHoverTrackingSubclass, 0);
}

void ClearWindowTheme(HWND control) {
    using SetWindowThemeFn = HRESULT(WINAPI*)(HWND, LPCWSTR, LPCWSTR);
    static HMODULE uxtheme = LoadLibraryW(L"uxtheme.dll");
    static auto set_theme =
        uxtheme ? reinterpret_cast<SetWindowThemeFn>(
                      GetProcAddress(uxtheme, "SetWindowTheme"))
                : nullptr;
    if (set_theme) {
        set_theme(control, L"", L"");
    }
}

bool ReadDpiOverride(const std::filesystem::path& executable) {
    if (executable.empty()) {
        return false;
    }
    std::error_code path_error;
    auto absolute = std::filesystem::absolute(executable, path_error);
    if (path_error) absolute = executable;

    constexpr wchar_t kLayersKey[] =
        L"Software\\Microsoft\\Windows NT\\CurrentVersion\\AppCompatFlags\\Layers";
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kLayersKey, 0, KEY_QUERY_VALUE, &key) !=
        ERROR_SUCCESS) {
        return false;
    }

    DWORD type = 0;
    DWORD size = 0;
    LSTATUS status =
        RegQueryValueExW(key, absolute.c_str(), nullptr, &type, nullptr, &size);
    if (status != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ) ||
        size < sizeof(wchar_t)) {
        RegCloseKey(key);
        return false;
    }

    std::wstring value(size / sizeof(wchar_t), L'\0');
    status = RegQueryValueExW(
        key, absolute.c_str(), nullptr, &type,
        reinterpret_cast<BYTE*>(value.data()), &size);
    RegCloseKey(key);
    if (status != ERROR_SUCCESS) {
        return false;
    }
    value.resize(size / sizeof(wchar_t));
    while (!value.empty() && value.back() == L'\0') {
        value.pop_back();
    }
    const std::wstring normalized = ToLower(value);
    return normalized.find(L"highdpiaware") != std::wstring::npos ||
           normalized.find(L"dpiunaware") != std::wstring::npos;
}

void RefreshDpiSettings() {
    SystemParametersInfoW(0x009F, 0, nullptr, 0);
}

std::wstring ApplyDpiOverride(const std::filesystem::path& executable,
                              bool enabled) {
    if (executable.empty()) {
        return L"DPI executable path is empty";
    }
    std::error_code path_error;
    auto absolute = std::filesystem::absolute(executable, path_error);
    if (path_error) absolute = executable;

    constexpr wchar_t kLayersKey[] =
        L"Software\\Microsoft\\Windows NT\\CurrentVersion\\AppCompatFlags\\Layers";
    HKEY key = nullptr;
    LSTATUS layer_status = RegCreateKeyExW(
        HKEY_CURRENT_USER, kLayersKey, 0, nullptr, 0,
        KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &key, nullptr);
    if (layer_status != ERROR_SUCCESS) return FormatLastError(layer_status);

    std::wstring current_flags;
    bool layer_value_exists = false;
    DWORD value_type = REG_SZ;
    DWORD value_size = 0;
    layer_status = RegQueryValueExW(
        key, absolute.c_str(), nullptr, &value_type, nullptr, &value_size);
    if (layer_status == ERROR_SUCCESS && value_size >= sizeof(wchar_t)) {
        layer_value_exists = true;
        std::wstring value(value_size / sizeof(wchar_t), L'\0');
        layer_status = RegQueryValueExW(
            key, absolute.c_str(), nullptr, &value_type,
            reinterpret_cast<BYTE*>(value.data()), &value_size);
        if (layer_status != ERROR_SUCCESS) {
            RegCloseKey(key);
            return FormatLastError(layer_status);
        }
        value.resize(value_size / sizeof(wchar_t));
        while (!value.empty() && value.back() == L'\0') value.pop_back();
        current_flags = std::move(value);
    } else if (layer_status != ERROR_FILE_NOT_FOUND) {
        RegCloseKey(key);
        return FormatLastError(layer_status);
    }
    const std::wstring previous_flags = current_flags;

    std::wistringstream token_stream(current_flags);
    std::vector<std::wstring> preserved;
    std::wstring token;
    while (token_stream >> token) {
        const std::wstring normalized = ToLower(token);
        if (normalized == L"highdpiaware" || normalized == L"dpiunaware" ||
            token == L"~") {
            continue;
        }
        preserved.push_back(token);
    }
    std::wstring updated_flags;
    if (enabled || !preserved.empty()) updated_flags = L"~";
    for (const auto& flag : preserved) {
        updated_flags += L" " + flag;
    }
    if (enabled) updated_flags += L" DPIUNAWARE";

    if (updated_flags.empty() || updated_flags == L"~") {
        const LSTATUS removed = RegDeleteValueW(key, absolute.c_str());
        if (removed != ERROR_SUCCESS && removed != ERROR_FILE_NOT_FOUND) {
            RegCloseKey(key);
            return FormatLastError(removed);
        }
    } else {
        const LSTATUS set = RegSetValueExW(
            key, absolute.c_str(), 0, REG_SZ,
            reinterpret_cast<const BYTE*>(updated_flags.c_str()),
            static_cast<DWORD>((updated_flags.size() + 1) * sizeof(wchar_t)));
        if (set != ERROR_SUCCESS) {
            RegCloseKey(key);
            return FormatLastError(set);
        }
    }
    RegCloseKey(key);
    auto restore_layer = [&] {
        HKEY restore_key = nullptr;
        if (RegCreateKeyExW(
                HKEY_CURRENT_USER, kLayersKey, 0, nullptr, 0,
                KEY_SET_VALUE, nullptr, &restore_key, nullptr) != ERROR_SUCCESS) {
            return;
        }
        if (layer_value_exists) {
            RegSetValueExW(
                restore_key, absolute.c_str(), 0, REG_SZ,
                reinterpret_cast<const BYTE*>(previous_flags.c_str()),
                static_cast<DWORD>(
                    (previous_flags.size() + 1) * sizeof(wchar_t)));
        } else {
            RegDeleteValueW(restore_key, absolute.c_str());
        }
        RegCloseKey(restore_key);
    };

    const std::wstring ifeo_key =
        L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution "
        L"Options\\" +
        absolute.filename().wstring();
    if (enabled) {
        const LSTATUS create = RegCreateKeyExW(
            HKEY_LOCAL_MACHINE, ifeo_key.c_str(), 0, nullptr, 0, KEY_SET_VALUE,
            nullptr, &key, nullptr);
        if (create != ERROR_SUCCESS) {
            restore_layer();
            return FormatLastError(create);
        }
        const DWORD value = 0;
        const LSTATUS set =
            RegSetValueExW(key, L"dpiAwareness", 0, REG_DWORD,
                           reinterpret_cast<const BYTE*>(&value), sizeof(value));
        RegCloseKey(key);
        if (set != ERROR_SUCCESS) {
            restore_layer();
            return FormatLastError(set);
        }
    } else {
        const LSTATUS open = RegOpenKeyExW(
            HKEY_LOCAL_MACHINE, ifeo_key.c_str(), 0, KEY_SET_VALUE, &key);
        if (open == ERROR_SUCCESS) {
            const LSTATUS removed = RegDeleteValueW(key, L"dpiAwareness");
            RegCloseKey(key);
            if (removed != ERROR_SUCCESS && removed != ERROR_FILE_NOT_FOUND) {
                restore_layer();
                return FormatLastError(removed);
            }
        } else if (open != ERROR_FILE_NOT_FOUND) {
            restore_layer();
            return FormatLastError(open);
        }
    }
    RefreshDpiSettings();
    return {};
}

struct ProfileDialogState {
    const Translation* translation = nullptr;
    Json config;
    std::string config_name;
    std::string display_name;
    std::string custom_icon;
    std::filesystem::path background_path;
    ProfileEditResult result;
    HWND dialog = nullptr;
    HWND title = nullptr;
    HWND display_label = nullptr;
    HWND icon_label = nullptr;
    HWND launch_label = nullptr;
    HWND target_label = nullptr;
    HWND arguments_label = nullptr;
    HWND prelaunch_label = nullptr;
    HWND prelaunch_wait_label = nullptr;
    HWND injection_label = nullptr;
    HWND seconds_label = nullptr;
    HWND display = nullptr;
    HWND icon_preview = nullptr;
    HWND icon = nullptr;
    HWND browse_icon = nullptr;
    HWND reset_icon = nullptr;
    HWND launch = nullptr;
    HWND browse_launch = nullptr;
    HWND target = nullptr;
    HWND browse_target = nullptr;
    HWND arguments = nullptr;
    HWND prelaunch = nullptr;
    HWND prelaunch_wait = nullptr;
    HWND dll_label = nullptr;
    HWND dlls = nullptr;
    HWND browse_dlls = nullptr;
    HWND remove_dll = nullptr;
    HWND move_dll_up = nullptr;
    HWND move_dll_down = nullptr;
    HWND injection = nullptr;
    HWND reshade = nullptr;
    HWND center = nullptr;
    HWND center_duration = nullptr;
    HWND dpi = nullptr;
    HWND dpi_hint = nullptr;
    HWND hint = nullptr;
    HWND delete_button = nullptr;
    HWND cancel_button = nullptr;
    HWND save_button = nullptr;
    UINT dpi_value = 96;
    int scroll_position = 0;
    HFONT title_font = nullptr;
    HFONT section_font = nullptr;
    HFONT body_font = nullptr;
    HFONT small_font = nullptr;
    HICON preview_icon = nullptr;
    HBRUSH background_brush = nullptr;
    HBRUSH panel_brush = nullptr;
    HBRUSH input_brush = nullptr;
    BackgroundImage background;
    RECT dlls_frame{};
    RECT panels[4]{};
    std::vector<RECT> input_frames;
    std::vector<HWND> section_labels;
    std::vector<HWND> body_controls;
    std::vector<HWND> small_controls;
};

void DestroyStateResources(ProfileDialogState& state) {
    if (state.background_brush) DeleteObject(state.background_brush);
    if (state.panel_brush) DeleteObject(state.panel_brush);
    if (state.input_brush) DeleteObject(state.input_brush);
    if (state.title_font) DeleteObject(state.title_font);
    if (state.section_font) DeleteObject(state.section_font);
    if (state.body_font) DeleteObject(state.body_font);
    if (state.small_font) DeleteObject(state.small_font);
    if (state.preview_icon) DestroyIcon(state.preview_icon);
    state.background.Clear();
    state.background_brush = nullptr;
    state.panel_brush = nullptr;
    state.input_brush = nullptr;
    state.title_font = nullptr;
    state.section_font = nullptr;
    state.body_font = nullptr;
    state.small_font = nullptr;
    state.preview_icon = nullptr;
}

void CreateStateResources(ProfileDialogState& state) {
    state.dpi_value = GetDpiForWindow(state.dialog);
    if (!state.dpi_value) state.dpi_value = GetDpiForSystem();
    state.background_brush = CreateSolidBrush(ColorBackground());
    state.panel_brush = CreateSolidBrush(ColorPanel());
    state.input_brush = CreateSolidBrush(ColorInput());
    state.title_font = CreateUiFont(state.dpi_value, 17, FW_SEMIBOLD);
    state.section_font = CreateUiFont(state.dpi_value, 10, FW_SEMIBOLD);
    state.body_font = CreateUiFont(state.dpi_value, 10, FW_NORMAL);
    state.small_font = CreateUiFont(state.dpi_value, 9, FW_NORMAL);
    LoadBackgroundImage(state.background_path, &state.background);
}

void ApplyFonts(ProfileDialogState& state) {
    SetFont(state.title, state.title_font);
    for (HWND label : state.section_labels) SetFont(label, state.section_font);
    for (HWND control : state.body_controls) SetFont(control, state.body_font);
    for (HWND control : state.small_controls) SetFont(control, state.small_font);
}

void MoveControl(HWND control, UINT dpi, int x, int y, int width, int height) {
    SetWindowPos(control, nullptr, Dip(dpi, x), Dip(dpi, y), Dip(dpi, width),
                 Dip(dpi, height), SWP_NOZORDER | SWP_NOACTIVATE);
}

void LayoutControls(ProfileDialogState& state) {
    const UINT dpi = state.dpi_value;
    RECT client{};
    GetClientRect(state.dialog, &client);
    const int client_width =
        MulDiv(static_cast<int>(client.right), 96, static_cast<int>(dpi));
    const int panel_left = 20;
    const int panel_right = std::min(client_width - 20, 740);
    const int panel_width = std::max(520, panel_right - panel_left);
    const int inner_left = panel_left + 14;
    const int inner_right = panel_left + panel_width - 14;
    const int field_left = inner_left + 130;
    const int label_width = 122;
    const int browse_width = 78;
    const int gap = 10;
    const int browse_left = inner_right - browse_width;
    const int field_right = browse_left - gap;

    state.panels[0] = {panel_left, 52, panel_left + panel_width, 168};
    state.panels[1] = {panel_left, 178, panel_left + panel_width, 372};
    state.panels[2] = {panel_left, 382, panel_left + panel_width, 638};
    state.panels[3] = {panel_left, 648, panel_left + panel_width, 792};

    state.input_frames.clear();
    auto move_input = [&](HWND control, int x, int y, int width, int height) {
        state.input_frames.push_back({x, y, x + width, y + height});
        MoveControl(control, dpi, x + 7, y + 5, width - 14, height - 10);
    };

    MoveControl(state.title, dpi, inner_left, 12, panel_width - 28, 34);
    MoveControl(state.section_labels[0], dpi, inner_left, 58, 280, 24);
    MoveControl(state.section_labels[1], dpi, inner_left, 184, 280, 24);
    MoveControl(state.section_labels[2], dpi, inner_left, 388, 380, 24);
    MoveControl(state.section_labels[3], dpi, inner_left, 654, 280, 24);

    MoveControl(state.display_label, dpi, inner_left, 88, label_width, 30);
    move_input(state.display, field_left, 86, field_right - field_left, 34);
    MoveControl(state.icon_label, dpi, inner_left, 126, label_width, 30);
    MoveControl(state.icon_preview, dpi, field_left, 124, 34, 34);
    const int icon_actions_left = inner_right - 166;
    const int icon_edit_left = field_left + 44;
    const int icon_edit_right = icon_actions_left - gap;
    state.input_frames.push_back(
        {icon_edit_left, 124, icon_edit_right, 158});
    MoveControl(state.icon, dpi, icon_edit_left + 7, 129,
                icon_edit_right - icon_edit_left - 14, 24);
    MoveControl(state.browse_icon, dpi, icon_actions_left, 124, browse_width, 34);
    MoveControl(state.reset_icon, dpi, icon_actions_left + browse_width + gap, 124,
                browse_width, 34);

    MoveControl(state.launch_label, dpi, inner_left, 214, label_width, 30);
    move_input(state.launch, field_left, 212, field_right - field_left, 34);
    MoveControl(state.browse_launch, dpi, browse_left, 212, browse_width, 34);
    MoveControl(state.target_label, dpi, inner_left, 250, label_width, 30);
    move_input(state.target, field_left, 248, field_right - field_left, 34);
    MoveControl(state.browse_target, dpi, browse_left, 248, browse_width, 34);
    MoveControl(state.arguments_label, dpi, inner_left, 286, label_width, 30);
    move_input(state.arguments, field_left, 284, field_right - field_left, 34);
    MoveControl(state.injection_label, dpi, inner_left, 322, label_width, 30);
    MoveControl(state.injection, dpi, field_left, 320, 168, 34);
    MoveControl(state.reshade, dpi, field_left + 188, 322,
                inner_right - (field_left + 188), 30);

    MoveControl(state.prelaunch_label, dpi, inner_left, 420, label_width, 30);
    move_input(state.prelaunch, field_left, 418, field_right - field_left, 34);
    MoveControl(state.prelaunch_wait_label, dpi, inner_left, 456, label_width, 30);
    move_input(state.prelaunch_wait, field_left, 454, 96, 34);

    MoveControl(state.dll_label, dpi, inner_left, 498, 120, 30);
    const int dlls_width = std::max(40, field_right - field_left);
    state.dlls_frame = {field_left, 494, field_left + dlls_width, 620};
    MoveControl(state.dlls, dpi, field_left + 7, 501, dlls_width - 14, 112);
    MoveControl(state.browse_dlls, dpi, browse_left, 494, browse_width, 34);
    MoveControl(state.remove_dll, dpi, browse_left, 534, browse_width, 34);
    MoveControl(state.move_dll_up, dpi, browse_left, 574, 34, 34);
    MoveControl(state.move_dll_down, dpi, browse_left + 44, 574, 34, 34);

    MoveControl(state.center, dpi, inner_left, 686, 360, 30);
    MoveControl(state.seconds_label, dpi, 402, 686, 38, 30);
    move_input(state.center_duration, 446, 684, 80, 34);
    MoveControl(state.dpi, dpi, inner_left, 718, inner_right - inner_left, 30);
    MoveControl(state.dpi_hint, dpi, inner_left, 748, inner_right - inner_left, 20);
    MoveControl(state.hint, dpi, inner_left, 770, inner_right - inner_left, 18);

    MoveControl(state.delete_button, dpi, panel_left, 810, 100, 36);
    MoveControl(state.cancel_button, dpi, panel_left + panel_width - 222, 810,
                102, 36);
    MoveControl(state.save_button, dpi, panel_left + panel_width - 110, 810, 110,
                36);
}

void UpdateScrollBar(ProfileDialogState& state) {
    RECT client{};
    GetClientRect(state.dialog, &client);
    const int content_height = Dip(state.dpi_value, kContentHeight);
    const int page = std::max(1, static_cast<int>(client.bottom));
    const int maximum = std::max(0, content_height - page);
    state.scroll_position = std::clamp(state.scroll_position, 0, maximum);
    SCROLLINFO info{};
    info.cbSize = sizeof(info);
    info.fMask = SIF_RANGE | SIF_PAGE | SIF_POS;
    info.nMin = 0;
    info.nMax = std::max(0, content_height - 1);
    info.nPage = static_cast<UINT>(page);
    info.nPos = state.scroll_position;
    SetScrollInfo(state.dialog, SB_VERT, &info, TRUE);
    ShowScrollBar(state.dialog, SB_VERT, maximum > 0);
}

void ScrollTo(ProfileDialogState& state, int position) {
    RECT client{};
    GetClientRect(state.dialog, &client);
    const int maximum = std::max(
        0, Dip(state.dpi_value, kContentHeight) - static_cast<int>(client.bottom));
    const int new_position = std::clamp(position, 0, maximum);
    const int delta = new_position - state.scroll_position;
    if (!delta) return;
    state.scroll_position = new_position;
    ScrollWindowEx(state.dialog, 0, -delta, nullptr, nullptr, nullptr, nullptr,
                   SW_INVALIDATE | SW_ERASE | SW_SCROLLCHILDREN);
    SCROLLINFO info{};
    info.cbSize = sizeof(info);
    info.fMask = SIF_POS;
    info.nPos = state.scroll_position;
    SetScrollInfo(state.dialog, SB_VERT, &info, TRUE);
    InvalidateRect(state.dialog, nullptr, FALSE);
}

void HandleScroll(ProfileDialogState& state, WPARAM wparam) {
    const int line = Dip(state.dpi_value, 36);
    switch (LOWORD(wparam)) {
        case SB_LINEUP:
            ScrollTo(state, state.scroll_position - line);
            break;
        case SB_LINEDOWN:
            ScrollTo(state, state.scroll_position + line);
            break;
        case SB_PAGEUP:
            ScrollTo(state, state.scroll_position - Dip(state.dpi_value, 240));
            break;
        case SB_PAGEDOWN:
            ScrollTo(state, state.scroll_position + Dip(state.dpi_value, 240));
            break;
        case SB_TOP:
            ScrollTo(state, 0);
            break;
        case SB_BOTTOM:
            ScrollTo(state, Dip(state.dpi_value, kContentHeight));
            break;
        case SB_THUMBTRACK:
        case SB_THUMBPOSITION:
            ScrollTo(state, HIWORD(wparam));
            break;
        default:
            break;
    }
}

void SizeAndCenterDialog(ProfileDialogState& state) {
    const UINT dpi = state.dpi_value;
    const int scroll_width = GetSystemMetricsForDpi(SM_CXVSCROLL, dpi);
    const int desired_width = Dip(dpi, kDialogWidth) + scroll_width;
    const int desired_height = Dip(dpi, kContentHeight);
    CenterOverlayWindow(state.dialog, GetWindow(state.dialog, GW_OWNER),
                        desired_width, desired_height);
}

void DrawPanel(HDC dc, const ProfileDialogState& state, RECT rect) {
    DrawRoundedSurface(dc, rect, ColorPanel(), ColorBorder(), state.dpi_value, 7);
}

void PaintDialog(ProfileDialogState& state) {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(state.dialog, &paint);
    RECT client{};
    GetClientRect(state.dialog, &client);
    FillRect(dc, &client, state.background_brush);
    DrawBackgroundCover(dc, client, state.background);
    LONG panel_right = state.panels[0].right;
    for (const RECT& panel : state.panels) {
        panel_right = std::max(panel_right, panel.right);
    }
    for (RECT rect : state.panels) {
        rect.right = panel_right;
        RECT physical{
            Dip(state.dpi_value, rect.left), Dip(state.dpi_value, rect.top),
            Dip(state.dpi_value, rect.right), Dip(state.dpi_value, rect.bottom)};
        OffsetRect(&physical, 0, -state.scroll_position);
        DrawPanel(dc, state, physical);
    }

    for (RECT frame : state.input_frames) {
        RECT physical{
            Dip(state.dpi_value, frame.left), Dip(state.dpi_value, frame.top),
            Dip(state.dpi_value, frame.right), Dip(state.dpi_value, frame.bottom)};
        OffsetRect(&physical, 0, -state.scroll_position);
        DrawRoundedSurface(dc, physical, ColorInput(), ColorBorder(),
                           state.dpi_value, 6);
    }

    RECT dlls_frame{
        Dip(state.dpi_value, state.dlls_frame.left),
        Dip(state.dpi_value, state.dlls_frame.top),
        Dip(state.dpi_value, state.dlls_frame.right),
        Dip(state.dpi_value, state.dlls_frame.bottom)};
    OffsetRect(&dlls_frame, 0, -state.scroll_position);
    DrawRoundedSurface(dc, dlls_frame, ColorInput(), ColorBorder(),
                       state.dpi_value, 6);

    const int section_y[] = {58, 184, 388, 654};
    for (int y : section_y) {
        RECT accent{
            Dip(state.dpi_value, 25), Dip(state.dpi_value, y + 5),
            Dip(state.dpi_value, 29), Dip(state.dpi_value, y + 19)};
        OffsetRect(&accent, 0, -state.scroll_position);
        DrawRoundedSurface(dc, accent, ColorAccent(), ColorAccent(),
                           state.dpi_value, 2, false);
    }

    RECT separator{
        Dip(state.dpi_value, 20), Dip(state.dpi_value, 800),
        client.right - Dip(state.dpi_value, 20),
        Dip(state.dpi_value, 801)};
    OffsetRect(&separator, 0, -state.scroll_position);
    HBRUSH separator_brush = CreateSolidBrush(ColorBorder());
    FillRect(dc, &separator, separator_brush);
    DeleteObject(separator_brush);
    EndPaint(state.dialog, &paint);
}

COLORREF Blend(COLORREF color, int amount) {
    auto channel = [amount](BYTE value) {
        return static_cast<BYTE>(
            std::clamp(static_cast<int>(value) + amount, 0, 255));
    };
    return RGB(channel(GetRValue(color)), channel(GetGValue(color)),
               channel(GetBValue(color)));
}

void DrawOwnerButton(const DRAWITEMSTRUCT& item, const ProfileDialogState& state) {
    const bool disabled = (item.itemState & ODS_DISABLED) != 0;
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;
    const bool hot = IsHovered(item.hwndItem, item.itemState);
    const bool save = item.CtlID == IDOK;
    const bool remove = item.CtlID == kDelete;
    const bool footer_action =
        item.CtlID == IDOK || item.CtlID == IDCANCEL || item.CtlID == kDelete;
    COLORREF fill = save ? ColorAccent() : ColorControl();
    COLORREF text = save ? RGB(8, 22, 12) : ColorText();
    if (remove) {
        fill = RGB(67, 24, 35);
    } else if (!save && hot) {
        fill = ColorPanelHover();
    } else if (save && hot) {
        fill = Blend(ColorAccent(), 32);
    }
    if (disabled) {
        fill = RGB(35, 40, 52);
        text = RGB(132, 139, 155);
    } else {
        if (remove && hot) fill = RGB(115, 40, 58);
        if (pressed) fill = Blend(fill, -20);
    }

    if (footer_action) {
        RECT parent_client{};
        RECT control_in_parent{};
        HWND parent = GetParent(item.hwndItem);
        GetClientRect(parent, &parent_client);
        GetWindowRect(item.hwndItem, &control_in_parent);
        MapWindowPoints(HWND_DESKTOP, parent,
                        reinterpret_cast<POINT*>(&control_in_parent), 2);
        FillBackgroundSegment(item.hDC, item.rcItem, control_in_parent,
                              parent_client, state.background);
    } else {
        FillRect(item.hDC, &item.rcItem, state.panel_brush);
    }
    DrawRoundedSurface(item.hDC, item.rcItem, fill, fill, state.dpi_value, 5,
                       false);

    const std::wstring label = GetControlText(item.hwndItem);
    SetBkMode(item.hDC, TRANSPARENT);
    SetTextColor(item.hDC, text);
    const HGDIOBJ old_font =
        SelectObject(item.hDC, save ? state.section_font : state.body_font);
    RECT text_rect = item.rcItem;
    InflateRect(&text_rect, -Dip(state.dpi_value, 10), 0);
    DrawTextW(item.hDC, label.c_str(), static_cast<int>(label.size()), &text_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                  DT_NOPREFIX);
    SelectObject(item.hDC, old_font);
    if ((item.itemState & ODS_FOCUS) && !disabled) {
        RECT focus = item.rcItem;
        InflateRect(&focus, -Dip(state.dpi_value, 2), -Dip(state.dpi_value, 2));
        DrawRoundedOutline(item.hDC, focus, ColorAccent(), state.dpi_value, 4);
    }
}

void DrawOwnerCombo(const DRAWITEMSTRUCT& item, const ProfileDialogState& state) {
    const bool selected = (item.itemState & ODS_SELECTED) != 0;
    const bool closed_control = item.itemID == static_cast<UINT>(-1);
    HBRUSH selected_brush = !closed_control && selected
                                ? CreateSolidBrush(ColorPanelHover())
                                : nullptr;
    HBRUSH background =
        selected_brush ? selected_brush : state.input_brush;
    FillRect(item.hDC, &item.rcItem, background);
    if (selected_brush) DeleteObject(selected_brush);
    SetBkMode(item.hDC, TRANSPARENT);
    SetTextColor(item.hDC, ColorText());
    const HGDIOBJ old_font = SelectObject(item.hDC, state.body_font);
    std::wstring text;
    if (closed_control) {
        wchar_t value[512]{};
        GetWindowTextW(item.hwndItem, value,
                       static_cast<int>(std::size(value)));
        text = value;
    } else {
        const LRESULT length =
            SendMessageW(item.hwndItem, CB_GETLBTEXTLEN, item.itemID, 0);
        if (length != CB_ERR && length >= 0) {
            text.resize(static_cast<size_t>(length) + 1, L'\0');
            SendMessageW(item.hwndItem, CB_GETLBTEXT, item.itemID,
                         reinterpret_cast<LPARAM>(text.data()));
            text.resize(static_cast<size_t>(length));
        }
    }
    RECT text_rect = item.rcItem;
    InflateRect(&text_rect, -Dip(state.dpi_value, 10), 0);
    if (closed_control) {
        text_rect.right -= Dip(state.dpi_value, 24);
    }
    DrawTextW(item.hDC, text.c_str(), -1, &text_rect,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
                  DT_END_ELLIPSIS);
    SelectObject(item.hDC, old_font);

    if (!closed_control) return;
    POINT arrow[3] = {
        {item.rcItem.right - Dip(state.dpi_value, 20),
         item.rcItem.top + (item.rcItem.bottom - item.rcItem.top) / 2 - 2},
        {item.rcItem.right - Dip(state.dpi_value, 10),
         item.rcItem.top + (item.rcItem.bottom - item.rcItem.top) / 2 - 2},
        {item.rcItem.right - Dip(state.dpi_value, 15),
         item.rcItem.top + (item.rcItem.bottom - item.rcItem.top) / 2 + 4}};
    HBRUSH arrow_brush = CreateSolidBrush(ColorMuted());
    HGDIOBJ old_brush = SelectObject(item.hDC, arrow_brush);
    HGDIOBJ old_pen = SelectObject(item.hDC, GetStockObject(NULL_PEN));
    Polygon(item.hDC, arrow, 3);
    SelectObject(item.hDC, old_pen);
    SelectObject(item.hDC, old_brush);
    DeleteObject(arrow_brush);
}

void DrawProfileCombo(HWND control, HDC dc,
                      const ProfileDialogState& state) {
    RECT client{};
    GetClientRect(control, &client);
    FillRect(dc, &client, state.panel_brush);
    const bool hot = GetPropW(control, kHoverProperty) != nullptr;
    DrawRoundedSurface(dc, client, hot ? ColorPanelHover() : ColorInput(),
                       hot ? ColorPanelHover() : ColorBorder(), state.dpi_value,
                       6);

    const LRESULT selected = SendMessageW(control, CB_GETCURSEL, 0, 0);
    std::wstring text;
    if (selected != CB_ERR) {
        const LRESULT length = SendMessageW(control, CB_GETLBTEXTLEN, selected, 0);
        if (length != CB_ERR && length >= 0) {
            text.resize(static_cast<size_t>(length) + 1, L'\0');
            SendMessageW(control, CB_GETLBTEXT, selected,
                         reinterpret_cast<LPARAM>(text.data()));
            text.resize(static_cast<size_t>(length));
        }
    }

    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, ColorText());
    const HGDIOBJ old_font = SelectObject(dc, state.body_font);
    RECT text_rect = client;
    text_rect.left += Dip(state.dpi_value, 12);
    text_rect.right -= Dip(state.dpi_value, 38);
    DrawTextW(dc, text.c_str(), -1, &text_rect,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
                  DT_END_ELLIPSIS);
    SelectObject(dc, old_font);

    const int center_y = (client.top + client.bottom) / 2;
    POINT arrow[3] = {
        {client.right - Dip(state.dpi_value, 23), center_y - 2},
        {client.right - Dip(state.dpi_value, 12), center_y - 2},
        {client.right - Dip(state.dpi_value, 18), center_y + 4}};
    HBRUSH arrow_brush = CreateSolidBrush(ColorMuted());
    const HGDIOBJ old_brush = SelectObject(dc, arrow_brush);
    const HGDIOBJ old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
    Polygon(dc, arrow, 3);
    SelectObject(dc, old_pen);
    SelectObject(dc, old_brush);
    DeleteObject(arrow_brush);

    if (GetFocus() == control) {
        RECT focus = client;
        InflateRect(&focus, -Dip(state.dpi_value, 2),
                    -Dip(state.dpi_value, 2));
        DrawRoundedOutline(dc, focus, ColorAccent(), state.dpi_value, 5);
    }
}

LRESULT CALLBACK ProfileComboProc(HWND control, UINT message, WPARAM wparam,
                                  LPARAM lparam, UINT_PTR subclass_id,
                                  DWORD_PTR reference_data) {
    auto* state = reinterpret_cast<ProfileDialogState*>(reference_data);
    if (!state) return DefSubclassProc(control, message, wparam, lparam);
    switch (message) {
        case WM_PAINT: {
            PAINTSTRUCT paint{};
            HDC dc = BeginPaint(control, &paint);
            DrawProfileCombo(control, dc, *state);
            EndPaint(control, &paint);
            return 0;
        }
        case WM_PRINTCLIENT:
            DrawProfileCombo(control, reinterpret_cast<HDC>(wparam), *state);
            return 0;
        case WM_ERASEBKGND:
        case WM_NCPAINT:
            return 0;
        case WM_SETFOCUS:
        case WM_KILLFOCUS:
        case WM_THEMECHANGED:
            InvalidateRect(control, nullptr, FALSE);
            break;
        case WM_NCDESTROY:
            RemoveWindowSubclass(control, ProfileComboProc, subclass_id);
            break;
        default:
            break;
    }
    return DefSubclassProc(control, message, wparam, lparam);
}

HWND CreateLabel(HWND dialog, const std::wstring& text) {
    HWND label =
        CreateChild(dialog, L"STATIC", text.c_str(),
                    SS_LEFT | SS_NOPREFIX | SS_ENDELLIPSIS | WS_CLIPSIBLINGS, 0,
                    WS_EX_TRANSPARENT);
    ApplyDarkTheme(label);
    return label;
}

HWND CreateEdit(HWND dialog, DWORD style, int id = 0) {
    HWND edit = CreateChild(dialog, L"EDIT", L"",
                            WS_TABSTOP | WS_CLIPSIBLINGS | style, id);
    SetEditMargins(edit);
    ApplyDarkTheme(edit);
    return edit;
}

HWND CreateButton(HWND dialog, const std::wstring& text, int id) {
    HWND button =
        CreateChild(dialog, L"BUTTON", text.c_str(), BS_OWNERDRAW | WS_TABSTOP, id);
    ApplyDarkTheme(button);
    EnableHoverTracking(button);
    return button;
}

HICON LoadPreviewIcon(const std::filesystem::path& path, UINT size) {
    if (path.empty() || !FileExists(path)) return nullptr;
    const std::wstring extension = ToLower(path.extension().wstring());
    if (extension == L".ico") {
        return static_cast<HICON>(LoadImageW(
            nullptr, path.c_str(), IMAGE_ICON, static_cast<int>(size),
            static_cast<int>(size), LR_LOADFROMFILE));
    }
    if (extension == L".exe" || extension == L".dll") {
        HICON large_icon = nullptr;
        HICON small_icon = nullptr;
        if (ExtractIconExW(path.c_str(), 0, &large_icon, &small_icon, 1) > 0) {
            if (large_icon) {
                if (small_icon) DestroyIcon(small_icon);
                return large_icon;
            }
            return small_icon;
        }
    }
    SHFILEINFOW file_info{};
    if (SHGetFileInfoW(path.c_str(), 0, &file_info, sizeof(file_info),
                       SHGFI_ICON | SHGFI_LARGEICON)) {
        return file_info.hIcon;
    }
    return nullptr;
}

void UpdateIconPreview(ProfileDialogState& state) {
    if (!state.icon_preview) return;
    if (state.preview_icon) DestroyIcon(state.preview_icon);
    state.preview_icon = nullptr;

    std::filesystem::path path = GetControlText(state.icon);
    if (!FileExists(path)) {
        path = GetControlText(state.target);
    }
    state.preview_icon = LoadPreviewIcon(path, 32);
    InvalidateRect(state.icon_preview, nullptr, TRUE);
}

bool IsReshadeDllValue(std::wstring_view value) {
    const std::filesystem::path path(value);
    return _wcsicmp(path.filename().c_str(), L"ReShade64.dll") == 0;
}

LRESULT FindReshadeDllEntry(HWND list) {
    const LRESULT count = SendMessageW(list, LB_GETCOUNT, 0, 0);
    for (LRESULT index = 0; count != LB_ERR && index < count; ++index) {
        const LRESULT length = SendMessageW(list, LB_GETTEXTLEN, index, 0);
        if (length == LB_ERR || length < 0) continue;
        std::wstring value(static_cast<size_t>(length) + 1, L'\0');
        SendMessageW(list, LB_GETTEXT, index,
                     reinterpret_cast<LPARAM>(value.data()));
        value.resize(static_cast<size_t>(length));
        if (IsReshadeDllValue(value)) return index;
    }
    return LB_ERR;
}

void SetReshadeListEntry(HWND list, bool enabled) {
    const LRESULT existing = FindReshadeDllEntry(list);
    if (enabled) {
        if (existing == LB_ERR) {
            SendMessageW(list, LB_INSERTSTRING, 0,
                         reinterpret_cast<LPARAM>(L"ReShade64.dll"));
        }
    } else if (existing != LB_ERR) {
        SendMessageW(list, LB_DELETESTRING, existing, 0);
    }
}

void DrawProfileCheckbox(HWND control, HDC dc,
                         const ProfileDialogState& state) {
    RECT client{};
    GetClientRect(control, &client);
    FillRect(dc, &client, state.panel_brush);

    const bool checked =
        SendMessageW(control, BM_GETCHECK, 0, 0) == BST_CHECKED;
    const bool enabled = IsWindowEnabled(control) != FALSE;
    const int box_size = Dip(state.dpi_value, 16);
    RECT box{0, (client.bottom - box_size) / 2, box_size,
             (client.bottom + box_size) / 2};

    const COLORREF fill =
        !enabled ? RGB(35, 40, 52)
                 : (checked ? ColorAccent() : ColorInput());
    const COLORREF border =
        !enabled ? RGB(62, 68, 82)
                 : (checked ? ColorAccent() : ColorBorder());
    DrawRoundedSurface(dc, box, fill, border, state.dpi_value, 3);

    if (checked) {
        HPEN check_pen = CreatePen(
            PS_SOLID, std::max(1, Dip(state.dpi_value, 2)),
            enabled ? RGB(8, 22, 12) : RGB(92, 99, 112));
        const HGDIOBJ old_check_pen = SelectObject(dc, check_pen);
        const int left = box.left + Dip(state.dpi_value, 4);
        const int top = box.top + Dip(state.dpi_value, 8);
        MoveToEx(dc, left, top, nullptr);
        LineTo(dc, left + Dip(state.dpi_value, 3),
               top + Dip(state.dpi_value, 3));
        LineTo(dc, left + Dip(state.dpi_value, 9),
               top - Dip(state.dpi_value, 5));
        SelectObject(dc, old_check_pen);
        DeleteObject(check_pen);
    }

    wchar_t text[1024]{};
    GetWindowTextW(control, text, static_cast<int>(std::size(text)));
    RECT text_rect = client;
    text_rect.left = box.right + Dip(state.dpi_value, 8);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, enabled ? ColorText() : RGB(132, 139, 155));
    const HGDIOBJ old_font = SelectObject(dc, state.body_font);
    DrawTextW(dc, text, -1, &text_rect,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
                  DT_END_ELLIPSIS);
    SelectObject(dc, old_font);

    if (GetFocus() == control) {
        RECT focus = box;
        InflateRect(&focus, Dip(state.dpi_value, 2),
                    Dip(state.dpi_value, 2));
        DrawRoundedOutline(dc, focus, ColorAccent(), state.dpi_value, 4);
    }
}

LRESULT CALLBACK ProfileCheckboxProc(HWND control, UINT message,
                                     WPARAM wparam, LPARAM lparam,
                                     UINT_PTR subclass_id,
                                     DWORD_PTR reference_data) {
    auto* state = reinterpret_cast<ProfileDialogState*>(reference_data);
    if (!state) return DefSubclassProc(control, message, wparam, lparam);
    if (message == WM_PAINT) {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(control, &paint);
        DrawProfileCheckbox(control, dc, *state);
        EndPaint(control, &paint);
        return 0;
    }
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_NCDESTROY) {
        RemoveWindowSubclass(control, ProfileCheckboxProc, subclass_id);
    }
    return DefSubclassProc(control, message, wparam, lparam);
}

void CreateControls(ProfileDialogState& state) {
    const Translation& translation = *state.translation;
    state.title = CreateLabel(
        state.dialog, ProfileTitle(translation, state.config_name));
    SetFont(state.title, state.title_font);

    const std::array<std::pair<std::string_view, std::wstring_view>, 4> sections = {{
        {"edit_config.name_group", L"配置信息"},
        {"edit_config.program_group", L"程序与参数"},
        {"edit_config.pre_launch_group", L"启动前命令与 DLL 列表"},
        {"edit_config.window_group", L"窗口与 DPI"},
    }};
    for (const auto& [key, fallback] : sections) {
        state.section_labels.push_back(
            CreateLabel(state.dialog, Tr(translation, key, fallback)));
    }

    auto add_body_label = [&](std::string_view key,
                              std::wstring_view fallback) {
        HWND label = CreateLabel(state.dialog, Tr(translation, key, fallback));
        state.body_controls.push_back(label);
        return label;
    };
    state.display_label =
        add_body_label("cxx.edit_config.display_name", L"显示名称");
    state.icon_label =
        add_body_label("cxx.edit_config.custom_icon", L"自定义图标");
    state.launch_label =
        add_body_label("cxx.edit_config.launch_program", L"启动程序");
    state.target_label =
        add_body_label("cxx.edit_config.injection_target", L"注入目标");
    state.arguments_label =
        add_body_label("cxx.edit_config.arguments", L"启动参数");
    state.prelaunch_label =
        add_body_label("edit_config.pre_launch_command_label", L"启动前命令");
    state.prelaunch_wait_label =
        add_body_label("edit_config.pre_launch_wait_label", L"命令后等待（秒）");
    state.dll_label =
        add_body_label("edit_config.dll_group", L"注入 DLL 列表");
    state.injection_label =
        add_body_label("cxx.edit_config.injection_method", L"注入方式");
    state.seconds_label = add_body_label("cxx.edit_config.seconds", L"秒");

    state.display = CreateEdit(state.dialog, ES_AUTOHSCROLL);
    state.icon_preview =
        CreateChild(state.dialog, L"STATIC", L"",
                    SS_OWNERDRAW | WS_CLIPSIBLINGS, kIconPreview);
    state.icon = CreateEdit(state.dialog, ES_AUTOHSCROLL);
    state.browse_icon = CreateButton(
        state.dialog, Tr(translation, "edit_config.change_icon", L"更改图标"),
        kBrowseIcon);
    state.reset_icon = CreateButton(
        state.dialog, Tr(translation, "edit_config.reset_icon", L"重置"),
        kResetIcon);
    state.body_controls.push_back(state.browse_icon);
    state.body_controls.push_back(state.reset_icon);
    state.launch = CreateEdit(state.dialog, ES_AUTOHSCROLL);
    state.browse_launch = CreateButton(
        state.dialog, Tr(translation, "edit_config.browse", L"浏览..."),
        kBrowseLaunch);
    state.body_controls.push_back(state.browse_launch);
    state.target = CreateEdit(state.dialog, ES_AUTOHSCROLL);
    state.browse_target = CreateButton(
        state.dialog, Tr(translation, "edit_config.browse", L"浏览..."),
        kBrowseTarget);
    state.body_controls.push_back(state.browse_target);
    state.arguments = CreateEdit(state.dialog, ES_AUTOHSCROLL);
    state.prelaunch = CreateEdit(state.dialog, ES_AUTOHSCROLL);
    state.prelaunch_wait =
        CreateEdit(state.dialog, ES_NUMBER | ES_AUTOHSCROLL);
    state.injection =
        CreateChild(state.dialog, L"COMBOBOX", L"",
                    WS_TABSTOP | WS_CLIPSIBLINGS | CBS_DROPDOWNLIST |
                        CBS_OWNERDRAWFIXED | CBS_HASSTRINGS | WS_VSCROLL);
    const std::wstring direct =
        Tr(translation, "cxx.edit_config.injection_direct", L"直接注入");
    const std::wstring hook =
        Tr(translation, "cxx.edit_config.injection_hook", L"钩子注入");
    SendMessageW(state.injection, CB_ADDSTRING, 0,
                 reinterpret_cast<LPARAM>(direct.c_str()));
    SendMessageW(state.injection, CB_ADDSTRING, 0,
                 reinterpret_cast<LPARAM>(hook.c_str()));
    ApplyDarkTheme(state.injection);
    EnableHoverTracking(state.injection);
    COMBOBOXINFO combo_info{};
    combo_info.cbSize = sizeof(combo_info);
    if (GetComboBoxInfo(state.injection, &combo_info)) {
        ApplyDarkTheme(combo_info.hwndList);
        ApplyDarkTheme(combo_info.hwndItem);
    }
    SetWindowSubclass(state.injection, ProfileComboProc,
                      kProfileCheckboxSubclass + 1,
                      reinterpret_cast<DWORD_PTR>(&state));
    const std::wstring reshade_text =
        Tr(translation, "cxx.edit_config.enable_reshade",
           L"启用 ReShade64.dll");
    state.reshade =
        CreateChild(state.dialog, L"BUTTON", reshade_text.c_str(),
                    WS_TABSTOP | WS_CLIPSIBLINGS | BS_AUTOCHECKBOX,
                    kToggleReshade);
    ApplyDarkTheme(state.reshade);
    state.dlls = CreateChild(
        state.dialog, L"LISTBOX", L"",
        WS_TABSTOP | WS_CLIPSIBLINGS | WS_VSCROLL | LBS_NOTIFY |
            LBS_NOINTEGRALHEIGHT,
        0);
    ApplyDarkTheme(state.dlls);
    const std::wstring add_dll_text =
        Tr(translation, "cxx.edit_config.add",
           Tr(translation, "edit_config.add_dll", L"添加 DLL"));
    state.browse_dlls = CreateButton(
        state.dialog, add_dll_text, kBrowseDlls);
    state.remove_dll = CreateButton(
        state.dialog,
        Tr(translation, "edit_config.remove_dll",
           Tr(translation, "cxx.edit_config.delete", L"删除")),
        kRemoveDll);
    state.move_dll_up =
        CreateButton(state.dialog, L"\u2191", kMoveDllUp);
    state.move_dll_down =
        CreateButton(state.dialog, L"\u2193", kMoveDllDown);
    state.body_controls.push_back(state.browse_dlls);
    state.body_controls.push_back(state.remove_dll);
    state.body_controls.push_back(state.move_dll_up);
    state.body_controls.push_back(state.move_dll_down);

    const std::wstring center_text =
        Tr(translation, "cxx.edit_config.force_center",
           L"启用启动时强制居中");
    state.center =
        CreateChild(state.dialog, L"BUTTON", center_text.c_str(),
                    WS_TABSTOP | WS_CLIPSIBLINGS | BS_AUTOCHECKBOX);
    ApplyDarkTheme(state.center);
    state.center_duration =
        CreateEdit(state.dialog, ES_NUMBER | ES_AUTOHSCROLL);
    const std::wstring dpi_text =
        Tr(translation, "cxx.edit_config.dpi_override",
           L"替代此程序的高 DPI 缩放行为");
    state.dpi =
        CreateChild(state.dialog, L"BUTTON", dpi_text.c_str(),
                    WS_TABSTOP | WS_CLIPSIBLINGS | BS_AUTOCHECKBOX);
    ApplyDarkTheme(state.dpi);
    for (HWND checkbox : {state.reshade, state.center, state.dpi}) {
        SetWindowSubclass(checkbox, ProfileCheckboxProc,
                          kProfileCheckboxSubclass,
                          reinterpret_cast<DWORD_PTR>(&state));
    }
    state.hint =
        CreateLabel(state.dialog, Tr(translation, "edit_config.hint", L""));
    state.dpi_hint = CreateLabel(state.dialog, L"");
    state.small_controls.push_back(state.hint);
    state.small_controls.push_back(state.dpi_hint);

    state.delete_button = CreateButton(
        state.dialog, Tr(translation, "cxx.edit_config.delete", L"删除"),
        kDelete);
    state.cancel_button = CreateButton(
        state.dialog, Tr(translation, "cxx.edit_config.cancel", L"取消"),
        IDCANCEL);
    state.save_button = CreateButton(
        state.dialog, Tr(translation, "cxx.edit_config.save", L"保存"), IDOK);
    state.body_controls.push_back(state.delete_button);
    state.body_controls.push_back(state.cancel_button);
    state.body_controls.push_back(state.save_button);

    for (HWND control :
         {state.display, state.icon, state.launch, state.target, state.arguments,
          state.prelaunch, state.prelaunch_wait, state.dlls, state.injection,
          state.reshade, state.center,
          state.center_duration, state.dpi}) {
        state.body_controls.push_back(control);
    }
    SendMessageW(state.dialog, DM_SETDEFID, IDOK, 0);
}

void RefreshDpiControls(ProfileDialogState& state) {
    std::filesystem::path executable = GetControlText(state.launch);
    if (executable.empty()) executable = GetControlText(state.target);
    if (executable.empty()) {
        executable = Utf8ToWide(
            state.config.value("game_dir", std::string()));
    }
    std::wstring dpi_hint =
        Tr(*state.translation, "edit_config.dpi_exe_hint",
           L"Target EXE: {exe}");
    dpi_hint = ReplaceToken(
        dpi_hint, L"{exe}",
        executable.empty() ? L"-" : executable.wstring());
    SetControlText(state.dpi_hint, dpi_hint);
    SendMessageW(state.dpi, BM_SETCHECK,
                 ReadDpiOverride(executable) ? BST_CHECKED
                                               : BST_UNCHECKED,
                 0);
}

void LoadControlValues(ProfileDialogState& state) {
    SetControlText(state.display, Utf8ToWide(state.display_name));
    SetControlText(state.icon, Utf8ToWide(state.custom_icon));
    SetControlText(state.launch,
                   Utf8ToWide(state.config.value("launch_program", std::string())));
    SetControlText(
        state.target,
        Utf8ToWide(state.config.value("target_program", std::string())));
    SetControlText(
        state.arguments,
        Utf8ToWide(state.config.value("launch_args", std::string())));
    SetControlText(
        state.prelaunch,
        Utf8ToWide(state.config.value("pre_launch_command", std::string())));
    SetControlText(
        state.prelaunch_wait,
        std::to_wstring(state.config.value("pre_launch_wait_seconds", 0)));
    const bool reshade_enabled =
        state.config.contains("reshade_dll") &&
        state.config["reshade_dll"].is_string() &&
        !state.config["reshade_dll"].get<std::string>().empty();
    SendMessageW(state.reshade, BM_SETCHECK,
                 reshade_enabled ? BST_CHECKED : BST_UNCHECKED, 0);
    SetReshadeListEntry(state.dlls, reshade_enabled);
    if (state.config.contains("dll_files") && state.config["dll_files"].is_array()) {
        for (const auto& dll : state.config["dll_files"]) {
            if (!dll.is_string()) continue;
            const std::wstring value =
                Utf8ToWide(dll.get<std::string>());
            if (IsReshadeDllValue(value)) continue;
            SendMessageW(state.dlls, LB_ADDSTRING, 0,
                         reinterpret_cast<LPARAM>(value.c_str()));
        }
    }
    const std::string method =
        state.config.value("injection_method", std::string("direct"));
    SendMessageW(state.injection, CB_SETCURSEL, ToLower(method) == "hook" ? 1 : 0,
                 0);
    SendMessageW(
        state.center, BM_SETCHECK,
        state.config.value("force_center_window", false) ? BST_CHECKED
                                                          : BST_UNCHECKED,
        0);
    SetControlText(state.center_duration,
                   std::to_wstring(state.config.value("center_window_duration", 10)));
    RefreshDpiControls(state);
}

INT_PTR CALLBACK ProfileDialogProc(HWND dialog, UINT message, WPARAM wparam,
                                   LPARAM lparam) {
    auto* state =
        reinterpret_cast<ProfileDialogState*>(GetWindowLongPtrW(dialog, DWLP_USER));
    if (message == WM_INITDIALOG) {
        state = reinterpret_cast<ProfileDialogState*>(lparam);
        state->dialog = dialog;
        SetWindowLongPtrW(dialog, DWLP_USER, lparam);
        SetWindowLongPtrW(dialog, GWL_EXSTYLE,
                          GetWindowLongPtrW(dialog, GWL_EXSTYLE) |
                              WS_EX_COMPOSITED);
        ConfigureOverlayWindow(dialog);
        SetDarkWindowFrame(dialog);
        CreateStateResources(*state);
        const std::wstring title =
            ProfileTitle(*state->translation, state->config_name);
        SetWindowTextW(dialog, title.c_str());
        CreateControls(*state);
        ApplyFonts(*state);
        LoadControlValues(*state);
        UpdateIconPreview(*state);
        SizeAndCenterDialog(*state);
        LayoutControls(*state);
        UpdateScrollBar(*state);
        RedrawWindow(dialog, nullptr, nullptr,
                     RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_FRAME);
        SetFocus(state->display);
        SendMessageW(state->display, EM_SETSEL, 0, 0);
        SendMessageW(state->display, EM_SCROLLCARET, 0, 0);
        return FALSE;
    }
    if (!state) return FALSE;

    switch (message) {
        case WM_PAINT:
            PaintDialog(*state);
            return TRUE;
        case WM_ERASEBKGND:
            return TRUE;
        case WM_SIZE:
            UpdateScrollBar(*state);
            RefreshOverlayRegion(dialog);
            RedrawWindow(dialog, nullptr, nullptr,
                         RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN |
                             RDW_FRAME);
            return TRUE;
        case WM_DPICHANGED: {
            DestroyStateResources(*state);
            state->dpi_value = HIWORD(wparam);
            state->background_brush = CreateSolidBrush(ColorBackground());
            state->panel_brush = CreateSolidBrush(ColorPanel());
            state->input_brush = CreateSolidBrush(ColorInput());
            state->title_font = CreateUiFont(state->dpi_value, 17, FW_SEMIBOLD);
            state->section_font = CreateUiFont(state->dpi_value, 10, FW_SEMIBOLD);
            state->body_font = CreateUiFont(state->dpi_value, 10, FW_NORMAL);
            state->small_font = CreateUiFont(state->dpi_value, 9, FW_NORMAL);
            LoadBackgroundImage(state->background_path, &state->background);
            ApplyFonts(*state);
            SizeAndCenterDialog(*state);
            state->scroll_position = 0;
            LayoutControls(*state);
            UpdateScrollBar(*state);
            UpdateIconPreview(*state);
            RedrawWindow(dialog, nullptr, nullptr,
                         RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN |
                             RDW_FRAME);
            return TRUE;
        }
        case WM_VSCROLL:
            HandleScroll(*state, wparam);
            return TRUE;
        case WM_MOUSEWHEEL: {
            const int delta = GET_WHEEL_DELTA_WPARAM(wparam);
            ScrollTo(*state,
                     state->scroll_position -
                         MulDiv(delta, Dip(state->dpi_value, 48), WHEEL_DELTA));
            return TRUE;
        }
        case WM_CTLCOLORDLG:
            return reinterpret_cast<INT_PTR>(state->background_brush);
        case WM_CTLCOLORSTATIC: {
            HDC dc = reinterpret_cast<HDC>(wparam);
            HWND control = reinterpret_cast<HWND>(lparam);
            SetBkMode(dc, TRANSPARENT);
            const bool heading =
                control == state->title ||
                std::find(state->section_labels.begin(),
                          state->section_labels.end(),
                          control) != state->section_labels.end();
            SetTextColor(dc, heading ? ColorText() : ColorMuted());
            return reinterpret_cast<INT_PTR>(GetStockObject(HOLLOW_BRUSH));
        }
        case WM_CTLCOLORBTN: {
            HDC dc = reinterpret_cast<HDC>(wparam);
            SetBkMode(dc, TRANSPARENT);
            SetTextColor(dc, ColorText());
            return reinterpret_cast<INT_PTR>(state->panel_brush);
        }
        case WM_CTLCOLOREDIT:
        case WM_CTLCOLORLISTBOX: {
            HDC dc = reinterpret_cast<HDC>(wparam);
            SetBkColor(dc, ColorInput());
            SetTextColor(dc, ColorText());
            return reinterpret_cast<INT_PTR>(state->input_brush);
        }
        case WM_CTLCOLORSCROLLBAR: {
            HDC dc = reinterpret_cast<HDC>(wparam);
            SetBkColor(dc, ColorBackground());
            return reinterpret_cast<INT_PTR>(state->background_brush);
        }
        case WM_DRAWITEM: {
            const auto* item = reinterpret_cast<const DRAWITEMSTRUCT*>(lparam);
            if (item && item->CtlID == kIconPreview) {
                FillRect(item->hDC, &item->rcItem, state->panel_brush);
                if (state->preview_icon) {
                    const int available =
                        std::min(item->rcItem.right - item->rcItem.left,
                                 item->rcItem.bottom - item->rcItem.top);
                    const int size =
                        std::max(1, available - Dip(state->dpi_value, 2));
                    DrawIconEx(
                        item->hDC,
                        item->rcItem.left +
                            (item->rcItem.right - item->rcItem.left - size) / 2,
                        item->rcItem.top +
                            (item->rcItem.bottom - item->rcItem.top - size) / 2,
                        state->preview_icon, size, size, 0, nullptr, DI_NORMAL);
                }
                return TRUE;
            }
            if (item && item->CtlType == ODT_COMBOBOX &&
                item->hwndItem == state->injection) {
                DrawOwnerCombo(*item, *state);
                return TRUE;
            }
            if (item && item->CtlType == ODT_BUTTON) {
                DrawOwnerButton(*item, *state);
                return TRUE;
            }
            break;
        }
        case WM_MEASUREITEM: {
            auto* item = reinterpret_cast<MEASUREITEMSTRUCT*>(lparam);
            if (item && item->CtlType == ODT_COMBOBOX) {
                item->itemHeight = Dip(state->dpi_value, 30);
                return TRUE;
            }
            break;
        }
        case WM_COMMAND: {
            const int id = LOWORD(wparam);
            if (reinterpret_cast<HWND>(lparam) == state->injection &&
                HIWORD(wparam) == CBN_SELCHANGE) {
                InvalidateRect(state->injection, nullptr, FALSE);
                return TRUE;
            }
            const std::wstring executable_filter =
                Tr(*state->translation, "cxx.file.filter.programs",
                   L"可执行文件");
            const std::wstring all_filter =
                Tr(*state->translation, "cxx.file.filter.all_files",
                   L"所有文件");
            const std::wstring dll_filter =
                Tr(*state->translation, "cxx.file.filter.dll_files",
                   L"DLL 文件");
            const std::wstring image_filter =
                Tr(*state->translation, "cxx.file.filter.icons", L"图标文件");
            const COMDLG_FILTERSPEC exe_filters[] = {
                {executable_filter.c_str(), L"*.exe"},
                {all_filter.c_str(), L"*.*"}};
            const COMDLG_FILTERSPEC dll_filters[] = {
                {dll_filter.c_str(), L"*.dll"}, {all_filter.c_str(), L"*.*"}};
            const COMDLG_FILTERSPEC image_filters[] = {
                {image_filter.c_str(), L"*.png;*.jpg;*.jpeg;*.ico"},
                {all_filter.c_str(), L"*.*"}};
            if (id == kToggleReshade && HIWORD(wparam) == BN_CLICKED) {
                SetReshadeListEntry(
                    state->dlls,
                    SendMessageW(state->reshade, BM_GETCHECK, 0, 0) ==
                        BST_CHECKED);
                InvalidateRect(state->reshade, nullptr, FALSE);
                return TRUE;
            }
            if (id == kBrowseIcon) {
                const std::wstring title =
                    Tr(*state->translation, "cxx.file.select_custom_icon",
                       L"选择图标文件");
                if (auto path =
                        PickFile(dialog, title.c_str(), image_filters, 2)) {
                    SetControlText(state->icon, path->wstring());
                    UpdateIconPreview(*state);
                }
                return TRUE;
            }
            if (id == kResetIcon) {
                SetControlText(state->icon, L"");
                UpdateIconPreview(*state);
                return TRUE;
            }
            if (id == kBrowseLaunch || id == kBrowseTarget) {
                const std::wstring title = Tr(
                    *state->translation,
                    id == kBrowseLaunch ? "cxx.file.select_launch_program"
                                        : "cxx.file.select_target_program",
                    L"选择可执行文件");
                if (auto path =
                        PickFile(dialog, title.c_str(), exe_filters, 2)) {
                    SetControlText(id == kBrowseLaunch ? state->launch
                                                      : state->target,
                                   path->wstring());
                    if (id == kBrowseLaunch) RefreshDpiControls(*state);
                    if (id == kBrowseTarget) UpdateIconPreview(*state);
                }
                return TRUE;
            }
            if (reinterpret_cast<HWND>(lparam) == state->launch &&
                HIWORD(wparam) == EN_KILLFOCUS) {
                RefreshDpiControls(*state);
                return TRUE;
            }
            if (id == kBrowseDlls) {
                const std::wstring title =
                    Tr(*state->translation, "cxx.file.add_dll_files",
                       L"请选择 DLL 文件");
                auto paths = PickFiles(dialog, title.c_str(), dll_filters, 2);
                if (!paths.empty()) {
                    for (const auto& path : paths) {
                        const std::wstring value = path.wstring();
                        if (IsReshadeDllValue(value)) {
                            SendMessageW(state->reshade, BM_SETCHECK,
                                         BST_CHECKED, 0);
                            InvalidateRect(state->reshade, nullptr, FALSE);
                            SetReshadeListEntry(state->dlls, true);
                            continue;
                        }
                        if (SendMessageW(state->dlls, LB_FINDSTRINGEXACT,
                                         static_cast<WPARAM>(-1),
                                         reinterpret_cast<LPARAM>(value.c_str())) ==
                            LB_ERR) {
                            SendMessageW(state->dlls, LB_ADDSTRING, 0,
                                         reinterpret_cast<LPARAM>(value.c_str()));
                        }
                    }
                    const LRESULT count =
                        SendMessageW(state->dlls, LB_GETCOUNT, 0, 0);
                    if (count != LB_ERR && count > 0) {
                        SendMessageW(state->dlls, LB_SETCURSEL, count - 1, 0);
                    }
                }
                return TRUE;
            }
            if (id == kRemoveDll) {
                const LRESULT selected =
                    SendMessageW(state->dlls, LB_GETCURSEL, 0, 0);
                if (selected != LB_ERR) {
                    const LRESULT length =
                        SendMessageW(state->dlls, LB_GETTEXTLEN, selected, 0);
                    if (length != LB_ERR && length >= 0) {
                        std::wstring value(static_cast<size_t>(length) + 1,
                                           L'\0');
                        SendMessageW(state->dlls, LB_GETTEXT, selected,
                                     reinterpret_cast<LPARAM>(value.data()));
                        value.resize(static_cast<size_t>(length));
                        if (IsReshadeDllValue(value)) {
                            SendMessageW(state->reshade, BM_SETCHECK,
                                         BST_UNCHECKED, 0);
                            InvalidateRect(state->reshade, nullptr, FALSE);
                        }
                    }
                    SendMessageW(state->dlls, LB_DELETESTRING, selected, 0);
                    const LRESULT count =
                        SendMessageW(state->dlls, LB_GETCOUNT, 0, 0);
                    if (count > 0) {
                        SendMessageW(
                            state->dlls, LB_SETCURSEL,
                            std::min<LRESULT>(selected, count - 1), 0);
                    }
                }
                return TRUE;
            }
            if (id == kMoveDllUp || id == kMoveDllDown) {
                const LRESULT selected =
                    SendMessageW(state->dlls, LB_GETCURSEL, 0, 0);
                const LRESULT count =
                    SendMessageW(state->dlls, LB_GETCOUNT, 0, 0);
                const LRESULT target =
                    selected + (id == kMoveDllUp ? -1 : 1);
                if (selected != LB_ERR && selected >= 0 && selected < count &&
                    target >= 0 && target < count) {
                    const LRESULT length =
                        SendMessageW(state->dlls, LB_GETTEXTLEN, selected, 0);
                    if (length != LB_ERR) {
                        std::wstring value(static_cast<size_t>(length) + 1, L'\0');
                        SendMessageW(state->dlls, LB_GETTEXT, selected,
                                     reinterpret_cast<LPARAM>(value.data()));
                        value.resize(static_cast<size_t>(length));
                        SendMessageW(state->dlls, LB_DELETESTRING, selected, 0);
                        SendMessageW(
                            state->dlls, LB_INSERTSTRING, target,
                            reinterpret_cast<LPARAM>(value.c_str()));
                        SendMessageW(state->dlls, LB_SETCURSEL, target, 0);
                    }
                }
                return TRUE;
            }
            if (id == 0 && HIWORD(wparam) == LBN_DBLCLK) {
                const LRESULT selected =
                    SendMessageW(state->dlls, LB_GETCURSEL, 0, 0);
                if (selected != LB_ERR) {
                    const LRESULT length =
                        SendMessageW(state->dlls, LB_GETTEXTLEN, selected, 0);
                    if (length != LB_ERR && length >= 0) {
                        std::wstring value(static_cast<size_t>(length) + 1,
                                           L'\0');
                        SendMessageW(state->dlls, LB_GETTEXT, selected,
                                     reinterpret_cast<LPARAM>(value.data()));
                        value.resize(static_cast<size_t>(length));
                        if (IsReshadeDllValue(value)) return TRUE;
                    }
                    const std::wstring title =
                        Tr(*state->translation, "cxx.file.add_dll_files",
                           L"请选择 DLL 文件");
                    if (auto path =
                            PickFile(dialog, title.c_str(), dll_filters, 2)) {
                        const std::wstring value = path->wstring();
                        SendMessageW(state->dlls, LB_DELETESTRING, selected, 0);
                        SendMessageW(state->dlls, LB_INSERTSTRING, selected,
                                     reinterpret_cast<LPARAM>(value.c_str()));
                        SendMessageW(state->dlls, LB_SETCURSEL, selected, 0);
                    }
                }
                return TRUE;
            }
            if (id == kDelete) {
                const std::wstring title =
                    Tr(*state->translation, "cxx.edit_config.delete_title",
                       L"确认删除");
                std::wstring confirm_message =
                    Tr(*state->translation, "cxx.edit_config.delete_message",
                       L"确定要删除配置 {name} 吗？");
                confirm_message =
                    ReplaceToken(confirm_message, L"{name}",
                                 Utf8ToWide(state->config_name));
                if (Confirm(dialog, title, confirm_message)) {
                    state->result.deleted = true;
                    EndDialog(dialog, IDOK);
                }
                return TRUE;
            }
            if (id == IDOK) {
                const std::wstring custom_icon_text = GetControlText(state->icon);
                if (!custom_icon_text.empty()) {
                    HICON custom_icon =
                        LoadPreviewIcon(custom_icon_text, 32);
                    if (!custom_icon) {
                        ShowError(
                            dialog,
                            Tr(*state->translation, "dialog.error", L"Error"),
                            Tr(*state->translation, "edit_config.icon_load_failed",
                               L"Cannot load the selected icon."));
                        return TRUE;
                    }
                    DestroyIcon(custom_icon);
                }
                Json config = state->config;
                config["launch_program"] =
                    WideToUtf8(NormalizePathSeparators(
                        GetControlText(state->launch)));
                config["target_program"] =
                    WideToUtf8(NormalizePathSeparators(
                        GetControlText(state->target)));
                const std::filesystem::path target_program(
                    GetControlText(state->target));
                config["game_dir"] = WideToUtf8(
                    NormalizePathSeparators(target_program.wstring()));
                config["game_exe_name"] =
                    WideToUtf8(target_program.filename().wstring());
                config["launch_args"] =
                    WideToUtf8(GetControlText(state->arguments));
                config["pre_launch_command"] =
                    WideToUtf8(GetControlText(state->prelaunch));
                try {
                    config["pre_launch_wait_seconds"] =
                        std::clamp(std::stoi(GetControlText(state->prelaunch_wait)),
                                   0, 300);
                } catch (...) {
                    config["pre_launch_wait_seconds"] = 0;
                }
                config["injection_method"] =
                    static_cast<int>(
                        SendMessageW(state->injection, CB_GETCURSEL, 0, 0)) == 1
                        ? "hook"
                        : "direct";
                Json dlls = Json::array();
                const LRESULT dll_count =
                    SendMessageW(state->dlls, LB_GETCOUNT, 0, 0);
                for (LRESULT index = 0;
                     dll_count != LB_ERR && index < dll_count; ++index) {
                    const LRESULT length =
                        SendMessageW(state->dlls, LB_GETTEXTLEN, index, 0);
                    if (length == LB_ERR || length <= 0) continue;
                    std::wstring value(static_cast<size_t>(length) + 1, L'\0');
                    SendMessageW(state->dlls, LB_GETTEXT, index,
                                 reinterpret_cast<LPARAM>(value.data()));
                    value.resize(static_cast<size_t>(length));
                    const auto normalized =
                        NormalizePathSeparators(std::move(value));
                    const std::filesystem::path path(normalized);
                    if (_wcsicmp(path.filename().c_str(),
                                 L"ReShade64.dll") != 0) {
                        dlls.push_back(WideToUtf8(normalized));
                    }
                }
                config["dll_files"] = std::move(dlls);
                if (SendMessageW(state->reshade, BM_GETCHECK, 0, 0) ==
                    BST_CHECKED) {
                    config["reshade_dll"] = "ReShade64.dll";
                } else {
                    config.erase("reshade_dll");
                }
                config["force_center_window"] =
                    SendMessageW(state->center, BM_GETCHECK, 0, 0) ==
                    BST_CHECKED;
                try {
                    config["center_window_duration"] =
                        std::stoi(GetControlText(state->center_duration));
                } catch (...) {
                    config["center_window_duration"] = 10;
                }
                const bool dpi_enabled =
                    SendMessageW(state->dpi, BM_GETCHECK, 0, 0) == BST_CHECKED;
                config["dpi_override"] = dpi_enabled;
                const auto dpi_error = ApplyDpiOverride(
                    Utf8ToWide(config.value(
                        "launch_program",
                        config.value("game_dir", std::string()))),
                    dpi_enabled);
                if (!dpi_error.empty()) {
                    std::wstring warning = Tr(
                        *state->translation, "edit_config.dpi_error",
                        L"DPI setting failed: {error}");
                    warning = ReplaceToken(warning, L"{error}", dpi_error);
                    ShowError(dialog,
                              Tr(*state->translation, "dialog.error", L"Error"),
                              warning);
                    SendMessageW(state->dpi, BM_SETCHECK, BST_UNCHECKED, 0);
                    return TRUE;
                }
                state->result.config = std::move(config);
                std::wstring display =
                    GetControlText(state->display);
                if (display.find_first_not_of(L" \t\r\n") ==
                    std::wstring::npos) {
                    display = Utf8ToWide(state->config_name);
                }
                state->result.display_name = WideToUtf8(display);
                state->result.custom_icon =
                    WideToUtf8(NormalizePathSeparators(
                        custom_icon_text));
                EndDialog(dialog, IDOK);
                return TRUE;
            }
            if (id == IDCANCEL) {
                EndDialog(dialog, IDCANCEL);
                return TRUE;
            }
            break;
        }
        case WM_CLOSE:
            EndDialog(dialog, IDCANCEL);
            return TRUE;
        case WM_NCDESTROY:
            DestroyStateResources(*state);
            SetWindowLongPtrW(dialog, DWLP_USER, 0);
            break;
    }
    return FALSE;
}

std::vector<BYTE> MakeDialogTemplate(const wchar_t* title,
                                     bool vertical_scroll = true) {
    const std::wstring title_text(title);
    const size_t bytes = sizeof(DLGTEMPLATE) + sizeof(WORD) * 2 +
                         (title_text.size() + 1) * sizeof(wchar_t);
    std::vector<BYTE> buffer(bytes, 0);
    auto* dialog = reinterpret_cast<DLGTEMPLATE*>(buffer.data());
    dialog->style = DS_CENTER | WS_POPUP | WS_CLIPCHILDREN;
    if (vertical_scroll) dialog->style |= WS_VSCROLL;
    dialog->dwExtendedStyle = WS_EX_COMPOSITED | WS_EX_TOOLWINDOW;
    dialog->cdit = 0;
    dialog->x = 0;
    dialog->y = 0;
    dialog->cx = 1;
    dialog->cy = 1;
    BYTE* cursor = buffer.data() + sizeof(DLGTEMPLATE);
    *reinterpret_cast<WORD*>(cursor) = 0;
    cursor += sizeof(WORD);
    *reinterpret_cast<WORD*>(cursor) = 0;
    cursor += sizeof(WORD);
    memcpy(cursor, title_text.c_str(), (title_text.size() + 1) * sizeof(wchar_t));
    return buffer;
}

void AppendRtfText(std::string& output, std::wstring_view text) {
    for (wchar_t character : text) {
        if (character == L'\\' || character == L'{' || character == L'}') {
            output.push_back('\\');
            output.push_back(static_cast<char>(character));
        } else if (character == L'\r') {
            continue;
        } else if (character == L'\n' || character == L'\t') {
            if (!output.empty() && output.back() != ' ') output.push_back(' ');
        } else if (character >= 0x20 && character <= 0x7e) {
            output.push_back(static_cast<char>(character));
        } else {
            int value = static_cast<int>(
                static_cast<std::uint16_t>(character));
            if (value > 32767) value -= 65536;
            output += "\\u" + std::to_string(value) + "?";
        }
    }
}

int RtfColorForHtml(std::wstring_view color) {
    const std::wstring normalized = ToLower(std::wstring(color));
    if (normalized == L"#82ff55") return 2;
    if (normalized == L"#ffa855") return 3;
    if (normalized == L"#55ffff") return 4;
    if (normalized == L"#ff55ff") return 5;
    return 1;
}

std::string HtmlToRtf(std::wstring_view html) {
    std::string body;
    body.reserve(html.size() * 2);
    std::wstring text;
    auto flush_text = [&] {
        AppendRtfText(body, text);
        text.clear();
    };

    for (size_t index = 0; index < html.size();) {
        if (html[index] == L'<') {
            flush_text();
            const size_t end = html.find(L'>', index + 1);
            if (end == std::wstring_view::npos) break;
            std::wstring raw =
                std::wstring(html.substr(index + 1, end - index - 1));
            const auto first_space = raw.find_first_of(L" \t\r\n");
            std::wstring tag = ToLower(
                raw.substr(0, first_space == std::wstring::npos
                                  ? raw.size()
                                  : first_space));
            const bool closing = !tag.empty() && tag.front() == L'/';
            if (closing) tag.erase(tag.begin());

            int color = 0;
            const std::wstring lower_raw = ToLower(raw);
            const size_t color_position = lower_raw.find(L"color:");
            if (color_position != std::wstring::npos) {
                size_t start = color_position + 6;
                while (start < raw.size() &&
                       (raw[start] == L' ' || raw[start] == L'\'' ||
                        raw[start] == L'"')) {
                    ++start;
                }
                size_t color_end = start;
                while (color_end < raw.size() &&
                       (std::iswalnum(raw[color_end]) ||
                        raw[color_end] == L'#')) {
                    ++color_end;
                }
                color = RtfColorForHtml(
                    raw.substr(start, color_end - start));
            }

            if (tag == L"br") {
                body += "\\par ";
            } else if (tag == L"p") {
                if (closing) body += "\\par ";
            } else if (tag == L"h2" || tag == L"h3") {
                if (closing) {
                    body += tag == L"h2"
                                ? "\\b0\\fs30\\cf1\\par "
                                : "\\b0\\fs24\\cf1\\par ";
                } else {
                    body += tag == L"h2"
                                ? "\\par\\b\\fs34\\cf2 "
                                : "\\par\\b\\fs26\\cf2 ";
                    if (color) {
                        body += "\\cf" + std::to_string(color) + " ";
                    }
                }
            } else if (tag == L"b" || tag == L"strong") {
                body += closing ? "\\b0\\cf1 " : "\\b ";
                if (color) body += "\\cf" + std::to_string(color) + " ";
            } else if (tag == L"i" || tag == L"em") {
                body += closing ? "\\i0 " : "\\i ";
            }
            index = end + 1;
            continue;
        }
        if (html[index] == L'&') {
            const size_t end = html.find(L';', index + 1);
            if (end != std::wstring_view::npos && end - index <= 8) {
                const std::wstring entity =
                    ToLower(std::wstring(html.substr(index + 1, end - index - 1)));
                if (entity == L"nbsp") {
                    text.push_back(L' ');
                } else if (entity == L"amp") {
                    text.push_back(L'&');
                } else if (entity == L"lt") {
                    text.push_back(L'<');
                } else if (entity == L"gt") {
                    text.push_back(L'>');
                } else if (entity == L"quot") {
                    text.push_back(L'"');
                } else {
                    text.append(html.substr(index, end - index + 1));
                }
                index = end + 1;
                continue;
            }
        }
        text.push_back(html[index++]);
    }
    flush_text();

    std::string rtf =
        "{\\rtf1\\ansi\\deff0"
        "{\\fonttbl{\\f0 Microsoft YaHei;}}"
        "{\\colortbl ;"
        "\\red240\\green246\\blue255;"
        "\\red92\\green255\\blue72;"
        "\\red255\\green168\\blue85;"
        "\\red85\\green255\\blue255;"
        "\\red255\\green85\\blue255;}"
        "\\viewkind4\\uc1\\pard\\sl240\\slmult1"
        "\\f0\\fs21\\cf1 ";
    rtf += body;
    rtf += "}";
    return rtf;
}

DWORD CALLBACK ReadRtfStream(DWORD_PTR cookie, LPBYTE buffer, LONG count,
                             LONG* bytes_read) {
    auto* data = reinterpret_cast<std::pair<const std::string*, size_t>*>(cookie);
    const size_t remaining = data->first->size() - data->second;
    const size_t requested = static_cast<size_t>(std::max(0L, count));
    const size_t copied = std::min(remaining, requested);
    if (copied) {
        memcpy(buffer, data->first->data() + data->second, copied);
        data->second += copied;
    }
    *bytes_read = static_cast<LONG>(copied);
    return 0;
}

void SetRichText(HWND control, const std::string& rtf) {
    size_t offset = 0;
    std::pair<const std::string*, size_t> state{&rtf, offset};
    EDITSTREAM stream{};
    stream.dwCookie = reinterpret_cast<DWORD_PTR>(&state);
    stream.pfnCallback = ReadRtfStream;
    SendMessageW(control, EM_STREAMIN, SF_RTF, reinterpret_cast<LPARAM>(&stream));
}

struct HelpDialogState {
    const Translation* translation = nullptr;
    std::filesystem::path background_path;
    HWND dialog = nullptr;
    HWND heading = nullptr;
    std::array<HWND, 7> tabs{};
    HWND text = nullptr;
    HWND close = nullptr;
    UINT dpi = 96;
    HFONT heading_font = nullptr;
    HFONT tab_font = nullptr;
    HFONT text_font = nullptr;
    HBRUSH background_brush = nullptr;
    HBRUSH panel_brush = nullptr;
    HBRUSH text_brush = nullptr;
    BackgroundImage background;
    RECT tabs_frame{};
    RECT body_frame{};
    std::vector<std::wstring> page_titles;
    std::vector<std::string> page_rtf;
    int selected_tab = 0;
};

void DestroyHelpResources(HelpDialogState& state) {
    if (state.heading_font) DeleteObject(state.heading_font);
    if (state.tab_font) DeleteObject(state.tab_font);
    if (state.text_font) DeleteObject(state.text_font);
    if (state.background_brush) DeleteObject(state.background_brush);
    if (state.panel_brush) DeleteObject(state.panel_brush);
    if (state.text_brush) DeleteObject(state.text_brush);
    state.background.Clear();
    state.heading_font = nullptr;
    state.tab_font = nullptr;
    state.text_font = nullptr;
    state.background_brush = nullptr;
    state.panel_brush = nullptr;
    state.text_brush = nullptr;
}

void CreateHelpResources(HelpDialogState& state) {
    state.dpi = GetDpiForWindow(state.dialog);
    if (!state.dpi) state.dpi = GetDpiForSystem();
    state.heading_font = CreateUiFont(state.dpi, 17, FW_SEMIBOLD);
    state.tab_font = CreateUiFont(state.dpi, 9, FW_SEMIBOLD);
    state.text_font = CreateUiFont(state.dpi, 10, FW_NORMAL);
    state.background_brush = CreateSolidBrush(ColorBackground());
    state.panel_brush = CreateSolidBrush(ColorPanel());
    state.text_brush = CreateSolidBrush(ColorPanel());
    LoadBackgroundImage(state.background_path, &state.background);
}

void SizeAndCenterHelpDialog(HelpDialogState& state) {
    CenterOverlayWindow(state.dialog, GetWindow(state.dialog, GW_OWNER),
                        Dip(state.dpi, 980), Dip(state.dpi, 680));
}

void LayoutHelpDialog(HelpDialogState& state) {
    RECT client{};
    GetClientRect(state.dialog, &client);
    const int margin = Dip(state.dpi, 22);
    const int heading_height = Dip(state.dpi, 36);
    const int button_height = Dip(state.dpi, 36);
    const int button_width = Dip(state.dpi, 104);
    const int tab_height = Dip(state.dpi, 36);
    const int tab_gap = Dip(state.dpi, 7);
    const int tabs_padding = Dip(state.dpi, 7);
    SetWindowPos(state.heading, nullptr, margin + Dip(state.dpi, 4),
                 Dip(state.dpi, 16),
                 std::max(10, static_cast<int>(client.right) - margin * 2),
                 heading_height, SWP_NOZORDER | SWP_NOACTIVATE);
    const int tabs_top = Dip(state.dpi, 64);
    const int tabs_width =
        std::max(10, static_cast<int>(client.right) - margin * 2);
    state.tabs_frame = {margin, tabs_top, margin + tabs_width,
                        tabs_top + tab_height};
    const int available_tab_width =
        std::max(20, tabs_width - tabs_padding * 2 -
                         tab_gap * (static_cast<int>(state.tabs.size()) - 1));
    std::vector<int> tab_widths(state.tabs.size(), 0);
    int natural_width_total = 0;
    HDC tab_dc = state.tabs.empty() ? nullptr : GetDC(state.tabs.front());
    HGDIOBJ old_tab_font = nullptr;
    if (tab_dc) {
        old_tab_font = SelectObject(tab_dc, state.tab_font);
        for (size_t i = 0; i < state.tabs.size(); ++i) {
            const std::wstring label = GetControlText(state.tabs[i]);
            SIZE text_size{};
            GetTextExtentPoint32W(tab_dc, label.c_str(),
                                  static_cast<int>(label.size()), &text_size);
            tab_widths[i] =
                std::max(Dip(state.dpi, 48), static_cast<int>(text_size.cx) +
                                                 Dip(state.dpi, 20));
            natural_width_total += tab_widths[i];
        }
        SelectObject(tab_dc, old_tab_font);
        ReleaseDC(state.tabs.front(), tab_dc);
    } else {
        std::fill(tab_widths.begin(), tab_widths.end(), 48);
        natural_width_total = 48 * static_cast<int>(tab_widths.size());
    }
    if (!tab_widths.empty()) {
        if (natural_width_total > available_tab_width) {
            int overflow = natural_width_total - available_tab_width;
            const int minimum_width = Dip(state.dpi, 44);
            while (overflow > 0) {
                bool changed = false;
                for (int& width : tab_widths) {
                    if (overflow == 0) break;
                    if (width > minimum_width) {
                        --width;
                        --overflow;
                        changed = true;
                    }
                }
                if (!changed) break;
            }
        } else {
            int extra = available_tab_width - natural_width_total;
            for (size_t i = 0; extra > 0; ++i, --extra) {
                ++tab_widths[i % tab_widths.size()];
            }
        }
    }
    int tab_x = margin + tabs_padding;
    for (size_t i = 0; i < state.tabs.size(); ++i) {
        SetWindowPos(state.tabs[i], nullptr, tab_x, tabs_top, tab_widths[i],
                     tab_height,
                     SWP_NOZORDER | SWP_NOACTIVATE);
        tab_x += tab_widths[i] + tab_gap;
    }

    const int body_top = tabs_top + tab_height + Dip(state.dpi, 14);
    const int body_bottom =
        static_cast<int>(client.bottom) - margin - button_height -
        Dip(state.dpi, 16);
    state.body_frame = {margin, body_top, margin + tabs_width,
                        std::max(body_top + Dip(state.dpi, 40), body_bottom)};
    const int body_padding = Dip(state.dpi, 9);
    SetWindowPos(state.text, HWND_TOP, state.body_frame.left + body_padding,
                 state.body_frame.top + body_padding,
                 std::max(10, static_cast<int>(state.body_frame.right -
                                               state.body_frame.left) -
                                  body_padding * 2),
                 std::max(10, static_cast<int>(state.body_frame.bottom -
                                               state.body_frame.top) -
                                  body_padding * 2),
                 SWP_NOACTIVATE);
    RECT text_client{};
    GetClientRect(state.text, &text_client);
    HDC text_dc = GetDC(state.text);
    const int text_dpi = std::max(1, GetDeviceCaps(text_dc, LOGPIXELSX));
    const int target_width =
        std::max(1, MulDiv(static_cast<int>(text_client.right), 1440, text_dpi));
    SendMessageW(state.text, EM_SETTARGETDEVICE,
                 reinterpret_cast<WPARAM>(text_dc),
                 target_width);
    ReleaseDC(state.text, text_dc);
    SendMessageW(state.text, EM_SETOPTIONS, ECOOP_AND,
                 static_cast<LPARAM>(~ECO_AUTOHSCROLL));
    SetWindowPos(state.close, nullptr,
                 static_cast<int>(client.right) - margin - button_width,
                 static_cast<int>(client.bottom) - margin - button_height,
                 button_width, button_height, SWP_NOZORDER | SWP_NOACTIVATE);
}

void UpdateHelpPage(HelpDialogState& state) {
    const int selected = state.selected_tab;
    if (selected >= 0 &&
        selected < static_cast<int>(state.page_rtf.size())) {
        SetRichText(state.text, state.page_rtf[selected]);
        RECT text_client{};
        GetClientRect(state.text, &text_client);
        HDC text_dc = GetDC(state.text);
        const int text_dpi = std::max(1, GetDeviceCaps(text_dc, LOGPIXELSX));
        const int target_width =
            std::max(1, MulDiv(static_cast<int>(text_client.right), 1440, text_dpi));
        SendMessageW(state.text, EM_SETTARGETDEVICE,
                     reinterpret_cast<WPARAM>(text_dc),
                     target_width);
        ReleaseDC(state.text, text_dc);
        SendMessageW(state.text, EM_SETBKGNDCOLOR, 0,
                     static_cast<LPARAM>(ColorPanel()));
        SendMessageW(state.text, EM_SETMARGINS,
                     EC_LEFTMARGIN | EC_RIGHTMARGIN,
                     MAKELPARAM(Dip(state.dpi, 22), Dip(state.dpi, 22)));
        SendMessageW(state.text, EM_SETSEL, 0, 0);
        SendMessageW(state.text, EM_SCROLLCARET, 0, 0);
        InvalidateRect(state.text, nullptr, FALSE);
    }
}

void DrawHelpButton(const DRAWITEMSTRUCT& item, const HelpDialogState& state,
                    std::wstring_view text, bool selected) {
    const bool disabled = (item.itemState & ODS_DISABLED) != 0;
    const bool close = item.CtlID == IDOK;
    const bool hot = IsHovered(item.hwndItem, item.itemState);
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;
    if (close) {
        RECT parent_client{};
        RECT control_in_parent{};
        HWND parent = GetParent(item.hwndItem);
        GetClientRect(parent, &parent_client);
        GetWindowRect(item.hwndItem, &control_in_parent);
        MapWindowPoints(HWND_DESKTOP, parent,
                        reinterpret_cast<POINT*>(&control_in_parent), 2);
        FillBackgroundSegment(item.hDC, item.rcItem, control_in_parent,
                              parent_client, state.background);
    } else {
        FillRect(item.hDC, &item.rcItem, state.panel_brush);
    }

    COLORREF fill = close ? (hot ? ColorPanelHover() : ColorControl())
                          : (selected || hot ? ColorPanelHover()
                                             : ColorPanel());
    if (pressed) fill = Blend(fill, -18);
    if (disabled) fill = RGB(35, 40, 52);
    DrawRoundedSurface(item.hDC, item.rcItem, fill, fill, state.dpi, 5, false);

    SetBkMode(item.hDC, TRANSPARENT);
    SetTextColor(item.hDC, disabled ? ColorMuted() : ColorText());
    const HGDIOBJ old_font = SelectObject(item.hDC, state.tab_font);
    RECT text_rect = item.rcItem;
    InflateRect(&text_rect, -Dip(state.dpi, 4), 0);
    DrawTextW(item.hDC, std::wstring(text).c_str(), -1, &text_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                  DT_NOPREFIX);
    SelectObject(item.hDC, old_font);
}

INT_PTR CALLBACK HelpDialogProc(HWND dialog, UINT message, WPARAM wparam,
                                LPARAM lparam) {
    auto* state =
        reinterpret_cast<HelpDialogState*>(GetWindowLongPtrW(dialog, DWLP_USER));
    if (message == WM_INITDIALOG) {
        state = reinterpret_cast<HelpDialogState*>(lparam);
        state->dialog = dialog;
        SetWindowLongPtrW(dialog, DWLP_USER, lparam);
        SetWindowLongPtrW(dialog, GWL_EXSTYLE,
                          GetWindowLongPtrW(dialog, GWL_EXSTYLE) |
                              WS_EX_COMPOSITED);
        ConfigureOverlayWindow(dialog);
        SetDarkWindowFrame(dialog);
        CreateHelpResources(*state);

        LoadLibraryW(L"Msftedit.dll");
        state->heading = CreateChild(
            dialog, L"STATIC",
            Tr(*state->translation, "help.guide_title",
               L"ReShade Launcher - User Guide").c_str(),
            SS_LEFT | SS_NOPREFIX | SS_CENTERIMAGE, 0, WS_EX_TRANSPARENT);
        state->text = CreateChild(
            dialog, MSFTEDIT_CLASS, L"",
            WS_TABSTOP | WS_CLIPSIBLINGS | WS_VSCROLL | ES_MULTILINE |
                ES_READONLY | ES_AUTOVSCROLL | ES_LEFT,
            0, WS_EX_COMPOSITED);
        state->close = CreateChild(
            dialog, L"BUTTON",
            Tr(*state->translation, "dialog.close", L"Close").c_str(),
            WS_TABSTOP | BS_OWNERDRAW, IDOK);
        SendMessageW(dialog, DM_SETDEFID, IDOK, 0);
        ApplyDarkTheme(state->heading);
        ApplyDarkTheme(state->text);
        ApplyDarkTheme(state->close);
        EnableHoverTracking(state->close);
        SendMessageW(state->heading, WM_SETFONT,
                     reinterpret_cast<WPARAM>(state->heading_font), TRUE);
        SendMessageW(state->text, WM_SETFONT,
                     reinterpret_cast<WPARAM>(state->text_font), TRUE);
        SendMessageW(state->close, WM_SETFONT,
                     reinterpret_cast<WPARAM>(state->text_font), TRUE);
        SendMessageW(state->text, EM_SETMARGINS,
                     EC_LEFTMARGIN | EC_RIGHTMARGIN, MAKELPARAM(12, 12));
        SendMessageW(state->text, EM_SETEDITSTYLE, SES_EXTENDBACKCOLOR,
                     SES_EXTENDBACKCOLOR);
        SendMessageW(state->text, EM_SETTARGETDEVICE, 0, 0);
        SendMessageW(state->text, EM_SETBKGNDCOLOR, 0,
                     static_cast<LPARAM>(ColorPanel()));

        const std::array<std::pair<std::string_view, std::string_view>, 7> pages = {{
            {"help.tab.config_title", "help.tab.config"},
            {"help.tab.launch_title", "help.tab.launch"},
            {"help.tab.creation_title", "help.tab.creation"},
            {"help.tab.reshade_title", "help.tab.reshade"},
            {"help.tab.process_title", "help.tab.process"},
            {"help.tab.tray_title", "help.tab.tray"},
            {"help.tab.other_title", "help.tab.other"},
        }};
        for (size_t index = 0; index < pages.size(); ++index) {
            const auto& [title_key, body_key] = pages[index];
            const std::wstring title =
                Tr(*state->translation, title_key, L"Help");
            state->page_titles.push_back(title);
            state->tabs[index] = CreateChild(
                dialog, L"BUTTON", title.c_str(),
                WS_TABSTOP | WS_CLIPSIBLINGS | BS_OWNERDRAW,
                kHelpTabBase + static_cast<int>(index));
            ApplyDarkTheme(state->tabs[index]);
            EnableHoverTracking(state->tabs[index]);
            SendMessageW(state->tabs[index], WM_SETFONT,
                         reinterpret_cast<WPARAM>(state->tab_font), TRUE);
            state->page_rtf.push_back(HtmlToRtf(
                state->translation->GetW(
                    body_key,
                    L"Help content is not available for this language.")));
        }
        state->selected_tab = 0;
        UpdateHelpPage(*state);
        SizeAndCenterHelpDialog(*state);
        LayoutHelpDialog(*state);
        SetFocus(state->close);
        return FALSE;
    }
    if (!state) return FALSE;
    switch (message) {
        case WM_PAINT: {
            PAINTSTRUCT paint{};
            HDC dc = BeginPaint(dialog, &paint);
            RECT client{};
            GetClientRect(dialog, &client);
            FillRect(dc, &client, state->background_brush);
            DrawBackgroundCover(dc, client, state->background, 150);
            DrawRoundedSurface(dc, state->tabs_frame, ColorPanel(),
                               ColorBorder(), state->dpi, 7);
            DrawRoundedSurface(dc, state->body_frame, ColorPanel(),
                               ColorBorder(), state->dpi, 7);
            EndPaint(dialog, &paint);
            return TRUE;
        }
        case WM_ERASEBKGND:
            return TRUE;
        case WM_SIZE:
            LayoutHelpDialog(*state);
            RefreshOverlayRegion(dialog);
            return TRUE;
        case WM_DPICHANGED: {
            DestroyHelpResources(*state);
            state->dpi = HIWORD(wparam);
            state->heading_font = CreateUiFont(state->dpi, 17, FW_SEMIBOLD);
            state->tab_font = CreateUiFont(state->dpi, 9, FW_SEMIBOLD);
            state->text_font = CreateUiFont(state->dpi, 10, FW_NORMAL);
            state->background_brush = CreateSolidBrush(ColorBackground());
            state->panel_brush = CreateSolidBrush(ColorPanel());
            state->text_brush = CreateSolidBrush(ColorPanel());
            LoadBackgroundImage(state->background_path, &state->background);
            SendMessageW(state->heading, WM_SETFONT,
                         reinterpret_cast<WPARAM>(state->heading_font), TRUE);
            for (HWND tab : state->tabs) {
                SendMessageW(tab, WM_SETFONT,
                             reinterpret_cast<WPARAM>(state->tab_font), TRUE);
            }
            SendMessageW(state->text, WM_SETFONT,
                         reinterpret_cast<WPARAM>(state->text_font), TRUE);
            SendMessageW(state->close, WM_SETFONT,
                         reinterpret_cast<WPARAM>(state->text_font), TRUE);
            SizeAndCenterHelpDialog(*state);
            LayoutHelpDialog(*state);
            return TRUE;
        }
        case WM_DRAWITEM: {
            const auto* item = reinterpret_cast<const DRAWITEMSTRUCT*>(lparam);
            if (!item || item->CtlType != ODT_BUTTON) break;
            if (item->CtlID == IDOK) {
                DrawHelpButton(
                    *item, *state,
                    Tr(*state->translation, "dialog.close", L"Close"), false);
                return TRUE;
            }
            const int index = static_cast<int>(item->CtlID) - kHelpTabBase;
            if (index >= 0 &&
                index < static_cast<int>(state->page_titles.size())) {
                DrawHelpButton(*item, *state, state->page_titles[index],
                               index == state->selected_tab);
                return TRUE;
            }
            break;
        }
        case WM_CTLCOLORDLG:
            return reinterpret_cast<INT_PTR>(state->background_brush);
        case WM_CTLCOLORSTATIC:
        case WM_CTLCOLOREDIT:
        case WM_CTLCOLORLISTBOX: {
            HDC dc = reinterpret_cast<HDC>(wparam);
            if (reinterpret_cast<HWND>(lparam) == state->text) {
                SetBkColor(dc, ColorPanel());
                SetTextColor(dc, ColorText());
                return reinterpret_cast<INT_PTR>(state->text_brush);
            }
            const bool heading =
                reinterpret_cast<HWND>(lparam) == state->heading;
            SetBkMode(dc, TRANSPARENT);
            SetTextColor(dc, ColorText());
            return reinterpret_cast<INT_PTR>(
                heading ? GetStockObject(HOLLOW_BRUSH) : state->panel_brush);
        }
        case WM_COMMAND:
            if (LOWORD(wparam) == IDOK || LOWORD(wparam) == IDCANCEL) {
                EndDialog(dialog, IDOK);
                return TRUE;
            }
            if (LOWORD(wparam) >= kHelpTabBase &&
                LOWORD(wparam) < kHelpTabBase + 7) {
                state->selected_tab =
                    static_cast<int>(LOWORD(wparam)) - kHelpTabBase;
                for (HWND tab : state->tabs) InvalidateRect(tab, nullptr, FALSE);
                UpdateHelpPage(*state);
                return TRUE;
            }
            break;
        case WM_CLOSE:
            EndDialog(dialog, IDOK);
            return TRUE;
        case WM_NCDESTROY:
            DestroyHelpResources(*state);
            SetWindowLongPtrW(dialog, DWLP_USER, 0);
            break;
    }
    return FALSE;
}

const wchar_t* YesNoLabel(bool yes) {
    const WORD language = GetUserDefaultUILanguage();
    switch (PRIMARYLANGID(language)) {
        case LANG_CHINESE: return yes ? L"是" : L"否";
        case LANG_JAPANESE: return yes ? L"はい" : L"いいえ";
        case LANG_KOREAN: return yes ? L"예" : L"아니요";
        case LANG_FRENCH: return yes ? L"Oui" : L"Non";
        case LANG_GERMAN: return yes ? L"Ja" : L"Nein";
        case LANG_SPANISH: return yes ? L"Sí" : L"No";
        case LANG_PORTUGUESE: return yes ? L"Sim" : L"Não";
        case LANG_RUSSIAN: return yes ? L"Да" : L"Нет";
        default: return yes ? L"Yes" : L"No";
    }
}

const wchar_t* OkLabel() {
    const WORD language = GetUserDefaultUILanguage();
    switch (PRIMARYLANGID(language)) {
        case LANG_CHINESE: return L"确定";
        case LANG_JAPANESE: return L"OK";
        case LANG_KOREAN: return L"확인";
        case LANG_FRENCH:
        case LANG_GERMAN:
        case LANG_PORTUGUESE: return L"OK";
        case LANG_SPANISH: return L"Aceptar";
        case LANG_RUSSIAN: return L"ОК";
        default: return L"OK";
    }
}

struct MessageDialogState {
    HWND dialog = nullptr;
    HWND primary = nullptr;
    HWND secondary = nullptr;
    HWND tertiary = nullptr;
    HWND details = nullptr;
    std::wstring title;
    std::wstring message;
    std::wstring details_text;
    std::wstring primary_label;
    std::wstring secondary_label;
    std::wstring tertiary_label;
    bool confirmation = false;
    bool error = false;
    int message_height = 104;
    UINT primary_id = IDOK;
    UINT secondary_id = IDNO;
    UINT tertiary_id = IDCANCEL;
    UINT dpi = 96;
    HFONT title_font = nullptr;
    HFONT body_font = nullptr;
    HFONT button_font = nullptr;
    HBRUSH background_brush = nullptr;
    HBRUSH panel_brush = nullptr;
    BackgroundImage background;
    std::filesystem::path background_path;
    RECT card{};
};

void DestroyMessageDialogResources(MessageDialogState& state) {
    if (state.title_font) DeleteObject(state.title_font);
    if (state.body_font) DeleteObject(state.body_font);
    if (state.button_font) DeleteObject(state.button_font);
    if (state.background_brush) DeleteObject(state.background_brush);
    if (state.panel_brush) DeleteObject(state.panel_brush);
    state.background.Clear();
    state.title_font = nullptr;
    state.body_font = nullptr;
    state.button_font = nullptr;
    state.background_brush = nullptr;
    state.panel_brush = nullptr;
}

void CreateMessageDialogResources(MessageDialogState& state) {
    DestroyMessageDialogResources(state);
    state.dpi = GetDpiForWindow(state.dialog);
    if (!state.dpi) state.dpi = GetDpiForSystem();
    state.title_font = CreateUiFont(state.dpi, 13, FW_SEMIBOLD);
    state.body_font = CreateUiFont(state.dpi, 10, FW_NORMAL);
    state.button_font = CreateUiFont(state.dpi, 10, FW_SEMIBOLD);
    state.background_brush = CreateSolidBrush(ColorBackground());
    state.panel_brush = CreateSolidBrush(ColorPanel());
    if (state.background_path.empty()) {
        state.background_path = DefaultDialogBackground();
    }
    LoadBackgroundImage(state.background_path, &state.background);
}

void SizeAndCenterMessageDialog(MessageDialogState& state) {
    const int target_width = state.details_text.empty() ? 560 : 720;
    int target_height = state.details_text.empty() ? 268 : 540;
    if (state.details_text.empty()) {
        HDC dc = GetDC(state.dialog);
        if (dc) {
            const HGDIOBJ previous = SelectObject(dc, state.body_font);
            RECT measured{0, 0, Dip(state.dpi, 460), 0};
            DrawTextW(dc, state.message.c_str(), -1, &measured,
                      DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX |
                          DT_EDITCONTROL);
            SelectObject(dc, previous);
            ReleaseDC(state.dialog, dc);
            state.message_height =
                std::clamp(static_cast<int>(measured.bottom), Dip(state.dpi, 48),
                           Dip(state.dpi, 360));
            target_height =
                std::max(target_height,
                         state.message_height + Dip(state.dpi, 148));
        }
    } else {
        state.message_height = 86;
    }
    CenterOverlayWindow(state.dialog, GetWindow(state.dialog, GW_OWNER),
                        Dip(state.dpi, target_width),
                        Dip(state.dpi, target_height));
}

void LayoutMessageDialog(MessageDialogState& state) {
    RECT client{};
    GetClientRect(state.dialog, &client);
    const int button_width = Dip(state.dpi, 116);
    const int button_height = Dip(state.dpi, 34);
    const int card_inset = Dip(state.dpi, 12);
    const int button_margin = Dip(state.dpi, 20);
    const int gap = Dip(state.dpi, 10);
    state.card = {card_inset, card_inset, client.right - card_inset,
                  client.bottom - card_inset};
    const int primary_x =
        state.card.right - button_margin - button_width;
    const int button_y =
        state.card.bottom - button_margin - button_height;
    SetWindowPos(state.primary, nullptr, primary_x,
                 button_y,
                 button_width, button_height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    if (state.secondary) {
        SetWindowPos(
            state.secondary, nullptr,
            primary_x - (button_width + gap),
            button_y,
            button_width, button_height,
            SWP_NOZORDER | SWP_NOACTIVATE);
    }
    if (state.tertiary) {
        SetWindowPos(
            state.tertiary, nullptr,
            primary_x - (button_width + gap) * 2,
            button_y,
            button_width, button_height,
            SWP_NOZORDER | SWP_NOACTIVATE);
    }
    if (state.details) {
        const int details_top = state.card.top + Dip(state.dpi, 158);
        const int details_bottom =
            button_y - Dip(state.dpi, 14);
        SetWindowPos(state.details, nullptr,
                     state.card.left + button_margin, details_top,
                     std::max(10, static_cast<int>(state.card.right -
                                                  state.card.left) -
                                      button_margin * 2),
                     std::max(10, details_bottom - details_top),
                     SWP_NOZORDER | SWP_NOACTIVATE);
    }
}

void ApplyMessageDialogFonts(MessageDialogState& state) {
    SendMessageW(state.primary, WM_SETFONT,
                 reinterpret_cast<WPARAM>(state.button_font), TRUE);
    if (state.secondary) {
        SendMessageW(state.secondary, WM_SETFONT,
                     reinterpret_cast<WPARAM>(state.button_font), TRUE);
    }
    if (state.tertiary) {
        SendMessageW(state.tertiary, WM_SETFONT,
                     reinterpret_cast<WPARAM>(state.button_font), TRUE);
    }
}

void DrawMessageButton(const DRAWITEMSTRUCT& item,
                       const MessageDialogState& state, bool primary) {
    const bool disabled = (item.itemState & ODS_DISABLED) != 0;
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;
    const bool hot = IsHovered(item.hwndItem, item.itemState);
    COLORREF fill = primary
                        ? (hot ? Blend(ColorAccent(), -10) : ColorAccent())
                        : (pressed || hot ? ColorPanelHover() : ColorPanel());
    COLORREF border = primary ? fill : ColorBorder();
    COLORREF text = primary ? RGB(8, 22, 12) : ColorText();
    if (pressed) fill = Blend(fill, -12);
    if (primary) border = fill;
    if (disabled) {
        fill = RGB(35, 40, 52);
        border = RGB(62, 68, 82);
        text = RGB(132, 139, 155);
    }
    FillRect(item.hDC, &item.rcItem, state.panel_brush);
    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, std::max(1, Dip(state.dpi, 1)),
                         border);
    const HGDIOBJ old_brush = SelectObject(item.hDC, brush);
    const HGDIOBJ old_pen = SelectObject(item.hDC, pen);
    RoundRect(item.hDC, item.rcItem.left, item.rcItem.top,
              item.rcItem.right, item.rcItem.bottom,
              Dip(state.dpi, 10), Dip(state.dpi, 10));
    SelectObject(item.hDC, old_pen);
    SelectObject(item.hDC, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);

    wchar_t label[128]{};
    GetWindowTextW(item.hwndItem, label,
                   static_cast<int>(std::size(label)));
    SetBkMode(item.hDC, TRANSPARENT);
    SetTextColor(item.hDC, text);
    const HGDIOBJ old_font =
        SelectObject(item.hDC, state.button_font);
    RECT text_rect = item.rcItem;
    DrawTextW(item.hDC, label, -1, &text_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    SelectObject(item.hDC, old_font);
}

void PaintMessageDialog(MessageDialogState& state) {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(state.dialog, &paint);
    RECT client{};
    GetClientRect(state.dialog, &client);
    FillRect(dc, &client, state.background_brush);
    DrawBackgroundCover(dc, client, state.background, 150);
    DrawRoundedSurface(dc, state.card, ColorPanel(), ColorBorder(), state.dpi, 8);

    SetBkMode(dc, TRANSPARENT);
    HGDIOBJ old_font = SelectObject(dc, state.title_font);
    const int content_left = state.card.left + Dip(state.dpi, 24);
    const int content_right = state.card.right - Dip(state.dpi, 24);
    HBRUSH accent_brush = CreateSolidBrush(ColorAccent());
    RECT accent{content_left, state.card.top + Dip(state.dpi, 17),
                content_left + Dip(state.dpi, 3),
                state.card.top + Dip(state.dpi, 47)};
    FillRect(dc, &accent, accent_brush);
    DeleteObject(accent_brush);

    SetTextColor(dc, ColorText());
    RECT title_rect{content_left + Dip(state.dpi, 12),
                    state.card.top + Dip(state.dpi, 14),
                    content_right, state.card.top + Dip(state.dpi, 50)};
    DrawTextW(dc, state.title.c_str(), -1, &title_rect,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
                  DT_END_ELLIPSIS);

    const int icon_size = Dip(state.dpi, 38);
    RECT icon{content_left, state.card.top + Dip(state.dpi, 62),
              content_left + icon_size,
              state.card.top + Dip(state.dpi, 62) + icon_size};
    const COLORREF icon_fill =
        state.error ? RGB(210, 73, 62) : ColorAccent();
    DrawRoundedSurface(dc, icon, icon_fill, icon_fill, state.dpi, 6, false);
    const wchar_t* symbol =
        state.error ? L"!" : (state.confirmation ? L"?" : L"i");
    SetTextColor(dc, RGB(8, 22, 12));
    SelectObject(dc, state.title_font);
    DrawTextW(dc, symbol, -1, &icon,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

    SetTextColor(dc, ColorText());
    SelectObject(dc, state.body_font);
    RECT message_rect{icon.right + Dip(state.dpi, 16),
                      icon.top - Dip(state.dpi, 2), content_right,
                      icon.top - Dip(state.dpi, 2) + state.message_height};
    DrawTextW(dc, state.message.c_str(), -1, &message_rect,
              DT_LEFT | DT_TOP | DT_WORDBREAK | DT_NOPREFIX |
                  DT_EDITCONTROL);
    SelectObject(dc, old_font);
    EndPaint(state.dialog, &paint);
}

INT_PTR CALLBACK MessageDialogProc(HWND dialog, UINT message,
                                   WPARAM wparam, LPARAM lparam) {
    auto* state = reinterpret_cast<MessageDialogState*>(
        GetWindowLongPtrW(dialog, DWLP_USER));
    if (message == WM_INITDIALOG) {
        state = reinterpret_cast<MessageDialogState*>(lparam);
        state->dialog = dialog;
        SetWindowLongPtrW(dialog, DWLP_USER, lparam);
        ConfigureOverlayWindow(dialog);
        SetDarkWindowFrame(dialog);
        CreateMessageDialogResources(*state);
        state->primary = CreateButton(
            dialog, state->primary_label, state->primary_id);
        if (state->primary_label.empty()) {
            SetWindowTextW(
                state->primary,
                state->confirmation ? YesNoLabel(true) : OkLabel());
        }
        if (!state->secondary_label.empty()) {
            state->secondary = CreateButton(
                dialog,
                state->secondary_label.empty()
                    ? YesNoLabel(false)
                    : state->secondary_label,
                state->secondary_id);
        }
        if (!state->tertiary_label.empty()) {
            state->tertiary = CreateButton(
                dialog, state->tertiary_label, state->tertiary_id);
        }
        if (!state->details_text.empty()) {
            LoadLibraryW(L"Msftedit.dll");
            state->details = CreateChild(
                dialog, MSFTEDIT_CLASS, L"",
                WS_TABSTOP | WS_CLIPSIBLINGS | WS_VSCROLL | ES_MULTILINE |
                    ES_READONLY | ES_AUTOVSCROLL | ES_LEFT);
            ApplyDarkTheme(state->details);
            SetWindowTextW(state->details, state->details_text.c_str());
            SendMessageW(state->details, EM_SETBKGNDCOLOR, 0,
                         static_cast<LPARAM>(ColorInput()));
            SendMessageW(state->details, EM_SETEDITSTYLE,
                         SES_EXTENDBACKCOLOR, SES_EXTENDBACKCOLOR);
            SendMessageW(state->details, EM_SETMARGINS,
                         EC_LEFTMARGIN | EC_RIGHTMARGIN,
                         MAKELPARAM(Dip(state->dpi, 10),
                                    Dip(state->dpi, 10)));
            SendMessageW(state->details, WM_SETFONT,
                         reinterpret_cast<WPARAM>(state->body_font), TRUE);
        }
        ApplyMessageDialogFonts(*state);
        SizeAndCenterMessageDialog(*state);
        LayoutMessageDialog(*state);
        SetFocus(state->primary);
        return FALSE;
    }
    if (!state) return FALSE;
    switch (message) {
        case WM_PAINT:
            PaintMessageDialog(*state);
            return TRUE;
        case WM_ERASEBKGND:
            return TRUE;
        case WM_SIZE:
            LayoutMessageDialog(*state);
            RefreshOverlayRegion(dialog);
            return TRUE;
        case WM_DPICHANGED: {
            CreateMessageDialogResources(*state);
            ApplyMessageDialogFonts(*state);
            if (state->details) {
                SendMessageW(state->details, WM_SETFONT,
                             reinterpret_cast<WPARAM>(state->body_font), TRUE);
                SendMessageW(state->details, EM_SETBKGNDCOLOR, 0,
                             static_cast<LPARAM>(ColorInput()));
            }
            SizeAndCenterMessageDialog(*state);
            LayoutMessageDialog(*state);
            InvalidateRect(dialog, nullptr, FALSE);
            return TRUE;
        }
        case WM_DRAWITEM: {
            const auto* item =
                reinterpret_cast<const DRAWITEMSTRUCT*>(lparam);
            if (item && item->hwndItem == state->primary) {
                DrawMessageButton(*item, *state, true);
                return TRUE;
            }
            if (item && (item->hwndItem == state->secondary ||
                         item->hwndItem == state->tertiary)) {
                DrawMessageButton(*item, *state, false);
                return TRUE;
            }
            break;
        }
        case WM_CTLCOLORDLG:
            return reinterpret_cast<INT_PTR>(
                state->background_brush);
        case WM_COMMAND:
            if (LOWORD(wparam) == state->primary_id ||
                LOWORD(wparam) == state->secondary_id ||
                LOWORD(wparam) == state->tertiary_id ||
                LOWORD(wparam) == IDCANCEL) {
                EndDialog(dialog, LOWORD(wparam));
                return TRUE;
            }
            break;
        case WM_CLOSE:
            EndDialog(dialog, state->tertiary_label.empty()
                                  ? (state->secondary_label.empty()
                                         ? state->primary_id
                                         : state->secondary_id)
                                  : state->tertiary_id);
            return TRUE;
        case WM_NCDESTROY:
            DestroyMessageDialogResources(*state);
            SetWindowLongPtrW(dialog, DWLP_USER, 0);
            break;
    }
    return FALSE;
}

INT_PTR ShowMessageDialog(HWND owner, std::wstring_view title,
                          std::wstring_view message, bool confirmation,
                          bool error) {
    MessageDialogState state;
    state.title = title;
    state.message = message;
    state.confirmation = confirmation;
    state.error = error;
    state.primary_label =
        confirmation ? YesNoLabel(true) : OkLabel();
    if (confirmation) {
        state.secondary_label = YesNoLabel(false);
    }
    auto dialog_template =
        MakeDialogTemplate(std::wstring(title).c_str(), false);
    return DialogBoxIndirectParamW(
        GetModuleHandleW(nullptr),
        reinterpret_cast<LPCDLGTEMPLATEW>(dialog_template.data()), owner,
        MessageDialogProc, reinterpret_cast<LPARAM>(&state));
}

}  // namespace

std::optional<std::filesystem::path> PickFile(
    HWND owner, const wchar_t* title, const COMDLG_FILTERSPEC* filters,
    UINT filter_count) {
    IFileOpenDialog* dialog = nullptr;
    if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog)))) {
        return std::nullopt;
    }
    dialog->SetTitle(title);
    dialog->SetFileTypes(filter_count, filters);
    FILEOPENDIALOGOPTIONS options{};
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST);
    std::optional<std::filesystem::path> result;
    if (SUCCEEDED(dialog->Show(owner))) {
        IShellItem* item = nullptr;
        if (SUCCEEDED(dialog->GetResult(&item))) {
            PWSTR raw = nullptr;
            if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw))) {
                result = raw;
                CoTaskMemFree(raw);
            }
            item->Release();
        }
    }
    dialog->Release();
    return result;
}

std::vector<std::filesystem::path> PickFiles(
    HWND owner, const wchar_t* title, const COMDLG_FILTERSPEC* filters,
    UINT filter_count) {
    std::vector<std::filesystem::path> results;
    IFileOpenDialog* dialog = nullptr;
    if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog)))) {
        return results;
    }
    dialog->SetTitle(title);
    dialog->SetFileTypes(filter_count, filters);
    FILEOPENDIALOGOPTIONS options{};
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST |
                       FOS_ALLOWMULTISELECT);
    if (SUCCEEDED(dialog->Show(owner))) {
        IShellItemArray* items = nullptr;
        if (SUCCEEDED(dialog->GetResults(&items))) {
            DWORD count = 0;
            items->GetCount(&count);
            for (DWORD index = 0; index < count; ++index) {
                IShellItem* item = nullptr;
                if (SUCCEEDED(items->GetItemAt(index, &item))) {
                    PWSTR raw = nullptr;
                    if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw))) {
                        results.emplace_back(raw);
                        CoTaskMemFree(raw);
                    }
                    item->Release();
                }
            }
            items->Release();
        }
    }
    dialog->Release();
    return results;
}

std::optional<std::filesystem::path> PickFolder(HWND owner, const wchar_t* title) {
    IFileOpenDialog* dialog = nullptr;
    if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog)))) {
        return std::nullopt;
    }
    dialog->SetTitle(title);
    FILEOPENDIALOGOPTIONS options{};
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
    std::optional<std::filesystem::path> result;
    if (SUCCEEDED(dialog->Show(owner))) {
        IShellItem* item = nullptr;
        if (SUCCEEDED(dialog->GetResult(&item))) {
            PWSTR raw = nullptr;
            if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw))) {
                result = raw;
                CoTaskMemFree(raw);
            }
            item->Release();
        }
    }
    dialog->Release();
    return result;
}

bool Confirm(HWND owner, std::wstring_view title, std::wstring_view message) {
    return ShowMessageDialog(owner, title, message, true, false) ==
           IDOK;
}

void ShowInfo(HWND owner, std::wstring_view title, std::wstring_view message) {
    ShowMessageDialog(owner, title, message, false, false);
}

void ShowError(HWND owner, std::wstring_view title, std::wstring_view message) {
    ShowMessageDialog(owner, title, message, false, true);
}

void ShowDetails(HWND owner, std::wstring_view title,
                 std::wstring_view message, std::wstring_view details,
                 bool error) {
    MessageDialogState state;
    state.title = title;
    state.message = message;
    state.details_text = details;
    state.error = error;
    state.primary_label = OkLabel();
    auto dialog_template =
        MakeDialogTemplate(std::wstring(title).c_str(), false);
    DialogBoxIndirectParamW(
        GetModuleHandleW(nullptr),
        reinterpret_cast<LPCDLGTEMPLATEW>(dialog_template.data()), owner,
        MessageDialogProc, reinterpret_cast<LPARAM>(&state));
}

int ShowChoiceDialog(HWND owner, std::wstring_view title,
                     std::wstring_view message,
                     std::wstring_view primary_label,
                     std::wstring_view secondary_label,
                     std::wstring_view cancel_label) {
    constexpr UINT kPrimaryId = 1001;
    constexpr UINT kSecondaryId = 1002;
    MessageDialogState state;
    state.title = title;
    state.message = message;
    state.primary_label = primary_label;
    state.secondary_label = secondary_label;
    state.tertiary_label = cancel_label;
    state.primary_id = kPrimaryId;
    state.secondary_id = kSecondaryId;
    state.tertiary_id = IDCANCEL;
    auto dialog_template =
        MakeDialogTemplate(std::wstring(title).c_str(), false);
    return static_cast<int>(DialogBoxIndirectParamW(
        GetModuleHandleW(nullptr),
        reinterpret_cast<LPCDLGTEMPLATEW>(dialog_template.data()), owner,
        MessageDialogProc, reinterpret_cast<LPARAM>(&state)));
}

std::optional<ProfileEditResult> EditProfile(
    HWND owner, const Translation& translation, std::string_view config_name,
    const Json& config, std::string_view display_name,
    std::string_view custom_icon, const std::filesystem::path& background) {
    ProfileDialogState state;
    state.translation = &translation;
    state.config = config;
    state.config_name = std::string(config_name);
    state.display_name = std::string(display_name);
    state.custom_icon = std::string(custom_icon);
    state.background_path = background;
    const std::wstring title = ProfileTitle(translation, config_name);
    auto dialog_template = MakeDialogTemplate(title.c_str());
    const INT_PTR result = DialogBoxIndirectParamW(
        GetModuleHandleW(nullptr),
        reinterpret_cast<LPCDLGTEMPLATEW>(dialog_template.data()), owner,
        ProfileDialogProc, reinterpret_cast<LPARAM>(&state));
    if (result != IDOK) {
        return std::nullopt;
    }
    return state.result;
}

void ShowHelp(HWND owner, const Translation& translation,
              const std::filesystem::path& background) {
    HelpDialogState state;
    state.translation = &translation;
    state.background_path = background;
    const std::wstring title =
        Tr(translation, "help.title", L"Help");
    auto dialog_template = MakeDialogTemplate(title.c_str(), false);
    DialogBoxIndirectParamW(
        GetModuleHandleW(nullptr),
        reinterpret_cast<LPCDLGTEMPLATEW>(dialog_template.data()), owner,
        HelpDialogProc, reinterpret_cast<LPARAM>(&state));
}

std::string HelpText(const Translation& translation) {
    return translation.Get(
        "help.cxx.summary",
        "Use the config selector to load a game, then press Launch. Add Game supports "
        "XXMI, built-in, game-only and custom DLL modes. The shader switch selects the "
        "bundled lite pack or downloads the full pack from GitHub. Update checks the "
        "latest GitHub release and installs it with the standard installer. Closing the "
        "window hides the launcher to the tray.");
}

}  // namespace rs
