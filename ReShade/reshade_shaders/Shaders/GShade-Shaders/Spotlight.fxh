/*
	Spotlight shader based on the Flashlight shader by luluco250

	MIT Licensed.

	Modifications by ninjafada and Marot Satil


	Copyright (c) 2017 Lucas Melo

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
*/

sampler2D sColor {
	Texture = ReShade::BackBufferTex;
	SRGBTexture = true;
	MinFilter = POINT;
	MagFilter = POINT;
};

#define SPOTLIGHT_SUMMONING(Spotlight_Category, Spotlight_Center_X, Spotlight_Center_Y, Spotlight_Brightness, Spotlight_Size, Spotlight_Color, Spotlight_InvertDepthCutoff, Spotlight_DepthCutoff, Spotlight_Distance, Spotlight_BlendFix, Spotlight_ToggleTexture, Spotlight_ToggleDepth, Spotlight_ToggleDepthCutoff, Spotlight_PS, Spotlight_Name) \
uniform float Spotlight_Center_X < \
	ui_category = Spotlight_Category; \
	ui_category_closed = true; \
	ui_label = "X位置"; \
	ui_type = "slider"; \
	ui_min = -1.0; ui_max = 1.0; \
	ui_tooltip = "光束中心的X坐标。坐标轴从屏幕左上角开始。"; \
> = 0; \
\
uniform float Spotlight_Center_Y < \
	ui_category = Spotlight_Category; \
	ui_label = "Y位置"; \
	ui_type = "slider"; \
	ui_min = -1.0; ui_max = 1.0; \
	ui_tooltip = "光束中心的Y坐标。坐标轴从屏幕左上角开始。"; \
> = 0; \
\
uniform float Spotlight_Brightness < \
	ui_category = Spotlight_Category; \
	ui_label = "亮度"; \
	ui_tooltip = \
		"聚光灯光晕亮度。\n" \
		"\n默认值: 10.0"; \
	ui_type = "slider"; \
	ui_min = 0.0; \
	ui_max = 100.0; \
	ui_step = 0.01; \
> = 10.0; \
\
uniform float Spotlight_Size < \
	ui_category = Spotlight_Category; \
	ui_label = "尺寸"; \
	ui_tooltip = \
		"聚光灯光晕尺寸（像素）。\n" \
		"\n默认值: 420.0"; \
	ui_type = "slider"; \
	ui_min = 10.0; \
	ui_max = 1000.0; \
	ui_step = 1.0; \
> = 420.0; \
\
uniform float3 Spotlight_Color < \
	ui_category = Spotlight_Category; \
	ui_label = "颜色"; \
	ui_tooltip = \
		"聚光灯光晕颜色。\n" \
		"\n默认值: R:255 G:230 B:200"; \
	ui_type = "color"; \
> = float3(255, 230, 200) / 255.0; \
\
uniform bool Spotlight_InvertDepthCutoff < \
	ui_category = Spotlight_Category; \
	ui_label = "反转深度截断"; \
> = 0; \
\
uniform float Spotlight_DepthCutoff < \
	ui_category = Spotlight_Category; \
	ui_label = "深度截断"; \
	ui_tooltip = \
		"聚光灯可见的距离。\n" \
		"仅在游戏有深度缓冲访问权限时有效。"; \
	ui_type = "slider"; \
	ui_min = 0.0; \
	ui_max = 1.0; \
> = 0.97; \
\
uniform float Spotlight_Distance < \
	ui_category = Spotlight_Category; \
	ui_label = "距离"; \
	ui_tooltip = \
		"聚光灯可以照亮的距离。\n" \
		"仅在游戏有深度缓冲访问权限时有效。\n" \
		"\n默认值: 0.1"; \
	ui_type = "slider"; \
	ui_min = 0.0; \
	ui_max = 1.0; \
	ui_step = 0.001; \
> = 0.1; \
\
uniform bool Spotlight_BlendFix < \
	ui_category = Spotlight_Category; \
	ui_label = "切换混合修复"; \
	ui_tooltip = "启用以使用原始混合模式。"; \
> = 0; \
\
uniform bool Spotlight_ToggleTexture < \
	ui_category = Spotlight_Category; \
	ui_label = "切换纹理"; \
	ui_tooltip = "启用或禁用聚光灯纹理。"; \
> = 1; \
\
uniform bool Spotlight_ToggleDepth < \
	ui_category = Spotlight_Category; \
	ui_label = "切换深度"; \
	ui_tooltip = "启用或禁用深度。"; \
> = 1; \
\
uniform bool Spotlight_ToggleDepthCutoff < \
	ui_category = Spotlight_Category; \
	ui_label = "切换深度截断"; \
	ui_tooltip = "启用或禁用深度截断。"; \
> = 0; \
\
\
float4 Spotlight_PS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET \
{ \
	const float depth = Spotlight_InvertDepthCutoff ? ReShade::GetLinearizedDepth(uv).r : 1 - ReShade::GetLinearizedDepth(uv).r; \
\
	if (!Spotlight_ToggleDepthCutoff || depth < Spotlight_DepthCutoff) \
	{ \
		const float2 res = BUFFER_SCREEN_SIZE; \
		const float2 coord = res * (uv - float2(Spotlight_Center_X, -Spotlight_Center_Y)); \
		const float halo = distance(coord, res * 0.5); \
		float spotlight = Spotlight_Size - min(halo, Spotlight_Size); \
		spotlight /= Spotlight_Size; \
\
		if (Spotlight_ToggleTexture == 0) \
		{ \
			float defects = sin(spotlight * 30.0) * 0.5 + 0.5; \
			defects = lerp(defects, 1.0, spotlight * 2.0); \
\
			static const float contrast = 0.125; \
\
			defects = 0.5 * (1.0 - contrast) + defects * contrast; \
			spotlight *= defects * 4.0; \
		} \
		else \
		{ \
			spotlight *= 2.0; \
		} \
\
		if (Spotlight_ToggleDepth == 1) \
		{ \
			const float sdepth = pow(max(1.0 - ReShade::GetLinearizedDepth(uv), 0.0), 1.0 / Spotlight_Distance); \
			spotlight *= sdepth; \
		} \
\
		float3 colored_spotlight = spotlight * Spotlight_Color; \
		colored_spotlight *= colored_spotlight * colored_spotlight; \
\
		const float3 result = 1.0 + colored_spotlight * Spotlight_Brightness; \
\
		float3 color = tex2D(sColor, uv).rgb; \
		color *= result; \
\
		if (!Spotlight_BlendFix) \
			color = max(color, (result - 1.0) * 0.001); \
\
		return float4(color, 1.0); \
	} \
	else \
	{ \
		discard; \
	} \
} \
\
technique Spotlight_Name { \
	pass { \
		VertexShader = PostProcessVS; \
		PixelShader = Spotlight_PS; \
		SRGBWriteEnable = true; \
	} \
} \
