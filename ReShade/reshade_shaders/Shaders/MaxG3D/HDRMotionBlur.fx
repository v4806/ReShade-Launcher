/**
 - Reshade HDR Motion Blur
 - Original code copyright, Jakob Wapenhensch
 - Tweaks and edits by MaxG3D
 **/


// Includes
#include "ReShadeUI.fxh"
#include "ReShade.fxh"
#include "HDRShadersFunctions.fxh"


// Defines
#ifndef BLUR_SAMPLES
#define BLUR_SAMPLES 20
#endif

#ifndef LINEAR_CONVERSION
#define LINEAR_CONVERSION 0
#endif

#ifndef FAKE_GAIN
#define FAKE_GAIN 0
#endif

#ifndef DEPTH_ENABLE
#define DEPTH_ENABLE 0
#endif

#define VELOCITY_SCALE 50.0
#define HALF_SAMPLES (BLUR_SAMPLES / 2)

static const int
	Linear = 0,
	Bezier = 1;

// UI
uniform int README
<
	ui_category = "使用说明";
	ui_category_closed = true;
	ui_label    = " ";
	ui_type     = "radio";
	ui_text     =
			"此着色器必须在其之前启用一个光流着色器，否则无法工作！";
>;

uniform uint UI_IN_COLOR_SPACE
<
	ui_label    = "输入色彩空间";
	ui_type     = "combo";
	ui_items    = "SDR sRGB\0HDR scRGB\0HDR10 BT.2020 PQ\0";
	ui_tooltip = "指定输入色彩空间\n对于HDR，请选择scRGB或HDR10";
	ui_category = "校准";
> = DEFAULT_COLOR_SPACE;

uniform uint UI_BLUR_CURVE
<
	ui_label    = "模糊曲线";
	ui_type     = "combo";
	ui_items    = "线性\0贝塞尔\0";
	ui_tooltip = "指定模糊的曲线形状"
	"\n""\n" "默认使用贝塞尔曲线，效果更具电影感"
	"\n" "也可使用线性采样，效果更人工但更闪亮";
	ui_category = "动态模糊";
> = Bezier;

uniform float  UI_BLUR_LENGTH <
	ui_min = 0.1; ui_max = 1.0; ui_step = 0.01;
	ui_type = "slider";
	ui_label = "模糊长度";
	ui_tooltip =
	"模糊量的缩放。";
	ui_category = "动态模糊";
> = 0.25;

/*
uniform int  UI_BLUR_SAMPLES_MAX <
	ui_min = 8; ui_max = 64; ui_step = 1;
	ui_type = "slider";
	ui_label = "Blur Samples";
	ui_tooltip =
	"How many samples is used for every pixel."
	"\n" "It is basically a quality tuner.";
	ui_category = "动态模糊";
> = 20;
*/

uniform float  UI_BLUR_BLUE_NOISE <
	ui_min = 0.0; ui_max = 1; ui_step = 0.01;
	ui_type = "slider";
	ui_label = "蓝噪声";
	ui_tooltip =
	"应用于像素采样坐标的蓝噪声量缩放。";
	ui_category = "动态模糊";
> = 0.25;

uniform bool UI_BLUR_BLUE_NOISE_DEBUG
<
	ui_label = "蓝噪声调试";
	ui_tooltip =
		"显示蓝噪声阈值。";
	ui_category = "动态模糊 - 高级";
> = false;

uniform float  UI_BLUR_LENGTH_CLAMP <
	ui_min = 0.05; ui_max = 1; ui_step = 0.001;
	ui_type = "slider";
	ui_label = "模糊长度限制";
	ui_tooltip =
	"最大模糊长度的限制。"
	"\n" "有助于在保持基于物体的强模糊的同时降低基于屏幕的运动。";
	ui_category = "动态模糊 - 高级";
> = 0.135;

uniform float  UI_BLUR_CENTER_SAMPLING <
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
	ui_type = "slider";
	ui_label = "模糊采样: 中心->滞后";
	ui_tooltip =
	"中心采样和前一帧采样之间的插值缩放。";
	ui_category = "动态模糊 - 高级";
> = 0.20;

uniform float  UI_BLUR_BLUE_THRESHOLD <
	ui_min = 0.000050; ui_max = 0.001000; ui_step = 0.000001;
	ui_type = "slider";
	ui_label = "蓝噪声阈值";
	ui_tooltip =
	"蓝噪声采样启动前的速度向量长度阈值。";
	ui_category = "动态模糊 - 高级";
> = 0.000125;

#if DEPTH_ENABLE
uniform float  UI_BLUR_DEPTH_WEIGHT <
	ui_label = "模糊深度权重";
	ui_min = 0.0;
	ui_max = 1000.0;
	ui_step = 0.01;
	ui_type = "slider";
	ui_tooltip =
	"深度对模糊的影响程度 - 深度对比度。";
	ui_category = "深度";
> = 20.00;

uniform float  UI_BLUR_DEPTH_BLUR_EDGES <
	ui_label = "模糊深度边缘模糊";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_step = 0.01;
	ui_type = "slider";
	ui_tooltip =
	"深度纹理模糊程度以使边缘更柔和";
	ui_category = "深度";
> = 6;

uniform int  UI_BLUR_DEPTH_BLUR_SAMPLES <
	ui_label = "模糊深度模糊采样";
	ui_min = 6;
	ui_max = 32;
	ui_step = 1;
	ui_type = "slider";
	ui_tooltip =
	"用于深度纹理模糊的采样数量";
	ui_category = "深度";
> = 16;

uniform bool UI_SHOW_DEPTH
<
	ui_category = "深度";
	ui_label = "显示深度";
	ui_tooltip =
		"显示深度纹理。";
> = false;
#endif

#if FAKE_GAIN
uniform bool UI_GAIN_THRESHOLD_DEBUG
<
	ui_label = "伪增益阈值调试";
	ui_tooltip =
	"显示增益阈值。";
	ui_category = "HDR模拟";
> = false;

uniform bool UI_GAIN_SCALE_DEBUG
<
	ui_label = "应用缩放的调试";
	ui_tooltip =
	"显示应用缩放后的增益阈值。";
	ui_category = "HDR模拟";
> = false;

uniform float UI_GAIN_SCALE <
	ui_label = "伪增益缩放";
	ui_min = 0.0;
	ui_max = 600.0;
	ui_step = 1;
	ui_type = "slider";
	ui_tooltip =
	"缩放增益对模糊像素的贡献。"
	"\n" "\n" "0.0基本上没有增益，而10.0是高度增强的高光。设为1.0获得相当中性的增强。";
	ui_category = "HDR模拟";
> = 550.0;

uniform float UI_GAIN_THRESHOLD <
	ui_label = "伪增益阈值";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.01;
	ui_type = "slider";
	ui_tooltip =
	"亮度高于此值的像素将被增强。";
	ui_category = "HDR模拟";
> = 0.9;

uniform float UI_GAIN_THRESHOLD_SMOOTH <
	ui_label = "伪增益平滑度";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_step = 0.01;
	ui_type = "slider";
	ui_tooltip =
	"在亮度最大值和最小值之间平滑插值的阈值。";
	ui_category = "HDR模拟";
> = 0.9;
#endif

namespace HDRShaders
{
	// Textures & Samplers
	texture DepthBufferTexture : DEPTH;
	sampler SamplerDepth
	{
		Texture = DepthBufferTexture;
	};

	texture DepthProcessedTex
	{
			Width = BUFFER_WIDTH;
			Height = BUFFER_HEIGHT;
	};
	sampler SamplerDepthProcessed
	{
		    Texture = DepthProcessedTex;
		    MinFilter = LINEAR;
		    MagFilter = LINEAR;
	};

// Namespace
}


texture texMotionVectors
{
		Width = BUFFER_WIDTH;
		Height = BUFFER_HEIGHT;
		Format = RG16F;
};
sampler SamplerMotionVectors2
{
		Texture = texMotionVectors;
		AddressU = Clamp;
		AddressV = Clamp;
		MipFilter = Point;
		MinFilter = Point;
		MagFilter = Point;
};

// Depth Procesing Pixels Shader
#if DEPTH_ENABLE
float4 DepthProcessPS(float4 p : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
	float4 ProcessedDepth = GetLinearizedDepth(HDRShaders::SamplerDepth, texcoord).xxxx;
	float NormalizeDepth = normalize(ProcessedDepth.xyzw).x;

	if (NormalizeDepth.x >= 0.9999999)
		ProcessedDepth = 0.f;
	return ProcessedDepth;
}
#endif

// Main Pixel Shader
float4 BlurPS(float4 p : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
	uint inColorSpace = UI_IN_COLOR_SPACE;

	static float2 Velocity = tex2D(SamplerMotionVectors2, texcoord).xy;
	static float2 VelocityTimed = Velocity / frametime;
	float2 BlurDist = 0;

	#if DEPTH_ENABLE
		float4 Depthbuffer = CircularBlur(HDRShaders::SamplerDepthProcessed, texcoord, UI_BLUR_DEPTH_BLUR_EDGES, UI_BLUR_DEPTH_BLUR_SAMPLES, 1);
		float4 DepthBufferScaled = saturate(min(pow((1.0 - Depthbuffer.xyzw), UI_BLUR_DEPTH_WEIGHT), 1));

		BlurDist = VelocityTimed * VELOCITY_SCALE * (DepthBufferScaled.xx) * UI_BLUR_LENGTH;
	#else
		BlurDist = VelocityTimed * VELOCITY_SCALE * UI_BLUR_LENGTH;
	#endif

	// Clamp large displacements
	BlurDist = ClampMotionVector(BlurDist, UI_BLUR_LENGTH_CLAMP/10);
	static const float HalfSampleSwitch = HALF_SAMPLES * (UI_BLUR_CENTER_SAMPLING);
	static const float HalfSampleSwitchInv = HALF_SAMPLES * (1.0 - UI_BLUR_CENTER_SAMPLING);
	static const float SamplesMinusOne = BLUR_SAMPLES - 1;
	float2 SampleDist = (BlurDist / SamplesMinusOne) * (lerp(1, 0.5, UI_BLUR_CENTER_SAMPLING));
	float SampleDistVector = dot(SampleDist, 0.25);

	// Define control points for the cubic Bezier curve
	static const float2 p0 = texcoord;
	float2 p1 = texcoord + BlurDist * 0.33;
	float2 p2 = texcoord + BlurDist * 0.66;
	float2 p3 = texcoord + BlurDist;

	float4 SummedSamples = 0;
	float4 Sampled = 0;
	float4 Color = tex2D(ReShade::BackBuffer, texcoord);
	float2 NoiseOffset = 0;
	if (abs(SampleDistVector) > UI_BLUR_BLUE_THRESHOLD)
	{
		NoiseOffset = BlueNoise(texcoord + SampleDist * (0 - HalfSampleSwitch)) * 0.001);
		Sampled += float3(1, 0, 0);
	}

	if (UI_BLUR_CURVE == 1)
	{
		// Blur Loop - Bezier
		for (float s = 0.0; s <= 1.0; s += 1.0 / BLUR_SAMPLES)
		{
			float2 SampleCoord = BezierCurveCubic(p0, p1, p2, p3, s);
			Sampled = tex2D(ReShade::BackBuffer, SampleCoord + SampleDist * (s - HalfSampleSwitchInv) + (NoiseOffset * UI_BLUR_BLUE_NOISE * 2));

			if (UI_BLUR_BLUE_NOISE_DEBUG)
			{
				if (abs(SampleDistVector) > UI_BLUR_BLUE_THRESHOLD)
				{
					Sampled += float3(1, 0, 0);
				}
			}

			// HDR10 BT.2020 PQ
			[branch]
			if (inColorSpace == 2)
			{
				Sampled.rgb = clamp(Sampled.rgb, -FLT16_MAX, FLT16_MAX);
				Sampled.rgb = PQToLinear(Sampled.rgb);
			}

			#if LINEAR_CONVERSION
				Sampled.rgb = sRGBToLinear_Safe(Sampled.rgb);
			#endif

			SummedSamples += Sampled / BLUR_SAMPLES;
			Color.rgb = max(Color.rgb, Sampled.rgb);
		}
	}

	else if (UI_BLUR_CURVE == 0)
	{
		// Blur Loop - Linear
		for (int s = 0; s < BLUR_SAMPLES; s++)
		{
			Sampled = tex2D(ReShade::BackBuffer, texcoord + SampleDist * (s - HalfSampleSwitchInv) + (NoiseOffset * UI_BLUR_BLUE_NOISE));

			if (UI_BLUR_BLUE_NOISE_DEBUG)
			{
				if (abs(SampleDistVector) > UI_BLUR_BLUE_THRESHOLD)
				{
					Sampled += float3(1, 0, 0);
				}
			}

			// HDR10 BT.2020 PQ
			[branch]
		    if (inColorSpace == 2)
		    {
		    	Sampled.rgb = clamp(Sampled.rgb, -FLT16_MAX, FLT16_MAX);
		        Sampled.rgb = PQToLinear(Sampled.rgb);
		    }

		    #if LINEAR_CONVERSION
		        Sampled.rgb = sRGBToLinear_Safe(Sampled.rgb);
		    #endif

			SummedSamples += Sampled / BLUR_SAMPLES;
			Color.rgb = max(Color.rgb, Sampled.rgb);
		}
	}

	// Luma Luminance
	//float LuminanceLuma = dot(SummedSamples.rgb, inColorSpace == 1 || inColorSpace == 2 ? lumCoeffHDR : lumCoeffsRGB);

	// OKLab Luminance
	static const float OklabLightness = RGBToOKLab(SummedSamples.rgb)[0];
	static const float OklabLuminance = OklabLightness * OklabLightness * OklabLightness * OklabLightness;
	float Luminance = OklabLuminance;
	if (Luminance < 0.0001f)
	{
		Luminance = -0.0001f;
	}
	static const float ClampedLuminance = clamp(Luminance, 0.0, Luminance/Luminance);

	float4 Finalcolor = 0.0;
	float Gain = 0.0;

	[branch]
	    #if FAKE_GAIN
	    [branch]
	    if (inColorSpace == 1 || inColorSpace == 2)
	    {
	    // Refined approach specifically for HDR
	    	if (UI_GAIN_SCALE > 0.0)
	    	{
		        Gain = smoothstep(UI_GAIN_THRESHOLD - UI_GAIN_THRESHOLD_SMOOTH * Luminance, UI_GAIN_THRESHOLD * pow(FLT16_MAX * Luminance, 0.5), Luminance);
				Gain *= pow(UI_GAIN_SCALE, UI_GAIN_SCALE * 0.002);
				Gain = BrightnessLimiter(ClampedLuminance, Gain);
				//Gain = max(Gain, 0.f);
			}
		}
	    else
	    {
	    	if (UI_GAIN_SCALE > 0.0)
	    	{
		        Gain = smoothstep(UI_GAIN_THRESHOLD - UI_GAIN_THRESHOLD_SMOOTH, UI_GAIN_THRESHOLD, saturate(Luminance));
				Gain *= UI_GAIN_SCALE;
		    /* Old approach made in nightmarish SDR days

		        Gain = smoothstep(UI_GAIN_THRESHOLD - UI_GAIN_THRESHOLD_SMOOTH, UI_GAIN_THRESHOLD, luminance);
				Gain *= smoothstep(-UI_GAIN_THRESHOLD_SMOOTH, 1.0, luminance);
				Gain *= UI_GAIN_SCALE;
			*/
			}
		}
	    #endif

	[branch]
	    #if FAKE_GAIN
	        Finalcolor = SaturationBrightnessLimiter(Color.rgb , SummedSamples.rgb * (1.0 - Gain) + Color.rgb * Gain);
			if (UI_GAIN_THRESHOLD_DEBUG)
			{
				Finalcolor = UI_GAIN_SCALE_DEBUG ? Gain.rrrr : Gain.rrrr / UI_GAIN_SCALE;
			}
	    #else
	        Finalcolor = SummedSamples;
	    #endif

	[branch]
	    #if LINEAR_CONVERSION
	        Finalcolor.rgb = LinearTosRGB_Safe(Finalcolor.rgb);
	    #endif

	// HDR10 BT.2020 PQ
	if (inColorSpace == 2)
	{
		Finalcolor.rgb = fixNAN(Finalcolor.rgb);
		Finalcolor.rgb = LinearToPQ(Finalcolor.rgb);
	}

	// SDR
	if (inColorSpace == 0)
	{
		Finalcolor *= 1.0 / max(dot(SummedSamples.rgb, lumCoeffsRGB), 1.0);
		clamp(Finalcolor, 0.0, 1.0);
	}

	#if DEPTH_ENABLE
		Finalcolor = UI_SHOW_DEPTH ? DepthBufferScaled.xxxx : Finalcolor;
	#endif

	return Finalcolor;
}

technique HDRMotionBlur <
ui_label = "HDRMotionBlur";>
{
	#if DEPTH_ENABLE
	pass DepthProcess
	{
		VertexShader = PostProcessVS;
		PixelShader = DepthProcessPS;
		RenderTarget = HDRShaders::DepthProcessedTex;
	}
	#endif

	pass MotionBlurPass
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurPS;
	}
}
