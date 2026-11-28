#include "update_client.h"

#include "update_internal.h"

#include <winhttp.h>

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdint>
#include <cwchar>
#include <limits>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace reshade_launcher::update {
namespace {

using detail::Version;
using detail::Win32ErrorMessage;

constexpr wchar_t kApiHost[] = L"api.github.com";
constexpr wchar_t kApiPath[] =
    L"/repos/v4806/ReShade-Launcher/releases/latest";
constexpr wchar_t kRepositoryOwner[] = L"v4806";
constexpr wchar_t kRepositoryName[] = L"ReShade-Launcher";
constexpr std::uint64_t kMaximumApiResponseBytes = 4ULL * 1024ULL * 1024ULL;
constexpr DWORD kReadChunkSize = 64 * 1024;

[[noreturn]] void ThrowWinHttpError(std::string_view operation) {
    throw UpdateError(
        std::string(operation) + ": " + Win32ErrorMessage(GetLastError()));
}

void ThrowIfCancelled(const CancelCallback& cancel) {
    if (cancel && cancel()) {
        throw UpdateCancelled("update cancelled");
    }
}

class WinHttpHandle {
public:
    WinHttpHandle() = default;
    explicit WinHttpHandle(HINTERNET handle) : handle_(handle) {}

    WinHttpHandle(const WinHttpHandle&) = delete;
    WinHttpHandle& operator=(const WinHttpHandle&) = delete;

    WinHttpHandle(WinHttpHandle&& other) noexcept : handle_(other.handle_) {
        other.handle_ = nullptr;
    }

    WinHttpHandle& operator=(WinHttpHandle&& other) noexcept {
        if (this != &other) {
            if (handle_ != nullptr) {
                WinHttpCloseHandle(handle_);
            }
            handle_ = other.handle_;
            other.handle_ = nullptr;
        }
        return *this;
    }

    ~WinHttpHandle() {
        if (handle_ != nullptr) {
            WinHttpCloseHandle(handle_);
        }
    }

    HINTERNET get() const {
        return handle_;
    }

private:
    HINTERNET handle_ = nullptr;
};

class HttpRequest {
public:
    HttpRequest(
        const std::wstring& host,
        const std::wstring& path,
        std::wstring_view headers) {
        session_ = WinHttpHandle(WinHttpOpen(
            L"ReShade-Launcher-Update-Client/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME,
            WINHTTP_NO_PROXY_BYPASS,
            0));
        if (session_.get() == nullptr) {
            ThrowWinHttpError("WinHttpOpen failed");
        }

        if (!WinHttpSetTimeouts(session_.get(), 30000, 60000, 60000, 120000)) {
            ThrowWinHttpError("WinHttpSetTimeouts failed");
        }

        connection_ = WinHttpHandle(WinHttpConnect(
            session_.get(), host.c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0));
        if (connection_.get() == nullptr) {
            ThrowWinHttpError("WinHttpConnect failed");
        }

        request_ = WinHttpHandle(WinHttpOpenRequest(
            connection_.get(), L"GET", path.c_str(), nullptr,
            WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
            WINHTTP_FLAG_SECURE));
        if (request_.get() == nullptr) {
            ThrowWinHttpError("WinHttpOpenRequest failed");
        }

        DWORD redirectPolicy = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
        if (!WinHttpSetOption(
                request_.get(), WINHTTP_OPTION_REDIRECT_POLICY,
                &redirectPolicy, sizeof(redirectPolicy))) {
            ThrowWinHttpError("cannot enable WinHTTP redirects");
        }

        if (!headers.empty() &&
            !WinHttpAddRequestHeaders(
                request_.get(), headers.data(), static_cast<DWORD>(headers.size()),
                WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE)) {
            ThrowWinHttpError("WinHttpAddRequestHeaders failed");
        }
    }

    void Send() {
        if (!WinHttpSendRequest(
                request_.get(), WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
            ThrowWinHttpError("WinHttpSendRequest failed");
        }
        if (!WinHttpReceiveResponse(request_.get(), nullptr)) {
            ThrowWinHttpError("WinHttpReceiveResponse failed");
        }

        DWORD statusCode = 0;
        DWORD statusCodeSize = sizeof(statusCode);
        if (!WinHttpQueryHeaders(
                request_.get(),
                WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &statusCodeSize,
                WINHTTP_NO_HEADER_INDEX)) {
            ThrowWinHttpError("cannot query HTTP status");
        }
        if (statusCode != HTTP_STATUS_OK) {
            throw UpdateError(
                "HTTP request failed with status " + std::to_string(statusCode));
        }
    }

    std::uint64_t QueryContentLength(bool& present) const {
        wchar_t value[64]{};
        DWORD valueSize = sizeof(value);
        if (!WinHttpQueryHeaders(
                request_.get(), WINHTTP_QUERY_CONTENT_LENGTH,
                WINHTTP_HEADER_NAME_BY_INDEX, value, &valueSize,
                WINHTTP_NO_HEADER_INDEX)) {
            const DWORD error = GetLastError();
            if (error == ERROR_WINHTTP_HEADER_NOT_FOUND) {
                present = false;
                return 0;
            }
            throw UpdateError(
                "cannot query Content-Length: " + Win32ErrorMessage(error));
        }

        present = true;
        wchar_t* end = nullptr;
        errno = 0;
        const unsigned long long parsed = std::wcstoull(value, &end, 10);
        if (errno == ERANGE || end == value || (end != nullptr && *end != L'\0')) {
            throw UpdateError("server returned an invalid Content-Length");
        }
        return static_cast<std::uint64_t>(parsed);
    }

    HINTERNET get() const {
        return request_.get();
    }

private:
    WinHttpHandle session_;
    WinHttpHandle connection_;
    WinHttpHandle request_;
};

class PartialFile {
public:
    explicit PartialFile(std::filesystem::path path) : path_(std::move(path)) {}

    PartialFile(const PartialFile&) = delete;
    PartialFile& operator=(const PartialFile&) = delete;

    ~PartialFile() {
        Close();
        if (!keep_) {
            std::error_code ignored;
            std::filesystem::remove(path_, ignored);
        }
    }

    void Open() {
        handle_ = CreateFileW(
            path_.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
        if (handle_ == INVALID_HANDLE_VALUE) {
            throw UpdateError(
                "cannot create .part file: " + Win32ErrorMessage(GetLastError()));
        }
    }

    void Close() {
        if (handle_ != INVALID_HANDLE_VALUE) {
            CloseHandle(handle_);
            handle_ = INVALID_HANDLE_VALUE;
        }
    }

    void Write(const unsigned char* data, DWORD size) {
        DWORD written = 0;
        if (!WriteFile(handle_, data, size, &written, nullptr) || written != size) {
            throw UpdateError(
                "cannot write .part file: " + Win32ErrorMessage(GetLastError()));
        }
    }

    const std::filesystem::path& path() const {
        return path_;
    }

    void Keep() {
        keep_ = true;
    }

private:
    std::filesystem::path path_;
    HANDLE handle_ = INVALID_HANDLE_VALUE;
    bool keep_ = false;
};

bool EqualsIgnoreCase(std::wstring_view left, std::wstring_view right) {
    if (left.size() != right.size()) {
        return false;
    }
    for (std::size_t index = 0; index < left.size(); ++index) {
        wchar_t leftCharacter = left[index];
        wchar_t rightCharacter = right[index];
        if (leftCharacter >= L'A' && leftCharacter <= L'Z') {
            leftCharacter = static_cast<wchar_t>(leftCharacter - L'A' + L'a');
        }
        if (rightCharacter >= L'A' && rightCharacter <= L'Z') {
            rightCharacter = static_cast<wchar_t>(rightCharacter - L'A' + L'a');
        }
        if (leftCharacter != rightCharacter) {
            return false;
        }
    }
    return true;
}

struct ParsedHttpsUrl {
    std::wstring host;
    std::wstring path;
};

bool TryParseHttpsUrl(const std::string& utf8Url, ParsedHttpsUrl& result) {
    const std::wstring wideUrl = detail::Utf8ToWide(utf8Url);
    if (wideUrl.empty()) {
        return false;
    }

    URL_COMPONENTS components{};
    components.dwStructSize = sizeof(components);
    components.dwSchemeLength = static_cast<DWORD>(-1);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);

    if (!WinHttpCrackUrl(
            wideUrl.c_str(), static_cast<DWORD>(wideUrl.size()), 0, &components)) {
        return false;
    }
    if (components.nScheme != INTERNET_SCHEME_HTTPS ||
        components.nPort != INTERNET_DEFAULT_HTTPS_PORT ||
        components.lpszHostName == nullptr ||
        components.lpszUrlPath == nullptr ||
        components.dwExtraInfoLength != 0) {
        return false;
    }

    result.host.assign(components.lpszHostName, components.dwHostNameLength);
    result.path.assign(components.lpszUrlPath, components.dwUrlPathLength);
    return !result.host.empty() && !result.path.empty();
}

void ValidateReleaseUrl(const ReleaseInfo& release) {
    ParsedHttpsUrl url;
    if (!TryParseHttpsUrl(release.downloadUrl, url)) {
        throw UpdateError("release asset URL must be a direct HTTPS URL");
    }
    if (!EqualsIgnoreCase(url.host, L"github.com")) {
        throw UpdateError("release asset URL must use github.com");
    }

    const std::wstring tag = detail::Utf8ToWide(release.tag);
    const std::wstring assetName = detail::Utf8ToWide(release.assetName);
    if (tag.empty() || assetName.empty()) {
        throw UpdateError("release tag or asset name is not valid UTF-8");
    }

    const std::wstring expectedPath =
        std::wstring(L"/") + kRepositoryOwner + L"/" + kRepositoryName +
        L"/releases/download/" + tag + L"/" + assetName;
    if (url.path != expectedPath) {
        throw UpdateError(
            "release asset URL does not match the repository, tag, and asset name");
    }
}

ReleaseInfo ValidateRelease(const ReleaseInfo& input) {
    ReleaseInfo release = input;
    std::string error;

    Version version;
    if (!detail::TryParseVersion(release.tag, true, version, error)) {
        throw UpdateError("invalid release tag '" + release.tag + "': " + error);
    }
    release.version = detail::VersionToString(version);

    const std::string expectedAsset =
        "ReShade-Launcher-installer-" + release.tag + ".exe";
    if (release.assetName != expectedAsset) {
        throw UpdateError(
            "release asset must be exactly '" + expectedAsset +
            "', got '" + release.assetName + "'");
    }
    if (release.assetSize == 0) {
        throw UpdateError("release asset size must be greater than zero");
    }
    if (!detail::TryNormalizeSha256(
            release.sha256, false, release.sha256, error)) {
        throw UpdateError("invalid release asset digest: " + error);
    }
    ValidateReleaseUrl(release);
    return release;
}

std::string GetLatestReleaseJson(const CancelCallback& cancel) {
    ThrowIfCancelled(cancel);
    HttpRequest request(
        kApiHost, kApiPath,
        L"Accept: application/vnd.github+json\r\n"
        L"X-GitHub-Api-Version: 2022-11-28\r\n");
    request.Send();
    ThrowIfCancelled(cancel);

    std::vector<unsigned char> body;
    std::array<unsigned char, kReadChunkSize> buffer{};
    for (;;) {
        ThrowIfCancelled(cancel);

        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request.get(), &available)) {
            ThrowWinHttpError("WinHttpQueryDataAvailable failed");
        }
        if (available == 0) {
            break;
        }

        while (available != 0) {
            ThrowIfCancelled(cancel);
            const DWORD toRead = (std::min)(available, kReadChunkSize);
            DWORD bytesRead = 0;
            if (!WinHttpReadData(
                    request.get(), buffer.data(), toRead, &bytesRead)) {
                ThrowWinHttpError("WinHttpReadData failed");
            }
            if (bytesRead == 0) {
                break;
            }
            if (body.size() + bytesRead > kMaximumApiResponseBytes) {
                throw UpdateError("GitHub API response is unexpectedly large");
            }
            body.insert(body.end(), buffer.begin(), buffer.begin() + bytesRead);
            available -= bytesRead;
        }
    }

    ThrowIfCancelled(cancel);
    return std::string(body.begin(), body.end());
}

std::string RequireStringField(
    const nlohmann::json& object,
    const char* fieldName) {
    const auto iterator = object.find(fieldName);
    if (iterator == object.end() || !iterator->is_string()) {
        throw UpdateError(std::string("GitHub response has no string field '") +
                          fieldName + "'");
    }
    return iterator->get<std::string>();
}

ReleaseInfo ParseLatestRelease(const std::string& body) {
    nlohmann::json document;
    try {
        document = nlohmann::json::parse(body);
    } catch (const nlohmann::json::exception& exception) {
        throw UpdateError(
            std::string("cannot parse GitHub release JSON: ") + exception.what());
    }

    if (!document.is_object()) {
        throw UpdateError("GitHub release response is not a JSON object");
    }

    const std::string tag = RequireStringField(document, "tag_name");
    Version parsedTag;
    std::string versionError;
    if (!detail::TryParseVersion(tag, true, parsedTag, versionError)) {
        throw UpdateError("invalid release tag '" + tag + "': " + versionError);
    }

    const std::string expectedAsset =
        "ReShade-Launcher-installer-" + tag + ".exe";
    const auto assetsIterator = document.find("assets");
    if (assetsIterator == document.end() || !assetsIterator->is_array()) {
        throw UpdateError("GitHub response has no assets array");
    }

    const nlohmann::json* selectedAsset = nullptr;
    for (const auto& asset : *assetsIterator) {
        if (!asset.is_object()) {
            continue;
        }
        const auto nameIterator = asset.find("name");
        if (nameIterator == asset.end() || !nameIterator->is_string()) {
            continue;
        }
        if (nameIterator->get<std::string>() != expectedAsset) {
            continue;
        }
        if (selectedAsset != nullptr) {
            throw UpdateError(
                "GitHub release contains duplicate installer assets");
        }
        selectedAsset = &asset;
    }

    if (selectedAsset == nullptr) {
        throw UpdateError(
            "GitHub release does not contain the required asset '" +
            expectedAsset + "'");
    }

    const auto sizeIterator = selectedAsset->find("size");
    if (sizeIterator == selectedAsset->end() ||
        (!sizeIterator->is_number_unsigned() &&
         !sizeIterator->is_number_integer())) {
        throw UpdateError("release asset has no valid unsigned size");
    }

    ReleaseInfo release;
    release.tag = tag;
    release.version = detail::VersionToString(parsedTag);
    release.assetName = expectedAsset;
    if (sizeIterator->is_number_unsigned()) {
        release.assetSize = sizeIterator->get<std::uint64_t>();
    } else {
        const std::int64_t signedSize = sizeIterator->get<std::int64_t>();
        if (signedSize <= 0) {
            throw UpdateError("release asset has no valid positive size");
        }
        release.assetSize = static_cast<std::uint64_t>(signedSize);
    }
    release.downloadUrl =
        RequireStringField(*selectedAsset, "browser_download_url");

    const auto digestIterator = selectedAsset->find("digest");
    if (digestIterator == selectedAsset->end() ||
        !digestIterator->is_string()) {
        throw UpdateError(
            "release asset has no SHA-256 digest; refusing an unverifiable update");
    }

    std::string digestError;
    if (!detail::TryNormalizeSha256(
            digestIterator->get<std::string>(), true, release.sha256,
            digestError)) {
        throw UpdateError("release asset digest is invalid: " + digestError);
    }

    return ValidateRelease(release);
}

void ReportProgress(
    const DownloadProgressCallback& progress,
    std::uint64_t downloaded,
    std::uint64_t total) {
    if (progress) {
        progress(DownloadProgress{downloaded, total});
    }
}

}  // namespace

UpdateCheckResult UpdateClient::CheckForUpdate(
    const std::string& currentVersion,
    const CancelCallback& cancel) const {
    Version localVersion;
    std::string versionError;
    if (!detail::TryParseVersion(
            currentVersion, false, localVersion, versionError)) {
        throw UpdateError(
            "invalid current version '" + currentVersion + "': " + versionError);
    }

    const ReleaseInfo release =
        ParseLatestRelease(GetLatestReleaseJson(cancel));

    Version remoteVersion;
    if (!detail::TryParseVersion(
            release.tag, true, remoteVersion, versionError)) {
        throw UpdateError(
            "invalid latest release tag '" + release.tag + "': " + versionError);
    }

    UpdateCheckResult result;
    result.currentVersion = detail::VersionToString(localVersion);
    result.release = release;
    result.updateAvailable =
        detail::CompareVersions(remoteVersion, localVersion) > 0;
    return result;
}

std::filesystem::path UpdateClient::DownloadInstaller(
    const ReleaseInfo& releaseInput,
    const std::filesystem::path& destinationInput,
    const DownloadProgressCallback& progress,
    const CancelCallback& cancel,
    const OptionalSignatureVerifier& optionalSignatureVerifier) const {
    ThrowIfCancelled(cancel);
    const ReleaseInfo release = ValidateRelease(releaseInput);

    if (destinationInput.empty() || destinationInput.filename().empty()) {
        throw UpdateError("installer destination must name a file");
    }

    std::error_code filesystemError;
    std::filesystem::path destination =
        std::filesystem::absolute(destinationInput, filesystemError);
    if (filesystemError) {
        throw UpdateError(
            "cannot resolve installer destination: " +
            filesystemError.message());
    }

    const std::filesystem::path parent = destination.parent_path();
    if (!parent.empty()) {
        std::filesystem::create_directories(parent, filesystemError);
        if (filesystemError) {
            throw UpdateError(
                "cannot create installer destination directory: " +
                filesystemError.message());
        }
    }

    PartialFile part(destination.wstring() + L".part");
    part.Open();
    ReportProgress(progress, 0, release.assetSize);

    ParsedHttpsUrl assetUrl;
    if (!TryParseHttpsUrl(release.downloadUrl, assetUrl)) {
        throw UpdateError("release asset URL is invalid");
    }

    HttpRequest request(
        assetUrl.host, assetUrl.path,
        L"Accept: application/octet-stream\r\n");
    ThrowIfCancelled(cancel);
    request.Send();

    bool hasContentLength = false;
    const std::uint64_t contentLength =
        request.QueryContentLength(hasContentLength);
    if (hasContentLength && contentLength != release.assetSize) {
        throw UpdateError(
            "server Content-Length does not match the release asset size");
    }

    std::array<unsigned char, kReadChunkSize> buffer{};
    std::uint64_t downloaded = 0;
    for (;;) {
        ThrowIfCancelled(cancel);

        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request.get(), &available)) {
            ThrowWinHttpError("WinHttpQueryDataAvailable failed");
        }
        if (available == 0) {
            break;
        }

        while (available != 0) {
            ThrowIfCancelled(cancel);
            const DWORD toRead = (std::min)(available, kReadChunkSize);
            DWORD bytesRead = 0;
            if (!WinHttpReadData(
                    request.get(), buffer.data(), toRead, &bytesRead)) {
                ThrowWinHttpError("WinHttpReadData failed");
            }
            if (bytesRead == 0) {
                break;
            }
            if (downloaded + bytesRead > release.assetSize) {
                throw UpdateError(
                    "downloaded data exceeds the release asset size");
            }

            part.Write(buffer.data(), bytesRead);
            downloaded += bytesRead;
            ReportProgress(progress, downloaded, release.assetSize);
            available -= bytesRead;
        }
    }

    if (downloaded != release.assetSize) {
        throw UpdateError(
            "downloaded size does not match the release asset size");
    }

    part.Close();

    std::string actualDigest;
    std::string hashError;
    if (!detail::TrySha256File(part.path(), actualDigest, hashError)) {
        throw UpdateError("cannot hash downloaded installer: " + hashError);
    }
    if (actualDigest != release.sha256) {
        throw UpdateError(
            "downloaded installer SHA-256 does not match the release digest");
    }

    ThrowIfCancelled(cancel);
    if (optionalSignatureVerifier) {
        std::string signatureError;
        if (!optionalSignatureVerifier(part.path(), signatureError)) {
            throw UpdateError(
                signatureError.empty()
                    ? "optional installer signature verification failed"
                    : "optional installer signature verification failed: " +
                          signatureError);
        }
    }

    ThrowIfCancelled(cancel);
    if (!MoveFileExW(
            part.path().c_str(), destination.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        throw UpdateError(
            "cannot finalize installer download: " +
            Win32ErrorMessage(GetLastError()));
    }
    part.Keep();
    return destination;
}

std::filesystem::path UpdateClient::DownloadFile(
    const std::string& url,
    std::uint64_t expectedSize,
    const std::string& expectedSha256,
    const std::filesystem::path& destinationInput,
    const DownloadProgressCallback& progress,
    const CancelCallback& cancel) const {
    ThrowIfCancelled(cancel);
    if (expectedSize == 0) {
        throw UpdateError("download size must be greater than zero");
    }
    std::string normalizedSha;
    std::string hashError;
    if (!detail::TryNormalizeSha256(
            expectedSha256, false, normalizedSha, hashError)) {
        throw UpdateError("invalid download SHA-256: " + hashError);
    }
    ParsedHttpsUrl assetUrl;
    if (!TryParseHttpsUrl(url, assetUrl)) {
        throw UpdateError("download URL must be a direct HTTPS URL");
    }
    if (destinationInput.empty() || destinationInput.filename().empty()) {
        throw UpdateError("download destination must name a file");
    }
    std::error_code filesystemError;
    const auto destination = std::filesystem::absolute(destinationInput, filesystemError);
    if (filesystemError) {
        throw UpdateError("cannot resolve download destination: " +
                          filesystemError.message());
    }
    std::filesystem::create_directories(destination.parent_path(), filesystemError);
    if (filesystemError) {
        throw UpdateError("cannot create download directory: " +
                          filesystemError.message());
    }

    PartialFile part(destination.wstring() + L".part");
    part.Open();
    ReportProgress(progress, 0, expectedSize);
    HttpRequest request(assetUrl.host, assetUrl.path,
                        L"Accept: application/octet-stream\r\n");
    request.Send();
    bool hasContentLength = false;
    const auto contentLength = request.QueryContentLength(hasContentLength);
    if (hasContentLength && contentLength != expectedSize) {
        throw UpdateError("download Content-Length does not match expected size");
    }

    std::array<unsigned char, kReadChunkSize> buffer{};
    std::uint64_t downloaded = 0;
    for (;;) {
        ThrowIfCancelled(cancel);
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request.get(), &available)) {
            ThrowWinHttpError("WinHttpQueryDataAvailable failed");
        }
        if (available == 0) break;
        while (available != 0) {
            ThrowIfCancelled(cancel);
            const DWORD toRead = (std::min)(available, kReadChunkSize);
            DWORD read = 0;
            if (!WinHttpReadData(request.get(), buffer.data(), toRead, &read)) {
                ThrowWinHttpError("WinHttpReadData failed");
            }
            if (read == 0) break;
            if (downloaded + read > expectedSize) {
                throw UpdateError("downloaded data exceeds expected size");
            }
            part.Write(buffer.data(), read);
            downloaded += read;
            ReportProgress(progress, downloaded, expectedSize);
            available -= read;
        }
    }
    if (downloaded != expectedSize) {
        throw UpdateError("downloaded size does not match expected size");
    }
    part.Close();
    std::string actual;
    if (!detail::TrySha256File(part.path(), actual, hashError)) {
        throw UpdateError("cannot hash download: " + hashError);
    }
    if (actual != normalizedSha) {
        throw UpdateError("download SHA-256 does not match expected digest");
    }
    ThrowIfCancelled(cancel);
    if (!MoveFileExW(part.path().c_str(), destination.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        throw UpdateError("cannot finalize download: " +
                          Win32ErrorMessage(GetLastError()));
    }
    part.Keep();
    return destination;
}

}  // namespace reshade_launcher::update
