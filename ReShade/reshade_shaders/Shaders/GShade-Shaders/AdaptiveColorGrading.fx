/**
 * Adaptive Color Grading
 * Runs two LUTs simultaneously, smoothly lerping between them based on luma.
 * By moriz1
 * Based on Marty's LUT shader 1.0 for ReShade 3.0
 * Copyright © 2008-2016 Marty McFly
 */

#ifndef fLUT_TextureDay
	#define fLUT_TextureDay "lutDAY.png"
#endif
#ifndef fLUT_TextureNight
	#define fLUT_TextureNight "lutNIGHT.png"
#endif
#ifndef fLUT_TileSizeXY
	#define fLUT_TileSizeXY 32
#endif
#ifndef fLUT_TileAmount
	#define fLUT_TileAmount 32
#endif

uniform bool DebugLuma <
    ui_label = "显示亮度调试条";
	ui_tooltip = "在屏幕左上角绘制调试条";
> = false;

uniform bool DebugLumaOutput <
    ui_label = "显示亮度输出";
	ui_tooltip = "黑白模糊模式！";
> = false;

uniform bool DebugLumaOutputHQ <
    ui_label = "显示原生分辨率亮度输出";
	ui_tooltip = "黑白模式！";
> = false;

uniform bool EnableHighlightsInDarkScenes <
	ui_label = "启用高光";
    ui_tooltip = "在暗场景中为明亮物体添加高光";
> = true;

uniform bool DebugHighlights <
    ui_label = "显示调试高光";
	ui_tooltip = "如果帧中有任何高光，将其着色为洋红色";
> = false;

uniform float LumaChangeSpeed <
	ui_label = "自适应速度";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.05;

uniform float LumaHigh <
	ui_label = "亮度最大阈值";
	ui_tooltip = "亮度高于此级别使用完整的日间LUT\n设置高于最小阈值";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.75;

uniform float LumaLow <
	ui_label = "亮度最小阈值";
	ui_tooltip = "亮度低于此级别使用完整的夜间LUT\n设置低于最大阈值";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.2;

uniform float AmbientHighlightThreshold <
	ui_label = "低亮度高光起始点";
	ui_tooltip = "如果平均亮度低于此限制，开始添加高光\n模拟低光下的HDR外观";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.5;

uniform float HighlightThreshold <
	ui_label = "高光最小亮度";
	ui_tooltip = "任何高于此值的亮度将有高光\n模拟低光下的HDR外观";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.5;

uniform float HighlightMaxThreshold <
	ui_label = "高光最大亮度";
	ui_tooltip = "高光在此亮度值达到最大强度\n模拟低光下的HDR外观";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.8;

#include "ReShade.fxh"

texture ACGLumaInputTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; MipLevels = 6; };
sampler LumaInputSampler { Texture = ACGLumaInputTex; MipLODBias = 6.0f; };
sampler LumaInputSamplerHQ { Texture = ACGLumaInputTex; };

texture ACGLumaTex { Width = 1; Height = 1; Format = R8; };
sampler LumaSampler { Texture = ACGLumaTex; };

texture ACGLumaTexLF { Width = 1; Height = 1; Format = R8; };
sampler LumaSamplerLF { Texture = ACGLumaTexLF; };

texture texLUTDay < source = fLUT_TextureDay; > { Width = fLUT_TileSizeXY*fLUT_TileAmount; Height = fLUT_TileSizeXY; Format = RGBA8; };
sampler	SamplerLUTDay	{ Texture = texLUTDay; };

texture texLUTNight < source = fLUT_TextureNight; > { Width = fLUT_TileSizeXY*fLUT_TileAmount; Height = fLUT_TileSizeXY; Format = RGBA8; };
sampler	SamplerLUTNight	{ Texture = texLUTNight; };

float SampleLuma(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	float luma = 0.0;

	const int width = BUFFER_WIDTH / 64;
	const int height = BUFFER_HEIGHT / 64;

	for (int i = width/3; i < 2*width/3; i++) {
		for (int j = height/3; j < 2*height/3; j++) {
			luma += tex2Dlod(LumaInputSampler, float4(i, j, 0, 6)).x;
		}
	}

	luma /= (width * 1/3) * (height * 1/3);

	const float lastFrameLuma = tex2D(LumaSamplerLF, float2(0.5, 0.5)).x;

	return lerp(lastFrameLuma, luma, LumaChangeSpeed);
}

float LumaInput(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	const float3 color = tex2D(ReShade::BackBuffer, texcoord).xyz;

	return pow(abs((color.r*2 + color.b + color.g*3) / 6), 1/2.2);
}

float3 ApplyLUT(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	float3 color = tex2D(ReShade::BackBuffer, texcoord.xy).rgb;
	const float lumaVal = tex2D(LumaSampler, float2(0.5, 0.5)).x;
	const float highlightLuma = tex2D(LumaInputSamplerHQ, texcoord.xy).x;

	if (DebugLumaOutputHQ) {
		return highlightLuma;
	}
	else if (DebugLumaOutput) {
		return lumaVal;
	}

	if (DebugLuma) {
		if (texcoord.y <= 0.01 && texcoord.x <= 0.01) {
			return lumaVal;
		}
		if (texcoord.y <= 0.01 && texcoord.x > 0.01 && texcoord.x <= 0.02) {
			if (lumaVal > LumaHigh) {
				return float3(1.0, 1.0, 1.0);
			}
			else {
				return float3(0.0, 0.0, 0.0);
			}
		}
		if (texcoord.y <= 0.01 && texcoord.x > 0.02 && texcoord.x <= 0.03) {
			if (lumaVal <= LumaHigh && lumaVal >= LumaLow) {
				return float3(1.0, 1.0, 1.0);
			}
			else {
				return float3(0.0, 0.0, 0.0);
			}
		}
		if (texcoord.y <= 0.01 && texcoord.x > 0.03 && texcoord.x <= 0.04) {
			if (lumaVal < LumaLow) {
				return float3(1.0, 1.0, 1.0);
			}
			else {
				return float3(0.0, 0.0, 0.0);
			}
		}
	}

	float2 texelsize = 1.0 / fLUT_TileSizeXY;
	texelsize.x /= fLUT_TileAmount;

	float3 lutcoord = float3((color.xy*fLUT_TileSizeXY-color.xy+0.5)*texelsize.xy,color.z*fLUT_TileSizeXY-color.z);
	const float lerpfact = frac(lutcoord.z);

	lutcoord.x += (lutcoord.z-lerpfact)*texelsize.y;
	
	const float3 color1 = lerp(tex2D(SamplerLUTDay, lutcoord.xy).xyz, tex2D(SamplerLUTDay, float2(lutcoord.x+texelsize.y,lutcoord.y)).xyz,lerpfact);
	const float3 color2 = lerp(tex2D(SamplerLUTNight, lutcoord.xy).xyz, tex2D(SamplerLUTNight, float2(lutcoord.x+texelsize.y,lutcoord.y)).xyz,lerpfact);	

	const float range = (lumaVal - LumaLow)/(LumaHigh - LumaLow);

	if (lumaVal > LumaHigh) {
		color.xyz = color1.xyz;
	}
	else if (lumaVal < LumaLow) {
		color.xyz = color2.xyz;
	}
	else {
		color.xyz = lerp(color2.xyz, color1.xyz, range);
	}

	float3 lutcoord2 = float3((color.xy*fLUT_TileSizeXY-color.xy+0.5)*texelsize.xy,color.z*fLUT_TileSizeXY-color.z);
	const float lerpfact2 = frac(lutcoord2.z);

	lutcoord2.x += (lutcoord2.z-lerpfact2)*texelsize.y;

	const float3 highlightColor = lerp(tex2D(SamplerLUTDay, lutcoord2.xy).xyz, tex2D(SamplerLUTDay, float2(lutcoord2.x+texelsize.y,lutcoord2.y)).xyz,lerpfact2);

	//apply highlights
	if (EnableHighlightsInDarkScenes) {
		if (lumaVal < AmbientHighlightThreshold && highlightLuma > HighlightThreshold) {
			const float range = saturate((highlightLuma - HighlightThreshold)/(HighlightMaxThreshold - HighlightThreshold)) * 
							saturate((AmbientHighlightThreshold - lumaVal)/(0.1));

			if (DebugHighlights) {
				color.xyz = lerp(color.xyz, float3(1.0, 0.0, 1.0), range);
				
				if (range >= 1.0) {
					color.xyz = float3(1.0, 0.0, 0.0);
				}
			}

			color.xyz = lerp(color.xyz, highlightColor.xyz, range);
		}
	}

	return color;
}

float SampleLumaLF(float4 position : SV_Position, float2 texcoord: TexCoord) : SV_Target {
	return tex2D(LumaSampler, float2(0.5, 0.5)).x;
}

technique AdaptiveColorGrading {
	pass Input {
		VertexShader = PostProcessVS;
		PixelShader = LumaInput;
		RenderTarget = ACGLumaInputTex
	;
	}
	pass StoreLuma {
		VertexShader = PostProcessVS;
		PixelShader = SampleLuma;
		RenderTarget = ACGLumaTex;
	}
	pass Apply_LUT {
		VertexShader = PostProcessVS;
		PixelShader = ApplyLUT;
	}
	pass StoreLumaLF {
		VertexShader = PostProcessVS;
		PixelShader = SampleLumaLF;
		RenderTarget = ACGLumaTexLF;
	}
}
