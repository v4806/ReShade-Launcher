#include "ReShade.fxh"

texture ditherTex < source = "ZNbluenoise512.png"; > { Width = 512; Height = 512; Format = RGBA8; };
sampler	ditherSam 	{ Texture = ditherTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};


uniform float Pixel_Size <
	ui_type = "slider";
	ui_tooltip = "对图像进行像素化处理";
	ui_label = "像素大小";
	ui_min = 0.0;
	ui_max = 16.0;
	ui_step = 1.0;
> = 3.0;

uniform float Dither_Strength <
	ui_type = "slider";
	ui_tooltip = "引入噪点以减少色带";
	ui_label = "抖动强度";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.05;

uniform float Contrast <
	ui_type = "slider";
	ui_label = "对比度";
	ui_min = 0.01;
	ui_max = 3.0;
> = 0.85;

uniform float Pre_Boost <
	ui_type = "slider";
	ui_tooltip = "在颜色调整之前提升亮度";
	ui_label = "预增益";
	ui_min = 0.0;
	ui_max = 3.0;
> = 0.55;

uniform float ToneGrade_Blend <
	ui_type = "slider";
	ui_tooltip = "在轻微色调映射和调色输入之间混合";
	ui_label = "调色";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.6;

uniform float Color_Quantize <
	ui_type = "slider";
	ui_tooltip = "降低色深以产生色带效果";
	ui_label = "颜色量化";
	ui_min = 1.0;
	ui_max = 255.0;
	ui_step = 1.0;
> = 32;

uniform float Bright_Scoop <
	ui_type = "slider";
	ui_tooltip = "增加亮色的对比度以防止图像过亮";
	ui_label = "高光压缩";
	ui_min = 0.0;
	ui_max = 30.0;
> = 3.0;



float3 ACESFilm(float3 x)
{
	float a = 2.51f;
	float b = 0.03f;
	float c = 2.43f;
	float d = 0.59f;
	float e = 0.14f;
	return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}



float3 ZN_Stylize_FXmain(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 uv = float2(BUFFER_WIDTH, BUFFER_HEIGHT);

	float2 CCV = 1.0 / Pixel_Size * uv;
	float3 ditherQuant = tex2D(ditherSam, ((texcoord * uv / (512 * Pixel_Size)) - floor(texcoord * uv / (512 * Pixel_Size)))).rgb;	//Allows for downsampling independent of aspect ratio
	float3 TexQuant = tex2D(ReShade::BackBuffer, 0.5 / uv +floor((texcoord * CCV)) / CCV).rgb;
	float3 input = tex2D(ReShade::BackBuffer, 0.5 / uv + floor((texcoord * CCV)) / CCV).rgb; //quantizes input based on Pixel_Size
	
	//Linear Gamma Conversion
	input = pow(input, 2.2) * Pre_Boost;
	
	
	//Color grading
	float3 blend = pow(input, Contrast * (1.0 / 2.2));
	blend.r = ((pow(blend.r, Bright_Scoop) / 1.77) + 1.0) * (0.8 * pow(sin (2.04* blend.r), 1.9) );
	blend.g = ((pow(blend.g, Bright_Scoop) / 1.77) + 1.0) * (0.8 * pow(sin (2.02* blend.g), 2.0) );
	blend.b = ((pow(blend.b, Bright_Scoop) / 1.77) + 1.0) * (0.8 * pow(sin (2.02* blend.b), 1.9) );
	
	//ACES tonemapping
	input = ACESFilm(input);
	
	//Gamma correction
	input = pow(input, 1.0 / 2.2);
	
	//Blending between ACES and Color grade
	input = lerp(input, blend, ToneGrade_Blend);
	
	//Contrast adjustment and dither blending
	input = pow(((1 - Dither_Strength) * input - Dither_Strength * ditherQuant), Contrast);
	
	//Color Quantization
	input = round((input) * Color_Quantize) / Color_Quantize;
	
	return input;
}

technique ZN_Stylize
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = ZN_Stylize_FXmain;
	}
}
