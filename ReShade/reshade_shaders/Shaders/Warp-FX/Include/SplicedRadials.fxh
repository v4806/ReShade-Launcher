#include "Include/Swirl.fxh"

uniform int number_splices <
    #if __RESHADE__ < 40000
        ui_type = "drag";
    #else
        ui_type = "slider";
    #endif
    ui_label = "切片数量";
    ui_tooltip = "设置切片数量。较高的值通过增加切片数量使效果更接近正常模式。";
    ui_category = "属性";
    ui_min = 1;
    ui_max = 50;
> = 10;
