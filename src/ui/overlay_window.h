#pragma once

#include <windows.h>

#include <vector>

namespace rs {

void AttachOverlayToOwner(HWND window, HWND owner);
void ConfigureOverlayWindow(HWND window);
void CenterOverlayWindow(HWND window, HWND owner, int desired_width,
                         int desired_height, int margin_dip = 12);
void RefreshOverlayRegion(HWND window);
void ResizeOverlayWindows(HWND owner);
bool CloseTopOverlay(HWND owner);
bool IsOwnerUiSuppressed(HWND window);

class ScopedOwnerUiSuppression {
public:
    explicit ScopedOwnerUiSuppression(HWND owner);
    ~ScopedOwnerUiSuppression();

    ScopedOwnerUiSuppression(const ScopedOwnerUiSuppression&) = delete;
    ScopedOwnerUiSuppression& operator=(const ScopedOwnerUiSuppression&) =
        delete;

private:
    HWND owner_ = nullptr;
    std::vector<HWND> disabled_controls_;
};

}  // namespace rs
