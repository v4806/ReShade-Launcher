//#region Includes

//#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "ACES.fxh"

//#endregion

//#region Macros

#ifndef ADAPTIVE_TONEMAPPER_SMALL_TEX_SIZE
#define ADAPTIVE_TONEMAPPER_SMALL_TEX_SIZE 256
#endif

// Should be set to `int(log2(ADAPTIVE_TONEMAPPER_SMALL_TEX_SIZE)) + 1`.
#ifndef ADAPTIVE_TONEMAPPER_SMALL_TEX_MIPLEVELS
#define ADAPTIVE_TONEMAPPER_SMALL_TEX_MIPLEVELS 9
#endif

//#endregion

//#region Constants

static const int2 AdaptResolution = ADAPTIVE_TONEMAPPER_SMALL_TEX_SIZE;
static const int AdaptMipLevels = ADAPTIVE_TONEMAPPER_SMALL_TEX_MIPLEVELS;

static const float3 LumaWeights = float3(0.299, 0.587, 0.114);

static const int TonemapOperator_Reinhard = 0;
static const int TonemapOperator_Filmic = 1;
static const int TonemapOperator_ACES = 2;

//#endregion

//#region Uniforms

uniform int TonemapOperator
<
	__UNIFORM_COMBO_INT1

	ui_label = "运算符";
	ui_tooltip =
		"确定用于图像色调映射的公式。\n"
		"\n默认: ACES (虚幻引擎4)";
	ui_items = "Reinhard\0电影级 (神秘海域2)\0ACES (虚幻引擎4)\0";
> = 2;

uniform float Amount
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "数量";
	ui_tooltip =
		"原始颜色与色调映射后颜色之间的插值。\n"
		"\n默认: 1.0";
	ui_category = "色调映射";
	ui_min = 0.0;
	ui_max = 2.0;
> = 1.0;

uniform float Exposure
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "曝光";
	ui_tooltip =
		"确定图像的亮度/相机曝光。\n"
		"以f档为单位测量，因此:\n"
		"  |暗|     |中性|   |亮|\n"
		"  ... -2.0 -1.0 0.0 +1.0 +2.0 ...\n"
		"\n默认: 0.0";
	ui_category = "色调映射";
	ui_min = -6.0;
	ui_max = 6.0;
> = 0.0;

uniform bool FixWhitePoint
<
	ui_label = "修复白点";
	ui_tooltip =
		"在色调映射后应用亮度校正。\n"
		"\n默认: 开";
	ui_category = "色调映射";
> = true;

uniform float2 AdaptRange
<
	__UNIFORM_DRAG_FLOAT2

	ui_label = "范围";
	ui_tooltip =
		"自适应可使用的最小和最大值。\n"
		"增加第一个值将限制图像可以变亮的程度。\n"
		"减少第二个值将限制图像可以变暗的程度。\n"
		"第一个值应始终小于或等于第二个值。\n"
		"\n默认: 0.0 1.0";
	ui_category = "自适应";
	ui_min = 0.001;
	ui_max = 1.0;
	ui_step = 0.001;
> = float2(0.0, 1.0);

uniform float AdaptTime
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "时间";
	ui_tooltip =
		"自适应发生所需的时间（秒）。\n"
		"设置为0.0使其即时发生。\n"
		"\n默认: 1.0";
	ui_category = "自适应";
	ui_min = 0.0;
	ui_max = 3.0;
	ui_step = 0.01;
> = 1.0;

uniform float AdaptSensitivity
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "灵敏度";
	ui_tooltip =
		"确定自适应对明亮光源的敏感程度，使其更非线性。\n"
		"本质上作为乘数起作用。\n"
		"\n默认: 1.0";
	ui_category = "自适应";
	ui_min = 0.0;
	ui_max = 3.0;
	ui_step = 0.01;
> = 1.0;

uniform int AdaptPrecision
<
	__UNIFORM_SLIDER_INT1

	ui_label = "精度";
	ui_tooltip =
		"确定屏幕中心点周围整体亮度时使用的精度。\n"
		"为0时，整个场景都被纳入考量。\n"
		"最大值可能因给定自适应纹理大小可用的LOD数量而异，\n"
		"但最大值始终导致只考虑屏幕的绝对中心进行自适应。\n"
		"\n默认: 0";
	ui_category = "自适应";
	ui_min = 0;
	ui_max = AdaptMipLevels;
> = 0;

uniform float2 AdaptFocalPoint
<
	__UNIFORM_DRAG_FLOAT2

	ui_label = "焦点";
	ui_tooltip =
		"确定自适应将以屏幕中的某个点为中心。\n"
		"当精度设置为0时无关紧要，但否则可以帮助聚焦于\n"
		"不一定在屏幕中心的物体，如地面。\n"
		"第一个值控制水平位置，从左到右。\n"
		"第二个值控制垂直位置，从上到下。\n"
		"两者都设为0.5表示屏幕绝对中心点。\n"
		"\n默认: 0.5 0.5";
	ui_category = "自适应";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
> = 0.5;

uniform float FrameTime <source = "frametime";>;

//#endregion

//#region Textures

texture BackBufferTex : COLOR;

sampler BackBuffer_Point
{
	Texture = BackBufferTex;
	SRGBTexture = true;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
};

sampler BackBuffer_Linear
{
	Texture = BackBufferTex;
	SRGBTexture = true;
};

texture SmallTex
{
	Width = AdaptResolution.x;
	Height = AdaptResolution.y;
	Format = R32F;
	MipLevels = AdaptMipLevels;
};
sampler Small
{
	Texture = SmallTex;
};

texture LastAdaptTex
{
	Format = R32F;
};
sampler LastAdapt
{
	Texture = LastAdaptTex;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
};

//#endregion

//#region Functions

float get_adapt()
{
	return tex2Dlod(
		Small,
		float4(AdaptFocalPoint, 0, AdaptMipLevels - AdaptPrecision)).x;
}

float3 reinhard(float3 color)
{
	return color / (1.0 + color);
}

float3 uncharted2_tonemap(float3 col, float exposure) {
    static const float A = 0.15; //shoulder strength
    static const float B = 0.50; //linear strength
	static const float C = 0.10; //linear angle
	static const float D = 0.20; //toe strength
	static const float E = 0.02; //toe numerator
	static const float F = 0.30; //toe denominator
	static const float W = 11.2; //linear white point value

    col *= exposure;

    col = ((col * (A * col + C * B) + D * E) / (col * (A * col + B) + D * F)) - E / F;
    static const float white = 1.0 / (((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F);
    col *= white;
    return col;
}

float3 tonemap(float3 color, float exposure)
{
	switch (TonemapOperator)
	{
		default:
			return 0.0;
		case TonemapOperator_Reinhard:
			return reinhard(color * exposure);
		case TonemapOperator_Filmic:
			return uncharted2_tonemap(color, exposure);
		case TonemapOperator_ACES:
			return ACESFitted(color * exposure);
	}
}

//#endregion

//#region Shaders

void PostProcessVS(
	uint id : SV_VERTEXID,
	out float4 p : SV_POSITION,
	out float2 uv : TEXCOORD)
{
	uv.x = (id == 2) ? 2.0 : 0.0;
	uv.y = (id == 1) ? 2.0 : 0.0;
	p = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float4 GetSmallPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float adapt = dot(tex2D(BackBuffer_Linear, uv).rgb, LumaWeights);
	adapt *= AdaptSensitivity;

	float last = tex2Dfetch(LastAdapt, 0).x;

	if (AdaptTime > 0.0)
		adapt = lerp(last, adapt, saturate((FrameTime * 0.001) / AdaptTime));

	return adapt;
}

float4 SaveAdaptPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	return get_adapt();
}

void MainVS(
	uint id : SV_VERTEXID,
	out float4 p : SV_POSITION,
	out float2 uv : TEXCOORD0,
	out float inv_white : TEXCOORD1,
	out float exposure : TEXCOORD2)
{
	PostProcessVS(id, p, uv);
	exposure = exp2(Exposure);

	float adapt = get_adapt();
	adapt = clamp(adapt, AdaptRange.x, AdaptRange.y);
	exposure /= adapt;

	inv_white = FixWhitePoint
		? rcp(tonemap(1.0, exposure).x)
		: 1.0;
}

float4 MainPS(
	float4 p : SV_POSITION,
	float2 uv : TEXCOORD0,
	float inv_white : TEXCOORD1,
	float exposure : TEXCOORD2) : SV_TARGET
{
	float4 color = tex2D(BackBuffer_Point, uv);
	color.rgb = lerp(
		color.rgb,
		tonemap(color.rgb, exposure) * inv_white,
		Amount);

	return color;
}

//#endregion

//#region Technique

technique AdaptiveTonemapper
{
	pass GetSmall
	{
		VertexShader = PostProcessVS;
		PixelShader = GetSmallPS;
		RenderTarget = SmallTex;
	}
	pass SaveAdapt
	{
		VertexShader = PostProcessVS;
		PixelShader = SaveAdaptPS;
		RenderTarget = LastAdaptTex;
	}
	pass Main
	{
		VertexShader = MainVS;
		PixelShader = MainPS;
		SRGBWriteEnable = true;
	}
}

//#endregion
