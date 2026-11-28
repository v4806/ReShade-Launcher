#pragma once

#include <cstdint>
#include <filesystem>
#include <functional>
#include <stdexcept>
#include <string>

namespace reshade_launcher::update {

struct ReleaseInfo {
    std::string tag;
    std::string version;
    std::string assetName;
    std::uint64_t assetSize = 0;
    std::string sha256;
    std::string downloadUrl;
};

struct UpdateCheckResult {
    bool updateAvailable = false;
    std::string currentVersion;
    ReleaseInfo release;
};

struct DownloadProgress {
    std::uint64_t downloadedBytes = 0;
    std::uint64_t totalBytes = 0;
};

class UpdateError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class UpdateCancelled : public UpdateError {
public:
    using UpdateError::UpdateError;
};

using CancelCallback = std::function<bool()>;
using DownloadProgressCallback = std::function<void(const DownloadProgress&)>;
// Optional hook that runs after size/SHA-256 verification and before the
// verified .part file is renamed to the final installer path.
using OptionalSignatureVerifier =
    std::function<bool(const std::filesystem::path& installerPath, std::string& error)>;

class UpdateClient {
public:
    UpdateCheckResult CheckForUpdate(
        const std::string& currentVersion,
        const CancelCallback& cancel = {}) const;

    std::filesystem::path DownloadInstaller(
        const ReleaseInfo& release,
        const std::filesystem::path& destination,
        const DownloadProgressCallback& progress = {},
        const CancelCallback& cancel = {},
        const OptionalSignatureVerifier& optionalSignatureVerifier = {}) const;

    std::filesystem::path DownloadFile(
        const std::string& url,
        std::uint64_t expectedSize,
        const std::string& expectedSha256,
        const std::filesystem::path& destination,
        const DownloadProgressCallback& progress = {},
        const CancelCallback& cancel = {}) const;
};

}  // namespace reshade_launcher::update
