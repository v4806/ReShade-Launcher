# -*- coding: utf-8 -*-
"""ReShade Launcher 程序入口。"""

import sys

from reshade_launcher.build_info import is_debug_build

if is_debug_build():
    # Debug 构建：在任何业务模块导入前启用完整诊断日志。
    try:
        from reshade_launcher.core.diagnostics import setup_logging

        setup_logging()
    except Exception as exc:
        print("[日志] 初始化诊断日志失败: %s" % (exc,), file=sys.stderr)
else:
    # Release 构建：关闭标准 logging，确保零日志输出与零磁盘写入。
    import logging

    logging.disable(logging.CRITICAL)

from reshade_launcher.app import main

if __name__ == "__main__":
    main()
