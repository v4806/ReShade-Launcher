//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 0.9.3 - UI

//license
//CC0 ^_^


#if UI_DIFFICULTY == 1

uniform int Hints<
	ui_text = "如果需要，可以将 UI_DIFFICULTY 设为 0 来简化界面。\n"
			  "高级分类包含一些不必要的选项，\n"
			  "如果修改不当可能会破坏着色器的效果。\n\n"
			  "请配合 ReShade_MotionVectors 使用四分之一分辨率。\n"
			  "当游戏使用时间滤镜（TAA、DLSS2、FSR2、TAAU、TSR 等）时，"
			  "使用更高分辨率的运动向量只会使效果更差。";

	ui_category = "提示 - 请阅读以获得良好效果";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

#if !NGL_HYBRID_MODE
uniform int GI <
	ui_type = "combo";
	ui_label = "模式";
	ui_items = "反射\0GI\0";
> = 1;
#endif

uniform bool UseCatrom <
	ui_label = "使用 Catrom 重采样";
	ui_tooltip = "使用 Catrom 重采样进行放大和重投影。较慢但更清晰。";
> = 0;

uniform bool SharpenGI <
	ui_label = "锐化 GI";
	ui_tooltip = "（无性能影响）进一步提高边缘清晰度。不过请先尝试 Catrom 重采样。";
> = 1;

uniform float fov <
	ui_label = "视场角";
	ui_type = "slider";
	ui_category = "光线追踪";
	ui_tooltip = "根据游戏的视场角进行设置。";
	ui_min = 50;
	ui_max = 120;
> = 70;

uniform float BUMP <
	ui_label = "凹凸贴图";
	ui_type = "slider";
	ui_category = "光线追踪";
	ui_tooltip = "为光照添加细微细节。";
	ui_min = 0.0;
	ui_max = 1;
> = 1;

uniform float roughness <
	ui_label = "粗糙度";
	ui_type = "slider";
	ui_category = "光线追踪";
	ui_tooltip = "反射的模糊程度。";
	ui_min = 0.0;
	ui_max = 0.999;
> = 0.4;

uniform bool TemporalRefine <
	ui_label = "时间精炼（实验性）";
	ui_category = "光线追踪（高级）";
	ui_tooltip = "实验性功能！可能会出现问题\n"
				 "降低（表面深度）并增加（步长抖动）\n"
				 "然后启用此选项以获得更准确的反射/GI。";
	ui_category_closed = true;
> = 0;

uniform float RAYINC <
	ui_label = "光线增量";
	ui_type = "slider";
	ui_category = "光线追踪（高级）";
	ui_tooltip = "以牺牲精度为代价增加光线长度。";
	ui_category_closed = true;
	ui_min = 1;
	ui_max = 2;
> = 2;

uniform uint UI_RAYSTEPS <
	ui_label = "最大步数";
	ui_type = "slider";
	ui_category = "光线追踪（高级）";
	ui_tooltip = "以牺牲性能为代价增加光线长度。";
	ui_category_closed = true;
	ui_min = 1;
	ui_max = 32;
> = 16;

uniform float RAYDEPTH <
	ui_label = "表面深度";
	ui_type = "slider";
	ui_category = "光线追踪（高级）";
	ui_tooltip = "以牺牲精度为代价获得更好的一致性。";
	ui_category_closed = true;
	ui_min = 0.05;
	ui_max = 10;
> = 2;

uniform float MVErrorTolerance <
	ui_label = "运动向量\n容错度";
	ui_type = "slider";
	ui_category = "降噪器（高级）";
	ui_tooltip = "较低的值对运动估计错误更敏感。\n"
				 "因此更依赖空间滤波\n"
				 "而不是时间累积";
	ui_category_closed = true;
	ui_step = 0.01;
> = 0.95;

uniform int MAX_Frames <
	ui_label = "历史长度";
	ui_type = "slider";
	ui_category = "降噪器（高级）";
	ui_tooltip = "较高的值增加平滑度\n"
				 "同时保留更多细节。但会\n"
				 "引入更多时间延迟。";
	ui_category_closed = true;
	ui_min = 8;
	ui_max = 64;
> = 64;

uniform float Sthreshold <
	ui_label = "空间降噪器\n阈值";
	ui_type = "slider";
	ui_category = "降噪器（高级）";
	ui_tooltip = "以牺牲细节为代价减少噪点。";
	ui_category_closed = true;
> = 0.003;

static const bool HLFix = 1;

uniform float EXP <
	ui_label = "菲涅尔指数";
	ui_type = "slider";
	ui_category = "混合选项";
	ui_tooltip = "光亮材质的混合强度。";
	ui_min = 1;
	ui_max = 10;
> = 4;

uniform float AO_Radius_Background <
	ui_label = "图像 AO";
	ui_type = "slider";
	ui_category = "混合选项";
	ui_tooltip = "图像的 AO 半径。";
> = 1;

uniform float AO_Radius_Reflection <
	ui_label = "GI AO";
	ui_type = "slider";
	ui_category = "混合选项";
	ui_tooltip = "GI 的 AO 半径。";
> = 1;

uniform float AO_Intensity <
	ui_label = "AO 强度";
	ui_type = "slider";
	ui_category = "混合选项";
	ui_tooltip = "AO 衰减曲线";
> = 1;

uniform float depthfade <
	ui_label = "深度淡化";
	ui_type = "slider";
	ui_category = "混合选项";
	ui_tooltip = "较高的值会降低远处物体的强度。\n"
				 "减少与游戏内雾效的混合问题。";
	ui_min = 0;
	ui_max = 1;
> = 0.8;

uniform bool LinearConvert <
	ui_type = "radio";
	ui_label = "sRGB 转线性";
	ui_category = "颜色管理";
	ui_tooltip = "如果游戏是 HDR 则禁用";
	ui_category_closed = true;
> = 1;



uniform float2 SatExp <
	ui_type = "slider";
	ui_label = "饱和度\n& 曝光";
	ui_category = "颜色管理";
	ui_tooltip = "左侧滑块是饱和度，右侧是曝光。";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 2;
> = float2(1,1);

uniform uint debug <
	ui_type = "combo";
	ui_items = "无\0光照\0深度\0法线\0累积\0粗糙度贴图\0";
	ui_category = "额外";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 5;
> = 0;

uniform float SkyDepth <
	ui_type = "slider";
	ui_label = "天空遮罩深度";
	ui_tooltip = "视为天空并从计算中排除的最小深度。";
	ui_category = "额外";
	ui_category_closed = true;
> = 0.99;

uniform int Credits<
	ui_text = "感谢 Lord of Lunacy、Leftfarian 和其他开发者的帮助。<3\n"
			  "感谢 Alea 和 MassiHancer 的测试。<3\n\n"

			  "致谢：\n"
			  "感谢 Crosire 的 ReShade。\n"
			  "https://reshade.me/\n\n"

			  "感谢 Jakob 的 DRME。\n"
			  "https://github.com/JakobPCoder/ReshadeMotionEstimation\n\n"

			  "从 qUINT_SSR 学到了很多。感谢 Pascal Gilcher。\n"
			  "https://github.com/martymcmodding/qUINT\n\n"

			  "也从 DH_RTGI 学到了很多。感谢 Demien Hambert。\n"
			  "https://github.com/AlucardDH/dh-reshade-shaders\n\n"

			  "感谢 Nvidia 的《光线追踪精粹 II》中的 ReBlur\n"
			  "https://link.springer.com/chapter/10.1007%2F978-1-4842-7185-8_49\n\n"

			  "感谢 Radegast 的 Unity Sponza 测试场景。\n"
			  "https://mega.nz/#!qVwGhYwT!rEwOWergoVOCAoCP3jbKKiuWlRLuHo9bf1mInc9dDGE\n\n"

			  "感谢 Timothy Lottes 和 AMD 的色调映射器和逆色调映射器。\n"
			  "https://gpuopen.com/learn/optimized-reversible-tonemapper-for-resolve/\n\n"

			  "感谢 Eric Reinhard 的亮度色调映射器及其逆运算。\n"
			  "https://www.cs.utah.edu/docs/techreports/2002/pdf/UUCS-02-001.pdf\n\n"

			  "感谢 sujay 的噪声函数。从 ShaderToy 移植。\n"
			  "https://www.shadertoy.com/view/lldBRn";

	ui_category = "致谢";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

uniform int Preprocessordefinitionstooltip<
	ui_text = "RESOLUTION_SCALE_ : 较低的值速度更快但可能稍微模糊。\n\n"

			  "SMOOTH_NORMALS : 0 为禁用，1 为低质量快速，2 为高质量较慢，3 为摄影模式非常慢。\n\n"

			  "UI_DIFFICULTY : 0 为简单模式，1 为 ReShade 高手模式。";//\n\n"

			  //"NGL_HYBRID_MODE : 0 表示一次只能使用一个效果。要么 GI 要么反射。1 表示同时拥有两种效果但更慢（不到 2 倍）";
	ui_category = "预处理器定义提示";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;
#endif

#if UI_DIFFICULTY == 0

uniform int Hints<
	ui_text = "如果想访问更多设置，请将 UI_DIFFICULTY 设为 1。\n"
			  "高级分类包含一些不必要的选项，\n"
			  "如果修改不当可能会破坏着色器的效果。\n\n"
			  "请配合 ReShade_MotionVectors 使用四分之一分辨率。\n"
			  "当游戏使用时间滤镜（TAA、DLSS2、FSR2、TAAU、TSR 等）时，"
			  "使用更高分辨率的运动向量只会使效果更差。";
	ui_category = "提示 - 请阅读！";
	ui_label = " ";
	ui_type = "radio";
>;

#if !NGL_HYBRID_MODE
uniform int GI <
	ui_type = "combo";
	ui_label = "模式";
	ui_items = "反射\0GI\0";
> = 1;
#endif

uniform int UI_QUALITY_PRESET <
	ui_type = "combo";
	ui_label = "质量预设";
	ui_items = "低 (16)\0中 (64)\0高 (160)\0非常高 (320)\0极致 (500)\0";
> = 1;

uniform float BUMP <
	ui_label = "凹凸贴图";
	ui_type = "slider";
	ui_category = "光线追踪";
	ui_tooltip = "为光照添加细微细节。";
	ui_min = 0.0;
	ui_max = 1;
> = 0.5;

uniform float roughness <
	ui_label = "粗糙度";
	ui_type = "slider";
	ui_category = "光线追踪";
	ui_tooltip = "反射的模糊程度。";
	ui_min = 0.0;
	ui_max = 0.999;
> = 0.4;

uniform float EXP <
	ui_label = "反射边缘淡化";
	ui_type = "slider";
	ui_category = "混合选项";
	ui_min = 1;
	ui_max = 10;
> = 4;

uniform float AO_Intensity <
	ui_label = "AO 强度";
	ui_type = "slider";
	ui_category = "混合选项";
	ui_tooltip = "环境光遮蔽衰减曲线";
> = 0.67;

uniform float depthfade <
	ui_label = "深度淡化";
	ui_type = "slider";
	ui_category = "混合选项";
	ui_tooltip = "较高的值会降低远处物体的强度。\n"
				 "减少与游戏内雾效的混合问题。";
	ui_min = 0;
	ui_max = 1;
> = 0.8;

uniform bool LinearConvert <
	ui_type = "radio";
	ui_label = "sRGB 转线性";
	ui_category = "颜色管理";
	ui_tooltip = "如果游戏是 HDR 则禁用";
	ui_category_closed = true;
> = 1;

uniform float2 SatExp <
	ui_type = "slider";
	ui_label = "饱和度 || 曝光";
	ui_category = "颜色管理";
	ui_tooltip = "左侧滑块是饱和度，右侧是曝光。";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 4;
> = float2(1,1);

uniform uint debug <
	ui_type = "combo";
	ui_items = "无\0光照\0深度\0法线\0累积\0粗糙度贴图\0";
	ui_category = "额外";
	ui_category_closed = true;
	ui_min = 0;
	ui_max = 4;
> = 0;

uniform int Credits<
	ui_text = "感谢 Lord of Lunacy、Leftfarian 和其他开发者的帮助。<3\n"
			  "感谢 Alea 和 MassiHancer 的测试。<3\n\n"

			  "致谢：\n"
			  "感谢 Crosire 的 ReShade。\n"
			  "https://reshade.me/\n\n"

			  "感谢 Jakob 的 DRME。\n"
			  "https://github.com/JakobPCoder/ReshadeMotionEstimation\n\n"

			  "从 qUINT_SSR 学到了很多。感谢 Pascal Gilcher。\n"
			  "https://github.com/martymcmodding/qUINT\n\n"

			  "也从 DH_RTGI 学到了很多。感谢 Demien Hambert。\n"
			  "https://github.com/AlucardDH/dh-reshade-shaders\n\n"

			  "感谢 Nvidia 的《光线追踪精粹 II》中的 ReBlur\n"
			  "https://link.springer.com/chapter/10.1007%2F978-1-4842-7185-8_49\n\n"

			  "感谢 Radegast 的 Unity Sponza 测试场景。\n"
			  "https://mega.nz/#!qVwGhYwT!rEwOWergoVOCAoCP3jbKKiuWlRLuHo9bf1mInc9dDGE\n\n"

			  "感谢 Timothy Lottes 和 AMD 的色调映射器和逆色调映射器。\n"
			  "https://gpuopen.com/learn/optimized-reversible-tonemapper-for-resolve/\n\n"

			  "感谢 Eric Reinhard 的亮度色调映射器及其逆运算。\n"
			  "https://www.cs.utah.edu/docs/techreports/2002/pdf/UUCS-02-001.pdf\n\n"

			  "感谢 sujay 的噪声函数。从 ShaderToy 移植。\n"
			  "https://www.shadertoy.com/view/lldBRn";

	ui_category = "致谢";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

uniform int Preprocessordefinitionstooltip<
	ui_text = "RESOLUTION_SCALE_ : 较低的值速度更快但可能稍微模糊。\n\n"

			  "SMOOTH_NORMALS : 0 为禁用，1 为低质量快速，2 为高质量较慢，3 为摄影模式非常慢。\n\n"

			  "UI_DIFFICULTY : 0 为简单模式，1 为 ReShade 高手模式。";//\n\n"

			  //"NGL_HYBRID_MODE : 0 表示一次只能使用一个效果。要么 GI 要么反射。1 表示同时拥有两种效果但更慢（不到 2 倍）";
	ui_category = "预处理器定义提示";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

#endif
