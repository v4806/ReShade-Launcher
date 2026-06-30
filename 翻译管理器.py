# -*- coding: utf-8 -*-
"""
翻译管理器 - 单例模式，支持多语言
功能：
  - 自动检测 Windows 系统显示语言并加载对应翻译
  - 加载 translations.json（支持打包环境）
  - 预留 10 种以上语言扩展能力
  - 提供全局翻译函数 _tr()
"""
import json
import os
import sys
import locale
import ctypes

class TranslationManager:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self._initialized = True
        self.translations = {}
        self.current_lang = 'zh_CN'          # 临时默认值，加载翻译文件后会根据系统语言重新设置
        self._load_translations()
        self._auto_set_language()

    def _load_translations(self):
        """加载 translations.json 文件（支持打包环境）"""
        possible_paths = []

        # 当前工作目录
        possible_paths.append('translations.json')

        # 应用程序根目录（exe所在目录）
        if getattr(sys, 'frozen', False):
            app_root = os.path.dirname(sys.executable)
            possible_paths.append(os.path.join(app_root, 'translations.json'))
        else:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            possible_paths.append(os.path.join(script_dir, 'translations.json'))

        # PyInstaller 临时目录
        if hasattr(sys, '_MEIPASS'):
            possible_paths.append(os.path.join(sys._MEIPASS, 'translations.json'))

        for path in possible_paths:
            if os.path.exists(path):
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        self.translations = json.load(f)
                    print(f"[翻译管理器] 已加载翻译文件: {path}")
                    return
                except Exception as e:
                    print(f"[翻译管理器] 加载翻译文件失败 {path}: {e}")

        print("[翻译管理器] 警告: 未找到 translations.json，将使用空翻译")
        self.translations = {}

    def _detect_system_language(self) -> str:
        """
        检测 Windows 系统显示语言，返回语言代码（如 'zh_CN', 'en_US'）
        若检测失败或语言不存在，返回 None，由调用者处理回退
        """
        # 优先使用 Windows API 获取用户界面语言
        if sys.platform == 'win32':
            try:
                windll = ctypes.windll.kernel32
                lcid = windll.GetUserDefaultUILanguage()
                # LCID 到语言代码的映射（仅包含 translations.json 中可能存在的语言）
                lcid_map = {
                    # 简体中文
                    0x0804: 'zh_CN',
                    # 繁体中文（映射到 zh_TW）
                    0x0404: 'zh_TW',      # 中文(台湾)
                    0x0C04: 'zh_TW',      # 中文(香港)
                    0x1404: 'zh_TW',      # 中文(澳门)
                    # 英语
                    0x0409: 'en_US',
                    0x0809: 'en_US',      # 英语(英国)
                    # 日语
                    0x0411: 'ja',         # 日语(日本)
                    # 韩语
                    0x0412: 'ko',         # 韩语(韩国)
                    # 法语
                    0x040C: 'fr',         # 法语(法国)
                    0x080C: 'fr',         # 法语(比利时)
                    0x0C0C: 'fr',         # 法语(加拿大)
                    # 德语
                    0x0407: 'de',         # 德语(德国)
                    0x0807: 'de',         # 德语(瑞士)
                    # 西班牙语
                    0x040A: 'es',         # 西班牙语(西班牙)
                    0x080A: 'es',         # 西班牙语(墨西哥)
                    # 葡萄牙语
                    0x0416: 'pt',         # 葡萄牙语(巴西)
                    0x0816: 'pt',         # 葡萄牙语(葡萄牙)
                    # 俄语
                    0x0419: 'ru',         # 俄语(俄罗斯)
                }
                lang_code = lcid_map.get(lcid)
                if lang_code:
                    print(f"[翻译管理器] 系统语言 LCID: {hex(lcid)} -> {lang_code}")
                    return lang_code
            except Exception as e:
                print(f"[翻译管理器] 通过 Windows API 检测语言失败: {e}")

        # 备选方案：使用 locale 模块
        try:
            lang, _ = locale.getdefaultlocale()
            if lang:
                # 统一格式：将 '-' 替换为 '_'，如 zh-CN -> zh_CN
                lang_code = lang.replace('-', '_')
                print(f"[翻译管理器] locale 检测语言: {lang_code}")
                return lang_code
        except Exception as e:
            print(f"[翻译管理器] 通过 locale 检测语言失败: {e}")

        # 默认返回 None，由上层决定回退语言
        return None

    def _auto_set_language(self):
        """自动设置当前语言为系统语言，若不存在则回退"""
        detected = self._detect_system_language()   # 返回类似 'fr_FR' 或 'zh_CN'
        if detected:
            # 1. 尝试完整匹配（例如 'zh_TW'）
            if detected in self.translations:
                self.current_lang = detected
                print(f"[翻译管理器] 已自动设置为系统语言: {detected}")
                return

            # 2. 尝试基本语言部分（例如 'fr'）
            base_lang = detected.split('_')[0]
            if base_lang in self.translations:
                self.current_lang = base_lang
                print(f"[翻译管理器] 已自动设置为基本语言: {base_lang}")
                return

            # 3. 原有回退逻辑（针对中文和英文）
            if detected.startswith('zh_') and 'zh_CN' in self.translations:
                self.current_lang = 'zh_CN'
                print(f"[翻译管理器] 系统语言 {detected} 无对应翻译，回退至简体中文")
                return
            if detected.startswith('en_') and 'en_US' in self.translations:
                self.current_lang = 'en_US'
                print(f"[翻译管理器] 系统语言 {detected} 无对应翻译，回退至英语")
                return

        # 4. 最终默认：简体中文
        self.current_lang = 'zh_CN'
        print("[翻译管理器] 使用默认语言: 简体中文")

    def set_language(self, lang_code: str) -> bool:
        """手动切换当前语言，预留多语言接口"""
        if lang_code in self.translations:
            self.current_lang = lang_code
            print(f"[翻译管理器] 手动切换语言为: {lang_code}")
            return True
        print(f"[翻译管理器] 语言代码 {lang_code} 不存在")
        return False

    def get(self, key: str, default: str = None, **kwargs) -> str:
        """
        获取当前语言的翻译文本
        :param key:     翻译键
        :param default: 缺省文本
        :param kwargs:  格式化参数
        :return:        翻译后的字符串
        """
        lang_dict = self.translations.get(self.current_lang, {})
        text = lang_dict.get(key)

        # 当前语言无此键 → 尝试 fallback 到中文
        if text is None:
            fallback = self.translations.get('zh_CN', {}).get(key)
            text = fallback if fallback is not None else (default if default else key)

        # 格式化
        if kwargs and text:
            try:
                text = text.format(**kwargs)
            except:
                pass
        return text

# 全局便捷函数
_tr = TranslationManager().get