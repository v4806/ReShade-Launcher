uniform float radius <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label="半径";
    ui_category="范围";
    ui_tooltip="控制扭曲的大小。";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;

uniform float tension <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "张力";
    ui_category="范围";
    ui_tooltip="控制效果达到最大扭曲的速度。";
    ui_min = 0.; ui_max = 10.; ui_step = 0.001;
> = 1.0;
