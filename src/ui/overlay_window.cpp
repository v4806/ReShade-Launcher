#include "ui/overlay_window.h"

#include <dwmapi.h>

#include <algorithm>

namespace rs {
namespace {

int Dip(UINT dpi, int value) {
    return MulDiv(value, static_cast<int>(dpi), 96);
}

}  // namespace

void ConfigureOverlayWindow(HWND window) {
    if (!window) return;
    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    style &= ~(WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX |
               WS_MAXIMIZEBOX);
    style |= WS_POPUP | WS_CLIPCHILDREN;
    SetWindowLongPtrW(window, GWL_STYLE, style);

    LONG_PTR ex_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    ex_style |= WS_EX_TOOLWINDOW | WS_EX_COMPOSITED;
    ex_style &= ~(WS_EX_APPWINDOW | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE);
    SetWindowLongPtrW(window, GWL_EXSTYLE, ex_style);

    const BOOL dark = TRUE;
    DwmSetWindowAttribute(window, 20, &dark, sizeof(dark));
}

void RefreshOverlayRegion(HWND window) {
    if (!window) return;
    RECT client{};
    GetClientRect(window, &client);
    const int width = client.right - client.left;
    const int height = client.bottom - client.top;
    if (width <= 0 || height <= 0) return;
    const UINT dpi = GetDpiForWindow(window);
    const int radius = Dip(dpi ? dpi : 96, 8);
    HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                     radius * 2, radius * 2);
    if (region) {
        SetWindowRgn(window, region, TRUE);
    }
}

void CenterOverlayWindow(HWND window, HWND owner, int desired_width,
                         int desired_height, int margin_dip) {
    if (!window) return;
    RECT target{};
    if (owner && IsWindow(owner)) {
        POINT origin{0, 0};
        ClientToScreen(owner, &origin);
        RECT owner_client{};
        GetClientRect(owner, &owner_client);
        target = {origin.x, origin.y, origin.x + owner_client.right,
                  origin.y + owner_client.bottom};
    } else {
        MONITORINFO monitor{};
        monitor.cbSize = sizeof(monitor);
        GetMonitorInfoW(
            MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor);
        target = monitor.rcWork;
    }

    const UINT dpi = owner && IsWindow(owner) ? GetDpiForWindow(owner)
                                              : GetDpiForSystem();
    const int margin = Dip(dpi ? dpi : 96, margin_dip);
    const int available_width =
        std::max(1, static_cast<int>(target.right - target.left) - margin * 2);
    const int available_height =
        std::max(1, static_cast<int>(target.bottom - target.top) - margin * 2);
    const int width = std::min(std::max(1, desired_width), available_width);
    const int height = std::min(std::max(1, desired_height), available_height);
    const int x =
        target.left + (static_cast<int>(target.right - target.left) - width) / 2;
    const int y =
        target.top + (static_cast<int>(target.bottom - target.top) - height) / 2;

    SetWindowPos(window, HWND_TOP, x, y, width, height,
                 SWP_NOACTIVATE | SWP_FRAMECHANGED);
    RefreshOverlayRegion(window);
}

}  // namespace rs
