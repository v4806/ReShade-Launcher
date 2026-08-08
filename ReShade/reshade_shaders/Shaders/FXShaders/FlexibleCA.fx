//#region Preprocessor

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

//#endregion

//#region Uniforms

uniform int Mode
<
	__UNIFORM_COMBO_INT1

	ui_text =
		"使用方法:\n"
		"\n"
		"首先，通过设置模式来选择您想要使用的色差类型。"
		"查看描述了解详情。\n"
		"\n"
		"其次，定义比例。这控制色差的'颜色'。\n"
		"\n"
		"最后，通过设置乘数来设置色差的大小。\n"
		" ";
	ui_label = "模式";
	ui_tooltip =
		"定义如何创建色差的模式。\n"
		"\n"
		"  平移:\n"
		"    水平和垂直移动通道。\n"
		"\n"
		"  缩放:\n"
		"    从中心缩放通道。\n"
		"\n"
		"默认: 缩放";
	ui_items = "平移\0缩放\0";
> = 1;

uniform float3 Ratio
<
	__UNIFORM_SLIDER_FLOAT3

	ui_label = "比例";
	ui_tooltip =
		"每个通道扭曲的比例。\n"
		"这些值分别控制红色、绿色和蓝色通道。\n"
		"\n"
		"默认: -1.0 0.0 1.0";
	ui_min = -1.0;
	ui_max = 1.0;
> = float3(-1.0, 0.0, 1.0);

uniform float Multiplier
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "乘数";
	ui_tooltip =
		"比例的乘数，定义有多少扭曲。\n"
		"\n"
		"默认: 1.0";
	ui_min = 0.0;
	ui_max = 6.0;
	ui_step = 0.001;
> = 1.0;

//#endregion

//#region Functions

float2 scale_uv(float2 uv, float2 scale, float2 center)
{
	return (uv - center) * scale + center;
}

//#endregion

//#region Shaders

float4 MainPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	const float2 ps = ReShade::PixelSize;

	float2 uv_r = uv;
	float2 uv_g = uv;
	float2 uv_b = uv;

	float3 ratio;

	switch (Mode)
	{
		case 0: // Translate
			ratio = Ratio * Multiplier;

			uv_r += ps * ratio.r;
			uv_g += ps * ratio.g;
			uv_b += ps * ratio.b;
			break;
		case 1: // Scale
			ratio = Multiplier * length(ps) + 1.0;
			ratio = lerp(ratio, 1.0 / ratio, Ratio * 0.5 + 0.5);

			uv_r = scale_uv(uv_r, ratio.r, 0.5);
			uv_g = scale_uv(uv_g, ratio.g, 0.5);
			uv_b = scale_uv(uv_b, ratio.b, 0.5);
			break;
	}

	float3 color = float3(
		tex2D(ReShade::BackBuffer, uv_r).r,
		tex2D(ReShade::BackBuffer, uv_g).g,
		tex2D(ReShade::BackBuffer, uv_b).b);

	return float4(color, 1.0);
}

//#endregion

//#region Technique

technique FlexibleCA
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = MainPS;
	}
}

//#endregion