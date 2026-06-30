# 文件名：缩放管理器.py
# 优化的自适应缩放模块
# -*- coding: utf-8 -*-
"""
优化的自适应缩放管理器模块
支持从720p到8K的各种常见分辨率，提供更精确的缩放系数
添加最终调整系数，可全局调整界面尺寸
"""

import sys
from PyQt6.QtWidgets import QApplication
from PyQt6.QtGui import QGuiApplication


class ScalingManager:
    """优化的自适应缩放管理器"""
    
    def __init__(self, final_adjust_scale=1.0):
        # 基准分辨率：1280×720，缩放系数1.0
        # 缩放系数与分辨率成正比（分辨率越高，系数越大）
        self.resolution_scales = {
            # 低分辨率（笔记本/平板）
            '720p': 1,          # 1280x720
            '768p': 1,          # 1366x768
            '900p': 1,          # 1600x900

            # 全高清系列
            '1080p': 1,         # 1920x1080
            '1200p': 1,         # 1920x1200（宽度同1080p）

            # 2K系列
            '2K': 1.2,             # 2560x1440（基准）
            '2K_UltraWide': 1.61,   # 3440x1440（3440/2560*1.2 = 1.6125 ≈ 1.61）
            '2K_Plus': 1.50,        # 3200x1800（3200/2560*1.2 = 1.5）
            
            # 4K系列
            '4K_UHD': 1.80,         # 3840x2160（3840/2560*1.2 = 1.8）
            '4K_DCI': 1.92,         # 4096x2160（4096/2560*1.2 = 1.92）
            '4K_UltraWide': 2.40,   # 5120x2160（5120/2560*1.2 = 2.4）
            
            # 5K+高分辨率
            '5K': 2.40,             # 5120x2880（与4K UltraWide宽度相同，系数一致）
            '6K': 2.82,             # 6016x3384（6016/2560*1.2 = 2.82）
            '8K': 3.60,             # 7680x4320（7680/2560*1.2 = 3.6）
        }
        
        # 备份默认缩放系数（用于未知分辨率）
        self.default_scales = {
            'low': 1.0,        # 低分辨率默认
            'medium': 2.0,     # 中等分辨率默认  
            'high': 3.0,       # 高分辨率默认
            'ultra': 4.0       # 超高分辨率默认
        }
        
        self.base_scale_factor = 1.0  # 基础缩放系数（根据分辨率计算得出）
        self.final_adjust_scale = final_adjust_scale  # 最终调整系数（可配置）
        self.scale_factor = 1.0  # 最终缩放系数 = base_scale_factor * final_adjust_scale
        self.detected_resolution = "Unknown"  # 检测到的分辨率信息
        
        # 初始化检测
        self._perform_initial_detection()
    
    def _perform_initial_detection(self):
        """执行初始检测"""
        try:
            # 检测屏幕分辨率级别
            resolution_level, resolution_info = self._detect_resolution_level()
            self.detected_resolution = resolution_info
            
            # 获取对应的缩放系数
            if resolution_level in self.resolution_scales:
                self.base_scale_factor = self.resolution_scales[resolution_level]
            else:
                # 使用基于分辨率的默认系数
                self.base_scale_factor = self._get_fallback_scale(resolution_info['width'])
            
            # 计算最终缩放系数
            self.scale_factor = self.base_scale_factor * self.final_adjust_scale
            
            print(f"分辨率缩放检测: 级别={resolution_level}, 分辨率={resolution_info}")
            print(f"基础缩放系数={self.base_scale_factor:.2f}, 最终调整系数={self.final_adjust_scale:.2f}, 最终缩放系数={self.scale_factor:.2f}")
            
        except Exception as e:
            print(f"分辨率缩放检测失败: {e}, 使用默认缩放系数1.0")
            self.base_scale_factor = 1.0
            self.scale_factor = 1.0 * self.final_adjust_scale
            self.detected_resolution = {"width": 1280, "height": 720, "ratio": "16:9"}
    
    def set_final_adjust_scale(self, adjust_scale):
        """设置最终调整系数，用于全局调整界面尺寸"""
        self.final_adjust_scale = adjust_scale
        # 重新计算最终缩放系数
        self.scale_factor = self.base_scale_factor * self.final_adjust_scale
        print(f"调整最终缩放系数: 基础={self.base_scale_factor:.2f}, 调整系数={self.final_adjust_scale:.2f}, 最终={self.scale_factor:.2f}")
    
    def _detect_resolution_level(self):
        """检测屏幕分辨率级别和详细信息（PyQt6 适配）"""
        try:
            app = QGuiApplication.instance()
            if app is None:
                return '720p', {"width": 1280, "height": 720, "ratio": "16:9"}

            screens = app.screens()
            if not screens:
                return '720p', {"width": 1280, "height": 720, "ratio": "16:9"}

            # 获取主屏幕（第一个屏幕）的分辨率
            screen_rect = screens[0].geometry()
            if screen_rect is None:
                return '720p', {"width": 1280, "height": 720, "ratio": "16:9"}
            
            physical_width = screen_rect.width()
            physical_height = screen_rect.height()
            aspect_ratio = self._calculate_aspect_ratio(physical_width, physical_height)
            
            resolution_info = {
                "width": physical_width,
                "height": physical_height, 
                "ratio": aspect_ratio
            }
            
            # 根据分辨率确定级别（基于宽度和宽高比）
            resolution_level = self._classify_resolution(physical_width, physical_height, aspect_ratio)
            
            return resolution_level, resolution_info
                
        except Exception as e:
            print(f"分辨率级别检测失败: {e}")
            return '720p', {"width": 1280, "height": 720, "ratio": "16:9"}
    
    def _calculate_aspect_ratio(self, width, height):
        """计算屏幕宽高比"""
        def gcd(a, b):
            while b:
                a, b = b, a % b
            return a
        
        divisor = gcd(width, height)
        width_ratio = width // divisor
        height_ratio = height // divisor
        
        # 常见宽高比映射
        common_ratios = {
            (16, 9): "16:9",
            (16, 10): "16:10", 
            (21, 9): "21:9",
            (32, 9): "32:9",
            (4, 3): "4:3",
            (5, 4): "5:4",
            (3, 2): "3:2"
        }
        
        return common_ratios.get((width_ratio, height_ratio), f"{width_ratio}:{height_ratio}")
    
    def _classify_resolution(self, width, height, ratio):
        """根据分辨率参数分类分辨率级别"""
        
        # 基于宽度的主要分类
        if width <= 1366:
            if width == 1280 and height == 720:
                return '720p'
            return '768p'
        
        elif width <= 1600:
            return '900p'
        
        elif width <= 1920:
            if height == 1200:
                return '1200p'
            return '1080p'
        
        elif width <= 2560:
            return '2K'
        
        elif width <= 3440:
            if ratio in ["21:9", "32:9"]:
                return '2K_UltraWide'
            return '2K_Plus'
        
        elif width <= 4096:
            if width == 3840:
                return '4K_UHD'
            return '4K_DCI'
        
        elif width <= 5120:
            if ratio in ["21:9", "32:9"]:
                return '4K_UltraWide'
            return '5K'
        
        elif width <= 6016:
            return '6K'
        
        else:
            return '8K'
    
    def _get_fallback_scale(self, width):
        """获取基于分辨率的备用缩放系数"""
        # 基于1280×720基准的线性比例计算
        base_width = 1280
        return width / base_width
    
    def get_scale_factor(self):
        """获取最终缩放系数"""
        return self.scale_factor
    
    def get_base_scale_factor(self):
        """获取基础缩放系数（不含最终调整）"""
        return self.base_scale_factor
    
    def get_final_adjust_scale(self):
        """获取最终调整系数"""
        return self.final_adjust_scale
    
    def get_detected_resolution(self):
        """获取检测到的分辨率信息"""
        return self.detected_resolution
    
    def scale_value(self, value):
        """缩放单个值"""
        return int(value * self.scale_factor)
    
    def scale_rect(self, x, y, width, height):
        """缩放矩形区域"""
        return (
            int(x * self.scale_factor),
            int(y * self.scale_factor),
            int(width * self.scale_factor),
            int(height * self.scale_factor)
        )
    
    def get_available_resolutions(self):
        """获取支持的所有分辨率级别（用于调试或UI显示）"""
        return list(self.resolution_scales.keys())


# 单例模式
_scaling_instance = None

def get_scaling_manager(final_adjust_scale=1):
    """获取缩放管理器单例
    
    Args:
        final_adjust_scale: 最终调整系数，用于全局调整界面尺寸
    """
    global _scaling_instance
    
    if _scaling_instance is None:
        _scaling_instance = ScalingManager(final_adjust_scale)
    else:
        # 如果实例已存在，但需要调整系数，可以调用设置方法
        _scaling_instance.set_final_adjust_scale(final_adjust_scale)
    
    return _scaling_instance