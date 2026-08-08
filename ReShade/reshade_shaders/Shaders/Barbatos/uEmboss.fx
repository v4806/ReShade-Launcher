/*------------------.
| :: Description :: |
'-------------------/

    uEmbossFX

    Version 1.2
    Author: Barbatos Bachiko
    License: MIT

    About: Emboss effect

    History:
    (*) Feature (+) Improvement (x) Bugfix (-) Information (!) Compatibility

    Version 1.2
    + Revised
*/

#include "ReShade.fxh"
#define GetColor(uv) tex2Dlod(ReShade::BackBuffer, float4((uv), 0, 0))

/*---------------.
| :: Settings :: |
'---------------*/

uniform float emboss_intensity <
    ui_type = "slider";
    ui_label = "浮雕强度";
    ui_tooltip = "浮雕混合的强度";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.1;
> = 0.2;

uniform int kernel_type <
    ui_type = "combo";
    ui_label = "核心类型";
    ui_tooltip = "0: 正常, 1: 反转, 2: 柔和";
    ui_items = "正常\0反转\0柔和\0";
> = 2;

uniform float kernel_scale <
    ui_type = "slider";
    ui_label = "核心比例";
    ui_tooltip = "卷积核的缩放因子";
    ui_min = 0.1; ui_max = 2.0; ui_step = 0.1;
> = 1.0;

uniform float edge_highlight_intensity <
    ui_type = "slider";
    ui_label = "边缘高光";
    ui_tooltip = "在检测到的边缘处增加亮度";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.1;
> = 0.2;

uniform int direction_mode <
    ui_type = "combo";
    ui_label = "方向";
    ui_tooltip = "0: 垂直, 1: 水平, 2: 对角线, 3: 全部";
    ui_items = "垂直\0水平\0对角线\0全部\0";
> = 3;

// 3x3 neighbor offsets
static const float2 Offsets[9] = {
    float2(-1, -1), float2( 0, -1), float2( 1, -1),
    float2(-1,  0), float2( 0,  0), float2( 1,  0),
    float2(-1,  1), float2( 0,  1), float2( 1,  1)
};

/*----------------.
| :: Functions :: |
'----------------*/

float IsSampleEnabled(int idx, int mode)
{
    switch (mode)
    {
        case 0: return (idx == 1 || idx == 4 || idx == 7);               // Vertical
        case 1: return (idx == 3 || idx == 4 || idx == 5);               // Horizontal
        case 2: return (idx == 0 || idx == 2 || idx == 6 || idx == 8);   // Diagonal
        default: return true;                                           // All
    }
}

void LoadKernel(int type, out float k[9])
{
    if (type == 1)
    {
        // Inverted
        k = {
             2,  1,  0,
             1, -1, -1,
             0, -1, -2
        };
    }
    else if (type == 2)
    {
        // Soft
        k = {
            -1, -1,  0,
            -1,  0,  1,
             0,  1,  1
        };
    }
    else
    {
        // Normal
        k = {
            -2, -1,  0,
            -1,  1,  1,
             0,  1,  2
        };
    }

    for (int i = 0; i < 9; i++)
        k[i] *= kernel_scale;
}

float4 EmbossPS(float4 pos : SV_Position, float2 uv : TexCoord) : SV_Target
{
    float3 base = GetColor(uv).rgb;
    float3 acc = 0;

    float k[9];
    LoadKernel(kernel_type, k);

    const float step = 0.001;

    for (int i = 0; i < 9; i++)
    {
        if (!IsSampleEnabled(i, direction_mode))
            continue;

        float2 sampleUV = clamp(uv + Offsets[i] * step, 0.0, 1.0);
        acc += GetColor(sampleUV).rgb * k[i];
    }

    float gray = dot(acc, float3(0.299, 0.587, 0.114));
    float edge = saturate(gray * edge_highlight_intensity);
    float3 embossed = gray + edge;

    float3 outColor = lerp(base, embossed, emboss_intensity);
    return float4(saturate(outColor), 1.0);
}

/*------------------.
| :: Techniques :: |
'------------------*/

technique EmbossFX
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = EmbossPS;
    }
}
