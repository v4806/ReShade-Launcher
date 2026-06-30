# -*- coding: utf-8 -*-
"""
托盘区图标模块
功能：系统托盘图标管理，支持动态更新图标（游戏图标 / 默认图标）
      右键菜单已适配缩放管理器 + 合并显示/隐藏为切换项 + 国际化
"""

import os
from PyQt6.QtCore import QObject, pyqtSignal
from PyQt6.QtGui import QIcon, QAction, QFont
from PyQt6.QtWidgets import QSystemTrayIcon, QMenu

from 翻译管理器 import _tr  # ← 新增：导入翻译函数


class TrayIcon(QObject):
    """系统托盘图标管理器"""
    
    # 信号：与主窗口交互
    exit_requested = pyqtSignal()          # 请求退出应用
    show_window_requested = pyqtSignal()   # 显示主窗口
    hide_window_requested = pyqtSignal()   # 隐藏主窗口
    mod_preset_all_requested = pyqtSignal()    # 处理所有mod预设
    mod_preset_select_requested = pyqtSignal()  # 选择文件夹处理mod预设
    mods_folder_requested = pyqtSignal()        # 打开mods安装目录

    def __init__(self, parent=None):
        super().__init__(parent)
        self.tray_icon = None
        self.current_icon = None
        self.default_icon_path = None
        self.scale_factor = 1.0
        
        # 回调函数，由主窗口提供
        self.get_config_icon_callback = None   # 返回当前配置的 QIcon（或 None）
        self.get_config_name_callback = None   # 返回当前配置的显示名称

    def init_tray(self, app_root, scale_factor=1.0, get_icon_cb=None, get_name_cb=None):
        """
        初始化托盘图标
        :param app_root: 应用程序根目录，用于定位默认图标 icon.ico
        :param scale_factor: 缩放系数（从主窗口传入）
        :param get_icon_cb: 回调，返回当前配置的 QIcon
        :param get_name_cb: 回调，返回当前配置的显示名称
        """
        self.scale_factor = scale_factor
        self.get_config_icon_callback = get_icon_cb
        self.get_config_name_callback = get_name_cb
        
        # 默认图标路径
        self.default_icon_path = os.path.join(app_root, "icon.ico")
        if not os.path.exists(self.default_icon_path):
            self.default_icon_path = None

        # 创建托盘图标对象
        self.tray_icon = QSystemTrayIcon(self)
        
        # 设置右键菜单（已缩放）
        self.tray_menu = QMenu()
        self._setup_menu()
        self.tray_icon.setContextMenu(self.tray_menu)
        
        # 连接激活信号（双击等）
        self.tray_icon.activated.connect(self._on_tray_activated)
        
        # 设置初始图标
        self.update_icon()
        
        # 显示托盘图标
        self.tray_icon.show()

    def _setup_menu(self):
        """构建右键菜单，并应用缩放样式"""
        sf = self.scale_factor
        padding_item = int(5 * sf)
        padding_horizontal = int(20 * sf)
        border_radius = int(6 * sf)
        separator_height = int(1 * sf)
        separator_margin = int(4 * sf)
        menu_padding = int(8 * sf)

        # ---------- ✨ 合并后的切换菜单项（显示/隐藏二合一）----------
        self.toggle_action = QAction(_tr("tray.show"), self)  # 初始文本，弹出时会更新
        self.toggle_action.triggered.connect(self._on_toggle_window)
        self.tray_menu.addAction(self.toggle_action)
        # ------------------------------------------------------------

        # ---------- mod 功能 ----------
        mod_preset_all_action = QAction(_tr("tray.mod_preset_all"), self)
        mod_preset_all_action.triggered.connect(self.mod_preset_all_requested.emit)
        self.tray_menu.addAction(mod_preset_all_action)

        mod_preset_select_action = QAction(_tr("tray.mod_preset_select"), self)
        mod_preset_select_action.triggered.connect(self.mod_preset_select_requested.emit)
        self.tray_menu.addAction(mod_preset_select_action)

        mods_folder_action = QAction(_tr("tray.mods_folder"), self)
        mods_folder_action.triggered.connect(self.mods_folder_requested.emit)
        self.tray_menu.addAction(mods_folder_action)

        self.tray_menu.addSeparator()

        quit_action = QAction(_tr("tray.quit"), self)
        quit_action.triggered.connect(self.exit_requested.emit)
        self.tray_menu.addAction(quit_action)

        # ---------- 菜单弹出前动态更新切换项文本 ----------
        self.tray_menu.aboutToShow.connect(self._update_toggle_action_text)
        # ------------------------------------------------

        # 应用缩放样式表
        self.tray_menu.setStyleSheet(f"""
            QMenu {{
                background-color: #2D2D30;
                color: #FFFFFF;
                border: 2px solid #555555;
                border-radius: {border_radius}px;
                padding: {menu_padding}px;
            }}
            QMenu::item {{
                padding: {padding_item}px {padding_horizontal}px;
                border-radius: {int(4 * sf)}px;
            }}
            QMenu::item:selected {{
                background-color: #3A3A3E;
                border: 1px solid #555577;
            }}
            QMenu::item:disabled {{
                color: #888888;
            }}
            QMenu::separator {{
                height: {separator_height}px;
                background-color: #555555;
                margin: {separator_margin}px {int(10 * sf)}px;
            }}
        """)
        # 设置菜单字体（强制点大小）
        font = QFont()
        font.setPointSize(max(1, int(12 * sf)))
        self.tray_menu.setFont(font)

    def _update_toggle_action_text(self):
        """根据主窗口当前可见性更新切换菜单项的文本"""
        if self.parent() and hasattr(self.parent(), 'isVisible'):
            if self.parent().isVisible():
                self.toggle_action.setText(_tr("tray.hide"))
            else:
                self.toggle_action.setText(_tr("tray.show"))
        else:
            # 降级：默认显示“显示主窗口”
            self.toggle_action.setText(_tr("tray.show"))

    def _on_toggle_window(self):
        """切换主窗口的显示/隐藏状态"""
        if self.parent() and hasattr(self.parent(), 'isVisible'):
            if self.parent().isVisible():
                self.hide_window_requested.emit()
            else:
                self.show_window_requested.emit()

    def _on_tray_activated(self, reason):
        """托盘图标被激活（单击、双击等）"""
        if reason == QSystemTrayIcon.ActivationReason.DoubleClick:
            # 双击：切换主窗口显示/隐藏
            if self.parent() and hasattr(self.parent(), 'isVisible'):
                if self.parent().isVisible():
                    self.hide_window_requested.emit()
                else:
                    self.show_window_requested.emit()

    def update_icon(self):
        """更新托盘图标：优先使用当前配置的图标，否则使用默认图标"""
        icon = None
        
        if self.get_config_icon_callback:
            try:
                icon = self.get_config_icon_callback()
            except Exception as e:
                print(f"[托盘] 获取配置图标失败: {e}")

        if icon is None or icon.isNull():
            if self.default_icon_path and os.path.exists(self.default_icon_path):
                icon = QIcon(self.default_icon_path)
            else:
                icon = QIcon.fromTheme("application-x-executable")

        if icon and not icon.isNull():
            self.tray_icon.setIcon(icon)
            self.current_icon = icon
            
            tooltip = "启动器"
            if self.get_config_name_callback:
                try:
                    name = self.get_config_name_callback()
                    if name:
                        tooltip = f"启动器 - {name}"
                except Exception:
                    pass
            self.tray_icon.setToolTip(tooltip)
        else:
            print("[托盘] 警告：无法设置托盘图标")

    def hide_tray(self):
        """隐藏托盘图标"""
        if self.tray_icon:
            self.tray_icon.hide()

    def show_tray(self):
        """显示托盘图标"""
        if self.tray_icon:
            self.tray_icon.show()

    def cleanup(self):
        """清理托盘图标（退出时调用）"""
        if self.tray_icon:
            self.tray_icon.hide()
            self.tray_icon.deleteLater()
            self.tray_icon = None
    def show_notification(self, title: str, message: str, duration_ms: int = 5000):
        """显示系统托盘通知（Windows 原生气泡/Toast）"""
        if self.tray_icon and self.tray_icon.isVisible():
            icon = self.current_icon if self.current_icon else QIcon()
            self.tray_icon.showMessage(title, message, icon, duration_ms)