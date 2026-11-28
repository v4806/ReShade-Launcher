#include "ui/main_window.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <shlobj.h>

#include <algorithm>
#include <atomic>
#include <exception>
#include <memory>
#include <thread>

#include "core/diagnostics.h"
#include "update/update_client.h"
#include "ui/dialogs.h"
#include "ui/overlay_window.h"

namespace rs {
namespace {

constexpr UINT kProgressUpdate = WM_APP + 1;
constexpr UINT kDownloadDone = WM_APP + 2;
constexpr UINT kCancelRequested = WM_APP + 3;

struct DownloadOutcome {
    bool success = false;
    bool cancelled = false;
    std::filesystem::path path;
    std::string error;
};

std::filesystem::path LocalAppDataDirectory() {
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &raw))) {
        return std::filesystem::temp_directory_path();
    }
    std::filesystem::path path(raw);
    CoTaskMemFree(raw);
    return path;
}

std::string TimestampForPath() {
    SYSTEMTIME time{};
    GetLocalTime(&time);
    char buffer[64]{};
    sprintf_s(buffer, "%04u%02u%02u-%02u%02u%02u", time.wYear, time.wMonth,
              time.wDay, time.wHour, time.wMinute, time.wSecond);
    return buffer;
}

bool IsVerifiedShaderCache(const std::filesystem::path& pack,
                           std::uint64_t size, std::string_view sha256) {
    std::error_code error;
    if (!FileExists(pack) ||
        std::filesystem::file_size(pack, error) != size || error) {
        return false;
    }
    const auto modified = std::filesystem::last_write_time(pack, error);
    if (error) return false;
    const auto verification =
        ReadJson(pack.parent_path() / L"full.verified.json");
    return verification && verification->value("size", std::uint64_t{0}) == size &&
           ToLower(verification->value("sha256", "")) ==
               ToLower(std::string(sha256)) &&
           verification->value("last_write_time", std::int64_t{0}) ==
               modified.time_since_epoch().count();
}

void MarkShaderCacheVerified(const std::filesystem::path& pack,
                             std::uint64_t size, std::string_view sha256) {
    std::error_code error;
    const auto modified = std::filesystem::last_write_time(pack, error);
    if (error) return;
    WriteJsonAtomic(
        pack.parent_path() / L"full.verified.json",
        Json{{"size", size},
             {"sha256", std::string(sha256)},
             {"last_write_time", modified.time_since_epoch().count()}});
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

COLORREF DownloadBackground() { return RGB(8, 13, 26); }
COLORREF DownloadPanel() { return RGB(18, 26, 46); }
COLORREF DownloadPanelHover() { return RGB(26, 66, 115); }
COLORREF DownloadInput() { return RGB(9, 17, 31); }
COLORREF DownloadBorder() { return RGB(44, 60, 90); }
COLORREF DownloadText() { return RGB(242, 246, 255); }
COLORREF DownloadMuted() { return RGB(173, 184, 217); }
COLORREF DownloadAccent() { return RGB(92, 255, 72); }

HFONT CreateDownloadFont(UINT dpi, int points, int weight) {
    return CreateFontW(-MulDiv(points, static_cast<int>(dpi), 72), 0, 0, 0,
                       weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                       OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                       CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
}

class DownloadProgressWindow {
public:
    using DownloadJob = std::function<std::filesystem::path(
        reshade_launcher::update::DownloadProgressCallback,
        reshade_launcher::update::CancelCallback)>;

    DownloadProgressWindow(HWND owner, std::wstring title,
                           const Translation& translation, DownloadJob job)
        : owner_(owner),
          title_(std::move(title)),
          translation_(translation),
          job_(std::move(job)) {}

    std::optional<DownloadOutcome> Run() {
        DebugLog("Download started: " + WideToUtf8(title_));
        ScopedOwnerUiSuppression suppress_owner(owner_);
        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = WindowProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.lpszClassName = L"ReShadeLauncherDownloadProgress";
        RegisterClassExW(&wc);
        hwnd_ = CreateWindowExW(
            WS_EX_TOOLWINDOW, wc.lpszClassName, title_.c_str(),
            WS_POPUP | WS_CLIPCHILDREN, 0, 0, 430, 155, owner_, nullptr,
            wc.hInstance, this);
        if (!hwnd_) return std::nullopt;
        AttachOverlayToOwner(hwnd_, owner_);
        ConfigureOverlayWindow(hwnd_);
        SizeWindow();
        ShowWindow(hwnd_, SW_SHOWNORMAL);
        UpdateWindow(hwnd_);

        MSG message{};
        while (IsWindow(hwnd_) && GetMessageW(&message, nullptr, 0, 0) > 0) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        if (worker_.joinable()) worker_.join();
        if (owner_ && IsWindow(owner_)) SetForegroundWindow(owner_);
        if (outcome_) {
            DebugLog(outcome_->success
                         ? "Download completed: " + WideToUtf8(title_)
                         : "Download failed: " + outcome_->error);
        }
        return outcome_;
    }

private:
    static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                       LPARAM lparam) {
        auto* self = reinterpret_cast<DownloadProgressWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
            self = static_cast<DownloadProgressWindow*>(create->lpCreateParams);
            self->hwnd_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA,
                              reinterpret_cast<LONG_PTR>(self));
        }
        return self ? self->Handle(message, wparam, lparam)
                    : DefWindowProcW(window, message, wparam, lparam);
    }

    LRESULT Handle(UINT message, WPARAM wparam, LPARAM lparam) {
        switch (message) {
            case WM_CREATE:
                dpi_ = GetDpiForWindow(hwnd_);
                if (!dpi_) dpi_ = GetDpiForSystem();
                CreateFonts();
                SetDarkFrame();
                cancel_ = CreateWindowExW(
                    0, L"BUTTON",
                    translation_.GetW("cxx.download.cancel", L"Cancel").c_str(),
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                    0, 0, 10, 10, hwnd_,
                    reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDCANCEL)),
                    GetModuleHandleW(nullptr), nullptr);
                LayoutControls();
                worker_ = std::thread([this] { Work(); });
                return 0;
            case kProgressUpdate:
                percent_ = std::clamp(static_cast<int>(wparam), 0, 100);
                progress_received_ = true;
                InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            case kDownloadDone: {
                std::unique_ptr<DownloadOutcome> result(
                    reinterpret_cast<DownloadOutcome*>(lparam));
                outcome_ = std::move(*result);
                DestroyWindow(hwnd_);
                return 0;
            }
            case kCancelRequested:
                if (cancelling_) return 0;
                cancelling_ = true;
                cancel_requested_ = true;
                if (cancel_) EnableWindow(cancel_, FALSE);
                InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            case WM_COMMAND:
                if (LOWORD(wparam) == IDCANCEL && !cancelling_) {
                    PostMessageW(hwnd_, kCancelRequested, 0, 0);
                    return 0;
                }
                break;
            case WM_DRAWITEM: {
                const auto* item =
                    reinterpret_cast<const DRAWITEMSTRUCT*>(lparam);
                if (item && item->CtlID == IDCANCEL) {
                    DrawCancelButton(*item);
                    return TRUE;
                }
                break;
            }
            case WM_PAINT:
                Paint();
                return 0;
            case WM_ERASEBKGND:
                return 1;
            case WM_SIZE:
                LayoutControls();
                RefreshOverlayRegion(hwnd_);
                InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            case WM_DPICHANGED: {
                DestroyFonts();
                dpi_ = HIWORD(wparam);
                CreateFonts();
                SizeWindow();
                LayoutControls();
                InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            }
            case WM_CLOSE:
                if (!cancelling_) PostMessageW(hwnd_, kCancelRequested, 0, 0);
                return 0;
            case WM_DESTROY:
                DestroyFonts();
                return 0;
        }
        return DefWindowProcW(hwnd_, message, wparam, lparam);
    }

    int Scale(int value) const {
        return MulDiv(value, static_cast<int>(dpi_), 96);
    }

    void CreateFonts() {
        heading_font_ = CreateDownloadFont(dpi_, 13, FW_SEMIBOLD);
        body_font_ = CreateDownloadFont(dpi_, 10, FW_NORMAL);
        button_font_ = CreateDownloadFont(dpi_, 10, FW_SEMIBOLD);
    }

    void DestroyFonts() {
        if (heading_font_) DeleteObject(heading_font_);
        if (body_font_) DeleteObject(body_font_);
        if (button_font_) DeleteObject(button_font_);
        heading_font_ = nullptr;
        body_font_ = nullptr;
        button_font_ = nullptr;
    }

    void SetDarkFrame() {
        const BOOL enabled = TRUE;
        DwmSetWindowAttribute(hwnd_, 20, &enabled, sizeof(enabled));
        const COLORREF background = DownloadBackground();
        const COLORREF text = DownloadText();
        DwmSetWindowAttribute(hwnd_, 35, &background, sizeof(background));
        DwmSetWindowAttribute(hwnd_, 36, &text, sizeof(text));
    }

    void LayoutControls() {
        if (!cancel_) return;
        RECT client{};
        GetClientRect(hwnd_, &client);
        const int width = Scale(92);
        const int height = Scale(32);
        const int margin = Scale(20);
        SetWindowPos(cancel_, nullptr,
                     std::max(margin, static_cast<int>(client.right) - margin -
                                           width),
                     std::max(margin, static_cast<int>(client.bottom) - margin -
                                           height),
                     width, height, SWP_NOZORDER | SWP_NOACTIVATE);
        SendMessageW(cancel_, WM_SETFONT,
                     reinterpret_cast<WPARAM>(button_font_), TRUE);
    }

    void Paint() {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(hwnd_, &paint);
        RECT client{};
        GetClientRect(hwnd_, &client);
        HBRUSH background = CreateSolidBrush(DownloadBackground());
        FillRect(dc, &client, background);
        DeleteObject(background);

        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, DownloadAccent());
        const HGDIOBJ old_font = SelectObject(dc, heading_font_);
        RECT heading{Scale(24), Scale(16),
                     static_cast<LONG>(client.right) - Scale(24), Scale(48)};
        DrawTextW(dc, title_.c_str(), -1, &heading,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
                      DT_END_ELLIPSIS);

        std::wstring status =
            cancelling_
                ? translation_.GetW("cxx.download.cancelling",
                                    L"Cancelling...")
                : translation_.GetW("cxx.download.starting",
                                    L"Downloading...");
        if (!cancelling_ && progress_received_) {
            status = translation_.GetW(
                "cxx.download.progress", L"Downloading... {percent}%");
            status = ReplaceToken(status, L"{percent}",
                                  std::to_wstring(percent_));
        }
        SelectObject(dc, body_font_);
        SetTextColor(dc, DownloadMuted());
        RECT status_rect{Scale(24), Scale(54),
                         static_cast<LONG>(client.right) - Scale(24),
                         Scale(82)};
        DrawTextW(dc, status.c_str(), -1, &status_rect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
                      DT_END_ELLIPSIS);

        RECT track{Scale(24), Scale(88),
                   static_cast<LONG>(client.right) - Scale(24), Scale(98)};
        HBRUSH track_brush = CreateSolidBrush(DownloadInput());
        HGDIOBJ previous_brush = SelectObject(dc, track_brush);
        HGDIOBJ previous_pen =
            SelectObject(dc, GetStockObject(NULL_PEN));
        RoundRect(dc, track.left, track.top, track.right, track.bottom,
                  Scale(10), Scale(10));
        SelectObject(dc, previous_pen);
        SelectObject(dc, previous_brush);
        DeleteObject(track_brush);

        if (percent_ > 0) {
            RECT fill = track;
            fill.right =
                track.left + (track.right - track.left) * percent_ / 100;
            HBRUSH fill_brush = CreateSolidBrush(DownloadAccent());
            previous_brush = SelectObject(dc, fill_brush);
            previous_pen = SelectObject(dc, GetStockObject(NULL_PEN));
            RoundRect(dc, fill.left, fill.top, fill.right, fill.bottom,
                      Scale(10), Scale(10));
            SelectObject(dc, previous_pen);
            SelectObject(dc, previous_brush);
            DeleteObject(fill_brush);
        }
        SelectObject(dc, old_font);
        EndPaint(hwnd_, &paint);
    }

    void DrawCancelButton(const DRAWITEMSTRUCT& item) const {
        const bool disabled = (item.itemState & ODS_DISABLED) != 0;
        const bool pressed = (item.itemState & ODS_SELECTED) != 0;
        HBRUSH fill = CreateSolidBrush(
            disabled ? DownloadInput()
                     : (pressed ? DownloadPanelHover() : DownloadPanel()));
        HPEN border = CreatePen(
            PS_SOLID, std::max(1, Scale(1)),
            disabled ? DownloadBorder() : DownloadAccent());
        const HGDIOBJ old_brush = SelectObject(item.hDC, fill);
        const HGDIOBJ old_pen = SelectObject(item.hDC, border);
        RoundRect(item.hDC, item.rcItem.left, item.rcItem.top,
                  item.rcItem.right, item.rcItem.bottom, Scale(8), Scale(8));
        SelectObject(item.hDC, old_pen);
        SelectObject(item.hDC, old_brush);
        DeleteObject(border);
        DeleteObject(fill);

        SetBkMode(item.hDC, TRANSPARENT);
        SetTextColor(item.hDC,
                     disabled ? DownloadMuted() : DownloadText());
        const HGDIOBJ old_font = SelectObject(item.hDC, button_font_);
        RECT text = item.rcItem;
        DrawTextW(item.hDC,
                  translation_.GetW("cxx.download.cancel", L"Cancel").c_str(),
                  -1, &text,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
        SelectObject(item.hDC, old_font);
    }

    void SizeWindow() {
        dpi_ = GetDpiForWindow(hwnd_);
        if (!dpi_) dpi_ = GetDpiForSystem();
        CenterOverlayWindow(hwnd_, owner_, Scale(500), Scale(190));
    }

    void Work() {
        auto result = std::make_unique<DownloadOutcome>();
        try {
            result->path = job_(
                [this](const reshade_launcher::update::DownloadProgress& progress) {
                    const int percent =
                        progress.totalBytes == 0
                            ? 0
                            : static_cast<int>(progress.downloadedBytes * 100 /
                                               progress.totalBytes);
                    PostMessageW(hwnd_, kProgressUpdate, static_cast<WPARAM>(percent), 0);
                },
                [this] { return cancel_requested_.load(); });
            result->success = true;
        } catch (const reshade_launcher::update::UpdateCancelled&) {
            result->cancelled = true;
            result->error = WideToUtf8(
                translation_.GetW("cxx.update.cancelled", L"Download cancelled."));
        } catch (const std::exception& error) {
            result->error = error.what();
        } catch (...) {
            result->error = WideToUtf8(
                translation_.GetW("cxx.update.unknown_error",
                                  L"Unknown download error."));
        }
        auto* raw_result = result.release();
        if (!PostMessageW(hwnd_, kDownloadDone, 0,
                          reinterpret_cast<LPARAM>(raw_result))) {
            delete raw_result;
        }
    }

    HWND owner_ = nullptr;
    HWND hwnd_ = nullptr;
    HWND cancel_ = nullptr;
    UINT dpi_ = 96;
    HFONT heading_font_ = nullptr;
    HFONT body_font_ = nullptr;
    HFONT button_font_ = nullptr;
    std::wstring title_;
    const Translation& translation_;
    DownloadJob job_;
    std::thread worker_;
    std::atomic_bool cancel_requested_{false};
    bool cancelling_ = false;
    bool progress_received_ = false;
    int percent_ = 0;
    std::optional<DownloadOutcome> outcome_;
};

struct UpdateCheckOutcome {
    std::optional<reshade_launcher::update::UpdateCheckResult> result;
    std::string error;
};

class UpdateCheckWindow {
public:
    UpdateCheckWindow(HWND owner, std::string current_version,
                      const Translation& translation)
        : owner_(owner),
          current_version_(std::move(current_version)),
          title_(translation.GetW("cxx.update.title", L"Update")),
          status_(translation.GetW("update.start",
                                   L"Checking for updates...")) {}

    std::optional<UpdateCheckOutcome> Run() {
        ScopedOwnerUiSuppression suppress_owner(owner_);
        constexpr wchar_t kClass[] = L"ReShadeLauncherUpdateCheck";
        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = WindowProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.lpszClassName = kClass;
        RegisterClassExW(&wc);
        hwnd_ = CreateWindowExW(
            WS_EX_TOOLWINDOW, kClass, title_.c_str(),
            WS_POPUP | WS_CLIPCHILDREN, 0, 0, 480, 180, owner_, nullptr,
            wc.hInstance, this);
        if (!hwnd_) return std::nullopt;
        AttachOverlayToOwner(hwnd_, owner_);
        ConfigureOverlayWindow(hwnd_);
        SizeWindow();
        ShowWindow(hwnd_, SW_SHOWNORMAL);
        UpdateWindow(hwnd_);
        worker_ = std::thread([this] { Work(); });

        MSG message{};
        while (!destroyed_ && GetMessageW(&message, nullptr, 0, 0) > 0) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        if (worker_.joinable()) worker_.join();
        return outcome_;
    }

private:
    static LRESULT CALLBACK WindowProc(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam) {
        auto* self = reinterpret_cast<UpdateCheckWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
            self = static_cast<UpdateCheckWindow*>(create->lpCreateParams);
            self->hwnd_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA,
                              reinterpret_cast<LONG_PTR>(self));
        }
        return self ? self->Handle(message, wparam, lparam)
                    : DefWindowProcW(window, message, wparam, lparam);
    }

    LRESULT Handle(UINT message, WPARAM wparam, LPARAM lparam) {
        constexpr UINT kCheckDone = WM_APP + 51;
        switch (message) {
            case WM_CREATE: {
                dpi_ = GetDpiForWindow(hwnd_);
                if (!dpi_) dpi_ = GetDpiForSystem();
                const BOOL dark = TRUE;
                const COLORREF background = DownloadBackground();
                const COLORREF text = DownloadText();
                DwmSetWindowAttribute(hwnd_, 20, &dark, sizeof(dark));
                DwmSetWindowAttribute(hwnd_, 35, &background,
                                      sizeof(background));
                DwmSetWindowAttribute(hwnd_, 36, &text, sizeof(text));
                background_brush_ = CreateSolidBrush(DownloadBackground());
                title_font_ = CreateDownloadFont(dpi_, 12, FW_SEMIBOLD);
                body_font_ = CreateDownloadFont(dpi_, 10, FW_NORMAL);
                return 0;
            }
            case WM_PAINT: {
                PAINTSTRUCT paint{};
                HDC dc = BeginPaint(hwnd_, &paint);
                RECT client{};
                GetClientRect(hwnd_, &client);
                FillRect(dc, &client, background_brush_);
                SetBkMode(dc, TRANSPARENT);
                SetTextColor(dc, DownloadAccent());
                const HGDIOBJ previous = SelectObject(dc, title_font_);
                RECT title_rect{Scale(20), Scale(18),
                                client.right - Scale(20), Scale(48)};
                DrawTextW(dc, title_.c_str(), -1, &title_rect,
                          DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
                SetTextColor(dc, DownloadMuted());
                SelectObject(dc, body_font_);
                RECT status_rect{Scale(20), Scale(66),
                                 client.right - Scale(20),
                                 client.bottom - Scale(18)};
                DrawTextW(dc, status_.c_str(), -1, &status_rect,
                          DT_LEFT | DT_TOP | DT_WORDBREAK | DT_NOPREFIX);
                SelectObject(dc, previous);
                EndPaint(hwnd_, &paint);
                return 0;
            }
            case WM_ERASEBKGND:
                return 1;
            case WM_CLOSE:
                return 0;
            case kCheckDone: {
                std::unique_ptr<UpdateCheckOutcome> outcome(
                    reinterpret_cast<UpdateCheckOutcome*>(lparam));
                if (outcome) outcome_ = std::move(*outcome);
                DestroyWindow(hwnd_);
                return 0;
            }
            case WM_DESTROY:
                destroyed_ = true;
                if (title_font_) DeleteObject(title_font_);
                if (body_font_) DeleteObject(body_font_);
                if (background_brush_) DeleteObject(background_brush_);
                title_font_ = nullptr;
                body_font_ = nullptr;
                background_brush_ = nullptr;
                return 0;
            default:
                return DefWindowProcW(hwnd_, message, wparam, lparam);
        }
    }

    void Work() {
        auto outcome = std::make_unique<UpdateCheckOutcome>();
        try {
            reshade_launcher::update::UpdateClient client;
            outcome->result = client.CheckForUpdate(current_version_);
            if (outcome->result) {
                DebugLog("Update check: current=" + outcome->result->currentVersion +
                         " latest=" + outcome->result->release.version +
                         " available=" +
                         (outcome->result->updateAvailable ? "true" : "false"));
            }
        } catch (const std::exception& error) {
            outcome->error = error.what();
            DebugLog(std::string("Update check failed: ") + error.what());
        } catch (...) {
            outcome->error = "unknown update check error";
            DebugLog("Update check failed: unknown error");
        }
        auto* raw = outcome.release();
        if (!PostMessageW(hwnd_, WM_APP + 51, 0,
                          reinterpret_cast<LPARAM>(raw))) {
            delete raw;
        }
    }

    int Scale(int value) const {
        return MulDiv(value, static_cast<int>(dpi_), 96);
    }

    void SizeWindow() {
        dpi_ = GetDpiForWindow(hwnd_);
        if (!dpi_) dpi_ = GetDpiForSystem();
        CenterOverlayWindow(hwnd_, owner_, Scale(480), Scale(180));
    }

    HWND owner_ = nullptr;
    HWND hwnd_ = nullptr;
    UINT dpi_ = 96;
    HFONT title_font_ = nullptr;
    HFONT body_font_ = nullptr;
    HBRUSH background_brush_ = nullptr;
    std::string current_version_;
    std::wstring title_;
    std::wstring status_;
    std::thread worker_;
    bool destroyed_ = false;
    std::optional<UpdateCheckOutcome> outcome_;
};

std::optional<UpdateCheckOutcome> RunUpdateCheck(
    HWND owner, std::string current_version,
    const Translation& translation) {
    UpdateCheckWindow window(owner, std::move(current_version), translation);
    return window.Run();
}

std::optional<DownloadOutcome> RunDownload(
    HWND owner, std::wstring title, const Translation& translation,
    DownloadProgressWindow::DownloadJob job) {
    DownloadProgressWindow window(owner, std::move(title), translation, std::move(job));
    return window.Run();
}

bool LaunchUpdater(const std::filesystem::path& installer,
                   const reshade_launcher::update::ReleaseInfo& release) {
    const auto updater_source =
        ExecutableDirectory() / L"ReShadeLauncherUpdater.exe";
    if (!FileExists(updater_source)) {
        return false;
    }
    const auto local = LocalAppDataDirectory() / L"ReShade-Launcher";
    const auto updater_dir = local / L"updater";
    const auto updater = updater_dir / L"ReShadeLauncherUpdater.exe";
    std::error_code ec;
    std::filesystem::create_directories(updater_dir, ec);
    ec.clear();
    if (!std::filesystem::copy_file(
            updater_source, updater,
            std::filesystem::copy_options::overwrite_existing, ec) ||
        ec) {
        return false;
    }
    const auto backup =
        local / L"rollback" / (Utf8ToWide(release.version) + L"-" +
                               Utf8ToWide(TimestampForPath()));
    const auto logs = local / L"logs";
    std::filesystem::create_directories(logs, ec);
    std::wstring command =
        L"\"" + updater.wstring() + L"\" --wait-pid " +
        std::to_wstring(GetCurrentProcessId()) + L" --installer \"" +
        installer.wstring() + L"\" --sha256 \"" + Utf8ToWide(release.sha256) +
        L"\" --version \"" + Utf8ToWide(release.version) +
        L"\" --install-dir \"" + ExecutableDirectory().wstring() +
        L"\" --backup-dir \"" + backup.wstring() + L"\" --log-dir \"" +
        logs.wstring() + L"\" --launch-exe \"" + ExecutablePath().wstring() + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(updater.c_str(), command.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, updater.parent_path().c_str(),
                        &startup, &process)) {
        return false;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}

}  // namespace

bool DownloadGitHubAsset(HWND owner, const Translation& translation,
                         std::wstring_view title, std::string_view url,
                         std::uint64_t expected_size,
                         std::string_view expected_sha256,
                         const std::filesystem::path& destination,
                         std::string* error, bool* cancelled) {
    if (error) error->clear();
    if (cancelled) *cancelled = false;
    DebugLog("GitHub download: " + std::string(url) + " size=" +
             std::to_string(expected_size));
    std::error_code ec;
    std::filesystem::create_directories(destination.parent_path(), ec);
    if (ec) {
        if (error) *error = "Cannot create the download directory.";
        return false;
    }
    try {
        reshade_launcher::update::UpdateClient client;
        auto download = RunDownload(
            owner, std::wstring(title), translation,
            [&](reshade_launcher::update::DownloadProgressCallback progress,
                reshade_launcher::update::CancelCallback cancel) {
                return client.DownloadFile(
                    std::string(url), expected_size,
                    std::string(expected_sha256), destination, progress,
                    cancel);
            });
        if (!download) {
            if (error) *error = "The download window could not be opened.";
            DebugLog("GitHub download failed: progress window unavailable");
            return false;
        }
        if (cancelled) *cancelled = download->cancelled;
        if (!download->success) {
            if (error) {
                *error = download->cancelled ? "Download cancelled."
                                             : download->error;
            }
            DebugLog(download->cancelled
                         ? "GitHub download cancelled"
                         : "GitHub download failed: " + download->error);
            return false;
        }
        DebugLog("GitHub download completed: " +
                 WideToUtf8(destination.wstring()));
        return true;
    } catch (const std::exception& exception) {
        if (error) *error = exception.what();
        DebugLog(std::string("GitHub download exception: ") + exception.what());
        return false;
    }
}

void RunManualUpdate(HWND owner, const AppData&, const Translation& translation) {
    const std::string current = WideToUtf8(ExecutableVersionString(ExecutablePath()));
    DebugLog("Manual update check requested; current version=" + current);
    if (current.empty()) {
        ShowError(
            owner, translation.GetW("cxx.update.title", L"Update"),
            translation.GetW("cxx.update.version_read_failed",
                             L"Cannot read the current application version."));
        return;
    }
    try {
        const auto checked = RunUpdateCheck(owner, current, translation);
        if (!checked || !checked->result) {
            auto message =
                translation.GetW("cxx.update.failed", L"Update failed: {error}");
            message = ReplaceToken(
                message, L"{error}",
                checked && !checked->error.empty()
                    ? Utf8ToWide(checked->error)
                    : translation.GetW("cxx.update.unknown_error",
                                       L"Unknown update error."));
            ShowError(owner, translation.GetW("cxx.update.title", L"Update"),
                      message);
            return;
        }
        const auto& check = *checked->result;
        if (!check.updateAvailable) {
            ShowInfo(owner, translation.GetW("cxx.update.title", L"Update"),
                     translation.GetW("cxx.update.latest",
                                      L"You are already using the latest version."));
            return;
        }
        std::wstring message = translation.GetW(
            "cxx.update.available_message",
            L"Current version: {current}\nLatest version: {latest}\n"
            L"Installer size: {size} MB\n\nDownload and install now?");
        message = ReplaceToken(message, L"{current}",
                               Utf8ToWide(check.currentVersion));
        message = ReplaceToken(message, L"{latest}",
                               Utf8ToWide(check.release.version));
        wchar_t size_text[32]{};
        swprintf_s(size_text, L"%.1f",
                   static_cast<double>(check.release.assetSize) /
                       (1024.0 * 1024.0));
        message = ReplaceToken(message, L"{size}", size_text);
        if (!Confirm(owner,
                     translation.GetW("cxx.update.available_title",
                                      L"Update available"),
                     message)) {
            return;
        }

        reshade_launcher::update::UpdateClient client;
        const auto destination =
            LocalAppDataDirectory() / L"ReShade-Launcher" / L"updates" /
            Utf8ToWide(check.release.tag) / Utf8ToWide(check.release.assetName);
        auto download = RunDownload(
            owner, translation.GetW("cxx.update.downloading", L"Downloading update"),
            translation,
            [&](reshade_launcher::update::DownloadProgressCallback progress,
                reshade_launcher::update::CancelCallback cancel) {
                return client.DownloadInstaller(check.release, destination, progress, cancel);
            });
        if (!download || !download->success) {
            if (download && !download->cancelled) {
                auto error = translation.GetW(
                    "cxx.update.failed", L"Update failed: {error}");
                error = ReplaceToken(error, L"{error}",
                                     Utf8ToWide(download->error));
                ShowError(owner, translation.GetW("cxx.update.title", L"Update"),
                          error);
            }
            return;
        }
        if (!LaunchUpdater(download->path, check.release)) {
            ShowError(
                owner, translation.GetW("cxx.update.title", L"Update"),
                translation.GetW(
                    "cxx.update.updater_start_failed",
                    L"Could not start ReShadeLauncherUpdater.exe. The installer "
                    L"remains available in LocalAppData."));
            return;
        }
        PostMessageW(owner, WM_APP + 30, 0, 0);
    } catch (const std::exception& error) {
        auto message =
            translation.GetW("cxx.update.failed", L"Update failed: {error}");
        message = ReplaceToken(message, L"{error}", Utf8ToWide(error.what()));
        ShowError(owner, translation.GetW("cxx.update.title", L"Update"), message);
    }
}

bool EnsureFullShaderPack(HWND owner, const AppData& app,
                          const Translation& translation, bool confirm_download) {
    const auto descriptor = ReadJson(app.resource_path(L"shader-packs/full.json"));
    if (!descriptor) {
        ShowError(
            owner,
            translation.GetW("cxx.shader.full_pack_title", L"Full shader pack"),
            translation.GetW("cxx.shader.descriptor_missing",
                             L"The full shader descriptor is missing from this build."));
        return false;
    }
    try {
        const auto url = descriptor->at("url").get<std::string>();
        const auto size = descriptor->at("size").get<uint64_t>();
        const auto sha = descriptor->at("sha256").get<std::string>();
        const auto destination =
            LocalAppDataDirectory() / L"ReShade-Launcher" / L"shader-packs" / L"full.zip";
        if (IsVerifiedShaderCache(destination, size, sha)) {
            return true;
        }
        if (FileExists(destination) &&
            std::filesystem::file_size(destination) == size &&
            ToLower(Sha256File(destination)) == ToLower(sha)) {
            MarkShaderCacheVerified(destination, size, sha);
            return true;
        }
        if (confirm_download) {
            std::wstring message = translation.GetW(
                "cxx.shader.download_prompt",
                L"Download the full shader pack ({size} MB)?");
            wchar_t size_text[32]{};
            swprintf_s(size_text, L"%.1f",
                       static_cast<double>(size) / (1024.0 * 1024.0));
            message = ReplaceToken(message, L"{size}", size_text);
            if (!Confirm(
                    owner,
                    translation.GetW("cxx.shader.full_pack_title",
                                     L"Full shader pack"),
                    message)) {
                return false;
            }
        }
        reshade_launcher::update::UpdateClient client;
        auto download = RunDownload(
            owner,
            translation.GetW("cxx.shader.downloading",
                             L"Downloading full shader pack"),
            translation,
            [&](reshade_launcher::update::DownloadProgressCallback progress,
                reshade_launcher::update::CancelCallback cancel) {
                return client.DownloadFile(url, size, sha, destination, progress, cancel);
            });
        if (!download || !download->success) {
            if (download && !download->cancelled) {
                std::wstring message = translation.GetW(
                    "cxx.shader.download_failed",
                    L"Could not download the full shader pack.\n\n{error}");
                message = ReplaceToken(message, L"{error}",
                                       Utf8ToWide(download->error));
                ShowError(
                    owner,
                    translation.GetW("cxx.shader.full_pack_title",
                                     L"Full shader pack"),
                    message);
            }
            return false;
        }
        MarkShaderCacheVerified(destination, size, sha);
        return true;
    } catch (const std::exception& error) {
        std::wstring message = translation.GetW(
            "cxx.shader.download_failed",
            L"Could not download the full shader pack.\n\n{error}");
        message = ReplaceToken(message, L"{error}", Utf8ToWide(error.what()));
        ShowError(
            owner,
            translation.GetW("cxx.shader.full_pack_title", L"Full shader pack"),
            message);
        return false;
    }
}

}  // namespace rs
