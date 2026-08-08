///////////////////////////////////////////////////////////////////////////////////
// pPalettePosterize.fx by Gimle Larpes
// Posterizes an image to a custom color palette.
///////////////////////////////////////////////////////////////////////////////////

#define P_OKLAB_VERSION_REQUIRE 100
#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//Clamp invnorm factor to prevent fp precision errors
#ifndef _POSTERIZE_MAX_INVNORM_FACTOR
	#define _POSTERIZE_MAX_INVNORM_FACTOR 12.5 //1000 nits
#endif

uniform int PaletteType < __UNIFORM_RADIO_INT1
	ui_label = "调色板";
	ui_tooltip = "使用的调色板类型";
	ui_items = "单色\0类似色\0互补色\0三色\0全部颜色\0";
	ui_category = "设置";
> = 2;
uniform float3 BaseColor < __UNIFORM_COLOR_FLOAT3
	ui_label = "基础颜色";
	ui_tooltip = "用于计算其他颜色的基础颜色";
	ui_category = "设置";
> = float3(0.52, 0.05, 0.05);
uniform int NumColors < __UNIFORM_SLIDER_INT1
	ui_label = "颜色数量";
	ui_min = 2; ui_max = 16;
	ui_tooltip = "色调分离的颜色数量";
	ui_category = "设置";
> = 4;
uniform float PaletteBalance < __UNIFORM_SLIDER_FLOAT1
	ui_label = "调色板平衡";
	ui_min = 0.001; ui_max = 1.0;
	ui_tooltip = "调整调色板的阈值";
	ui_category = "设置";
> = 0.5;
uniform float DitheringFactor < __UNIFORM_SLIDER_FLOAT1
	ui_label = "抖动";
	ui_min = 0.0; ui_max = 0.1;
	ui_tooltip = "应用的抖动量";
	ui_category = "设置";
> = 0.02;
uniform bool DesaturateHighlights <
	ui_type = "bool";
	ui_label = "降低高光饱和度";
	ui_tooltip = "创建更柔和的图像";
	ui_category = "设置";
> = false;
uniform float DesaturateFactor < __UNIFORM_SLIDER_FLOAT1
	ui_label = "降低饱和度量";
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "高光降低饱和度的程度";
	ui_category = "设置";
> = 0.75;
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "快速色彩空间转换";
	ui_tooltip = "使用不太精确的近似值代替完整的转换函数";
	ui_category = "性能";
> = false;


//2x2 Bayer
static const int bayer[2 * 2] = {
	0, 2,
	3, 1
};

float3 PosterizeDitherPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	static const float PI = 3.1415927;

	static const float INVNORM_FACTOR = min(Oklab::INVNORM_FACTOR, _POSTERIZE_MAX_INVNORM_FACTOR);
	static const float HDR_PAPER_WHITE = Oklab::HDR_PAPER_WHITE;

	static const float3 BaseColor = Oklab::RGB_to_LCh(BaseColor);
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_LCh(color)
		: Oklab::DisplayFormat_to_LCh(color);


	//Dithering
	float m;
	if (DitheringFactor != 0.0)
	{
		int2 xy = int2(texcoord * ReShade::ScreenSize) % 2;
		m = (bayer[xy.x + 2 * xy.y] * 0.25 - 0.5) * INVNORM_FACTOR * DitheringFactor;
	}
	else
	{
		m = 0.0;
	}

	float luminance = color.r + m;
	float adapted_luminance = (Oklab::IS_HDR) ? min(2.0 * luminance / HDR_PAPER_WHITE, 1.0) : luminance;
	static const float PW_COMPENSATION = 2.2 - HDR_PAPER_WHITE / INVNORM_FACTOR;
	static const float PALETTE_CONTROL = PW_COMPENSATION * PaletteBalance;
	float hue_range;
	float hue_offset = 0.0;
	
	switch (PaletteType)
	{
		case 0: //Monochrome
		{
			hue_range = 0.0;
		} break;
		case 1: //Analogous
		{
			hue_range = PI/2.0;
		} break;
		case 2: //Complementary
		{
			hue_range = PI/2.0;
			hue_offset = (adapted_luminance > 0.5 * PALETTE_CONTROL)
				? PI*0.75
				: 0.0;
		} break;
		case 3: //Triadic
		{
			hue_range = PI/2.0;
			hue_offset = (adapted_luminance > 0.33 * PALETTE_CONTROL)
				? PI*0.4167 * floor(adapted_luminance * 3.0 / PALETTE_CONTROL)
				: 0.0;
		} break;
		case 4: //All colors
		{
			hue_range = PI*2.0;
		} break;
	}

	color.r = ceil(luminance * NumColors) / NumColors;
	color.g = (DesaturateHighlights)
		? BaseColor.g * (1.0 - (adapted_luminance * adapted_luminance) * DesaturateFactor)
		: BaseColor.g;
	color.b = BaseColor.b + (color.r - rcp(NumColors)) * hue_range + hue_offset;
	
	color = (UseApproximateTransforms)
		? Oklab::Fast_LCh_to_DisplayFormat(color)
		: Oklab::LCh_to_DisplayFormat(color);
	return color.rgb;
}

technique PalettePosterize <ui_tooltip =
"将图像色调分离为自定义调色板。\n\n"
"(支持 HDR)";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = PosterizeDitherPass;
	}
}
