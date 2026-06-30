# -*- coding: utf-8 -*-
"""
进程管理模块
功能：
  1. 终结游戏进程（仅游戏本身）
  2. 终结软件启动链上的所有进程
  3. 进程监控机制：记录本次启动的根进程 PID，用于进程树操作
完全独立于 GUI，仅依赖标准库
（修复：退出时强制终结所有进程 + 无根进程记录时按名称强杀）
（新增：静态方法 is_process_running，用于检测指定进程是否在运行）
（修复：_get_all_child_pids 添加 visited 集合避免循环递归）
（增强：注册时同时记录 root_pid 和 target_pid，终结时优先使用 target_pid）
"""

import os
import subprocess
import threading
import time
import sys
from typing import List, Optional, Dict, Tuple

if sys.platform == "win32":
    try:
        CREATE_NO_WINDOW = subprocess.CREATE_NO_WINDOW
    except AttributeError:
        CREATE_NO_WINDOW = 0x08000000
else:
    CREATE_NO_WINDOW = 0


class ProcessManager:
    """
    进程管理器（每个软件实例独有，与当前主窗口绑定）
    """

    def __init__(self, parent=None):
        self.parent = parent
        self._launched_processes = []      # 元素: {"root_pid": int, "target_pid": int, "game_exe_name": str, "game_dir": str}
        self._lock = threading.Lock()
        self._process_tree_cache = None
        self._cache_time = 0

    def get_all_launched_processes(self) -> List[dict]:
        with self._lock:
            return self._launched_processes.copy()

    @staticmethod
    def is_process_running(process_name: str) -> bool:
        if sys.platform != "win32":
            return False
        try:
            cmd = ['tasklist', '/FI', f'IMAGENAME eq {process_name}']
            output = subprocess.check_output(
                cmd,
                universal_newlines=True,
                stderr=subprocess.DEVNULL,
                creationflags=CREATE_NO_WINDOW
            )
            if process_name in output and "No tasks are running" not in output:
                return True
        except Exception:
            pass
        return False

    def terminate_all_launched_processes(self):
        with self._lock:
            processes = self._launched_processes.copy()

        for proc in processes:
            game_exe_name = proc["game_exe_name"]
            game_dir = proc["game_dir"]
            target_pid = proc.get("target_pid")
            root_pid = proc.get("root_pid")

            # 优先杀目标进程
            if target_pid is not None and target_pid != root_pid:
                try:
                    cmd = f'taskkill /F /PID {target_pid}'
                    subprocess.run(cmd, shell=True, check=False,
                                   capture_output=True, creationflags=CREATE_NO_WINDOW)
                    print(f"[进程管理] 已终结目标进程 PID={target_pid}")
                except Exception as e:
                    print(f"[进程管理] 终结目标进程失败: {e}")

            # 杀根进程树
            if root_pid is not None:
                self._kill_process_tree(root_pid)
            else:
                try:
                    cmd = f'taskkill /F /IM {game_exe_name}'
                    subprocess.run(cmd, shell=True, check=False,
                                   capture_output=True, creationflags=CREATE_NO_WINDOW)
                    print(f"[进程管理] 已按名称强制终结: {game_exe_name}")
                except Exception as e:
                    print(f"[进程管理] 按名称终结失败: {e}")

            # ❌ 已删除 ReShade 备份恢复的调用

        with self._lock:
            self._launched_processes.clear()

        try:
            subprocess.run('taskkill /F /IM injector.exe', shell=True, check=False,
                           capture_output=True, creationflags=CREATE_NO_WINDOW)
            print("[进程管理] 已清理 injector.exe（若存在）")
        except Exception:
            pass

    def _build_process_tree(self) -> Dict[int, List[int]]:
        now = time.time()
        if self._process_tree_cache is not None and now - self._cache_time < 1.0:
            return self._process_tree_cache
        tree = {}
        try:
            ps_cmd = (
                'powershell -NoProfile -Command '
                '"Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId | '
                'ConvertTo-Csv -NoTypeInformation"'
            )
            output = subprocess.check_output(
                ps_cmd, shell=True, universal_newlines=True,
                stderr=subprocess.DEVNULL, timeout=5,
                creationflags=CREATE_NO_WINDOW
            )
            lines = output.strip().split('\n')
            for line in lines[1:]:
                if not line.strip():
                    continue
                parts = line.split(',')
                if len(parts) >= 2:
                    try:
                        pid = int(parts[0].strip('"'))
                        ppid = int(parts[1].strip('"'))
                        if pid > 0 and ppid > 0 and pid != ppid:
                            tree.setdefault(ppid, []).append(pid)
                    except:
                        continue
        except Exception:
            pass
        if not tree:
            try:
                cmd = 'wmic process get ProcessId,ParentProcessId /FORMAT:CSV'
                output = subprocess.check_output(
                    cmd, shell=True, universal_newlines=True,
                    stderr=subprocess.DEVNULL, timeout=3,
                    creationflags=CREATE_NO_WINDOW
                )
                lines = output.strip().split('\n')
                for line in lines[1:]:
                    if not line.strip():
                        continue
                    parts = line.split(',')
                    if len(parts) >= 3:
                        try:
                            parent_pid = int(parts[1].strip('"'))
                            child_pid = int(parts[2].strip('"'))
                            if parent_pid > 0 and child_pid > 0 and child_pid != parent_pid:
                                tree.setdefault(parent_pid, []).append(child_pid)
                        except:
                            continue
            except Exception:
                pass
        self._process_tree_cache = tree
        self._cache_time = now
        return tree

    def _get_all_child_pids(self, parent_pid: int, visited: set = None) -> List[int]:
        if visited is None:
            visited = set()
        if parent_pid in visited:
            return []
        visited.add(parent_pid)

        result = []
        tree = self._build_process_tree()
        children = tree.get(parent_pid, [])
        for child in children:
            if child not in visited:
                result.append(child)
                result.extend(self._get_all_child_pids(child, visited))
        return result

    def register_launch(self, root_pid: int, target_pid: int, game_exe_name: str, game_dir: str):
        with self._lock:
            self._launched_processes = [
                p for p in self._launched_processes
                if not (p["game_exe_name"] == game_exe_name and p["game_dir"] == game_dir)
            ]
            self._launched_processes.append({
                "root_pid": root_pid,
                "target_pid": target_pid,
                "game_exe_name": game_exe_name,
                "game_dir": game_dir
            })
            print(f"[进程管理] 已注册根进程: PID={root_pid}, 目标PID={target_pid}, EXE={game_exe_name}, DIR={game_dir}")

    def _get_root_pid_by_game(self, game_exe_name: str, game_dir: str) -> Optional[int]:
        with self._lock:
            for p in self._launched_processes:
                if p["game_exe_name"] == game_exe_name and p["game_dir"] == game_dir:
                    return p["root_pid"]
        return None

    def _get_game_pid_from_root(self, root_pid: int, game_exe_name: str) -> Optional[int]:
        all_pids = self._get_all_child_pids(root_pid)
        all_pids.append(root_pid)
        for pid in all_pids:
            try:
                cmd = f'tasklist /FI "PID eq {pid}" /FO CSV'
                output = subprocess.check_output(
                    cmd, shell=True, universal_newlines=True,
                    stderr=subprocess.DEVNULL, creationflags=CREATE_NO_WINDOW
                )
                if game_exe_name.lower() in output.lower():
                    return pid
            except:
                continue
        return None

    def _kill_process_tree(self, root_pid: int):
        try:
            cmd = f'taskkill /F /T /PID {root_pid}'
            subprocess.run(
                cmd, shell=True, check=False, capture_output=True,
                creationflags=CREATE_NO_WINDOW
            )
            print(f"[进程管理] 已发送终结进程树命令: PID={root_pid}")
        except Exception as e:
            print(f"[进程管理] 终结进程树失败: {e}")

    def terminate_software_chain(self, game_exe_name: str, game_dir: str) -> bool:
        # ❌ 已删除部署状态检查和备份恢复
        # 直接进行进程终结

        # 查找对应的进程记录
        record = None
        with self._lock:
            for p in self._launched_processes:
                if p["game_exe_name"] == game_exe_name and p["game_dir"] == game_dir:
                    record = p
                    break

        if record is None:
            print(f"[进程管理] 未找到进程记录，尝试按名称强杀: {game_exe_name}")
            try:
                cmd = f'taskkill /F /IM {game_exe_name}'
                subprocess.run(cmd, shell=True, check=False, capture_output=True,
                            creationflags=CREATE_NO_WINDOW)
                print(f"[进程管理] 已按名称强制终结: {game_exe_name}")
                return True
            except Exception as e:
                print(f"[进程管理] 按名称终结失败: {e}")
                return False

        root_pid = record.get("root_pid")
        target_pid = record.get("target_pid")

        # 1. 优先杀目标进程（真正的游戏进程）
        if target_pid is not None and target_pid != root_pid:
            try:
                cmd = f'taskkill /F /PID {target_pid}'
                subprocess.run(cmd, shell=True, check=False, capture_output=True,
                            creationflags=CREATE_NO_WINDOW)
                print(f"[进程管理] 已直接终结目标进程 PID={target_pid}")
            except Exception as e:
                print(f"[进程管理] 杀目标进程失败: {e}")

        # 2. 再杀根进程树（确保整个启动链退出）
        if root_pid is not None:
            self._kill_process_tree(root_pid)

        # 3. 从记录中移除
        with self._lock:
            self._launched_processes = [
                p for p in self._launched_processes
                if not (p["game_exe_name"] == game_exe_name and p["game_dir"] == game_dir)
            ]

        return True

    def terminate_game_process(self, game_exe_name: str, game_dir: str, game_pid: int = None) -> bool:
        # 极速路径：直接杀指定PID
        if game_pid is not None:
            try:
                cmd = f'taskkill /F /PID {game_pid}'
                subprocess.run(cmd, shell=True, check=False, capture_output=True,
                               creationflags=CREATE_NO_WINDOW)
                print(f"[进程管理] ✅ 已直接终结游戏进程 PID={game_pid}")
                with self._lock:
                    self._launched_processes = [
                        p for p in self._launched_processes
                        if not (p["game_exe_name"] == game_exe_name and p["game_dir"] == game_dir)
                    ]
                return True
            except Exception as e:
                print(f"[进程管理] ⚠️ 直接杀PID失败，降级到传统方法: {e}")

        # 查找记录中的 target_pid
        with self._lock:
            for p in self._launched_processes:
                if p["game_exe_name"] == game_exe_name and p["game_dir"] == game_dir:
                    target_pid = p.get("target_pid")
                    if target_pid is not None and target_pid != p["root_pid"]:
                        try:
                            cmd = f'taskkill /F /PID {target_pid}'
                            subprocess.run(cmd, shell=True, check=False, capture_output=True,
                                           creationflags=CREATE_NO_WINDOW)
                            print(f"[进程管理] ✅ 已根据记录终结游戏进程 PID={target_pid}")
                            return True
                        except Exception as e:
                            print(f"[进程管理] ⚠️ 杀目标PID失败: {e}")
                    # 如果没有 target_pid 或杀失败，则使用 root_pid 查找
                    root_pid = p["root_pid"]
                    game_pid = self._get_game_pid_from_root(root_pid, game_exe_name)
                    if game_pid is not None:
                        try:
                            cmd = f'taskkill /F /PID {game_pid}'
                            subprocess.run(cmd, shell=True, check=False, capture_output=True,
                                           creationflags=CREATE_NO_WINDOW)
                            print(f"[进程管理] 已通过进程树终结游戏进程 PID={game_pid}")
                            return True
                        except Exception as e:
                            print(f"[进程管理] 终结失败: {e}")
                    break  # 找到记录但无法终结，跳出

        # 保底：按进程名强杀
        try:
            cmd = f'taskkill /F /IM {game_exe_name}'
            subprocess.run(cmd, shell=True, check=False, capture_output=True,
                           creationflags=CREATE_NO_WINDOW)
            print(f"[进程管理] 已按名称强制终结: {game_exe_name}")
            return True
        except Exception as e:
            print(f"[进程管理] 按名称终结失败: {e}")
            return False