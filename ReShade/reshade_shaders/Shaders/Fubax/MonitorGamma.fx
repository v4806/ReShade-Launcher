/*------------------.
| :: Description :: |
'-------------------/

Monitor Gamma Correction PS (version 1.1.3)

Author:
Jakub Maksymilian Fober

First publication:
2023

Copyright:
This work is free of known copyright restrictions.
https://creativecommons.org/publicdomain/mark/1.0/
*/

/*-------------.
| :: Macros :: |
'-------------*/

#ifndef GAMMA_TEX_FILE
	#define GAMMA_TEX_FILE "GammaTex.png"
#endif
#ifndef GAMMA_TEX_SIZE
	#define GAMMA_TEX_SIZE 256
#endif

/*--------------.
| :: Commons :: |
'--------------*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "LinearGammaWorkflow.fxh"
#include "BlueNoiseDither.fxh"

/*-----------.
| :: Menu :: |
'-----------*/

uniform float Gamma
<	__UNIFORM_DRAG_FLOAT1
	ui_text = "使标志消失:";
	ui_label = "显示器伽马";
	ui_tooltip =
		"调整直到标志消失。\n"
		"您可能需要眯着眼睛看。";
	ui_min = 1f; ui_max = 3f;
> = 1f;

uniform float GammaRedShift
<	__UNIFORM_DRAG_FLOAT1
	ui_category = "颜色偏移";
	ui_text = "如果标志有一些颜色色调:";
	ui_label = "红色伽马";
	ui_tooltip =
		"调整直到标志消失。\n"
		"您可能需要眯着眼睛看。";
	ui_min = 0.5; ui_max = 1.5;
> = 1f;

uniform float GammaGreenShift
<	__UNIFORM_DRAG_FLOAT1
	ui_category = "颜色偏移";
	ui_label = "绿色伽马";
	ui_tooltip =
		"调整直到标志消失。\n"
		"您可能需要眯着眼睛看。";
	ui_min = 0.5; ui_max = 1.5;
> = 1f;

uniform float GammaBlueShift
<	__UNIFORM_DRAG_FLOAT1
	ui_category = "颜色偏移";
	ui_label = "蓝色伽马";
	ui_tooltip =
		"调整直到标志消失。\n"
		"您可能需要眯着眼睛看。";
	ui_min = 0.5; ui_max = 1.5;
> = 1f;

uniform bool Debug
<	__UNIFORM_INPUT_BOOL1
	ui_text = "调试选项:";
	ui_label = "永久显示标志";
> = false;

uniform uint hovered_variable < source = "overlay_hovered"; >;
uniform uint active_variable  < source = "overlay_active"; >;

/*---------------.
| :: Textures :: |
'---------------*/

texture GammaTex
<
	source = GAMMA_TEX_FILE;
	pooled = true;
>
{
	Width = GAMMA_TEX_SIZE;
	Height = GAMMA_TEX_SIZE;
	Format = R8;
};
// Sampler for blue noise texture
sampler GammaTexSmp
{ Texture = GammaTex; };

/*--------------.
| :: Shaders :: |
'--------------*/

// Vertex shader generating a triangle covering the entire screen
void MonitorGamma_VS(
	in  uint   vertexId  : SV_VertexID,
	out float4 vertexPos : SV_Position
)
{
	// Define vertex position
	const float2 vertexPosList[3] =
	{
		float2(-1f, 1f), // Top left
		float2(-1f,-3f), // Bottom left
		float2( 3f, 1f)  // Top right
	};
	// Export  vertex position,
	vertexPos.xy = vertexPosList[vertexId];
	vertexPos.zw = float2(0f, 1f); // Export vertex position
}

// Horizontal luminosity blur pass
void MonitorGamma_PS(
	in  float4 pixCoord : SV_Position,
	out float3    color : SV_Target
)
{
	// Get current pixel coordinates
	uint2 texelPos = uint2(pixCoord.xy);

	if (bool(hovered_variable) || bool(active_variable) || Debug) // display calibration image
	{
		uint2 screenCenterOffset = uint2(BUFFER_SCREEN_SIZE-GAMMA_TEX_SIZE)/2u;
		color = lerp(texelPos.y % 2u, 0.5, tex2Dfetch(GammaTexSmp, texelPos-screenCenterOffset).r);
	}
	else // gamma correct back buffer
	{
		// Get current pixel color value
		color = tex2Dfetch(ReShade::BackBuffer, texelPos).rgb;

		// Convert to linear gamma
		color = GammaConvert::to_linear(color);
	}

	// Apply correction gamma
	color = pow(abs(color), rcp(Gamma));

	if (GammaRedShift == 1f || GammaGreenShift == 1f || GammaBlueShift == 1f) // apply gamma color tint
		color = pow(abs(color), rcp(float3(GammaRedShift, GammaGreenShift, GammaBlueShift)));

	// Apply color dither
	color = BlueNoise::dither(color, texelPos);
}

/*-------------.
| :: Output :: |
'-------------*/

technique MonitorGamma
<
	ui_label = "显示器伽马";
	ui_tooltip =
		"校准您的显示器伽马。\n"
		"\n"
		"作者 Jakub Maksymilian Fober\n"
		"CC0 公共领域许可";
>
{
	pass
	{
		VertexShader = MonitorGamma_VS;
		PixelShader  = MonitorGamma_PS;
	}
}
