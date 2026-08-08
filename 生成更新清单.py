# -*- coding: utf-8 -*-
"""
生成更新清单工具（开发者/维护者使用）

作用：扫描指定的「数据源目录」，生成 update_manifest.json
     （记录每个需更新文件的内容 SHA-256，供「更新管理器」做哈希比对）

用法：
    python 生成更新清单.py                                   # 数据源=脚本所在目录
    python 生成更新清单.py --source "D:\\ReShade Launcher"    # 指定数据源目录
    python 生成更新清单.py --source "D:\\ReShade Launcher" --out "D:\\out\\update_manifest.json"

说明：
    - 只处理 MANIFEST_ITEMS 中列出的条目（translations.json / injector.exe / b.jpg /
      icon.ico / ReShade\\ReShade64.dll / ReShade\\Addons / ReShade\\Presets /
      ReShade\\reshade_shaders / ReShade\\sound / README），其余文件一律忽略
    - 生成后，将数据源目录中的数据与 update_manifest.json 一起同步到仓库根目录即可
      （可用 git / GitHub Desktop / 网页上传等常规方式同步）
    - manifest 记录的是「发布数据」的哈希，请以将要发布的数据为准生成
"""

import argparse
import os
import sys
import json
import zipfile
import hashlib

from 更新管理器 import (
    build_manifest_items, get_base_url, MANIFEST_ITEMS,
    get_local_app_version, APP_EXE_NAMES,
)

MANIFEST_FILENAME = "update_manifest.json"
APP_ZIP_DIR = "update"  # 仓库中存放 app 更新包的目录


def build_app_zip(app_src: str, out_zip: str) -> None:
    """将两个 exe 与 _internal 打包成 app 更新 zip（zip 根为两个 exe + _internal/）"""
    with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as z:
        for name in APP_EXE_NAMES:
            p = os.path.join(app_src, name)
            if os.path.isfile(p):
                z.write(p, name)
            else:
                print(f"  ⚠ 缺少 {name}，已跳过")
        internal = os.path.join(app_src, "_internal")
        if os.path.isdir(internal):
            for root, _dirs, files in os.walk(internal):
                for fn in files:
                    fp = os.path.join(root, fn)
                    arc = os.path.relpath(fp, app_src).replace('\\', '/')
                    z.write(fp, arc)
        else:
            print("  ⚠ 缺少 _internal 目录")


def _print_items_summary(items):
    """打印清单条目收录概览"""
    print()
    print("-" * 60)
    for item in items:
        if item.get('type') == 'dir':
            print(f"  [目录] {item['path']}  ({len(item.get('files', []))} 个文件)")
        else:
            print(f"  [文件] {item['path']}")
    print("-" * 60)


def main():
    # 确保控制台/管道输出编码兼容（避免 GBK 无法编码 emoji 报错）
    if hasattr(sys.stdout, 'reconfigure'):
        try:
            sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        except Exception:
            pass
    parser = argparse.ArgumentParser(
        description="生成更新清单 update_manifest.json（供更新管理器哈希比对）")
    parser.add_argument(
        "--source", default=None,
        help="数据源目录（含要发布的组件与数据）。默认使用脚本所在目录")
    parser.add_argument(
        "--out", default=None,
        help="输出清单文件路径。默认在数据源目录下生成 update_manifest.json")
    parser.add_argument(
        "--app-src", default=None,
        help="打包产物目录（含 ReShade Launcher Build.exe / ReShade Debug.exe / _internal），"
             "提供后生成 app 更新包并写入清单")
    args = parser.parse_args()

    source = os.path.abspath(args.source) if args.source \
        else os.path.dirname(os.path.abspath(__file__))
    out = os.path.abspath(args.out) if args.out \
        else os.path.join(source, MANIFEST_FILENAME)

    if not os.path.isdir(source):
        print(f"❌ 数据源目录不存在: {source}")
        return 1

    print("=" * 60)
    print("正在扫描并生成更新清单...")
    print(f"数据源目录: {source}")
    print(f"输出文件  : {out}")
    print("=" * 60)

    items = build_manifest_items(source)

    if not items:
        print("❌ 未找到任何可发布的数据，请确认数据源目录结构正确。")
        return 1

    manifest = {
        "schema_version": 1,
        "base": get_base_url(),
        "items": items,
    }

    # ---- 生成 exe/_internal 的 app 更新包（按版本号整体更新）----
    if args.app_src:
        app_src = os.path.abspath(args.app_src)
        version = get_local_app_version(os.path.join(app_src, APP_EXE_NAMES[0]))
        if version == "0.0.0.0":
            print(f"⚠ 无法从打包产物读取 exe 版本，跳过 app 更新包生成: {app_src}")
        else:
            zip_dir = os.path.join(source, APP_ZIP_DIR)
            os.makedirs(zip_dir, exist_ok=True)
            zip_name = f"ReShade_Launcher_{version}.zip"
            zip_path = os.path.join(zip_dir, zip_name)
            build_app_zip(app_src, zip_path)
            manifest["app"] = {
                "version": version,
                "url": get_base_url() + f"{APP_ZIP_DIR}/{zip_name}",
                "sha256": hashlib.sha256(open(zip_path, 'rb').read()).hexdigest(),
            }
            print(f"\n✅ app 更新包: {zip_path}")
            print(f"   版本: {version}, 大小: {os.path.getsize(zip_path) / 1024 / 1024:.1f} MB")

    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    total_files = sum(
        len(i.get('files', [])) if i.get('type') == 'dir' else 1
        for i in items
    )

    print()
    print(f"✅ 已生成: {out}")
    print(f"   条目数: {len(items)}, 文件总数: {total_files}")
    _print_items_summary(items)
    print()
    print("下一步：将数据源目录中的数据与 update_manifest.json 一起同步到仓库根目录")
    print(f"      仓库: https://github.com/v4806/ReShade-Launcher（main 分支）")
    print()
    return 0


if __name__ == '__main__':
    sys.exit(main())
