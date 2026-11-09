# -*- coding: utf-8 -*-
"""应用根目录与入口脚本位置。

打包环境（PyInstaller）下根目录是 exe 所在目录；源码运行时根目录是项目根目录。
"""

import os
import sys


def get_app_root() -> str:
    """获取应用程序根目录（exe 所在目录或项目根目录）。"""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


APP_ROOT = get_app_root()
ENTRY_SCRIPT = os.path.join(APP_ROOT, "main.py")
