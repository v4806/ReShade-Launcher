////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Directional Depth Blur shader for ReShade
// By Frans Bouma, aka Otis / Infuse Project (Otis_Inf)
// https://fransbouma.com 
//
// This shader has been released under the following license:
//
// Copyright (c) 2022 Frans Bouma
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// 
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
////////////////////////////////////////////////////////////////////////////////////////////////////
// 
// Version History
// 28-jun-2023: 	v1.5: Fixed issue with parallel strokes not working due to change introduced in 1.4
// 28-jun-2023:		v1.4: Added a setting to flip the feather band to feather the outside of the blur area
//					      Added a setting to flip the direction of the blur in Focus Point Targeting Strokes.
//     					  Fixed highlight gain not properly feathered.
// 30-aug-2022: 	v1.3: Added filter circle with feather support for focus point strokes mode, and tweaked some defaults.
// 18-apr-2020:		v1.2: Added blend factor for blur
// 13-apr-2020:		v1.1: Added highlight control (I know it flips the hue in focus point mode, it's a bug that actually looks great), 
//					      higher precision in buffers, better defaults
// 10-apr-2020:		v1.0: First release
//
////////////////////////////////////////////////////////////////////////////////////////////////////


#include "ReShade.fxh"

namespace DirectionalDepthBlur
{
// Uncomment line below for debug info / code / controls
//	#define CD_DEBUG 1
	
	#define DIRECTIONAL_DEPTH_BLUR_VERSION "v1.5"

	//////////////////////////////////////////////////
	//
	// User interface controls
	//
	//////////////////////////////////////////////////

	uniform float FocusPlane <
		ui_category = "对焦";
		ui_label= "焦平面";
		ui_type = "drag";
		ui_min = 0.001; ui_max = 1.000;
		ui_step = 0.001;
		ui_tooltip = "模糊开始的平面深度，相对于相机";
	> = 0.010;
	uniform float FocusRange <
		ui_category = "对焦";
		ui_label= "焦点范围";
		ui_type = "drag";
		ui_min = 0.001; ui_max = 1.000;
		ui_step = 0.001;
		ui_tooltip = "焦平面周围不被模糊的范围。\n1.0是焦平面最大范围。";
	> = 0.001;
	uniform float FocusPlaneMaxRange <
		ui_category = "对焦";
		ui_label= "焦平面最大范围";
		ui_type = "drag";
		ui_min = 10; ui_max = 300;
		ui_step = 1;
		ui_tooltip = "焦平面为1.0时的最大范围。\n1000是地平线。";
	> = 150;
	uniform float BlurAngle <
		ui_category = "模糊调整";
		ui_label="模糊角度";
		ui_type = "drag";
		ui_min = 0.01; ui_max = 1.00;
		ui_tooltip = "模糊方向的角度";
		ui_step = 0.01;
	> = 1.0;
	uniform float BlurLength <
		ui_category = "模糊调整";
		ui_label = "模糊长度";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 1.0;
		ui_step = 0.001;
		ui_tooltip = "每个像素的模糊条纹长度。1.0是整个屏幕。";
	> = 0.1;
	uniform float BlurQuality <
		ui_category = "模糊调整";
		ui_label = "模糊质量";
		ui_type = "drag";
		ui_min = 0.01; ui_max = 1.0;
		ui_step = 0.01;
		ui_tooltip = "模糊的质量。1.0表示读取模糊长度内的所有像素，\n0.5表示读取一半的像素。";
	> = 0.5;
	uniform float ScaleFactor <
		ui_category = "模糊调整";
		ui_label = "缩放系数";
		ui_type = "drag";
		ui_min = 0.010; ui_max = 1.000;
		ui_step = 0.001;
		ui_tooltip = "模糊像素的缩放系数。较低的值会缩小源帧，\n导致更宽的模糊条纹。";
	> = 1.000;
	uniform int BlurType <
		ui_category = "模糊调整";
		ui_type = "combo";
		ui_min= 0; ui_max=1;
		ui_items="平行条纹\0焦点目标条纹\0";
		ui_label = "模糊类型";
		ui_tooltip = "模糊类型。焦点目标条纹表示每个像素的模糊方向\n指向焦点。";
	> = 0;
	uniform float2 FocusPoint <
		ui_category = "模糊调整，焦点";
		ui_label = "模糊焦点";
		ui_type = "drag";
		ui_step = 0.001;
		ui_min = 0.000; ui_max = 1.000;
		ui_tooltip = "模糊焦点的X和Y坐标，用于'焦点目标条纹'模糊类型。\n0,0是左上角，0.5,0.5是屏幕中心。";
	> = float2(0.5, 0.5);
	uniform float3 FocusPointBlendColor <
		ui_category = "模糊调整，焦点";
		ui_label = "颜色";
		ui_type= "color";
		ui_tooltip = "焦点模式下焦点的颜色。像素越接近焦点，\n越会变成这个颜色。格式：（红、绿、蓝）";
	> = float3(0.0,0.0,0.0);
	uniform float FocusPointBlendFactor <
		ui_category = "模糊调整，焦点";
		ui_label = "颜色混合系数";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 1.000;
		ui_step = 0.001;
		ui_tooltip = "焦点颜色与最终图像混合的系数";
	> = 1.000;
	uniform bool FocusPointViewFilterCircleOnMouseDown <
		ui_category = "模糊调整，焦点";
		ui_label = "鼠标按下时显示滤镜圆";
		ui_tooltip = "用于焦点目标条纹模糊类型：\n勾选后将显示当前滤镜圆的叠加层。\n白色表示会有模糊，透明表示无模糊";
	> = false;
	uniform bool FocusPointFadeBlurInFeatherBand <
		ui_category = "模糊调整，焦点";
		ui_label = "在羽化带中淡化模糊";
		ui_tooltip = "用于焦点目标条纹模糊类型：\n勾选后将在滤镜圆的羽化区域淡出模糊";
	> = false;
	uniform bool FlipFadeBlurInFeatherBand <
		ui_category = "模糊调整，焦点";
		ui_label = "翻转羽化带";
		ui_tooltip = "用于焦点目标条纹模糊类型：\n勾选后将羽化带从朝向中心翻转为朝向边缘";
	> = false;
	uniform bool FlipFocusPointTargetingBlurDirection <
		ui_category = "模糊调整，焦点";
		ui_label = "翻转焦点目标条纹模糊方向";
		ui_tooltip = "用于焦点目标条纹模糊类型：\n勾选后将模糊方向从内向外翻转为外向内";
	> = false;
	uniform float FilterCircleRadius <
		ui_category = "模糊调整，焦点";
		ui_label = "滤镜圆半径";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 2.000;
		ui_step = 0.001;
		ui_tooltip = "用于焦点目标条纹模糊类型：\n滤镜圆的半径。此圆内的所有点不会或只会部分模糊";
	> = 0.1;
	uniform float2 FilterCircleDeformFactors <
		ui_category = "模糊调整，焦点";
		ui_label = "滤镜圆变形系数";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 2.000;
		ui_step = 0.001;
		ui_tooltip = "用于焦点目标条纹模糊类型：\n滤镜圆宽度和高度的半径系数。\n1.0表示无变形，其他值表示该方向有变形";
	> = float2(1.0, 1.0);
	uniform float FilterCircleRotationFactor <
		ui_category = "模糊调整，焦点";
		ui_label = "滤镜圆旋转系数";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 1.000;
		ui_step = 0.001;
		ui_tooltip = "用于焦点目标条纹模糊类型：\n滤镜圆的旋转系数";
	> = 0.0;
	uniform float FilterCircleFeather <
		ui_category = "模糊调整，焦点";
		ui_label = "滤镜圆羽化";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 1.000;
		ui_step = 0.001;
		ui_tooltip = "用于焦点目标条纹模糊类型：\n滤镜圆内的羽化区域。\n1.0表示整个内部区域都被羽化，0.0表示无羽化区域。";
	> = 0.1;
	
	uniform float HighlightGain <
		ui_category = "模糊调整";
		ui_label="高光增益";
		ui_type = "drag";
		ui_min = 0.00; ui_max = 10.00;
		ui_tooltip = "条纹平面中高光的增益。值越高，高光越亮。";
		ui_step = 0.01;
	> = 0.5;
	uniform float BlendFactor <
		ui_category = "模糊调整";
		ui_label="混合系数";
		ui_type = "drag";
		ui_min = 0.00; ui_max = 1.00;
		ui_tooltip = "效果应用到原始图像的强度。1.0是100%，0.0是0%。";
		ui_step = 0.01;
	> = 1.000;	
#if CD_DEBUG
	// ------------- DEBUG
	uniform bool DBVal1 <
		ui_category = "Debugging";
	> = false;
	uniform bool DBVal2 <
		ui_category = "Debugging";
	> = false;
	uniform float DBVal3f <
		ui_category = "Debugging";
		ui_type = "drag";
		ui_min = 0.00; ui_max = 1.00;
		ui_step = 0.01;
	> = 0.0;
	uniform float DBVal4f <
		ui_category = "Debugging";
		ui_type = "drag";
		ui_min = 0.00; ui_max = 10.00;
		ui_step = 0.01;
	> = 1.0;
#endif
	//////////////////////////////////////////////////
	//
	// Defines, constants, samplers, textures, uniforms, structs
	//
	//////////////////////////////////////////////////

#ifndef BUFFER_PIXEL_SIZE
	#define BUFFER_PIXEL_SIZE	ReShade::PixelSize
#endif
#ifndef BUFFER_SCREEN_SIZE
	#define BUFFER_SCREEN_SIZE	ReShade::ScreenSize
#endif
	
	uniform float2 MouseCoords < source = "mousepoint"; >;
	uniform bool LeftMouseDown < source = "mousebutton"; keycode = 0; toggle = false; >;
	
	texture texDownsampledBackBuffer { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
	texture texBlurDestination { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; }; 
	texture texFilterCircle { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
	
	sampler samplerDownsampledBackBuffer { Texture = texDownsampledBackBuffer; AddressU = MIRROR; AddressV = MIRROR; AddressW = MIRROR;};
	sampler samplerBlurDestination { Texture = texBlurDestination; };
	sampler samplerFilterCircle { Texture = texFilterCircle; };
	
	struct VSPIXELINFO
	{
		float4 vpos : SV_Position;
		float2 texCoords : TEXCOORD0;
		float2 pixelDelta: TEXCOORD1;
		float blurLengthInPixels: TEXCOORD2;
		float focusPlane: TEXCOORD3;
		float focusRange: TEXCOORD4;
		float4 texCoordsScaled: TEXCOORD5;
		float2x2 rotationMatrix: TEXCOORD6;
		float2 centerDisplacementDelta: TEXCOORD8;
		float featherRadius: TEXCOORD9;
	};
	
	//////////////////////////////////////////////////
	//
	// Functions
	//
	//////////////////////////////////////////////////
	
	float2 CalculatePixelDeltas(float2 texCoords)
	{
		float2 newCoords = (FlipFocusPointTargetingBlurDirection && BlurType==1) ? float2(texCoords.x - FocusPoint.x, texCoords.y - FocusPoint.y) 
																: float2(FocusPoint.x - texCoords.x, FocusPoint.y - texCoords.y);
		return newCoords * length(BUFFER_PIXEL_SIZE);
	}
	
	float3 AccentuateWhites(float3 fragment)
	{
		return fragment / (1.5 - clamp(fragment, 0, 1.49));	// accentuate 'whites'. 1.5 factor was empirically determined.
	}
	
	float3 CorrectForWhiteAccentuation(float3 fragment)
	{
		return (fragment.rgb * 1.5) / (1.0 + fragment.rgb);		// correct for 'whites' accentuation in taps. 1.5 factor was empirically determined.
	}
	
	float3 PostProcessBlurredFragment(float3 fragment, float maxLuma, float3 averageGained, float normalizationFactor)
	{
		const float3 lumaDotWeight = float3(0.3, 0.59, 0.11);

		float newFragmentLuma = dot(fragment, lumaDotWeight);
		averageGained.rgb = CorrectForWhiteAccentuation(averageGained.rgb);
		// increase luma to the max luma found on the gained taps. This over-boosts the luma on the averageGained, which we'll use to blend
		// together with the non-boosted fragment using the normalization factor to smoothly merge the highlights.
		averageGained.rgb *= 1+saturate(maxLuma-newFragmentLuma);
		fragment = (1-normalizationFactor) * fragment + normalizationFactor * averageGained.rgb;
		return fragment;
	}
	
	//////////////////////////////////////////////////
	//
	// Vertex Shaders
	//
	//////////////////////////////////////////////////
	
	VSPIXELINFO VS_PixelInfo(in uint id : SV_VertexID)
	{
		VSPIXELINFO pixelInfo;
		
		pixelInfo.texCoords.x = (id == 2) ? 2.0 : 0.0;
		pixelInfo.texCoords.y = (id == 1) ? 2.0 : 0.0;
		pixelInfo.vpos = float4(pixelInfo.texCoords * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
		float angleToUse = 6.28318530717958 * BlurAngle;
		sincos(angleToUse, pixelInfo.pixelDelta.y, pixelInfo.pixelDelta.x);
		float pixelSizeLength = length(BUFFER_PIXEL_SIZE);
		pixelInfo.pixelDelta *= pixelSizeLength;
		pixelInfo.blurLengthInPixels = length(BUFFER_SCREEN_SIZE) * BlurLength;
		pixelInfo.focusPlane = (FocusPlane * FocusPlaneMaxRange) / 1000.0; 
		pixelInfo.focusRange = (FocusRange * FocusPlaneMaxRange) / 1000.0;
		pixelInfo.texCoordsScaled = float4(pixelInfo.texCoords * ScaleFactor, pixelInfo.texCoords / ScaleFactor);
		// rotation matrix for focus point filter circle rotation
		float2 sincosFactor = float2(0,0);
		sincos(6.28318530717958 * FilterCircleRotationFactor, sincosFactor.x, sincosFactor.y);
		pixelInfo.rotationMatrix = float2x2(sincosFactor.y, sincosFactor.x, -sincosFactor.x, sincosFactor.y);
		// displacement delta for focus point to properly apply deformation
		pixelInfo.centerDisplacementDelta = FocusPoint - float2(0.5, 0.5);
		pixelInfo.featherRadius = FilterCircleRadius - (FilterCircleRadius * FilterCircleFeather); 
		return pixelInfo;
	}

	//////////////////////////////////////////////////
	//
	// Pixel Shaders
	//
	//////////////////////////////////////////////////

	void PS_Blur(VSPIXELINFO pixelInfo, out float4 fragment : SV_Target0)
	{
		const float3 lumaDotWeight = float3(0.3, 0.59, 0.11);

		float filterCircleValue = tex2Dlod(samplerFilterCircle, float4(pixelInfo.texCoords, 0, 0)).r;
		// pixelInfo.texCoordsScaled.xy is for scaled down UV, pixelInfo.texCoordsScaled.zw is for scaled up UV
		float3 color = tex2Dlod(samplerDownsampledBackBuffer, float4(pixelInfo.texCoordsScaled.xy, 0, 0)).rgb;
		float4 average = float4(color, 1.0);
		float3 averageGained = AccentuateWhites(average.rgb);
		float2 pixelDelta = BlurType==0 ? pixelInfo.pixelDelta : CalculatePixelDeltas(pixelInfo.texCoords);
		float maxLuma = dot(averageGained.rgb, lumaDotWeight);
		float blurLengthInPixels = pixelInfo.blurLengthInPixels;
		float alpha = 0.0f;
		float highlightGainToUse = HighlightGain;
		if(BlurType==1)
		{
			blurLengthInPixels *= filterCircleValue;
			highlightGainToUse *= filterCircleValue;
		}
		for(float tapIndex=0.0;tapIndex<blurLengthInPixels;tapIndex+=(1/BlurQuality))
		{
			float2 tapCoords = saturate(pixelInfo.texCoords + (pixelDelta * tapIndex));
			// we have to use a slightly smaller scalefactor here otherwise it might be we're reading just 1 pixel outside the downsized texture and that will lead to dark edges. 
			float3 tapColor = tex2Dlod(samplerDownsampledBackBuffer, float4(tapCoords * (ScaleFactor-0.001), 0, 0)).rgb;
			float tapDepth = ReShade::GetLinearizedDepth(tapCoords);
			float weight = tapDepth <= pixelInfo.focusPlane ? 0.0 : 1-(tapIndex / (blurLengthInPixels + (blurLengthInPixels==0)));
			average.rgb+=(tapColor * weight);
			average.a+=weight;
			float3 gainedTap = AccentuateWhites(tapColor.rgb);
			averageGained += gainedTap * weight;
			float lumaSample = saturate(dot(gainedTap, lumaDotWeight));
			maxLuma = weight > 0 ? max(maxLuma, lumaSample) : maxLuma;
			alpha = 1.0f;
		}
		float distanceToFocusPoint = distance(pixelInfo.texCoords, FocusPoint);
		fragment.rgb = average.rgb / (average.a + (average.a==0));
		fragment.rgb = BlurType==0 
							? fragment.rgb
							: lerp(fragment.rgb, saturate(lerp(FocusPointBlendColor, fragment.rgb, smoothstep(0, 1, distanceToFocusPoint))), FocusPointBlendFactor);
							
		float blendFactorToUse = BlendFactor * (BlurType==0 ? 1.0 : filterCircleValue);
		fragment.rgb = lerp(color, PostProcessBlurredFragment(fragment.rgb, saturate(maxLuma), (averageGained / (average.a + (average.a==0))), highlightGainToUse), blendFactorToUse);
		fragment.a = alpha;
	}


	void PS_Combiner(VSPIXELINFO pixelInfo, out float4 fragment : SV_Target0)
	{
		float colorDepth = ReShade::GetLinearizedDepth(pixelInfo.texCoords);
		float4 realColor = tex2Dlod(ReShade::BackBuffer, float4(pixelInfo.texCoords, 0, 0));
		float filterCircleValue = tex2Dlod(samplerFilterCircle, float4(pixelInfo.texCoords, 0, 0)).r;
		if(colorDepth <= pixelInfo.focusPlane || (BlurLength <= 0.0))
		{
			fragment = realColor;
			return;
		}
		float4 color = tex2Dlod(samplerBlurDestination, float4(pixelInfo.texCoords, 0, 0));
		float rangeEnd = (pixelInfo.focusPlane+pixelInfo.focusRange);
		float blendFactor = rangeEnd < colorDepth 
								? 1.0 
								: smoothstep(0, 1, 1-((rangeEnd-colorDepth) / pixelInfo.focusRange));

		if(BlurType==1 && FocusPointFadeBlurInFeatherBand)
		{
			blendFactor *= filterCircleValue;
		}
		fragment.rgb = lerp(realColor.rgb, color.rgb, blendFactor * color.a);
		if(FocusPointViewFilterCircleOnMouseDown && LeftMouseDown && BlurType==1)
		{
			fragment.rgb = lerp(fragment.rgb, float3(1.0f, 1.0f, 1.0f), filterCircleValue * 0.7f);
		}
	}
	
	void PS_DownSample(VSPIXELINFO pixelInfo, out float4 fragment : SV_Target0)
	{
		// pixelInfo.texCoordsScaled.xy is for scaled down UV, pixelInfo.texCoordsScaled.zw is for scaled up UV
		float2 sourceCoords = pixelInfo.texCoordsScaled.zw;
		if(max(sourceCoords.x, sourceCoords.y) > 1.0001)
		{
			// source pixel is outside the frame
			discard;
		}
		fragment = tex2D(ReShade::BackBuffer, sourceCoords);
	}
	
	
	void PS_CreateFilterCircle(VSPIXELINFO pixelInfo, out float4 fragment : SV_Target0)
	{
		fragment = 0.0f;
		if(BlurType!=1)
		{
			return;
		}
		// apply deform factors to the texcoord
		// rotate the texcoord with the matrix we constructed so a pixel which normally wouldn't end up in the filter circle will potentially do now
		// so we rotate the frame instead of the circle (as we do cheap deformation with a single vector)
		float2 texcoordCenterNormalized = mul(((pixelInfo.texCoords-pixelInfo.centerDisplacementDelta) - 0.5), pixelInfo.rotationMatrix) * FilterCircleDeformFactors;
		float2 focusPointCenterNormalized = (FocusPoint-pixelInfo.centerDisplacementDelta) - 0.5;
		float texcoordDistance = distance(texcoordCenterNormalized, focusPointCenterNormalized);
		// if the distance is larger than the filter circle radius, blur is always done. If it's smaller, we have to
		// take into account the feather width. So radius-feather is the feather band
		if(texcoordDistance < pixelInfo.featherRadius)
		{
			// inside the feather band start, so always transparent
			fragment = 0.0f;
		}
		else
		{
			if(texcoordDistance > FilterCircleRadius)
			{
				// outside the filter circle
				fragment = 1.0f;
			}
			else
			{
				// within the featherband
				float featherbandWidth = FilterCircleRadius - pixelInfo.featherRadius;
				fragment = lerp(0.0f, 1.0f, (texcoordDistance - pixelInfo.featherRadius) / (featherbandWidth + (featherbandWidth==0)));
			}
		}
		if(FlipFadeBlurInFeatherBand)
		{
			fragment = 1.0 - fragment;
		}
	}
	
	//////////////////////////////////////////////////
	//
	// Techniques
	//
	//////////////////////////////////////////////////

	technique DirectionalDepthBlur
#if __RESHADE__ >= 40000
	< ui_tooltip = "方向深度模糊 "
			DIRECTIONAL_DEPTH_BLUR_VERSION
			"\n===========================================\n\n"
			"方向深度模糊是一个根据每个像素的深度\n"
			"添加远平面方向模糊的着色器\n\n"
			"作者: Frans 'Otis_Inf' Bouma，OtisFX系列\n"
			"https://fransbouma.com | https://github.com/FransBouma/OtisFX"; >
#endif	
	{
		pass CreateFilterCircle { VertexShader = VS_PixelInfo; PixelShader = PS_CreateFilterCircle; RenderTarget = texFilterCircle; }
		pass Downsample { VertexShader = VS_PixelInfo ; PixelShader = PS_DownSample; RenderTarget = texDownsampledBackBuffer; }
		pass BlurPass { VertexShader = VS_PixelInfo; PixelShader = PS_Blur; RenderTarget = texBlurDestination; }
		pass Combiner { VertexShader = VS_PixelInfo; PixelShader = PS_Combiner; }
	}
}