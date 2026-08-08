/*
ZN Depth Aware Mipmapped Ray Tracing (DAMP RT), by Zenteon (Daniel Oren-Ibarra)

Techniques used, papers inpiring, and information aquired:

Improved Normal Reconstruction from Depth:
	https://atyuwen.github.io/posts/normal-reconstruction/
Fitted modified ACES Tonemapping curve:
	https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
Bandwidth Efficient Graphics (Dual Kawase Blur):
	https://community.arm.com/cfs-file/__key/communityserver-blogs-components-weblogfiles/00-00-00-20-66/siggraph2015_2D00_mmg_2D00_marius_2D00_notes.pdf
Neighborhood Clamping:
	https://www.elopezr.com/temporal-aa-and-the-quest-for-the-holy-trail/	
TAA (Used for denoising)
	https://de45xmedrsdbp.cloudfront.net/Resources/files/TemporalAA_small-59732822.pdf
Variance Clamping:
	https://developer.download.nvidia.com/gameworks/events/GDC2016/msalvi_temporal_supersampling.pdf
Simple Hash:
	https://www.shadertoy.com/view/4djSRW
Reinhardt Jodie tonemapper https:
	//www.shadertoy.com/view/4dBcD1
Thanks to Matsilagi for the Sponza Test: //https://mega.nz/#!qVwGhYwT!rEwOWergoVOCAoCP3jbKKiuWlRLuHo9bf1mInc9dDGE
*/

#include "ReShade.fxh"

#ifndef DO_REFLECT
//============================================================================================
	#define DO_REFLECT 0 //Enables diffuse reflections
//============================================================================================
#endif

#ifndef ZNRY_SAMPLE_DIV
//============================================================================================
	#define ZNRY_SAMPLE_DIV 4 //Sample Texture Resolution Divider
//============================================================================================
#endif

#ifndef ZNRY_RENDER_SCL
//============================================================================================
	#define ZNRY_RENDER_SCL 0.5 //Sample Texture Resolution Divider
//============================================================================================
#endif


#ifndef ZNRY_MAX_LODS
//============================================================================================
	#define ZNRY_MAX_LODS 6 //How many Lods are checked during sampling, moderate impact
//============================================================================================
#endif

#ifndef HIDE_EXPERIMENTAL
//============================================================================================
	#define HIDE_EXPERIMENTAL 1 //Hides experimental or unfinished features
//============================================================================================
#endif

#ifndef HIDE_ADVANCED
//============================================================================================
	#define HIDE_ADVANCED 1 //Hides advanced settings that you probably shouldn't touch
//============================================================================================
#endif

#ifndef HIDE_INTERMEDIATE
//============================================================================================
	#define HIDE_INTERMEDIATE 1 //Hides experimental or unfinished features
//============================================================================================
#endif

#ifndef IMPORT_SAM
//============================================================================================
	#define IMPORT_SAM 0 //Hides experimental or unfinished features
//============================================================================================
#endif


#ifndef ZNRY_MV_TYPE
//============================================================================================
	#define ZNRY_MV_TYPE 0 //Vort, other, launchpad
//============================================================================================
#endif

#define RES float2(BUFFER_WIDTH, BUFFER_HEIGHT)
#define FARPLANE RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
#define ASPECT_RATIO RES.x/RES.y

uniform int FRAME_COUNT <
	source = "framecount";>;



static int2 TAA_SAM_DST[8] = {
		int2(1,-3), int2(-1,3), 
		int2(5,1), int2(-3,-5),
		int2(-5,5), int2(-7,-1),
		int2(3,7), int2(7,-7)};

uniform int ZN_DAMPRT <
	ui_label = " ";
	ui_text = "注意：使用前请阅读'预处理器信息'并启用运动向量\n\n"
			"Zentient DAMP RT（深度感知Mip映射光线追踪）是一个基于\n"
			"采样mip级别来在2D空间中近似锥体追踪\n"
			"然后外推到3D的着色器\n"
			"虽然没有直接取自任何论文，但在看到\n"
			"Alexander Sannikov使用辐射级联计算GI的方法后受到了很大启发。\n";
	ui_type = "radio";
	ui_category = "ZN DAMP RT";
> = 1;  

uniform float BUFFER_SCALE <
	ui_type = "slider";
	ui_min = 0.5;
	ui_max = 5.0;
	ui_label = "缓冲区缩放";
	ui_tooltip = "调整近处物体的深度缓冲精度";
	ui_category = "深度缓冲设置";
	hidden = true;
> = 2.0;

uniform float NEAR_PLANE <
	ui_type = "slider";
	ui_min = -1.0;
	ui_max = 2.0;
	ui_label = "近平面";
	ui_tooltip = "调整深度缓冲的最小深度，如果看到暗线或遮挡伪影请稍微增加";
	ui_category = "深度缓冲设置";
	ui_category_closed = true;
	hidden = HIDE_ADVANCED;
> = 0.0;

uniform float FOV <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 110.0;
	ui_label = "视野";
	hidden = true;
	ui_tooltip = "调整以匹配游戏内FOV";
	ui_category = "深度缓冲设置";
	ui_step = 1;
> = 70;

uniform bool SMOOTH_NORMALS <
	ui_label = "平滑法线";
	ui_tooltip = "平滑法线以模拟更高面数的模型 || 中等性能影响";
	ui_category = "深度缓冲设置";
	hidden = HIDE_EXPERIMENTAL;
> = 0;

uniform float INTENSITY <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 20.0;
	ui_label = "GI强度";
	ui_tooltip = "效果强度。最高可达40，但不建议保持在那里";
	ui_category = "显示";
	ui_category_closed = true;
> = 6.0;

uniform float SHADOW_INT <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "阴影强度";
	ui_tooltip = "在添加GI之前加深阴影";
	ui_category = "显示";
> = 0.8;

uniform float SHADOW_GAMMA <
	ui_type = "slider";
	ui_min = 0.01;
	ui_max = 2.0;
	ui_label = "阴影伽马";
	ui_tooltip = "混合前应用于阴影的伽马值";
	hidden = HIDE_INTERMEDIATE;
	ui_category = "显示";
> = 1.0;


uniform float3 SKY_COLOR <
	ui_type = "color";
	ui_label = "环境光颜色";
	ui_tooltip = "为场景添加环境光";
	ui_category = "显示";
> = float3(0.45, 0.45, 0.5);

uniform float LIGHTMAP_SAT <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 3.0;
	ui_label = "光照图饱和度";
	ui_tooltip = "提升光照图饱和度以补偿下采样";
	hidden = HIDE_INTERMEDIATE;
	ui_category = "显示";
	ui_category_closed = true;
> = 1.2;

uniform float HDR_RED <
	ui_type = "slider";
	ui_min = 1.01;
	ui_max = 1.6;
	ui_label = "HDR衰减";
	ui_tooltip = "减少明暗区域之间的最大差异";
	hidden = HIDE_INTERMEDIATE;
	ui_category = "显示";
	ui_category_closed = true;
> = 1.1;

uniform bool DO_BOUNCE <
	ui_label = "弹射光照";
	ui_tooltip = "累积前几帧的GI来计算额外的GI步骤 || 无性能影响";
	ui_category = "显示";
	hidden = HIDE_INTERMEDIATE;
> = 1;

uniform float TERT_INTENSITY <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "弹射强度";
	ui_tooltip = "累积弹射光照的强度，对GI有复合效果";
	ui_category = "显示";
	hidden = HIDE_INTERMEDIATE;
	ui_category_closed = true;
> = 0.5;

uniform float AMBIENT_NEG <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "曝光减少";
	ui_tooltip = "在添加GI之前减少曝光";
	ui_category = "显示";
> = 0.0;

uniform bool DO_AO <
	ui_label = "环境光遮蔽";
	ui_tooltip = "轻量级环境光遮蔽实现 || 低性能影响";
	ui_category = "显示";
> = 1;

uniform float DEPTH_MASK <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_label = "深度遮罩";
	ui_tooltip = "深度衰减以兼容游戏内雾效";
	ui_category = "显示";
> = 0.08;	

uniform float COLORMAP_BIAS <
	ui_type = "slider";
	ui_label = "色彩映射偏移";
	ui_tooltip = "标准化颜色缓冲，建议保持非常接近1.0";
	ui_category = "颜色";
	ui_category_closed = true;
	hidden = HIDE_ADVANCED;
	ui_min = 0.9;
	ui_max = 1.0;
> = 0.997;

uniform float COLORMAP_OFFSET <
	ui_type = "slider";
	ui_label = "色彩映射补偿";
	hidden = HIDE_ADVANCED;
	ui_tooltip = "尝试减少暗色中的伪影，但在某些场景中可能会使其褪色";
	ui_category = "颜色";
	ui_min = 0.0;
	ui_max = 0.01;
> = 0.001;

uniform float3 DETINT_COLOR <
	ui_type = "color";
	ui_label = "去色偏颜色";
	ui_tooltip = "可以帮助从GI中移除某些增强的颜色（例如紫色阴影）";
	ui_category = "颜色";
> = float3(0.06, 0.45, 1.0);

uniform float DETINT_LEVEL <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "去色偏强度";
	ui_tooltip = "应用的去色偏量";
	ui_category = "颜色";
> = 0.0;

uniform bool TAA_ERROR <
	ui_label = "时间平滑";
	ui_tooltip = "配合运动向量着色器使用时几乎可以完全消除噪点，如果不使用运动向量请禁用\n"
				"推荐使用vort_motion或qUINT_MotionVectors，也应该与大多数运动向量兼容";
	ui_category = "降噪";
	ui_min = 0.0;
	ui_max = 1.0;
> = 1.0;

uniform bool DONT_SPATIAL <
	ui_label = "禁用空间降噪";
	ui_tooltip = "在时间降噪之前禁用空间上采样/降噪器";
	ui_category = "降噪";
	hidden = HIDE_ADVANCED;
> = 0;

uniform float TAA_SKIP <
	ui_type = "slider";
	ui_label = "时间跳过";
	ui_tooltip = "帮助减少没有运动向量时的闪烁\n"
					"如果不使用运动向量请设置为2";
	ui_category = "降噪";
	ui_min = 1.0;
	ui_max = 2.0;
	ui_step = 1.0;
> = 1.0;

uniform float FRAME_PERSIST <
	ui_type = "slider";
	ui_label = "帧持久性";
	ui_tooltip = "较低的值鬼影较少但噪点较多，较高的值噪点较少但鬼影较多\n";
	ui_category = "降噪";
	ui_min = 0.1;
	ui_max = 0.95;
> = 0.875;

uniform int UPSCALE_ITER <
	ui_type = "slider";
	ui_label = "降噪采样数";
	ui_tooltip = "减少噪点并改善上采样，但会牺牲细节和性能";
	ui_min = 2;
	ui_max = 64;
> = 8;

uniform int SAMPLE_COUNT <
	ui_type = "slider";
	ui_label = "光线数量";
	ui_min = 3;
	ui_max = 24;
	ui_tooltip = "每像素投射的光线数量。超过6条后收益递减显著 || 高性能影响";
	ui_category = "采样";
	ui_category_closed = true;
> = 5;



uniform bool SHADOW <
	ui_label = "阴影";
	ui_tooltip = "拒绝部分采样以投射软阴影，本质上是一个很好的AO || 几乎无性能影响";
	ui_category = "采样";
	hidden = HIDE_INTERMEDIATE;
> = 1;

uniform bool ENABLE_Z_THK <
	ui_label = "启用Z厚度";
	ui_tooltip = "为阴影遮挡启用厚度以防止阴影光晕 || 低性能影响";
	ui_category = "采样";
	hidden = HIDE_INTERMEDIATE;
> = 1;

uniform float SHADOW_Z_THK <
	ui_type = "slider";
	ui_label = "Z厚度";
	ui_tooltip = "投射阴影的深度";
	ui_category = "采样";
	hidden = HIDE_INTERMEDIATE;
	ui_min = 0.001;
	ui_max = 1.0;
> = 0.01;

uniform float SHADOW_BIAS <
	ui_type = "slider";
	ui_label = "阴影偏移";
	ui_tooltip = "减少阴影的伪影和强度";
	ui_category = "采样";
	hidden = HIDE_ADVANCED;
	ui_min = -0.01;
	ui_max = 0.01;
> = 0.001;

uniform bool BLOCK_SCATTER <
	ui_label = "阻挡散射";
	ui_tooltip = "防止表面散射和已经明亮区域的增亮 || 低-中性能影响";
	ui_category = "采样";
	hidden = HIDE_INTERMEDIATE;
> = 1;

uniform float RAY_LENGTH <
ui_type = "slider";
	ui_min = 0.5;
	ui_max = 10.0;
	ui_label = "光线步长";
	ui_tooltip = "改变每个Mip的光线步长，降低整体采样质量但增加光线范围 || 中等性能影响";
	ui_category = "采样";
	hidden = HIDE_INTERMEDIATE;
> = 4.0;

uniform float DIST_BIAS <
ui_type = "slider";
	ui_min = 0.0;
	ui_max = 2.0;
	ui_label = "距离偏移";
	ui_tooltip = "给远处采样稍高的权重以弥补不完整的采样 || 无性能影响";
	ui_category = "采样";
	hidden = HIDE_INTERMEDIATE;
> = 0.25;

uniform float DISTANCE_SCALE <
	ui_type = "slider";
	ui_min = 0.01;
	ui_max = 20.0;
	ui_label = "距离缩放";
	ui_tooltip = "进行亮度计算的尺度\n"
				"较高的值使光线衰减更快，较低的值使光线传播更远。\n"
					"注意较低的值不一定'更好'";
	ui_category = "采样";
	hidden = HIDE_INTERMEDIATE;
> = 1.0;

uniform float DISTANCE_POW <
ui_type = "slider";
	ui_min = 0.5;
	ui_max = 3.0;
	ui_label = "距离指数";
	ui_tooltip = "光线衰减的逆幂，2.0是平方反比，1.0是线性";
	ui_category = "采样";
	hidden = HIDE_ADVANCED;
> = 2.0;

uniform int DEBUG <
	ui_type = "combo";
	ui_category = "调试设置";
	ui_items = "无\0光照\0GI * 色彩映射\0全局光照\0阴影\0色彩映射\0去鬼影遮罩\0法线\0深度\0光照图\0";
	hidden = HIDE_INTERMEDIATE;
> = 0;

uniform bool SHOW_MIPS <
	ui_label = "显示Mip映射";
	ui_category = "调试设置";
	ui_tooltip = "仅供娱乐，让想要可视化其工作原理的人使用\n"
		"建议使用光照或GI调试视图";
	hidden = HIDE_INTERMEDIATE;
> = 0;

uniform bool STATIC_NOISE <
	ui_label = "静态噪点";
	ui_category = "调试设置";
	ui_tooltip = "禁用采样抖动";
	hidden = HIDE_ADVANCED;
> = 0;

uniform bool DONT_DENOISE <
	ui_category = "调试设置";
	ui_label = "禁用时间降噪";
	hidden = HIDE_ADVANCED;
> = 0;


uniform float SPECULAR_POW <
	ui_type = "slider";
	ui_min = 0.5;
	ui_max = 10.0;
	ui_label = "反射强度";
	ui_tooltip = "漫反射强度，仅在启用实验性反射时有效";
	hidden = 1 - DO_REFLECT;
> = 2.0;

uniform int TONEMAPPER <
	ui_type = "combo";
	ui_items = "ZN Filmic\0Sony A7RIII\0ACES\0改进版Reinhard Jodie\0无\0"; //Contrast\0
	ui_label = "色调映射器";
	ui_tooltip = "色调映射器选择，Reinhardt Jodie最接近原始图像，但也提供了其他选项";
	ui_category = "实验性";
	hidden = HIDE_EXPERIMENTAL;
> = 3;

uniform bool DYNA_SAMPL <
	ui_category = "实验性";
	ui_label = "动态采样";
	ui_tooltip = "动态应用采样数量以节省性能";
	hidden = HIDE_EXPERIMENTAL;
> = 0;

uniform bool REMOVE_DIRECTL <
	ui_label = "亮度遮罩";
	ui_tooltip = "防止已照亮区域的过度照明，但会显著降低局部对比度 || 无性能影响";
	ui_category = "实验性";
	hidden = true;
> = 0;


uniform int PREPRO_SETTINGS <
	ui_type = "radio";
	ui_category = "预处理器信息";
	ui_category_closed = true;
	ui_text = "预处理器定义指南：\n"
			"\n"
			"注意：只有在知道自己在做什么时才更改预处理器，如果更改设置导致编译失败，请创建新预设或清除RESHADEPRESET.ini中的DAMP预处理器设置\n"
			"\n"
			"DO_REFLECT - 启用实验性漫反射，未完成，相当不准确，且有显著的性能影响\n"
			"\n"
			"HIDE INTERMEDIATE/ADVANCED/EXPERIMENTAL - 显示不同级别的高级设置，实验性设置未完成且未测试\n"
			"\n"
			"IMPORT_SAM - 切换实验性重要性采样以挑选结果，有中等性能影响，通常提供较差的结果\n"
			"\n"
			"ZNRY_MAX_LODS - 采样的最大LOD，对性能有直接影响，对光线范围有指数影响。最大推荐7，一般最大9但可能在低分辨率缩放时导致编译失败\n"
			"7通常足以覆盖接近全屏\n"
			"\n"
			"ZNRY_MV_TYPE - 选择要使用的运动向量着色器：0为vort_Motion，1为launchpad，2为大多数其他（qUINT、Uber等）\n"
			"注意运动向量必须正确配置以防止噪点和鬼影\n"
			"\n"
			"ZNRY_RENDER_SCL - GI的分辨率缩放（0.5是50%，1.0是100%），更改可能需要重新加载ReShade。\n"
			"\n"
			"ZNRY_SAMPLE_DIV - 采样纹理的mip级别（例如，4是1/4分辨率，2是一半分辨率，1是全分辨率）\n"
			"这有中等性能影响，质量改善最小，对范围有负面影响，不建议设置低于2";
> = 1;

uniform int CREDITS <
	ui_type = "radio";
	ui_category = "致谢";
	ui_text = "\n致谢和感谢：\n"
			"特别感谢Soop、Beta|Alea、Can、AlucardDH、BlueSkyDefender、Ceejay.dk和Dreamt的着色器测试和反馈\n"
			"感谢BlueSkyDefender、Vortigern和LordofLunacy\n"
			"他们疯狂到尝试理解这个意大利面条代码着色器的一些部分\n"
			"特别感谢Crushius提供'Shadow Man Remastered'的副本，让我可以在Skyrim以外的游戏中测试\n"
			"如果您帮助过开发但我忘记在这里提及您，请联系我以便我修正致谢";
	ui_label = " ";
> = 0;

uniform int SHADER_VERSION <
	ui_type = "radio";
	ui_text = "\n" "着色器版本 - 测试版 A26-3-1 (v0.2.6.3.1)";
	ui_label = " ";
> = 0;



//============================================================================================
//Textures/Samplers
//=================================================================================
namespace A26{
	texture BlueNoiseTex < source = "ZNbluenoise512.png"; >
	{
		Width  = 512.0;
		Height = 512.0;
		Format = RGBA8;
	};
	sampler NoiseSam{Texture = BlueNoiseTex; MipFilter = Point;};
	
	texture NorTex{Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 3;};
	sampler NorSam{Texture = NorTex;};
	
	texture NorDivTex{
		Width = BUFFER_WIDTH / ZNRY_SAMPLE_DIV;
		Height = BUFFER_HEIGHT / ZNRY_SAMPLE_DIV;
		Format = RGBA8;
		MipLevels = ZNRY_MAX_LODS;
	};
	sampler NorDivSam{
		Texture = NorDivTex;
		MinFilter = POINT;
		MagFilter = POINT;
		MipFilter = POINT;
	};
	
	texture NorInTex{
		Width = BUFFER_WIDTH;
		Height = BUFFER_HEIGHT;
		Format = RGBA8;
		MipLevels = ZNRY_MAX_LODS;
	};
	sampler NorInSam{Texture = NorInTex;};
	
	texture BufTex{
		Width = int(BUFFER_WIDTH * ZNRY_RENDER_SCL / ZNRY_SAMPLE_DIV);
		Height = int(BUFFER_HEIGHT * ZNRY_RENDER_SCL / ZNRY_SAMPLE_DIV);
		Format = R16;
		MipLevels = ZNRY_MAX_LODS;
	};
	sampler DepSam{
		Texture = BufTex;
		MinFilter = POINT;
		MagFilter = POINT;
		MipFilter = POINT;
	};
	
	texture BilaTex{
		Width = int(BUFFER_WIDTH * ZNRY_RENDER_SCL);
		Height = int(BUFFER_HEIGHT * ZNRY_RENDER_SCL);
		Format = RGBA8;
		MipLevels = ZNRY_MAX_LODS;
	};
	sampler BilaSam{Texture = BilaTex;};
	texture LumTex{
		Width = int(BUFFER_WIDTH * ZNRY_RENDER_SCL / ZNRY_SAMPLE_DIV);
		Height = int(BUFFER_HEIGHT * ZNRY_RENDER_SCL / ZNRY_SAMPLE_DIV);
		Format = RGBA16F;
		MipLevels = ZNRY_MAX_LODS + 1;
	};
	sampler LumSam{Texture = LumTex;};
	
	texture GITex{
		Width = int(BUFFER_WIDTH * ZNRY_RENDER_SCL);
		Height = int(BUFFER_HEIGHT * ZNRY_RENDER_SCL);
		Format = RGBA16F;MipLevels = 3;
	};
	sampler GISam{
		Texture = GITex;
	};
	texture UpscaleTex{
		Width = BUFFER_WIDTH;
		Height = BUFFER_HEIGHT;
		Format = RGBA16F;MipLevels = 3;
	};
	sampler UpSam{
		Texture = UpscaleTex;
	};
	
	texture PreTex {
		Width = BUFFER_WIDTH;
		Height = BUFFER_HEIGHT;
		Format = RGBA8;
	};
	sampler PreFrm {Texture = PreTex;};
	
	texture PreLuminTex {
		Width = int(BUFFER_WIDTH * ZNRY_RENDER_SCL);
		Height = int(BUFFER_HEIGHT * ZNRY_RENDER_SCL);
		Format = R16;
		MipLevels = 2;
	};
	sampler PreLumin {Texture = PreLuminTex;};
	
	texture CurTex {
		Width = BUFFER_WIDTH;
		Height = BUFFER_HEIGHT;
		Format = RGBA8;
		MipLevels = 3;
	};
	sampler CurFrm {Texture = CurTex;};
	
	texture DualTex {
		Width = BUFFER_WIDTH;
		Height = BUFFER_HEIGHT; 
		Format = RGBA8; MipLevels = 3;
	};
	sampler DualFrm {Texture = DualTex;};	
}



#define MV_TEX_PROPS {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F;};
#define POINT_SAM MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;

#if(ZNRY_MV_TYPE == 2)
texture2D texMotionVectors MV_TEX_PROPS	
sampler motionSam {Texture = texMotionVectors; POINT_SAM};

#elif(ZNRY_MV_TYPE == 1)
namespace Deferred {
	texture2D MotionVectorsTex MV_TEX_PROPS
}	
sampler motionSam {Texture = Deferred::MotionVectorsTex; POINT_SAM};

#else
texture2D MotVectTexVort MV_TEX_PROPS	
sampler motionSam {Texture = MotVectTexVort; POINT_SAM};
#endif
//============================================================================================
//Tonemappers
//============================================================================================


float3 SONYA7RIII(float3 z) //This is a custom tonemapper modeled after the SONY A7RIII sensor
{							//It looks somewhat bad
    float a = 0.1;
    float b = 1.1;
    float c = 0.5;
    float3 d = float3(0.02, 0.01, 0.02);
    float e = 1.3;
    float f = 4.8;
    float g = 0.3;
    float h = 2.0;
    float i = 0.2;
    float j = 0.6;
    float k = 1.3;
    float l = 2.5;
    
    z *= 20.0;
    z = h*(c+pow(a*z,b)-d*(sin(e*z)-j)/((k*z-f)*(k*z-f)+g));
    z = i*l*log(z);
    
    return saturate(z);
}

float3 ReinhardtJ(float3 x) //Modified Reinhardt Jodie
{
	float  lum = dot(x, float3(0.2126, 0.7152, 0.0722));
	float3 tx  = x / (x + 1.0);
	return HDR_RED * lerp(x / (lum + 1.0), tx, pow(tx, 0.7));
}

float3 InvReinhardtJ(float3 x)
{
	float  lum = dot(x, float3(0.2126, 0.7152, 0.0722));
	float3 tx  = -x / (x - HDR_RED);
	return lerp(tx, -lum / ((0.5 * x + 0.5 * lum) - HDR_RED), pow(x, 0.7));
}

float3 ZNFilmic(float3 x)
{
	float a = 17.36;
	float b = 16.667;
	float c = 3.0;
	float d = 0.4;
	return saturate((a*x*x+d*x) / (b*x*x + c*x + 1.0));
}

float3 ACESFilm(float3 x)
{
	float a = 2.51f;
	float b = 0.03f;
	float c = 2.43f;
	float d = 0.59f;
	float e = 0.14f;
	return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

//============================================================================================
//Functions
//============================================================================================

float3 saturation(float3 c, float sat)
{
	float lum = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722;
	c	 	= lerp(lum, c, sat);
	return saturate(c);
}

float3 eyePos(float2 xy, float z)//takes screen coords (0-1) and depth (0-1) and converts to eyespace position
{
	float  nd	 = z * FARPLANE;
	float3 eyp	= float3((2f * xy - 1f) * nd, nd);
	return eyp * float3(ASPECT_RATIO, 1.0, 1.0);
}

float3 NorEyePos(float2 xy)//takes screen coords (0-1) and depth (0-1) and converts to eyespace position
{
	float  nd	 = ReShade::GetLinearizedDepth(xy) * FARPLANE;
	float3 eyp	= float3((2f * xy - 1f) * nd, nd);
	return eyp * float3(ASPECT_RATIO, 1.0, 1.0);
}

float3 GetScreenPos(float3 xyz)//takes eyespace position and reprojects to screenspace
{
	xyz /= float3(ASPECT_RATIO, 1.0, 1.0);
	return float3(0.5 + 0.5 * (xyz.xy / xyz.z), xyz.z / FARPLANE);
}

int weighthash(float2 p, float w1, float w2) //For importance sampling
{
	float3 p3	= frac(float3(p.xyx) * .1031);
    	   p3	+= dot(p3, p3.yzx + 33.33);
    float  hsh   = frac((p3.x + p3.y) * p3.z);
    float  c	 = w1 / (w1 + w2);
    
    if(hsh < c) return 0;
    else return 1;
}

float2 hash(float2 p)
{
	float3 p3	= frac(p.xyx * float3(.1031, .1030, .0973));
    	   p3	+= dot(p3, p3.yzx+33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

float hash12(float2 p)
{
	float3 p3  = frac(p.xyx * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float3 hash3(float3 x)
{
	x		= frac(x * float3(.1031, .1030, .0973));
    x		+= dot(x, x.yxz+33.33);
    return   frac((x.xxy + x.yxx)*x.zyx);
}

float4 DAMPGI(float2 xy, float2 offset)//offset is noise value, output RGB is GI, A is shadows;
{
float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float  f	 = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
	float  n	 = NEAR_PLANE;
	float2 PW	= 2.0 * tan(FOV * 0.00875) * (f - n); //Dimensions of FarPlane
		   PW.y *= res.x / res.y;

	int	LODS  = ZNRY_MAX_LODS;
    float  trueD = ReShade::GetLinearizedDepth(xy);
    	if(trueD == 1.0) {return float4(0.0, 0.0, 0.0, 1.0);}
    float3 surfN = 2.0 * tex2D(A26::NorSam, xy).rgb - 1.0;
    
    float  d	 = trueD;
    float3 rp	= float3(xy, d);
    float3 l;	//Light accumulation value
   
    float  occ;
    float3 trueC = pow(tex2D(A26::LumSam, xy).rgb, 1.0 / 2.2);

	int sampl = SAMPLE_COUNT;   
	if(DYNA_SAMPL) sampl = 1 + ceil((1.0 - 0.33 * (trueC.r + trueC.g + trueC.b)) * max(SAMPLE_COUNT - 1, 0));
	float3 actSam; //Active reseviour sample
	float  resW; //Reseviour weight
	float  iW;	//Sample weights
    for(int i = 0; i < sampl; i++){
    	
    	d =  trueD;
    	int iLOD = 0;
    		   rp	  = float3(xy, d);
    	float3 minD	= 1.0;//rp;//float3(rp.xy, 1.0);
    	float3 maxD	= 0.0;//float3(rp.xy, 0.0);
    	float2 vec	 = float2(sin((6.28 * offset.r) + (i+1) * 6.28 / sampl), cos((6.28 * offset.r) + (i+1) * 6.28 / sampl));
    	float3 pixP	= float3(xy, trueD);
    	
 	   for(int ii = 2; ii <= ZNRY_MAX_LODS; ii++)
    	{
    		//Max shadow vector calculation
    		float3 compVec0	= normalize(rp - pixP + 0.000001);
    		float3 compVec1	= normalize(minD - pixP + 0.000001);
    		float3 compVec2	= normalize(maxD - pixP + 0.000001);
			//float3 compVec2	= normalize(maxD - pixP + 0.000001);			
			if(compVec0.z <= compVec1.z) {minD = rp;} 
			if(compVec0.z >= compVec1.z) {maxD = float3(rp.xy, rp.z + SHADOW_Z_THK);} 
    		
			//Ray vector and depth calculations
			float2 rd = offset.xy * abs(SHOW_MIPS - 1.0);
			//	   rd += (0.5 * surfN.xy);//Biases sampling group
   
    		rp.xy += (RAY_LENGTH * (vec + rd) * pow(2, ii)) / res;
    		if(rp.x > 1.0 || rp.y > 1.0) {break;}
    		if(rp.x < 0 || rp.y < 0) {break;}
    		
			d = tex2Dlod(A26::DepSam, float4(rp.xy, 0, floor(0.75 * iLOD))).r;
    		rp.z = d;
    		
    		
    		//Occlusion calculations
   		 float sh;
   		 if(SHADOW == 0) {sh = 1.0;}
   		 float3 eyeXY	 = eyePos(rp.xy, rp.z);
			float3 texXY	 = eyePos(xy, trueD);
   		 float3 shvMin	= normalize(minD - pixP);
   		 float3 shvMax	= normalize(maxD - pixP);
   		 float  shd	   = distance(rp, float3(xy, trueD));
   		 float  sb		= SHADOW_BIAS;
   		 bool   zd;		//= d >= (trueD + shd * shvMax.z);
   		 
			if(ENABLE_Z_THK) zd = d > (trueD + shd * shvMax.z + SHADOW_Z_THK) - sb;		 
   		 if(d <= (trueD + shd * shvMin.z) + sb || zd) {sh = 1.0;}
			
			//Diffuse Lighting calculations
			float3 col = tex2Dlod(A26::LumSam, float4(rp.xy, 0, iLOD)).rgb;
			float  smb = 1.0;
			
			if(BLOCK_SCATTER)
			{
				float3 nor = 2.0 * tex2Dlod(A26::NorDivSam, float4(rp.xy, 0, iLOD)).rgb - 1.0;
				float3 lv2 = normalize(eyePos(pixP.xy, pixP.z) - eyePos(rp.xy, rp.z) );
				smb = 4.0 * max(dot(nor, lv2), 0.0);
			}
				
			float  ed	 = 1.0 + pow(abs((DISTANCE_SCALE * distance(texXY, 0.0))), DISTANCE_POW) / f;
			float  cd	 = 1.0 + pow(abs((DISTANCE_SCALE * distance(eyeXY, texXY))), DISTANCE_POW) / f;
			float3 lv	 = normalize(eyePos(rp.xy, rp.z) - eyePos(pixP.xy, pixP.z));
			float  amb	= max(dot(surfN, lv), 0.0);
				   //sh 	+= length(col) / LODS;
			float  rfs	= 1.0;
			#if DO_REFLECT
				float3 vVec = normalize(NorEyePos(xy));
				float3 rVec = reflect(vVec, surfN);
				rfs = pow(0.5 + 0.5 * dot(lv, rVec), SPECULAR_POW);
			#endif
			
			col *= ed;
			float3 lAcc = smb * amb * (col / (cd *ed));//(pow(4.0, iLOD) / (4.0 * cd)) * 
			l += rfs * sh * lAcc * pow(1.0 + DIST_BIAS, iLOD);
			occ += amb * sh * saturate(length(col) / ed);//1.0 / ((ii + 1.0) - pow(distance(eyePos(minD.xy, minD.z), texXY) * f, 2.0));
			
			iW += (lAcc.r + lAcc.g + lAcc.b); //Accumulation for weighted sampling
			iLOD++;	
    	}
    	#if IMPORT_SAM
    		if(weighthash(abs(vec), resW, iW) == 1) {actSam = l; resW += iW;}
    		l = 0.0; actSam *= 1.0; iW = 0.0;
    	#endif
    }
    #if IMPORT_SAM
		l = actSam;
	#endif    
    l /= sampl / 16.0;
	l = pow(l / LODS, 1.0 / 2.2);// / (2.0 * pow(2.0, LODS))
	occ = saturate(4.0 * length(l + 0.01) * length(tex2D(A26::LumSam, xy)));//saturate(0.1 + occ);////saturate(2.0 * occ / (sampl * LODS));
	
	float4 result = float4(l, pow(occ, SHADOW_GAMMA));
		   //result = result / (result + 1.0);
	return max(0.001, result);//Prevents negative values from entering the denoiser
}

float3 tonemap(float3 input)
{
	input = max(0.0, input);
	if(TONEMAPPER == 0) input = ZNFilmic(input);
	if(TONEMAPPER == 1) input = SONYA7RIII(input);
	if(TONEMAPPER == 2) input = ACESFilm(input);
	if(TONEMAPPER == 3) input = ReinhardtJ(input);
	if(TONEMAPPER == 4) {return pow(input, 1.0 / 2.2);}
	if(TONEMAPPER == 5) input = pow(input, 0.5 * input + 1.0);
	input = pow(input, 1.0 / 2.2);
	return saturate(input);
}

float SampleAO(float2 xy, float SampleLength, float Thickness)
{
	return 1.0;
	/*
	float3 NormalVector	= 2f * tex2Dlod(A26::NorSam, float4(xy, 0, 0)).xyz - 1f;
	float  PixelDepth	  = ReShade::GetLinearizedDepth(xy);
	float3 PixelPos		= NorEyePos(xy);//GetEyePos(xy, PixelDepth);
	
	float Accumulate;
	#define SMP 8
	[loop]
	for(int i; i < SMP; i++)
	{
		float3 rVec = normalize(2f * hash3(float3(xy * RES, i)) - 1f);
			   rVec = SampleLength * normalize(rVec + NormalVector);
		
		float3 nPos = GetScreenPos(PixelPos + rVec);
		float  nDep = ReShade::GetLinearizedDepth(nPos.xy);
		
		if(nPos.z > nDep && nPos.z < nDep + Thickness) Accumulate++;//= distance(nPos.z, nDep);
	}
	return 1.0 - Accumulate / SMP;
	*/
}

float3 BlendGI(float3 input, float4 GI, float depth, float2 xy)
{
	float dAccp = 1.0 - DEPTH_MASK;
	input	   = pow(input, 2.2);
	float3 ICol = saturate(input);
		   ICol = lerp(normalize(ICol + COLORMAP_OFFSET) / 0.577, input, 0.5 + 0.5 * COLORMAP_BIAS);
		   
	float  ILum = (input.r + input.g + input.b) / 3.0;
	float3 iGI;
	GI.rgb	  = pow(GI.rgb, 2.2);
	GI.rgb	  *= 1.0 + (1.0 - DETINT_COLOR) * pow(DETINT_LEVEL, 7.0);
	GI.rgb	  /= exp(pow(15.0 * depth * DEPTH_MASK, 2.0));
	GI.a		=  lerp(1.0, GI.a, 1.0 / exp(pow(15.0 * depth * DEPTH_MASK, 2.0)));
	float GILum = (GI.r + GI.g + GI.b) / 3.0;
	
	
	if(REMOVE_DIRECTL == 0) {ILum = 0.0;}
	
	
		 if(DEBUG == 2) {input = saturate(INTENSITY * GI.rgb) * ICol;}
	else if(DEBUG == 3) {input = saturate(GI.rgb);}
	else if(DEBUG == 4) {input = saturate(pow(GI.a, 2.2));}
	else if(DEBUG == 1)
	{
		input	= 0.33;//normalize(input) / 0.577 * pow((input.r + input.g + input.b) / 3.0, 1.0 + AMBIENT_NEG);//Exposure
		input	= input * GI.a;
		iGI	  = INTENSITY * (GI.rgb);
		//input = GI.a * pow(lerp(1.0, GI.rgb, GILum), 3.0);
	}
	else if(DEBUG == 5) {input = ICol;}
	else
	{
		if(depth == 1.0) return - input / (input - 1.1);
		input	= normalize(input) / 0.577 * pow((input.r + input.g + input.b) / 3.0, 1.0 + AMBIENT_NEG);//Exposure
		input	= lerp(input, GI.a * input, SHADOW_INT);
		iGI	  = (INTENSITY * (GI.rgb - (ILum)) * ICol);
	}
	
	return iGI - input / (input - 1.1);
}


//Modified variance clamping for TAA denoising
float4 NbrClamp(sampler frame, float2 xy, float4 col, float deG)
{
	float2 res	 = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float2 mVec	= tex2D(motionSam, xy).xy;
	
	float4 m;
	float4 m1;
	float gam = 1.0;
	for(int i = 0; i <= 1; i++) for(int ii = 0; ii <= 1; ii++)
	{
		float2 coord = xy + TAA_SKIP * float2(i - 0.5, ii - 0.5) / res;
		float4 c 	= tex2Dlod(frame, float4(coord, 0, 1));
		float4 cb	= tex2Dlod(A26::PreFrm, float4(coord + mVec, 0, 1));
		
		c  = lerp(c, cb, FRAME_PERSIST * TAA_ERROR * round(1.0 - deG));//(max(exp((deG / 2.0) -deG), 0.0) + 0.2)
		m  += c;
		m1 += c*c;
	}
	float4 mu	  = m / 4.0;
	float4 sig	 = sqrt(m1 / 4.0 - mu * mu);
	float4 minC	= mu - sig * gam;
	float4 maxC	= mu + sig * gam;
	return clamp(col, minC, maxC);
}

//============================================================================================
//Buffer Definitions
//============================================================================================

//Saves LightMap and LODS
float4 LightMap(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	float2 res	   = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / 2.0;
    float2 hp		= 0.5 / res;
    float  offset	= 4.0;
	
    float3 acc =  tex2D(ReShade::BackBuffer, xy).rgb * 4.0;
		   acc += tex2D(ReShade::BackBuffer, xy - hp * offset).rgb;
	       acc += tex2D(ReShade::BackBuffer, xy + hp * offset).rgb;
	       acc += tex2D(ReShade::BackBuffer, xy + float2(hp.x, -hp.y) * offset).rgb;
	       acc += tex2D(ReShade::BackBuffer, xy - float2(hp.x, -hp.y) * offset).rgb;
		   acc /= 8.0;
	
	float  p 	= 2.2;
	float3 te	= acc;
		   te	= pow(te, p);	   	   
	
	te = saturate(saturation(te, LIGHTMAP_SAT));
	te = InvReinhardtJ(te);//-te / (te - 1.1);
	if(DO_BOUNCE)
	{
		float2 mVec	 =  tex2Dlod(motionSam, float4(xy, 0, 0)).xy;
		float3 GISec	=  tex2Dlod(A26::DualFrm, float4(mVec + xy, 0, 2)).rgb;
		te += ((te) * 5.0 * pow(SKY_COLOR, 2.2)) + lerp(normalize(te), te, 0.9) * GISec * TERT_INTENSITY;
		
	}
	
	
	
	return float4(max(0, te), 1.0);
}

//Generates Normal Buffer from depth, as described here: https://atyuwen.github.io/posts/normal-reconstruction/
float4 NormalBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 vc	  = NorEyePos(texcoord);
	
	float3 vx0	  = vc - NorEyePos(texcoord + float2(1, 0) / RES);
	float3 vy0 	 = vc - NorEyePos(texcoord + float2(0, 1) / RES);
	
	float3 vx1	  = -vc + NorEyePos(texcoord - float2(1, 0) / RES);
	float3 vy1 	 = -vc + NorEyePos(texcoord - float2(0, 1) / RES);
	
	float3 vx = abs(vx0.z) < abs(vx1.z) ? vx0 : vx1;
	float3 vy = abs(vy0.z) < abs(vy1.z) ? vy0 : vy1;
	
	float3 output = 0.5 + 0.5 * normalize(cross(vy, vx));
	
	return float4(output, 1.0);
}

float4 NormalSmooth(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	if(!SMOOTH_NORMALS) return float4(tex2D(A26::NorInSam, texcoord).xyz, 1.0);
	float3 cCol;// = tex2D(ReShade::BackBuffer, texcoord).rgb;
	float3 cNor = tex2D(A26::NorInSam, texcoord).xyz;
	float  cDep = ReShade::GetLinearizedDepth(texcoord);
	float  ang  = hash12(texcoord * RES);
	float  tw;
	#define ITER  4
	for(int i; i <= ITER; i++)
	{
		float2 npos = 15.0 * float2(sin(ang), cos(ang)) * hash12((texcoord + 0.5) * RES * (i + 1.0)) / RES;
		float3 rNor = tex2Dlod(A26::NorInSam, float4(texcoord + npos, 0, 0)).xyz;
		float3 rCol = tex2Dlod(A26::NorInSam, float4(texcoord + npos, 0, 0)).xyz;
		float  rDep = ReShade::GetLinearizedDepth(texcoord + npos);//tex2D(A26::DepSam, texcoord + npos).x;
		ang  += 6.28 / ITER;
		float wn  = pow(2.0 * max(dot(2.0 * rNor - 1.0, 2.0 * cNor - 1.0) - 0.5, 0.0), 1.0);//exp(min(dot(rNor, cNor) + 1.0, 1.0) * 12.0);
		float wd  = exp(-distance(rDep, cDep) / 0.00003);
			  tw += wn*wd;
		
		cCol += rCol * wn*wd;
	}
	if(tw < 0.00001) return float4(tex2D(A26::NorInSam, texcoord).xyz, 1.0);
	return float4(cCol / tw, 1.0);
}

//Renders GI to a texture for resolution scaling and blending
float4 RawGI(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	
	float2 bxy		= float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float2 MSOff	  = 1.0 * TAA_SAM_DST[FRAME_COUNT % 8] / (16.0 * bxy);
	float2 tempOff	= 1.0 * (1-STATIC_NOISE) * hash((1.0 + FRAME_COUNT % 128) * bxy);
		   tempOff	= floor(tempOff * RES) / RES;
		   
	float2 offset	= frac(0.4 + tempOff + texcoord * (bxy / (512 / ZNRY_RENDER_SCL)));
	float3 noise	 = tex2D(A26::NoiseSam, offset).rgb;
	
	float4 GI		= float4(DAMPGI(MSOff + texcoord, 3.0 * (0.5 - noise.xy)));
		   GI		= saturate(GI + 0.125 * (noise.r - 0.5));
	float  AO		= 1;
	if(DO_AO) AO	 = SampleAO(texcoord, noise.r, 0.001);
	return AO * (GI / (GI + 1.0));
	
}

float4 NormalDiv(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	return tex2Dlod(A26::NorSam, float4(texcoord, 0, 0));	
}
//Bilateral Upscaler
float4 UpFrame(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	if(DONT_SPATIAL) return tex2D(A26::GISam, texcoord);
	float4 cCol;// = tex2D(ReShade::BackBuffer, texcoord).rgb;
	float3 cNor = 2.0 * tex2D(A26::NorSam, texcoord).xyz - 1.0;//ReShade::GetLinearizedDepth(texcoord);
	float  cDep = ReShade::GetLinearizedDepth(texcoord);
	float  ang  = 6.28 * hash12(texcoord * RES * (FRAME_COUNT % 128));
	float  tw;
	for(int i; i <= UPSCALE_ITER; i++)
	{
		float2 npos = float2(sin(ang), cos(ang)) ;//hash12((texcoord + 0.5) * RES * (i + 1.0)) / RES;
			   npos = (1.0 / ZNRY_RENDER_SCL) * npos * (1.0 + i) / RES;
		float3 rNor = 2.0 * tex2Dlod(A26::BilaSam, float4(texcoord + npos, 0, 0)).xyz - 1.0;
		float  rDep = tex2Dlod(A26::PreLumin, float4(texcoord + npos, 0, 0)).r;
		float4 rCol = tex2Dlod(A26::GISam, float4(texcoord + npos, 0, 0));
		ang  += 12.56 / UPSCALE_ITER;
		float nw  = pow(max(dot(rNor, cNor) - 0.5, 0), 4.0);
		float dw  = exp(-distance(eyePos(texcoord, rDep), eyePos(texcoord, cDep)) * 3.0);
			  tw += nw * dw;
		
		cCol += rCol * nw * dw;
	}
	if(tw < 0.0001) return tex2D(A26::GISam, texcoord);
	return cCol / tw;
}

//Temporal Denoisers
float4 CurrentFrame(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 CF	  = tex2D(A26::UpSam, texcoord);
	float2 mVec	= tex2D(motionSam, texcoord).xy;
	float3 nor	 = tex2D(A26::NorSam, texcoord).rgb;
	float3 CC	  = tex2D(ReShade::BackBuffer, texcoord).rgb;
	float  CD	  = ReShade::GetLinearizedDepth(texcoord);//saturate(CC.r * 0.2126 + CC.g * 0.7152 + CC.b * 0.0722);
	float4 PF	  = tex2D(A26::PreFrm, texcoord + mVec);
	float  PD	  = tex2D(A26::PreLumin, texcoord + mVec).r;
	
	float  DeGhostMask = 1.0 - saturate(pow(abs(PD / CD), 12.0) + 0.02);//pow(1.0 - saturate(distance(CD, PD)), 1.0);
	CF = lerp(PF.rgba, CF, (1.0 - FRAME_PERSIST));
	CF = NbrClamp(A26::UpSam, texcoord, CF, DeGhostMask);
	return float4(CF);
}

float4 DualFrame(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 CF	  = tex2D(A26::CurFrm, texcoord);
	float2 mVec	= tex2D(motionSam, texcoord).xy;
	float3 nor	 = tex2D(A26::NorSam, texcoord).rgb;
	float3 CC	  = tex2D(ReShade::BackBuffer, texcoord).rgb;
	float  CD	  = ReShade::GetLinearizedDepth(texcoord);//saturate(CC.r * 0.2126 + CC.g * 0.7152 + CC.b * 0.0722);
	float4 PF	  = tex2D(A26::PreFrm, texcoord + mVec);
	float  PD	  = tex2D(A26::PreLumin, texcoord + 1.0 * mVec).r;
	
	float  DeGhostMask = 1.0 - saturate(pow(abs(PD / CD), 12.0) + 0.02);//pow(1.0 - saturate(distance(CD, PD)), 1.0);
	if(DEBUG == 6) {return DeGhostMask;}
	CF = lerp(PF.rgba, CF, (1.0 - FRAME_PERSIST));
	CF = NbrClamp(A26::CurFrm, texcoord, CF, DeGhostMask);
	return float4(CF);
}

float DrawDepth(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	return ReShade::GetLinearizedDepth(texcoord);
}

float DrawLum(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 c   = tex2D(ReShade::BackBuffer, texcoord).rgb;
	return saturate(c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722);
}

float4 PreviousFrame(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	
	return tex2D(A26::CurFrm, texcoord);
}



//============================================================================================
//Main
//============================================================================================



float3 DAMPRT(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;
		   input = saturate(input);
	float4 GI;
	if(DONT_DENOISE) GI	= saturate(tex2Dlod(A26::UpSam, float4(texcoord, 0, 0)));
	else 			GI	= tex2Dlod(A26::DualFrm, float4(texcoord, 0, 0));
	float			depth = ReShade::GetLinearizedDepth(texcoord);
	if(depth > 0.99) return input;
	GI = 1.1 * -GI / (GI - 1.1);
	
	input = BlendGI(input, GI, depth, texcoord);
	float3 AmbientFog = pow(SKY_COLOR, 2.2) / exp(pow(15.0 * depth * DEPTH_MASK, 2.0));
	input = tonemap(input * (1.0 + 5.0 * AmbientFog));
	
	if(DEBUG == 6) {input = GI.rgb;}
	else if(DEBUG == 7) {input = tex2D(A26::NorSam, texcoord).rgb;}
	else if(DEBUG == 8) {input = tex2D(A26::DepSam, texcoord).r;}
	else if(DEBUG == 9) {input = tex2D(A26::LumSam, texcoord).rgb;}
	return input;
}

technique ZN_DAMPRT_A26 <
    ui_label = "DAMP RT A26-3-1";
    ui_tooltip ="Zentient DAMP RT - by Zenteon\n" 
				"The sucessor to SDIL, a much more efficient and accurate GI approximation";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = LightMap;
		RenderTarget = A26::LumTex;
	}
	
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = DrawDepth;
		RenderTarget = A26::BufTex;
	}
	
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalBuffer;
		RenderTarget = A26::NorInTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalSmooth;
		RenderTarget = A26::NorTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalDiv;
		RenderTarget = A26::NorDivTex;
	}

	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalDiv;
		RenderTarget = A26::BilaTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = RawGI;
		RenderTarget = A26::GITex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = UpFrame;
		RenderTarget = A26::UpscaleTex;
	}
	
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = CurrentFrame;
		RenderTarget = A26::CurTex;
	}
	
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = DualFrame;
		RenderTarget = A26::DualTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = DrawDepth;
		RenderTarget = A26::PreLuminTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = DAMPRT;
	}
	
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PreviousFrame;
		RenderTarget = A26::PreTex;
	}
	
}
