import json
import zipfile
from pathlib import Path

import pytest

from tools.build_shader_packs import (
    ShaderPackError,
    _safe_archive_path,
    _strip_comments,
    build_shader_packs,
    extract_effect_references,
)


def _write(path: Path, content: str | bytes = b"data") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content, encoding="utf-8")


def _source_fixture(root: Path) -> Path:
    source = root / "ReShade"
    _write(
        source / "ReShade.ini",
        "[GENERAL]\n"
        "EffectSearchPaths=reshade_shaders/Shaders;custom_effects\n"
        "TextureSearchPaths=reshade_shaders/Textures;custom_textures\n",
    )
    _write(
        source / "Presets" / "one.ini",
        "Techniques=Main@A/Main.fx,Ignored@A/Ignored.fx\n"
        "TechniqueSorting=Sorted@B/Sorted.fx\n",
    )
    _write(
        source / "Presets" / "two.ini",
        "; Techniques=No@Nope.fx\n"
        "Techniques=Main2@A/Main.fx,MissingStyle@A/Main.fx\n",
    )

    _write(
        source / "reshade_shaders" / "Shaders" / "A" / "Main.fx",
        '// #include "ignored.fxh"\n'
        '/* #include "also-ignored.fxh" */\n'
        '#include ".\\common.fxh"\n'
        '#include <search_only.fxh>\n'
        'texture Local < source = "local.png"; > { Width = 1; Height = 1; };\n'
        'texture Shared < source = "shared/dup.png"; > { Width = 1; Height = 1; };\n',
    )
    _write(source / "reshade_shaders" / "Shaders" / "A" / "common.fxh", "// shared name A\n")
    _write(source / "reshade_shaders" / "Shaders" / "A" / "Ignored.fx", "// referenced by Techniques\n")
    _write(source / "reshade_shaders" / "Shaders" / "A" / "ignored.fxh", "ignored\n")
    _write(source / "reshade_shaders" / "Shaders" / "A" / "also-ignored.fxh", "ignored\n")
    _write(
        source / "reshade_shaders" / "Shaders" / "B" / "Sorted.fx",
        '#include "common.fxh"\n'
        '#include "../A/common.fxh"\n'
        '#include "nested_only.fxh"\n'
        'texture LocalB < source = "local.png"; > { Width = 1; Height = 1; };\n',
    )
    _write(source / "reshade_shaders" / "Shaders" / "B" / "common.fxh", "// shared name B\n")
    _write(source / "reshade_shaders" / "Shaders" / "Nested" / "nested_only.fxh", "nested\n")
    _write(source / "reshade_shaders" / "Shaders" / "Unused.fx", '#include "unused.fxh"\n')
    _write(source / "reshade_shaders" / "Shaders" / "unused.fxh", "unused\n")
    _write(source / "reshade_shaders" / "Shaders" / "full.zip", b"do not pack")
    _write(source / "custom_effects" / "search_only.fxh", "// custom search path\n")

    _write(source / "reshade_shaders" / "Textures" / "A" / "local.png", b"A-local")
    _write(source / "reshade_shaders" / "Textures" / "B" / "local.png", b"B-local")
    _write(source / "reshade_shaders" / "Textures" / "local.png", b"root-local")
    _write(source / "reshade_shaders" / "Textures" / "Unused.png", b"unused")
    _write(source / "reshade_shaders" / "Textures" / "shared" / "dup.png", b"shared")
    _write(source / "reshade_shaders" / "full.zip", b"full archive")
    _write(source / "custom_textures" / "unused.png", b"custom unused")
    return source


def test_extract_effect_references_uses_both_preset_keys(tmp_path):
    source = _source_fixture(tmp_path)

    references = extract_effect_references(source / "Presets")

    assert references == {"A/Main.fx", "A/Ignored.fx", "B/Sorted.fx"}


def test_comment_stripping_preserves_only_active_include_syntax():
    shader = """
    // #include "line-comment.fxh"
    /* #include "block-comment.fxh" */
    #include "active.fxh" // trailing comment
    const char *text = "/* not a comment */";
    """

    stripped = _strip_comments(shader)

    assert "line-comment.fxh" not in stripped
    assert "block-comment.fxh" not in stripped
    assert '#include "active.fxh"' in stripped
    assert "/* not a comment */" in stripped


def test_build_packs_resolves_relative_search_and_duplicate_names(tmp_path):
    source = _source_fixture(tmp_path)
    out = tmp_path / "out"

    lite, full = build_shader_packs(source, out)

    assert lite.manifest["kind"] == "lite"
    assert full.manifest["kind"] == "full"
    assert lite.manifest["schema_version"] == 1
    assert len(lite.manifest["pack_id"]) == 64
    assert lite.zip_size > 0
    assert full.zip_size > 0

    with zipfile.ZipFile(lite.zip_path) as archive:
        names = set(archive.namelist())
        embedded = json.loads(archive.read("pack.json"))
        assert embedded == lite.manifest

    assert "Shaders/A/Main.fx" in names
    assert "Shaders/A/Ignored.fx" in names
    assert "Shaders/A/common.fxh" in names
    assert "Shaders/B/common.fxh" in names
    assert "Shaders/B/Sorted.fx" in names
    assert "Shaders/Nested/nested_only.fxh" in names
    assert "Shaders/search_only.fxh" in names
    assert "Shaders/A/ignored.fxh" not in names
    assert "Shaders/A/also-ignored.fxh" not in names
    assert "Shaders/Unused.fx" not in names
    assert "Textures/A/local.png" in names
    assert "Textures/B/local.png" in names
    assert "Textures/local.png" not in names
    assert "Textures/shared/dup.png" in names
    assert "Textures/Unused.png" not in names
    assert "full.zip" not in names

    with zipfile.ZipFile(full.zip_path) as archive:
        full_names = set(archive.namelist())
        embedded = json.loads(archive.read("pack.json"))
        assert embedded["kind"] == "full"

    assert "Shaders/Unused.fx" in full_names
    assert "Textures/Unused.png" in full_names
    assert all(not name.endswith("full.zip") for name in full_names)
    assert [entry["path"] for entry in lite.manifest["files"]] == sorted(
        (entry["path"] for entry in lite.manifest["files"]),
        key=str.casefold,
    )
    for entry in lite.manifest["files"]:
        assert entry["size"] > 0
        assert len(entry["sha256"]) == 64


def test_build_packs_does_not_modify_source_tree(tmp_path):
    source = _source_fixture(tmp_path)
    before = {
        path.relative_to(source).as_posix(): path.read_bytes()
        for path in source.rglob("*")
        if path.is_file()
    }

    build_shader_packs(source, tmp_path / "out")

    after = {
        path.relative_to(source).as_posix(): path.read_bytes()
        for path in source.rglob("*")
        if path.is_file()
    }
    assert after == before


def test_cli_honors_explicit_output_paths(tmp_path, capsys):
    from tools.build_shader_packs import main

    source = _source_fixture(tmp_path)
    lite_out = tmp_path / "artifacts" / "custom-lite.zip"
    full_out = tmp_path / "artifacts" / "custom-full.zip"

    result = main(
        [
            "--source",
            str(source),
            "--out-dir",
            str(tmp_path / "ignored-default"),
            "--lite-out",
            str(lite_out),
            "--full-out",
            str(full_out),
        ]
    )

    assert result == 0
    assert lite_out.is_file()
    assert full_out.is_file()
    assert not (tmp_path / "ignored-default").exists()
    output = capsys.readouterr().out
    assert "lite:" in output
    assert "full:" in output


def test_rejects_unsafe_archive_paths():
    with pytest.raises(ShaderPackError):
        _safe_archive_path("../escape.fx")
    with pytest.raises(ShaderPackError):
        _safe_archive_path("/absolute.fx")
    with pytest.raises(ShaderPackError):
        _safe_archive_path("C:/absolute.fx")
    with pytest.raises(ShaderPackError):
        _safe_archive_path("folder/../file.fx")


def test_rejects_absolute_texture_source(tmp_path):
    source = _source_fixture(tmp_path)
    _write(
        source / "reshade_shaders" / "Shaders" / "A" / "Main.fx",
        'texture Bad < source = "C:/secret.png"; > { Width = 1; Height = 1; };\n',
    )

    with pytest.raises(ShaderPackError, match="Absolute path"):
        build_shader_packs(source, tmp_path / "out")
