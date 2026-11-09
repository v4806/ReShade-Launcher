import importlib
import json

from pathlib import Path

from reshade_launcher.core.config import ConfigManager
from reshade_launcher.game.injector import build_injection_plan


ROOT = Path(__file__).resolve().parents[1]


def _write(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"test")
    return path


def test_legacy_config_without_injection_method_defaults_to_direct(tmp_path):
    dll = _write(tmp_path / "custom.dll")
    config = {"dll_files": [str(dll)]}

    plan = build_injection_plan(config, str(ROOT))

    assert plan.method == "direct"


def test_saved_configs_include_explicit_direct_method(tmp_path):
    game = _write(tmp_path / "game" / "game.exe")
    manager = ConfigManager(str(tmp_path))

    reshade, _ = manager.save_reshade_config(str(game))
    builtin, _ = manager.save_builtin_config(str(game))
    custom, _ = manager.save_custom_config(str(game), [])

    assert reshade["injection_method"] == "direct"
    assert builtin["injection_method"] == "direct"
    assert custom["injection_method"] == "direct"


def test_xxmi_config_saves_explicit_direct_method(tmp_path):
    game = _write(tmp_path / "game" / "ZenlessZoneZero.exe")
    xxmi_exe = _write(tmp_path / "xxmi" / "Resources" / "Bin" / "XXMI Launcher.exe")
    manager = ConfigManager(str(tmp_path))

    config, _ = manager.save_xxmi_config(str(game), str(xxmi_exe))

    assert config["injection_method"] == "direct"


def test_validate_launch_uses_3dmloader_not_injector(tmp_path):
    facade = importlib.import_module("reshade_launcher.game.launch")
    game = _write(tmp_path / "game" / "game.exe")
    config = {"launch_program": str(game), "target_program": str(game)}

    ok, error = facade.validate_launch(config, str(tmp_path))

    assert ok is False
    assert "3dmloader.dll" in error
    assert "injector.exe" not in error


def test_process_cleanup_has_no_global_injector_taskkill():
    source_text = (ROOT / "reshade_launcher" / "game" / "process_manager.py").read_text(encoding="utf-8")

    assert "taskkill /F /IM injector.exe" not in source_text


def test_game_exit_monitor_uses_target_pid():
    source_text = (ROOT / "reshade_launcher" / "app.py").read_text(encoding="utf-8")

    assert "def _wait_for_game_exit(self, launch_id, target_pid)" in source_text


def test_edit_dialog_source_contains_injection_method_selector():
    source_text = (ROOT / "reshade_launcher" / "ui" / "dialogs.py").read_text(encoding="utf-8")

    assert "injection_method_combo" in source_text
    assert "new_config['injection_method']" in source_text


def test_saved_json_round_trip_preserves_hook_method(tmp_path):
    manager = ConfigManager(str(tmp_path))
    config_path = tmp_path / "launch_config" / "game_custom.json"
    payload = {"injection_method": "hook", "dll_files": []}
    config_path.write_text(json.dumps(payload), encoding="utf-8")

    loaded = manager.load_json(str(config_path))

    assert loaded["injection_method"] == "hook"
