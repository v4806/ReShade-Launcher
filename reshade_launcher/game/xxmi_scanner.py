# -*- coding: utf-8 -*-
"""
XXMI 游戏扫描器 - 移植自特定游戏扫描器.py
提供三级扫描策略：快速扫描 → 深度扫描 → 全盘扫描
独立于UI，通过信号返回结果
"""
import os
import sys
import threading
from PyQt6.QtCore import QObject, pyqtSignal

class XXMIGameScanner(QObject):
    """
    XXMI 游戏扫描器
    信号：
        found_signal(str): 找到目标文件时发送完整路径
        finished_signal(): 扫描完成（无论是否找到）
        progress_signal(str): 进度信息（可选）
    """
    found_signal = pyqtSignal(str)
    finished_signal = pyqtSignal()
    progress_signal = pyqtSignal(str)

    # 硬编码游戏信息（与特定游戏扫描器.py保持一致）
    _GAMES = [
        {"exe": "YuanShen.exe",          "name": "原神",          "publisher": "米哈游"},
        {"exe": "GenshinImpact.exe",     "name": "原神国际服",    "publisher": "米哈游"},
        {"exe": "BH3.exe",              "name": "崩坏3",         "publisher": "米哈游"},
        {"exe": "StarRail.exe",         "name": "崩坏：星穹铁道","publisher": "米哈游"},
        {"exe": "ZenlessZoneZero.exe",  "name": "绝区零",        "publisher": "米哈游"},
        {"exe": "Client-Win64-Shipping.exe", "name": "鸣潮",     "publisher": "库洛游戏"},
        {"exe": "Endfield.exe",         "name": "明日方舟：终末地","publisher": "鹰角网络"},
    ]

    # 需要跳过的系统目录（递归搜索时忽略）
    _SKIP_DIRS = [
        "$RECYCLE.BIN",
        "System Volume Information",
        "Windows",
        "ProgramData",
        "Recovery",
        "Boot",
        "System32",
        "SysWOW64",
        "WinSxS",
        "AppData",          # 用户临时目录，通常不存放游戏
        "Application Data",
        "Local Settings",
        "Temp",
        "tmp",
        "node_modules",     # 开发目录
        ".git",
        ".svn",
        "Cache",
        "Logs"
    ]

    def __init__(self, parent=None):
        super().__init__(parent)
        self.scanning = False
        self._stop_flag = False
        # 建立 exe -> game_info 映射，方便快速查找
        self._game_map = {g["exe"]: g for g in self._GAMES}

    def get_game_info_by_exe(self, exe_name: str) -> dict:
        """根据可执行文件名获取游戏信息"""
        return self._game_map.get(exe_name)

    def get_common_paths(self, game_info: dict) -> list:
        """获取游戏的常见安装路径（完整路径到exe）"""
        exe_name = game_info["exe"]
        publisher = game_info["publisher"]
        common_paths = []

        # 获取所有可用驱动器
        drives = []
        if sys.platform == "win32":
            import string
            for drive in string.ascii_uppercase:
                drive_path = f"{drive}:\\"
                if os.path.exists(drive_path):
                    drives.append(drive_path)

        # 根据厂商和游戏名生成常见路径
        if publisher == "米哈游":
            if exe_name == "YuanShen.exe":
                for d in drives:
                    common_paths.extend([
                        f"{d}Program Files\\Genshin Impact\\Genshin Impact Game\\{exe_name}",
                        f"{d}Program Files (x86)\\Genshin Impact\\Genshin Impact Game\\{exe_name}",
                        f"{d}Program Files\\HoYoverse\\Genshin Impact\\Genshin Impact Game\\{exe_name}",
                        f"{d}Program Files\\miHoYo Launcher\\games\\Genshin Impact Game\\{exe_name}",
                        f"{d}Games\\Genshin Impact\\Genshin Impact Game\\{exe_name}",
                        f"{d}Genshin Impact\\Genshin Impact Game\\{exe_name}"
                    ])
            elif exe_name == "GenshinImpact.exe":
                for d in drives:
                    common_paths.extend([
                        f"{d}Program Files\\Genshin Impact\\Genshin Impact Game\\{exe_name}",
                        f"{d}Program Files (x86)\\Genshin Impact\\Genshin Impact Game\\{exe_name}",
                        f"{d}Program Files\\HoYoverse\\Genshin Impact\\Genshin Impact Game\\{exe_name}",
                        f"{d}Games\\Genshin Impact\\Genshin Impact Game\\{exe_name}"
                    ])
            elif exe_name == "BH3.exe":
                for d in drives:
                    common_paths.extend([
                        f"{d}Program Files\\崩坏3\\Games\\{exe_name}",
                        f"{d}Program Files (x86)\\崩坏3\\Games\\{exe_name}",
                        f"{d}Program Files\\Honkai Impact 3\\Games\\{exe_name}",
                        f"{d}Program Files\\miHoYo Launcher\\games\\Honkai Impact 3rd Game\\{exe_name}",
                        f"{d}Games\\崩坏3\\Games\\{exe_name}"
                    ])
            elif exe_name == "StarRail.exe":
                for d in drives:
                    common_paths.extend([
                        f"{d}Program Files\\Star Rail\\Game\\{exe_name}",
                        f"{d}Program Files (x86)\\Star Rail\\Game\\{exe_name}",
                        f"{d}Program Files\\HoYoverse\\Star Rail\\Game\\{exe_name}",
                        f"{d}Program Files\\miHoYo Launcher\\games\\Star Rail Game\\{exe_name}",
                        f"{d}Games\\Star Rail\\Game\\{exe_name}"
                    ])
            elif exe_name == "ZenlessZoneZero.exe":
                for d in drives:
                    common_paths.extend([
                        f"{d}Program Files\\HoYoPlay\\games\\ZenlessZoneZero\\Game\\{exe_name}",
                        f"{d}Program Files (x86)\\HoYoPlay\\games\\ZenlessZoneZero\\Game\\{exe_name}",
                        f"{d}Program Files\\miHoYo Launcher\\games\\ZenlessZoneZero Game\\{exe_name}",
                        f"{d}Games\\ZenlessZoneZero\\Game\\{exe_name}"
                    ])
        elif publisher == "库洛游戏":
            if exe_name == "Client-Win64-Shipping.exe":
                for d in drives:
                    common_paths.extend([
                        f"{d}Program Files\\Wuthering Waves\\Wuthering Waves Game\\{exe_name}",
                        f"{d}Program Files (x86)\\Wuthering Waves\\Wuthering Waves Game\\{exe_name}",
                        f"{d}Games\\Wuthering Waves\\Wuthering Waves Game\\{exe_name}",
                        f"{d}Wuthering Waves\\Wuthering Waves Game\\{exe_name}"
                    ])
        elif publisher == "鹰角网络":
            if exe_name == "Endfield.exe":
                for d in drives:
                    common_paths.extend([
                        f"{d}Program Files\\ArknightsEndfield\\{exe_name}",
                        f"{d}Program Files (x86)\\ArknightsEndfield\\{exe_name}",
                        f"{d}Games\\ArknightsEndfield\\{exe_name}",
                        f"{d}明日方舟终末地\\{exe_name}",
                        f"{d}ArknightsEndfield\\{exe_name}"
                    ])

        return common_paths

    def get_publisher_dirs(self, publisher: str) -> list:
        """获取游戏厂商的常见目录（用于深度扫描）"""
        dirs = []
        drives = []
        if sys.platform == "win32":
            import string
            for drive in string.ascii_uppercase:
                drive_path = f"{drive}:\\"
                if os.path.exists(drive_path):
                    drives.append(drive_path)

        for d in drives:
            if publisher == "米哈游":
                dirs.extend([
                    f"{d}Program Files\\Genshin Impact",
                    f"{d}Program Files (x86)\\Genshin Impact",
                    f"{d}Program Files\\HoYoverse",
                    f"{d}Program Files\\miHoYo Launcher",
                    f"{d}Program Files\\Honkai Impact 3",
                    f"{d}Program Files\\Star Rail",
                    f"{d}Program Files\\HoYoPlay",
                    f"{d}Games\\Genshin Impact",
                    f"{d}Games\\HoYoverse"
                ])
            elif publisher == "库洛游戏":
                dirs.extend([
                    f"{d}Program Files\\Wuthering Waves",
                    f"{d}Program Files (x86)\\Wuthering Waves",
                    f"{d}Games\\Wuthering Waves"
                ])
            elif publisher == "鹰角网络":
                dirs.extend([
                    f"{d}Program Files\\ArknightsEndfield",
                    f"{d}Program Files (x86)\\ArknightsEndfield",
                    f"{d}Games\\ArknightsEndfield",
                    f"{d}明日方舟终末地"
                ])
        return dirs

    def recursive_search_dir(self, start_dir: str, target_file: str, max_depth: int, current_depth=0) -> str:
        """
        递归搜索目录，返回第一个匹配的完整路径，未找到返回 None
        """
        if not self.scanning or self._stop_flag:
            return None
        if current_depth > max_depth:
            return None

        try:
            with os.scandir(start_dir) as entries:
                for entry in entries:
                    if not self.scanning or self._stop_flag:
                        return None

                    # 检查是否为目标文件
                    if entry.is_file() and entry.name.lower() == target_file.lower():
                        return entry.path

                    # 如果是目录，继续递归
                    if entry.is_dir():
                        # 跳过系统目录
                        skip = False
                        for skip_dir in self._SKIP_DIRS:
                            if skip_dir.lower() in entry.name.lower():
                                skip = True
                                break
                        if skip:
                            continue
                        # 递归深度加1
                        found = self.recursive_search_dir(
                            entry.path, target_file, max_depth, current_depth + 1
                        )
                        if found:
                            return found
        except (PermissionError, OSError):
            # 无权限访问的目录直接跳过
            pass
        return None

    def _scan_extra_paths(self, extra_paths: list, target_exe: str) -> str:
        """
        扫描额外路径列表（快速扫描的第二阶段）
        允许进入以下子目录（不区分大小写）：
            'game', 'bin', 'steamapps', 'common', 'Games', 'games', 以及目标exe不含扩展名的文件夹名
        限制深度为2（即根目录下最多进入两层子目录）
        """
        allowed = [
            'game', 'bin', 'steamapps', 'common', 'Games', 'games',
            os.path.splitext(target_exe)[0].lower()
        ]

        for path in extra_paths:
            if not os.path.isdir(path):
                continue
            try:
                # 使用 os.walk 控制深度
                base_depth = path.count(os.sep)
                for root, dirs, files in os.walk(path, topdown=True):
                    if not self.scanning or self._stop_flag:
                        return None
                    # 检查目标文件
                    if target_exe in files:
                        return os.path.join(root, target_exe)
                    # 限制子目录
                    current_depth = root.count(os.sep) - base_depth
                    if current_depth >= 2:
                        dirs.clear()
                    else:
                        # 只保留允许进入的子目录
                        dirs[:] = [d for d in dirs if d.lower() in allowed]
            except Exception:
                continue
        return None

    def _three_stage_scan(self, target_exe: str, extra_paths: list = None):
        """
        三级扫描主逻辑（在子线程中执行）
        """
        self.scanning = True
        self._stop_flag = False

        # 获取游戏信息（如果已知）
        game_info = self.get_game_info_by_exe(target_exe)

        # ---------- 第一阶段：快速扫描（常见路径）----------
        self.progress_signal.emit("🚀 第一阶段：快速扫描（常见路径）")
        if game_info:
            common_paths = self.get_common_paths(game_info)
            for path in common_paths:
                if not self.scanning or self._stop_flag:
                    break
                if os.path.isfile(path):
                    self.found_signal.emit(path)
                    self.finished_signal.emit()
                    return

        # ---------- 快速扫描第二阶段：额外路径（来自XXMI启动器）----------
        if extra_paths:
            self.progress_signal.emit("📂 快速扫描（额外目录）")
            found = self._scan_extra_paths(extra_paths, target_exe)
            if found:
                self.found_signal.emit(found)
                self.finished_signal.emit()
                return

        # ---------- 第二阶段：深度扫描（厂商目录）----------
        if game_info:
            self.progress_signal.emit("🔍 第二阶段：深度扫描（厂商目录）")
            publisher = game_info["publisher"]
            publisher_dirs = self.get_publisher_dirs(publisher)
            for pub_dir in publisher_dirs:
                if not self.scanning or self._stop_flag:
                    break
                if os.path.isdir(pub_dir):
                    found = self.recursive_search_dir(pub_dir, target_exe, max_depth=3)
                    if found:
                        self.found_signal.emit(found)
                        self.finished_signal.emit()
                        return

        # ---------- 第三阶段：全盘扫描----------
        self.progress_signal.emit("🌐 第三阶段：全盘扫描（所有驱动器）")
        drives = []
        if sys.platform == "win32":
            import string
            for drive in string.ascii_uppercase:
                drive_path = f"{drive}:\\"
                if os.path.exists(drive_path):
                    drives.append(drive_path)

        for drive in drives:
            if not self.scanning or self._stop_flag:
                break
            found = self.recursive_search_dir(drive, target_exe, max_depth=5)
            if found:
                self.found_signal.emit(found)
                self.finished_signal.emit()
                return

        # 未找到任何文件
        self.finished_signal.emit()

    def scan(self, target_exe: str, extra_paths: list = None):
        """
        启动扫描（非阻塞）
        :param target_exe: 目标可执行文件名，例如 "YuanShen.exe"
        :param extra_paths: 额外需要扫描的目录列表（可选）
        """
        if self.scanning:
            return
        # 启动扫描线程
        thread = threading.Thread(
            target=self._three_stage_scan,
            args=(target_exe, extra_paths),
            daemon=True
        )
        thread.start()

    def stop(self):
        """停止当前扫描"""
        self._stop_flag = True
        self.scanning = False