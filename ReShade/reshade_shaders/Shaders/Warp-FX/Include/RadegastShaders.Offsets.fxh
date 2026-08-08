uniform bool use_offset_coords <
    ui_label = "使用偏移坐标";
    ui_tooltip = "在原始坐标以外的任意位置显示扭曲效果。";
    ui_category = "偏移";
> = 0;

uniform float offset_x <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "X";
    ui_category = "偏移";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;


uniform float offset_y <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "Y";
    ui_category = "偏移";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;
