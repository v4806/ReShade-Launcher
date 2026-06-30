# 文件名：注入启动模块.py
# 功能：负责将DLL注入到游戏进程并启动目标程序
# 包含：配置验证、DLL列表构建、实际启动（子线程）
# （已适配打包环境，增加返回目标进程PID）
# （修复：为 Popen 调用添加 CREATE_NO_WINDOW + STARTUPINFO 隐藏 injector.exe 控制台窗口）
# （增强：支持从 PyInstaller 临时目录（sys._MEIPASS）查找 injector.exe、ReShade64.dll、version.json）
# （增强：强制 ReShade64.dll 为注入列表首位 + 自动转换包含空格的路径为短路径名）
# （优化：使用新版 injector.exe 集成启动逻辑，不再手动启动游戏）
# （增强：返回 (game_pid, game_pid) 元组，game_pid 为实际游戏进程 PID）
# （修改：XXMI模式直接启动XXMI Launcher，跳过注入器）

import os
import sys
import subprocess
import shlex
import threading
import json
import time
import ctypes
from ctypes import wintypes
import urllib.request
import tempfile
import winreg
# ---------- 进程树检测（依赖 pywin32，可选）----------
try:
    import win32process
    import win32api
    import win32con
    WIN32_AVAILABLE = True
except ImportError:
    WIN32_AVAILABLE = False
    print("[注入启动] 警告：未安装 pywin32，将无法精确获取游戏进程 PID，将使用启动器 PID 代替。")
# ----------------------------------------------------

# 定义用于隐藏控制台窗口的常量（Windows）
if sys.platform == "win32":
    try:
        CREATE_NO_WINDOW = subprocess.CREATE_NO_WINDOW   # Python 3.7+
    except AttributeError:
        CREATE_NO_WINDOW = 0x08000000                   # 手动指定
    SW_HIDE = 0                                         # 隐藏窗口
    STARTF_USESHOWWINDOW = 0x00000001                  # 使用 wShowWindow 标志

    # ---------- Windows API: 获取短路径名（解决路径含空格问题）----------
    _GetShortPathNameW = ctypes.windll.kernel32.GetShortPathNameW
    _GetShortPathNameW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.DWORD]
    _GetShortPathNameW.restype = wintypes.DWORD

    def get_short_path(long_path):
        """将长路径（可能含空格）转换为短路径名（8.3格式），失败返回原路径"""
        if not long_path or ' ' not in long_path:
            return long_path
        buffer_size = _GetShortPathNameW(long_path, None, 0)
        if buffer_size == 0:
            return long_path
        buffer = ctypes.create_unicode_buffer(buffer_size)
        _GetShortPathNameW(long_path, buffer, buffer_size)
        return buffer.value
    # ----------------------------------------------------------------
else:
    CREATE_NO_WINDOW = 0
    SW_HIDE = 0
    STARTF_USESHOWWINDOW = 0
    def get_short_path(long_path):
        return long_path


def _get_injector_path(script_dir):
    """
    获取 injector.exe 的完整路径，支持打包环境下的备选目录。
    优先级：
      1. script_dir/injector.exe（应用程序根目录）
      2. sys._MEIPASS/injector.exe（PyInstaller 临时解压目录）
    若均不存在，返回 None。
    """
    primary = os.path.join(script_dir, "injector.exe")
    if os.path.exists(primary):
        return primary

    if hasattr(sys, '_MEIPASS'):
        meipass = sys._MEIPASS
        secondary = os.path.join(meipass, "injector.exe")
        if os.path.exists(secondary):
            return secondary

    return None


def load_version_config(script_dir):
    """加载 version.json 配置文件（支持主目录及打包临时目录）"""
    version_path = os.path.join(script_dir, "version.json")
    if not os.path.exists(version_path) and hasattr(sys, '_MEIPASS'):
        version_path = os.path.join(sys._MEIPASS, "version.json")
    try:
        with open(version_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        print(f"[注入启动] 加载 version.json 失败: {e}")
        return {}


def _normalize_path(path):
    """统一为正斜杠，提高可读性（不影响实际调用）"""
    if path:
        return path.replace('\\', '/')
    return path


def _find_game_pid_by_name(game_exe_name: str, timeout: float = 10.0) -> int:
    """
    通过进程名查找游戏进程 PID。
    若超时仍未找到，返回 0。
    """
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            if sys.platform != "win32":
                return 0
            cmd = ['tasklist', '/FI', f'IMAGENAME eq {game_exe_name}', '/FO', 'CSV']
            output = subprocess.check_output(
                cmd,
                universal_newlines=True,
                stderr=subprocess.DEVNULL,
                creationflags=CREATE_NO_WINDOW
            )
            # 解析 CSV 输出，格式："映像名称","PID","会话名","会话#","内存使用"
            import csv
            from io import StringIO
            reader = csv.reader(StringIO(output))
            rows = list(reader)
            if len(rows) > 1:  # 跳过标题行
                for row in rows[1:]:
                    if len(row) >= 2:
                        pid_str = row[1].strip('"')
                        if pid_str.isdigit():
                            return int(pid_str)
        except Exception as e:
            print(f"[注入启动] 查找进程 PID 出错: {e}")
        time.sleep(0.5)
    return 0


def validate_launch(config, script_dir):
    """
    验证启动所需文件是否存在
    script_dir: 应用程序根目录（exe所在目录）
    返回 (是否成功, 错误信息)
    """
    mode = config.get('mode')
    
    # 所有模式（含XXMI）都使用注入器 + DLL 注入方式
    # 检查注入器和DLL
    injector_path = _get_injector_path(script_dir)
    if not injector_path or not os.path.exists(injector_path):
        return False, f"找不到注入器程序: injector.exe（已检查主目录及打包临时目录）"

    launch_program = config.get('launch_program') or config.get('game_dir')
    if not launch_program or not os.path.exists(launch_program):
        return False, f"启动程序不存在: {launch_program}"

    dll_list = _build_dll_list(config, script_dir, check_exists=True)
    missing_dlls = [dll for dll in dll_list if not os.path.exists(dll)]
    if missing_dlls:
        return False, f"以下 DLL 文件缺失: {', '.join(missing_dlls)}"

    return True, ""


def launch_game(config, script_dir, version_config):
    """
    在后台线程中启动游戏（非阻塞）
    script_dir: 应用程序根目录（exe所在目录）
    返回：(root_pid, target_pid) 元组，若启动失败返回 (None, None)
    """
    def _launch_task():
        try:
            mode = config.get('mode')
            
            # ========== 所有模式（含XXMI）统一使用 injector.exe 注入 ==========
            dll_paths = _build_dll_list(config, script_dir, check_exists=False)
            dll_paths = [_normalize_path(p) for p in dll_paths]
            if not dll_paths:
                print("[注入启动] 警告：没有需要注入的 DLL，将直接启动游戏而不注入")

            launch_program = config.get('launch_program') or config.get('game_dir')
            target_exe_name = config.get('game_exe_name') or os.path.basename(config.get('game_dir', ''))
            launch_args_str = config.get('launch_args', '')

            # ========== 构建完整的启动命令行（供 injector 使用）==========
            launch_program_quoted = f'"{launch_program}"'
            if launch_args_str:
                full_cmdline = f"{launch_program_quoted} {launch_args_str}"
            else:
                full_cmdline = launch_program_quoted

            # ========== 调用 injector.exe ==========
            injector_path = _get_injector_path(script_dir)
            if not injector_path:
                raise FileNotFoundError("找不到 injector.exe，请检查安装完整性")

            injector_cmd = [injector_path] + dll_paths + [target_exe_name, full_cmdline]

            # 优化日志输出，清晰分隔各部分
            print("[注入启动] ========== 注入器调用详情 ==========")
            print(f"[注入启动] 注入器路径: {injector_path}")
            print(f"[注入启动] 待注入 DLL 列表: {dll_paths}")
            print(f"[注入启动] 目标进程名: {target_exe_name}")
            print(f"[注入启动] 启动命令行: {full_cmdline}")
            print("[注入启动] ========================================")

            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = SW_HIDE
            injector_proc = subprocess.Popen(
                injector_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                startupinfo=startupinfo,
                creationflags=CREATE_NO_WINDOW
            )

            try:
                stdout, stderr = injector_proc.communicate(timeout=30)
                if injector_proc.returncode != 0:
                    print(f"[注入启动] 注入器返回错误码 {injector_proc.returncode}")
                    print(f"[注入启动] 错误输出: {stderr.decode('utf-8', errors='ignore')}")
                    return None, None
                else:
                    print("[注入启动] 注入器成功完成")
            except subprocess.TimeoutExpired:
                injector_proc.kill()
                injector_proc.wait()
                print("[注入启动] 注入器执行超时，已终止")
                return None, None

            # ========== 查找游戏进程 PID ==========
            game_pid = _find_game_pid_by_name(target_exe_name, timeout=10.0)
            if game_pid == 0:
                print(f"[注入启动] 无法找到游戏进程 {target_exe_name} 的 PID")
                return None, None

            print(f"[注入启动] 游戏进程 PID: {game_pid}")
            return game_pid, game_pid

        except Exception as e:
            print(f"[注入启动] 启动过程异常: {e}")
            return None, None

    return _launch_task()


def _build_dll_list(config, script_dir, check_exists=False):
    """
    根据配置构建需要注入的 DLL 文件列表（完整路径）
    ★ 强制 ReShade64.dll 为列表首位（使用 insert(0)）
    ★ 自动转换包含空格的路径为短路径名，避免注入器解析失败
    注入顺序：
    1. ReShade64.dll       —— 始终在第一位
    2. d3d11.dll          —— 如果 config 中包含 'd3d11_path' 键
    3. 自定义 DLL 列表    —— 如果 config 中包含 'dll_files' 键
    如果 check_exists=True，返回的列表中只会包含实际存在的文件
    """
    dlls = []

    # 1. ReShade64.dll（任何模式均可启用）
    if config.get('reshade_dll'):
        reshade_path = os.path.join(script_dir, "ReShade", "ReShade64.dll")
        if not os.path.exists(reshade_path) and hasattr(sys, '_MEIPASS'):
            reshade_path = os.path.join(sys._MEIPASS, "ReShade", "ReShade64.dll")
        reshade_path = get_short_path(reshade_path)
        if not check_exists or os.path.exists(reshade_path):
            dlls.insert(0, reshade_path)
            # print(f"[注入启动] 添加 ReShade64.dll (首位): {reshade_path}")
        else:
            print(f"[注入启动] 警告: ReShade64.dll 不存在 - {reshade_path}")

    # 2. 内置模式的 d3d11.dll
    if config.get('d3d11_path'):
        d3d11_path = config['d3d11_path']
        d3d11_path = get_short_path(d3d11_path)
        if not check_exists or os.path.exists(d3d11_path):
            dlls.append(d3d11_path)
            # print(f"[注入启动] 添加 d3d11.dll: {d3d11_path}")
        else:
            print(f"[注入启动] 警告: d3d11.dll 不存在 - {d3d11_path}")

    # 3. 自定义 DLL 列表
    if config.get('dll_files'):
        for dll in config['dll_files']:
            dll = get_short_path(dll)
            if not check_exists or os.path.exists(dll):
                dlls.append(dll)
                # print(f"[注入启动] 添加自定义 DLL: {dll}")
            else:
                print(f"[注入启动] 警告: 自定义 DLL 不存在 - {dll}")

    return dlls

def is_vc_redist_installed():
    """检查 VC++ 2015-2022 Redistributable x64 是否已安装"""
    # 方法1：检查关键 DLL 是否存在
    system32 = os.path.join(os.environ.get('SystemRoot', 'C:\\Windows'), 'System32', 'msvcp140.dll')
    if os.path.exists(system32):
        return True
    # 方法2：检查注册表
    try:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64")
        installed, _ = winreg.QueryValueEx(key, "Installed")
        return installed == 1
    except Exception:
        pass
    return False

def download_vc_redist(dest_path):
    """下载 VC++ 运行库安装程序到指定路径，返回成功与否"""
    url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    try:
        urllib.request.urlretrieve(url, dest_path)
        return True
    except Exception as e:
        print(f"下载 VC++ 运行库失败: {e}")
        return False

def install_vc_redist(exe_path):
    """静默安装 VC++ 运行库，返回成功与否"""
    try:
        # 使用 /quiet /norestart 静默安装，等待完成
        result = subprocess.run([exe_path, '/quiet', '/norestart'], 
                                capture_output=True, timeout=300)
        return result.returncode == 0
    except Exception as e:
        print(f"安装 VC++ 运行库失败: {e}")
        return False

def ensure_vc_redist(progress_callback=None):
    """
    确保 VC++ 运行库已安装，如果未安装则尝试自动下载安装。
    progress_callback 可选，用于接收状态字符串。
    返回 True 表示已就绪，False 表示无法安装。
    """
    if is_vc_redist_installed():
        return True

    if progress_callback:
        progress_callback("检测到 VC++ 运行库缺失，正在下载安装程序...")

    temp_dir = tempfile.gettempdir()
    installer_path = os.path.join(temp_dir, "vc_redist.x64.exe")
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