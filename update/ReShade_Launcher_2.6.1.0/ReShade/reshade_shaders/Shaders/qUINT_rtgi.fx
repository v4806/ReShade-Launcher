/*=============================================================================

	ReShade 4 effect file
    github.com/martymcmodding

	Support me:
   		paypal.me/mcflypg
   		patreon.com/mcflypg

    Path Traced Global Illumination 

    * Unauthorized copying of this file, via any medium is strictly prohibited
 	* Proprietary and confidential

=============================================================================*/

/*=============================================================================
	Preprocessor settings
=============================================================================*/

#ifndef INFINITE_BOUNCES
 #define INFINITE_BOUNCES       0   //[0 or 1]      If enabled, path tracer samples previous frame GI as well, causing a feedback loop to simulate secondary bounces, causing a more widespread GI.
#endif

#ifndef SKYCOLOR_MODE
 #define SKYCOLOR_MODE          0   //[0 to 2]      0: skycolor feature disabled | 1: manual skycolor | 2: dynamic skycolor
#endif

#ifndef MATERIAL_TYPE
 #define MATERIAL_TYPE          0   //[0 to 1]      0: Lambert diffuse | 1: GGX BRDF
#endif

#ifndef HALFRES_INPUT
 #define HALFRES_INPUT 			0   //[0 to 1]      0: use full resolution color and depth input | 1 : use half resolution color and depth input (faster)
#endif

#ifndef FADEOUT_MODE
 #define FADEOUT_MODE 			0   //[0 to 3]      0: smoothstep original* using distance vs depth | 1: linear | 2: biquadratic | 3: exponential
#endif

/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform int UIHELP <
	ui_type = "radio";
	ui_label = " ";	
	ui_text ="This shader adds ray traced / ray marched global illumination to games\nby traversing the height field described by the depth map of the game.\n\nHover over the settings below to display more information.\n\n          >>>>>>>>>> IMPORTANT <<<<<<<<<      \n\nIf the shader appears to do nothing when enabled, make sure ReShade's\ndepth access is properly set up - no output without proper input.\n\n          >>>>>>>>>> IMPORTANT <<<<<<<<<      ";
	ui_category = "Overview / Help";
	ui_category_closed = true;
>;

uniform float RT_SAMPLE_RADIUS <
	ui_type = "drag";
	ui_min = 0.5; ui_max = 20.0;
    ui_step = 0.01;
    ui_label = "光线长度";
	ui_tooltip = "最大光线长度，直接影响\n阴影/反射光照的扩散半径";
    ui_category = "路径追踪";
> = 4.0;

uniform int RT_RAY_AMOUNT <
	ui_type = "slider";
	ui_min = 1; ui_max = 20;
    ui_label = "光线数量";
    ui_tooltip = "每像素发射的光线数量，用于估算\n该位置的全局光照。\n需要过滤的噪点与sqrt(光线数量)成正比。";
    ui_category = "路径追踪";
> = 3;

uniform int RT_RAY_STEPS <
	ui_type = "slider";
	ui_min = 1; ui_max = 20;
    ui_label = "每条光线的步数";
    ui_tooltip = "RTGI执行步进式光线行进来检查光线命中。\n步数太少可能导致光线跳过小细节。";
    ui_category = "路径追踪";
> = 12;

uniform float RT_Z_THICKNESS <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 4.0;
    ui_step = 0.01;
    ui_label = "Z轴厚度";
	ui_tooltip = "着色器无法知道物体有多厚，因为它只能\n看到相机朝向的一面，必须假设一个固定值。\n\n使用此参数来消除薄物体周围的光晕。";
    ui_category = "路径追踪";
> = 0.5;

uniform bool RT_HIGHP_LIGHT_SPREAD <
    ui_label = "启用精确光照扩散";
    ui_tooltip = "光线在小误差范围内接受场景交叉。\n启用此项将使光线对齐到实际命中位置。\n这会产生更锐利但更真实的光照效果。";
    ui_category = "路径追踪";
> = true;

uniform bool RT_BACKFACE_MIRROR <
    ui_label = "启用背面光照模拟";
    ui_tooltip = "RTGI只能模拟屏幕上可见物体反射的光线。\n为了估算来自可见物体非可见面的光线，\n此功能将使用正面颜色作为替代。";
    ui_category = "路径追踪";
> = false;

uniform bool RT_ALTERNATE_INTERSECT_TEST <
    ui_label = "替代交叉测试";
    ui_tooltip = "启用替代方式来接受或拒绝光线命中。\n将消除薄物体周围的光晕，但会在\n其他地方产生更多光照和阴影。\n光照更准确但>>SSAO<<轮廓效果不那么明显。";
    ui_category = "路径追踪";
> = false;

#if MATERIAL_TYPE == 1
uniform float RT_SPECULAR <
	ui_type = "drag";
	ui_min = 0.01; ui_max = 1.0;
    ui_step = 0.01;
    ui_label = "镜面反射";
    ui_tooltip = "GGX微表面BRDF的镜面反射材质参数";
    ui_category = "材质";
> = 1.0;

uniform float RT_ROUGHNESS <
	ui_type = "drag";
	ui_min = 0.05; ui_max = 1.0;
    ui_step = 0.01;
    ui_label = "粗糙度";
    ui_tooltip = "GGX微表面BRDF的粗糙度材质参数";
    ui_category = "材质";
> = 1.0;
#endif

#if SKYCOLOR_MODE != 0

#if SKYCOLOR_MODE == 1
uniform float3 SKY_COLOR <
	ui_type = "color";
	ui_label = "天空颜色";
    ui_category = "混合";
> = float3(1.0, 0.0, 0.0);
#endif

#if SKYCOLOR_MODE == 2
uniform float SKY_COLOR_SAT <
	ui_type = "drag";
	ui_min = 0; ui_max = 5.0;
    ui_step = 0.01;
    ui_label = "自动天空颜色饱和度";
    ui_category = "混合";
> = 1.0;
#endif

uniform float SKY_COLOR_AMBIENT_MIX <
	ui_type = "drag";
	ui_min = 0; ui_max = 1.0;
    ui_step = 0.01;
    ui_label = "天空颜色环境光混合";
    ui_tooltip = "被遮蔽的环境色中有多少被视为天空颜色\n\n如果为0，环境光遮蔽移除白色环境光，\n如果为1，环境光遮蔽只移除天空颜色";
    ui_category = "混合";
> = 0.2;

uniform float SKY_COLOR_AMT <
	ui_type = "drag";
	ui_min = 0; ui_max = 10.0;
    ui_step = 0.01;
    ui_label = "天空颜色强度";
    ui_category = "混合";
> = 4.0;
#endif

uniform float RT_AO_AMOUNT <
	ui_type = "drag";
	ui_min = 0; ui_max = 10.0;
    ui_step = 0.01;
    ui_label = "环境光遮蔽强度";
    ui_category = "混合";
> = 4.0;

uniform float RT_IL_AMOUNT <
	ui_type = "drag";
	ui_min = 0; ui_max = 10.0;
    ui_step = 0.01;
    ui_label = "反射光照强度";
    ui_category = "混合";
> = 4.0;

#if INFINITE_BOUNCES != 0
    uniform float RT_IL_BOUNCE_WEIGHT <
        ui_type = "drag";
        ui_min = 0; ui_max = 2.0;
        ui_step = 0.01;
        ui_label = "下一次反弹权重";
        ui_category = "混合";
    > = 0.0;
#endif

uniform float2 RT_FADE_DEPTH <
	ui_type = "drag";
    ui_label = "淡出起始/结束距离";
	ui_min = 0.00; ui_max = 1.00;
	ui_tooltip = "GI开始淡出的距离 | 完全淡出的距离。";
    ui_category = "混合";
> = float2(0.0, 0.5);

uniform int RT_DEBUG_VIEW <
	ui_type = "radio";
    ui_label = "启用调试视图";
	ui_items = "无\0光照通道\0法线通道\0";
	ui_tooltip = "不同的调试输出";
    ui_category = "调试";
> = 0;

uniform bool RT_DO_RENDER <
    ui_label = "渲染静态帧（用于截图）";
    ui_category = "实验性";
    ui_tooltip = "这将以极高质量逐步渲染一个静态帧（目前滤镜关闭）。\n要开始渲染，勾选此框并等待直到结果噪点足够少。\n您仍可以调整混合和切换调试模式，但不要触碰其他任何东西。\n要恢复游戏，取消勾选此框。\n\n需要场景中没有移动物体才能正常工作。";
> = false;

/*
uniform float4 tempF1 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform float4 tempF2 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform float4 tempF3 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);
 */

/*=============================================================================
	Textures, Samplers, Globals
=============================================================================*/

#define RESHADE_QUINT_COMMON_VERSION_REQUIRE 202
#define RESHADE_QUINT_EFFECT_DEPTH_REQUIRE
#include "qUINT_common.fxh"

//only works for positive numbers up to 8 bit but I don't expect buffer_width to exceed 61k pixels
//forcing uints so it works for NvCamera as well
#define CONST_LOG2(v)   (((uint(v) >> 1u) != 0u) + ((uint(v) >> 2u) != 0u) + ((uint(v) >> 3u) != 0u) + ((uint(v) >> 4u) != 0u) + ((uint(v) >> 5u) != 0u) + ((uint(v) >> 6u) != 0u) + ((uint(v) >> 7u) != 0u))

//for 1920x1080, use 3 mip levels
//double the screen size, use one mip level more
//log2(1920/240) = 3
//log2(3840/240) = 4
#define MIP_AMT 	CONST_LOG2(BUFFER_WIDTH / 240)

#if HALFRES_INPUT != 0
#define MIP_BIAS_IL	1
texture ZTex               < pooled = true; >  { Width = BUFFER_WIDTH>>1;   Height = BUFFER_HEIGHT>>1;   Format = R16F;      MipLevels = MIP_AMT;};
texture ColorTex           < pooled = true; >  { Width = BUFFER_WIDTH>>1;   Height = BUFFER_HEIGHT>>1;   Format = RGB10A2;   MipLevels = MIP_AMT + MIP_BIAS_IL;  };
#else 
#define MIP_BIAS_IL	2
texture ZTex               < pooled = true; >  { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = R16F;      MipLevels = MIP_AMT;};
texture ColorTex           < pooled = true; >  { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGB10A2;   MipLevels = MIP_AMT + MIP_BIAS_IL;  };
#endif

texture GBufferTex      					    { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
texture GBufferTex1      					    { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
texture GBufferTex2      					    { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
texture GITex0	            					{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
texture GITex1	            					{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
texture GITex2	            					{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
texture GITexFilterTemp0 /*infinite bounces*/	{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
texture GITexFilterTemp1 < pooled = true; >	    { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
texture SkyCol                                  { Width = 1;   			  Height = 1;   			Format = RGBA8; };
texture SkyColPrev                              { Width = 1;   			  Height = 1;   			Format = RGBA8; };
texture JitterTex < source = "bluenoise.png"; > { Width = 32; 			  Height = 32; 				Format = RGBA8; };



sampler sZTex	            					{ Texture = ZTex;	    };
sampler sColorTex	        					{ Texture = ColorTex;	};
sampler sGBufferTex								{ Texture = GBufferTex;	};
sampler sGBufferTex1							{ Texture = GBufferTex1;	};
sampler sGBufferTex2							{ Texture = GBufferTex2;	};
sampler sGITex0       							{ Texture = GITex0;    };
sampler sGITex1       							{ Texture = GITex1;    };
sampler sGITex2       							{ Texture = GITex2;    };
sampler sGITexFilterTemp0       				{ Texture = GITexFilterTemp0;    };
sampler sGITexFilterTemp1       				{ Texture = GITexFilterTemp1;    };
sampler sSkyCol	        						{ Texture = SkyCol;	};
sampler sSkyColPrev	    						{ Texture = SkyColPrev;	};
sampler	sJitterTex          					{ Texture = JitterTex; AddressU = WRAP; AddressV = WRAP;};

/*=============================================================================
	Vertex Shader
=============================================================================*/

struct VSOUT
{
	float4                  vpos        : SV_Position;
    float2                  uv          : TEXCOORD0;
};

VSOUT VS_RT(in uint id : SV_VertexID)
{
    VSOUT o;
    PostProcessVS(id, o.vpos, o.uv); //use original fullscreen triangle VS
    return o;
}

/*=============================================================================
	Functions
=============================================================================*/

struct RTInputs
{
	//per pixel
    float3 pos;
    float3 normal;
    float3 eyedir;
    float3x3 tangent_base;
    float3 jitter;

    //runtime pixel independent
    int nrays;
    int nsteps;
};

#include "RTGI/Projection.fxh"
#include "RTGI/Normal.fxh"
#include "RTGI/RaySorting.fxh"
#include "RTGI/RayTracing.fxh"
#include "RTGI\Denoise.fxh"

RTInputs init(VSOUT i)
{
	RTInputs o;
	o.nrays   = RT_RAY_AMOUNT;
    o.nsteps  = RT_RAY_STEPS;

	o.pos = Projection::uv_to_proj(i.uv);
	o.eyedir = -normalize(o.pos);
	o.normal = tex2D(sGBufferTex, i.uv).xyz;

    o.normal += tex2D(sGBufferTex, i.uv + float2(1,1) * qUINT::PIXEL_SIZE * 0.75).xyz;
    o.normal += tex2D(sGBufferTex, i.uv + float2(-1,1) * qUINT::PIXEL_SIZE * 0.75).xyz;
    o.normal += tex2D(sGBufferTex, i.uv + float2(1,-1) * qUINT::PIXEL_SIZE * 0.75).xyz;
    o.normal += tex2D(sGBufferTex, i.uv + float2(-1,-1) * qUINT::PIXEL_SIZE * 0.75).xyz;
    o.normal = normalize(o.normal);

	o.jitter =                 tex2Dfetch(sJitterTex, i.vpos.xy 	  % 32u).xyz;
    o.jitter = frac(o.jitter + tex2Dfetch(sJitterTex, (i.vpos.xy / 32) % 32u).xyz);  

	o.tangent_base = Normal::base_from_vector(o.normal);

    if(RT_DO_RENDER)
    {    
        o.nsteps  = 255;
        o.nrays   = 1;
    }

	return o;
}

void unpack_hdr(inout float3 color)
{
  color = color * rcp(1.01 - saturate(color)); 
}

void pack_hdr(inout float3 color)
{
  color = 1.01 * color * rcp(color + 1.0);  
}

float3 dither(in VSOUT i)
{
    const float2 magicdot = float2(0.75487766624669276, 0.569840290998);
    const float3 magicadd = float3(0, 0.025, 0.0125) * dot(magicdot, 1);

    const int bit_depth = 8; //TODO: add BUFFER_COLOR_DEPTH once it works
    const float lsb = exp2(bit_depth) - 1;

    float3 dither = frac(dot(i.vpos.xy, magicdot) + magicadd);
    dither /= lsb;
    
    return dither;
}

float3 ggx_vndf(float2 uniform_disc, float2 alpha, float3 v)
{
	//scale by alpha, 3.2
	float3 Vh = normalize(float3(alpha * v.xy, v.z));
	//point on projected area of hemisphere
	float2 p = uniform_disc;
	p.y = lerp(sqrt(1.0 - p.x*p.x), 
		       p.y,
		       Vh.z * 0.5 + 0.5);

	float3 Nh =  float3(p.xy, sqrt(saturate(1.0 - dot(p, p)))); //150920 fixed sqrt() of z

	//reproject onto hemisphere
	Nh = mul(Nh, Normal::base_from_vector(Vh));

	//revert scaling
	Nh = normalize(float3(alpha * Nh.xy, saturate(Nh.z)));

	return Nh;
}

float3 schlick_fresnel(float vdoth, float3 f0)
{
	vdoth = saturate(vdoth);
	return lerp(pow(vdoth, 5), 1, f0);
}

float ggx_g2_g1(float3 l, float3 v, float2 alpha)
{
	//smith masking-shadowing g2/g1, v and l in tangent space
	l.xy *= alpha;
	v.xy *= alpha;
	float nl = length(l);
	float nv = length(v);

    float ln = l.z * nv;
    float lv = l.z * v.z;
    float vn = v.z * nl;
    //in tangent space, v.z = ndotv and l.z = ndotl
    return (ln + lv) / (vn + ln + 1e-7);
}

float3 weyl3d(float3 p0, int n) 
{    
   static const float3 a = float3(1.2207440846, 1.4902161201, 1.819172513396);
   return frac(p0 + n * rcp(a));
}

float fade_distance(in VSOUT i)
{
    float distance = saturate(length(Projection::uv_to_proj(i.uv)) / RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
    float fade;
#if(FADEOUT_MODE == 1)
    fade = saturate((RT_FADE_DEPTH.y - distance) / (RT_FADE_DEPTH.y - RT_FADE_DEPTH.x + 1e-6));
#elif(FADEOUT_MODE == 2)
    fade = saturate((RT_FADE_DEPTH.y - distance) / (RT_FADE_DEPTH.y - RT_FADE_DEPTH.x + 1e-6));
    fade *= fade; 
    fade *= fade;
#elif(FADEOUT_MODE == 3)
    fade = exp(-distance * rcp(RT_FADE_DEPTH.y * RT_FADE_DEPTH.y * 8.0 + 0.001) + RT_FADE_DEPTH.x);
#else
    fade = smoothstep(RT_FADE_DEPTH.y+0.001, RT_FADE_DEPTH.x, distance);  
#endif

    return fade;    
}

/*=============================================================================
	Pixel Shaders
=============================================================================*/

void PS_InputSetup(in VSOUT i, out float4 color : SV_Target0, out float depth : SV_Target1, out float4 gbuffer : SV_Target2)
{ 
    depth = qUINT::linear_depth(i.uv);
    color = tex2D(qUINT::sBackBufferTex, i.uv);
    color *= saturate(999.0 - depth * 1000.0); //mask sky
    depth = Projection::depth_to_z(depth);
    gbuffer.xyz = Normal::normal_from_depth(i);
    gbuffer.w = depth;
}

void PS_InputSetupHalf1(in VSOUT i, out float4 gbuffer : SV_Target0)
{ 
    gbuffer.xyz = Normal::normal_from_depth(i);
    gbuffer.w = Projection::depth_to_z(qUINT::linear_depth(i.uv));
}

void PS_InputSetupHalf2(in VSOUT i, out float4 color : SV_Target0, out float depth : SV_Target1)
{
   	float4 texels; //TODO: replace with gather()
    texels.x = qUINT::linear_depth(i.uv + float2( 0.5, 0.5) * qUINT::PIXEL_SIZE);
    texels.y = qUINT::linear_depth(i.uv + float2(-0.5, 0.5) * qUINT::PIXEL_SIZE);
    texels.z = qUINT::linear_depth(i.uv + float2( 0.5,-0.5) * qUINT::PIXEL_SIZE);
    texels.w = qUINT::linear_depth(i.uv + float2(-0.5,-0.5) * qUINT::PIXEL_SIZE);
    float   avg = dot(texels, 0.25);
    float4 diff = saturate(1.0 - avg / texels);    
    depth = dot(texels, diff);
    depth /= dot(diff, 1); 

    color = tex2D(qUINT::sBackBufferTex, i.uv);
    color *= saturate(999.0 - depth * 1000.0); //mask sky

    depth = Projection::depth_to_z(depth);
}

//1 -> 2
void PS_Copy_1_to_2(in VSOUT i, out float4 o0 : SV_Target0, out float4 o1 : SV_Target1)
{
	o0 = tex2D(sGITex1, i.uv);
	o1 = tex2D(sGBufferTex1, i.uv);
}

//0 -> 1
void PS_Copy_0_to_1(in VSOUT i, out float4 o0 : SV_Target0, out float4 o1 : SV_Target1)
{
	o0 = tex2D(sGITex0, i.uv);
	o1 = tex2D(sGBufferTex, i.uv);
}

//update 0
void PS_RTMain(in VSOUT i, out float4 o : SV_Target0)
{
	RTInputs parameters = init(i);
	//bias position a bit to fix precision issues
	parameters.pos *= 0.999;
	parameters.pos += parameters.normal * Projection::z_to_depth(parameters.pos.z);
	SampleSet sampleset = ray_sorting(i, qUINT::FRAME_COUNT, parameters.jitter.x); 

#if MATERIAL_TYPE == 1
    float3 specular_color = tex2D(qUINT::sBackBufferTex, i.uv).rgb; 
    specular_color = normalize(specular_color + 0.5) * rsqrt(3.0);
#endif
    o = 0;

    [loop]
    for(int r = 0; r < 0 + parameters.nrays; r++)
    {
        RayTracing::RayDesc ray;
        ray.pos = parameters.pos;

#if MATERIAL_TYPE == 0
        //lambert cosine distribution without TBN reorientation

        ray.dir.z = (r + sampleset.index) / parameters.nrays * 2.0 - 1.0;       
        ray.dir.xy = sampleset.dir_xy * sqrt(1.0 - ray.dir.z * ray.dir.z); //build sphere
        ray.dir = normalize(ray.dir + parameters.normal);
        
if(RT_DO_RENDER) 
{
		//use x and z here as y is used for step jittering
        parameters.jitter = weyl3d(parameters.jitter, (qUINT::FRAME_COUNT % 3000u) * parameters.nrays + r);

        ray.dir.z = parameters.jitter.x;
        ray.dir.xy = 1 - ray.dir.z;
        ray.dir = sqrt(ray.dir);
        ray.dir.xy *= float2(sin(parameters.jitter.z * 3.1415927 * 2), cos(parameters.jitter.z * 3.1415927 * 2));
        //reorient ray to surface alignment
        ray.dir = mul(ray.dir, parameters.tangent_base); 
}

#elif MATERIAL_TYPE == 1
        float alpha = RT_ROUGHNESS * RT_ROUGHNESS; //isotropic  
        float3 f0 = specular_color * RT_SPECULAR;
        float3 v = mul(parameters.eyedir, transpose(parameters.tangent_base)); //v to tangent space
        //"random" point on disc - do I have to do sqrt() ?
        float2 uniform_disc = sqrt((r + sampleset.index) / parameters.nrays) * sampleset.dir_xy;

		if(RT_DO_RENDER) //generate a pseudorandom ray for each iteration
		{
			parameters.jitter = weyl3d(parameters.jitter, (qUINT::FRAME_COUNT % 3000u) * parameters.nrays + r);
			sincos(parameters.jitter.x * 3.1415927 * 2.0, uniform_disc.y, uniform_disc.x);
			uniform_disc *= sqrt(parameters.jitter.z);
		}

        float3 h = ggx_vndf(uniform_disc, alpha.xx, v);
        float3 l = reflect(-v, h);

        //single scatter lobe
        float3 brdf = ggx_g2_g1(l, v , alpha.xx); //if l.z > 0 is checked later
        brdf = l.z < 1e-7 ? 0 : brdf; //test?
        float vdoth = dot(parameters.eyedir, h);
        brdf *= schlick_fresnel(vdoth, f0);

        ray.dir = mul(l, parameters.tangent_base); //l from tangent to projection
#endif      
        ray.maxlen = RT_SAMPLE_RADIUS * RT_SAMPLE_RADIUS;

        //advance to next ray dir
        sampleset.dir_xy = mul(sampleset.dir_xy, sampleset.nextdir); 

        if (dot(ray.dir, parameters.normal) < 0.0)
            continue;

        float cos_view = dot(normalize(parameters.pos), ray.dir);
        ray.steplen = ray.maxlen  * rsqrt(1.0 - cos_view * cos_view) / parameters.nsteps;
        ray.currlen = ray.steplen * parameters.jitter.y;  
        
        float intersected = RayTracing::compute_intersection(ray, parameters, i);        
        o.w += intersected;

        if(RT_IL_AMOUNT * intersected == 0) 
            continue;

        float3 albedo           = tex2Dlod(sColorTex,    float4(ray.uv, 0, ray.width + MIP_BIAS_IL)).rgb; unpack_hdr(albedo);
        float3 intersect_normal = tex2Dlod(sGBufferTex,  float4(ray.uv, 0, 0)).xyz;

#if INFINITE_BOUNCES != 0
        float3 nextbounce       = tex2Dlod(sGITexFilterTemp0,  float4(ray.uv, 0, 0)).rgb; unpack_hdr(nextbounce);            
        albedo += nextbounce * RT_IL_BOUNCE_WEIGHT;
#endif
        float backface_check = saturate(dot(-intersect_normal, ray.dir) * 100.0);
        
        //since we searched systematically for an occluder, we can assume there is a direct line of sight between occluder and source point
        //hence all we have to do
        if(RT_BACKFACE_MIRROR)                             
            backface_check = lerp(backface_check, 1.0, 0.1);

        albedo *= backface_check;

#if MATERIAL_TYPE == 0
        o.rgb += albedo;   // * cos(theta) / pdf == 1 here for cosine weighted sampling  
#elif MATERIAL_TYPE == 1

        albedo *= brdf;
        albedo *= 10.0;

        o.rgb += albedo;
#endif   
    }

    o /= parameters.nrays; 

//temporal integration stuff

#define read_counter(tex) tex2Dfetch(tex, 0).w
#define store_counter(val) o.w = max(i.vpos.x, i.vpos.y) <= 1.0 ? val : o.w;

    if(!RT_DO_RENDER)
    {
    	store_counter(0);
    }
    else
    {
    	float counter = read_counter(sGITex1);
    	counter++;
    	float4 last_accumulated = tex2D(sGITex1, i.uv);
    	unpack_hdr(last_accumulated.rgb);
    	o = lerp(last_accumulated, o, rcp(counter));
    	store_counter(counter);
    }

	pack_hdr(o.rgb);
}

void PS_Combine(in VSOUT i, out float4 o : SV_Target0)
{
	float4 gi[2], gbuf[2];
	gi[0] = tex2D(sGITex1, i.uv);
	gi[1] = tex2D(sGITex2, i.uv);
	gbuf[0] = tex2D(sGBufferTex1, i.uv);
	gbuf[1] = tex2D(sGBufferTex2, i.uv);

	float4 combined = tex2D(sGITex0, i.uv);
	float sumweight = 1.0;
	float4 gbuf_reference = tex2D(sGBufferTex, i.uv);

	[unroll]
	for(int j = 0; j < 2; j++)
	{
		float4 delta = abs(gbuf_reference - gbuf[j]);

		float normal_sensitivity = 2.0;
		float z_sensitivity = 1.0;

		//TODO: investigate corner cases, if this is actually useful
		float time_delta = qUINT::FRAME_TIME; 
		time_delta = max(time_delta, 1.0) / 16.7; //~1 for 60 fps, expected range
		delta /= time_delta;

		float d = dot(delta, float4(delta.xyz * normal_sensitivity, z_sensitivity)); //normal squared, depth linear
		float w = exp(-d);

		combined += gi[j] * w;
		sumweight += w;
	}
	combined /= sumweight;
	o = combined;
}

void PS_Filter0(in VSOUT i, out float4 o : SV_Target0)
{
    o = Denoise::filter(i, sGITexFilterTemp0, 0, 0);
}
void PS_Filter1(in VSOUT i, out float4 o : SV_Target0)
{
    o = Denoise::filter(i, sGITexFilterTemp1, 1, RT_DO_RENDER);
}
void PS_Filter2(in VSOUT i, out float4 o : SV_Target0)
{
    o = Denoise::filter(i, sGITexFilterTemp0, 2, RT_DO_RENDER);
}
void PS_Filter3(in VSOUT i, out float4 o : SV_Target0)
{
    o = Denoise::filter(i, sGITexFilterTemp1, 3, RT_DO_RENDER);
}

void PS_Disp(in VSOUT i, out float4 o : SV_Target0)
{
    float4 gi = tex2D(sGITexFilterTemp0, i.uv);
    float3 color = tex2D(qUINT::sBackBufferTex, i.uv).rgb;

    unpack_hdr(color);
    unpack_hdr(gi.rgb);  

    color = RT_DEBUG_VIEW == 1 ? 1 : color; 

    float similarity = distance(normalize(color + 0.00001), normalize(gi.rgb + 0.00001));
	similarity = saturate(similarity * 3.0);
	gi.rgb = lerp(dot(gi.rgb, 0.3333), gi.rgb, saturate(similarity * 0.5 + 0.5));  
   
    float fade = fade_distance(i);  
    gi *= fade; 

#if SKYCOLOR_MODE != 0
 #if SKYCOLOR_MODE == 1
    float3 skycol = SKY_COLOR;
 #else
    float3 skycol = tex2Dfetch(sSkyCol, int4(0,0,0,0)).rgb;
    skycol = lerp(dot(skycol, 0.333), skycol, SKY_COLOR_SAT * 0.2);
 #endif
    skycol *= fade;

    color = color * (1.0 + gi.rgb * RT_IL_AMOUNT * RT_IL_AMOUNT); //apply GI
    color = color / (1.0 + lerp(1.0, skycol, SKY_COLOR_AMBIENT_MIX) * gi.w * RT_AO_AMOUNT); //apply AO as occlusion of skycolor
    color = color * (1.0 + skycol * SKY_COLOR_AMT);
#else
    color = color * (1.0 + gi.rgb * RT_IL_AMOUNT * RT_IL_AMOUNT); //apply GI
    color = color / (1.0 + gi.w * RT_AO_AMOUNT);
#endif
    pack_hdr(color.rgb);

    //dither a little bit as large scale lighting might exhibit banding
    color += dither(i);

    color = RT_DEBUG_VIEW == 2 ? -tex2D(sGBufferTex, i.uv).xyz * 0.5 + 0.5 : color;
    o = float4(color, 1);
}

void PS_ReadSkycol(in VSOUT i, out float4 o : SV_Target0)
{
    float2 gridpos;
    gridpos.x = qUINT::FRAME_COUNT % 64u;
    gridpos.y = floor(qUINT::FRAME_COUNT / 64) % 64u;

    float2 unormgridpos = gridpos / 64.0;

    int searchsize = 10;

    float4 skycolor = 0.0;

    for(float x = 0; x < searchsize; x++)
    for(float y = 0; y < searchsize; y++)
    {
        float2 loc = (float2(x, y) + unormgridpos) * rcp(searchsize);

        float z = qUINT::linear_depth(loc);
        float issky = z == 1;

        skycolor += float4(tex2Dlod(qUINT::sBackBufferTex, float4(loc, 0, 0)).rgb, 1) * issky;
    }

    skycolor.rgb /= skycolor.w + 0.000001;

    float4 prevskycolor = tex2D(sSkyColPrev, 1);

    bool skydetectedthisframe = skycolor.w > 0.000001;
    bool skydetectedatall = prevskycolor.w; //0 if skycolor has not been read yet at all

    float interp = 0;

    //no skycol yet stored, now we have skycolor, use it
    if(!skydetectedatall && skydetectedthisframe)
        interp = 1;

    if(skydetectedatall && skydetectedthisframe)
        interp = saturate(0.1 * 0.01 * qUINT::FRAME_TIME);

    o.rgb = lerp(prevskycolor.rgb, skycolor.rgb, interp);
    o.w = skydetectedthisframe || skydetectedatall;
}

void PS_CopyPrevSkycol(in VSOUT i, out float4 o : SV_Target0)
{
    o = tex2D(sSkyCol, 1.0);
}

/*=============================================================================
	Techniques
=============================================================================*/

technique RTGlobalIllumination
< ui_tooltip = "              >> qUINT::RTGI 0.17 <<\n\n"
               "         EARLY ACCESS -- PATREON ONLY\n"
               "Official versions only via patreon.com/mcflypg\n"
               "\nRTGI is written by Marty McFly / Pascal Gilcher\n"
               "Early access, featureset might be subject to change"; >
{
#if SKYCOLOR_MODE == 2
    pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_ReadSkycol;
        RenderTarget = SkyCol;
    }
    pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_CopyPrevSkycol;
        RenderTarget = SkyColPrev;
    }
#endif
	//Update history chain
	pass
    {
		VertexShader = VS_RT;
		PixelShader  = PS_Copy_1_to_2; //1 -> 2
		RenderTarget0 = GITex2; 
		RenderTarget1 = GBufferTex2; 
    }
    pass
    {
		VertexShader = VS_RT;
		PixelShader  = PS_Copy_0_to_1; //0 -> 1
		RenderTarget0 = GITex1;
		RenderTarget1 = GBufferTex1; 
    }
    //Create new inputs
    #if HALFRES_INPUT == 0
    pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_InputSetup;
        RenderTarget0 = ColorTex;
        RenderTarget1 = ZTex;
        RenderTarget2 = GBufferTex;
    }
    #else
    pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_InputSetupHalf1;
        RenderTarget0 = GBufferTex;
    }
    pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_InputSetupHalf2;
        RenderTarget0 = ColorTex;
        RenderTarget1 = ZTex;
    }
    #endif
    pass
	{
		VertexShader = VS_RT;
		PixelShader  = PS_RTMain; //update 0
		RenderTarget0 = GITex0;      
	}
	//Combine temporal layers
	pass
	{
		VertexShader = VS_RT;
		PixelShader  = PS_Combine;
		RenderTarget0 = GITexFilterTemp0;
	}
	//Filter
	pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_Filter0;
        RenderTarget0 = GITexFilterTemp1;
    }
    pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_Filter1;
        RenderTarget0 = GITexFilterTemp0;
    } 
    pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_Filter2;
        RenderTarget0 = GITexFilterTemp1;
    } 
    pass
    {
        VertexShader = VS_RT;
        PixelShader  = PS_Filter3;
        RenderTarget = GITexFilterTemp0;
    }
    //Blend
    pass
	{
		VertexShader = VS_RT;
        PixelShader  = PS_Disp;
	}
}