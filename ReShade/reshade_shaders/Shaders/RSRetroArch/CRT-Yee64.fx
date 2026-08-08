/*
	Ported from RSDKV5U Decompile project
	CRT-Soft from Sonic Mania
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

uniform float brightness <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_step = 0.001;
	ui_label = "遮罩亮度 [CRT-Yee64]";
	ui_tooltip = "遮罩的亮度倍增。";
> = 1.25;

float4 PS_CRTYee64(float4 pos : SV_Position, float2 coords : TEXCOORD0) : SV_Target
{
    float2 texelPos = (texture_size.xy / pixel_size.xy) * coords.xy;
    float4 size     = (pixel_size.xy / texture_size.xy).xyxy * texelPos.xyxy;
    float2 exp      = size.zw * texture_size.xy + -floor(size.zw * texture_size.xy) + -0.5;

    float4 factor  = pow(2, pow(-exp.x + float4(-1, 1, -2, 2), 2) * -3);
    float  factor2 = pow(2, pow(exp.x, 2) * -3); // used for the same stuff as 'factor', just doesn't fit in a float4 :)

    float3 power;
    power.x = pow(2, pow(exp.y, 2) * -8);
    power.y = pow(2, pow(-exp.y + -1, 2) * -8);
    power.z = pow(2, pow(-exp.y + 1, 2) * -8);

    float2 viewPos      = floor(texelPos.xy * ReShade::ScreenSize.xy) + 0.5;
    float intencityPos  = frac((viewPos.y * 3.0 + viewPos.x) * 0.166667);

    float4 scanlineIntencity;
    if (intencityPos < 0.333)
        scanlineIntencity.rgb = intencity.xyz;
    else if (intencityPos < 0.666)
        scanlineIntencity.rgb = intencity.zxy;
    else
        scanlineIntencity.rgb = intencity.yzx;

    float3 color1  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + float2( 1, -1))   + 0.5)      / texture_size.xy).rgb * factor.y * brightness;
    float3 color2  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + float2(-2,  0))   + 0.5)      / texture_size.xy).rgb * factor.z * brightness;
    float3 color3  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + float2(-1,  0))   + 0.5)      / texture_size.xy).rgb * factor.x * brightness;
    float3 color4  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + float2( 1,  0))   + 0.5)      / texture_size.xy).rgb * factor.y * brightness;
    float3 color5  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + 0)                + 0.5)      / texture_size.xy).rgb * factor2  * brightness;
    float3 color6  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + float2(-1,  1))   + 0.5)      / texture_size.xy).rgb * factor.x * brightness;
    float3 color7  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + float2( 2,  0))   + 0.5)      / texture_size.xy).rgb * factor.w * brightness;
    float3 color8  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + -1)               + 0.5)      / texture_size.xy).rgb * factor.x * brightness;
    float3 color9  = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + float2( 0, -1))   + 0.5)      / texture_size.xy).rgb * factor2  * brightness;
    float3 color10 = tex2D(ReShade::BackBuffer, (floor(size.zw * texture_size.xy   + 1)                + 0.5)      / texture_size.xy).rgb * factor.y * brightness;
    float3 color11 = tex2D(ReShade::BackBuffer, (floor(size.xy * texture_size.xy   + float2( 0,  1))   + 0.5)      / texture_size.xy).rgb * factor2  * brightness;

    float3 final = 
        power.x * (color2 + color3 + color4 + color5 + color7) / (factor.z + factor.x + factor.y + factor2 + factor.w) +
        power.y * (color1 + color8 + color9)                   / (factor.y + factor.x + factor2)                 +
        power.z * (color10 + color6 + color11)                 / (factor.y + factor.x + factor2);

	float4 outColor;
    outColor.rgb = viewSizeHD < ReShade::ScreenSize.y ? (scanlineIntencity.rgb * final.rgb) : final.rgb;
    outColor.a = 1.0;
	
	return outColor;
}

technique CRTYee64
{
	pass CRTYee64
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_CRTYee64;
	}
}
