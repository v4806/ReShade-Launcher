//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 1.6
/*******************************************************************
 Copyright (c) MohammadJavad Ehsan. All rights reserved.
    
    * Unauthorized copying of this file, via any medium is strictly prohibited
 	* Proprietary and confidential

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.
 *******************************************************************/
 
#include "CompleteRT_Main.fxh"

#if __RESHADE__ >= 50300

	#define FILTER_RENDER_TARGET_TEX0 \
	RenderTarget0 = RT_FilterTex0; \
	GenerateMipMaps = false;
	
	#define FILTER_RENDER_TARGET_TEX1 \
	RenderTarget0 = RT_FilterTex1; \
	GenerateMipMaps = false;

#else

	#define FILTER_RENDER_TARGET_TEX0 \
	RenderTarget0 = RT_FilterTex0; \
	
	#define FILTER_RENDER_TARGET_TEX1 \
	RenderTarget0 = RT_FilterTex1; \

#endif

technique COMPLETE_RT<
	ui_label = "COMPLETE RT";
	ui_tooltip = "||                COMPLETE RT || 版本 1.6.0             ||\n"
	             "||                        作者 NiceGuy                       ||\n"
	             "||一体化反射和间接光照解决方案。||\n\n"

	             "重要提示：修改着色器前请先阅读提示！";
>
{
	pass GBufferGenerator
	{
		VertexShader  = PostProcessVS;
		PixelShader   = GBuffer1;
		RenderTarget0 = RT_FilterTex0;
		ClearRenderTargets = TRUE;
	}
	pass SmoothNormals
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SmoothNormals;
		RenderTarget0 = RT_NormTex;
		RenderTarget1 = RT_RoughnessTex;
		RenderTarget2 = RT_HQNormTex;
		ClearRenderTargets = TRUE;
	}
	pass LowResGBuffer
	{
		VertexShader  = PostProcessVS;
		PixelShader   = CopyGBufferLowRes;
		RenderTarget0 = RT_LowResDepthTex;
		ClearRenderTargets = TRUE;
	}
	pass thickness
	{
		VertexShader  = PostProcessVS;
		PixelShader   = ThicknessEstimation;
		RenderTarget0 = RT_ThicknessTex;
		
		ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
	}
	pass SkyColor
	{
		VertexShader  = PostProcessVS;
		PixelShader   = Sky;
		RenderTarget0 = RT_HLTex1;
		
		ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = INVSRCALPHA;
        DestBlend = SRCALPHA;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = RayMarchPrep;
		RenderTarget0 = RT_FilterTex0;
		RenderTarget1 = RT_HLTex0;
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalReservoir_CopyBuffer;
		RenderTarget0 = RT_TReservoirHistory;
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = RayMarchDiffuse_PS;
		RenderTarget0 = RT_FilterTex1;
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = RayMarchSpecular_PS;
		RenderTarget0 = RT_FilterTex1;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalFilter;
		RenderTarget0 = RT_HLTex0;
		RenderTarget1 = RT_FilterTex0;
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter0;
		FILTER_RENDER_TARGET_TEX1
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = HistoryBuffer0;
		RenderTarget0 = RT_HistoryTex0;
		ClearRenderTargets = FALSE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter1;
		FILTER_RENDER_TARGET_TEX0
		ClearRenderTargets = TRUE;
	}
	pass 
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter2;
		FILTER_RENDER_TARGET_TEX1
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter3;
		FILTER_RENDER_TARGET_TEX0
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = SpatialFilter4;
		FILTER_RENDER_TARGET_TEX1
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalStabilizer;
		FILTER_RENDER_TARGET_TEX0
		ClearRenderTargets = TRUE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = TemporalStabilizer_CopyBuffer;
		RenderTarget0 = RT_HistoryTex1;
		RenderTarget1 = RT_HLTex1;
		ClearRenderTargets = FALSE;
	}
	pass
	{
		VertexShader  = PostProcessVS;
		PixelShader   = Output;
	}
}
