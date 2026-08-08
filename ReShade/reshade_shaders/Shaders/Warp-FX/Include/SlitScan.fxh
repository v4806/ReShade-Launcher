#include "Include/RadegastShaders.BlendingModes.fxh"

uniform float x_col <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "位置";
    ui_tooltip = "开始扫描的屏幕位置。（启用动画时无效。）";
    ui_category = "属性";
    ui_max = 1.0;
    ui_min = 0.0;
> = 0.5;

uniform float scan_speed <
 #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label="扫描速度";
    ui_tooltip=
        "调整扫描速率。较低的值意味着较慢的扫描，可以获得更好的图像质量，但扫描速度会降低。";
    ui_category = "属性";
    ui_max = 3.0;
    ui_min = 0.0;
> = 1.0;

uniform int direction <
    ui_type = "combo";
    ui_label = "扫描方向";
    ui_items = "左\0右\0上\0下\0";
    ui_tooltip = "将扫描方向更改为指定的方向。";
    ui_category = "属性";
> = 0;

uniform int animate <
    ui_type = "combo";
    ui_label = "动画";
    ui_items = "否\0是\0";
    ui_tooltip = "启用扫描列动画，使其从一端移动到另一端。";
    ui_category = "属性";
> = 0;

uniform float frame_rate <
    source = "framecount";
>;

uniform float2 anim_rate <
    source = "pingpong";
    min = 0.0;
    max = 1.0;
    step = 0.001;
    smoothing = 0.0;
>;

uniform float min_depth <
    ui_type = "slider";
    ui_label="最小深度";
    ui_tooltip="取消遮罩设定深度之前的所有内容。";
    ui_category="深度";
    ui_min=0.0;
    ui_max=1.0;
> = 0;