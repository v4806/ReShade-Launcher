#pragma once

#include <windows.h>

namespace rs {

void ConfigureOverlayWindow(HWND window);
void CenterOverlayWindow(HWND window, HWND owner, int desired_width,
                         int desired_height, int margin_dip = 12);
void RefreshOverlayRegion(HWND window);

}  // namespace rs
