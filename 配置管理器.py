# 配置管理器.py
# （已适配打包环境）
# 修改：XXMI模式不再保存dll信息，改为修改XXMI Launcher Config.json

import os
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# 桌面快捷方式依赖（可选）
try:
    import winshell
    from win32com.client import Dispatch
    SHORTCUT_AVAILABLE = True
except ImportError:
    SHORTCUT_AVAILABLE = False
    print("[配置管理器] 未安装 winshell 或 pywin32，桌面快捷功能不可用。")


class ConfigManager:
    """配置管理器，处理所有与配置文件相关的逻辑"""
    
    def __init__(self, base_dir: str = None):
        """
        初始化配置管理器
        
        Args:
            base_dir: 应用程序根目录（exe所在目录或脚本所在目录）。
                     如果为 None，则使用当前脚本所在目录。
        """
        if base_dir is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
        
        self.base_dir = base_dir
        self.launch_config_dir = os.path.join(base_dir, "launch_config")
        self.mod_loader_dir = os.path.join(base_dir, "MOD_loader")
        
        # 确保目录存在
        self._ensure_directories()
    
    def _ensure_directories(self):
        """确保必要的目录存在"""
        os.makedirs(self.launch_config_dir, exist_ok=True)
        os.makedirs(self.mod_loader_dir, exist_ok=True)
    
    def validate_xxmi_exe(self, file_path: str) -> bool:
        """验证是否为有效的XXMI Launcher.exe文件"""
        filename = os.path.basename(file_path)
        return filename.lower() == "xxmi launcher.exe"
    
    def validate_exe_file(self, file_path: str) -> bool:
        """验证是否为有效的.exe文件"""
        return file_path.lower().endswith('.exe')
    
    def validate_dll_file(self, file_path: str) -> bool:
        """验证是否为有效的.dll文件"""
        return file_path.lower().endswith('.dll')
    
    def get_game_name_from_exe(self, exe_path: str) -> str:
        """从exe文件路径中提取游戏名（不带扩展名）"""
        filename = os.path.basename(exe_path)
        return os.path.splitext(filename)[0]
    
    def get_config_path(self, config_name: str) -> str:
        """获取配置文件的完整路径"""
        return os.path.join(self.launch_config_dir, f"{config_name}.json")
    
    def get_all_config_files(self) -> List[str]:
        """获取所有配置文件（.json）的文件名列表，按名称排序"""
        config_files = []
        if os.path.exists(self.launch_config_dir):
            for file in os.listdir(self.launch_config_dir):
                if file.endswith('.json'):
                    config_files.append(file)
        return sorted(config_files)

    def _determine_programs(self, game_exe_path: str, mode: str, xxmi_file: str = None) -> Tuple[str, str, str]:
        """
        根据游戏路径和模式自动推导启动程序、目标程序和默认启动参数
        针对鸣潮（Wuthering Waves）和终末地（Endfield）做特殊处理
        """
        game_dir = os.path.dirname(game_exe_path)
        game_exe_name = os.path.basename(game_exe_path).lower()
        game_name = self.get_game_name_from_exe(game_exe_path)
        
        # 默认情况：启动程序 = 目标程序 = 用户选择的exe
        launch_program = game_exe_path
        target_program = game_exe_path
        default_args = "-force-d3d11"  # 默认参数
        
        # 检查是否是鸣潮（保持原有的鸣潮启动器/内核程序特殊逻辑）
        if "wuthering" in game_exe_name or "client-win64-shipping" in game_exe_name:
            if game_exe_name == "client-win64-shipping.exe":
                # 用户选择了内核程序，启动程序应为 Wuthering Waves.exe
                potential_launcher = os.path.join(game_dir, "..", "..", "..", "Wuthering Waves.exe")
                potential_launcher = os.path.normpath(potential_launcher)
                if os.path.exists(potential_launcher):
                    launch_program = potential_launcher
                else:
                    alt = os.path.join(game_dir, "Wuthering Waves.exe")
                    if os.path.exists(alt):
                        launch_program = alt
                target_program = game_exe_path
                default_args = "-dx11"
            elif "wuthering waves.exe" in game_exe_name:
                # 用户选择了启动器，目标程序应为内核程序
                potential_target = os.path.join(game_dir, "Client", "Binaries", "Win64", "Client-Win64-Shipping.exe")
                potential_target = os.path.normpath(potential_target)
                if os.path.exists(potential_target):
                    target_program = potential_target
                else:
                    target_program = game_exe_path
                launch_program = game_exe_path
                default_args = "-dx11"
        else:
            # 其他游戏：启动程序 = 目标程序 = 游戏exe
            launch_program = game_exe_path
            target_program = game_exe_path
            default_args = "-force-d3d11"
        
        return launch_program, target_program, default_args

    def _get_xxmi_module(self, game_name: str, version_config: dict = None) -> Optional[str]:
        """
        根据游戏名获取对应的XXMI模块标识（如 EFMI、GIMI）
        优先从 version_config 中的 xxmi_launch_args_游戏名 提取 --xxmi 参数
        否则使用硬编码映射
        """
        if version_config:
            args_key = f"xxmi_launch_args_{game_name}"
            args_list = version_config.get(args_key, [])
            for i, arg in enumerate(args_list):
                if arg == '--xxmi' and i + 1 < len(args_list):
                    return args_list[i + 1]
        # 硬编码映射
        mapping = {
            'YuanShen': 'GIMI',
            'GenshinImpact': 'GIMI',
            'BH3': 'HIMI',
            'StarRail': 'SRMI',
            'ZenlessZoneZero': 'ZZMI',
            'Client-Win64-Shipping': 'WWMI',
            'Endfield': 'EFMI'
        }
        return mapping.get(game_name)

    def _update_xxmi_config_json(self, xxmi_exe_path: str, module: str, enable_reshade: bool):
        """
        修改 XXMI Launcher Config.json 文件，为指定模块设置 extra_libraries 并启用
        :param xxmi_exe_path: XXMI Launcher.exe 的完整路径
        :param module: MI模块名，如 EFMI
        :param enable_reshade: 是否启用 ReShade（决定 extra_libraries 是否包含 ReShade64.dll）
        """
        # 定位配置文件：xxmi_exe_path 位于 .../Resources/Bin/XXMI Launcher.exe，配置文件位于 .../XXMI Launcher Config.json
        xxmi_root = os.path.dirname(os.path.dirname(os.path.dirname(xxmi_exe_path)))  # 向上三级：Bin -> Resources -> XXMI根目录
        config_path = os.path.join(xxmi_root, "XXMI Launcher Config.json")
        if not os.path.exists(config_path):
            print(f"[配置管理器] 警告：找不到 XXMI 配置文件 {config_path}，跳过修改")
            return

        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        except Exception as e:
            print(f"[配置管理器] 读取 XXMI 配置文件失败: {e}")
            return

        # 定位到 Importers.模块.Importer
        importers = config.get("Importers", {})
        if module not in importers:
            print(f"[配置管理器] 警告：XXMI 配置中没有模块 {module}，跳过修改")
            return

        importer = importers[module].get("Importer", {})
        if not importer:
            return

        # --- 构造 extra_libraries 字符串，保留单个反斜杠 ---
        reshade_dll_path = os.path.join(self.base_dir, "ReShade", "ReShade64.dll")
        d3d11_dll_path = os.path.join(xxmi_root, module, "d3d11.dll")

        # 确保路径使用 Windows 反斜杠（但保留单个反斜杠）
        reshade_dll_path = reshade_dll_path.replace('/', '\\')
        d3d11_dll_path = d3d11_dll_path.replace('/', '\\')

        # 根据 enable_reshade 决定内容，使用换行符分隔
        if enable_reshade:
            extra_libs = reshade_dll_path + "\n" + d3d11_dll_path
        else:
            extra_libs = d3d11_dll_path

        # 更新字段
        importer["extra_libraries"] = extra_libs
        importer["extra_libraries_enabled"] = True

        # 写回文件，json.dump 会自动将 \ 转义为 \\，将换行符保留为 \n
        try:
            with open(config_path, 'w', encoding='utf-8') as f:
                json.dump(config, f, ensure_ascii=False, indent=4)
            print(f"[配置管理器] 已更新 XXMI 配置文件: {config_path}")
            # 调试输出，显示实际写入的 extra_libraries 原始字符串
            print(f"[配置管理器] extra_libraries 原始内容: {repr(extra_libs)}")
        except Exception as e:
            print(f"[配置管理器] 写入 XXMI 配置文件失败: {e}")

    def save_xxmi_config(
        self, 
        game_exe_path: str, 
        xxmi_exe_path: str,
        enable_reshade: bool = False,
        launch_program: str = None,
        target_program: str = None,
        launch_args: str = None,
        version_config: dict = None
    ) -> Tuple[Dict, str]:
        """
        保存XXMI模式配置
        不再保存dll信息，而是修改XXMI全局配置文件，让XXMI自己注入。
        返回 (配置字典, 配置文件名)
        """
        game_name = self.get_game_name_from_exe(game_exe_path)
        config_name = f"{game_name}_xxmi"
        
        # 获取XXMI模块标识，用于定位 d3d11.dll 路径
        module = self._get_xxmi_module(game_name, version_config)
        if not module:
            print(f"[配置管理器] 警告：无法确定 {game_name} 对应的XXMI模块")
        
        # 优先从 XXMI Launcher Config.json 的 extra_libraries 读取 d3d11.dll 路径
        # xxmi_exe_path: .../Resources/Bin/XXMI Launcher.exe
        # XXMI 根目录向上三级: .../Resources/Bin → .../Resources → ...
        xxmi_root = os.path.dirname(os.path.dirname(os.path.dirname(xxmi_exe_path)))
        d3d11_dll_path = ""
        
        if module:
            # 方法1：从 XXMI 配置文件读取
            xxmi_config_path = os.path.join(xxmi_root, "XXMI Launcher Config.json")
            if os.path.exists(xxmi_config_path):
                try:
                    with open(xxmi_config_path, 'r', encoding='utf-8') as f:
                        xxmi_cfg = json.load(f)
                    importer = xxmi_cfg.get("Importers", {}).get(module, {}).get("Importer", {})
                    extra_libs = importer.get("extra_libraries", "")
                    if extra_libs:
                        # extra_libraries 是以换行符分隔的 DLL 路径列表
                        for lib_path in extra_libs.split('\n'):
                            lib_path = lib_path.strip()
                            if lib_path and lib_path.lower().endswith('d3d11.dll') and os.path.exists(lib_path):
                                d3d11_dll_path = lib_path.replace('\\', '/')
                                print(f"[配置管理器] 从 XXMI 配置读取 d3d11.dll: {d3d11_dll_path}")
                                break
                except Exception as e:
                    print(f"[配置管理器] 读取 XXMI 配置文件失败: {e}")
            
            # 方法2：从目录结构推导（后备方案）
            if not d3d11_dll_path:
                d3d11_path = os.path.join(xxmi_root, module, "d3d11.dll")
                if os.path.exists(d3d11_path):
                    d3d11_dll_path = d3d11_path.replace('\\', '/')
                    print(f"[配置管理器] 从目录结构找到 d3d11.dll: {d3d11_dll_path}")
                else:
                    print(f"[配置管理器] 警告：无法找到 XXMI {module} 的 d3d11.dll")

        # 确定启动程序和参数（直接游戏 exe，不再启动 XXMI Launcher）
        if launch_program is None or target_program is None:
            lp, tp, da = self._determine_programs(game_exe_path, 'xxmi')
            if launch_program is None:
                launch_program = lp
            if target_program is None:
                target_program = tp
            if not launch_args:  # None 或空字符串都使用默认值
                launch_args = da

        # 构建 DLL 注入列表（XXMI 的 d3d11.dll 放在首位）
        dll_files = []
        if d3d11_dll_path:
            dll_files.append(d3d11_dll_path)

        config = {
            "launch_program": launch_program.replace('\\', '/'),
            "target_program": target_program.replace('\\', '/'),
            "launch_args": launch_args,
            "game_dir": game_exe_path,
            "game_exe_name": os.path.basename(game_exe_path),
            "dll_files": dll_files,
            "xxmi_launcher_path": xxmi_exe_path,
            "xxmi_exe_name": os.path.basename(xxmi_exe_path),
            "xxmi_module": module or "",
            "mode": "xxmi"
        }

        if enable_reshade:
            config["reshade_dll"] = "ReShade64.dll"

        self._save_json(self.get_config_path(config_name), config)
        return config, config_name
    
    def save_builtin_config(
        self, 
        game_exe_path: str, 
        enable_reshade: bool = False,
        launch_program: str = None,
        target_program: str = None,
        launch_args: str = None
    ) -> Tuple[Dict, str]:
        """保存内置模式配置，返回 (配置字典, 配置文件名)"""
        game_name = self.get_game_name_from_exe(game_exe_path)
        config_name = f"{game_name}_builtin"
        game_dir = os.path.dirname(game_exe_path)
        game_mod_dir = os.path.join(self.mod_loader_dir, game_name)
        d3d11_path = os.path.join(game_mod_dir, "d3d11.dll")
        d3d11_exists = os.path.exists(d3d11_path)

        if launch_program is None or target_program is None:
            lp, tp, da = self._determine_programs(game_exe_path, 'builtin')
            if launch_program is None:
                launch_program = lp
            if target_program is None:
                target_program = tp
            if launch_args is None:
                launch_args = da

        config = {
            "launch_program": launch_program.replace('\\', '/'),
            "target_program": target_program.replace('\\', '/'),
            "launch_args": launch_args,
            "game_dir": game_exe_path,
            "game_exe_name": os.path.basename(game_exe_path),
            "mod_loader_dir": game_mod_dir.replace('\\', '/'),
            "d3d11_exists": d3d11_exists,
            "mode": "builtin"
        }

        if d3d11_exists:
            config["d3d11_path"] = d3d11_path.replace('\\', '/')

        if enable_reshade:
            config["reshade_dll"] = "ReShade64.dll"

        self._save_json(self.get_config_path(config_name), config)
        return config, config_name

    def save_reshade_config(
        self, 
        game_exe_path: str,
        enable_reshade: bool = False,
        launch_program: str = None,
        target_program: str = None,
        launch_args: str = None
    ) -> Tuple[Dict, str]:
        """保存游戏模式配置，返回 (配置字典, 配置文件名)"""
        game_name = self.get_game_name_from_exe(game_exe_path)
        config_name = f"{game_name}_reshade"
        
        if launch_program is None or target_program is None:
            lp, tp, da = self._determine_programs(game_exe_path, 'game')
            if launch_program is None:
                launch_program = lp
            if target_program is None:
                target_program = tp
            if launch_args is None:
                launch_args = da
        
        config = {
            "launch_program": launch_program.replace('\\', '/'),
            "target_program": target_program.replace('\\', '/'),
            "launch_args": launch_args,
            "game_dir": game_exe_path,
            "game_exe_name": os.path.basename(game_exe_path),
            "mode": "game"
        }
        
        if enable_reshade:
            config["reshade_dll"] = "ReShade64.dll"
        
        self._save_json(self.get_config_path(config_name), config)
        return config, config_name
    
    def save_custom_config(
        self,
        game_exe_path: str,
        dll_files: List[str],
        enable_reshade: bool = False,
        launch_program: str = None,
        target_program: str = None,
        launch_args: str = None
    ) -> Tuple[Dict, str]:
        """保存自定义模式配置，返回 (配置字典, 配置文件名)"""
        game_name = self.get_game_name_from_exe(game_exe_path)
        config_name = f"{game_name}_custom"
        
        if launch_program is None or target_program is None:
            lp, tp, da = self._determine_programs(game_exe_path, 'custom')
            if launch_program is None:
                launch_program = lp
            if target_program is None:
                target_program = tp
            if launch_args is None:
                launch_args = da
        
        config = {
            "launch_program": launch_program.replace('\\', '/'),
            "target_program": target_program.replace('\\', '/'),
            "launch_args": launch_args,
            "game_dir": game_exe_path,
            "game_exe_name": os.path.basename(game_exe_path),
            "dll_files": [dll.replace('\\', '/') for dll in dll_files],
            "mode": "custom"
        }
        
        if enable_reshade:
            config["reshade_dll"] = "ReShade64.dll"
        
        self._save_json(self.get_config_path(config_name), config)
        return config, config_name
    
    def open_mod_loader_directory(self, game_name: str):
        """打开mod加载器目录"""
        game_mod_dir = os.path.join(self.mod_loader_dir, game_name)
        os.makedirs(game_mod_dir, exist_ok=True)
        try:
            if os.name == 'nt':
                os.startfile(game_mod_dir)
            else:
                import subprocess
                subprocess.Popen(['xdg-open', game_mod_dir])
        except Exception as e:
            print(f"打开目录失败: {e}")
    
    def get_mod_loader_path(self, game_name: str) -> str:
        """获取mod加载器目录路径"""
        return os.path.join(self.mod_loader_dir, game_name)
    
    def _save_json(self, file_path: str, data: Dict):
        """保存JSON文件"""
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
    
    def load_json(self, file_path: str) -> Optional[Dict]:
        """加载JSON文件"""
        if not os.path.exists(file_path):
            return None
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"加载JSON文件失败: {e}")
            return None
    
    def check_and_create_mod_loader_dir(self, game_name: str) -> bool:
        """检查并创建mod加载器目录"""
        game_mod_dir = os.path.join(self.mod_loader_dir, game_name)
        if os.path.exists(game_mod_dir):
            return True
        try:
            os.makedirs(game_mod_dir, exist_ok=True)
            return False
        except Exception as e:
            print(f"创建目录失败: {e}")
            return False

    # ---------- 桌面快捷方式创建 ----------
    def create_desktop_shortcut(self, config_name: str, display_name: str = None) -> bool:
        """
        为指定配置生成桌面快捷方式
        :param config_name: 配置文件名（不含.json）
        :param display_name: 显示名称（用于快捷方式文件名），如果为None则使用config_name
        :return: 是否成功
        """
        if not SHORTCUT_AVAILABLE:
            print("[配置管理器] winshell 或 pywin32 未安装，无法创建桌面快捷方式")
            return False

        try:
            config_path = self.get_config_path(config_name)
            config_data = self.load_json(config_path)
            if not config_data:
                print(f"[配置管理器] 无法加载配置: {config_name}")
                return False

            game_exe_path = config_data.get('game_dir')
            if not game_exe_path or not os.path.exists(game_exe_path):
                print(f"[配置管理器] 游戏可执行文件不存在: {game_exe_path}")
                return False

            shortcut_name = f"ReShade {display_name or config_name}.lnk"
            desktop = winshell.desktop()
            shortcut_path = os.path.join(desktop, shortcut_name)

            if getattr(sys, 'frozen', False):
                target = sys.executable
                arguments = f'"{config_name}.json"'
                working_dir = os.path.dirname(sys.executable)
            else:
                target = sys.executable
                script_path = os.path.join(os.path.dirname(__file__), "ReShade启动器.py")
                arguments = f'"{script_path}" "{config_name}.json"'
                working_dir = os.path.dirname(__file__)

            shell = Dispatch('WScript.Shell')
            shortcut = shell.CreateShortCut(shortcut_path)
            shortcut.TargetPath = target
            shortcut.Arguments = arguments
            shortcut.WorkingDirectory = working_dir
            shortcut.IconLocation = game_exe_path
            shortcut.save()

            print(f"[配置管理器] 已创建桌面快捷方式: {shortcut_path}")
            return True
        except Exception as e:
            print(f"[配置管理器] 创建快捷方式失败: {e}")
            return False