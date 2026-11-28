#include <windows.h>
#include <commctrl.h>
#include <objbase.h>

#include <memory>
#include <optional>
#include <string>

#include "ui/main_window.h"

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR command_line, int) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_STANDARD_CLASSES | ICC_LISTVIEW_CLASSES};
    InitCommonControlsEx(&controls);
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    std::optional<std::string> startup_config;
    if (command_line && *command_line) {
        std::wstring argument(command_line);
        if (argument.size() > 2 && argument.front() == L'"' && argument.back() == L'"') {
            argument = argument.substr(1, argument.size() - 2);
        }
        std::filesystem::path path(argument);
        if (path.extension() == L".json") {
            startup_config = path.stem().string();
        }
    }

    rs::MainWindow window(instance);
    if (!window.Create(std::move(startup_config))) {
        return 1;
    }
    const int result = window.Run();
    CoUninitialize();
    return result;
}
