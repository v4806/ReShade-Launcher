//#region Preprocessor

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "FXShaders/Common.fxh"
#include "FXShaders/Math.fxh"

/*
	0: Manual
	1: Colorpicker
	2: Automatic
*/
#ifndef WHITEPOINT_FIXER_MODE
#define WHITEPOINT_FIXER_MODE 0
#endif

#ifndef WHITEPOINT_FIXER_DOWNSAMPLE_SIZE
#define WHITEPOINT_FIXER_DOWNSAMPLE_SIZE 16
#endif

#define WHITEPOINT_FIXER_MODE_1_OR_2 \
(WHITEPOINT_FIXER_MODE == 1 || WHITEPOINT_FIXER_MODE == 2)

//#endregion

namespace FXShaders
{

//#region Constants

static const float2 ShowWhitepointSize = 300.0;

#if WHITEPOINT_FIXER_MODE == 1

static const float2 ColorPickerTooltipOffset = float2(0.0, -100.0);
static const float ColorPickerTooltipRadius = 50.0;

static const float ColorPickerCrosshairThickness = 5.0;

#endif

#if WHITEPOINT_FIXER_MODE == 2

static const int DownsampleSize = WHITEPOINT_FIXER_DOWNSAMPLE_SIZE;
static const int DownsampleMaxMip =
	FXSHADERS_LOG2(WHITEPOINT_FIXER_DOWNSAMPLE_SIZE) + 1;

#endif

#if WHITEPOINT_FIXER_MODE_1_OR_2

static const int GrayscaleFormula_Average = 0;
static const int GrayscaleFormula_Max = 1;
static const int GrayscaleFormula_Luma = 2;

#endif

//#endregion

//#region Uniforms

FXSHADERS_HELP(
	"不同模式可通过设置 WHITEPOINT_FIXER_MODE 来使用：\n"
	"  0: 手动颜色选择，使用参数。\n"
	"  1: 使用图像上的取色器选择白点颜色。\n"
	"  2: 通过查找图像中最亮的颜色自动猜测白点。\n"
);

#if WHITEPOINT_FIXER_MODE == 0

uniform float Whitepoint
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "白点值";
	ui_tooltip =
		"手动白点值。\n"
		"\n默认值: 1.0";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.00392156; //1.0 / 255.0;
> = 1.0;

#elif WHITEPOINT_FIXER_MODE == 1

uniform bool RunColorPicker
<
	ui_label = "运行取色器";
	ui_tooltip =
		"启用此选项时，按住鼠标右键将使用光标下像素的颜色作为白点。\n"
		"\n默认值: 关";
> = false;

uniform float2 MousePoint <source = "mousepoint";>;

uniform bool MouseRightDown <source = "mousebutton"; keycode = 1;>;

#endif

#if WHITEPOINT_FIXER_MODE == 2

uniform float TransitionSpeed
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "过渡速度";
	ui_tooltip =
		"从上一个白点过渡到下一个白点所需的时间（秒）。\n"
		"设为 0.0 可使过渡瞬时完成。\n"
		"\n默认值: 1.0";
	ui_min = 0.0;
	ui_max = 5.0;
	ui_step = 1.0 / 100.0;
> = 1.0;

uniform float FrameTime <source = "frametime";>;

#endif

#if WHITEPOINT_FIXER_MODE_1_OR_2

uniform int GrayscaleFormula
<
	__UNIFORM_COMBO_INT1

	ui_label = "灰度公式";
	ui_tooltip =
		"用于获取白点值的灰度颜色的公式。\n"
		"\n默认值: 平均值";
	ui_items = "平均值\0最大值\0亮度\0";
> = 0;

uniform float MinimumWhitepoint
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "最小白点";
	ui_tooltip =
		"可使用的最小白点值。\n"
		"任何低于此值的白点将被重新映射为"重映射白点"的值。\n"
		"\n默认值: 0.8";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 1.0 / 255.0;
> = 0.8;

uniform float RemappedWhitepoint
<
	__UNIFORM_DRAG_FLOAT1

	ui_label = "重映射白点";
	ui_tooltip =
		"当白点低于最小白点值时应使用的白点值。\n"
		"\n默认值: 1.0";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 1.0 / 255.0;
> = 1.0;

uniform bool ShowWhitepoint
<
	ui_label = "显示白点";
	ui_tooltip =
		"在屏幕上显示白点颜色。\n"
		"\n默认值: 关";
> = false;

#endif

//#endregion

//#region Textures

#if WHITEPOINT_FIXER_MODE_1_OR_2

texture PickedColorTex //<pooled = true;>
{
	Format = R32F;
};

sampler PickedColor
{
	Texture = PickedColorTex;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
};

#endif

#if WHITEPOINT_FIXER_MODE == 2

texture DownsampleTex <pooled = true;>
{
	Width = DownsampleSize;
	Height = DownsampleSize;
	Format = R8;
};

sampler Downsample
{
	Texture = DownsampleTex;
};

texture LastPickedColorTex
{
	Format = R32F;
};

sampler LastPickedColor
{
	Texture = LastPickedColorTex;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
};

#endif

//#endregion

//#region Functions

#if WHITEPOINT_FIXER_MODE_1_OR_2

float GetGrayscale(float3 color)
{
	switch (GrayscaleFormula)
	{
		case GrayscaleFormula_Average:
			return dot(color, 0.333);
		case GrayscaleFormula_Max:
			return max(color.r, max(color.g, color.b));
		case GrayscaleFormula_Luma:
			return GetLumaGamma(color);
	}

	return 0.0;
}

#endif

float GetWhitepoint()
{
	#if WHITEPOINT_FIXER_MODE == 0
		return Whitepoint;
	#elif WHITEPOINT_FIXER_MODE_1_OR_2
		return tex2Dfetch(PickedColor, 0).x;
	#else
		#error "Invalid mode"
	#endif
}

/**
 * Check if a contains b within a size margin.
 */
float Contains(float size, float a, float b)
{
	return step(a - size, b) * step(b, a + size);
}

//#endregion

//#region Shaders

#if WHITEPOINT_FIXER_MODE == 2

float DownsamplePS(
	float4 pos : SV_POSITION,
	float2 uv : TEXCOORD) : SV_TARGET
{
	float4 color = tex2D(ReShade::BackBuffer, uv);
	float value = GetGrayscale(color.rgb);

	return value;
}

#endif

#if WHITEPOINT_FIXER_MODE_1_OR_2

float PickColorPS(
	float4 pos : SV_POSITION,
	float2 uv : TEXCOORD) : SV_TARGET
{
	float value;

	#if WHITEPOINT_FIXER_MODE == 1
	{
		if (!(RunColorPicker && MouseRightDown))
			discard;

		float2 cursor_uv = MousePoint * GetPixelSize();
		float4 pixel = tex2D(ReShade::BackBuffer, cursor_uv);
		value = GetGrayscale(pixel.rgb);
	}
	#elif WHITEPOINT_FIXER_MODE == 2
	{
		value = 0.0;

		for (int x = 0; x < DownsampleSize; ++x)
		{
			for (int y = 0; y < DownsampleSize; ++y)
			{
				float pixel = tex2Dfetch(Downsample, int4(x, y, 0, 0)).x;
				value = max(value, pixel);
			}
		}
	}
	#else
		#error "Invalid mode"
	#endif

	value = (value < MinimumWhitepoint)
		? RemappedWhitepoint
		: value;

	#if WHITEPOINT_FIXER_MODE == 2
		if (abs(TransitionSpeed) > 1e-6)
		{
			value = FXSHADERS_INTERPOLATE(
				tex2Dfetch(LastPickedColor, 0).x,
				value,
				TransitionSpeed,
				FrameTime * 0.001);
		}
	#endif

	return value;
}

#endif

#if WHITEPOINT_FIXER_MODE == 2

float SavePickedColorPS(
	float4 pos : SV_POSITION,
	float2 uv : TEXCOORD) : SV_TARGET
{
	return tex2Dfetch(PickedColor, 0).x;
}

#endif

float4 MainPS(
	float4 pos : SV_POSITION,
	float2 uv : TEXCOORD) : SV_TARGET
{

	float2 res = GetResolution();
	float2 coord = uv * res;

	float4 color = tex2D(ReShade::BackBuffer, uv);
	float whitepoint = GetWhitepoint();
	color.rgb /= max(whitepoint, 1e-6);

	#if WHITEPOINT_FIXER_MODE == 1
		if (RunColorPicker && MouseRightDown)
		{
			{
				float size = ColorPickerCrosshairThickness;
				size *= 0.5;

				color.rgb = lerp(
					color.rgb,
					1.0 - color.rgb,
					saturate(
						Contains(size, MousePoint.x, coord.x) +
						Contains(size, MousePoint.y, coord.y)));
			}

			float2 picker_pos = MousePoint;
			float2 offset = ColorPickerTooltipOffset;

			// Make the tooltip always visible on the screen by flipping the
			// offset if it's gone outside the screen bounds.
			picker_pos +=
				(picker_pos + offset < 0.0 ||
				picker_pos + offset > res)
					? -offset
					: offset;

			float dist = distance(coord, picker_pos);
			float circle = step(dist, ColorPickerTooltipRadius);

			color.rgb = lerp(color.rgb, whitepoint, circle);
		}
	#endif

	#if WHITEPOINT_FIXER_MODE_1_OR_2
		if (ShowWhitepoint)
		{
			float2 whitepoint_pos =
				(1.0 - abs(uv - 0.5) * 2.0) * res;

			if (
				whitepoint_pos.x < ShowWhitepointSize.x &&
				whitepoint_pos.y < ShowWhitepointSize.y)
			{
				color.rgb = whitepoint;
			}
		}
	#endif

	return color;
}

//#endregion

//#region Technique

technique WhitepointerFixer
{
	#if WHITEPOINT_FIXER_MODE == 2

	pass Downsample
	{
		VertexShader = PostProcessVS;
		PixelShader = DownsamplePS;
		RenderTarget = DownsampleTex;
	}

	#endif

	#if WHITEPOINT_FIXER_MODE_1_OR_2

	pass PickColor
	{
		VertexShader = PostProcessVS;
		PixelShader = PickColorPS;
		RenderTarget = PickedColorTex;
	}

	#if WHITEPOINT_FIXER_MODE == 2

	pass SavePickedColor
	{
		VertexShader = PostProcessVS;
		PixelShader = SavePickedColorPS;
		RenderTarget = LastPickedColorTex;
	}

	#endif

	#endif

	pass Main
	{
		VertexShader = PostProcessVS;
		PixelShader = MainPS;
	}
}

//#endregion

}
