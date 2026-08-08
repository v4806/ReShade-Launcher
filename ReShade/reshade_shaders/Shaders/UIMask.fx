/*
	Simple UIMask shader by luluco250

	I have no idea why this was never ported back to ReShade 3.0 from 2.0,
	but if you missed it, here it is.

	It doesn't feature the auto mask from the original shader.

	It does feature a new multi-channnel masking feature. UI masks can now contain
	separate 'modes' within each of the three color channels.

	For example, you can have the regular hud on the red channel (the default one),
	a mask for an inventory screen on the green channel and a mask for a quest menu
	on the blue channel. You can then use keyboard keys to toggle each channel on or off.

	Multiple channels can be active at once, they'll just add up to mask the image.

	Simple/legacy masks are not affected by this, they'll work just as you'd expect,
	so you can still make simple black and white masks that use all color channels, it'll
	be no different than just having it on a single channel.

	Tips:

	--You can adjust how much it will affect your HUD by changing "Mask Intensity".

	--You don't actually need to place the UIMask_Bottom technique at the bottom of
	  your shader pipeline, if you have any effects that don't necessarily affect
	  the visibility of the HUD you can place it before that.
	  For instance, if you use color correction shaders like LUT, you might want
	  to place UIMask_Bottom just before that.

	--Preprocessor flags:
	  --UIMASK_MULTICHANNEL:
		Enables having up to three different masks on each color channel.

	--Refer to this page for keycodes:
	  https://msdn.microsoft.com/en-us/library/windows/desktop/dd375731(v=vs.85).aspx

	--To make a custom mask:

	  1-Take a screenshot of your game with the HUD enabled,
	   preferrably with any effects disabled for maximum visibility.

	  2-Open the screenshot with your preferred image editor program, I use GIMP.

	  3-Make a background white layer if there isn't one already.
		Be sure to leave it behind your actual screenshot for the while.

	  4-Make an empty layer for the mask itself, you can call it "mask".

	  5-Having selected the mask layer, paint the places where HUD constantly is,
		such as health bars, important messages, minimaps etc.

	  6-Delete or make your screenshot layer invisible.

	  7-Before saving your mask, let's do some gaussian blurring to improve it's look and feel:
		For every step of blurring you want to do, make a new layer, such as:
		Mask - Blur16x16
		Mask - Blur8x8
		Mask - Blur4x4
		Mask - Blur2x2
		Mask - NoBlur
		You should use your image editor's default gaussian blurring filter, if there is one.
		This avoids possible artifacts and makes the mask blend more easily on the eyes.
		You may not need this if your mask is accurate enough and/or the HUD is simple enough.

	  8-Now save the final image with a unique name such as "MyUIMask.png" in your textures folder.

	  9-Set the preprocessor definition UIMASK_TEXTURE to the unique name of your image, with quotes.
	    You're done!


	MIT Licensed:

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

//#region Preprocessor

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

#ifndef UIMASK_MULTICHANNEL
	#define UIMASK_MULTICHANNEL 0
#endif

#if !UIMASK_MULTICHANNEL
	#define TEXFORMAT R8
#else
	#define TEXFORMAT RGBA8
#endif

#ifndef UIMASK_TEXTURE
	#define UIMASK_TEXTURE "UIMask.png"
#endif

//#endregion

namespace UIMask
{

//#region Uniforms

uniform int _Help
<
	ui_label = " ";
	ui_text =
		"有关更详细的说明，请参阅此效果着色器文件(UIMask.fx)顶部的文本。\n"
		"\n"
		"可用的预处理器定义：\n"
		"  UIMASK_MULTICHANNEL:\n"
		"    如果设置为1，纹理中的每个RGB颜色通道将被视为单独的遮罩。\n"
		"\n"
		"如何创建遮罩：\n"
		"\n"
		"1. 截取游戏UI显示时的截图。\n"
		"2. 在图像编辑器中打开截图，推荐使用GIMP或Photoshop。\n"
		"3. 在截图图层上创建新图层，用黑色填充。\n"
		"4. 降低图层不透明度以便看到下面的截图图层。\n"
		"5. 用白色覆盖UI以将其从效果中遮罩。遮罩白色越强，遮罩越不透明。\n"
		"6. 将遮罩图层不透明度恢复到100%。\n"
		"7. 将图像保存到您的纹理文件夹之一，确保使用唯一名称，如：\"MyUIMask.png\"\n"
		"8. 将预处理器定义UIMASK_TEXTURE设置为您图像的名称，带引号：\"MyUIMask.png\"\n"
		;
	ui_category = "帮助";
	ui_category_closed = true;
	ui_type = "radio";
>;

uniform float fMask_Intensity
<
	__UNIFORM_SLIDER_FLOAT1

	ui_label = "遮罩强度";
	ui_tooltip =
		"效果对原始图像遮罩的程度。\n"
		"\n默认值: 1.0";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
> = 1.0;

uniform bool bDisplayMask <
	ui_label = "显示遮罩";
	ui_tooltip =
		"显示遮罩纹理。\n"
		"用于测试多通道或遮罩本身。\n"
		"\n默认值: 关闭";
> = false;

#if UIMASK_MULTICHANNEL

uniform bool bToggleRed <
	ui_label = "切换红色通道";
	ui_tooltip = "切换红色通道的UI遮罩。\n"
		     "右键点击分配快捷键。\n"
		     "\n默认值: 开启";
> = true;

uniform bool bToggleGreen <
	ui_label = "切换绿色通道";
	ui_tooltip = "切换绿色通道的UI遮罩。\n"
		     "右键点击分配快捷键。"
		     "\n默认值: 开启";
> = true;

uniform bool bToggleBlue <
	ui_label = "切换蓝色通道";
	ui_tooltip = "切换蓝色通道的UI遮罩。\n"
		     "右键点击分配快捷键。"
		     "\n默认值: 开启";
> = true;

#endif

//#endregion

//#region Textures

texture BackupTex
{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
};
sampler Backup
{
	Texture = BackupTex;
};

texture MaskTex <source=UIMASK_TEXTURE;>
{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = TEXFORMAT;
};
sampler Mask
{
	Texture = MaskTex;
};

//#endregion

//#region Shaders

float4 BackupPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return tex2D(ReShade::BackBuffer, uv);
}

float4 MainPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	float4 color = tex2D(ReShade::BackBuffer, uv);
	float4 backup = tex2D(Backup, uv);

	#if !UIMASK_MULTICHANNEL
		float mask = tex2D(Mask, uv).r;
	#else
		float3 mask_rgb = tex2D(Mask, uv).rgb;

		// This just works, it basically adds masking with each channel that has
		// been toggled.
		float mask = saturate(
			1.0 - dot(1.0 - mask_rgb,
				float3(bToggleRed, bToggleGreen, bToggleBlue)));
	#endif

	color = lerp(color, backup, mask * fMask_Intensity);
	color = bDisplayMask ? mask : color;

	return color;
}

//#endregion

//#region Techniques

technique UIMask_Top
<
	ui_tooltip = "将此放置在要被遮罩的效果*上方*。";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = BackupPS;
		RenderTarget = BackupTex;
	}
}

technique UIMask_Bottom
<
	ui_tooltip =
		"将此放置在要被遮罩的效果*下方*。\n"
		"如果要为效果添加切换键，请将其设置在这里。";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = MainPS;
	}
}

//#endregion

} // Namespace.
