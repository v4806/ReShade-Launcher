#include "Include/RadegastShaders.Depth.fxh"
#include "Include/RadegastShaders.Positional.fxh"
#include "Include/RadegastShaders.Radial.fxh"
#include "Include/RadegastShaders.AspectRatio.fxh"
#include "Include/RadegastShaders.Offsets.fxh"
#include "Include/RadegastShaders.Transforms.fxh"
#include "Include/RadegastShaders.BlendingModes.fxh"

uniform float magnitude <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "强度";
    ui_min = -1.0;
    ui_max = 1.0;
    ui_tooltip = "扭曲的强度。正值使图像向外凸起，负值使图像向内收缩。";
    ui_category = "属性";
> = -0.5;

uniform int animate <
    ui_type = "combo";
    ui_label = "动画";
    ui_items = "否\0是\0";
    ui_tooltip = "启用效果动画。";
    ui_category = "属性";
> = 0;

uniform float anim_rate <
    source = "timer";
>;
