#include <windows.h>

#include <cstdio>
#include <string>

static std::wstring GetArgValue(int argc, wchar_t** argv, const wchar_t* name) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (_wcsicmp(argv[i], name) == 0) {
            return argv[i + 1];
        }
    }
    return L"";
}

static bool HasArg(int argc, wchar_t** argv, const wchar_t* name) {
    for (int i = 1; i < argc; ++i) {
        if (_wcsicmp(argv[i], name) == 0) {
            return true;
        }
    }
    return false;
}

static void WritePidFile(const std::wstring& path) {
    if (path.empty()) {
        return;
    }
    FILE* file = nullptr;
    _wfopen_s(&file, path.c_str(), L"wb");
    if (file) {
        fprintf(file, "%lu", GetCurrentProcessId());
        fclose(file);
    }
}

static bool FileExists(const std::wstring& path) {
    return !path.empty() && GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

static void PumpMessages(DWORD lifetime_ms) {
    const DWORD deadline = GetTickCount() + lifetime_ms;
    MSG msg{};
    while (GetTickCount() < deadline) {
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        Sleep(20);
    }
}

static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

int wmain(int argc, wchar_t** argv) {
    WritePidFile(GetArgValue(argc, argv, L"--pid-file"));

    const std::wstring go_file = GetArgValue(argc, argv, L"--go-file");
    if (!go_file.empty()) {
        const DWORD deadline = GetTickCount() + 10000;
        while (!FileExists(go_file) && GetTickCount() < deadline) {
            Sleep(20);
        }
        Sleep(200);
    }

    const int lifetime_ms = _wtoi(GetArgValue(argc, argv, L"--lifetime-ms").c_str());
    const DWORD lifetime = lifetime_ms > 0 ? static_cast<DWORD>(lifetime_ms) : 5000;

    if (!HasArg(argc, argv, L"--no-window")) {
        WNDCLASSW window_class{};
        window_class.lpfnWndProc = WindowProc;
        window_class.hInstance = GetModuleHandleW(nullptr);
        window_class.lpszClassName = L"XxmiInjectorTestTarget";
        RegisterClassW(&window_class);

        HWND hwnd = CreateWindowExW(
            0,
            window_class.lpszClassName,
            L"XXMI Injector Test Target",
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            320,
            200,
            nullptr,
            nullptr,
            window_class.hInstance,
            nullptr);
        if (hwnd) {
            ShowWindow(hwnd, SW_HIDE);
            UpdateWindow(hwnd);
        }
    }

    PumpMessages(lifetime);
    return 0;
}
