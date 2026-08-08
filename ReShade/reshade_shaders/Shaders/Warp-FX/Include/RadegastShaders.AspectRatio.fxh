uniform float aspect_ratio <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label="宽高比";
    ui_category="宽高比";
    ui_min = -100.0;
    ui_max = 100.0;
> = 0;

uniform float aspect_ratio_angle <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label="宽高比角度";
    ui_category="宽高比";
    ui_min = -180.0;
    ui_max = 180.0;
> = 0;