/*------------------.
| :: Description :: |
'-------------------/

Filmic Anamorph Sharpen PS (version 1.5.0)

Copyright:
This code © 2018-2023 Jakub Maximilian Fober
Some changes by ccritchfield https://github.com/ccritchfield

License:
This work is licensed under the Creative Commons
Attribution-ShareAlike 4.0 International License.
To view a copy of this license, visit
http://creativecommons.org/licenses/by-sa/4.0/
*/

/*--------------.
| :: Commons :: |
'--------------*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "ColorConversion.fxh"
#include "LinearGammaWorkflow.fxh"

/*-----------.
| :: Menu :: |
'-----------*/

uniform float Strength
<	__UNIFORM_SLIDER_FLOAT1
	ui_label = "强度";
	ui_min = 0.0; ui_max = 100.0; ui_step = 0.01;
> = 60.0;

uniform float Offset
<	__UNIFORM_SLIDER_FLOAT1
	ui_units = " 像素";
	ui_label = "半径";
	ui_tooltip = "高通交叉偏移（像素）";
	ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.1;

uniform float Clamp
<	__UNIFORM_SLIDER_FLOAT1
	ui_label = "限幅值";
	ui_min = 0.5; ui_max = 1.0; ui_step = 0.001;
> = 0.65;

uniform bool UseMask
<	__UNIFORM_INPUT_BOOL1
	ui_label = "仅锐化中心";
	ui_tooltip = "仅锐化图像中心区域";
> = false;

uniform bool DepthMask
<	__UNIFORM_INPUT_BOOL1
	ui_label = "启用深度边缘遮罩";
	ui_tooltip = "深度高通遮罩开关";
	ui_category = "深度遮罩";
	ui_category_closed = true;
> = false;

uniform int DepthMaskContrast
<	__UNIFORM_DRAG_INT1
	ui_label = "边缘遮罩强度";
	ui_tooltip = "深度高通遮罩强度";
	ui_category = "深度遮罩";
	ui_min = 0; ui_max = 2000; ui_step = 1;
> = 128;

uniform bool Preview
<	__UNIFORM_INPUT_BOOL1
	ui_label = "预览锐化层";
	ui_tooltip = "预览锐化层和遮罩以进行调整。\n"
		"如果您看不到红色笔触，\n"
		"请尝试在设置选项卡中更改预处理器定义。";
	ui_category = "调试视图";
	ui_category_closed = true;
> = false;

/*---------------.
| :: Textures :: |
'---------------*/

// Define screen texture with mirror tiles
sampler BackBuffer
{
	Texture = ReShade::BackBufferTex;
	AddressU = MIRROR;
	AddressV = MIRROR;
};

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
	return 2f*(MinA*MinB+MaxA+MaxB-MaxA*MaxB)-1.5;
}

// Overlay blending mode for one input
float Overlay(float LayerAB)
{
	float MinAB = min(LayerAB, 0.5);
	float MaxAB = max(LayerAB, 0.5);
	return 2f*(MinAB*MinAB+MaxAB+MaxAB-MaxAB*MaxAB)-1.5;
}

/*--------------.
| :: Shaders :: |
'--------------*/

// Sharpen pass
float3 FilmicAnamorphSharpenPS(
	float4 pos     : SV_Position,
	float2 UvCoord : TEXCOORD
) : SV_Target
{
	// Sample display image
	float3 Source = GammaConvert::to_linear(tex2D(BackBuffer, UvCoord).rgb);

	// Generate radial mask
	float Mask;
	if (UseMask)
	{
		// Generate radial mask
		Mask = 1f-length(UvCoord*2f-1f);
		Mask = Overlay(Mask) * Strength;
		// Bypass
		if (Mask<=0) return GammaConvert::to_display(Source);
	}
	else Mask = Strength;

	// Get pixel size
	float2 Pixel = BUFFER_PIXEL_SIZE;

	if (DepthMask)
	{
		/*
		// original
		float2 DepthPixel = Pixel*Offset+Pixel;
		Pixel *= Offset;
		*/

		// !!! calc pixel*offset once, use twice
		float2 PixelOffset = Pixel * Offset;
		float2 DepthPixel = PixelOffset + Pixel;
		Pixel = PixelOffset;

		// Sample display depth image
		float SourceDepth = ReShade::GetLinearizedDepth(UvCoord);

		float2 NorSouWesEst[4] = {
			float2(UvCoord.x, UvCoord.y + Pixel.y),
			float2(UvCoord.x, UvCoord.y - Pixel.y),
			float2(UvCoord.x + Pixel.x, UvCoord.y),
			float2(UvCoord.x - Pixel.x, UvCoord.y)
		};

		float2 DepthNorSouWesEst[4] = {
			float2(UvCoord.x, UvCoord.y + DepthPixel.y),
			float2(UvCoord.x, UvCoord.y - DepthPixel.y),
			float2(UvCoord.x + DepthPixel.x, UvCoord.y),
			float2(UvCoord.x - DepthPixel.x, UvCoord.y)
		};

		// Luma high-pass color
		// Luma high-pass depth
		float HighPassColor = 0f, DepthMask = 0f;

		[unroll]for(int s=0; s<4; s++)
		{
			HighPassColor +=
				ColorConvert::RGB_to_Luma(
					GammaConvert::to_linear(
						tex2D(BackBuffer, NorSouWesEst[s]).rgb
				));
			DepthMask +=
				 ReShade::GetLinearizedDepth(NorSouWesEst[s])
				+ReShade::GetLinearizedDepth(DepthNorSouWesEst[s]);
		}

		HighPassColor = 0.5-0.5*(HighPassColor*0.25-ColorConvert::RGB_to_Luma(Source));

		DepthMask = 1f-DepthMask*0.125+SourceDepth;
		DepthMask = min(1f, DepthMask)+1f-max(1f, DepthMask);
		DepthMask = saturate(DepthMaskContrast*DepthMask+1f-DepthMaskContrast);

		// Sharpen strength
		HighPassColor = lerp(0.5, HighPassColor, Mask*DepthMask);

		// Clamping sharpen
		/*
		// original
		HighPassColor = Clamp!=1f ? max(min(HighPassColor, Clamp), 1f-Clamp) : HighPassColor;
		*/

		// !!! Clamp in settings above is restricted to 0.5 to 1.0
		// !!! 1.0 - Clamp is the low value, while Clamp is the high value
		// !!! so we can literally just use the clamp() func instead of min/max.
		// !!! not sure if author was trying to take advantage of some kind of
		// !!! compiler "cheat" using min/max instead of clamp to improve
		// !!! performance. doesn't make sense to min/max otherwise.
		HighPassColor = Clamp!=1f ? clamp(HighPassColor, 1f-Clamp, Clamp ) : HighPassColor;

		float3 Sharpen = float3(
			Overlay(Source.r, HighPassColor),
			Overlay(Source.g, HighPassColor),
			Overlay(Source.b, HighPassColor)
		);

		if(Preview) // Preview mode ON
		{
			float PreviewChannel = lerp(HighPassColor, HighPassColor*DepthMask, 0.5);
			return
				GammaConvert::to_display(float3(
					1f-DepthMask * (1f-HighPassColor),
					PreviewChannel,
					PreviewChannel
				));
		}

		return GammaConvert::to_display(Sharpen);
	}
	else
	{
		Pixel *= Offset;

		float2 NorSouWesEst[4] = {
			float2(UvCoord.x, UvCoord.y + Pixel.y),
			float2(UvCoord.x, UvCoord.y - Pixel.y),
			float2(UvCoord.x + Pixel.x, UvCoord.y),
			float2(UvCoord.x - Pixel.x, UvCoord.y)
		};

		// Luma high-pass color
		float HighPassColor = 0f;
		[unroll] for(uint s=0u; s<4u; s++)
			HighPassColor +=
				ColorConvert::RGB_to_Luma(
					GammaConvert::to_linear(
						tex2D(BackBuffer, NorSouWesEst[s]).rgb
				));

		// !!! added space above to make it more obvious
		// !!! that loop is now a one-liner in this else branch
		// !!! where-as loop in branch above was multi-part
		HighPassColor = 0.5-0.5*(HighPassColor*0.25-ColorConvert::RGB_to_Luma(Source));

		// Sharpen strength
		HighPassColor = lerp(0.5, HighPassColor, Mask);

		// Clamping sharpen
		/*
		// original
		HighPassColor = Clamp!=1f ? max(min(HighPassColor, Clamp), 1f-Clamp) : HighPassColor;
		*/

		// !!! Clamp in settings above is restricted to 0.5 to 1.0
		// !!! 1.0 - Clamp is the low value, while Clamp is the high value
		// !!! so we can literally just use the clamp() func instead of min/max.
		// !!! not sure if author was trying to take advantage of some kind of
		// !!! compiler "cheat" using min/max instead of clamp to improve
		// !!! performance. doesn't make sense to min/max otherwise.
		HighPassColor = Clamp!=1f ? clamp(HighPassColor, 1f-Clamp, Clamp) : HighPassColor;

		float3 Sharpen = float3(
			Overlay(Source.r, HighPassColor),
			Overlay(Source.g, HighPassColor),
			Overlay(Source.b, HighPassColor)
		);

		return GammaConvert::to_display(
			Preview // preview mode ON
			? HighPassColor
			: Sharpen
		);
	}
}

/*-------------.
| :: Output :: |
'-------------*/

technique FilmicAnamorphSharpen
<
	ui_label = "电影变形锐化";
	ui_tooltip =
		"This effect © 2018-2023 Jakub Maksymilian Fober\n"
		"Licensed under CC BY-SA 4.0";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = FilmicAnamorphSharpenPS;
	}
}
