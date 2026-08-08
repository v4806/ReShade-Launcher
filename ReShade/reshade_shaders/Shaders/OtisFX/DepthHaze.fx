///////////////////////////////////////////////////////////////////
// This effect works like a one-side DoF for distance haze, which slightly
// blurs far away elements. A normal DoF has a focus point and blurs using
// two planes. 
//
// It works by first blurring the screen buffer using 2-pass block blur and
// then blending the blurred result into the screen buffer based on depth
// it uses depth-difference for extra weight in the blur method so edges
// of high-contrasting lines with high depth diffence don't bleed.
///////////////////////////////////////////////////////////////////
// By Otis / Infuse Project
///////////////////////////////////////////////////////////////////

uniform float EffectStrength <
	ui_type = "drag";
	ui_min = 0.0; ui_max=1.0;
	ui_label = "效果强度";
	ui_tooltip = "效果的强度。范围从0.0（无效果）到1.0（像素根据深度100%模糊）。";
> = 0.9;
uniform float3 FogColor <
	ui_type= "color";
	ui_label = "雾颜色";
	ui_tooltip = "雾的颜色，格式为（红、绿、蓝）";
> = float3(0.8,0.8,0.8);
uniform float FogStart <
	ui_type = "drag";
	ui_min = 0.0; ui_max=1.0;
	ui_label = "雾起始点";
	ui_tooltip = "雾的起始位置。0.0在相机处，1.0在地平线处，0.5在地平线的一半处。在此点之前不会出现雾。";
> = 0.2;
uniform float FogFactor <
	ui_type = "drag";
	ui_min = 0.0; ui_max=1.0;
	ui_label = "雾系数";
	ui_tooltip = "添加到场景中的雾量。0.0是无雾，1.0是最强的雾。";
> = 0.2;

#include "Reshade.fxh"

//////////////////////////////////////
// textures
//////////////////////////////////////
texture   Otis_FragmentBuffer1 	{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;};	
texture   Otis_FragmentBuffer2 	{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;};	

//////////////////////////////////////
// samplers
//////////////////////////////////////
sampler2D Otis_SamplerFragmentBuffer2 { Texture = Otis_FragmentBuffer2; };
sampler2D Otis_SamplerFragmentBuffer1 {	Texture = Otis_FragmentBuffer1; };

//////////////////////////////////////
// code
//////////////////////////////////////
float CalculateWeight(float distanceFromSource, float sourceDepth, float neighborDepth)
{
	return (1.0 - abs(sourceDepth - neighborDepth)) * (1/distanceFromSource) * neighborDepth;
}

void PS_Otis_DEH_BlockBlurHorizontal(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outFragment : SV_Target0)
{
	float4 color = tex2D(ReShade::BackBuffer, texcoord);
	float colorDepth = ReShade::GetLinearizedDepth(texcoord).r;
	float n = 1.0f;

	[loop]
	for(float i = 1; i < 5; ++i) 
	{
		float2 sourceCoords = texcoord + float2(i * ReShade::PixelSize.x, 0.0);
		float weight = CalculateWeight(i, colorDepth, ReShade::GetLinearizedDepth(sourceCoords).r);
		color += (tex2D(ReShade::BackBuffer, sourceCoords) * weight);
		n+=weight;
		
		sourceCoords = texcoord - float2(i * ReShade::PixelSize.x, 0.0);
		weight = CalculateWeight(i, colorDepth, ReShade::GetLinearizedDepth(sourceCoords).r);
		color += (tex2D(ReShade::BackBuffer, sourceCoords) * weight);
		n+=weight;
	}
	outFragment = color/n;
}

void PS_Otis_DEH_BlockBlurVertical(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outFragment : SV_Target0)
{
	float4 color = tex2D(Otis_SamplerFragmentBuffer1, texcoord);
	float colorDepth = ReShade::GetLinearizedDepth(texcoord).r;
	float n=1.0f;
	
	[loop]
	for(float j = 1; j < 5; ++j) 
	{
		float2 sourceCoords = texcoord + float2(0.0, j * ReShade::PixelSize.y);
		float weight = CalculateWeight(j, colorDepth, ReShade::GetLinearizedDepth(sourceCoords).r);
		color += (tex2D(Otis_SamplerFragmentBuffer1, sourceCoords) * weight);
		n+=weight;

		sourceCoords = texcoord - float2(0.0, j * ReShade::PixelSize.y);
		weight = CalculateWeight(j, colorDepth, ReShade::GetLinearizedDepth(sourceCoords).r);
		color += (tex2D(Otis_SamplerFragmentBuffer1, sourceCoords) * weight);
		n+=weight;
	}
	outFragment = color/n;
}

void PS_Otis_DEH_BlendBlurWithNormalBuffer(float4 vpos: SV_Position, float2 texcoord: TEXCOORD, out float4 fragment: SV_Target0)
{
	float depth = ReShade::GetLinearizedDepth(texcoord).r;
	float4 blendedFragment = lerp(tex2D(ReShade::BackBuffer, texcoord), tex2D(Otis_SamplerFragmentBuffer2, texcoord), clamp(depth  * EffectStrength, 0.0, 1.0)); 
	float yFactor = clamp(texcoord.y > 0.5 ? 1-((texcoord.y-0.5)*2.0) : texcoord.y * 2.0, 0, 1);
	fragment = lerp(blendedFragment, float4(FogColor, blendedFragment.r), clamp((depth-FogStart) * yFactor * FogFactor, 0.0, 1.0));
}

technique DepthHaze
{
	// 3 passes. First 2 passes blur screenbuffer into Otis_FragmentBuffer2 using 2 pass block blur with 10 samples each (so 2 passes needed)
	// 3rd pass blends blurred fragments based on depth with screenbuffer.
	pass Otis_DEH_Pass0
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_DEH_BlockBlurHorizontal;
		RenderTarget = Otis_FragmentBuffer1;
	}

	pass Otis_DEH_Pass1
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_DEH_BlockBlurVertical;
		RenderTarget = Otis_FragmentBuffer2;
	}
	
	pass Otis_DEH_Pass2
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_DEH_BlendBlurWithNormalBuffer;
	}
}
