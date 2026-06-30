# -*- coding: utf-8 -*-
"""
数据管理模块 - 自定义数据管理器
（已适配打包环境）
"""

import os
import json


class CustomDataManager:
    """自定义数据管理器"""
    def __init__(self, base_dir: str = None):
        """
        初始化自定义数据管理器
        
        Args:
            base_dir: 应用程序根目录（exe所在目录或脚本所在目录）。
                     如果为 None，则使用当前脚本所在目录。
        """
        if base_dir is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
        
        self.base_dir = base_dir
        self.custom_data_dir = os.path.join(base_dir, "custom_data")
        self.custom_data_file = os.path.join(self.custom_data_dir, "custom_configs.json")
        self.global_settings_file = os.path.join(self.custom_data_dir, "global_settings.json")
        
        # 确保目录存在
        if not os.path.exists(self.custom_data_dir):
            os.makedirs(self.custom_data_dir)
        
        # 加载自定义数据
        self.custom_data = self.load_custom_data()
        
        # 加载全局设置
        self.global_settings = self.load_global_settings()
    
    def load_custom_data(self):
        """加载自定义数据"""
        if os.path.exists(self.custom_data_file):
            try:
                with open(self.custom_data_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"加载自定义数据失败: {e}")
        
        return {}
    
    def save_custom_data(self):
        """保存自定义数据"""
        try:
            with open(self.custom_data_file, 'w', encoding='utf-8') as f:
                json.dump(self.custom_data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存自定义数据失败: {e}")
    
    def load_global_settings(self):
        """加载全局设置"""
        if os.path.exists(self.global_settings_file):
            try:
                with open(self.global_settings_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"加载全局设置失败: {e}")
        
        # 默认全局设置
        defaults = {
            'last_selected_config': None,
            'reshade_enabled': True
        }
        # 首次启动：自动设置 b.jpg 为默认背景（如果存在）
        b_jpg = os.path.join(self.base_dir, 'b.jpg')
        if os.path.exists(b_jpg):
            defaults['background_image'] = b_jpg
        return defaults
    
    def save_global_settings(self):
        """保存全局设置"""
        try:
            with open(self.global_settings_file, 'w', encoding='utf-8') as f:
                json.dump(self.global_settings, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存全局设置失败: {e}")
    
    def get_custom_data(self, config_name):
        """获取配置的自定义数据"""
        return self.custom_data.get(config_name, {})
    
    def save_custom_data_for_config(self, config_name, custom_data):
        """保存配置的自定义数据"""
        self.custom_data[config_name] = custom_data
        self.save_custom_data()
    
    def update_custom_data(self, config_name, key, value):
        """更新配置的自定义数据"""
        if config_name not in self.custom_data:
            self.custom_data[config_name] = {}
        
        self.custom_data[config_name][key] = value
        self.save_custom_data()
    
    def get_last_selected_config(self):
        """获取上次选择的配置"""
        return self.global_settings.get('last_selected_config')
    
    def set_last_selected_config(self, config_name):
        """设置上次选择的配置"""
        self.global_settings['last_selected_config'] = config_name
        self.save_global_settings()
    
    def get_global_setting(self, key, default=None):
        """获取全局设置"""
        return self.global_settings.get(key, default)
    
    def set_global_setting(self, key, value):
        """设置全局设置"""
        self.global_settings[key] = value
        self.save_global_settings()