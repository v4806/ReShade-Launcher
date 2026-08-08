#define NGL_HYBRID_MODE 0
#include "NGLighting-Shader.fxh"

technique NGLighting<
	ui_label = "NiceGuy 光照 (GI/反射)";
	ui_tooltip = "||           NiceGuy 光照 ||版本 1.0.0              ||\n"
				 "||                       作者: NiceGuy                        ||\n"
				 "||一个免费轻量的 ReShade 光线追踪 GI 着色器||\n"
				 "重要提示：修改着色器前请先阅读提示！";
>
{
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = GBuffer1;
		RenderTarget0 = SSSR_NormTex;
		RenderTarget1 = SSSR_RoughTex;
	}
#if SMOOTH_NORMALS > 0
	pass SmoothNormalHpass
	{
		VertexShader = PostProcessVS;
		PixelShader = SNH;
		RenderTarget = SSSR_NormTex1;
	}
	pass SmoothNormalVpass
	{
		VertexShader = PostProcessVS;
		PixelShader = SNV;
		RenderTarget = SSSR_NormTex;
	}
#endif //SMOOTH_NORMALS
#if __RENDERER__ >= 0xa000 // If DX10 or higher
	pass LowResGBuffer
	{
		VertexShader = PostProcessVS;
		PixelShader = CopyGBufferLowRes;
		RenderTarget0 = SSSR_LowResNormTex;
		RenderTarget1 = SSSR_LowResDepthTex;
	}
#endif //DX9 compatibility
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = RayMarch;
		RenderTarget0 = SSSR_ReflectionTex;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalFilter;
		RenderTarget0 = SSSR_FilterTex0;
		RenderTarget1 = SSSR_HLTex0;
	}
	pass{VertexShader = PostProcessVS; PixelShader = SpatialFilter0; RenderTarget0 = SSSR_FilterTex1;}
	pass{VertexShader = PostProcessVS; PixelShader = SpatialFilter1; RenderTarget0 = SSSR_FilterTex0;}
	pass{VertexShader = PostProcessVS; PixelShader = SpatialFilter2; RenderTarget0 = SSSR_FilterTex1;
		RenderTarget1 = SSSR_PNormalTex;
		RenderTarget2 = SSSR_POGColTex;
		RenderTarget3 = SSSR_HLTex1;
		RenderTarget4 = SSSR_FilterTex2;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalStabilizer;
		RenderTarget0 = SSSR_FilterTex3;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = Output;
	}
}
