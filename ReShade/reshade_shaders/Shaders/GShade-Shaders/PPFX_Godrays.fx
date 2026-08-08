// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
// *** PPFX Godrays from the Post-Processing Suite 1.03.29 for ReShade
// *** SHADER AUTHOR: Pascal Matthäus ( Euda )
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++

//+++++++++++++++++++++++++++++
// DEV_NOTES
//+++++++++++++++++++++++++++++
// Updated for compatibility with ReShade 4 and isolated by Marot Satil.

#include "ReShade.fxh"

//+++++++++++++++++++++++++++++
// CUSTOM PARAMETERS
//+++++++++++++++++++++++++++++

// ** GODRAYS **
uniform int pGodraysSampleAmount <
    ui_label = "采样数量";
    ui_tooltip = "实际上是光线的分辨率。低值可能看起来粗糙但帧率更高。";
    ui_type = "slider";
    ui_min = 8;
    ui_max = 250;
    ui_step = 1;
> = 64;

uniform float2 pGodraysSource <
    ui_label = "光源位置";
    ui_tooltip = "屏幕空间中光线的消失点。0.500,0.500是屏幕中心。";
    ui_type = "slider";
    ui_min = -0.5;
    ui_max = 1.5;
    ui_step = 0.001;
> = float2(0.5, 0.4);

uniform float pGodraysExposure <
    ui_label = "曝光";
    ui_tooltip = "每个光斑对最终光线的曝光贡献。0.100通常就足够了。";
    ui_type = "slider";
    ui_min = 0.01;
    ui_max = 1.0;
    ui_step = 0.01;
> = 0.1;

uniform float pGodraysFreq <
    ui_label = "频率";
    ui_tooltip = "较高值会产生更密集的单独光线。'1.000'会导致光线始终覆盖整个屏幕。平衡衰减、采样和此值之间的关系。";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 10.0;
    ui_step = 0.001;
> = 1.2;

uniform float pGodraysThreshold <
    ui_label = "阈值";
    ui_tooltip = "暗于此值的像素不会投射光线。";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.001;
> = 0.65;

uniform float pGodraysFalloff <
    ui_label = "衰减";
    ui_tooltip = "使光线亮度随着与'光源位置'中指定的光源距离增加而淡出/衰减。";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 2.0;
    ui_step = 0.001;
> = 1.06;

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   TEXTURES   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

// *** ESSENTIALS ***
texture texColorGRA { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture texColorGRB < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture texGameDepth : DEPTH;

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   SAMPLERS   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

// *** ESSENTIALS ***

sampler SamplerColorGRA
{
	Texture = texColorGRA;
	AddressU = BORDER;
	AddressV = BORDER;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
};

sampler SamplerColorGRB
{
	Texture = texColorGRB;
	AddressU = BORDER;
	AddressV = BORDER;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
};

sampler2D SamplerDepth
{
	Texture = texGameDepth;
};

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   VARIABLES   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

static const float3 lumaCoeff = float3(0.2126f,0.7152f,0.0722f);
#define ZNEAR 0.3
#define ZFAR 50.0

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   STRUCTS   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

struct VS_OUTPUT_POST
{
	float4 vpos : SV_Position;
	float2 txcoord : TEXCOORD0;
};

struct VS_INPUT_POST
{
	uint id : SV_VertexID;
};

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   HELPERS   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

float linearDepth(float2 txCoords)
{
	return (2.0*ZNEAR)/(ZFAR+ZNEAR-tex2D(SamplerDepth,txCoords).x*(ZFAR-ZNEAR));
}

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   EFFECTS   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

// *** Godrays ***
	float4 FX_Godrays( float4 pxInput, float2 txCoords )
	{
		const float2	stepSize = (txCoords-pGodraysSource) / (pGodraysSampleAmount*pGodraysFreq);
		float3	rayMask = 0.0;
		float	rayWeight = 1.0;
		float	finalWhitePoint = pxInput.w;
		
		[loop]
		for (int i=1;i<(int)pGodraysSampleAmount;i++)
		{
			rayMask += saturate(saturate(tex2Dlod(SamplerColorGRB, float4(txCoords-stepSize*(float)i, 0.0, 0.0)).xyz) - pGodraysThreshold) * rayWeight * pGodraysExposure;
			finalWhitePoint += rayWeight * pGodraysExposure;
			rayWeight /= pGodraysFalloff;
		}
		
		rayMask.xyz = dot(rayMask.xyz,lumaCoeff.xyz) / (finalWhitePoint-pGodraysThreshold);
		return float4(pxInput.xyz+rayMask.xyz,finalWhitePoint);
	}

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   VERTEX-SHADERS   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

VS_OUTPUT_POST VS_PostProcess(VS_INPUT_POST IN)
{
	VS_OUTPUT_POST OUT;

	if (IN.id == 2)
		OUT.txcoord.x = 2.0;
	else
		OUT.txcoord.x = 0.0;

	if (IN.id == 1)
		OUT.txcoord.y = 2.0;
	else
		OUT.txcoord.y = 0.0;

	OUT.vpos = float4(OUT.txcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
	return OUT;
}

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   PIXEL-SHADERS   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

// *** Shader Structure ***

// *** Further FX ***
float4 PS_LightFX(VS_OUTPUT_POST IN) : COLOR
{
	const float2 pxCoord = IN.txcoord.xy;
	const float4 res = tex2D(ReShade::BackBuffer,pxCoord);
	
	return FX_Godrays(res,pxCoord.xy);
}

float4 PS_ColorFX(VS_OUTPUT_POST IN) : COLOR
{
	const float2 pxCoord = IN.txcoord.xy;
	const float4 res = tex2D(SamplerColorGRA,pxCoord);

	return float4(res.xyz,1.0);
}

float4 PS_ImageFX(VS_OUTPUT_POST IN) : COLOR
{
	const float2 pxCoord = IN.txcoord.xy;
	const float4 res = tex2D(SamplerColorGRB,pxCoord);

	return float4(res.xyz, 1.0);
}

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// +++++   TECHNIQUES   +++++
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

technique PPFX_Godrays < ui_label = "PPFX Godrays"; ui_tooltip = "Godrays | Lets bright areas cast rays on the screen."; >
{
	pass lightFX
	{
		VertexShader = VS_PostProcess;
		PixelShader = PS_LightFX;
		RenderTarget0 = texColorGRA;
	}
	
	pass colorFX
	{
		VertexShader = VS_PostProcess;
		PixelShader = PS_ColorFX;
		RenderTarget0 = texColorGRB;
	}
	
	pass imageFX
	{
		VertexShader = VS_PostProcess;
		PixelShader = PS_ImageFX;
	}
}