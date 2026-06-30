# -*- coding: utf-8 -*-
"""
终端主界面 - 主窗口和启动代码
（已集成国际化 + 窗口图标同步更新 + 配置菜单缓存修复）
（优化：支持 launch_program, target_program, launch_args 配置字段）
（修复：XXMI 模式保存启动参数）
（重构：将非 GUI 逻辑移至对应模块）
"""

import sys
import os
import threading
import subprocess
import time
from PyQt6.QtCore import Qt, QPoint, QRect, QFileInfo, QSize, QTimer, pyqtSignal
from PyQt6.QtGui import (QColor, QPixmap, QPainter, QPen, QPainterPath,
                         QTextLayout, QTextOption, QIcon, QFont, QBrush, QAction, QMovie)
from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QLabel, QPushButton,
                             QToolButton, QMenu, QWidgetAction, QFileDialog, QFileIconProvider,
                             QSizePolicy, QMessageBox, QDialog, QToolTip)

# ---------- 导入翻译管理器 ----------
from 翻译管理器 import _tr

# 定义用于隐藏控制台窗口的常量（Windows）
if sys.platform == "win32":
    try:
        CREATE_NO_WINDOW = subprocess.CREATE_NO_WINDOW   # Python 3.7+
    except AttributeError:
        CREATE_NO_WINDOW = 0x08000000                   # 手动指定
else:
    CREATE_NO_WINDOW = 0

# -------------------- 窗口检测相关（win32gui）--------------------
try:
    import win32gui
    import win32process
    WIN32_AVAILABLE = True
except ImportError:
    WIN32_AVAILABLE = False
    print("[警告] 未安装 pywin32，窗口检测功能不可用。请执行: pip install pywin32")
# ----------------------------------------------------------------

# 导入自定义模块
from 自定义控件模块 import StrokeLabel_4, ConfigMenuItem, StrokePushButton, StrokeToolButton
from 数据管理模块 import CustomDataManager
from 配置管理器 import ConfigManager
from 缩放管理器 import get_scaling_manager
from 注入启动模块 import validate_launch, launch_game, load_version_config
import reshade配置文件
from 窗口居中模块 import start_center_loop
from 托盘区图标 import TrayIcon
from 进程管理 import ProcessManager
from 对话框模块 import SimpleMessageBox, QuestionDialog, LaunchModeDialog, EditConfigDialog, XXMIGameSelector, DllFileListDialog
from xxmi_scanner import XXMIGameScanner   # 三级扫描器

# -------------------- 桌面快捷方式依赖已移至配置管理器，无需在此导入 --------------------

def get_app_root():
    """获取应用程序根目录（即 exe 所在目录或脚本所在目录）"""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    else:
        return os.path.dirname(os.path.abspath(__file__))

class DesignedWindow(QMainWindow):
    launch_status_signal = pyqtSignal(str)
    game_launched_signal = pyqtSignal(int, int, str, str)
    game_exited_signal = pyqtSignal(int)
    game_window_detected_signal = pyqtSignal()
    fix_shadow_complete = pyqtSignal()

    def __init__(self):
        super().__init__()
        self.app_root = get_app_root()
        self.original_window_width = 800
        self.original_window_height = 600

        self.dragging = False
        self.drag_position = QPoint()
        self.resizing = False
        self.resize_direction = None
        self.resize_start_geometry = QRect()
        self.resize_start_pos = QPoint()

        self.config_manager = ConfigManager(base_dir=self.app_root)
        self.version_config = self._load_version_config()
        self.scaling_manager = get_scaling_manager()
        self.scale_factor = self.scaling_manager.get_scale_factor()
        self.custom_data_manager = CustomDataManager(base_dir=self.app_root)

        # ---------- 配置菜单缓存 ----------
        self.config_menu = None
        self.last_config_dir_mtime = 0.0
        
        # 初始化目录修改时间
        config_dir = self.config_manager.launch_config_dir
        if os.path.exists(config_dir):
            self.last_config_dir_mtime = os.path.getmtime(config_dir)
        self.menu_visible = False

        # ---------- 当前配置相关属性（必须在使用前初始化）----------
        self.current_config = None
        self.current_config_name = None

        # ---------- 设置窗口图标（首次加载默认图标）----------
        self.update_window_icon()   # 此时无配置，会显示软件默认图标

        print(f"使用缩放系数: {self.scale_factor:.2f}")
        print(f"应用程序根目录: {self.app_root}")

        self.current_launch_id = 0
        self.current_game_pid = None
        self.base_config_info = ""
        self.launch_status_signal.connect(self.update_launch_status_text)
        self.game_launched_signal.connect(self.on_game_launched)
        self.game_exited_signal.connect(self._on_game_exited)
        self.game_window_detected_signal.connect(self._on_game_window_detected)
        self.fix_shadow_complete.connect(self._on_fix_shadow_complete)

        self.setup_window_properties()
        self.setup_ui()
        self.setup_mouse_handling()

        # 加载上次选择的配置（此时会更新 self.current_config/name 并更新图标）
        self.load_last_selected_config()

        self.tray_icon = None
        self._init_tray_icon()

        self.process_manager = ProcessManager(self)
        self.launched_by_shortcut = False

        # 窗口检测定时器
        self.window_detection_timer = QTimer(self)
        self.window_detection_timer.timeout.connect(self._check_game_window)
        self.gif_label = QLabel(self.central_widget)
        self.gif_label.setObjectName("gif_layer")
        self.gif_label.setStyleSheet("background-color: transparent;")
        self.gif_label.setScaledContents(True)
        self.gif_label.hide()
        self.gif_label.lower()  # 置于所有控件最底层
        self.movie = None
        self.apply_background()

    def _get_mods_folder_path(self):
        """根据当前配置获取 mods 文件夹的完整路径，若无法确定则返回 None"""
        if not self.current_config:
            return None
        config = self.current_config

        # ===== 通用查找逻辑：收集所有可能的 DLL 路径，逐一检查 mods 文件夹 =====
        candidate_dlls = []

        # 1. 从 dll_files 列表收集
        if config.get('dll_files'):
            for dll in config['dll_files']:
                if dll and os.path.exists(dll):
                    candidate_dlls.append(dll)

        # 2. 从 d3d11_path 收集
        d3d11_path = config.get('d3d11_path')
        if d3d11_path and os.path.exists(d3d11_path) and d3d11_path not in candidate_dlls:
            candidate_dlls.append(d3d11_path)

        # 3. 从 reshade_dll 收集（ReShade64.dll 路径）
        if config.get('reshade_dll'):
            reshade_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                        "ReShade", "ReShade64.dll")
            if os.path.exists(reshade_path) and reshade_path not in candidate_dlls:
                candidate_dlls.append(reshade_path)

        # 4. 针对 XXMI 模式特殊处理：通过 xxmi_launcher_path 定位
        if config.get('mode') == 'xxmi':
            xxmi_launcher = config.get('xxmi_launcher_path')
            if xxmi_launcher and os.path.exists(xxmi_launcher):
                resources_dir = os.path.dirname(os.path.dirname(xxmi_launcher))
                xxmi_root = os.path.dirname(resources_dir)
                # 查找 XXMI 模块目录（尝试从 dll_files 中已有的 d3d11.dll 推断）
                for dll in candidate_dlls:
                    dll_dir = os.path.dirname(dll)
                    mods_path = os.path.join(dll_dir, 'mods')
                    if os.path.isdir(mods_path):
                        return mods_path
                # 如果 dll_files 中没有找到，尝试所有可能的模块目录
                if os.path.isdir(xxmi_root):
                    for entry in os.listdir(xxmi_root):
                        module_dir = os.path.join(xxmi_root, entry)
                        if os.path.isdir(module_dir):
                            mods_path = os.path.join(module_dir, 'mods')
                            if os.path.isdir(mods_path):
                                return mods_path
                            # 如果没有 mods 目录但有 d3d11.dll，返回模块目录下的 mods
                            dll_path = os.path.join(module_dir, 'd3d11.dll')
                            if os.path.exists(dll_path):
                                return os.path.join(module_dir, 'mods')

        # 5. 逐一检查候选 DLL 旁是否有 mods 目录
        for dll in candidate_dlls:
            dll_dir = os.path.dirname(dll)
            mods_path = os.path.join(dll_dir, 'mods')
            if os.path.isdir(mods_path):
                return mods_path
            # 如果 mods 目录不存在但 DLL 存在，仍然返回 mods 路径（后续可创建）
            return os.path.join(dll_dir, 'mods')

        # 6. 最后尝试游戏 exe 所在目录
        game_dir = config.get('game_dir') or config.get('launch_program', '')
        if game_dir and os.path.exists(game_dir):
            parent = os.path.dirname(game_dir) if os.path.isfile(game_dir) else game_dir
            mods_path = os.path.join(parent, 'mods')
            if os.path.isdir(mods_path):
                return mods_path
            return mods_path  # 即使不存在也返回，后续会创建

        return None

    def create_shortcut_for_config(self, config_name):
        """为指定配置创建桌面快捷方式"""
        custom_data = self.custom_data_manager.get_custom_data(config_name)
        display_name = custom_data.get('display_name', config_name)
        success = self.config_manager.create_desktop_shortcut(config_name, display_name)
        if success:
            self.launch_status_signal.emit(_tr("status.shortcut_created", name=display_name))
        else:
            self.launch_status_signal.emit(_tr("status.shortcut_failed", name=display_name))

    def _on_tray_mod_preset_all(self):
        """托盘菜单：处理当前游戏的所有 mod 预设"""
        if not self.current_config:
            self.launch_status_signal.emit(_tr("status.no_config"))
            return
        # 复用 FileListDemoDialog 的逻辑
        from 对话框模块 import FileListDemoDialog, WorkerThread
        from PyQt6.QtWidgets import QMessageBox, QFileDialog
        dialog = FileListDemoDialog(self)
        d3dx_path, mods_folder = dialog.get_current_game_paths()
        if not mods_folder or not os.path.isdir(mods_folder):
            reply = QMessageBox.question(
                self, _tr("dialog.info"), _tr("mod_preset.ask_select_mods_folder"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
            if reply == QMessageBox.StandardButton.Yes:
                folder = QFileDialog.getExistingDirectory(
                    self, _tr("file_dialog.select_mods_folder"), "",
                    QFileDialog.Option.ShowDirsOnly)
                if folder:
                    mods_folder = folder
                else:
                    return
            else:
                return
        if not d3dx_path or not os.path.exists(d3dx_path):
            reply = QMessageBox.question(
                self, _tr("dialog.info"), _tr("mod_preset.ask_continue_no_d3dx"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
            if reply != QMessageBox.StandardButton.Yes:
                return
        self.launch_status_signal.emit(_tr("status.mod_preset_running"))
        # 直接运行工作线程（不打开对话框）
        self._worker_thread = WorkerThread(d3dx_path, mods_folder)
        self._worker_thread.finished_signal.connect(
            lambda: self._show_tray_notification(_tr("status.mod_preset_done")))
        self._worker_thread.start()

    def _on_tray_mod_preset_select(self):
        """托盘菜单：选择文件夹处理 mod 预设"""
        if not self.current_config:
            self.launch_status_signal.emit(_tr("status.no_config"))
            return
        from PyQt6.QtWidgets import QFileDialog, QMessageBox
        from 对话框模块 import FileListDemoDialog, WorkerThread
        folder = QFileDialog.getExistingDirectory(
            self, _tr("file_dialog.select_folder"), "",
            QFileDialog.Option.ShowDirsOnly)
        if not folder:
            return
        dialog = FileListDemoDialog(self)
        d3dx_path, _ = dialog.get_current_game_paths()
        if not d3dx_path or not os.path.exists(d3dx_path):
            reply = QMessageBox.question(
                self, _tr("dialog.info"), _tr("mod_preset.ask_continue_no_d3dx"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
            if reply != QMessageBox.StandardButton.Yes:
                return
        self.launch_status_signal.emit(_tr("status.mod_preset_running"))
        self._worker_thread = WorkerThread(d3dx_path, folder)
        self._worker_thread.finished_signal.connect(
            lambda: self._show_tray_notification(_tr("status.mod_preset_done")))
        self._worker_thread.start()

    def _show_tray_notification(self, message):
        """显示系统托盘通知（Windows 原生气泡，窗口隐藏时也能看到）"""
        self.tray_icon.show_notification(_tr("tray.notification_title"), message)
        # 窗口可见时也更新状态栏
        self.launch_status_signal.emit(message)

    def _on_shader_switch(self):
        """着色器精简/完整切换"""
        from 着色器管理 import get_current_state, apply_lite, apply_full, set_reshade_dir
        from PyQt6.QtWidgets import QMessageBox
        reshade_dir = os.path.join(self.app_root, "ReShade")
        set_reshade_dir(reshade_dir)

        current = get_current_state()
        if current == 'full':
            reply = QMessageBox.question(
                self, _tr("dialog.info"),
                _tr("shader.confirm_lite"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
            if reply != QMessageBox.StandardButton.Yes:
                return
            self.launch_status_signal.emit(_tr("shader.lite_running"))
            kept, deleted = apply_lite(lambda msg: self.launch_status_signal.emit(msg))
            self.launch_status_signal.emit(_tr("shader.lite_done", kept=kept, deleted=deleted))
        elif current == 'lite':
            reply = QMessageBox.question(
                self, _tr("dialog.info"),
                _tr("shader.confirm_full"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
            if reply != QMessageBox.StandardButton.Yes:
                return
            self.launch_status_signal.emit(_tr("shader.full_running"))
            ok = apply_full(lambda msg: self.launch_status_signal.emit(msg))
            if ok:
                self.launch_status_signal.emit(_tr("shader.full_done"))
            else:
                self.launch_status_signal.emit(_tr("shader.full_failed"))
        else:
            QMessageBox.warning(self, _tr("dialog.info"), _tr("shader.no_zip"))

    def _open_mods_folder(self):
        """打开当前配置的 mods 文件夹（若不存在则创建，无法确定时让用户手动选择）"""
        folder = self._get_mods_folder_path()
        if not folder:
            # 无法自动确定，弹出文件夹选择对话框让用户手动选择
            from PyQt6.QtWidgets import QFileDialog
            folder = QFileDialog.getExistingDirectory(
                self, _tr("file_dialog.select_mods_folder"), "",
                QFileDialog.Option.ShowDirsOnly)
            if not folder:
                return
            # 将用户选择的路径保存到配置中，供下次使用
            if self.current_config is not None:
                self.current_config['mods_folder'] = folder.replace('\\', '/')
                # 同时保存到配置文件
                config_path = self.config_manager.get_config_path(self.current_config_name)
                if os.path.exists(config_path):
                    import json
                    try:
                        with open(config_path, 'r', encoding='utf-8') as f:
                            cfg = json.load(f)
                        cfg['mods_folder'] = folder.replace('\\', '/')
                        with open(config_path, 'w', encoding='utf-8') as f:
                            json.dump(cfg, f, ensure_ascii=False, indent=4)
                    except Exception:
                        pass

        # 确保文件夹存在
        if not os.path.exists(folder):
            try:
                os.makedirs(folder)
            except Exception as e:
                self.launch_status_signal.emit(f"创建 mods 文件夹失败: {e}")
                return

        try:
            if os.name == 'nt':
                os.startfile(folder)
            else:
                import subprocess
                subprocess.Popen(['xdg-open', folder])
        except Exception as e:
            self.launch_status_signal.emit(f"打开文件夹失败: {e}")

    def _on_fix_shadow_complete(self):
        """修复阴影线程完成后的回调（主线程）"""
        # 恢复按钮状态
        self.button_2.setEnabled(True)
        # 更新状态提示
        self.launch_status_signal.emit(_tr("status.depth_toggled"))
        # 延迟500ms后自动启动游戏
        from PyQt6.QtCore import QTimer
        QTimer.singleShot(500, self.on_button_7_clicked)

    # ---------- 获取应用程序默认图标 ----------
    def get_app_icon(self):
        """从 exe 所在目录或临时目录加载 icon.ico"""
        icon_path = None
        root_icon = os.path.join(self.app_root, "icon.ico")
        if os.path.exists(root_icon):
            icon_path = root_icon
        elif hasattr(sys, '_MEIPASS'):
            meipass_icon = os.path.join(sys._MEIPASS, "icon.ico")
            if os.path.exists(meipass_icon):
                icon_path = meipass_icon
        if icon_path:
            return QIcon(icon_path)
        return QIcon()

    # ---------- 更新窗口图标（与托盘图标逻辑一致）----------
    def update_window_icon(self):
        """根据当前配置更新窗口图标（任务栏/任务管理器）"""
        icon = None
        if self.current_config and self.current_config_name:
            game_exe_path = self.current_config.get('game_dir', '')
            custom_data = self.custom_data_manager.get_custom_data(self.current_config_name)
            icon = self.get_config_icon(self.current_config_name, game_exe_path, custom_data)
        if icon is None or icon.isNull():
            icon = self.get_app_icon()
        if not icon.isNull():
            self.setWindowIcon(icon)

    # ---------- 配置菜单缓存刷新标记（已修复缓存失效问题）----------
    def _should_rebuild_config_menu(self):
        """检查配置目录是否有变化（仅依赖目录修改时间，稳定可靠）"""
        config_dir = self.config_manager.launch_config_dir
        if not os.path.exists(config_dir):
            return True
        try:
            current_mtime = os.path.getmtime(config_dir)
            if current_mtime != self.last_config_dir_mtime:
                self.last_config_dir_mtime = current_mtime
                return True
        except Exception as e:
            print(f"[菜单缓存] 获取目录修改时间失败: {e}")
        return False

    def _load_version_config(self):
        return reshade配置文件.load_version_config(self.app_root)

    def load_and_launch_config(self, config_file):
        if not os.path.isabs(config_file):
            config_path = os.path.join(self.config_manager.launch_config_dir, config_file)
        else:
            config_path = config_file
        if not os.path.exists(config_path):
            print(f"[快捷启动] 配置文件不存在: {config_path}")
            return False
        config_data = self.config_manager.load_json(config_path)
        if not config_data:
            print(f"[快捷启动] 无法加载配置: {config_file}")
            return False
        config_name = os.path.splitext(os.path.basename(config_file))[0]
        self.current_config = config_data
        self.current_config_name = config_name
        self.update_button8_icon(config_name)
        self.update_config_display(config_name, config_data)
        self.update_tray_icon()          # 会同时更新窗口图标
        # ---------- ✨ 标记为快捷方式启动 ----------
        self.launched_by_shortcut = True
        # ----------------------------------------
        
        # ✅ 关键修改：通过 lambda 传递 shortcut=True
        QTimer.singleShot(50, lambda: self.on_button_7_clicked(shortcut=True))
        return True

    def get_resource_path(self, filename):
        """获取资源文件路径，优先使用自定义背景"""
        if filename == 'b.png':
            custom_bg = self.custom_data_manager.get_global_setting('background_image')
            if custom_bg and os.path.exists(custom_bg):
                return custom_bg
        path = os.path.join(self.app_root, filename)
        if os.path.exists(path):
            return path
        if hasattr(sys, '_MEIPASS'):
            path = os.path.join(sys._MEIPASS, filename)
            if os.path.exists(path):
                return path
        return filename

    def setup_window_properties(self):
        scaled_width = int(self.original_window_width * self.scale_factor)
        scaled_height = int(self.original_window_height * self.scale_factor)
        self.setWindowTitle(_tr("main.title"))
        self.resize(scaled_width, scaled_height)
        self.setFixedSize(scaled_width, scaled_height)

    def setup_ui(self):
        """设置UI界面 - 使用缩放系数调整所有尺寸，字体通过 QFont 设置"""
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)

        self.central_widget.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.central_widget.setStyleSheet("background-color: transparent;")

        scaled_width = int(self.original_window_width * self.scale_factor)
        scaled_height = int(self.original_window_height * self.scale_factor)
        self.central_widget.setGeometry(0, 0, scaled_width, scaled_height)

        # 标签控件 1（背景图片深色遮罩）
        label1_x, label1_y, label1_w, label1_h = self.scaling_manager.scale_rect(0, 0, 800, 605)
        self.label_1 = QLabel('', self.central_widget)
        self.label_1.setGeometry(label1_x, label1_y, label1_w, label1_h)
        label1_padding = int(10 * self.scale_factor)
        label1_border_radius = int(5 * self.scale_factor)
        self.label_1.setStyleSheet(f"""
        QLabel {{
            background-color: rgba(45, 45, 48, 0.5);
            color: #FFFFFF;
            border-radius: {label1_border_radius}px;
            border: 1px solid #555555;
            padding: {label1_padding}px;
            white-space: pre-wrap;
        }}
        """)
        font = QFont("Microsoft YaHei", max(1, int(14 * self.scale_factor)))
        font.setWeight(QFont.Weight.Normal)
        font.setStyle(QFont.Style.StyleNormal)
        self.label_1.setFont(font)
        self.label_1.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        self.label_1.setWindowOpacity(0.5)
        self.label_1.setWordWrap(False)
        self.label_1.show()

        # 按钮 2 - 修复阴影颠倒
        btn2_x, btn2_y, btn2_w, btn2_h = self.scaling_manager.scale_rect(490, 550, 160, 40)
        self.button_2 = StrokePushButton(_tr('button.fix_shadow'), self.central_widget)
        self.button_2.setGeometry(btn2_x, btn2_y, btn2_w, btn2_h)
        self.button_2.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        btn_border_radius = int(5 * self.scale_factor)
        btn_padding = int(5 * self.scale_factor)
        self.button_2.setStyleSheet(f"""
        QPushButton {{
            background-color: rgba(85, 85, 127, 0.38);
            color: #FFFFFF;
            border-radius: {btn_border_radius}px;
            border: 3px solid #bababa;
            padding: {btn_padding}px;
        }}
        QPushButton:hover {{
            background-color: rgba(0, 90, 158, 0.38);
            color: #FFFFFF;
        }}
        QPushButton:pressed {{
            background-color: rgba(0, 63, 107, 0.38);
        }}
        QPushButton:disabled {{
            background-color: #555555;
            color: #AAAAAA;
        }}
        """)
        btn_font = QFont("Microsoft YaHei", max(1, int(12 * self.scale_factor)))
        self.button_2.setFont(btn_font)
        self.button_2.setToolTip(_tr("button.fix_shadow.tooltip"))
        self.button_2.setWindowOpacity(0.38)
        self.button_2.show()
        self.button_2.clicked.connect(self.on_button_2_clicked)

        # 按钮 3 - 添加游戏
        btn3_x, btn3_y, btn3_w, btn3_h = self.scaling_manager.scale_rect(150, 550, 160, 40)
        self.button_3 = StrokePushButton(_tr('button.add_game'), self.central_widget)
        self.button_3.setGeometry(btn3_x, btn3_y, btn3_w, btn3_h)
        self.button_3.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        self.button_3.setStyleSheet(f"""
        QPushButton {{
            background-color: rgba(85, 85, 127, 0.38);
            color: #FFFFFF;
            border-radius: {btn_border_radius}px;
            border: 3px solid #bababa;
            padding: {btn_padding}px;
        }}
        QPushButton:hover {{
            background-color: rgba(0, 90, 158, 0.38);
            color: #FFFFFF;
        }}
        QPushButton:pressed {{
            background-color: rgba(0, 63, 107, 0.38);
        }}
        QPushButton:disabled {{
            background-color: #555555;
            color: #AAAAAA;
        }}
        """)
        self.button_3.setFont(btn_font)
        self.button_3.setToolTip(_tr("button.add_game.tooltip"))
        self.button_3.setWindowOpacity(0.38)
        self.button_3.show()
        self.button_3.clicked.connect(self.on_button_3_clicked)

        # 标签控件 4 - 描边标签（初始文本留空，由状态更新）
        label4_x, label4_y, label4_w, label4_h = self.scaling_manager.scale_rect(0, 0, 800, 550)
        self.label_4 = StrokeLabel_4('', self.central_widget)
        self.label_4.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        label4_font_size = max(1, int(14 * self.scale_factor))
        label4_padding = int(10 * self.scale_factor)
        label4_border_radius = int(5 * self.scale_factor)
        label4_stroke_width = int(2 * self.scale_factor)
        label_4_props = {
            'text': '',
            'background_color': '#2D2D30',
            'text_color': '#FFFFFF',
            'font_size': label4_font_size,
            'font_family': 'Microsoft YaHei',
            'font_bold': False,
            'font_italic': False,
            'border_radius': label4_border_radius,
            'border_width': 0,
            'border_color': '#555555',
            'border_style': 'solid',
            'width': label4_w,
            'height': label4_h,
            'position_x': label4_x,
            'position_y': label4_y,
            'opacity': 0.0,
            'tooltip': '',
            'enabled': True,
            'visible': True,
            'alignment': 'left_top',
            'padding': label4_padding,
            'stroke_width': label4_stroke_width,
            'stroke_color': '#000000',
            'word_wrap': False
        }
        self.label_4.set_properties(label_4_props)
        self.label_4.setGeometry(label4_x, label4_y, label4_w, label4_h)
        self.label_4.setStyleSheet(f"""
        QLabel {{
            background-color: rgba(45, 45, 48, 0.0);
            color: #FFFFFF;
            border-radius: {label4_border_radius}px;
            border: none;
            padding: {label4_padding}px;
            white-space: pre-wrap;
        }}
        """)
        self.label_4.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        self.label_4.setWindowOpacity(0.0)
        self.label_4.setWordWrap(False)
        self.label_4.show()

        # 按钮 5 - 强制关闭游戏
        btn5_x, btn5_y, btn5_w, btn5_h = self.scaling_manager.scale_rect(320, 550, 160, 40)
        self.button_5 = StrokePushButton(_tr('button.force_close'), self.central_widget)
        self.button_5.setGeometry(btn5_x, btn5_y, btn5_w, btn5_h)
        self.button_5.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        self.button_5.setStyleSheet(f"""
        QPushButton {{
            background-color: rgba(85, 85, 127, 0.38);
            color: #FFFFFF;
            border-radius: {btn_border_radius}px;
            border: 3px solid #bababa;
            padding: {btn_padding}px;
        }}
        QPushButton:hover {{
            background-color: rgba(0, 90, 158, 0.38);
            color: #FFFFFF;
        }}
        QPushButton:pressed {{
            background-color: rgba(0, 63, 107, 0.38);
        }}
        QPushButton:disabled {{
            background-color: #555555;
            color: #AAAAAA;
        }}
        """)
        self.button_5.setFont(btn_font)
        self.button_5.setToolTip(_tr("button.force_close.tooltip"))
        self.button_5.setWindowOpacity(0.38)
        self.button_5.show()
        self.button_5.clicked.connect(self.on_button_5_clicked)

        # 按钮 6 - 帮助（宽度改为60）
        btn6_x, btn6_y, btn6_w, btn6_h = self.scaling_manager.scale_rect(660, 550, 60, 40)
        self.button_6 = StrokePushButton(_tr('button.help'), self.central_widget)
        self.button_6.setGeometry(btn6_x, btn6_y, btn6_w, btn6_h)
        self.button_6.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        self.button_6.setStyleSheet(f"""
        QPushButton {{
            background-color: rgba(85, 85, 127, 0.38);
            color: #FFFFFF;
            border-radius: {btn_border_radius}px;
            border: 3px solid #bababa;
            padding: {btn_padding}px;
        }}
        QPushButton:hover {{
            background-color: rgba(0, 90, 158, 0.38);
            color: #FFFFFF;
        }}
        QPushButton:pressed {{
            background-color: rgba(0, 63, 107, 0.38);
        }}
        QPushButton:disabled {{
            background-color: #555555;
            color: #AAAAAA;
        }}
        """)
        self.button_6.setFont(btn_font)
        self.button_6.setToolTip(_tr("button.help.tooltip"))
        self.button_6.setWindowOpacity(0.38)
        self.button_6.show()
        self.button_6.clicked.connect(self.on_button_6_clicked)

        # 按钮 8 - 配置选择按钮（图标按钮）
        btn8_x, btn8_y, btn8_w, btn8_h = self.scaling_manager.scale_rect(10, 550, 40, 40)
        self.button_8 = QToolButton(self.central_widget)
        self.button_8.setGeometry(btn8_x, btn8_y, btn8_w, btn8_h)
        self.button_8.setIcon(self.get_arrow_icon())
        self.button_8.setIconSize(QSize(24, 24))
        self.button_8.setStyleSheet(f"""
        QToolButton {{
            background-color: rgba(85, 85, 127, 0.38);
            color: #FFFFFF;
            border-radius: {btn_border_radius}px;
            border: 3px solid #bababa;
        }}
        QToolButton:hover {{
            background-color: rgba(0, 90, 158, 0.38);
            color: #FFFFFF;
        }}
        QToolButton:pressed {{
            background-color: rgba(0, 63, 107, 0.38);
        }}
        QToolButton:disabled {{
            background-color: #555555;
            color: #AAAAAA;
        }}
        """)
        btn_font_large = QFont("Microsoft YaHei", max(1, int(18 * self.scale_factor)))
        self.button_8.setFont(btn_font_large)
        self.button_8.setToolTip(_tr("button.select_config.tooltip"))
        self.button_8.setWindowOpacity(0.38)
        self.button_8.show()
        self.button_8.clicked.connect(self.on_button_8_clicked)

        # 按钮 7 - 启动
        btn7_x, btn7_y, btn7_w, btn7_h = self.scaling_manager.scale_rect(60, 550, 80, 40)
        self.button_7 = StrokePushButton(_tr('button.launch'), self.central_widget)
        self.button_7.setGeometry(btn7_x, btn7_y, btn7_w, btn7_h)
        self.button_7.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        self.button_7.setStyleSheet(f"""
        QPushButton {{
            background-color: rgba(85, 85, 127, 0.38);
            color: #FFFFFF;
            border-radius: {btn_border_radius}px;
            border: 3px solid #bababa;
            padding: {btn_padding}px;
        }}
        QPushButton:hover {{
            background-color: rgba(0, 90, 158, 0.38);
            color: #FFFFFF;
        }}
        QPushButton:pressed {{
            background-color: rgba(0, 63, 107, 0.38);
        }}
        QPushButton:disabled {{
            background-color: #555555;
            color: #AAAAAA;
        }}
        """)
        self.button_7.setFont(btn_font)
        self.button_7.setToolTip(_tr("button.launch.tooltip"))
        self.button_7.setWindowOpacity(0.38)
        self.button_7.show()
        self.button_7.clicked.connect(self.on_button_7_clicked)

        # ---------- 新增：右上角“mod预设保存”按钮（已国际化）----------
        btn_text = _tr("button.save_mod_preset")
        new_btn_width = int(160 * self.scale_factor)
        new_btn_height = int(40 * self.scale_factor)
        window_width = int(self.original_window_width * self.scale_factor)
        btn_top_x = window_width - new_btn_width - int(10 * self.scale_factor)
        btn_top_y = int(10 * self.scale_factor)

        self.button_top_right = StrokePushButton(btn_text, self.central_widget)
        self.button_top_right.setGeometry(btn_top_x, btn_top_y, new_btn_width, new_btn_height)
        self.button_top_right.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        self.button_top_right.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {int(5 * self.scale_factor)}px;
                border: 3px solid #bababa;
                padding: {int(5 * self.scale_factor)}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
                color: #FFFFFF;
            }}
            QPushButton:pressed {{
                background-color: rgba(0, 63, 107, 0.38);
            }}
            QPushButton:disabled {{
                background-color: #555555;
                color: #AAAAAA;
            }}
        """)
        btn_font_large = QFont("Microsoft YaHei", max(1, int(12 * self.scale_factor)))
        self.button_top_right.setFont(btn_font_large)
        self.button_top_right.setToolTip(_tr("button.save_mod_preset.tooltip"))
        self.button_top_right.setWindowOpacity(0.38)
        self.button_top_right.show()
        self.button_top_right.clicked.connect(self.on_top_right_button_clicked)

        # ---------- 新增：mods安装目录按钮 ----------
        mods_btn_text = _tr("button.mods_folder")
        mods_btn_y = btn_top_y + new_btn_height + int(10 * self.scale_factor)  # 在预设按钮下方，间距10

        self.button_mods_folder = StrokePushButton(mods_btn_text, self.central_widget)
        self.button_mods_folder.setGeometry(btn_top_x, mods_btn_y, new_btn_width, new_btn_height)
        self.button_mods_folder.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        self.button_mods_folder.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {int(5 * self.scale_factor)}px;
                border: 3px solid #bababa;
                padding: {int(5 * self.scale_factor)}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
                color: #FFFFFF;
            }}
            QPushButton:pressed {{
                background-color: rgba(0, 63, 107, 0.38);
            }}
            QPushButton:disabled {{
                background-color: #555555;
                color: #AAAAAA;
            }}
        """)
        btn_font_large = QFont("Microsoft YaHei", max(1, int(12 * self.scale_factor)))
        self.button_mods_folder.setFont(btn_font_large)
        self.button_mods_folder.setToolTip(_tr("button.mods_folder.tooltip"))
        self.button_mods_folder.setWindowOpacity(0.38)
        self.button_mods_folder.show()
        self.button_mods_folder.clicked.connect(self._open_mods_folder)

        # ---------- 着色器切换按钮 ----------
        shader_btn_text = _tr("button.shader_switch")
        shader_btn_y = mods_btn_y + new_btn_height + int(10 * self.scale_factor)
        self.button_shader = StrokePushButton(shader_btn_text, self.central_widget)
        self.button_shader.setGeometry(btn_top_x, shader_btn_y, new_btn_width, new_btn_height)
        self.button_shader.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        self.button_shader.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {int(5 * self.scale_factor)}px;
                border: 3px solid #bababa;
                padding: {int(5 * self.scale_factor)}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
                color: #FFFFFF;
            }}
            QPushButton:pressed {{
                background-color: rgba(0, 63, 107, 0.38);
            }}
            QPushButton:disabled {{
                background-color: #555555;
                color: #AAAAAA;
            }}
        """)
        self.button_shader.setFont(btn_font_large)
        self.button_shader.setToolTip(_tr("button.shader_switch.tooltip"))
        self.button_shader.setWindowOpacity(0.38)
        self.button_shader.show()
        self.button_shader.clicked.connect(self._on_shader_switch)

        # ---------- 新增齿轮按钮（在帮助按钮右侧，已国际化）----------
        gear_x, gear_y, gear_w, gear_h = self.scaling_manager.scale_rect(730, 550, 40, 40)
        self.button_gear = StrokePushButton(" ", self.central_widget)
        self.button_gear.setGeometry(gear_x, gear_y, gear_w, gear_h)
        self.button_gear.set_stroke_properties(int(2 * self.scale_factor), '#000000')
        self.button_gear.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {int(20 * self.scale_factor)}px;
                border: 3px solid #bababa;
                padding: {int(5 * self.scale_factor)}px;
                font-size: {int(14 * self.scale_factor)}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
                color: #FFFFFF;
            }}
            QPushButton:pressed {{
                background-color: rgba(0, 63, 107, 0.38);
            }}
            QPushButton:disabled {{
                background-color: #555555;
                color: #AAAAAA;
            }}
        """)
        btn_font_large = QFont("Microsoft YaHei", max(1, int(18 * self.scale_factor)))
        self.button_gear.setFont(btn_font_large)
        self.button_gear.setToolTip(_tr("button.change_background.tooltip"))
        self.button_gear.setWindowOpacity(0.38)
        self.button_gear.show()
        self.button_gear.clicked.connect(self.change_background_image)

    def on_top_right_button_clicked(self):
        from 对话框模块 import FileListDemoDialog
        dialog = FileListDemoDialog(self)
        dialog.exec()

    # ---------- 齿轮按钮功能 ----------
    def on_gear_button_clicked(self):
        """齿轮按钮点击：弹出更换背景图片菜单"""
        menu = QMenu(self)
        menu_scale = self.scale_factor * 0.5
        menu.setStyleSheet(f"""
            QMenu {{
                background-color: #2D2D30;
                color: #FFFFFF;
                border: 2px solid #555555;
                border-radius: {int(10 * menu_scale)}px;
                padding: {int(15 * menu_scale)}px {int(10 * menu_scale)}px;
            }}
            QMenu::item {{
                background-color: transparent;
                padding: {int(8 * menu_scale)}px {int(20 * menu_scale)}px;
                border-radius: {int(4 * menu_scale)}px;
                font-size: {int(16 * menu_scale * 2)}px;
            }}
            QMenu::item:selected {{
                background-color: #3A3A3E;
                border: 1px solid #555577;
            }}
        """)
        menu.setMinimumWidth(int(200 * menu_scale * 2))
        change_bg_action = QAction(_tr("menu.change_background"), self)
        change_bg_action.triggered.connect(self.change_background_image)
        menu.addAction(change_bg_action)
        menu.popup(self.button_gear.mapToGlobal(self.button_gear.rect().bottomLeft()))


    # ---------- 更新启动状态文本框 ----------
    def update_launch_status_text(self, status):
        if self.base_config_info:
            full_text = self.base_config_info + "\n" + _tr("status.launch_state") + " " + status
        else:
            full_text = _tr("status.launch_state") + " " + status
        self.label_4.setText(full_text)

    # ---------- 游戏启动成功回调 ----------
    def on_game_launched(self, root_pid, target_pid, game_exe_name, game_dir):
        if target_pid is not None:
            self.process_manager.register_launch(root_pid, target_pid, game_exe_name, game_dir)
            self.current_game_pid = target_pid  # 记录目标 PID 用于窗口检测
            print(f"[主窗口] 已注册启动进程: 根PID={root_pid}, 目标PID={target_pid}, EXE={game_exe_name}")

            # ═══ 窗口强制居中（若配置启用）═══
            if self.current_config and self.current_config.get('force_center_window', False):
                duration = self.current_config.get('center_window_duration', 15)
                print(f"[主窗口] 配置启用了窗口强制居中，持续 {duration} 秒")
                # 延迟启动居中循环，等待游戏窗口完全初始化完成
                from PyQt6.QtCore import QTimer
                QTimer.singleShot(3000, lambda: start_center_loop(target_pid, duration_seconds=duration))
            # ═══════════════════════════════════

            if WIN32_AVAILABLE:
                self.window_detection_timer.start(500)
                print("[主窗口] 窗口检测定时器已启动")
            else:
                print("[主窗口] 窗口检测功能不可用，跳过")

    def _cleanup_and_quit(self):
        """清理并退出应用程序"""
        if not self.button_7.isEnabled():
            print("[主窗口] 检测到游戏正在运行，退出前进行清理...")
            if self.current_config and self.current_config_name:
                game_exe_name = self.current_config.get('game_exe_name', '')
                game_dir = os.path.dirname(self.current_config.get('game_dir', ''))
                self.process_manager.terminate_software_chain(game_exe_name, game_dir)
        self.process_manager.terminate_all_launched_processes()
        QApplication.quit()

    def _check_game_window(self):
        """定时器回调：检测目标游戏窗口是否已出现"""
        if not WIN32_AVAILABLE:
            self.window_detection_timer.stop()
            return
        pid = self.current_game_pid
        if pid is None:
            return
        try:
            found_windows = []
            def enum_windows_callback(hwnd, param):
                if win32gui.IsWindowVisible(hwnd):
                    window_text = win32gui.GetWindowText(hwnd)
                    if window_text:
                        _, window_pid = win32process.GetWindowThreadProcessId(hwnd)
                        if window_pid == pid:
                            found_windows.append(hwnd)
                return True
            win32gui.EnumWindows(enum_windows_callback, None)
            if found_windows:
                print(f"[窗口检测] 发现 {len(found_windows)} 个目标窗口，即将隐藏启动器")
                self.window_detection_timer.stop()
                self.game_window_detected_signal.emit()
        except Exception as e:
            print(f"[窗口检测] 检测过程中出错: {e}")

    def _on_game_window_detected(self):
        """游戏窗口已出现：立即更新状态，延迟1秒后隐藏窗口"""
        self.launch_status_signal.emit(_tr("status.game_started"))
        QTimer.singleShot(50, lambda: self.hide() if self.isVisible() else None)

    def get_arrow_icon(self):
        """获取倒三角箭头图标"""
        try:
            icon_size = 24
            pixmap = QPixmap(icon_size, icon_size)
            pixmap.fill(Qt.GlobalColor.transparent)
            painter = QPainter(pixmap)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.setPen(QPen(QColor(255, 255, 255), 2))
            painter.setBrush(QBrush(QColor(255, 255, 255)))
            points = [
                QPoint(icon_size // 4, icon_size // 3),
                QPoint(icon_size * 3 // 4, icon_size // 3),
                QPoint(icon_size // 2, icon_size * 2 // 3)
            ]
            painter.drawPolygon(points)
            painter.end()
            return QIcon(pixmap)
        except Exception as e:
            print(f"创建箭头图标失败: {e}")
            return QIcon()

    def update_button8_icon(self, config_name=None):
        """更新按钮8的图标"""
        if config_name and self.current_config:
            game_exe_path = self.current_config.get('game_dir', '')
            custom_data = self.custom_data_manager.get_custom_data(config_name)
            icon = self.get_config_icon(config_name, game_exe_path, custom_data)
            if not icon.isNull():
                self.button_8.setIcon(icon)
                self.button_8.setIconSize(QSize(30, 30))
                self.button_8.setText("")
                return
        self.button_8.setIcon(self.get_arrow_icon())
        self.button_8.setIconSize(QSize(24, 24))
        self.button_8.setText("")

    def load_last_selected_config(self):
        """加载上次选择的配置"""
        try:
            last_config = self.custom_data_manager.get_last_selected_config()
            if last_config:
                config_path = os.path.join(self.config_manager.launch_config_dir, f"{last_config}.json")
                if os.path.exists(config_path):
                    config_data = self.config_manager.load_json(config_path)
                    if config_data:
                        self.current_config = config_data
                        self.current_config_name = last_config
                        self.update_button8_icon(last_config)
                        self.update_config_display(last_config, config_data)
                        self.update_window_icon()   # 同步更新窗口图标
                        print(f"已自动加载上次选择的配置: {last_config}")
                        return True
                    else:
                        print(f"配置文件已损坏: {last_config}")
                else:
                    print(f"配置文件不存在: {last_config}")
        except Exception as e:
            print(f"加载上次选择的配置失败: {e}")
        return False

    def save_last_selected_config(self, config_name):
        """保存上次选择的配置"""
        try:
            self.custom_data_manager.set_last_selected_config(config_name)
            print(f"已保存上次选择的配置: {config_name}")
        except Exception as e:
            print(f"保存上次选择的配置失败: {e}")

    def update_config_display(self, config_name, config_data):
        """更新配置显示（同时存储基础信息）"""
        if not config_data:
            return
        custom_data = self.custom_data_manager.get_custom_data(config_name)
        display_name = custom_data.get('display_name', config_name)
        mode = config_data.get('mode', 'unknown')

        mode_text_map = {
            'xxmi': _tr('mode.xxmi'),
            'builtin': _tr('mode.builtin'),
            'reshade': _tr('mode.reshade'),
            'custom': _tr('mode.custom'),
            'game': _tr('mode.game')
        }
        mode_text = mode_text_map.get(mode, _tr('mode.unknown'))

        info_text = _tr("config.selected", name=display_name) + "\n"
        info_text += _tr("config.mode", mode=mode_text) + "\n"

        if 'reshade_dll' in config_data:
            info_text += _tr("reshade.enabled") + "\n"
        if mode == 'xxmi':
            if 'd3d11_path' in config_data:
                # 特殊XXMI模式（Endfield）—— 显示 mod 加载器状态
                if config_data.get('d3d11_exists', False):
                    info_text += _tr("modloader.installed") + "\n"
                else:
                    info_text += _tr("modloader.not_found") + "\n"
            else:
                launcher_name = config_data.get('xxmi_exe_name', _tr('mode.unknown'))
                info_text += _tr("config.launcher", name=launcher_name) + "\n"
        elif mode == 'builtin':
            if config_data.get('d3d11_exists', False):
                info_text += _tr("modloader.installed") + "\n"
            else:
                info_text += _tr("modloader.not_found") + "\n"
        elif mode == 'custom':
            dll_count = len(config_data.get('dll_files', []))
            info_text += _tr("dll.count", count=dll_count) + "\n"
        self.base_config_info = info_text
        self.label_4.setText(info_text)

    def on_button_2_clicked(self):
        """修复阴影颠倒：强制关闭游戏 → 切换深度参数 → 自动重启（全程后台执行）"""
        # ---------- ✨ 用户手动切换配置，取消自动退出 ----------
        self.launched_by_shortcut = False
        # ----------------------------------------------------
        if not self.current_config:
            self.launch_status_signal.emit(_tr("status.error.no_config"))
            return

        # ---------- 获取当前游戏信息（快照）----------
        config = self.current_config
        game_exe_name = config.get('game_exe_name', '')
        if not game_exe_name:
            game_exe_name = os.path.basename(config.get('game_dir', ''))
        game_dir = os.path.dirname(config.get('game_dir', ''))
        game_pid = self.current_game_pid   # 若有记录PID则直接使用，可加速

        # ---------- 界面反馈：禁用按钮，显示状态----------
        self.button_2.setEnabled(False)
        self.launch_status_signal.emit(_tr("status.terminating"))

        # ---------- 启动后台工作线程（避免卡死）----------
        def task():
            # 1. 强制终结游戏进程（使用已知PID或进程名）
            success = self.process_manager.terminate_game_process(
                game_exe_name, game_dir, game_pid=game_pid
            )
            if success:
                # 2. 等待进程完全退出（最多3秒）
                for _ in range(15):
                    if not ProcessManager.is_process_running(game_exe_name):
                        break
                    time.sleep(0.2)
                # 3. 切换 ReShade 深度参数
                reshade配置文件.toggle_depth_upside_down(game_dir, game_exe_name, self.app_root)
            # 4. 发出完成信号（在主线程中重启游戏）
            self.fix_shadow_complete.emit()

        thread = threading.Thread(target=task, daemon=True)
        thread.start()

    def on_button_3_clicked(self):
        """添加游戏按钮点击事件"""
        print("添加游戏按钮被点击")
        from 对话框模块 import LaunchModeDialog
        dialog = LaunchModeDialog(self.config_manager, self)
        dialog.setStyleSheet("""
            QDialog {
                background-color: #2D2D30;
                color: #FFFFFF;
            }
        """)
        if dialog.exec():
            mode = dialog.selected_mode
            enable_reshade = dialog.enable_reshade
            if mode == "xxmi":
                self.handle_xxmi_mode(enable_reshade)
            elif mode == "builtin":
                self.handle_builtin_mode(enable_reshade)
            elif mode == "reshade":
                self.handle_reshade_mode(enable_reshade)
            elif mode == "custom":
                self.handle_custom_mode(enable_reshade)
        else:
            print("用户取消了模式选择")

    def on_button_5_clicked(self):
        """强制关闭当前激活的游戏进程"""
        print("按钮 5 被点击 - 强制关闭游戏进程")
        if not self.current_config:
            self.launch_status_signal.emit(_tr("status.error.no_config"))
            return
        game_exe_name = self.current_config.get('game_exe_name', '')
        game_dir = os.path.dirname(self.current_config.get('game_dir', ''))
        self.process_manager.terminate_game_process(
            game_exe_name,
            game_dir,
            game_pid=self.current_game_pid
        )

    def on_button_6_clicked(self):
        """帮助按钮"""
        print("按钮 6 被点击")
        from 帮助 import HelpDialog
        dialog = HelpDialog(self)
        dialog.exec()

    def on_button_7_clicked(self, shortcut=False):
        """启动按钮点击事件
        :param shortcut: 是否由快捷方式启动触发（True 时保留 launched_by_shortcut 标志）
        """
        # ---------- ✨ 用户手动启动 → 清除自动退出标记；快捷方式启动 → 保留标记 ----------
        if not shortcut:
            self.launched_by_shortcut = False
        # ------------------------------------------------------------------------
        if not self.current_config:
            self.launch_status_signal.emit(_tr("status.error.no_config"))
            return

        ok, error_msg = validate_launch(self.current_config, self.app_root)
        if not ok:
            self.launch_status_signal.emit(f"{_tr('dialog.error')}: {error_msg}")
            return

        game_exe_name = self.current_config.get('game_exe_name', '')
        if not game_exe_name:
            game_exe_name = os.path.basename(self.current_config.get('game_dir', ''))

        # ========== 检测同名进程 ==========
        if ProcessManager.is_process_running(game_exe_name):
            dialog = QuestionDialog(
                _tr("question.title"),
                _tr("question.message", message=f"{game_exe_name} {_tr('status.already_running')}"),
                self
            )
            reply = dialog.exec()
            if reply == QDialog.DialogCode.Accepted:
                self.launch_status_signal.emit(_tr("status.terminating"))

                # ---------- 新增：XXMI 模式需要手动终结进程 ----------
                mode = self.current_config.get('mode')
                if mode == 'xxmi':
                    game_dir = os.path.dirname(self.current_config.get('game_dir', ''))
                    game_pid = self.current_game_pid
                    self.process_manager.terminate_game_process(
                        game_exe_name, game_dir, game_pid=game_pid
                    )
                    # 等待进程完全退出（最多5秒）
                    for _ in range(25):
                        if not ProcessManager.is_process_running(game_exe_name):
                            break
                        time.sleep(0.2)
                # ----------------------------------------------------
            else:
                self.launch_status_signal.emit(_tr("status.cancelled"))
                return
        # ========== 检测结束 ==========

        self.button_7.setEnabled(False)
        self.current_launch_id += 1
        launch_id = self.current_launch_id
        self.launch_status_signal.emit(_tr("status.launching"))
        threading.Thread(
            target=self._launch_game_thread,
            args=(self.current_config, self.app_root, self.version_config,
                launch_id, game_exe_name),
            daemon=True
        ).start()

    def clear_current_config(self):
        """清除当前选中的配置，恢复界面到无配置状态"""
        self.current_config = None
        self.current_config_name = None
        # 更新按钮8图标为箭头
        self.update_button8_icon(None)
        # 清空信息显示
        self.base_config_info = ""
        self.label_4.setText("")
        # 更新窗口图标为默认
        self.update_window_icon()
        # 更新托盘图标
        if self.tray_icon:
            self.tray_icon.update_icon()

    def _launch_game_thread(self, config, script_dir, version_config, launch_id, game_exe_name):
        from 注入启动模块 import ensure_vc_redist
        def status_cb(msg):
            self.launch_status_signal.emit(msg)
        if not ensure_vc_redist(status_cb):
            # 安装失败，终止启动
            self.game_exited_signal.emit(launch_id)  # 确保恢复按钮状态
            return
        try:
            game_dir = os.path.dirname(config.get('game_dir', ''))
            game_exe_name = config.get('game_exe_name', os.path.basename(config.get('game_dir', '')))
            game_name = os.path.splitext(game_exe_name)[0]
            self.current_game_dir = game_dir
            self.current_game_name = game_name
            
            # ❌ 已删除 ReShade 准备和清理的调用
            # 直接启动游戏，不再进行 ReShade 配置的备份、部署、恢复

            result = launch_game(config, script_dir, version_config)
            if result is not None:
                root_pid, target_pid = result
                if target_pid is not None:
                    self.game_launched_signal.emit(root_pid, target_pid, game_exe_name, game_dir)
                else:
                    self.launch_status_signal.emit(_tr("status.launch_failed_no_pid"))
                    return
            else:
                self.launch_status_signal.emit(_tr("status.launch_failed_no_pid"))
                return
            self._wait_for_game_exit(game_exe_name, launch_id)
            # ❌ 已删除 ReShade 清理调用
        except Exception as e:
            if launch_id == self.current_launch_id:
                self.launch_status_signal.emit(f"{_tr('dialog.error')}: {str(e)}")
        finally:
            self.game_exited_signal.emit(launch_id)
            self.window_detection_timer.stop()
            self.current_game_pid = None

    def _wait_for_game_exit(self, process_name, launch_id):
        """等待游戏进程完全退出（阻塞）"""
        import time
        started = False
        for _ in range(30):
            if launch_id != self.current_launch_id:
                return
            if ProcessManager.is_process_running(process_name):
                started = True
                break
            time.sleep(1)
        if not started:
            self.launch_status_signal.emit(_tr("status.launch_timeout"))
            return
        while True:
            if launch_id != self.current_launch_id:
                return
            if not ProcessManager.is_process_running(process_name):
                self.launch_status_signal.emit(_tr("status.game_exited"))
                break
            time.sleep(1)

    def _on_game_exited(self, launch_id):
        if launch_id == self.current_launch_id:
            self.button_7.setEnabled(True)
            self.game_window_appeared = False
            print("[主窗口] 启动按钮已恢复")
            
            # ---------- ✨ 快捷方式启动 → 自动退出 ----------
            if self.launched_by_shortcut:
                print("[主窗口] 快捷方式启动模式，游戏已退出，软件将自动关闭")
                QTimer.singleShot(500, self._cleanup_and_quit)
            else:
                # 非快捷方式启动：如果窗口当前是隐藏的，则恢复显示
                if not self.isVisible():
                    print("[主窗口] 游戏已退出，恢复显示主窗口")
                    self.show_and_activate()
            # ------------------------------------------------

    # ------------------------------------------------------------
    # 🚀 优化：配置菜单缓存 + 修复卡顿问题
    # ------------------------------------------------------------
    def on_button_8_clicked(self):
        """配置选择按钮点击事件 - 菜单打开时按钮禁用，关闭时恢复"""
        print("配置选择按钮被点击")

        # 如果菜单已存在且可见 → 说明按钮此时应被禁用（但以防万一，直接返回）
        if self.config_menu is not None and self.config_menu.isVisible():
            return

        # 菜单不可见 → 正常打开流程
        rebuild_needed = (self.config_menu is None) or self._should_rebuild_config_menu()
        if rebuild_needed:
            print("[菜单缓存] 配置目录有变化或首次打开，重建菜单...")
            self._rebuild_config_menu()

        if self.config_menu:
            # 弹出菜单前先禁用按钮
            self.button_8.setEnabled(False)
            self.config_menu.popup(self.button_8.mapToGlobal(self.button_8.rect().bottomLeft()))
        else:
            # 极低概率：重建失败，强制重建一次
            self._rebuild_config_menu(force=True)
            if self.config_menu:
                self.button_8.setEnabled(False)
                self.config_menu.popup(self.button_8.mapToGlobal(self.button_8.rect().bottomLeft()))
                
    def _rebuild_config_menu(self, force=False):
        """
        重建配置菜单（仅构建 QMenu 对象，不弹出）
        当 force=True 时强制重建（忽略缓存状态）
        """
        from 自定义控件模块 import ConfigMenuItem
        from PyQt6.QtWidgets import QMenu, QWidgetAction
        from PyQt6.QtGui import QFont

        # 删除旧菜单（如果有）
        if self.config_menu is not None:
            self.config_menu.deleteLater()
            self.config_menu = None

        # 计算缩放系数（菜单使用更紧凑的比例）
        menu_scale = self.scale_factor * 0.5

        # ---------- 创建 QMenu 对象 ----------
        menu = QMenu(self)
        menu.aboutToHide.connect(lambda: self.button_8.setEnabled(True))
        menu.setStyleSheet(f"""
        QMenu {{
            background-color: #2D2D30;
            color: #FFFFFF;
            border: 2px solid #555555;
            border-radius: {int(10 * menu_scale)}px;
            padding: {int(15 * menu_scale)}px {int(10 * menu_scale)}px;
        }}
        QMenu::item {{
            background-color: transparent;
            padding: 0px;
            border-radius: {int(6 * menu_scale)}px;
            margin: {int(5 * menu_scale)}px 0;
            min-height: 0px;
        }}
        QMenu::item:selected {{
            background-color: #3A3A3E;
            border: 1px solid #555577;
        }}
        QMenu::item:disabled {{
            color: #888888;
            background-color: transparent;
        }}
        QMenu::separator {{
            height: {int(2 * menu_scale * 1.5)}px;
            background-color: #555555;
            margin: {int(10 * menu_scale * 1.5)}px {int(15 * menu_scale * 1.5)}px;
        }}
        """)
        
        menu_font = QFont()
        menu_font.setPointSize(max(1, int(16 * menu_scale * 1.5)))
        menu.setFont(menu_font)
        menu.setMinimumWidth(int(400 * menu_scale * 1.5))

        # ---------- 获取所有配置文件 ----------
        config_files = self.config_manager.get_all_config_files()

        if config_files:
            for config_file in config_files:
                config_name = os.path.splitext(config_file)[0]
                config_path = os.path.join(self.config_manager.launch_config_dir, config_file)
                config_data = self.config_manager.load_json(config_path)

                if config_data:
                    game_exe_path = config_data.get('game_dir', '')
                    custom_data = self.custom_data_manager.get_custom_data(config_name)
                    display_name = custom_data.get('display_name', config_name)
                    icon = self.get_config_icon(config_name, game_exe_path, custom_data)

                    # ---------- 自定义菜单项控件 ----------
                    menu_item = ConfigMenuItem(
                        config_name,
                        icon,
                        display_name,
                        scale_factor=menu_scale,
                        parent=self
                    )
                    menu_item.edit_requested.connect(self.edit_config)
                    menu_item.shortcut_requested.connect(self.create_shortcut_for_config)

                    # ---------- 将自定义控件封装为 QWidgetAction ----------
                    widget_action = QWidgetAction(menu)
                    widget_action.setDefaultWidget(menu_item)
                    # 连接触发信号（选择配置）
                    widget_action.triggered.connect(
                        lambda checked, cfg=config_data, name=config_name:
                        self.on_config_selected(cfg, name)
                    )
                    menu.addAction(widget_action)

            menu.addSeparator()
        else:
            # 无配置文件时显示提示项（禁用）
            no_config_action = QAction(_tr("menu.no_config"), self)
            no_config_action.setEnabled(False)
            no_config_action.setFont(menu_font)
            menu.addAction(no_config_action)
            menu.addSeparator()

        # ---------- 添加“刷新列表”菜单项 ----------
        refresh_action = QAction(_tr("menu.refresh"), self)
        refresh_action.setIcon(self.get_refresh_icon())
        refresh_action.triggered.connect(self.refresh_config_list)
        refresh_action.setFont(menu_font)
        menu.addAction(refresh_action)

        # ---------- 保存菜单对象 ----------
        self.config_menu = menu

    # ------------------------------------------------------------
    def get_config_icon(self, config_name, game_exe_path, custom_data):
        """获取配置图标"""
        custom_icon_path = custom_data.get('custom_icon_path')
        if custom_icon_path and os.path.exists(custom_icon_path):
            icon = QIcon(custom_icon_path)
            if not icon.isNull():
                return icon
        if game_exe_path and os.path.exists(game_exe_path):
            file_info = QFileInfo(game_exe_path)
            icon_provider = QFileIconProvider()
            icon = icon_provider.icon(file_info)
            if not icon.isNull():
                return icon
        return self.get_default_icon()

    def get_exe_icon(self, exe_path):
        """获取EXE文件图标"""
        try:
            if exe_path and os.path.exists(exe_path):
                file_info = QFileInfo(exe_path)
                icon_provider = QFileIconProvider()
                icon = icon_provider.icon(file_info)
                if icon.isNull():
                    print(f"无法获取图标: {exe_path}")
                    return self.get_default_icon()
                print(f"成功获取EXE图标: {os.path.basename(exe_path)}")
                return icon
            else:
                print(f"EXE文件不存在: {exe_path}")
                return self.get_default_icon()
        except Exception as e:
            print(f"获取EXE图标失败: {e}")
            return self.get_default_icon()

    def get_default_icon(self):
        """获取默认图标"""
        try:
            icon_provider = QFileIconProvider()
            icon = icon_provider.icon(QFileIconProvider.IconType.File)
            if icon.isNull():
                icon_size = int(48 * 1.5)
                pixmap = QPixmap(icon_size, icon_size)
                pixmap.fill(Qt.GlobalColor.transparent)
                painter = QPainter(pixmap)
                painter.setRenderHint(QPainter.RenderHint.Antialiasing)
                painter.setBrush(QBrush(QColor(0, 120, 215)))
                painter.setPen(Qt.PenStyle.NoPen)
                painter.drawRoundedRect(0, 0, icon_size, icon_size, 12, 12)
                painter.setPen(QPen(QColor(255, 255, 255), 3))
                painter.setBrush(Qt.BrushStyle.NoBrush)
                font = painter.font()
                font.setPointSize(int(18 * 1.5))
                painter.setFont(font)
                painter.drawText(icon_size//4, icon_size*3//4, "G")
                painter.end()
                icon = QIcon(pixmap)
            return icon
        except Exception as e:
            print(f"创建默认图标失败: {e}")
            return QIcon()

    def get_refresh_icon(self):
        """获取刷新图标"""
        try:
            icon_size = int(48 * 1.5)
            pixmap = QPixmap(icon_size, icon_size)
            pixmap.fill(Qt.GlobalColor.transparent)
            painter = QPainter(pixmap)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.setPen(QPen(QColor(255, 255, 255), 4))
            painter.setBrush(Qt.BrushStyle.NoBrush)
            offset = icon_size // 6
            painter.drawArc(offset, offset, icon_size - 2*offset, icon_size - 2*offset, 30 * 16, 300 * 16)
            painter.drawLine(icon_size - offset*2, offset*2, icon_size - offset, offset)
            painter.drawLine(icon_size - offset*2, offset*2, icon_size - offset*3, offset*2)
            painter.end()
            return QIcon(pixmap)
        except Exception as e:
            print(f"创建刷新图标失败: {e}")
            return QIcon()

    def on_config_selected(self, config_data, game_name):
        """配置项被选中"""
        print(f"选择了配置: {game_name}")
        self.current_config = config_data
        self.current_config_name = game_name
        self.save_last_selected_config(game_name)
        self.update_button8_icon(game_name)
        self.update_window_icon()   # 同步更新窗口图标

        custom_data = self.custom_data_manager.get_custom_data(game_name)
        display_name = custom_data.get('display_name', game_name)
        mode = config_data.get('mode', 'unknown')

        mode_text_map = {
            'xxmi': _tr('mode.xxmi'),
            'builtin': _tr('mode.builtin'),
            'reshade': _tr('mode.reshade'),
            'custom': _tr('mode.custom'),
            'game': _tr('mode.game')
        }
        mode_text = mode_text_map.get(mode, _tr('mode.unknown'))

        info_text = _tr("config.selected", name=display_name) + "\n"
        info_text += _tr("config.mode", mode=mode_text) + "\n"

        if 'reshade_dll' in config_data:
            info_text += _tr("reshade.enabled") + "\n"
        if mode == 'xxmi':
            if 'd3d11_path' in config_data:
                if config_data.get('d3d11_exists', False):
                    info_text += _tr("modloader.installed") + "\n"
                else:
                    info_text += _tr("modloader.not_found") + "\n"
            else:
                launcher_name = config_data.get('xxmi_exe_name', _tr('mode.unknown'))
                info_text += _tr("config.launcher", name=launcher_name) + "\n"
        elif mode == 'builtin':
            if config_data.get('d3d11_exists', False):
                info_text += _tr("modloader.installed") + "\n"
            else:
                info_text += _tr("modloader.not_found") + "\n"
        elif mode == 'custom':
            dll_count = len(config_data.get('dll_files', []))
            info_text += _tr("dll.count", count=dll_count) + "\n"

        self.base_config_info = info_text
        self.label_4.setText(info_text)
        self.launch_status_signal.emit(_tr("status.config_created", name=display_name))
        self.update_tray_icon()   # 托盘图标也会更新，内部已调用 update_window_icon

    def refresh_config_list(self):
        """刷新配置列表 - 清除菜单缓存，下次点击时重建"""
        print("刷新配置列表")
        if self.config_menu is not None:
            self.config_menu.deleteLater()
            self.config_menu = None
        try:
            config_dir = self.config_manager.launch_config_dir
            if os.path.exists(config_dir):
                self.last_config_dir_mtime = os.path.getmtime(config_dir)
        except Exception as e:
            print(f"[刷新] 获取目录修改时间失败: {e}")

    def edit_config(self, config_name):
        """编辑配置"""
        print(f"编辑配置: {config_name}")
        from 对话框模块 import EditConfigDialog
        config_path = os.path.join(self.config_manager.launch_config_dir, f"{config_name}.json")
        config_data = self.config_manager.load_json(config_path)
        if not config_data:
            self.show_message_box(_tr("dialog.error"), f"无法加载配置: {config_name}")
            return
        custom_data = self.custom_data_manager.get_custom_data(config_name)
        dialog = EditConfigDialog(config_name, config_data, custom_data, self)
        dialog.setStyleSheet("""
            QDialog {
                background-color: #2D2D30;
                color: #FFFFFF;
            }
        """)
        if dialog.exec():
            if dialog.deleted:
                # 如果删除的是当前选中的配置，则清除当前配置
                if config_name == self.current_config_name:
                    self.clear_current_config()
                self.refresh_config_list()
                return
            new_config_data = dialog.get_config_data()
            new_custom_data = dialog.get_custom_data()
            self.config_manager._save_json(config_path, new_config_data)
            self.custom_data_manager.save_custom_data_for_config(config_name, new_custom_data)
            self.show_message_box(_tr("dialog.success"), _tr("edit_config.updated", config_name=config_name))
            self.refresh_config_list()
            if self.current_config and config_name == self.current_config_name:
                self.current_config = new_config_data
                self.update_button8_icon(config_name)
                self.update_tray_icon()

    def show_message_box(self, title, message):
        """显示消息提示框（非启动相关弹窗）"""
        from 对话框模块 import SimpleMessageBox
        msg_box = SimpleMessageBox(title, message, self)
        msg_box.setStyleSheet("""
            QDialog {
                background-color: #2D2D30;
            }
        """)
        msg_box.exec()

    def show_xxmi_file_dialog(self):
        """显示XXMI文件选择器，允许选择任意文件，选择后再验证是否为XXMI Launcher.exe"""
        print("显示XXMI文件选择器")
        while True:
            file_dialog = QFileDialog()
            file_dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
            # 修改过滤器：显示所有文件（也可以同时保留可执行文件选项，但默认显示所有）
            file_dialog.setNameFilter(f"{_tr('filter.all')} (*.*)")
            file_dialog.setWindowTitle(_tr("file_dialog.select_xxmi"))
            if file_dialog.exec():
                selected_files = file_dialog.selectedFiles()
                if selected_files:
                    file_path = selected_files[0]
                    # 调用配置管理器的验证方法（需确保该方法逻辑正确）
                    if self.config_manager.validate_xxmi_exe(file_path):
                        print(f"选择的XXMI文件: {file_path}")
                        return file_path
                    else:
                        self.show_message_box(_tr("dialog.error"), _tr("message.xxmi_invalid"))
                        continue  # 重新选择
            else:
                return None

    def show_exe_file_dialog(self, title=None):
        """显示exe文件选择器"""
        if title is None:
            title = _tr("file_dialog.select_exe")
        print(f"显示exe文件选择器: {title}")
        file_dialog = QFileDialog()
        file_dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
        file_dialog.setNameFilter(f"{_tr('filter.exe')} (*.exe);;{_tr('filter.all')} (*.*)")
        file_dialog.setWindowTitle(title)
        if file_dialog.exec():
            selected_files = file_dialog.selectedFiles()
            if selected_files:
                file_path = selected_files[0]
                if self.config_manager.validate_exe_file(file_path):
                    print(f"选择的exe文件: {file_path}")
                    return file_path
                else:
                    self.show_message_box(_tr("dialog.error"), _tr("message.exe_invalid"))
                    return None
        return None

    def show_dll_file_dialog(self):
        """显示dll文件选择器"""
        print("显示dll文件选择器")
        file_dialog = QFileDialog()
        file_dialog.setFileMode(QFileDialog.FileMode.ExistingFiles)
        file_dialog.setNameFilter(f"{_tr('filter.dll')} (*.dll);;{_tr('filter.all')} (*.*)")
        file_dialog.setWindowTitle(_tr("file_dialog.select_dll"))
        if file_dialog.exec():
            selected_files = file_dialog.selectedFiles()
            valid_files = []
            for file_path in selected_files:
                if self.config_manager.validate_dll_file(file_path):
                    valid_files.append(file_path)
                else:
                    print(f"跳过无效文件: {file_path}")
            if valid_files:
                print(f"选择的dll文件: {valid_files}")
                return valid_files
            else:
                self.show_message_box(_tr("dialog.error"), _tr("message.dll_invalid"))
                return None
        return None

    # ------------------------------------------------------------
    # XXMI 模式处理（使用三级扫描器）
    # ------------------------------------------------------------
    def handle_xxmi_mode(self, enable_reshade):
        """处理XXMI模式（使用三级扫描器）"""
        print(f"选择了XXMI模式，ReShade: {enable_reshade}")

        from 对话框模块 import SimpleMessageBox, XXMIGameSelector

        # 1. 选择 XXMI Launcher
        self.show_message_box(_tr("dialog.info"), _tr("message.xxmi_scan_prompt"))
        xxmi_file = self.show_xxmi_file_dialog()
        if not xxmi_file:
            return

        # 2. 加载游戏列表
        version_cfg = self.version_config
        game_list = version_cfg.get('xxmi_games', [])
        if not game_list:
            print("[XXMI] 未找到 xxmi_games 字段，尝试从旧配置构建列表")
            game_list = []
            exe_names = version_cfg.get('xxmi_game_exe_name', [])
            for exe in exe_names:
                name = os.path.splitext(exe)[0]
                game_list.append({'exe': exe, 'name': name})
            if not game_list:
                for key in version_cfg:
                    if key.startswith('xxmi_launch_args_'):
                        game_id = key.replace('xxmi_launch_args_', '')
                        exe = f"{game_id}.exe"
                        game_list.append({'exe': exe, 'name': game_id})
        if not game_list:
            self.show_message_box(_tr("dialog.error"), _tr("message.xxmi_no_games"))
            return

        # 3. 游戏选择对话框
        selector = XXMIGameSelector(game_list, self)
        if not selector.exec():
            return
        selected = selector.selected_game
        target_exe_name = selected['exe']
        name_key = selected.get('name_key')
        display_name = _tr(name_key) if name_key else target_exe_name

        self.launch_status_signal.emit(_tr("message.xxmi_scanning"))

        # 构建额外扫描目录（来自 XXMI Launcher 所在位置）
        extra_paths = []
        xxmi_dir = os.path.dirname(xxmi_file)
        if os.path.exists(xxmi_dir):
            extra_paths.append(xxmi_dir)
        xxmi_root = os.path.dirname(xxmi_dir)
        if os.path.exists(xxmi_root):
            extra_paths.append(xxmi_root)
        xxmi_base = os.path.dirname(xxmi_root)
        if os.path.exists(xxmi_base):
            extra_paths.append(xxmi_base)
            games_dir = os.path.join(xxmi_base, "Games")
            if os.path.exists(games_dir):
                extra_paths.append(games_dir)

        # 使用新三级扫描器
        self.scanner = XXMIGameScanner(self)
        self._scan_found = False

        def on_scan_found(path):
            self._scan_found = True
            if hasattr(self, 'scan_progress_dialog') and self.scan_progress_dialog:
                self.scan_progress_dialog.accept()
                self.scan_progress_dialog = None
            self._on_game_found_for_xxmi(xxmi_file, path, display_name, enable_reshade)

        def on_scan_finished():
            if hasattr(self, 'scan_progress_dialog') and self.scan_progress_dialog:
                self.scan_progress_dialog.accept()
                self.scan_progress_dialog = None
            if not self._scan_found:
                reply = QMessageBox.question(
                    self,
                    _tr("dialog.info"),
                    _tr("message.xxmi_not_found", exe=target_exe_name),
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
                )
                if reply == QMessageBox.StandardButton.Yes:
                    game_file = self.show_exe_file_dialog(_tr("file_dialog.select_exe"))
                    if game_file:
                        self._on_game_found_for_xxmi(xxmi_file, game_file, display_name, enable_reshade)

        self.scanner.found_signal.connect(on_scan_found)
        self.scanner.finished_signal.connect(on_scan_finished)

        self.scan_progress_dialog = SimpleMessageBox(
            _tr("dialog.info"),
            _tr("message.xxmi_scan_progress"),
            self
        )
        self.scan_progress_dialog.show()

        self.scanner.scan(target_exe_name, extra_paths)

    def _on_game_found_for_xxmi(self, xxmi_file, game_file, display_name, enable_reshade):
        """扫描到游戏文件后自动创建配置并生成桌面快捷方式"""
        # ========== XXMI 模式不再使用旧版 xxmi_launch_args（已废弃），使用默认 -force-d3d11 ==========

        # 保存配置，并传入 version_config 以便修改 XXMI 配置文件
        config, config_name = self.config_manager.save_xxmi_config(
            game_exe_path=game_file,
            xxmi_exe_path=xxmi_file,
            enable_reshade=enable_reshade,
            # launch_args 不传 → 使用 _determine_programs 的默认值 -force-d3d11
            version_config=self.version_config
        )

        config_path = self.config_manager.get_config_path(config_name)

        self.custom_data_manager.update_custom_data(config_name, 'display_name', display_name)

        self.current_config = config
        self.current_config_name = config_name
        self.update_button8_icon(config_name)
        self.save_last_selected_config(config_name)
        self.update_config_display(config_name, config)
        self.update_tray_icon()   # 会同时更新窗口图标

        # 创建桌面快捷方式（使用配置管理器的方法）
        self.config_manager.create_desktop_shortcut(config_name, display_name)
        # ❌ 已删除 ReShade 预设文件和 Addon 文件的复制

        self.show_message_box(
            _tr("dialog.success"),
            _tr("message.xxmi_success", name=display_name, path=config_path)
        )
        self.launch_status_signal.emit(_tr("status.config_created", name=display_name))
        self.refresh_config_list()

    
    # ------------------------------------------------------------
    # 其他模式处理
    # ------------------------------------------------------------
    def handle_builtin_mode(self, enable_reshade):
        """处理内置模式"""
        print(f"选择了内置模式，ReShade: {enable_reshade}")
        self.show_message_box(_tr("dialog.info"), _tr("message.builtin_prompt"))
        game_file = self.show_exe_file_dialog()
        if game_file:
            config, config_name = self.config_manager.save_builtin_config(
                game_exe_path=game_file,
                enable_reshade=enable_reshade
            )
            config_path = self.config_manager.get_config_path(config_name)
            self.current_config = config
            self.current_config_name = config_name
            self.update_button8_icon(config_name)
            self.save_last_selected_config(config_name)
            self.update_config_display(config_name, config)
            self.update_tray_icon()   # 同步更新窗口图标

            # 获取显示名称
            custom_data = self.custom_data_manager.get_custom_data(config_name)
            display_name = custom_data.get('display_name', config_name)

            # 创建桌面快捷方式
            self.config_manager.create_desktop_shortcut(config_name, display_name)
            # ❌ 已删除 ReShade 预设文件和 Addon 文件的复制

            if config.get('d3d11_exists', False):
                print(f"内置模式配置已保存（找到d3d11.dll）: {config_path}")
                self.show_message_box(
                    _tr("dialog.success"),
                    _tr("message.builtin_success_with_d3d11", path=config_path)
                )
            else:
                print(f"内置模式配置已保存（未找到d3d11.dll）: {config_path}")
                self.show_message_box(
                    _tr("dialog.info"),
                    _tr("message.builtin_no_d3d11")
                )
                self.config_manager.open_mod_loader_directory(self.config_manager.get_game_name_from_exe(game_file))
            self.refresh_config_list()
        else:
            print("用户取消了文件选择")

    def handle_reshade_mode(self, enable_reshade):
        """处理ReShade模式"""
        print(f"选择了ReShade模式，ReShade: {enable_reshade}")
        self.show_message_box(_tr("dialog.info"), _tr("message.reshade_prompt"))
        game_file = self.show_exe_file_dialog()
        if game_file:
            config, config_name = self.config_manager.save_reshade_config(
                game_exe_path=game_file,
                enable_reshade=enable_reshade
            )
            config_path = self.config_manager.get_config_path(config_name)
            self.current_config = config
            self.current_config_name = config_name
            self.update_button8_icon(config_name)
            self.save_last_selected_config(config_name)
            self.update_config_display(config_name, config)
            self.update_tray_icon()

            # 获取显示名称
            custom_data = self.custom_data_manager.get_custom_data(config_name)
            display_name = custom_data.get('display_name', config_name)

            self.config_manager.create_desktop_shortcut(config_name, display_name)
            # ❌ 已删除 ReShade 预设文件和 Addon 文件的复制

            print(f"ReShade模式配置已保存: {config_path}")
            self.show_message_box(
                _tr("dialog.success"),
                _tr("message.reshade_success", path=config_path)
            )
            self.refresh_config_list()
        else:
            print("用户取消了文件选择")

    def handle_custom_mode(self, enable_reshade):
        """处理自定义模式"""
        print(f"选择了自定义模式，ReShade: {enable_reshade}")
        from 对话框模块 import DllFileListDialog

        self.show_message_box(_tr("dialog.info"), _tr("message.custom_dll_prompt"))
        dll_dialog = DllFileListDialog(self)
        dll_dialog.setStyleSheet(""" QDialog { background-color: #2D2D30; } """)
        if dll_dialog.exec():
            selected_dlls = dll_dialog.dll_files
            print(f"自定义模式：添加了{len(selected_dlls)}个DLL文件: {selected_dlls}")
            if not selected_dlls:
                self.show_message_box(_tr("dialog.info"), _tr("message.custom_no_dlls"))
                return
            self.show_message_box(_tr("dialog.info"), _tr("message.custom_game_prompt"))
            game_file = self.show_exe_file_dialog()
            if game_file:
                config, config_name = self.config_manager.save_custom_config(
                    game_exe_path=game_file,
                    dll_files=selected_dlls,
                    enable_reshade=enable_reshade
                )
                config_path = self.config_manager.get_config_path(config_name)
                self.current_config = config
                self.current_config_name = config_name
                self.update_button8_icon(config_name)
                self.save_last_selected_config(config_name)
                self.update_config_display(config_name, config)
                self.update_tray_icon()

                # 获取显示名称
                custom_data = self.custom_data_manager.get_custom_data(config_name)
                display_name = custom_data.get('display_name', config_name)

                self.config_manager.create_desktop_shortcut(config_name, display_name)
                # ❌ 已删除 ReShade 预设文件和 Addon 文件的复制

                print(f"自定义模式配置已保存: {config_path}")
                self.show_message_box(
                    _tr("dialog.success"),
                    _tr("message.custom_success", path=config_path)
                )
                self.refresh_config_list()
            else:
                print("用户取消了主程序文件选择")
        else:
            print("用户取消了DLL文件添加")

    def apply_background(self):
        """根据当前设置启用或禁用 GIF 背景"""
        custom_bg = self.custom_data_manager.get_global_setting('background_image')
        if custom_bg and os.path.exists(custom_bg) and custom_bg.lower().endswith('.gif'):
            if self.movie:
                self.movie.stop()
                self.movie.deleteLater()
            self.movie = QMovie(custom_bg)
            self.movie.frameChanged.connect(self.update)  # 每帧触发重绘
            self.movie.start()
        else:
            if self.movie:
                self.movie.stop()
                self.movie = None
            self.update()  # 重绘静态背景

    def draw_static_background(self, painter):
        """绘制静态背景（纯色 + b.png）"""
        painter.fillRect(self.rect(), QColor('#2D2D30'))
        bg_filename = 'b.png'
        bg_image_path = self.get_resource_path(bg_filename)
        try:
            bg_pixmap = QPixmap(bg_image_path)
            if not bg_pixmap.isNull():
                scaled_pixmap = bg_pixmap.scaled(
                    self.size(),
                    Qt.AspectRatioMode.KeepAspectRatioByExpanding,
                    Qt.TransformationMode.SmoothTransformation
                )
                x = (self.width() - scaled_pixmap.width()) // 2
                y = (self.height() - scaled_pixmap.height()) // 2
                painter.drawPixmap(x, y, scaled_pixmap)
        except Exception as e:
            print(f"加载背景图片失败: {e}")

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)

        # 优先绘制 GIF 背景
        if self.movie and self.movie.state() == QMovie.MovieState.Running:
            pixmap = self.movie.currentPixmap()
            if not pixmap.isNull():
                scaled_pixmap = pixmap.scaled(
                    self.size(),
                    Qt.AspectRatioMode.KeepAspectRatioByExpanding,
                    Qt.TransformationMode.SmoothTransformation
                )
                x = (self.width() - scaled_pixmap.width()) // 2
                y = (self.height() - scaled_pixmap.height()) // 2
                painter.drawPixmap(x, y, scaled_pixmap)
            else:
                self.draw_static_background(painter)
        else:
            self.draw_static_background(painter)

        painter.end()

    def change_background_image(self):
        """打开文件选择器，选择图片并保存为背景（已国际化）"""
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            _tr("dialog.select_background"),
            "",
            f"{_tr('filter.image')} (*.png *.jpg *.jpeg *.bmp *.gif);;{_tr('filter.all')} (*.*)"
        )
        if file_path:
            self.custom_data_manager.set_global_setting('background_image', file_path)
            self.apply_background()  # 立即应用新背景
            from 对话框模块 import SimpleMessageBox
            SimpleMessageBox(_tr("dialog.info"), _tr("message.background_updated"), self).exec()

    def setup_mouse_handling(self):
        self.dragging = False
        self.drag_position = QPoint()
        self.resizing = False
        self.resize_direction = None
        self.resize_start_geometry = QRect()
        self.resize_start_pos = QPoint()
        self.setMouseTracking(True)
        self.central_widget.setMouseTracking(True)

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            pos = event.pos()
            if self.movable() and self.is_draggable_area(pos):
                self.dragging = True
                self.drag_position = event.globalPosition().toPoint() - self.frameGeometry().topLeft()
                if self.show_drag_cursor():
                    self.setCursor(Qt.CursorShape.ClosedHandCursor)
                return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        pos = event.pos()
        if event.buttons() == Qt.MouseButton.LeftButton and self.dragging and self.movable():
            self.move(event.globalPosition().toPoint() - self.drag_position)
            return
        self.update_cursor(pos)
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self.dragging = False
        self.resizing = False
        self.resize_direction = None
        self.update_cursor(event.pos())
        super().mouseReleaseEvent(event)

    def get_resize_direction(self, pos):
        if not self.resize_enabled():
            return None
        border_width = self.get_resize_border_width()
        x, y = pos.x(), pos.y()
        width, height = self.width(), self.height()
        left = x <= border_width
        right = x >= width - border_width
        top = y <= border_width
        bottom = y >= height - border_width
        if left and top: return 'top_left'
        if right and top: return 'top_right'
        if left and bottom: return 'bottom_left'
        if right and bottom: return 'bottom_right'
        if left: return 'left'
        if right: return 'right'
        if top: return 'top'
        if bottom: return 'bottom'
        return None

    def get_resize_cursor(self, direction):
        cursors = {
            'left': Qt.CursorShape.SizeHorCursor,
            'right': Qt.CursorShape.SizeHorCursor,
            'top': Qt.CursorShape.SizeVerCursor,
            'bottom': Qt.CursorShape.SizeVerCursor,
            'top_left': Qt.CursorShape.SizeFDiagCursor,
            'bottom_right': Qt.CursorShape.SizeFDiagCursor,
            'top_right': Qt.CursorShape.SizeBDiagCursor,
            'bottom_left': Qt.CursorShape.SizeBDiagCursor
        }
        return cursors.get(direction, Qt.CursorShape.ArrowCursor)

    def update_cursor(self, pos):
        if self.resizing or self.dragging:
            return
        if self.resize_enabled():
            direction = self.get_resize_direction(pos)
            if direction:
                self.setCursor(self.get_resize_cursor(direction))
                return
        if self.movable() and self.is_draggable_area(pos):
            if self.show_drag_cursor():
                self.setCursor(Qt.CursorShape.OpenHandCursor)
            else:
                self.setCursor(Qt.CursorShape.ArrowCursor)
        else:
            self.setCursor(Qt.CursorShape.ArrowCursor)

    def is_draggable_area(self, pos):
        if self.anywhere_draggable():
            return True
        return pos.y() <= int(30 * self.scale_factor)

    def resize_enabled(self):
        return False

    def get_resize_border_width(self):
        return int(5 * self.scale_factor)

    def anywhere_draggable(self):
        return True

    def show_drag_cursor(self):
        return False

    def movable(self):
        return True

    def handle_resize(self, event):
        if not self.resizing or not self.resize_direction:
            return
        current_pos = event.globalPosition().toPoint()
        delta = current_pos - self.resize_start_pos
        new_geometry = QRect(self.resize_start_geometry)
        direction = self.resize_direction
        if 'left' in direction:
            new_left = self.resize_start_geometry.left() + delta.x()
            new_width = self.resize_start_geometry.width() - delta.x()
            if new_width >= self.minimumWidth():
                new_geometry.setLeft(new_left)
                new_geometry.setWidth(new_width)
        if 'right' in direction:
            new_width = self.resize_start_geometry.width() + delta.x()
            if new_width >= self.minimumWidth():
                new_geometry.setWidth(new_width)
        if 'top' in direction:
            new_top = self.resize_start_geometry.top() + delta.y()
            new_height = self.resize_start_geometry.height() - delta.y()
            if new_height >= self.minimumHeight():
                new_geometry.setTop(new_top)
                new_geometry.setHeight(new_height)
        if 'bottom' in direction:
            new_height = self.resize_start_geometry.height() + delta.y()
            if new_height >= self.minimumHeight():
                new_geometry.setHeight(new_height)
        geometry_changed = False
        if new_geometry.width() < self.minimumWidth():
            if 'left' in direction:
                new_geometry.setLeft(new_geometry.right() - self.minimumWidth())
            else:
                new_geometry.setWidth(self.minimumWidth())
            geometry_changed = True
        if new_geometry.height() < self.minimumHeight():
            if 'top' in direction:
                new_geometry.setTop(new_geometry.bottom() - self.minimumHeight())
            else:
                new_geometry.setHeight(self.minimumHeight())
            geometry_changed = True
        self.setGeometry(new_geometry)
        if geometry_changed:
            self.resize_start_geometry = self.geometry()
            self.resize_start_pos = current_pos
        elif new_geometry != self.resize_start_geometry:
            self.resize_start_geometry = new_geometry
            self.resize_start_pos = current_pos

    # ---------- 托盘图标相关方法 ----------
    def _init_tray_icon(self):
        self.tray_icon = TrayIcon(self)
        self.tray_icon.exit_requested.connect(self._cleanup_and_quit)
        self.tray_icon.show_window_requested.connect(self.show_and_activate)
        self.tray_icon.hide_window_requested.connect(self.hide)
        self.tray_icon.mod_preset_all_requested.connect(self._on_tray_mod_preset_all)
        self.tray_icon.mod_preset_select_requested.connect(self._on_tray_mod_preset_select)
        self.tray_icon.mods_folder_requested.connect(self._open_mods_folder)
        self.tray_icon.init_tray(
            app_root=self.app_root,
            scale_factor=self.scale_factor,
            get_icon_cb=self._get_current_config_icon_for_tray,
            get_name_cb=self._get_current_config_display_name
        )

    def _get_current_config_icon_for_tray(self):
        if self.current_config and self.current_config_name:
            game_exe_path = self.current_config.get('game_dir', '')
            custom_data = self.custom_data_manager.get_custom_data(self.current_config_name)
            return self.get_config_icon(self.current_config_name, game_exe_path, custom_data)
        return None

    def _get_current_config_display_name(self):
        if self.current_config_name:
            custom_data = self.custom_data_manager.get_custom_data(self.current_config_name)
            return custom_data.get('display_name', self.current_config_name)
        return None

    def update_tray_icon(self):
        """更新托盘图标并同步更新窗口图标"""
        if self.tray_icon:
            self.tray_icon.update_icon()
        self.update_window_icon()

    def closeEvent(self, event):
        """重写关闭事件：始终隐藏窗口，不退出程序"""
        event.ignore()      # 忽略关闭事件
        self.hide()         # 隐藏主窗口

    def show_and_activate(self):
        """显示窗口并强制置顶、获取焦点"""
        self.show()
        self.raise_()
        self.activateWindow()
        if self.isMinimized():
            self.showNormal()

if __name__ == "__main__":
    import sys
    import os
    from PyQt6.QtCore import Qt
    from PyQt6.QtWidgets import QApplication, QProxyStyle, QStyle
    from PyQt6.QtGui import QFont

    # ---------- 导入缩放管理器 ----------
    from 缩放管理器 import get_scaling_manager

    # ---------- 禁用 Qt 内置自动缩放 ----------
    os.environ["QT_AUTO_SCREEN_SCALE_FACTOR"] = "0"
    os.environ["QT_SCALE_FACTOR"] = "1"

    if hasattr(Qt.ApplicationAttribute, 'AA_EnableHighDpiScaling'):
        QApplication.setAttribute(Qt.ApplicationAttribute.AA_EnableHighDpiScaling, False)

    # ---------- 零延迟工具提示样式 ----------
    class NoDelayToolTipStyle(QProxyStyle):
        def styleHint(self, hint, option=None, widget=None, returnData=None):
            if hint == QStyle.StyleHint.SH_ToolTip_WakeUpDelay:
                return 0
            return super().styleHint(hint, option, widget, returnData)

    app = QApplication(sys.argv)
    app.setStyle(NoDelayToolTipStyle())

    # ---------- 获取缩放系数 ----------
    scaling_manager = get_scaling_manager()
    scale_factor = scaling_manager.get_scale_factor()
    print(f"[工具提示] 缩放系数: {scale_factor:.2f}")

    # ---------- 工具提示样式美化 ----------
    base_font_size = 12
    font_size_multiplier = 1
    target_font_size = max(16, int(base_font_size * font_size_multiplier * scale_factor))
    print(f"[工具提示] 强制字体大小: {target_font_size}pt")

    border_width = max(1, int(2 * scale_factor))
    border_radius = max(2, int(6 * scale_factor))
    padding_v = max(2, int(6 * scale_factor))
    padding_h = max(4, int(12 * scale_factor))

    app.setStyleSheet(f"""
        QToolTip {{
            background-color: #2D2D30;
            color: #FFFFFF;
            border: {border_width}px solid #82FF55;
            border-radius: {border_radius}px;
            padding: {padding_v}px {padding_h}px;
            font-weight: bold;
            font-size: {target_font_size}pt;
        }}
    """)

    QApplication.setQuitOnLastWindowClosed(False)
    window = DesignedWindow()

    if len(sys.argv) > 1:
        config_param = sys.argv[1]
        if config_param.endswith('.json'):
            window.load_and_launch_config(config_param)

    window.show()
    sys.exit(app.exec())