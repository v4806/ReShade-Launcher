#include "ui/main_window.h"

#include <d2d1helper.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <windowsx.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <exception>
#include <sstream>

#include "ui/dialogs.h"
#include "ui/overlay_window.h"

namespace rs {
namespace {

constexpr wchar_t kWindowClass[] = L"ReShadeLauncherCxxWindow";
constexpr UINT kLaunchDone = WM_APP + 10;
constexpr UINT kGameExited = WM_APP + 11;
constexpr UINT kToggleWindow = WM_APP + 12;
constexpr UINT kTrayCallback = WM_APP + 13;
constexpr UINT kModPresetDone = WM_APP + 21;
constexpr UINT kXXMIScanDone = WM_APP + 22;
constexpr UINT kTimerWindow = 1;
constexpr UINT kTimerGif = 2;
constexpr int kTrayExit = 40001;
constexpr int kTrayShow = 40002;
constexpr int kTrayMods = 40003;
constexpr int kTrayModPresetAll = 40004;
constexpr int kTrayModPresetSelect = 40005;

D2D1_COLOR_F ColorBackground() {
    return D2D1::ColorF(0.035f, 0.045f, 0.09f, 1.0f);
}
D2D1_COLOR_F ColorPanel() {
    return D2D1::ColorF(0.09f, 0.12f, 0.22f, 0.92f);
}
D2D1_COLOR_F ColorPanelHover() {
    return D2D1::ColorF(0.10f, 0.26f, 0.45f, 0.98f);
}
D2D1_COLOR_F ColorAccent() {
    return D2D1::ColorF(0.36f, 1.0f, 0.28f, 1.0f);
}
D2D1_COLOR_F ColorText() {
    return D2D1::ColorF(0.95f, 0.96f, 1.0f, 1.0f);
}
D2D1_COLOR_F ColorMuted() {
    return D2D1::ColorF(0.68f, 0.72f, 0.85f, 1.0f);
}

template <typename T>
void SafeRelease(T*& value) {
    if (value) {
        value->Release();
        value = nullptr;
    }
}

bool PointInRect(POINT point, const RECT& rect) {
    return point.x >= rect.left && point.x < rect.right && point.y >= rect.top &&
           point.y < rect.bottom;
}

POINT PointToDips(POINT point, UINT dpi) {
    return {MulDiv(point.x, 96, static_cast<int>(dpi)),
            MulDiv(point.y, 96, static_cast<int>(dpi))};
}

std::wstring FormatSize(uintmax_t bytes) {
    wchar_t buffer[64]{};
    if (bytes >= 1024ull * 1024ull) {
        swprintf_s(buffer, L"%.1f MB", static_cast<double>(bytes) / (1024.0 * 1024.0));
    } else {
        swprintf_s(buffer, L"%llu KB", static_cast<unsigned long long>(bytes / 1024));
    }
    return buffer;
}

std::wstring ReplaceToken(std::wstring text, std::wstring_view token,
                          std::wstring_view value) {
    size_t position = 0;
    while ((position = text.find(token, position)) != std::wstring::npos) {
        text.replace(position, token.size(), value);
        position += value.size();
    }
    return text;
}

std::wstring Localized(const Translation& translation, std::string_view key,
                       std::wstring_view fallback) {
    return translation.GetW(key, fallback);
}

std::wstring LocalizedShaderError(const Translation& translation,
                                  std::string_view error) {
    if (error == "Unknown shader mode") {
        return translation.GetW("cxx.shader.error.unknown_mode",
                                L"Unknown shader mode");
    }
    if (error == "Full shader pack is not downloaded") {
        return translation.GetW("cxx.shader.error.full_missing",
                                L"Full shader pack is not downloaded");
    }
    if (error == "Bundled lite shader pack is missing") {
        return translation.GetW("cxx.shader.error.lite_missing",
                                L"Bundled lite shader pack is missing");
    }
    if (error == "Cannot open shader pack") {
        return translation.GetW("cxx.shader.error.open_failed",
                                L"Cannot open shader pack");
    }
    if (error == "Shader pack manifest is missing") {
        return translation.GetW("cxx.shader.error.manifest_missing",
                                L"Shader pack manifest is missing");
    }
    if (error == "Shader pack extraction failed") {
        return translation.GetW("cxx.shader.error.extract_failed",
                                L"Shader pack extraction failed");
    }
    if (error == "Cannot move current shader directory") {
        return translation.GetW("cxx.shader.error.move_failed",
                                L"Cannot move current shader directory");
    }
    if (error == "Cannot activate shader pack") {
        return translation.GetW("cxx.shader.error.activate_failed",
                                L"Cannot activate shader pack");
    }
    if (error == "Cannot write shader transaction state" ||
        error == "Cannot write shader state") {
        return translation.GetW("cxx.shader.error.state_failed",
                                L"Cannot save the shader mode state");
    }
    return Utf8ToWide(error);
}

HICON LoadIconFromPath(IWICImagingFactory* wic_factory,
                       const std::filesystem::path& path, UINT size) {
    if (path.empty() || !FileExists(path) || size == 0) return nullptr;
    const std::wstring extension = ToLower(path.extension().wstring());
    if (extension == L".exe" || extension == L".dll") {
        HICON large_icon = nullptr;
        HICON small_icon = nullptr;
        if (ExtractIconExW(path.c_str(), 0, &large_icon, &small_icon, 1) == 0) {
            return nullptr;
        }
        if (large_icon) {
            if (small_icon) DestroyIcon(small_icon);
            return large_icon;
        }
        return small_icon;
    }
    if (extension == L".ico") {
        return static_cast<HICON>(LoadImageW(
            nullptr, path.c_str(), IMAGE_ICON, static_cast<int>(size),
            static_cast<int>(size), LR_LOADFROMFILE));
    }
    if (!wic_factory) return nullptr;

    IWICBitmapDecoder* decoder = nullptr;
    IWICBitmapFrameDecode* frame = nullptr;
    IWICBitmapScaler* scaler = nullptr;
    IWICFormatConverter* converter = nullptr;
    HICON icon = nullptr;
    if (FAILED(wic_factory->CreateDecoderFromFilename(
            path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand,
            &decoder)) ||
        FAILED(decoder->GetFrame(0, &frame))) {
        if (frame) frame->Release();
        if (decoder) decoder->Release();
        return nullptr;
    }

    UINT source_width = 0;
    UINT source_height = 0;
    frame->GetSize(&source_width, &source_height);
    const double scale =
        std::min(static_cast<double>(size) / std::max(1u, source_width),
                 static_cast<double>(size) / std::max(1u, source_height));
    const UINT output_width =
        std::max(1u, static_cast<UINT>(source_width * scale));
    const UINT output_height =
        std::max(1u, static_cast<UINT>(source_height * scale));
    if (SUCCEEDED(wic_factory->CreateBitmapScaler(&scaler)) &&
        SUCCEEDED(scaler->Initialize(
            frame, output_width, output_height, WICBitmapInterpolationModeFant)) &&
        SUCCEEDED(wic_factory->CreateFormatConverter(&converter)) &&
        SUCCEEDED(converter->Initialize(
            scaler, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone,
            nullptr, 0.0, WICBitmapPaletteTypeCustom))) {
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = static_cast<LONG>(size);
        info.bmiHeader.biHeight = -static_cast<LONG>(size);
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        void* raw_bits = nullptr;
        HBITMAP color =
            CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &raw_bits, nullptr, 0);
        if (color && raw_bits) {
            std::vector<BYTE> pixels(
                static_cast<size_t>(output_width) * output_height * 4);
            if (SUCCEEDED(converter->CopyPixels(
                    nullptr, output_width * 4,
                    static_cast<UINT>(pixels.size()), pixels.data()))) {
                auto* destination = static_cast<BYTE*>(raw_bits);
                const UINT left = (size - output_width) / 2;
                const UINT top = (size - output_height) / 2;
                for (UINT y = 0; y < output_height; ++y) {
                    memcpy(destination + (static_cast<size_t>(top + y) * size + left) * 4,
                           pixels.data() + static_cast<size_t>(y) * output_width * 4,
                           static_cast<size_t>(output_width) * 4);
                }
                HBITMAP mask = CreateBitmap(static_cast<int>(size),
                                            static_cast<int>(size), 1, 1, nullptr);
                ICONINFO icon_info{};
                icon_info.fIcon = TRUE;
                icon_info.hbmMask = mask;
                icon_info.hbmColor = color;
                icon = CreateIconIndirect(&icon_info);
                if (mask) DeleteObject(mask);
            }
        }
        if (color) DeleteObject(color);
    }

    if (converter) converter->Release();
    if (scaler) scaler->Release();
    frame->Release();
    decoder->Release();
    return icon;
}

ID2D1Bitmap* LoadIconBitmap(IWICImagingFactory* wic_factory,
                            ID2D1RenderTarget* render_target,
                            const std::filesystem::path& path, UINT size) {
    HICON icon = LoadIconFromPath(wic_factory, path, size);
    if (!icon || !render_target || size == 0) return nullptr;

    ICONINFO icon_info{};
    if (!GetIconInfo(icon, &icon_info)) {
        DestroyIcon(icon);
        return nullptr;
    }

    BITMAPINFO bitmap_info{};
    bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = static_cast<LONG>(size);
    bitmap_info.bmiHeader.biHeight = -static_cast<LONG>(size);
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = BI_RGB;
    void* pixels = nullptr;
    HBITMAP bitmap = CreateDIBSection(
        nullptr, &bitmap_info, DIB_RGB_COLORS, &pixels, nullptr, 0);
    ID2D1Bitmap* result = nullptr;
    if (bitmap && pixels) {
        memset(pixels, 0, static_cast<size_t>(size) * size * 4);
        HDC screen = GetDC(nullptr);
        HDC memory = CreateCompatibleDC(screen);
        if (memory) {
            HGDIOBJ previous = SelectObject(memory, bitmap);
            DrawIconEx(memory, 0, 0, icon, static_cast<int>(size),
                       static_cast<int>(size), 0, nullptr, DI_NORMAL);
            SelectObject(memory, previous);
            DeleteDC(memory);
        }
        if (screen) ReleaseDC(nullptr, screen);

        auto* bgra = static_cast<BYTE*>(pixels);
        for (size_t index = 0; index < static_cast<size_t>(size) * size; ++index) {
            BYTE* pixel = bgra + index * 4;
            if (pixel[3] == 0 && (pixel[0] || pixel[1] || pixel[2])) {
                pixel[3] = 255;
            }
        }
        const D2D1_BITMAP_PROPERTIES properties = D2D1::BitmapProperties(
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                              D2D1_ALPHA_MODE_PREMULTIPLIED));
        render_target->CreateBitmap(D2D1::SizeU(size, size), pixels,
                                    size * 4, properties, &result);
    }
    if (bitmap) DeleteObject(bitmap);
    if (icon_info.hbmColor) DeleteObject(icon_info.hbmColor);
    if (icon_info.hbmMask) DeleteObject(icon_info.hbmMask);
    DestroyIcon(icon);
    return result;
}

std::filesystem::path WriteModPresetLog(
    const std::filesystem::path& root, const ModPresetResult& result,
    const std::filesystem::path& target) {
    SYSTEMTIME time{};
    GetLocalTime(&time);
    wchar_t filename[64]{};
    swprintf_s(filename, L"日志_%04u_%02u_%02u_%02u_%02u.log",
               time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute);
    const auto path = root / filename;
    const auto previous = ReadUtf8(path).value_or("");
    std::ostringstream entry;
    entry << "\n--- " << time.wYear << '-' << time.wMonth << '-' << time.wDay
          << ' ' << time.wHour << ':' << time.wMinute << " ---\n"
          << "Target: " << WideToUtf8(target.wstring()) << '\n'
          << "Updated: " << result.updated_files
          << ", scanned: " << result.scanned_files
          << ", failed: " << result.failed_files << '\n';
    for (const auto& line : result.log) entry << line << '\n';
    if (!WriteUtf8Atomic(path, previous + entry.str())) {
        return {};
    }
    return path;
}

std::wstring JoinModPresetLog(const std::vector<std::string>& lines) {
    std::wstring text;
    for (const auto& line : lines) {
        text += Utf8ToWide(line);
        text.push_back(L'\n');
    }
    return text;
}

void ShowModPresetDetails(HWND owner, const Translation& translation,
                          bool failed, const std::filesystem::path& log_path,
                          const std::vector<std::string>& log_lines,
                          std::wstring_view summary) {
    const std::wstring title =
        translation.GetW("mod_preset.title", L"Save Mod preset");
    std::wstring content(summary);
    if (!log_path.empty()) {
        content += L"\n\n";
        content += log_path.wstring();
    }
    std::wstring details = JoinModPresetLog(log_lines);
    constexpr size_t kMaximumDetails = 12000;
    if (details.size() > kMaximumDetails) {
        details = details.substr(details.size() - kMaximumDetails);
    }
    ShowDetails(owner, title, content, details, failed);
}

struct ModPresetProgressOutcome {
    ModPresetResult result;
    std::filesystem::path log_path;
};

class ModPresetProgressWindow {
public:
    ModPresetProgressWindow(HWND owner, const Translation& translation,
                            std::filesystem::path d3dx,
                            std::filesystem::path target,
                            std::filesystem::path log_root)
        : owner_(owner),
          translation_(translation),
          d3dx_(std::move(d3dx)),
          target_(std::move(target)),
          log_root_(std::move(log_root)) {}

    std::optional<ModPresetProgressOutcome> Run() {
        constexpr wchar_t kClass[] = L"ReShadeLauncherModPresetProgress";
        static bool registered = false;
        if (!registered) {
            WNDCLASSEXW wc{};
            wc.cbSize = sizeof(wc);
            wc.lpfnWndProc = WindowProc;
            wc.hInstance = GetModuleHandleW(nullptr);
            wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
            wc.lpszClassName = kClass;
            if (!RegisterClassExW(&wc)) return std::nullopt;
            registered = true;
        }

        const std::wstring title =
            translation_.GetW("mod_preset.title", L"Save Mod preset");
        hwnd_ = CreateWindowExW(
            WS_EX_TOOLWINDOW, kClass, title.c_str(),
            WS_POPUP | WS_CLIPCHILDREN, 0, 0, 700, 470, owner_, nullptr,
            GetModuleHandleW(nullptr), this);
        if (!hwnd_) return std::nullopt;
        ConfigureOverlayWindow(hwnd_);
        CenterOverOwner();
        EnableWindow(owner_, FALSE);
        ShowWindow(hwnd_, SW_SHOWNORMAL);
        UpdateWindow(hwnd_);

        MSG message{};
        while (!destroyed_ && GetMessageW(&message, nullptr, 0, 0) > 0) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        if (worker_.joinable()) worker_.join();
        if (owner_ && IsWindow(owner_)) EnableWindow(owner_, TRUE);
        return outcome_;
    }

private:
    static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                       LPARAM lparam) {
        auto* self = reinterpret_cast<ModPresetProgressWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
            self = static_cast<ModPresetProgressWindow*>(create->lpCreateParams);
            self->hwnd_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA,
                              reinterpret_cast<LONG_PTR>(self));
        }
        return self ? self->Handle(message, wparam, lparam)
                    : DefWindowProcW(window, message, wparam, lparam);
    }

    LRESULT Handle(UINT message, WPARAM wparam, LPARAM lparam) {
        constexpr UINT kAppendLog = WM_APP + 40;
        constexpr UINT kFinished = WM_APP + 41;
        switch (message) {
            case WM_CREATE:
                dpi_ = GetDpiForWindow(hwnd_);
                if (!dpi_) dpi_ = 96;
                background_brush_ = CreateSolidBrush(RGB(8, 13, 26));
                panel_brush_ = CreateSolidBrush(RGB(18, 26, 46));
                font_ = CreateUiFont(dpi_, 10, FW_NORMAL);
                title_font_ = CreateUiFont(dpi_, 12, FW_SEMIBOLD);
                title_ = CreateWindowExW(
                    0, L"STATIC",
                    translation_.GetW("mod_preset.header", L"Choose Mods to save.")
                        .c_str(),
                    WS_CHILD | WS_VISIBLE | SS_LEFT | SS_NOPREFIX, 0, 0, 10, 10,
                    hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
                log_ = CreateWindowExW(
                    WS_EX_CLIENTEDGE, L"EDIT", L"",
                    WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE |
                        ES_AUTOVSCROLL | ES_READONLY,
                    0, 0, 10, 10, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
                status_ = CreateWindowExW(
                    0, L"STATIC",
                    translation_.GetW("status.mod_preset_running",
                                      L"Processing Mod presets...")
                        .c_str(),
                    WS_CHILD | WS_VISIBLE | SS_LEFT | SS_NOPREFIX, 0, 0, 10, 10,
                    hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
                close_ = CreateWindowExW(
                    0, L"BUTTON",
                    translation_.GetW("dialog.close", L"Close").c_str(),
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON, 0, 0,
                    10, 10, hwnd_,
                    reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDCANCEL)),
                    GetModuleHandleW(nullptr), nullptr);
                SendMessageW(title_, WM_SETFONT,
                             reinterpret_cast<WPARAM>(title_font_), TRUE);
                for (HWND control : {log_, status_, close_}) {
                    SendMessageW(control, WM_SETFONT,
                                 reinterpret_cast<WPARAM>(font_), TRUE);
                }
                SendMessageW(log_, EM_SETMARGINS,
                             EC_LEFTMARGIN | EC_RIGHTMARGIN, MAKELPARAM(8, 8));
                EnableWindow(close_, FALSE);
                Layout();
                worker_ = std::thread([this] { Work(); });
                return 0;
            case kAppendLog: {
                std::unique_ptr<std::string> text(
                    reinterpret_cast<std::string*>(lparam));
                if (text) AppendLog(Utf8ToWide(*text));
                return 0;
            }
            case kFinished: {
                std::unique_ptr<ModPresetProgressOutcome> result(
                    reinterpret_cast<ModPresetProgressOutcome*>(lparam));
                if (result) {
                    outcome_ = std::move(*result);
                    AppendLog(translation_.GetW(
                        "mod_preset.completed", L"Processing complete."));
                }
                finished_ = true;
                EnableWindow(close_, TRUE);
                SetWindowTextW(
                    status_,
                    translation_.GetW("mod_preset.completed",
                                      L"Processing complete.")
                        .c_str());
                SetFocus(close_);
                return 0;
            }
            case WM_SIZE:
                Layout();
                RefreshOverlayRegion(hwnd_);
                return 0;
            case WM_DPICHANGED: {
                dpi_ = HIWORD(wparam);
                if (font_) DeleteObject(font_);
                if (title_font_) DeleteObject(title_font_);
                font_ = CreateUiFont(dpi_, 10, FW_NORMAL);
                title_font_ = CreateUiFont(dpi_, 12, FW_SEMIBOLD);
                SendMessageW(title_, WM_SETFONT,
                             reinterpret_cast<WPARAM>(title_font_), TRUE);
                for (HWND control : {log_, status_, close_}) {
                    SendMessageW(control, WM_SETFONT,
                                 reinterpret_cast<WPARAM>(font_), TRUE);
                }
                CenterOverOwner();
                Layout();
                return 0;
            }
            case WM_CTLCOLORDLG:
                return reinterpret_cast<INT_PTR>(background_brush_);
            case WM_CTLCOLORSTATIC: {
                HDC dc = reinterpret_cast<HDC>(wparam);
                SetBkMode(dc, TRANSPARENT);
                SetTextColor(dc, RGB(235, 241, 255));
                return reinterpret_cast<INT_PTR>(background_brush_);
            }
            case WM_CTLCOLOREDIT: {
                HDC dc = reinterpret_cast<HDC>(wparam);
                SetBkColor(dc, RGB(9, 17, 31));
                SetTextColor(dc, RGB(235, 241, 255));
                return reinterpret_cast<INT_PTR>(panel_brush_);
            }
            case WM_COMMAND:
                if (LOWORD(wparam) == IDCANCEL && finished_) {
                    DestroyWindow(hwnd_);
                    return 0;
                }
                break;
            case WM_CLOSE:
                if (finished_) DestroyWindow(hwnd_);
                return 0;
            case WM_DESTROY:
                destroyed_ = true;
                if (owner_ && IsWindow(owner_)) EnableWindow(owner_, TRUE);
                return 0;
            case WM_NCDESTROY:
                if (font_) DeleteObject(font_);
                if (title_font_) DeleteObject(title_font_);
                if (background_brush_) DeleteObject(background_brush_);
                if (panel_brush_) DeleteObject(panel_brush_);
                font_ = nullptr;
                title_font_ = nullptr;
                background_brush_ = nullptr;
                panel_brush_ = nullptr;
                break;
        }
        return DefWindowProcW(hwnd_, message, wparam, lparam);
    }

    void Work() {
        auto outcome = std::make_unique<ModPresetProgressOutcome>();
        try {
            outcome->result = ModPresetService::Apply(
                d3dx_, target_,
                [this](const std::string& text) {
                    auto* value = new std::string(text);
                    if (!PostMessageW(hwnd_, WM_APP + 40, 0,
                                      reinterpret_cast<LPARAM>(value))) {
                        delete value;
                    }
                });
            outcome->log_path =
                WriteModPresetLog(log_root_, outcome->result, target_);
            if (outcome->log_path.empty()) {
                ++outcome->result.failed_files;
                const std::string error =
                    "Cannot write the Mod preset log file";
                outcome->result.log.push_back(error);
                PostWorkerLog(error);
            }
        } catch (const std::exception& error) {
            outcome->result.fatal_error = error.what();
            outcome->result.log.push_back(error.what());
            PostWorkerLog(error.what());
        } catch (...) {
            outcome->result.fatal_error = "Unknown Mod preset error";
            outcome->result.log.push_back(outcome->result.fatal_error);
            PostWorkerLog(outcome->result.fatal_error);
        }
        auto* raw_outcome = outcome.release();
        if (!PostMessageW(hwnd_, WM_APP + 41, 0,
                          reinterpret_cast<LPARAM>(raw_outcome))) {
            delete raw_outcome;
        }
    }

    void PostWorkerLog(const std::string& text) {
        auto* value = new std::string(text);
        if (!PostMessageW(hwnd_, WM_APP + 40, 0,
                          reinterpret_cast<LPARAM>(value))) {
            delete value;
        }
    }

    void Layout() {
        RECT client{};
        GetClientRect(hwnd_, &client);
        const int width = client.right - client.left;
        const int height = client.bottom - client.top;
        const int margin = MulDiv(18, dpi_, 96);
        const int button_width = MulDiv(96, dpi_, 96);
        const int button_height = MulDiv(32, dpi_, 96);
        SetWindowPos(title_, nullptr, margin, margin,
                     std::max(10, width - margin * 2), MulDiv(50, dpi_, 96),
                     SWP_NOZORDER | SWP_NOACTIVATE);
        SetWindowPos(log_, nullptr, margin, MulDiv(72, dpi_, 96),
                     std::max(10, width - margin * 2),
                     std::max(10, height - MulDiv(132, dpi_, 96)),
                     SWP_NOZORDER | SWP_NOACTIVATE);
        SetWindowPos(status_, nullptr, margin, height - margin - button_height,
                     std::max(10, width - margin * 2 - button_width -
                                      MulDiv(12, dpi_, 96)),
                     button_height, SWP_NOZORDER | SWP_NOACTIVATE);
        SetWindowPos(close_, nullptr, width - margin - button_width,
                     height - margin - button_height, button_width,
                     button_height, SWP_NOZORDER | SWP_NOACTIVATE);
    }

    void AppendLog(std::wstring_view line) {
        if (!log_ || line.empty()) return;
        const LRESULT length = GetWindowTextLengthW(log_);
        SendMessageW(log_, EM_SETSEL, static_cast<WPARAM>(length),
                     static_cast<LPARAM>(length));
        std::wstring text(line);
        text += L"\r\n";
        SendMessageW(log_, EM_REPLACESEL, FALSE,
                     reinterpret_cast<LPARAM>(text.c_str()));
        SendMessageW(log_, EM_SCROLLCARET, 0, 0);
    }

    void CenterOverOwner() {
        const UINT dpi = GetDpiForWindow(hwnd_);
        CenterOverlayWindow(hwnd_, owner_, MulDiv(700, dpi ? dpi : 96, 96),
                            MulDiv(470, dpi ? dpi : 96, 96));
    }

    static HFONT CreateUiFont(UINT dpi, int points, int weight) {
        return CreateFontW(-MulDiv(points, static_cast<int>(dpi), 72), 0, 0, 0,
                           weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                           CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    }

    HWND owner_ = nullptr;
    HWND hwnd_ = nullptr;
    HWND title_ = nullptr;
    HWND log_ = nullptr;
    HWND status_ = nullptr;
    HWND close_ = nullptr;
    const Translation& translation_;
    std::filesystem::path d3dx_;
    std::filesystem::path target_;
    std::filesystem::path log_root_;
    UINT dpi_ = 96;
    HFONT font_ = nullptr;
    HFONT title_font_ = nullptr;
    HBRUSH background_brush_ = nullptr;
    HBRUSH panel_brush_ = nullptr;
    std::thread worker_;
    bool finished_ = false;
    bool destroyed_ = false;
    std::optional<ModPresetProgressOutcome> outcome_;
};

}  // namespace

MainWindow::MainWindow(HINSTANCE instance)
    : instance_(instance),
      app_(ExecutableDirectory()),
      translation_(ExecutableDirectory()),
      configs_(app_),
      processes_(app_),
      mod_loaders_(app_),
      shaders_(app_) {
    app_.Load();
    if (app_.globals().contains("reshade_enabled") &&
        app_.globals()["reshade_enabled"].is_boolean()) {
        mode_reshade_enabled_ =
            app_.globals()["reshade_enabled"].get<bool>();
    }
    background_path_ = Utf8ToWide(app_.BackgroundImage());
    if (background_path_.empty()) {
        background_path_ = app_.resource_path(L"b.jpg").wstring();
    }
}

MainWindow::~MainWindow() {
    center_stop_ = true;
    xxmi_scan_cancel_ = true;
    if (hwnd_) KillTimer(hwnd_, kTimerGif);
    if (center_thread_.joinable()) center_thread_.join();
    if (xxmi_scan_thread_.joinable()) xxmi_scan_thread_.join();
    if (wait_thread_.joinable()) wait_thread_.detach();
    if (tray_visible_) {
        Shell_NotifyIconW(NIM_DELETE, &tray_);
        tray_visible_ = false;
    }
    for (auto* frame : background_frames_) SafeRelease(frame);
    background_frames_.clear();
    if (window_icon_large_) DestroyIcon(window_icon_large_);
    if (window_icon_small_) DestroyIcon(window_icon_small_);
    if (tray_icon_) DestroyIcon(tray_icon_);
    window_icon_large_ = nullptr;
    window_icon_small_ = nullptr;
    tray_icon_ = nullptr;
    DiscardGraphics();
    SafeRelease(d2d_factory_);
    SafeRelease(dwrite_factory_);
    SafeRelease(wic_factory_);
}

bool MainWindow::Create(std::optional<std::string> startup_config) {
    startup_config_ = std::move(startup_config);
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = instance_;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(instance_, MAKEINTRESOURCEW(1));
    wc.hbrBackground = nullptr;
    wc.lpszClassName = kWindowClass;
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        return false;
    }
    std::wstring window_title =
        Localized(translation_, "cxx.app.title", L"ReShade Launcher");
    const std::wstring version = ExecutableVersionString(ExecutablePath());
    if (!version.empty()) window_title += L" v" + version;
    hwnd_ = CreateWindowExW(WS_EX_APPWINDOW, kWindowClass, window_title.c_str(),
                            WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT,
                            CW_USEDEFAULT, 640, 530, nullptr, nullptr, instance_, this);
    if (!hwnd_) {
        return false;
    }
    taskbar_created_message_ =
        RegisterWindowMessageW(L"TaskbarCreated");
    const BOOL dark_titlebar = TRUE;
    DwmSetWindowAttribute(hwnd_, 20, &dark_titlebar, sizeof(dark_titlebar));
    const COLORREF caption_color = RGB(8, 13, 26);
    const COLORREF text_color = RGB(240, 245, 255);
    DwmSetWindowAttribute(hwnd_, 35, &caption_color, sizeof(caption_color));
    DwmSetWindowAttribute(hwnd_, 36, &text_color, sizeof(text_color));
    const UINT dpi = GetDpiForWindow(hwnd_);
    dpi_ = dpi ? dpi : 96;
    RECT desired{0, 0, MulDiv(640, dpi_, 96), MulDiv(530, dpi_, 96)};
    AdjustWindowRectExForDpi(&desired, WS_OVERLAPPEDWINDOW, FALSE, WS_EX_APPWINDOW, dpi_);
    SetWindowPos(hwnd_, nullptr, 0, 0, desired.right - desired.left,
                 desired.bottom - desired.top,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    InitializeGraphics();
    const bool shader_recovery_ok = shaders_.Recover();
    shader_mode_ = shaders_.CurrentMode();
    RefreshProfiles(false);
    if (startup_config_) {
        const auto it = std::find_if(profiles_.begin(), profiles_.end(), [&](const auto& p) {
            return p.config_name == *startup_config_;
        });
        if (it != profiles_.end()) {
            selected_index_ = static_cast<int>(std::distance(profiles_.begin(), it));
            launched_by_shortcut_ = true;
        }
    }
    if (selected_index_ >= 0) {
        app_.SetLastSelectedConfig(profiles_[selected_index_].config_name);
    }
    UpdateWindowIcons();
    UpdateTrayIcon();
    status_ = WideToUtf8(Localized(translation_, "status.ready", L"Ready"));
    if (!shader_recovery_ok) {
        status_ = WideToUtf8(Localized(
            translation_, "cxx.shader.error.recovery_failed",
            L"Shader recovery failed. Toggle the shader mode to repair the folder."));
    }
    SetTimer(hwnd_, kTimerWindow, 500, nullptr);
    ShowWindow(hwnd_, SW_SHOWNORMAL);
    UpdateWindow(hwnd_);
    const UINT current_dpi = GetDpiForWindow(hwnd_);
    const UINT previous_dpi = dpi_;
    if (current_dpi) dpi_ = current_dpi;
    RECT logical{0, 0, MulDiv(640, dpi_, 96), MulDiv(530, dpi_, 96)};
    AdjustWindowRectExForDpi(&logical, WS_OVERLAPPEDWINDOW, FALSE,
                             WS_EX_APPWINDOW, dpi_);
    SetWindowPos(hwnd_, nullptr, 0, 0, logical.right - logical.left,
                 logical.bottom - logical.top,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    if (dpi_ != previous_dpi) {
        DiscardGraphics();
        InitializeGraphics();
        RebuildProfileIcons();
    }
    if (launched_by_shortcut_ && selected_index_ >= 0) {
        PostMessageW(hwnd_, WM_COMMAND, 0, 0);
        StartLaunch(true);
    }
    return true;
}

int MainWindow::Run() {
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return static_cast<int>(message.wParam);
}

LRESULT CALLBACK MainWindow::WindowProc(HWND window, UINT message, WPARAM wparam,
                                         LPARAM lparam) {
    auto* self = reinterpret_cast<MainWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
        self = static_cast<MainWindow*>(create->lpCreateParams);
        self->hwnd_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self && self->taskbar_created_message_ != 0 &&
        message == self->taskbar_created_message_) {
        self->tray_visible_ = false;
        self->UpdateTrayIcon();
        return 0;
    }
    return self ? self->HandleMessage(message, wparam, lparam)
                : DefWindowProcW(window, message, wparam, lparam);
}

LRESULT MainWindow::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
        case WM_PAINT:
            Draw();
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_SIZE:
            ResizeGraphics(LOWORD(lparam), HIWORD(lparam));
            return 0;
        case WM_MOUSEMOVE:
            mouse_ = PointToDips({GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)}, dpi_);
            {
                TRACKMOUSEEVENT tracking{};
                tracking.cbSize = sizeof(tracking);
                tracking.dwFlags = TME_LEAVE;
                tracking.hwndTrack = hwnd_;
                TrackMouseEvent(&tracking);
            }
            {
                int index = -1;
                RECT anchor{};
                const auto action = HitTest(mouse_, &index, &anchor);
                const bool hover_changed =
                    action != hover_action_ || index != hover_index_;
                hover_action_ = action;
                hover_index_ = index;
                UpdateTooltip(action, index, anchor);
                if (hover_changed) InvalidateRect(hwnd_, nullptr, FALSE);
            }
            return 0;
        case WM_MOUSELEAVE: {
            mouse_ = {-1, -1};
            const bool had_hover = hover_action_ != Action::None;
            hover_action_ = Action::None;
            hover_index_ = -1;
            HideTooltip();
            if (had_hover) InvalidateRect(hwnd_, nullptr, FALSE);
            return 0;
        }
        case WM_KEYDOWN:
            if (!hit_areas_.empty()) {
                if (wparam == VK_TAB || wparam == VK_RIGHT || wparam == VK_DOWN ||
                    wparam == VK_LEFT || wparam == VK_UP) {
                    keyboard_focus_visible_ = true;
                    const bool backward =
                        wparam == VK_LEFT || wparam == VK_UP ||
                        (wparam == VK_TAB && (GetKeyState(VK_SHIFT) & 0x8000));
                    auto eligible = [&](const HitArea& area) {
                        if (xxmi_menu_open_) {
                            return area.action == Action::XXMIGame;
                        }
                        if (mode_menu_open_) {
                            return area.action == Action::ModeXXMI ||
                                   area.action == Action::ModeBuiltin ||
                                   area.action == Action::ModeGame ||
                                   area.action == Action::ModeCustom ||
                                   area.action == Action::ReshadeToggle;
                        }
                        if (config_menu_open_) {
                            return area.action == Action::SelectConfig &&
                                       area.index >= 0 ||
                                   area.action == Action::ConfigEdit ||
                                   area.action == Action::ConfigShortcut ||
                                   area.action == Action::ConfigRefresh;
                        }
                        return true;
                    };
                    const int count =
                        static_cast<int>(hit_areas_.size());
                    int candidate =
                        keyboard_focus_ < 0 || keyboard_focus_ >= count
                            ? (backward ? 0 : -1)
                            : keyboard_focus_;
                    for (int step = 0; step < count; ++step) {
                        candidate =
                            (candidate + (backward ? -1 : 1) + count) %
                            count;
                        if (eligible(hit_areas_[candidate])) {
                            keyboard_focus_ = candidate;
                            break;
                        }
                    }
                    InvalidateRect(hwnd_, nullptr, FALSE);
                    return 0;
                }
                if (wparam == VK_RETURN || wparam == VK_SPACE) {
                    if (keyboard_focus_ >= 0 &&
                        keyboard_focus_ < static_cast<int>(hit_areas_.size())) {
                        const RECT& rect = hit_areas_[keyboard_focus_].rect;
                        OnClick(POINT{(rect.left + rect.right) / 2,
                                      (rect.top + rect.bottom) / 2});
                    }
                    return 0;
                }
            }
            if (wparam == VK_ESCAPE &&
                (config_menu_open_ || mode_menu_open_ || xxmi_menu_open_)) {
                config_menu_open_ = false;
                mode_menu_open_ = false;
                xxmi_menu_open_ = false;
                InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            }
            break;
        case WM_LBUTTONDOWN: {
            const POINT raw_point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
            const POINT point = PointToDips(raw_point, dpi_);
            keyboard_focus_visible_ = false;
            HideTooltip();
            OnClick(point);
            InvalidateRect(hwnd_, nullptr, FALSE);
            return 0;
        }
        case WM_DPICHANGED: {
            dpi_ = HIWORD(wparam);
            OnDpiChanged(dpi_, reinterpret_cast<RECT*>(lparam));
            return 0;
        }
        case WM_GETMINMAXINFO: {
            auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
            RECT minimum{0, 0, MulDiv(610, dpi_, 96), MulDiv(500, dpi_, 96)};
            AdjustWindowRectExForDpi(&minimum, WS_OVERLAPPEDWINDOW, FALSE,
                                     WS_EX_APPWINDOW, dpi_);
            info->ptMinTrackSize = {minimum.right - minimum.left,
                                    minimum.bottom - minimum.top};
            return 0;
        }
        case WM_TIMER:
            if (wparam == kTimerWindow) {
                CheckGameWindow();
                return 0;
            }
            if (wparam == kTimerGif) {
                AdvanceBackgroundFrame();
                return 0;
            }
            break;
        case WM_MOUSEWHEEL:
            if (config_menu_open_ && profiles_.size() > 6) {
                const int direction = GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? -3 : 3;
                const int maximum =
                    static_cast<int>(profiles_.size()) - 6;
                config_menu_offset_ = static_cast<size_t>(std::clamp(
                    static_cast<int>(config_menu_offset_) + direction, 0, maximum));
                InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            }
            break;
        case kLaunchDone: {
            auto* payload = reinterpret_cast<LaunchPayload*>(lparam);
            OnLaunchFinished(payload);
            return 0;
        }
        case kModPresetDone: {
            auto* payload = reinterpret_cast<ModPresetPayload*>(lparam);
            OnModPresetFinished(payload);
            return 0;
        }
        case kXXMIScanDone: {
            auto* payload = reinterpret_cast<XXMIScanPayload*>(lparam);
            OnXXMIScanFinished(payload);
            return 0;
        }
        case WM_APP + 20: {
            std::unique_ptr<std::string> text(reinterpret_cast<std::string*>(lparam));
            if (text) SetStatus(*text);
            return 0;
        }
        case WM_APP + 30:
            DestroyWindow(hwnd_);
            return 0;
        case kGameExited:
            OnGameExited(static_cast<std::uint64_t>(wparam));
            return 0;
        case kToggleWindow:
            ShowFromTray();
            return 0;
        case kTrayCallback:
            if (LOWORD(lparam) == WM_LBUTTONDBLCLK) {
                if (IsWindowVisible(hwnd_)) {
                    HideToTray();
                } else {
                    ShowFromTray();
                }
            } else if (LOWORD(lparam) == WM_RBUTTONUP) {
                POINT point{};
                if (!GetCursorPos(&point)) {
                    const DWORD message_position = GetMessagePos();
                    point.x = GET_X_LPARAM(message_position);
                    point.y = GET_Y_LPARAM(message_position);
                }
                HMENU menu = CreatePopupMenu();
                AppendMenuW(menu, MF_STRING, kTrayShow,
                            Localized(translation_,
                                      IsWindowVisible(hwnd_) ? "tray.hide" : "tray.show",
                                      IsWindowVisible(hwnd_) ? L"Hide window"
                                                             : L"Show window")
                                .c_str());
                AppendMenuW(menu, MF_STRING, kTrayModPresetAll,
                            Localized(translation_, "tray.mod_preset_all",
                                      L"Apply d3dx parameters to all Mods")
                                .c_str());
                AppendMenuW(menu, MF_STRING, kTrayModPresetSelect,
                            Localized(translation_, "tray.mod_preset_select",
                                      L"Apply d3dx parameters to selected folder")
                                .c_str());
                AppendMenuW(menu, MF_STRING, kTrayMods,
                            Localized(translation_, "button.mods_folder", L"Mods folder")
                                .c_str());
                AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
                AppendMenuW(menu, MF_STRING, kTrayExit,
                            Localized(translation_, "tray.quit", L"Exit").c_str());
                SetForegroundWindow(hwnd_);
                TrackPopupMenu(menu,
                               TPM_BOTTOMALIGN | TPM_LEFTALIGN |
                                   TPM_RIGHTBUTTON,
                               point.x, point.y, 0, hwnd_, nullptr);
                PostMessageW(hwnd_, WM_NULL, 0, 0);
                DestroyMenu(menu);
            }
            return 0;
        case WM_COMMAND:
            if (LOWORD(wparam) == kTrayExit) {
                StopActiveSession();
                DestroyWindow(hwnd_);
            } else if (LOWORD(wparam) == kTrayShow) {
                if (IsWindowVisible(hwnd_)) {
                    HideToTray();
                } else {
                    ShowFromTray();
                }
            } else if (LOWORD(wparam) == kTrayMods) {
                ResolveAndOpenMods();
            } else if (LOWORD(wparam) == kTrayModPresetAll) {
                StartModPreset();
            } else if (LOWORD(wparam) == kTrayModPresetSelect) {
                StartModPresetSelect();
            }
            return 0;
        case WM_CLOSE:
            HideToTray();
            return 0;
        case WM_DESTROY:
            KillTimer(hwnd_, kTimerWindow);
            KillTimer(hwnd_, kTimerGif);
            xxmi_scan_cancel_ = true;
            StopActiveSession();
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd_, message, wparam, lparam);
}

float MainWindow::Scale() const { return static_cast<float>(dpi_) / 96.0f; }

RECT MainWindow::ScaledRect(float x, float y, float width, float height) const {
    return RECT{static_cast<LONG>(x), static_cast<LONG>(y),
                static_cast<LONG>(x + width), static_cast<LONG>(y + height)};
}

void MainWindow::InitializeGraphics() {
    D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &d2d_factory_);
    DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                        reinterpret_cast<IUnknown**>(&dwrite_factory_));
    CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                     IID_PPV_ARGS(&wic_factory_));
    auto make_format = [&](const wchar_t* font, float size, DWRITE_TEXT_ALIGNMENT alignment,
                           IDWriteTextFormat** output) {
        dwrite_factory_->CreateTextFormat(font, nullptr,
                                          DWRITE_FONT_WEIGHT_NORMAL,
                                          DWRITE_FONT_STYLE_NORMAL,
                                          DWRITE_FONT_STRETCH_NORMAL, size, L"",
                                          output);
        (*output)->SetTextAlignment(alignment);
        (*output)->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
        (*output)->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    };
    make_format(L"Segoe UI", 22.0f, DWRITE_TEXT_ALIGNMENT_LEADING,
                &title_format_);
    make_format(L"Segoe UI", 14.0f, DWRITE_TEXT_ALIGNMENT_LEADING,
                &text_format_);
    make_format(L"Segoe UI", 12.0f, DWRITE_TEXT_ALIGNMENT_LEADING,
                &small_format_);
    make_format(L"Segoe UI", 14.0f, DWRITE_TEXT_ALIGNMENT_CENTER,
                &button_format_);
    make_format(L"Segoe MDL2 Assets", 18.0f,
                DWRITE_TEXT_ALIGNMENT_CENTER, &icon_format_);
    RECT rect{};
    GetClientRect(hwnd_, &rect);
    ResizeGraphics(rect.right - rect.left, rect.bottom - rect.top);
}

void MainWindow::DiscardGraphics() {
    for (auto* frame : background_frames_) SafeRelease(frame);
    background_frames_.clear();
    background_frame_delays_ms_.clear();
    background_frame_index_ = 0;
    for (auto* icon : profile_icons_) SafeRelease(icon);
    profile_icons_.clear();
    SafeRelease(brush_);
    SafeRelease(render_target_);
    SafeRelease(title_format_);
    SafeRelease(text_format_);
    SafeRelease(small_format_);
    SafeRelease(button_format_);
    SafeRelease(icon_format_);
}

void MainWindow::ResizeGraphics(UINT width, UINT height) {
    if (!d2d_factory_) return;
    if (!render_target_) {
        const auto size = D2D1::SizeU(std::max(1u, width), std::max(1u, height));
        const auto properties = D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(),
            96.0f, 96.0f);
        d2d_factory_->CreateHwndRenderTarget(
            properties,
            D2D1::HwndRenderTargetProperties(hwnd_, size), &render_target_);
        render_target_->CreateSolidColorBrush(ColorText(), &brush_);
        LoadBackground();
    } else if (width && height) {
        render_target_->Resize(D2D1::SizeU(width, height));
    }
}

void MainWindow::LoadBackground() {
    if (hwnd_) KillTimer(hwnd_, kTimerGif);
    for (auto* frame : background_frames_) SafeRelease(frame);
    background_frames_.clear();
    background_frame_delays_ms_.clear();
    background_frame_index_ = 0;
    if (!wic_factory_ || !render_target_ || background_path_.empty()) return;
    IWICBitmapDecoder* decoder = nullptr;
    if (FAILED(wic_factory_->CreateDecoderFromFilename(
            background_path_.c_str(), nullptr, GENERIC_READ,
            WICDecodeMetadataCacheOnDemand, &decoder))) {
        return;
    }
    UINT frame_count = 0;
    if (SUCCEEDED(decoder->GetFrameCount(&frame_count))) {
        for (UINT index = 0; index < frame_count; ++index) {
            IWICBitmapFrameDecode* frame = nullptr;
            IWICFormatConverter* converter = nullptr;
            ID2D1Bitmap* bitmap = nullptr;
            UINT delay_ms = 100;
            if (SUCCEEDED(decoder->GetFrame(index, &frame))) {
                IWICMetadataQueryReader* metadata = nullptr;
                if (SUCCEEDED(frame->GetMetadataQueryReader(&metadata))) {
                    PROPVARIANT value;
                    PropVariantInit(&value);
                    if (SUCCEEDED(metadata->GetMetadataByName(
                            L"/grctlext/Delay", &value))) {
                        if (value.vt == VT_UI2) {
                            delay_ms = std::max<UINT>(20, value.uiVal * 10);
                        } else if (value.vt == VT_UI4) {
                            delay_ms = std::max<UINT>(20, value.ulVal * 10);
                        }
                    }
                    PropVariantClear(&value);
                    metadata->Release();
                }
                if (SUCCEEDED(wic_factory_->CreateFormatConverter(&converter)) &&
                    SUCCEEDED(converter->Initialize(
                        frame, GUID_WICPixelFormat32bppPBGRA,
                        WICBitmapDitherTypeNone, nullptr, 0.0,
                        WICBitmapPaletteTypeCustom)) &&
                    SUCCEEDED(render_target_->CreateBitmapFromWicBitmap(
                        converter, nullptr, &bitmap))) {
                    background_frames_.push_back(bitmap);
                    background_frame_delays_ms_.push_back(delay_ms);
                    bitmap = nullptr;
                }
                if (bitmap) bitmap->Release();
                if (converter) converter->Release();
                frame->Release();
            }
        }
    }
    SafeRelease(decoder);
    if (background_frames_.size() > 1) {
        SetTimer(hwnd_, kTimerGif,
                 background_frame_delays_ms_.front(), nullptr);
    }
}

void MainWindow::RebuildProfileIcons() {
    for (auto* icon : profile_icons_) SafeRelease(icon);
    profile_icons_.clear();
    if (!render_target_ || !wic_factory_) return;
    const UINT icon_size = static_cast<UINT>(std::max(16, MulDiv(28, dpi_, 96)));
    profile_icons_.resize(profiles_.size(), nullptr);
    for (size_t index = 0; index < profiles_.size(); ++index) {
        const auto& profile = profiles_[index];
        std::filesystem::path icon_path;
        if (!profile.custom_icon.empty()) {
            icon_path = Utf8ToWide(profile.custom_icon);
        }
        if (!FileExists(icon_path)) icon_path = profile.game_exe;
        profile_icons_[index] =
            LoadIconBitmap(wic_factory_, render_target_, icon_path, icon_size);
    }
}

void MainWindow::AdvanceBackgroundFrame() {
    if (background_frames_.size() < 2) {
        KillTimer(hwnd_, kTimerGif);
        return;
    }
    background_frame_index_ =
        (background_frame_index_ + 1) % background_frames_.size();
    SetTimer(hwnd_, kTimerGif,
             background_frame_delays_ms_[background_frame_index_], nullptr);
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::AddHitArea(Action action, RECT rect, int index) {
    hit_areas_.push_back({rect, action, index});
    if (static_cast<int>(hit_areas_.size()) - 1 == keyboard_focus_) {
        keyboard_focus_rect_ = rect;
    }
}

MainWindow::Action MainWindow::HitTest(POINT point, int* index,
                                       RECT* rect) const {
    for (auto it = hit_areas_.rbegin(); it != hit_areas_.rend(); ++it) {
        if (PointInRect(point, it->rect)) {
            if (index) *index = it->index;
            if (rect) *rect = it->rect;
            return it->action;
        }
    }
    if (rect) *rect = {};
    return Action::None;
}

void MainWindow::UpdateTooltip(Action action, int index, const RECT& anchor) {
    if (config_menu_open_ || mode_menu_open_ || xxmi_menu_open_) {
        HideTooltip();
        return;
    }
    std::wstring text;
    switch (action) {
        case Action::SelectConfig:
            text = Localized(translation_, "button.select_config.tooltip",
                             L"Select a saved configuration");
            break;
        case Action::Launch:
            text = Localized(translation_, "button.launch.tooltip",
                             L"Launch with the current configuration");
            break;
        case Action::FixShadow:
            text = Localized(translation_, "button.fix_shadow.tooltip",
                             L"Toggle ReShade depth orientation");
            break;
        case Action::AddGame:
            text = Localized(translation_, "button.add_game.tooltip",
                             L"Add a game launch configuration");
            break;
        case Action::ForceClose:
            text = Localized(translation_, "button.force_close.tooltip",
                             L"Force close the running game");
            break;
        case Action::Help:
            text = Localized(translation_, "button.help.tooltip", L"Help");
            break;
        case Action::ChangeBackground:
            text = Localized(translation_, "button.change_background.tooltip",
                             L"Change background image");
            break;
        case Action::SaveModPreset:
            text = Localized(translation_, "button.save_mod_preset.tooltip",
                             L"Save the current Mod preset");
            break;
        case Action::ModsFolder:
            text = Localized(translation_, "button.mods_folder.tooltip",
                             L"Open the Mods folder");
            break;
        case Action::ShaderToggle:
            text = Localized(translation_, "button.shader_switch.tooltip",
                             L"Switch between lite and full shaders");
            break;
        case Action::Update:
            text = Localized(translation_, "button.update.tooltip",
                             L"Check for the latest version");
            break;
        case Action::ConfigRefresh:
            text = Localized(translation_, "menu.refresh", L"Refresh list");
            break;
        case Action::ConfigEdit:
        case Action::ConfigShortcut:
            if (index >= 0 && index < static_cast<int>(profiles_.size())) {
                const auto name = Utf8ToWide(profiles_[index].display_name);
                text = Localized(
                    translation_,
                    action == Action::ConfigEdit ? "menu.edit.tooltip"
                                                 : "menu.shortcut.tooltip",
                    action == Action::ConfigEdit ? L"Edit {name}"
                                                 : L"Create shortcut for {name}");
                text = ReplaceToken(text, L"{name}", name);
            }
            break;
        case Action::CancelXXMIScan:
            text = Localized(translation_, "dialog.cancel", L"Cancel");
            break;
        default:
            break;
    }
    if (text.empty()) {
        HideTooltip();
        return;
    }
    tooltip_text_ = std::move(text);
    tooltip_anchor_ = anchor;
}

void MainWindow::HideTooltip() {
    tooltip_anchor_ = {};
    tooltip_text_.clear();
}

void MainWindow::DrawButton(const HitArea& area, std::wstring_view label, bool active,
                            bool icon, ID2D1Bitmap* bitmap,
                            bool allow_hover) {
    const bool hover = allow_hover && PointInRect(mouse_, area.rect);
    brush_->SetColor(active ? ColorAccent() : (hover ? ColorPanelHover() : ColorPanel()));
    const auto rounded = D2D1::RoundedRect(
        D2D1::RectF(static_cast<float>(area.rect.left) + 1.0f,
                    static_cast<float>(area.rect.top) + 1.0f,
                    static_cast<float>(area.rect.right) - 1.0f,
                    static_cast<float>(area.rect.bottom) - 1.0f),
        5.0f, 5.0f);
    render_target_->FillRoundedRectangle(rounded, brush_);
    float text_left = static_cast<float>(area.rect.left) + 3.0f;
    if (bitmap) {
        const float icon_size = std::min(
            28.0f, static_cast<float>(area.rect.bottom - area.rect.top) - 6.0f);
        render_target_->DrawBitmap(
            bitmap,
            D2D1::RectF(static_cast<float>(area.rect.left) + 5.0f,
                        static_cast<float>(area.rect.top) +
                            (static_cast<float>(area.rect.bottom - area.rect.top) -
                             icon_size) /
                                2.0f,
                        static_cast<float>(area.rect.left) + 5.0f + icon_size,
                        static_cast<float>(area.rect.top) +
                            (static_cast<float>(area.rect.bottom - area.rect.top) +
                             icon_size) /
                                2.0f),
            1.0f, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        text_left += icon_size + 5.0f;
    }
    brush_->SetColor(active ? D2D1::ColorF(0.08f, 0.12f, 0.08f, 1.0f) : ColorText());
    render_target_->DrawTextW(
        std::wstring(label).c_str(), static_cast<UINT32>(label.size()),
        icon ? icon_format_ : button_format_,
        D2D1::RectF(text_left,
                    static_cast<float>(area.rect.top), static_cast<float>(area.rect.right),
                    static_cast<float>(area.rect.bottom)),
        brush_, D2D1_DRAW_TEXT_OPTIONS_CLIP);
}

void MainWindow::DrawPictureIcon(const RECT& rect) {
    const float center_x =
        (static_cast<float>(rect.left) + static_cast<float>(rect.right)) / 2.0f;
    const float center_y =
        (static_cast<float>(rect.top) + static_cast<float>(rect.bottom)) / 2.0f;
    const float left = center_x - 9.0f;
    const float top = center_y - 7.0f;
    const float right = center_x + 9.0f;
    const float bottom = center_y + 7.0f;

    brush_->SetColor(ColorText());
    render_target_->DrawRoundedRectangle(
        D2D1::RoundedRect(D2D1::RectF(left, top, right, bottom), 2.0f, 2.0f),
        brush_, 1.25f);
    render_target_->DrawEllipse(
        D2D1::Ellipse(D2D1::Point2F(right - 4.8f, top + 4.6f), 1.7f, 1.7f),
        brush_, 1.2f);
    render_target_->DrawLine(
        D2D1::Point2F(left + 2.2f, bottom - 2.4f),
        D2D1::Point2F(left + 7.0f, bottom - 7.6f), brush_, 1.25f);
    render_target_->DrawLine(
        D2D1::Point2F(left + 7.0f, bottom - 7.6f),
        D2D1::Point2F(left + 11.4f, bottom - 3.8f), brush_, 1.25f);
    render_target_->DrawLine(
        D2D1::Point2F(left + 9.8f, bottom - 3.8f),
        D2D1::Point2F(right - 2.2f, bottom - 7.0f), brush_, 1.25f);
    render_target_->DrawLine(
        D2D1::Point2F(right - 2.2f, bottom - 7.0f),
        D2D1::Point2F(right - 2.2f, bottom - 2.4f), brush_, 1.25f);
}

void MainWindow::DrawTooltip() {
    if (tooltip_text_.empty() || !dwrite_factory_ || !render_target_ ||
        !brush_) {
        return;
    }

    constexpr float kMaximumWidth = 280.0f;
    constexpr float kPaddingX = 11.0f;
    constexpr float kPaddingY = 8.0f;
    IDWriteTextLayout* layout = nullptr;
    if (FAILED(dwrite_factory_->CreateTextLayout(
            tooltip_text_.c_str(), static_cast<UINT32>(tooltip_text_.size()),
            text_format_, kMaximumWidth - kPaddingX * 2.0f, 160.0f,
            &layout)) ||
        !layout) {
        return;
    }
    layout->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
    layout->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
    layout->SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
    DWRITE_TEXT_METRICS metrics{};
    layout->GetMetrics(&metrics);

    const float tooltip_width = std::clamp(
        metrics.widthIncludingTrailingWhitespace + kPaddingX * 2.0f,
        128.0f, kMaximumWidth);
    const float tooltip_height =
        std::max(38.0f, metrics.height + kPaddingY * 2.0f);
    const D2D1_SIZE_F physical_size = render_target_->GetSize();
    const float client_width = physical_size.width / std::max(0.01f, Scale());
    const float client_height = physical_size.height / std::max(0.01f, Scale());
    const float anchor_left = static_cast<float>(tooltip_anchor_.left);
    const float anchor_top = static_cast<float>(tooltip_anchor_.top);
    const float anchor_right = static_cast<float>(tooltip_anchor_.right);
    const float anchor_bottom = static_cast<float>(tooltip_anchor_.bottom);
    const float minimum_x = 8.0f;
    const float maximum_x =
        std::max(minimum_x, client_width - tooltip_width - 8.0f);
    const float minimum_y = 8.0f;
    const float maximum_y =
        std::max(minimum_y, client_height - tooltip_height - 8.0f);
    const auto fits = [&](const D2D1_RECT_F& candidate) {
        if (candidate.left < minimum_x || candidate.top < minimum_y ||
            candidate.right > client_width - 8.0f ||
            candidate.bottom > client_height - 8.0f) {
            return false;
        }
        RECT candidate_rect{
            static_cast<LONG>(candidate.left), static_cast<LONG>(candidate.top),
            static_cast<LONG>(candidate.right),
            static_cast<LONG>(candidate.bottom)};
        return std::none_of(hit_areas_.begin(), hit_areas_.end(),
                            [&](const HitArea& area) {
                                RECT intersection{};
                                return IntersectRect(&intersection,
                                                     &candidate_rect,
                                                     &area.rect) != FALSE;
                            });
    };

    const std::array<D2D1_RECT_F, 4> candidates = {
        D2D1::RectF(anchor_right + 8.0f, anchor_top,
                    anchor_right + 8.0f + tooltip_width,
                    anchor_top + tooltip_height),
        D2D1::RectF(anchor_left - tooltip_width - 8.0f, anchor_top,
                    anchor_left - 8.0f, anchor_top + tooltip_height),
        D2D1::RectF(anchor_left, anchor_top - tooltip_height - 8.0f,
                    anchor_left + tooltip_width, anchor_top - 8.0f),
        D2D1::RectF(anchor_left, anchor_bottom + 8.0f,
                    anchor_left + tooltip_width,
                    anchor_bottom + 8.0f + tooltip_height)};
    D2D1_RECT_F placement = candidates.front();
    bool placement_found = false;
    for (D2D1_RECT_F candidate : candidates) {
        candidate.left =
            std::clamp(candidate.left, minimum_x,
                       std::max(minimum_x,
                                maximum_x + tooltip_width -
                                    (candidate.right - candidate.left)));
        candidate.right = candidate.left + tooltip_width;
        candidate.top =
            std::clamp(candidate.top, minimum_y,
                       std::max(minimum_y,
                                maximum_y + tooltip_height -
                                    (candidate.bottom - candidate.top)));
        candidate.bottom = candidate.top + tooltip_height;
        if (fits(candidate)) {
            placement = candidate;
            placement_found = true;
            break;
        }
    }
    if (!placement_found) {
        placement.left =
            std::clamp(placement.left, minimum_x, maximum_x);
        placement.top = std::clamp(placement.top, minimum_y, maximum_y);
        placement.right = placement.left + tooltip_width;
        placement.bottom = placement.top + tooltip_height;
    }
    const float x = placement.left;
    const float y = placement.top;

    const auto box = D2D1::RoundedRect(
        D2D1::RectF(x, y, x + tooltip_width, y + tooltip_height), 6.0f, 6.0f);
    brush_->SetColor(D2D1::ColorF(0.035f, 0.06f, 0.12f, 0.98f));
    render_target_->FillRoundedRectangle(box, brush_);
    brush_->SetColor(D2D1::ColorF(0.24f, 0.30f, 0.44f, 1.0f));
    render_target_->DrawRoundedRectangle(box, brush_, 1.0f);
    brush_->SetColor(ColorText());
    render_target_->DrawTextLayout(
        D2D1::Point2F(x + kPaddingX, y + kPaddingY), layout, brush_,
        D2D1_DRAW_TEXT_OPTIONS_CLIP);
    layout->Release();
}

void MainWindow::DrawShaderSwitch(const RECT& rect, ShaderPackManager::Mode mode,
                                  bool allow_hover) {
    const bool full = mode == ShaderPackManager::Mode::Full;
    const bool hover = allow_hover && PointInRect(mouse_, rect);
    brush_->SetColor(hover ? ColorPanelHover() : ColorPanel());
    render_target_->FillRoundedRectangle(
        D2D1::RoundedRect(
            D2D1::RectF(static_cast<float>(rect.left) + 1,
                        static_cast<float>(rect.top) + 1,
                        static_cast<float>(rect.right) - 1,
                        static_cast<float>(rect.bottom) - 1),
            5, 5),
        brush_);

    const std::wstring label = full
                                   ? Localized(translation_, "shader.switch.full",
                                               L"Full shaders")
                                   : Localized(translation_, "shader.switch.lite",
                                               L"Lite shaders");
    brush_->SetColor(ColorText());
    render_target_->DrawTextW(
        label.c_str(), static_cast<UINT32>(label.size()), text_format_,
        D2D1::RectF(static_cast<float>(rect.left) + 8, static_cast<float>(rect.top),
                    static_cast<float>(rect.right) - 56, static_cast<float>(rect.bottom)),
        brush_, D2D1_DRAW_TEXT_OPTIONS_CLIP);

    const float track_left = static_cast<float>(rect.right) - 50.0f;
    const float track_top = static_cast<float>(rect.top) + 8.0f;
    const float track_right = static_cast<float>(rect.right) - 8.0f;
    const float track_bottom = static_cast<float>(rect.bottom) - 8.0f;
    brush_->SetColor(full ? ColorAccent()
                          : D2D1::ColorF(0.20f, 0.24f, 0.35f, 1.0f));
    render_target_->FillRoundedRectangle(
        D2D1::RoundedRect(D2D1::RectF(track_left, track_top, track_right, track_bottom),
                          8, 8),
        brush_);
    const float radius = 7.0f;
    const float center_x = full ? track_right - 10.0f : track_left + 10.0f;
    const float center_y = (track_top + track_bottom) / 2.0f;
    brush_->SetColor(ColorText());
    render_target_->FillEllipse(
        D2D1::Ellipse(D2D1::Point2F(center_x, center_y), radius, radius), brush_);
}

void MainWindow::Draw() {
    PAINTSTRUCT paint{};
    BeginPaint(hwnd_, &paint);
    if (!render_target_ || !brush_) {
        EndPaint(hwnd_, &paint);
        return;
    }
    render_target_->BeginDraw();
    hit_areas_.clear();
    keyboard_focus_rect_ = {};
    const auto physical_size = render_target_->GetSize();
    const float scale = Scale();
    const D2D1_SIZE_F size = D2D1::SizeF(
        physical_size.width / std::max(0.01f, scale),
        physical_size.height / std::max(0.01f, scale));
    render_target_->SetTransform(D2D1::Matrix3x2F::Scale(scale, scale));
    brush_->SetColor(ColorBackground());
    render_target_->FillRectangle(D2D1::RectF(0, 0, size.width, size.height), brush_);
    if (!background_frames_.empty() &&
        background_frame_index_ < background_frames_.size()) {
        ID2D1Bitmap* background_bitmap_ =
            background_frames_[background_frame_index_];
        const auto image = background_bitmap_->GetSize();
        const float image_scale =
            std::max(size.width / image.width, size.height / image.height);
        const float width = image.width * image_scale;
        const float height = image.height * image_scale;
        render_target_->DrawBitmap(
            background_bitmap_,
            D2D1::RectF((size.width - width) / 2, (size.height - height) / 2,
                        (size.width + width) / 2, (size.height + height) / 2),
            0.72f, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
    }

    const float left = 22.0f;
    const float right = size.width - 22.0f;
    const float top = 18.0f;
    const bool base_hover_enabled =
        !config_menu_open_ && !mode_menu_open_ && !xxmi_menu_open_;
    brush_->SetColor(ColorText());
    const std::wstring app_title =
        translation_.GetW("cxx.app.title", L"ReShade Launcher");
    render_target_->DrawTextW(app_title.c_str(), static_cast<UINT32>(app_title.size()),
                              title_format_,
                              D2D1::RectF(left, top, right, top + 30), brush_);
    brush_->SetColor(CurrentDisplayName().empty() ? ColorMuted() : ColorText());
    const auto config_rect =
        ScaledRect(22, 58, 300, 36);
    const HitArea config_hit{config_rect, Action::SelectConfig};
    const std::wstring config_text =
        CurrentDisplayName().empty()
            ? Localized(translation_, "ui.select_game", L"Select game")
            : CurrentDisplayName();
    ID2D1Bitmap* selected_icon = nullptr;
    if (selected_index_ >= 0 &&
        selected_index_ < static_cast<int>(profile_icons_.size())) {
        selected_icon = profile_icons_[selected_index_];
    }
    DrawButton(config_hit, config_text, false, false, selected_icon,
               base_hover_enabled);
    AddHitArea(Action::SelectConfig, config_rect);
    if (selected_index_ >= 0 && selected_index_ < static_cast<int>(profiles_.size())) {
        const auto& profile = profiles_[selected_index_];
        const std::string mode_key =
            "mode." + (profile.mode.empty() ? std::string("unknown") : profile.mode);
        std::vector<std::wstring> summary = {
            Localized(translation_, mode_key, Utf8ToWide(profile.mode)),
        };
        if (profile.data.contains("reshade_dll") &&
            profile.data["reshade_dll"].is_string() &&
            !profile.data["reshade_dll"].get<std::string>().empty()) {
            summary.push_back(translation_.GetW("reshade.enabled", L"ReShade enabled"));
        }
        if (profile.mode == "xxmi") {
            if (profile.data.contains("d3d11_path")) {
                const bool found = profile.data.value("d3d11_exists", false);
                summary.push_back(translation_.GetW(
                    found ? "modloader.installed" : "modloader.not_found",
                    found ? L"Mod loader installed" : L"Mod loader not found"));
            } else {
                std::wstring launcher =
                    translation_.GetW("config.launcher", L"Launcher: {name}");
                launcher = ReplaceToken(
                    launcher, L"{name}",
                    Utf8ToWide(profile.data.value(
                        "xxmi_exe_name",
                        translation_.Get("mode.unknown", "unknown"))));
                summary.push_back(std::move(launcher));
            }
        } else if (profile.mode == "builtin") {
            const bool found = profile.data.value("d3d11_exists", false);
            summary.push_back(translation_.GetW(
                found ? "modloader.installed" : "modloader.not_found",
                found ? L"Mod loader installed" : L"Mod loader not found"));
        } else if (profile.mode == "custom" &&
                   profile.data.contains("dll_files") &&
                   profile.data["dll_files"].is_array()) {
            std::wstring dll_count =
                translation_.GetW("dll.count", L"DLL files: {count}");
            dll_count = ReplaceToken(
                dll_count, L"{count}",
                std::to_wstring(profile.data["dll_files"].size()));
            summary.push_back(std::move(dll_count));
        }
        float summary_y = 104.0f;
        for (const auto& line : summary) {
            brush_->SetColor(ColorMuted());
            render_target_->DrawTextW(
                line.c_str(), static_cast<UINT32>(line.size()), small_format_,
                D2D1::RectF(left, summary_y, left + 310.0f, summary_y + 22.0f),
                brush_, D2D1_DRAW_TEXT_OPTIONS_CLIP);
            summary_y += 22.0f;
        }
    }
    if (xxmi_scanning_) {
        const auto cancel_rect = ScaledRect(22, 205, 132, 34);
        DrawButton({cancel_rect, Action::CancelXXMIScan},
                   translation_.GetW("dialog.cancel", L"Cancel"), false, false,
                   nullptr, base_hover_enabled);
        AddHitArea(Action::CancelXXMIScan, cancel_rect);
    }

    const auto launch_rect = ScaledRect(size.width - 190, size.height - 68, 168, 38);
    DrawButton(
        {launch_rect, Action::Launch},
        active_launch_id_ != 0
            ? translation_.GetW("cxx.launch.status.running", L"Game running")
            : translation_.GetW("button.launch", L"Launch"),
        active_launch_id_ != 0, false, nullptr, base_hover_enabled);
    if (active_launch_id_ == 0) AddHitArea(Action::Launch, launch_rect);

    const std::vector<std::pair<Action, std::wstring>> left_buttons = {
        {Action::FixShadow,
         translation_.GetW("button.fix_shadow", L"Fix upside-down shadows")},
        {Action::AddGame, translation_.GetW("button.add_game", L"Add game")},
        {Action::ForceClose, translation_.GetW("button.force_close", L"Force close")},
        {Action::Help, translation_.GetW("button.help", L"Help")},
    };
    float y = size.height - 232;
    for (const auto& [action, label] : left_buttons) {
        const auto rect = ScaledRect(22, y, 132, 34);
        DrawButton({rect, action}, label, false, false, nullptr,
                   base_hover_enabled);
        AddHitArea(action, rect);
        y += 42;
    }
    const auto settings_rect = ScaledRect(22, size.height - 40, 40, 30);
    DrawButton({settings_rect, Action::ChangeBackground}, L"", false, false,
               nullptr, base_hover_enabled);
    DrawPictureIcon(settings_rect);
    AddHitArea(Action::ChangeBackground, settings_rect);

    const std::vector<std::pair<Action, std::wstring>> right_buttons = {
        {Action::SaveModPreset,
         Localized(translation_, "button.save_mod_preset", L"Save Mod preset")},
        {Action::ModsFolder, translation_.GetW("button.mods_folder", L"Mods folder")},
        {Action::Update, Localized(translation_, "button.update", L"Check update")},
    };
    y = 58;
    for (const auto& [action, label] : right_buttons) {
        const auto rect = ScaledRect(size.width - 190, y, 168, 34);
        DrawButton({rect, action}, label, false, false, nullptr,
                   base_hover_enabled);
        AddHitArea(action, rect);
        y += 44;
    }
    const auto shader_rect = ScaledRect(size.width - 190, y, 168, 34);
    DrawShaderSwitch(shader_rect, shader_mode_, base_hover_enabled);
    AddHitArea(Action::ShaderToggle, shader_rect);

    brush_->SetColor(ColorMuted());
    render_target_->DrawTextW(Utf8ToWide(status_).c_str(),
                              static_cast<UINT32>(Utf8ToWide(status_).size()),
                              text_format_,
                              D2D1::RectF(left + 58, size.height - 39,
                                          right - 22, size.height - 8),
                              brush_);
    if (config_menu_open_) DrawConfigMenu();
    if (mode_menu_open_) DrawModeMenu();
    if (xxmi_menu_open_) DrawXXMIGameMenu();
    if (keyboard_focus_visible_ &&
        keyboard_focus_rect_.right > keyboard_focus_rect_.left) {
        const auto focus_rect = D2D1::RoundedRect(
            D2D1::RectF(static_cast<float>(keyboard_focus_rect_.left) + 2.0f,
                        static_cast<float>(keyboard_focus_rect_.top) + 2.0f,
                        static_cast<float>(keyboard_focus_rect_.right) - 2.0f,
                        static_cast<float>(keyboard_focus_rect_.bottom) - 2.0f),
            4.0f, 4.0f);
        brush_->SetColor(ColorAccent());
        render_target_->DrawRoundedRectangle(focus_rect, brush_, 1.0f);
    }
    DrawTooltip();
    render_target_->SetTransform(D2D1::Matrix3x2F::Identity());
    render_target_->EndDraw();
    EndPaint(hwnd_, &paint);
}

void MainWindow::DrawConfigMenu() {
    constexpr size_t kVisibleRows = 6;
    const size_t maximum_offset =
        profiles_.size() > kVisibleRows ? profiles_.size() - kVisibleRows : 0;
    config_menu_offset_ = std::min(config_menu_offset_, maximum_offset);
    const size_t end =
        std::min(profiles_.size(), config_menu_offset_ + kVisibleRows);
    const size_t visible_count = end - config_menu_offset_;
    const float refresh_y =
        profiles_.empty() ? 154.0f : 116.0f + visible_count * 42.0f;
    const float menu_height = refresh_y + 42.0f - 100.0f;
    const auto menu_rect = ScaledRect(22, 100, 360, menu_height);
    brush_->SetColor(D2D1::ColorF(0.035f, 0.06f, 0.12f, 0.98f));
    render_target_->FillRoundedRectangle(
        D2D1::RoundedRect(D2D1::RectF(static_cast<float>(menu_rect.left),
                                      static_cast<float>(menu_rect.top),
                                      static_cast<float>(menu_rect.right),
                                      static_cast<float>(menu_rect.bottom)),
                          6, 6),
        brush_);
    float y = 108;
    if (profiles_.empty()) {
        const auto empty_rect = ScaledRect(28, 108, 348, 34);
        brush_->SetColor(ColorMuted());
        render_target_->DrawTextW(
            Localized(translation_, "menu.no_config", L"No configurations").c_str(),
            static_cast<UINT32>(
                Localized(translation_, "menu.no_config", L"No configurations")
                    .size()),
            text_format_,
            D2D1::RectF(static_cast<float>(empty_rect.left) + 10,
                        static_cast<float>(empty_rect.top),
                        static_cast<float>(empty_rect.right) - 10,
                        static_cast<float>(empty_rect.bottom)),
            brush_, D2D1_DRAW_TEXT_OPTIONS_CLIP);
    } else {
        for (size_t i = config_menu_offset_; i < end; ++i) {
            const auto row = ScaledRect(28, y, 348, 34);
            const bool hover = PointInRect(mouse_, row);
            brush_->SetColor(hover ? ColorPanelHover() : ColorPanel());
            render_target_->FillRoundedRectangle(
                D2D1::RoundedRect(
                    D2D1::RectF(static_cast<float>(row.left),
                                static_cast<float>(row.top),
                                static_cast<float>(row.right),
                                static_cast<float>(row.bottom)),
                    4, 4),
                brush_);
            float row_text_left = static_cast<float>(row.left) + 10.0f;
            if (i < profile_icons_.size() && profile_icons_[i]) {
                const float icon_size =
                    std::min(24.0f, static_cast<float>(row.bottom - row.top) - 6.0f);
                render_target_->DrawBitmap(
                    profile_icons_[i],
                    D2D1::RectF(
                        static_cast<float>(row.left) + 5.0f,
                        static_cast<float>(row.top) +
                            (static_cast<float>(row.bottom - row.top) - icon_size) /
                                2.0f,
                        static_cast<float>(row.left) + 5.0f + icon_size,
                        static_cast<float>(row.top) +
                            (static_cast<float>(row.bottom - row.top) + icon_size) /
                                2.0f),
                    1.0f, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
                row_text_left = static_cast<float>(row.left) + 36.0f;
            }
            brush_->SetColor(ColorText());
            const std::wstring display = Utf8ToWide(profiles_[i].display_name);
            render_target_->DrawTextW(
                display.c_str(), static_cast<UINT32>(display.size()), text_format_,
                D2D1::RectF(row_text_left,
                            static_cast<float>(row.top),
                            static_cast<float>(row.right) - 100,
                            static_cast<float>(row.bottom)),
                brush_);
            const auto edit = RECT{row.right - 92, row.top + 4, row.right - 48,
                                   row.bottom - 4};
            const auto shortcut = RECT{row.right - 44, row.top + 4,
                                       row.right - 4, row.bottom - 4};
            DrawButton({edit, Action::ConfigEdit, static_cast<int>(i)},
                       Localized(translation_, "menu.edit", L"Edit"));
            DrawButton({shortcut, Action::ConfigShortcut, static_cast<int>(i)},
                       Localized(translation_, "menu.shortcut", L"Link"));
            AddHitArea(Action::SelectConfig, row, static_cast<int>(i));
            AddHitArea(Action::ConfigEdit, edit, static_cast<int>(i));
            AddHitArea(Action::ConfigShortcut, shortcut, static_cast<int>(i));
            y += 42;
        }
    }
    const auto refresh = ScaledRect(28, refresh_y, 348, 34);
    DrawButton({refresh, Action::ConfigRefresh},
               L"\u21BB " +
                   Localized(translation_, "menu.refresh", L"Refresh list"));
    AddHitArea(Action::ConfigRefresh, refresh);

}

void MainWindow::DrawModeMenu() {
    const auto panel = ScaledRect(260, 110, 320, 245);
    brush_->SetColor(D2D1::ColorF(0.035f, 0.06f, 0.12f, 0.98f));
    render_target_->FillRoundedRectangle(
        D2D1::RoundedRect(D2D1::RectF(static_cast<float>(panel.left),
                                      static_cast<float>(panel.top),
                                      static_cast<float>(panel.right),
                                      static_cast<float>(panel.bottom)),
                          8, 8),
        brush_);
    brush_->SetColor(ColorText());
    const std::wstring title =
        Localized(translation_, "launch_mode.title", L"Create launch method");
    render_target_->DrawTextW(title.c_str(), static_cast<UINT32>(title.size()),
                              title_format_,
                              D2D1::RectF(static_cast<float>(panel.left) + 16,
                                          static_cast<float>(panel.top) + 10,
                                          static_cast<float>(panel.right) - 10,
                                          static_cast<float>(panel.top) + 42),
                              brush_);
    const std::array<std::pair<Action, std::wstring>, 4> modes = {{
        {Action::ModeXXMI, Localized(translation_, "launch_mode.btn_xxmi", L"XXMI")},
        {Action::ModeBuiltin,
         Localized(translation_, "launch_mode.btn_builtin", L"Built-in")},
        {Action::ModeGame, Localized(translation_, "launch_mode.btn_game", L"Game")},
        {Action::ModeCustom,
         Localized(translation_, "launch_mode.btn_custom", L"Custom DLL")},
    }};
    float y = 157;
    for (const auto& [action, label] : modes) {
        const auto rect = ScaledRect(276, y, 288, 32);
        DrawButton({rect, action}, label);
        AddHitArea(action, rect);
        y += 38;
    }
    const auto check = ScaledRect(278, 318, 250, 24);
    const RECT checkbox{check.left, check.top + 4, check.left + 16, check.top + 20};
    brush_->SetColor(mode_reshade_enabled_ ? ColorAccent() : ColorPanel());
    render_target_->FillRoundedRectangle(
        D2D1::RoundedRect(
            D2D1::RectF(static_cast<float>(checkbox.left),
                        static_cast<float>(checkbox.top),
                        static_cast<float>(checkbox.right),
                        static_cast<float>(checkbox.bottom)),
            3, 3),
        brush_);
    if (mode_reshade_enabled_) {
        brush_->SetColor(ColorBackground());
        render_target_->DrawLine(
            D2D1::Point2F(static_cast<float>(checkbox.left) + 4.0f,
                          static_cast<float>(checkbox.top) + 8.0f),
            D2D1::Point2F(static_cast<float>(checkbox.left) + 7.0f,
                          static_cast<float>(checkbox.top) + 11.0f),
            brush_, 2.0f);
        render_target_->DrawLine(
            D2D1::Point2F(static_cast<float>(checkbox.left) + 7.0f,
                          static_cast<float>(checkbox.top) + 11.0f),
            D2D1::Point2F(static_cast<float>(checkbox.left) + 12.0f,
                          static_cast<float>(checkbox.top) + 5.0f),
            brush_, 2.0f);
    }
    const std::wstring reshade_label =
        Localized(translation_, "launch_mode.reshade_checkbox",
                  L"Enable ReShade64.dll");
    brush_->SetColor(ColorText());
    render_target_->DrawTextW(
        reshade_label.c_str(), static_cast<UINT32>(reshade_label.size()), small_format_,
        D2D1::RectF(static_cast<float>(check.left) + 24,
                    static_cast<float>(check.top), static_cast<float>(check.right),
                    static_cast<float>(check.bottom)),
        brush_, D2D1_DRAW_TEXT_OPTIONS_CLIP);
    AddHitArea(Action::ReshadeToggle, check);
}

void MainWindow::DrawXXMIGameMenu() {
    const float row_height = 36.0f;
    const float panel_height =
        72.0f + static_cast<float>(std::max<size_t>(1, xxmi_games_.size())) * 40.0f;
    const auto panel = ScaledRect(140, 78, 360,
                                  std::min(430.0f, panel_height));
    brush_->SetColor(D2D1::ColorF(0.035f, 0.06f, 0.12f, 0.98f));
    render_target_->FillRoundedRectangle(
        D2D1::RoundedRect(
            D2D1::RectF(static_cast<float>(panel.left),
                        static_cast<float>(panel.top),
                        static_cast<float>(panel.right),
                        static_cast<float>(panel.bottom)),
            8, 8),
        brush_);

    const std::wstring title =
        Localized(translation_, "xxmi_selector.title", L"Select game");
    brush_->SetColor(ColorText());
    render_target_->DrawTextW(
        title.c_str(), static_cast<UINT32>(title.size()), title_format_,
        D2D1::RectF(static_cast<float>(panel.left) + 16,
                    static_cast<float>(panel.top) + 8,
                    static_cast<float>(panel.right) - 12,
                    static_cast<float>(panel.top) + 42),
        brush_, D2D1_DRAW_TEXT_OPTIONS_CLIP);

    float y = 126.0f;
    for (size_t index = 0; index < xxmi_games_.size(); ++index) {
        const auto row = ScaledRect(156, y, 328, 34);
        if (y + row_height > static_cast<float>(panel.bottom) - 8.0f) {
            break;
        }
        const std::wstring display = Localized(
            translation_, xxmi_games_[index].name_key,
            Utf8ToWide(xxmi_games_[index].exe));
        DrawButton({row, Action::XXMIGame, static_cast<int>(index)}, display);
        AddHitArea(Action::XXMIGame, row, static_cast<int>(index));
        y += 40.0f;
    }
}

void MainWindow::OnClick(POINT point) {
    int index = -1;
    const auto action = HitTest(point, &index);
    if (action != Action::None) {
        for (size_t i = 0; i < hit_areas_.size(); ++i) {
            if (PointInRect(point, hit_areas_[i].rect) &&
                hit_areas_[i].action == action &&
                hit_areas_[i].index == index) {
                keyboard_focus_ = static_cast<int>(i);
                break;
            }
        }
    }
    if (xxmi_menu_open_) {
        xxmi_menu_open_ = false;
        if (action == Action::XXMIGame && index >= 0 &&
            index < static_cast<int>(xxmi_games_.size())) {
            BeginXXMIScan(xxmi_games_[index]);
        } else {
            InvalidateRect(hwnd_, nullptr, FALSE);
        }
        return;
    }
    if (mode_menu_open_) {
        if (action == Action::ReshadeToggle) {
            mode_reshade_enabled_ = !mode_reshade_enabled_;
            app_.globals()["reshade_enabled"] = mode_reshade_enabled_;
            app_.SaveGlobals();
            InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        if (action == Action::AddGame) {
            mode_menu_open_ = false;
            InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        if (action != Action::ModeXXMI && action != Action::ModeBuiltin &&
            action != Action::ModeGame && action != Action::ModeCustom) {
            mode_menu_open_ = false;
            InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        mode_menu_open_ = false;
        HandleMode(action);
        return;
    }
    if (config_menu_open_ && action != Action::SelectConfig &&
        action != Action::ConfigEdit && action != Action::ConfigShortcut &&
        action != Action::ConfigRefresh) {
        config_menu_open_ = false;
        InvalidateRect(hwnd_, nullptr, FALSE);
        return;
    }
    switch (action) {
        case Action::SelectConfig:
            if (index >= 0) {
                SelectProfile(index);
            } else {
                ShowConfigMenu();
            }
            break;
        case Action::ConfigEdit:
            if (index >= 0) {
                selected_index_ = index;
                EditSelectedProfile();
            }
            break;
        case Action::ConfigShortcut:
            if (index >= 0) {
                const bool created = ShortcutService::Create(
                    profiles_[index].display_name, profiles_[index].config_name,
                    profiles_[index].game_exe);
                std::wstring message = Localized(
                    translation_,
                    created ? "status.shortcut_created" : "status.shortcut_failed",
                    created ? L"Desktop shortcut created: {name}"
                            : L"Failed to create desktop shortcut: {name}");
                message = ReplaceToken(message, L"{name}",
                                       Utf8ToWide(profiles_[index].display_name));
                SetStatus(WideToUtf8(message));
            }
            break;
        case Action::ConfigRefresh:
            RefreshProfiles(true);
            config_menu_open_ = false;
            SetStatus(translation_.Get("status.ready", "Ready"));
            break;
        case Action::CancelXXMIScan:
            if (xxmi_scanning_) {
                xxmi_scan_cancel_ = true;
                SetStatus(translation_.Get("status.cancelled", "Cancelled"));
            }
            break;
        case Action::Launch: StartLaunch(); break;
        case Action::FixShadow: ToggleShadowFix(); break;
        case Action::AddGame: OpenAddMode(); break;
        case Action::ForceClose:
            if (active_launch_id_ != 0 && !active_session_) {
                ShowInfo(
                    hwnd_,
                    translation_.GetW("cxx.launch.dialog.running_title",
                                      L"Game running"),
                    translation_.GetW("cxx.launch.status.launching",
                                      L"Launching..."));
            } else if (active_session_) {
                StopActiveSession();
            } else if (selected_index_ >= 0) {
                const auto process_ids = ProcessManager::FindProcessIdsByName(
                    profiles_[selected_index_].game_exe.filename().wstring());
                if (process_ids.size() == 1) {
                    processes_.Terminate(process_ids.front());
                } else if (process_ids.size() > 1) {
                    ShowInfo(
                        hwnd_,
                        translation_.GetW("dialog.info", L"Information"),
                        translation_.GetW(
                            "cxx.launch.force_close_multiple",
                            L"Multiple game processes have the same executable name. Start from this launcher so the correct process can be closed."));
                }
            }
            break;
        case Action::Help:
            ShowHelp(hwnd_, translation_, background_path_);
            break;
        case Action::ChangeBackground: ChooseBackground(); break;
        case Action::SaveModPreset: {
            const int choice = ShowChoiceDialog(
                hwnd_,
                translation_.GetW("mod_preset.title", L"Save Mod preset"),
                translation_.GetW("mod_preset.header",
                                  L"Choose Mods to save."),
                translation_.GetW("mod_preset.all_mods", L"All Mods"),
                translation_.GetW("mod_preset.selected_mod",
                                  L"Selected Mods"),
                translation_.GetW("dialog.cancel", L"Cancel"));
            if (choice == 1001) {
                StartModPreset();
            } else if (choice == 1002) {
                StartModPresetSelect();
            }
            break;
        }
        case Action::ModsFolder: ResolveAndOpenMods(); break;
        case Action::ShaderToggle: ToggleShaderMode(); break;
        case Action::Update:
            if (busy_ || active_launch_id_ != 0) {
                ShowInfo(hwnd_,
                         translation_.GetW("dialog.info", L"Information"),
                         translation_.GetW(
                             "cxx.update.game_running",
                             L"Close the running game before updating."));
            } else {
                RunManualUpdate(hwnd_, app_, translation_);
            }
            break;
        default: break;
    }
}

std::wstring MainWindow::CurrentDisplayName() const {
    if (selected_index_ >= 0 && selected_index_ < static_cast<int>(profiles_.size())) {
        return Utf8ToWide(profiles_[selected_index_].display_name);
    }
    return L"";
}

std::filesystem::path MainWindow::CurrentGameExecutable() const {
    if (selected_index_ < 0) return {};
    return profiles_[selected_index_].game_exe;
}

void MainWindow::RefreshProfiles(bool preserve_selection) {
    std::string previous;
    if (preserve_selection && selected_index_ >= 0 &&
        selected_index_ < static_cast<int>(profiles_.size())) {
        previous = profiles_[selected_index_].config_name;
    }
    profiles_ = configs_.ListProfiles();
    RebuildProfileIcons();
    std::error_code time_error;
    const auto modified =
        std::filesystem::last_write_time(app_.launch_config_dir(), time_error);
    if (!time_error) {
        config_dir_time_ = modified;
        config_dir_time_valid_ = true;
    }
    selected_index_ = profiles_.empty() ? -1 : 0;
    if (!previous.empty()) {
        const auto it = std::find_if(profiles_.begin(), profiles_.end(),
                                     [&](const auto& p) { return p.config_name == previous; });
        if (it != profiles_.end()) selected_index_ = static_cast<int>(std::distance(profiles_.begin(), it));
    } else {
        const auto last = app_.LastSelectedConfig();
        const auto it = std::find_if(profiles_.begin(), profiles_.end(),
                                     [&](const auto& p) { return p.config_name == last; });
        if (it != profiles_.end()) selected_index_ = static_cast<int>(std::distance(profiles_.begin(), it));
    }
    UpdateWindowIcons();
    UpdateTrayIcon();
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::SelectProfile(int index) {
    if (index < 0 || index >= static_cast<int>(profiles_.size())) return;
    selected_index_ = index;
    config_menu_open_ = false;
    app_.SetLastSelectedConfig(profiles_[index].config_name);
    SetStatus(profiles_[index].display_name);
    UpdateWindowIcons();
    UpdateTrayIcon();
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::ToggleShadowFix() {
    if (selected_index_ < 0 ||
        selected_index_ >= static_cast<int>(profiles_.size())) {
        SetStatus(translation_.Get("status.error.no_config",
                                   "Error: select a configuration first"));
        return;
    }

    const auto& profile = profiles_[selected_index_];
    const auto game_stem = profile.game_exe.stem().wstring();
    std::vector<std::filesystem::path> candidates;
    auto add_parent_candidate = [&](const char* key) {
        if (!profile.data.contains(key) || !profile.data[key].is_string()) return;
        const std::filesystem::path value =
            Utf8ToWide(profile.data[key].get<std::string>());
        const auto parent =
            FileExists(value) ? value.parent_path() : value;
        candidates.push_back(parent / L"ReShade.ini");
    };
    add_parent_candidate("game_dir");
    add_parent_candidate("launch_program");
    if (!game_stem.empty()) {
        candidates.push_back(app_.root() / game_stem / L"ReShade.ini");
        candidates.push_back(app_.reshade_dir() / L"reshade_config" /
                             (game_stem + L".ini"));
    }

    std::set<std::wstring> visited;
    size_t changed_files = 0;
    for (const auto& candidate : candidates) {
        const std::wstring key = ToLower(candidate.lexically_normal().wstring());
        if (key.empty() || !visited.insert(key).second) continue;
        const auto contents = ReadUtf8(candidate);
        if (!contents) continue;
        std::string updated = *contents;
        constexpr std::string_view kEnabled =
            "RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=1";
        constexpr std::string_view kDisabled =
            "RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=0";
        const bool has_enabled = updated.find(kEnabled) != std::string::npos;
        const bool has_disabled = updated.find(kDisabled) != std::string::npos;
        if (!has_enabled && !has_disabled) continue;
        while (true) {
            const auto position = updated.find(has_enabled ? kEnabled : kDisabled);
            if (position == std::string::npos) break;
            updated.replace(position, (has_enabled ? kEnabled : kDisabled).size(),
                            has_enabled ? kDisabled : kEnabled);
        }
        if (updated != *contents && WriteUtf8Atomic(candidate, updated)) {
            ++changed_files;
        }
    }

    if (changed_files == 0) {
        ShowInfo(hwnd_, translation_.GetW("button.fix_shadow", L"Fix shadows"),
                 translation_.GetW(
                     "status.depth_not_found",
                     L"No editable ReShade.ini depth setting was found."));
        return;
    }
    SetStatus(translation_.Get("status.depth_toggled",
                               "Depth parameter toggled"));
}

void MainWindow::StartLaunch(bool shortcut) {
    if (selected_index_ < 0) {
        SetStatus(translation_.Get("status.error.no_config",
                                   "Error: select a configuration first"));
        return;
    }
    if (!shortcut) launched_by_shortcut_ = false;
    if (busy_) return;
    if (active_launch_id_ != 0) {
        ShowInfo(hwnd_, translation_.GetW("cxx.launch.dialog.running_title",
                                          L"Game running"),
                 translation_.GetW(
                     "cxx.launch.dialog.running_message",
                     L"Close the running game process first?"));
        return;
    }
    const auto& profile = profiles_[selected_index_];
    DWORD stale_pid = 0;
    stale_pid = ProcessManager::FindProcessIdByPath(profile.game_exe);
    if (stale_pid != 0) {
        if (!Confirm(hwnd_,
                     translation_.GetW("cxx.launch.dialog.running_title",
                                       L"Game running"),
                     translation_.GetW("cxx.launch.dialog.running_message",
                                       L"Close the running game process first?"))) {
            return;
        }
    }
    const std::uint64_t launch_id = next_launch_id_++;
    active_launch_id_ = launch_id;
    busy_ = true;
    SetStatus(translation_.Get("cxx.launch.status.launching", "Launching..."));
    const std::string config_name = profile.config_name;
    const std::string game_name = profile.game_exe.filename().string();
    const Json config = profile.data;
    const auto app_root = app_.root();
    HWND window = hwnd_;
    std::thread([config, config_name, game_name, launch_id, window, app_root,
                 stale_pid] {
        AppData thread_app(app_root);
        thread_app.Load();
        ProcessManager thread_processes(thread_app);
        LaunchResult result;
        try {
            bool stale_process_running = false;
            if (stale_pid) {
                thread_processes.Terminate(stale_pid);
                for (int attempt = 0;
                     attempt < 25 && thread_processes.IsRunning(stale_pid);
                     ++attempt) {
                    Sleep(200);
                }
                stale_process_running =
                    thread_processes.IsRunning(stale_pid);
            }
            if (stale_process_running) {
                result.error = "The previous game process did not exit";
            } else {
                result = thread_processes.Launch(
                    config, [window](const std::string& text) {
                        auto* value = new std::string(text);
                        if (!PostMessageW(window, WM_APP + 20, 0,
                                          reinterpret_cast<LPARAM>(value))) {
                            delete value;
                        }
                    });
            }
        } catch (const std::exception& error) {
            result.error = error.what();
        } catch (...) {
            result.error = "Unexpected launch error";
        }
        auto* payload = new LaunchPayload{
            launch_id, result.ok(), result.error, config_name, game_name,
            std::move(result.session)};
        if (!PostMessageW(window, kLaunchDone, 0,
                          reinterpret_cast<LPARAM>(payload))) {
            if (payload->session.Valid()) {
                thread_processes.Terminate(payload->session.target_pid);
                thread_processes.Terminate(payload->session.root_pid);
                for (DWORD pid : payload->session.extra_pids) {
                    if (pid != payload->session.root_pid &&
                        pid != payload->session.target_pid) {
                        thread_processes.Terminate(pid);
                    }
                }
            }
            delete payload;
        }
    }).detach();
}

void MainWindow::OnLaunchFinished(LaunchPayload* payload) {
    std::unique_ptr<LaunchPayload> owned(payload);
    if (!payload) return;
    if (payload->launch_id != active_launch_id_) {
        if (payload->session.Valid()) {
            processes_.Terminate(payload->session.target_pid);
            processes_.Terminate(payload->session.root_pid);
            for (DWORD pid : payload->session.extra_pids) {
                if (pid != payload->session.root_pid &&
                    pid != payload->session.target_pid) {
                    processes_.Terminate(pid);
                }
            }
        }
        return;
    }
    busy_ = false;
    if (!payload->ok) {
        active_launch_id_ = 0;
        std::wstring status = Localized(
            translation_, "cxx.launch.status.failed", L"Launch failed: {error}");
        status = ReplaceToken(status, L"{error}", Utf8ToWide(payload->error));
        SetStatus(WideToUtf8(status));
        const std::wstring dialog_message = ReplaceToken(
            translation_.GetW(
                "cxx.launch.dialog.failed_message",
                L"The game could not be launched.\n\n{error}"),
            L"{error}", Utf8ToWide(payload->error));
        ShowError(hwnd_,
                  translation_.GetW("cxx.launch.dialog.failed_title", L"Launch failed"),
                  dialog_message);
        return;
    }
    active_session_ = std::move(payload->session);
    game_window_seen_ = false;
    SetStatus(translation_.Get("cxx.launch.status.running", "Game running"));
    UpdateTrayIcon();
    HANDLE wait_handle =
        OpenProcess(SYNCHRONIZE, FALSE, active_session_->target_pid);
    if (!wait_handle &&
        active_session_->target_pid == active_session_->root_pid) {
        DuplicateHandle(GetCurrentProcess(), active_session_->process,
                        GetCurrentProcess(), &wait_handle, SYNCHRONIZE, FALSE, 0);
    }
    if (wait_handle) {
        poll_target_exit_ = false;
        const std::uint64_t launch_id = active_launch_id_;
        HWND window = hwnd_;
        wait_thread_ = std::thread([wait_handle, launch_id, window] {
            WaitForSingleObject(wait_handle, INFINITE);
            CloseHandle(wait_handle);
            PostMessageW(window, kGameExited,
                         static_cast<WPARAM>(launch_id), 0);
        });
        wait_thread_.detach();
    } else {
        poll_target_exit_ = true;
    }
    bool center = false;
    int duration = 10;
    const auto profile_it = std::find_if(
        profiles_.begin(), profiles_.end(),
        [&](const auto& item) {
            return item.config_name == payload->config_name;
        });
    if (profile_it != profiles_.end()) {
        center = profile_it->data.value("force_center_window", false);
        duration =
            profile_it->data.value("center_window_duration", 10);
    }
    if (center) {
        if (center_thread_.joinable()) center_thread_.join();
        center_stop_ = false;
        DWORD target = active_session_->target_pid;
        center_thread_ = std::thread([this, target, duration] {
            ProcessManager::CenterWindowsForPid(target, duration, &center_stop_);
        });
    }
}

void MainWindow::OnGameExited(std::uint64_t launch_id) {
    if (launch_id == 0 || launch_id != active_launch_id_) return;
    StopActiveSession();
    busy_ = false;
    center_stop_ = true;
    SetStatus(translation_.Get("cxx.launch.status.exited", "Game exited"));
    if (launched_by_shortcut_) {
        DestroyWindow(hwnd_);
    } else {
        ShowFromTray();
        InvalidateRect(hwnd_, nullptr, FALSE);
    }
}

void MainWindow::StopActiveSession() {
    if (!active_session_) {
        active_launch_id_ = 0;
        return;
    }
    center_stop_ = true;
    if (active_session_->target_pid) {
        processes_.Terminate(active_session_->target_pid);
    }
    if (active_session_->root_pid &&
        active_session_->root_pid != active_session_->target_pid) {
        processes_.Terminate(active_session_->root_pid);
    }
    for (DWORD pid : active_session_->extra_pids) {
        if (pid != active_session_->root_pid &&
            pid != active_session_->target_pid) {
            processes_.Terminate(pid);
        }
    }
    active_session_.reset();
    active_launch_id_ = 0;
    poll_target_exit_ = false;
}

void MainWindow::CheckGameWindow() {
    if (!initial_window_resized_) {
        initial_window_resized_ = true;
        const UINT current_dpi = GetDpiForWindow(hwnd_);
        const UINT old_dpi = dpi_;
        if (current_dpi) dpi_ = current_dpi;
        RECT logical{0, 0, MulDiv(640, dpi_, 96), MulDiv(530, dpi_, 96)};
        AdjustWindowRectExForDpi(&logical, WS_OVERLAPPEDWINDOW, FALSE,
                                 WS_EX_APPWINDOW, dpi_);
        RECT current{};
        GetWindowRect(hwnd_, &current);
        SetWindowPos(hwnd_, nullptr, current.left, current.top,
                     logical.right - logical.left, logical.bottom - logical.top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
        if (old_dpi != dpi_) {
            DiscardGraphics();
            InitializeGraphics();
            RebuildProfileIcons();
        }
    }
    if (!active_session_) return;
    if (poll_target_exit_ &&
        !ProcessManager::IsProcessIdPresent(active_session_->target_pid)) {
        OnGameExited(active_launch_id_);
        return;
    }
    if (game_window_seen_) return;
    if (ProcessManager::FindMainWindowPid(active_session_->target_pid) != 0) {
        game_window_seen_ = true;
        HideToTray();
    }
}

void MainWindow::OpenAddMode() {
    HideTooltip();
    mode_menu_open_ = !mode_menu_open_;
    config_menu_open_ = false;
    xxmi_menu_open_ = false;
    keyboard_focus_ = -1;
    keyboard_focus_visible_ = false;
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::CompleteProfileCreation(const LaunchProfile& profile,
                                         std::string_view success_message_key,
                                         std::wstring_view fallback_message,
                                         bool show_success) {
    if (!profile.save_error.empty()) {
        RefreshProfiles(true);
        std::wstring message = translation_.GetW(
            "cxx.config.create_failed",
            L"Could not create the configuration.\n\n{error}");
        message = ReplaceToken(message, L"{error}",
                               Utf8ToWide(profile.save_error));
        ShowError(hwnd_,
                  translation_.GetW("dialog.error", L"Error"),
                  message);
        return;
    }
    app_.SetLastSelectedConfig(profile.config_name);
    RefreshProfiles(false);
    const auto it = std::find_if(profiles_.begin(), profiles_.end(),
                                 [&](const auto& item) {
                                     return item.config_name == profile.config_name;
                                 });
    if (it != profiles_.end()) {
        selected_index_ = static_cast<int>(std::distance(profiles_.begin(), it));
    }
    const std::wstring display = Utf8ToWide(profile.display_name);
    const bool shortcut = ShortcutService::Create(profile.display_name, profile.config_name,
                                                  profile.game_exe);
    std::wstring status =
        Localized(translation_, "status.config_created", L"Configuration created: {name}");
    status = ReplaceToken(status, L"{name}", display);
    SetStatus(WideToUtf8(shortcut
                             ? status
                             : ReplaceToken(
                                   Localized(translation_, "status.shortcut_failed",
                                             L"Failed to create desktop shortcut: {name}"),
                                   L"{name}", display)));
    if (!shortcut || !show_success) {
        InvalidateRect(hwnd_, nullptr, FALSE);
        return;
    }
    std::wstring message =
        Localized(translation_, success_message_key, fallback_message);
    message = ReplaceToken(message, L"{name}", display);
    message = ReplaceToken(message, L"{path}",
                           app_.config_path(profile.config_name).wstring());
    ShowInfo(hwnd_,
             translation_.GetW("dialog.success", L"Success"),
             message);
}

void MainWindow::OpenXXMIGameSelection(const std::filesystem::path& xxmi_exe) {
    HideTooltip();
    pending_xxmi_exe_ = xxmi_exe;
    xxmi_games_.clear();
    auto name_key_for = [](std::string exe) {
        exe = ToLower(std::move(exe));
        if (exe == "yuanshen.exe") return std::string("game_name_xxmi_yuanshen");
        if (exe == "genshinimpact.exe") return std::string("game_name_xxmi_genshin");
        if (exe == "bh3.exe") return std::string("game_name_xxmi_bh3");
        if (exe == "starrail.exe") return std::string("game_name_xxmi_starrail");
        if (exe == "zenlesszonezero.exe") return std::string("game_name_xxmi_zzz");
        if (exe == "client-win64-shipping.exe")
            return std::string("game_name_xxmi_wuthering");
        if (exe == "endfield.exe") return std::string("game_name_xxmi_endfield");
        return std::string{};
    };
    const auto version = ReadJson(app_.resource_path(L"version.json"));
    if (version && version->contains("xxmi_games") &&
        (*version)["xxmi_games"].is_array()) {
        for (const auto& item : (*version)["xxmi_games"]) {
            if (!item.is_object() || !item.contains("exe") ||
                !item["exe"].is_string()) {
                continue;
            }
            XXMIGameOption option;
            option.exe = item["exe"].get<std::string>();
            if (item.contains("name_key") && item["name_key"].is_string()) {
                option.name_key = item["name_key"].get<std::string>();
            }
            xxmi_games_.push_back(std::move(option));
        }
    }
    if (xxmi_games_.empty() && version &&
        version->contains("xxmi_game_exe_name") &&
        (*version)["xxmi_game_exe_name"].is_array()) {
        for (const auto& item : (*version)["xxmi_game_exe_name"]) {
            if (!item.is_string()) continue;
            XXMIGameOption option;
            option.exe = item.get<std::string>();
            option.name_key = name_key_for(option.exe);
            xxmi_games_.push_back(std::move(option));
        }
    }
    if (xxmi_games_.empty() && version) {
        for (const auto& [key, value] : version->items()) {
            (void)value;
            constexpr std::string_view prefix = "xxmi_launch_args_";
            if (!key.starts_with(prefix) || key.size() == prefix.size()) continue;
            XXMIGameOption option;
            option.exe = key.substr(prefix.size()) + ".exe";
            option.name_key = name_key_for(option.exe);
            xxmi_games_.push_back(std::move(option));
        }
    }
    if (xxmi_games_.empty()) {
        ShowError(hwnd_,
                  translation_.GetW("dialog.error", L"Error"),
                  translation_.GetW(
                      "message.xxmi_no_games",
                      L"No XXMI games are defined in version.json."));
        return;
    }
    mode_menu_open_ = false;
    config_menu_open_ = false;
    xxmi_menu_open_ = true;
    keyboard_focus_ = -1;
    keyboard_focus_visible_ = false;
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::BeginXXMIScan(const XXMIGameOption& game) {
    if (xxmi_scanning_ || pending_xxmi_exe_.empty()) return;
    if (xxmi_scan_thread_.joinable()) xxmi_scan_thread_.join();
    xxmi_scan_cancel_ = false;
    xxmi_scanning_ = true;
    SetStatus(translation_.Get("message.xxmi_scanning", "Scanning game files..."));
    const std::filesystem::path xxmi_exe = pending_xxmi_exe_;
    const std::string game_exe = game.exe;
    const std::wstring display =
        Localized(translation_, game.name_key, Utf8ToWide(game.exe));
    HWND window = hwnd_;
    xxmi_scan_thread_ = std::thread([this, xxmi_exe, game_exe, display, window] {
        const auto found =
            XXMIScanner::FindGameDeep(Utf8ToWide(game_exe), xxmi_exe.wstring(),
                                      &xxmi_scan_cancel_);
        auto* payload = new XXMIScanPayload;
        payload->xxmi_exe = xxmi_exe;
        payload->game_exe_name = game_exe;
        payload->display_name = WideToUtf8(display);
        if (found) payload->game_exe = *found;
        if (!PostMessageW(window, kXXMIScanDone, 0,
                          reinterpret_cast<LPARAM>(payload))) {
            delete payload;
        }
    });
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::OnXXMIScanFinished(XXMIScanPayload* payload) {
    std::unique_ptr<XXMIScanPayload> owned(payload);
    if (xxmi_scan_thread_.joinable()) xxmi_scan_thread_.join();
    xxmi_scanning_ = false;
    if (!payload || xxmi_scan_cancel_.load()) {
        xxmi_scan_cancel_ = false;
        SetStatus(translation_.Get("status.cancelled", "Cancelled"));
        InvalidateRect(hwnd_, nullptr, FALSE);
        return;
    }
    if (payload->game_exe.empty()) {
        std::wstring question =
            Localized(translation_, "message.xxmi_not_found",
                      L"{exe} was not found. Select the game executable manually?");
        question = ReplaceToken(question, L"{exe}", Utf8ToWide(payload->game_exe_name));
        if (!Confirm(hwnd_, translation_.GetW("dialog.info", L"Information"),
                     question)) {
            SetStatus(translation_.Get("status.ready", "Ready"));
            return;
        }
        const std::wstring programs_label =
            translation_.GetW("cxx.file.filter.programs", L"Programs");
        const std::wstring all_label =
            translation_.GetW("cxx.file.filter.all_files", L"All files");
        const COMDLG_FILTERSPEC exe_filter[] = {
            {programs_label.c_str(), L"*.exe"},
            {all_label.c_str(), L"*.*"}};
        auto selected = PickFile(
            hwnd_, translation_.GetW("cxx.file.select_game", L"Select game").c_str(),
            exe_filter, 2);
        if (!selected) {
            SetStatus(translation_.Get("status.ready", "Ready"));
            return;
        }
        payload->game_exe = *selected;
    }
    auto created =
        configs_.CreateXXMI(payload->game_exe, payload->xxmi_exe, mode_reshade_enabled_);
    const std::wstring display = Utf8ToWide(payload->display_name);
    if (created.save_error.empty() &&
        !app_.SetCustomData(created.config_name, WideToUtf8(display), "")) {
        created.save_error =
            "Cannot save custom configuration data: " +
            WideToUtf8(
                (app_.custom_data_dir() / L"custom_configs.json").wstring());
    }
    created.display_name = WideToUtf8(display);
    CompleteProfileCreation(created, "message.xxmi_success",
                            L"XXMI configuration created.\nConfiguration: {path}");
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::HandleMode(Action mode) {
    const std::wstring programs_filter =
        translation_.GetW("cxx.file.filter.programs", L"Programs");
    const std::wstring dll_filter_text =
        translation_.GetW("cxx.file.filter.dll_files", L"DLL files");
    const std::wstring all_filter =
        translation_.GetW("cxx.file.filter.all_files", L"All files");
    const COMDLG_FILTERSPEC exe_filter[] = {{programs_filter.c_str(), L"*.exe"},
                                            {all_filter.c_str(), L"*.*"}};
    const COMDLG_FILTERSPEC dll_filter[] = {{dll_filter_text.c_str(), L"*.dll"},
                                            {all_filter.c_str(), L"*.*"}};
    if (mode == Action::ModeXXMI) {
        while (true) {
            auto xxmi = PickFile(
                hwnd_,
                translation_.GetW("cxx.file.select_xxmi",
                                  L"Select XXMI Launcher.exe")
                    .c_str(),
                exe_filter, 2);
            if (!xxmi) return;
            if (_wcsicmp(xxmi->filename().c_str(), L"XXMI Launcher.exe") == 0) {
                OpenXXMIGameSelection(*xxmi);
                return;
            }
            ShowError(
                hwnd_, translation_.GetW("dialog.error", L"Error"),
                translation_.GetW(
                    "message.xxmi_invalid",
                    L"The selected file is not a valid XXMI Launcher.exe."));
        }
    }

    if (mode == Action::ModeCustom) {
        auto dlls = PickFiles(
            hwnd_,
            translation_.GetW("cxx.file.select_dlls", L"Select DLLs to inject")
                .c_str(),
            dll_filter, 2);
        if (dlls.empty()) {
            ShowInfo(hwnd_, translation_.GetW("dialog.info", L"Information"),
                     translation_.GetW("message.custom_no_dlls",
                                       L"No DLL files were added."));
            return;
        }
        auto game = PickFile(
            hwnd_,
            translation_.GetW("cxx.file.select_game", L"Select game executable")
                .c_str(),
            exe_filter, 2);
        if (!game) return;
        auto created =
            configs_.CreateCustom(*game, dlls, mode_reshade_enabled_);
        CompleteProfileCreation(created, "message.custom_success",
                                L"Custom configuration created.\nConfiguration: {path}");
        return;
    }

    auto game = PickFile(
        hwnd_,
        translation_.GetW("cxx.file.select_game", L"Select game executable").c_str(),
        exe_filter, 2);
    if (!game) return;
    if (mode == Action::ModeBuiltin) {
        const auto loader_info = configs_.ResolveBuiltinModLoader(*game);
        auto loader_dll =
            app_.mod_loader_dir() / Utf8ToWide(loader_info.folder_name) /
            L"d3d11.dll";
        bool has_loader = FileExists(loader_dll);
        bool download_cancelled = false;
        std::wstring loader_error;
        if (!has_loader && loader_info.downloadable()) {
            SetStatus(translation_.Get("cxx.download.starting",
                                       "Downloading..."));
            InvalidateRect(hwnd_, nullptr, FALSE);
            UpdateWindow(hwnd_);

            const auto archive =
                std::filesystem::temp_directory_path() /
                (L"ReShadeLauncher-" +
                 Utf8ToWide(loader_info.folder_name) + L".zip");
            std::string download_error;
            const bool downloaded = DownloadGitHubAsset(
                hwnd_, translation_,
                translation_.GetW("launch_mode.builtin", L"Built-in mode"),
                loader_info.download_url, loader_info.download_size,
                loader_info.sha256, archive, &download_error,
                &download_cancelled);
            if (downloaded) {
                std::string install_error;
                has_loader = mod_loaders_.InstallArchive(
                    archive, loader_info.folder_name, &install_error);
                if (!has_loader) {
                    download_error = std::move(install_error);
                    loader_error = Utf8ToWide(download_error);
                }
            } else if (!download_cancelled) {
                loader_error = Utf8ToWide(download_error);
            }
            std::error_code cleanup_error;
            std::filesystem::remove(archive, cleanup_error);
            SetStatus(translation_.Get("status.ready", "Ready"));
        }
        if (download_cancelled) {
            InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }

        auto created = configs_.CreateBuiltin(*game, mode_reshade_enabled_);
        has_loader = created.data.value("d3d11_exists", false);
        if (!has_loader) {
            std::wstring message = translation_.GetW(
                "message.builtin_no_d3d11",
                L"No Mod loader for this game is available from GitHub. "
                L"The target folder will be opened so you can add one "
                L"manually.");
            if (!loader_error.empty()) {
                message += L"\n\n" + loader_error;
            }
            ShowInfo(hwnd_, translation_.GetW("dialog.info", L"Information"),
                     message);
            CompleteProfileCreation(
                created, "message.builtin_success_with_d3d11",
                L"Built-in configuration created.\nConfiguration: {path}", false);
            OpenInExplorer(app_.mod_loader_dir() /
                           Utf8ToWide(loader_info.folder_name));
        } else {
            CompleteProfileCreation(
                created, "message.builtin_success_with_d3d11",
                L"Built-in configuration created.\nConfiguration: {path}");
        }
    } else if (mode == Action::ModeGame) {
        auto created = configs_.CreateGame(*game, mode_reshade_enabled_);
        CompleteProfileCreation(created, "message.reshade_success",
                                L"Game configuration created.\nConfiguration: {path}");
    }
}

void MainWindow::EditSelectedProfile() {
    if (selected_index_ < 0) return;
    const auto profile = profiles_[selected_index_];
    auto result = EditProfile(hwnd_, translation_, profile.config_name, profile.data,
                              profile.display_name, profile.custom_icon,
                              background_path_);
    if (!result) return;
    if (result->deleted) {
        const bool config_deleted =
            configs_.Delete(profile.config_name);
        const bool custom_deleted =
            app_.RemoveCustomData(profile.config_name);
        if (!config_deleted || !custom_deleted) {
            ShowError(
                hwnd_,
                translation_.GetW("dialog.error", L"Error"),
                Utf8ToWide("Cannot completely delete configuration: " +
                           profile.config_name));
            RefreshProfiles(true);
            return;
        }
    } else {
        if (!configs_.Save(profile.config_name, result->config)) {
            std::wstring message = translation_.GetW(
                "cxx.config.save_failed",
                L"Could not save the configuration.\n\n{error}");
            message = ReplaceToken(
                message, L"{error}",
                app_.config_path(profile.config_name).wstring());
            ShowError(
                hwnd_,
                translation_.GetW("dialog.error", L"Error"),
                message);
            return;
        }
        if (!app_.SetCustomData(profile.config_name,
                                result->display_name,
                                result->custom_icon)) {
            ShowError(
                hwnd_,
                translation_.GetW("dialog.error", L"Error"),
                Utf8ToWide(
                    "Cannot save custom configuration data: " +
                    WideToUtf8(
                        (app_.custom_data_dir() /
                         L"custom_configs.json")
                            .wstring())));
            return;
        }
    }
    RefreshProfiles(true);
}

void MainWindow::ShowConfigMenu() {
    HideTooltip();
    config_menu_open_ = !config_menu_open_;
    mode_menu_open_ = false;
    keyboard_focus_ = -1;
    keyboard_focus_visible_ = false;
    if (config_menu_open_) {
        std::error_code time_error;
        const auto modified =
            std::filesystem::last_write_time(app_.launch_config_dir(), time_error);
        if (time_error ||
            !config_dir_time_valid_ ||
            modified != config_dir_time_) {
            RefreshProfiles(true);
        }
    }
    if (config_menu_open_ && selected_index_ >= 0 && profiles_.size() > 6) {
        config_menu_offset_ =
            static_cast<size_t>(std::max(0, selected_index_ - 2));
    } else {
        config_menu_offset_ = 0;
    }
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::ChooseBackground() {
    const std::wstring image_label =
        translation_.GetW("cxx.file.filter.images", L"Images");
    const std::wstring all_label =
        translation_.GetW("cxx.file.filter.all_files", L"All files");
    const COMDLG_FILTERSPEC filters[] = {
        {image_label.c_str(), L"*.png;*.jpg;*.jpeg;*.bmp;*.gif"},
        {all_label.c_str(), L"*.*"}};
    auto path = PickFile(
        hwnd_,
        translation_.GetW("cxx.file.select_background", L"Select background image")
            .c_str(),
        filters, 2);
    if (!path) return;
    app_.SetBackgroundImage(*path);
    background_path_ = path->wstring();
    LoadBackground();
    InvalidateRect(hwnd_, nullptr, FALSE);
    ShowInfo(hwnd_, translation_.GetW("dialog.info", L"Information"),
             translation_.GetW(
                 "message.background_updated",
                 L"Background image updated."));
}

void MainWindow::ToggleShaderMode() {
    if (busy_) return;
    const auto current = shader_mode_;
    const std::wstring title =
        translation_.GetW("cxx.shader.title", L"Shader mode");
    if (current == ShaderPackManager::Mode::Full) {
        if (!Confirm(hwnd_, title,
                     translation_.GetW(
                         "shader.confirm_lite",
                         L"Switch to lite shaders and keep only preset-used files?"))) {
            return;
        }
        SetStatus(translation_.Get("shader.lite_running", "Pruning shaders..."));
        std::string error;
        if (!shaders_.SetMode(ShaderPackManager::Mode::Lite, false, &error)) {
            const auto message = LocalizedShaderError(translation_, error);
            SetStatus(WideToUtf8(message));
            ShowError(hwnd_, title, message);
        } else {
            shader_mode_ = ShaderPackManager::Mode::Lite;
            SetStatus(translation_.Get("shader.switch.lite", "Lite shaders"));
        }
    } else {
        if (!Confirm(
                hwnd_, title,
                translation_.GetW(
                    "shader.confirm_full",
                    L"Switch to full shaders? The full pack will be downloaded if needed."))) {
            return;
        }
        if (EnsureFullShaderPack(hwnd_, app_, translation_, false)) {
            std::string error;
            SetStatus(translation_.Get("shader.full_running", "Deploying full shaders..."));
            if (!shaders_.SetMode(ShaderPackManager::Mode::Full, false, &error)) {
                const auto message =
                    error.empty()
                        ? translation_.GetW("cxx.shader.activate_failed",
                                            L"Full shader pack could not be activated.")
                        : LocalizedShaderError(translation_, error);
                SetStatus(WideToUtf8(message));
                ShowError(hwnd_, title, message);
            } else {
                shader_mode_ = ShaderPackManager::Mode::Full;
                SetStatus(translation_.Get("shader.full_done",
                                           "Full shaders deployed"));
            }
        }
    }
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::StartModPreset(const std::filesystem::path& mods_directory) {
    if (selected_index_ < 0) {
        ShowInfo(hwnd_, translation_.GetW("dialog.info", L"Information"),
                 translation_.GetW("mod_preset.error.no_config",
                                   L"Select a configuration first."));
        return;
    }
    if (mod_preset_running_) {
        ShowInfo(hwnd_, translation_.GetW("dialog.info", L"Information"),
                 translation_.GetW("mod_preset.error.task_running",
                                   L"Another task is already running."));
        return;
    }

    std::filesystem::path target =
        mods_directory.empty() ? ResolveModsFolder() : mods_directory;
    if (target.empty() || !DirectoryExists(target)) {
        if (!Confirm(
                hwnd_, translation_.GetW("dialog.info", L"Information"),
                translation_.GetW("mod_preset.ask_select_mods_folder",
                                  L"Mods folder not found. Select it manually?"))) {
            return;
        }
        auto selected = PickFolder(
            hwnd_,
            translation_.GetW("file_dialog.select_folder", L"Select folder").c_str());
        if (!selected) return;
        target = *selected;
    }
    if (!DirectoryExists(target)) {
        std::wstring message =
            Localized(translation_, "mod_preset.error.mods_folder_not_exist",
                      L"Mods folder does not exist:\n{0}");
        message = ReplaceToken(message, L"{0}", target.wstring());
        ShowError(hwnd_, translation_.GetW("dialog.error", L"Error"), message);
        return;
    }

    const auto d3dx = ResolveD3dxUserIni();
    if (d3dx.empty() || !FileExists(d3dx)) {
        std::wstring message =
            Localized(translation_, "mod_preset.error.d3dx_not_exist",
                      L"d3dx_user.ini does not exist:\n{0}");
        message = ReplaceToken(message, L"{0}", d3dx.wstring());
        ShowError(hwnd_, translation_.GetW("dialog.error", L"Error"), message);
        return;
    }
    if (mods_directory.empty() &&
        !Confirm(hwnd_, translation_.GetW("dialog.info", L"Information"),
                 translation_.GetW("mod_preset.confirm_all",
                                   L"Continue and update all matched Mod presets?"))) {
        return;
    }

    mod_preset_running_ = true;
    SetStatus(translation_.Get("status.mod_preset_running",
                               "Processing Mod presets..."));
    auto progress = ModPresetProgressWindow(
                        hwnd_, translation_, d3dx, target, app_.root())
                        .Run();
    if (!progress) {
        mod_preset_running_ = false;
        ShowError(hwnd_, translation_.GetW("dialog.error", L"Error"),
                  translation_.GetW("mod_preset.error.progress_window",
                                    L"Could not open the Mod preset progress window."));
        return;
    }
    auto* payload = new ModPresetPayload;
    payload->updated_files = progress->result.updated_files;
    payload->scanned_files = progress->result.scanned_files;
    payload->failed_files = progress->result.failed_files;
    payload->error = progress->result.fatal_error;
    payload->target = target;
    payload->log = progress->result.log;
    payload->log_path = progress->log_path;
    OnModPresetFinished(payload);
}

void MainWindow::StartModPresetSelect() {
    if (selected_index_ < 0) {
        ShowInfo(hwnd_, translation_.GetW("dialog.info", L"Information"),
                 translation_.GetW("mod_preset.error.no_config",
                                   L"Select a configuration first."));
        return;
    }
    auto selected = PickFolder(
        hwnd_,
        translation_.GetW("file_dialog.select_folder", L"Select folder").c_str());
    if (!selected) return;
    StartModPreset(*selected);
}

void MainWindow::OnModPresetFinished(ModPresetPayload* payload) {
    std::unique_ptr<ModPresetPayload> owned(payload);
    mod_preset_running_ = false;
    if (!payload) return;
    if (!payload->error.empty()) {
        const auto message = Utf8ToWide(payload->error);
        SetStatus(WideToUtf8(message));
        ShowError(hwnd_, translation_.GetW("dialog.error", L"Error"), message);
        ShowModPresetDetails(hwnd_, translation_, true, payload->log_path,
                             payload->log, message);
        return;
    }
    std::wstring message =
        Localized(translation_, "status.mod_preset_done",
                  L"Mod presets processed");
    message += L" (" + std::to_wstring(payload->updated_files) + L"/" +
               std::to_wstring(payload->scanned_files) + L")";
    if (payload->failed_files > 0) {
        std::wstring failed =
            Localized(translation_, "mod_preset.failed_count",
                      L"failed {count}");
        failed = ReplaceToken(failed, L"{count}",
                              std::to_wstring(payload->failed_files));
        message += L", " + failed;
    }
    SetStatus(WideToUtf8(message));
    ShowNotification(
        translation_.GetW("tray.notification_title", L"ReShade Launcher"), message);
    ShowModPresetDetails(hwnd_, translation_, payload->failed_files > 0,
                         payload->log_path,
                         payload->log, message);
    InvalidateRect(hwnd_, nullptr, FALSE);
}

std::filesystem::path MainWindow::ResolveModsFolder() const {
    if (selected_index_ < 0) return {};
    const auto& config = profiles_[selected_index_].data;
    if (config.contains("mods_folder") && config["mods_folder"].is_string()) {
        const auto saved = Utf8ToWide(config["mods_folder"].get<std::string>());
        if (DirectoryExists(saved)) return saved;
    }
    std::vector<std::filesystem::path> candidates;
    if (config.contains("d3d11_path") && config["d3d11_path"].is_string()) {
        candidates.emplace_back(Utf8ToWide(config["d3d11_path"].get<std::string>()));
    }
    if (config.contains("dll_files") && config["dll_files"].is_array()) {
        for (const auto& value : config["dll_files"]) {
            if (value.is_string()) {
                candidates.emplace_back(
                    Utf8ToWide(value.get<std::string>()));
            }
        }
    }
    if (config.contains("xxmi_launcher_path") &&
        config["xxmi_launcher_path"].is_string()) {
        const std::filesystem::path launcher =
            Utf8ToWide(config["xxmi_launcher_path"].get<std::string>());
        const auto root =
            launcher.parent_path().parent_path().parent_path();
        std::string module;
        if (config.contains("xxmi_module") &&
            config["xxmi_module"].is_string()) {
            module = config["xxmi_module"].get<std::string>();
        }
        if (!module.empty()) {
            const auto mods = root / Utf8ToWide(module) / L"Mods";
            if (DirectoryExists(mods)) return mods;
        }
        std::error_code ec;
        for (const auto& entry :
             std::filesystem::directory_iterator(
                 root, std::filesystem::directory_options::skip_permission_denied,
                 ec)) {
            if (ec) break;
            if (!entry.is_directory(ec)) continue;
            if (!FileExists(entry.path() / L"d3d11.dll")) continue;
            const auto mods = entry.path() / L"Mods";
            if (DirectoryExists(mods)) return mods;
        }
    }
    for (const auto& candidate : candidates) {
        auto mods = candidate.parent_path() / L"Mods";
        if (DirectoryExists(mods)) return mods;
    }
    for (const char* key : {"launch_program", "game_dir"}) {
        if (!config.contains(key) || !config[key].is_string()) continue;
        const std::filesystem::path executable =
            Utf8ToWide(config[key].get<std::string>());
        const auto parent =
            FileExists(executable) ? executable.parent_path() : executable;
        const auto mods = parent / L"Mods";
        if (DirectoryExists(mods)) return mods;
    }
    auto game = profiles_[selected_index_].game_exe.parent_path() / L"Mods";
    return DirectoryExists(game) ? game : std::filesystem::path{};
}

std::filesystem::path MainWindow::ResolveD3dxUserIni() const {
    if (selected_index_ < 0) return {};
    const auto& config = profiles_[selected_index_].data;
    if (config.contains("mods_folder") && config["mods_folder"].is_string()) {
        const std::filesystem::path mods =
            Utf8ToWide(config["mods_folder"].get<std::string>());
        const auto path = mods.parent_path() / L"d3dx_user.ini";
        if (FileExists(path)) return path;
    }
    std::vector<std::filesystem::path> candidates;
    if (config.contains("d3d11_path") && config["d3d11_path"].is_string()) {
        candidates.emplace_back(Utf8ToWide(config["d3d11_path"].get<std::string>()));
    }
    if (config.contains("dll_files") && config["dll_files"].is_array()) {
        for (const auto& value : config["dll_files"]) {
            if (value.is_string()) {
                candidates.emplace_back(Utf8ToWide(value.get<std::string>()));
            }
        }
    }
    if (config.contains("xxmi_launcher_path") &&
        config["xxmi_launcher_path"].is_string()) {
        const std::filesystem::path launcher =
            Utf8ToWide(config["xxmi_launcher_path"].get<std::string>());
        const auto root =
            launcher.parent_path().parent_path().parent_path();
        std::string module;
        if (config.contains("xxmi_module") &&
            config["xxmi_module"].is_string()) {
            module = config["xxmi_module"].get<std::string>();
        }
        if (!module.empty()) {
            const auto path =
                root / Utf8ToWide(module) / L"d3dx_user.ini";
            if (FileExists(path)) return path;
        }
        std::error_code ec;
        for (const auto& entry :
             std::filesystem::directory_iterator(
                 root, std::filesystem::directory_options::skip_permission_denied,
                 ec)) {
            if (ec) break;
            if (!entry.is_directory(ec)) continue;
            if (!FileExists(entry.path() / L"d3d11.dll")) continue;
            const auto path = entry.path() / L"d3dx_user.ini";
            if (FileExists(path)) return path;
        }
    }
    for (const char* key : {"launch_program", "game_dir"}) {
        if (!config.contains(key) || !config[key].is_string()) continue;
        const std::filesystem::path executable =
            Utf8ToWide(config[key].get<std::string>());
        const auto parent =
            FileExists(executable) ? executable.parent_path() : executable;
        const auto path = parent / L"d3dx_user.ini";
        if (FileExists(path)) return path;
    }
    for (const auto& candidate : candidates) {
        const auto path = candidate.parent_path() / L"d3dx_user.ini";
        if (FileExists(path)) return path;
    }
    return {};
}

void MainWindow::ResolveAndOpenMods() {
    if (selected_index_ < 0) return;
    auto folder = ResolveModsFolder();
    if (folder.empty()) {
        auto selected = PickFolder(
            hwnd_,
            translation_.GetW("file_dialog.select_mods_folder",
                              L"Select Mods folder")
                .c_str());
        if (!selected) {
            ShowInfo(hwnd_, translation_.GetW("cxx.mods.title", L"Mods"),
                     translation_.GetW(
                         "cxx.mods.path_error",
                         L"Could not determine the current game's Mods folder."));
            return;
        }
        auto& profile = profiles_[selected_index_];
        profile.data["mods_folder"] = WideToUtf8(selected->wstring());
        if (!configs_.Save(profile.config_name, profile.data)) {
            ShowError(hwnd_, translation_.GetW("dialog.error", L"Error"),
                      translation_.GetW("cxx.mods.path_error",
                                        L"Could not save the Mods folder."));
            return;
        }
        folder = *selected;
    }
    if (OpenInExplorer(folder)) {
        SetStatus(WideToUtf8(folder.wstring()));
    } else {
        ShowError(hwnd_, translation_.GetW("dialog.error", L"Error"),
                  translation_.GetW("cxx.mods.path_error",
                                    L"Could not open the Mods folder."));
    }
}

void MainWindow::SetStatus(std::string text) {
    status_ = std::move(text);
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::UpdateWindowIcons() {
    if (window_icon_large_) DestroyIcon(window_icon_large_);
    if (window_icon_small_) DestroyIcon(window_icon_small_);
    if (tray_icon_) DestroyIcon(tray_icon_);
    window_icon_large_ = nullptr;
    window_icon_small_ = nullptr;
    tray_icon_ = nullptr;

    std::filesystem::path icon_path;
    if (selected_index_ >= 0 &&
        selected_index_ < static_cast<int>(profiles_.size())) {
        const auto& profile = profiles_[selected_index_];
        if (!profile.custom_icon.empty()) {
            icon_path = Utf8ToWide(profile.custom_icon);
        }
        if (!FileExists(icon_path)) {
            icon_path = profile.game_exe;
        }
    }

    const UINT large_size =
        static_cast<UINT>(GetSystemMetricsForDpi(SM_CXICON, dpi_));
    const UINT small_size =
        static_cast<UINT>(GetSystemMetricsForDpi(SM_CXSMICON, dpi_));
    window_icon_large_ = LoadIconFromPath(wic_factory_, icon_path, large_size);
    window_icon_small_ = LoadIconFromPath(wic_factory_, icon_path, small_size);
    if (!window_icon_large_) {
        window_icon_large_ = static_cast<HICON>(
            LoadImageW(instance_, MAKEINTRESOURCEW(1), IMAGE_ICON,
                       static_cast<int>(large_size), static_cast<int>(large_size),
                       0));
    }
    if (!window_icon_small_) {
        window_icon_small_ = static_cast<HICON>(
            LoadImageW(instance_, MAKEINTRESOURCEW(1), IMAGE_ICON,
                       static_cast<int>(small_size), static_cast<int>(small_size),
                       0));
    }
    tray_icon_ = LoadIconFromPath(
        wic_factory_, icon_path,
        static_cast<UINT>(GetSystemMetricsForDpi(SM_CXSMICON, dpi_)));
    if (hwnd_) {
        if (window_icon_large_) {
            SendMessageW(hwnd_, WM_SETICON, ICON_BIG,
                         reinterpret_cast<LPARAM>(window_icon_large_));
        }
        if (window_icon_small_) {
            SendMessageW(hwnd_, WM_SETICON, ICON_SMALL,
                         reinterpret_cast<LPARAM>(window_icon_small_));
        }
    }
}

void MainWindow::UpdateTrayIcon() {
    tray_.cbSize = sizeof(tray_);
    tray_.hWnd = hwnd_;
    tray_.uID = 1;
    tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    tray_.uCallbackMessage = kTrayCallback;
    tray_.hIcon = tray_icon_ ? tray_icon_ : LoadIconW(instance_, MAKEINTRESOURCEW(1));
    if (!tray_.hIcon) tray_.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    std::wstring tooltip =
        Localized(translation_, "cxx.tray.tooltip", L"Launcher - {name}");
    tooltip = ReplaceToken(tooltip, L"{name}",
                           CurrentDisplayName().empty()
                               ? translation_.GetW("cxx.app.title",
                                                   L"ReShade Launcher")
                               : CurrentDisplayName());
    wcsncpy_s(tray_.szTip, tooltip.c_str(), _TRUNCATE);
    if (!tray_visible_) {
        tray_visible_ =
            Shell_NotifyIconW(NIM_ADD, &tray_) != FALSE;
    } else {
        if (!Shell_NotifyIconW(NIM_MODIFY, &tray_)) {
            Shell_NotifyIconW(NIM_DELETE, &tray_);
            tray_visible_ = false;
        }
    }
}

void MainWindow::HideToTray() {
    UpdateTrayIcon();
    if (!tray_visible_) {
        ShowWindow(hwnd_, SW_MINIMIZE);
        return;
    }
    ShowWindow(hwnd_, SW_HIDE);
}

void MainWindow::ShowFromTray() {
    ShowWindow(hwnd_, SW_SHOWNORMAL);
    SetForegroundWindow(hwnd_);
}

void MainWindow::ShowNotification(std::wstring_view title, std::wstring_view message) {
    if (!tray_visible_) return;
    tray_.uFlags = NIF_INFO;
    wcsncpy_s(tray_.szInfoTitle, title.data(), _TRUNCATE);
    wcsncpy_s(tray_.szInfo, message.data(), _TRUNCATE);
    tray_.dwInfoFlags = NIIF_INFO;
    Shell_NotifyIconW(NIM_MODIFY, &tray_);
}

void MainWindow::OnDpiChanged(UINT dpi, const RECT* suggested) {
    dpi_ = dpi;
    if (suggested) {
        SetWindowPos(hwnd_, nullptr, suggested->left, suggested->top,
                     suggested->right - suggested->left,
                     suggested->bottom - suggested->top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
    } else {
        RECT logical{0, 0, MulDiv(640, dpi_, 96),
                     MulDiv(530, dpi_, 96)};
        AdjustWindowRectExForDpi(
            &logical, WS_OVERLAPPEDWINDOW, FALSE,
            WS_EX_APPWINDOW, dpi_);
        SetWindowPos(hwnd_, nullptr, 0, 0,
                     logical.right - logical.left,
                     logical.bottom - logical.top,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
    DiscardGraphics();
    InitializeGraphics();
    RebuildProfileIcons();
    UpdateWindowIcons();
    UpdateTrayIcon();
    InvalidateRect(hwnd_, nullptr, FALSE);
}

}  // namespace rs
