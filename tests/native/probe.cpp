#include <windows.h>

#include <cstdio>

static void AppendMarker() {
    wchar_t marker_path[MAX_PATH]{};
    DWORD length = GetEnvironmentVariableW(L"XXMI_PROBE_MARKER", marker_path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return;
    }

    HANDLE file = CreateFileW(
        marker_path,
        FILE_APPEND_DATA,
        FILE_SHARE_READ,
        nullptr,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }

    char buffer[64]{};
    const int written = sprintf_s(buffer, "%lu\n", GetCurrentProcessId());
    DWORD bytes_written = 0;
    if (written > 0) {
        WriteFile(file, buffer, static_cast<DWORD>(written), &bytes_written, nullptr);
    }
    CloseHandle(file);
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
        AppendMarker();
    }
    return TRUE;
}
