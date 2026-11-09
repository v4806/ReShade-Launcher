from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import logging
import os
import re
import subprocess
import sys
import time

from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

import psutil

_log = logging.getLogger(__name__)


CREATE_SUSPENDED = 0x00000004
CREATE_UNICODE_ENVIRONMENT = 0x00000400
CREATE_NO_WINDOW = 0x08000000
STARTF_USESHOWWINDOW = 0x00000001
SW_SHOWNORMAL = 1
TH32CS_SNAPMODULE = 0x00000008
TH32CS_SNAPMODULE32 = 0x00000010
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value


class InjectionError(RuntimeError):
    pass


class _STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ("cb", wt.DWORD),
        ("lpReserved", wt.LPWSTR),
        ("lpDesktop", wt.LPWSTR),
        ("lpTitle", wt.LPWSTR),
        ("dwX", wt.DWORD),
        ("dwY", wt.DWORD),
        ("dwXSize", wt.DWORD),
        ("dwYSize", wt.DWORD),
        ("dwXCountChars", wt.DWORD),
        ("dwYCountChars", wt.DWORD),
        ("dwFillAttribute", wt.DWORD),
        ("dwFlags", wt.DWORD),
        ("wShowWindow", wt.WORD),
        ("cbReserved2", wt.WORD),
        ("lpReserved2", wt.LPBYTE),
        ("hStdInput", wt.HANDLE),
        ("hStdOutput", wt.HANDLE),
        ("hStdError", wt.HANDLE),
    ]


class _PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("hProcess", wt.HANDLE),
        ("hThread", wt.HANDLE),
        ("dwProcessId", wt.DWORD),
        ("dwThreadId", wt.DWORD),
    ]


class _MODULEENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wt.DWORD),
        ("th32ModuleID", wt.DWORD),
        ("th32ProcessID", wt.DWORD),
        ("GlblcntUsage", wt.DWORD),
        ("ProccntUsage", wt.DWORD),
        ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)),
        ("modBaseSize", wt.DWORD),
        ("hModule", wt.HMODULE),
        ("szModule", wt.WCHAR * 256),
        ("szExePath", wt.WCHAR * 260),
    ]


@dataclass(frozen=True)
class InjectionPlan:
    method: str
    hook_dll: Path | None
    direct_dlls: tuple[Path, ...]


@dataclass
class LaunchResult:
    root_pid: int
    target_pid: int
    root_process: "SuspendedProcess | None" = None


class SuspendedProcess:
    def __init__(self, process_handle: int, thread_handle: int, pid: int, tid: int):
        self.process_handle = process_handle
        self.thread_handle = thread_handle
        self.pid = pid
        self.tid = tid
        self._resumed = False

    def resume(self) -> None:
        if self._resumed:
            return
        result = ctypes.windll.kernel32.ResumeThread(self.thread_handle)
        if result == 0xFFFFFFFF:
            error = ctypes.GetLastError()
            _log.error("恢复挂起进程失败: PID=%s, GetLastError=%s", self.pid, error)
            raise ctypes.WinError(error)
        self._resumed = True
        self.close_thread()
        _log.debug("已恢复挂起进程: PID=%s", self.pid)

    def terminate(self, exit_code: int = 1) -> None:
        if self.process_handle:
            _log.warning("终止挂起进程: PID=%s, exit_code=%s", self.pid, exit_code)
            ctypes.windll.kernel32.TerminateProcess(self.process_handle, exit_code)

    def close_thread(self) -> None:
        if self.thread_handle:
            ctypes.windll.kernel32.CloseHandle(self.thread_handle)
            self.thread_handle = 0

    def close(self) -> None:
        self.close_thread()
        if self.process_handle:
            ctypes.windll.kernel32.CloseHandle(self.process_handle)
            self.process_handle = 0
        _log.debug("已关闭进程句柄: PID=%s", self.pid)


class XxmiInjector:
    def __init__(self, injector_path: str | Path):
        self.path = Path(injector_path).resolve()
        _log.info("加载注入器 DLL: %s", self.path)
        self.lib = ctypes.WinDLL(str(self.path))
        self.hook = wt.HHOOK()
        self.mutex = wt.HANDLE()
        self._hooked = False

        self.lib.Inject.argtypes = [wt.DWORD, wt.LPCWSTR, ctypes.c_int]
        self.lib.Inject.restype = ctypes.c_int
        self.lib.HookLibraryByPid.argtypes = [
            wt.LPCWSTR,
            wt.DWORD,
            ctypes.POINTER(wt.HHOOK),
            ctypes.POINTER(wt.HANDLE),
        ]
        self.lib.HookLibraryByPid.restype = ctypes.c_int
        self.lib.UnhookLibraryByPid.argtypes = [
            ctypes.POINTER(wt.HHOOK),
            ctypes.POINTER(wt.HANDLE),
        ]
        self.lib.UnhookLibraryByPid.restype = ctypes.c_int

    def inject(self, pid: int, dll_path: str | Path, timeout: int = 15) -> None:
        path = Path(dll_path).resolve()
        _log.info("注入 DLL: PID=%s, DLL=%s, timeout=%ss", pid, path, timeout)
        started = time.monotonic()
        result = self.lib.Inject(pid, str(path), timeout)
        elapsed = time.monotonic() - started
        if result != 0:
            _log.error(
                "注入失败: PID=%s, DLL=%s, 原生返回码=%s, 耗时=%.3fs",
                pid, path, result, elapsed,
            )
            raise InjectionError(f"Failed to inject {path} into PID {pid}: native code {result}")
        _log.info("注入调用成功: PID=%s, DLL=%s, 耗时=%.3fs", pid, path.name, elapsed)

    def hook_by_pid(self, dll_path: str | Path, target_pid: int) -> None:
        if self._hooked:
            _log.error("Hook 重复安装被拒绝: 已有活动 Hook")
            raise InjectionError("Injector hook is already active")
        path = Path(dll_path).resolve()
        _log.info("安装 Hook: PID=%s, DLL=%s", target_pid, path)
        result = self.lib.HookLibraryByPid(
            str(path),
            target_pid,
            ctypes.byref(self.hook),
            ctypes.byref(self.mutex),
        )
        if result != 0:
            _log.error(
                "Hook 安装失败: PID=%s, DLL=%s, 原生返回码=%s",
                target_pid, path, result,
            )
            raise InjectionError(f"Failed to hook {path} for PID {target_pid}: native code {result}")
        self._hooked = True
        _log.info("Hook 安装成功: PID=%s, DLL=%s", target_pid, path)

    def verify(self, pid: int, dll_path: str | Path, timeout: float = 5.0) -> None:
        path = Path(dll_path).resolve()
        _log.info("验证模块加载: PID=%s, DLL=%s, timeout=%.1fs", pid, path.name, timeout)
        state = _wait_for_module(pid, path, timeout=timeout)
        if state is True:
            _log.info("模块已加载: PID=%s, DLL=%s", pid, path.name)
            return
        if state is None:
            # 模块枚举不可用（受反作弊保护的进程），Inject 已返回成功，
            # 不能仅凭无法枚举就判定注入失败。
            _log.warning(
                "无法枚举模块（可能受反作弊保护），保留注入成功结论: PID=%s, DLL=%s",
                pid, path.name,
            )
            return
        _log.error("模块未加载: PID=%s, DLL=%s", pid, path.name)
        raise InjectionError(f"Module was not loaded in PID {pid}: {path}")

    def unhook(self) -> None:
        if not self._hooked:
            return
        _log.info("移除 Hook")
        try:
            result = self.lib.UnhookLibraryByPid(ctypes.byref(self.hook), ctypes.byref(self.mutex))
            if result != 0:
                _log.error("移除 Hook 失败: 原生返回码=%s", result)
                raise InjectionError(f"Failed to remove injector hook: native code {result}")
            _log.info("Hook 已移除")
        finally:
            self.hook = wt.HHOOK()
            self.mutex = wt.HANDLE()
            self._hooked = False


def resolve_runtime_file(script_dir: str | Path, relative_path: str) -> Path | None:
    root = Path(script_dir)
    candidates = [root / relative_path]
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidates.append(Path(meipass) / relative_path)

    for candidate in candidates:
        if candidate.is_file():
            _log.debug("运行时文件命中: %s", candidate.resolve())
            return candidate.resolve()
    _log.debug("运行时文件未找到: %s (候选=%s)", relative_path, [str(c) for c in candidates])
    return None


def _normalize_method(config: dict) -> str:
    method = str(config.get("injection_method") or "direct").strip().lower()
    if method not in {"direct", "hook"}:
        _log.error("不支持的注入方式: %s", method)
        raise ValueError(f"Unsupported injection_method: {method}")
    _log.debug("注入方式: %s", method)
    return method


def hook_candidate(config: dict) -> Path | None:
    d3d11_path = config.get("d3d11_path")
    if d3d11_path:
        return Path(d3d11_path)
    for dll_path in config.get("dll_files") or []:
        candidate = Path(dll_path)
        if candidate.name.lower() == "d3d11.dll":
            return candidate
    return None


def _selected_dlls(config: dict, script_dir: Path) -> list[Path]:
    dlls: list[Path] = []
    if config.get("reshade_dll"):
        reshade = resolve_runtime_file(script_dir, os.path.join("ReShade", "ReShade64.dll"))
        if reshade is not None:
            dlls.append(reshade)
        else:
            dlls.append((script_dir / "ReShade" / "ReShade64.dll").resolve())

    if config.get("d3d11_path"):
        dlls.append(Path(config["d3d11_path"]))

    dlls.extend(Path(path) for path in (config.get("dll_files") or []))
    return [path.resolve() for path in dlls]


def _validate_same_executable(config: dict) -> None:
    launch_program = config.get("launch_program")
    target_program = config.get("target_program")
    if not launch_program or not target_program:
        raise ValueError("HOOK requires launch_program and target_program")
    launch = os.path.normcase(os.path.abspath(launch_program))
    target = os.path.normcase(os.path.abspath(target_program))
    if launch != target:
        raise ValueError("HOOK requires launch_program and target_program to be the same executable")


def build_injection_plan(config: dict, script_dir: str | Path) -> InjectionPlan:
    root = Path(script_dir)
    method = _normalize_method(config)
    dlls = _selected_dlls(config, root)
    _log.info("构建注入计划: 方式=%s, 应用根目录=%s, DLL 候选=%s", method, root, [str(p) for p in dlls])

    for dll_path in dlls:
        if not dll_path.is_file():
            _log.error("注入计划失败，DLL 不存在: %s", dll_path)
            raise FileNotFoundError(str(dll_path))

    if method == "direct":
        _log.info("注入计划: direct, DLL 顺序=%s", [str(p) for p in dlls])
        return InjectionPlan(method=method, hook_dll=None, direct_dlls=tuple(dlls))

    _validate_same_executable(config)
    candidate = hook_candidate(config)
    if candidate is None:
        _log.error("注入计划失败: HOOK 模式缺少 d3d11.dll 候选")
        raise ValueError("HOOK requires a d3d11.dll candidate")
    candidate = candidate.resolve()
    if not candidate.is_file():
        _log.error("注入计划失败，Hook DLL 不存在: %s", candidate)
        raise FileNotFoundError(str(candidate))

    direct_dlls = tuple(path for path in dlls if os.path.normcase(path) != os.path.normcase(candidate))
    _log.info("注入计划: hook, Hook DLL=%s, 直接注入=%s", candidate, [str(p) for p in direct_dlls])
    return InjectionPlan(method=method, hook_dll=candidate, direct_dlls=direct_dlls)


def validate_injection_plan(config: dict, script_dir: str | Path) -> tuple[bool, str]:
    try:
        build_injection_plan(config, script_dir)
    except (FileNotFoundError, ValueError, OSError) as exc:
        _log.warning("注入计划校验失败: %s", exc)
        return False, str(exc)
    return True, ""


def _create_suspended_process(launch_program: str | Path, launch_args: str = "") -> SuspendedProcess:
    exe_path = str(Path(launch_program).resolve())
    command_line = subprocess.list2cmdline([exe_path])
    if launch_args:
        command_line = f"{command_line} {launch_args}"
    _log.info("创建挂起进程: %s", command_line)
    _log.debug("工作目录: %s", str(Path(exe_path).parent))

    startup = _STARTUPINFOW()
    startup.cb = ctypes.sizeof(startup)
    startup.dwFlags = STARTF_USESHOWWINDOW
    startup.wShowWindow = SW_SHOWNORMAL
    process_info = _PROCESS_INFORMATION()
    command_buffer = ctypes.create_unicode_buffer(command_line)

    kernel32 = ctypes.windll.kernel32
    kernel32.CreateProcessW.argtypes = [
        wt.LPCWSTR,
        wt.LPWSTR,
        wt.LPVOID,
        wt.LPVOID,
        wt.BOOL,
        wt.DWORD,
        wt.LPVOID,
        wt.LPCWSTR,
        ctypes.POINTER(_STARTUPINFOW),
        ctypes.POINTER(_PROCESS_INFORMATION),
    ]
    kernel32.CreateProcessW.restype = wt.BOOL
    success = kernel32.CreateProcessW(
        exe_path,
        command_buffer,
        None,
        None,
        False,
        CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
        None,
        str(Path(exe_path).parent),
        ctypes.byref(startup),
        ctypes.byref(process_info),
    )
    if not success:
        error = ctypes.GetLastError()
        _log.error(
            "CreateProcessW 失败: 程序=%s, GetLastError=%s, 参数=%s",
            exe_path, error, launch_args or "(无)",
        )
        raise ctypes.WinError(error)

    _log.info(
        "已创建挂起进程: root PID=%s, TID=%s, 程序=%s",
        int(process_info.dwProcessId),
        int(process_info.dwThreadId),
        exe_path,
    )
    return SuspendedProcess(
        int(process_info.hProcess),
        int(process_info.hThread),
        int(process_info.dwProcessId),
        int(process_info.dwThreadId),
    )


def _psutil_process_snapshot() -> dict[int, dict]:
    snapshot = {}
    for process in psutil.process_iter(["pid", "ppid", "name", "exe", "cmdline"]):
        try:
            info = process.info
            snapshot[int(info["pid"])] = {
                "pid": int(info["pid"]),
                "ppid": int(info.get("ppid") or 0),
                "name": info.get("name") or "",
                "exe": info.get("exe") or "",
                "cmdline": info.get("cmdline") or [],
            }
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    return snapshot


def _describe_processes(pids, processes: dict[int, dict]) -> list[dict]:
    """记录候选进程的 PID、父 PID、路径和命令行，便于确认注入是否选错进程。"""
    details = []
    for pid in pids:
        process = processes.get(pid) or {}
        cmdline = " ".join(process.get("cmdline") or [])
        if len(cmdline) > 500:
            cmdline = cmdline[:500] + "..."
        details.append({
            "pid": pid,
            "ppid": process.get("ppid"),
            "name": process.get("name"),
            "exe": process.get("exe"),
            "cmdline": cmdline,
        })
    return details


def _is_descendant_or_root(
    pid: int,
    root_pid: int,
    processes: dict[int, dict],
) -> bool:
    current = pid
    visited = set()
    while current and current not in visited:
        if current == root_pid:
            return True
        visited.add(current)
        process = processes.get(current)
        if not process:
            return False
        current = int(process.get("ppid") or 0)
    return False


def _process_matches_target(process: dict, target_program: str | None, game_exe_name: str) -> bool:
    if target_program:
        expected = os.path.normcase(os.path.abspath(target_program))
        actual = process.get("exe") or ""
        if actual and os.path.normcase(os.path.abspath(actual)) == expected:
            return True

    # 路径不可读（受保护进程）或路径不匹配时退回到进程名匹配。
    # 目标程序的 exe 名优先，game_exe_name 可能来自旧配置/自动探测而过期。
    expected_names = set()
    if target_program:
        expected_names.add(Path(target_program).name.lower())
    if game_exe_name:
        expected_names.add(Path(game_exe_name).name.lower())
    name = (process.get("name") or "").lower()
    return bool(name) and name in expected_names


def _find_child_target_pid_from_snapshot(
    root_pid: int,
    target_program: str | None,
    game_exe_name: str,
    baseline_pids: set[int],
    process_snapshot,
    timeout: float = 30.0,
    interval: float = 0.1,
) -> int | None:
    _log.info(
        "等待目标子进程: root PID=%s, 目标=%s, exe=%s, 超时=%.1fs",
        root_pid, target_program or "(未指定)", game_exe_name or "(未指定)", timeout,
    )
    deadline = time.monotonic() + timeout
    last_candidates = None
    while True:
        processes = process_snapshot()
        new_targets = [
            pid
            for pid, process in processes.items()
            if pid not in baseline_pids
            and _process_matches_target(process, target_program, game_exe_name)
        ]
        descendant_candidates = [
            pid for pid in new_targets
            if _is_descendant_or_root(pid, root_pid, processes)
        ]
        candidates = descendant_candidates or new_targets
        if candidates:
            details = _describe_processes(candidates, processes)
            if details != last_candidates:
                _log.info("候选目标进程: %s", details)
                last_candidates = details
        if len(candidates) == 1:
            pid = candidates[0]
            _log.info(
                "已锁定目标进程: PID=%s (root PID=%s), 详情=%s",
                pid, root_pid, _describe_processes([pid], processes),
            )
            return pid
        if len(candidates) > 1:
            _log.error(
                "发现多个候选目标进程: %s, 详情=%s",
                candidates, _describe_processes(candidates, processes),
            )
            raise InjectionError(f"Multiple target processes found for PID chain {root_pid}: {candidates}")
        if time.monotonic() >= deadline:
            _log.error("等待目标进程超时: root PID=%s, 超时=%.1fs", root_pid, timeout)
            return None
        time.sleep(interval)


def _find_child_target_pid(
    root_pid: int,
    target_program: str | None,
    game_exe_name: str,
    baseline_pids: set[int],
    timeout: float,
) -> int:
    pid = _find_child_target_pid_from_snapshot(
        root_pid,
        target_program,
        game_exe_name,
        baseline_pids,
        _psutil_process_snapshot,
        timeout=timeout,
    )
    if pid is None:
        _log.error("目标进程未在 %.1fs 内启动: exe=%s", timeout, game_exe_name)
        raise InjectionError(f"Target process did not start within {timeout:.1f}s")
    return pid


def _is_module_loaded(pid: int, dll_path: str | Path) -> bool | None:
    """返回 True=已加载，False=确认未加载，None=无法查询（受保护进程）。"""
    expected = os.path.normcase(str(Path(dll_path).resolve()))
    kernel32 = ctypes.windll.kernel32
    kernel32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
    kernel32.CreateToolhelp32Snapshot.restype = wt.HANDLE
    kernel32.Module32FirstW.argtypes = [wt.HANDLE, ctypes.POINTER(_MODULEENTRY32W)]
    kernel32.Module32FirstW.restype = wt.BOOL
    kernel32.Module32NextW.argtypes = [wt.HANDLE, ctypes.POINTER(_MODULEENTRY32W)]
    kernel32.Module32NextW.restype = wt.BOOL
    kernel32.CloseHandle.argtypes = [wt.HANDLE]
    kernel32.CloseHandle.restype = wt.BOOL
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid)
    if not snapshot or snapshot == INVALID_HANDLE_VALUE:
        return None
    try:
        entry = _MODULEENTRY32W()
        entry.dwSize = ctypes.sizeof(entry)
        if not kernel32.Module32FirstW(snapshot, ctypes.byref(entry)):
            return None
        while True:
            if os.path.normcase(entry.szExePath) == expected:
                return True
            if not kernel32.Module32NextW(snapshot, ctypes.byref(entry)):
                return False
    finally:
        kernel32.CloseHandle(snapshot)


def _wait_for_module(
    pid: int,
    dll_path: str | Path,
    timeout: float = 5.0,
    interval: float = 0.05,
) -> bool | None:
    deadline = time.monotonic() + timeout
    last_state: bool | None = False
    reported: bool | None = None
    while time.monotonic() < deadline:
        state = _is_module_loaded(pid, dll_path)
        if state:
            _log.debug("模块已加载: PID=%s, DLL=%s", pid, dll_path)
            return True
        if state != reported:
            _log.debug("模块等待状态: PID=%s, DLL=%s, state=%s", pid, dll_path, state)
            reported = state
        last_state = state
        time.sleep(interval)
    _log.debug("模块等待结束: PID=%s, DLL=%s, 最终状态=%s", pid, dll_path, last_state)
    return last_state


def _inject_and_verify(injector, pid: int, dll_paths: tuple[Path, ...]) -> None:
    """逐个注入并校验；单个 DLL 失败不阻断后续 DLL（例如 ReShade 失败不应连累 d3d11）。"""
    _log.info("开始注入 %s 个 DLL 到 PID=%s: %s", len(dll_paths), pid, [p.name for p in dll_paths])
    errors: list[str] = []
    injected: list[Path] = []
    for dll_path in dll_paths:
        try:
            _log.info("注入 DLL 开始: PID=%s, DLL=%s", pid, dll_path.name)
            injector.inject(pid, dll_path)
        except Exception as exc:
            _log.error("注入 DLL 失败: PID=%s, DLL=%s, 错误=%s", pid, dll_path, exc)
            errors.append(f"{dll_path}: {exc}")
            continue
        injected.append(dll_path)
    for dll_path in injected:
        try:
            injector.verify(pid, dll_path)
            _log.info("注入并验证成功: PID=%s, DLL=%s", pid, dll_path.name)
        except Exception as exc:
            _log.error("验证 DLL 失败: PID=%s, DLL=%s, 错误=%s", pid, dll_path, exc)
            errors.append(f"{dll_path}: {exc}")
    if errors:
        _log.error("注入流程存在 %s 个错误: %s", len(errors), errors)
        raise InjectionError("; ".join(errors))


@contextmanager
def _temporary_d3dx_target(dll_paths: tuple[Path, ...], target_exe_name: str):
    originals: dict[Path, bytes] = {}
    try:
        for dll_path in dll_paths:
            if dll_path.name.lower() != "d3d11.dll":
                continue
            d3dx_path = dll_path.parent / "d3dx.ini"
            if not d3dx_path.is_file() or d3dx_path in originals:
                continue
            original_bytes = d3dx_path.read_bytes()
            originals[d3dx_path] = original_bytes
            has_bom = original_bytes.startswith(b"\xef\xbb\xbf")
            text = original_bytes.decode("utf-8-sig")
            updated, count = re.subn(
                r"(?mi)^(\s*target\s*=\s*)[^\r\n]*",
                rf"\g<1>{target_exe_name}",
                text,
                count=1,
            )
            if count:
                encoding = "utf-8-sig" if has_bom else "utf-8"
                d3dx_path.write_text(updated, encoding=encoding, newline="")
                _log.info("已临时修改 d3dx.ini 的 target: %s -> %s", d3dx_path, target_exe_name)
            else:
                _log.warning("d3dx.ini 中未找到 target 字段: %s", d3dx_path)
        yield
    finally:
        for d3dx_path, original_bytes in originals.items():
            try:
                d3dx_path.write_bytes(original_bytes)
                _log.info("已恢复 d3dx.ini: %s", d3dx_path)
            except Exception as exc:
                _log.error("恢复 d3dx.ini 失败: %s, 错误=%s", d3dx_path, exc)


def launch_game(
    config: dict,
    script_dir: str | Path,
    *,
    injector_factory=XxmiInjector,
) -> LaunchResult:
    _log.info("=" * 70)
    _log.info("启动游戏流程开始")
    _log.debug(
        "配置: launch_program=%s, target_program=%s, launch_args=%s, injection_method=%s",
        config.get("launch_program"), config.get("target_program"),
        config.get("launch_args"), config.get("injection_method"),
    )
    plan = build_injection_plan(config, script_dir)
    injector_path = resolve_runtime_file(script_dir, "3dmloader.dll")
    if injector_path is None:
        _log.error("找不到注入器 DLL: 3dmloader.dll (script_dir=%s)", script_dir)
        raise FileNotFoundError("3dmloader.dll")
    _log.info("注入器 DLL: %s", injector_path)

    launch_program = config.get("launch_program") or config.get("game_dir")
    target_program = config.get("target_program") or config.get("game_dir")
    if not launch_program:
        _log.error("launch_program 未配置，无法启动")
        raise ValueError("launch_program is required")

    timeout = float(config.get("process_timeout") or 30)
    baseline_pids = set(psutil.pids())
    _log.info(
        "启动参数: 程序=%s, 目标=%s, 进程基线=%s, 超时=%ss",
        launch_program, target_program or launch_program, len(baseline_pids), timeout,
    )
    process = _create_suspended_process(launch_program, config.get("launch_args", ""))
    injector = None
    resumed = False
    hook_installed = False
    target_exe_name = Path(target_program or launch_program).name

    try:
        injector = injector_factory(injector_path)
        same_executable = os.path.normcase(os.path.abspath(launch_program)) == os.path.normcase(
            os.path.abspath(target_program or launch_program)
        )
        _log.info("启动模式: %s (同一可执行文件=%s)", plan.method, same_executable)
        if plan.method == "hook":
            if not same_executable or plan.hook_dll is None:
                raise ValueError("HOOK requires launch_program and target_program to be the same executable")
            with _temporary_d3dx_target((plan.hook_dll, *plan.direct_dlls), target_exe_name):
                injector.hook_by_pid(plan.hook_dll, process.pid)
                hook_installed = True
                process.resume()
                resumed = True
                hook_state = _wait_for_module(process.pid, plan.hook_dll, timeout=timeout)
                if hook_state is False:
                    _log.error("Hook 模块未加载: PID=%s, DLL=%s", process.pid, plan.hook_dll)
                    raise InjectionError(f"Hook module was not loaded in PID {process.pid}: {plan.hook_dll}")
                _inject_and_verify(injector, process.pid, plan.direct_dlls)
            target_pid = process.pid
        elif same_executable:
            process.resume()
            resumed = True
            with _temporary_d3dx_target(plan.direct_dlls, target_exe_name):
                _inject_and_verify(injector, process.pid, plan.direct_dlls)
            target_pid = process.pid
        else:
            process.resume()
            resumed = True
            target_pid = _find_child_target_pid(
                process.pid,
                target_program,
                config.get("game_exe_name", ""),
                baseline_pids,
                timeout,
            )
            with _temporary_d3dx_target(plan.direct_dlls, target_exe_name):
                _inject_and_verify(injector, target_pid, plan.direct_dlls)

        _log.info("启动流程完成: root PID=%s, target PID=%s", process.pid, target_pid)
        return LaunchResult(root_pid=process.pid, target_pid=target_pid, root_process=None)
    except Exception:
        _log.exception("启动/注入流程失败")
        if not resumed:
            _log.warning("终止未恢复的挂起进程: PID=%s", process.pid)
            process.terminate()
        raise
    finally:
        if hook_installed and injector is not None:
            injector.unhook()
        process.close()

