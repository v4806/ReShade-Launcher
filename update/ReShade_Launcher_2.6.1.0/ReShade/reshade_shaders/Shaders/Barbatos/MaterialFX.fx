/*------------------.
| :: Description :: |
'-------------------/
    MaterialFX

    Version 1.4
    Author: Barbatos Bachiko
    License: MIT

    About: Bits, Chromatic Aberration, Fog, Film Grain, Vignette, and Color Grading.

     History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility
    Version 1.4
    * Added Film Grain effect 
    * Added Vignette effect
*/

#include "ReShade.fxh"
#define GetColor(c) tex2Dlod(ReShade::BackBuffer, float4((c).xy, 0, 0))

/*---------------.
| :: Settings :: |
'---------------*/

// Main Effect Selection
uniform int combo
<
    ui_category = "效果选择";
    ui_type = "combo";
    ui_label = "材质效果";
    ui_tooltip = "选择主要视觉效果";
    ui_items =
    "像素化\0"
    "色差\0"
    "胶片颗粒\0"
    "暗角\0";
>
= 0;

uniform float effect_intensity
<
    ui_category = "效果选择";
    ui_type = "slider";
    ui_label = "效果强度";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
>
= 1.0;

// Bits Settings
uniform int bits_levels
<
    ui_category = "像素化设置";
    ui_type = "slider";
    ui_label = "位级别";
    ui_tooltip = "每个通道的颜色级别数（值越低 = 色调分离越明显）";
    ui_min = 2; ui_max = 32; ui_step = 1;
>
= 8;

// Chromatic Aberration Settings
uniform float CAStrength
<
    ui_category = "色差";
    ui_type = "slider";
    ui_label = "水平强度";
    ui_min = 0.0; ui_max = 0.050; ui_step = 0.001;
>
= 0.001;

uniform float CAVertical
<
    ui_category = "色差";
    ui_type = "slider";
    ui_label = "垂直强度";
    ui_min = 0.0; ui_max = 0.050; ui_step = 0.001;
>
= 0.0;

uniform bool CA_radial
<
    ui_category = "色差";
    ui_label = "径向模式";
    ui_tooltip = "从中心径向应用色差";
>
= false;

// Film Grain Settings
uniform float grain_intensity
<
    ui_category = "胶片颗粒";
    ui_type = "slider";
    ui_label = "颗粒强度";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
>
= 1.0;

uniform float grain_size
<
    ui_category = "胶片颗粒";
    ui_type = "slider";
    ui_label = "颗粒大小";
    ui_tooltip = "单个颗粒粒子的大小";
    ui_min = 0.1; ui_max = 2.0; ui_step = 0.1;
>
= 1.0;

uniform bool grain_colored
<
    ui_category = "胶片颗粒";
    ui_label = "彩色颗粒";
>
= false;

uniform int grain_noise_type
<
    ui_category = "胶片颗粒";
    ui_type = "combo";
    ui_label = "噪点类型";
    ui_tooltip = "使用的噪点算法类型";
    ui_items = "简单随机\0IGN (交错梯度)\0程序蓝噪声\0";
>
= 1;

uniform float grain_hold_length
<
    ui_category = "胶片颗粒";
    ui_type = "slider";
    ui_label = "保持时长";
    ui_tooltip = "保持相同噪点模式的帧数";
    ui_min = 1.0; ui_max = 120.0; ui_step = 1.0;
>
= 48.0;

// Vignette Settings
uniform float vignette_radius
<
    ui_category = "暗角";
    ui_type = "slider";
    ui_label = "暗角半径";
    ui_min = 0.1; ui_max = 2.0; ui_step = 0.01;
>
= 0.7;

uniform float vignette_strength
<
    ui_category = "暗角";
    ui_type = "slider";
    ui_label = "暗角强度";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
>
= 0.5;

uniform float3 vignette_color
<
    ui_category = "暗角";
    ui_type = "color";
    ui_label = "暗角颜色";
>
= float3(0.0, 0.0, 0.0);

uniform int FRAME_COUNT < source = "framecount"; >;

/*----------------.
| :: Functions :: |
'----------------*/

float lum(float3 color)
{
    return (color.r + color.g + color.b) * 0.3333333;
}

float IGN(float2 n)
{
    float f = 0.06711056 * n.x + 0.00583715 * n.y;
    return frac(52.9829189 * frac(f));
}

float3 IGN3dts(float2 texcoord, float HL)
{
    float3 OutColor;
    float2 seed = texcoord * BUFFER_SCREEN_SIZE + (FRAME_COUNT % HL) * 5.588238;
    OutColor.r = IGN(seed);
    OutColor.g = IGN(seed + 91.534651 + 189.6854);
    OutColor.b = IGN(seed + 167.28222 + 281.9874);
    return OutColor;
}

float3 ProceduralBN3dts(float2 texcoord, float HL)
{
    float2 uv = texcoord * BUFFER_SCREEN_SIZE;
    float frame = FRAME_COUNT % HL;
    float3 noise = float3(0, 0, 0);
    float2 p = uv * 0.1 + frame * 0.01;

    for (int i = 0; i < 4; i++)
    {
        float scale = pow(2.0, i);
        float2 coord = p * scale + frame * (i + 1) * 0.1;
        noise.r += IGN(coord) / scale;
        noise.g += IGN(coord + 127.1) / scale;
        noise.b += IGN(coord + 311.7) / scale;
    }

    return frac(noise);
}

float random(float2 coords, float time)
{
    return frac(sin(dot(coords + time, float2(12.9898, 78.233))) * 43758.5453);
}

float random(float2 coords)
{
    return random(coords, 0.0);
}

float4 MaterialFXPass(float4 pos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float4 color = GetColor(texcoord);
    float4 original = color;
    
    if (combo == 0) // Bits
    {
        float levels = float(bits_levels);
        color.rgb = floor(color.rgb * levels) / levels;
    }
    else if (combo == 1) // Chromatic Aberration
    {
        if (CA_radial)
        {
            float2 center = float2(0.5, 0.5);
            float2 offset = texcoord - center;
            float distance = length(offset);
            float2 direction = normalize(offset);
            
            float2 redOffset = direction * CAStrength * distance;
            float2 blueOffset = direction * -CAStrength * distance;
            
            float4 redChannel = GetColor(texcoord + redOffset);
            float4 blueChannel = GetColor(texcoord + blueOffset);
            color.rgb = float3(redChannel.r, color.g, blueChannel.b);
        }
        else
        {
            float2 offsetAmount = float2(CAStrength, CAVertical);
            float4 redChannel = GetColor(texcoord + offsetAmount);
            float4 blueChannel = GetColor(texcoord - offsetAmount);
            color.rgb = float3(redChannel.r, color.g, blueChannel.b);
        }
    }
    else if (combo == 2) // Film Grain
    {
        float2 grainCoord = texcoord * BUFFER_SCREEN_SIZE / (grain_size * 100.0);
        float3 grainColor = float3(0, 0, 0);
        
        if (grain_noise_type == 0) // Simple Random
        {
            float time = FRAME_COUNT % grain_hold_length;
            float grain = random(grainCoord, time) - 0.5;
            
            if (grain_colored)
            {
                grainColor = float3(
                    random(grainCoord + float2(1.0, 0.0), time),
                    random(grainCoord + float2(0.0, 1.0), time),
                    random(grainCoord + float2(1.0, 1.0), time)
                ) - 0.5;
            }
            else
            {
                grainColor = float3(grain, grain, grain);
            }
        }
        else if (grain_noise_type == 1) // IGN (Interleaved Gradient)
        {
            float3 noise = IGN3dts(texcoord, grain_hold_length) - 0.5;
            
            if (grain_colored)
            {
                grainColor = noise;
            }
            else
            {
                float luminance = lum(noise);
                grainColor = float3(luminance, luminance, luminance);
            }
        }
        else if (grain_noise_type == 2) // Procedural Blue Noise
        {
            float3 noise = ProceduralBN3dts(texcoord, grain_hold_length) - 0.5;
            
            if (grain_colored)
            {
                grainColor = noise;
            }
            else
            {
                float luminance = lum(noise);
                grainColor = float3(luminance, luminance, luminance);
            }
        }
        
        color.rgb += grainColor * grain_intensity * 0.1;
    }
    else if (combo == 3) // Vignette
    {
        float2 center = float2(0.5, 0.5);
        float distance = length(texcoord - center);
        float vignette = smoothstep(vignette_radius, vignette_radius - 0.3, distance);
        vignette = lerp(1.0, vignette, vignette_strength);
        color.rgb = lerp(vignette_color, color.rgb, vignette);
    }

    color.rgb = lerp(original.rgb, color.rgb, effect_intensity);
    return float4(saturate(color.rgb), 1.0);
}

/*-----------------.
| :: Techniques :: |
'-----------------*/
technique MaterialFX
<
    ui_tooltip = "像素化、色差、胶片颗粒和暗角";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = MaterialFXPass;
    }
}
