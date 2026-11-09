import json
import zipfile
from pathlib import Path

import reshade_launcher.update.update_manager as 更新管理器


ROOT = Path(__file__).resolve().parents[1]


def test_update_configuration_uses_3dmloader_instead_of_injector():
    manifest_paths = {item["path"] for item in 更新管理器.MANIFEST_ITEMS}
    update_ids = {
        item["id"]
        for group in 更新管理器.UPDATE_GROUPS
        for item in group["items"]
    }

    assert "injector.exe" not in manifest_paths
    assert "injector.exe" not in update_ids
    assert "update.item.injector" not in update_ids


def test_update_manifest_uses_application_zip_and_not_injector():
    manifest = json.loads((ROOT / "update_manifest.json").read_text(encoding="utf-8"))
    item_paths = {item["path"] for item in manifest.get("items", [])}

    assert "injector.exe" not in item_paths
    assert manifest["app"]["url"].endswith(".zip")


def test_pyinstaller_specs_include_3dmloader_and_relative_icon():
    for spec_name in ("ReShade Launcher Build.spec", "ReShade Debug.spec"):
        spec_text = (ROOT / "packaging" / spec_name).read_text(encoding="utf-8")
        assert "3dmloader.dll" in spec_text
        assert "D:\\\\DEV\\\\ReShade-Launcher-sync\\\\icon.ico" not in spec_text


def test_translations_do_not_tell_users_to_install_injector():
    translations = (ROOT / "translations.json").read_text(encoding="utf-8")

    assert "injector.exe" not in translations
    assert "3dmloader.dll" in translations


def test_application_update_zip_contains_packaged_injector():
    manifest = json.loads((ROOT / "update_manifest.json").read_text(encoding="utf-8"))
    zip_name = manifest["app"]["url"].rsplit("/", 1)[-1]
    zip_path = ROOT / "update" / zip_name
    with zipfile.ZipFile(zip_path) as archive:
        names = set(archive.namelist())

    assert "_internal/3dmloader.dll" in names
    assert "injector.exe" not in names
    assert "ReShade Launcher Build.exe" in names
    assert "ReShade Debug.exe" in names
