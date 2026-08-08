#include "Blending.fxh"

BLENDING_COMBO(
    render_type,
    "混合模式",
    "将效果与之前的图层进行混合。",
    "混合",
    false,
    0,
    0
);

uniform float blending_amount <
    ui_type = "slider";
    ui_label = "不透明度";
    ui_category = "混合";
    ui_tooltip = "调整混合数量。";
    ui_min = 0.0;
    ui_max = 1.0;
> = 1.0;