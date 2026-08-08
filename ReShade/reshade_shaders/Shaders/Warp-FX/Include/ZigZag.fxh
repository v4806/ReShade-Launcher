#include "Include/RadegastShaders.Depth.fxh"
#include "Include/RadegastShaders.Positional.fxh"
#include "Include/RadegastShaders.Radial.fxh"
#include "Include/RadegastShaders.AspectRatio.fxh"
#include "Include/RadegastShaders.Offsets.fxh"
#include "Include/RadegastShaders.Transforms.fxh"
#include "Include/RadegastShaders.BlendingModes.fxh"

uniform int mode <
    ui_type = "combo";
    ui_label = "模式";
    ui_items = "围绕中心\0从中心向外\0";
    ui_tooltip = "选择扭曲应通过的处理模式。";
    ui_category = "属性";
> = 0;

uniform float angle <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "角度";
    ui_tooltip = "作为相位和振幅的乘数。根据值是负还是正，也会影响基于相位的动画运动。";
    ui_category = "属性";
    ui_min = -999.0;
    ui_max = 999.0;
    ui_step = 1.0;
> = 180.0;

uniform float period <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_type = "相位";
    ui_label = "周期";
    ui_tooltip = "调整扭曲的速率。";
    ui_category = "属性";
    ui_min = 0.1;
    ui_max = 10.0;
> = 0.25;

uniform float amplitude <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "振幅";
    ui_tooltip = "增加图像来回扭曲的程度。";
    ui_category = "属性";
    ui_min = -10.0;
    ui_max = 10.0;
> = 1.0;

uniform float phase <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "相位";
    ui_tooltip = "像素从中心来回扭曲的偏移量。";
    ui_category = "属性";
    ui_min = -5.0;
    ui_max = 5.0;
> = 0.0;

uniform int animate <
    ui_type = "combo";
    ui_label = "动画";
    ui_items = "否\0振幅\0相位\0";
    ui_tooltip = "启用或禁用动画。通过相位或振幅来动画化锯齿效果。";
    ui_category = "属性";
> = 0;

uniform float anim_rate <
    source = "timer";
>;
