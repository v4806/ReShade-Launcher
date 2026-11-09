# -*- coding: utf-8 -*-
"""构建类型判定。

正常版与排错版放在同一目录、共享 ``_internal``：

    ReShade Launcher Build.exe  正常版，不启用日志
    ReShade Debug.exe           排错版，启用完整日志

源码运行视为 Debug。判定只依赖可执行文件名，因此两个 exe 可以共用同一份
``_internal`` 与运行数据。
"""

import os
import sys


def is_debug_build() -> bool:
    """返回当前是否 Debug 构建（源码运行为 Debug）。"""
    if not getattr(sys, "frozen", False):
        return True
    return "debug" in os.path.basename(sys.executable).lower()
