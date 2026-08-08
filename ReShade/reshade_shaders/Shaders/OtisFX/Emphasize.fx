//////////////////////////////////////////////////////////////////
// This effect works like a simple DoF for desaturating what otherwise would have been blurred.
//
// It works by determining whether a pixel is outside the emphasize zone using the depth buffer
// if so, the pixel is desaturated and blended with the color specified in the cfg file. 
///////////////////////////////////////////////////////////////////
// Main shader by Otis / Infuse Project
// 3D emphasis code by SirCobra. 
///////////////////////////////////////////////////////////////////
uniform float FocusDepth <
	ui_type = "drag";
	ui_min = 0.000; ui_max = 1.000;
	ui_step = 0.001;
	ui_label = "焦点深度";
	ui_tooltip = "手动设置焦点的深度。范围从0.0（相机为焦平面）到1.0（地平线为焦平面）。";
> = 0.026;
uniform float FocusRangeDepth <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.000;
	ui_step = 0.001;
	ui_label = "焦点范围深度";
	ui_tooltip = "手动焦点深度周围应被强调的范围深度。在此范围之外，去强调将生效";
> = 0.001;
uniform float FocusEdgeDepth <
	ui_type = "drag";
	ui_min = 0.000; ui_max = 1.000;
	ui_label = "焦点边缘深度";
	ui_tooltip = "焦点范围边缘的深度。范围从0.00（无深度，在焦点范围边缘效果全力生效）\n到1.00（效果在focusRangeEdge到地平线的范围内平滑应用）。";
	ui_step = 0.001;
> = 0.050;
uniform bool Spherical <
	ui_label = "球形模式";
	ui_tooltip = "在焦点周围启用球形强调模式，而不是2D平面";
> = false;
uniform int Sphere_FieldOfView <
	ui_type = "drag";
	ui_min = 1; ui_max = 180;
	ui_label = "球形视场角";
	ui_tooltip = "指定您当前游戏的估计视场角。范围从1度到180度（场景的一半）。\n正常游戏通常使用60到90之间的值。";
> = 75;
uniform float Sphere_FocusHorizontal <
	ui_type = "drag";
	ui_min = 0; ui_max = 1;
	ui_label = "水平焦点位置";
	ui_tooltip = "指定焦点在水平轴上的位置。范围从0（屏幕左边缘）到1（屏幕右边缘）。";
> = 0.5;
uniform float Sphere_FocusVertical <
	ui_type = "drag";
	ui_min = 0; ui_max = 1;
	ui_label = "垂直焦点位置";
	ui_tooltip = "指定焦点在垂直轴上的位置。范围从0（屏幕上边缘）到1（屏幕下边缘）。";
> = 0.5;
uniform float3 BlendColor <
	ui_type = "color";
	ui_label = "混合颜色";
	ui_tooltip = "指定与灰度混合的颜色（红、绿、蓝）。使用深色来使远处的物体更暗";
> = float3(0.0, 0.0, 0.0);
uniform float BlendFactor <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "混合系数";
	ui_tooltip = "指定混合颜色的混合系数。范围从0.0（完全灰度）到1.0（完全混合颜色）";
> = 0.0;
uniform float EffectFactor <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "效果强度";
	ui_tooltip = "指定去饱和度应用的系数。范围从0.0（效果关闭，正常图像）到1.0（去饱和部分\n完全灰度，或如果启用了颜色混合则为颜色混合）";
> = 0.9;

#include "Reshade.fxh"

#ifndef M_PI
	#define M_PI 3.1415927
#endif

float CalculateDepthDiffCoC(float2 texcoord : TEXCOORD)
{
	const float scenedepth = ReShade::GetLinearizedDepth(texcoord);
	const float scenefocus = FocusDepth;
	const float desaturateFullRange = FocusRangeDepth + FocusEdgeDepth;
	float depthdiff;

	if (Spherical == true)
	{
		texcoord.x = (texcoord.x - Sphere_FocusHorizontal)*ReShade::ScreenSize.x;
		texcoord.y = (texcoord.y - Sphere_FocusVertical)*ReShade::ScreenSize.y;
		const float degreePerPixel = Sphere_FieldOfView / ReShade::ScreenSize.x;
		const float fovDifference = sqrt((texcoord.x*texcoord.x) + (texcoord.y*texcoord.y))*degreePerPixel;
		depthdiff = sqrt((scenedepth*scenedepth) + (scenefocus*scenefocus) - (2 * scenedepth*scenefocus*cos(fovDifference*(2 * M_PI / 360))));
	}
	else
	{
		depthdiff = abs(scenedepth - scenefocus);
	}

	return saturate((depthdiff > desaturateFullRange) ? 1.0 : smoothstep(FocusRangeDepth, desaturateFullRange, depthdiff));
}

void PS_Otis_EMZ_Desaturate(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 outFragment : SV_Target)
{
	const float depthDiffCoC = CalculateDepthDiffCoC(texcoord.xy);
	const float4 colFragment = tex2D(ReShade::BackBuffer, texcoord);
	const float greyscaleAverage = (colFragment.x + colFragment.y + colFragment.z) / 3.0;
	float4 desColor = float4(greyscaleAverage, greyscaleAverage, greyscaleAverage, depthDiffCoC);
	desColor = lerp(desColor, float4(BlendColor, depthDiffCoC), BlendFactor);
	outFragment = lerp(colFragment, desColor, saturate(depthDiffCoC * EffectFactor));
}

technique Emphasize
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_EMZ_Desaturate;
	}
}
