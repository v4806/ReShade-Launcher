////////////////////////////////////////////////////////////////////////////////////////////////////////
// Frequency (Frquency_CS.fx) by SirCobra
// Version 0.1.1
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// Frequency_CS.fx creates an effect also known as `Frequency Modulation`, which
// scans the image from left to right and releases a wave whenever a luminance-
// based threshold is reached. The pixel luminance is summed up and modulated
// depending on a given period. Additional parameters give the effect a unique
// look. A masking stage enables filtering affected colors and depth.
//
// ----------Credits-----------
// Thanks to...
// ... TeoTave for introducing me to this effect!
// ... https://dominik.ws/art/movingdots/ for showcasing a concrete example on how the effect can look!
// ... Marty McFly, Lord of Lunacy and CeeJayDK for technical discussions.
////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "Reshade.fxh"

uniform float timer <
    source = "timer";
> ;

// Shader Start

//  Namespace everything!

namespace COBRA_XFRQ
{

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                            Defines & UI
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Defines

    #define COBRA_XFRQ_VERSION "0.1.1"
    #define COBRA_UTL_MODE 0
    #include ".\CobraUtility.fxh"

    #define COBRA_XFRQ_THREADS 16
    #define COBRA_XFRQ_THREAD_WIDTH 16
    #define COBRA_XFRQ_DISPATCHES ROUNDUP(BUFFER_HEIGHT, COBRA_XFRQ_THREADS)

    // We need Compute Shader Support
    #if (((__RENDERER__ >= 0xb000 && __RENDERER__ < 0x10000) || (__RENDERER__ >= 0x14300)) && __RESHADE__ >= 40800)
        #define COBRA_XFRQ_COMPUTE 1
    #else
        #define COBRA_XFRQ_COMPUTE 0
        #warning "Frequency.fx does only work with ReShade 4.8 or newer, DirectX 11 or newer, OpenGL 4.3 or newer and Vulkan."
    #endif

    #if COBRA_XFRQ_COMPUTE != 0

    // Includes

    // UI

    uniform uint UI_Frequency <
        ui_label     = " 周期";
        ui_type      = "slider";
        ui_spacing   = 2;
        ui_min       = 1;
        ui_max       = 200;
        ui_step      = 1;
        ui_tooltip   = "确定波浪出现的频率。较低的值使波浪出现的间隔更短。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 20;

    uniform float UI_Thickness <
        ui_label     = " 厚度";
        ui_type      = "slider";
        ui_min       = 1;
        ui_max       = 100;
        ui_step      = 1;
        ui_units     = "px";
        ui_tooltip   = "波浪的像素厚度。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 4;

    uniform float UI_Gamma <
        ui_label     = " 伽马值";
        ui_type      = "slider";
        ui_min       = 0.4;
        ui_max       = 4.4;
        ui_step      = 0.01;
        ui_tooltip   = "伽马校正值。默认值为1。该值越高，高光越持久。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.5;

    uniform float UI_BaseIncrease <
        ui_label     = " 基础增量";
        ui_type      = "slider";
        ui_min       = 0.00;
        ui_max       = 10.00;
        ui_step      = 0.01;
        ui_tooltip   = "此值添加到每个像素以创建独立于图像的基础频率。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.150;

    uniform bool UI_BaseMultiply <
        ui_label     = " 基础值与背景相乘";
        ui_tooltip   = "基础值与场景值相乘以依赖于图像内容。\n现在它作为图像值的乘数。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    uniform float UI_Decay <
        ui_label     = " 衰减";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "每次波浪后的频率衰减。高度不稳定，但可以产生\n有趣的效果。不建议在动画波浪时使用超过0的值。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.000;

    uniform float UI_Offset <
        ui_label     = " 偏移";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 100.0;
        ui_step      = 0.1;
        ui_units     = "%%";
        ui_tooltip   = "第一个波浪的初始偏移。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.1;

    uniform int UI_BlendMode <
        ui_label     = " 混合模式";
        ui_type      = "combo";
        ui_items     = "色调\0颜色\0明度\0";
        ui_tooltip   = "应用于波浪的混合模式。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 2;

    uniform float3 UI_EffectTint <
        ui_label     = " 色调";
        ui_type      = "color";
        ui_tooltip   = "当混合模式设置为色调时，指定波浪的色调。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = float3(1.00, 0.50, 0.50);

    uniform float UI_Transparency <
        ui_label     = " 黑色透明度";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 100.0;
        ui_step      = 0.1;
        ui_units     = "%%";
        ui_tooltip   = "未受波浪影响区域的透明度。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.0;

    uniform uint UI_RotationType <
        ui_label     = " 方向";
        ui_type      = "combo";
        ui_items     = "左\0下\0右\0上\0";
        ui_tooltip   = "效果开始的方向。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0;

    uniform int UI_Blur <
        ui_label     = " 模糊";
        ui_type      = "combo";
        ui_items     = "无\0二\0四\0六\0八\0";
        ui_tooltip   = "应用于输入的模糊。较高的值使波浪更平滑。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 2;

    uniform bool UI_Animate <
        ui_label     = " 动画";
        ui_tooltip   = "使波浪随时间移动。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = true;

    uniform bool UI_Invert <
        ui_label     = " 反转";
        ui_tooltip   = "反转波浪。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    uniform bool UI_UseDepth <
        ui_label     = " 使用深度";
        ui_tooltip   = "波浪将响应场景深度而非场景亮度。\n需要可用的深度缓冲区。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    uniform float UI_DepthMultiplier <
        ui_label     = " 深度乘数";
        ui_type      = "slider";
        ui_min       = 0.01;
        ui_max       = 10.00;
        ui_tooltip   = "使用深度时的深度值乘数。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.0;

    uniform bool UI_HotsamplingMode <
        ui_label     = " 热采样模式";
        ui_tooltip   = "启用此选项，然后调整设置，效果在所有分辨率下\n保持相似。如果不打算使用热采样，请关闭此选项。";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    #define COBRA_UTL_MODE 1
    #include ".\CobraUtility.fxh"

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " 着色器版本：" COBRA_XFRQ_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                             Textures & Samplers & Storage & Shared Memory
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Texture

    texture TEX_Frequency
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = R8;
    };

    texture TEX_Mask
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = R16F;
    };

    // Sampler

    sampler2D SAM_Frequency { Texture = TEX_Frequency; };
    sampler2D SAM_Mask { Texture = TEX_Mask; };

    // Storage

    storage STOR_Frequency { Texture = TEX_Frequency; };
    storage STOR_Mask { Texture = TEX_Mask; };

    // Groupshared Memory
    groupshared float summary[COBRA_XFRQ_THREADS * COBRA_XFRQ_THREAD_WIDTH];
    groupshared uint overlap[COBRA_XFRQ_THREADS * COBRA_XFRQ_THREAD_WIDTH];
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    #define COBRA_UTL_MODE 2
    #define COBRA_UTL_COLOR 1
    #include "CobraUtility.fxh"

    // rotate the screen
    float2 rotate(float2 texcoord1, bool revert)
    {
        float2 texcoord = texcoord1.xy;
        uint ANGLE      = UI_RotationType * 90 + (360 - 2 * UI_RotationType * 90) * revert;
        float2 rotated  = texcoord;

        // easy cases to avoid dividing by zero; values 0 & 360 are trivial
        rotated = (ANGLE == 90) ? float2(texcoord.y, 1 - texcoord.x) : rotated;
        rotated = (ANGLE == 180) ? float2(1 - texcoord.x, 1 - texcoord.y) : rotated;
        rotated = (ANGLE == 270) ? float2(1 - texcoord.y, texcoord.x) : rotated;
        return rotated.xy;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    void VS_Clear(in uint id : SV_VertexID, out float4 position : SV_Position)
    {
        position = -3.0;
    }

    void PS_Clear(float4 position : SV_Position, out float4 fragment : SV_TARGET0)
    {
        fragment = 0.0;
        discard;
    }

    void PS_Mask(float4 vpos : SV_Position, out float fragment : SV_TARGET)
    {
        float val    = 0.0;
        uint counter = 0;
        [unroll] for (int i = -8; i <= 8; i++)
        {
            if (((vpos.y + i) > 0) && ((vpos.y + i) < BUFFER_HEIGHT) && (abs(i) <= (2 * UI_Blur)))
            {
                float2 texcoord = (vpos.xy + int2(0, i)) / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
                texcoord        = rotate(texcoord, false);
                float3 rgb      = tex2D(ReShade::BackBuffer, texcoord).rgb;
                float depth     = ReShade::GetLinearizedDepth(texcoord);
                float f         = check_focus(rgb, depth, texcoord);
                if (f)
                {
                    val += UI_UseDepth ? f * UI_DepthMultiplier * pow(abs(depth), UI_Gamma) : f * dot(pow(abs(rgb), UI_Gamma), 1.0);
                    counter++;
                }
            }
        }

        float HS_MULT       = UI_HotsamplingMode ? 1920.0 / BUFFER_WIDTH : 1.0;
        fragment            = val / max(counter, 0.5);
        float intermediate  = UI_BaseMultiply ? fragment : 1.0;
        fragment            = fragment + UI_BaseIncrease * intermediate;
        fragment           *= HS_MULT;
    }

    void CS_Frequency(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
    {
        uint start       = id.x * ROUNDUP(BUFFER_WIDTH, COBRA_XFRQ_THREAD_WIDTH);
        uint end         = min(start + ROUNDUP(BUFFER_WIDTH, COBRA_XFRQ_THREAD_WIDTH) - 1, BUFFER_WIDTH - 1);
        uint global_zero = tid.y * COBRA_XFRQ_THREAD_WIDTH;
        float accum_s    = UI_Offset / 100.0 * UI_Frequency - fmod(UI_Animate * timer / 200.0, UI_Frequency);
        accum_s          = (id.x == 0) ? accum_s : 0.0;
        float accum      = accum_s;
        float section[ROUNDUP(BUFFER_WIDTH, COBRA_XFRQ_THREAD_WIDTH)];
        // parallel prefix sum version
        // 1) add local array, write sum to global thread array -> global write
        if (id.y < BUFFER_HEIGHT)
        {
            for (uint i = start; i <= end; i++)
            {
                section[i - start] = tex2Dfetch(SAM_Mask, int2(i, id.y)).r;
                accum += section[i - start];
            }
            summary[global_zero + id.x] = accum;
        }

        // 1.5) clear global array, due to two arrays we dont need another sync
        overlap[global_zero + id.x] = 0;

        barrier();
        // 2) sync arrays and add sum -> global read
        float accum_l = accum_s;
        if (id.y < BUFFER_HEIGHT)
        {
            for (uint i = 0; i < id.x; i++)
            {
                accum_l += summary[global_zero + i];
            }
        }

        // 3) calculate modulos: if decay==0 by modulo in local array, if decay > 0 by subtracting iterations from total value until in cell.
        //    Also shade areas and write overlap to thread array (forward or backward reading? probably forward with atomicAdd) -> forward add
        float decay         = 1.0;
        uint remaining      = 0;
        uint first_position = end;
        const uint R        = UI_HotsamplingMode ? UI_Thickness * float(BUFFER_WIDTH) / 1920.0 : UI_Thickness;
        const float U       = 1.0 + UI_Decay;
        if (id.y < BUFFER_HEIGHT)
        {
            /*  the math idea for future corrections
                accum - ((f) + (f * u) + (f * u * u) + ...) < 0
                accum < (f) + (f * u) + (f * u * u) + ...
                accum < f *((1) + (1 * u) + (1 * u * u) + ...);
                accum < s(n) with a = UI_Frequency, r = u;
                accum < a (1- u^n) / (1-u) // (1-u) negative cause u>1
                accum/a*(1-u) > (1-u^n) // * -1
                -accum/a*(1-u) < u^n - 1
                1 -accum/a*(1-u) < u^n
                log(1 -accum/a*(1-u)) < n * log(u) // logu > 0
                log(1 -accum/a*(1-u))/ log(u) < n
                n = ceil(log(1 -accum/a*(1-u))/ log(u))
                accum -= s(n)
                accum -= a * (1- u^n) / (1-u)

                ==1 case:
                accum < an
                accumfd < n
                n = ceil(accumfd)
                accum - UI_Frequency*n
            */
            //float accumfd = uint(accum_l) / UI_Frequency; // @TODO for some reason i need uint conversion and additional while pass
            /* if (!(U > 1.0)) // always produces rounding issues past initial thread.
            {
                uint n = ROUNDUP(uint(accum_l), UI_Frequency);
                accum_l -= UI_Frequency * n;
            } */
            /* else
            {  // currently doesn't work properly although math should be correct
                uint n = ceil(log(1-accumfd*(1-u)) * rcp(log(u)));
                decay = (1-pow(u,n))/(1-u);
                accum_l -= UI_Frequency * decay;
            } */

            while (accum_l > 0.0)
            {
                accum_l -= UI_Frequency * decay;
                decay *= U;
            }

            for (uint i = start; i <= end; i++)
            {
                accum_l += section[i - start];
                if (accum_l > 0.0)
                {
                    remaining      = R;
                    first_position = min(i, first_position);
                    accum_l -= UI_Frequency * decay;
                    decay *= U;
                }

                if (remaining > 0)
                {
                    remaining--;
                    tex2Dstore(STOR_Frequency, int2(i, id.y), 1.0);
                }
            }

            uint next = 1;
            while (remaining > 0 && ((id.x + next) < COBRA_XFRQ_THREAD_WIDTH))
            {
                atomicMax(overlap[global_zero + id.x + next++], remaining);
                remaining = max(int(remaining) - ROUNDUP(BUFFER_WIDTH, COBRA_XFRQ_THREAD_WIDTH), 0);
            }
        }

        barrier();

        // 4) shade overlap
        if (id.y < BUFFER_HEIGHT)
        {
            remaining = overlap[global_zero + id.x];
            for (uint i = start; i < first_position; i++)
            {
                if (remaining > 0)
                {
                    remaining--;
                    tex2Dstore(STOR_Frequency, int2(i, id.y), 1.0); // TODO coords
                }
            }
        }
    }

    // reproject to output window
    void PS_PrintFrequency(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        float3 value        = tex2Dfetch(ReShade::BackBuffer, floor(vpos.xy)).rgb;
        float3 intermediate = UI_BlendMode == 2 ? dot(value.rgb, 1.0) / 3.0 : value;
        intermediate        = UI_BlendMode == 0 ? UI_EffectTint : intermediate;
        float2 texcoord_new = rotate(texcoord, true);
        float intensity     = tex2D(SAM_Frequency, texcoord_new).r;
        intensity           = intensity + (1.0 - 2.0 * intensity) * UI_Invert;
        fragment.rgb        = intensity * intermediate + (1.0 - intensity) * value * UI_Transparency / 100.0;
        fragment.a          = 1.0;
        fragment.rgb        = UI_ShowMask ? 1.0 - tex2D(SAM_Mask, texcoord_new).rrr : fragment.rgb;
        fragment            = (UI_ShowSelectedHue * UI_FilterColor) ? show_hue(texcoord, fragment) : fragment;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_Frequency <
        ui_label     = "频率";
        ui_tooltip   = "------关于-------\n"                      
                       "从左到右扫描图像，并在达到基于亮度的阈值时释放波浪。\n"
                       "像素亮度被累加并根据给定周期进行调制。\n"
                       "额外参数使效果具有独特的外观。\n"
                       "遮罩阶段可以过滤受影响的颜色和深度。\n\n"
                       "版本：    " COBRA_XFRQ_VERSION "\n作者：     SirCobra\n合集： CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass Mask
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_Mask;
            RenderTarget = TEX_Mask;
        }

        pass PrepareFrequency
        {
            VertexShader       = VS_Clear;
            PixelShader        = PS_Clear;
            RenderTarget0      = TEX_Frequency;
            ClearRenderTargets = true;
            PrimitiveTopology  = POINTLIST;
            VertexCount        = 1;
        }

        pass Frequency
        {
            ComputeShader = CS_Frequency<COBRA_XFRQ_THREAD_WIDTH, COBRA_XFRQ_THREADS>;
            DispatchSizeX = 1;
            DispatchSizeY = COBRA_XFRQ_DISPATCHES;
        }

        pass PrintFrequency
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_PrintFrequency;
        }
    }

#endif // Shader End

} // Namespace End

/*-------------.
| ::  TODO  :: |
'--------------/

* RGB channels independent
* full rotation support
* hotsampling
* mask displacement (2 Techniques)
* 3rd Technique for Frequency AA
*/
