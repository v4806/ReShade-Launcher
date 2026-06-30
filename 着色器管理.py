# -*- coding: utf-8 -*-
"""
着色器管理模块 - 精简/完整着色器切换
"""
import os
import re
import zipfile
import shutil

RESHADE_DIR = None  # 由主窗口调用时设置

# 白名单目录：这些目录中的文件不会被删除（如 REST 插件的依赖文件）
WHITELIST_DIRS = {'REST'}


def _get_reshade_dir():
    """获取 ReShade 根目录"""
    global RESHADE_DIR
    if RESHADE_DIR:
        return RESHADE_DIR
    return None


def set_reshade_dir(path):
    """由主窗口设置 ReShade 目录"""
    global RESHADE_DIR
    RESHADE_DIR = path


def _get_presets_dir():
    rd = _get_reshade_dir()
    if not rd:
        return None
    return os.path.join(rd, "Presets")


def _get_shaders_dir():
    rd = _get_reshade_dir()
    if not rd:
        return None
    return os.path.join(rd, "reshade_shaders", "Shaders")


def _get_full_zip_path():
    rd = _get_reshade_dir()
    if not rd:
        return None
    return os.path.join(rd, "reshade_shaders", "full.zip")


def get_current_state():
    """返回当前着色器状态: 'full', 'lite', 或 'unknown'"""
    shaders_dir = _get_shaders_dir()
    full_zip = _get_full_zip_path()
    print(f"[着色器管理] Shaders dir: {shaders_dir}")
    print(f"[着色器管理] full.zip: {full_zip}")
    if not shaders_dir or not os.path.isdir(shaders_dir):
        print("[着色器管理] Shaders 目录不存在")
        return 'unknown'
    if not full_zip or not os.path.exists(full_zip):
        print("[着色器管理] full.zip 不存在")
        return 'unknown'
    # 递归统计 Shaders 目录下所有文件（不含目录本身）
    file_count = 0
    for root, dirs, files in os.walk(shaders_dir):
        file_count += len(files)
    # 统计 zip 中的文件数
    with zipfile.ZipFile(full_zip, 'r') as z:
        zip_files = [n for n in z.namelist() if not n.endswith('/')]
    print(f"[着色器管理] Shaders 文件数: {file_count}, zip 文件数: {len(zip_files)}")
    # 如果当前文件数远少于 zip 中的文件数，则为精简版
    if file_count < len(zip_files) * 0.5:
        print("[着色器管理] 判定为: lite")
        return 'lite'
    else:
        print("[着色器管理] 判定为: full")
        return 'full'


def scan_presets_for_fx_files():
    """扫描 Presets 目录下所有 .ini，提取 Techniques 行引用的 .fx 文件名"""
    presets_dir = _get_presets_dir()
    print(f"[着色器管理] Presets dir: {presets_dir}")
    if not presets_dir or not os.path.isdir(presets_dir):
        print("[着色器管理] Presets 目录不存在")
        return set()

    fx_files = set()

    for fname in os.listdir(presets_dir):
        if not fname.lower().endswith('.ini'):
            continue
        fpath = os.path.join(presets_dir, fname)
        print(f"[着色器管理] 扫描预设: {fname}")
        try:
            with open(fpath, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception:
            try:
                with open(fpath, 'r', encoding='gbk') as f:
                    content = f.read()
            except Exception:
                continue
        # 只匹配 Techniques= 行
        for line in content.split('\n'):
            line = line.strip()
            if not line.startswith('Techniques='):
                continue
            # 格式: Techniques=Name1@File1.fx,Name2@File2.fx,...
            parts = line[len('Techniques='):].split(',')
            for part in parts:
                part = part.strip()
                if not part:
                    continue
                # 提取 @ 后面的文件名
                if '@' in part:
                    fname_only = part.split('@', 1)[1]
                else:
                    fname_only = part
                if fname_only.lower().endswith('.fx') or fname_only.lower().endswith('.fxh'):
                    fx_files.add(fname_only)
                    print(f"[着色器管理]   -> 发现引用: {fname_only}")

    print(f"[着色器管理] 共发现 {len(fx_files)} 个引用的着色器文件")
    return fx_files


def resolve_dependencies(fx_name, shaders_dir, visited=None):
    """递归解析 .fx 文件的 #include 依赖"""
    if visited is None:
        visited = set()
    if fx_name in visited:
        return visited
    visited.add(fx_name)
    print(f"[着色器管理] 解析依赖: {fx_name}")

    # 查找 fx 文件（可能在子目录中）
    fx_path = None
    for root, dirs, files in os.walk(shaders_dir):
        if fx_name in files:
            fx_path = os.path.join(root, fx_name)
            break

    if not fx_path:
        print(f"[着色器管理]   未找到文件: {fx_name}")
        return visited

    try:
        with open(fx_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"[着色器管理]   读取失败 {fx_name}: {e}")
        return visited

    # 查找 #include "filename" 或 #include <filename>
    for match in re.finditer(r'#include\s+["<]([^">]+)[">]', content):
        inc_name = match.group(1)
        inc_base = os.path.basename(inc_name)
        print(f"[着色器管理]   依赖: {fx_name} -> {inc_base}")
        if inc_base not in visited:
            resolve_dependencies(inc_base, shaders_dir, visited)

    return visited


def get_all_needed_files():
    """获取所有需要的着色器文件（引用文件 + 依赖文件）"""
    shaders_dir = _get_shaders_dir()
    if not shaders_dir or not os.path.isdir(shaders_dir):
        return set()

    # 从 Presets 获取引用的 .fx 文件
    fx_refs = scan_presets_for_fx_files()
    if not fx_refs:
        return set()

    # 解析所有依赖
    all_needed = set()
    for fx_name in fx_refs:
        deps = resolve_dependencies(fx_name, shaders_dir)
        all_needed.update(deps)

    # 始终保留核心文件
    all_needed.add('ReShade.fxh')
    all_needed.add('ReShadeUI.fxh')

    return all_needed


def apply_lite(progress_callback=None):
    """
    精简模式：只保留预设中用到的着色器及其依赖，删除其余
    返回 (成功数, 删除数)
    """
    shaders_dir = _get_shaders_dir()
    if not shaders_dir or not os.path.isdir(shaders_dir):
        if progress_callback:
            progress_callback("错误：着色器目录不存在")
        return 0, 0

    if progress_callback:
        progress_callback("正在扫描预设文件...")

    needed = get_all_needed_files()
    print(f"[着色器管理] 需要的文件: {needed}")
    if not needed:
        if progress_callback:
            progress_callback("未找到预设中引用的着色器，无法精简")
            progress_callback("提示：请确认 Presets 目录下有 .ini 预设文件，且其中包含 Techniques= 行")
        return 0, 0

    if progress_callback:
        progress_callback(f"找到 {len(needed)} 个需要的着色器文件，正在清理...")

    kept = 0
    deleted = 0

    # 遍历 Shaders 目录所有文件，删除不在 needed 中的
    all_items = []
    for root, dirs, files in os.walk(shaders_dir, topdown=False):
        for f in files:
            all_items.append(os.path.join(root, f))
        for d in dirs:
            dirpath = os.path.join(root, d)
            # 只处理空目录
            all_items.append(dirpath)

    for item_path in all_items:
        rel_path = os.path.relpath(item_path, shaders_dir)

        # 检查是否在白名单目录中（如 REST/），是则跳过不删除
        is_whitelisted = False
        for whitelist_dir in WHITELIST_DIRS:
            if rel_path.startswith(whitelist_dir + os.sep) or rel_path == whitelist_dir:
                is_whitelisted = True
                break
        if is_whitelisted:
            kept += 1
            continue

        # 如果是文件，检查是否需要保留
        if os.path.isfile(item_path):
            fname = os.path.basename(item_path)
            if fname in needed:
                kept += 1
            else:
                try:
                    os.remove(item_path)
                    deleted += 1
                except Exception:
                    pass
        elif os.path.isdir(item_path):
            # 删除空目录
            try:
                os.rmdir(item_path)
            except Exception:
                pass

    if progress_callback:
        progress_callback(f"精简完成：保留 {kept} 个，删除 {deleted} 个")

    return kept, deleted


def apply_full(progress_callback=None):
    """
    完整模式：解压 full.zip 覆盖 Shaders 目录
    返回 True/False
    """
    shaders_dir = _get_shaders_dir()
    full_zip = _get_full_zip_path()

    if not shaders_dir:
        if progress_callback:
            progress_callback("错误：着色器目录不存在")
        return False
    if not full_zip or not os.path.exists(full_zip):
        if progress_callback:
            progress_callback("错误：未找到 full.zip，请确认安装完整性")
        return False

    if progress_callback:
        progress_callback("正在解压完整着色器包...")

    print(f"[着色器管理] 开始解压 {full_zip} -> {shaders_dir}")

    try:
        # 清空当前 Shaders 目录
        if os.path.exists(shaders_dir):
            for item in os.listdir(shaders_dir):
                item_path = os.path.join(shaders_dir, item)
                try:
                    if os.path.isfile(item_path) or os.path.islink(item_path):
                        os.unlink(item_path)
                    elif os.path.isdir(item_path):
                        shutil.rmtree(item_path)
                except Exception as e:
                    print(f"[着色器管理] 删除失败 {item_path}: {e}")
        else:
            os.makedirs(shaders_dir)

        # 解压 full.zip 到 Shaders 目录
        with zipfile.ZipFile(full_zip, 'r') as z:
            # zip 中文件在 Shaders/ 子目录下，提取时去掉这层前缀
            for info in z.infolist():
                if info.filename.endswith('/'):
                    continue
                # 去掉 Shaders/ 前缀
                rel_name = info.filename
                if rel_name.startswith('Shaders/'):
                    rel_name = rel_name[len('Shaders/'):]
                target_path = os.path.join(shaders_dir, rel_name)
                os.makedirs(os.path.dirname(target_path), exist_ok=True)
                with z.open(info) as src, open(target_path, 'wb') as dst:
                    shutil.copyfileobj(src, dst)

        unpacked = len([n for n in z.namelist() if not n.endswith('/')])
        print(f"[着色器管理] 解压完成: {unpacked} 个文件")
        if progress_callback:
            progress_callback(f"完整着色器已部署：{unpacked} 个文件")

        return True
    except Exception as e:
        if progress_callback:
            progress_callback(f"部署完整着色器失败：{e}")
        return False
