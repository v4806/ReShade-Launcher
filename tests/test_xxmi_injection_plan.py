from pathlib import Path

import pytest

from reshade_launcher.game.injector import build_injection_plan, validate_injection_plan


def _write(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"test")
    return path


def test_direct_plan_preserves_reshade_d3d11_and_custom_order(tmp_path):
    script_dir = tmp_path / "app"
    reshade = _write(script_dir / "ReShade" / "ReShade64.dll")
    d3d11 = _write(tmp_path / "importer" / "d3d11.dll")
    custom = _write(tmp_path / "custom" / "custom.dll")
    config = {
        "reshade_dll": "ReShade64.dll",
        "d3d11_path": str(d3d11),
        "dll_files": [str(custom)],
    }

    plan = build_injection_plan(config, str(script_dir))

    assert plan.method == "direct"
    assert plan.hook_dll is None
    assert [path.name for path in plan.direct_dlls] == [
        "ReShade64.dll",
        "d3d11.dll",
        "custom.dll",
    ]
    assert plan.direct_dlls[0] == reshade.resolve()


def test_missing_dll_is_an_error_not_filtered(tmp_path):
    config = {"dll_files": [str(tmp_path / "missing.dll")]}

    ok, error = validate_injection_plan(config, str(tmp_path))

    assert ok is False
    assert "missing.dll" in error


def test_hook_plan_excludes_hook_dll_from_direct_list(tmp_path):
    script_dir = tmp_path / "app"
    reshade = _write(script_dir / "ReShade" / "ReShade64.dll")
    d3d11 = _write(tmp_path / "importer" / "d3d11.dll")
    custom = _write(tmp_path / "custom" / "custom.dll")
    config = {
        "injection_method": "hook",
        "reshade_dll": "ReShade64.dll",
        "dll_files": [str(d3d11), str(custom)],
        "launch_program": str(tmp_path / "game" / "game.exe"),
        "target_program": str(tmp_path / "game" / "game.exe"),
    }
    Path(config["launch_program"]).parent.mkdir(parents=True)
    Path(config["launch_program"]).write_bytes(b"exe")

    plan = build_injection_plan(config, str(script_dir))

    assert plan.method == "hook"
    assert plan.hook_dll == d3d11.resolve()
    assert plan.direct_dlls == (reshade.resolve(), custom.resolve())


def test_launcher_child_target_rejects_hook(tmp_path):
    launch = _write(tmp_path / "launcher" / "launcher.exe")
    target = _write(tmp_path / "game" / "game.exe")
    d3d11 = _write(tmp_path / "importer" / "d3d11.dll")
    config = {
        "injection_method": "hook",
        "launch_program": str(launch),
        "target_program": str(target),
        "dll_files": [str(d3d11)],
    }

    ok, error = validate_injection_plan(config, str(tmp_path))

    assert ok is False
    assert "same executable" in error


def test_unknown_injection_method_is_rejected(tmp_path):
    config = {"injection_method": "magic"}

    with pytest.raises(ValueError, match="injection_method"):
        build_injection_plan(config, str(tmp_path))


def test_existing_rehade_builtin_custom_and_xxmi_modes_build_plans(tmp_path):
    script_dir = tmp_path / "app"
    reshade = _write(script_dir / "ReShade" / "ReShade64.dll")
    builtin_dll = _write(tmp_path / "builtin" / "d3d11.dll")
    custom_dll = _write(tmp_path / "custom" / "custom.dll")
    xxmi_dll = _write(tmp_path / "XXMI" / "ZZMI" / "d3d11.dll")

    reshade_plan = build_injection_plan({"reshade_dll": "ReShade64.dll"}, str(script_dir))
    builtin_plan = build_injection_plan({"d3d11_path": str(builtin_dll)}, str(script_dir))
    custom_plan = build_injection_plan({"dll_files": [str(custom_dll)]}, str(script_dir))
    xxmi_plan = build_injection_plan({"dll_files": [str(xxmi_dll)]}, str(script_dir))

    assert reshade_plan.direct_dlls == (reshade.resolve(),)
    assert builtin_plan.direct_dlls == (builtin_dll.resolve(),)
    assert custom_plan.direct_dlls == (custom_dll.resolve(),)
    assert xxmi_plan.direct_dlls == (xxmi_dll.resolve(),)
