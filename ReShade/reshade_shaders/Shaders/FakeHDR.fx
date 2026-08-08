/**
 * HDR高动态范围
 * by Christian Cann Schuldt Jensen ~ CeeJay.dk
 *
 * 并非真正的HDR - 它只是尝试模拟HDR外观（相对较高的性能成本）
 */

#include "ReShadeUI.fxh"

uniform float HDRPower < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 8.0;
	ui_label = "强度";
> = 1.30;
uniform float radius1 < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 8.0;
	ui_label = "半径1";
> = 0.793;
uniform float radius2 < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 8.0;
	ui_label = "半径2";
	ui_tooltip = "提高此值似乎会使效果更强且更亮。";
> = 0.87;

#include "ReShade.fxh"

float3 HDRPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;

	float3 bloom_sum1 = tex2D(ReShade::BackBuffer, texcoord + float2(1.5, -1.5) * radius1 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum1 += tex2D(ReShade::BackBuffer, texcoord + float2(-1.5, -1.5) * radius1 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum1 += tex2D(ReShade::BackBuffer, texcoord + float2( 1.5,  1.5) * radius1 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum1 += tex2D(ReShade::BackBuffer, texcoord + float2(-1.5,  1.5) * radius1 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum1 += tex2D(ReShade::BackBuffer, texcoord + float2( 0.0, -2.5) * radius1 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum1 += tex2D(ReShade::BackBuffer, texcoord + float2( 0.0,  2.5) * radius1 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum1 += tex2D(ReShade::BackBuffer, texcoord + float2(-2.5,  0.0) * radius1 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum1 += tex2D(ReShade::BackBuffer, texcoord + float2( 2.5,  0.0) * radius1 * BUFFER_PIXEL_SIZE).rgb;

	bloom_sum1 *= 0.005;

	float3 bloom_sum2 = tex2D(ReShade::BackBuffer, texcoord + float2(1.5, -1.5) * radius2 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum2 += tex2D(ReShade::BackBuffer, texcoord + float2(-1.5, -1.5) * radius2 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum2 += tex2D(ReShade::BackBuffer, texcoord + float2( 1.5,  1.5) * radius2 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum2 += tex2D(ReShade::BackBuffer, texcoord + float2(-1.5,  1.5) * radius2 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum2 += tex2D(ReShade::BackBuffer, texcoord + float2( 0.0, -2.5) * radius2 * BUFFER_PIXEL_SIZE).rgb;	
	bloom_sum2 += tex2D(ReShade::BackBuffer, texcoord + float2( 0.0,  2.5) * radius2 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum2 += tex2D(ReShade::BackBuffer, texcoord + float2(-2.5,  0.0) * radius2 * BUFFER_PIXEL_SIZE).rgb;
	bloom_sum2 += tex2D(ReShade::BackBuffer, texcoord + float2( 2.5,  0.0) * radius2 * BUFFER_PIXEL_SIZE).rgb;

	bloom_sum2 *= 0.010;

	float dist = radius2 - radius1;
	float3 HDR = (color + (bloom_sum2 - bloom_sum1)) * dist;
	float3 blend = HDR + color;
	color = pow(abs(blend), abs(HDRPower)) + HDR; // pow - don't use fractions for HDRpower
	
	return saturate(color);
}

technique HDR
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = HDRPass;
	}
}
