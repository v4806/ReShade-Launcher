////////////////////////////////////////////////////////////////////////////////////////////////////////
// Droste Effect (Droste.fx) by SirCobra
// Version 0.4.3
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// The Droste effect warps the image-space to recursively appear within itself.
////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "Reshade.fxh"

// Shader Start

// Namespace Everything!

namespace COBRA_DRO
{

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                            Defines & UI
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Defines

    #define COBRA_DRO_VERSION "0.4.3"

    #define COBRA_UTL_MODE 0
    #include ".\CobraUtility.fxh"

    // UI

    uniform int UI_EffectType <
        ui_label     = " 效果类型";
        ui_type      = "radio";
        ui_spacing   = 2;
        ui_items     = "圆形\0矩形\0";
        ui_tooltip   = "递归外观的形状。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0;

    uniform bool UI_Spiral <
        ui_label     = " 螺旋";
        ui_spacing   = 2;
        ui_tooltip   = "将空间扭曲成螺旋形。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = true;

    uniform float UI_OuterRing <
        ui_label     = " 外环大小";
        ui_type      = "slider";
        ui_min       = 0.00;
        ui_max       = 1.00;
        ui_step      = 0.01;
        ui_tooltip   = "外环定义纹理边界向屏幕边缘的范围。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.00;

    uniform float UI_Zoom <
        ui_label     = " 缩放";
        ui_type      = "slider";
        ui_min       = 0.00;
        ui_max       = 9.90;
        ui_step      = 0.01;
        ui_tooltip   = "放大输出。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.00;

    uniform float UI_Frequency <
        ui_label     = " 频率";
        ui_type      = "slider";
        ui_min       = 0.10;
        ui_max       = 5.00;
        ui_step      = 0.01;
        ui_tooltip   = "定义递归的频率。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.00;

    uniform float UI_X_Offset <
        ui_label     = " 中心水平偏移";
        ui_type      = "slider";
        ui_min       = -0.50;
        ui_max       = 0.50;
        ui_step      = 0.01;
        ui_tooltip   = "更改中心的水平位置。保持为 0 可获得最佳效果。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.00;

    uniform float UI_Y_Offset <
        ui_label     = " 中心垂直偏移";
        ui_type      = "slider";
        ui_min       = -0.50;
        ui_max       = 0.50;
        ui_step      = 0.01;
        ui_tooltip   = "更改中心的垂直位置。保持为 0 可获得最佳效果。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.00;

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " 着色器版本：" COBRA_DRO_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    #define COBRA_UTL_MODE 2
    #include ".\CobraUtility.fxh"

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    vs2ps VS_Droste(uint id : SV_VertexID)
    {
        const float2 AR                 = UI_EffectType == 0 ? float2(float(BUFFER_WIDTH) / BUFFER_HEIGHT, 1.0) : float2(1.0, 1.0);
        const float2 OFFSET             = float2(UI_X_Offset, UI_Y_Offset);
        const float NEW_CENTER_ANGLE    = abs(OFFSET.x) + abs(OFFSET.y) < 0.01 ? 1 : (atan2_approx(-OFFSET.x * AR.x, -OFFSET.y) + M_PI) / (2 * M_PI);
        const float INNER_RING          = 1 / exp(1 / (UI_Frequency));
        return vs_basic(id, float2(NEW_CENTER_ANGLE, INNER_RING));
    }

    void PS_Droste(vs2ps o, out float4 fragment : SV_Target)
    {
        // transform coordinate system
        const float2 AR     = UI_EffectType == 0 ? float2(float(BUFFER_WIDTH) / BUFFER_HEIGHT, 1.0) : 1.0;
        const float2 OFFSET = float2(UI_X_Offset, UI_Y_Offset);
        float2 new_pos      = (o.uv.xy - 0.5 + OFFSET) * AR;

        // calculate orientation of center and pixel
        const float NEW_CENTER_DISTANCE =  (1 - 2.0 * max(abs(OFFSET.x), abs(OFFSET.y)));
        const float NEW_CENTER_ANGLE    = o.uv.z;

        // calculate and normalize angle
        float angle                     = (atan2_approx(new_pos.x, new_pos.y) + M_PI) / (2 * M_PI);
        float val                       = angle * UI_Spiral;
        angle                           = 1 - fmod(abs(abs(angle - NEW_CENTER_ANGLE) - 0.5), 0.5) * 2;

        //smooth off-center projection
        float angle_smooth = (1 - cos(angle * angle * M_PI)) / 2;
        float intensity    = lerp(NEW_CENTER_DISTANCE, 1, angle_smooth);

        // calculate distance from center

        float cicle_dist = sqrt(dot(new_pos,new_pos)) / intensity;
        float rect_dist  = max(abs(new_pos.x), abs(new_pos.y));
        float rcdist     = UI_EffectType == 0 ? cicle_dist : rect_dist;
        rcdist           = log(rcdist * (10 - UI_Zoom)) * UI_Frequency;
        val             += rcdist;
        val              = (exp(fmod(val, 1) / UI_Frequency) - 1) / (rcp(o.uv.w) - 1);

        // normalized vector
        float vector_length     = sqrt(dot(new_pos,new_pos));
        float unit_circle_ratio = UI_EffectType == 0 ? 0.5 / vector_length : 0.5 / max(abs(new_pos.x), abs(new_pos.y));
        float2 normalized       = new_pos * unit_circle_ratio;

        // calculate relative position towards outer and inner ring and interpolate
        const float INNER_RING = o.uv.w * UI_OuterRing;
        float real_scale       = lerp(INNER_RING, UI_OuterRing,val);
        real_scale            *= intensity;
        float2 adjusted        = normalized * real_scale / AR + 0.5 - OFFSET;
        fragment               = tex2D(ReShade::BackBuffer, adjusted);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_Droste <
        ui_label     = "德罗斯特效果";
        ui_tooltip   = "------关于-------\n"
                       "Droste.fx 将图像空间扭曲为递归地出现在自身内部。\n\n"
                       "版本:    " COBRA_DRO_VERSION "\n作者:     SirCobra\n合集: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass Droste
        {
            VertexShader = VS_Droste;
            PixelShader  = PS_Droste;
        }
    }
}
