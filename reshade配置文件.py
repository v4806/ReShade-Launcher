# -*- coding: utf-8 -*-
"""
ReShade 配置管理器 - 精简版
仅保留：加载 version.json、切换深度颠倒参数
其余 ReShade.ini 处理功能已移除（由 ReShade 本体插件接管）
"""

import os
import sys
import json

def load_version_config(app_root: str) -> dict:
    """
    加载 version.json 配置文件
    支持打包环境：优先从 app_root 查找，若不存在且处于打包状态，
    则从 sys._MEIPASS 临时目录查找。
    """
    candidates = []
    candidates.append(os.path.join(app_root, "version.json"))
    
    if hasattr(sys, '_MEIPASS'):
        candidates.append(os.path.join(sys._MEIPASS, "version.json"))
    
    for path in candidates:
        if os.path.exists(path):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"[ReShadeConfig] 加载 version.json 失败 ({path}): {e}")
    
    print("[ReShadeConfig] 警告：无法找到 version.json，将使用空配置")
    return {}

def toggle_depth_upside_down(game_dir: str, game_exe_name: str, app_root: str) -> None:
    """
    切换 ReShade 深度颠倒参数（修复阴影颠倒）
    仅修改两个位置的 ReShade.ini：
      - 游戏目录下的 ReShade.ini
      - 配置目录中的 {game_name}.ini
    """
    game_name = os.path.splitext(game_exe_name)[0]

    candidates = [
        # 游戏目录下的 ReShade.ini（旧方案，DLL 同目录部署）
        os.path.join(game_dir, "ReShade.ini"),
        # RESHADE_BASE_PATH_OVERRIDE 目标路径（新方案，启动器根目录/<游戏名>/）
        os.path.join(app_root, game_name, "ReShade.ini"),
        # reshade_config 目录（启动器统一管理的配置文件目录）
        os.path.join(app_root, "ReShade", "reshade_config", f"{game_name}.ini"),
    ]

    toggled = False
    for file_path in candidates:
        if not os.path.exists(file_path):
            continue

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()

            new_lines = []
            modified = False
            for line in lines:
                if line.strip().startswith('PreprocessorDefinitions='):
                    if 'RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=0' in line:
                        new_line = line.replace('RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=0', 'RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=1')
                        modified = True
                    elif 'RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=1' in line:
                        new_line = line.replace('RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=1', 'RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=0')
                        modified = True
                    else:
                        new_line = line
                    new_lines.append(new_line)
                else:
                    new_lines.append(line)

            if modified:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.writelines(new_lines)
                print(f"[ReShadeConfig] 已切换深度参数: {file_path}")
                toggled = True
            else:
                print(f"[ReShadeConfig] 文件中未找到深度参数: {file_path}")

        except Exception as e:
            print(f"[ReShadeConfig] 修改深度参数失败 {file_path}: {e}")

    if toggled:
        print("[ReShadeConfig] 深度参数切换完成，重启游戏后生效")
    else:
        print("[ReShadeConfig] 未找到任何可修改的配置文件")