#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <bcrypt.h>
#include <winver.h>

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

namespace reshade_launcher::update::detail {

struct Version {
    std::vector<std::uint32_t> parts;
};

inline std::string WideToUtf8(std::wstring_view value) {
    if (value.empty()) {
        return {};
    }

    const int required = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
        nullptr, 0, nullptr, nullptr);
    if (required <= 0) {
        return {};
    }

    std::string result(static_cast<std::size_t>(required), '\0');
    WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
        result.data(), required, nullptr, nullptr);
    return result;
}

inline std::wstring Utf8ToWide(std::string_view value) {
    if (value.empty()) {
        return {};
    }

    const int required = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
        nullptr, 0);
    if (required <= 0) {
        return {};
    }

    std::wstring result(static_cast<std::size_t>(required), L'\0');
    MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
        result.data(), required);
    return result;
}

inline std::string Win32ErrorMessage(DWORD error) {
    wchar_t* buffer = nullptr;
    const DWORD length = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);

    std::string message;
    if (length != 0 && buffer != nullptr) {
        std::wstring_view text(buffer, length);
        while (!text.empty() &&
               (text.back() == L'\r' || text.back() == L'\n' || text.back() == L' ')) {
            text.remove_suffix(1);
        }
        message = WideToUtf8(text);
    }
    if (buffer != nullptr) {
        LocalFree(buffer);
    }

    if (message.empty()) {
        return "Windows error " + std::to_string(error);
    }
    return message + " (" + std::to_string(error) + ")";
}

inline std::string BCryptErrorMessage(NTSTATUS status) {
    wchar_t code[16]{};
    swprintf_s(code, L"0x%08X", static_cast<unsigned int>(status));
    return "BCrypt error " + WideToUtf8(code);
}

inline bool TryParseVersion(
    std::string_view text,
    bool requireLeadingV,
    Version& version,
    std::string& error) {
    version = {};
    if (text.empty()) {
        error = "version is empty";
        return false;
    }

    if (text.front() == 'v' || text.front() == 'V') {
        text.remove_prefix(1);
    } else if (requireLeadingV) {
        error = "release tag must start with 'v'";
        return false;
    }

    if (text.empty()) {
        error = "version has no numeric components";
        return false;
    }

    std::size_t offset = 0;
    while (offset < text.size()) {
        if (version.parts.size() == 4) {
            error = "version has more than four components";
            return false;
        }
        if (text[offset] < '0' || text[offset] > '9') {
            error = "version contains a non-numeric component";
            return false;
        }

        std::uint64_t value = 0;
        while (offset < text.size() && text[offset] >= '0' && text[offset] <= '9') {
            value = value * 10 + static_cast<unsigned int>(text[offset] - '0');
            if (value > std::numeric_limits<std::uint32_t>::max()) {
                error = "version component exceeds 32-bit range";
                return false;
            }
            ++offset;
        }
        version.parts.push_back(static_cast<std::uint32_t>(value));

        if (offset == text.size()) {
            break;
        }
        if (text[offset] != '.') {
            error = "version must contain only digits and dots";
            return false;
        }
        ++offset;
        if (offset == text.size()) {
            error = "version ends with a dot";
            return false;
        }
    }

    if (version.parts.empty()) {
        error = "version has no numeric components";
        return false;
    }
    return true;
}

inline std::string VersionToString(const Version& version) {
    std::string result;
    for (std::size_t index = 0; index < version.parts.size(); ++index) {
        if (index != 0) {
            result.push_back('.');
        }
        result += std::to_string(version.parts[index]);
    }
    return result;
}

inline int CompareVersions(const Version& left, const Version& right) {
    const std::size_t count = (std::max)(left.parts.size(), right.parts.size());
    for (std::size_t index = 0; index < count; ++index) {
        const std::uint32_t leftPart =
            index < left.parts.size() ? left.parts[index] : 0;
        const std::uint32_t rightPart =
            index < right.parts.size() ? right.parts[index] : 0;
        if (leftPart < rightPart) {
            return -1;
        }
        if (leftPart > rightPart) {
            return 1;
        }
    }
    return 0;
}

inline bool IsSha256Hex(std::string_view value) {
    if (value.size() != 64) {
        return false;
    }
    for (const char character : value) {
        const bool isDigit = character >= '0' && character <= '9';
        const bool isLower = character >= 'a' && character <= 'f';
        const bool isUpper = character >= 'A' && character <= 'F';
        if (!isDigit && !isLower && !isUpper) {
            return false;
        }
    }
    return true;
}

inline bool TryNormalizeSha256(
    std::string_view value,
    bool requirePrefix,
    std::string& normalized,
    std::string& error) {
    const std::string input(value);
    value = input;
    constexpr std::string_view prefix = "sha256:";

    bool hasPrefix = false;
    if (value.size() >= prefix.size()) {
        hasPrefix = true;
        for (std::size_t index = 0; index < prefix.size(); ++index) {
            char character = value[index];
            if (character >= 'A' && character <= 'Z') {
                character = static_cast<char>(character - 'A' + 'a');
            }
            if (character != prefix[index]) {
                hasPrefix = false;
                break;
            }
        }
    }

    if (hasPrefix) {
        value.remove_prefix(prefix.size());
    } else if (requirePrefix) {
        error = "digest must use the sha256:<hex> format";
        return false;
    }

    if (!IsSha256Hex(value)) {
        error = "SHA-256 value must contain exactly 64 hexadecimal characters";
        return false;
    }

    normalized.assign(value);
    for (char& character : normalized) {
        if (character >= 'A' && character <= 'F') {
            character = static_cast<char>(character - 'A' + 'a');
        }
    }
    return true;
}

inline bool TrySha256File(
    const std::filesystem::path& path,
    std::string& digest,
    std::string& error) {
    digest.clear();

    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    HANDLE file = INVALID_HANDLE_VALUE;

    auto closeHash = [&]() {
        if (hash != nullptr) {
            BCryptDestroyHash(hash);
            hash = nullptr;
        }
    };
    auto closeAlgorithm = [&]() {
        if (algorithm != nullptr) {
            BCryptCloseAlgorithmProvider(algorithm, 0);
            algorithm = nullptr;
        }
    };
    auto closeFile = [&]() {
        if (file != INVALID_HANDLE_VALUE) {
            CloseHandle(file);
            file = INVALID_HANDLE_VALUE;
        }
    };

    NTSTATUS status = BCryptOpenAlgorithmProvider(
        &algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
    if (!BCRYPT_SUCCESS(status)) {
        error = BCryptErrorMessage(status);
        return false;
    }

    DWORD hashLength = 0;
    DWORD resultLength = 0;
    status = BCryptGetProperty(
        algorithm, BCRYPT_HASH_LENGTH,
        reinterpret_cast<PUCHAR>(&hashLength), sizeof(hashLength),
        &resultLength, 0);
    if (!BCRYPT_SUCCESS(status) || hashLength == 0) {
        error = !BCRYPT_SUCCESS(status)
                    ? BCryptErrorMessage(status)
                    : "BCrypt returned an invalid SHA-256 length";
        closeAlgorithm();
        return false;
    }

    status = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0);
    if (!BCRYPT_SUCCESS(status)) {
        error = BCryptErrorMessage(status);
        closeAlgorithm();
        return false;
    }

    file = CreateFileW(
        path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = "cannot open file for SHA-256: " + Win32ErrorMessage(GetLastError());
        closeHash();
        closeAlgorithm();
        return false;
    }

    std::vector<unsigned char> buffer(64 * 1024);
    for (;;) {
        DWORD bytesRead = 0;
        if (!ReadFile(
                file, buffer.data(), static_cast<DWORD>(buffer.size()),
                &bytesRead, nullptr)) {
            const DWORD readError = GetLastError();
            if (readError != ERROR_HANDLE_EOF) {
                error =
                    "cannot read file for SHA-256: " +
                    Win32ErrorMessage(readError);
                closeFile();
                closeHash();
                closeAlgorithm();
                return false;
            }
            break;
        }
        if (bytesRead == 0) {
            break;
        }
        status = BCryptHashData(hash, buffer.data(), bytesRead, 0);
        if (!BCRYPT_SUCCESS(status)) {
            error = BCryptErrorMessage(status);
            closeFile();
            closeHash();
            closeAlgorithm();
            return false;
        }
    }

    std::vector<unsigned char> hashValue(hashLength);
    status = BCryptFinishHash(
        hash, hashValue.data(), static_cast<ULONG>(hashValue.size()), 0);
    if (!BCRYPT_SUCCESS(status)) {
        error = BCryptErrorMessage(status);
        closeFile();
        closeHash();
        closeAlgorithm();
        return false;
    }

    closeFile();
    closeHash();
    closeAlgorithm();

    constexpr char hex[] = "0123456789abcdef";
    digest.reserve(hashValue.size() * 2);
    for (const unsigned char byte : hashValue) {
        digest.push_back(hex[byte >> 4]);
        digest.push_back(hex[byte & 0x0f]);
    }
    return true;
}

inline bool TryGetFileProductVersion(
    const std::filesystem::path& path,
    std::string& version,
    std::string& error) {
    version.clear();

    DWORD ignored = 0;
    const DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
    if (size == 0) {
        error = "cannot read version resource: " + Win32ErrorMessage(GetLastError());
        return false;
    }

    std::vector<unsigned char> data(size);
    if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
        error = "cannot load version resource: " + Win32ErrorMessage(GetLastError());
        return false;
    }

    VS_FIXEDFILEINFO* fixedInfo = nullptr;
    UINT fixedInfoSize = 0;
    if (!VerQueryValueW(
            data.data(), L"\\", reinterpret_cast<void**>(&fixedInfo), &fixedInfoSize) ||
        fixedInfo == nullptr ||
        fixedInfoSize < sizeof(VS_FIXEDFILEINFO) ||
        fixedInfo->dwSignature != 0xFEEF04BD) {
        error = "version resource has no valid VS_FIXEDFILEINFO";
        return false;
    }

    version =
        std::to_string(HIWORD(fixedInfo->dwProductVersionMS)) + "." +
        std::to_string(LOWORD(fixedInfo->dwProductVersionMS)) + "." +
        std::to_string(HIWORD(fixedInfo->dwProductVersionLS)) + "." +
        std::to_string(LOWORD(fixedInfo->dwProductVersionLS));
    return true;
}

}  // namespace reshade_launcher::update::detail
