uniform float2 depth_bounds <
    ui_type = "slider";
    ui_label = "深度范围";
    ui_category = "深度";
    ui_tooltip = "计算效果的深度范围。";
    min = 0.0;
    max = 1.0;
> = float2(0.0, 1.0);

uniform float min_depth <
    ui_type = "slider";
    ui_label="最小深度";
    ui_tooltip="取消遮罩设定深度之前的所有内容。";
    ui_category="深度";
    ui_min=0.0;
    ui_max=1.0;
> = 0;