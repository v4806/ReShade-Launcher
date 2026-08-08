/*
	Credits to opezdl/AgainstAllAuthority       and The ReShade team 
	Amateur port by Insomnia 
*/	

uniform float CrossContrast <
	ui_type = "slider";
	ui_min = 0.50; ui_max = 2.0;
	ui_label = "对比度";
	ui_tooltip = "对比度";
> = 1.0;
uniform float CrossSaturation <
	ui_type = "slider";
	ui_min = 0.50; ui_max = 2.00;
	ui_label = "饱和度";
	ui_tooltip = "饱和度";
> = 1.0;
uniform float CrossBrightness <
	ui_type = "slider";
	ui_min = -1.000; ui_max = 1.000;
	ui_label = "亮度";
	ui_tooltip = "亮度";
> = 0.0;
uniform float CrossAmount <
	ui_type = "slider";
	ui_min = 0.05; ui_max = 1.50;
	ui_label = "交叉量";
	ui_tooltip = "交叉量";
> = 0.50;


#include "ReShade.fxh"

float3 CrossPass(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
  const float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	const float2 CrossMatrix [3] = {
		float2 (1.03, 0.04),
		float2 (1.09, 0.01),
		float2 (0.78, 0.13),
 		};

	float3 image1 = color.rgb;
	float3 image2 = color.rgb;
	const float gray = dot(float3(0.5,0.5,0.5), image1);  
	image1 = lerp (gray, image1,CrossSaturation);
	image1 = lerp (0.35, image1,CrossContrast);
	image1 +=CrossBrightness;
	image2.r = image1.r * CrossMatrix[0].x + CrossMatrix[0].y;
	image2.g = image1.g * CrossMatrix[1].x + CrossMatrix[1].y;
	image2.b = image1.b * CrossMatrix[2].x + CrossMatrix[2].y;

	return lerp(image1, image2, CrossAmount);
}


technique Cross
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = CrossPass;
	}
}
