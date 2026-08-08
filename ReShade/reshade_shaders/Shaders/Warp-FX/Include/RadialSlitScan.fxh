#include "Include/RadegastShaders.BlendingModes.fxh"
#include "Include/RadegastShaders.Positional.fxh"

uniform int animate <
    ui_type = "combo";
    ui_label = "动画";
    ui_items = "否\0是\0";
    ui_tooltip = "启用扫描列动画，使其从一端移动到另一端。";
> = 0;

uniform float frame_rate <
    source = "framecount";
>;

uniform float2 anim_rate <
    source = "pingpong";
    min = 0.0;
    max = 1.0;
    step = 0.0001;
    smoothing = 0.0;
>;

uniform float3 border_color <
    ui_type = "color";
    ui_label = "边框颜色";
    ui_category = "颜色设置";
> = float3(1.0, 0.0, 0.0);

uniform float opacity <
    ui_type = "slider";
    ui_label = "不透明度";
    ui_category = "颜色设置";
> = 1.0;

uniform float min_depth <
    ui_type     = "slider";
    ui_label    = "最小深度";
    ui_tooltip  = "取消遮罩设定深度之前的所有内容。";
    ui_category = "深度";
    ui_min=0.0;
    ui_max=1.0;
> = 0;