/*------------------.
| :: Description :: |
'-------------------/

    Shading
    Version 1.7
    Author: Barbatos Bachiko 
    License: MIT

    About: Outline Shading otimizado e limpeza de código
    History:
    (*) Feature (+) Improvement  (x) Bugfix  (-) Information  (!) Compatibility

    Version 1.7
    + Revised
*/

#ifndef RENDER_SCALE
#define RENDER_SCALE 1.0
#endif
#define RENDER_WIDTH  (BUFFER_RCP_WIDTH  * RENDER_SCALE)
#define RENDER_HEIGHT (BUFFER_RCP_HEIGHT * RENDER_SCALE)

#define GetColor(c) tex2Dlod(ReShade::BackBuffer, float4((c).xy, 0, 0))
#define getDepth(coords)      (ReShade::GetLinearizedDepth(coords))

#include "ReShade.fxh"

// UI Settings

uniform float ShadingIntensity <
    ui_type = "slider";
    ui_label = "着色强度";
    ui_tooltip = "控制效果强度。";
    ui_min = 0.0;
    ui_max = 10.0;
    ui_default = 1.5;
    ui_category = "着色设置";
> = 1.5;

uniform float sharpness <
    ui_type = "slider";
    ui_label = "锐度";
    ui_tooltip = "控制锐度级别。";
    ui_min = 0.0;
    ui_max = 10.0;
    ui_default = 0.2;
    ui_category = "着色设置";
> = 0.2;

uniform int SamplingArea <
    ui_type = "combo";
    ui_label = "采样区域";
    ui_tooltip = "选择采样半径。";
    ui_items = "3x3\0.5x5\0.7x7\0.9x9\0.11x11\0";
    ui_default = 0;
    ui_category = "着色设置";
> = 0;

uniform bool EnableMixWithSceneColor <
    ui_label = "与场景颜色混合";
    ui_category = "着色设置";
> = false;

uniform bool EnableNormalMap <
    ui_label = "启用法线贴图";
    ui_category = "着色设置";
> = false;

uniform int viewMode <
    ui_type = "combo";
    ui_label = "视图模式";
    ui_tooltip = "选择视图模式";
    ui_items = "无\0法线\0深度\0";
    ui_category = "调试模式";
> = 0;
static const int SAMPLE_RADIUS_TABLE[5] = { 1, 2, 3, 4, 5 };

float4 LoadPixel(sampler2D tex, float2 uv)
{
    return tex2D(tex, uv);
}

float3 GetNormalFromDepth(float2 coords)
{
    float2 texelSize = float2(RENDER_WIDTH, RENDER_HEIGHT);
    float dc = getDepth(coords);
    float dx = getDepth(coords + float2(texelSize.x, 0));
    float dy = getDepth(coords + float2(0, texelSize.y));
    float3 dX = float3(texelSize.x, 0, dx - dc);
    float3 dY = float3(0, texelSize.y, dy - dc);
    float3 n = normalize(cross(dX, dY));
    return isnan(n.x) ? float3(0, 0, 1) : n;
}

float4 ApplySharpness(float4 color, float2 uv)
{
    float2 ps = float2(RENDER_WIDTH, RENDER_HEIGHT);
    
    static const float2 Offsets[4] =
    {
        float2(-ps.x, 0.0), // left
        float2(ps.x, 0.0), // right
        float2(0.0, -ps.y), // top
        float2(0.0, ps.y) // bottom
    };

    float4 sum = float4(0.0, 0.0, 0.0, 0.0);

    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float2 o = Offsets[i];
        sum += GetColor(float4(uv + o, 0.0, 0.0));
    }

    float factor = sharpness;
    float4 sharpened = color * (1.0 + factor) - sum * (factor * 0.25);
    return clamp(sharpened, 0.0, 1.0);
}

float4 ApplyShading(float4 color, float2 uv)
{
    float2 ps = float2(RENDER_WIDTH, RENDER_HEIGHT);
    int r = SAMPLE_RADIUS_TABLE[SamplingArea];
    float3 curN = EnableNormalMap ? GetNormalFromDepth(uv) : float3(0, 0, 1);
    float3 accDiff = float3(0, 0, 0);
    int samples = 0;

    for (int y = -r; y <= r; ++y)
    {
        for (int x = -r; x <= r; ++x)
        {
            if (x == 0 && y == 0)
                continue;
            float2 coord = uv + float2(x, y) * ps;
            float4 nc = GetColor(float4(coord, 0, 0));
            float3 nn = EnableNormalMap ? GetNormalFromDepth(coord) : float3(0, 0, 1);
            float influence = EnableNormalMap ? max(dot(curN, nn), 0) : 1;
            accDiff += abs(nc.rgb - color.rgb) * influence;
            samples++;
        }
    }
    float complexity = (samples > 0) ? dot(accDiff, float3(1, 1, 1)) / samples : 0;
    float shadeF = max(1 - complexity * ShadingIntensity, 0);
    float4 result = color * shadeF;
    return EnableMixWithSceneColor ? lerp(color, result, 0.5) : result;
}

float4 ShadingPS(float4 vpos : SV_Position, float2 uv : TexCoord) : SV_Target
{
    if (viewMode == 1)
    {
        float3 n = GetNormalFromDepth(uv);
        return float4(n * 0.5 + 0.5, 1);
    }
    else if (viewMode == 2)
    {
        float d = getDepth(uv);
        return float4(d, d, d, 1);
    }

    float4 col = GetColor(float4(uv, 0, 0));
    col = ApplyShading(col, uv);
    return ApplySharpness(col, uv);
}

technique Shading
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = ShadingPS;
    }
}
