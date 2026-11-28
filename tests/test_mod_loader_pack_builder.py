import json
import zipfile
from pathlib import Path

from tools.build_mod_loader_packs import build_mod_loader_packs


def _write(path: Path, content: str | bytes = b"data") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content, encoding="utf-8")


def test_builds_known_loader_archives_and_manifest(tmp_path):
    root = tmp_path / "MOD_loader"
    _write(root / "AzurPromilia" / "d3d11.dll", b"loader")
    _write(root / "AzurPromilia" / "Core" / "Core.ini", "core")
    _write(root / "AzurPromilia" / "Mods" / "user" / "mod.ini", "user")
    _write(root / "AzurPromilia" / "MODS" / "user" / "leak.ini", "user")
    _write(root / "AzurPromilia" / "d3dx_user.ini", "user")
    _write(root / "UnknownGame" / "d3d11.dll", b"unknown")
    version_file = tmp_path / "version.json"
    version_file.write_text('{"xxmi_games": []}\n', encoding="utf-8")
    output = tmp_path / "mod-loaders"

    entries = build_mod_loader_packs(root, output, version_file)

    assert [entry["folder_name"] for entry in entries] == ["AzurPromilia"]
    entry = entries[0]
    assert entry["display_name"] == "蓝色星原"
    assert entry["exe_names"] == ["AzurPromilia.exe"]
    assert entry["download_url"].endswith("/AzurPromilia.zip")
    assert entry["size"] > 0
    assert len(entry["sha256"]) == 64

    archive_path = output / "AzurPromilia.zip"
    with zipfile.ZipFile(archive_path) as archive:
        names = set(archive.namelist())
    assert "d3d11.dll" in names
    assert "Core/Core.ini" in names
    assert "d3dx_user.ini" not in names
    assert all(
        not any(part.casefold() == "mods" for part in name.split("/"))
        for name in names
    )

    version = json.loads(version_file.read_text(encoding="utf-8"))
    assert version["builtin_mod_loaders"] == entries


def test_archives_are_deterministic(tmp_path):
    root = tmp_path / "MOD_loader"
    _write(root / "Endfield" / "d3d11.dll", b"loader")
    _write(root / "Endfield" / "Core" / "main.ini", "core")
    version_file = tmp_path / "version.json"
    version_file.write_text("{}\n", encoding="utf-8")
    output = tmp_path / "mod-loaders"

    first = build_mod_loader_packs(root, output, version_file)
    first_hash = first[0]["sha256"]
    second = build_mod_loader_packs(root, output, version_file)

    assert second[0]["sha256"] == first_hash
