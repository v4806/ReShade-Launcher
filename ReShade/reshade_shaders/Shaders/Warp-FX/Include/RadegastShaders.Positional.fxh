uniform bool use_mouse_point <
    ui_label="使用鼠标坐标";
    ui_category="坐标";
> = false;

uniform float x_coord <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label="X";
    ui_category="坐标";
    ui_tooltip="效果中心的 X 位置。";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;

uniform float y_coord <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label="Y";
    ui_category="坐标";
    ui_tooltip="效果中心的 Y 位置。";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;

uniform float2 mouse_coordinates <
source= "mousepoint";
>;
