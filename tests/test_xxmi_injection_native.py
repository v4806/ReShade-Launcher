import ctypes
import ctypes.wintypes
import os
import subprocess
import time

from pathlib import Path

import pytest

from reshade_launcher.game.injector import launch_game


ROOT = Path(__file__).resolve().parents[1]
INJECTOR_DLL = ROOT / "3dmloader.dll"
NATIVE_BIN = ROOT / "tests" / "native" / "bin" / "x64"
TARGET_EXE = NATIVE_BIN / "target.exe"
PROBE_DLL = NATIVE_BIN / "probe.dll"


def _wait_for_file(path: Path, timeout: float = 10.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.is_file():
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {path}")


def _start_target(tmp_path: Path, name: str, *, wait_for_go: bool = False, window: bool = True):
    pid_file = tmp_path / f"{name}.pid"
    go_file = tmp_path / f"{name}.go"
    marker_file = tmp_path / f"{name}.marker"
    args = [
        str(TARGET_EXE),
        "--pid-file",
        str(pid_file),
        "--lifetime-ms",
        "8000",
    ]
    if wait_for_go:
        args.extend(["--go-file", str(go_file)])
    if not window:
        args.append("--no-window")

    env = os.environ.copy()
    env["XXMI_PROBE_MARKER"] = str(marker_file)
    process = subprocess.Popen(args, env=env)
    _wait_for_file(pid_file)
    pid = int(pid_file.read_text())
    return process, pid, go_file, marker_file


@pytest.fixture(scope="module", autouse=True)
def build_native_fixture():
    subprocess.run(
        [
            "powershell",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "tests" / "native" / "build_test_binaries.ps1"),
        ],
        cwd=ROOT,
        check=True,
    )


@pytest.fixture()
def loader():
    assert INJECTOR_DLL.is_file(), "3dmloader.dll is missing"
    return ctypes.WinDLL(str(INJECTOR_DLL))


def test_direct_injection_loads_probe_dll(tmp_path, loader):
    process, pid, _go_file, marker_file = _start_target(tmp_path, "direct", window=False)
    try:
        loader.Inject.argtypes = [ctypes.wintypes.DWORD, ctypes.wintypes.LPCWSTR, ctypes.c_int]
        loader.Inject.restype = ctypes.c_int
        result = loader.Inject(pid, str(PROBE_DLL.resolve()), 10)

        assert result == 0
        _wait_for_file(marker_file)
        assert marker_file.read_text().strip() == str(pid)
    finally:
        process.terminate()
        process.wait(timeout=5)


def test_hook_injection_loads_d3d11_candidate_in_new_pid(tmp_path, loader):
    process, pid, go_file, marker_file = _start_target(tmp_path, "hook", wait_for_go=True)
    hook = ctypes.wintypes.HHOOK()
    mutex = ctypes.wintypes.HANDLE()
    try:
        loader.HookLibraryByPid.argtypes = [
            ctypes.wintypes.LPCWSTR,
            ctypes.wintypes.DWORD,
            ctypes.POINTER(ctypes.wintypes.HHOOK),
            ctypes.POINTER(ctypes.wintypes.HANDLE),
        ]
        loader.HookLibraryByPid.restype = ctypes.c_int
        loader.UnhookLibraryByPid.argtypes = [
            ctypes.POINTER(ctypes.wintypes.HHOOK),
            ctypes.POINTER(ctypes.wintypes.HANDLE),
        ]
        loader.UnhookLibraryByPid.restype = ctypes.c_int

        assert loader.HookLibraryByPid(str(PROBE_DLL.resolve()), pid, ctypes.byref(hook), ctypes.byref(mutex)) == 0
        go_file.write_text("go", encoding="ascii")

        _wait_for_file(marker_file)
        assert marker_file.read_text().strip() == str(pid)
    finally:
        loader.UnhookLibraryByPid(ctypes.byref(hook), ctypes.byref(mutex))
        process.terminate()
        process.wait(timeout=5)


def test_preexisting_same_name_process_is_not_injected(tmp_path, loader):
    old_process, old_pid, _old_go, old_marker = _start_target(
        tmp_path, "old", window=False
    )
    new_process, new_pid, go_file, new_marker = _start_target(
        tmp_path, "new", wait_for_go=True
    )
    hook = ctypes.wintypes.HHOOK()
    mutex = ctypes.wintypes.HANDLE()
    try:
        loader.HookLibraryByPid.argtypes = [
            ctypes.wintypes.LPCWSTR,
            ctypes.wintypes.DWORD,
            ctypes.POINTER(ctypes.wintypes.HHOOK),
            ctypes.POINTER(ctypes.wintypes.HANDLE),
        ]
        loader.HookLibraryByPid.restype = ctypes.c_int
        loader.UnhookLibraryByPid.argtypes = [
            ctypes.POINTER(ctypes.wintypes.HHOOK),
            ctypes.POINTER(ctypes.wintypes.HANDLE),
        ]
        loader.UnhookLibraryByPid.restype = ctypes.c_int

        assert loader.HookLibraryByPid(str(PROBE_DLL.resolve()), new_pid, ctypes.byref(hook), ctypes.byref(mutex)) == 0
        go_file.write_text("go", encoding="ascii")

        _wait_for_file(new_marker)
        assert new_marker.read_text().strip() == str(new_pid)
        assert not old_marker.exists()
        assert new_pid != old_pid
    finally:
        loader.UnhookLibraryByPid(ctypes.byref(hook), ctypes.byref(mutex))
        new_process.terminate()
        old_process.terminate()
        new_process.wait(timeout=5)
        old_process.wait(timeout=5)


def test_launch_game_direct_runs_through_adapted_adapter(tmp_path, monkeypatch):
    pid_file = tmp_path / "adapter-direct.pid"
    marker_file = tmp_path / "adapter-direct.marker"
    monkeypatch.setenv("XXMI_PROBE_MARKER", str(marker_file))
    config = {
        "launch_program": str(TARGET_EXE),
        "target_program": str(TARGET_EXE),
        "game_exe_name": TARGET_EXE.name,
        "launch_args": f"--no-window --pid-file {pid_file} --lifetime-ms 5000",
        "injection_method": "direct",
        "dll_files": [str(PROBE_DLL)],
    }

    result = launch_game(config, str(ROOT))
    try:
        _wait_for_file(marker_file)
        assert result.target_pid == int(pid_file.read_text())
        assert marker_file.read_text().strip() == str(result.target_pid)
    finally:
        process = subprocess.Popen(["taskkill", "/F", "/PID", str(result.target_pid)], stdout=subprocess.DEVNULL)
        process.wait(timeout=5)


def test_launch_game_hook_runs_through_adapted_adapter(tmp_path, monkeypatch):
    pid_file = tmp_path / "adapter-hook.pid"
    go_file = tmp_path / "adapter-hook.go"
    marker_file = tmp_path / "adapter-hook.marker"
    go_file.write_text("go", encoding="ascii")
    monkeypatch.setenv("XXMI_PROBE_MARKER", str(marker_file))
    config = {
        "launch_program": str(TARGET_EXE),
        "target_program": str(TARGET_EXE),
        "game_exe_name": TARGET_EXE.name,
        "launch_args": (
            f"--pid-file {pid_file} --go-file {go_file} "
            "--lifetime-ms 5000"
        ),
        "injection_method": "hook",
        "d3d11_path": str(PROBE_DLL),
    }

    result = launch_game(config, str(ROOT))
    try:
        _wait_for_file(marker_file)
        assert result.target_pid == int(pid_file.read_text())
        assert marker_file.read_text().strip() == str(result.target_pid)
    finally:
        process = subprocess.Popen(["taskkill", "/F", "/PID", str(result.target_pid)], stdout=subprocess.DEVNULL)
        process.wait(timeout=5)


def test_launch_game_launcher_child_injects_into_new_target(tmp_path, monkeypatch):
    """启动程序 != 目标程序：等待目标进程出现后自动注入（真实进程链）。"""
    pid_file = tmp_path / "child.pid"
    marker_file = tmp_path / "child.marker"
    monkeypatch.setenv("XXMI_PROBE_MARKER", str(marker_file))
    child_args = subprocess.list2cmdline([
        "start",
        "",
        str(TARGET_EXE),
        "--no-window",
        "--pid-file",
        str(pid_file),
        "--lifetime-ms",
        "8000",
    ])
    config = {
        "launch_program": os.environ.get("COMSPEC", r"C:\Windows\System32\cmd.exe"),
        "target_program": str(TARGET_EXE),
        "game_exe_name": "unrelated-stale-name.exe",
        "launch_args": f"/c {child_args}",
        "injection_method": "direct",
        "dll_files": [str(PROBE_DLL)],
    }

    result = launch_game(config, str(ROOT))
    try:
        _wait_for_file(marker_file)
        assert pid_file.is_file()
        assert result.target_pid == int(pid_file.read_text())
        assert marker_file.read_text().strip() == str(result.target_pid)
    finally:
        process = subprocess.Popen(
            ["taskkill", "/F", "/PID", str(result.target_pid)], stdout=subprocess.DEVNULL
        )
        process.wait(timeout=5)

