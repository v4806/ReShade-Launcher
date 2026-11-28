#pragma once

#include <windows.h>
#include <shobjidl.h>

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "core/common.h"

namespace rs {

std::optional<std::filesystem::path> PickFile(
    HWND owner, const wchar_t* title, const COMDLG_FILTERSPEC* filters,
    UINT filter_count);
std::vector<std::filesystem::path> PickFiles(
    HWND owner, const wchar_t* title, const COMDLG_FILTERSPEC* filters,
    UINT filter_count);
std::optional<std::filesystem::path> PickFolder(HWND owner, const wchar_t* title);
bool Confirm(HWND owner, std::wstring_view title, std::wstring_view message);
void ShowInfo(HWND owner, std::wstring_view title, std::wstring_view message);
void ShowError(HWND owner, std::wstring_view title, std::wstring_view message);
void ShowDetails(HWND owner, std::wstring_view title,
                 std::wstring_view message, std::wstring_view details,
                 bool error);
int ShowChoiceDialog(HWND owner, std::wstring_view title,
                     std::wstring_view message,
                     std::wstring_view primary_label,
                     std::wstring_view secondary_label,
                     std::wstring_view cancel_label);

struct ProfileEditResult {
    Json config;
    std::string display_name;
    std::string custom_icon;
    bool deleted = false;
};

std::optional<ProfileEditResult> EditProfile(
    HWND owner, const Translation& translation, std::string_view config_name,
    const Json& config, std::string_view display_name,
    std::string_view custom_icon, const std::filesystem::path& background);

void ShowHelp(HWND owner, const Translation& translation,
              const std::filesystem::path& background);
std::string HelpText(const Translation& translation);

}  // namespace rs
