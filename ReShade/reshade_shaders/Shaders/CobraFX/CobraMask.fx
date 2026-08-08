////////////////////////////////////////////////////////////////////////////////////////////////////////
// Cobra Mask (CobraMask.fx) by SirCobra
// Version 0.3.0
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// CobraMask.fx allows to apply ReShade shaders exclusively to a selected part of the screen.
// The mask can be defined through color and scene-depth parameters. The parameters are
// specifically designed to work in accordance with the color and depth selection of other
// CobraFX shaders. This shader works the following way: In the effect window, you put
// "Cobra Mask: Start" above, and "Cobra Mask: Finish" below the shaders you want to be
// affected by the mask. When you turn it on, the effects in between will only affect the
// part of the screen with the correct color and depth.
//
// ----------Credits-----------
// 1) The effect can be applied to a specific area like a DoF shader. The basic methods for this were
// taken with permission from: https://github.com/FransBouma/OtisFX/blob/master/Shaders/Emphasize.fx
// 2) HSV conversions by Sam Hocevar: http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "Reshade.fxh"

// Shader Start

// Namespace Everything!

namespace COBRA_MSK
{

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                            Defines & UI
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Defines
    #define COBRA_MSK_VERSION "0.3.0"

    #define COBRA_UTL_MODE 0
    #include ".\CobraUtility.fxh"

    // UI

    uniform float UI_Opacity <
        ui_label     = " 效果不透明度";
        ui_type      = "slider";
        ui_spacing   = 2;
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_tooltip   = "整体不透明度。";
        ui_step      = 0.001;
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.000;

    #define COBRA_UTL_MODE 1
    #include ".\CobraUtility.fxh"

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " 着色器版本：" COBRA_MSK_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                         Textures & Samplers
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Texture

    texture TEX_Mask
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16F;
    };

    // Sampler

    sampler2D SAM_Mask
    {
        Texture   = TEX_Mask;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    #define COBRA_UTL_MODE 2
    #define COBRA_UTL_COLOR 1
    #include ".\CobraUtility.fxh"

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    void PS_MaskStart(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        float4 color   = tex2Dfetch(ReShade::BackBuffer, floor(vpos.xy));
        float depth    = ReShade::GetLinearizedDepth(texcoord);
        float in_focus = check_focus(color.rgb, depth, texcoord);
        fragment       = float4(color.rgb, in_focus);
    }

    void PS_MaskEnd(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = tex2Dfetch(SAM_Mask, floor(vpos.xy));
        fragment = UI_ShowMask ? 1 - fragment.aaaa : lerp(tex2Dfetch(ReShade::BackBuffer, floor(vpos.xy)), fragment, (1.0 - fragment.a * UI_Opacity));
        fragment = (UI_ShowSelectedHue * UI_FilterColor) ? show_hue(texcoord, fragment) : fragment;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_CobraMaskStart <
        ui_label     = "Cobra遮罩: 开始";
        ui_tooltip   = "将此放置在要遮罩的着色器上方。\n"
                       "被遮罩的区域会在这里复制并存储，这意味着\n"
                       "开始和结束之间的所有效果只影响未遮罩的区域。\n\n"
                       "------关于-------\n"
                       "CobraMask.fx允许将ReShade着色器仅应用于屏幕的选定部分。\n"
                       "遮罩可以通过颜色和场景深度参数来定义。这些参数\n"
                       "专门设计用于与其他CobraFX着色器的颜色和深度选择配合使用。\n\n"
                       "版本:    " COBRA_MSK_VERSION "\n作者:     SirCobra\n合集: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass MaskStart
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_MaskStart;
            RenderTarget = TEX_Mask;
        }
    }

    technique TECH_CobraMaskFinish <
        ui_label     = "Cobra遮罩: 结束";
        ui_tooltip   = "将此放置在要遮罩的着色器下方。\n"
                       "被遮罩的区域会再次应用到屏幕上。\n\n"
                       "------关于-------\n"
                       "CobraMask.fx允许将ReShade着色器仅应用于屏幕的选定部分。\n"
                       "遮罩可以通过颜色和场景深度参数来定义。这些参数\n"
                       "专门设计用于与其他CobraFX着色器的颜色和深度选择配合使用。\n\n"
                       "版本:    " COBRA_MSK_VERSION "\n作者:     SirCobra\n合集: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass MaskEnd
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_MaskEnd;
        }
    }
}