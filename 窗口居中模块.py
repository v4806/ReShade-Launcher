# -*- coding: utf-8 -*-
"""
窗口居中模块 - 强制将目标游戏窗口居中并持续对抗主动位移
使用 ctypes 直接调用 Win32 API，无需 pywin32
"""

import ctypes
import ctypes.wintypes
import time
import threading
import logging

logger = logging.getLogger(__name__)

# ─── Win32 API ───
user32 = ctypes.windll.user32

SM_CXSCREEN = 0
SM_CYSCREEN = 1

SWP_NOSIZE = 0x0001
SWP_NOZORDER = 0x0004
SWP_SHOWWINDOW = 0x0040
SWP_NOACTIVATE = 0x0010


class RECT(ctypes.Structure):
    _fields_ = [
        ("left",   ctypes.c_long),
        ("top",    ctypes.c_long),
        ("right",  ctypes.c_long),
        ("bottom", ctypes.c_long),
    ]


def _get_screen_size():
    """获取屏幕尺寸（GetSystemMetrics，与 GetWindowRect 同坐标系）"""
    w = user32.GetSystemMetrics(SM_CXSCREEN)
    h = user32.GetSystemMetrics(SM_CYSCREEN)
    return w, h


def _get_window_rect(hwnd):
    rect = RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return rect


def _center_window_once(hwnd):
    """尝试居中窗口一次，返回 True 表示执行了移动"""
    if hwnd == 0:
        return False
    if not user32.IsWindowVisible(hwnd):
        return False

    rect = _get_window_rect(hwnd)
    win_w = rect.right - rect.left
    win_h = rect.bottom - rect.top
    if win_w <= 0 or win_h <= 0:
        return False

    screen_w, screen_h = _get_screen_size()

    x = max(0, (screen_w - win_w) // 2)
    y = max(0, (screen_h - win_h) // 2)

    # 如果已经在中央附近（偏差 < 50px），跳过
    if abs(rect.left - x) < 50 and abs(rect.top - y) < 50:
        return False

    ok = user32.SetWindowPos(
        hwnd, 0, x, y, 0, 0,
        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
    )
    if ok:
        logger.debug(f"窗口居中: ({x}, {y}) 尺寸 ({win_w}x{win_h}) 屏幕 ({screen_w}x{screen_h})")
    return bool(ok)


def _find_window_by_pid(pid):
    """通过进程 ID 查找可见的主窗口句柄"""
    result = [0]

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_int, ctypes.c_int)
    def callback(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        window_pid = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(window_pid))
        if window_pid.value == pid:
            result[0] = hwnd
            return False
        return True

    user32.EnumWindows(callback, 0)
    return result[0]


def start_center_loop(pid, duration_seconds=15, interval=0.15):
    """
    启动后台线程，持续居中指定 PID 的窗口。
    
    Args:
        pid: 目标进程 PID
        duration_seconds: 持续守护时长（秒）
        interval: 检测间隔（秒）
    
    Returns:
        threading.Thread 对象，可调用 join() 等待结束
    """
    def _loop():
        end_time = time.time() + duration_seconds
        center_count = 0
        logger.info(f"[窗口居中] 开始守护 PID={pid}，持续 {duration_seconds} 秒")

        while time.time() < end_time:
            hwnd = _find_window_by_pid(pid)
            if hwnd != 0 and _center_window_once(hwnd):
                center_count += 1
            time.sleep(interval)

        logger.info(f"[窗口居中] 守护结束，共居中 {center_count} 次")

    thread = threading.Thread(target=_loop, daemon=True, name="WindowCenter")
    thread.start()
    return thread
