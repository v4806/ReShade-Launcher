//#region Includes

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "ColorLab.fxh"
#include "FXShaders/Blending.fxh"
#include "FXShaders/Common.fxh"
#include "FXShaders/Convolution.fxh"
#include "FXShaders/Dithering.fxh"
#include "FXShaders/Tonemap.fxh"

//#endregion

//#region Macros

#ifndef NEO_BLOOM_TEXTURE_SIZE
#define NEO_BLOOM_TEXTURE_SIZE 1024
#endif

// Should be ((int)log2(NEO_BLOOM_TEXTURE_SIZE) + 1)
#ifndef NEO_BLOOM_TEXTURE_MIP_LEVELS
#define NEO_BLOOM_TEXTURE_MIP_LEVELS 11
#endif

#ifndef NEO_BLOOM_BLUR_SAMPLES
#define NEO_BLOOM_BLUR_SAMPLES 27
#endif

#ifndef NEO_BLOOM_DOWN_SCALE
#define NEO_BLOOM_DOWN_SCALE 2
#endif

#ifndef NEO_BLOOM_ADAPT
#define NEO_BLOOM_ADAPT 0
#endif

#ifndef NEO_BLOOM_DEBUG
#define NEO_BLOOM_DEBUG 0
#endif

#ifndef NEO_BLOOM_LENS_DIRT
#define NEO_BLOOM_LENS_DIRT 0
#endif

#ifndef NEO_BLOOM_LENS_DIRT_TEXTURE_NAME
#define NEO_BLOOM_LENS_DIRT_TEXTURE_NAME "NeoBloom_LensDirt.png"
#endif

#ifndef NEO_BLOOM_LENS_DIRT_TEXTURE_WIDTH
#define NEO_BLOOM_LENS_DIRT_TEXTURE_WIDTH 1280
#endif

#ifndef NEO_BLOOM_LENS_DIRT_TEXTURE_HEIGHT
#define NEO_BLOOM_LENS_DIRT_TEXTURE_HEIGHT 720
#endif

#ifndef NEO_BLOOM_LENS_DIRT_ASPECT_RATIO_CORRECTION
#define NEO_BLOOM_LENS_DIRT_ASPECT_RATIO_CORRECTION 1
#endif

#ifndef NEO_BLOOM_GHOSTING
#define NEO_BLOOM_GHOSTING 0
#endif

#ifndef NEO_BLOOM_GHOSTING_DOWN_SCALE
#define NEO_BLOOM_GHOSTING_DOWN_SCALE (NEO_BLOOM_DOWN_SCALE / 4.0)
#endif

#ifndef NEO_BLOOM_DEPTH
#define NEO_BLOOM_DEPTH 0
#endif

#ifndef NEO_BLOOM_DEPTH_ANTI_FLICKER
#define NEO_BLOOM_DEPTH_ANTI_FLICKER 0
#endif

#define NEO_BLOOM_NEEDS_LAST (NEO_BLOOM_GHOSTING || NEO_BLOOM_DEPTH && NEO_BLOOM_DEPTH_ANTI_FLICKER)

#ifndef NEO_BLOOM_DITHERING
#define NEO_BLOOM_DITHERING 0
#endif

//#endregion

namespace FXShaders
{

//#region Data Types

struct BlendPassParams
{
	float4 p : SV_POSITION;
	float2 uv : TEXCOORD0;

	#if NEO_BLOOM_LENS_DIRT
		float2 lens_uv : TEXCOORD1;
	#endif
};

//#endregion

//#region Constants

// Each bloom means: (x, y, scale, miplevel).
static const int BloomCount = 5;
static const float4 BloomLevels[] =
{
	float4(0.0, 0.5, 0.5, 1),
	float4(0.5, 0.0, 0.25, 2),
	float4(0.75, 0.875, 0.125, 3),
	float4(0.875, 0.0, 0.0625, 5),
	float4(0.0, 0.0, 0.03, 7)
	//float4(0.0, 0.0, 0.03125, 9)
};
static const int MaxBloomLevel = BloomCount - 1;

static const int BlurSamples = NEO_BLOOM_BLUR_SAMPLES;

static const float2 PixelScale = 1.0;

static const float2 DirtResolution = float2(
	NEO_BLOOM_LENS_DIRT_TEXTURE_WIDTH,
	NEO_BLOOM_LENS_DIRT_TEXTURE_HEIGHT);
static const float2 DirtPixelSize = 1.0 / DirtResolution;
static const float DirtAspectRatio = DirtResolution.x * DirtPixelSize.y;
static const float DirtAspectRatioInv = 1.0 / DirtAspectRatio;

static const int DebugOption_None = 0;
static const int DebugOption_OnlyBloom = 1;
static const int DebugOptions_TextureAtlas = 2;
static const int DebugOption_Adaptation = 3;

#if NEO_BLOOM_ADAPT
	static const int DebugOption_DepthRange = 4;
#else
	static const int DebugOption_DepthRange = 3;
#endif

static const int AdaptMode_FinalImage = 0;
static const int AdaptMode_OnlyBloom = 1;

static const int BloomBlendMode_Mix = 0;
static const int BloomBlendMode_Addition = 1;
static const int BloomBlendMode_Screen = 2;

//#endregion

//#region Uniforms

// Bloom

FXSHADERS_HELP(
	"NeoBloom has many options and may be difficult to setup or may look "
	"bad at first, but it's designed to be very flexible to adapt to many "
	"different cases.\n"
	"Make sure to take a look at the preprocessor definitions at the "
	"bottom!\n"
	"For more specific descriptions, move the mouse cursor over the name "
	"of the option you need help with.\n"
	"\n"
	"Here's a general description of the features:\n"
	"\n"
	"  Bloom:\n"
	"    Basic options for controlling the look of bloom itself.\n"
	"\n"
	"  Adaptation:\n"
	"    Used to dynamically increase or reduce the image brightness "
	"depending on the scene, giving an HDR look.\n"
	"    Looking at a bright object, like a lamp, would cause the image to "
	"darken; lookinng at a dark spot, like a cave, would cause the "
	"image to brighten.\n"
	"\n"
	"  Blending:\n"
	"    Used to control how the different bloom textures are blended, "
	"each representing a different level-of-detail.\n"
	"    Can be used to simulate an old mid-2000s bloom, ambient light "
	"etc.\n"
	"\n"
	"  Ghosting:\n"
	"    Smoothens the bloom between frames, causing a \"motion blur\" or "
	"\"trails\" effect.\n"
	"\n"
	"  Depth:\n"
	"    Used to increase or decrease the brightness of parts of the image "
	"depending on depth.\n"
	"    Can be used for effects like brightening the sky.\n"
	"    An optional anti-flicker feature is available to help with games "
	"with depth flickering problems, which can cause bloom to flicker as "
	"well with the depth feature enabled.\n"
	"\n"
	"  HDR:\n"
	"    Options for controlling the high dynamic range simulation.\n"
	"    Useful for simulating a more foggy bloom, like an old soap opera, "
	"a high-contrast sunny look etc.\n"
	"\n"
	"  Blur:\n"
	"    Options for controlling the blurring effect used to generate the "
	"bloom textures.\n"
	"    Mostly can be left untouched.\n"
	"\n"
	"  Debug:\n"
	"    Enables testing options, like viewing the bloom texture alone, "
	"before mixing with the image.\n"
);

uniform float Intensity
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "强度";
	ui_tooltip =
		"Determines how much bloom is added to the image. For HDR games you'd "
		"generally want to keep this low-ish, otherwise everything might look "
		"too bright.\n"
		"\nDefault: 1.0";
	ui_category = "泛光";
	ui_min = 0.0;
	ui_max = 1.0;
> = 1.0;

uniform float Saturation
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "饱和度";
	ui_tooltip =
		"Saturation of the bloom texture.\n"
		"\nDefault: 1.0";
	ui_category = "泛光";
	ui_min = 0.0;
	ui_max = 3.0;
> = 1.0;

uniform float3 ColorFilter
<
	__UNIFORM_COLOR_FLOAT3

	ui_label = "颜色滤镜";
	ui_tooltip =
		"乘以泛光的颜色，用于过滤。\n"
		"设置为全白(255, 255, 255)可禁用。\n"
		"\n默认: 255 255 255";
	ui_category = "泛光";
> = float3(1.0, 1.0, 1.0);

uniform int BloomBlendMode
<
	__UNIFORM_COMBO_INT1

	ui_label = "混合模式";
	ui_tooltip =
		"确定用于将泛光与场景颜色混合的公式。\n"
		"某些混合模式可能与其他选项不兼容。\n"
		"作为备选，加法模式始终有效。\n"
		"\n默认: 混合";
	ui_category = "泛光";
	ui_items = "混合\0加法\0滤色\0";
> = 1;

#if NEO_BLOOM_LENS_DIRT

uniform float LensDirtAmount
<
	__UNIFORM_SLIDER_FLOAT1

	ui_text =
		"Set NEO_BLOOM_DIRT to 0 to disable this feature to reduce resource "
		"usage.";
	ui_label = "数量";
	ui_tooltip =
		"添加到泛光纹理的镜头污垢量。\n"
		"\n默认: 0.0";
	ui_category = "镜头污垢";
	ui_min = 0.0;
	ui_max = 3.0;
> = 0.0;

#endif

#if NEO_BLOOM_ADAPT

// Adaptation

uniform int AdaptMode
<
	__UNIFORM_COMBO_INT1

	ui_text =
		"Set NEO_BLOOM_ADAPT to 0 to disable this feature to reduce resource "
		"usage.";
	ui_label = "模式";
	ui_tooltip =
		"选择自适应应用的不同模式。\n"
		"  最终图像:\n"
		"    在与泛光混合后将自适应应用于图像。\n"
		"  仅泛光:\n"
		"    仅将自适应应用于泛光，在与图像混合之前。\n"
		"\n默认: 最终图像";
	ui_category = "自适应";
	ui_items = "最终图像\0仅泛光\0";
> = 0;

uniform float AdaptAmount
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "数量";
	ui_tooltip =
		"自适应对图像亮度的影响程度。\n"
		"\n默认: 1.0";
	ui_category = "自适应";
	ui_min = 0.0;
	ui_max = 2.0;
> = 1.0;

uniform float AdaptSensitivity
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "灵敏度";
	ui_tooltip =
		"自适应对亮点的敏感程度？\n"
		"\n默认: 1.0";
	ui_category = "自适应";
	ui_min = 0.0;
	ui_max = 2.0;
> = 1.0;

uniform float AdaptExposure
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "曝光";
	ui_tooltip =
		"确定效果应该适应的一般亮度。\n"
		"以f档为单位测量，因此0是基础曝光，<0会更暗，>0会更亮。\n"
		"\n默认: 0.0";
	ui_category = "自适应";
	ui_min = -3.0;
	ui_max = 3.0;
> = 0.0;

uniform bool AdaptUseLimits
<
	ui_label = "使用限制";
	ui_tooltip =
		"自适应是否应限制在下面指定的最小和最大值范围内？\n"
		"\n默认: 开";
	ui_category = "自适应";
> = true;

uniform float2 AdaptLimits
<
	__UNIFORM_SLIDER_FLOAT2

	ui_label = "限制";
	ui_tooltip =
		"自适应可以达到的最小和最大值。\n"
		"增加最小值将减少图像在暗场景中变亮的程度。\n"
		"减少最大值将减少图像在亮场景中变暗的程度。\n"
		"\n默认: 0.0 1.0";
	ui_category = "自适应";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
> = float2(0.0, 1.0);

uniform float AdaptTime
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "时间";
	ui_tooltip =
		"效果适应所需的时间。\n"
		"\n默认: 1.0";
	ui_category = "自适应";
	ui_min = 0.02;
	ui_max = 3.0;
> = 1.0;

uniform float AdaptPrecision
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "精度";
	ui_tooltip =
		"自适应对图像中心的精确程度。\n"
		"0.0将产生整体图像亮度的自适应，而较高的值将\n"
		"越来越关注中心像素。\n"
		"\n默认: 0.0";
	ui_category = "自适应";
	ui_min = 0.0;
	ui_max = NEO_BLOOM_TEXTURE_MIP_LEVELS;
	ui_step = 1.0;
> = 0.0;

uniform int AdaptFormula
<
	__UNIFORM_COMBO_INT1

	ui_label = "公式";
	ui_tooltip =
		"从颜色中提取亮度信息时使用的公式。\n"
		"\n默认: 亮度 (线性)";
	ui_category = "自适应";
	ui_items = "平均值\0明度\0亮度 (伽马)\0亮度 (线性)\0";
> = 3;

#endif

// Blending

uniform float Mean
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "均值";
	ui_tooltip =
		"作为所有泛光纹理/大小之间的偏差。这意味着\n"
		"较低的值将产生更多细节泛光，而相反\n"
		"将产生大的高光。\n"
		"指定的方差越多，此设置的效果越小，\n"
		"因此如果您想要非常精细的细节泛光，请同时降低两个参数。\n"
		"\n默认: 0.0";
	ui_category = "混合";
	ui_min = 0.0;
	ui_max = BloomCount;
	//ui_step = 0.005;
> = 0.0;

uniform float Variance
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "方差";
	ui_tooltip =
		"确定泛光纹理/大小的'多样性'/'对比度'。这\n"
		"意味着低方差将产生更多由均值指定的泛光大小；\n"
		"也就是说，低方差和均值将产生更多精细细节泛光。\n"
		"高方差将减少均值的效果，因为它会\n"
		"使所有泛光纹理更均匀地混合。\n"
		"低方差和高均值将产生类似于'环境光'的效果，\n"
		"有大的光泛光，但细节较少。\n"
		"\n默认: 1.0";
	ui_category = "混合";
	ui_min = 1.0;
	ui_max = BloomCount;
	//ui_step = 0.005;
> = BloomCount;

#if NEO_BLOOM_GHOSTING

// Last

uniform float GhostingAmount
<
	__UNIFORM_SLIDER_FLOAT1

	ui_text =
		"Set NEO_BLOOM_GHOSTING to 0 if you don't use this feature to reduce "
		"resource usage.";
	ui_label = "数量";
	ui_tooltip =
		"应用的残影量。\n"
		"\n默认: 0.0";
	ui_category = "残影";
	ui_min = 0.0;
	ui_max = 0.999;
> = 0.0;

#endif

#if NEO_BLOOM_DEPTH

uniform float3 DepthMultiplier
<
	__UNIFORM_DRAG_FLOAT3

	ui_text =
		"Set NEO_BLOOM_DEPTH to 0 if you don't use this feature to reduce "
		"resource usage.";
	ui_label = "乘数";
	ui_tooltip =
		"定义将应用于深度中每个范围的乘数。\n"
		" - 第一个值定义近处深度的乘数。\n"
		" - 第二个值定义中间深度的乘数。\n"
		" - 第三个值定义远处深度的乘数。\n"
		"\n默认: 1.0 1.0 1.0";
	ui_category = "深度";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_step = 0.01;
> = float3(1.0, 1.0, 1.0);

uniform float2 DepthRange
<
	__UNIFORM_DRAG_FLOAT2

	ui_label = "范围";
	ui_tooltip =
		"定义深度乘数的深度范围。\n"
		" - 第一个值定义中间深度的开始。\n"
		" - 第二个值定义中间深度的结束和远处深度的开始。\n"
		"\n默认: 0.0 1.0";
	ui_category = "深度";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
> = float2(0.0, 1.0);

uniform float DepthSmoothness
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "平滑度";
	ui_tooltip =
		"深度范围之间过渡的平滑程度。\n"
		"\n默认: 1.0";
	ui_category = "深度";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
> = 1.0;

#if NEO_BLOOM_DEPTH_ANTI_FLICKER

uniform float DepthAntiFlicker
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "抗闪烁量";
	ui_tooltip =
		"应用于深度功能的抗闪烁量。\n"
		"如果您注意到使用高乘数时远处泛光闪烁，请使用此功能。\n"
		"\n默认: 0.999";
	ui_min = 0.0;
	ui_max = 0.999;
> = 0.999;

#endif

#endif

// HDR

uniform float MaxBrightness
<
	__UNIFORM_DRAG_FLOAT1

	ui_label  = "最大亮度";
	ui_tooltip =
		"简而言之：HDR对比度。\n"
		"\n确定像素通过'逆向色调映射'可以达到的最大亮度，\n"
		"即效果尝试从图像中提取HDR信息时。\n"
		"实际上，100和1000之间的差异在于白色像素\n"
		"可以变得多亮/多泛光/多大，如太阳或汽车前灯。\n"
		"较低的值也可用于制作更'平衡'的泛光，\n"
		"高光较少刺眼，整个场景同样雾蒙蒙，\n"
		"像老电视节目或脏镜头一样。\n"
		"\n默认: 100.0";
	ui_category = "高动态范围";
	ui_min = 1.0;
	ui_max = 1000.0;
	ui_step = 1.0;
> = 100.0;

uniform bool NormalizeBrightness
<
	ui_label = "标准化亮度";
	ui_tooltip =
		"是否在与图像混合时标准化泛光亮度。\n"
		"如果没有它，泛光可能会有非常刺眼的亮点。\n"
		"\n默认: 开";
	ui_category = "高动态范围";
> = true;

uniform bool MagicMode
<
	ui_label = "魔法模式";
	ui_tooltip =
		"启用时，模拟MagicBloom的外观。\n"
		"这是一个实验性选项，可能与其他参数不一致。\n"
		"\n默认: 关";
	ui_category = "高动态范围";
> = false;

// Blur

uniform float Sigma
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "Sigma";
	ui_tooltip =
		"模糊程度。值太高会破坏模糊效果。\n"
		"推荐值在2到4之间。\n"
		"\n默认: 2.0";
	ui_category = "模糊";
	ui_min = 1.0;
	ui_max = 10.0;
	ui_step = 0.01;
> = 4.0;

uniform float Padding
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "填充";
	ui_tooltip =
		"指定内部纹理图集中泛光纹理周围的额外填充，\n"
		"在模糊过程中使用。\n"
		"这样做的原因是减少屏幕边缘泛光亮度的损失，\n"
		"由于模糊的工作方式。\n"
		"\n"
		"如果需要，可以将其设置为零以故意减少边缘周围的泛光量。\n"
		"在增加模糊sigma、采样数和/或泛光缩小比例时，\n"
		"可能需要增加此参数。\n"
		"\n"
		"由于其工作方式，建议尽可能保持较低的值，\n"
		"因为它会导致模糊过程在'较低'分辨率下工作。\n"
		"\n"
		"如果您仍然对此参数感到困惑，请尝试使用调试模式\n"
		"查看纹理图集，并观察当它增加时会发生什么。\n"
		"\n默认: 0.1";
	ui_category = "模糊";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_step = 0.001;
> = 0.1;

#if NEO_BLOOM_DEBUG

// Debug

uniform int DebugOptions
<
	__UNIFORM_COMBO_INT1

	ui_text =
		"Set NEO_BLOOM_DEBUG to 0 if you don't use this feature to reduce "
		"resource usage.";
	ui_label = "调试选项";
	ui_tooltip =
		"调试选项包括:\n"
		"  - 仅显示泛光纹理。'显示的泛光纹理'参数可用于\n"
		"    确定要可视化的泛光纹理。\n"
		"  - 显示用于模糊所有泛光'纹理'的原始内部纹理图集，\n"
		"    按比例可视化所有泛光。\n"
		#if NEO_BLOOM_ADAPT
		"  - 直接显示自适应纹理。\n"
		#endif
		#if NEO_BLOOM_DEPTH
		"  - 显示深度范围纹理，将近处范围显示为红色，\n"
		"    中间为绿色，远处为蓝色。\n"
		#endif
		"\n默认: 无";
	ui_category = "调试";
	ui_items =
		"无\0仅显示泛光\0显示纹理图集\0"
		#if NEO_BLOOM_ADAPT
		"显示自适应\0"
		#endif
		#if NEO_BLOOM_DEPTH
		"显示深度范围\0"
		#endif
		;
> = false;

uniform int BloomTextureToShow
<
	__UNIFORM_SLIDER_INT1

	ui_label = "显示的泛光纹理";
	ui_tooltip =
		"使用'仅显示泛光'调试选项时显示的泛光纹理。\n"
		"设置为-1可查看所有混合的纹理。\n"
		"\n默认: -1";
	ui_category = "调试";
	ui_min = -1;
	ui_max = MaxBloomLevel;
> = -1;

#endif

#if NEO_BLOOM_DITHERING

uniform float DitherAmount
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "数量";
	ui_tooltip =
		"应用于泛光的抖动量。\n"
		"\n默认: 0.1";
	ui_category = "抖动";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
> = 0.1;

#endif

#if NEO_BLOOM_ADAPT

uniform float FrameTime <source = "frametime";>;

#endif

//#endregion

//#region Textures

sampler BackBuffer
{
	Texture = ReShade::BackBufferTex;
	SRGBTexture = true;
};

texture NeoBloom_DownSample <pooled="true";>
{
	Width = NEO_BLOOM_TEXTURE_SIZE;
	Height = NEO_BLOOM_TEXTURE_SIZE;
	Format = RGBA16F;
	MipLevels = NEO_BLOOM_TEXTURE_MIP_LEVELS;
};
sampler DownSample
{
	Texture = NeoBloom_DownSample;
};

texture NeoBloom_AtlasA <pooled="true";>
{
	Width = BUFFER_WIDTH / NEO_BLOOM_DOWN_SCALE;
	Height = BUFFER_HEIGHT / NEO_BLOOM_DOWN_SCALE;
	Format = RGBA16F;
};
sampler AtlasA
{
	Texture = NeoBloom_AtlasA;
	AddressU = BORDER;
	AddressV = BORDER;
};

texture NeoBloom_AtlasB <pooled="true";>
{
	Width = BUFFER_WIDTH / NEO_BLOOM_DOWN_SCALE;
	Height = BUFFER_HEIGHT / NEO_BLOOM_DOWN_SCALE;
	Format = RGBA16F;
};
sampler AtlasB
{
	Texture = NeoBloom_AtlasB;
	AddressU = BORDER;
	AddressV = BORDER;
};

#if NEO_BLOOM_ADAPT

texture NeoBloom_Adapt <pooled="true";>
{
	Format = R16F;
};
sampler Adapt
{
	Texture = NeoBloom_Adapt;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
};

texture NeoBloom_LastAdapt
{
	Format = R16F;
};
sampler LastAdapt
{
	Texture = NeoBloom_LastAdapt;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
};

#endif

#if NEO_BLOOM_LENS_DIRT

texture NeoBloom_LensDirt
<
	source = NEO_BLOOM_LENS_DIRT_TEXTURE_NAME;
>
{
	Width = NEO_BLOOM_LENS_DIRT_TEXTURE_WIDTH;
	Height = NEO_BLOOM_LENS_DIRT_TEXTURE_HEIGHT;
};
sampler LensDirt
{
	Texture = NeoBloom_LensDirt;
};

#endif

#if NEO_BLOOM_NEEDS_LAST

texture NeoBloom_Last
{
	Width = BUFFER_WIDTH / NEO_BLOOM_GHOSTING_DOWN_SCALE;
	Height = BUFFER_HEIGHT / NEO_BLOOM_GHOSTING_DOWN_SCALE;

	#if NEO_BLOOM_GHOSTING && NEO_BLOOM_DEPTH_ANTI_FLICKER
		Format = RGBA16F;
	#else
		Format = R8;
	#endif
};
sampler Last
{
	Texture = NeoBloom_Last;
};

#if NEO_BLOOM_DEPTH

texture NeoBloom_Depth
{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = R8;
};
sampler Depth
{
	Texture = NeoBloom_Depth;
};

#endif

#endif

//#endregion

//#region Functions

float3 blend_bloom(float3 color, float3 bloom)
{
	float w;
	if (NormalizeBrightness)
		w = Intensity / MaxBrightness;
	else
		w = Intensity;

	switch (BloomBlendMode)
	{
		default:
			return 0.0;
		case BloomBlendMode_Mix:
			return lerp(color, bloom, log2(w + 1.0));
		case BloomBlendMode_Addition:
			return color + bloom * w * 3.0;
		case BloomBlendMode_Screen:
			return BlendScreen(color, bloom, w);
	}
}

float3 inv_tonemap_bloom(float3 color)
{
	if (MagicMode)
		return pow(abs(color), MaxBrightness * 0.01);

	return Tonemap::Reinhard::InverseOldLum(color, 1.0 / MaxBrightness);
}

float3 inv_tonemap(float3 color)
{
	if (MagicMode)
		return color;

	return Tonemap::Reinhard::InverseOld(color, 1.0 / MaxBrightness);
}

float3 tonemap(float3 color)
{
	if (MagicMode)
		return color;

	return Tonemap::Reinhard::Apply(color);
}

//#endregion

//#region Shaders

#if NEO_BLOOM_DEPTH && NEO_BLOOM_DEPTH_ANTI_FLICKER

float GetDepthPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float3 depth = ReShade::GetLinearizedDepth(uv);

	#if NEO_BLOOM_GHOSTING
		float last = tex2D(Last, uv).a;
	#else
		float last = tex2D(Last, uv).r;
	#endif

	depth = lerp(depth, last, DepthAntiFlicker);

	return depth;
}

#endif

float4 DownSamplePS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float4 color = tex2D(BackBuffer, uv);
	color.rgb = saturate(ApplySaturation(color.rgb, Saturation));
	color.rgb *= ColorFilter;
	color.rgb = inv_tonemap_bloom(color.rgb);

	#if NEO_BLOOM_DEPTH
		#if NEO_BLOOM_DEPTH_ANTI_FLICKER
			float3 depth = tex2D(Depth, uv).x;
		#else
			float3 depth = ReShade::GetLinearizedDepth(uv);
		#endif

		float is_near = smoothstep(
			depth - DepthSmoothness,
			depth + DepthSmoothness,
			DepthRange.x);

		float is_far = smoothstep(
			DepthRange.y - DepthSmoothness,
			DepthRange.y + DepthSmoothness, depth);

		float is_middle = (1.0 - is_near) * (1.0 - is_far);

		color.rgb *= lerp(1.0, DepthMultiplier.x, is_near);
		color.rgb *= lerp(1.0, DepthMultiplier.y, is_middle);
		color.rgb *= lerp(1.0, DepthMultiplier.z, is_far);
	#endif

	return color;
}

float4 SplitPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float4 color = 0.0;

	[unroll]
	for (int i = 0; i < BloomCount; ++i)
	{
		float4 rect = BloomLevels[i];
		float2 rect_uv = ScaleCoord(uv - rect.xy, 1.0 / rect.z, 0.0);
		float inbounds =
			step(0.0, rect_uv.x) * step(rect_uv.x, 1.0) *
			step(0.0, rect_uv.y) * step(rect_uv.y, 1.0);

		rect_uv = ScaleCoord(rect_uv, 1.0 + Padding * (i + 1), 0.5);

		float4 pixel = tex2Dlod(DownSample, float4(rect_uv, 0, rect.w));
		pixel.rgb *= inbounds;
		pixel.a = inbounds;

		color += pixel;
	}

	return color;
}

float4 BlurXPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float2 dir =
		PixelScale *
		float2(BUFFER_RCP_WIDTH, 0.0) *
		NEO_BLOOM_DOWN_SCALE;

	return GaussianBlur1D(AtlasA, uv, dir, Sigma, BlurSamples);
}

float4 BlurYPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float2 dir =
		PixelScale *
		float2(0.0, BUFFER_RCP_HEIGHT) *
		NEO_BLOOM_DOWN_SCALE;

	return GaussianBlur1D(AtlasB, uv, dir, Sigma, BlurSamples);
}

#if NEO_BLOOM_ADAPT

float4 CalcAdaptPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float3 color = tex2Dlod(
		DownSample,
		float4(0.5, 0.5, 0.0, NEO_BLOOM_TEXTURE_MIP_LEVELS - AdaptPrecision)
	).rgb;
	color = tonemap(color);

	float gs;
	switch (AdaptFormula)
	{
		case 0:
			gs = dot(color, 0.333);
			break;
		case 1:
			gs = max(color.r, max(color.g, color.b));
			break;
		case 2:
			gs = GetLumaGamma(color);
			break;
		case 3:
			gs = GetLumaLinear(color);
			break;
	}

	gs *= AdaptSensitivity;
	gs = AdaptUseLimits ? clamp(gs, AdaptLimits.x, AdaptLimits.y) : gs;

	float last = tex2D(LastAdapt, 0.0).r;
	gs = lerp(last, gs, saturate((FrameTime * 0.001) / max(AdaptTime, 0.001)));

	return float4(gs, 0.0, 0.0, 1.0);
}

float4 SaveAdaptPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	return tex2D(Adapt, 0.0);
}

#endif

float4 JoinBloomsPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float4 bloom = 0.0;
	float accum = 0.0;

	[unroll]
	for (int i = 0; i < BloomCount; ++i)
	{
		float4 rect = BloomLevels[i];
		float2 rect_uv = ScaleCoord(uv, 1.0 / (1.0 + Padding * (i + 1)), 0.5);
		rect_uv = ScaleCoord(rect_uv + rect.xy / rect.z, rect.z, 0.0);

		float weight = NormalDistribution(i, Mean, Variance);
		bloom += tex2D(AtlasA, rect_uv) * weight;
		accum += weight;
	}
	bloom /= accum;

	#if NEO_BLOOM_GHOSTING
		float3 last = tex2D(Last, uv).rgb;
		bloom.rgb = lerp(bloom.rgb, last.rgb, GhostingAmount);
	#endif

	return bloom;
}

#if NEO_BLOOM_NEEDS_LAST

float4 SaveLastBloomPS(
	float4 p : SV_POSITION,
	float2 uv : TEXCOORD
) : SV_TARGET
{
	float4 color = float4(0.0, 0.0, 0.0, 1.0);

	#if NEO_BLOOM_DEPTH && NEO_BLOOM_DEPTH_ANTI_FLICKER
		color = tex2D(Depth, uv).x;
	#endif

	#if NEO_BLOOM_GHOSTING
		color.rgb = tex2D(AtlasB, uv).rgb;
	#endif

	return color;
}

#endif

// As a workaround for a bug in the current ReShade DirectX 9 code generator,
// we have to return the parameters instead of using out.
// If we don't do that, the DirectX 9 half pixel offset bug is not automatically
// corrected by the code generator, which leads to a slightly blurry image.
BlendPassParams BlendVS(uint id : SV_VERTEXID)
{
	BlendPassParams p;

	PostProcessVS(id, p.p, p.uv);

	#if NEO_BLOOM_LENS_DIRT && NEO_BLOOM_LENS_DIRT_ASPECT_RATIO_CORRECTION
		float ar = BUFFER_WIDTH * BUFFER_RCP_HEIGHT;
		float ar_inv = BUFFER_HEIGHT * BUFFER_RCP_WIDTH;
		float is_horizontal = step(ar, DirtAspectRatio);
		float ratio = lerp(
			DirtAspectRatio * ar_inv,
			ar * DirtAspectRatioInv,
			is_horizontal);

		p.lens_uv = ScaleCoord(p.uv, float2(1.0, ratio), 0.5);
	#endif

	return p;
}

float4 BlendPS(BlendPassParams p) : SV_TARGET
{
	float2 uv = p.uv;

	float4 color = tex2D(BackBuffer, uv);
	color.rgb = inv_tonemap(color.rgb);

	#if NEO_BLOOM_GHOSTING
		float4 bloom = tex2D(AtlasB, uv);
	#else
		float4 bloom = JoinBloomsPS(p.p, uv);
	#endif

	#if NEO_BLOOM_DITHERING
		bloom.rgb = FXShaders::Dithering::Ordered16::Apply(
			bloom.rgb,
			uv,
			DitherAmount);
	#endif

	#if NEO_BLOOM_LENS_DIRT
		float4 dirt = tex2D(LensDirt, p.lens_uv);
		bloom.rgb = mad(dirt.rgb, bloom.rgb * LensDirtAmount, bloom.rgb);
	#endif

	#if NEO_BLOOM_DEBUG
		switch (DebugOptions)
		{
			case DebugOption_OnlyBloom:
				if (BloomTextureToShow == -1)
				{
					color.rgb = tonemap(bloom.rgb);
				}
				else
				{
					float4 rect = BloomLevels[BloomTextureToShow];
					float2 rect_uv = ScaleCoord(
						uv,
						1.0 / (1.0 + Padding * (BloomTextureToShow + 1)),
						0.5
					);

					rect_uv = ScaleCoord(rect_uv + rect.xy / rect.z, rect.z, 0.0);
					color = tex2D(AtlasA, rect_uv);
					color.rgb = tonemap(color.rgb);
				}

				return color;
			case DebugOptions_TextureAtlas:
				color = tex2D(AtlasA, uv);
				color.rgb = lerp(checkered_pattern(uv), color.rgb, color.a);
				color.a = 1.0;

				return color;

			#if NEO_BLOOM_ADAPT
				case DebugOption_Adaptation:
					color = tex2Dlod(
						DownSample,
						float4(
							uv,
							0.0,
							NEO_BLOOM_TEXTURE_MIP_LEVELS - AdaptPrecision)
					);
					color.rgb = tonemap(color.rgb);
					return color;
			#endif

			#if NEO_BLOOM_DEPTH
				case DebugOption_DepthRange:
					#if NEO_BLOOM_DEPTH_ANTI_FLICKER
						float depth = tex2D(Depth, uv).x;
					#else
						float depth = ReShade::GetLinearizedDepth(uv);
					#endif

					color.r = smoothstep(0.0, DepthRange.x, depth);
					color.g = smoothstep(DepthRange.x, DepthRange.y, depth);
					color.b = smoothstep(DepthRange.y, 1.0, depth);

					color.r *= smoothstep(
						depth - DepthSmoothness,
						depth + DepthSmoothness,
						DepthRange.x);

					color.g *= smoothstep(
						depth - DepthSmoothness,
						depth + DepthSmoothness,
						DepthRange.y);

					return color;
			#endif
		}
	#endif

	#if NEO_BLOOM_ADAPT
		float adapt = tex2D(Adapt, 0.0).r;
		float exposure = exp(AdaptExposure) / max(adapt, 0.001);
		exposure = lerp(1.0, exposure, AdaptAmount);

		if (MagicMode)
		{
			bloom.rgb = Tonemap::Uncharted2Filmic::Apply(
				bloom.rgb * exposure * 0.1);
		}

		switch (AdaptMode)
		{
			case AdaptMode_FinalImage:
				color = blend_bloom(color, bloom);
				color.rgb *= exposure;
				break;
			case AdaptMode_OnlyBloom:
				bloom.rgb *= exposure;
				color = blend_bloom(color, bloom);
				break;
		}
	#else
		if (MagicMode)
			bloom.rgb = Tonemap::Uncharted2Filmic::Apply(bloom.rgb * 10.0);

		color.rgb = blend_bloom(color.rgb, bloom.rgb);
	#endif

	if (!MagicMode)
		color.rgb = tonemap(color.rgb);

	return color;
}

//#endregion

//#region Technique

technique NeoBloom
{
	#if NEO_BLOOM_DEPTH && NEO_BLOOM_DEPTH_ANTI_FLICKER
		pass GetDepth
		{
			VertexShader = PostProcessVS;
			PixelShader = GetDepthPS;
			RenderTarget = NeoBloom_Depth;
		}
	#endif

	pass DownSample
	{
		VertexShader = PostProcessVS;
		PixelShader = DownSamplePS;
		RenderTarget = NeoBloom_DownSample;
	}
	pass Split
	{
		VertexShader = PostProcessVS;
		PixelShader = SplitPS;
		RenderTarget = NeoBloom_AtlasA;
	}
	pass BlurX
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurXPS;
		RenderTarget = NeoBloom_AtlasB;
	}
	pass BlurY
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurYPS;
		RenderTarget = NeoBloom_AtlasA;
	}

	#if NEO_BLOOM_ADAPT
		pass CalcAdapt
		{
			VertexShader = PostProcessVS;
			PixelShader = CalcAdaptPS;
			RenderTarget = NeoBloom_Adapt;
		}
		pass SaveAdapt
		{
			VertexShader = PostProcessVS;
			PixelShader = SaveAdaptPS;
			RenderTarget = NeoBloom_LastAdapt;
		}
	#endif

	#if NEO_BLOOM_NEEDS_LAST
		pass JoinBlooms
		{
			VertexShader = PostProcessVS;
			PixelShader = JoinBloomsPS;
			RenderTarget = NeoBloom_AtlasB;
		}
		pass SaveLastBloom
		{
			VertexShader = PostProcessVS;
			PixelShader = SaveLastBloomPS;
			RenderTarget = NeoBloom_Last;
		}
	#endif

	pass Blend
	{
		VertexShader = BlendVS;
		PixelShader = BlendPS;
		SRGBWriteEnable = true;
	}
}

//#endregion

}
