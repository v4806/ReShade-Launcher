#include "../update/update_internal.h"

#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cwchar>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {

namespace fs = std::filesystem;
using reshade_launcher::update::detail::Version;
using reshade_launcher::update::detail::Win32ErrorMessage;

class UsageError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class UpdateProcessError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class InvalidPathError : public UpdateProcessError {
public:
    using UpdateProcessError::UpdateProcessError;
};

struct Options {
    DWORD waitPid = 0;
    fs::path installerPath;
    std::string expectedSha256;
    Version expectedVersion;
    std::string expectedVersionText;
    fs::path installDir;
    fs::path backupDir;
    fs::path logDir;
    fs::path launchExe;
};

class Logger {
public:
    explicit Logger(const fs::path& path) {
        stream_.open(path, std::ios::binary | std::ios::app);
        if (!stream_) {
            throw UpdateProcessError("cannot open updater log file");
        }
    }

    void Info(std::string_view message) {
        Write("INFO", message);
    }

    void Error(std::string_view message) {
        Write("ERROR", message);
    }

private:
    void Write(std::string_view level, std::string_view message) {
        SYSTEMTIME localTime{};
        GetLocalTime(&localTime);

        std::ostringstream line;
        line << std::setfill('0') << std::setw(4) << localTime.wYear << '-'
             << std::setw(2) << localTime.wMonth << '-' << std::setw(2)
             << localTime.wDay << ' ' << std::setw(2) << localTime.wHour << ':'
             << std::setw(2) << localTime.wMinute << ':' << std::setw(2)
             << localTime.wSecond << " [" << level << "] " << message << '\n';

        const std::string text = line.str();
        stream_.write(text.data(), static_cast<std::streamsize>(text.size()));
        stream_.flush();
    }

    std::ofstream stream_;
};

std::string PathToUtf8(const fs::path& path) {
    return reshade_launcher::update::detail::WideToUtf8(path.wstring());
}

std::wstring QuotePath(const fs::path& path) {
    return L"\"" + path.wstring() + L"\"";
}

bool EqualsPathComponent(
    const fs::path& left,
    const fs::path& right) {
    return _wcsicmp(left.c_str(), right.c_str()) == 0;
}

bool IsPathWithin(const fs::path& candidate, const fs::path& parent) {
    auto candidateIterator = candidate.begin();
    auto parentIterator = parent.begin();

    for (; parentIterator != parent.end(); ++parentIterator, ++candidateIterator) {
        if (candidateIterator == candidate.end() ||
            !EqualsPathComponent(*candidateIterator, *parentIterator)) {
            return false;
        }
    }
    return true;
}

fs::path NormalizePath(const fs::path& input, std::string_view description) {
    if (input.empty()) {
        throw InvalidPathError(std::string(description) + " is empty");
    }

    std::error_code error;
    const fs::path absolute = fs::absolute(input, error);
    if (error) {
        throw InvalidPathError(
            "cannot resolve " + std::string(description) + ": " +
            error.message());
    }

    fs::path normalized = fs::weakly_canonical(absolute, error);
    if (error) {
        throw InvalidPathError(
            "cannot normalize " + std::string(description) + ": " +
            error.message());
    }
    normalized = normalized.lexically_normal();
    if (normalized.empty()) {
        throw InvalidPathError(
            std::string(description) + " resolved to an empty path");
    }
    return normalized;
}

std::wstring ReadRequiredValue(
    int& index,
    int argc,
    wchar_t** argv,
    const std::wstring& option) {
    if (index + 1 >= argc) {
        throw UsageError(
            "missing value for " + reshade_launcher::update::detail::WideToUtf8(option));
    }
    ++index;
    const std::wstring value = argv[index];
    if (value.empty()) {
        throw UsageError(
            "empty value for " + reshade_launcher::update::detail::WideToUtf8(option));
    }
    return value;
}

DWORD ParseProcessId(const std::wstring& value) {
    wchar_t* end = nullptr;
    errno = 0;
    const unsigned long parsed = std::wcstoul(value.c_str(), &end, 10);
    if (errno == ERANGE || end == value.c_str() || *end != L'\0' ||
        parsed == 0 || parsed > MAXDWORD) {
        throw UsageError("--wait-pid must be a non-zero 32-bit process ID");
    }
    return static_cast<DWORD>(parsed);
}

Options ParseCommandLine(int argc, wchar_t** argv) {
    const std::unordered_set<std::wstring> allowed = {
        L"--wait-pid",
        L"--installer",
        L"--sha256",
        L"--version",
        L"--install-dir",
        L"--backup-dir",
        L"--log-dir",
        L"--launch-exe",
    };

    std::unordered_map<std::wstring, std::wstring> values;
    for (int index = 1; index < argc; ++index) {
        const std::wstring option = argv[index];
        if (allowed.find(option) == allowed.end()) {
            throw UsageError(
                "unknown option " +
                reshade_launcher::update::detail::WideToUtf8(option));
        }
        if (values.find(option) != values.end()) {
            throw UsageError(
                "duplicate option " +
                reshade_launcher::update::detail::WideToUtf8(option));
        }
        values.emplace(option, ReadRequiredValue(index, argc, argv, option));
    }

    if (values.size() != allowed.size()) {
        throw UsageError("all documented options are required");
    }

    Options options;
    options.waitPid = ParseProcessId(values.at(L"--wait-pid"));
    options.installerPath = fs::path(values.at(L"--installer"));
    options.installDir = fs::path(values.at(L"--install-dir"));
    options.backupDir = fs::path(values.at(L"--backup-dir"));
    options.logDir = fs::path(values.at(L"--log-dir"));
    options.launchExe = fs::path(values.at(L"--launch-exe"));

    const std::string shaText =
        reshade_launcher::update::detail::WideToUtf8(values.at(L"--sha256"));
    std::string shaError;
    if (!reshade_launcher::update::detail::TryNormalizeSha256(
            shaText, false, options.expectedSha256, shaError)) {
        throw UsageError("--sha256 is invalid: " + shaError);
    }

    const std::string versionText =
        reshade_launcher::update::detail::WideToUtf8(values.at(L"--version"));
    std::string versionError;
    if (!reshade_launcher::update::detail::TryParseVersion(
            versionText, false, options.expectedVersion, versionError)) {
        throw UsageError("--version is invalid: " + versionError);
    }
    options.expectedVersionText =
        reshade_launcher::update::detail::VersionToString(options.expectedVersion);
    return options;
}

void ValidateFileSystemLayout(Options& options) {
    options.installerPath =
        NormalizePath(options.installerPath, "installer path");
    options.installDir = NormalizePath(options.installDir, "install directory");
    options.backupDir = NormalizePath(options.backupDir, "backup directory");
    options.logDir = NormalizePath(options.logDir, "log directory");

    fs::path launchExe = options.launchExe;
    if (launchExe.is_relative()) {
        launchExe = options.installDir / launchExe;
    }
    options.launchExe = NormalizePath(launchExe, "launch executable");

    if (!options.installDir.has_parent_path() ||
        options.installDir.parent_path() == options.installDir) {
        throw InvalidPathError("install directory cannot be a drive or share root");
    }
    if (!IsPathWithin(options.launchExe, options.installDir)) {
        throw InvalidPathError(
            "launch executable must be inside the install directory");
    }
    if (IsPathWithin(options.backupDir, options.installDir) ||
        IsPathWithin(options.installDir, options.backupDir)) {
        throw InvalidPathError(
            "backup directory and install directory cannot overlap");
    }
    if (IsPathWithin(options.logDir, options.installDir)) {
        throw InvalidPathError(
            "log directory must be outside the install directory");
    }
}

void WaitForParent(DWORD processId, Logger& logger) {
    if (processId == GetCurrentProcessId()) {
        throw UpdateProcessError("--wait-pid points to the updater process");
    }

    HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, processId);
    if (process == nullptr) {
        const DWORD error = GetLastError();
        if (error == ERROR_INVALID_PARAMETER) {
            logger.Info("parent process is already gone");
            return;
        }
        throw UpdateProcessError(
            "cannot open parent process: " + Win32ErrorMessage(error));
    }

    const DWORD waitResult = WaitForSingleObject(process, INFINITE);
    const DWORD waitError = GetLastError();
    CloseHandle(process);
    if (waitResult != WAIT_OBJECT_0) {
        throw UpdateProcessError(
            "cannot wait for parent process: " +
            Win32ErrorMessage(
                waitResult == WAIT_FAILED ? waitError : ERROR_GEN_FAILURE));
    }
    logger.Info("parent process exited");
}

void VerifyInstallerSha256(const Options& options, Logger& logger) {
    std::error_code error;
    if (!fs::is_regular_file(options.installerPath, error) || error) {
        throw UpdateProcessError("installer file does not exist");
    }

    std::string digest;
    std::string hashError;
    if (!reshade_launcher::update::detail::TrySha256File(
            options.installerPath, digest, hashError)) {
        throw UpdateProcessError("cannot hash installer: " + hashError);
    }
    if (digest != options.expectedSha256) {
        throw UpdateProcessError(
            "installer SHA-256 does not match --sha256");
    }
    logger.Info("installer SHA-256 verified");
}

void CreateDirectoryChecked(const fs::path& path) {
    std::error_code error;
    fs::create_directories(path, error);
    if (error) {
        throw UpdateProcessError(
            "cannot create directory '" + PathToUtf8(path) + "': " +
            error.message());
    }
}

bool ShouldSkipProgramBackupPath(const fs::path& relative) {
    std::string path = relative.generic_string();
    std::transform(path.begin(), path.end(), path.begin(),
                   [](unsigned char character) {
                       return static_cast<char>(std::tolower(character));
                   });
    const auto starts = [&](std::string_view prefix) {
        return path == prefix || path.starts_with(std::string(prefix) + "/");
    };
    for (std::string_view prefix : {
             "launch_config",
             "custom_data",
             "reshade/reshade_config",
             "reshade/presets",
             "reshade/reshade_shaders",
             "reshade/reshade_shaders.rollback",
             "reshade/reshade_shaders.stage",
             "shader-packs/full.zip",
         }) {
        if (starts(prefix)) return true;
    }
    if (starts("mod_loader") &&
        (path.find("/mods") != std::string::npos ||
         path.ends_with("/d3dx_user.ini"))) {
        return true;
    }
    return path.starts_with("日志_") && path.ends_with(".log");
}

void CopyDirectoryContents(
    const fs::path& source,
    const fs::path& destination,
    std::uint64_t& copiedFiles,
    std::uint64_t& copiedBytes,
    const fs::path& installRoot,
    bool overwriteExisting) {
    CreateDirectoryChecked(destination);

    std::error_code error;
    fs::directory_iterator iterator(source, error);
    if (error) {
        throw UpdateProcessError(
            "cannot enumerate directory '" + PathToUtf8(source) + "': " +
            error.message());
    }

    for (const fs::directory_entry& entry : iterator) {
        const fs::path target = destination / entry.path().filename();
        const fs::path relative = fs::relative(entry.path(), installRoot, error);
        if (error) {
            throw UpdateProcessError(
                "cannot resolve backup-relative path '" +
                PathToUtf8(entry.path()) + "': " + error.message());
        }
        if (ShouldSkipProgramBackupPath(relative)) continue;
        const fs::file_status status = entry.symlink_status(error);
        if (error) {
            throw UpdateProcessError(
                "cannot inspect '" + PathToUtf8(entry.path()) + "': " +
                error.message());
        }

        if (fs::is_symlink(status)) {
            throw UpdateProcessError(
                "symbolic link is not supported in program backup: '" +
                PathToUtf8(entry.path()) + "'");
        }
        if (fs::is_directory(status)) {
            CopyDirectoryContents(
                entry.path(), target, copiedFiles, copiedBytes, installRoot,
                overwriteExisting);
            continue;
        }
        if (!fs::is_regular_file(status)) {
            throw UpdateProcessError(
                "unsupported file type in program backup: '" +
                PathToUtf8(entry.path()) + "'");
        }

        const std::uint64_t fileSize = entry.file_size(error);
        if (error) {
            throw UpdateProcessError(
                "cannot read file size for '" + PathToUtf8(entry.path()) +
                "': " + error.message());
        }
        if (!CopyFileW(entry.path().c_str(), target.c_str(),
                       overwriteExisting ? FALSE : TRUE)) {
            throw UpdateProcessError(
                "cannot copy '" + PathToUtf8(entry.path()) + "': " +
                Win32ErrorMessage(GetLastError()));
        }
        ++copiedFiles;
        copiedBytes += fileSize;
    }
}

void CreateProgramBackup(const Options& options, Logger& logger) {
    std::error_code error;
    const bool installExists = fs::is_directory(options.installDir, error);
    if (error || !installExists) {
        throw UpdateProcessError("install directory does not exist");
    }

    if (fs::exists(options.backupDir, error)) {
        if (error || !fs::is_directory(options.backupDir, error)) {
            throw UpdateProcessError("backup path exists but is not a directory");
        }
        const bool backupEmpty = fs::is_empty(options.backupDir, error);
        if (error) {
            throw UpdateProcessError(
                "cannot inspect backup directory: " + error.message());
        }
        if (!backupEmpty) {
            throw UpdateProcessError(
                "backup directory must be absent or empty");
        }
    } else {
        if (error) {
            throw UpdateProcessError(
                "cannot inspect backup directory: " + error.message());
        }
        CreateDirectoryChecked(options.backupDir);
    }

    std::uint64_t copiedFiles = 0;
    std::uint64_t copiedBytes = 0;
    CopyDirectoryContents(
        options.installDir, options.backupDir, copiedFiles, copiedBytes,
        options.installDir, false);
    logger.Info(
        "program backup created: files=" + std::to_string(copiedFiles) +
        ", bytes=" + std::to_string(copiedBytes));
}

DWORD RunInstaller(
    const Options& options,
    const fs::path& innoLog,
    Logger& logger) {
    const std::wstring parameters =
        L" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
        L" /DIR=\"" +
        options.installDir.wstring() + L"\" /LOG=\"" + innoLog.wstring() + L"\"";

    STARTUPINFOW startupInfo{};
    startupInfo.cb = sizeof(startupInfo);
    PROCESS_INFORMATION processInfo{};
    HANDLE installerProcess = nullptr;

    logger.Info("starting Inno Setup installer");
    const fs::path installerWorkingDirectory =
        options.installerPath.parent_path();
    std::wstring commandLine =
        QuotePath(options.installerPath) + L" " + parameters;
    if (!CreateProcessW(
            options.installerPath.c_str(), commandLine.data(), nullptr, nullptr,
            FALSE, 0, nullptr, installerWorkingDirectory.c_str(), &startupInfo,
            &processInfo)) {
        const DWORD error = GetLastError();
        if (error != ERROR_ELEVATION_REQUIRED) {
            throw UpdateProcessError(
                "cannot start installer: " + Win32ErrorMessage(error));
        }

        logger.Info("installer requires elevation");
        SHELLEXECUTEINFOW executeInfo{};
        executeInfo.cbSize = sizeof(executeInfo);
        executeInfo.fMask =
            SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
        executeInfo.lpVerb = L"runas";
        executeInfo.lpFile = options.installerPath.c_str();
        executeInfo.lpParameters = parameters.c_str();
        executeInfo.lpDirectory = installerWorkingDirectory.c_str();
        executeInfo.nShow = SW_HIDE;
        if (!ShellExecuteExW(&executeInfo) ||
            executeInfo.hProcess == nullptr) {
            throw UpdateProcessError(
                "cannot start elevated installer: " +
                Win32ErrorMessage(GetLastError()));
        }
        installerProcess = executeInfo.hProcess;
    } else {
        CloseHandle(processInfo.hThread);
        installerProcess = processInfo.hProcess;
    }

    const DWORD waitResult = WaitForSingleObject(installerProcess, INFINITE);
    const DWORD waitError = GetLastError();
    if (waitResult != WAIT_OBJECT_0) {
        CloseHandle(installerProcess);
        throw UpdateProcessError(
            "cannot wait for installer: " +
            Win32ErrorMessage(
                waitResult == WAIT_FAILED ? waitError : ERROR_GEN_FAILURE));
    }

    DWORD exitCode = 0;
    const bool gotExitCode = GetExitCodeProcess(installerProcess, &exitCode);
    const DWORD exitCodeError = GetLastError();
    CloseHandle(installerProcess);

    if (!gotExitCode) {
        throw UpdateProcessError(
            "cannot read installer exit code: " +
            Win32ErrorMessage(exitCodeError));
    }
    if (exitCode != 0) {
        throw UpdateProcessError(
            "installer failed with exit code " + std::to_string(exitCode));
    }
    logger.Info("installer completed with exit code 0");
    return exitCode;
}

void VerifyInstalledVersion(const Options& options, Logger& logger) {
    std::string productVersion;
    std::string versionError;
    if (!reshade_launcher::update::detail::TryGetFileProductVersion(
            options.launchExe, productVersion, versionError)) {
        throw UpdateProcessError(
            "cannot read installed executable ProductVersion: " +
            versionError);
    }

    Version actualVersion;
    std::string parseError;
    if (!reshade_launcher::update::detail::TryParseVersion(
            productVersion, false, actualVersion, parseError)) {
        throw UpdateProcessError(
            "installed executable has invalid ProductVersion '" +
            productVersion + "': " + parseError);
    }
    if (reshade_launcher::update::detail::CompareVersions(
            actualVersion, options.expectedVersion) != 0) {
        throw UpdateProcessError(
            "installed ProductVersion " + productVersion +
            " does not match expected version " +
            options.expectedVersionText);
    }
    logger.Info("installed ProductVersion verified: " + productVersion);
}

void RestoreProgramBackup(const Options& options, Logger& logger) {
    CreateDirectoryChecked(options.installDir);

    // Remove program files added by the failed installer. User data is left
    // untouched because it is intentionally absent from the program backup.
    std::error_code error;
    std::vector<fs::path> extraPaths;
    for (fs::recursive_directory_iterator iterator(options.installDir, error), end;
         !error && iterator != end; iterator.increment(error)) {
        const fs::path relative =
            fs::relative(iterator->path(), options.installDir, error);
        if (error) {
            throw UpdateProcessError(
                "cannot resolve installed path during rollback: " +
                error.message());
        }
        if (ShouldSkipProgramBackupPath(relative)) {
            if (iterator->is_directory(error) && !error) {
                iterator.disable_recursion_pending();
            }
            if (error) {
                throw UpdateProcessError(
                    "cannot inspect installed path during rollback: " +
                    error.message());
            }
            continue;
        }
        if (!fs::exists(options.backupDir / relative, error)) {
            if (error) {
                throw UpdateProcessError(
                    "cannot inspect backup path during rollback: " +
                    error.message());
            }
            if (iterator->is_directory(error) && !error) {
                iterator.disable_recursion_pending();
            }
            if (error) {
                throw UpdateProcessError(
                    "cannot inspect installed directory during rollback: " +
                    error.message());
            }
            extraPaths.push_back(iterator->path());
        }
    }
    if (error) {
        throw UpdateProcessError(
            "cannot enumerate installed files during rollback: " +
            error.message());
    }
    for (const fs::path& path : extraPaths) {
        fs::remove_all(path, error);
        if (error) {
            throw UpdateProcessError(
                "cannot remove failed program path during rollback: " +
                error.message());
        }
    }

    std::uint64_t restoredFiles = 0;
    std::uint64_t restoredBytes = 0;
    CopyDirectoryContents(
        options.backupDir, options.installDir, restoredFiles, restoredBytes,
        options.installDir, true);
    logger.Info(
        "program backup restored: files=" + std::to_string(restoredFiles) +
        ", bytes=" + std::to_string(restoredBytes));
}

void LaunchApplication(const Options& options, Logger& logger) {
    std::wstring commandLine = QuotePath(options.launchExe);
    STARTUPINFOW startupInfo{};
    startupInfo.cb = sizeof(startupInfo);
    startupInfo.dwFlags = STARTF_USESHOWWINDOW;
    startupInfo.wShowWindow = SW_SHOWNORMAL;
    PROCESS_INFORMATION processInfo{};

    const fs::path workingDirectory = options.launchExe.parent_path();
    if (!CreateProcessW(
            options.launchExe.c_str(), commandLine.data(), nullptr, nullptr,
            FALSE, 0, nullptr, workingDirectory.c_str(), &startupInfo,
            &processInfo)) {
        throw UpdateProcessError(
            "installation succeeded, but restart failed: " +
            Win32ErrorMessage(GetLastError()));
    }

    CloseHandle(processInfo.hThread);
    CloseHandle(processInfo.hProcess);
    logger.Info("application restarted");
}

void ExecuteUpdate(const Options& options, Logger& logger) {
    logger.Info(
        "updater started: pid=" + std::to_string(GetCurrentProcessId()) +
        ", waiting-for=" + std::to_string(options.waitPid));
    logger.Info("installer=" + PathToUtf8(options.installerPath));
    logger.Info("install-dir=" + PathToUtf8(options.installDir));
    logger.Info("backup-dir=" + PathToUtf8(options.backupDir));
    logger.Info("launch-exe=" + PathToUtf8(options.launchExe));

    WaitForParent(options.waitPid, logger);
    VerifyInstallerSha256(options, logger);

    const fs::path innoLog = options.logDir / L"installer-inno.log";
    bool backupReady = false;
    try {
        CreateProgramBackup(options, logger);
        backupReady = true;

        RunInstaller(options, innoLog, logger);
        VerifyInstalledVersion(options, logger);
    } catch (const std::exception& exception) {
        std::string failure = exception.what();
        logger.Error(failure);

        if (backupReady) {
            logger.Error("attempting program backup restore");
            try {
                RestoreProgramBackup(options, logger);
            } catch (const std::exception& rollbackException) {
                throw UpdateProcessError(
                    failure + "; backup restore also failed: " +
                    rollbackException.what());
            }
        }
        throw UpdateProcessError(failure);
    }

    LaunchApplication(options, logger);
    std::error_code cleanupError;
    fs::remove_all(options.backupDir, cleanupError);
    if (cleanupError) {
        logger.Info("backup cleanup skipped: " + cleanupError.message());
    }
    cleanupError.clear();
    fs::remove(options.installerPath, cleanupError);
    if (cleanupError) {
        logger.Info("installer cleanup skipped: " + cleanupError.message());
    }
    logger.Info("update completed successfully");
}

void PrintUsage() {
    std::wcerr
        << L"Usage:\n"
        << L"  Updater.exe --wait-pid <pid> --installer <exe> --sha256 <hex>\n"
        << L"    --version <version> --install-dir <dir> --backup-dir <dir>\n"
        << L"    --log-dir <dir> --launch-exe <path-inside-install-dir>\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    std::optional<Options> activeOptions;
    try {
        activeOptions = ParseCommandLine(argc, argv);
        ValidateFileSystemLayout(*activeOptions);

        CreateDirectoryChecked(activeOptions->logDir);
        Logger logger(activeOptions->logDir / L"Updater.log");
        ExecuteUpdate(*activeOptions, logger);
        return 0;
    } catch (const UsageError& exception) {
        std::wcerr << reshade_launcher::update::detail::Utf8ToWide(
                          exception.what())
                   << L"\n";
        PrintUsage();
        return 1;
    } catch (const std::exception& exception) {
        const std::wstring error =
            reshade_launcher::update::detail::Utf8ToWide(
                exception.what());
        std::wcerr << L"Updater failed: " << error << L"\n";
        if (activeOptions) {
            std::wstring message =
                L"ReShade Launcher update failed.\n\n" + error;
            if (!activeOptions->logDir.empty()) {
                message += L"\n\nLog: " +
                           (activeOptions->logDir / L"Updater.log")
                               .wstring();
            }
            MessageBoxW(nullptr, message.c_str(),
                        L"ReShade Launcher Update",
                        MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
            if (!activeOptions->launchExe.empty() &&
                fs::exists(activeOptions->launchExe)) {
                ShellExecuteW(
                    nullptr, L"open",
                    activeOptions->launchExe.c_str(), nullptr,
                    activeOptions->installDir.c_str(), SW_SHOWNORMAL);
            }
        }
        return 2;
    }
}
