/**
 * Tonemap version 1.1
 * by Christian Cann Schuldt Jensen ~ CeeJay.dk
 */

#include "ReShadeUI.fxh"

uniform float Gamma < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 2.0;
	ui_label = "伽马";
	ui_tooltip = "调整中间调。1.0是中性值。此设置与提升伽马增益中的设置完全相同，只是控制较少。";
> = 1.0;
uniform float Exposure < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "曝光";
	ui_tooltip = "调整曝光";
> = 0.0;
uniform float Saturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "饱和度";
	ui_tooltip = "调整饱和度";
> = 0.0;

uniform float Bleach < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "漂白";
	ui_tooltip = "提亮阴影并淡化颜色";
> = 0.0;

uniform float Defog < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "去雾";
	ui_tooltip = "要去除多少颜色色调";
> = 0.0;
uniform float3 FogColor < __UNIFORM_COLOR_FLOAT3
	ui_label = "去雾颜色";
	ui_tooltip = "要去除的颜色色调";
> = float3(0.0, 0.0, 1.0);


#include "ReShade.fxh"

float3 TonemapPass(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color = saturate(color - Defog * FogColor * 2.55); // Defog
	color *= pow(2.0f, Exposure); // Exposure
	color = pow(color, Gamma); // Gamma

	const float3 coefLuma = float3(0.2126, 0.7152, 0.0722);
	float lum = dot(coefLuma, color);
	
	float L = saturate(10.0 * (lum - 0.45));
	float3 A2 = Bleach * color;

	float3 result1 = 2.0f * color * lum;
	float3 result2 = 1.0f - 2.0f * (1.0f - lum) * (1.0f - color);
	
	float3 newColor = lerp(result1, result2, L);
	float3 mixRGB = A2 * newColor;
	color += ((1.0f - A2) * mixRGB);
	
	float3 middlegray = dot(color, (1.0 / 3.0));
	float3 diffcolor = color - middlegray;
	color = (color + diffcolor * Saturation) / (1 + (diffcolor * Saturation)); // Saturation
	
	return color;
}

technique Tonemap
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = TonemapPass;
	}
}
