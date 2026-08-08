/*------------------.
| :: Description :: |
'-------------------/

    Vertical Previewer and Composition (version 0.3)

    Authors: CeeJay.dk, seri14, Marot Satil, prod80, uchu suzume, originalnicodr
                    Composition https://github.com/Daodan317081/reshade-shaders
    License: MIT

    About:
    Show the preview rotated to the 90 degree angle on your screen to help you take vertical screenshot.
    Composition guides created by Daodan31708 are integrated and added new variations are built in.
    Can be used simply as a composition guide by turning off the preview.

    History:
    (*) Feature (+) Improvement (x) Bugfix (-) Information (!) Compatibility
    
    Version 0.3 Uchu Suzume & Marot Satil
    * Created by Uchu Suzume, with code optimization by Marot Satil.
	* Added an on/off toggle variable.
    * Added a feature to make this shader not visible in screenshots.
    * Added a guide showing thumbnail crop ratios for posting to social media.
	x Fixed a double include of ReShade.fxh.


	BSD 3-Clause License

	Composition.fx
	Copyright (c) 2018-2019, Alexander Federwisch
	All rights reserved.

	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are met:

	* Redistributions of source code must retain the above copyright notice, this
	list of conditions and the following disclaimer.

	* Redistributions in binary form must reproduce the above copyright notice,
	this list of conditions and the following disclaimer in the documentation
	and/or other materials provided with the distribution.

	* Neither the name of the copyright holder nor the names of its
	contributors may be used to endorse or promote products derived from
	this software without specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
	AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
	IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
	DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
	FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
	DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
	SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
	OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
	OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#define VP_GOLDEN_RATIO 1.6180339887
#define VP_INV_GOLDEN_RATIO  1.0 / 1.6180339887
#define VP_SILVER_RATIO 1.4142135623
#define VP_INV_SILVER_RATIO  1.0 / 1.4142135623

uniform bool VPreToggle <
    ui_text = "*** 此着色器的预览在截图中将被忽略 ***";
    ui_label = "切换预览开/关";
    ui_tooltip = "可以通过右键点击分配快捷键。";
> = false;

uniform int cLayerVPre_Angle <
    ui_type = "combo";
    ui_spacing = 1;
    ui_label = "垂直预览";
    ui_tooltip = "-90度: 向左旋转。\n"
                 " 90度: 向右旋转。\n";
    ui_items = "-90度\0"
               "  0度\0"
               " 90度\0"
               "180度\0"
               "禁用垂直预览\0";
> = 2;

uniform float cLayerVPre_Scale <
    ui_type = "slider";
    ui_label = "缩放";
    ui_tooltip = "0.75 将在16:9(FHD)比例下\n"
                 "垂直适应。";
    ui_min = 0.50; ui_max = 1.00;
    ui_step = 0.001;
> = 0.750;

uniform float cLayerVPre_PosX <
    ui_type = "slider";
    ui_label = "位置 X";
    ui_tooltip = "在UI被预览遮挡等情况下很有用。\n";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.001;
> = 0.500;

uniform float cLayerVPre_PosY <
    ui_type = "slider";
    ui_label = "位置 Y";
    ui_tooltip = "在预览干扰UI等情况下很有用。\n";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.001;
> = 0.500;

uniform int cLayerVPre_Composition <
    ui_type = "combo";
    ui_spacing = 1;
    ui_label = "构图线";
    ui_tooltip = "通过将主体/物体\n"
                 "定位在方格中心\n"
                 "或\n"
                 "对齐到线条或交叉点，\n"
                 "你的画面可能更加平衡。";
    ui_items = "关\0"
               "中心线\0"
               "三分法\0"
               "四分法\0"
               "五分法\0"
               "黄金比例\0"
               "白银比例\0"
               "对角线一\0"
               "对角线二\0"
               "黄金分割网格\0"
               "二分之一网格\0"
               "谐波骨架\0"
               "铁路员比例\0";
> = 2;

uniform float4 UIGridColor <
    ui_type = "color";
    ui_label = "网格颜色";
> = float4(1.0, 1.0, 1.0, 0.294);

uniform float UIGridLineWidth <
    ui_type = "slider";
    ui_label = "网格线宽度";
    ui_min = 0.0; ui_max = 5.0;
    ui_steps = 0.01;
> = 2.0;

uniform int cLayerVPre_CompositionARatio <
    ui_type = "combo";
    ui_spacing = 1;
    ui_label = "缩略图裁剪参考线";
    ui_tooltip = "显示Twitter和Instagram上\n"
                 "缩略图裁剪的参考线。\n"
                 "线条之间的区域将\n"
                 "反映到缩略图中。\n";
    ui_items = "关\0"
               "1.33 (Twitter上1张竖图)\0"
               "1.15 (Twitter上2张竖图)\0"
               "1.44 (3张帖子中后2张竖图)\0"
               "2.05 (Twitter上2张横图)\0"
               "1:1  (Instagram)\0";
> = 0;

uniform float4 UIGridColorARatio <
    ui_type = "color";
    ui_label = "网格颜色";
> = float4(0.686, 1.000, 0.196, 0.529);

uniform float UIGridLineWidthARatio <
    ui_type = "slider";
    ui_label = "网格线宽度";
    ui_min = 0.0; ui_max = 5.0;
    ui_steps = 0.01;
> = 2.5;

uniform float cLayer_Blend_BGFill <
    ui_type = "slider";
    ui_spacing = 1;
    ui_label = "背景填充";
    ui_tooltip = "-0.5 将填充黑色，\n"
                 "+0.5 将填充白色。";
    ui_min = -0.5; ui_max = 0.5;
    ui_step = 0.001;
> = 0.000;

// -------------------------------------
// Entrypoints
// -------------------------------------

#include "ReShade.fxh"

texture texDraw { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
texture texDrawARatio { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
texture texVPreOut { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };

sampler samplerDraw { Texture = texDraw; };
sampler samplerDrawARatio { Texture = texDrawARatio; };
sampler samplerVPreOut { Texture = texVPreOut; };

struct sctpoint {
    float3 color;
    float2 coord;
    float2 offset;
};

sctpoint NewPoint(float3 color, float2 offset, float2 coord) {
    sctpoint p;
    p.color = color;
    p.offset = offset;
    p.coord = coord;
    return p;
}

float3 DrawPoint(float3 texcolor, sctpoint p, float2 texCoord) {
    float2 pixelsize = BUFFER_PIXEL_SIZE * p.offset;
    
    if(p.coord.x == -1 || p.coord.y == -1)
        return texcolor;

    if(texCoord.x <= p.coord.x + pixelsize.x &&
    texCoord.x >= p.coord.x - pixelsize.x &&
    texCoord.y <= p.coord.y + pixelsize.y &&
    texCoord.y >= p.coord.y - pixelsize.y)
    return p.color;
    return texcolor;
}

float3 DrawCenterLines(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(0.5, texCoord.y));
    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 0.5));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineH1, texCoord);

    return result;
}

float3 DrawThirds(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / 3.0, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(2.0 / 3.0, texCoord.y));

    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 / 3.0));
    sctpoint lineH2 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 2.0 / 3.0));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineH1, texCoord);
    result = DrawPoint(result, lineH2, texCoord);

    return result;
}

float3 DrawFourth(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / 4.0, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(2.0 / 4.0, texCoord.y));
    sctpoint lineV3 = NewPoint(gridColor, lineWidth, float2(3.0 / 4.0, texCoord.y));

    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 / 4.0));
    sctpoint lineH2 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 2.0 / 4.0));
    sctpoint lineH3 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 3.0 / 4.0));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineV3, texCoord);
    result = DrawPoint(result, lineH1, texCoord);
    result = DrawPoint(result, lineH2, texCoord);
    result = DrawPoint(result, lineH3, texCoord);

    return result;
}

float3 DrawFifths(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / 5.0, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(2.0 / 5.0, texCoord.y));
    sctpoint lineV3 = NewPoint(gridColor, lineWidth, float2(3.0 / 5.0, texCoord.y));
    sctpoint lineV4 = NewPoint(gridColor, lineWidth, float2(4.0 / 5.0, texCoord.y));

    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 / 5.0));
    sctpoint lineH2 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 2.0 / 5.0));
    sctpoint lineH3 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 3.0 / 5.0));
    sctpoint lineH4 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 4.0 / 5.0));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineV3, texCoord);
    result = DrawPoint(result, lineV4, texCoord);
    result = DrawPoint(result, lineH1, texCoord);
    result = DrawPoint(result, lineH2, texCoord);
    result = DrawPoint(result, lineH3, texCoord);
    result = DrawPoint(result, lineH4, texCoord);

    return result;
}

float3 DrawGoldenRatio(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / VP_GOLDEN_RATIO, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(1.0 - 1.0 / VP_GOLDEN_RATIO, texCoord.y));

    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 / VP_GOLDEN_RATIO));
    sctpoint lineH2 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 - 1.0 / VP_GOLDEN_RATIO));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineH1, texCoord);
    result = DrawPoint(result, lineH2, texCoord);

    return result;
}

float3 DrawSilverRatio(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / VP_SILVER_RATIO, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(1.0 - 1.0 / VP_SILVER_RATIO, texCoord.y));

    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 / VP_SILVER_RATIO));
    sctpoint lineH2 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 - 1.0 / VP_SILVER_RATIO));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineH1, texCoord);
    result = DrawPoint(result, lineH2, texCoord);

    return result;
}

float3 DrawDiagonalsOne(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint line1 = NewPoint(gridColor, lineWidth + 1.0, float2(texCoord.x, texCoord.x));
    sctpoint line2 = NewPoint(gridColor, lineWidth + 1.0, float2(texCoord.x, 1.0 - texCoord.x));
    
    result = DrawPoint(background, line1, texCoord);
    result = DrawPoint(result, line2, texCoord);

    return result;
}

float3 DrawDiagonalsTwo(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    float slope = 1.50;

    sctpoint line1 = NewPoint(gridColor, lineWidth + 1.0, float2(texCoord.x, texCoord.x * slope));
    sctpoint line2 = NewPoint(gridColor, lineWidth + 1.0, float2(texCoord.x, 1.0 - texCoord.x * slope));
    sctpoint line3 = NewPoint(gridColor, lineWidth + 1.0, float2(texCoord.x, (1.0 - texCoord.x) * slope));
    sctpoint line4 = NewPoint(gridColor, lineWidth + 1.0, float2(texCoord.x, texCoord.x * slope + 1.0 - slope));

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / 3.0, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(2.0 / 3.0, texCoord.y));

    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 / 3.0));
    sctpoint lineH2 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 2.0 / 3.0));

    result = DrawPoint(background, line1, texCoord);
    result = DrawPoint(result, line2, texCoord);
    result = DrawPoint(result, line3, texCoord);
    result = DrawPoint(result, line4, texCoord);
    result = DrawPoint(result, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineH1, texCoord);
    result = DrawPoint(result, lineH2, texCoord);

    return result;
}

float3 DrawGoldenSection(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint line1 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, texCoord.x));
    sctpoint line2 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x,1.0 - texCoord.x));

    float slope = pow(VP_GOLDEN_RATIO, 2);

    sctpoint line3 = NewPoint(gridColor, lineWidth + 2.0, float2(texCoord.x, texCoord.x * slope));
    sctpoint line4 = NewPoint(gridColor, lineWidth + 2.0, float2(texCoord.x, 1.0 - texCoord.x * slope));

    sctpoint line5 = NewPoint(gridColor, lineWidth + 2.0, float2(texCoord.x, (1.0 - texCoord.x) * slope));
    sctpoint line6 = NewPoint(gridColor, lineWidth + 2.0, float2(texCoord.x, texCoord.x * slope + 1.0 - slope));

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / VP_GOLDEN_RATIO, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(1.0 - 1.0 / VP_GOLDEN_RATIO, texCoord.y));

    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 / VP_GOLDEN_RATIO));
    sctpoint lineH2 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 - 1.0 / VP_GOLDEN_RATIO));

    result = DrawPoint(background, line1, texCoord);
    result = DrawPoint(result, line2, texCoord);
    result = DrawPoint(result, line3, texCoord);
    result = DrawPoint(result, line4, texCoord);
    result = DrawPoint(result, line5, texCoord);
    result = DrawPoint(result, line6, texCoord);
    result = DrawPoint(result, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineH1, texCoord);
    result = DrawPoint(result, lineH2, texCoord);
    
    return result;
}

float3 DrawOneHalfRectangle(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint line1 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, texCoord.x));
    sctpoint line2 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, 1.0 - texCoord.x));

    float slope = pow(1.5, 2);

    sctpoint line3 = NewPoint(gridColor, lineWidth + 2.0, float2(texCoord.x, texCoord.x * slope));
    sctpoint line4 = NewPoint(gridColor, lineWidth + 2.0, float2(texCoord.x, 1.0 - texCoord.x * slope));

    sctpoint line5 = NewPoint(gridColor, lineWidth + 2.0, float2(texCoord.x, (1.0 - texCoord.x) * slope));
    sctpoint line6 = NewPoint(gridColor, lineWidth + 2.0, float2(texCoord.x, texCoord.x * slope + 1.0 - slope));

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / 1.8, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(1.0 - 1.0 / 1.8, texCoord.y));

    sctpoint lineH1 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 / 1.8));
    sctpoint lineH2 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 - 1.0 /1.8));

    result = DrawPoint(background, line1, texCoord);
    result = DrawPoint(result, line2, texCoord);
    result = DrawPoint(result, line3, texCoord);
    result = DrawPoint(result, line4, texCoord);
    result = DrawPoint(result, line5, texCoord);
    result = DrawPoint(result, line6, texCoord);
    result = DrawPoint(result, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineH1, texCoord);
    result = DrawPoint(result, lineH2, texCoord);
    
    return result;
}

float3 DrawHarmonicArmature(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint line1 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, texCoord.x));
    sctpoint line2 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x,1.0 - texCoord.x));

    float slope1 = 0.5;

    sctpoint line3 = NewPoint(gridColor, lineWidth, float2(texCoord.x, texCoord.x * slope1));
    sctpoint line4 = NewPoint(gridColor, lineWidth, float2(texCoord.x, 1.0 - texCoord.x * slope1));

    sctpoint line5 = NewPoint(gridColor, lineWidth, float2(texCoord.x, (1.0 - texCoord.x) * slope1));
    sctpoint line6 = NewPoint(gridColor, lineWidth, float2(texCoord.x, texCoord.x * slope1 + 1.0 - slope1));

    float slope2 = 1.5;
    
    sctpoint line7 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, texCoord.x * slope2));
    sctpoint line8 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, 1.0 - texCoord.x * slope2));

    sctpoint line9 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, (1.0 - texCoord.x) * slope2));
    sctpoint line10 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, texCoord.x * slope2 + 1.0 - slope2));

    result = DrawPoint(background, line1, texCoord);
    result = DrawPoint(result, line2, texCoord);
    result = DrawPoint(result, line3, texCoord);
    result = DrawPoint(result, line4, texCoord);
    result = DrawPoint(result, line5, texCoord);
    result = DrawPoint(result, line6, texCoord);
    result = DrawPoint(result, line7, texCoord);
    result = DrawPoint(result, line8, texCoord);
    result = DrawPoint(result, line9, texCoord);
    result = DrawPoint(result, line10, texCoord);
    
    return result;
}

float3 DrawRailmanRatio(float3 background, float3 gridColor, float lineWidth, float2 texCoord) {
    float3 result;

    sctpoint line1 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, texCoord.x));
    sctpoint line2 = NewPoint(gridColor, lineWidth + 0.6, float2(texCoord.x, 1.0 - texCoord.x));

    sctpoint lineV1 = NewPoint(gridColor, lineWidth, float2(1.0 / 4.0, texCoord.y));
    sctpoint lineV2 = NewPoint(gridColor, lineWidth, float2(2.0 / 4.0, texCoord.y));
    sctpoint lineV3 = NewPoint(gridColor, lineWidth, float2(3.0 / 4.0, texCoord.y));

    result = DrawPoint(background, line1, texCoord);
    result = DrawPoint(result, line2, texCoord);
    result = DrawPoint(result, lineV1, texCoord);
    result = DrawPoint(result, lineV2, texCoord);
    result = DrawPoint(result, lineV3, texCoord);

    return result;
}

void PS_DrawLine(in float4 pos : SV_Position, float2 texCoord : TEXCOORD, out float4 passColor : SV_Target) {
    const float4 backColor = tex2D(ReShade::BackBuffer, texCoord);
        switch(cLayerVPre_Composition)
        {
            default:
                passColor = float4(backColor.rgb, backColor.a);
                break;
            case 1:
                const float3 VPreCenter = DrawCenterLines(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreCenter.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 2:
                const float3 VPreThirds = DrawThirds(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreThirds.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 3:
                const float3 VPreFourth = DrawFourth(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreFourth.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 4:
                const float3 VPreFifths = DrawFifths(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreFifths.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 5:
                const float3 VPreGolden = DrawGoldenRatio(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreGolden.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 6:
                const float3 VPreSilver = DrawSilverRatio(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreSilver.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 7:
                const float3 VPreDiagonalsOne = DrawDiagonalsOne(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreDiagonalsOne.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 8:
                const float3 VPreDiagonalsTwo = DrawDiagonalsTwo(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreDiagonalsTwo.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 9:
                const float3 VPreGoldenSection = DrawGoldenSection(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreGoldenSection.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 10:
                const float3 VPreOneHalfRectangle = DrawOneHalfRectangle(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreOneHalfRectangle.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 11:
                const float3 VPreHarmonicArmature = DrawHarmonicArmature(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreHarmonicArmature.rgb, UIGridColor.w).rgb, backColor.a);
                break;
            case 12:
                const float3 VPreRailman = DrawRailmanRatio(backColor.rgb, UIGridColor.rgb, UIGridLineWidth, texCoord);
                passColor = float4(lerp(backColor.rgb, VPreRailman.rgb, UIGridColor.w).rgb, backColor.a);
                break;
        }
}

float3 DrawLineARatio(float3 background, float3 gridColorARatio, float lineWidthARatio, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 0.25, texCoord.y));
    sctpoint lineH1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 1.75, texCoord.y));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineH1, texCoord);

    return result;
}

float3 DrawLineARatio_2(float3 background, float3 gridColorARatio, float lineWidthARatio, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 0.35, texCoord.y));
    sctpoint lineH1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 1.65, texCoord.y));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineH1, texCoord);

    return result;
}

float3 DrawLineARatio_3(float3 background, float3 gridColorARatio, float lineWidthARatio, float2 texCoord) {
    float3 result;
    
    sctpoint lineV1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 0.69, texCoord.y));
    sctpoint lineH1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 1.31, texCoord.y));

    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineH1, texCoord);

    return result;
}

float3 DrawLineARatio_4(float3 background, float3 gridColorARatio, float lineWidthARatio, float2 texCoord) {
    float3 result;

    sctpoint lineV1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 0.514, texCoord.y));
    sctpoint lineH1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 1.486, texCoord.y));
    
    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineH1, texCoord);

    return result;
}

float3 DrawLineARatio_5(float3 background, float3 gridColorARatio, float lineWidthARatio, float2 texCoord) {
    float3 result;
    
    sctpoint lineV1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 0.5, texCoord.y));
    sctpoint lineH1 = NewPoint(gridColorARatio, lineWidthARatio, float2(((BUFFER_WIDTH / BUFFER_HEIGHT) * 0.5) * 1.5, texCoord.y));

    result = DrawPoint(background, lineV1, texCoord);
    result = DrawPoint(result, lineH1, texCoord);

    return result;
}

void PS_DrawLineARatio(in float4 pos : SV_Position, float2 texCoord : TEXCOORD, out float4 passColor : SV_Target) {
    const float4 backColor = tex2D(samplerDraw, texCoord);
        switch(cLayerVPre_CompositionARatio)
        {
            default:
                passColor = float4(backColor.rgb, backColor.a);
                break;
            case 1:
                const float3 DrawLineARatio = DrawLineARatio(backColor.rgb, UIGridColorARatio.rgb, UIGridLineWidthARatio, texCoord);
                passColor = float4(lerp(backColor.rgb, DrawLineARatio.rgb, UIGridColorARatio.w).rgb, backColor.a);
                break;
            case 2:
                const float3 DrawLineARatio_2 = DrawLineARatio_2(backColor.rgb, UIGridColorARatio.rgb, UIGridLineWidthARatio, texCoord);
                passColor = float4(lerp(backColor.rgb, DrawLineARatio_2.rgb, UIGridColorARatio.w).rgb, backColor.a);
                break;
            case 3:
                const float3 DrawLineARatio_3 = DrawLineARatio_3(backColor.rgb, UIGridColorARatio.rgb, UIGridLineWidthARatio, texCoord);
                passColor = float4(lerp(backColor.rgb, DrawLineARatio_3.rgb, UIGridColorARatio.w).rgb, backColor.a);
                break;
            case 4:
                const float3 DrawLineARatio_4 = DrawLineARatio_4(backColor.rgb, UIGridColorARatio.rgb, UIGridLineWidthARatio, texCoord);
                passColor = float4(lerp(backColor.rgb, DrawLineARatio_4.rgb, UIGridColorARatio.w).rgb, backColor.a);
                break;
            case 5:
                const float3 DrawLineARatio_5 = DrawLineARatio_5(backColor.rgb, UIGridColorARatio.rgb, UIGridLineWidthARatio, texCoord);
                passColor = float4(lerp(backColor.rgb, DrawLineARatio_5.rgb, UIGridColorARatio.w).rgb, backColor.a);
                break;
        }
}

float3 bri(float3 backColor, float x)
{
    //screen
    const float3 c = 1.0f - ( 1.0f - backColor.rgb ) * ( 1.0f - backColor.rgb );
    if (x < 0.0f) {
        x = x * 0.5f;
    }
    return saturate( lerp( backColor.rgb, c.rgb, x ));   
}

void PS_VPreOut(in float4 pos : SV_Position, float2 texCoord : TEXCOORD, out float4 passColor : SV_Target) {
    if (VPreToggle) {
        passColor = tex2D(ReShade::BackBuffer, texCoord);
    }
    else {
    const float3 pivot = float3(0.5, 0.5, 0.0);
    const float3 mulUV = float3(texCoord.x, texCoord.y, 1);
    const float2 ScaleSize = (float2(BUFFER_WIDTH, BUFFER_HEIGHT) * cLayerVPre_Scale / BUFFER_SCREEN_SIZE);
    const float AspectX = 1.0 - BUFFER_WIDTH * (1.0 / BUFFER_HEIGHT);
    const float AspectY = 1.0 - BUFFER_HEIGHT * (1.0 / BUFFER_WIDTH);
    const float ScaleX =  ScaleSize.x * AspectX * cLayerVPre_Scale;
    const float ScaleY =  ScaleSize.y * AspectY * cLayerVPre_Scale;

    float Rotate = 0;
        switch(cLayerVPre_Angle)
        {
            case 0:
                Rotate = -90.0 * (3.1415926 / 180.0);
                break;
            case 1:
                Rotate = 0;
                break;
            case 2:
                Rotate = 90.0 * (3.1415926 / 180.0);
                break;
            case 3:
                Rotate = 180 * (3.1415926 / 180.0);
                break;
            case 4:
                Rotate = 0;
                break;
        }

    const float3x3 positionMatrix = float3x3 (
        1, 0, 0,
        0, 1, 0,
        -cLayerVPre_PosX, -cLayerVPre_PosY, 1
    );


    const float3x3 scaleMatrix = float3x3 (
        1/ScaleX, 0, 0,
        0,  1/ScaleY, 0,
        0, 0, 1
    );

    const float3x3 rotateMatrix = float3x3 (
       (cos (Rotate) * AspectX), (sin(Rotate) * AspectX), 0,
       (-sin(Rotate) * AspectY), (cos(Rotate) * AspectY), 0,
        0, 0, 1
    );

    float3 SumUV = mul (mul (mul (mulUV, positionMatrix), rotateMatrix), scaleMatrix);
    float4 backColor = tex2D(samplerDrawARatio, texCoord);
        switch (cLayerVPre_Angle) {
            default:
                const float4 Void = float4(0.0, 0.0, 0.0, 1.0) * all(SumUV + pivot == saturate(SumUV + pivot));
                const float4 VPreOut = tex2D(samplerDrawARatio, SumUV.rg + pivot.rg) * all(SumUV + pivot == saturate(SumUV + pivot));
                const float FillValue = cLayer_Blend_BGFill + 0.5;
                if (cLayer_Blend_BGFill != 0.0f) {
                    backColor.rgb = lerp(2 * backColor.rgb * FillValue, 1.0 - 2 * (1.0 - backColor.rgb) * (1.0 - FillValue), step(0.5, FillValue));
                }
                passColor = VPreOut + lerp(backColor, Void, Void.a);
                break;
            case 4:
                passColor = backColor;
                break;
        }
    }
}

// -------------------------------------
// Techniques
// -------------------------------------

technique Vertical_Previewer <
ui_label = "Vertical Previewer and Composition (Hidden In Screenshots)";
enabled_in_screenshot = false;
ui_tooltip = "+++ Vertical Previewer and Composition +++\n"
                     "By showing a preview on the screen to protect\n"
                     "your neck while taking vertical screenshots.\n\n"
                     "      Can be used as a composition guide\n"
                     "   or a small preview window overlooking\n"
                     "     whole screen with your preference.\n\n"
                     "     Recommend adding to your hotkeys\n"
                     " by right click from here for easy access."; >
{
    pass pass0
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_DrawLine;
        RenderTarget = texDraw;
    }
    pass pass1
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_DrawLineARatio;
        RenderTarget = texDrawARatio;
    }
    pass pass2
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_VPreOut;
    }

}

technique Vertical_Previewer_S <
ui_label = "Vertical Previewer and Composition (Visible In Screenshots)";
ui_tooltip = "+++ Vertical Previewer and Composition +++\n"
                     "***バーチカル プレビュワー アンド コンポジション***\n\n"
                     "By showing a preview on the screen to protect\n"
                     "your neck while taking vertical screenshots.\n\n"
                     "      Can be used as a composition guide\n"
                     "   or a small preview window overlooking\n"
                     "     whole screen with your preference.\n\n"
                     "     Recommend adding to your hotkeys\n"
                     " by right click from here for easy access."; >
{
    pass pass0
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_DrawLine;
        RenderTarget = texDraw;
    }
    pass pass1
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_DrawLineARatio;
        RenderTarget = texDrawARatio;
    }
    pass pass2
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_VPreOut;
    }

}
