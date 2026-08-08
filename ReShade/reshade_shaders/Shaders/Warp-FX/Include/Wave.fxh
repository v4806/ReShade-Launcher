#include "Include/RadegastShaders.Depth.fxh"
#include "Include/RadegastShaders.BlendingModes.fxh"

uniform int wave_type <
    ui_type = "combo";
    ui_label = "波浪类型";
    ui_tooltip = "选择要应用的扭曲类型。";
    ui_items = "X/X\0X/Y\0";
    ui_tooltip = "扭曲应在哪个轴上执行。";
    ui_category = "属性";
> = 1;

uniform float angle <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "角度";
    ui_tooltip = "发生扭曲的角度。";
    ui_category = "属性";
    ui_min = -360.0;
    ui_max = 360.0;
    ui_step = 1.0;
> = 0.0;

uniform float period <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "周期";
    ui_tooltip = "扭曲的波长。较小的值产生较长的波长。";
    ui_category = "属性";
    ui_min = 0.1;
    ui_max = 10.0;
> = 3.0;

uniform float amplitude <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "振幅";
    ui_tooltip = "每个方向扭曲的振幅。";
    ui_category = "属性";
    ui_min = -1.0;
    ui_max = 1.0;
> = 0.075;

uniform float phase <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "相位";
    ui_min = -5.0;
    ui_max = 5.0;
    ui_tooltip = "应用于扭曲波浪的偏移量。";
> = 0.0;

uniform int animate <
    ui_type = "combo";
    ui_label = "动画";
    ui_items = "否\0振幅\0相位\0角度\0";
    ui_tooltip = "启用或禁用动画。通过相位、振幅或角度来动画化波浪效果。";
    ui_category = "属性";
> = 0;

uniform float anim_rate <
    source = "timer";
>;
