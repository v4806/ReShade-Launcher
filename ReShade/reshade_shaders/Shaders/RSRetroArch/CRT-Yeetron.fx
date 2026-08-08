/*
	Ported from RSDKV5U Decompile project
	CRT-Sharp from Sonic Mania
*/

#include "ReShade.fxh"

uniform float pixel_sizeX <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = BUFFER_WIDTH;
	ui_label = "内部宽度 [CRT-Yee64]";
> = 320.0;

uniform float pixel_sizeY <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = BUFFER_HEIGHT;
	ui_label = "内部高度 [CRT-Yee64]";
> = 240.0;

#define pixel_size float2(pixel_sizeX, pixel_sizeY)

uniform float texture_sizeX <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = BUFFER_WIDTH;
	ui_label = "屏幕宽度 [CRT-Yee64]";
> = 320.0;

uniform float texture_sizeY <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = BUFFER_HEIGHT;
	ui_label = "屏幕高度 [CRT-Yee64]";
> = 240.0;

#define texture_size float2(texture_sizeX, texture_sizeY)

#define RSDK_PI 3.14159

uniform int viewSizeHD <
	ui_type = "drag";
	ui_min = 1;
	ui_max = BUFFER_HEIGHT;
	ui_step = 1;
	ui_label = "高清视图尺寸 [CRT-Yee64]";
	ui_tooltip = "分辨率缩放高度达到此值后将模拟变暗效果"; 
> = 720;

uniform float3 intencity <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
	ui_label = "变暗强度 [CRT-Yee64]";
	ui_tooltip = "模拟CRT效果时屏幕变暗的程度。";
> = float3(1.2, 0.9, 0.9);

float4 PS_CRTYeetron(float4 pos : SV_Position, float2 coords : TEXCOORD0) : SV_Target
{
    float2 viewPos      = floor((texture_size.xy / pixel_size.xy) * coords.xy * ReShade::ScreenSize.xy) + 0.5;
    float intencityPos  = frac((viewPos.y * 3.0 + viewPos.x) * 0.166667);

    float4 scanlineIntencity;
    if (intencityPos < 0.333)
        scanlineIntencity.rgb = intencity.xyz;
    else if (intencityPos < 0.666)
        scanlineIntencity.rgb = intencity.zxy;
    else
        scanlineIntencity.rgb = intencity.yzx;

    float2 pixelPos         = coords.xy * texture_size.xy;
    float2 roundedPixelPos  = floor(pixelPos.xy);

    scanlineIntencity.a = clamp(abs(sin(pixelPos.y * RSDK_PI)) + 0.25, 0.5, 1.0);
    pixelPos.xy         = frac(pixelPos.xy) + -0.5;

    float2 invTexPos = -coords.xy * texture_size.xy + (roundedPixelPos + 0.5);
    
    float2 newTexPos;
    newTexPos.x = clamp(-abs(invTexPos.x * 0.5) + 1.5, 0.8, 1.25);
    newTexPos.y = clamp(-abs(invTexPos.y * 2.0) + 1.25, 0.5, 1.0);

    float2 colorMod;
    colorMod.x = newTexPos.x * newTexPos.y;
    colorMod.y = newTexPos.x * ((scanlineIntencity.a + newTexPos.y) * 0.5);

    scanlineIntencity.a *= newTexPos.x;

    float2 texPos   = ((pixelPos.xy + -clamp(pixelPos.xy, -0.25, 0.25)) * 2.0 + roundedPixelPos + 0.5) / texture_size.xy;
    float4 texColor = tex2D(ReShade::BackBuffer, texPos.xy);

    float3 blendedColor;
    blendedColor.r  = scanlineIntencity.a * texColor.r;
    blendedColor.gb = colorMod.xy * texColor.gb;

    float4 outColor;
    outColor.rgb    = ReShade::ScreenSize.y >= viewSizeHD ? (scanlineIntencity.rgb * blendedColor.rgb) : blendedColor.rgb;
    outColor.a      = texColor.a;
	
	return outColor;
}

technique CRTYeetron
{
	pass CRTYeetron
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_CRTYeetron;
	}
}
