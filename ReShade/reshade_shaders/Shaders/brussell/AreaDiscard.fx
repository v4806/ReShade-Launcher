//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// AreaDiscard by brussell
// v. 1.1
// License: CC BY 4.0
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#ifndef Enable_RelativeCoordinates
#define Enable_RelativeCoordinates   0
#endif

#ifndef Enable_Coloring
#define Enable_Coloring   0
#endif

//effect parameters
uniform bool bAD_EnableArea <
      ui_label = "启用区域";
      ui_tooltip = "启用自定义矩形区域的丢弃/着色。";
> = false;

#if (Enable_RelativeCoordinates == 0)
uniform float2 fAD_AreaXY <
    ui_label = "区域坐标";
    ui_tooltip = "区域左上角的x和y坐标。";
    ui_type = "drag";
    ui_min = 1.0;
    ui_max = BUFFER_WIDTH;
    ui_step = 1.0;
> = float2(800, 200);

uniform float2 fAD_AreaSize <
    ui_label = "区域尺寸";
    ui_tooltip = "x和y方向的区域大小。";
    ui_type = "drag";
    ui_min = 1.0;
    ui_max = BUFFER_WIDTH;
    ui_step = 1.0;
> = float2(400, 300);
#else
uniform float2 fAD_AreaXY <
    ui_label = "区域坐标";
    ui_tooltip = "区域左上角的相对x和y坐标。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.0001;
> = float2(0.416, 0.185);

uniform float2 fAD_AreaSize <
    ui_label = "区域尺寸";
    ui_tooltip = "x和y方向的相对区域大小。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.0001;
> = float2(0.208, 0.278);
#endif

uniform bool bAD_EnableEdges <
      ui_label = "启用边缘";
      ui_tooltip = "启用屏幕边缘的丢弃/着色。";
> = true;

#if (Enable_RelativeCoordinates == 0)
uniform float fAD_EdgeLeftWidth <
    ui_label = "左边缘宽度";
    ui_tooltip = "左边缘宽度（像素）。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = BUFFER_WIDTH / 2;
    ui_step = 1.0;
> = 240;

uniform float fAD_EdgeRightWidth <
    ui_label = "右边缘宽度";
    ui_tooltip = "右边缘宽度（像素）。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = BUFFER_WIDTH / 2;
    ui_step = 1.0;
> = 240;

uniform float fAD_EdgeTopHeight <
    ui_label = "顶边缘高度";
    ui_tooltip = "顶边缘高度（像素）。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = BUFFER_HEIGHT / 2;
    ui_step = 1.0;
> = 0;

uniform float fAD_EdgeBottomHeight <
    ui_label = "底边缘高度";
    ui_tooltip = "底边缘高度（像素）。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = BUFFER_HEIGHT / 2;
    ui_step = 1.0;
> = 0;
#else
uniform float fAD_EdgeLeftWidth <
    ui_label = "左边缘宽度";
    ui_tooltip = "左边缘相对宽度。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 0.5;
    ui_step = 0.0001;
> = 0.125;

uniform float fAD_EdgeRightWidth <
    ui_label = "右边缘宽度";
    ui_tooltip = "右边缘相对宽度。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 0.5;
    ui_step = 0.0001;
> = 0.125;

uniform float fAD_EdgeTopHeight <
    ui_label = "顶边缘高度";
    ui_tooltip = "顶边缘相对高度。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 0.5;
    ui_step = 0.0001;
> = 0;

uniform float fAD_EdgeBottomHeight <
    ui_label = "底边缘高度";
    ui_tooltip = "底边缘相对高度。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 0.5;
    ui_step = 0.0001;
> = 0;
#endif

uniform float3 fAD_FillColor <
    ui_label = "区域/边缘填充颜色\n";
    ui_type = "color";
> = float3(0.0, 0.0, 0.0);

#include "ReShade.fxh"

//textures and samplers
#if (Enable_Coloring == 0)
texture texColorOrig { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
sampler ColorOrig { Texture = texColorOrig; };
#endif

//pixel shaders
#if (Enable_Coloring == 0)
float4 PS_AreaDiscard_StoreColor(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return tex2D(ReShade::BackBuffer, texcoord);
}
#endif

float4 PS_AreaDiscard(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 color = tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0, 0));

    #if (Enable_RelativeCoordinates == 0)
    float2 coord = vpos.xy + 1.0;
    float width = BUFFER_WIDTH;
    float height = BUFFER_HEIGHT;
    #else
    float2 coord = texcoord;
    float width = 1.0;
    float height = 1.0;
    #endif

    #if (Enable_Coloring == 0)
    float3 colorOrig =  tex2Dlod(ColorOrig, float4(texcoord, 0, 0)).xyz;
    #else
    float3 colorOrig = fAD_FillColor;
    #endif

    if (bAD_EnableArea) {
        if (coord.x >= fAD_AreaXY.x && coord.y >= fAD_AreaXY.y && coord.x <= (fAD_AreaXY + fAD_AreaSize).x && coord.y <= (fAD_AreaXY + fAD_AreaSize).y) {
            color.xyz = colorOrig;
        }
    }

    if (bAD_EnableEdges) {
        if (coord.x <= fAD_EdgeLeftWidth || coord.y <= fAD_EdgeTopHeight || coord.x > (width - fAD_EdgeRightWidth) || coord.y > (height - fAD_EdgeBottomHeight)) {
            color.xyz = colorOrig;
        }
    }

    return color;
}

//techniques
#if (Enable_Coloring == 0)
technique AreaDiscard_StoreColor
{
    pass {
        VertexShader = PostProcessVS;
        PixelShader = PS_AreaDiscard_StoreColor;
        RenderTarget = texColorOrig;
    }
}
#endif

technique AreaDiscard <
    ui_tooltip =    "AreaDiscard allows the definition of screen areas, where no effects should be active. Those\n"
                    "areas can be drawn black, colored or, like UIMask, with the restored image at a certain\n"
                    "point in the effect pipeline. The area(s) are a rectangle of arbitrary size or the screen\n"
                    "edges. Latter are useful to draw movie bars (top & bottom) or aspect bars (left & right).\n\n"
                    "Instructions:\n"
                    "Place \"AreaDiscard\" last in the load order and, optionally, \"AreaDiscard_StoreColor\"\n"
                    "before effects that shouldn't affect the discarded areas.\n\n\n"
                    "Preprocessor definitions:\n"
                    " Enable_Coloring:            Enable just the coloring of the discarded areas. This disables\n"
                    "                             the image restoration and the \"AreaDiscard_StoreColor technique.\n"
                    " Enable_RelativeCoordinates: Enable relative coordinates instead of absolute pixel coordinates.\n"
                    "                             This is useful for variable window sizes. Coordinate and dimension\n"
                    "                             values must be reset after changing this setting.\n"
                    ; >
{
    pass {
        VertexShader = PostProcessVS;
        PixelShader = PS_AreaDiscard;
    }
}
