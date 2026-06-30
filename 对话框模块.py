# -*- coding: utf-8 -*-
"""
对话框模块 - 包含所有对话框类
（PyQt6 适配 + 完整缩放支持 + 国际化 + 背景图片与描边 + 深色遮罩）
（扩展：EditConfigDialog 支持编辑 launch_program, target_program, launch_args）
（优化：修复窗口移动时高度缩减、按钮文本裁剪问题）
（新增：编辑界面增加删除按钮）
"""

import os
import sys
import winreg
from PyQt6.QtCore import Qt, QSettings, QSize, QFileInfo, pyqtSignal, QThread
from PyQt6.QtGui import QIcon, QPixmap, QFont, QPainter, QColor, QMouseEvent, QFontMetrics, QPainterPath, QPen, QMovie
from PyQt6.QtWidgets import (QWidget, QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
                             QListWidget, QListWidgetItem, QFileDialog, QMessageBox,
                             QCheckBox, QGroupBox, QLineEdit, QFormLayout, QGridLayout,
                             QFileIconProvider, QComboBox, QTextEdit, QApplication,
                             QStyleOptionButton, QStyle, QSizePolicy)
from typing import List, Optional, Dict, Any

from 翻译管理器 import _tr
from 自定义控件模块 import StrokeLabel_4, StrokePushButton, StrokeToolButton
from mod预设保存 import Worker
from 数据管理模块 import CustomDataManager   # 新增导入

# ----------------------------------------------------------------------
# DPI 覆盖辅助函数（Windows 缩放替代）
# ----------------------------------------------------------------------
DPI_LAYERS_KEY = r"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
DPI_IFEO_BASE = r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"

def _get_dpi_exe_path(config_data: Dict[str, Any]) -> str:
    """从配置数据中获取游戏 EXE 路径（用于 DPI 注册表操作）"""
    return config_data.get('launch_program') or config_data.get('game_dir', '')

def _read_dpi_override_state(exe_path: str) -> bool:
    """
    读取 Windows 注册表中该 EXE 的 DPI 覆盖状态。
    如果 Layers 键存在且包含 HIGHDPIAWARE/DPIUNAWARE 则返回 True。
    """
    if not exe_path:
        return False
    abs_path = os.path.abspath(exe_path)
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, DPI_LAYERS_KEY, 0, winreg.KEY_READ)
        try:
            value, _ = winreg.QueryValueEx(key, abs_path)
            winreg.CloseKey(key)
            return any(tag in value.upper() for tag in ['HIGHDPIAWARE', 'DPIUNAWARE'])
        except FileNotFoundError:
            winreg.CloseKey(key)
            return False
    except (FileNotFoundError, PermissionError, OSError):
        return False

def _apply_dpi_override(exe_path: str) -> str:
    """
    应用 Windows DPI 覆盖（禁用缩放替代），使游戏使用系统缩放。
    返回空字符串表示成功，否则返回错误信息。
    """
    if not exe_path:
        return "未指定 EXE 路径"
    abs_path = os.path.abspath(exe_path)
    exe_name = os.path.basename(abs_path)

    # 1. 写 Layers：标记为 DPI_UNAWARE，让系统负责缩放
    try:
        key = winreg.CreateKey(winreg.HKEY_CURRENT_USER, DPI_LAYERS_KEY)
        winreg.SetValueEx(key, abs_path, 0, winreg.REG_SZ, "~ DPIUNAWARE")
        winreg.CloseKey(key)
    except Exception as e:
        return f"Layers 写入失败: {e}"

    # 2. 写 IFEO dpiAwareness=0（DPI_UNAWARE，Win11 关键）
    try:
        ifeo_path = DPI_IFEO_BASE + "\\" + exe_name
        key = winreg.CreateKey(winreg.HKEY_LOCAL_MACHINE, ifeo_path)
        winreg.SetValueEx(key, "dpiAwareness", 0, winreg.REG_DWORD, 0)  # 0 = DPI_UNAWARE
        winreg.CloseKey(key)
    except PermissionError:
        return "需要管理员权限（HKLM 写入失败）"
    except Exception as e:
        return f"IFEO 写入失败: {e}"

    # 3. 强制刷新
    try:
        import ctypes
        ctypes.windll.user32.SystemParametersInfoW(0x009F, 0, None, 0)  # SPI_SETLOGICALDPIOVERRIDE
    except Exception:
        pass

    return ""

def _remove_dpi_override(exe_path: str) -> str:
    """移除 Windows DPI 覆盖注册表项"""
    if not exe_path:
        return "未指定 EXE 路径"
    abs_path = os.path.abspath(exe_path)
    exe_name = os.path.basename(abs_path)

    # 1. 删除 Layers 项
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, DPI_LAYERS_KEY, 0, winreg.KEY_SET_VALUE | winreg.KEY_QUERY_VALUE)
        try:
            winreg.DeleteValue(key, abs_path)
        except FileNotFoundError:
            pass
        winreg.CloseKey(key)
    except Exception as e:
        return f"Layers 删除失败: {e}"

    # 2. 删除 IFEO 项
    try:
        ifeo_path = DPI_IFEO_BASE + "\\" + exe_name
        winreg.DeleteKey(winreg.HKEY_LOCAL_MACHINE, ifeo_path)
    except FileNotFoundError:
        pass
    except PermissionError:
        return "需要管理员权限（HKLM 删除失败）"
    except Exception as e:
        return f"IFEO 删除失败: {e}"

    # 3. 强制刷新
    try:
        import ctypes
        ctypes.windll.user32.SystemParametersInfoW(0x009F, 0, None, 0)
    except Exception:
        pass

    return ""

# ----------------------------------------------------------------------
# 基类：带背景图片和深色遮罩的对话框
# ----------------------------------------------------------------------
class StyledDialog(QDialog):
    """带背景图片和深色遮罩的对话框基类（支持GIF背景，保持比例）"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.scale_factor = 1.0
        if parent:
            if hasattr(parent, 'scale_factor'):
                self.scale_factor = parent.scale_factor
            elif hasattr(parent, 'scaling_manager'):
                self.scale_factor = parent.scaling_manager.get_scale_factor()

        # 创建自定义数据管理器
        self.custom_data_manager = CustomDataManager(base_dir=self.get_app_root())

        # 创建深色遮罩
        self.overlay = QLabel(self)
        self.overlay.setObjectName("overlay_mask")
        self.overlay.setStyleSheet(f"background-color: rgba(0, 0, 0, 0.5);")
        self.overlay.lower()
        self.overlay.hide()

        # GIF 播放器（无控件，仅在 paintEvent 中绘制）
        self.movie = None

        # 窗口拖拽相关
        self._drag_pos = None

    def get_app_root(self):
        """获取应用程序根目录"""
        if getattr(sys, 'frozen', False):
            return os.path.dirname(sys.executable)
        else:
            return os.path.dirname(os.path.abspath(__file__))
    def mousePressEvent(self, event):
        """鼠标按下：开始拖拽窗口"""
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_pos = event.globalPosition().toPoint() - self.frameGeometry().topLeft()
            event.accept()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        """鼠标移动：拖拽窗口"""
        if event.buttons() == Qt.MouseButton.LeftButton and self._drag_pos is not None:
            self.move(event.globalPosition().toPoint() - self._drag_pos)
            event.accept()
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        """鼠标释放：结束拖拽"""
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_pos = None
            event.accept()
        super().mouseReleaseEvent(event)



    def get_resource_path(self, filename):
        if filename == 'b.png':
            custom_bg = self.custom_data_manager.get_global_setting('background_image')
            if custom_bg and os.path.exists(custom_bg):
                return custom_bg
        path = os.path.join(self.get_app_root(), filename)
        if os.path.exists(path):
            return path
        if hasattr(sys, '_MEIPASS'):
            path = os.path.join(sys._MEIPASS, filename)
            if os.path.exists(path):
                return path
        return filename

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

        # 优先绘制 GIF 背景（如果存在且正在运行）
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
                # 若获取帧失败，降级绘制静态背景
                self.draw_static_background(painter)
        else:
            self.draw_static_background(painter)

        painter.end()

    def showEvent(self, event):
        """窗口显示时应用背景并确保遮罩可见"""
        super().showEvent(event)
        self.apply_background()
        self.overlay.setGeometry(0, 0, self.width(), self.height())
        self.overlay.show()
        self.overlay.lower()

    def resizeEvent(self, event):
        """窗口大小变化时更新遮罩大小"""
        super().resizeEvent(event)
        self.overlay.setGeometry(0, 0, self.width(), self.height())

# ----------------------------------------------------------------------
# 自定义描边复选框（解决换行裁剪，样式还原）
# ----------------------------------------------------------------------
class StrokeCheckBox(QWidget):
    """带描边文本的自定义复选框（样式与原始QCheckBox完全一致，文本带描边）"""
    toggled = pyqtSignal(bool)

    def __init__(self, text="", parent=None, stroke_width=2, stroke_color="#000000"):
        super().__init__(parent)
        self.stroke_width = stroke_width
        self.stroke_color = stroke_color
        self._checked = False

        # 水平布局：复选框指示器 + 描边文本
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(5)

        # 复选框指示器（使用 QCheckBox 但隐藏文本，样式还原）
        self.checkbox = QCheckBox(self)
        self.checkbox.setText("")
        self.checkbox.setStyleSheet("""
            QCheckBox::indicator {
                width: 18px;
                height: 18px;
            }
            QCheckBox::indicator:checked {
                background-color: #82FF55;
                border: 2px solid #82FF55;
                border-radius: 3px;
            }
            QCheckBox::indicator:unchecked {
                background-color: #555555;
                border: 2px solid #AAAAAA;
                border-radius: 3px;
            }
        """)
        self.checkbox.toggled.connect(self._on_toggled)
        layout.addWidget(self.checkbox)

        # 描边标签显示文本（禁止换行，自动伸展）
        self.label = StrokeLabel_4(text, self)
        self.label.set_stroke_properties(stroke_width, stroke_color)
        self.label.setStyleSheet("color: #FFFFFF; background-color: transparent;")
        self.label.setWordWrap(False)
        self.label.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        self.label.mousePressEvent = self._label_clicked
        layout.addWidget(self.label)

        layout.addStretch()  # 确保右侧不留空白

    def _on_toggled(self, checked):
        self._checked = checked
        self.toggled.emit(checked)

    def _label_clicked(self, event):
        self.checkbox.toggle()

    def isChecked(self):
        return self._checked

    def setChecked(self, checked):
        self.checkbox.setChecked(checked)

    def setText(self, text):
        self.label.setText(text)

# ----------------------------------------------------------------------
# 简单消息框
# ----------------------------------------------------------------------
class SimpleMessageBox(StyledDialog):
    """简单的消息提示框（已缩放）"""
    def __init__(self, title="", message="", parent=None):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setWindowFlags(Qt.WindowType.Dialog)
        self.setFixedSize(max(1, int(400 * self.scale_factor)), max(1, int(200 * self.scale_factor)))
        self.setup_ui(message)

    def setup_ui(self, message):
        sf = self.scale_factor
        layout = QVBoxLayout(self)

        label = StrokeLabel_4(message, self)
        label.set_stroke_properties(int(2 * sf), '#000000')
        label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        label.setWordWrap(True)
        label.setStyleSheet("color: #FFFFFF; background-color: transparent;")
        font = QFont()
        font.setPointSize(max(1, int(14 * sf)))
        label.setFont(font)
        layout.addWidget(label)

        ok_btn = StrokePushButton(_tr("dialog.ok"), self)
        ok_btn.set_stroke_properties(int(2 * sf), '#000000')
        ok_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {max(1, int(5 * sf))}px;
                border: 3px solid #bababa;
                padding: {max(1, int(5 * sf))}px;
                min-width: {max(1, int(80 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
            }}
        """)
        btn_font = QFont()
        btn_font.setPointSize(max(1, int(14 * sf)))
        ok_btn.setFont(btn_font)
        ok_btn.clicked.connect(self.accept)

        layout.addWidget(ok_btn, alignment=Qt.AlignmentFlag.AlignCenter)
        layout.setContentsMargins(max(1, int(20 * sf)), max(1, int(20 * sf)),
                                  max(1, int(20 * sf)), max(1, int(20 * sf)))
        self.setStyleSheet("background-color: transparent;")

# ----------------------------------------------------------------------
# 自定义描边 GroupBox（用于标题描边，保持原始布局）
# ----------------------------------------------------------------------
class StrokeGroupBox(QGroupBox):
    """带描边标题的 GroupBox，完全模拟原始 QGroupBox 样式"""
    def __init__(self, title, parent=None, stroke_width=2, stroke_color="#000000", scale_factor=1.0):
        super().__init__(parent)
        self._title = title
        self.stroke_width = stroke_width
        self.stroke_color = stroke_color
        self.scale_factor = scale_factor
        super().setTitle("")  # 禁用原始标题，由我们自己绘制

    def setTitle(self, title):
        self._title = title
        self.update()

    def title(self):
        return self._title

    def paintEvent(self, event):
        # 先绘制默认边框和背景（保留所有样式）
        super().paintEvent(event)

        # 绘制描边标题
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # 使用当前字体（与原始标题一致）
        font = self.font()
        painter.setFont(font)
        fm = QFontMetrics(font)

        # 计算标题位置（模仿原始样式：左缩进15*sf，垂直居中于标题区域）
        sf = self.scale_factor
        left_margin = int(15 * sf)
        # 垂直位置取字体 ascent，使文本基线对齐（原始标题大致位置）
        y = fm.ascent() + int(5 * sf)  # 微调，使文本垂直居中于预留空间

        text = self._title
        # 绘制描边：先画粗轮廓，再填充白色文字
        path = QPainterPath()
        path.addText(left_margin, y, font, text)
        painter.strokePath(path, QPen(QColor(self.stroke_color), self.stroke_width))
        painter.setPen(QColor("#FFFFFF"))
        painter.drawText(left_margin, y, text)

        painter.end()


# ----------------------------------------------------------------------
# 编辑配置对话框（完整实现，仅替换为描边标签，尺寸布局完全不变）
# ----------------------------------------------------------------------
class EditConfigDialog(StyledDialog):
    """编辑配置对话框（已缩放）- 支持编辑启动程序、注入目标程序、启动参数"""
    def __init__(self, config_name, config_data, custom_data, parent=None):
        super().__init__(parent)
        self.main_window = parent          # 保存主窗口引用
        self.config_name = config_name
        self.config_data = config_data.copy()  # 原始配置副本
        self.custom_data = custom_data or {}
        self.custom_icon_path = None
        self.deleted = False               # 新增标志

        # 读取 DPI 覆盖状态（从注册表实时读取）
        self._dpi_exe_path = _get_dpi_exe_path(self.config_data)
        self._dpi_enabled = _read_dpi_override_state(self._dpi_exe_path)

        self.setWindowTitle(_tr("edit_config.title", name=config_name))
        self.setWindowFlags(Qt.WindowType.Dialog)
        self.setup_ui()

        # 计算合适的高度：内容最小高度 vs 屏幕可用高度（取较小值）
        from PyQt6.QtWidgets import QApplication
        screen = QApplication.primaryScreen()
        max_h = screen.availableGeometry().height() - int(60 * self.scale_factor) if screen else 800
        min_h = self.minimumSizeHint().height()
        dialog_h = min(min_h, max_h)
        self.setFixedSize(max(1, int(600 * self.scale_factor)), max(1, dialog_h))

        # 居中显示
        if parent and parent.isVisible():
            parent_center = parent.frameGeometry().center()
            self.move(parent_center.x() - self.width() // 2,
                      max(0, parent_center.y() - self.height() // 2))
        else:
            if screen:
                screen_geo = screen.availableGeometry()
                self.move(screen_geo.center().x() - self.width() // 2,
                          screen_geo.center().y() - self.height() // 2)

    def setup_ui(self):
        sf = self.scale_factor
        layout = QVBoxLayout(self)
        layout.setSpacing(max(1, int(10 * sf)))
        layout.setContentsMargins(max(1, int(5 * sf)), max(1, int(5 * sf)),
                                  max(1, int(5 * sf)), max(1, int(5 * sf)))

        # 标题（描边标签）—— 原始已有，保留不变
        title_label = StrokeLabel_4(_tr("edit_config.title", name=self.config_name), self)
        title_label.set_stroke_properties(int(2 * sf), '#000000')
        title_label.setStyleSheet("color: #FFFFFF; font-weight: bold; background-color: transparent;")
        title_font = QFont()
        title_font.setPointSize(max(1, int(20 * sf)))
        title_font.setBold(True)
        title_label.setFont(title_font)
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title_label)

        # ========== 图标预览区域（使用 StrokeGroupBox，标题描边）==========
        icon_group = StrokeGroupBox(_tr("edit_config.icon_group"), self,
                                    stroke_width=int(2*sf), stroke_color='#000000',
                                    scale_factor=sf)
        icon_group.setStyleSheet(f"""
            QGroupBox {{
                color: #FFFFFF;
                font-weight: bold;
                border: 2px solid #555555;
                border-radius: {max(1, int(8 * sf))}px;
                margin-top: {max(1, int(10 * sf))}px;
                padding-top: {max(1, int(15 * sf))}px;
                background-color: rgba(0, 0, 0, 0.7);
            }}
        """)
        group_font = QFont()
        group_font.setPointSize(max(1, int(16 * sf)))
        group_font.setBold(True)
        icon_group.setFont(group_font)

        icon_layout = QHBoxLayout()

        self.icon_label = QLabel(self)
        self.icon_label.setFixedSize(max(1, int(80 * sf)), max(1, int(80 * sf)))
        self.icon_label.setStyleSheet(f"""
            QLabel {{
                border: 3px solid #555555;
                border-radius: {max(1, int(8 * sf))}px;
                background-color: #2D2D30;
            }}
        """)
        self.icon_label.setScaledContents(True)
        self.load_icon()

        icon_layout.addWidget(self.icon_label, alignment=Qt.AlignmentFlag.AlignCenter)
        icon_layout.addStretch()

        icon_btn_layout = QVBoxLayout()
        icon_btn_layout.setSpacing(max(1, int(10 * sf)))

        change_icon_btn = StrokePushButton(_tr("edit_config.change_icon"), self)
        change_icon_btn.set_stroke_properties(int(2 * sf), '#000000')
        change_icon_btn.setMinimumSize(max(1, int(120 * sf)), max(1, int(35 * sf)))
        change_icon_btn.setFixedHeight(max(1, int(35 * sf)))
        change_icon_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.5);
                color: #FFFFFF;
                font-weight: bold;
                border-radius: {max(1, int(5 * sf))}px;
                border: 2px solid #bababa;
                padding: {max(1, int(5 * sf))}px {max(1, int(10 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.6);
            }}
            QPushButton:pressed {{
                background-color: rgba(0, 63, 107, 0.6);
            }}
        """)
        btn_font = QFont()
        btn_font.setPointSize(max(1, int(10 * sf)))
        btn_font.setBold(True)
        change_icon_btn.setFont(btn_font)
        change_icon_btn.clicked.connect(self.change_icon)

        reset_icon_btn = StrokePushButton(_tr("edit_config.reset_icon"), self)
        reset_icon_btn.set_stroke_properties(int(2 * sf), '#000000')
        reset_icon_btn.setMinimumSize(max(1, int(120 * sf)), max(1, int(35 * sf)))
        reset_icon_btn.setFixedHeight(max(1, int(35 * sf)))
        reset_icon_btn.setStyleSheet(change_icon_btn.styleSheet())
        reset_icon_btn.setFont(btn_font)
        reset_icon_btn.clicked.connect(self.reset_icon)

        icon_btn_layout.addWidget(change_icon_btn, alignment=Qt.AlignmentFlag.AlignCenter)
        icon_btn_layout.addWidget(reset_icon_btn, alignment=Qt.AlignmentFlag.AlignCenter)
        icon_btn_layout.addStretch()

        icon_layout.addLayout(icon_btn_layout)
        icon_group.setLayout(icon_layout)
        layout.addWidget(icon_group)

        # ========== 配置名称编辑区域（使用 StrokeGroupBox）==========
        name_group = StrokeGroupBox(_tr("edit_config.name_group"), self,
                                    stroke_width=int(2*sf), stroke_color='#000000',
                                    scale_factor=sf)
        name_group.setStyleSheet(f"""
            QGroupBox {{
                color: #FFFFFF;
                font-weight: bold;
                border: 2px solid #555555;
                border-radius: {max(1, int(8 * sf))}px;
                margin-top: {max(1, int(10 * sf))}px;
                padding-top: {max(1, int(15 * sf))}px;
                background-color: rgba(0, 0, 0, 0.7);
            }}
        """)
        name_group.setFont(group_font)

        name_layout = QVBoxLayout()
        name_layout.setContentsMargins(max(1, int(15 * sf)), max(1, int(15 * sf)),
                                       max(1, int(15 * sf)), max(1, int(15 * sf)))

        self.name_edit = QLineEdit(self)
        self.name_edit.setText(self.custom_data.get('display_name', self.config_name))
        self.name_edit.setFixedHeight(max(1, int(35 * sf)))
        self.name_edit.setStyleSheet(f"""
            QLineEdit {{
                background-color: #2D2D30;
                color: #FFFFFF;
                border: 2px solid #555555;
                border-radius: {max(1, int(5 * sf))}px;
                padding: {max(1, int(5 * sf))}px;
            }}
            QLineEdit:focus {{
                border: 2px solid #82FF55;
            }}
        """)
        edit_font = QFont()
        edit_font.setPointSize(max(1, int(16 * sf)))
        self.name_edit.setFont(edit_font)
        name_layout.addWidget(self.name_edit)
        name_group.setLayout(name_layout)
        layout.addWidget(name_group)

        # ========== 程序与参数编辑区域（使用 StrokeGroupBox）==========
        program_group = StrokeGroupBox(_tr("edit_config.program_group"), self,
                                       stroke_width=int(2*sf), stroke_color='#000000',
                                       scale_factor=sf)
        program_group.setStyleSheet(f"""
            QGroupBox {{
                color: #FFFFFF;
                font-weight: bold;
                border: 2px solid #555555;
                border-radius: {max(1, int(8 * sf))}px;
                margin-top: {max(1, int(10 * sf))}px;
                padding-top: {max(1, int(15 * sf))}px;
                background-color: rgba(0, 0, 0, 0.7);
            }}
        """)
        program_group.setFont(group_font)

        form_layout = QFormLayout()
        form_layout.setSpacing(max(1, int(10 * sf)))
        form_layout.setLabelAlignment(Qt.AlignmentFlag.AlignRight)

        # 创建三个描边标签
        launch_label = StrokeLabel_4(_tr("edit_config.launch_program_label"), self)
        target_label = StrokeLabel_4(_tr("edit_config.target_program_label"), self)
        args_label = StrokeLabel_4(_tr("edit_config.launch_args_label"), self)

        # 统一设置描边属性
        for label in (launch_label, target_label, args_label):
            label.set_stroke_properties(int(2 * sf), '#000000')
            label.setStyleSheet("color: #FFFFFF; background-color: transparent;")
            label.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            label.setWordWrap(False)  # 禁止换行

        # 计算三个标签中最长文本的宽度，并统一设置最小宽度（确保足够）
        # 使用当前缩放后的字体度量
        fm = QFontMetrics(launch_label.font())  # 所有标签字体相同
        label_texts = [launch_label.text(), target_label.text(), args_label.text()]
        max_width = 0
        for text in label_texts:
            width = fm.horizontalAdvance(text) + int(10 * sf)  # 增加 10*sf 像素的额外空间
            if width > max_width:
                max_width = width
        # 为所有标签设置相同的最小宽度
        launch_label.setMinimumWidth(max_width)
        target_label.setMinimumWidth(max_width)
        args_label.setMinimumWidth(max_width)

        # 启动程序行
        self.launch_program_edit = QLineEdit(self)
        self.launch_program_edit.setText(self.config_data.get('launch_program', ''))
        self.launch_program_edit.setFixedHeight(max(1, int(30 * sf)))
        self.launch_program_edit.setStyleSheet(f"""
            QLineEdit {{
                background-color: #2D2D30;
                color: #FFFFFF;
                border: 2px solid #555555;
                border-radius: {max(1, int(5 * sf))}px;
                padding: {max(1, int(3 * sf))}px {max(1, int(5 * sf))}px;
            }}
        """)
        launch_program_btn = StrokePushButton(_tr("edit_config.browse"), self)
        launch_program_btn.set_stroke_properties(int(2 * sf), '#000000')
        launch_program_btn.setFixedHeight(max(1, int(30 * sf)))
        launch_program_btn.setFixedWidth(max(1, int(60 * sf)))
        launch_program_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.5);
                color: #FFFFFF;
                border-radius: {max(1, int(5 * sf))}px;
                border: 2px solid #bababa;
                padding: {max(1, int(3 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.6);
            }}
        """)
        launch_program_btn.clicked.connect(self._browse_launch_program)
        launch_program_layout = QHBoxLayout()
        launch_program_layout.setSpacing(max(1, int(5 * sf)))
        launch_program_layout.addWidget(self.launch_program_edit)
        launch_program_layout.addWidget(launch_program_btn)
        form_layout.addRow(launch_label, launch_program_layout)

        # 注入目标程序行
        self.target_program_edit = QLineEdit(self)
        self.target_program_edit.setText(self.config_data.get('target_program', ''))
        self.target_program_edit.setFixedHeight(max(1, int(30 * sf)))
        self.target_program_edit.setStyleSheet(self.launch_program_edit.styleSheet())
        target_program_btn = StrokePushButton(_tr("edit_config.browse"), self)
        target_program_btn.set_stroke_properties(int(2 * sf), '#000000')
        target_program_btn.setFixedHeight(max(1, int(30 * sf)))
        target_program_btn.setFixedWidth(max(1, int(60 * sf)))
        target_program_btn.setStyleSheet(launch_program_btn.styleSheet())
        target_program_btn.clicked.connect(self._browse_target_program)
        target_program_layout = QHBoxLayout()
        target_program_layout.setSpacing(max(1, int(5 * sf)))
        target_program_layout.addWidget(self.target_program_edit)
        target_program_layout.addWidget(target_program_btn)
        form_layout.addRow(target_label, target_program_layout)

        # 启动参数行
        self.launch_args_edit = QLineEdit(self)
        self.launch_args_edit.setText(self.config_data.get('launch_args', ''))
        self.launch_args_edit.setFixedHeight(max(1, int(30 * sf)))
        self.launch_args_edit.setStyleSheet(self.launch_program_edit.styleSheet())
        form_layout.addRow(args_label, self.launch_args_edit)

        program_group.setLayout(form_layout)
        layout.addWidget(program_group)

        # ========== 注入 DLL 列表区域 ==========
        dll_group = StrokeGroupBox(_tr("edit_config.dll_group"), self,
                                    stroke_width=int(2*sf), stroke_color='#000000',
                                    scale_factor=sf)
        dll_group.setStyleSheet(f"""
            QGroupBox {{
                color: #FFFFFF;
                font-weight: bold;
                border: 2px solid #555555;
                border-radius: {max(1, int(8 * sf))}px;
                margin-top: {max(1, int(10 * sf))}px;
                padding-top: {max(1, int(15 * sf))}px;
                background-color: rgba(0, 0, 0, 0.7);
            }}
        """)
        dll_group.setFont(group_font)

        dll_layout = QVBoxLayout()
        dll_layout.setContentsMargins(max(1, int(10 * sf)), max(1, int(10 * sf)),
                                       max(1, int(10 * sf)), max(1, int(10 * sf)))
        dll_layout.setSpacing(max(1, int(6 * sf)))

        # 可滚动的 DLL 列表区域
        from PyQt6.QtWidgets import QScrollArea
        self.dll_scroll = QScrollArea(self)
        self.dll_scroll.setWidgetResizable(True)
        self.dll_scroll.setStyleSheet(f"""
            QScrollArea {{
                background-color: transparent;
                border: 1px solid #555555;
                border-radius: {max(1, int(4 * sf))}px;
            }}
            QScrollBar:vertical {{
                width: {max(1, int(8 * sf))}px;
                background: #2D2D30;
            }}
            QScrollBar::handle:vertical {{
                background: #555555;
                border-radius: {max(1, int(4 * sf))}px;
            }}
        """)
        self.dll_scroll.setMinimumHeight(max(1, int(60 * sf)))

        self.dll_list_widget = QWidget()
        self.dll_list_widget.setStyleSheet("background-color: transparent;")
        self.dll_list_layout = QVBoxLayout(self.dll_list_widget)
        self.dll_list_layout.setContentsMargins(max(1, int(5 * sf)), max(1, int(5 * sf)),
                                                 max(1, int(5 * sf)), max(1, int(5 * sf)))
        self.dll_list_layout.setSpacing(max(1, int(5 * sf)))
        self.dll_list_layout.addStretch()

        self.dll_scroll.setWidget(self.dll_list_widget)
        dll_layout.addWidget(self.dll_scroll)

        # 添加 DLL 按钮
        add_dll_btn = StrokePushButton(_tr("edit_config.add_dll"), self)
        add_dll_btn.set_stroke_properties(int(2 * sf), '#000000')
        add_dll_btn.setFixedHeight(max(1, int(28 * sf)))
        add_dll_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.5);
                color: #FFFFFF;
                font-weight: bold;
                border-radius: {max(1, int(5 * sf))}px;
                border: 2px solid #82FF55;
                padding: {max(1, int(3 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.6);
            }}
        """)
        add_dll_btn.setFont(btn_font)
        add_dll_btn.clicked.connect(lambda: self._add_dll_row())
        dll_layout.addWidget(add_dll_btn)

        dll_group.setLayout(dll_layout)
        layout.addWidget(dll_group)

        # 加载已有 DLL 列表
        self.dll_rows = []
        # 如果启用了 ReShade64.dll，作为第一行加入列表
        reshade_enabled = self.config_data.get("reshade_dll") is not None and self.config_data.get("reshade_dll") != ""
        if reshade_enabled:
            self._add_dll_row("ReShade64.dll")
        for dll_path in self.config_data.get('dll_files', []):
            self._add_dll_row(dll_path)

                # ========== 窗口居中设置区域 ==========
        center_group = StrokeGroupBox(_tr("edit_config.center_group"), self,
                                      stroke_width=int(2*sf), stroke_color='#000000',
                                      scale_factor=sf)
        center_group.setStyleSheet(f"""
            QGroupBox {{
                color: #FFFFFF;
                font-weight: bold;
                border: 2px solid #555555;
                border-radius: {max(1, int(8 * sf))}px;
                margin-top: {max(1, int(10 * sf))}px;
                padding-top: {max(1, int(15 * sf))}px;
                background-color: rgba(0, 0, 0, 0.7);
            }}
        """)
        center_group.setFont(group_font)

        center_layout = QVBoxLayout()
        center_layout.setContentsMargins(max(1, int(15 * sf)), max(1, int(12 * sf)),
                                         max(1, int(15 * sf)), max(1, int(12 * sf)))
        center_layout.setSpacing(max(1, int(8 * sf)))

        # 第一行：复选框（使用普通 QCheckBox 避免 StrokeCheckBox 裁剪问题）
        from PyQt6.QtWidgets import QCheckBox as PlainCheckBox
        self.center_checkbox = PlainCheckBox(_tr("edit_config.center_enable"), self)
        self.center_checkbox.setStyleSheet(f"""
            QCheckBox {{
                color: #FFFFFF;
                background-color: transparent;
                font-size: {max(1, int(12 * sf))}px;
                spacing: {max(1, int(5 * sf))}px;
            }}
            QCheckBox::indicator {{
                width: {max(1, int(16 * sf))}px;
                height: {max(1, int(16 * sf))}px;
            }}
            QCheckBox::indicator:checked {{
                background-color: #82FF55;
                border: 2px solid #82FF55;
                border-radius: {max(1, int(3 * sf))}px;
            }}
            QCheckBox::indicator:unchecked {{
                background-color: #555555;
                border: 2px solid #AAAAAA;
                border-radius: {max(1, int(3 * sf))}px;
            }}
        """)
        center_checkbox_font = QFont()
        center_checkbox_font.setPointSize(max(1, int(12 * sf)))
        self.center_checkbox.setFont(center_checkbox_font)
        center_enabled = self.config_data.get('force_center_window', False)
        self.center_checkbox.setChecked(center_enabled)
        center_layout.addWidget(self.center_checkbox)

        # 第二行：时长控件（水平排列）
        duration_row = QHBoxLayout()
        duration_row.setSpacing(max(1, int(8 * sf)))
        duration_row.addSpacing(max(1, int(25 * sf)))  # 缩进对齐复选框

        duration_label = QLabel(_tr("edit_config.center_duration_label"), self)
        duration_label.setStyleSheet(f"""
            color: #FFFFFF;
            background-color: transparent;
            font-size: {max(1, int(12 * sf))}px;
        """)
        duration_label.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
        dur_font = QFont()
        dur_font.setPointSize(max(1, int(12 * sf)))
        duration_label.setFont(dur_font)
        duration_row.addWidget(duration_label)

        from PyQt6.QtWidgets import QSpinBox
        self.center_duration_spin = QSpinBox(self)
        self.center_duration_spin.setRange(5, 120)
        self.center_duration_spin.setValue(self.config_data.get('center_window_duration', 15))
        self.center_duration_spin.setSuffix(" " + _tr("edit_config.center_seconds"))
        self.center_duration_spin.setFixedHeight(max(1, int(28 * sf)))
        self.center_duration_spin.setFixedWidth(max(1, int(90 * sf)))
        self.center_duration_spin.setStyleSheet(f"""
            QSpinBox {{
                background-color: #2D2D30;
                color: #FFFFFF;
                border: 2px solid #555555;
                border-radius: {max(1, int(5 * sf))}px;
                padding: {max(1, int(2 * sf))}px;
                font-size: {max(1, int(12 * sf))}px;
            }}
            QSpinBox:focus {{
                border: 2px solid #82FF55;
            }}
            QSpinBox::up-button {{
                width: {max(1, int(18 * sf))}px;
                border-left: 1px solid #555555;
                border-bottom: 1px solid #555555;
                border-top-right-radius: {max(1, int(4 * sf))}px;
            }}
            QSpinBox::down-button {{
                width: {max(1, int(18 * sf))}px;
                border-left: 1px solid #555555;
                border-bottom-right-radius: {max(1, int(4 * sf))}px;
            }}
        """)
        duration_row.addWidget(self.center_duration_spin)
        duration_row.addStretch()

        center_layout.addLayout(duration_row)
        center_group.setLayout(center_layout)
        layout.addWidget(center_group)

                # ========== Windows 缩放替代设置区域 ==========
        dpi_group = StrokeGroupBox(_tr("edit_config.dpi_group"), self,
                                   stroke_width=int(2*sf), stroke_color='#000000',
                                   scale_factor=sf)
        dpi_group.setStyleSheet(f"""
            QGroupBox {{
                color: #FFFFFF;
                font-weight: bold;
                border: 2px solid #555555;
                border-radius: {max(1, int(8 * sf))}px;
                margin-top: {max(1, int(10 * sf))}px;
                padding-top: {max(1, int(15 * sf))}px;
                background-color: rgba(0, 0, 0, 0.7);
            }}
        """)
        dpi_group.setFont(group_font)

        dpi_layout = QVBoxLayout()
        dpi_layout.setContentsMargins(max(1, int(15 * sf)), max(1, int(12 * sf)),
                                      max(1, int(15 * sf)), max(1, int(12 * sf)))
        dpi_layout.setSpacing(max(1, int(8 * sf)))

        from PyQt6.QtWidgets import QCheckBox as PlainCheckBox
        self.dpi_checkbox = PlainCheckBox(_tr("edit_config.dpi_enable"), self)
        self.dpi_checkbox.setStyleSheet(f"""
            QCheckBox {{
                color: #FFFFFF;
                background-color: transparent;
                font-size: {max(1, int(12 * sf))}px;
                spacing: {max(1, int(5 * sf))}px;
            }}
            QCheckBox::indicator {{
                width: {max(1, int(16 * sf))}px;
                height: {max(1, int(16 * sf))}px;
            }}
            QCheckBox::indicator:checked {{
                background-color: #82FF55;
                border: 2px solid #82FF55;
                border-radius: {max(1, int(3 * sf))}px;
            }}
            QCheckBox::indicator:unchecked {{
                background-color: #555555;
                border: 2px solid #AAAAAA;
                border-radius: {max(1, int(3 * sf))}px;
            }}
        """)
        dpi_checkbox_font = QFont()
        dpi_checkbox_font.setPointSize(max(1, int(12 * sf)))
        self.dpi_checkbox.setFont(dpi_checkbox_font)
        # 从注册表读取当前 DPI 状态
        self.dpi_checkbox.setChecked(self._dpi_enabled)
        dpi_layout.addWidget(self.dpi_checkbox)

        # 显示当前 EXE 路径提示
        dpi_hint = QLabel(self)
        dpi_hint.setStyleSheet(f"""
            color: #AAAAAA;
            font-style: italic;
            background-color: transparent;
            font-size: {max(1, int(9 * sf))}px;
        """)
        dpi_hint_font = QFont()
        dpi_hint_font.setPointSize(max(1, int(9 * sf)))
        dpi_hint.setFont(dpi_hint_font)
        dpi_hint.setWordWrap(True)
        exe_display = self._dpi_exe_path.replace('/', '\\') if self._dpi_exe_path else _tr("edit_config.dpi_no_exe")
        dpi_hint.setText(_tr("edit_config.dpi_exe_hint", exe=exe_display))
        dpi_layout.addWidget(dpi_hint)

        dpi_group.setLayout(dpi_layout)
        layout.addWidget(dpi_group)

        # 提示信息（改为描边标签，样式与原 QLabel 完全一致）
        info_label = StrokeLabel_4(_tr("edit_config.hint"), self)
        info_label.set_stroke_properties(int(2 * sf), '#000000')
        info_label.setStyleSheet("""
            color: #AAAAAA;
            font-style: italic;
            background-color: transparent;
        """)
        info_font = QFont()
        info_font.setPointSize(max(1, int(8 * sf)))
        info_label.setFont(info_font)
        info_label.setWordWrap(True)
        layout.addWidget(info_label)

        # 按钮区域（完全保留原始布局）
        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(max(1, int(20 * sf)))

        save_btn = StrokePushButton(_tr("edit_config.save"), self)
        save_btn.set_stroke_properties(int(2 * sf), '#000000')
        save_btn.setFixedSize(max(1, int(120 * sf)), max(1, int(40 * sf)))
        save_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(130, 255, 85, 0.5);
                color: #FFFFFF;
                font-weight: bold;
                border-radius: {max(1, int(6 * sf))}px;
                border: 3px solid #82FF55;
                padding: {max(1, int(2 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(130, 255, 85, 0.7);
            }}
            QPushButton:pressed {{
                background-color: rgba(100, 200, 65, 0.7);
            }}
        """)
        save_btn.setFont(btn_font)
        save_btn.clicked.connect(self.accept)

        delete_btn = StrokePushButton(_tr("edit_config.delete"), self)
        delete_btn.set_stroke_properties(int(2 * sf), '#000000')
        delete_btn.setFixedSize(max(1, int(120 * sf)), max(1, int(40 * sf)))
        delete_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 85, 85, 0.5);
                color: #FFFFFF;
                font-weight: bold;
                border-radius: {max(1, int(6 * sf))}px;
                border: 3px solid #FF5555;
                padding: {max(1, int(2 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(255, 85, 85, 0.7);
            }}
            QPushButton:pressed {{
                background-color: rgba(200, 65, 65, 0.7);
            }}
        """)
        delete_btn.setFont(btn_font)
        delete_btn.clicked.connect(self._delete_config)

        cancel_btn = StrokePushButton(_tr("edit_config.cancel"), self)
        cancel_btn.set_stroke_properties(int(2 * sf), '#000000')
        cancel_btn.setFixedSize(max(1, int(120 * sf)), max(1, int(40 * sf)))
        cancel_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.5);
                color: #FFFFFF;
                font-weight: bold;
                border-radius: {max(1, int(6 * sf))}px;
                border: 3px solid #bababa;
                padding: {max(1, int(2 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(85, 85, 127, 0.7);
            }}
            QPushButton:pressed {{
                background-color: rgba(65, 65, 100, 0.7);
            }}
        """)
        cancel_btn.setFont(btn_font)
        cancel_btn.clicked.connect(self.reject)

        btn_layout.addStretch()
        btn_layout.addWidget(save_btn)
        btn_layout.addWidget(delete_btn)
        btn_layout.addWidget(cancel_btn)
        btn_layout.addStretch()

        layout.addLayout(btn_layout)

        self.load_icon()
        self.setStyleSheet("background-color: transparent;")

    # 以下方法与原始版本完全一致
    def _browse_launch_program(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, _tr("edit_config.browse_title"), "", f"{_tr('filter.exe')} (*.exe);;{_tr('filter.all')} (*.*)")
        if file_path:
            self.launch_program_edit.setText(file_path)

    def _browse_target_program(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, _tr("edit_config.browse_title"), "", f"{_tr('filter.exe')} (*.exe);;{_tr('filter.all')} (*.*)")
        if file_path:
            self.target_program_edit.setText(file_path)

    def load_icon(self):
        if not hasattr(self, 'target_program_edit'):
            return
        sf = self.scale_factor
        self.icon_label.setScaledContents(True)
        custom_icon_path = self.custom_data.get('custom_icon_path')
        if custom_icon_path and os.path.exists(custom_icon_path):
            icon = QIcon(custom_icon_path)
            if not icon.isNull():
                self.custom_icon_path = custom_icon_path
                pixmap = icon.pixmap(self.icon_label.size())
                if not pixmap.isNull():
                    self.icon_label.setPixmap(pixmap)
                    return
        target = self.target_program_edit.text()
        if target and os.path.exists(target):
            file_info = QFileInfo(target)
            icon_provider = QFileIconProvider()
            icon = icon_provider.icon(file_info)
            if not icon.isNull():
                pixmap = icon.pixmap(self.icon_label.size())
                if not pixmap.isNull():
                    self.icon_label.setPixmap(pixmap)
                    return
        self.icon_label.clear()

    def change_icon(self):
        sf = self.scale_factor
        file_dialog = QFileDialog()
        file_dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
        file_dialog.setNameFilter(f"{_tr('filter.icon')} (*.png *.jpg *.jpeg *.ico)")
        file_dialog.setWindowTitle(_tr("edit_config.select_icon"))
        if file_dialog.exec():
            selected_files = file_dialog.selectedFiles()
            if selected_files:
                icon_path = selected_files[0]
                icon = QIcon(icon_path)
                if not icon.isNull():
                    self.custom_icon_path = icon_path
                    best_pixmap = None
                    best_size = 0
                    available_sizes = icon.availableSizes()
                    target_size = QSize(max(1, int(80 * sf)), max(1, int(80 * sf)))
                    if available_sizes:
                        for size in available_sizes:
                            area = size.width() * size.height()
                            if area > best_size:
                                best_size = area
                                best_pixmap = icon.pixmap(size)
                    else:
                        best_pixmap = icon.pixmap(max(1, int(80 * sf)), max(1, int(80 * sf)))
                    if best_pixmap and not best_pixmap.isNull():
                        scaled_pixmap = best_pixmap.scaled(
                            self.icon_label.size(),
                            Qt.AspectRatioMode.KeepAspectRatio,
                            Qt.TransformationMode.SmoothTransformation
                        )
                        self.icon_label.setPixmap(scaled_pixmap)
                        QMessageBox.information(self, _tr("dialog.success"), _tr("edit_config.icon_changed", file=os.path.basename(icon_path)))
                    else:
                        QMessageBox.warning(self, _tr("dialog.error"), _tr("edit_config.icon_load_failed"))
                else:
                    QMessageBox.warning(self, _tr("dialog.error"), _tr("edit_config.icon_load_failed"))

    def reset_icon(self):
        self.custom_icon_path = None
        if 'custom_icon_path' in self.custom_data:
            del self.custom_data['custom_icon_path']
        self.load_icon()
        QMessageBox.information(self, _tr("dialog.success"), _tr("edit_config.icon_reset"))

    def _delete_config(self):
        """删除当前配置"""
        reply = QMessageBox.question(
            self,
            _tr("dialog.confirm_delete_title"),
            _tr("dialog.confirm_delete_message", name=self.config_name),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            # 删除配置文件
            config_path = self.main_window.config_manager.get_config_path(self.config_name)
            if os.path.exists(config_path):
                os.remove(config_path)
            # 删除自定义数据
            if self.config_name in self.main_window.custom_data_manager.custom_data:
                del self.main_window.custom_data_manager.custom_data[self.config_name]
                self.main_window.custom_data_manager.save_custom_data()
            self.deleted = True
            self.accept()

    def get_custom_data(self):
        display_name = self.name_edit.text().strip()
        if not display_name:
            display_name = self.config_name
        return {
            'display_name': display_name,
            'custom_icon_path': self.custom_icon_path
        }


    def _add_dll_row(self, dll_path: str = ""):
        """添加一行 DLL 路径编辑控件"""
        sf = self.scale_factor
        row_widget = QWidget()
        row_widget.setStyleSheet("background-color: transparent;")
        row_layout = QHBoxLayout(row_widget)
        row_layout.setContentsMargins(0, 0, 0, 0)
        row_layout.setSpacing(max(1, int(4 * sf)))

        dll_edit = QLineEdit(self)
        dll_edit.setText(dll_path)
        dll_edit.setFixedHeight(max(1, int(26 * sf)))
        dll_edit.setStyleSheet(f"""
            QLineEdit {{
                background-color: #2D2D30;
                color: #FFFFFF;
                border: 2px solid #555555;
                border-radius: {max(1, int(4 * sf))}px;
                padding: {max(1, int(2 * sf))}px;
            }}
            QLineEdit:focus {{
                border: 2px solid #82FF55;
            }}
        """)
        small_font = QFont()
        small_font.setPointSize(max(1, int(10 * sf)))
        dll_edit.setFont(small_font)

        browse_btn = StrokePushButton(_tr("edit_config.browse_dll"), self)
        browse_btn.set_stroke_properties(int(2 * sf), '#000000')
        browse_btn.setFixedSize(max(1, int(50 * sf)), max(1, int(26 * sf)))
        browse_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.5);
                color: #FFFFFF;
                border-radius: {max(1, int(4 * sf))}px;
                border: 2px solid #bababa;
                padding: {max(1, int(2 * sf))}px;
                font-size: {max(1, int(10 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.6);
            }}
        """)
        browse_btn.setFont(small_font)
        browse_btn.clicked.connect(lambda checked, e=dll_edit: self._browse_dll(e))

        remove_btn = StrokePushButton(_tr("edit_config.remove_dll"), self)
        remove_btn.set_stroke_properties(int(2 * sf), '#000000')
        remove_btn.setFixedSize(max(1, int(50 * sf)), max(1, int(26 * sf)))
        remove_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 85, 85, 0.5);
                color: #FFFFFF;
                border-radius: {max(1, int(4 * sf))}px;
                border: 2px solid #FF5555;
                padding: {max(1, int(2 * sf))}px;
                font-size: {max(1, int(10 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(255, 85, 85, 0.7);
            }}
        """)
        remove_btn.setFont(small_font)
        remove_btn.clicked.connect(lambda checked, w=row_widget: self._remove_dll_row(w))

        row_layout.addWidget(dll_edit)
        row_layout.addWidget(browse_btn)

        # 上移按钮
        up_btn = QPushButton("▲", self)
        up_btn.setFixedSize(max(1, int(24 * sf)), max(1, int(24 * sf)))
        up_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.5);
                color: #FFFFFF;
                font-weight: bold;
                border-radius: {max(1, int(3 * sf))}px;
                border: 1px solid #555555;
                font-size: {max(1, int(8 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 130, 200, 0.7);
            }}
        """)
        up_btn.clicked.connect(lambda checked, w=row_widget: self._move_dll_row(w, -1))

        # 下移按钮
        down_btn = QPushButton("▼", self)
        down_btn.setFixedSize(max(1, int(24 * sf)), max(1, int(24 * sf)))
        down_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.5);
                color: #FFFFFF;
                font-weight: bold;
                border-radius: {max(1, int(3 * sf))}px;
                border: 1px solid #555555;
                font-size: {max(1, int(8 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 130, 200, 0.7);
            }}
        """)
        down_btn.clicked.connect(lambda checked, w=row_widget: self._move_dll_row(w, 1))

        row_layout.addWidget(up_btn)
        row_layout.addWidget(down_btn)
        row_layout.addWidget(remove_btn)

        self.dll_list_layout.insertWidget(self.dll_list_layout.count() - 1, row_widget)
        self.dll_rows.append(row_widget)

    def _move_dll_row(self, row_widget, direction):
        """移动 DLL 行排序：direction=-1 上移, direction=1 下移"""
        idx = self.dll_list_layout.indexOf(row_widget)
        if idx < 0:
            return
        new_idx = idx + direction
        # 不能移到 stretch 之后（stretch 在最后一项）
        if new_idx < 0 or new_idx >= self.dll_list_layout.count() - 1:
            return
        # 交换在 dll_rows 中的位置
        row_idx = self.dll_rows.index(row_widget)
        swap_idx = row_idx + direction
        if swap_idx < 0 or swap_idx >= len(self.dll_rows):
            return
        self.dll_rows[row_idx], self.dll_rows[swap_idx] = self.dll_rows[swap_idx], self.dll_rows[row_idx]
        # 在布局中移动 widget
        self.dll_list_layout.insertWidget(new_idx, self.dll_list_layout.takeAt(idx).widget())

    def _remove_dll_row(self, row_widget):
        """删除一行 DLL 路径"""
        if row_widget in self.dll_rows:
            self.dll_rows.remove(row_widget)
        self.dll_list_layout.removeWidget(row_widget)
        row_widget.deleteLater()

    def _browse_dll(self, dll_edit):
        """浏览选择 DLL 文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, _tr("file_dialog.select_dll"), "", f"DLL (*.dll);;{_tr('filter.all')} (*.*)")
        if file_path:
            dll_edit.setText(file_path)

    def get_config_data(self) -> Dict[str, Any]:
        new_config = self.config_data.copy()
        new_config['launch_program'] = self.launch_program_edit.text().replace('\\', '/')
        new_config['target_program'] = self.target_program_edit.text().replace('\\', '/')
        new_config['launch_args'] = self.launch_args_edit.text()
        new_config['force_center_window'] = self.center_checkbox.isChecked()
        new_config['center_window_duration'] = self.center_duration_spin.value()
        # 收集 DLL 列表
        dll_files = []
        has_reshade = False
        for row_widget in self.dll_rows:
            dll_edit = row_widget.findChild(QLineEdit)
            if dll_edit and dll_edit.text().strip():
                path = dll_edit.text().strip().replace('\\', '/')
                if path == "ReShade64.dll":
                    has_reshade = True
                else:
                    dll_files.append(path)
        new_config['dll_files'] = dll_files
        # 根据列表中是否包含 ReShade64.dll 设置启用状态
        if has_reshade:
            new_config['reshade_dll'] = 'ReShade64.dll'
        else:
            new_config.pop('reshade_dll', None)
        return new_config

    def accept(self):
        """重写 accept：保存时应用或移除 DPI 覆盖设置"""
        if self.dpi_checkbox.isChecked():
            err = _apply_dpi_override(self._dpi_exe_path)
        else:
            err = _remove_dpi_override(self._dpi_exe_path)
        if err:
            from PyQt6.QtWidgets import QMessageBox
            QMessageBox.warning(self, _tr("dialog.error"),
                _tr("edit_config.dpi_error", error=err))
        super().accept()

# ----------------------------------------------------------------------
# DLL文件列表对话框（完整实现）
# 修改：背景全透明，列表项使用描边标签
# ----------------------------------------------------------------------
class DllFileListDialog(StyledDialog):
    """自定义模式的文件列表对话框（已缩放）"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle(_tr("dll_list.title"))
        self.setWindowFlags(Qt.WindowType.Dialog)
        self.setFixedSize(max(1, int(600 * self.scale_factor)), max(1, int(400 * self.scale_factor)))
        self.dll_files = []

        # 居中显示
        if parent and parent.isVisible():
            parent_center = parent.frameGeometry().center()
            self.move(parent_center.x() - self.width() // 2,
                      parent_center.y() - self.height() // 2)

        self.setup_ui()

    def setup_ui(self):
        sf = self.scale_factor
        layout = QVBoxLayout(self)

        title_label = StrokeLabel_4(_tr("dll_list.header"), self)
        title_label.set_stroke_properties(int(2 * sf), '#000000')
        title_label.setStyleSheet("color: #FFFFFF; font-weight: bold; background-color: transparent;")
        title_font = QFont()
        title_font.setPointSize(max(1, int(16 * sf)))
        title_font.setBold(True)
        title_label.setFont(title_font)
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title_label)

        # 列表控件：背景透明，保留边框和选中样式
        self.list_widget = QListWidget(self)
        self.list_widget.setStyleSheet(f"""
            QListWidget {{
                background-color: transparent;
                color: #FFFFFF;
                border: 1px solid #555555;
                border-radius: {max(1, int(5 * sf))}px;
            }}
            QListWidget::item {{
                padding: {max(1, int(5 * sf))}px;
            }}
            QListWidget::item:selected {{
                background-color: #555577;
            }}
        """)
        list_font = QFont()
        list_font.setPointSize(max(1, int(12 * sf)))
        self.list_widget.setFont(list_font)
        layout.addWidget(self.list_widget)

        btn_layout = QHBoxLayout()
        btn_style = f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {max(1, int(5 * sf))}px;
                border: 3px solid #bababa;
                padding: {max(1, int(5 * sf))}px {max(1, int(15 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
            }}
        """
        btn_font = QFont()
        btn_font.setPointSize(max(1, int(14 * sf)))

        add_btn = StrokePushButton(_tr("dll_list.add"), self)
        add_btn.set_stroke_properties(int(2 * sf), '#000000')
        add_btn.setStyleSheet(btn_style)
        add_btn.setFont(btn_font)
        add_btn.clicked.connect(self.add_dll_file)

        remove_btn = StrokePushButton(_tr("dll_list.remove"), self)
        remove_btn.set_stroke_properties(int(2 * sf), '#000000')
        remove_btn.setStyleSheet(btn_style)
        remove_btn.setFont(btn_font)
        remove_btn.clicked.connect(self.remove_selected_file)

        clear_btn = StrokePushButton(_tr("dll_list.clear"), self)
        clear_btn.set_stroke_properties(int(2 * sf), '#000000')
        clear_btn.setStyleSheet(btn_style)
        clear_btn.setFont(btn_font)
        clear_btn.clicked.connect(self.clear_list)

        next_btn = StrokePushButton(_tr("dll_list.next"), self)
        next_btn.set_stroke_properties(int(2 * sf), '#000000')
        next_btn.setStyleSheet(btn_style)
        next_btn.setFont(btn_font)
        next_btn.clicked.connect(self.accept)

        cancel_btn = StrokePushButton(_tr("dialog.cancel"), self)
        cancel_btn.set_stroke_properties(int(2 * sf), '#000000')
        cancel_btn.setStyleSheet(btn_style)
        cancel_btn.setFont(btn_font)
        cancel_btn.clicked.connect(self.reject)

        btn_layout.addWidget(add_btn)
        btn_layout.addWidget(remove_btn)
        btn_layout.addWidget(clear_btn)
        btn_layout.addStretch()
        btn_layout.addWidget(next_btn)
        btn_layout.addWidget(cancel_btn)

        layout.addLayout(btn_layout)
        layout.setContentsMargins(max(1, int(20 * sf)), max(1, int(20 * sf)),
                                  max(1, int(20 * sf)), max(1, int(20 * sf)))
        self.setStyleSheet("background-color: transparent;")

    def add_dll_file(self):
        file_dialog = QFileDialog()
        file_dialog.setFileMode(QFileDialog.FileMode.ExistingFiles)
        file_dialog.setNameFilter(f"{_tr('filter.dll')} (*.dll)")
        file_dialog.setWindowTitle(_tr("file_dialog.select_dll"))
        if file_dialog.exec():
            file_names = file_dialog.selectedFiles()
            for file_name in file_names:
                if file_name not in self.dll_files:
                    self.dll_files.append(file_name)

                    # 创建项，并存储文件名到 data
                    item = QListWidgetItem()
                    item.setData(Qt.ItemDataRole.UserRole, file_name)

                    # 根据缩放因子设置项的高度
                    row_height = int(30 * self.scale_factor)
                    item.setSizeHint(QSize(0, row_height))

                    # 创建包含描边标签的 widget
                    container = QWidget()
                    container.setStyleSheet("background-color: transparent;")
                    layout = QHBoxLayout(container)
                    layout.setContentsMargins(5, 0, 5, 0)

                    label = StrokeLabel_4(file_name, container)
                    label.set_stroke_properties(int(2 * self.scale_factor), '#000000')
                    label.setStyleSheet("color: #FFFFFF; background-color: transparent;")
                    label.setWordWrap(False)
                    label.setFixedWidth(int(10000 * self.scale_factor))
                    label.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
                    

                    layout.addWidget(label)
                    layout.addStretch()

                    self.list_widget.addItem(item)
                    self.list_widget.setItemWidget(item, container)

    def remove_selected_file(self):
        selected_items = self.list_widget.selectedItems()
        for item in selected_items:
            file_name = item.data(Qt.ItemDataRole.UserRole)
            if file_name in self.dll_files:
                self.dll_files.remove(file_name)
            self.list_widget.takeItem(self.list_widget.row(item))

    def clear_list(self):
        self.dll_files.clear()
        self.list_widget.clear()


# ----------------------------------------------------------------------
# 启动模式选择对话框（修正版：文本白色、复选框不换行）
# ----------------------------------------------------------------------
class LaunchModeDialog(StyledDialog):
    """启动模式选择对话框（已缩放）- 完全去除反色，所有文本带描边，描述文字为白色"""
    def __init__(self, config_manager, parent=None):
        super().__init__(parent)
        self.config_manager = config_manager
        self.setWindowTitle(_tr("launch_mode.title"))
        self.setWindowFlags(Qt.WindowType.Dialog)
        self.setFixedSize(max(1, int(600 * self.scale_factor)), max(1, int(400 * self.scale_factor)))
        self.settings = QSettings("ReShadeLauncher", "LaunchMode")
        self.setup_ui()

    def setup_ui(self):
        sf = self.scale_factor
        layout = QVBoxLayout(self)

        # 标题（描边）
        title_label = StrokeLabel_4(_tr("launch_mode.prompt"), self)
        title_label.set_stroke_properties(int(2 * sf), '#000000')
        title_label.setStyleSheet("color: #FFFFFF; font-weight: bold; background-color: transparent;")
        title_font = QFont()
        title_font.setPointSize(max(1, int(18 * sf)))
        title_font.setBold(True)
        title_label.setFont(title_font)
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title_label)

        btn_grid = QVBoxLayout()
        btn_grid.setSpacing(max(1, int(15 * sf)))

        btn_normal_base = f"""
            background-color: rgba(85, 85, 127, 0.38);
            font-weight: bold;
            border-radius: {max(1, int(5 * sf))}px;
            border: 3px solid;
            padding: {max(1, int(5 * sf))}px {max(1, int(2 * sf))}px;
            min-width: {max(1, int(80 * sf))}px;
        """

        btn_hover_style = f"""
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
            }}
        """
        btn_font = QFont()
        btn_font.setPointSize(max(1, int(14 * sf)))
        btn_font.setBold(True)

        desc_font = QFont()
        desc_font.setPointSize(max(1, int(10 * sf)))
        xxmi_font = QFont()
        xxmi_font.setPointSize(max(1, int(14 * sf)))

        # XXMI 模式
        xxmi_layout = QHBoxLayout()
        xxmi_label = StrokeLabel_4(_tr("launch_mode.xxmi"), self)
        xxmi_label.set_stroke_properties(int(2 * sf), '#000000')
        xxmi_label.setStyleSheet("color: #55FFFF; min-width: {}px; background-color: transparent;".format(max(1, int(100 * sf))))
        xxmi_label.setFont(xxmi_font)
        xxmi_layout.addWidget(xxmi_label)

        xxmi_desc = StrokeLabel_4(_tr("launch_mode.xxmi.desc"), self)
        xxmi_desc.set_stroke_properties(int(2 * sf), '#000000')
        xxmi_desc.setStyleSheet("color: #FFFFFF; background-color: transparent;")  # 改为白色
        xxmi_desc.setFont(desc_font)
        xxmi_layout.addWidget(xxmi_desc)

        xxmi_btn = StrokePushButton(_tr("launch_mode.btn_xxmi"), self)
        xxmi_btn.set_stroke_properties(int(2 * sf), '#000000')
        xxmi_btn.setStyleSheet(f"""
            QPushButton {{
                {btn_normal_base}
                color: #55FFFF;
                border-color: #55FFFF;
            }}
            {btn_hover_style}
        """)
        xxmi_btn.setFont(btn_font)
        xxmi_btn.clicked.connect(lambda: self.handle_mode_selected("xxmi"))
        xxmi_layout.addWidget(xxmi_btn)
        btn_grid.addLayout(xxmi_layout)

        # 内置模式
        builtin_layout = QHBoxLayout()
        builtin_label = StrokeLabel_4(_tr("launch_mode.builtin"), self)
        builtin_label.set_stroke_properties(int(2 * sf), '#000000')
        builtin_label.setStyleSheet("color: #FFA855; min-width: {}px; background-color: transparent;".format(max(1, int(100 * sf))))
        builtin_label.setFont(xxmi_font)
        builtin_layout.addWidget(builtin_label)

        builtin_desc = StrokeLabel_4(_tr("launch_mode.builtin.desc"), self)
        builtin_desc.set_stroke_properties(int(2 * sf), '#000000')
        builtin_desc.setStyleSheet("color: #FFFFFF; background-color: transparent;")  # 改为白色
        builtin_desc.setFont(desc_font)
        builtin_layout.addWidget(builtin_desc)

        builtin_btn = StrokePushButton(_tr("launch_mode.btn_builtin"), self)
        builtin_btn.set_stroke_properties(int(2 * sf), '#000000')
        builtin_btn.setStyleSheet(f"""
            QPushButton {{
                {btn_normal_base}
                color: #FFA855;
                border-color: #FFA855;
            }}
            {btn_hover_style}
        """)
        builtin_btn.setFont(btn_font)
        builtin_btn.clicked.connect(lambda: self.handle_mode_selected("builtin"))
        builtin_layout.addWidget(builtin_btn)
        btn_grid.addLayout(builtin_layout)

        # 游戏模式
        game_layout = QHBoxLayout()
        game_label = StrokeLabel_4(_tr("launch_mode.game"), self)
        game_label.set_stroke_properties(int(2 * sf), '#000000')
        game_label.setStyleSheet("color: #82FF55; min-width: {}px; background-color: transparent;".format(max(1, int(100 * sf))))
        game_label.setFont(xxmi_font)
        game_layout.addWidget(game_label)

        game_desc = StrokeLabel_4(_tr("launch_mode.game.desc"), self)
        game_desc.set_stroke_properties(int(2 * sf), '#000000')
        game_desc.setStyleSheet("color: #FFFFFF; background-color: transparent;")  # 改为白色
        game_desc.setFont(desc_font)
        game_layout.addWidget(game_desc)

        game_btn = StrokePushButton(_tr("launch_mode.btn_game"), self)
        game_btn.set_stroke_properties(int(2 * sf), '#000000')
        game_btn.setStyleSheet(f"""
            QPushButton {{
                {btn_normal_base}
                color: #82FF55;
                border-color: #82FF55;
            }}
            {btn_hover_style}
        """)
        
        game_btn.setFont(btn_font)
        game_btn.clicked.connect(lambda: self.handle_mode_selected("reshade"))
        game_layout.addWidget(game_btn)
        btn_grid.addLayout(game_layout)

        # 自定义模式
        custom_layout = QHBoxLayout()
        custom_label = StrokeLabel_4(_tr("launch_mode.custom"), self)
        custom_label.set_stroke_properties(int(2 * sf), '#000000')
        custom_label.setStyleSheet("color: #FF55FF; min-width: {}px; background-color: transparent;".format(max(1, int(100 * sf))))
        custom_label.setFont(xxmi_font)
        custom_layout.addWidget(custom_label)

        custom_desc = StrokeLabel_4(_tr("launch_mode.custom.desc"), self)
        custom_desc.set_stroke_properties(int(2 * sf), '#000000')
        custom_desc.setStyleSheet("color: #FFFFFF; background-color: transparent;")  # 改为白色
        custom_desc.setFont(desc_font)
        custom_layout.addWidget(custom_desc)

        custom_btn = StrokePushButton(_tr("launch_mode.btn_custom"), self)
        custom_btn.set_stroke_properties(int(2 * sf), '#000000')
        custom_btn.setStyleSheet(f"""
            QPushButton {{
                {btn_normal_base}
                color: #FF55FF;
                border-color: #FF55FF;
            }}
            {btn_hover_style}
        """)
        custom_btn.setFont(btn_font)
        custom_btn.clicked.connect(lambda: self.handle_mode_selected("custom"))
        custom_layout.addWidget(custom_btn)
        btn_grid.addLayout(custom_layout)

        layout.addLayout(btn_grid)

        # ReShade 开关（使用修正后的自定义描边复选框，并设置最小宽度避免换行）
        reshade_container = QVBoxLayout()
        reshade_container.setSpacing(max(1, int(10 * sf)))

        self.reshade_checkbox = StrokeCheckBox(_tr("launch_mode.reshade_checkbox"), self, int(2 * sf), '#000000')
        self.reshade_checkbox.setStyleSheet("background-color: transparent;")
        # 设置最小宽度，确保文本不换行
        self.reshade_checkbox.setMinimumWidth(int(530 * sf))
        chk_font = QFont()
        chk_font.setPointSize(max(1, int(13 * sf)))
        self.reshade_checkbox.setFont(chk_font)

        reshade_enabled = self.settings.value("reshade_enabled", True, type=bool)
        self.reshade_checkbox.setChecked(reshade_enabled)

        reshade_hint = StrokeLabel_4(_tr("launch_mode.reshade_hint"), self)
        reshade_hint.set_stroke_properties(int(2 * sf), '#000000')
        reshade_hint.setStyleSheet("color: #FFFFFF; font-style: italic; padding-left: 22px; background-color: transparent;")  # 改为白色
        hint_font = QFont()
        hint_font.setPointSize(max(1, int(14 * sf)))
        reshade_hint.setFont(hint_font)

        reshade_container.addWidget(self.reshade_checkbox, alignment=Qt.AlignmentFlag.AlignLeft)
        reshade_container.addWidget(reshade_hint, alignment=Qt.AlignmentFlag.AlignLeft)

        reshade_wrapper = QHBoxLayout()
        reshade_wrapper.addStretch()
        reshade_wrapper.addLayout(reshade_container)
        reshade_wrapper.addStretch()

        layout.addLayout(reshade_wrapper)
        layout.addStretch()

        # 取消按钮
        cancel_btn = StrokePushButton(_tr("dialog.cancel"), self)
        cancel_btn.set_stroke_properties(int(2 * sf), '#000000')
        cancel_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {max(1, int(5 * sf))}px;
                border: 3px solid #bababa;
                padding: {max(1, int(8 * sf))}px {max(1, int(30 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
            }}
        """)
        cancel_btn.setFont(btn_font)
        cancel_btn.clicked.connect(self.reject)
        layout.addWidget(cancel_btn, alignment=Qt.AlignmentFlag.AlignCenter)

        layout.setContentsMargins(max(1, int(30 * sf)), max(1, int(30 * sf)),
                                  max(1, int(30 * sf)), max(1, int(30 * sf)))
        self.setStyleSheet("background-color: transparent;")

    def handle_mode_selected(self, mode):
        self.settings.setValue("reshade_enabled", self.reshade_checkbox.isChecked())
        self.selected_mode = mode
        self.enable_reshade = self.reshade_checkbox.isChecked()
        self.accept()


# ----------------------------------------------------------------------
# XXMI 游戏选择对话框（修复标题裁剪）
# ----------------------------------------------------------------------
class XXMIGameSelector(StyledDialog):
    """XXMI 游戏选择对话框（下拉列表）- 修复标题裁剪问题"""
    def __init__(self, game_list: List[dict], parent=None):
        super().__init__(parent)
        self.game_list = game_list
        self.selected_game = None

        if self.scale_factor <= 0:
            print(f"[警告] XXMIGameSelector 缩放系数无效: {self.scale_factor}，已重置为 1.0")
            self.scale_factor = 1.0
        else:
            self.scale_factor = max(0.1, self.scale_factor)

        self.setWindowTitle(_tr("xxmi_selector.title"))
        self.setFixedSize(max(1, int(450 * self.scale_factor)), max(1, int(250 * self.scale_factor)))
        self.setup_ui()

    def setup_ui(self):
        sf = self.scale_factor
        layout = QVBoxLayout(self)
        layout.setSpacing(int(15 * sf))

        # 标题（描边）- 设置自动换行，确保完整显示
        title = StrokeLabel_4(_tr("xxmi_selector.prompt"), self)
        title.set_stroke_properties(int(2 * sf), '#000000')
        title.setStyleSheet("color: #FFFFFF; font-weight: bold; background-color: transparent;")
        title_font = QFont()
        title_font.setPointSize(max(8, int(16 * sf)))
        title.setFont(title_font)
        title.setWordWrap(True)
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.setMinimumHeight(int(50 * sf))
        layout.addWidget(title)

        self.combo = QComboBox(self)
        combo_font = QFont()
        combo_font.setPointSize(max(1, int(14 * sf)))
        self.combo.setFont(combo_font)
        self.combo.view().setFont(combo_font)
        self.combo.setStyleSheet(f"""
            QComboBox {{
                background-color: #2D2D30;
                color: #FFFFFF;
                border: 2px solid #555555;
                border-radius: {max(1, int(14*sf))}px;
                padding: {max(1, int(8*sf))}px;
                min-height: {max(1, int(20*sf))}px;
            }}
            QComboBox::drop-down {{
                border: none;
            }}
            QComboBox QAbstractItemView {{
                background-color: #2D2D30;
                color: #FFFFFF;
                selection-background-color: #555577;
            }}
        """)

        for game in self.game_list:
            name_key = game.get('name_key')
            display_name = _tr(name_key) if name_key else game.get('exe', '')
            self.combo.addItem(display_name, game)

        layout.addWidget(self.combo)

        btn_layout = QHBoxLayout()
        ok_btn = StrokePushButton(_tr("xxmi_selector.ok"), self)
        ok_btn.set_stroke_properties(int(2 * sf), '#000000')
        cancel_btn = StrokePushButton(_tr("dialog.cancel"), self)
        cancel_btn.set_stroke_properties(int(2 * sf), '#000000')
        btn_style = f"""
            QPushButton {{
                background-color: rgba(85,85,127,0.38);
                color: #FFFFFF;
                border-radius: {max(1, int(14*sf))}px;
                border: 3px solid #bababa;
                padding: {max(1, int(8*sf))}px {max(1, int(20*sf))}px;
            }}
            QPushButton:hover {{ background-color: rgba(0,90,158,0.38); }}
        """
        btn_font = QFont()
        btn_font.setPointSize(max(1, int(14 * sf)))
        ok_btn.setStyleSheet(btn_style)
        ok_btn.setFont(btn_font)
        ok_btn.clicked.connect(self.accept)
        cancel_btn.setStyleSheet(btn_style)
        cancel_btn.setFont(btn_font)
        cancel_btn.clicked.connect(self.reject)

        btn_layout.addStretch()
        btn_layout.addWidget(ok_btn)
        btn_layout.addWidget(cancel_btn)
        btn_layout.addStretch()
        layout.addLayout(btn_layout)

        layout.setContentsMargins(max(1, int(20*sf)), max(1, int(20*sf)),
                                  max(1, int(20*sf)), max(1, int(20*sf)))
        self.setStyleSheet("background-color: transparent;")

    def accept(self):
        self.selected_game = self.combo.currentData()
        super().accept()


# ----------------------------------------------------------------------
# 询问对话框（是/否）
# ----------------------------------------------------------------------
class QuestionDialog(StyledDialog):
    """询问对话框（是/否），样式与 SimpleMessageBox 完全一致"""
    def __init__(self, title="", message="", parent=None):
        super().__init__(parent)
        self.setWindowTitle(title if title else _tr("question.title"))
        self.setWindowFlags(Qt.WindowType.Dialog)
        self.setFixedSize(max(1, int(450 * self.scale_factor)), max(1, int(220 * self.scale_factor)))
        self.setup_ui(message)

    def setup_ui(self, message):
        sf = self.scale_factor
        layout = QVBoxLayout(self)

        label = StrokeLabel_4(message, self)
        label.set_stroke_properties(int(2 * sf), '#000000')
        label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        label.setWordWrap(True)
        label.setStyleSheet("color: #FFFFFF; background-color: transparent;")
        font = QFont()
        font.setPointSize(max(1, int(14 * sf)))
        label.setFont(font)
        layout.addWidget(label)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(max(1, int(30 * sf)))

        yes_btn = StrokePushButton(_tr("dialog.yes"), self)
        yes_btn.set_stroke_properties(int(2 * sf), '#000000')
        yes_btn.setMinimumSize(max(1, int(100 * sf)), max(1, int(40 * sf)))
        yes_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {max(1, int(5 * sf))}px;
                border: 3px solid #bababa;
                padding: {max(1, int(5 * sf))}px;
                font-size: {int(14 * sf)}px;
                font-weight: bold;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
            }}
        """)
        yes_btn.clicked.connect(self.accept)

        no_btn = StrokePushButton(_tr("dialog.no"), self)
        no_btn.set_stroke_properties(int(2 * sf), '#000000')
        no_btn.setMinimumSize(max(1, int(100 * sf)), max(1, int(40 * sf)))
        no_btn.setStyleSheet(yes_btn.styleSheet())
        no_btn.clicked.connect(self.reject)

        btn_layout.addStretch()
        btn_layout.addWidget(yes_btn)
        btn_layout.addWidget(no_btn)
        btn_layout.addStretch()

        layout.addLayout(btn_layout)
        layout.setContentsMargins(max(1, int(20 * sf)), max(1, int(20 * sf)),
                                  max(1, int(20 * sf)), max(1, int(20 * sf)))
        layout.setSpacing(max(1, int(15 * sf)))

        self.setStyleSheet("background-color: transparent;")

# ========== 修改后：mod切换参数保存窗口（集成外部脚本，已国际化） ==========
from PyQt6.QtCore import QThread, pyqtSignal
from PyQt6.QtWidgets import QFileDialog, QMessageBox
from mod预设保存 import Worker  # 导入外部脚本的工作类

class WorkerThread(QThread):
    """后台工作线程，执行 Worker.run() 并将日志通过信号发送"""
    log_signal = pyqtSignal(str)
    finished_signal = pyqtSignal()

    def __init__(self, d3dx_path, target_dir):
        super().__init__()
        self.d3dx_path = d3dx_path
        self.target_dir = target_dir

    def run(self):
        worker = Worker(self.d3dx_path, self.target_dir)
        # 重定向 log 方法，同时输出到控制台和发送信号
        original_log = worker.log
        worker.log = lambda msg: (original_log(msg), self.log_signal.emit(msg))
        try:
            worker.run()
        finally:
            self.finished_signal.emit()


class FileListDemoDialog(StyledDialog):
    """mod切换参数保存窗口 - 集成外部脚本处理mod预设参数（已国际化）"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent  # 保存主窗口引用，用于获取当前配置
        self.setWindowTitle(_tr("mod_preset.title"))
        self.setWindowFlags(Qt.WindowType.Dialog)
        self.setFixedSize(max(1, int(600 * self.scale_factor)), max(1, int(400 * self.scale_factor)))
        self.worker_thread = None
        self.setup_ui()

    def setup_ui(self):
        sf = self.scale_factor
        layout = QVBoxLayout(self)

        # 标题（描边标签，允许换行）
        title_label = StrokeLabel_4(_tr("mod_preset.header"), self)
        title_label.set_stroke_properties(int(2 * sf), '#000000')
        title_label.setStyleSheet("color: #FFFFFF; font-weight: bold; background-color: transparent;")
        title_font = QFont()
        title_font.setPointSize(max(1, int(14 * sf)))
        title_font.setBold(True)
        title_label.setFont(title_font)
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title_label.setWordWrap(True)
        layout.addWidget(title_label)

        # 日志显示文本框（只读，用于显示处理过程）
        self.text_edit = QTextEdit(self)
        self.text_edit.setReadOnly(True)
        self.text_edit.setStyleSheet(f"""
            QTextEdit {{
                background-color: rgba(0, 0, 0, 0.7);
                color: #FFFFFF;
                border: 2px solid #555555;
                border-radius: {max(1, int(6 * sf))}px;
                padding: {max(1, int(8 * sf))}px;
                font-size: {max(1, int(12 * sf))}px;
            }}
        """)
        self.text_edit.setPlaceholderText(_tr("mod_preset.log_placeholder"))
        layout.addWidget(self.text_edit)

        # 底部按钮（两个居中）
        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(max(1, int(20 * sf)))

        btn_style = f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {max(1, int(5 * sf))}px;
                border: 3px solid #bababa;
                padding: {max(1, int(8 * sf))}px {max(1, int(30 * sf))}px;
                font-size: {max(1, int(14 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
            }}
        """
        btn_font = QFont()
        btn_font.setPointSize(max(1, int(14 * sf)))

        # 左边按钮：所有mod（触发对当前游戏mods文件夹的处理）
        self.all_mod_btn = StrokePushButton(_tr("mod_preset.all_mods"), self)
        self.all_mod_btn.set_stroke_properties(int(2 * sf), '#000000')
        self.all_mod_btn.setStyleSheet(btn_style)
        self.all_mod_btn.setFont(btn_font)
        self.all_mod_btn.clicked.connect(self.on_all_mods)

        # 右边按钮：选定mod（选择文件夹后处理）
        self.selected_mod_btn = StrokePushButton(_tr("mod_preset.selected_mod"), self)
        self.selected_mod_btn.set_stroke_properties(int(2 * sf), '#000000')
        self.selected_mod_btn.setStyleSheet(btn_style)
        self.selected_mod_btn.setFont(btn_font)
        self.selected_mod_btn.clicked.connect(self.on_select_folder)

        btn_layout.addStretch()
        btn_layout.addWidget(self.all_mod_btn)
        btn_layout.addWidget(self.selected_mod_btn)
        btn_layout.addStretch()

        layout.addLayout(btn_layout)
        layout.setContentsMargins(max(1, int(20 * sf)), max(1, int(20 * sf)),
                                  max(1, int(20 * sf)), max(1, int(20 * sf)))
        self.setStyleSheet("background-color: transparent;")

    # ---------- 辅助方法：获取当前游戏配置的 d3dx_user.ini 和 mods 文件夹路径 ----------
    def get_current_game_paths(self):
        """
        根据主窗口的当前配置，返回 (d3dx_user_ini_path, mods_folder_path)
        支持所有模式（xxmi、builtin、game、custom）
        若无法确定，返回 (None, None)
        """
        if not self.main_window or not self.main_window.current_config:
            return None, None

        config = self.main_window.current_config

        # ===== 收集所有候选 DLL 目录 =====
        candidate_dirs = []

        # 1. 从 dll_files 列表收集
        if config.get('dll_files'):
            for dll in config['dll_files']:
                if dll and os.path.exists(dll):
                    dll_dir = os.path.dirname(dll)
                    if dll_dir not in candidate_dirs:
                        candidate_dirs.append(dll_dir)

        # 2. 从 d3d11_path 收集
        d3d11_path = config.get('d3d11_path')
        if d3d11_path and os.path.exists(d3d11_path):
            dll_dir = os.path.dirname(d3d11_path)
            if dll_dir not in candidate_dirs:
                candidate_dirs.append(dll_dir)

        # 3. 针对 XXMI 模式：通过 xxmi_launcher_path 定位模块目录
        if config.get('mode') == 'xxmi':
            xxmi_launcher = config.get('xxmi_launcher_path')
            if xxmi_launcher and os.path.exists(xxmi_launcher):
                try:
                    resources_dir = os.path.dirname(os.path.dirname(xxmi_launcher))
                    xxmi_root = os.path.dirname(resources_dir)
                    if os.path.isdir(xxmi_root):
                        for entry in os.listdir(xxmi_root):
                            module_dir = os.path.join(xxmi_root, entry)
                            if os.path.isdir(module_dir) and module_dir not in candidate_dirs:
                                dll_path = os.path.join(module_dir, 'd3d11.dll')
                                if os.path.exists(dll_path):
                                    candidate_dirs.append(module_dir)
                except Exception:
                    pass

        # 4. 从 launch_program / game_dir 收集（游戏 exe 所在目录）
        for key in ('launch_program', 'game_dir'):
            path = config.get(key)
            if path and os.path.exists(path):
                parent = os.path.dirname(path) if os.path.isfile(path) else path
                if parent not in candidate_dirs:
                    candidate_dirs.append(parent)

        # 5. 如果用户已保存 mods_folder，直接返回
        saved_mods = config.get('mods_folder')
        if saved_mods:
            # 同时尝试找 d3dx_user.ini
            parent = os.path.dirname(saved_mods) if not os.path.isfile(saved_mods) else saved_mods
            d3dx_candidate = os.path.join(parent, 'd3dx_user.ini')
            if not os.path.exists(d3dx_candidate):
                d3dx_candidate = os.path.join(saved_mods, '..', 'd3dx_user.ini')
                d3dx_candidate = os.path.normpath(d3dx_candidate)
            d3dx_ini = d3dx_candidate if os.path.exists(d3dx_candidate) else None
            return d3dx_ini, saved_mods

        # ===== 遍历候选目录查找 d3dx_user.ini 和 mods 文件夹 =====
        d3dx_ini_path = None
        found_mods = None

        for dll_dir in candidate_dirs:
            # 检查 d3dx_user.ini
            if d3dx_ini_path is None:
                ini_candidate = os.path.join(dll_dir, 'd3dx_user.ini')
                if os.path.exists(ini_candidate):
                    d3dx_ini_path = ini_candidate

            # 检查 mods 文件夹
            if found_mods is None:
                mods_candidate = os.path.join(dll_dir, 'mods')
                if os.path.isdir(mods_candidate):
                    found_mods = mods_candidate

            # 两者都找到就可以提前退出
            if d3dx_ini_path and found_mods:
                break

        # 如果找到了 ini 但没找到 mods，用 ini 所在目录的 mods
        if d3dx_ini_path and found_mods is None:
            ini_dir = os.path.dirname(d3dx_ini_path)
            found_mods = os.path.join(ini_dir, 'mods')

        # 如果都没找到但有候选目录，用第一个候选目录的 mods
        if found_mods is None and candidate_dirs:
            found_mods = os.path.join(candidate_dirs[0], 'mods')

        return d3dx_ini_path, found_mods

    def run_worker(self, d3dx_path, target_dir):
        """启动后台线程处理指定的文件夹"""
        if self.worker_thread and self.worker_thread.isRunning():
            QMessageBox.warning(self, _tr("dialog.info"), _tr("mod_preset.error.task_running"))
            return

        # 清空日志显示
        self.text_edit.clear()

        # 检查 d3dx_user.ini 是否存在
        if not d3dx_path or not os.path.exists(d3dx_path):
            QMessageBox.critical(self, _tr("dialog.error"), _tr("mod_preset.error.d3dx_not_exist").format(d3dx_path))
            return

        # 检查目标文件夹是否存在
        if not target_dir or not os.path.isdir(target_dir):
            QMessageBox.critical(self, _tr("dialog.error"), _tr("mod_preset.error.target_folder_not_exist").format(target_dir))
            return

        # 创建并启动工作线程
        self.worker_thread = WorkerThread(d3dx_path, target_dir)
        self.worker_thread.log_signal.connect(self.append_log)
        self.worker_thread.finished_signal.connect(self.on_worker_finished)
        self.worker_thread.start()

        # 禁用按钮防止重复点击
        self.all_mod_btn.setEnabled(False)
        self.selected_mod_btn.setEnabled(False)

    def append_log(self, msg):
        """将日志消息追加到文本框"""
        self.text_edit.append(msg)

    def on_worker_finished(self):
        """线程结束后的处理"""
        self.all_mod_btn.setEnabled(True)
        self.selected_mod_btn.setEnabled(True)
        self.worker_thread = None
        self.append_log(_tr("mod_preset.completed"))

    # ---------- 按钮事件 ----------
    def on_all_mods(self):
        """处理当前游戏的所有mod（mods文件夹）"""
        if not self.main_window or not self.main_window.current_config:
            QMessageBox.warning(self, _tr("dialog.info"), _tr("mod_preset.error.no_config"))
            return

        d3dx_path, mods_folder = self.get_current_game_paths()

        # 如果 mods 文件夹找不到，让用户手动选择
        if not mods_folder or not os.path.isdir(mods_folder):
            reply = QMessageBox.question(
                self,
                _tr("dialog.info"),
                _tr("mod_preset.ask_select_mods_folder"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
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
                self,
                _tr("dialog.info"),
                _tr("mod_preset.ask_continue_no_d3dx"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if reply != QMessageBox.StandardButton.Yes:
                return

        reply = QMessageBox.question(
            self,
            _tr("dialog.info"),
            _tr("mod_preset.confirm_all"),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            self.run_worker(d3dx_path, mods_folder)

    def on_select_folder(self):
        """弹出文件夹选择窗口，处理用户选定的文件夹"""
        folder = QFileDialog.getExistingDirectory(self, _tr("file_dialog.select_folder"))
        if not folder:
            return

        if not self.main_window or not self.main_window.current_config:
            QMessageBox.warning(self, _tr("dialog.info"), _tr("mod_preset.error.no_config"))
            return

        d3dx_path, _ = self.get_current_game_paths()
        if not d3dx_path or not os.path.exists(d3dx_path):
            reply = QMessageBox.question(
                self,
                _tr("dialog.info"),
                _tr("mod_preset.ask_continue_no_d3dx"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if reply != QMessageBox.StandardButton.Yes:
                return

        self.run_worker(d3dx_path, folder)