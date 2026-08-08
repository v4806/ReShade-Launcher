/**
 - Reshade HDR Saturation
 - Original code copyright, Pumbo
 - Tweaks and edits by MaxG3D
 **/

// Includes
#include "ReShadeUI.fxh"
#include "ReShade.fxh"
#include "HDRShadersFunctions.fxh"

// Defines

#ifndef ENABLE_DESATURATION
#define ENABLE_DESATURATION 0
#endif

static const int
	Luma = 0,
	YUV = 1,
	Average = 2,
	Vibrance = 3,
	Adaptive = 4,
	OKLAB = 5;

namespace HDRShaders
{

// UI
uniform int UI_SATURATION_METHOD
<
	ui_category = "饱和度";
	ui_label = "方法";
	ui_tooltip =
		"指定使用哪种饱和度函数"
		"\n""\n" "默认: HSV";
	ui_type = "combo";
	ui_items = "亮度\0YUV\0平均值\0自然饱和度\0自适应\0OKLAB\0";
> = OKLAB;

uniform float UI_SATURATION_AMOUNT <
	ui_category = "饱和度";
	#if ENABLE_DESATURATION
		ui_min = -1.0;
	#else
		ui_min = 0.01;
	#endif
	ui_max = 100.0;
	ui_label = "数量";
	ui_tooltip = "饱和度调整程度，0 = 中性";
	ui_step = 1;
	ui_type = "slider";
> = 75.0;

uniform float UI_SATURATION_GAMUT_EXPANSION <
	ui_category = "饱和度";
	ui_min = 0.0; ui_max = 100.0;
	ui_label = "色域扩展";
	ui_tooltip = "从明亮饱和的SDR颜色生成HDR颜色。0时为中性";
	ui_step = 1;
	ui_type = "slider";
> = 100.0;

uniform bool UI_SATURATION_KEEP_BRIGHTNESS <
	ui_category = "饱和度 - 高级";
	ui_label = "保持亮度";
	ui_tooltip = "是否禁止饱和度增加图像亮度？"
	"\n" "\n" "通常不建议开启，"
	"\n" "因为增加亮度是感知饱和度增加的一部分。";
> = 0;

uniform float UI_SATURATION_LIMIT <
	ui_category = "饱和度 - 高级";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "全局>高光";
	ui_tooltip = "在全局或仅高光饱和度之间切换";
	ui_step = 0.001;
	ui_type = "slider";
> = 0.995;

uniform float UI_SATURATION_LUMA_LIMIT <
	ui_category = "饱和度 - 高级";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "亮度保留";
	ui_tooltip = "避免裁剪高光细节";
	ui_step = 0.01;
	ui_type = "slider";
> = 0.95;

uniform float UI_SATURATION_COLORS_LIMIT <
	ui_category = "饱和度 - 高级";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "色度保留";
	ui_tooltip = "避免裁剪颜色细节。";
	ui_step = 0.01;
	ui_type = "slider";
> = 0.60;

uniform float UI_SATURATION_GAMUT_EXPANSION_CLIPPING_LIMIT <
	ui_category = "饱和度 - 高级";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "色域扩展阈值";
	ui_tooltip = "色域扩展受图像亮度控制的程度";
	ui_step = 0.01;
	ui_type = "slider";
> = 0.90;

float3 SaturationAdjustment(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
	const float3x3 sRGB_2_AP1 = mul(XYZ_2_AP1_MAT, mul(D65_2_D60_CAT, sRGB_2_XYZ_MAT));
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color = clamp(color, -FLT16_MAX, FLT16_MAX);
	if (Luminance(color, lumCoeffHDR) < 0.f)
	{
		color = 0.f;
	};
	const float3 PreProcessedColor = color;
	const float HDRLuminance = Luminance(PreProcessedColor, lumCoeffHDR);

	const float OklabLightness = RGBToOKLab(PreProcessedColor)[0];
	const float MidSaturationRatio = OklabLightness;
	const float OKlabLuminance = pow(OklabLightness, 4.0);
	//const float OKlabLuminanceSoft2 = smootherLerp(pow(OKlabLuminance, 0.25), OKlabLuminance, 0.5);
	const float OKlabLuminanceSoft = smoothstep(-8, 8, OKlabLuminance);
	const float HighlightSaturationRatio = (OklabLightness + (1.f / 48.f)) / (192.f / 1.f);

	const float3 ChromaComponents = PreProcessedColor - OKlabLuminance;
	const float Chroma = length(ChromaComponents);
	const float ChromaSoft = sqrt(sqrt(sqrt(Chroma)));
	const float ChromaMix = smoothLerp(Chroma,ChromaSoft,0.5);
	const float ChromaLimit = UI_SATURATION_COLORS_LIMIT * ChromaSoft;

	float BaseSaturationRatio = 1.0 + UI_SATURATION_AMOUNT;
	float SaturationClippingFactor = 1.0 - saturate(OKlabLuminanceSoft) * (UI_SATURATION_LUMA_LIMIT);
	float AdjustedSaturationRatio = BaseSaturationRatio;

	float RatioBlend = 0.0;
	if (UI_SATURATION_AMOUNT > 0.0)
	{
		AdjustedSaturationRatio *= SaturationClippingFactor;
		RatioBlend = lerp(MidSaturationRatio, HighlightSaturationRatio, UI_SATURATION_LIMIT);
	}
	else
	{
		RatioBlend = 1.0;
	}

	float3 ProcessedColor = PreProcessedColor;
	float AdjustedSaturation = max(lerp(1.f, AdjustedSaturationRatio, RatioBlend), .0f);
	if (UI_SATURATION_METHOD == Luma)
	{
		ProcessedColor = LumaSaturation(ProcessedColor, AdjustedSaturation);
	}
	else if (UI_SATURATION_METHOD == YUV)
	{
		ProcessedColor = YUVSaturation(ProcessedColor, AdjustedSaturation);
	}
	else if (UI_SATURATION_METHOD == Average)
	{
		ProcessedColor = AverageSaturation(ProcessedColor, AdjustedSaturation);
	}
	else if (UI_SATURATION_METHOD == Vibrance)
	{
		ProcessedColor = VibranceSaturation(ProcessedColor, AdjustedSaturation);
	}
	else if (UI_SATURATION_METHOD == Adaptive)
	{
		ProcessedColor = AdaptiveSaturation(ProcessedColor, AdjustedSaturation);
	}
	else if (UI_SATURATION_METHOD == OKLAB)
	{
		ProcessedColor = OKLABSaturation(ProcessedColor, AdjustedSaturation);
	}

	if (UI_SATURATION_KEEP_BRIGHTNESS)
	{
		ProcessedColor = SaturationBrightnessLimiter(PreProcessedColor, ProcessedColor);
	}

	ProcessedColor = WideColorsClamp(ProcessedColor);
	ProcessedColor = GamutMapping(ProcessedColor);
	ProcessedColor = lerp(ProcessedColor, max(ProcessedColor, 0.f), ChromaLimit);

	if (UI_SATURATION_GAMUT_EXPANSION > 0.f)
	{
		ProcessedColor = ExpandGamut
		(
			ProcessedColor,
			(UI_SATURATION_GAMUT_EXPANSION / 5) * saturate(smoothstep(1, 1.0 - ChromaMix, UI_SATURATION_GAMUT_EXPANSION_CLIPPING_LIMIT))
		);
		ProcessedColor = GamutMapping(ProcessedColor);
	}
	float3 XYZColor = mul(sRGB_2_XYZ_MAT, ProcessedColor);
	XYZColor = max(XYZColor, 0.f);
	float3 FinalColor = mul(XYZ_2_sRGB_MAT, XYZColor);

	return FinalColor;
}

technique HDR_Saturation <
ui_label = "HDRSaturation";>

{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader  = SaturationAdjustment;
	}
}

//Namespace
}
