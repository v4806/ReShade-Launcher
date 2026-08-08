//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// EyeAdaption by brussell
// v. 2.32
// License: CC BY 4.0
//
// Credits:
// luluco250 - luminance get/store code from Magic Bloom
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

//effect parameters
uniform float fAdp_Delay <
    ui_label = "适应延迟";
    ui_tooltip = "图像适应亮度变化的速度。\n"
                 "0 = 即时适应\n"
                 "2 = 非常缓慢的适应";
    ui_category = "常规设置";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.6;

uniform float fAdp_TriggerRadius <
    ui_label = "适应触发半径";
    ui_tooltip = "触发适应的屏幕区域平均亮度。\n"
                 "1 = 仅使用图像中心\n"
                 "7 = 使用整个图像";
    ui_category = "常规设置";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 7.0;
    ui_step = 0.1;
> = 6.0;

uniform float fAdp_YAxisFocalPoint <
    ui_label = "Y轴焦点";
    ui_tooltip = "适应触发半径沿Y轴应用的位置。\n"
                 "0 = 屏幕顶部\n"
                 "1 = 屏幕底部";
    ui_category = "常规设置";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;

uniform float fAdp_Equilibrium <
    ui_label = "适应平衡点";
    ui_tooltip = "图像亮度值，在此值下不进行亮度适应。\n"
                 "0 = 早期增亮，晚期变暗\n"
                 "1 = 晚期增亮，早期变暗";
    ui_category = "常规设置";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;

uniform float fAdp_Strength <
    ui_label = "适应强度";
    ui_tooltip = "亮度适应的基础强度。\n";
    ui_category = "常规设置";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.0;

uniform float fAdp_BrightenHighlights <
    ui_label = "增亮高光";
    ui_tooltip = "高光区域的增亮强度。";
    ui_category = "增亮";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

uniform float fAdp_BrightenMidtones <
    ui_label = "增亮中间调";
    ui_tooltip = "中间调区域的增亮强度。";
    ui_category = "增亮";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.2;

uniform float fAdp_BrightenShadows <
    ui_label = "增亮阴影";
    ui_tooltip = "阴影区域的增亮强度。\n"
                 "设置为0以保留纯黑色。";
    ui_category = "增亮";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

uniform float fAdp_DarkenHighlights <
    ui_label = "变暗高光";
    ui_tooltip = "高光区域的变暗强度。\n"
                 "设置为0以保留纯白色。";
    ui_category = "变暗";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

uniform float fAdp_DarkenMidtones <
    ui_label = "变暗中间调";
    ui_tooltip = "中间调区域的变暗强度。";
    ui_category = "变暗";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.2;

uniform float fAdp_DarkenShadows <
    ui_label = "变暗阴影";
    ui_tooltip = "阴影区域的变暗强度。";
    ui_category = "变暗";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

#include "ReShade.fxh"

//global vars
#define LumCoeff float3(0.212656, 0.715158, 0.072186)
uniform float Frametime < source = "frametime"; >;

//textures and samplers
texture2D TexLuma { Width = 256; Height = 256; Format = R8; MipLevels = 7; };
texture2D TexAvgLuma { Format = R16F; };
texture2D TexAvgLumaLast { Format = R16F; };

sampler SamplerLuma { Texture = TexLuma; };
sampler SamplerAvgLuma { Texture = TexAvgLuma; };
sampler SamplerAvgLumaLast { Texture = TexAvgLumaLast; };

//pixel shaders
float PS_Luma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 color = tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0, 0));
    float luma = dot(color.xyz, LumCoeff);
    return luma;
}

float PS_AvgLuma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float avgLumaCurrFrame = tex2Dlod(SamplerLuma, float4(fAdp_YAxisFocalPoint.xx, 0, fAdp_TriggerRadius)).x;
    float avgLumaLastFrame = tex2Dlod(SamplerAvgLumaLast, float4(0.0.xx, 0, 0)).x;
    float delay = sign(fAdp_Delay) * saturate(0.815 + fAdp_Delay / 10.0 - Frametime / 1000.0);
    float avgLuma = lerp(avgLumaCurrFrame, avgLumaLastFrame, delay);
    return avgLuma;
}

float AdaptionDelta(float luma, float strengthMidtones, float strengthShadows, float strengthHighlights)
{
    float midtones = (4.0 * strengthMidtones - strengthHighlights - strengthShadows) * luma * (1.0 - luma);
    float shadows = strengthShadows * (1.0 - luma);
    float highlights = strengthHighlights * luma;
    float delta = midtones + shadows + highlights;
    return delta;
}

float4 PS_Adaption(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 color = tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0, 0));
    float avgLuma = tex2Dlod(SamplerAvgLuma, float4(0.0.xx, 0, 0)).x;

    color.xyz = pow(saturate(color.xyz), 1.0/2.2);
    float luma = dot(color.xyz, LumCoeff);
    float3 chroma = color.xyz - luma;

    float avgLumaAdjusted = lerp (avgLuma, 1.4 * avgLuma / (0.4 + avgLuma), fAdp_Equilibrium);
    float delta = 0;

    float curve = fAdp_Strength * 10.0 * pow(abs(avgLumaAdjusted - 0.5), 4.0);
    if (avgLumaAdjusted < 0.5) {
        delta = AdaptionDelta(luma, fAdp_BrightenMidtones, fAdp_BrightenShadows, fAdp_BrightenHighlights);
    } else {
        delta = -AdaptionDelta(luma, fAdp_DarkenMidtones, fAdp_DarkenShadows, fAdp_DarkenHighlights);
    }
    delta *= curve;

    luma += delta;
    color.xyz = saturate(luma + chroma);
    color.xyz = pow(color.xyz, 2.2);

    return color;
}

float PS_StoreAvgLuma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float avgLuma = tex2Dlod(SamplerAvgLuma, float4(0.0.xx, 0, 0)).x;
    return avgLuma;
}

//techniques
technique EyeAdaption <
    ui_tooltip =    "眼部适应尝试模拟眼睛适应不同光线条件的能力，\n"
                    "通过增亮暗区和变暗亮区来实现。"
                    ; >
{
    pass Luma
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Luma;
        RenderTarget = TexLuma;
    }

    pass AvgLuma
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_AvgLuma;
        RenderTarget = TexAvgLuma;
    }

    pass Adaption
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Adaption;
    }

    pass StoreAvgLuma
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_StoreAvgLuma;
        RenderTarget = TexAvgLumaLast;
    }
}
