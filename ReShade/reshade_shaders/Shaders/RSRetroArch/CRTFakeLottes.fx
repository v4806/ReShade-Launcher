#include "ReShade.fxh"

// Simple scanlines with curvature and mask effects lifted from crt-lottes
// by hunterk

////////////////////////////////////////////////////////////////////
////////////////////////////  SETTINGS  ////////////////////////////
/////  comment these lines to disable effects and gain speed  //////
////////////////////////////////////////////////////////////////////

#ifndef MASK
	#define MASK 1 // fancy, expensive phosphor mask effect
#endif

#ifndef CURVATURE
	#define CURVATURE 1 // applies barrel distortion to the screen
#endif

#ifndef SCANLINES
	#define SCANLINES 1  // applies horizontal scanline effect
#endif

#ifndef ROTATE_SCANLINES
	#define ROTATE_SCANLINES 0 // for TATE games; also disables the mask effects, which look bad with it
#endif

#ifndef EXTRA_MASKS
	#define EXTRA_MASKS 1 // disable these if you need extra registers freed up
#endif

////////////////////////////////////////////////////////////////////
//////////////////////////  END SETTINGS  //////////////////////////
////////////////////////////////////////////////////////////////////

// prevent stupid behavior
#if (ROTATE_SCANLINES == 1) && (SCANLINES == 0)
	#define SCANLINES 1
#endif

uniform float video_sizeX <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = BUFFER_WIDTH;
	ui_label = "帧宽度 [CRT-FakeLottes]";
	ui_tooltip = "应根据纹理中的视频数据进行设置 (如果使用模拟器，请设置为模拟器视频帧大小，否则保持与屏幕宽高或全屏分辨率相同。)";
> = 320.0;

uniform float video_sizeY <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = BUFFER_HEIGHT;
	ui_label = "帧高度 [CRT-FakeLottes]";
	ui_tooltip = "应根据纹理中的视频数据进行设置 (如果使用模拟器，请设置为模拟器视频帧大小，否则保持与屏幕宽高或全屏分辨率相同。)";
> = 240.0;

uniform float shadowMask <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 4.0;
	ui_step = 1.0;
	ui_label = "阴影遮罩 [CRT-FakeLottes]";
> = 1.0;

uniform float SCANLINE_SINE_COMP_B <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.05;
	ui_label = "扫描线强度 [CRT-FakeLottes]";
> = 0.40;

uniform float warpX <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 0.125;
	ui_step = 0.01;
	ui_label = "X轴弯曲 [CRT-FakeLottes]";
> = 0.031;

uniform float warpY < 
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 0.125;
	ui_step = 0.01;
	ui_label = "Y轴弯曲 [CRT-FakeLottes]"; 
> = 0.041;

uniform float maskDark <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 2.0;
	ui_step = 0.1;
	ui_label = "遮罩暗部 [CRT-FakeLottes]"; 
> = 0.5;

uniform float maskLight <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 2.0;
	ui_step = 0.1;
	ui_label = "遮罩亮部 [CRT-FakeLottes]";
> = 1.5;

uniform float crt_gamma <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = 4.0;
	ui_step = 0.05;
	ui_label = "CRT伽马 [CRT-FakeLottes]";
> = 2.5;

uniform float monitor_gamma  <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = 4.0;
	ui_step = 0.05;
	ui_label = "显示器伽马 [CRT-FakeLottes]";
> = 2.2;
uniform float SCANLINE_SINE_COMP_A <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 0.10;
	ui_step = 0.01;
	ui_label = "扫描线正弦分量A [CRT-FakeLottes]";
> = 0.0;

uniform float SCANLINE_BASE_BRIGHTNESS < 
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.01;
	ui_label = "扫描线基础亮度 [CRT-FakeLottes]"; 
> = 0.95;

#define video_size float2(video_sizeX, video_sizeY)

float4 scanline(float2 coord, float4 frame) {
#if (SCANLINES == 1)
	float2 omega = float2(3.1415 * ReShade::ScreenSize.x, 2.0 * 3.1415 * video_size.y);
	float2 sine_comp = float2(SCANLINE_SINE_COMP_A, SCANLINE_SINE_COMP_B);
	float3 res = frame.xyz;
	#if(ROTATE_SCANLINES == 1)
		sine_comp = sine_comp.yx;
		omega = omega.yx;
	#endif
	float3 scanline = res * (SCANLINE_BASE_BRIGHTNESS + dot(sine_comp * sin(coord * omega), float2(1.0, 1.0)));

	return float4(scanline.x, scanline.y, scanline.z, 1.0);
#else
	return frame;
#endif
}

#if (CURVATURE == 1)
// Distortion of scanlines, and end of screen alpha.
float2 Warp(float2 pos)
{
    pos  = pos*2.0-1.0;    
    pos *= float2(1.0 + (pos.y*pos.y)*warpX, 1.0 + (pos.x*pos.x)*warpY);
    
    return pos*0.5 + 0.5;
}
#endif

#if (MASK == 1) && (ROTATE_SCANLINES == 0)
	// Shadow mask.
	float4 Mask(float2 pos)
	{
		float3 mask = float3(maskDark, maskDark, maskDark);
	  
		// Very compressed TV style shadow mask.
		if (shadowMask == 1.0) 
		{
			float line = maskLight;
			float odd = 0.0;
			
			if (frac(pos.x*0.166666666) < 0.5) odd = 1.0;
			if (frac((pos.y + odd) * 0.5) < 0.5) line = maskDark;  
			
			pos.x = frac(pos.x*0.333333333);

			if      (pos.x < 0.333) mask.r = maskLight;
			else if (pos.x < 0.666) mask.g = maskLight;
			else                    mask.b = maskLight;
			mask*=line;  
		} 

		// Aperture-grille.
		else if (shadowMask == 2.0) 
		{
			pos.x = frac(pos.x*0.333333333);

			if      (pos.x < 0.333) mask.r = maskLight;
			else if (pos.x < 0.666) mask.g = maskLight;
			else                    mask.b = maskLight;
		} 
	#if (EXTRA_MASKS == 1)
		// These can cause moire with curvature and scanlines
		// so they're an easy target for freeing up registers
		
		// Stretched VGA style shadow mask (same as prior shaders).
		else if (shadowMask == 3.0) 
		{
			pos.x += pos.y*3.0;
			pos.x  = frac(pos.x*0.166666666);

			if      (pos.x < 0.333) mask.r = maskLight;
			else if (pos.x < 0.666) mask.g = maskLight;
			else                    mask.b = maskLight;
		}

		// VGA style shadow mask.
		else if (shadowMask == 4.0) 
		{
			pos.xy  = floor(pos.xy*float2(1.0, 0.5));
			pos.x  += pos.y*3.0;
			pos.x   = frac(pos.x*0.166666666);

			if      (pos.x < 0.333) mask.r = maskLight;
			else if (pos.x < 0.666) mask.g = maskLight;
			else                    mask.b = maskLight;
		}
	#endif
		
		else mask = float3(1.,1.,1.);

		return float4(mask, 1.0);
	}
#endif

float4 PS_CRTFakeLottes(float4 vpos : SV_Position, float2 txcoord : TexCoord) : SV_Target
{
	float4 col;
	#if (CURVATURE == 1)
		float2 pos = Warp(txcoord.xy);
	#else
		float2 pos = txcoord.xy;
	#endif

	#if (MASK == 1) && (ROTATE_SCANLINES == 0)
		// mask effects look bad unless applied in linear gamma space
		float4 in_gamma = float4(monitor_gamma, monitor_gamma, monitor_gamma, 1.0);
		float4 out_gamma = float4(1.0 / crt_gamma, 1.0 / crt_gamma, 1.0 / crt_gamma, 1.0);
		float4 res = pow(tex2D(ReShade::BackBuffer, pos), in_gamma);
	#else
		float4 res = tex2D(ReShade::BackBuffer, pos);
	#endif

	#if (MASK == 1) && (ROTATE_SCANLINES == 0)
		// apply the mask; looks bad with vert scanlines so make them mutually exclusive
		res *= Mask(txcoord * ReShade::ScreenSize.xy * 1.0001);
	#endif

	#if (MASK == 1) && (ROTATE_SCANLINES == 0)
		// re-apply the gamma curve for the mask path
		col = pow(scanline(pos, res), out_gamma);
	#else
		col = scanline(pos, res);
	#endif

	return col;
}

technique CRTFakeLottes {
	pass CRT_FakeLottes {
		VertexShader=PostProcessVS;
		PixelShader=PS_CRTFakeLottes;
	}
}