/**
  Vibrance
  by Christian Cann Schuldt Jensen ~ CeeJay.dk
 
  Vibrance intelligently boosts the saturation of pixels so pixels that had little color get a larger boost than pixels that had a lot.
  This avoids oversaturation of pixels that were already very saturated.

  History:

  Version 1.0 by Ceejay.dk
  - Original 
  Version 1.1 by CeeJay.dk
  - Introduced RBG balance to help colorblind users
  Version 1.1.1
  - Minor UI improvements for Reshade 3.x
 */

#include "ReShadeUI.fxh"

uniform float Vibrance < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "自然饱和度";
	ui_tooltip = "根据像素原本的饱和度智能地饱和（或使用负值时去饱和）像素。";
> = 0.15;

uniform float3 VibranceRGBBalance <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 10.0;
	ui_label = "RGB平衡";
	ui_tooltip = "每个通道对自然饱和度强度的倍增器，让您可以对某些颜色给予比其他颜色更多的增强。\n如果您是色盲并且对特定颜色不太敏感，这会很有用。\n然后您可以比其他颜色更多地增强该颜色。";
> = float3(1.0, 1.0, 1.0);

/*
uniform int Vibrance_Luma <
	ui_type = "combo";
	ui_label = "Luma type";
	ui_items = "Perceptual\0Even\0";
> = 0;
*/

#include "ReShade.fxh"

float3 VibrancePass(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
  
	float3 coefLuma = float3(0.212656, 0.715158, 0.072186);
	
	/*
	if (Vibrance_Luma)
		coefLuma = float3(0.333333, 0.333334, 0.333333);
	*/
	
	float luma = dot(coefLuma, color);


	float max_color = max(color.r, max(color.g, color.b)); // Find the strongest color
	float min_color = min(color.r, min(color.g, color.b)); // Find the weakest color

	float color_saturation = max_color - min_color; // The difference between the two is the saturation

	// Extrapolate between luma and original by 1 + (1-saturation) - current
	float3 coeffVibrance = float3(VibranceRGBBalance * Vibrance);
	color = lerp(luma, color, 1.0 + (coeffVibrance * (1.0 - (sign(coeffVibrance) * color_saturation))));

	return color;
}

technique Vibrance
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = VibrancePass;
	}
}
