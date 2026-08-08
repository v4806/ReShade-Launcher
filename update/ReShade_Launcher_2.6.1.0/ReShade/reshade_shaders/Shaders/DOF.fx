//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//LICENSE AGREEMENT AND DISTRIBUTION RULES:
//1 Copyrights of the Master Effect exclusively belongs to author - Gilcher Pascal aka Marty McFly.
//2 Master Effect (the SOFTWARE) is DonateWare application, which means you may or may not pay for this software to the author as donation.
//3 If included in ENB presets, credit the author (Gilcher Pascal aka Marty McFly).
//4 Software provided "AS IS", without warranty of any kind, use it on your own risk. 
//5 You may use and distribute software in commercial or non-commercial uses. For commercial use it is required to warn about using this software (in credits, on the box or other places). Commercial distribution of software as part of the games without author permission prohibited.
//6 Author can change license agreement for new versions of the software.
//7 All the rights, not described in this license agreement belongs to author.
//8 Using the Master Effect means that user accept the terms of use, described by this license agreement.
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// For more information about license agreement contact me:
// https://www.facebook.com/MartyMcModding
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Advanced Depth of Field 4.2 by Marty McFly 
// Version for release
// Copyright © 2008-2015 Marty McFly
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Credits :: Matso (Matso DOF), PetkaGtA, gp65cj042
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#include "ReShadeUI.fxh"

uniform bool DOF_AUTOFOCUS <
	ui_label = "自动对焦";
	ui_tooltip = "基于自动对焦中心周围的采样启用自动焦点识别。";
> = true;
uniform bool DOF_MOUSEDRIVEN_AF <
	ui_label = "鼠标驱动自动对焦";
	ui_tooltip = "启用鼠标驱动的自动对焦。如果为1，AF焦点从鼠标坐标读取，否则使用DOF_FOCUSPOINT。";
> = false;
uniform float2 DOF_FOCUSPOINT < __UNIFORM_SLIDER_FLOAT2
	ui_label = "对焦点";
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "自动对焦中心的X和Y坐标。坐标轴从屏幕左上角开始。";
> = float2(0.5, 0.5);
uniform int DOF_FOCUSSAMPLES < __UNIFORM_SLIDER_INT1
	ui_label = "对焦采样数";
	ui_min = 3; ui_max = 10;
	ui_tooltip = "焦点周围的采样数量，用于更平滑的焦平面检测。";
> = 6;
uniform float DOF_FOCUSRADIUS < __UNIFORM_SLIDER_FLOAT1
	ui_label = "对焦半径";
	ui_min = 0.02; ui_max = 0.20;
	ui_tooltip = "焦点周围的采样半径。";
> = 0.05;
uniform float DOF_NEARBLURCURVE <
	ui_type = "drag";
	ui_label = "近景模糊曲线";
	ui_min = 0.5; ui_max = 1000.0;
	ui_tooltip = "比焦平面更近的模糊曲线。值越高意味着模糊越少。";
> = 1.60;
uniform float DOF_FARBLURCURVE <
	ui_type = "drag";
	ui_label = "远景模糊曲线";
	ui_min = 0.05; ui_max = 5.0;
	ui_tooltip = "焦平面后方的模糊曲线。值越高意味着模糊越少。";
> = 2.00;
uniform float DOF_MANUALFOCUSDEPTH < __UNIFORM_SLIDER_FLOAT1
	ui_label = "手动对焦深度";
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "关闭自动对焦时的焦平面深度。0.0表示相机，1.0表示无限远。";
> = 0.02;
uniform float DOF_INFINITEFOCUS <
	ui_type = "drag";
	ui_label = "无限远对焦";
	ui_min = 0.01; ui_max = 1.0;
	ui_tooltip = "深度被视为无限远的距离。1.0是标准值。\n低值仅在对焦物体非常靠近相机时才产生失焦模糊。推荐用于游戏。";
> = 1.00;
uniform float DOF_BLURRADIUS <
	ui_type = "drag";
	ui_label = "模糊半径";
	ui_min = 2.0; ui_max = 100.0;
	ui_tooltip = "最大模糊半径（像素）。";
> = 15.0;

// Ring DOF Settings
uniform int iRingDOFSamples < __UNIFORM_SLIDER_INT1
	ui_label = "环形采样数";
	ui_min = 5; ui_max = 30;
	ui_tooltip = "第一个环上的采样数。周围的其他环有更多采样。";
> = 6;
uniform int iRingDOFRings < __UNIFORM_SLIDER_INT1
	ui_label = "环形数量";
	ui_min = 1; ui_max = 8;
	ui_tooltip = "环的数量";
> = 4;
uniform float fRingDOFThreshold < __UNIFORM_SLIDER_FLOAT1
	ui_label = "散景增亮阈值";
	ui_min = 0.5; ui_max = 3.0;
	ui_tooltip = "散景增亮的阈值。超过此值后，一切都会变得更亮。\n1.0是LDR游戏（如GTASA）的最大值，更高的值仅适用于HDR游戏（如Skyrim等）。";
> = 0.7;
uniform float fRingDOFGain < __UNIFORM_SLIDER_FLOAT1
	ui_label = "散景增益";
	ui_min = 0.1; ui_max = 30.0;
	ui_tooltip = "亮度超过阈值的像素的增亮量。";
> = 27.0;
uniform float fRingDOFBias < __UNIFORM_SLIDER_FLOAT1
	ui_label = "散景偏差";
	ui_min = 0.0; ui_max = 2.0;
	ui_tooltip = "散景偏差";
> = 0.0;
uniform float fRingDOFFringe < __UNIFORM_SLIDER_FLOAT1
	ui_label = "色差量";
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "色差量";
> = 0.5;

// Magic DOF Settings
uniform int iMagicDOFBlurQuality < __UNIFORM_SLIDER_INT1
	ui_label = "模糊质量";
	ui_min = 1; ui_max = 30;
	ui_tooltip = "模糊质量作为采样数的控制值。\n质量15产生721个采样，其他DOF着色器最多只能做到约150个。";
> = 8;
uniform float fMagicDOFColorCurve < __UNIFORM_SLIDER_FLOAT1
	ui_label = "颜色曲线";
	ui_min = 1.0; ui_max = 10.0;
	ui_tooltip = "DOF权重曲线";
> = 4.0;

// GP65CJ042 DOF Settings
uniform int iGPDOFQuality < __UNIFORM_SLIDER_INT1
	ui_label = "模糊质量";
	ui_min = 0; ui_max = 7;
	ui_tooltip = "0 = 仅轻微高斯远景模糊无散景。1-7散景模糊，更高意味着更好的模糊质量但更低的帧率。";
> = 6;
uniform bool bGPDOFPolygonalBokeh <
	ui_label = "多边形散景";
	ui_tooltip = "启用多边形散景形状，例如POLYGON_NUM 5表示五边形散景形状。设为false则产生圆形散景形状。";
> = true;
uniform int iGPDOFPolygonCount < __UNIFORM_SLIDER_INT1
	ui_label = "多边形边数";
	ui_min = 3; ui_max = 9;
	ui_tooltip = "控制多边形散景形状的边数。3=三角形，4=正方形，5=五边形等。";
> = 5;
uniform float fGPDOFBias < __UNIFORM_SLIDER_FLOAT1
	ui_label = "散景偏差";
	ui_min = 0.0; ui_max = 20.0;
	ui_tooltip = "将散景权重偏移到散景形状边缘。设为0产生均匀明亮的散景形状，增加则产生中心较暗边缘较亮的散景形状。";
> = 10.0;
uniform float fGPDOFBiasCurve < __UNIFORM_SLIDER_FLOAT1
	ui_label = "散景偏差曲线";
	ui_min = 0.0; ui_max = 3.0;
	ui_tooltip = "散景偏差的幂。增加以获得更明显的散景形状边缘轮廓。";
> = 2.0;
uniform float fGPDOFBrightnessThreshold < __UNIFORM_SLIDER_FLOAT1
	ui_label = "亮度阈值";
	ui_min = 0.5; ui_max = 2.0;
	ui_tooltip = "散景增亮的阈值。超过此值后，一切都会变得更亮。\n1.0是LDR游戏（如GTASA）的最大值，更高的值仅适用于HDR游戏（如Skyrim等）。";
> = 0.5;
uniform float fGPDOFBrightnessMultiplier < __UNIFORM_SLIDER_FLOAT1
	ui_label = "亮度倍增";
	ui_min = 0.0; ui_max = 2.0;
	ui_tooltip = "对亮度超过阈值的像素的增亮量。";
> = 2.0;
uniform float fGPDOFChromaAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "色差量";
	ui_min = 0.0; ui_max = 0.4;
	ui_tooltip = "应用于模糊区域的色移量。";
> = 0.15;

// MATSO DOF Settings
uniform bool bMatsoDOFChromaEnable <
	ui_label = "启用色差";
	ui_tooltip = "启用色差。";
> = true;
uniform float fMatsoDOFChromaPow < __UNIFORM_SLIDER_FLOAT1
	ui_label = "色差强度";
	ui_min = 0.2; ui_max = 3.0;
	ui_tooltip = "色差色移量。";
> = 1.4;
uniform float fMatsoDOFBokehCurve < __UNIFORM_SLIDER_FLOAT1
	ui_label = "散景曲线";
	ui_min = 0.5; ui_max = 20.0;
	ui_tooltip = "散景曲线";
> = 8.0;
uniform int iMatsoDOFBokehQuality < __UNIFORM_SLIDER_INT1
	ui_label = "散景质量";
	ui_min = 1; ui_max = 10;
	ui_tooltip = "模糊质量作为采样数的控制值。";
> = 2;
uniform float fMatsoDOFBokehAngle < __UNIFORM_SLIDER_FLOAT1
	ui_label = "散景角度";
	ui_min = 0; ui_max = 360; ui_step = 1;
	ui_tooltip = "散景形状的旋转角度。";
> = 0;

// MCFLY ADVANCED DOF Settings - SHAPE
#ifndef bADOF_ShapeTextureEnable
	#define bADOF_ShapeTextureEnable 0 // Enables the use of a texture overlay. Quite some performance drop.
	#define iADOF_ShapeTextureSize 63 // Higher texture size means less performance. Higher quality integers better work with detailed shape textures. Uneven numbers recommended because even size textures have no center pixel.
#endif

#ifndef iADOF_ShapeVertices
	#define iADOF_ShapeVertices 5 // Polygon count of bokeh shape. 4 = square, 5 = pentagon, 6 = hexagon and so on.
#endif

uniform int iADOF_ShapeQuality < __UNIFORM_SLIDER_INT1
	ui_label = "形状质量";
	ui_min = 1; ui_max = 255;
	ui_tooltip = "DOF形状的质量级别。更高意味着更多偏移采样，形状更干净但性能更低。编译时间保持不变。";
> = 17;
uniform float fADOF_ShapeRotation < __UNIFORM_SLIDER_FLOAT1
	ui_label = "形状旋转";
	ui_min = 0; ui_max = 360; ui_step = 1;
	ui_tooltip = "散景形状的静态旋转。";
> = 15;
uniform bool bADOF_RotAnimationEnable <
	ui_label = "启用旋转动画";
	ui_tooltip = "启用随时间持续的形状旋转。";
> = false;
uniform float fADOF_RotAnimationSpeed < __UNIFORM_SLIDER_FLOAT1
	ui_label = "旋转动画速度";
	ui_min = -5; ui_max = 5;
	ui_tooltip = "形状旋转的速度。负数改变方向。";
> = 2.0;
uniform bool bADOF_ShapeCurvatureEnable <
	ui_label = "启用形状曲率";
	ui_tooltip = "将多边形形状的边缘向外（或向内）弯曲。圆形效果最佳需要顶点数>7。";
> = false;
uniform float fADOF_ShapeCurvatureAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "形状曲率量";
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "边缘弯曲量。1.0产生圆形。低于0的值产生星形形状。";
> = 0.3;
uniform bool bADOF_ShapeApertureEnable <
	ui_label = "启用光圈效果";
	ui_tooltip = "启用将散景形状变形为漩涡状光圈。您可以尝试一下就会明白。大散景形状效果最佳。";
> = false;
uniform float fADOF_ShapeApertureAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "光圈效果量";
	ui_min = -0.05; ui_max = 0.05;
	ui_tooltip = "变形量。负值产生镜像效果。";
> = 0.01;
uniform bool bADOF_ShapeAnamorphEnable <
	ui_label = "启用变形宽银幕";
	ui_tooltip = "减少形状的水平宽度以模拟电影中看到的变形宽银幕散景形状。";
> = false;
uniform float fADOF_ShapeAnamorphRatio < __UNIFORM_SLIDER_FLOAT1
	ui_label = "变形宽银幕比例";
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "水平宽度系数。1.0表示100%宽度，0.0表示0%宽度（散景形状将是垂直线）。";
> = 0.2;
uniform bool bADOF_ShapeDistortEnable <
	ui_label = "启用边缘畸变";
	ui_tooltip = "在屏幕边缘变形散景形状以模拟镜头畸变。屏幕边缘的散景形状看起来像鸡蛋。";
> = false;
uniform float fADOF_ShapeDistortAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "畸变量";
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "变形量。";
> = 0.2;
uniform bool bADOF_ShapeDiffusionEnable <
	ui_label = "启用形状扩散";
	ui_tooltip = "启用散景形状的一些模糊，使其不那么清晰。";
> = false;
uniform float fADOF_ShapeDiffusionAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "形状扩散量";
	ui_min = 0.0; ui_max = 1.0;
	ui_tooltip = "形状扩散量。高值看起来像散景形状爆炸了。";
> = 0.1;
uniform bool bADOF_ShapeWeightEnable <
	ui_label = "启用形状权重";
	ui_tooltip = "启用散景形状权重偏差并将颜色移向形状边缘。";
> = false;
uniform float fADOF_ShapeWeightCurve < __UNIFORM_SLIDER_FLOAT1
	ui_label = "形状权重曲线";
	ui_min = 0.5; ui_max = 8.0;
	ui_tooltip = "形状权重偏差的曲线。";
> = 4.0;
uniform float fADOF_ShapeWeightAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "形状权重量";
	ui_min = 0.5; ui_max = 8.0;
	ui_tooltip = "形状权重偏差的量。";
> = 1.0;
uniform float fADOF_BokehCurve < __UNIFORM_SLIDER_FLOAT1
	ui_label = "散景曲线";
	ui_min = 1.0; ui_max = 20.0;
	ui_tooltip = "散景因子。更高的值对分离的亮点产生更明显的散景形状。";
> = 4.0;

// MCFLY ADVANCED DOF Settings - CHROMATIC ABERRATION
uniform bool bADOF_ShapeChromaEnable <
	ui_label = "启用形状色差";
	ui_tooltip = "在散景形状边缘启用色差。这意味着3倍的采样数=性能降低。";
> = false;
uniform int iADOF_ShapeChromaMode <
	ui_type = "combo";
	ui_label = "色差模式";
	ui_items = "模式 1\0模式 2\0模式 3\0模式 4\0模式 5\0模式 6\0";
	ui_tooltip = "在可能的RGB偏移之间切换。";
> = 3;
uniform float fADOF_ShapeChromaAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "色差量";
	ui_min = 0.0; ui_max = 0.5;
	ui_tooltip = "色移量。";
> = 0.125;
uniform bool bADOF_ImageChromaEnable <
	ui_label = "启用图像色差";
	ui_tooltip = "在屏幕角落启用图像色差。\n这个比形状色差（以及网上的任何其他色差）要复杂得多。";
> = false;
uniform int iADOF_ImageChromaHues < __UNIFORM_SLIDER_INT1
	ui_label = "图像色差色相数";
	ui_min = 2; ui_max = 20;
	ui_tooltip = "通过光谱的采样数以获得平滑的渐变。";
> = 5;
uniform float fADOF_ImageChromaCurve < __UNIFORM_SLIDER_FLOAT1
	ui_label = "图像色差曲线";
	ui_min = 0.5; ui_max = 2.0;
	ui_tooltip = "图像色差曲线。更高意味着屏幕中心区域的色差更少。";
> = 1.0;
uniform float fADOF_ImageChromaAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "图像色差量";
	ui_min = 0.25; ui_max = 10.0;
	ui_tooltip = "线性增加图像色差量。";
> = 3.0;

// MCFLY ADVANCED DOF Settings - POSTFX
uniform float fADOF_SmootheningAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "平滑量";
	ui_min = 0.5; ui_max = 2.0;
	ui_tooltip = "散景后方框模糊的倍增器以平滑形状。方框模糊比高斯更好。";
> = 1.0;

#ifndef bADOF_ImageGrainEnable
	#define bADOF_ImageGrainEnable 0 // Enables some fuzzyness in blurred areas. The more out of focus, the more grain
#endif

#if bADOF_ImageGrainEnable
uniform float fADOF_ImageGrainCurve < __UNIFORM_SLIDER_FLOAT1
	ui_label = "图像噪点曲线";
	ui_min = 0.5; ui_max = 5.0;
	ui_tooltip = "图像噪点分布曲线。更高的值减少中等模糊区域的噪点。";
> = 1.0;
uniform float fADOF_ImageGrainAmount < __UNIFORM_SLIDER_FLOAT1
	ui_label = "图像噪点量";
	ui_min = 0.1; ui_max = 2.0;
	ui_tooltip = "线性倍增应用的图像噪点量。";
> = 0.55;
uniform float fADOF_ImageGrainScale < __UNIFORM_SLIDER_FLOAT1
	ui_label = "图像噪点缩放";
	ui_min = 0.5; ui_max = 2.0;
	ui_tooltip = "噪点纹理缩放。低值产生更粗糙的噪点。";
> = 1.0;
#endif

/////////////////////////TEXTURES / INTERNAL PARAMETERS/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////TEXTURES / INTERNAL PARAMETERS/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if bADOF_ImageGrainEnable
texture texNoise < source = "mcnoise.png"; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler SamplerNoise { Texture = texNoise; };
#endif
#if bADOF_ShapeTextureEnable
texture texMask < source = "mcmask.png"; > { Width = iADOF_ShapeTextureSize; Height = iADOF_ShapeTextureSize; Format = R8; };
sampler SamplerMask { Texture = texMask; };
#endif

#define DOF_RENDERRESMULT 0.6

texture texHDR1 { Width = BUFFER_WIDTH * DOF_RENDERRESMULT; Height = BUFFER_HEIGHT * DOF_RENDERRESMULT; Format = RGBA8; };
texture texHDR2 { Width = BUFFER_WIDTH * DOF_RENDERRESMULT; Height = BUFFER_HEIGHT * DOF_RENDERRESMULT; Format = RGBA8; }; 
sampler SamplerHDR1 { Texture = texHDR1; };
sampler SamplerHDR2 { Texture = texHDR2; };

/////////////////////////FUNCTIONS//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////FUNCTIONS//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"

uniform float2 MouseCoords < source = "mousepoint"; >;

float GetCoC(float2 coords)
{
	float scenedepth = ReShade::GetLinearizedDepth(coords);
	float scenefocus, scenecoc = 0.0;

	if (DOF_AUTOFOCUS)
	{
		scenefocus = 0.0;

		float2 focusPoint = DOF_MOUSEDRIVEN_AF ? MouseCoords * BUFFER_PIXEL_SIZE : DOF_FOCUSPOINT;

		[loop]
		for (int r = DOF_FOCUSSAMPLES; 0 < r; r--)
		{
			sincos((6.2831853 / DOF_FOCUSSAMPLES) * r, coords.y, coords.x);
			coords.y *= BUFFER_ASPECT_RATIO;
			scenefocus += ReShade::GetLinearizedDepth(coords * DOF_FOCUSRADIUS + focusPoint);
		}
		scenefocus /= DOF_FOCUSSAMPLES;
	}
	else
	{
		scenefocus = DOF_MANUALFOCUSDEPTH;
	}

	scenefocus = smoothstep(0.0, DOF_INFINITEFOCUS, scenefocus);
	scenedepth = smoothstep(0.0, DOF_INFINITEFOCUS, scenedepth);

	float farBlurDepth = scenefocus * pow(4.0, DOF_FARBLURCURVE);

	if (scenedepth < scenefocus)
	{
		scenecoc = (scenedepth - scenefocus) / scenefocus;
	}
	else
	{
		scenecoc = (scenedepth - scenefocus) / (farBlurDepth - scenefocus);
		scenecoc = saturate(scenecoc);
	}

	return saturate(scenecoc * 0.5 + 0.5);
}

/////////////////////////PIXEL SHADERS//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////PIXEL SHADERS//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

void PS_Focus(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 hdr1R : SV_Target0)
{
	float4 scenecolor = tex2D(ReShade::BackBuffer, texcoord);
	scenecolor.w = GetCoC(texcoord);
	hdr1R = scenecolor;
}

// RING DOF
void PS_RingDOF1(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 hdr2R : SV_Target0)
{
	float4 scenecolor = tex2D(SamplerHDR1, texcoord);

	float centerDepth = scenecolor.w;
	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS;

	discRadius *= (centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

	float2 blurRadius = discRadius * BUFFER_PIXEL_SIZE / iRingDOFRings;
	scenecolor.x = tex2Dlod(SamplerHDR1, float4(texcoord + float2( 0.000,  1.0) * fRingDOFFringe * discRadius * BUFFER_PIXEL_SIZE, 0, 0)).x;
	scenecolor.y = tex2Dlod(SamplerHDR1, float4(texcoord + float2(-0.866, -0.5) * fRingDOFFringe * discRadius * BUFFER_PIXEL_SIZE, 0, 0)).y;
	scenecolor.z = tex2Dlod(SamplerHDR1, float4(texcoord + float2( 0.866, -0.5) * fRingDOFFringe * discRadius * BUFFER_PIXEL_SIZE, 0, 0)).z;

	scenecolor.w = centerDepth;
	hdr2R = scenecolor;
}
void PS_RingDOF2(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 blurcolor : SV_Target)
{
	blurcolor = tex2D(SamplerHDR2, texcoord);
	float4 noblurcolor = tex2D(ReShade::BackBuffer, texcoord);

	float centerDepth = GetCoC(texcoord);

	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS;

	discRadius *= (centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

	if (discRadius < 1.2)
	{
		blurcolor = float4(noblurcolor.xyz, centerDepth);
		return;
	}

	blurcolor.w = 1.0;

	float s = 1.0;
	int ringsamples;

	[loop]
	for (int g = 1; g <= iRingDOFRings; g += 1)
	{
		ringsamples = g * iRingDOFSamples;

		[loop]
		for (int j = 0; j < ringsamples; j += 1)
		{
			float step = 6.283 / ringsamples;
			float2 sampleoffset = 0.0;
			sincos(j * step, sampleoffset.y, sampleoffset.x);
			float4 tap = tex2Dlod(SamplerHDR2, float4(texcoord + sampleoffset * BUFFER_PIXEL_SIZE * discRadius * g / iRingDOFRings, 0, 0));

			float tapluma = dot(tap.xyz, 0.333);
			float tapthresh = max((tapluma - fRingDOFThreshold) * fRingDOFGain, 0.0);
			tap.xyz *= 1.0 + tapthresh * blurAmount;

			tap.w = (tap.w >= centerDepth * 0.99) ? 1.0 : pow(abs(tap.w * 2.0 - 1.0), 4.0);
			tap.w *= lerp(1.0, g / iRingDOFRings, fRingDOFBias);
			blurcolor.xyz += tap.xyz * tap.w;
			blurcolor.w += tap.w;
		}
	}

	blurcolor.xyz /= blurcolor.w;
	blurcolor.xyz = lerp(noblurcolor.xyz, blurcolor.xyz, smoothstep(1.2, 2.0, discRadius)); // smooth transition between full res color and lower res blur
	blurcolor.w = centerDepth;
}

// MAGIC DOF
void PS_MagicDOF1(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 hdr2R : SV_Target0)
{
	float4 blurcolor = tex2D(SamplerHDR1, texcoord);

	float centerDepth = blurcolor.w;
	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS;

	discRadius *= (centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

	if (discRadius < 1.2)
	{
		hdr2R = float4(blurcolor.xyz, centerDepth);
	}
	else
	{
		blurcolor = 0.0;

		[loop]
		for (int i = -iMagicDOFBlurQuality; i <= iMagicDOFBlurQuality; ++i)
		{
			float2 tapoffset = float2(1, 0) * i;
			float4 tap = tex2Dlod(SamplerHDR1, float4(texcoord + tapoffset * discRadius * BUFFER_RCP_WIDTH / iMagicDOFBlurQuality, 0, 0));
			tap.w = (tap.w >= centerDepth*0.99) ? 1.0 : pow(abs(tap.w * 2.0 - 1.0), 4.0);
			blurcolor.xyz += tap.xyz*tap.w;
			blurcolor.w += tap.w;
		}

		blurcolor.xyz /= blurcolor.w;
		blurcolor.w = centerDepth;
		hdr2R = blurcolor;
	}
}
void PS_MagicDOF2(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 blurcolor : SV_Target)
{
	blurcolor = 0.0;
	float4 noblurcolor = tex2D(ReShade::BackBuffer, texcoord);

	float centerDepth = GetCoC(texcoord); //use fullres CoC data
	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS;

	discRadius *= (centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

	if (discRadius < 1.2)
	{
		blurcolor = float4(noblurcolor.xyz, centerDepth);
		return;
	}

	[loop]
	for (int i = -iMagicDOFBlurQuality; i <= iMagicDOFBlurQuality; ++i)
	{
		float2 tapoffset1 = float2(0.5, 0.866) * i;
		float2 tapoffset2 = float2(-tapoffset1.x, tapoffset1.y);

		float4 tap1 = tex2Dlod(SamplerHDR2, float4(texcoord + tapoffset1 * discRadius * BUFFER_PIXEL_SIZE / iMagicDOFBlurQuality, 0, 0));
		float4 tap2 = tex2Dlod(SamplerHDR2, float4(texcoord + tapoffset2 * discRadius * BUFFER_PIXEL_SIZE / iMagicDOFBlurQuality, 0, 0));

		blurcolor.xyz += pow(abs(min(tap1.xyz, tap2.xyz)), fMagicDOFColorCurve);
		blurcolor.w += 1.0;
	}

	blurcolor.xyz /= blurcolor.w;
	blurcolor.xyz = pow(saturate(blurcolor.xyz), 1.0 / fMagicDOFColorCurve);
	blurcolor.xyz = lerp(noblurcolor.xyz, blurcolor.xyz, smoothstep(1.2, 2.0, discRadius));
}

// GP65CJ042 DOF
void PS_GPDOF1(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 hdr2R : SV_Target0)
{
	float4 blurcolor = tex2D(SamplerHDR1, texcoord);

	float centerDepth = blurcolor.w;
	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = max(0.0, blurAmount - 0.1) * DOF_BLURRADIUS; //optimization to clean focus areas a bit

	discRadius *= (centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

	float3 distortion = float3(-1.0, 0.0, 1.0);
	distortion *= fGPDOFChromaAmount;

	float4 chroma1 = tex2D(SamplerHDR1, texcoord + discRadius * BUFFER_PIXEL_SIZE * distortion.x);
	chroma1.w = smoothstep(0.0, centerDepth, chroma1.w);
	blurcolor.x = lerp(blurcolor.x, chroma1.x, chroma1.w);

	float4 chroma2 = tex2D(SamplerHDR1, texcoord + discRadius * BUFFER_PIXEL_SIZE * distortion.z);
	chroma2.w = smoothstep(0.0, centerDepth, chroma2.w);
	blurcolor.z = lerp(blurcolor.z, chroma2.z, chroma2.w);

	blurcolor.w = centerDepth;
	hdr2R = blurcolor;
}
void PS_GPDOF2(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 blurcolor : SV_Target)
{
	blurcolor = tex2D(SamplerHDR2, texcoord);
	float4 noblurcolor = tex2D(ReShade::BackBuffer, texcoord);

	float centerDepth = GetCoC(texcoord);

	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS;

	discRadius *= (centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

	if (discRadius < 1.2)
	{
		blurcolor = float4(noblurcolor.xyz, centerDepth);
		return;
	}

	blurcolor.w = dot(blurcolor.xyz, 0.3333);
	blurcolor.w = max((blurcolor.w - fGPDOFBrightnessThreshold) * fGPDOFBrightnessMultiplier, 0.0);
	blurcolor.xyz *= (1.0 + blurcolor.w * blurAmount);
	blurcolor.xyz *= lerp(1.0, 0.0, saturate(fGPDOFBias));
	blurcolor.w = 1.0;

	int sampleCycle = 0;
	int sampleCycleCounter = 0;
	int sampleCounterInCycle = 0;
	float basedAngle = 360.0 / iGPDOFPolygonCount;
	float2 currentVertex, nextVertex;

	int	dofTaps = bGPDOFPolygonalBokeh ? (iGPDOFQuality * (iGPDOFQuality + 1) * iGPDOFPolygonCount / 2.0) : (iGPDOFQuality * (iGPDOFQuality + 1) * 4);

	for (int i = 0; i < dofTaps; i++)
	{
		//dumb step incoming
		bool dothatstep = sampleCounterInCycle == 0;
		if (sampleCycle != 0)
		{
			if (sampleCounterInCycle % sampleCycle == 0)
				dothatstep = true;
		}
		//until here
		//ask yourself why so complicated? if(sampleCounterInCycle % sampleCycle == 0 ) gives warnings when sampleCycle=0
		//but it can only be 0 when sampleCounterInCycle is also 0 so it essentially is no division through 0 even if
		//the compiler believes it, it's 0/0 actually but without disabling shader optimizations this is the only way to workaround that.

		if (dothatstep)
		{
			sampleCounterInCycle = 0;
			sampleCycleCounter++;

			if (bGPDOFPolygonalBokeh)
			{
				sampleCycle += iGPDOFPolygonCount;
				currentVertex.xy = float2(1.0, 0.0);
				sincos(basedAngle* 0.017453292, nextVertex.y, nextVertex.x);
			}
			else
			{
				sampleCycle += 8;
			}
		}

		sampleCounterInCycle++;

		float2 sampleOffset;

		if (bGPDOFPolygonalBokeh)
		{
			float sampleAngle = basedAngle / float(sampleCycleCounter) * sampleCounterInCycle;
			float remainAngle = frac(sampleAngle / basedAngle) * basedAngle;

			if (remainAngle < 0.000001)
			{
				currentVertex = nextVertex;
				sincos((sampleAngle + basedAngle) * 0.017453292, nextVertex.y, nextVertex.x);
			}

			sampleOffset = lerp(currentVertex.xy, nextVertex.xy, remainAngle / basedAngle);
		}
		else
		{
			float sampleAngle = 0.78539816 / float(sampleCycleCounter) * sampleCounterInCycle;
			sincos(sampleAngle, sampleOffset.y, sampleOffset.x);
		}

		sampleOffset *= sampleCycleCounter;

		float4 tap = tex2Dlod(SamplerHDR2, float4(texcoord + sampleOffset * discRadius * BUFFER_PIXEL_SIZE / iGPDOFQuality, 0, 0));

		float brightMultipiler = max((dot(tap.xyz, 0.333) - fGPDOFBrightnessThreshold) * fGPDOFBrightnessMultiplier, 0.0);
		tap.xyz *= 1.0 + brightMultipiler * abs(tap.w * 2.0 - 1.0);

		tap.w = (tap.w >= centerDepth * 0.99) ? 1.0 : pow(abs(tap.w * 2.0 - 1.0), 4.0);
		float BiasCurve = 1.0 + fGPDOFBias * pow(abs((float)sampleCycleCounter / iGPDOFQuality), fGPDOFBiasCurve);

		blurcolor.xyz += tap.xyz * tap.w * BiasCurve;
		blurcolor.w += tap.w * BiasCurve;

	}

	blurcolor.xyz /= blurcolor.w;
	blurcolor.xyz = lerp(noblurcolor.xyz, blurcolor.xyz, smoothstep(1.2, 2.0, discRadius));
}

// MATSO DOF
float4 GetMatsoDOFCA(sampler col, float2 tex, float CoC)
{
	float3 chroma = pow(float3(0.5, 1.0, 1.5), fMatsoDOFChromaPow * CoC);

	float2 tr = ((2.0 * tex - 1.0) * chroma.r) * 0.5 + 0.5;
	float2 tg = ((2.0 * tex - 1.0) * chroma.g) * 0.5 + 0.5;
	float2 tb = ((2.0 * tex - 1.0) * chroma.b) * 0.5 + 0.5;
	
	float3 color = float3(tex2Dlod(col, float4(tr,0,0)).r, tex2Dlod(col, float4(tg,0,0)).g, tex2Dlod(col, float4(tb,0,0)).b) * (1.0 - CoC);
	
	return float4(color, 1.0);
}
float4 GetMatsoDOFBlur(int axis, float2 coord, sampler SamplerHDRX)
{
	float4 blurcolor = tex2D(SamplerHDRX, coord.xy);

	float centerDepth = blurcolor.w;
	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS; //optimization to clean focus areas a bit

	discRadius*=(centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

	blurcolor = 0.0;

	const float2 tdirs[4] = { 
		float2(-0.306,  0.739),
		float2( 0.306,  0.739),
		float2(-0.739,  0.306),
		float2(-0.739, -0.306)
	};

	for (int i = -iMatsoDOFBokehQuality; i < iMatsoDOFBokehQuality; i++)
	{
		float2 taxis =  tdirs[axis];

		taxis.x = cos(fMatsoDOFBokehAngle * 0.0175) * taxis.x - sin(fMatsoDOFBokehAngle * 0.0175) * taxis.y;
		taxis.y = sin(fMatsoDOFBokehAngle * 0.0175) * taxis.x + cos(fMatsoDOFBokehAngle * 0.0175) * taxis.y;
		
		float2 tcoord = coord.xy + (float)i * taxis * discRadius * BUFFER_PIXEL_SIZE * 0.5 / iMatsoDOFBokehQuality;

		float4 ct = bMatsoDOFChromaEnable ? GetMatsoDOFCA(SamplerHDRX, tcoord.xy, discRadius * BUFFER_RCP_WIDTH * 0.5 / iMatsoDOFBokehQuality) : tex2Dlod(SamplerHDRX, float4(tcoord.xy, 0, 0));

		// my own pseudo-bokeh weighting
		float b = dot(ct.rgb, 0.333) + length(ct.rgb) + 0.1;
		float w = pow(abs(b), fMatsoDOFBokehCurve) + abs((float)i);

		blurcolor.xyz += ct.xyz * w;
		blurcolor.w += w;
	}

	blurcolor.xyz /= blurcolor.w;
	blurcolor.w = centerDepth;
	return blurcolor;
}

void PS_MatsoDOF1(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 hdr2R : SV_Target0)
{
	hdr2R = GetMatsoDOFBlur(2, texcoord, SamplerHDR1);	
}
void PS_MatsoDOF2(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 hdr1R : SV_Target0)
{
	hdr1R = GetMatsoDOFBlur(3, texcoord, SamplerHDR2);	
}
void PS_MatsoDOF3(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 hdr2R : SV_Target0)
{
	hdr2R = GetMatsoDOFBlur(0, texcoord, SamplerHDR1);	
}
void PS_MatsoDOF4(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 blurcolor : SV_Target)
{
	float4 noblurcolor = tex2D(ReShade::BackBuffer, texcoord);
	blurcolor = GetMatsoDOFBlur(1, texcoord, SamplerHDR2);
	float centerDepth = GetCoC(texcoord); //fullres coc data

	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS;

	discRadius*=(centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0; 

	//not 1.2 - 2.0 because matso's has a weird bokeh weighting that is almost like a tonemapping and border between blur and no blur appears to harsh
	blurcolor.xyz = lerp(noblurcolor.xyz,blurcolor.xyz,smoothstep(0.2,2.0,discRadius)); 
}

// MARTY MCFLY DOF
float2 GetDistortedOffsets(float2 intexcoord, float2 sampleoffset)
{
	float2 tocenter = intexcoord - float2(0.5, 0.5);
	float3 perp = normalize(float3(tocenter.y, -tocenter.x, 0.0));

	float rotangle = length(tocenter) * 2.221 * fADOF_ShapeDistortAmount;  
	float3 oldoffset = float3(sampleoffset, 0);

	float3 rotatedoffset =  oldoffset * cos(rotangle) + cross(perp, oldoffset) * sin(rotangle) + perp * dot(perp, oldoffset) * (1.0 - cos(rotangle));

	return rotatedoffset.xy;
}

float4 tex2Dchroma(sampler2D tex, float2 sourcecoord, float2 offsetcoord)
{
	float4 res = 0.0;

	float4 sample1 = tex2Dlod(tex, float4(sourcecoord.xy + offsetcoord.xy * (1.0 - fADOF_ShapeChromaAmount), 0, 0));
	float4 sample2 = tex2Dlod(tex, float4(sourcecoord.xy + offsetcoord.xy, 0, 0));
	float4 sample3 = tex2Dlod(tex, float4(sourcecoord.xy + offsetcoord.xy * (1.0 + fADOF_ShapeChromaAmount), 0, 0));

	if (iADOF_ShapeChromaMode == 0)		
		res.xyz = float3(sample1.x, sample2.y, sample3.z);
	else if (iADOF_ShapeChromaMode == 1)	
		res.xyz = float3(sample2.x, sample3.y, sample1.z);
	else if (iADOF_ShapeChromaMode == 2)
		res.xyz = float3(sample3.x, sample1.y, sample2.z);
	else if (iADOF_ShapeChromaMode == 3)
		res.xyz = float3(sample1.x, sample3.y, sample2.z);
	else if (iADOF_ShapeChromaMode == 4)
		res.xyz = float3(sample2.x, sample1.y, sample3.z);
	else if (iADOF_ShapeChromaMode == 5)
		res.xyz = float3(sample3.x, sample2.y, sample1.z);

	res.w = sample2.w;
	return res;
}

#if bADOF_ShapeTextureEnable
	#undef iADOF_ShapeVertices
	#define iADOF_ShapeVertices 4
#endif

uniform float Timer < source = "timer"; >;

float3 BokehBlur(sampler2D tex, float2 coord, float CoC, float centerDepth)
{
	float4 res = float4(tex2Dlod(tex, float4(coord.xy, 0.0, 0.0)).xyz, 1.0);
	int ringCount = round(lerp(1.0, (float)iADOF_ShapeQuality, CoC / DOF_BLURRADIUS));
	float rotAngle = fADOF_ShapeRotation;
	float2 discRadius = CoC * BUFFER_PIXEL_SIZE;
	float2 edgeVertices[iADOF_ShapeVertices + 1];

	if (bADOF_ShapeWeightEnable)
		res.w = (1.0 - fADOF_ShapeWeightAmount);

	res.xyz = pow(abs(res.xyz), fADOF_BokehCurve)*res.w;

	if (bADOF_ShapeAnamorphEnable)
		discRadius.x *= fADOF_ShapeAnamorphRatio;

	if (bADOF_RotAnimationEnable)
		rotAngle += fADOF_RotAnimationSpeed * Timer * 0.005;

	float2 Grain;
	if (bADOF_ShapeDiffusionEnable)
	{
		Grain = float2(frac(sin(coord.x + coord.y * 543.31) *  493013.0), frac(cos(coord.x - coord.y * 573.31) * 289013.0));
		Grain = (Grain - 0.5) * fADOF_ShapeDiffusionAmount + 1.0;
	}

	[unroll]
	for (int z = 0; z <= iADOF_ShapeVertices; z++)
	{
		sincos((6.2831853 / iADOF_ShapeVertices)*z + radians(rotAngle), edgeVertices[z].y, edgeVertices[z].x);
	}

	[fastopt]
	for (float i = 1; i <= ringCount; i++)
	{
		[fastopt]
		for (int j = 1; j <= iADOF_ShapeVertices; j++)
		{
			float radiusCoeff = i / ringCount;
			float blursamples = i;

#if bADOF_ShapeTextureEnable
			blursamples *= 2;
#endif

			[fastopt]
			for (float k = 0; k < blursamples; k++)
			{
				if (bADOF_ShapeApertureEnable)
					radiusCoeff *= 1.0 + sin(k / blursamples * 6.2831853 - 1.5707963)*fADOF_ShapeApertureAmount; // * 2 pi - 0.5 pi so it's 1x up and down in [0|1] space.

				float2 sampleOffset = lerp(edgeVertices[j - 1], edgeVertices[j], k / blursamples) * radiusCoeff;

				if (bADOF_ShapeCurvatureEnable)
					sampleOffset = lerp(sampleOffset, normalize(sampleOffset) * radiusCoeff, fADOF_ShapeCurvatureAmount);

				if (bADOF_ShapeDistortEnable)
					sampleOffset = GetDistortedOffsets(coord, sampleOffset);

				if (bADOF_ShapeDiffusionEnable)
					sampleOffset *= Grain;

				float4 tap = bADOF_ShapeChromaEnable ? tex2Dchroma(tex, coord, sampleOffset * discRadius) : tex2Dlod(tex, float4(coord.xy + sampleOffset.xy * discRadius, 0, 0));
				tap.w = (tap.w >= centerDepth*0.99) ? 1.0 : pow(abs(tap.w * 2.0 - 1.0), 4.0);

				if (bADOF_ShapeWeightEnable)
					tap.w *= lerp(1.0, pow(length(sampleOffset), fADOF_ShapeWeightCurve), fADOF_ShapeWeightAmount);

#if bADOF_ShapeTextureEnable
				tap.w *= tex2Dlod(SamplerMask, float4((sampleOffset + 0.707) * 0.707, 0, 0)).x;
#endif

				res.xyz += pow(abs(tap.xyz), fADOF_BokehCurve) * tap.w;
				res.w += tap.w;
			}
		}
	}

	res.xyz = max(res.xyz / res.w, 0.0);
	return pow(res.xyz, 1.0 / fADOF_BokehCurve);
}

void PS_McFlyDOF1(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 hdr2R : SV_Target0)
{
	texcoord /= DOF_RENDERRESMULT;

	float4 blurcolor = tex2D(SamplerHDR1, saturate(texcoord));

	float centerDepth = blurcolor.w;
	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS;

	discRadius *= (centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

	if (max(texcoord.x, texcoord.y) <= 1.05 && discRadius >= 1.2)
	{
		//doesn't bring that much with intelligent tap calculation
		blurcolor.xyz = (discRadius >= 1.2) ? BokehBlur(SamplerHDR1, texcoord, discRadius, centerDepth) : blurcolor.xyz;
		blurcolor.w = centerDepth;
	}

	hdr2R = blurcolor;
}
void PS_McFlyDOF2(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 scenecolor : SV_Target)
{   
	scenecolor = 0.0;
	float4 blurcolor = tex2D(SamplerHDR2, texcoord*DOF_RENDERRESMULT);
	float4 noblurcolor = tex2D(ReShade::BackBuffer, texcoord);
	
	float centerDepth = GetCoC(texcoord); 
	float blurAmount = abs(centerDepth * 2.0 - 1.0);
	float discRadius = blurAmount * DOF_BLURRADIUS;

	discRadius *= (centerDepth < 0.5) ? (1.0 / max(DOF_NEARBLURCURVE * 2.0, 1.0)) : 1.0;

#if __RENDERER__ < 0xa000 && !__RESHADE_PERFORMANCE_MODE__
	[flatten]
#endif
	if (bADOF_ImageChromaEnable)
	{
		float2 coord = texcoord * 2.0 - 1.0;
		float centerfact = length(coord);
		centerfact = pow(centerfact, fADOF_ImageChromaCurve) * fADOF_ImageChromaAmount;

		float chromafact = BUFFER_RCP_WIDTH * centerfact * discRadius;
		float3 chromadivisor = 0.0;

		for (float c = 0; c < iADOF_ImageChromaHues; c++)
		{
			float temphue = c / iADOF_ImageChromaHues;
			float3 tempchroma = saturate(float3(abs(temphue * 6.0 - 3.0) - 1.0, 2.0 - abs(temphue * 6.0 - 2.0), 2.0 - abs(temphue * 6.0 - 4.0)));
			float  tempoffset = (c + 0.5) / iADOF_ImageChromaHues - 0.5;
			float3 tempsample = tex2Dlod(SamplerHDR2, float4((coord.xy * (1.0 + chromafact * tempoffset) * 0.5 + 0.5) * DOF_RENDERRESMULT, 0, 0)).xyz;
			scenecolor.xyz += tempsample.xyz*tempchroma.xyz;
			chromadivisor += tempchroma;
		}

		scenecolor.xyz /= dot(chromadivisor.xyz, 0.333);
	}
	else
	{
		scenecolor = blurcolor;
	}

	scenecolor.xyz = lerp(scenecolor.xyz, noblurcolor.xyz, smoothstep(2.0,1.2,discRadius));

	scenecolor.w = centerDepth;
}
void PS_McFlyDOF3(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 scenecolor : SV_Target)
{
	scenecolor = tex2D(ReShade::BackBuffer, texcoord);
	float4 blurcolor = 0.0001;
	float outOfFocus = abs(scenecolor.w * 2.0 - 1.0);

	//move all math out of loop if possible
	float2 blurmult = smoothstep(0.3, 0.8, outOfFocus) * BUFFER_PIXEL_SIZE * fADOF_SmootheningAmount;

	float weights[3] = { 1.0,0.75,0.5 };
	//Why not separable? For the glory of Satan, of course!
	for (int x = -2; x <= 2; x++)
	{
		for (int y = -2; y <= 2; y++)
		{
			float2 offset = float2(x, y);
			float offsetweight = weights[abs(x)] * weights[abs(y)];
			blurcolor.xyz += tex2Dlod(ReShade::BackBuffer, float4(texcoord + offset.xy * blurmult, 0, 0)).xyz * offsetweight;
			blurcolor.w += offsetweight;
		}
	}

	scenecolor.xyz = blurcolor.xyz / blurcolor.w;

#if bADOF_ImageGrainEnable
	float ImageGrain = frac(sin(texcoord.x + texcoord.y * 543.31) *  893013.0 + Timer * 0.001);

	float3 AnimGrain = 0.5;
	float2 GrainPixelSize = BUFFER_PIXEL_SIZE / fADOF_ImageGrainScale;
	//My emboss noise
	AnimGrain += lerp(tex2D(SamplerNoise, texcoord * fADOF_ImageGrainScale + float2(GrainPixelSize.x, 0)).xyz, tex2D(SamplerNoise, texcoord * fADOF_ImageGrainScale + 0.5 + float2(GrainPixelSize.x, 0)).xyz, ImageGrain) * 0.1;
	AnimGrain -= lerp(tex2D(SamplerNoise, texcoord * fADOF_ImageGrainScale + float2(0, GrainPixelSize.y)).xyz, tex2D(SamplerNoise, texcoord * fADOF_ImageGrainScale + 0.5 + float2(0, GrainPixelSize.y)).xyz, ImageGrain) * 0.1;
	AnimGrain = dot(AnimGrain.xyz, 0.333);

	//Photoshop overlay mix mode
	float3 graincolor = (scenecolor.xyz < 0.5 ? (2.0 * scenecolor.xyz * AnimGrain.xxx) : (1.0 - 2.0 * (1.0 - scenecolor.xyz) * (1.0 - AnimGrain.xxx)));
	scenecolor.xyz = lerp(scenecolor.xyz, graincolor.xyz, pow(outOfFocus, fADOF_ImageGrainCurve) * fADOF_ImageGrainAmount);
#endif

	//focus preview disabled!
}

/////////////////////////TECHNIQUES/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////TECHNIQUES/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

technique RingDOF
{
	pass Focus { VertexShader = PostProcessVS; PixelShader = PS_Focus; RenderTarget = texHDR1; }
	pass RingDOF1 { VertexShader = PostProcessVS; PixelShader = PS_RingDOF1; RenderTarget = texHDR2; }
	pass RingDOF2 { VertexShader = PostProcessVS; PixelShader = PS_RingDOF2; /* renders to backbuffer*/ }
}

technique MagicDOF
{
	pass Focus { VertexShader = PostProcessVS; PixelShader = PS_Focus; RenderTarget = texHDR1; }
	pass MagicDOF1 { VertexShader = PostProcessVS; PixelShader = PS_MagicDOF1; RenderTarget = texHDR2; }
	pass MagicDOF2 { VertexShader = PostProcessVS; PixelShader = PS_MagicDOF2; /* renders to backbuffer*/ }
}

technique GP65CJ042DOF
{
	pass Focus { VertexShader = PostProcessVS; PixelShader = PS_Focus; RenderTarget = texHDR1; }
	pass GPDOF1 { VertexShader = PostProcessVS; PixelShader = PS_GPDOF1; RenderTarget = texHDR2; }
	pass GPDOF2 { VertexShader = PostProcessVS; PixelShader = PS_GPDOF2; /* renders to backbuffer*/ }
}

technique MatsoDOF
{
	pass Focus { VertexShader = PostProcessVS; PixelShader = PS_Focus; RenderTarget = texHDR1; }
	pass MatsoDOF1 { VertexShader = PostProcessVS; PixelShader = PS_MatsoDOF1; RenderTarget = texHDR2; }
	pass MatsoDOF2 { VertexShader = PostProcessVS; PixelShader = PS_MatsoDOF2; RenderTarget = texHDR1; }
	pass MatsoDOF3 { VertexShader = PostProcessVS; PixelShader = PS_MatsoDOF3; RenderTarget = texHDR2; }
	pass MatsoDOF4 { VertexShader = PostProcessVS; PixelShader = PS_MatsoDOF4; /* renders to backbuffer*/ }
}

technique MartyMcFlyDOF
{
	pass Focus { VertexShader = PostProcessVS; PixelShader = PS_Focus; RenderTarget = texHDR1; }
	pass McFlyDOF1 { VertexShader = PostProcessVS; PixelShader = PS_McFlyDOF1; RenderTarget = texHDR2; }
	pass McFlyDOF2 { VertexShader = PostProcessVS; PixelShader = PS_McFlyDOF2; /* renders to backbuffer*/ }
	pass McFlyDOF3 { VertexShader = PostProcessVS; PixelShader = PS_McFlyDOF3; /* renders to backbuffer*/ }
}
