#include "Include/RadegastShaders.Transforms.fxh"
#include "Include/RadegastShaders.Positional.fxh"

#define PI 3.141592358

uniform float2 offset <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "偏移";
    ui_tooltip = "将显示中心水平/垂直偏移一定量。";
    ui_category = "属性";
    ui_min = -.5;
    ui_max = .5;
> = 0;

uniform float scale <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "缩放";
    ui_tooltip = "确定显示在投影球体上的 Z 位置。如果星球太小或太大，可以使用此选项来放大或缩小。";
    ui_category = "属性";
    ui_min = 0.0;
    ui_max = 10.0;
> = 10.0;

uniform float z_rotation <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "Z轴旋转";
    ui_tooltip = "沿 Z 轴旋转显示。这可以帮助您按照想要的方式定位显示中的角色或特征。";
    ui_category = "属性";
    ui_min = 0.0;
    ui_max = 360.0;
> = 0.5;

uniform float seam_scale <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_min = 0.5;
    ui_max = 1.0;
    ui_label = "接缝混合";
    ui_tooltip = "混合屏幕两端，使接缝在一定程度上得到隐藏。";
    ui_category = "属性";
> = 0.5;
