//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// AreaCopy by brussell
// v. 1.23
// License: CC BY 4.0
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

//effect parameters
uniform float2 fAC_SourceXY <
    ui_label = "源坐标";
    ui_tooltip = "源区域左上角的x和y坐标。";
    ui_type = "drag";
    ui_min = 1.0;
    ui_max = BUFFER_WIDTH;
    ui_step = 1.0;
> = float2(600, 100);

uniform float2 fAC_DestXY <
    ui_label = "目标坐标";
    ui_tooltip = "目标区域左上角的x和y坐标。";
    ui_type = "drag";
    ui_min = 1.0;
    ui_max = BUFFER_WIDTH;
    ui_step = 1.0;
> = float2(1200, 600);

uniform float2 fAC_Size <
    ui_label = "区域尺寸";
    ui_tooltip = "x和y方向的区域大小。";
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = BUFFER_WIDTH;
    ui_step = 1.0;
> = float2(400, 300);

uniform float fAC_DestOpacity <
    ui_label = "目标不透明度";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.05;
> = 1.0;

uniform float fAC_Zoom <
    ui_label = "目标缩放";
    ui_tooltip = "目标区域的缩放强度。";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 20.0;
    ui_step = 0.05;
> = 1.0;

uniform float fAC_DestAngle <
    ui_label = "目标旋转";
    ui_tooltip = "目标区域的旋转角度。";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 360;
    ui_step = 15.0;
> = 0;

uniform bool bAC_EnableDestOutline <
      ui_label = "启用目标轮廓";
      ui_tooltip = "在目标区域周围绘制轮廓。";
> = true;

uniform float fAC_DestOutlineWidth <
    ui_label = "轮廓宽度";
    ui_tooltip = "目标区域轮廓宽度（像素）。";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 30.0;
    ui_step = 1.0;
> = 2.0;

uniform float fAC_DestOutlineOpacity <
    ui_label = "轮廓不透明度";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.05;
> = 1.0;

uniform float3 fAC_DestOutlineColor <
    ui_label = "轮廓颜色";
    ui_type = "color";
> = float3(1.0, 1.0, 1.0);

uniform bool bAC_EnableSourceColorFill <
      ui_label = "启用源颜色填充";
      ui_tooltip = "用下面指定的颜色填充源区域。";
> = true;

uniform float3 fAC_SourceFillColor <
    ui_label = "填充颜色";
    ui_type = "color";
> = float3(0.0, 0.0, 0.0);

uniform float fAC_SourceOpacity <
    ui_label = "填充颜色不透明度";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.05;
> = 0.5;

#include "ReShade.fxh"

//pixel shaders
float4 PS_AreaCopy(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float2 pos = vpos.xy + 1.0;
    float4 color = tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0, 0));
    float4 colorBackup = color;
    float2 areaCenter = fAC_Size / 2.0;
    float sine, cosine;
    float2 sourceCenterCoord;

    float2 destPos = (pos.xy - fAC_DestXY - areaCenter) / fAC_Zoom + fAC_SourceXY + areaCenter;
    float2 destCoord = destPos * ReShade::PixelSize;

    float2 sourceTopLeft = fAC_SourceXY;
    float2 sourceBottomRight = fAC_SourceXY + fAC_Size;
    float2 destTopLeft = fAC_DestXY;
    float2 destBottomRight = fAC_DestXY + fAC_Size;

    if (fAC_DestAngle != 0) {
        sine = sin(radians(-fAC_DestAngle));
        cosine = cos(radians(-fAC_DestAngle));
        sourceCenterCoord = (fAC_SourceXY + areaCenter) * ReShade::PixelSize;

        destCoord -= sourceCenterCoord;
        destCoord.x *= ReShade::AspectRatio;
        destCoord = float2(cosine * destCoord.x - sine * destCoord.y, cosine * destCoord.y + sine * destCoord.x);
        destCoord.x /= ReShade::AspectRatio;
        destCoord += sourceCenterCoord;
    }

    float4 colorDest= tex2Dlod(ReShade::BackBuffer, float4(destCoord, 0, 0));

    if (bAC_EnableSourceColorFill) {
        if (pos.x >= sourceTopLeft.x && pos.y >= sourceTopLeft.y && pos.x <= sourceBottomRight.x && pos.y <= sourceBottomRight.y) {
            color.xyz = lerp(color.xyz, fAC_SourceFillColor, fAC_SourceOpacity);
        }
    }

    if (bAC_EnableDestOutline) {
        if (pos.x >= (destTopLeft.x - fAC_DestOutlineWidth) && pos.y >= (destTopLeft.y - fAC_DestOutlineWidth) && pos.x <= (destBottomRight.x + fAC_DestOutlineWidth) && pos.y <= (destBottomRight.y + fAC_DestOutlineWidth)) {
            color.xyz = lerp(color.xyz, fAC_DestOutlineColor, fAC_DestOutlineOpacity);
        }
    }

    if (pos.x >= destTopLeft.x && pos.y >= destTopLeft.y && pos.x <= destBottomRight.x && pos.y <= destBottomRight.y) {
        color.xyz = lerp(colorBackup.xyz, colorDest.xyz, fAC_DestOpacity);
    }

    return color;
}

//techniques
technique AreaCopy <
    ui_tooltip =    "AreaCopy allows the duplication of a screen area (rectangle) to another part of the screen\n"
                    "The copied area (destination area) can be rotated or zoomed in, with arbitrary opacity.\n"
                    "It's also possible to set the source and destination coordinates to the same values, if just\n"
                    "a zoom or rotation of a specific area is desired."
                    ; >
{
    pass {
        VertexShader = PostProcessVS;
        PixelShader = PS_AreaCopy;
    }
}
