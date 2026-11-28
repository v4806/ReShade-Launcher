#!/usr/bin/env python3
"""Build full and dependency-only ReShade shader packs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import posixpath
import re
import sys
import uuid
import zipfile
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path


SCHEMA_VERSION = 1
MANIFEST_NAME = "pack.json"

_INCLUDE_RE = re.compile(
    r'^\s*#\s*include\s*(?:"([^"]+)"|<([^>]+)>)',
    re.IGNORECASE,
)
_TEXTURE_DECL_RE = re.compile(
    r"\btexture(?:1D|2D|3D|Cube)?\s+[A-Za-z_]\w*\s*<(?P<annotations>.*?)>",
    re.IGNORECASE | re.DOTALL,
)
_TEXTURE_SOURCE_RE = re.compile(
    r'\bsource\s*=\s*"((?:\\.|[^"])*)"',
    re.IGNORECASE,
)
_SEARCH_PATH_RE = re.compile(
    r"^\s*(EffectSearchPaths|TextureSearchPaths)\s*=\s*(.*?)\s*$",
    re.IGNORECASE,
)


class ShaderPackError(ValueError):
    """Raised when a shader pack cannot be built safely."""


@dataclass(frozen=True)
class _FileRef:
    path: Path
    kind: str
    root: Path
    relative_path: str

    @property
    def archive_path(self) -> str:
        folder = "Shaders" if self.kind == "shader" else "Textures"
        return _safe_archive_path(f"{folder}/{self.relative_path}")


@dataclass(frozen=True)
class SourceLayout:
    source: Path
    preset_dir: Path
    shader_roots: tuple[Path, ...]
    texture_roots: tuple[Path, ...]
    config_files: tuple[Path, ...]


@dataclass(frozen=True)
class PackResult:
    kind: str
    zip_path: Path
    manifest: dict[str, object]
    file_count: int
    zip_size: int


def _read_text(path: Path) -> str:
    for encoding in ("utf-8-sig", "gb18030", "latin-1"):
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
    raise ShaderPackError(f"Unable to decode {path}")


def _strip_comments(text: str) -> str:
    """Replace C/C++ comments with spaces while preserving strings and newlines."""
    result: list[str] = []
    index = 0
    state = "code"
    quote = ""

    while index < len(text):
        char = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""

        if state == "code":
            if char == "/" and following == "/":
                result.extend((" ", " "))
                index += 2
                state = "line_comment"
                continue
            if char == "/" and following == "*":
                result.extend((" ", " "))
                index += 2
                state = "block_comment"
                continue
            if char in ('"', "'"):
                quote = char
                state = "string"
            result.append(char)
        elif state == "line_comment":
            if char == "\n":
                result.append(char)
                state = "code"
            else:
                result.append(" ")
        elif state == "block_comment":
            if char == "*" and following == "/":
                result.extend((" ", " "))
                index += 2
                state = "code"
                continue
            result.append("\n" if char == "\n" else " ")
        else:
            result.append(char)
            if char == "\\" and following:
                result.append(following)
                index += 2
                continue
            if char == quote:
                state = "code"
        index += 1

    return "".join(result)


def _normalize_relative_path(value: str, *, context: str) -> str:
    value = value.strip().replace("\\", "/")
    if not value:
        raise ShaderPackError(f"Empty path in {context}")
    if value.startswith("/") or re.match(r"^[A-Za-z]:", value):
        raise ShaderPackError(f"Absolute path is not allowed in {context}: {value}")
    normalized = posixpath.normpath(value)
    if normalized in ("", "."):
        raise ShaderPackError(f"Invalid path in {context}: {value}")
    return normalized


def _safe_archive_path(value: str) -> str:
    raw_value = value.strip().replace("\\", "/")
    if ".." in raw_value.split("/"):
        raise ShaderPackError(f"Parent traversal is not allowed in archive path: {value}")
    normalized = _normalize_relative_path(value, context="archive")
    if normalized == ".." or normalized.startswith("../"):
        raise ShaderPackError(f"Archive path escapes its root: {value}")
    return normalized


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return True


def _is_excluded(path: Path) -> bool:
    return path.name.casefold() == "full.zip"


def _iter_files(root: Path) -> Iterable[Path]:
    if not root.is_dir():
        return
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix().casefold()):
        if not path.is_file() or _is_excluded(path):
            continue
        if not _is_within(path, root):
            raise ShaderPackError(f"File escapes search root: {path}")
        yield path


def _split_search_paths(value: str) -> list[str]:
    paths: list[str] = []
    current: list[str] = []
    quote = ""
    for char in value:
        if char in ('"', "'"):
            if quote == char:
                quote = ""
            elif not quote:
                quote = char
            continue
        if not quote and char in ";,":
            candidate = "".join(current).strip()
            if candidate:
                paths.append(candidate)
            current.clear()
            continue
        current.append(char)
    candidate = "".join(current).strip()
    if candidate:
        paths.append(candidate)
    return paths


def _configured_search_paths(
    config_files: Iterable[Path],
) -> tuple[list[Path], list[Path]]:
    effect_paths: list[Path] = []
    texture_paths: list[Path] = []
    for config_path in config_files:
        try:
            content = _read_text(config_path)
        except OSError:
            continue
        for line in content.splitlines():
            if line.lstrip().startswith(("#", ";")):
                continue
            match = _SEARCH_PATH_RE.match(line)
            if not match:
                continue
            target = effect_paths if match.group(1).casefold() == "effectsearchpaths" else texture_paths
            for raw_path in _split_search_paths(match.group(2)):
                expanded = os.path.expandvars(raw_path)
                candidate = Path(expanded)
                if not candidate.is_absolute():
                    candidate = config_path.parent / candidate
                target.append(candidate.resolve())
    return effect_paths, texture_paths


def discover_source_layout(source: str | Path) -> SourceLayout:
    source_path = Path(source).expanduser().resolve()
    preset_dir = source_path / "Presets"
    if not preset_dir.is_dir():
        raise ShaderPackError(f"Presets directory not found: {preset_dir}")

    config_files = tuple(
        sorted(
            (
                path
                for path in source_path.iterdir()
                if path.is_file() and path.suffix.casefold() == ".ini"
            ),
            key=lambda path: path.name.casefold(),
        )
    )
    configured_effects, configured_textures = _configured_search_paths(config_files)

    effect_roots = list(configured_effects)
    texture_roots = list(configured_textures)
    for shader_root in (
        source_path / "reshade_shaders" / "Shaders",
        source_path / "Shaders",
    ):
        if shader_root.is_dir():
            effect_roots.append(shader_root.resolve())
            break
    for texture_root in (
        source_path / "reshade_shaders" / "Textures",
        source_path / "Textures",
    ):
        if texture_root.is_dir():
            texture_roots.append(texture_root.resolve())
            break

    effect_roots = _unique_existing_dirs(effect_roots)
    texture_roots = _unique_existing_dirs(texture_roots)
    if not effect_roots:
        raise ShaderPackError(f"Shader search paths not found below {source_path}")

    return SourceLayout(
        source=source_path,
        preset_dir=preset_dir.resolve(),
        shader_roots=tuple(effect_roots),
        texture_roots=tuple(texture_roots),
        config_files=config_files,
    )


def _unique_existing_dirs(paths: Iterable[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[str] = set()
    for path in paths:
        resolved = path.resolve()
        key = os.path.normcase(str(resolved))
        if key not in seen and resolved.is_dir():
            seen.add(key)
            result.append(resolved)
    return result


def extract_effect_references(preset_dir: str | Path) -> set[str]:
    """Extract effect paths from Techniques and TechniqueSorting preset entries."""
    preset_path = Path(preset_dir)
    references: set[str] = set()
    for path in sorted(preset_path.glob("*.ini"), key=lambda item: item.name.casefold()):
        for line in _read_text(path).splitlines():
            stripped = line.lstrip()
            if stripped.startswith(("#", ";")):
                continue
            key, separator, value = stripped.partition("=")
            if not separator or key.strip().casefold() not in ("techniques", "techniquesorting"):
                continue
            for item in value.split(","):
                item = item.strip()
                if not item:
                    continue
                effect_name = item.rsplit("@", 1)[-1].strip()
                if effect_name.casefold().endswith(".fx"):
                    references.add(effect_name)
    return references


class _ShaderResolver:
    def __init__(self, layout: SourceLayout):
        self.layout = layout
        self.records: dict[Path, _FileRef] = {}
        self.relative_index: dict[tuple[str, str], _FileRef] = {}
        self.name_index: dict[str, list[_FileRef]] = {}
        self._record_keys: set[str] = set()

        for root in layout.shader_roots:
            for path in _iter_files(root):
                resolved = path.resolve()
                relative = path.relative_to(root).as_posix()
                record = _FileRef(resolved, "shader", root, relative)
                self._register(record)

    def _register(self, record: _FileRef) -> None:
        key = os.path.normcase(str(record.path))
        if key in self._record_keys:
            return
        self._record_keys.add(key)
        self.records[record.path] = record
        self.relative_index[(os.path.normcase(str(record.root)), record.relative_path.casefold())] = record
        self.name_index.setdefault(Path(record.relative_path).name.casefold(), []).append(record)

    def resolve_reference(self, reference: str) -> _FileRef:
        try:
            normalized = _normalize_relative_path(reference, context="preset effect")
        except ShaderPackError:
            raise

        exact: list[_FileRef] = []
        for root in self.layout.shader_roots:
            record = self.relative_index.get((os.path.normcase(str(root)), normalized.casefold()))
            if record:
                exact.append(record)
        if exact:
            return exact[0]

        matches = sorted(
            self.name_index.get(Path(normalized).name.casefold(), []),
            key=lambda record: (
                self.layout.shader_roots.index(record.root),
                record.relative_path.casefold(),
            ),
        )
        if matches:
            return matches[0]
        raise ShaderPackError(f"Effect referenced by a preset was not found: {reference}")

    def resolve_include(self, including_file: _FileRef, include: str) -> _FileRef:
        normalized = _normalize_relative_path(include, context=f"include in {including_file.relative_path}")

        relative_candidate = posixpath.normpath(
            posixpath.join(posixpath.dirname(including_file.relative_path), normalized)
        )
        relative_record = self.relative_index.get(
            (os.path.normcase(str(including_file.root)), relative_candidate.casefold())
        )
        if relative_record:
            return relative_record

        for root in self.layout.shader_roots:
            record = self.relative_index.get((os.path.normcase(str(root)), normalized.casefold()))
            if record:
                return record

        matches = [
            record
            for record in self.records.values()
            if record.relative_path.casefold() == normalized.casefold()
            or record.relative_path.casefold().endswith("/" + normalized.casefold())
        ]
        if matches:
            including_parent = [part.casefold() for part in Path(including_file.relative_path).parts[:-1]]
            return min(
                matches,
                key=lambda record: (
                    -_common_suffix_length(
                        including_parent,
                        [part.casefold() for part in Path(record.relative_path).parts[:-1]],
                    ),
                    self.layout.shader_roots.index(record.root),
                    record.relative_path.casefold(),
                ),
            )
        raise ShaderPackError(
            f"Include not found: {include} (from {including_file.relative_path})"
        )

    def collect_dependencies(self, references: Iterable[str]) -> set[_FileRef]:
        selected: set[_FileRef] = set()
        pending = [self.resolve_reference(reference) for reference in references]

        while pending:
            current = pending.pop()
            if current in selected:
                continue
            selected.add(current)
            content = _strip_comments(_read_text(current.path))
            for line in content.splitlines():
                match = _INCLUDE_RE.match(line)
                if not match:
                    continue
                include = match.group(1) or match.group(2)
                pending.append(self.resolve_include(current, include))
        return selected


class _TextureResolver:
    def __init__(self, layout: SourceLayout):
        self.layout = layout
        self.records: list[_FileRef] = []
        self.exact_index: dict[tuple[str, str], _FileRef] = {}
        self.name_index: dict[str, list[_FileRef]] = {}

        for root in layout.texture_roots:
            for path in _iter_files(root):
                resolved = path.resolve()
                relative = path.relative_to(root).as_posix()
                record = _FileRef(resolved, "texture", root, relative)
                self.records.append(record)
                self.exact_index[(os.path.normcase(str(root)), relative.casefold())] = record
                self.name_index.setdefault(Path(relative).name.casefold(), []).append(record)

    def resolve(self, shader: _FileRef, source: str) -> _FileRef:
        source = source.replace("\\", "/")
        normalized = _normalize_relative_path(source, context=f"texture in {shader.relative_path}")

        shader_adjacent = shader.path.parent / Path(normalized)
        if shader_adjacent.is_file() and not _is_excluded(shader_adjacent):
            return _FileRef(
                shader_adjacent.resolve(),
                "shader",
                shader.root,
                shader_adjacent.resolve().relative_to(shader.root).as_posix(),
            )

        shader_parent = posixpath.dirname(shader.relative_path)
        for root in self.layout.texture_roots:
            candidates: list[str] = []
            if shader_parent:
                candidates.append(posixpath.join(shader_parent, normalized))
            candidates.append(normalized)
            for candidate in candidates:
                record = self.exact_index.get((os.path.normcase(str(root)), candidate.casefold()))
                if record:
                    return record

        matches = [
            record
            for record in self.name_index.get(Path(normalized).name.casefold(), [])
            if record.relative_path.casefold().endswith(normalized.casefold())
        ]
        if matches:
            shader_parts = [part.casefold() for part in Path(shader_parent).parts]
            return min(
                matches,
                key=lambda record: (
                    -_common_suffix_length(
                        shader_parts,
                        [part.casefold() for part in Path(record.relative_path).parts[:-1]],
                    ),
                    self.layout.texture_roots.index(record.root),
                    record.relative_path.casefold(),
                ),
            )
        raise ShaderPackError(
            f"Texture not found: {source} (referenced by {shader.relative_path})"
        )


def _common_suffix_length(left: list[str], right: list[str]) -> int:
    count = 0
    for left_part, right_part in zip(reversed(left), reversed(right)):
        if left_part != right_part:
            break
        count += 1
    return count


def _collect_texture_references(
    shader_files: Iterable[_FileRef],
    texture_resolver: _TextureResolver,
) -> set[_FileRef]:
    textures: set[_FileRef] = set()
    for shader in shader_files:
        content = _strip_comments(_read_text(shader.path))
        for declaration in _TEXTURE_DECL_RE.finditer(content):
            for match in _TEXTURE_SOURCE_RE.finditer(declaration.group("annotations")):
                source = match.group(1).replace('\\"', '"')
                textures.add(texture_resolver.resolve(shader, source))
    return textures


def _file_entry(path: Path, archive_path: str) -> dict[str, object]:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "path": _safe_archive_path(archive_path),
        "size": path.stat().st_size,
        "sha256": digest.hexdigest(),
    }


def _build_manifest(kind: str, records: Iterable[_FileRef]) -> dict[str, object]:
    files = sorted(
        (_file_entry(record.path, record.archive_path) for record in records),
        key=lambda item: str(item["path"]).casefold(),
    )
    identity = json.dumps(
        {"kind": kind, "files": files},
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return {
        "schema_version": SCHEMA_VERSION,
        "pack_id": hashlib.sha256(identity).hexdigest(),
        "kind": kind,
        "files": files,
    }


def _write_pack(
    kind: str,
    records: Iterable[_FileRef],
    destination: Path,
) -> PackResult:
    destination = destination.expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    records_by_path = {
        _safe_archive_path(record.archive_path): record
        for record in records
    }
    if not records_by_path:
        raise ShaderPackError(f"Refusing to create an empty {kind} pack")

    manifest = _build_manifest(kind, records_by_path.values())
    manifest_bytes = json.dumps(
        manifest,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ).encode("utf-8")

    temporary = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}.tmp")
    try:
        with zipfile.ZipFile(
            temporary,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
        ) as archive:
            archive.writestr(MANIFEST_NAME, manifest_bytes)
            for archive_path, record in sorted(records_by_path.items()):
                archive.write(record.path, archive_path)
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()

    return PackResult(
        kind=kind,
        zip_path=destination,
        manifest=manifest,
        file_count=len(records_by_path),
        zip_size=destination.stat().st_size,
    )


def build_shader_packs(
    source: str | Path,
    out_dir: str | Path,
    *,
    lite_out: str | Path | None = None,
    full_out: str | Path | None = None,
) -> tuple[PackResult, PackResult]:
    """Build lite and full packs and return (lite, full)."""
    layout = discover_source_layout(source)
    output_root = Path(out_dir).expanduser().resolve()
    lite_path = Path(lite_out).expanduser().resolve() if lite_out else output_root / "lite.zip"
    full_path = Path(full_out).expanduser().resolve() if full_out else output_root / "full.zip"
    if lite_path == full_path:
        raise ShaderPackError("--lite-out and --full-out must be different files")

    references = extract_effect_references(layout.preset_dir)
    if not references:
        raise ShaderPackError("No .fx references found in Techniques or TechniqueSorting")

    shader_resolver = _ShaderResolver(layout)
    texture_resolver = _TextureResolver(layout)
    lite_shaders = shader_resolver.collect_dependencies(references)
    lite_textures = _collect_texture_references(lite_shaders, texture_resolver)

    full_shaders = set(shader_resolver.records.values())
    full_textures = set(texture_resolver.records)

    lite = _write_pack("lite", lite_shaders | lite_textures, lite_path)
    full = _write_pack("full", full_shaders | full_textures, full_path)
    return lite, full


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build lite and full ReShade shader packs.")
    parser.add_argument("--source", required=True, help="ReShade directory containing Presets")
    parser.add_argument(
        "--out-dir",
        default="build/shader-packs",
        help="Default output directory for lite.zip and full.zip",
    )
    parser.add_argument("--lite-out", help="Explicit lite ZIP output path")
    parser.add_argument("--full-out", help="Explicit full ZIP output path")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        lite, full = build_shader_packs(
            args.source,
            args.out_dir,
            lite_out=args.lite_out,
            full_out=args.full_out,
        )
    except (OSError, ShaderPackError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for result in (lite, full):
        print(
            f"{result.kind}: {result.zip_path} "
            f"({result.file_count} files, {result.zip_size / (1024 * 1024):.2f} MiB)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
