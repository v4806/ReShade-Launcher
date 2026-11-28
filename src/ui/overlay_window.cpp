#include "ui/overlay_window.h"

#include <dwmapi.h>

#include <algorithm>

namespace rs {
namespace {

constexpr wchar_t kOwnerUiSuppressedProperty[] =
    L"ReShadeLauncher.OwnerUiSuppressed";
constexpr wchar_t kOverlayWindowProperty[] =
    L"ReShadeLauncher.OverlayWindow";
constexpr wchar_t kOverlayWidthProperty[] =
    L"ReShadeLauncher.OverlayWidth";
constexpr wchar_t kOverlayHeightProperty[] =
    L"ReShadeLauncher.OverlayHeight";
constexpr wchar_t kOverlayMarginProperty[] =
    L"ReShadeLauncher.OverlayMargin";

int Dip(UINT dpi, int value) {
    return MulDiv(value, static_cast<int>(dpi), 96);
}

void RefreshOwner(HWND owner) {
    if (!owner || !IsWindow(owner)) return;
    RedrawWindow(owner, nullptr, nullptr,
                 RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW |
                     RDW_ALLCHILDREN);
}

}  // namespace

void AttachOverlayToOwner(HWND window, HWND owner) {
    if (!window || !owner || !IsWindow(owner)) return;
    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    style &= ~WS_POPUP;
    style |= WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN;
    SetWindowLongPtrW(window, GWL_STYLE, style);
    SetParent(window, owner);
    SetPropW(window, kOverlayWindowProperty,
             reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)));
    // DialogBox and the custom progress loops disable the owner. A disabled
    // parent disables its child overlays too, so suppression replaces that.
    EnableWindow(owner, TRUE);
}

void ConfigureOverlayWindow(HWND window) {
    if (!window) return;
    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    style &= ~(WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX |
               WS_MAXIMIZEBOX);
    if (!(style & WS_CHILD)) style |= WS_POPUP;
    style |= WS_CLIPCHILDREN;
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
    RECT bounds{};
    GetWindowRect(window, &bounds);
    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
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
    const bool child = (GetWindowLongPtrW(window, GWL_STYLE) & WS_CHILD) != 0;
    RECT target{};
    HWND parent = child ? GetParent(window) : nullptr;
    if (parent && IsWindow(parent)) {
        GetClientRect(parent, &target);
    } else if (owner && IsWindow(owner)) {
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

    const HWND dpi_source =
        parent && IsWindow(parent) ? parent : owner;
    const UINT dpi = dpi_source && IsWindow(dpi_source)
                         ? GetDpiForWindow(dpi_source)
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
    SetPropW(window, kOverlayWidthProperty,
             reinterpret_cast<HANDLE>(static_cast<INT_PTR>(desired_width)));
    SetPropW(window, kOverlayHeightProperty,
             reinterpret_cast<HANDLE>(static_cast<INT_PTR>(desired_height)));
    SetPropW(window, kOverlayMarginProperty,
             reinterpret_cast<HANDLE>(static_cast<INT_PTR>(margin_dip)));
    RefreshOverlayRegion(window);
}

void ResizeOverlayWindows(HWND owner) {
    if (!owner || !IsWindow(owner)) return;
    for (HWND child = GetWindow(owner, GW_CHILD); child;
         child = GetWindow(child, GW_HWNDNEXT)) {
        if (!GetPropW(child, kOverlayWindowProperty)) continue;
        const auto width = reinterpret_cast<INT_PTR>(
            GetPropW(child, kOverlayWidthProperty));
        const auto height = reinterpret_cast<INT_PTR>(
            GetPropW(child, kOverlayHeightProperty));
        const auto margin = reinterpret_cast<INT_PTR>(
            GetPropW(child, kOverlayMarginProperty));
        if (width <= 0 || height <= 0) continue;
        CenterOverlayWindow(child, owner, static_cast<int>(width),
                            static_cast<int>(height),
                            static_cast<int>(margin > 0 ? margin : 12));
    }
}

bool CloseTopOverlay(HWND owner) {
    if (!owner || !IsWindow(owner)) return false;
    for (HWND child = GetWindow(owner, GW_CHILD); child;
         child = GetWindow(child, GW_HWNDNEXT)) {
        if (!IsWindowVisible(child) ||
            !GetPropW(child, kOverlayWindowProperty)) {
            continue;
        }
        SendMessageW(child, WM_CLOSE, 0, 0);
        return true;
    }
    return false;
}

bool IsOwnerUiSuppressed(HWND window) {
    return window && GetPropW(window, kOwnerUiSuppressedProperty) != nullptr;
}

ScopedOwnerUiSuppression::ScopedOwnerUiSuppression(HWND owner)
    : owner_(owner) {
    if (!owner_ || !IsWindow(owner_)) {
        owner_ = nullptr;
        return;
    }
    const auto depth = reinterpret_cast<INT_PTR>(
        GetPropW(owner_, kOwnerUiSuppressedProperty));
    if (depth == 0) {
        for (HWND child = GetWindow(owner_, GW_CHILD); child;
             child = GetWindow(child, GW_HWNDNEXT)) {
            if (GetPropW(child, kOverlayWindowProperty) ||
                !IsWindowEnabled(child)) {
                continue;
            }
            EnableWindow(child, FALSE);
            disabled_controls_.push_back(child);
        }
    }
    SetPropW(owner_, kOwnerUiSuppressedProperty,
             reinterpret_cast<HANDLE>(depth + 1));
    RefreshOwner(owner_);
}

ScopedOwnerUiSuppression::~ScopedOwnerUiSuppression() {
    if (!owner_ || !IsWindow(owner_)) return;
    const auto depth = reinterpret_cast<INT_PTR>(
        GetPropW(owner_, kOwnerUiSuppressedProperty));
    if (depth <= 1) {
        RemovePropW(owner_, kOwnerUiSuppressedProperty);
        for (HWND child : disabled_controls_) {
            if (IsWindow(child)) EnableWindow(child, TRUE);
        }
    } else {
        SetPropW(owner_, kOwnerUiSuppressedProperty,
                 reinterpret_cast<HANDLE>(depth - 1));
    }
    RefreshOwner(owner_);
}

}  // namespace rs
