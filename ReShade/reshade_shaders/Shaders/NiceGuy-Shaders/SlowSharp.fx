//SlowSharp
//Written by MJ_Ehsan for Reshade
//Version 1.0

//license
//CC0 ^_^

///////////////Include/////////////////////

#include "ReShadeUI.fxh"
#define pix float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

///////////////Include/////////////////////
///////////////Textures-Samplers///////////

texture TexColor : COLOR;
sampler sTexColor {Texture = TexColor; SRGBTexture = false;};

texture2D Ssharp_Tex1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSsharp_Tex1 {Texture = Ssharp_Tex1; };

texture2D Ssharp_Tex2 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSsharp_Tex2 {Texture = Ssharp_Tex2; };


///////////////Textures-Samplers///////////
///////////////UI//////////////////////////

uniform float threshold <
	ui_type = "slider";
	ui_label = "边缘避免阈值";
> = 0.1;

uniform float intensity <
	ui_type = "slider";
	ui_label = "强度";
> = 0.5;

uniform int size <
	ui_type = "slider";
	ui_label = "滤镜宽度";
	ui_tooltip = "较高: 更宽的滤镜但更慢";
	ui_min = 1;
	ui_max = 16;
> = 8;

uniform float bias <
	ui_type = "slider";
	ui_label = "偏移";
	ui_tooltip = "较高: 更宽的滤镜但更慢";
	ui_min = -0.5;
	ui_max =  0.5;
> = -0.5;

///////////////UI//////////////////////////
///////////////Functions///////////////////
///////////////Functions///////////////////
///////////////Vertex Shader///////////////

void VS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
{
	texcoord.x = (id == 2) ? 2.0 : 0.0;
	texcoord.y = (id == 1) ? 2.0 : 0.0;
	position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

///////////////Vertex Shader///////////////
///////////////Pixel Shader////////////////

float3 H(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 color = float4(tex2D(sTexColor, texcoord).rgb, 1);
 
	float4 s = 0;
	s.a = 1;
	float4 s1= 0;
	float2 p = pix;
	int width = size;

	for (int i = -width; i <= width; i++)
	{
		s.rgb = tex2D(sTexColor, texcoord + float2(i*p.x, 0)).rgb;
		float3 diff3 = abs(s.rgb - color.rgb);
		float  diff  = dot(0.333, diff3);
		if( diff < threshold + 0.0001){s1 += s;}
	}
	return s1.rgb/s1.a;
}

float3 V(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 color = float4(tex2D(sSsharp_Tex1, texcoord).rgb, 1);
 
	float4 s = 0;
	s.a = 1;
	float4 s1    = 0;
	float2 p     = pix;
	int    width = size;

	for (int i = -width; i <= width; i++)
	{
		s.rgb = tex2D(sSsharp_Tex1, texcoord + float2(0, i*p.y)).rgb;
		float3 diff3 = abs(s.rgb - color.rgb);
		float  diff  = dot(0.333, diff3);
		if( diff < threshold + 0.0001){s1 += s;}
	}
	return s1.rgb/s1.a;

}

float3 Sharp(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(sTexColor, texcoord).rgb;
	float3 blur  = tex2D(    sSsharp_Tex2, texcoord).rgb;
	float3 sharp = color + (color - blur);
	//return blur;
	return lerp( color, sharp, intensity); 
}


///////////////Pixel Shader////////////////
///////////////Techniques//////////////////

technique SlowSharp
< ui_label = "慢速锐化";
  ui_tooltip = "超宽锐化，几乎没有伪影"; >
{
	pass Horizontal
	{
		VertexShader = VS;
		PixelShader = H;
		RenderTarget = Ssharp_Tex1;
	}
	pass Vertical
	{
		VertexShader = VS;
		PixelShader = V;
		RenderTarget = Ssharp_Tex2;
	}
	pass Sharpening
	{
		VertexShader = VS;
		PixelShader = Sharp;
	}
}

///////////////Techniques//////////////////
