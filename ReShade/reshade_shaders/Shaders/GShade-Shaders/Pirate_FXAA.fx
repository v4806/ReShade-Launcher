////////////////////////////////////////////////////////
// Pirate FXAA
// Author: Heathen
// Repository: https://github.com/Heathen/Pirate-Shaders
////////////////////////////////////////////////////////

//===================================================================================================================
#include "ReShade.fxh"
//===================================================================================================================

uniform float FXAA_RADIUS <
	ui_label = "FXAA - 半径";
	ui_type = "slider";
	ui_min = 0.5; ui_max = 2.0;
	ui_tooltip = "尽量保持接近1.0。";
	> = 1.0;
uniform float FXAA_STRENGTH <
	ui_label = "FXAA - 强度";
	ui_type = "slider";
	ui_min = 0.0001; ui_max = 1.0;
	ui_tooltip = "不言自明。";
	> = 1.0;
uniform bool FXAA_DEBUG <
	ui_label = "FXAA - 调试";
	ui_tooltip = "显示屏幕上正在进行模糊处理的区域。";
	> = false;

//===================================================================================================================
//===================================================================================================================

float4 FastFXAA(float4 colorIN : COLOR, float2 coord : TEXCOORD) : COLOR {
	const float2 tap[8] = {
		float2(1.0, 0.0),
		float2(-1.0, 0.0),
		float2(0.0, 1.0),
		float2(0.0, -1.0),
		float2(-1.0, -1.0),
		float2( 1.0, -1.0),
		float2( 1.0,  1.0),
		float2(-1.0,  1.0)
	};
	float4 ret;
	float edge;
	float3 blur = colorIN.rgb;
	const float intensity = dot(blur, 0.3333);
	
	[unroll]
	for(int i=0; i < 8; i++) {
		ret = tex2D(ReShade::BackBuffer, coord + tap[i] * BUFFER_PIXEL_SIZE * FXAA_RADIUS);
		float weight = abs(intensity - dot(ret.rgb, 0.33333));
		blur = lerp(blur, ret.rgb, weight / 8.0);
		edge += weight;
	}
	
	edge /= 8;
	ret.rgb = lerp(colorIN.rgb, blur, FXAA_STRENGTH);
	
	if (FXAA_DEBUG)	ret.rgb = edge;
	
	return ret;
}

//===================================================================================================================
//===================================================================================================================

float4 PS_FXAA(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : COLOR
{
	return FastFXAA(tex2D(ReShade::BackBuffer, texcoord), texcoord);
}

//===================================================================================================================
//===================================================================================================================

technique Pirate_FXAA
{
	pass FXAA_Pass
	{
		VertexShader = PostProcessVS;
		PixelShader  = PS_FXAA;
	}
}