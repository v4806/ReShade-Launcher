////----------//
///**Trails**///
//----------////

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//* Trails
//* For Reshade 3.0
//* --------------------------
//* This work is licensed under a Creative Commons Attribution 3.0 Unported License.
//* So you are free to share, modify and adapt it for your needs, and even use it for commercial use.
//* I would also love to hear about a project you are using it with.
//* https://creativecommons.org/licenses/by/3.0/us/
//*
//* Have fun,
//* Jose Negrete AKA BlueSkyDefender
//*
//* https://github.com/BlueSkyDefender/Depth3D
//* ---------------------------------
//*
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define Per_Color_Channel 0 // Lets you adjust per Color Channel.Default 0 off
#define Add_Depth_Effects 0 // Lets this effect be affected by Depth..Default 0 off

#if !Per_Color_Channel
uniform float Persistence <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.00;
	ui_label = "持久性";
	ui_tooltip = "增加持久性使拖尾或残影更长。\n"
				"如果调高，效果类似长曝光。\n"
				"可用于游戏中的光绘效果。\n"
				"1000/1 是 1.0，1/2 是 0.5，以此类推。\n"
				"默认值为0.25，0表示无限。";
> = 0.25;
#else
uniform float3 Persistence <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.00;
	ui_label = "持久性";
	ui_tooltip = "增加持久性使拖尾或残影更长（RGB通道）。\n"
				"如果调高，效果类似长曝光。\n"
				"可用于游戏中的光绘效果。\n"
				"1000/1 是 1.0，1/2 是 0.5，以此类推。\n"
				"默认值为0.25，0表示无限。";
> = float3(0.25,0.25,0.25);
#endif

uniform float TQ <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "拖尾模糊质量";
	ui_tooltip = "调整拖尾模糊质量。\n"
				"默认值为零。";
> = 0.0;

//uniform bool TrailsX2 <
//	ui_label = "Trails X2";
//	ui_tooltip = "Two times the samples.\n"
//				 "This disables Trail Quality.";
//> = false;

uniform bool PS2 <
	ui_label = "PS2风格回声";
	ui_tooltip = "在游戏中启用PS2风格回声效果。\n"
				 "这将禁用拖尾质量选项。";
> = false;
#if Add_Depth_Effects
uniform bool Allow_Depth <
	ui_label = "深度图开关";
	ui_tooltip = "允许在拖尾效果中使用深度。";
	ui_category = "深度缓冲";
> = 0;

uniform int Depth_Map <
	ui_type = "combo";
	ui_items = "正常\0反转\0";
	ui_label = "自定义深度图";
	ui_tooltip = "选择你的深度图。";
	ui_category = "深度缓冲";
> = 0;

uniform float Depth_Map_Adjust <
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "深度图调整";
	ui_tooltip = "调整深度图和锐化距离。";
	ui_category = "深度缓冲";
> = 0.0;

uniform bool Hard_CutOff <
	ui_label = "硬截止";
	ui_tooltip = "深度截止开关，提供深度隔离的硬截止。";
	ui_category = "深度缓冲";
> = 0;

uniform bool Depth_Map_Flip <
	ui_label = "深度图翻转";
	ui_tooltip = "如果深度图上下颠倒，请翻转。";
	ui_category = "深度缓冲";
> = 0;

uniform bool Invert_Depth <
	ui_label = "深度图反转";
	ui_tooltip = "反转深度，让你只针对武器或近处物体。";
	ui_category = "深度缓冲";
> = 0;

uniform bool Depth_View <
	ui_label = "深度图查看";
	ui_tooltip = "让你查看深度以便调试。";
	ui_category = "深度缓冲";
> = 0;
#else
static const int Allow_Depth = 0;
static const int Depth_Map = 0;
static const float Depth_Map_Adjust = 250.0;
static const int Depth_Map_Flip = 0;
static const int Invert_Depth = 0;
static const int Depth_View = 0;
static const int Hard_CutOff = 0;
#endif
/////////////////////////////////////////////D3D Starts Here/////////////////////////////////////////////////////////////////
texture DepthBufferTex : DEPTH;

sampler DepthBuffer
	{
		Texture = DepthBufferTex;
	};

texture BackBufferTex : COLOR;

sampler BackBuffer
	{
		Texture = BackBufferTex;
	};

texture CurrentBackBufferT  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;};

sampler CBackBuffer
	{
		Texture = CurrentBackBufferT;
	};


texture PBB  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 2;};

sampler PBackBuffer
	{
		Texture = PBB;
	};
	
texture PSBB  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;};

sampler PSBackBuffer
	{
		Texture = PSBB;
	};

///////////////////////////////////////////////////////////TAA/////////////////////////////////////////////////////////////////////
#define pix float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
float Depth(in float2 texcoord : TEXCOORD0)
{
	if (Depth_Map_Flip)
		texcoord.y =  1 - texcoord.y;

	float zBuffer = tex2D(DepthBuffer, texcoord).x; //Depth Buffer

	//Conversions to linear space.....
	//Near & Far Adjustment
	float Far = 1.0, Near = 0.125/250.0; //Division Depth Map Adjust - Near

	float2 Z = float2( zBuffer, 1-zBuffer );

	if (Depth_Map == 0)//DM0. Normal
		zBuffer = Far * Near / (Far + Z.x * (Near - Far));
	else if (Depth_Map == 1)//DM1. Reverse
		zBuffer = Far * Near / (Far + Z.y * (Near - Far));

	return saturate(zBuffer);
}

float3 T_Out(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
	float TQA = TQ, D = Depth(texcoord);
	if(PS2)
		TQA = 0;
		
    float3 C = tex2D(BackBuffer, texcoord).rgb;
	//float3 PS = tex2D(PSBackBuffer, texcoord).rgb;

    float3 P = tex2Dlod(PBackBuffer, float4(texcoord,0,TQA)).rgb;
	
    #if !PerColor
      float Per = 1-Persistence;
    #else
      float3 Per = 1-Persistence;
    #endif

	D = smoothstep(0,Depth_Map_Adjust,D);
	
	if(Hard_CutOff)
		D = step(0.5,D);

	if(Invert_Depth)
	D = 1-D;

    if(!PS2)
    {
		P *= Per;
		C = max( tex2D(BackBuffer, texcoord).rgb, P);
		//PS = max( tex2D(BackBuffer, texcoord).rgb, P);
    }
    else
    {
		C = (1-Per) * C + Per * P;
		//PS = (1-Per) * PS + Per * P;
	}
	
	//if(TrailsX2)
	//{
	//	C = lerp(PS,C,0.5);
	//}
	
	if(Allow_Depth)
		C = lerp(C,tex2D(BackBuffer, texcoord).rgb,saturate(D));

	if(Depth_View)
		C = D;

  return C;
}

void Current_BackBuffer_T(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 color : SV_Target0)
{
	color = tex2D(BackBuffer,texcoord);
}

void Past_BB(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 Past : SV_Target0, out float4 PastSingle : SV_Target1)
{   float2 samples[12] = {
	float2(-0.326212, -0.405805),
	float2(-0.840144, -0.073580),
	float2(-0.695914, 0.457137),
	float2(-0.203345, 0.620716),
	float2(0.962340, -0.194983),
	float2(0.473434, -0.480026),
	float2(0.519456, 0.767022),
	float2(0.185461, -0.893124),
	float2(0.507431, 0.064425),
	float2(0.896420, 0.412458),
	float2(-0.321940, -0.932615),
	float2(-0.791559, -0.597705)
	};

	float4 sum_A = tex2D(BackBuffer,texcoord), sum_B = 0;//tex2D(CBackBuffer,texcoord);

	if(!PS2)
	{
			float Adjust = TQ*pix.x;
			[loop]
			for (int i = 0; i < 12; i++)
			{
				sum_A += tex2Dlod(BackBuffer, float4(texcoord + Adjust * samples[i],0,0));
				//sum_B += tex2Dlod(CBackBuffer, float4(texcoord + Adjust * samples[i],0,0));
			}
		Past = sum_A * 0.07692307;
		PastSingle = 0;//sum_B * 0.07692307;
	}
	else
	{
		Past = sum_A;
		PastSingle = 0;//sum_B * 0.07692307;
	}
}

///////////////////////////////////////////////////////////ReShade.fxh/////////////////////////////////////////////////////////////
// Vertex shader generating a triangle covering the entire screen
void PostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
{
	texcoord.x = (id == 2) ? 2.0 : 0.0;
	texcoord.y = (id == 1) ? 2.0 : 0.0;
	position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}
technique Trails
	{
			pass CBB
		{
			VertexShader = PostProcessVS;
			PixelShader = Current_BackBuffer_T;
			RenderTarget = CurrentBackBufferT;
		}
			pass Trails
		{
			VertexShader = PostProcessVS;
			PixelShader = T_Out;
		}
			pass PBB
		{
			VertexShader = PostProcessVS;
			PixelShader = Past_BB;
			RenderTarget0 = PBB;
			RenderTarget1 = PSBB;

		}
	}
