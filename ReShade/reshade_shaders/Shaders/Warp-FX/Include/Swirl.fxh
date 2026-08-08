#include "Include/RadegastShaders.Depth.fxh"
#include "Include/RadegastShaders.Positional.fxh"
#include "Include/RadegastShaders.Radial.fxh"
#include "Include/RadegastShaders.AspectRatio.fxh"
#include "Include/RadegastShaders.Offsets.fxh"
#include "Include/RadegastShaders.Transforms.fxh"
#include "Include/RadegastShaders.BlendingModes.fxh"

uniform float inner_radius <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "内半径";
    ui_tooltip = "正常模式 -- 设置自动设定最大角度的内半径。\n切片径向模式 -- 定义最内层切片圆的大小。";
    ui_category = "属性";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0;

uniform float angle <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label="角度";
    ui_category = "属性";
    ui_min = -1800.0;
    ui_max = 1800.0;
    ui_step = 1.0;
> = 180.0;

uniform int inverse <
    ui_type = "combo";
    ui_label = "反转角度";
    ui_items = "否\0是\0";
    ui_tooltip = "反转漩涡的角度，使边缘扭曲最大。";
    ui_category = "属性";
> = 0;

uniform int animate <
    ui_type = "combo";
    ui_label = "动画";
    ui_items = "否\0是\0";
    ui_tooltip = "启用漩涡动画，使其顺时针和逆时针移动。";
    ui_category = "属性";
> = 0;

uniform float anim_rate <
    source = "timer";
>;
