# -*- coding: utf-8 -*-
"""
自定义控件模块 - 包含自定义的控件类
（PyQt6 适配 + 完整缩放支持 + 国际化）
"""

from PyQt6.QtCore import Qt, QPoint, QSize, pyqtSignal
from PyQt6.QtGui import (QColor, QPixmap, QPainter, QPen, QPainterPath,
                         QTextLayout, QTextOption, QIcon, QFont, QBrush,
                         QPalette)
from PyQt6.QtWidgets import (QWidget, QLabel, QPushButton, QHBoxLayout,
                             QVBoxLayout, QSizePolicy, QListWidgetItem,
                             QToolButton)

from 翻译管理器 import _tr

# ----------------------------------------------------------------------
# 描边标签（原有，保留完整）
# ----------------------------------------------------------------------
class StrokeLabel_4(QLabel):
    """自定义标签控件 4 - 支持描边效果"""
    def __init__(self, text='', parent=None):
        super().__init__(text, parent)
        self.stroke_width = 0
        self.stroke_color = '#000000'
        self.properties = {}
        self.actual_font_size = 12

    def set_stroke_properties(self, stroke_width, stroke_color):
        self.stroke_width = stroke_width
        self.stroke_color = stroke_color
        self.update()

    def paintEvent(self, event):
        if self.stroke_width > 0:
            self.paint_with_stroke()
        else:
            super().paintEvent(event)

    def paint_with_stroke(self):
        try:
            painter = QPainter(self)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)

            font = self.font()
            painter.setFont(font)

            text = self.text()
            if not text:
                return

            alignment = self.alignment()
            padding = self.properties.get('padding', 5)
            content_rect = self.contentsRect()
            text_rect = content_rect.adjusted(padding, padding, -padding, -padding)
            if text_rect.width() <= 0 or text_rect.height() <= 0:
                text_rect = content_rect.adjusted(5, 5, -5, -5)

            path = QPainterPath()
            metrics = self.fontMetrics()
            line_spacing = metrics.lineSpacing()
            word_wrap = self.properties.get('word_wrap', True)

            if word_wrap:
                text_option = QTextOption()
                text_option.setWrapMode(QTextOption.WrapMode.WordWrap)
                text_option.setAlignment(alignment)
                text_layout = QTextLayout(text, font)
                text_layout.setTextOption(text_option)
                text_layout.beginLayout()
                lines = []
                while True:
                    line = text_layout.createLine()
                    if not line.isValid():
                        break
                    line.setLineWidth(text_rect.width())
                    lines.append(line)
                text_layout.endLayout()
                total_height = len(lines) * line_spacing
                if alignment & Qt.AlignmentFlag.AlignTop:
                    start_y = text_rect.top() + metrics.ascent()
                elif alignment & Qt.AlignmentFlag.AlignBottom:
                    start_y = text_rect.bottom() - total_height + metrics.ascent()
                else:
                    start_y = text_rect.top() + (text_rect.height() - total_height) / 2 + metrics.ascent()
                for i, line in enumerate(lines):
                    line_text = text[line.textStart():line.textStart() + line.textLength()]
                    if not line_text.strip():
                        continue
                    line_width = metrics.horizontalAdvance(line_text)
                    if alignment & Qt.AlignmentFlag.AlignLeft:
                        x = text_rect.left()
                    elif alignment & Qt.AlignmentFlag.AlignRight:
                        x = text_rect.right() - line_width
                    else:
                        x = text_rect.left() + (text_rect.width() - line_width) / 2
                    y = start_y + i * line_spacing
                    path.addText(x, y, font, line_text)
            else:
                lines = text.split('\n')
                total_height = len(lines) * line_spacing
                if alignment & Qt.AlignmentFlag.AlignTop:
                    start_y = text_rect.top() + metrics.ascent()
                elif alignment & Qt.AlignmentFlag.AlignBottom:
                    start_y = text_rect.bottom() - total_height + metrics.ascent()
                else:
                    start_y = text_rect.top() + (text_rect.height() - total_height) / 2 + metrics.ascent()
                for i, line in enumerate(lines):
                    if not line.strip():
                        continue
                    line_width = metrics.horizontalAdvance(line)
                    if alignment & Qt.AlignmentFlag.AlignLeft:
                        x = text_rect.left()
                    elif alignment & Qt.AlignmentFlag.AlignRight:
                        x = text_rect.right() - line_width
                    else:
                        x = text_rect.left() + (text_rect.width() - line_width) / 2
                    y = start_y + i * line_spacing
                    path.addText(x, y, font, line)

            if self.stroke_width > 0:
                pen = QPen(QColor(self.stroke_color))
                pen.setWidthF(self.stroke_width * 2)
                pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
                pen.setCapStyle(Qt.PenCapStyle.RoundCap)
                painter.setPen(pen)
                painter.setBrush(Qt.BrushStyle.NoBrush)
                painter.drawPath(path)

            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(QColor(self.palette().color(self.foregroundRole())))
            painter.drawPath(path)

        except Exception as e:
            print(f"描边绘制失败: {e}")
            super().paintEvent(None)

    def set_properties(self, props):
        self.properties = props
        stroke_width = props.get('stroke_width', 0)
        stroke_color = props.get('stroke_color', '#000000')
        self.set_stroke_properties(stroke_width, stroke_color)
        self.apply_style(props)
        opacity = props.get('opacity', 1.0)
        if opacity < 1.0:
            self.setWindowOpacity(opacity)

    def apply_style(self, props):
        try:
            bg_color = props.get('background_color', '#2D2D30')
            text_color = props.get('text_color', '#FFFFFF')
            font_size = max(1, props.get('font_size', 12))
            font_family = props.get('font_family', 'Microsoft YaHei')
            font_bold = props.get('font_bold', False)
            font_italic = props.get('font_italic', False)
            border_radius = max(1, props.get('border_radius', 5))
            border_width = props.get('border_width', 1)
            border_color = props.get('border_color', '#555555')
            border_style = props.get('border_style', 'solid')
            padding = max(1, props.get('padding', 5))

            font = QFont(font_family, font_size)
            font.setBold(font_bold)
            font.setItalic(font_italic)
            self.setFont(font)

            border_style_map = {
                'solid': 'solid',
                'dashed': 'dashed',
                'dotted': 'dotted',
                'double': 'double',
                'none': 'none'
            }
            actual_border_style = border_style_map.get(border_style, 'solid')
            if border_width > 0 and actual_border_style != 'none':
                border_style_css = f"border: {border_width}px {actual_border_style} {border_color};"
            else:
                border_style_css = "border: none;"

            stylesheet = f"""
            StrokeLabel{{
                background-color: {bg_color};
                color: {text_color};
                border-radius: {border_radius}px;
                {border_style_css}
                padding: {padding}px;
            }}
            """
            self.setStyleSheet(stylesheet)
        except Exception as e:
            print(f"应用标签样式失败: {e}")


# ----------------------------------------------------------------------
# 描边按钮（新）
# ----------------------------------------------------------------------
class StrokePushButton(QPushButton):
    """带描边文本的 QPushButton"""
    def __init__(self, text='', parent=None, stroke_width=2, stroke_color='#000000'):
        super().__init__(text, parent)
        self.stroke_width = stroke_width
        self.stroke_color = stroke_color

    def set_stroke_properties(self, stroke_width, stroke_color):
        self.stroke_width = stroke_width
        self.stroke_color = stroke_color
        self.update()

    def paintEvent(self, event):
        super().paintEvent(event)
        text = self.text()
        if not text:
            return
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)
        font = self.font()
        painter.setFont(font)
        text_color = self.palette().color(self.foregroundRole())
        if not text_color.isValid():
            text_color = QColor(255, 255, 255)
        rect = self.rect()
        path = QPainterPath()
        path.addText(rect.center().x() - self.fontMetrics().horizontalAdvance(text) / 2,
                     rect.center().y() + self.fontMetrics().ascent() / 2,
                     font, text)
        if self.stroke_width > 0:
            pen = QPen(QColor(self.stroke_color))
            pen.setWidthF(self.stroke_width * 2)
            pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
            pen.setCapStyle(Qt.PenCapStyle.RoundCap)
            painter.setPen(pen)
            painter.setBrush(Qt.BrushStyle.NoBrush)
            painter.drawPath(path)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(text_color)
        painter.drawPath(path)


class StrokeToolButton(QToolButton):
    """带描边文本的 QToolButton（文本非空时生效）"""
    def __init__(self, parent=None, stroke_width=2, stroke_color='#000000'):
        super().__init__(parent)
        self.stroke_width = stroke_width
        self.stroke_color = stroke_color

    def set_stroke_properties(self, stroke_width, stroke_color):
        self.stroke_width = stroke_width
        self.stroke_color = stroke_color
        self.update()

    def paintEvent(self, event):
        super().paintEvent(event)
        text = self.text()
        if not text:
            return
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)
        font = self.font()
        painter.setFont(font)
        text_color = self.palette().color(self.foregroundRole())
        if not text_color.isValid():
            text_color = QColor(255, 255, 255)
        rect = self.rect()
        path = QPainterPath()
        path.addText(rect.center().x() - self.fontMetrics().horizontalAdvance(text) / 2,
                     rect.center().y() + self.fontMetrics().ascent() / 2,
                     font, text)
        if self.stroke_width > 0:
            pen = QPen(QColor(self.stroke_color))
            pen.setWidthF(self.stroke_width * 2)
            pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
            pen.setCapStyle(Qt.PenCapStyle.RoundCap)
            painter.setPen(pen)
            painter.setBrush(Qt.BrushStyle.NoBrush)
            painter.drawPath(path)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(text_color)
        painter.drawPath(path)


# ----------------------------------------------------------------------
# 自定义配置菜单项（国际化）
# ----------------------------------------------------------------------
class ConfigMenuItem(QWidget):
    """自定义配置菜单项 - 添加鼠标悬停效果，支持缩放系数"""
    edit_requested = pyqtSignal(str)
    shortcut_requested = pyqtSignal(str)

    def __init__(self, config_name, icon, display_name, scale_factor=1.0, parent=None):
        super().__init__(parent)
        self.config_name = config_name
        self.display_name = display_name
        self.scale_factor = scale_factor
        self.is_hovered = False

        self.setMouseTracking(True)
        self.setup_ui(icon)

    def setup_ui(self, icon):
        sf = self.scale_factor
        layout = QHBoxLayout(self)
        layout.setContentsMargins(
            max(1, int(15 * sf)),
            max(1, int(10 * sf)),
            max(1, int(15 * sf)),
            max(1, int(10 * sf))
        )
        layout.setSpacing(max(1, int(20 * sf)))

        self.setStyleSheet("QWidget { background-color: transparent; border-radius: 8px; }")

        icon_size = max(16, int(48 * 1.5 * sf))
        self.icon_label = QLabel()
        self.icon_label.setFixedSize(icon_size, icon_size)
        self.icon_label.setScaledContents(True)
        pixmap = icon.pixmap(icon_size, icon_size)
        if not pixmap.isNull():
            self.icon_label.setPixmap(pixmap)
        layout.addWidget(self.icon_label)

        font_size = max(1, int(16 * 1.5 * sf))
        self.name_label = QLabel(self.display_name)
        self.name_label.setStyleSheet(f"""
            QLabel {{
                color: #FFFFFF;
                padding: {max(1, int(5 * sf))}px;
                background-color: transparent;
            }}
        """)
        font = QFont("Microsoft YaHei", font_size)
        font.setWeight(QFont.Weight(500))
        self.name_label.setFont(font)
        self.name_label.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        layout.addWidget(self.name_label)

        self.edit_btn = QPushButton(_tr("menu.edit"))
        self.edit_btn.setFixedSize(
            max(40, int(60 * sf * 1.8)),
            max(20, int(35 * sf * 1.8))
        )
        self.edit_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.6);
                color: #FFFFFF;
                font-weight: bold;
                border-radius: {max(1, int(5 * sf))}px;
                border: 2px solid #555555;
                padding: {max(1, int(5 * sf))}px {max(1, int(10 * sf))}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.8);
                border: 2px solid #007ACC;
            }}
            QPushButton:pressed {{
                background-color: rgba(0, 63, 107, 0.8);
            }}
        """)
        btn_font = QFont("Microsoft YaHei", max(1, int(14 * sf * 2)))
        btn_font.setBold(True)
        self.edit_btn.setFont(btn_font)
        self.edit_btn.setToolTip(_tr("menu.edit.tooltip", name=self.display_name))
        self.edit_btn.clicked.connect(self.on_edit_clicked)
        layout.addWidget(self.edit_btn)

        # 创建桌面快捷方式按钮
        self.shortcut_btn = QPushButton(_tr("menu.shortcut"))
        self.shortcut_btn.setFixedSize(max(40, int(60 * sf * 1.8)), max(20, int(35 * sf * 1.8)))
        btn_ss = (
            "QPushButton {"
            "background-color: rgba(85, 85, 127, 0.6);"
            "color: #FFFFFF; font-weight: bold;"
            "border-radius: %dpx; border: 2px solid #555555;"
            "padding: %dpx %dpx;"
            "}"
            "QPushButton:hover {"
            "background-color: rgba(0, 158, 90, 0.8);"
            "border: 2px solid #00CC55;"
            "}"
            "QPushButton:pressed {"
            "background-color: rgba(0, 107, 63, 0.8);"
            "}"
        ) % (max(1, int(5 * sf)), max(1, int(5 * sf)), max(1, int(10 * sf)))
        self.shortcut_btn.setStyleSheet(btn_ss)
        self.shortcut_btn.setFont(btn_font)
        self.shortcut_btn.setToolTip(_tr("menu.shortcut.tooltip", name=self.display_name))
        self.shortcut_btn.clicked.connect(self.on_shortcut_clicked)
        layout.addWidget(self.shortcut_btn)

        # 创建桌面快捷方式按钮 self.setMinimumHeight(max(40, int(80 * sf)))

    def enterEvent(self, event):
        self.is_hovered = True
        sf = self.scale_factor
        self.setStyleSheet(f"""
            QWidget {{
                background-color: rgba(58, 58, 62, 0.8);
                border-radius: {max(1, int(8 * sf))}px;
                border: 1px solid #555577;
            }}
        """)
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.is_hovered = False
        sf = self.scale_factor
        self.setStyleSheet(f"""
            QWidget {{
                background-color: transparent;
                border-radius: {max(1, int(8 * sf))}px;
            }}
        """)
        super().leaveEvent(event)

    def on_edit_clicked(self):
        self.edit_requested.emit(self.config_name)

    def on_shortcut_clicked(self):
        self.shortcut_requested.emit(self.config_name)

    def update_display_name(self, new_name):
        self.display_name = new_name
        self.name_label.setText(new_name)

    def update_icon(self, icon):
        sf = self.scale_factor
        icon_size = max(16, int(48 * 1.5 * sf))
        pixmap = icon.pixmap(icon_size, icon_size)
        if not pixmap.isNull():
            scaled_pixmap = pixmap.scaled(
                self.icon_label.size(),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation
            )
            self.icon_label.setPixmap(scaled_pixmap)