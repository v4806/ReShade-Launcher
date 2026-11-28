#include <windows.h>

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include "core/common.h"
#include "game/game.h"
#include "miniz.h"
#include "update/update_internal.h"

namespace {

void Check(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAILED: " << message << '\n';
        std::exit(1);
    }
}

void WriteEmpty(const std::filesystem::path& path) {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream(path, std::ios::binary).put('\0');
}

bool WriteZip(const std::filesystem::path& path) {
    mz_zip_archive archive{};
    if (!mz_zip_writer_init_file(
            &archive, rs::WideToUtf8(path.wstring()).c_str(), 0)) {
        return false;
    }
    const char loader[] = "loader";
    const char core[] = "core";
    bool ok =
        mz_zip_writer_add_mem(&archive, "d3d11.dll", loader,
                              sizeof(loader) - 1, MZ_BEST_COMPRESSION) &&
        mz_zip_writer_add_mem(&archive, "Core/main.ini", core,
                              sizeof(core) - 1, MZ_BEST_COMPRESSION);
    ok = mz_zip_writer_finalize_archive(&archive) && ok;
    ok = mz_zip_writer_end(&archive) && ok;
    return ok;
}

}  // namespace

int wmain() {
    const auto temp = std::filesystem::temp_directory_path() /
                      (L"ReShadeLauncherCxxTests-" + std::to_wstring(GetCurrentProcessId()));
    std::error_code ec;
    std::filesystem::remove_all(temp, ec);
    std::filesystem::create_directories(temp);

    rs::AppData app(temp);
    app.Load();
    Check(!app.WindowClientSize(), "window size starts unset");
    Check(app.SetWindowClientSize(SIZE{812, 644}),
          "window size persisted");
    rs::AppData reloaded_app(temp);
    reloaded_app.Load();
    const auto saved_window_size = reloaded_app.WindowClientSize();
    Check(saved_window_size && saved_window_size->cx == 812 &&
              saved_window_size->cy == 644,
          "window size restored");
    rs::WriteUtf8Atomic(
        temp / L"version.json",
        R"({
  "builtin_mod_loaders": [
    {
      "folder_name": "AzurPromilia",
      "display_name": "蓝色星原",
      "exe_names": ["AzurPromilia.exe"],
      "download_url": "https://example.invalid/AzurPromilia.zip",
      "size": 6,
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    {
      "folder_name": "ZenlessZoneZero",
      "display_name": "绝区零",
      "exe_names": ["ZenlessZoneZero.exe", "ZenlessZoneZeroBeta.exe"],
      "download_url": "https://example.invalid/ZenlessZoneZero.zip",
      "size": 6,
      "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  ]
})");
    rs::ConfigManager configs(app);
    const auto game = temp / L"game" / L"AzurPromilia.exe";
    WriteEmpty(game);
    WriteEmpty(temp / L"MOD_loader" / L"AzurPromilia" / L"d3d11.dll");

    const auto builtin = configs.CreateBuiltin(game, true);
    Check(builtin.save_error.empty(), "builtin configuration persisted");
    Check(builtin.data["launch_args"] == "-start=azurpromilia_launcher",
          "Azur Promilia launch arguments");
    Check(builtin.display_name == "蓝色星原", "Azur Promilia display name");
    Check(builtin.data.contains("d3d11_path"), "builtin d3d11 discovery");
    const auto missing_loader_game = temp / L"game" / L"UnknownGame.exe";
    WriteEmpty(missing_loader_game);
    const auto missing_loader_config =
        configs.CreateBuiltin(missing_loader_game, true);
    Check(missing_loader_config.save_error.empty(),
          "builtin configuration without loader persisted");
    Check(missing_loader_config.data.contains("d3d11_path") &&
              missing_loader_config.data["d3d11_exists"] == false,
          "builtin loader path is retained for later manual installation");
    Check(builtin.data.contains("reshade_dll"), "ReShade option persisted");
    const auto azur_loader = configs.ResolveBuiltinModLoader(game);
    Check(azur_loader.folder_name == "AzurPromilia" &&
              azur_loader.display_name == "蓝色星原" &&
              azur_loader.downloadable(),
          "built-in loader metadata resolves");

    const auto loaded = configs.Load(builtin.config_name);
    Check(loaded.has_value(), "configuration reload");
    Check(loaded->data["mode"] == "builtin", "configuration mode reload");

    rs::WriteUtf8Atomic(
        app.config_path("invalid_mode"),
        "{\"mode\":null,\"game_dir\":\"invalid.exe\"}");
    const auto profiles = configs.ListProfiles();
    Check(std::none_of(profiles.begin(), profiles.end(),
                       [](const auto& profile) {
                           return profile.config_name == "invalid_mode";
                       }),
          "invalid configuration mode skipped");

    const auto beta_game =
        temp / L"game" / L"ZenlessZoneZeroBeta.exe";
    WriteEmpty(beta_game);
    const auto beta_xxmi_exe =
        temp / L"XXMI" / L"Resources" / L"Bin" / L"XXMI Launcher.exe";
    WriteEmpty(temp / L"XXMI" / L"ZZMI" / L"d3d11.dll");
    const auto beta_xxmi = configs.CreateXXMI(
        beta_game, beta_xxmi_exe, false);
    Check(beta_xxmi.save_error.empty(),
          "Zenless Zone Zero Beta XXMI configuration persisted");
    Check(beta_xxmi.data["xxmi_module"] == "ZZMI",
          "Zenless Zone Zero Beta maps to ZZMI");
    Check(beta_xxmi.data["dll_files"].size() == 1,
          "XXMI module DLL is recorded");
    const auto beta_loader = configs.ResolveBuiltinModLoader(beta_game);
    Check(beta_loader.folder_name == "ZenlessZoneZero",
          "Zenless Zone Zero Beta maps to the production loader");

    const auto loader_archive = temp / L"loader-test.zip";
    Check(WriteZip(loader_archive), "test Mod loader archive created");
    const auto existing_mod =
        temp / L"MOD_loader" / L"TestLoader" / L"Mods" / L"keep.ini";
    WriteEmpty(existing_mod);
    rs::ModLoaderManager mod_loaders(app);
    std::string loader_error;
    Check(mod_loaders.InstallArchive(loader_archive, "TestLoader",
                                     &loader_error),
          "Mod loader archive installs");
    Check(rs::FileExists(temp / L"MOD_loader" / L"TestLoader" /
                         L"d3d11.dll"),
          "Mod loader archive places d3d11.dll");
    Check(rs::FileExists(existing_mod),
          "Mod loader archive preserves user Mods");

    const auto missing_xxmi_game =
        temp / L"game" / L"StarRail.exe";
    WriteEmpty(missing_xxmi_game);
    const auto missing_xxmi = configs.CreateXXMI(
        missing_xxmi_game,
        temp / L"MissingXXMI" / L"Resources" / L"Bin" /
            L"XXMI Launcher.exe",
        false);
    Check(!missing_xxmi.save_error.empty(),
          "missing XXMI module DLL is rejected");

    const auto preset_ini = temp / L"preset" / L"d3dx_user.ini";
    const auto preset_mod = temp / L"preset" / L"Mods" / L"sample" / L"sample.ini";
    rs::WriteUtf8Atomic(
        preset_ini,
        "[Constants]\n\\ShaderFixes\\sample.ini\\$enabled = 1\n");
    rs::WriteUtf8Atomic(
        preset_mod,
        "namespace = sample\\sample.ini\n[Constants]\n$enabled = 0\n");
    std::vector<std::string> preset_log;
    const auto preset_result =
        rs::ModPresetService::Apply(preset_ini, preset_ini.parent_path() / L"Mods",
                                    [&](const std::string& line) {
                                        preset_log.push_back(line);
                                    });
    Check(preset_result.updated_files == 1, "Mod preset file updated");
    Check(!preset_log.empty(), "Mod preset progress callback");
    Check(rs::ReadUtf8(preset_mod).value_or("").find("$enabled = 1") !=
              std::string::npos,
          "Mod preset value synchronized");

    rs::Json custom = {
        {"launch_program", rs::WideToUtf8(game.wstring())},
        {"target_program", rs::WideToUtf8(game.wstring())},
        {"injection_method", "direct"},
        {"dll_files", rs::Json::array()},
    };
    const auto reshade = temp / L"ReShade" / L"ReShade64.dll";
    const auto first = temp / L"first.dll";
    const auto second = temp / L"second.dll";
    WriteEmpty(reshade);
    WriteEmpty(first);
    WriteEmpty(second);
    custom["reshade_dll"] = "ReShade64.dll";

    rs::Json builtin_launch = {
        {"mode", "builtin"},
        {"mod_loader_dir",
         rs::WideToUtf8(
             (temp / L"MOD_loader" / L"AzurPromilia").wstring())},
        {"injection_method", "direct"},
        {"launch_program", rs::WideToUtf8(game.wstring())},
        {"target_program", rs::WideToUtf8(game.wstring())},
    };
    rs::ProcessManager builtin_processes(app);
    std::string builtin_error;
    const auto builtin_plan =
        builtin_processes.BuildInjectionPlan(builtin_launch, &builtin_error);
    Check(builtin_error.empty() && builtin_plan.direct_dlls.size() == 1 &&
              builtin_plan.direct_dlls.front().filename() == L"d3d11.dll",
          "builtin loader is resolved at launch time");

    const auto custom_config = configs.CreateCustom(
        game,
        {rs::Utf8ToWide("ReShade64.dll"), first, first},
        false);
    Check(custom_config.save_error.empty(),
          "custom configuration with ReShade persisted");
    Check(custom_config.data["reshade_dll"] == "ReShade64.dll",
          "custom ReShade selection enables managed ReShade");
    Check(custom_config.data["dll_files"].size() == 1,
          "custom DLLs are de-duplicated without managed ReShade");

    custom["dll_files"].push_back(rs::WideToUtf8(first.wstring()));
    custom["dll_files"].push_back(rs::WideToUtf8(second.wstring()));
    custom["dll_files"].push_back(rs::WideToUtf8(first.wstring()));
    rs::ProcessManager processes(app);
    std::string error;
    const auto plan = processes.BuildInjectionPlan(custom, &error);
    Check(error.empty(), "injection plan error");
    Check(plan.direct_dlls.size() == 3, "injection order count");
    Check(plan.direct_dlls[0].filename() == L"ReShade64.dll", "ReShade injected first");
    Check(plan.direct_dlls[1] == first, "first custom DLL injected");
    Check(plan.direct_dlls[2] == second, "second custom DLL injected");

    custom["reshade_dll"] = nullptr;
    error.clear();
    const auto no_reshade = processes.BuildInjectionPlan(custom, &error);
    Check(error.empty(), "null ReShade value ignored");
    Check(no_reshade.direct_dlls.size() == 2,
          "null ReShade value does not inject");
    custom["reshade_dll"] = "ReShade64.dll";

    const auto wuthering_client =
        temp / L"game" / L"Client" / L"Binaries" / L"Win64" /
        L"Client-Win64-Shipping.exe";
    const auto wuthering_launcher = temp / L"game" / L"Wuthering Waves.exe";
    WriteEmpty(wuthering_client);
    WriteEmpty(wuthering_launcher);
    const auto wuthering = configs.CreateBuiltin(wuthering_client, false);
    std::error_code equivalent_error;
    const bool launcher_matches = std::filesystem::equivalent(
        rs::Utf8ToWide(wuthering.data["launch_program"].get<std::string>()),
        wuthering_launcher, equivalent_error);
    Check(!equivalent_error && launcher_matches,
          "Wuthering Waves launcher discovery");
    Check(wuthering.data["launch_args"] == "-dx11",
          "Wuthering Waves launch arguments");

    const auto hook_dll = temp / L"hook" / L"d3d11.dll";
    WriteEmpty(hook_dll);
    custom.erase("reshade_dll");
    custom["injection_method"] = "hook";
    custom["launch_program"] = rs::WideToUtf8(game.wstring());
    custom["target_program"] = rs::WideToUtf8(game.wstring());
    custom["dll_files"] = rs::Json::array();
    custom["dll_files"].push_back(rs::WideToUtf8(hook_dll.wstring()));
    error.clear();
    const auto hook_plan = processes.BuildInjectionPlan(custom, &error);
    Check(error.empty() && hook_plan.hook_dll == hook_dll,
          "HOOK finds d3d11.dll in dll_files");

    custom.erase("reshade_dll");
    custom["dll_files"] = rs::Json::array();
    custom["dll_files"].push_back(rs::WideToUtf8((temp / L"Missing.dll").wstring()));
    error.clear();
    const auto invalid = processes.BuildInjectionPlan(custom, &error);
    Check(!error.empty() && invalid.direct_dlls.empty(), "missing DLL rejected");

    const auto hash_file = temp / L"hash.txt";
    rs::WriteUtf8Atomic(hash_file, "abc");
    Check(rs::Sha256File(hash_file) ==
              "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          "SHA-256");

    std::string digest =
        "sha256:c6f6d435e0eeda453804fa66083cc3c1d5a2876be6dabf8d9ef11bbb34d80e1e";
    error.clear();
    Check(reshade_launcher::update::detail::TryNormalizeSha256(
              digest, true, digest, error),
          "SHA-256 digest normalization");
    Check(digest ==
              "c6f6d435e0eeda453804fa66083cc3c1d5a2876be6dabf8d9ef11bbb34d80e1e",
          "SHA-256 in-place normalization");

    std::filesystem::remove_all(temp, ec);
    std::cout << "core tests passed\n";
    return 0;
}
