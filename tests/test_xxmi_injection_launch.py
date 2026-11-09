import os
from pathlib import Path

import pytest

import reshade_launcher.game.injector as xxmi_injection
from reshade_launcher.game.injector import launch_game


ROOT = Path(__file__).resolve().parents[1]


def _write(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"test")
    return path


class FakeSuspendedProcess:
    def __init__(self, pid=100):
        self.pid = pid
        self.events = []
        self.closed = False

    def resume(self):
        self.events.append("resume")

    def terminate(self):
        self.events.append("terminate")

    def close(self):
        self.closed = True


class FakeInjector:
    def __init__(self, events, fail_on=None):
        self.events = events
        self.fail_on = fail_on
        self.injected = []
        self.verified = []
        self.unhook_count = 0
        self.hook = None

    def inject(self, pid, dll_path, timeout=15):
        path = Path(dll_path)
        self.events.append(f"inject:{path.name}")
        if self.fail_on == path.name:
            raise RuntimeError(f"failed to inject {path.name}")
        self.injected.append((pid, path.name))

    def hook_by_pid(self, dll_path, target_pid):
        path = Path(dll_path)
        self.events.append(f"hook:{path.name}")
        self.hook = (target_pid, path)

    def verify(self, pid, dll_path):
        path = Path(dll_path)
        self.events.append(f"verify:{path.name}")
        self.verified.append((pid, path.name))

    def unhook(self):
        self.events.append("unhook")
        self.unhook_count += 1


def _base_config(tmp_path, method="direct"):
    game = _write(tmp_path / "game" / "game.exe")
    d3d11 = _write(tmp_path / "importer" / "d3d11.dll")
    custom = _write(tmp_path / "custom" / "custom.dll")
    return {
        "launch_program": str(game),
        "target_program": str(game),
        "game_exe_name": "game.exe",
        "launch_args": "",
        "injection_method": method,
        "dll_files": [str(d3d11), str(custom)],
    }


def test_direct_same_exe_resumes_then_injects(tmp_path, monkeypatch):
    config = _base_config(tmp_path)
    fake_process = FakeSuspendedProcess()
    fake_injector = FakeInjector(fake_process.events)
    monkeypatch.setattr(
        xxmi_injection,
        "_create_suspended_process",
        lambda *args, **kwargs: fake_process,
    )

    result = launch_game(
        config,
        str(ROOT),
        injector_factory=lambda path: fake_injector,
    )

    assert result.root_pid == fake_process.pid
    assert result.target_pid == fake_process.pid
    assert fake_process.events == [
        "resume",
        "inject:d3d11.dll",
        "inject:custom.dll",
        "verify:d3d11.dll",
        "verify:custom.dll",
    ]


def test_hook_launch_cleans_up_after_injection_error(tmp_path, monkeypatch):
    config = _base_config(tmp_path, method="hook")
    fake_process = FakeSuspendedProcess()
    fake_injector = FakeInjector(fake_process.events, fail_on="custom.dll")
    monkeypatch.setattr(
        xxmi_injection,
        "_create_suspended_process",
        lambda *args, **kwargs: fake_process,
    )
    monkeypatch.setattr(xxmi_injection, "_wait_for_module", lambda *args, **kwargs: True)

    with pytest.raises(RuntimeError, match="custom.dll"):
        launch_game(
            config,
            str(ROOT),
            injector_factory=lambda path: fake_injector,
        )

    assert fake_injector.unhook_count == 1
    assert fake_process.events[-1] == "unhook"


def test_launch_terminates_suspended_process_if_injector_load_fails(tmp_path, monkeypatch):
    config = _base_config(tmp_path)
    fake_process = FakeSuspendedProcess()
    monkeypatch.setattr(
        xxmi_injection,
        "_create_suspended_process",
        lambda *args, **kwargs: fake_process,
    )

    with pytest.raises(RuntimeError, match="loader failure"):
        launch_game(
            config,
            str(ROOT),
            injector_factory=lambda path: (_ for _ in ()).throw(RuntimeError("loader failure")),
        )

    assert fake_process.events == ["terminate"]


def test_launcher_child_direct_injects_after_child_pid(tmp_path, monkeypatch):
    launch = _write(tmp_path / "launcher" / "launcher.exe")
    target = _write(tmp_path / "game" / "game.exe")
    dll = _write(tmp_path / "importer" / "d3d11.dll")
    config = {
        "launch_program": str(launch),
        "target_program": str(target),
        "game_exe_name": "game.exe",
        "injection_method": "direct",
        "dll_files": [str(dll)],
    }
    fake_process = FakeSuspendedProcess(pid=200)
    fake_injector = FakeInjector(fake_process.events)
    monkeypatch.setattr(
        xxmi_injection,
        "_create_suspended_process",
        lambda *args, **kwargs: fake_process,
    )
    monkeypatch.setattr(
        xxmi_injection,
        "_find_child_target_pid",
        lambda *args, **kwargs: 201,
    )

    result = launch_game(
        config,
        str(ROOT),
        injector_factory=lambda path: fake_injector,
    )

    assert result.root_pid == 200
    assert result.target_pid == 201
    assert "hook:d3d11.dll" not in fake_process.events
    assert fake_process.events[0] == "resume"
    assert fake_injector.injected == [(201, "d3d11.dll")]


def test_find_child_target_pid_rejects_unrelated_same_name_process():
    root_pid = 300
    target_path = r"D:\Games\Game\Game.exe"
    processes = {
        300: {"pid": 300, "ppid": 1, "name": "launcher.exe", "exe": r"D:\Games\Launcher.exe"},
        301: {"pid": 301, "ppid": 300, "name": "Game.exe", "exe": target_path},
        302: {"pid": 302, "ppid": 1, "name": "Game.exe", "exe": target_path},
    }

    selected = xxmi_injection._find_child_target_pid_from_snapshot(
        root_pid,
        target_path,
        "Game.exe",
        baseline_pids={302},
        process_snapshot=lambda: processes,
        timeout=0.01,
        interval=0.001,
    )

    assert selected == 301


def test_find_child_target_pid_accepts_new_exact_target_outside_launcher_tree():
    root_pid = 400
    target_path = r"E:\zzz_beta\ZenlessZoneZeroBeta.exe"
    processes = {
        400: {"pid": 400, "ppid": 1, "name": "kafka-bootstrap.exe", "exe": r"E:\zzz_beta\kafka-bootstrap.exe"},
        401: {"pid": 401, "ppid": 999, "name": "ZenlessZoneZeroBeta.exe", "exe": target_path},
    }

    selected = xxmi_injection._find_child_target_pid_from_snapshot(
        root_pid,
        target_path,
        "ZenlessZoneZero.exe",
        baseline_pids=set(),
        process_snapshot=lambda: processes,
        timeout=0.01,
        interval=0.001,
    )

    assert selected == 401


def test_launch_temporarily_uses_current_target_name_in_d3dx_ini(tmp_path, monkeypatch):
    game = _write(tmp_path / "game" / "ZenlessZoneZeroBeta.exe")
    importer = tmp_path / "importer"
    importer.mkdir()
    d3d11 = _write(importer / "d3d11.dll")
    d3dx = importer / "d3dx.ini"
    original = "[Loader]\r\ntarget = ZenlessZoneZero.exe\r\nloader = XXMI Launcher.exe\r\n"
    d3dx.write_text(original, encoding="utf-8", newline="")
    config = {
        "launch_program": str(game),
        "target_program": str(game),
        "game_exe_name": game.name,
        "injection_method": "direct",
        "dll_files": [str(d3d11)],
    }
    fake_process = FakeSuspendedProcess()
    seen = {}

    class InspectingInjector(FakeInjector):
        def inject(self, pid, dll_path, timeout=15):
            seen["target_line"] = next(
                line for line in d3dx.read_text(encoding="utf-8").splitlines()
                if line.lower().startswith("target")
            )
            super().inject(pid, dll_path, timeout)

    fake_injector = InspectingInjector(fake_process.events)
    monkeypatch.setattr(
        xxmi_injection,
        "_create_suspended_process",
        lambda *args, **kwargs: fake_process,
    )

    launch_game(
        config,
        str(ROOT),
        injector_factory=lambda path: fake_injector,
    )

    assert seen["target_line"] == "target = ZenlessZoneZeroBeta.exe"
    assert d3dx.read_text(encoding="utf-8", newline="") == original


def test_process_matches_target_by_target_name_when_exe_path_unavailable():
    target = r"E:\zzz_beta\ZenlessZoneZeroBeta.exe"
    process = {"pid": 500, "ppid": 1, "name": "ZenlessZoneZeroBeta.exe", "exe": ""}

    # 旧配置里 game_exe_name 可能是 ZenlessZoneZero.exe（与目标程序不同），
    # 但目标程序名必须能匹配，否则受保护进程（读不到 exe 路径）永远找不到。
    assert xxmi_injection._process_matches_target(process, target, "ZenlessZoneZero.exe") is True


def test_inject_and_verify_keeps_going_after_one_dll_fails(tmp_path):
    class Recorder:
        events = []
        def inject(self, pid, dll_path, timeout=15):
            self.events.append(f"inject:{Path(dll_path).name}")
            if Path(dll_path).name == "ReShade64.dll":
                raise RuntimeError("reshade injection failed")
        def verify(self, pid, dll_path):
            self.events.append(f"verify:{Path(dll_path).name}")

    dlls = (tmp_path / "ReShade64.dll", tmp_path / "d3d11.dll")
    recorder = Recorder()

    with pytest.raises(xxmi_injection.InjectionError, match="ReShade64.dll"):
        xxmi_injection._inject_and_verify(recorder, 1, dlls)

    assert "inject:d3d11.dll" in recorder.events
    assert "verify:d3d11.dll" in recorder.events


def test_verify_accepts_unqueryable_module_list(monkeypatch):
    injector = xxmi_injection.XxmiInjector.__new__(xxmi_injection.XxmiInjector)
    monkeypatch.setattr(xxmi_injection, "_wait_for_module", lambda *args, **kwargs: None)

    # 受反作弊保护的进程无法枚举模块，Inject 已成功返回，不能判定失败。
    injector.verify(1, "d3d11.dll")

