from __future__ import annotations

import argparse
import hashlib
import json
import os
import zipfile
from pathlib import Path


DEFAULT_BASE_URL = (
    "https://raw.githubusercontent.com/v4806/ReShade-Launcher/main/mod-loaders/"
)

KNOWN_LOADERS = {
    "AzurPromilia": {
        "display_name": "蓝色星原",
        "exe_names": ["AzurPromilia.exe"],
    },
    "Client-Win64-Shipping": {
        "display_name": "鸣潮",
        "exe_names": ["Client-Win64-Shipping.exe"],
    },
    "Endfield": {
        "display_name": "明日方舟：终末地",
        "exe_names": ["Endfield.exe"],
    },
    "ZenlessZoneZero": {
        "display_name": "绝区零",
        "exe_names": ["ZenlessZoneZero.exe", "ZenlessZoneZeroBeta.exe"],
    },
}


class ModLoaderPackError(RuntimeError):
    pass


def _payload_files(game_root: Path) -> list[Path]:
    files: list[Path] = []
    for path in game_root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(game_root)
        if "Mods" in relative.parts:
            continue
        if path.name.casefold() == "d3dx_user.ini":
            continue
        files.append(path)
    return sorted(files, key=lambda item: item.as_posix().casefold())


def _write_archive(game_root: Path, destination: Path) -> None:
    files = _payload_files(game_root)
    if not files:
        raise ModLoaderPackError(f"No files found for {game_root.name}")
    if not (game_root / "d3d11.dll").is_file():
        raise ModLoaderPackError(f"d3d11.dll is missing from {game_root}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(
        temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for source in files:
            relative = source.relative_to(game_root).as_posix()
            info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, source.read_bytes(), compresslevel=9)
    os.replace(temporary, destination)


def build_mod_loader_packs(
    mod_loader_root: Path,
    output_dir: Path,
    version_file: Path,
    base_url: str = DEFAULT_BASE_URL,
) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for folder_name, metadata in KNOWN_LOADERS.items():
        game_root = mod_loader_root / folder_name
        if not game_root.is_dir():
            continue
        archive = output_dir / f"{folder_name}.zip"
        _write_archive(game_root, archive)
        content = archive.read_bytes()
        entries.append(
            {
                "folder_name": folder_name,
                "display_name": metadata["display_name"],
                "exe_names": list(metadata["exe_names"]),
                "download_url": base_url.rstrip("/") + "/" + archive.name,
                "size": len(content),
                "sha256": hashlib.sha256(content).hexdigest(),
            }
        )

    version = json.loads(version_file.read_text(encoding="utf-8"))
    version["builtin_mod_loaders"] = entries
    version_file.write_text(
        json.dumps(version, ensure_ascii=False, indent=4) + "\n",
        encoding="utf-8",
    )
    return entries


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build downloadable built-in Mod loader archives."
    )
    parser.add_argument("--mod-loader-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--version-file", type=Path, required=True)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    args = parser.parse_args(argv)

    entries = build_mod_loader_packs(
        args.mod_loader_root,
        args.output_dir,
        args.version_file,
        args.base_url,
    )
    for entry in entries:
        print(
            f"{entry['folder_name']}: {entry['size']} bytes "
            f"sha256={entry['sha256']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
