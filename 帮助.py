# -*- coding: utf-8 -*-
"""
帮助模块 - 显示软件功能使用教程
（适配缩放管理器 + 国际化 + 背景图片与描边 + 深色遮罩，继承自对话框模块的StyledDialog以支持GIF背景）
"""
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QLabel,
                             QPushButton, QTabWidget, QTextEdit, QWidget)
import os
import sys

from 翻译管理器 import _tr
from 自定义控件模块 import StrokeLabel_4, StrokePushButton
from 对话框模块 import StyledDialog   # 导入已实现背景和GIF的基类


class HelpDialog(StyledDialog):
    """帮助对话框，以标签页形式展示各功能说明"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle(_tr("help.title"))
        self.setWindowFlags(Qt.WindowType.Dialog)

        self.resize(int(700 * self.scale_factor), int(500 * self.scale_factor))
        self.setMinimumSize(int(600 * self.scale_factor), int(400 * self.scale_factor))
        self.setup_ui()

    def setup_ui(self):
        sf = self.scale_factor
        layout = QVBoxLayout(self)

        # 标题（描边标签）
        title = StrokeLabel_4(_tr("help.guide_title"), self)
        title_font = QFont("Microsoft YaHei", max(12, int(18 * sf)))
        title_font.setBold(True)
        title.setFont(title_font)
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.set_stroke_properties(int(2 * sf), '#000000')
        title.setStyleSheet("color: #FFFFFF; padding: 10px; background-color: transparent;")
        layout.addWidget(title)

        # 标签页
        tab_widget = QTabWidget()
        tab_widget.setStyleSheet(f"""
            QTabWidget::pane {{
                border: 2px solid #555555;
                border-radius: {int(6 * sf)}px;
                background-color: rgba(45, 45, 48, 0.8);
            }}
            QTabBar::tab {{
                background-color: #3A3A3E;
                color: #FFFFFF;
                border: 1px solid #555555;
                border-radius: {int(4 * sf)}px;
                padding: {int(8 * sf)}px {int(16 * sf)}px;
                margin: {int(2 * sf)}px;
                font-size: {int(14 * sf)}px;
            }}
            QTabBar::tab:selected {{
                background-color: #555577;
                border: 1px solid #82FF55;
            }}
            QTabBar::tab:hover {{
                background-color: #4A4A4E;
            }}
        """)

        tab_widget.addTab(self._create_text_tab(_tr("help.tab.config")), _tr("help.tab.config_title"))
        tab_widget.addTab(self._create_text_tab(_tr("help.tab.launch")), _tr("help.tab.launch_title"))
        tab_widget.addTab(self._create_text_tab(_tr("help.tab.creation")), _tr("help.tab.creation_title"))
        tab_widget.addTab(self._create_text_tab(_tr("help.tab.reshade")), _tr("help.tab.reshade_title"))
        tab_widget.addTab(self._create_text_tab(_tr("help.tab.process")), _tr("help.tab.process_title"))
        tab_widget.addTab(self._create_text_tab(_tr("help.tab.tray")), _tr("help.tab.tray_title"))
        tab_widget.addTab(self._create_text_tab(_tr("help.tab.other")), _tr("help.tab.other_title"))

        layout.addWidget(tab_widget)

        # 关闭按钮（描边按钮）
        btn_layout = QHBoxLayout()
        close_btn = StrokePushButton(_tr("dialog.close"), self)
        close_btn.set_stroke_properties(int(2 * sf), '#000000')
        close_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(85, 85, 127, 0.38);
                color: #FFFFFF;
                border-radius: {int(5 * sf)}px;
                border: 3px solid #bababa;
                padding: {int(8 * sf)}px {int(30 * sf)}px;
                font-size: {int(14 * sf)}px;
            }}
            QPushButton:hover {{
                background-color: rgba(0, 90, 158, 0.38);
            }}
        """)
        close_btn.clicked.connect(self.accept)
        btn_layout.addStretch()
        btn_layout.addWidget(close_btn)
        btn_layout.addStretch()
        layout.addLayout(btn_layout)

        layout.setContentsMargins(int(20 * sf), int(20 * sf), int(20 * sf), int(20 * sf))
        self.setStyleSheet("background-color: transparent;")

    def _create_text_tab(self, html_content):
        """创建只读的 QTextEdit 标签页"""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        text = QTextEdit()
        text.setReadOnly(True)
        text.setStyleSheet("""
            QTextEdit {
                background-color: rgba(0, 0, 0, 0.2);
                color: #E0E0E0;
                border: none;
                font-size: 14px;
            }
        """)
        text.setHtml(html_content)
        layout.addWidget(text)
        return widget