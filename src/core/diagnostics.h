#pragma once

#include <filesystem>
#include <string_view>

namespace rs {

bool InitializeDiagnostics();
void ShutdownDiagnostics();
void DebugLog(std::string_view message);
void DebugLog(std::wstring_view message);
const std::filesystem::path& DiagnosticsLogPath();

}  // namespace rs
