/*
	PandaFX version 2.0 for ReShade 3.4.x
	by Jukka Korhonen aka Loadus ~ twitter.com/thatbonsaipanda
	November 2018
	jukka.korhonen@gmail.com
	
	Applies cinematic lens effects and color grading.
	Free licence to copy, modify, tweak and publish but
	if you can, give credit. Thanks. o/
	
	- jP
 */

#include "ReShade.fxh"

namespace PandaFX
{
	// UNIFORMS
	//--------------------------------------------
	uniform bool Enable_Diffusion <
		ui_label = "启用镜头漫射效果";
		ui_tooltip = "启用模拟相机镜头眩光的光线漫射效果。";
	> = true;

	uniform bool Enable_Bleach_Bypass <
		ui_label = "启用'漂白旁路'效果";
		ui_tooltip = "启用模拟胶片漂白旁路的电影对比度效果。常用于战争电影，使图像更具粗犷感。";
	> = true;

	uniform bool Enable_Static_Dither <
		ui_label = "应用静态抖动";
		ui_tooltip = "对漫射进行抖动。仅应用静态抖动图像纹理。";
	> = true;

	uniform bool Enable_Dither <
		ui_label = "对最终输出进行抖动";
		ui_tooltip = "对着色器的最终结果进行抖动。";
	> = false;

	uniform float Blend_Amount <
		ui_label = "混合量";
		ui_type = "drag";
		ui_min = 0.000;
		ui_max = 1.000;
		ui_step = 0.01;
		ui_tooltip = "将效果与原始图像混合。";
	> = 0.5;

	uniform float Bleach_Bypass_Amount <
		ui_label = "漂白旁路量";
		ui_type = "drag";
		ui_min = 0.000;
		ui_max = 1.000;
		ui_step = 0.01;
		ui_tooltip = "调整第三漫射层的量。";
	> = 0.5;

	uniform float Contrast_R <
		ui_label = "对比度（红）";
		ui_type = "drag";
		ui_min = 0.00001;
		ui_max = 20.0;
		ui_step = 0.01;
		ui_tooltip = "对红色应用对比度。";
	> = 0.9;

	uniform float Contrast_G <
		ui_label = "对比度（绿）";
		ui_type = "drag";
		ui_min = 0.00001;
		ui_max = 20.0;
		ui_step = 0.01;
		ui_tooltip = "对绿色应用对比度。";
	> = 0.8;

	uniform float Contrast_B <
		ui_label = "对比度（蓝）";
		ui_type = "drag";
		ui_min = 0.00001;
		ui_max = 20.0;
		ui_step = 0.01;
		ui_tooltip = "对蓝色应用对比度。";
	> = 0.8;

	uniform float Gamma_R <
		ui_label = "伽马（红）";
		ui_type = "drag";
		ui_min = 0.02;
		ui_max = 5.00;
		ui_step = 0.01;
		ui_tooltip = "对红色应用伽马。";
	> = 1.0;

	uniform float Gamma_G <
		ui_label = "伽马（绿）";
		ui_type = "drag";
		ui_min = 0.02;
		ui_max = 5.00;
		ui_step = 0.01;
		ui_tooltip = "对绿色应用伽马。";
	> = 1.0;

	uniform float Gamma_B <
		ui_label = "伽马（蓝）";
		ui_type = "drag";
		ui_min = 0.02;
		ui_max = 5.00;
		ui_step = 0.01;
		ui_tooltip = "对蓝色应用伽马。";
	> = 0.99;

	uniform float Diffusion_1_Amount <
		ui_category = "漫射层 1";
		ui_label = "数量";
		ui_type = "drag";
		ui_min = 0.000;
		ui_max = 1.000;
		ui_step = 0.01;
		ui_tooltip = "调整第一漫射层的量。";
	> = 0.3;

	uniform float Diffusion_1_Radius <
		ui_category = "漫射层 1";
		ui_label = "半径";
		ui_type = "drag";
		ui_min = 5.0;
		ui_max = 20.0;
		ui_step = 0.01;
		ui_tooltip = "设置第一漫射层的半径。";
	> = 8.0;

	uniform float Diffusion_1_Gamma <
		ui_category = "漫射层 1";
		ui_label = "中间调";
		ui_type = "drag";
		ui_min = 0.02;
		ui_max = 5.0;
		ui_step = 0.01;
		ui_tooltip = "对第一漫射层应用伽马。";
	> = 0.7;

	uniform float Diffusion_1_Quality <
		ui_category = "漫射层 1";
		ui_label = "采样质量";
		ui_type = "drag";
		ui_min = 1.00;
		ui_max = 64.00;
		ui_step = 1.0;
		ui_tooltip = "设置第一漫射层的质量。数字是纹理尺寸减半的除数。数字越小质量越高，但需要更多处理。（通常无需调整。）";
	> = 2.0;

	uniform float Diffusion_2_Amount <
		ui_category = "漫射层 2";
		ui_label = "数量";
		ui_type = "drag";
		ui_min = 0.000;
		ui_max = 1.000;
		ui_step = 0.01;
		ui_tooltip = "调整第二漫射层的量。";
	> = 0.2;

	uniform float Diffusion_2_Radius <
		ui_category = "漫射层 2";
		ui_label = "半径";
		ui_type = "drag";
		ui_min = 5.0;
		ui_max = 20.0;
		ui_step = 0.01;
		ui_tooltip = "设置第二漫射层的半径。";
	> = 5.0;

	uniform float Diffusion_2_Gamma <
		ui_category = "漫射层 2";
		ui_label = "中间调";
		ui_type = "drag";
		ui_min = 0.02;
		ui_max = 5.0;
		ui_step = 0.01;
		ui_tooltip = "对第二漫射层应用伽马。";
	> = 0.5;

	uniform float Diffusion_2_Quality <
		ui_category = "漫射层 2";
		ui_label = "采样质量";
		ui_type = "drag";
		ui_min = 1.00;
		ui_max = 64.00;
		ui_step = 1.0;
		ui_tooltip = "设置第二漫射层的质量。数字是纹理尺寸减半的除数。数字越小质量越高，但需要更多处理。（通常无需调整。）";
	> = 16.0;

	uniform float Diffusion_3_Amount <
		ui_category = "漫射层 3";
		ui_label = "数量";
		ui_type = "drag";
		ui_min = 0.000;
		ui_max = 1.000;
		ui_step = 0.01;
		ui_tooltip = "调整第三漫射层的量。";
	> = 1.0;

	uniform float Diffusion_3_Radius <
		ui_category = "漫射层 3";
		ui_label = "半径";
		ui_type = "drag";
		ui_min = 5.0;
		ui_max = 20.0;
		ui_step = 0.01;
		ui_tooltip = "设置第三漫射层的半径。";
	> = 7.4;

	uniform float Diffusion_3_Gamma <
		ui_category = "漫射层 3";
		ui_label = "中间调";
		ui_type = "drag";
		ui_min = 0.02;
		ui_max = 5.0;
		ui_step = 0.01;
		ui_tooltip = "对第三漫射层应用伽马。";
	> = 5.0;

	uniform float Diffusion_3_Quality <
		ui_category = "漫射层 3";
		ui_label = "采样质量";
		ui_type = "drag";
		ui_min = 1.00;
		ui_max = 64.00;
		ui_step = 1.0;
		ui_tooltip = "设置第三漫射层的质量。数字是纹理尺寸减半的除数。数字越小质量越高，但需要更多处理。（通常无需调整。）";
	> = 3.0;

	uniform int framecount < source = "framecount"; >;


	// TEXTURES
	//--------------------------------------------
	texture NoiseTex <source = "hd_noise.png"; > { Width = 1920; Height = 1080; Format = RGBA8; };
	texture prePassLayer { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
	texture blurLayerHorizontal { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA8; };
	texture blurLayerVertical { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA8; };
	texture blurLayerHorizontalMedRes { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA8; };
	texture blurLayerVerticalMedRes { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA8; };
	texture blurLayerHorizontalLoRes { Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA8; };
	texture blurLayerVerticalLoRes { Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA8; };


	// SAMPLERS
	//--------------------------------------------
	sampler2D NoiseSampler { Texture = NoiseTex; };
	sampler2D PFX_PrePassLayer { Texture = prePassLayer; };
	// ------- samplers for large radius blur
	sampler2D PFX_blurHorizontalLayer { Texture = blurLayerHorizontal; };
	sampler2D PFX_blurVerticalLayer { Texture = blurLayerVertical; };
	sampler2D PFX_blurHorizontalLayerMedRes { Texture = blurLayerHorizontalMedRes; };
	sampler2D PFX_blurVerticalLayerMedRes { Texture = blurLayerVerticalMedRes; };
	sampler2D PFX_blurHorizontalLayerLoRes { Texture = blurLayerHorizontalLoRes; };
	sampler2D PFX_blurVerticalLayerLoRes { Texture = blurLayerVerticalLoRes; };


	// FUNCTIONS
	//--------------------------------------------
	float AdjustableSigmoidCurve (float value, float amount) 
	{
		return value < 0.5 ? pow(value, amount) * pow(2.0, amount) * 0.5 
						   : 1.0 - pow(1.0 - value, amount) * pow(2.0, amount) * 0.5;
	}

	float Randomize (float2 coord) 
	{
		return clamp((frac(sin(dot(coord, float2(12.9898, 78.233))) * 43758.5453)), 0.0, 1.0);
	}

	float SigmoidCurve (float value) 
	{
		value = value * 2.0 - 1.0;
		return -value * abs(value) * 0.5 + value + 0.5;	
	}

	float4 BlurH (sampler2D input, float2 uv, float radius, float sampling) 
	{
		float4 avgColor = float4(0.0, 0.0, 0.0, 0.0);
		float width = 1.0 / BUFFER_WIDTH * (sampling + (sampling==0));
		float4 tapCoord = float4(0, 0, 0, 0);
		for (float x = -radius; x <= radius; x++)
		{
			float2 coordinate = uv + float2(x * width, 0.0);
			tapCoord.xy = clamp(coordinate, 0.0, 1.0); 
			float weight = SigmoidCurve(1.0 - (abs(x) / (radius + (radius==0))));
			avgColor.rgb += tex2Dlod(input, tapCoord).rgb * weight;
			avgColor.a += weight;
		}
		
		avgColor.rgb /= (avgColor.a + (avgColor.a==0));
		avgColor.a = 1.0;
		return avgColor;
	}

	float4 BlurV (sampler input, float2 uv, float radius, float sampling) 
	{
		float4 avgColor = float4(0.0, 0.0, 0.0, 0.0);
		float height = 1.0 / BUFFER_HEIGHT * sampling;
		float4 tapCoord = float4(0, 0, 0, 0);
		for (float y = -radius; y <= radius; y++)
		{
			float2 coordinate = uv + float2(0.0, y * height);
			tapCoord.xy = clamp(coordinate, 0.0, 1.0); 
			float weight = SigmoidCurve(1.0 - (abs(y) / (radius + (radius==0))));
			avgColor.rgb += tex2Dlod(input, tapCoord).rgb * weight;
			avgColor.a += weight;
		}
		
		avgColor.rgb /= (avgColor.a + (avgColor.a==0));
		avgColor.a = 1.0;
		return avgColor;
	}



	// SHADERS
	//--------------------------------------------
	void PS_PrePass (float4 pos : SV_Position, 
					 float2 uv : TEXCOORD, 
					 out float4 result : SV_Target) 
	{
		float4 A = tex2D(ReShade::BackBuffer, uv);
		A.r = pow(A.r, Gamma_R);
		A.g = pow(A.g, Gamma_G);
		A.b = pow(A.b, Gamma_B);
		A.r = AdjustableSigmoidCurve(A.r, Contrast_R);
		A.g = AdjustableSigmoidCurve(A.g, Contrast_G);
		A.b = AdjustableSigmoidCurve(A.b, Contrast_B);
		
		// ------- Change color weights of the final render, similar to a printed film
		A.g = A.g * 0.8 + A.b * 0.2;

		float red = clamp(A.r - A.g - A.b, 0.0, 1.0);
		float green = clamp(A.g - A.r - A.b, 0.0, 1.0);
		float blue = clamp(A.b - A.r - A.g, 0.0, 1.0);

		A = A * (1.0 - red * 0.6);
		A = A * (1.0 - green * 0.8);
		A = A * (1.0 - blue * 0.3);

		result = A;
	}


	void PS_HorizontalPass (float4 pos : SV_Position, 
							float2 uv : TEXCOORD, out float4 result : SV_Target) 
	{
		result = BlurH(PFX_PrePassLayer, uv, Diffusion_1_Radius, Diffusion_1_Quality);
	}

	void PS_VerticalPass (float4 pos : SV_Position, 
						  float2 uv : TEXCOORD, out float4 result : SV_Target) 
	{
		result = BlurV(PFX_blurHorizontalLayer, uv, Diffusion_1_Radius, Diffusion_1_Quality);
	}

	void PS_HorizontalPassMedRes (float4 pos : SV_Position, 
							float2 uv : TEXCOORD, out float4 result : SV_Target) 
	{
		result = BlurH(PFX_blurVerticalLayer, uv, Diffusion_2_Radius, Diffusion_2_Quality);
	}

	void PS_VerticalPassMedRes (float4 pos : SV_Position, 
						  float2 uv : TEXCOORD, out float4 result : SV_Target) 
	{
		result = BlurV(PFX_blurHorizontalLayerMedRes, uv, Diffusion_2_Radius, Diffusion_2_Quality);
	}

	void PS_HorizontalPassLoRes (float4 pos : SV_Position, 
							float2 uv : TEXCOORD, out float4 result : SV_Target) 
	{
		result = BlurH(PFX_blurVerticalLayerMedRes, uv, Diffusion_3_Radius, Diffusion_3_Quality);
	}

	void PS_VerticalPassLoRes (float4 pos : SV_Position, 
						  float2 uv : TEXCOORD, out float4 result : SV_Target) 
	{
		result = BlurV(PFX_blurHorizontalLayerLoRes, uv, Diffusion_3_Radius, Diffusion_3_Quality);
	}

	float4 PS_Composition (float4 vpos : SV_Position, 
							 float2 uv : TEXCOORD) : SV_Target 
	{
		// ------- Create blurred layers for lens diffusion
		float4 blurLayer;
		float4 blurLayerMedRes;
		float4 blurLayerLoRes;

		// ------- Read original image
		float4 A = tex2D(PFX_PrePassLayer, uv);
		float4 O = tex2D(ReShade::BackBuffer, uv);
		float3 rndSample = tex2D(NoiseSampler, uv).rgb;
		
		if (Enable_Diffusion)
		{
			// TODO enable/disable for performance >>
			blurLayer = tex2D(PFX_blurVerticalLayer, uv);
			blurLayerMedRes = tex2D(PFX_blurVerticalLayerMedRes, uv);
			blurLayerLoRes = tex2D(PFX_blurVerticalLayerLoRes, uv);

			// ------- Colorize the blur layers
			blurLayerMedRes = lerp(blurLayerMedRes, dot(0.3333, blurLayerMedRes.rgb), 0.75);
			blurLayerLoRes = lerp(blurLayerLoRes, dot(0.3333, blurLayerLoRes.rgb), 0.75);

			// ------- Set blur layer weights
			blurLayer *= Diffusion_1_Amount;
			blurLayerMedRes *= Diffusion_2_Amount;
			blurLayerLoRes *= Diffusion_3_Amount;
		
			blurLayer = pow(blurLayer, Diffusion_1_Gamma);
			blurLayerMedRes = pow(blurLayerMedRes, Diffusion_2_Gamma);
			blurLayerLoRes = pow(blurLayerLoRes, Diffusion_3_Gamma);

			if (Enable_Static_Dither)
			{
				float3 hd_noise = 1.0 - (rndSample * 0.01);
				blurLayer.rgb = 1.0 - hd_noise * (1.0 - blurLayer.rgb);
				blurLayerMedRes.rgb = 1.0 - hd_noise * (1.0 - blurLayerMedRes.rgb);
				blurLayerLoRes.rgb = 1.0 - hd_noise * (1.0 - blurLayerLoRes.rgb);
			}

			blurLayer = clamp(blurLayer, 0.0, 1.0);
			blurLayerMedRes = clamp(blurLayerMedRes, 0.0, 1.0);
			blurLayerLoRes = clamp(blurLayerLoRes, 0.0, 1.0);

			// ------- Screen blend the blur layers to create lens diffusion
			A.rgb = 1.0 - (1.0 - blurLayer.rgb) * (1.0 - A.rgb);
			A.rgb = 1.0 - (1.0 - blurLayerMedRes.rgb) * (1.0 - A.rgb);
			A.rgb = 1.0 - (1.0 - blurLayerLoRes.rgb) * (1.0 - A.rgb);
		}

		// ------ Compress contrast using Hard Light blending ------
		float Ag = dot(float3(0.3333, 0.3333, 0.3333), A.rgb);
		float4 C = (Ag > 0.5) ? 1 - 2 * (1 - Ag) * (1 - A) : 2 * Ag * A;
		C = pow(C, 0.6);
		A = lerp(A, C, Enable_Bleach_Bypass ? Bleach_Bypass_Amount : 0);

		// ------ Compress to TV levels if needed ------
		// A = A * 0.9373 + 0.0627;
		// ------ Create noise for dark level dither (heavy processing!) ------
		if (Enable_Dither)
		{
			float uvRnd = Randomize(rndSample.rg * framecount);
			float uvRnd2 = Randomize(rndSample.rg * framecount + 1);
			A -= tex2D(NoiseSampler, uv * uvRnd2).r * 0.04;
			A += tex2D(NoiseSampler, uv * uvRnd).r * 0.04;
		}
		return lerp(O, A, Blend_Amount);
	}

	// TECHNIQUES
	//--------------------------------------------
	technique PandaFX 
	{
		pass PreProcess	
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_PrePass;
			RenderTarget = prePassLayer;
		}

		pass HorizontalPass
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_HorizontalPass;
			RenderTarget = blurLayerHorizontal;
		}

		pass VerticalPass
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_VerticalPass;
			RenderTarget = blurLayerVertical;
		}

		pass HorizontalPassMedRes
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_HorizontalPassMedRes;
			RenderTarget = blurLayerHorizontalMedRes;
		}

		pass VerticalPassMedRes
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_VerticalPassMedRes;
			RenderTarget = blurLayerVerticalMedRes;
		}

		pass HorizontalPassLoRes
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_HorizontalPassLoRes;
			RenderTarget = blurLayerHorizontalLoRes;
		}

		pass VerticalPassLoRes
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_VerticalPassLoRes;
			RenderTarget = blurLayerVerticalLoRes;
		}

		pass CustomPass
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_Composition ;
		}
	}
}