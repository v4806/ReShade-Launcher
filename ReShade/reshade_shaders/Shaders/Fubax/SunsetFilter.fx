/*------------------.
| :: Description :: |
'-------------------/

SunsetFilter PS (version 1.1.0)

Copyright:
This code © 2018-2023 Jakub Maksymilian Fober

License:
This work is licensed under the Creative Commons
Attribution-ShareAlike 4.0 International License.
To view a copy of this license, visit
http://creativecommons.org/licenses/by-sa/4.0/
*/

/*--------------.
| :: Commons :: |
'--------------*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "LinearGammaWorkflow.fxh"

/*-----------.
| :: Menu :: |
'-----------*/

uniform float3 ColorA
<	__UNIFORM_COLOR_FLOAT3
	ui_label = "颜色 (A)";
	ui_category = "颜色";
> = float3(1f, 0f, 0f);

uniform float3 ColorB
<	__UNIFORM_COLOR_FLOAT3
	ui_label = "颜色 (B)";
	ui_type = "color";
	ui_category = "颜色";
> = float3(0f, 0f, 0f);

uniform bool Flip
<
	ui_label = "颜色翻转";
	ui_category = "颜色";
> = false;

uniform int Axis
<	__UNIFORM_SLIDER_INT1
	ui_units = "°";
	ui_label = "角度";
	ui_min = -180; ui_max = 180;
	ui_category = "控制";
> = -7;

uniform float Scale
<	__UNIFORM_SLIDER_FLOAT1
	ui_label = "渐变锐度";
	ui_min = 0.5; ui_max = 1f; ui_step = 0.005;
	ui_category = "控制";
> = 1f;

uniform float Offset
<	__UNIFORM_SLIDER_FLOAT1
	ui_label = "位置";
	ui_min = 0f; ui_max = 0.5;
	ui_category = "控制";
> = 0f;

/*----------------.
| :: Functions :: |
'----------------*/

// Overlay blending mode
float Overlay(float Layer)
{
	float Min = min(Layer, 0.5);
	float Max = max(Layer, 0.5);
	return 2f*(Min*Min+2f*Max-Max*Max)-1.5;
}

// Screen blending mode
float3 Screen(float3 LayerA, float3 LayerB)
{ return 1f-(1f-LayerA)*(1f-LayerB); }

/*--------------.
| :: Shaders :: |
'--------------*/

void SunsetFilterPS(
	float4 vpos      : SV_Position,
	float2 UvCoord   : TEXCOORD,
	out float3 Image : SV_Target
)
{
	// Grab screen texture
	Image = GammaConvert::to_linear(tex2D(ReShade::BackBuffer, UvCoord).rgb);
	// Correct Aspect Ratio
	float2 UvCoordAspect = UvCoord;
	UvCoordAspect.y += BUFFER_ASPECT_RATIO*0.5-0.5;
	UvCoordAspect.y /= BUFFER_ASPECT_RATIO;
	// Center coordinates
	UvCoordAspect = UvCoordAspect*2f-1f;
	UvCoordAspect *= Scale;

	// Tilt vector
	float Angle = radians(-Axis);
	float2 TiltVector = float2(sin(Angle), cos(Angle));

	// Blend Mask
	float BlendMask = dot(TiltVector, UvCoordAspect)+Offset;
	BlendMask = Overlay(BlendMask*0.5+0.5); // Linear coordinates

	// Color image
	Image = Screen(
		Image.rgb,
		lerp(
			GammaConvert::to_linear(ColorA),
			GammaConvert::to_linear(ColorB),
			Flip ? 1f-BlendMask : BlendMask
		));

	Image = GammaConvert::to_display(Image);
}

/*-------------.
| :: Output :: |
'-------------*/

technique SunsetFilter
<
	ui_label = "日落滤镜";
	ui_tooltip =
		"此效果 © 2018-2023 Jakub Maksymilian Fober\n"
		"基于 CC BY-SA 4.0 许可";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = SunsetFilterPS;
	}
}
