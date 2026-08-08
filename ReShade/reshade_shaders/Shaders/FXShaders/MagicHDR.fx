//#region Includes

#include "FXShaders/API.fxh"
#include "FXShaders/Canvas.fxh"
#include "FXShaders/Common.fxh"
#include "FXShaders/Convolution.fxh"
#include "FXShaders/Math.fxh"
#include "FXShaders/Tonemap.fxh"

//#endregion

//#region Preprocessor Directives

#ifndef MAGIC_HDR_BLUR_SAMPLES
#define MAGIC_HDR_BLUR_SAMPLES 13
#endif

#if MAGIC_HDR_BLUR_SAMPLES < 1
	#error "Blur samples cannot be less than 1"
#endif

#ifndef MAGIC_HDR_DOWNSAMPLE
#define MAGIC_HDR_DOWNSAMPLE 4
#endif

#if MAGIC_HDR_DOWNSAMPLE < 1
	#error "Downsample cannot be less than 1x"
#endif

#ifndef MAGIC_HDR_SRGB_INPUT
#define MAGIC_HDR_SRGB_INPUT 1
#endif

#ifndef MAGIC_HDR_SRGB_OUTPUT
#define MAGIC_HDR_SRGB_OUTPUT 1
#endif

#ifndef MAGIC_HDR_ENABLE_ADAPTATION
#define MAGIC_HDR_ENABLE_ADAPTATION 0
#endif

//#endregion

namespace FXShaders
{

//#region Constants

static const int2 DownsampleAmount = MAGIC_HDR_DOWNSAMPLE;

static const int BlurSamples = MAGIC_HDR_BLUR_SAMPLES;

static const float2 AdaptFocusPointDebugSize = 10.0;

static const int
	InvTonemap_Reinhard = 0,
	InvTonemap_Lottes = 1,
	InvTonemap_Unreal3 = 2,
	InvTonemap_NarkowiczACES = 3,
	InvTonemap_Uncharted2Filmic = 4,
	InvTonemap_BakingLabACES = 5;

static const int
	Tonemap_Reinhard = 0,
	Tonemap_Lottes = 1,
	Tonemap_Unreal3 = 2,
	Tonemap_NarkowiczACES = 3,
	Tonemap_Uncharted2Filmic = 4,
	Tonemap_BakingLabACES = 5;

//#endregion

//#region Uniforms

FXSHADERS_WIP_WARNING();

FXSHADERS_CREDITS();

FXSHADERS_HELP(
	"This effect allows you to add both bloom and tonemapping, drastically "
	"changing the mood of the image.\n"
	"\n"
	"Care should be taken to select an appropriate inverse tonemapper that can "
	"accurately extract HDR information from the original image.\n"
	"HDR10 users should also take care to select a tonemapper that's "
	"compatible with what the HDR monitor is expecting from the LDR output of "
	"the game, which *is* tonemapped too.\n"
	"\n"
	"Available preprocessor directives:\n"
	"\n"
	"MAGIC_HDR_BLUR_SAMPLES:\n"
	"  Determines how many pixels are sampled during each blur pass for the "
	"bloom effect.\n"
	"  This value directly influences the Blur Size, so the more samples the "
	"bigger the blur size can be.\n"
	"  Setting MAGIC_HDR_DOWNSAMPLE above 1x will also increase the blur size "
	"to compensate for the lower resolution. This effect may be desirable, "
	"however.\n"
	"\n"
	"MAGIC_HDR_DOWNSAMPLE:\n"
	"  Serves to divide the resolution of the textures used for processing the "
	"bloom effect.\n"
	"  Leave at 1x for maximum detail, 2x or 4x should still be fine.\n"
	"  Values too high may introduce flickering.\n"
);

uniform float InputExposure
<
	ui_category = "色调映射";
	ui_label = "输入曝光";
	ui_tooltip =
		"原始图像的近似曝光。\n"
		"该值以f档为单位测量。\n"
		"\n默认: 1.0";
	ui_type = "slider";
	ui_min = -3.0;
	ui_max = 3.0;
> = 0.0;

uniform float Exposure
<
	ui_category = "色调映射";
	ui_label = "输出曝光";
	ui_tooltip =
		"效果结束时应用的曝光。\n"
		"该值以f档为单位测量。\n"
		"\n默认: 1.0";
	ui_type = "slider";
	ui_min = -3.0;
	ui_max = 3.0;
> = 0.0;

uniform int InvTonemap
<
	ui_category = "色调映射";
	ui_label = "逆向色调映射器";
	ui_tooltip =
		"用于获取HDR信息的逆向色调映射运算符。\n"
		"\n默认: Reinhard";
	ui_type = "combo";
	ui_items =
		"Reinhard\0Lottes\0Unreal 3\0Narkowicz ACES\0Uncharted 2 Filmic\0Baking Lab ACES\0";
> = InvTonemap_Reinhard;

uniform int Tonemap
<
	ui_category = "色调映射";
	ui_label = "输出色调映射器";
	ui_tooltip =
		"效果结束时应用的色调映射运算符。\n"
		"\n默认: Baking Lab ACES";
	ui_type = "combo";
	ui_items =
		"Reinhard\0Lottes\0Unreal 3\0Narkowicz ACES\0Uncharted 2 Filmic\0Baking Lab ACES\0";
> = Tonemap_BakingLabACES;

uniform float BloomAmount
<
	ui_category = "泛光";
	ui_category_closed = true;
	ui_label = "数量";
	ui_tooltip =
		"应用于图像的泛光量。\n"
		"\n默认: 0.3";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.3;

uniform float BloomBrightness
<
	ui_category = "泛光";
	ui_label = "亮度";
	ui_tooltip =
		"该值用于乘以泛光纹理亮度。\n"
		"这与数量不同，因为它直接影响亮度，\n"
		"而不是作为HDR颜色和泛光颜色之间混合的百分比。\n"
		"\n默认: 3.0";
	ui_type = "slider";
	ui_min = 1.0;
	ui_max = 5.0;
> = 3.0;

uniform float BloomSaturation
<
	ui_category = "泛光";
	ui_label = "饱和度";
	ui_tooltip =
		"确定泛光的饱和度。\n"
		"\n默认: 1.0";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 2.0;
> = 1.0;

uniform float BlurSize
<
	ui_category = "泛光 - 高级";
	ui_category_closed = true;
	ui_label = "模糊大小";
	ui_tooltip =
		"用于创建泛光效果的高斯模糊大小。\n"
		"该值直接受MAGIC_HDR_BLUR_SAMPLES和\n"
		"MAGIC_HDR_DOWNSAMPLE的值影响。\n"
		"\n默认: 0.5";
	ui_type = "slider";
	ui_min = 0.01;
	ui_max = 1.0;
> = 0.5;

uniform float BlendingAmount
<
	ui_category = "泛光 - 高级";
	ui_label = "混合量";
	ui_tooltip =
		"内部使用的各种泛光纹理之间的混合程度。\n"
		"减小该值会使泛光更均匀，变化更少。\n"
		"\n默认: 0.5";
	ui_type = "slider";
	ui_min = 0.1;
	ui_max = 1.0;
> = 0.5;

uniform float BlendingBase
<
	ui_category = "泛光 - 高级";
	ui_label = "混合基数";
	ui_tooltip =
		"确定混合时的基础泛光大小。\n"
		"在较低的混合量下更有效。\n"
		"\n默认: 0.8";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.8;

#if MAGIC_HDR_ENABLE_ADAPTATION

uniform float AdaptTime
<
	ui_category = "自适应";
	ui_category_closed = true;
	ui_label = "延迟";
	ui_tooltip =
		"确定自适应在前一个值和下一个值之间过渡所需的时间（秒）。\n"
		"\n默认: 1.0";
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_step = 0.001;
> = 1.0;

uniform float2 AdaptMinMax
<
	ui_category = "自适应";
	ui_label = "范围";
	ui_tooltip =
		"分别确定自适应的最小和最大值。\n"
		"增加最小值将减少图像可以变亮的程度。\n"
		"减少最大值将减少图像可以变暗的程度。\n"
		"\n默认: 0.0 1.0";
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 3.0;
	ui_step = 0.001;
> = float2(0.0, 1.0);

uniform float AdaptSensitivity
<
	ui_category = "自适应 - 高级";
	ui_category_closed = true;
	ui_label = "灵敏度";
	ui_tooltip =
		"确定自适应对明亮物体的敏感程度。\n"
		"\n默认: 1.0";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 2.0;
> = 1.0;

uniform float AdaptPrecision
<
	ui_category = "自适应 - 高级";
	ui_label = "精度";
	ui_tooltip =
		"确定图像的哪些部分对自适应影响更大。\n"
		"在0.0时，自适应受整个图像的平均影响。\n"
		"在1.0时，自适应将更多地受到靠近焦点的物体的影响。\n"
		"\n默认: 0.0";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.0;

uniform float2 AdaptPoint
<
	ui_category = "自适应 - 高级";
	ui_label = "焦点";
	ui_tooltip =
		"确定屏幕上用于确定自适应值的点。\n"
		"第一个值确定水平位置，从左到右。\n"
		"第二个值确定垂直位置，从上到下。\n"
		"(0.5, 0.5)是屏幕中心。\n"
		"\n默认: 0.5 0.5";
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
> = 0.5;

uniform float FrameTime <source = "frametime";>;

#endif

uniform bool ShowBloom
<
	ui_category = "调试";
	ui_category_closed = true;
	ui_label = "显示泛光";
	ui_tooltip =
		"显示泛光纹理。\n"
		"\n默认: 关";
> = false;

#if MAGIC_HDR_ENABLE_ADAPTATION

uniform bool ShowAdapt
<
	ui_category = "调试";
	ui_label = "显示自适应";
	ui_tooltip =
		"显示用于自适应的纹理和焦点。\n"
		"\n默认: 关";
> = false;

#endif

//#endregion

//#region Textures

texture ColorTex : COLOR;

sampler Color
{
	Texture = ColorTex;

	#if MAGIC_HDR_SRGB_INPUT
		SRGBTexture = true;
	#endif
};

#define DEF_DOWNSAMPLED_TEX(name, downscale, maxMip) \
texture name##Tex <pooled = true;> \
{ \
	Width = BUFFER_WIDTH / DownsampleAmount.x / downscale; \
	Height = BUFFER_HEIGHT / DownsampleAmount.y / downscale; \
	Format = RGBA16F; \
	MipLevels = maxMip; \
}; \
\
sampler name \
{ \
	Texture = name##Tex; \
}

// This texture is used as a sort of "HDR backbuffer".
DEF_DOWNSAMPLED_TEX(Temp, 1, 1);

// These are the textures in which the many bloom LODs are stored.
DEF_DOWNSAMPLED_TEX(Bloom0, 1, 1);
DEF_DOWNSAMPLED_TEX(Bloom1, 2, 1);
DEF_DOWNSAMPLED_TEX(Bloom2, 4, 1);
DEF_DOWNSAMPLED_TEX(Bloom3, 8, 1);
DEF_DOWNSAMPLED_TEX(Bloom4, 16, 1);
DEF_DOWNSAMPLED_TEX(Bloom5, 32, 1);

#if MAGIC_HDR_ENABLE_ADAPTATION
	#if FXSHADERS_API_IS(FXSHADERS_API_OPENGL)
		#define MAGIC_HDR_ADAPT_TEXTURE_RESOLUTION \
			FXSHADERS_NPOT(FXSHADERS_MAX(BUFFER_WIDTH, BUFFER_HEIGHT) / 64)

		texture Bloom6Tex <pooled = true;>
		{
			Width = MAGIC_HDR_ADAPT_TEXTURE_RESOLUTION;
			Height = MAGIC_HDR_ADAPT_TEXTURE_RESOLUTION;
			Format = RGBA16F;
			MipLevels = FXSHADERS_GET_MAX_MIP(
				MAGIC_HDR_ADAPT_TEXTURE_RESOLUTION,
				MAGIC_HDR_ADAPT_TEXTURE_RESOLUTION);
		};

		sampler Bloom6
		{
			Texture = Bloom6Tex;
		};
	#else
		DEF_DOWNSAMPLED_TEX(
			Bloom6,
			64,
			FXSHADERS_GET_MAX_MIP(BUFFER_WIDTH / 64, BUFFER_HEIGHT / 64));
	#endif
#else
	DEF_DOWNSAMPLED_TEX(Bloom6, 64, 1);
#endif

#if MAGIC_HDR_ENABLE_ADAPTATION

texture AdaptTex <pooled = true;>
{
	Format = R32F;
};

sampler Adapt
{
	Texture = AdaptTex;
};

texture LastAdaptTex
{
	Format = R32F;
};

sampler LastAdapt
{
	Texture = LastAdaptTex;
};

#endif

//#endregion

//#region Functions


float3 ApplyInverseTonemap(float3 color, float2 uv)
{
	switch (InvTonemap)
	{
		case InvTonemap_Reinhard:
			color = Tonemap::Reinhard::Inverse(color);
			break;
		case InvTonemap_Lottes:
			color = Tonemap::Lottes::Inverse(color);
			break;
		case InvTonemap_Unreal3:
			color = Tonemap::Unreal3::Inverse(color);
			break;
		case InvTonemap_NarkowiczACES:
			color = Tonemap::NarkowiczACES::Inverse(color);
			break;
		case InvTonemap_Uncharted2Filmic:
			color = Tonemap::Uncharted2Filmic::Inverse(color);
			break;
		case InvTonemap_BakingLabACES:
			color = Tonemap::BakingLabACES::Inverse(color);
			break;
	}

	color /= exp(InputExposure);

	return color;
}

float3 ApplyTonemap(float3 color, float2 uv)
{
	float exposure = exp(Exposure);

	#if MAGIC_HDR_ENABLE_ADAPTATION
		exposure /= tex2Dfetch(Adapt, 0).x;
	#endif

	switch (Tonemap)
	{
		case Tonemap_Reinhard:
			color = Tonemap::Reinhard::Apply(color * exposure);
			break;
		case Tonemap_Lottes:
			color = Tonemap::Lottes::Apply(color * exposure);
			break;
		case Tonemap_Unreal3:
			color = Tonemap::Unreal3::Apply(color * exposure);
			break;
		case Tonemap_NarkowiczACES:
			color = Tonemap::NarkowiczACES::Apply(color * exposure);
			break;
		case Tonemap_Uncharted2Filmic:
			color = Tonemap::Uncharted2Filmic::Apply(color * exposure);
			break;
		case Tonemap_BakingLabACES:
			color = Tonemap::BakingLabACES::Apply(color * exposure);
			break;
	}

	return color;
}

float4 Blur(sampler sp, float2 uv, float2 dir)
{
	float4 color = GaussianBlur1D(
		sp,
		uv,
		dir * GetPixelSize() * DownsampleAmount,
		sqrt(BlurSamples) * BlurSize,
		BlurSamples);

	return color;
}

#if MAGIC_HDR_ENABLE_ADAPTATION

float GetAdaptSensitivity()
{
	return log10(AdaptSensitivity + 1.0);
}

#endif

//#endregion

//#region Shaders

float4 InverseTonemapPS(
	float4 p : SV_POSITION,
	float2 uv : TEXCOORD) : SV_TARGET
{
	float4 color = tex2D(Color, uv);

	float saturation = (BloomSaturation > 1.0)
		? pow(abs(BloomSaturation), 2.0)
		: BloomSaturation;

	color.rgb = saturate(ApplySaturation(color.rgb, saturation));

	color.rgb = ApplyInverseTonemap(color.rgb, uv);

	// TODO: Saturation and other color filtering options?
	color.rgb *= exp(BloomBrightness);

	return color;
}

#define DEF_BLUR_SHADER(x, y, input, scale) \
float4 Blur##x##PS( \
	float4 p : SV_POSITION, \
	float2 uv : TEXCOORD) : SV_TARGET \
{ \
	return Blur(input, uv, float2(scale, 0.0)); \
} \
\
float4 Blur##y##PS( \
	float4 p : SV_POSITION, \
	float2 uv : TEXCOORD) : SV_TARGET \
{ \
	return Blur(Temp, uv, float2(0.0, scale)); \
}

DEF_BLUR_SHADER(0, 1, Bloom0, 1)
DEF_BLUR_SHADER(2, 3, Bloom0, 2)
DEF_BLUR_SHADER(4, 5, Bloom1, 4)
DEF_BLUR_SHADER(6, 7, Bloom2, 8)
DEF_BLUR_SHADER(8, 9, Bloom3, 16)
DEF_BLUR_SHADER(10, 11, Bloom4, 32)
DEF_BLUR_SHADER(12, 13, Bloom5, 64)

#if MAGIC_HDR_ENABLE_ADAPTATION

float4 CalcAdaptPS(
	float4 p : SV_POSITION,
	float2 uv : TEXCOORD) : SV_TARGET
{
	#if FXSHADERS_API_IS(FXSHADERS_API_OPENGL)
		float mip = FXSHADERS_GET_MAX_MIP(
			MAGIC_HDR_ADAPT_TEXTURE_RESOLUTION,
			MAGIC_HDR_ADAPT_TEXTURE_RESOLUTION);
	#else
		float mip = FXSHADERS_GET_MAX_MIP(
			BUFFER_WIDTH / 64,
			BUFFER_HEIGHT / 64);
	#endif

	mip *= AdaptPrecision;

	float3 color = tex2Dlod(Bloom6, float4(AdaptPoint, 0.0, mip)).rgb;
	float adapt = GetLumaLinear(color);

	// adapt = lerp(0.5, adapt, AdaptSensitivity);
	adapt *= GetAdaptSensitivity();

	float2 minMax = AdaptMinMax;
	minMax = (minMax.x > minMax.y) ? minMax.yx : minMax;

	adapt = clamp(adapt, max(minMax.x, 0.001), minMax.y);

	if (AdaptTime > 0.001)
	{
		float last = tex2Dfetch(LastAdapt, 0).x;
		float dt = FrameTime * 0.001;

		adapt = lerp(last, adapt, saturate(dt / max(AdaptTime, 0.001)));
	}

	return adapt;
}

float4 SaveAdaptPS(
	float4 p : SV_POSITION,
	float2 uv : TEXCOORD) : SV_TARGET
{
	return tex2Dfetch(Adapt, 0);
}

#endif

float4 TonemapPS(
	float4 p : SV_POSITION,
	float2 uv : TEXCOORD) : SV_TARGET
{
	#if MAGIC_HDR_ENABLE_ADAPTATION
		if (ShowAdapt)
		{
			float mip = FXSHADERS_GET_MAX_MIP(
				BUFFER_WIDTH / 64,
				BUFFER_HEIGHT / 64) * AdaptPrecision;

			float4 color = tex2Dlod(Bloom6, float4(uv, 0.0, mip));
			color.rgb *= GetAdaptSensitivity();
			//color.rgb = lerp(0.5, color.rgb, AdaptSensitivity);

			float2 res = GetResolution();
			float2 coord = uv * res;
			float2 pointPos = AdaptPoint * res;

			float4 pointColor = float4(1.0 - color.rgb, color.a);
			pointColor.rgb = (abs(pointColor.rgb - color.rgb) < 0.1)
				? pointColor.rgb * 1.5
				: pointColor.rgb;

			float4 rect = ConvertToRect(pointPos, AdaptFocusPointDebugSize);

			FillRect(color, coord, rect, pointColor);

			return color;
		}
	#endif

	float4 color = tex2D(Color, uv);
	color.rgb = ApplyInverseTonemap(color.rgb, uv);

	float mean = BlendingBase * 7;
	float variance = BlendingAmount * 7;

	float4 bloom =
		tex2D(Bloom0, uv) * NormalDistribution(1, mean, variance) +
		tex2D(Bloom1, uv) * NormalDistribution(2, mean, variance) +
		tex2D(Bloom2, uv) * NormalDistribution(3, mean, variance) +
		tex2D(Bloom3, uv) * NormalDistribution(4, mean, variance) +
		tex2D(Bloom4, uv) * NormalDistribution(5, mean, variance) +
		tex2D(Bloom5, uv) * NormalDistribution(6, mean, variance) +
		tex2D(Bloom6, uv) * NormalDistribution(7, mean, variance);

	bloom /= 7;

	color.rgb = ShowBloom
		? bloom.rgb
		: lerp(color.rgb, bloom.rgb, log10(BloomAmount + 1.0));

	color.rgb = ApplyTonemap(color.rgb, uv);

	return color;
}

//#endregion

//#region Technique

technique MagicHDR <ui_tooltip = "FXShaders - Bloom and tonemapping effect.";>
{
	pass InverseTonemap
	{
		VertexShader = ScreenVS;
		PixelShader = InverseTonemapPS;
		RenderTarget = Bloom0Tex;
	}

	#define DEF_BLUR_PASS(index, x, y) \
	pass Blur##x \
	{ \
		VertexShader = ScreenVS; \
		PixelShader = Blur##x##PS; \
		RenderTarget = TempTex; \
	} \
	pass Blur##y \
	{ \
		VertexShader = ScreenVS; \
		PixelShader = Blur##y##PS; \
		RenderTarget = Bloom##index##Tex; \
	}

	DEF_BLUR_PASS(0, 0, 1)
	DEF_BLUR_PASS(1, 2, 3)
	DEF_BLUR_PASS(2, 4, 5)
	DEF_BLUR_PASS(3, 6, 7)
	DEF_BLUR_PASS(4, 8, 9)
	DEF_BLUR_PASS(5, 10, 11)
	DEF_BLUR_PASS(6, 12, 13)

	#if MAGIC_HDR_ENABLE_ADAPTATION
		pass CalcAdapt
		{
			VertexShader = ScreenVS;
			PixelShader = CalcAdaptPS;
			RenderTarget = AdaptTex;
		}
		pass SaveAdapt
		{
			VertexShader = ScreenVS;
			PixelShader = SaveAdaptPS;
			RenderTarget = LastAdaptTex;
		}
	#endif

	pass Tonemap
	{
		VertexShader = ScreenVS;
		PixelShader = TonemapPS;

		#if MAGIC_HDR_SRGB_OUTPUT
			SRGBWriteEnable = true;
		#endif
	}
}

//#endregion

} // Namespace.
