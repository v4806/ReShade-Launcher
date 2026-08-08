//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 1.6 - User Interface

static const bool bTest0 = 0;
static const bool bTest1 = 1;
static const bool UI_TemporalReSTIRGI = 0;

#if C_RT_UI_DIFFICULTY == 1

uniform int Hints <
	ui_text = "1- 配合运动估计着色器使用，例如：\n"

	          "  A: 推荐 - ReShade_MotionVectors\n"
	          "  B: qUINT_MotionVectors\n"
	          "  C: DRME\n"
	          "  D: iMMERSE Launchpad\n"
	          "  E: DH_UBER_MOTION\n"
	          "2- 修改预处理器设置前请先阅读提示说明。\n"
	          "3- 祝您使用愉快！:)";

	ui_category = "提示 - 请阅读以获得最佳效果。";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

//Reflection
uniform bool UI_ReflectionEnable <
	ui_label = "启用反射";
	ui_category = "反射";
	ui_category_toggle = true;
> = 1;

uniform float UI_ReflectionRayDepth <
	ui_label = "表面厚度";
	ui_type = "slider";
	ui_category = "反射";
	ui_category_closed = true;
	ui_min = 0.05;
	ui_max = 10;
> = 3;


uniform uint UI_ReflectionRaySteps <
	ui_label = "光线精度";
	ui_type = "slider";
	ui_category = "反射";
	ui_tooltip = "提高精度但降低性能。";
	ui_category_closed = true;
	ui_min = 1;
	ui_max = 24;
> = 20;

uniform uint UI_SampleCount <
	ui_label = "采样数";
	ui_type = "slider";
	ui_category = "反射";
	ui_tooltip = "提高细节和稳定性但降低性能。";
	ui_category_closed = true;
	ui_min = 1;
	ui_max = 4;
> = 1;

uniform float UI_SpecularIntensity <
	ui_label = "强度";
	ui_type = "slider";
	ui_category = "反射";
> = 0.5;

uniform float fov <
	ui_label = "视场角";
	ui_type = "slider";
	ui_category = "反射";
	ui_tooltip = "如果反射看起来异常请调整此值。";
	ui_min = 60;
	ui_max = 120;
> = 70;

uniform float UI_Roughness <
	ui_label = "粗糙度";
	ui_type = "slider";
	ui_category = "反射";
	ui_category_closed = true;
	ui_min = 0.0;
	ui_max = 0.999;
> = 0.4;

uniform bool UI_RainRoughness <
	ui_label           = "雨天模式";
	ui_category        = "反射";
	ui_category_closed = true;
	ui_tooltip         = "降低地面粗糙度以模拟雨天天气，\n"
	                     "同时保持其他表面的粗糙度不变。";
> = 0;

//Diffuse Illumination
uniform bool UI_GIAOEnable <
	ui_label = "启用漫反射光照";
	ui_category = "漫反射光照";
	ui_category_toggle = true;
> = 1;

uniform bool UI_ReuseSamples <
	ui_label    = "启用 ReSTIR-GI";
	ui_type     = "radio";
	ui_category = "漫反射光照";
	ui_tooltip  = "降低噪点并提高精度但降低性能\n";
	ui_category_closed = true;
> = 0;

uniform int UI_RTColorSubCategory <
	ui_label = " ";
	ui_text = "=== 颜色调整 ===";
	ui_category = "漫反射光照";
	ui_type = "radio";
> = 0;

uniform float UI_Exposure <
	ui_type = "slider";
	ui_label = "曝光";
	ui_category = "漫反射光照";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 4;
> = 1;

uniform float UI_Saturation <
	ui_type = "slider";
	ui_label = "饱和度";
	ui_category = "漫反射光照";
	ui_min = 0;
	ui_max = 2;
> = 1;

uniform int UI_GIMaskSubCategory <
	ui_label = " ";
	ui_text = "=== 光照贴图遮罩 ===";
	ui_category = "漫反射光照";
	ui_type = "radio";
> = 0;

uniform float UI_MaskDirect <
	ui_type     = "slider";
	ui_label    = "排除直接光源";
	ui_category = "漫反射光照";
	ui_tooltip  = "直接光源（太阳、灯具等）将不会影响漫反射光照。\n"
	              "较低的值可以更敏感地检测直接光源。";
	ui_min      = 0.5;
> = 1;

uniform bool UI_MaskSky <
	ui_label    = "从光追中排除天空";
	ui_category = "漫反射光照";
	ui_tooltip  = "启用后天空将不会影响光线追踪光照。";
> = 1;

uniform int UI_DiffuseRaySubCategory <
	ui_label = " ";
	ui_text = "=== 光线追踪 ===";
	ui_category = "漫反射光照";
	ui_type = "radio";
> = 0;

uniform uint UI_RaySteps <
	ui_label = "光线精度";
	ui_type = "slider";
	ui_category = "漫反射光照";
	ui_tooltip = "提高精度但降低性能。";
	ui_category_closed = true;
	ui_min = 1;
	ui_max = 64;
> = 64;

uniform float UI_RayLength <
	ui_label = "光线长度";
	ui_type = "slider";
	ui_category = "漫反射光照";
	ui_tooltip = "增加光线长度但降低精度。";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 1;
> = 1.0;

uniform float UI_RayDepth <
	ui_label = "表面厚度";
	ui_type = "slider";
	ui_category = "漫反射光照";
	ui_tooltip = "估计表面厚度的乘数";
	ui_category_closed = true;
	ui_min = 0.05;
	ui_max = 10;
> = 3;

uniform bool UI_ThicknessEstimation <
	ui_label = "估计厚度";
	ui_category = "漫反射光照";
	ui_tooltip = "用于改善来自微小物体的光照";
	ui_category_closed = true;
> = 0;

//Ambient Occlusion
uniform float UI_AORadius <
	ui_label = "半径";
	ui_type = "slider";
	ui_category = "环境光遮蔽（需启用漫反射光照）";
	ui_category_closed = true;
	ui_tooltip = "查找遮挡的最大距离。";
> = 0.25;

uniform float UI_AOIntensity <
	ui_label = "强度";
	ui_type = "slider";
	ui_category = "环境光遮蔽（需启用漫反射光照）";
> = 0.5;

//Ambient Lighting
uniform float UI_SkyColorIntensity <
	ui_type = "slider";
	ui_label = "天空颜色强度";
	ui_category = "环境光照";
	ui_min = 0;
	ui_max = 1;
> = 0;

uniform float3 UI_SkyColorTint <
	ui_type = "color";
	ui_label = "色调";
	ui_category = "环境光照";
> = float3(1.0, 1.0, 1.0);

uniform bool UI_SkyColorMode <
	ui_type = "radio";
	ui_label = "自动检测天空颜色";
	ui_category = "环境光照";
> = 1;

uniform float UI_AmbientLight <
	ui_label = "环境光强度";
	ui_type  = "slider";
	ui_category = "环境光照";
> = 1.0;

//Normal Filtering
uniform float UI_BumpStrength <
	ui_label = "凹凸贴图强度";
	ui_type = "slider";
	ui_category = "法线过滤";
	ui_tooltip = "为光照添加微小细节。";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.4;

uniform int UI_SmoothNormals <
	ui_label = "平滑法线质量";
	ui_type  = "slider";
	ui_category = "法线过滤";
	ui_min = 0;
	ui_max = 10;
> = 3;

uniform float UI_ResolutionScale <
	ui_type = "slider";
	ui_category = "性能";
	ui_label = "分辨率缩放";
	ui_min  = 0.333333;
> = 0.5;

//Denoiser (Advanced)
uniform float UI_MVErrorT <
	ui_label = "运动矢量\n容错度";
	ui_type = "slider";
	ui_category = "降噪器（高级）";
	ui_tooltip = "较低的值可减少鬼影\n"
	             "较高的值可增加稳定性\n"
	             "如果游戏图像不稳定（如\n"
	             "严重的胶片颗粒），请适当增加此值。";
	ui_category_closed = true;
	//hidden = true;
	ui_min = 0;
	ui_max = 0.1;
> = 0.03;

//Denoiser (Advanced)
uniform int UI_FilterQuality <
	ui_label = "过滤质量";
	ui_type  = "combo";
	ui_items = "中等\0高\0";
	ui_category = "降噪器（高级）";
	ui_category_closed = true;
> = 1;

uniform int UI_MaxFrames <
	ui_label = "历史长度";
	ui_type = "slider";
	ui_category = "降噪器（高级）";
	ui_tooltip = "较高的值可增加平滑度\n"
				 "同时保留更多细节。";
	ui_category_closed = true;
	//hidden = true;
	ui_min = 1;
	ui_max = 64;
> = 64;

uniform float UI_Sthreshold <
	ui_label = "空间降噪器\n阈值";
	ui_type = "slider";
	ui_category = "降噪器（高级）";
	ui_tooltip = "不建议修改！！\n顺便说一下，较低 = 更少噪点，较高 = 更多细节。";
	ui_category_closed = true;
	//hidden = true;
	ui_min = 0.001;
	ui_max = 4;
> = 1;

//Masking
uniform float UI_DepthFade <
	ui_label = "深度衰减";
	ui_type = "slider";
	ui_category = "遮罩";
	ui_category_closed = true;
	ui_tooltip = "较高的值会降低远处物体的强度。\n"
				 "可减少与游戏内雾效的混合问题。";
	ui_min = 0;
	ui_max = 1;
> = 0.75;

uniform int UI_FadeMode <
	ui_label = "衰减模式";
	ui_type = "combo";
	ui_category = "遮罩";
	ui_tooltip = "指数：适用于具有物理和体积雾的现代游戏\n"
	             "线性：适用于具有简单和假雾的老游戏";
	ui_items = "指数\0线性\0";
#if __RENDERER__ >= 0xb000
> = 0;
#else
> = 1;
#endif

uniform uint UI_Debug <
	ui_type = "combo";
	ui_label = "调试模式";
	ui_items = "无\0"                                          //0
	           "光照\0光照贴图\0"                            //1-2
	           "深度\0法线\0累积\0"                   //3-4-5
	           //"Roughness\0Variance\0Motion\0ReSTIR\0Thickness\0"//6-7-8   for DEV_MODE only
			;
	ui_category = "其他";
#ifndef DevMode
	ui_max = 5;
#endif
	ui_category_closed = true;
> = 0;

uniform int Preprocessordefinitionstooltip<
	ui_text = "C_RT_UI_DIFFICULTY:\n0为简易设置，1可访问更多设置。\n\n"

	          "C_RT_USE_LAUNCHPAD_MOTIONS:\n如果您想将CompleteRT与iMMERSE Launchpad的运动矢量配合使用，请将此设为1。";

	ui_category = "预处理器设置说明";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

#else //EZ Mode

uniform int Hints <
	ui_text = "1- 配合运动估计着色器使用，例如：\n"

	          "  A: 推荐 - ReShade_MotionVectors\n"
	          "  B: qUINT_MotionVectors\n"
	          "  C: DRME\n"
	          "  D: iMMERSE Launchpad\n"
	          "  E: DH_UBER_MOTION\n"
	          "2- 修改预处理器设置前请先阅读提示说明。\n"
	          "3- 祝您使用愉快！:)";

	ui_category = "提示 - 请阅读以获得最佳效果。";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

uniform bool UI_ReflectionEnable <
	ui_label = "启用反射";
> = 1;

uniform bool UI_GIAOEnable <
	ui_label = "启用漫反射光照";
> = 1;

uniform int UI_QualityPreset <
	ui_type = "combo";
	ui_label = "质量预设";
	ui_items =
"极低\0"
"低\0"
"中等\0"
"高\0"
"极高\0";
> = 1;

uniform float UI_BumpStrength <
	ui_label = "凹凸贴图强度";
	ui_type = "slider";
	ui_tooltip = "为光照添加微小细节。";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.4;

uniform float UI_Roughness <
	ui_label = "粗糙度";
	ui_type = "slider";
	ui_category = "反射";
	ui_category_closed = true;
	ui_tooltip = "反射的模糊程度。";
	ui_min = 0.0;
	ui_max = 0.999;
> = 0.4;

uniform bool UI_RainRoughness <
	ui_label           = "雨天模式";
	ui_category        = "反射";
	ui_category_closed = true;
	ui_tooltip         = "降低地面粗糙度以模拟雨天天气，\n"
	                     "同时保持其他表面的粗糙度不变。";
> = 0;

uniform float UI_SpecularIntensity <
	ui_label           = "强度";
	ui_type            = "slider";
	ui_category        = "反射";
	ui_category_closed = true;
	ui_tooltip         = "反射的强度。";
> = 0.5;

uniform float UI_AORadius <
	ui_label = "环境光遮蔽半径";
	ui_type = "slider";
	ui_category = "环境光遮蔽";
	ui_category_closed = true;
	ui_tooltip = "查找遮挡的最大距离。";
> = 0.25;

uniform float UI_AOIntensity <
	ui_label = "环境光遮蔽强度";
	ui_type = "slider";
	ui_category = "环境光遮蔽";
	ui_category_closed = true;
> = 0.5;

uniform float UI_AmbientLight <
	ui_label = "环境光强度";
	ui_type  = "slider";
	ui_category = "环境光遮蔽";
> = 1.0;

uniform float UI_Exposure <
	ui_type = "slider";
	ui_label = "全局光照曝光";
	ui_category = "漫反射光照";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 4;
> = 1;

uniform float UI_Saturation <
	ui_type = "slider";
	ui_label = "全局光照饱和度";
	ui_category = "漫反射光照";
	ui_category_closed = true;
	hidden = true;
	ui_min = 0;
	ui_max = 2;
> = 1;

uniform float UI_MaskDirect <
	ui_type     = "slider";
	ui_label    = "排除直接光源";
	ui_category = "漫反射光照";
	ui_category_closed = true;
	ui_tooltip  = "直接光源（太阳、灯具等）将不会影响漫反射光照。\n"
	              "较低的值可以更敏感地检测直接光源。";
	ui_min      = 0.5;
> = 1;

uniform bool UI_MaskSky <
	ui_label    = "从光追中排除天空";
	ui_category = "漫反射光照";
	ui_category_closed = true;
	ui_tooltip  = "启用后天空将不会影响光线追踪光照。";
> = 1;

uniform float UI_SkyColorIntensity <
	ui_type = "slider";
	ui_label = "天空颜色强度";
	ui_category = "漫反射光照";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 1;
> = 0;


uniform float UI_DepthFade <
	ui_label = "深度衰减";
	ui_type = "slider";
	ui_category = "遮罩";
	ui_tooltip = "较高的值会降低远处物体的强度。\n"
				 "可减少与游戏内雾效的混合问题。";
	ui_min = 0;
	ui_max = 1;
> = 0.75;

uniform uint UI_Debug <
	ui_type = "combo";
	ui_label = "调试模式";
	ui_items = "无\0"                                      // 0
	           "光照\0光照贴图\0"                        //1 -2
	           "深度\0法线\0"                             //3-4
	           //"Accumulation\0Roughness\0Variance\0Motion\0ReSTIR\0Thickness\0"      //6-7-8   for DEV_MODE only
;	ui_category = "调试";
	ui_category_closed = true;
	ui_max = 4;
> = 0;

uniform int Preprocessordefinitionstooltip<
	ui_text = "C_RT_UI_DIFFICULTY:\n0为简易设置，1可访问更多设置。\n\n"

	          "C_RT_USE_LAUNCHPAD_MOTIONS:\n如果您想将CompleteRT与iMMERSE Launchpad的运动矢量配合使用，请将此设为1。";

	ui_category = "预处理器设置说明";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

#endif
