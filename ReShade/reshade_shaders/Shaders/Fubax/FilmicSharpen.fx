/*------------------.
| :: Description :: |
'-------------------/

Filmic Sharpen PS (version 1.5.0)

Copyright:
This code © 2018-2023 Jakub Maximilian Fober

License:
This work is licensed under the Creative Commons
Attribution-ShareAlike 4.0 International License.
To view a copy of this license, visit
http://creativecommons.org/licenses/by-sa/4.0/

For updates visit GitHub repository at
https://github.com/Fubaxiusz/fubax-shaders

Contact:
jakub.m.fober@protonmail.com
*/

/*--------------.
| :: Commons :: |
'--------------*/

#include "ReShadeUI.fxh"
#include "ReShade.fxh"
#include "ColorConversion.fxh"
#include "BlueNoiseDither.fxh"

/*-----------.
| :: Menu :: |
'-----------*/

uniform uint Strength
<	__UNIFORM_SLIDER_INT1
	ui_label = "强度";
	ui_min = 1u; ui_max = 64u;
> = 32u;

uniform float Offset
<	__UNIFORM_SLIDER_FLOAT1
	ui_units = " 像素";
	ui_label = "半径";
	ui_tooltip = "高通交叉偏移像素";
	ui_min = 0.05; ui_max = 0.25; ui_step = 0.01;
> = 0.1;

uniform bool UseMask
<	__UNIFORM_INPUT_BOOL1
	ui_label = "仅锐化中心";
	ui_tooltip = "仅锐化图像中心区域";
> = false;

uniform float Clamp
<	__UNIFORM_SLIDER_FLOAT1
	ui_label = "高光限制";
	ui_min = 0.5; ui_max = 1.0; ui_step = 0.1;
	ui_category = "附加设置";
	ui_category_closed = true;
> = 0.6;

uniform bool Preview
<	__UNIFORM_INPUT_BOOL1
	ui_label = "预览锐化层";
	ui_tooltip = "预览锐化层和遮罩以进行调整。\n"
		"如果您看不到红色笔触，\n"
		"请尝试在设置选项卡中更改预处理器定义。";
	ui_category = "调试视图";
	ui_category_closed = true;
> = false;

/*----------------.
| :: Functions :: |
'----------------*/

// Overlay blending mode
float Overlay(float LayerA, float LayerB)
{
	float MinA = min(LayerA, 0.5);
	float MinB = min(LayerB, 0.5);
	float MaxA = max(LayerA, 0.5);
	float MaxB = max(LayerB, 0.5);
	return 2f*((MinA*MinB+MaxA)+(MaxB-MaxA*MaxB))-1.5;
}

/*--------------.
| :: Shaders :: |
'--------------*/

// Sharpen pass
void FilmicSharpenPS(
	float4 pixelPos  : SV_Position,
	float2 UvCoord   : TEXCOORD,
	out float3 color : SV_Target
)
{
	// Sample display image
	color = tex2D(ReShade::BackBuffer, UvCoord).rgb;

	// Generate and apply radial mask
	float Mask;
	if (UseMask)
	{
		// Center coordinates
		float2 viewCoord = UvCoord*2f-1f;
		// Correct aspect
		viewCoord.y *= BUFFER_HEIGHT*BUFFER_RCP_WIDTH;
		// Generate radial mask
		Mask = Strength-min(dot(viewCoord, viewCoord), 1f)*Strength;
	}
	else Mask = Strength;

	// Get pixel size
	float2 Pixel = BUFFER_PIXEL_SIZE*Offset;

	// Sampling coordinates
	float2 NorSouWesEst[4] = {
		float2(UvCoord.x, UvCoord.y+Pixel.y),
		float2(UvCoord.x, UvCoord.y-Pixel.y),
		float2(UvCoord.x+Pixel.x, UvCoord.y),
		float2(UvCoord.x-Pixel.x, UvCoord.y)
	};

	// Luma high-pass
	float HighPass = 0f;
	[unroll] for(uint i=0u; i<4u; i++)
		HighPass += ColorConvert::RGB_to_Luma(tex2D(ReShade::BackBuffer, NorSouWesEst[i]).rgb);

	HighPass = 0.5-0.5*(HighPass*0.25-ColorConvert::RGB_to_Luma(color));

	// Sharpen strength
	HighPass = lerp(0.5, HighPass, Mask);

	// Clamp sharpening
	HighPass = Clamp!=1f? clamp(HighPass, 1f-Clamp, Clamp) : HighPass;

	// Choose output
	if (Preview) color = HighPass;
	else
	{
		[unroll] for(uint i=0u; i<3u; i++)
			// Apply sharpening
			color[i] = Overlay(color[i], HighPass);
	}

	// Dither final 8/10-bit result
	color = BlueNoise::dither(color, uint2(pixelPos.xy));
}

/*-------------.
| :: Output :: |
'-------------*/

technique FilmicSharpen
<
	ui_label = "电影锐化";
	ui_tooltip =
		"此效果 © 2018-2023 Jakub Maksymilian Fober\n"
		"基于 CC BY-SA 4.0 许可";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = FilmicSharpenPS;
	}
}
