# -*- coding: utf-8 -*-
"""
更新管理器 - 从 GitHub 仓库安全检测并更新组件与数据文件

检测方案（不依赖文件修改日期）：
    基于「内容 SHA-256 哈希 + 远程清单(manifest)」比对：
    1. 仓库根维护 update_manifest.json，记录每个文件的内容哈希
    2. 更新时对本地文件计算 SHA-256 并与远程清单比对
    3. 哈希不一致 → 内容确实不同 → 需要更新
    4. 只下载发生变化的文件（临时文件 + 原子替换，避免覆盖中断损坏）

优势：
    - 用户手动复制文件导致文件日期变新，只要内容与仓库不同，哈希就能准确识别为"需要更新"
    - 若内容与仓库一致（哪怕日期被手动改旧/改新），哈希相同，不会误报
    - 目录按文件粒度比对，只更新真正变化的文件
"""

import os
import sys
import json
import hashlib
import base64
import shutil
import tempfile
import zipfile
import ctypes
import urllib.request
from urllib.parse import quote

# ---------------- GitHub 仓库配置 ----------------
REPO = "v4806/ReShade-Launcher"
BRANCH = "main"
MANIFEST_FILENAME = "update_manifest.json"

# 需要更新检查的顶层条目（与仓库保持一致）
MANIFEST_ITEMS = [
    {"path": "translations.json", "type": "file"},
    {"path": "version.json", "type": "file"},
    {"path": "injector.exe", "type": "file"},
    {"path": "b.jpg", "type": "file"},
    {"path": "icon.ico", "type": "file"},
    {"path": "ReShade/ReShade64.dll", "type": "file"},
    {"path": "ReShade/Addons", "type": "dir"},
    # 预设为用户自定义：只补本地缺失的，不覆盖用户已存在的预设（preserve_existing）
    {"path": "ReShade/Presets", "type": "dir", "preserve_existing": True},
    # 着色器库同样只补缺：用户可能对着色器做汉化/自定义，已存在的文件不覆盖
    {"path": "ReShade/reshade_shaders", "type": "dir", "preserve_existing": True},
    {"path": "ReShade/sound", "type": "dir"},
    {"path": "README", "type": "dir"},
]

# 更新组件分组（用于「更新选择对话框」；item 的 id 与 MANIFEST_ITEMS 的 path 或特殊值 'app' 对应）
UPDATE_GROUPS = [
    {"key": "update.group.program", "items": [
        {"id": "app", "label": "update.item.app"},
    ]},
    {"key": "update.group.config", "items": [
        {"id": "translations.json", "label": "update.item.translations"},
        {"id": "version.json", "label": "update.item.version"},
        {"id": "injector.exe", "label": "update.item.injector"},
        {"id": "b.jpg", "label": "update.item.background"},
        {"id": "icon.ico", "label": "update.item.icon"},
    ]},
    {"key": "update.group.reshade", "items": [
        {"id": "ReShade/ReShade64.dll", "label": "update.item.reshade_dll"},
        {"id": "ReShade/Addons", "label": "update.item.addons"},
        {"id": "ReShade/reshade_shaders", "label": "update.item.shaders"},
        {"id": "ReShade/sound", "label": "update.item.sound"},
        {"id": "ReShade/Presets", "label": "update.item.presets"},
    ]},
    {"key": "update.group.docs", "items": [
        {"id": "README", "label": "update.item.readme"},
    ]},
]


def get_base_url() -> str:
    """获取 raw.githubusercontent.com 的基础 URL"""
    return f"https://raw.githubusercontent.com/{REPO}/{BRANCH}/"


def _url_quote(path: str) -> str:
    """对 URL 路径进行百分号编码（处理空格/中文等字符）"""
    return quote(path, safe='/.')


def _local_path(local_root: str, rel_path: str) -> str:
    """将仓库相对路径(正斜杠)转换为本地绝对路径"""
    return os.path.join(local_root, rel_path.replace('/', os.sep))


def sha256_file(path: str) -> str:
    """
    计算文件内容 SHA-256。
    文本文件（不含 NUL 字节）忽略 CRLF/LF 行尾差异（与 Git autocrlf 存储语义一致），
    二进制文件保持原始字节。这样本地 CRLF 版本与仓库 LF 版本视为内容一致，
    不会因行尾差异导致重复下载。
    """
    with open(path, 'rb') as f:
        data = f.read()
    if b'\x00' in data:  # 二进制文件
        return hashlib.sha256(data).hexdigest()
    # 文本文件：统一按 LF 规范化后计算
    return hashlib.sha256(data.replace(b'\r\n', b'\n')).hexdigest()


def fetch_manifest() -> dict:
    """
    获取远程更新清单。
    优先使用 GitHub API（实时内容，绕过 raw CDN 缓存，避免拿到陈旧清单导致重复下载）；
    若 API 失败则回退到 raw.githubusercontent.com 下载。
    失败抛出异常。
    """
    manifest = None
    # 1. GitHub API（实时内容，无 CDN 缓存）
    try:
        api_url = f"https://api.github.com/repos/{REPO}/contents/{MANIFEST_FILENAME}"
        req = urllib.request.Request(api_url, headers={'User-Agent': 'ReShade-Launcher'})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode('utf-8'))
        manifest = json.loads(base64.b64decode(data.get('content', '')).decode('utf-8'))
    except Exception as api_e:
        print(f"[更新管理器] GitHub API 获取清单失败，回退到 raw 下载: {api_e}")
        url = get_base_url() + _url_quote(MANIFEST_FILENAME)
        with urllib.request.urlopen(url, timeout=30) as resp:
            data = resp.read().decode('utf-8')
        manifest = json.loads(data)

    if manifest.get('schema_version') != 1:
        raise ValueError("更新清单格式版本不兼容")
    return manifest


def check_updates(local_root: str, manifest: dict):
    """
    比对本地文件与远程清单，返回 (pending, orphans)。
    pending: 需要更新的文件列表，元素 {"rel": 相对路径, "url": 下载地址, "item": 所属条目}
    orphans: 本地存在但清单未收录的文件（保留不删除，仅报告）
    """
    base = manifest.get('base', get_base_url())
    pending = []
    orphans = []
    items = manifest.get('items', [])

    for item in items:
        rel = item['path']
        kind = item.get('type', 'file')

        if kind == 'dir':
            local_dir = _local_path(local_root, rel)
            remote_files = {f['path'].replace('\\', '/'): f for f in item.get('files', [])}
            # preserve_existing=True 的目录（如 Presets）：只下载本地缺失的文件，
            # 已存在的文件即使内容不同也跳过，避免覆盖用户自定义内容
            preserve = bool(item.get('preserve_existing'))
            for f_rel, f in remote_files.items():
                fpath = _local_path(local_dir, f_rel)
                full_rel = f"{rel}/{f_rel}"
                if not os.path.isfile(fpath):
                    pending.append({'rel': full_rel, 'url': base + _url_quote(full_rel), 'item': rel, 'sha256': f['sha256']})
                elif not preserve and sha256_file(fpath) != f['sha256']:
                    pending.append({'rel': full_rel, 'url': base + _url_quote(full_rel), 'item': rel, 'sha256': f['sha256']})
            # 检测本地多余文件（清单未收录，可能是用户自增文件，保留不删）
            if os.path.isdir(local_dir):
                for root, _dirs, files in os.walk(local_dir):
                    for fn in files:
                        abs_p = os.path.join(root, fn)
                        rel_p = os.path.relpath(abs_p, local_dir).replace('\\', '/')
                        if rel_p not in remote_files:
                            orphans.append(f"{rel}/{rel_p}")
        else:
            fpath = _local_path(local_root, rel)
            if not os.path.isfile(fpath):
                pending.append({'rel': rel, 'url': base + _url_quote(rel), 'item': rel, 'sha256': item['sha256']})
            elif sha256_file(fpath) != item['sha256']:
                pending.append({'rel': rel, 'url': base + _url_quote(rel), 'item': rel, 'sha256': item['sha256']})

    return pending, orphans


def download_to(url: str, dest: str) -> None:
    """
    下载文件到目标路径。
    先写入同目录临时文件，成功后用 os.replace 原子替换，防止覆盖中断损坏。
    """
    dest = os.path.abspath(dest)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(dest), suffix='.tmp')
    os.close(fd)
    try:
        with urllib.request.urlopen(url, timeout=120) as resp:
            with open(tmp_path, 'wb') as f:
                shutil.copyfileobj(resp, f)
        os.replace(tmp_path, dest)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass


def update_all(local_root: str, progress_cb=None, selected=None) -> dict:
    """
    执行完整更新流程：获取清单 → 比对 → 下载变更文件。
    progress_cb: 可选回调，接收进度字符串。
    selected: 可选，要检测/更新的组件 id 列表（如 ["app", "translations.json", ...]，
              对应 UPDATE_GROUPS 中的 id）；为 None 时更新全部组件。
    返回统计 dict：{ok, error, updated, failed, orphans, app_update}
    """
    result = {'ok': False, 'error': '', 'updated': [], 'failed': [], 'orphans': []}

    # 1. 获取远程清单
    try:
        if progress_cb:
            progress_cb("正在获取更新清单...")
        manifest = fetch_manifest()
    except Exception as e:
        result['error'] = f"获取更新清单失败: {e}"
        return result

    # 2. 比对本地文件（支持按 selected 过滤组件）
    try:
        selected_set = None
        filtered_manifest = manifest
        if selected is not None:
            selected_set = set(selected)
            filtered_manifest = dict(manifest)
            filtered_manifest['items'] = [
                it for it in manifest.get('items', [])
                if it['path'] in selected_set
            ]
        pending, orphans = check_updates(local_root, filtered_manifest)
    except Exception as e:
        result['error'] = f"比对本地文件失败: {e}"
        return result

    result['orphans'] = orphans

    # 3. 逐个下载更新的文件（下载后校验哈希，防止服务器缓存返回旧内容导致反复下载）
    total = len(pending)
    for i, p in enumerate(pending):
        if progress_cb:
            progress_cb(f"({i + 1}/{total}) 下载 {p['rel']}")
        dest = _local_path(local_root, p['rel'])
        try:
            ok = False
            for _attempt in range(3):
                download_to(p['url'], dest)
                if p.get('sha256') is None or sha256_file(dest) == p['sha256']:
                    ok = True
                    break
            if ok:
                result['updated'].append(p['rel'])
            else:
                result['failed'].append((p['rel'], '下载内容校验不一致（服务器缓存滞后），请稍后重试'))
        except Exception as e:
            result['failed'].append((p['rel'], str(e)))

    # 5. 检测并准备 exe/_internal 更新（按版本号，整体 zip 更新；仅当未过滤或选中 app）
    app_update = {'need_update': False, 'local': '', 'remote': '', 'error': ''}
    if selected is None or 'app' in (selected_set or set()):
        try:
            app_update = check_app_update(local_root, manifest)
            if app_update.get('need_update'):
                if progress_cb:
                    progress_cb(f"检测到新版本 {app_update.get('remote')}，正在下载更新包...")
                app_update['stage_dir'] = stage_app_update(local_root, app_update)
        except Exception as e:
            app_update['error'] = str(e)
            app_update['need_update'] = False
    result['app_update'] = app_update

    result['ok'] = True
    return result


def build_manifest_items(root: str) -> list:
    """
    扫描本地数据目录，构建与 MANIFEST_ITEMS 对应的清单条目列表。
    供「生成更新清单.py」使用。
    """
    items = []
    for spec in MANIFEST_ITEMS:
        rel = spec['path']
        full = _local_path(root, rel)
        if not os.path.exists(full):
            print(f"⚠ 跳过（本地不存在）: {rel}")
            continue
        if spec.get('type') == 'dir':
            files = []
            for dirpath, _dirs, filenames in os.walk(full):
                for fn in sorted(filenames):
                    abs_p = os.path.join(dirpath, fn)
                    f_rel = os.path.relpath(abs_p, full).replace('\\', '/')
                    files.append({"path": f_rel, "sha256": sha256_file(abs_p)})
            item = {"path": rel.replace('\\', '/'), "type": "dir", "files": files}
            if spec.get('preserve_existing'):
                item['preserve_existing'] = True
            items.append(item)
        else:
            items.append({"path": rel.replace('\\', '/'), "type": "file", "sha256": sha256_file(full)})
    return items


# ==================== exe / _internal 更新（按版本号，整体 zip 更新）====================
# 打包后的两个 exe（ReShade Launcher Build.exe / ReShade Debug.exe）+ _internal 目录
# 作为一个整体更新单元：用版本号检测（避免对上千文件逐个哈希比对），版本不同则
# 下载整体 zip 包，通过「重启替换」脚本在程序退出后覆盖。
APP_EXE_NAMES = ['ReShade Launcher Build.exe', 'ReShade Debug.exe']


def _version_tuple(v: str) -> tuple:
    """将版本字符串（如 2.6.0.0 / 2.6）转为可比较的整数元组"""
    parts = []
    for p in str(v).replace('-', '.').replace('_', '.').split('.'):
        if p.isdigit():
            parts.append(int(p))
        else:
            break
    parts = (parts + [0, 0, 0, 0])[:4]
    return tuple(parts)


def get_local_app_version(exe_path: str) -> str:
    """读取 exe 的文件版本号（如 2.6.0.0），失败返回 0.0.0.0"""
    if not os.path.isfile(exe_path):
        return "0.0.0.0"
    try:
        size = ctypes.windll.version.GetFileVersionInfoSizeW(exe_path, None)
        if size <= 0:
            return "0.0.0.0"
        data = ctypes.create_string_buffer(size)
        if not ctypes.windll.version.GetFileVersionInfoW(exe_path, 0, size, data):
            return "0.0.0.0"
        ptr = ctypes.c_void_p()
        length = ctypes.c_uint()
        if not ctypes.windll.version.VerQueryValueW(data, "\\", ctypes.byref(ptr), ctypes.byref(length)):
            return "0.0.0.0"
        ffi = ctypes.cast(ptr, ctypes.POINTER(ctypes.c_uint32))
        ms = ffi[2]  # dwFileVersionMS
        ls = ffi[3]  # dwFileVersionLS
        return f"{(ms >> 16) & 0xffff}.{ms & 0xffff}.{(ls >> 16) & 0xffff}.{ls & 0xffff}"
    except Exception:
        return "0.0.0.0"


def check_app_update(app_root: str, manifest: dict) -> dict:
    """按版本号检测 exe/_internal 是否有更新，返回更新信息 dict"""
    app = manifest.get('app') or {}
    remote = app.get('version', '0.0.0.0')
    local_exe = _local_path(app_root, APP_EXE_NAMES[0])
    local = get_local_app_version(local_exe)
    need = _version_tuple(local) < _version_tuple(remote)
    return {
        'need_update': need,
        'local': local,
        'remote': remote,
        'url': app.get('url', ''),
        'sha256': app.get('sha256', ''),
    }


def stage_app_update(app_root: str, app_info: dict) -> str:
    """
    下载 app 更新包 zip 并解压到临时目录（不覆盖运行中的文件）。
    返回解压后的目录（含新 exe 与 _internal）。
    """
    url = app_info.get('url', '')
    if not url:
        raise ValueError('更新包下载地址缺失')
    tmp_root = tempfile.mkdtemp(prefix='ReShadeUpdate_')
    zip_path = os.path.join(tmp_root, 'app_update.zip')
    download_to(url, zip_path)
    # zip 是二进制，用原始字节哈希校验
    if app_info.get('sha256'):
        actual = hashlib.sha256(open(zip_path, 'rb').read()).hexdigest()
        if actual != app_info['sha256']:
            raise ValueError('更新包校验失败，可能下载不完整')
    with zipfile.ZipFile(zip_path, 'r') as z:
        z.extractall(tmp_root)
    return tmp_root


def make_restart_bat(app_root: str, stage_dir: str) -> str:
    """
    生成「退出→备份→覆盖→启动新 exe→清理」的重启替换批处理，返回 bat 绝对路径。
    由主程序用 detach 方式启动后立即退出；bat 等待主程序退出后替换 exe/_internal。
    """
    bat_path = os.path.join(stage_dir, 'apply_update.bat')
    lines = [
        '@echo off',
        'title ReShade Launcher Updater',
        'rem wait for main exe to exit',
        'ping 127.0.0.1 -n 3 >nul',
        'set "APP=%s"' % app_root,
        'if exist "%APP%\\_internal" (',
        '  if exist "%APP%\\_internal_old" rmdir /s /q "%APP%\\_internal_old"',
        '  rename "%APP%\\_internal" "_internal_old"',
        ')',
        'xcopy /y /e /q "%~dp0_internal" "%APP%\\_internal"',
        'copy /y /q "%~dp0ReShade Launcher Build.exe" "%APP%\\ReShade Launcher Build.exe"',
        'copy /y /q "%~dp0ReShade Debug.exe" "%APP%\\ReShade Debug.exe"',
        'if exist "%APP%\\_internal_old" rmdir /s /q "%APP%\\_internal_old"',
        'start "" "%APP%\\ReShade Launcher Build.exe"',
        'start "" cmd /c "ping 127.0.0.1 -n 4 >nul & rmdir /s /q \"%~dp0\""',
        'exit',
    ]
    with open(bat_path, 'w', encoding='gbk', errors='replace') as f:
        f.write('\r\n'.join(lines))
    return bat_path
