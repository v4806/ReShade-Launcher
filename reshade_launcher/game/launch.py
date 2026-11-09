# -*- coding: utf-8 -*-
"""Launch facade backed by the adapted XXMI 3dmloader injector."""

import logging
import os
import subprocess
import tempfile
import urllib.request

from reshade_launcher.game.injector import (
    XxmiInjector,
    build_injection_plan,
    launch_game as launch_with_xxmi_injector,
    resolve_runtime_file,
    validate_injection_plan,
)

_log = logging.getLogger(__name__)


def is_vc_redist_installed():
    """检查 VC++ 2015-2022 Redistributable x64 是否已安装"""
    system32 = os.path.join(
        os.environ.get('SystemRoot', 'C:\\Windows'),
        'System32',
        'msvcp140.dll',
    )
    if os.path.exists(system32):
        return True

    try:
        import winreg

        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
        )
        installed, _ = winreg.QueryValueEx(key, "Installed")
        _log.debug("VC++ 运行库注册表 Installed=%s", installed)
        return installed == 1
    except Exception as exc:
        _log.debug("读取 VC++ 运行库注册表失败: %s", exc)
        return False


def download_vc_redist(dest_path):
    """下载 VC++ 运行库安装程序到指定路径，返回成功与否"""
    url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    _log.info("下载 VC++ 运行库: %s -> %s", url, dest_path)
    try:
        urllib.request.urlretrieve(url, dest_path)
        return True
    except Exception as exc:
        _log.error("下载 VC++ 运行库失败: %s", exc)
        return False


def install_vc_redist(exe_path):
    """静默安装 VC++ 运行库，返回成功与否"""
    _log.info("安装 VC++ 运行库: %s", exe_path)
    try:
        result = subprocess.run(
            [exe_path, '/quiet', '/norestart'],
            capture_output=True,
            timeout=300,
        )
        if result.returncode != 0:
            _log.warning("VC++ 运行库安装返回码=%s", result.returncode)
        return result.returncode == 0
    except Exception as exc:
        _log.error("安装 VC++ 运行库失败: %s", exc)
        return False


def ensure_vc_redist(progress_callback=None):
    """确保 VC++ 运行库可用，缺失时尝试自动安装。"""
    if is_vc_redist_installed():
        return True

    if progress_callback:
        progress_callback("检测到 VC++ 运行库缺失，正在下载安装程序...")

    installer_path = os.path.join(tempfile.gettempdir(), "vc_redist.x64.exe")
    if not download_vc_redist(installer_path):
        if progress_callback:
            progress_callback("下载 VC++ 运行库失败，请手动安装。")
        return False

    if progress_callback:
        progress_callback("正在安装 VC++ 运行库，请等待...（可能弹出 UAC 窗口）")

    if not install_vc_redist(installer_path):
        if progress_callback:
            progress_callback("安装 VC++ 运行库失败，请手动安装。")
        return False

    if progress_callback:
        progress_callback("VC++ 运行库安装完成。")
    return True


def validate_launch(config, script_dir):
    _log.debug("校验启动配置: script_dir=%s", script_dir)
    if resolve_runtime_file(script_dir, "3dmloader.dll") is None:
        _log.error("校验失败: 找不到注入器 3dmloader.dll (script_dir=%s)", script_dir)
        return False, "找不到注入器: 3dmloader.dll"

    launch_program = config.get('launch_program') or config.get('game_dir')
    if not launch_program or not os.path.exists(launch_program):
        _log.error("校验失败: 启动程序不存在 %s", launch_program)
        return False, f"启动程序不存在: {launch_program}"

    ok, error = validate_injection_plan(config, script_dir)
    if ok:
        _log.info("启动配置校验通过: %s", launch_program)
    else:
        _log.error("启动配置校验失败: %s", error)
    return ok, error


def _build_dll_list(config, script_dir, check_exists=False):
    plan = build_injection_plan(config, script_dir)
    dlls = list(plan.direct_dlls)
    if plan.hook_dll is not None:
        dlls.insert(0, plan.hook_dll)
    return [str(path) for path in dlls]


def launch_game(config, script_dir):
    try:
        result = launch_with_xxmi_injector(
            config,
            script_dir,
            injector_factory=XxmiInjector,
        )
        _log.info("启动成功: root PID=%s, target PID=%s", result.root_pid, result.target_pid)
        return result.root_pid, result.target_pid
    except Exception as exc:
        _log.exception("启动过程异常: %s", exc)
        return None
