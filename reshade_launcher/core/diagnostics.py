# -*- coding: utf-8 -*-
"""统一诊断日志配置（仅 Debug 构建启用）。

- Debug 构建（源码运行或 PyInstaller Debug spec，``__debug__`` 为 True）：
  控制台 + 文件双输出，记录完整运行上下文、注入链路与未捕获异常。
- Release 构建（PyInstaller Release spec，``optimize=1``）：不导入本模块，
  由 ``main.py`` 关闭标准 logging，保证零日志输出、零磁盘写入。
"""

from __future__ import annotations

import faulthandler
import logging
import logging.handlers
import locale
import os
import platform
import sys
import tempfile
import threading
import time
import uuid
from datetime import datetime

APP_LOG_PREFIX = "launcher_"
CRASH_LOG_PREFIX = "crash_"
MAX_BYTES = 10 * 1024 * 1024
BACKUP_COUNT = 3
KEEP_DAYS = 14

_session_id = ""
_log_file = ""
_log_dir = ""
_crash_stream = None
_initialized = False


def app_root() -> str:
    """返回应用根目录（exe 所在目录或项目根目录）。"""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def get_log_directory() -> str:
    """返回日志目录（当前会话已初始化时）。"""
    return _log_dir


def get_log_file() -> str:
    """返回当前会话日志文件路径。"""
    return _log_file


def _resolve_log_directory() -> str:
    base = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA")
    if not base:
        base = tempfile.gettempdir()
    return os.path.join(base, "ReShadeLauncher", "Logs")


def _version() -> str:
    try:
        from reshade_launcher.core.config import APP_VERSION

        return APP_VERSION
    except Exception:
        return "unknown"


def _new_session_id() -> str:
    return "%s_%s_%s" % (
        datetime.now().strftime("%Y%m%d_%H%M%S"),
        os.getpid(),
        uuid.uuid4().hex[:6],
    )


def _cleanup_old_logs(directory: str) -> None:
    cutoff = time.time() - KEEP_DAYS * 86400
    try:
        names = os.listdir(directory)
    except OSError:
        return
    for name in names:
        if not (name.startswith(APP_LOG_PREFIX) or name.startswith(CRASH_LOG_PREFIX)):
            continue
        path = os.path.join(directory, name)
        try:
            if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
                os.remove(path)
        except OSError:
            pass


def _install_exception_hooks(logger: logging.Logger) -> None:
    previous_excepthook = sys.excepthook
    previous_thread_hook = getattr(threading, "excepthook", None)
    previous_unraisable_hook = getattr(sys, "unraisablehook", None)

    def excepthook(exc_type, exc, tb):
        try:
            logger.critical("未捕获异常", exc_info=(exc_type, exc, tb))
        finally:
            try:
                previous_excepthook(exc_type, exc, tb)
            except Exception:
                pass

    def thread_excepthook(args):
        thread_name = getattr(getattr(args, "thread", None), "name", "?")
        try:
            logger.critical(
                "线程未捕获异常 (thread=%s)", thread_name,
                exc_info=(args.exc_type, args.exc_value, args.exc_traceback),
            )
        finally:
            if previous_thread_hook is not None:
                try:
                    previous_thread_hook(args)
                except Exception:
                    pass

    def unraisablehook(unraisable):
        try:
            logger.error(
                "未捕获的不可引发异常: %s",
                getattr(unraisable, "err_msg", None),
                exc_info=(
                    getattr(unraisable, "exc_type", None),
                    getattr(unraisable, "exc_value", None),
                    getattr(unraisable, "exc_traceback", None),
                ),
            )
        finally:
            if previous_unraisable_hook is not None:
                try:
                    previous_unraisable_hook(unraisable)
                except Exception:
                    pass

    sys.excepthook = excepthook
    if hasattr(threading, "excepthook"):
        threading.excepthook = thread_excepthook
    if hasattr(sys, "unraisablehook"):
        sys.unraisablehook = unraisablehook


def _enable_crash_dump(directory: str) -> None:
    """启用 faulthandler，把原生崩溃栈写入独立会话文件。"""
    global _crash_stream
    path = os.path.join(directory, "%s%s.log" % (CRASH_LOG_PREFIX, _session_id))
    try:
        _crash_stream = open(path, "a", encoding="utf-8", errors="backslashreplace")
        faulthandler.enable(file=_crash_stream, all_threads=True)
    except Exception:
        _crash_stream = None


def setup_logging(console_level: int = logging.DEBUG, file_level: int = logging.DEBUG) -> logging.Logger:
    """初始化日志系统，幂等。仅在 Debug 构建中调用。"""
    global _initialized, _log_file, _log_dir, _session_id
    root = logging.getLogger()
    if _initialized:
        return root
    _initialized = True

    _session_id = _new_session_id()
    _log_dir = _resolve_log_directory()

    try:
        os.makedirs(_log_dir, exist_ok=True)
        _cleanup_old_logs(_log_dir)
    except Exception:
        # 日志目录不可写时退化为仅控制台，不阻止应用启动。
        _log_dir = ""

    formatter = logging.Formatter(
        "%(asctime)s.%(msecs)03d [%(levelname)-7s] "
        "[%(process)d:%(threadName)s] %(name)s:%(lineno)d | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    if _log_dir:
        log_path = os.path.join(_log_dir, "%s%s.log" % (APP_LOG_PREFIX, _session_id))
        try:
            file_handler = logging.handlers.RotatingFileHandler(
                log_path,
                maxBytes=MAX_BYTES,
                backupCount=BACKUP_COUNT,
                encoding="utf-8",
                errors="backslashreplace",
            )
            file_handler.setLevel(file_level)
            file_handler.setFormatter(formatter)
            root.addHandler(file_handler)
            _log_file = log_path
        except Exception as exc:
            _log_file = ""
            print("[日志] 无法创建日志文件 %s: %s" % (log_path, exc), file=sys.stderr)

    stream = sys.stdout
    if stream is not None:
        console_handler = logging.StreamHandler(stream)
        console_handler.setLevel(console_level)
        console_handler.setFormatter(formatter)
        root.addHandler(console_handler)

    root.setLevel(min(console_level, file_level))

    logger = logging.getLogger("reshade_launcher")
    logger.info("=" * 88)
    logger.info("ReShade Launcher 启动 | 版本=%s | 构建=Debug", _version())
    logger.info("会话 ID: %s", _session_id)
    logger.info("时间: %s", datetime.now().astimezone().isoformat(timespec="seconds"))
    logger.info("程序: %s", sys.executable)
    logger.info("命令行: %s", sys.argv)
    logger.info("工作目录: %s", os.getcwd())
    logger.info("应用根目录: %s", app_root())
    logger.info("日志文件: %s", _log_file or "(仅控制台)")
    logger.info("Python: %s", sys.version.replace("\n", " "))
    logger.info("平台: %s", platform.platform())
    try:
        logger.info("区域/语言: %s", locale.getlocale())
    except Exception:
        logger.info("区域/语言: 未知")
    logger.info("打包运行: %s", bool(getattr(sys, "frozen", False)))
    logger.info("=" * 88)

    _install_exception_hooks(logger)
    if _log_dir:
        _enable_crash_dump(_log_dir)

    return root
