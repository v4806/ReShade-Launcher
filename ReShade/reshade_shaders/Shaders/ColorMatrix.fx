/**
 * Color Matrix version 1.0
 * by Christian Cann Schuldt Jensen ~ CeeJay.dk
 *
 * ColorMatrix allow the user to transform the colors using a color matrix
 */

#include "ReShadeUI.fxh"

uniform float3 ColorMatrix_Red < __UNIFORM_SLIDER_FLOAT3
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "红色矩阵";
	ui_tooltip = "新红色值应包含多少红、绿、蓝色调。如果不想改变亮度，三者之和应为1.0。";
> = float3(0.817, 0.183, 0.000);
uniform float3 ColorMatrix_Green < __UNIFORM_SLIDER_FLOAT3
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "绿色矩阵";
	ui_tooltip = "新绿色值应包含多少红、绿、蓝色调。如果不想改变亮度，三者之和应为1.0。";
> = float3(0.333, 0.667, 0.000);
uniform float3 ColorMatrix_Blue < __UNIFORM_SLIDER_FLOAT3
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "蓝色矩阵";
	ui_tooltip = "新蓝色值应包含多少红、绿、蓝色调。如果不想改变亮度，三者之和应为1.0。";
> = float3(0.000, 0.125, 0.875);

uniform float Strength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "强度";
	ui_tooltip = "调整效果的强度。";
> = 1.0;

#include "ReShade.fxh"

float3 ColorMatrixPass(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;

	const float3x3 ColorMatrix = float3x3(ColorMatrix_Red, ColorMatrix_Green, ColorMatrix_Blue);
	color = lerp(color, mul(ColorMatrix, color), Strength);

	return saturate(color);
}

technique ColorMatrix
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = ColorMatrixPass;
	}
}
