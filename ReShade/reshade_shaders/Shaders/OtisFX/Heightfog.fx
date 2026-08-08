////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Height Fog shader to create a volumetric plane with fog in a 3D scene
// By Marty McFly and Otis_Inf
// (c) 2022 All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////////////////////////
//
// This shader has been released under the following license:
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
// Additional Credits:
// Plane intersection code by Inigo 'Iq' Quilez: https://www.iquilezles.org/www/articles/intersectors/intersectors.htm
// 
////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Version history:
// 17-nov-2022:		Added filter circle support so you can define an area where the fog should appear
// 12-sep-2022:		Added opacity max, max blending based on fog texture and evenly distributed fog.
// 17-apr-2022: 	Removed HDR blending as it results in fog that's too dark.
// 29-mar-2022: 	Fixed Fog start, it now works as intended, and added smoothing to the fog so it doesn't create hard edges anymore around geometry. 
//                  Overall it looks better now.
// 25-mar-2022: 	Added vertical/horizontal cloud control and wider range so more cloud details are possible
//                  Added blending in HDR
// 22-mar-2022: 	First release
////////////////////////////////////////////////////////////////////////////////////////////////////

#include "Reshade.fxh"

namespace Heightfog
{
	#define HEIGHT_FOG_VERSION  "1.0.5"

// uncomment the line below to enable debug mode
//#define HF_DEBUG 1

	uniform float3 FogColor <
		ui_category = "通用设置";
		ui_label = "雾颜色";
		ui_type = "color";
	> = float3(0.8, 0.8, 0.8);

	uniform float FogDensity <
		ui_category = "通用设置";
		ui_type = "drag";
		ui_label = "雾密度";
		ui_min = 0.000; ui_max=1.000;
		ui_step = 0.001;
		ui_tooltip = "控制雾在最厚点的浓度";
	> = 1.0;

	uniform float OveralFogDensityMax <
		ui_type = "drag";
		ui_label = "总体雾密度最大值";
		ui_min = 0.0; ui_max=1.0;
		ui_step = 0.01;
		ui_category = "通用设置";
	> = 1.0;

	uniform float FogStart <
		ui_category = "通用设置";
		ui_label = "雾起始点";
		ui_type = "drag";
		ui_min = 0.0; ui_max=1.000;
		ui_tooltip = "控制雾相对于相机的起始位置";
		ui_step = 0.001;
	> = 0;

	uniform float FogCurve <
		ui_category = "通用设置";
		ui_type = "drag";
		ui_label = "雾曲线";
		ui_min = 0.001; ui_max=1000.00;
		ui_tooltip = "控制雾变浓的速度";
		ui_step = 0.1;
	> = 25;

	uniform float FoV <
		ui_category = "通用设置";
		ui_type = "drag";
		ui_label = "视场角（度）";
		ui_tooltip = "场景的视场角，用于正确放置雾在场景中";
		ui_min = 10; ui_max=140;
		ui_step = 0.1;
	> = 60;

	uniform float2 PlaneOrientation <
		ui_category = "通用设置";
		ui_type = "drag";
		ui_label = "雾平面方向";
		ui_tooltip = "旋转雾平面以匹配场景。\n第一个值是翻滚，第二个值是上下";
		ui_min = -2; ui_max=2;
		ui_step = 0.001;
	> = float2(1.751, -0.464);

	uniform float PlaneZ <
		ui_category = "通用设置";
		ui_type = "drag";
		ui_label = "雾平面Z轴";
		ui_tooltip = "上下移动雾平面。负值将平面向下移动";
		ui_min = -2; ui_max=2;
		ui_step = 0.001;
	> = -0.001;

	uniform bool EvenlyDistributeFog <
		ui_category = "通用设置";
		ui_label = "均匀分布雾";
		ui_tooltip = "勾选后将均匀分布雾，使近处的雾和远处一样浓";
	> = false;

	uniform bool MovingFog <
		ui_label = "移动雾";
		ui_tooltip = "控制雾云是静态的还是在平面上移动";
		ui_category = "云配置";
	> = false;

	uniform float MovementSpeed <
		ui_type = "drag";
		ui_label = "云移动速度";
		ui_tooltip = "配置云移动的速度。0.0是不移动，1.0是最大速度";
		ui_min = 0; ui_max=1;
		ui_step = 0.01;
		ui_category = "云配置";
	> = 0.4;

	uniform float FogCloudScaleMax <
		ui_type = "drag";
		ui_label = "云缩放（最大）";
		ui_tooltip = "配置雾的云大小，用于最大值";
		ui_min = 0.0; ui_max=20;
		ui_step = 0.01;
		ui_category = "云配置";
	> = 1.0;

	uniform float FogCloudScaleVertical <
		ui_type = "drag";
		ui_label = "云缩放（垂直）";
		ui_tooltip = "配置雾的云大小，垂直方向";
		ui_min = 0.0; ui_max=20;
		ui_step = 0.01;
		ui_category = "云配置";
	> = 1.0;

	uniform float FogCloudScaleHorizontal <
		ui_type = "drag";
		ui_label = "云缩放（水平）";
		ui_tooltip = "配置雾的云大小，水平方向";
		ui_min = 0.0; ui_max=10;
		ui_step = 0.01;
		ui_category = "云配置";
	> = 1.0;

	uniform float FogCloudFactor <
		ui_type = "drag";
		ui_label = "云系数";
		ui_tooltip = "配置雾中云形成的量。\n1.0表示完全云，0.0表示无云";
		ui_min = 0; ui_max=1;
		ui_step = 0.01;
		ui_category = "云配置";
	> = 1.0;

	uniform float2 FogCloudOffset <
		ui_type = "drag";
		ui_label = "云偏移";
		ui_tooltip = "配置雾云纹理的偏移。\n使用此选项代替移动雾来控制云位置";
		ui_min = 0.0; ui_max=1;
		ui_step = 0.01;
		ui_category = "云配置";
	> = float2(0.0, 0.0);

	uniform float2 FogMaxOffset <
		ui_type = "drag";
		ui_label = "最大偏移";
		ui_tooltip = "配置雾云纹理的偏移。\n使用此选项代替移动雾来控制云位置";
		ui_min = 0.0; ui_max=1;
		ui_step = 0.01;
		ui_category = "云配置";
	> = float2(0.0, 0.0);

	uniform bool UseFilterCircle <
		ui_category = "滤镜圆边缘过滤";
		ui_label = "使用滤镜圆";
		ui_tooltip = "控制边缘滤镜是否激活";
	> = false;
	uniform bool FocusPointViewFilterCircleOnMouseDown <
		ui_category = "滤镜圆边缘过滤";
		ui_label = "鼠标按下时显示滤镜圆";
		ui_tooltip = "勾选后，将显示当前滤镜圆的叠加层。\n红色表示不会出现雾，\n透明表示会出现雾";
	> = false;
	uniform float2 FilterCircleCenterPoint <
		ui_category = "滤镜圆边缘过滤";
		ui_label = "中心点";
		ui_type = "drag";
		ui_step = 0.001;
		ui_min = 0.000; ui_max = 1.000;
		ui_tooltip = "滤镜圆中心的X和Y坐标\n0,0是左上角，0.5,0.5是屏幕中心。";
	> = float2(0.5, 0.5);
	uniform float FilterCircleRadius <
		ui_category = "滤镜圆边缘过滤";
		ui_label = "半径";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 2.000;
		ui_step = 0.001;
		ui_tooltip = "滤镜圆的半径。\n此圆外的所有点不会或只会部分被雾化";
	> = 0.1;
	uniform float2 FilterCircleDeformFactors <
		ui_category = "滤镜圆边缘过滤";
		ui_label = "变形系数";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 2.000;
		ui_step = 0.001;
		ui_tooltip = "滤镜圆宽度和高度的半径系数。\n1.0表示无变形，其他值表示该方向有变形";
	> = float2(1.0, 1.0);
	uniform float FilterCircleRotationFactor <
		ui_category = "滤镜圆边缘过滤";
		ui_label = "旋转系数";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 1.000;
		ui_step = 0.001;
		ui_tooltip = "滤镜圆的旋转系数";
	> = 0.0;
	uniform float FilterCircleFeather <
		ui_category = "滤镜圆边缘过滤";
		ui_label = "羽化";
		ui_type = "drag";
		ui_min = 0.000; ui_max = 1.000;
		ui_step = 0.001;
		ui_tooltip = "滤镜圆内的羽化区域。\n1.0表示整个内部区域都被羽化，\n0.0表示无羽化区域。";
	> = 0.1;

#ifdef HF_DEBUG
	uniform bool DBVal1 <
		ui_label = "DBVal1";
		ui_category = "调试";
	> = false;
	uniform bool DBVal2 <
		ui_label = "DBVal2";
		ui_category = "调试";
	> = false;
	uniform float DBVal3f <
		ui_type = "drag";
		ui_label = "DBVal3f";
		ui_min = 1.0; ui_max=10;
		ui_step = 0.01;
		ui_category = "调试";
	> = 1.0;
	uniform float DBVal4f <
		ui_type = "drag";
		ui_label = "DBVal4f";
		ui_min = 0.0; ui_max=100.0;
		ui_step = 0.01;
		ui_category = "调试";
	> = 1.0;
#endif

	uniform float timer < source = "timer"; >; // Time in milliseconds it took for the last frame 
	uniform bool LeftMouseDown < source = "mousebutton"; keycode = 0; toggle = false; >;
	
#ifndef M_PI
	#define M_PI 3.1415927
#endif

#ifndef M_2PI
	#define M_2PI 6.283185
#endif

	#define PITCH_MULTIPLIER		1.751
	#define YAW_MULTIPLIER			-0.464
	#define BUFFER_ASPECT_RATIO2     float2(1.0, BUFFER_WIDTH * BUFFER_RCP_HEIGHT)

	texture texFogNoise				< source = "fognoise.jpg"; > { Width = 512; Height = 512; Format = RGBA8; };
	texture texFilterCircle { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };

	sampler SamplerFogNoise				{ Texture = texFogNoise; AddressU = WRAP; AddressV = WRAP; AddressW = WRAP;};
	sampler samplerFilterCircle { Texture = texFilterCircle; };
		
	struct VSPIXELINFO
	{
		float4 vpos : SV_Position;
		float2 texCoords : TEXCOORD0;
		float2x2 rotationMatrix: TEXCOORD6;
		float2 centerDisplacementDelta: TEXCOORD8;
		float featherRadius: TEXCOORD9;
	};
	
	//////////////////////////////////////////////////
	//
	// Functions
	//
	//////////////////////////////////////////////////
	
	float3 uvToProj(float2 uv, float z)
	{
		//optimized math to simplify matrix mul
		const float3 uvtoprojADD = float3(-tan(radians(FoV) * 0.5).xx, 1.0) * BUFFER_ASPECT_RATIO2.yxx;
		const float3 uvtoprojMUL = float3(-2.0 * uvtoprojADD.xy, 0.0);

		return (uv.xyx * uvtoprojMUL + uvtoprojADD) * z;
	}


	// from iq
	float planeIntersect(float3 ro, float3 rd, float4 p)
	{
		return -(dot(ro,p.xyz)+p.w)/dot(rd,p.xyz);
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
		// rotation matrix for focus point filter circle rotation
		float2 sincosFactor = float2(0,0);
		sincos(6.28318530717958 * FilterCircleRotationFactor, sincosFactor.x, sincosFactor.y);
		pixelInfo.rotationMatrix = float2x2(sincosFactor.y, sincosFactor.x, -sincosFactor.x, sincosFactor.y);
		// displacement delta for focus point to properly apply deformation
		pixelInfo.centerDisplacementDelta = FilterCircleCenterPoint - float2(0.5, 0.5);
		pixelInfo.featherRadius = FilterCircleRadius - (FilterCircleRadius * FilterCircleFeather); 
		return pixelInfo;
	}
	
	//////////////////////////////////////////////////
	//
	// PIXEL Shaders
	//
	//////////////////////////////////////////////////
	
	void PS_FogIt(VSPIXELINFO pixelInfo, out float4 fragment : SV_Target0)
	{
		float4 originalFragment = tex2D(ReShade::BackBuffer, pixelInfo.texCoords);
		float depth = lerp(1.0, 1000.0, ReShade::GetLinearizedDepth(pixelInfo.texCoords))/1000.0;
		float phi = PlaneOrientation.x * M_2PI; //I can never tell longitude and latitude apart... let's use wikipedia definitions
		float theta = PlaneOrientation.y * M_PI;

		float3 planeNormal;
		planeNormal.x = cos(phi)*sin(theta);
		planeNormal.y = sin(phi)*sin(theta);
		planeNormal.z = cos(theta);
		planeNormal = normalize(planeNormal); //for sanity

		float4 iqplane = float4(planeNormal, PlaneZ);	//anchor point is _apparently_ ray dir * this length in IQ formula
		float3 scenePosition = uvToProj(pixelInfo.texCoords, depth); 
		float sceneDistance = length(scenePosition); //actually length(position - camera) but as camera is 0 0 0, it's just length(position)
		float3 rayDirection = scenePosition / sceneDistance; //normalize(scenePosition)

		//camera at 0 0 0, so we pass 0.0 for ray origin (the first argument)
		float distanceToIntersect = planeIntersect(0, rayDirection, iqplane); //produces negative numbers if looking away from camera - makes sense as if you look away, you need to go _backwards_ i.e. in negative view direction
		float speedFactor = 100000.0 * (1-(MovementSpeed-0.01));
		float fogTextureValueHorizontally = tex2D(SamplerFogNoise, (pixelInfo.texCoords + FogCloudOffset) * FogCloudScaleHorizontal + (MovingFog ? frac(timer / speedFactor) : 0.0)).r;
		float fogTextureValueVertically = tex2D(SamplerFogNoise, (pixelInfo.texCoords + FogCloudOffset) * FogCloudScaleVertical + (MovingFog ? frac(timer / speedFactor) : 0.0)).r;
		float fogMaxValue = tex2D(SamplerFogNoise, (pixelInfo.texCoords + FogMaxOffset) * FogCloudScaleMax + (MovingFog ? frac(timer / speedFactor) : 0.0)).r;
		
		distanceToIntersect = distanceToIntersect < 0 ? 10000000 : distanceToIntersect; //if negative, we didn't hit it, so set hit distance to infinity
		distanceToIntersect *= lerp(1.0, fogTextureValueVertically, FogCloudFactor);
		float distanceTraveled = (depth - distanceToIntersect);
		distanceTraveled = saturate(distanceTraveled-saturate(0.5 * (FogStart - distanceToIntersect)));
		distanceTraveled = EvenlyDistributeFog ? distanceTraveled / 50.0f : (distanceTraveled * distanceTraveled);
		distanceTraveled *= fogMaxValue;
		float filterCircleValue = UseFilterCircle ? tex2Dlod(samplerFilterCircle, float4(pixelInfo.texCoords, 0, 0)).r : 0.0f;
		float lerpFactor = saturate(distanceTraveled * 10.0 * FogCurve * FogDensity * lerp(1.0, fogTextureValueHorizontally, FogCloudFactor)) * OveralFogDensityMax * saturate(1-filterCircleValue);
		fragment.rgb = sceneDistance < distanceToIntersect ? originalFragment.rgb 
														   : lerp(originalFragment.rgb, FogColor.rgb, lerpFactor);
		fragment.a = 1.0;
		
		if(FocusPointViewFilterCircleOnMouseDown && LeftMouseDown)
		{
			fragment.rgb = lerp(fragment.rgb, float3(1.0f, 0.0f, 0.0f), filterCircleValue * 0.7f);
		}
	}
	
		
	
	void PS_CreateFilterCircle(VSPIXELINFO pixelInfo, out float4 fragment : SV_Target0)
	{
		fragment = 0.0f;
		// apply deform factors to the texcoord
		// rotate the texcoord with the matrix we constructed so a pixel which normally wouldn't end up in the filter circle will potentially do now
		// so we rotate the frame instead of the circle (as we do cheap deformation with a single vector)
		float2 texcoordCenterNormalized = mul(((pixelInfo.texCoords-pixelInfo.centerDisplacementDelta) - 0.5), pixelInfo.rotationMatrix) * FilterCircleDeformFactors;
		float2 focusPointCenterNormalized = (FilterCircleCenterPoint-pixelInfo.centerDisplacementDelta) - 0.5;
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
	}
	
	technique HeightFog
#if __RESHADE__ >= 40000
	< ui_tooltip = "高度雾 "
			HEIGHT_FOG_VERSION
			"\n===========================================\n\n"
			"高度雾着色器用于在3D场景中引入体积雾平面，\n"
			"作者: Marty McFly 和 Otis_Inf"; >
#endif
	{
		pass CreateFilterCircle { VertexShader = VS_PixelInfo; PixelShader = PS_CreateFilterCircle; RenderTarget = texFilterCircle; }
		pass ApplyFog { VertexShader = VS_PixelInfo; PixelShader = PS_FogIt; }
	}
}