/*------------------.
| :: Description :: |
'-------------------/

Display LUT PS (version 1.3.4)
Apply LUT PS (version 2.0.2)

Copyright:
Display LUT © 2018-2023 Jakub Maksymilian Fober

Apply LUT © 2018-2023 Jakub Maksymilian Fober
(remix of version 1.0 LUT shader © 2016 Marty McFly)

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

/*-------------.
| :: Macros :: |
'-------------*/

// Define LUT texture size
#ifndef LUT_BLOCK_SIZE
	#define LUT_BLOCK_SIZE 32
#endif
// Define LUT texture name
#ifndef LUT_FILE_NAME
	#define LUT_FILE_NAME "lut.png"
#endif
// Define LUT orientation
#ifndef LUT_VERTICAL
	#define LUT_VERTICAL 0
#endif

// Global macros
#if LUT_VERTICAL
	#define LUT_DIMENSIONS int2(LUT_BLOCK_SIZE, LUT_BLOCK_SIZE*LUT_BLOCK_SIZE)
#else
	#define LUT_DIMENSIONS int2(LUT_BLOCK_SIZE*LUT_BLOCK_SIZE, LUT_BLOCK_SIZE)
#endif
#define LUT_PIXEL_SIZE 1f/LUT_DIMENSIONS

/*-----------.
| :: Menu :: |
'-----------*/

uniform int LutRes
<
	ui_label = "LUT方块分辨率";
	ui_tooltip =
		"水平分辨率等于值的平方。\n"
		"默认32是1024。\n"
		"要设置ApplyLUT的纹理大小和名称，定义\n"
		" LUT_BLOCK_SIZE [数字]\n"
		"和\n"
		" LUT_FILE_NAME [名称]";
	ui_type = "drag";
	ui_category = "显示LUT设置";
	ui_min = 8; ui_max = 128; ui_step = 1;
> = 32;

uniform bool VerticalOrietation
<	__UNIFORM_INPUT_BOOL1
	ui_label = "垂直LUT";
	ui_tooltip =
		"选择LUT纹理方向，默认为水平。\n"
		"要更改输入LUT的方向，添加预处理器定义'LUT_VERTICAL true'。";
	ui_category = "显示LUT设置";
> = false;

uniform float2 LutChromaLuma
<	__UNIFORM_SLIDER_FLOAT2
	ui_label = "LUT色度/亮度混合";
	ui_tooltip = "LUT影响色度/亮度的程度";
	ui_category = "应用LUT设置";
	ui_min = 0f; ui_max = 1f; ui_step = 0.005;
> = float2(1f, 1f);

/*----------------.
| :: Functions :: |
'----------------*/

// Convert 3D LUT texel coordinates to 2D texel coordinates
int2 toLut2D(int3 lut3D)
{
	#if LUT_VERTICAL
		return int2(lut3D.x, lut3D.y+lut3D.z);
	#else
		return int2(lut3D.x+lut3D.z, lut3D.y);
	#endif
}

/*---------------.
| :: Textures :: |
'---------------*/

// LUT texture for Apply Lut PS
texture LUTTex < source = LUT_FILE_NAME;>
{
	Width  = LUT_DIMENSIONS.x;
	Height = LUT_DIMENSIONS.y;
	Format = RGBA8;
};
sampler LUTSampler
{ Texture = LUTTex; };

/*--------------.
| :: Shaders :: |
'--------------*/

// Shader No.1 pass
float3 DisplayLutPS(
	float4 vois : SV_Position,
	float2 TexCoord : TEXCOORD
) : SV_Target
{
	// Calculate LUT texture bounds
	float2 LutBounds;
	if (VerticalOrietation)
		LutBounds = float2(LutRes, LutRes*LutRes);
	else
		LutBounds = float2(LutRes*LutRes, LutRes);
	LutBounds *= BUFFER_PIXEL_SIZE;

	if( any(TexCoord>=LutBounds) ) return tex2D(ReShade::BackBuffer, TexCoord).rgb;
	else
	{
		// Generate pattern UV
		float2 Gradient = TexCoord*BUFFER_SCREEN_SIZE/LutRes;
		// Convert pattern to RGB LUT
		float3 LUT;
		LUT.rg = frac(Gradient)-0.5/LutRes;
		LUT.rg /= 1f-1f/LutRes;
		LUT.b = floor(VerticalOrietation? Gradient.g : Gradient.r)/(LutRes-1);
		// Display LUT texture
		return LUT;
	}
}

// Shader No.2 pass
void ApplyLutPS(
	float4 vois : SV_Position,
	float2 TexCoord : TEXCOORD,
	out float3 Image : SV_Target
)
{
	// Grab background color
	Image = tex2D(ReShade::BackBuffer, TexCoord).rgb;

	// Convert to sub pixel coordinates
	float3 lut3D = Image*(LUT_BLOCK_SIZE-1);

	// Get 2D LUT coordinates
	float2 lut2D[2];
	#if LUT_VERTICAL
		// Front
		lut2D[0].x = lut3D.x;
		lut2D[0].y = floor(lut3D.z)*LUT_BLOCK_SIZE+lut3D.y;
		// Back
		lut2D[1].x = lut3D.x;
		lut2D[1].y = ceil(lut3D.z)*LUT_BLOCK_SIZE+lut3D.y;
	#else
		// Front
		lut2D[0].x = floor(lut3D.z)*LUT_BLOCK_SIZE+lut3D.x;
		lut2D[0].y = lut3D.y;
		// Back
		lut2D[1].x = ceil(lut3D.z)*LUT_BLOCK_SIZE+lut3D.x;
		lut2D[1].y = lut3D.y;
	#endif

	// Convert from texel to texture coords
	lut2D[0] = (lut2D[0]+0.5)*LUT_PIXEL_SIZE;
	lut2D[1] = (lut2D[1]+0.5)*LUT_PIXEL_SIZE;

	// Bicubic LUT interpolation
	float3 LutImage = lerp(
		tex2D(LUTSampler, lut2D[0]).rgb, // Front Z
		tex2D(LUTSampler, lut2D[1]).rgb, // Back Z
		frac(lut3D.z)
	);

	// Blend LUT image with original
	if ( all(LutChromaLuma==1f) )
		Image = LutImage;
	else
	{
		Image = lerp(
			normalize(Image),
			normalize(LutImage),
			LutChromaLuma.x
		)*lerp(
			length(Image),
			length(LutImage),
			LutChromaLuma.y
		);
	}
}

/*-------------.
| :: Output :: |
'-------------*/

technique DisplayLUT
<
	ui_label = "显示 LUT";
	ui_tooltip =
		"在屏幕左角显示生成的中性 LUT 纹理\n"
		"\n"
		"使用方法：\n"
		"* 调整 LUT 大小\n"
		"* （可选）调整颜色效果以将着色器烘焙到 LUT 中\n"
		"* 截图\n"
		"* 使用外部图像编辑器调整并裁剪截图为纹理\n"
		"* 在'Apply LUT .fx'中加载 LUT 纹理"
		"\n"
		"此效果 © 2018-2023 Jakub Maksymilian Fober\n"
		"基于 CC BY-SA 4.0 许可";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = DisplayLutPS;
	}
}

technique ApplyLUT
<
	ui_label = "应用 LUT";
	ui_tooltip =
		"应用 LUT 纹理颜色调整\n"
		"要更改纹理名称，在全局预处理器定义中添加：\n"
		"\n"
		"   LUT_FILE_NAME 'YourLUT.png'\n"
		"\n"
		"要更改 LUT 纹理分辨率，定义：\n"
		"\n"
		"   LUT_BLOCK_SIZE 17\n"
		"\n"
		"要更改 LUT 纹理方向，定义：\n"
		"\n"
		"   LUT_VERTICAL true\n"
		"\n"
		"此效果 © 2018-2023 Jakub Maksymilian Fober\n"
		"基于 CC BY-SA 4.0 许可";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = ApplyLutPS;
	}
}
