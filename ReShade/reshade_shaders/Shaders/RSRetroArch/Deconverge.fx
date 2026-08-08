#include "ReShade.fxh"

uniform float3 ConvergeX <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
	ui_label = "水平会聚 [Converge]";
	ui_tooltip = "X轴会聚";
> = float3(0.0, 0.0, 0.0);

uniform float3 ConvergeY <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
	ui_label = "垂直会聚 [Converge]";
	ui_tooltip = "Y轴会聚";
> = float3(0.0, 0.0, 0.0);

uniform float3 RadialConvergeX <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
	ui_label = "径向水平会聚 [Converge]";
	ui_tooltip = "X轴径向会聚";
> = float3(0.0, 0.0, 0.0);

uniform float3 RadialConvergeY <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
	ui_label = "径向垂直会聚 [Converge]";
	ui_tooltip = "Y轴径向会聚";
> = float3(0.0, 0.0, 0.0);


//DEV NOTE: Even if they have those options, best to leave them to same or the best looking, since ReShade can't go that deep on injection
uniform float2 ScreenDims <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = 100000.0;
	ui_step = 1.0;
	ui_label = "屏幕尺寸 [Converge]";
	ui_tooltip = "应设置为显示器分辨率";
> = float2(320.0,240.0);

uniform float2 TargetDims <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = 100000.0;
	ui_step = 1.0;
	ui_label = "目标尺寸 [Converge]";
	ui_tooltip = "应设置为目标或游戏分辨率";
> = float2(320.0,240.0);


float4 PS_Deconverge(float4 vpos : SV_Position, float2 texcoord : TEXCOORD0) : SV_Target0
{
	vpos.xy /= ReShade::ScreenSize.xy;
	vpos.y = 1.0f - texcoord.y; // flip y
	vpos.xy -= 0.5f; // center
	vpos.xy *= 2.0f; // zoom

	texcoord += 0.5f / TargetDims; // half texel offset correction (DX9)

	// imaginary texel dimensions independed from screen dimension, but ratio
	float2 TexelDims = (1.0f / 1024);

	// center coordinates
	texcoord.x -= 0.5f;
	texcoord.y -= 0.5f;

	// radial converge offset to "translate" the most outer pixel as thay would be translated by the linar converge with the same amount
	float2 radialConvergeOffset = 2.0f;

	// radial converge
	texcoord.x *= 1.0f + RadialConvergeX * TexelDims.x * radialConvergeOffset.x;
	texcoord.y *= 1.0f + RadialConvergeY * TexelDims.y * radialConvergeOffset.y;

	// un-center coordinates
	texcoord.x += 0.5f;
	texcoord.y += 0.5f;

	// linear converge
	texcoord.x += ConvergeX * TexelDims.x;
	texcoord.y += ConvergeY * TexelDims.y;

	float3 col = tex2D(ReShade::BackBuffer,texcoord).rgb;

	return float4(col,1.0);
}

technique Deconverge_MAME
{
	pass DeconvergeMAME
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Deconverge;
	}
}