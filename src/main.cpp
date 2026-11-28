#include <windows.h>
#include <commctrl.h>
#include <objbase.h>

#include <filesystem>
#include <exception>
#include <memory>
#include <optional>
#include <string>

#include "core/diagnostics.h"
#include "ui/main_window.h"
#include "version.h"

namespace {

std::optional<std::string> ParseStartupConfig(std::wstring argument) {
    if (argument.empty()) return std::nullopt;
    if (argument.size() > 2 && argument.front() == L'"' &&
        argument.back() == L'"') {
        argument = argument.substr(1, argument.size() - 2);
    }
    const std::filesystem::path path(argument);
    if (_wcsicmp(path.extension().c_str(), L".json") != 0) {
        return std::nullopt;
    }
    return path.stem().string();
}

int RunLauncher(HINSTANCE instance, std::wstring command_line) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    INITCOMMONCONTROLSEX controls{
        sizeof(controls), ICC_STANDARD_CLASSES | ICC_LISTVIEW_CLASSES};
    InitCommonControlsEx(&controls);
    const HRESULT com_result =
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(com_result)) {
        rs::DebugLog("COM initialization failed: " +
                     std::to_string(com_result));
    }

    rs::MainWindow window(instance);
    if (!window.Create(ParseStartupConfig(std::move(command_line)))) {
        rs::DebugLog("Main window creation failed");
        if (SUCCEEDED(com_result)) CoUninitialize();
        return 1;
    }
    const int result = window.Run();
    if (SUCCEEDED(com_result)) CoUninitialize();
    return result;
}

}  // namespace

#ifdef RESHADE_LAUNCHER_DEBUG_BUILD

int wmain(int argc, wchar_t** argv) {
    rs::InitializeDiagnostics();
    rs::DebugLog("Debug build starting");
    rs::DebugLog("Version " RESHADE_LAUNCHER_VERSION_STRING);
    const std::wstring command_line = argc > 1 ? argv[1] : L"";
    int result = 1;
    try {
        result = RunLauncher(GetModuleHandleW(nullptr), command_line);
    } catch (const std::exception& error) {
        rs::DebugLog(std::string("Unhandled C++ exception: ") + error.what());
    } catch (...) {
        rs::DebugLog("Unhandled unknown exception");
    }
    rs::DebugLog("Debug build exited with code " + std::to_string(result));
    rs::ShutdownDiagnostics();
    return result;
}

#else

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR command_line, int) {
    return RunLauncher(instance, command_line ? command_line : L"");
}

#endif
