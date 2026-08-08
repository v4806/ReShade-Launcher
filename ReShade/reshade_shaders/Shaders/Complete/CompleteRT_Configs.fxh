//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 1.6 - Configs
//=============================================================//
//==================Quality Preset Settings====================//
//=============================================================//
//presets are : Very Low - Low - Medium - High - Very High - Ultra(currently unavailable)
//step count - ray length - reuse sample count
static const float3 DiffuseRM_Preset[6] = 
{        
	float3(24,   0.5, 1),
	float3(24,   0.5, 1),
	float3(32,   0.5, 1),
	float3(64,  1.00, 1),   
	float3(64,  1.00, 21),
	float3(128, 1.00, 21)
};

//step count - back steps count - sample count
static const float3 ReflectionRM_PresetSmooth[6] = 
{
	float3(10,  3, 1),
	float3(20,  3, 1),
	float3(20,  3, 1),
	float3(20,  3, 1),
	float3(20,  3, 1),
	float3(20,  3, 1)
};
//step count - back steps count - sample count
static const float3 ReflectionRM_presetRough[6] =
{
	float3(12, 0, 1),
	float3(20, 3, 4),
	float3(20, 3, 4),
	float3(20, 3, 4), 
	float3(20, 3, 8),
	float3(20, 3, 12)
};
//0 : 4 pass 3x3 atrous - 1,3,9,27 kernel || 5*5 spatial variance
//1 : 5 pass 3X3 atrous - 1,2,4,8,18,32 kernel || 7*7 spatial variance
static const bool Denoiser_preset[6] =
{
	0,
	1,
	0,
	1,
	1,
	1
};

static const float Resolution_preset[6] =
{
	0.333,
	0.500,
	0.740,
	1.000,
	1.000,
	1.000
};

static const int SmoothNormals_preset[6] =
{
	 0,
	 0,
	 0,
	 3,
	 6,
	 10
};

static const bool ThicknessEstimation_preset[6] =
{
	0,
	0,
	0,
	1,
	1,
	1
};


//=============================================================//
//==================UI PreCompile Settings=====================//
//=============================================================//

#ifndef C_RT_UI_DIFFICULTY
 #define C_RT_UI_DIFFICULTY 0
#endif

#ifndef C_RT_USE_LAUNCHPAD_MOTIONS
 #define C_RT_USE_LAUNCHPAD_MOTIONS 0
#endif

//=============================================================//
//======================Other Settings=========================//
//=============================================================//

//Experimental
static const bool UI_DepthBasedResolution = 1;

static const bool UI_FixOutlines = 1;
static const bool UI_PostRCRS = 0;
static const bool UI_PostRCRS2 = 0;

#define HighPrecisionMode 0

#if !HighPrecisionMode
 #define TexP RGBA16f
#else
 #define TexP RGBA32f
#endif 

//#define DevMode 0

#if __RENDERER__ < 0xa000
 #undef C_RT_HYBRID_MODE
 #define C_RT_HYBRID_MODE 0
#endif

#define NO_ROUGH_TEX          0
#define SMOOTHNORMALS_ENABLED 1

//Finding the max allowed mip level
#if BUFFER_WIDTH < BUFFER_HEIGHT
 #define MIN_DIM BUFFER_WIDTH
#else
 #define MIN_DIM BUFFER_HEIGHT
#endif

//Depth Buffer res for ray marching
#define RES_M 1

//=============================================================//
//====================Smooth Normals===========================//
//=============================================================//

static const float SN_DThreshold <ui_type="drag";> = 0.01;//max d diff
static const float SN_NThreshold <ui_type="drag";> = 0.7; //max n diff
static const float SN_Radius  <ui_type="drag";> = 32;     //radius
static const int   SN_DirCount = 12;                         //dirs

#define Bump_Mapping_EdgeThreshold 0.2

//=============================================================//
//====================Color Conversion=========================//
//=============================================================//

//Tonemapping mode : 1 = Timothy Lottes || 0 = Reinhardt
#define TM_Mode 1
#define IT_Intensity 0.96
//clamps the maximum luma of pixels to avoid unsolvable fireflies
#define LUM_MAX 25.0

//=============================================================//
//=====================Simple UI Preset========================//
//=============================================================//

#define STEPNOISE 3
#define SkyDepth 0.99

#if !C_RT_UI_DIFFICULTY

 //simple UI mode preset
 #define fov 80
 #define UI_RayDepth 5
 #define UI_ReflectionRayDepth 2
 #define UI_MaxFrames 32 
 #define UI_Sthreshold 1
 #define UI_MVErrorT 0.02
 #define UI_SkyColorMode 1
 #define UI_SkyColorTint float3(1,1,1)
 #define UI_FilterQuality (Denoiser_preset[UI_QualityPreset])
 #define UI_ThicknessEstimation (ThicknessEstimation_preset[UI_QualityPreset])

 //assuming newer games use the more accurate one
 #if __RENDERER__ >= 0xb000
  #define UI_FadeMode 0
 #else
  #define UI_FadeMode 1
 #endif

#endif

//=============================================================//
//===================Temporal Stabilizer=======================//
//=============================================================//

//Temporal stabilizer Intensity
#define TSIntensity 0.9
#define TS_Clamp 1
#define TS_JitterUpscale 1
#define TS_Sharpness 0
#define TS_PostSharpness 1//for after upscaling

//=============================================================//
//========================Filtering============================//
//=============================================================//

#define Spatial_Filter_Radius 1 //1 or 2, don't go bigger. Massively affects performance
#define Spatial_Filter_Base (UI_FilterQuality ? 2 : 3) //power base of the sample distance. 2 goes for 1-2-4-8-16, 3 goes for 1-3-9-27 for Lite mode
#define VarianceEstimationSearchRadius (UI_FilterQuality ? 3 : 2)
//to toggle each spatial pass
#define SF0 1
#define SF1 1
#define SF2 1
#define SF3 1
#define SF4 (UI_FilterQuality)

#define Spatial_Filter_NormalT           100.0//100
#define Spatial_Filter_DepthT            100.0//100
#define Spatial_Filter_LuminanceT        (0.5 * UI_Sthreshold)

#define Temporal_Filter_MVErrorT   (sqrt(UI_MVErrorT * 0.1)) //lower = more sensitive
#define Temporal_Filter_DepthT     0.010 //0.010 //lower = more sensitive
#define Temporal_Filter_LuminanceT 2.000 //4.00 //higher = more sentsitive
#define Temporal_Filter_MinClamp   0.000 //0.5? //higher = more history clamping in stationary scene
#define Temporal_Filter_MaxClamp   1.000
static const bool Temporal_Filter_ClampOutput = 1;
#define Temporal_Filter_Recurrence_MaxFrames 20 //20