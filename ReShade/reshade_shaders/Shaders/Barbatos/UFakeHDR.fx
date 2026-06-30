/*

uFakeHDR

Version 1.5.1
Author: Barbatos Bachiko
License: MIT
 
About : This shader simulates HDR effects(expected by me) for SDR. 

History:
(*) Feature (+) Improvement\t(x) Bugfix (-) Information (!)Compatibility

Version 1.5.1:
+ Revised
*/

#include "ReShade.fxh"
#define GetColor(c) tex2Dlod(ReShade::BackBuffer, float4((c).xy, 0, 0))

uniform float HDRPower < ui_type="slider";ui_label="HDR 强度"; ui_min=0.1; ui_max=4.0; > = 1.150;
uniform int ToneMappingMethod < ui_type="combo";ui_label="色调映射方法"; ui_items="Reinhard\0电影\0ACES\0BT.709\0对数\0自适应\0"; > = 5;
uniform int HDRExtraMode < ui_type="combo";ui_label="额外模式"; ui_items="无\0多重曝光\0"; > = 0;
uniform bool EnableDithering < ui_category="抖动";ui_type="checkbox"; ui_label="启用抖动"; > = false;
uniform float DitherStrength < ui_category="抖动";ui_type="slider"; ui_label="抖动强度"; ui_min=0.0; ui_max=1.0; > = 0.05;
uniform float NoiseScale < ui_category="抖动";ui_type="slider"; ui_label="噪点比例"; ui_min=0.1; ui_max=10.0; > = 1.0;
uniform float NoiseSeed < ui_category="抖动";ui_type="slider"; ui_label="噪点种子"; ui_min=1.0; ui_max=10000.0; > = 4375.8545;
uniform float AdaptationSpeed < ui_category="亮度 (自适应)";ui_type="slider"; ui_label="适应速度"; ui_min=0.01; ui_max=1.0; > = 0.10;

static float lastSceneLuminance = 0.0;

float CalculateSceneLuminance(float2 uv)
{
    float lum = dot(GetColor(float4(uv, 0, 0)).rgb,
                    float3(0.2126, 0.7152, 0.0722));
    lastSceneLuminance = lerp(lastSceneLuminance, lum, AdaptationSpeed);
    return lastSceneLuminance;
}

// Tone Mapping functions
float3 ReinhardToneMapping(float3 c)
{
    float lum = max(dot(c, float3(0.2126, 0.7152, 0.0722)) * 1.2, 0.0001);
    float nLum = clamp(lum / 0.25, 0.0, 1.0);
    return saturate(c * (nLum / (nLum + 1.0)) * 1.2);
}

float3 FilmicToneMapping(float3 c)
{
    return saturate((c * (c * 0.6 + 0.4)) / (c + 0.6) * 1.5);
}

float3 ACESToneMapping(float3 c)
{
    return saturate((c * (c + 0.0245786) - (c * c * 0.000093607)) / (c + 0.000009));
}

float3 BTToneMapping(float3 c)
{
    return saturate(c * (c * 0.7 + 0.3));
}

float3 LogarithmicToneMapping(float3 c)
{
    return saturate(log2(c + 1.0));
}

float3 AdaptiveToneMapping(float3 c, float sceneLum)
{
    float adjust = lerp(1.0, clamp(0.5 / (sceneLum + 0.001), 0.5, 2.0), AdaptationSpeed);
    return saturate(c * adjust);
}

float3 MultipleExposuresHDR(float3 c)
{
    return saturate(max(max(pow(c, 2.0), c), pow(c, 0.5)));
}

float make_noise(float2 uv)
{
    return frac(sin(dot(uv * NoiseScale, float2(12.9898, 78.233))) * NoiseSeed);
}

float3 ApplyDithering(float3 c, float2 uv)
{
    return saturate(c + (make_noise(uv) - 0.5) * DitherStrength);
}

float3 ApplyToneMapping(float3 c, float2 uv)
{
    switch (ToneMappingMethod)
    {
        case 0:
            c = ReinhardToneMapping(c);
            break;
        case 1:
            c = FilmicToneMapping(c);
            break;
        case 2:
            c = ACESToneMapping(c);
            break;
        case 3:
            c = BTToneMapping(c);
            break;
        case 4:
            c = LogarithmicToneMapping(c);
            break;
        case 5:
            c = AdaptiveToneMapping(c, CalculateSceneLuminance(uv));
            break;
        default:
            break;
    }
    return c;
}

float4 uFakeHDRPass(float4 pos : SV_Position, float2 uv : TexCoord) : SV_Target
{
    float3 c = pow(tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb, HDRPower);
    c = ApplyToneMapping(c, uv);
    if (HDRExtraMode == 1)
        c = MultipleExposuresHDR(c);
    if (EnableDithering)
        c = ApplyDithering(c, uv);
    return float4(saturate(c), 1.0);
}

technique uFakeHDR
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = uFakeHDRPass;
    }
}
