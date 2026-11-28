#include "core/diagnostics.h"

#include <windows.h>
#include <shlobj.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <mutex>
#include <sstream>

#include "core/common.h"

namespace rs {
namespace {

std::mutex g_log_mutex;
std::ofstream g_log_file;
std::filesystem::path g_log_path;
std::atomic_bool g_initialized = false;
LPTOP_LEVEL_EXCEPTION_FILTER g_previous_filter = nullptr;
std::terminate_handler g_previous_terminate = nullptr;

std::filesystem::path ResolveLogDirectory() {
    PWSTR raw = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE,
                                       nullptr, &raw))) {
        std::filesystem::path path(raw);
        CoTaskMemFree(raw);
        return path / L"ReShade-Launcher" / L"logs";
    }
    const DWORD required = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
    if (required > 1) {
        std::wstring value(required, L'\0');
        const DWORD written = GetEnvironmentVariableW(
            L"LOCALAPPDATA", value.data(), required);
        if (written > 0 && written < required) {
            value.resize(written);
            return std::filesystem::path(value) / L"ReShade-Launcher" / L"logs";
        }
    }
    return std::filesystem::temp_directory_path() / L"ReShade-Launcher" / L"logs";
}

std::wstring Timestamp(bool milliseconds) {
    SYSTEMTIME time{};
    GetLocalTime(&time);
    wchar_t buffer[64]{};
    if (milliseconds) {
        swprintf_s(buffer, L"%04u-%02u-%02u %02u:%02u:%02u.%03u",
                   time.wYear, time.wMonth, time.wDay, time.wHour,
                   time.wMinute, time.wSecond, time.wMilliseconds);
    } else {
        swprintf_s(buffer, L"%04u%02u%02u_%02u%02u%02u", time.wYear,
                   time.wMonth, time.wDay, time.wHour, time.wMinute,
                   time.wSecond);
    }
    return buffer;
}

void CleanupOldLogs(const std::filesystem::path& directory) {
    std::error_code error;
    const auto now = std::filesystem::file_time_type::clock::now();
    for (const auto& entry :
         std::filesystem::directory_iterator(directory, error)) {
        if (error) break;
        if (!entry.is_regular_file(error) || error) {
            error.clear();
            continue;
        }
        const auto name = entry.path().filename().wstring();
        if (name.rfind(L"launcher_", 0) != 0 &&
            name.rfind(L"crash_", 0) != 0) {
            continue;
        }
        const auto modified = entry.last_write_time(error);
        if (!error &&
            now - modified > std::chrono::hours(24 * 14)) {
            std::filesystem::remove(entry.path(), error);
        }
        error.clear();
    }
}

void WriteConsoleLine(std::wstring_view line) {
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    if (output && output != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteConsoleW(output, line.data(), static_cast<DWORD>(line.size()),
                      &written, nullptr);
    }
    OutputDebugStringW(std::wstring(line).c_str());
}

void LogLine(std::string_view message) {
    if (!g_initialized.load(std::memory_order_acquire)) return;
    const std::wstring stamp = Timestamp(true);
    const std::wstring wide_message = Utf8ToWide(message);
    std::wstring console_line =
        stamp + L" [" + std::to_wstring(GetCurrentProcessId()) + L":" +
        std::to_wstring(GetCurrentThreadId()) + L"] " + wide_message + L"\r\n";

    std::lock_guard lock(g_log_mutex);
    WriteConsoleLine(console_line);
    if (g_log_file) {
        g_log_file << WideToUtf8(console_line);
        g_log_file.flush();
    }
}

LONG WINAPI UnhandledExceptionFilter(EXCEPTION_POINTERS* exception) {
    if (exception && exception->ExceptionRecord) {
        const DWORD code = exception->ExceptionRecord->ExceptionCode;
        const void* address = exception->ExceptionRecord->ExceptionAddress;
        std::ostringstream text;
        text << "Unhandled native exception code=0x" << std::hex << code
             << " address=" << address;
        LogLine(text.str());
    } else {
        LogLine("Unhandled native exception without exception record");
    }
    if (g_previous_filter) {
        return g_previous_filter(exception);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

void TerminateHandler() {
    LogLine("std::terminate called");
    if (g_previous_terminate) {
        g_previous_terminate();
    }
    std::abort();
}

}  // namespace

bool InitializeDiagnostics() {
    if (g_initialized.load(std::memory_order_acquire)) return true;

    SetConsoleOutputCP(CP_UTF8);
    SetConsoleTitleW(L"ReShade Debug - Diagnostics");
    const auto directory = ResolveLogDirectory();
    std::error_code error;
    std::filesystem::create_directories(directory, error);
    if (!error) CleanupOldLogs(directory);

    g_log_path =
        directory /
        (L"launcher_" + Timestamp(false) + L"_" +
         std::to_wstring(GetCurrentProcessId()) + L".log");
    g_log_file.open(g_log_path, std::ios::binary | std::ios::trunc);
    if (!g_log_file) {
        g_log_path.clear();
    }
    g_initialized.store(true, std::memory_order_release);

    std::string header = "===== ReShade Launcher Debug =====";
    LogLine(header);
    LogLine("Version: " + WideToUtf8(ExecutableVersionString(ExecutablePath())));
    LogLine("Executable: " + WideToUtf8(ExecutablePath().wstring()));
    LogLine("Working directory: " +
            WideToUtf8(std::filesystem::current_path(error).wstring()));
    LogLine("Command line: " + WideToUtf8(GetCommandLineW()));
    LogLine("Log file: " +
            WideToUtf8(g_log_path.empty() ? L"(console only)" : g_log_path.wstring()));

    g_previous_filter = SetUnhandledExceptionFilter(UnhandledExceptionFilter);
    g_previous_terminate = std::set_terminate(TerminateHandler);
    return !g_log_path.empty();
}

void ShutdownDiagnostics() {
    if (!g_initialized.exchange(false, std::memory_order_acq_rel)) return;
    LogLine("Application stopped");
    std::lock_guard lock(g_log_mutex);
    if (g_log_file) {
        g_log_file.flush();
        g_log_file.close();
    }
    SetUnhandledExceptionFilter(g_previous_filter);
    std::set_terminate(g_previous_terminate);
}

void DebugLog(std::string_view message) {
    LogLine(message);
}

void DebugLog(std::wstring_view message) {
    LogLine(WideToUtf8(message));
}

const std::filesystem::path& DiagnosticsLogPath() {
    return g_log_path;
}

}  // namespace rs
