/*=============================================================================
                                                           
 d8b 888b     d888 888b     d888 8888888888 8888888b.   .d8888b.  8888888888 
 Y8P 8888b   d8888 8888b   d8888 888        888   Y88b d88P  Y88b 888        
     88888b.d88888 88888b.d88888 888        888    888 Y88b.      888        
 888 888Y88888P888 888Y88888P888 8888888    888   d88P  "Y888b.   8888888    
 888 888 Y888P 888 888 Y888P 888 888        8888888P"      "Y88b. 888        
 888 888  Y8P  888 888  Y8P  888 888        888 T88b         "888 888        
 888 888   "   888 888   "   888 888        888  T88b  Y88b  d88P 888        
 888 888       888 888       888 8888888888 888   T88b  "Y8888P"  8888888888                                                                 
                                                                            
    Copyright (c) Pascal Gilcher. All rights reserved.
    
    * Unauthorized copying of this file, via any medium is strictly prohibited
 	* Proprietary and confidential

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.

===============================================================================

    Author:         Pascal Gilcher

    More info:      https://martysmods.com
                    https://patreon.com/mcflypg
                    https://github.com/martymcmodding  	

=============================================================================*/

/*=============================================================================
	Preprocessor settings
=============================================================================*/

/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform int DIFFUSE_GI_Q <
	ui_type = "combo";
    ui_label = "质量";
	ui_items = "关闭\0极低\0低\0中\0高\0超高\0";
    ui_category = "漫反射RTGI";
> = 3;

uniform float RT_AO_AMOUNT <
	ui_type = "drag";
	ui_min = 0; ui_max = 10.0;
    ui_label = "环境光遮蔽强度";
    ui_category = "漫反射RTGI";
> = 10.0;

uniform float RT_IL_AMOUNT <
	ui_type = "drag";
	ui_min = 0; ui_max = 10.0;
    ui_label = "光线反弹强度";
    ui_category = "漫反射RTGI";
> = 10.0;

uniform float RT_Z_THICKNESS <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "物体厚度";
    ui_tooltip = "着色器不知道物体在可见面之外延伸多少，必须假设一个固定值。\n\n将此值设置得尽可能低，但不要损失GI强度。";
	ui_category = "漫反射RTGI";
> = 0.25;

uniform int SPECULAR_GI_Q <
	ui_type = "combo";
    ui_label = "质量";
	ui_items = "关闭\0低\0中\0高\0超高\0";
    ui_category = "镜面反射RTGI";
> = 0;

uniform float RT_ROUGHNESS <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 0.5;
    ui_label = "表面粗糙度";
	ui_tooltip = "BRDF表面粗糙度决定了镜面GI的光泽/哑光程度。\n较低的值产生更光泽的反射，较高的值产生更漫反射的反射。";
    ui_category = "镜面反射RTGI";
> = 0.2;

#define GGX_ALPHA max(0.001, RT_ROUGHNESS * RT_ROUGHNESS)

uniform float RT_SPEC_AMOUNT <
	ui_type = "drag";
	ui_min = 0; ui_max = 1.0;
    ui_label = "镜面光照强度";
    ui_category = "镜面反射RTGI";
> = 1.0;

uniform float FILTER_SMOOTHNESS <
	ui_type = "drag";
	ui_min = 0; ui_max = 1.0;
    ui_label = "平滑度";
    ui_category = "降噪器";
> = 0.5;

uniform float RT_AMBIENT_LEVEL <
	ui_type = "drag";
    ui_label = "环境光级别";
	ui_min = 0.25; ui_max = 1.0;
	ui_tooltip = "环境光照强度。较低的值会移除场景中的恒定光线，让RTGI重新添加动态光照。";
    ui_category = "混合";
> = 0.3;

uniform float RT_FADE_DEPTH <
	ui_type = "drag";
    ui_label = "淡出范围";
	ui_min = 0.001; ui_max = 1.0;
	ui_tooltip = "距离衰减，较高的值会增加RTGI的绘制距离。";
    ui_category = "混合";
> = 0.3;

uniform int RT_DEBUG_VIEW <
	ui_type = "combo";
    ui_label = "调试视图";
	ui_items = "禁用\0漫反射RTGI\0镜面反射RTGI\0验证层\0";
	ui_tooltip = "验证层显示：\n\n- 深度\n- 光照\n- 法线向量\n- 光流";
    ui_category = "调试";
> = 0;

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

uniform float4 tempF4 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform float4 tempF5 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform float4 tempF6 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);


uniform float4 tempF7 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform bool debug_key_down < source = "key"; keycode = 0x46; mode = ""; >;//f
uniform bool debug_key_down2 < source = "key"; keycode = 0x47; mode = ""; >;//g
uniform bool debug_key_down3 < source = "key"; keycode = 0x48; mode = ""; >;//h
*/

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

//do NOT change anything here. "hurr durr I changed this and now it works"
//you ARE breaking things down the line, if the shader does not work without changes
//here, it's by design.

#define VARIANCE_FP16_QUANTIZATION_SCALE 128.0

uniform uint  FRAMECOUNT  < source = "framecount"; >;
uniform float FRAMETIME   < source = "frametime";  >;

texture ColorInputTex : COLOR;
texture DepthInputTex : DEPTH;
sampler ColorInput 	{ Texture = ColorInputTex; };
sampler DepthInput  { Texture = DepthInputTex; };

#include ".\MartysMods\mmx_global.fxh"
#include ".\MartysMods\mmx_depth.fxh"
#include ".\MartysMods\mmx_math.fxh"
#include ".\MartysMods\mmx_qmc.fxh"
#include ".\MartysMods\mmx_bxdf.fxh"
#include ".\MartysMods\mmx_deferred.fxh"
#include ".\MartysMods\mmx_camera.fxh"
#include ".\MartysMods\mmx_debug.fxh"
#include ".\MartysMods\mmx_texture.fxh"
#include ".\MartysMods\mmx_hash.fxh"
#include ".\MartysMods\mmx_harmonics.fxh"

//Precomputed stuff
texture RTGI_HorizonLUT  < source = "iMMERSE_horizonlut.png"; > { Width = 32; Height = 16; Format = R8; };
sampler	sRTGI_HorizonLUT { Texture = RTGI_HorizonLUT;  };
texture RTGI_GGXIntegralLUT  < source = "iMMERSE_ggxint.png"; > { Width = 32; Height = 32; Format = R8; };
sampler	sRTGI_GGXIntegralLUT { Texture = RTGI_GGXIntegralLUT;  };
texture RTGI_STBN128_s  < source = "iMMERSE_bluenoise_temporal128_s.png"; > { Width = 1024; Height = 512; Format = RGBA8; };
sampler	sRTGI_STBN128_s { Texture = RTGI_STBN128_s; AddressU = WRAP; AddressV = WRAP; };
texture RTGI_STBN128    < source = "iMMERSE_bluenoise_temporal128.png"; > { Width = 1024; Height = 512; Format = RGBA8; };
sampler	sRTGI_STBN128   { Texture = RTGI_STBN128; AddressU = WRAP; AddressV = WRAP; };

//Reusable
texture RTGI_Aux0  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; MipLevels = 4;};
texture RTGI_Aux1  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; MipLevels = 4;};
texture RTGI_Aux2  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
texture RTGI_Aux3  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
texture RTGI_Aux4  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
texture RTGI_Aux5  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
sampler sRTGI_Aux0 { Texture = RTGI_Aux0; };
sampler sRTGI_Aux1 { Texture = RTGI_Aux1; };
sampler sRTGI_Aux2 { Texture = RTGI_Aux2; };
sampler sRTGI_Aux3 { Texture = RTGI_Aux3; };
sampler sRTGI_Aux4 { Texture = RTGI_Aux4; };
sampler sRTGI_Aux5 { Texture = RTGI_Aux5; };
storage stRTGI_Aux0 { Texture = RTGI_Aux0; };
storage stRTGI_Aux1 { Texture = RTGI_Aux1; };
storage stRTGI_Aux2 { Texture = RTGI_Aux2; };
storage stRTGI_Aux3 { Texture = RTGI_Aux3; };
storage stRTGI_Aux4 { Texture = RTGI_Aux4; };
storage stRTGI_Aux5 { Texture = RTGI_Aux5; };

//Diffuse GI
texture RTGI_ZSrcTex     { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = R16F; MipLevels = 8;};
sampler sRTGI_ZSrcTex	{ Texture = RTGI_ZSrcTex;  MinFilter = POINT; MipFilter = POINT; MagFilter = POINT;};
sampler sRTGI_ZSrcTexLinear	{ Texture = RTGI_ZSrcTex;  };
storage stRTGI_ZSrcTex0	{ Texture = RTGI_ZSrcTex;  MipLevel = 0;};
storage stRTGI_ZSrcTex1	{ Texture = RTGI_ZSrcTex;  MipLevel = 1;};
storage stRTGI_ZSrcTex2	{ Texture = RTGI_ZSrcTex;  MipLevel = 2;};
storage stRTGI_ZSrcTex3	{ Texture = RTGI_ZSrcTex;  MipLevel = 3;};
storage stRTGI_ZSrcTex4	{ Texture = RTGI_ZSrcTex;  MipLevel = 4;};
storage stRTGI_ZSrcTex5	{ Texture = RTGI_ZSrcTex;  MipLevel = 5;};
storage stRTGI_ZSrcTex6	{ Texture = RTGI_ZSrcTex;  MipLevel = 6;};
storage stRTGI_ZSrcTex7	{ Texture = RTGI_ZSrcTex;  MipLevel = 7;};

texture3D RTGI_RadianceVolume  { Width = BUFFER_WIDTH_DLSS>>2; Height = BUFFER_HEIGHT_DLSS>>2; Depth = 3*6; Format = RGBA16F;  };
sampler3D sRTGI_RadianceVolume { Texture = RTGI_RadianceVolume; MinFilter=POINT; MipFilter=POINT;MagFilter=POINT;};
storage3D stRTGI_RadianceVolume { Texture = RTGI_RadianceVolume; };

texture RTGI_STSG_Cache  { Width = CEIL_DIV(BUFFER_WIDTH_DLSS, 32) * 32; Height = CEIL_DIV(BUFFER_HEIGHT_DLSS, 32) * 32; Format = RG32F; };
sampler sRTGI_STSG_Cache { Texture = RTGI_STSG_Cache; };
storage stRTGI_STSG_Cache { Texture = RTGI_STSG_Cache; };

//Specular
texture RTGI_HiZMipChain     { Width = BUFFER_WIDTH_DLSS + 128; Height = BUFFER_HEIGHT_DLSS + 128; Format = RG32F; MipLevels = 8;};
sampler sRTGI_HiZMipChain	{ Texture = RTGI_HiZMipChain;              MinFilter = POINT; MipFilter = POINT; MagFilter = POINT; };
storage stRTGI_HiZMipChain0	{ Texture = RTGI_HiZMipChain;  MipLevel = 0;};
storage stRTGI_HiZMipChain1	{ Texture = RTGI_HiZMipChain;  MipLevel = 1;};
storage stRTGI_HiZMipChain2	{ Texture = RTGI_HiZMipChain;  MipLevel = 2;};
storage stRTGI_HiZMipChain3	{ Texture = RTGI_HiZMipChain;  MipLevel = 3;};
storage stRTGI_HiZMipChain4	{ Texture = RTGI_HiZMipChain;  MipLevel = 4;};
storage stRTGI_HiZMipChain5	{ Texture = RTGI_HiZMipChain;  MipLevel = 5;};
storage stRTGI_HiZMipChain6	{ Texture = RTGI_HiZMipChain;  MipLevel = 6;};
storage stRTGI_HiZMipChain7	{ Texture = RTGI_HiZMipChain;  MipLevel = 7;};

//Filter / Temporal
texture RTGI_GBufferPrev  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
sampler sRTGI_GBufferPrev { Texture = RTGI_GBufferPrev; };
storage stRTGI_GBufferPrev { Texture = RTGI_GBufferPrev; };

//I have to denoise diffuse RGB irradiance and AO. But have to keep variance too for SVGF
//so I have to use an auxiliary texture for AO. Since I have to read the gbuffer anyways, might as well
//r/w it and put AO in there.
texture RTGI_GBufferForFilter  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
sampler sRTGI_GBufferForFilter { Texture = RTGI_GBufferForFilter; };
storage stRTGI_GBufferForFilter { Texture = RTGI_GBufferForFilter; };

texture RTGI_SpatialMomentsDiff  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
texture RTGI_SpatialMomentsSpec  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
sampler sRTGI_SpatialMomentsDiff { Texture = RTGI_SpatialMomentsDiff; };
sampler sRTGI_SpatialMomentsSpec { Texture = RTGI_SpatialMomentsSpec; };
storage stRTGI_SpatialMomentsDiff { Texture = RTGI_SpatialMomentsDiff; };
storage stRTGI_SpatialMomentsSpec { Texture = RTGI_SpatialMomentsSpec; };

texture RTGI_AccumDiff  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
texture RTGI_AccumSpec  { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
sampler sRTGI_AccumDiff { Texture = RTGI_AccumDiff; };
sampler sRTGI_AccumSpec { Texture = RTGI_AccumSpec; };
storage stRTGI_AccumDiff { Texture = RTGI_AccumDiff; };
storage stRTGI_AccumSpec { Texture = RTGI_AccumSpec; };


struct VSOUT
{
    float4 vpos : SV_Position;
    float2 uv   : TEXCOORD0;
};

struct CSIN 
{
    uint3 groupthreadid     : SV_GroupThreadID;         
    uint3 groupid           : SV_GroupID;            
    uint3 dispatchthreadid  : SV_DispatchThreadID;     
    uint threadid           : SV_GroupIndex;
};

struct TraceContext
{
    float2 uv;
    uint2 texel; //xy: working pos, zw: write pos
    float3 pos; //view space position
    float3 normal;
    float3 viewdir;
    float depth;
    float3 jitter;
    float3 geonormal;
};

/*=============================================================================
	Functions
=============================================================================*/

uint2 morton_idx_to_xy(uint idx)
{    
    uint2 pos = uint2(idx, idx >> 1);
    pos &= 0x55555555u;   
    pos = (pos ^ (pos >> 1)) & 0x33333333u; 
    pos = (pos ^ (pos >> 2)) & 0x0F0F0F0Fu; 
    pos = (pos ^ (pos >> 4)) & 0x00FF00FFu; 
    pos = (pos ^ (pos >> 8)) & 0x0000FFFFu;
    return pos;
}

float2 pixel_idx_to_uv(uint2 pos, float2 texture_size)
{
    float2 inv_texture_size = rcp(texture_size);
    return pos * inv_texture_size + 0.5 * inv_texture_size;
}

bool check_boundaries(uint2 pos, uint2 dest_size)
{
    return all(pos < dest_size) && all(pos >= uint2(0, 0));
}

float3 srgb_to_AgX(float3 srgb)
{
    const float3x3 toagx = float3x3(0.842479, 0.0784336, 0.0792237, 
                                    0.042328, 0.8784686, 0.0791661, 
                                    0.042376, 0.0784336, 0.8791430);
    return mul(toagx, srgb);         
}

float3 AgX_to_srgb(float3 AgX)
{   
    const float3x3 fromagx = float3x3(1.19688,  -0.0980209, -0.0990297,
                                     -0.0528969, 1.1519,    -0.0989612,
                                     -0.0529716, -0.0980435, 1.15107);
    return mul(fromagx, AgX);            
}

float3 unpack_hdr(float3 color)
{
    color  = saturate(color);   
    color = color*0.283799*((2.52405+color)*color);    
    color = srgb_to_AgX(color);
    color = color * rcp(1.04 - saturate(color));    
    return color;
}

float3 pack_hdr(float3 color)
{
    color =  1.04 * color * rcp(color + 1.0);   
    color = AgX_to_srgb(color);    
    color  = saturate(color);
    color = 1.14374*(-0.126893*color+sqrt(color));
    return color;     
}

float3 linear_to_ycocg(float3 color)
{
    float3 ycocg;
    ycocg.y = color.r - color.b;
    float tmp = color.b + ycocg.y * 0.5;
    ycocg.z = color.g - tmp;
    ycocg.x = tmp + ycocg.z * 0.5;
    return ycocg;
}

float3 ycocg_to_linear(float3 color)
{
    float tmp = color.x - color.z * 0.5;
    float3 rgb;
    rgb.g = color.z + tmp;
    rgb.b = tmp - color.y * 0.5;
    rgb.r = color.y + rgb.b;
    return rgb;
}

float get_brdf(float ndotv, float alpha)
{
    float brdf = tex2Dlod(sRTGI_GGXIntegralLUT, float2(ndotv, alpha), 0).x;
    return brdf * brdf; //stored sqrt
}

void copy_batch4(CSIN i, const int groupsize, sampler s_input, storage st_output)
{
    int2 p = i.groupid.xy * groupsize * 2 + morton_idx_to_xy(i.threadid).yx;

    int2 p00 = p;
    int2 p01 = int2(p.x + groupsize, p.y);
    int2 p10 = int2(p.x, p.y + groupsize);
    int2 p11 = int2(p.x + groupsize, p.y + groupsize);

    float4 t00 = tex2Dfetch(s_input, p00);
    float4 t01 = tex2Dfetch(s_input, p01);
    float4 t10 = tex2Dfetch(s_input, p10);
    float4 t11 = tex2Dfetch(s_input, p11);

    tex2Dstore(st_output, p00, t00);
    tex2Dstore(st_output, p01, t01);
    tex2Dstore(st_output, p10, t10);
    tex2Dstore(st_output, p11, t11);
}

float get_fade_factor(float depth)
{   
    if(RT_DEBUG_VIEW) return 1;

    float fade = saturate(1 - depth * depth); //fixed fade that smoothly goes to 0 at depth = 1, to multiply on top 
    float t = depth / (1e-6 + RT_FADE_DEPTH * RT_FADE_DEPTH);
    return saturate(exp2(-t) * fade - 0.01); //so it actually reaches 0    
}

bool can_earlyout(float depth)
{
    return get_fade_factor(depth) < 1e-5;
}

float3 showmotion(float2 motion)
{
	float angle = atan2(motion.y, motion.x);
	float dist = length(motion);
	float3 rgb = saturate(3 * abs(2 * frac(angle / 6.283 + float3(0, -1.0/3.0, 1.0/3.0)) - 1) - 1);
	return lerp(0.5, rgb, saturate(log(1 + dist * 400.0 / FRAMETIME)));//normalize by frametime such that we don't need to adjust visualization intensity all the time
}

/*=============================================================================
	Prepare Inputs
=============================================================================*/

VSOUT MainVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv); 
    return o;
}

struct ZDownsamplePayload
{    
    float depth;
    float energy;
    float2 hilo;
};

ZDownsamplePayload _ZDownsamplePayload()
{
    ZDownsamplePayload ts;   
    ts.depth = 0;  
    ts.energy = 0;  
    ts.hilo = 0;
    return ts;
}

ZDownsamplePayload _ZDownsamplePayload(float z, float2 uv)
{
    ZDownsamplePayload ts;
    ts.depth = z;
    float3 irradiance = unpack_hdr(tex2Dlod(ColorInput, uv, 0).rgb);
    ts.energy = length(irradiance);   
    ts.hilo = float2(pow(ts.depth, -8.0), pow(ts.depth, 8.0));
    return ts;
}

groupshared ZDownsamplePayload downsample_tgsm[32*32];

ZDownsamplePayload downsample(ZDownsamplePayload a, ZDownsamplePayload b, ZDownsamplePayload c, ZDownsamplePayload d)
{
    ZDownsamplePayload combined = _ZDownsamplePayload(); 
    combined.hilo = 0.25 * (a.hilo + b.hilo + c.hilo + d.hilo);

    float2 hilo = pow(combined.hilo, float2(-0.125, 0.125));
    float4 depths = float4(a.depth, b.depth, c.depth, d.depth);
    float4 energy = float4(a.energy, b.energy, c.energy, d.energy);

    const float sharpness = 9.0;

    float4 weights_near = exp(-max(1, depths / hilo.x) * sharpness);
    float4 weights_faar = exp(-max(1, hilo.y / depths) * sharpness);
    weights_near *= 0.1 + energy;
    weights_faar *= 0.1 + energy;

    float wsum_near = dot(weights_near, 1);
    float wsum_faar = dot(weights_faar, 1);
    float anchor = wsum_near > wsum_faar ? hilo.x : hilo.y;
    float4 weights = wsum_near > wsum_faar ? weights_near : weights_faar;

    combined.depth = dot(depths, weights) / dot(weights, 1);
    combined.energy = dot(energy, weights) / dot(weights, 1);

    return combined;
}

void DiffuseZDownsampleCS(in CSIN i)
{
     //remap 32x32 threads to morton order
    i.dispatchthreadid.xy = i.groupid.xy * 32u + morton_idx_to_xy(i.threadid);

    //reducing 32x32 to 1x1 equals 32² -> 16² -> 8² -> 4² -> 2² -> 1² = 5 mipmaps
    //so to create 7 mipmaps, we need to downsample 2 times i.e. each thread needs to reduce 4x4 pixels first
    ZDownsamplePayload quad_reservoirs[4];

    [unroll]
    for(int quad = 0; quad < 4; quad++)
    {
        //repeat logic inside the 4x4 block, i.e. order pixels by morton index
        //here we tex2Dgather each 2x2 subblock, but for a regular reduce pass, they'd be sampled directly
        uint2 quad_offset = morton_idx_to_xy(quad);
        uint2 global_pos = i.dispatchthreadid.xy * 4 + quad_offset * 2;

        float2 quad_topleft_uv = saturate((global_pos + 0.5) * BUFFER_PIXEL_SIZE_DLSS);
        float2 corrected_uv = Depth::correct_uv(quad_topleft_uv);
        corrected_uv.y -= BUFFER_PIXEL_SIZE_DLSS.y * 0.5;    //shift upwards since gather looks down and right

#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
    corrected_uv.y -= BUFFER_PIXEL_SIZE_DLSS.y * 0.5;    //shift upwards since gather looks down and right
    float4 quad_texels = tex2DgatherR(DepthInput, corrected_uv).wzyx;  
#else
    float4 quad_texels = tex2DgatherR(DepthInput, corrected_uv);
#endif
        quad_texels = Depth::linearize(quad_texels);
        //WZ
        //XY

        ZDownsamplePayload X = _ZDownsamplePayload(quad_texels.x, quad_topleft_uv + BUFFER_PIXEL_SIZE_DLSS * float2(-0.5,  0.5));
        ZDownsamplePayload Y = _ZDownsamplePayload(quad_texels.y, quad_topleft_uv + BUFFER_PIXEL_SIZE_DLSS * float2( 0.5,  0.5));
        ZDownsamplePayload Z = _ZDownsamplePayload(quad_texels.z, quad_topleft_uv + BUFFER_PIXEL_SIZE_DLSS * float2( 0.5, -0.5));
        ZDownsamplePayload W = _ZDownsamplePayload(quad_texels.w, quad_topleft_uv + BUFFER_PIXEL_SIZE_DLSS * float2(-0.5, -0.5));

        //gather order is wack               
        tex2Dstore(stRTGI_ZSrcTex0, global_pos + uint2(0, 0), Camera::depth_to_z(W.depth));        
        tex2Dstore(stRTGI_ZSrcTex0, global_pos + uint2(0, 1), Camera::depth_to_z(X.depth));     
        tex2Dstore(stRTGI_ZSrcTex0, global_pos + uint2(1, 0), Camera::depth_to_z(Z.depth));       
        tex2Dstore(stRTGI_ZSrcTex0, global_pos + uint2(1, 1), Camera::depth_to_z(Y.depth));   

        quad_reservoirs[quad] = downsample(X, Y, Z, W);
        tex2Dstore(stRTGI_ZSrcTex1, global_pos / 2, Camera::depth_to_z(quad_reservoirs[quad].depth));
    }

    ZDownsamplePayload combined = downsample(quad_reservoirs[0], quad_reservoirs[1], quad_reservoirs[2], quad_reservoirs[3]);
    tex2Dstore(stRTGI_ZSrcTex2, i.dispatchthreadid.xy, Camera::depth_to_z(combined.depth)); 
    downsample_tgsm[i.threadid] = combined;
    barrier();

    if(!(i.threadid & 3))
    {
        combined = downsample(downsample_tgsm[i.threadid + 0*1], downsample_tgsm[i.threadid + 1*1], downsample_tgsm[i.threadid + 2*1], downsample_tgsm[i.threadid + 3*1]);
        tex2Dstore(stRTGI_ZSrcTex3, i.dispatchthreadid.xy / 2, Camera::depth_to_z(combined.depth)); 
        downsample_tgsm[i.threadid] = combined;
    }
    barrier();
    if(!(i.threadid & 15))
    {
        combined = downsample(downsample_tgsm[i.threadid + 0*4], downsample_tgsm[i.threadid + 1*4], downsample_tgsm[i.threadid + 2*4], downsample_tgsm[i.threadid + 3*4]);   
        tex2Dstore(stRTGI_ZSrcTex4, i.dispatchthreadid.xy / 4, Camera::depth_to_z(combined.depth));  
        downsample_tgsm[i.threadid] = combined;
    }
    barrier();
    if(!(i.threadid & 63))
    {
        combined = downsample(downsample_tgsm[i.threadid + 0*16], downsample_tgsm[i.threadid + 1*16], downsample_tgsm[i.threadid + 2*16], downsample_tgsm[i.threadid + 3*16]);
        tex2Dstore(stRTGI_ZSrcTex5, i.dispatchthreadid.xy / 8, Camera::depth_to_z(combined.depth)); 
        downsample_tgsm[i.threadid] = combined;
    }
    barrier();
    if(!(i.threadid & 255))
    {
        combined = downsample(downsample_tgsm[i.threadid + 0*64], downsample_tgsm[i.threadid + 1*64], downsample_tgsm[i.threadid + 2*64], downsample_tgsm[i.threadid + 3*64]);
        tex2Dstore(stRTGI_ZSrcTex6, i.dispatchthreadid.xy / 16, Camera::depth_to_z(combined.depth));  
        downsample_tgsm[i.threadid] = combined; 
    }
    barrier();
    if(!(i.threadid & 1023))
    {
        combined = downsample(downsample_tgsm[i.threadid + 0*256], downsample_tgsm[i.threadid + 1*256], downsample_tgsm[i.threadid + 2*256], downsample_tgsm[i.threadid + 3*256]);
        tex2Dstore(stRTGI_ZSrcTex7, i.dispatchthreadid.xy / 32, Camera::depth_to_z(combined.depth));  
        downsample_tgsm[i.threadid] = combined; 
    }
}

void InitRadianceVolumeCS(in CSIN i)
{ 
    float wsum = 0;
    float4 sh[3];
    sh[0] = sh[1] = sh[2] = 0;

    float anchor = tex2Dlod(sRTGI_ZSrcTex, pixel_idx_to_uv(i.dispatchthreadid.xy, BUFFER_SCREEN_SIZE_DLSS >> 2), 2).x;
    
    [loop]for(int y = 0; y < 4; y++)
    [loop]for(int x = 0; x < 4; x++)
    {
        float2 tuv = (i.dispatchthreadid.xy * 4 + int2(x, y) + 0.5) * BUFFER_PIXEL_SIZE_DLSS;

        float3 irradiance = unpack_hdr(tex2Dlod(ColorInput, tuv, 0).rgb);
        float3 n = Deferred::get_geometry_normals(tuv);
        float4 dir_sh = SphericalHarmonics::dir_to_sh(n);
        float z = tex2Dlod(sRTGI_ZSrcTex, tuv, 0).x;

        float depth = Camera::z_to_depth(z);
        irradiance *= step(depth, 0.999);

        const float sharpness = 9.0;
        float w = exp(-max(z / anchor, anchor / z) * sharpness);
       
        sh[0] += dir_sh * irradiance.r * w;
        sh[1] += dir_sh * irradiance.g * w;
        sh[2] += dir_sh * irradiance.b * w;
        wsum += w;
    }

    tex3Dstore(stRTGI_RadianceVolume, int3(i.dispatchthreadid.xy, 0),  sh[0] / wsum);
    tex3Dstore(stRTGI_RadianceVolume, int3(i.dispatchthreadid.xy, 6),  sh[1] / wsum);
    tex3Dstore(stRTGI_RadianceVolume, int3(i.dispatchthreadid.xy, 12), sh[2] / wsum);
}

void radiance_volume_propagate(in CSIN i, int layer)
{
    int stepsize = 1 << layer;

    float wsum = 0;
    float4 sh[3];
    sh[0] = sh[1] = sh[2] = 0;

    float2 gw = float2(2, 1);

    float anchor = tex2Dlod(sRTGI_ZSrcTex, pixel_idx_to_uv(i.dispatchthreadid.xy, BUFFER_SCREEN_SIZE_DLSS >> 2), layer + 3).x;//use next layer here

    [unroll]for(int y = -1; y <= 1; y++)
    [unroll]for(int x = -1; x <= 1; x++)
    {
        float w = gw[abs(x)] * gw[abs(y)];
        int2 p = i.dispatchthreadid.xy + int2(x, y) * stepsize;
        float depth = tex2Dlod(sRTGI_ZSrcTex, pixel_idx_to_uv(p, BUFFER_SCREEN_SIZE_DLSS >> 2), layer + 2).x;

        const float sharpness = 9.0;
        float wz = exp(-max(depth / anchor, anchor / depth) * sharpness); 
        w *= wz;
        w += 0.001;

        float4 sh_r = tex3Dfetch(stRTGI_RadianceVolume, int3(p, layer));
        float4 sh_g = tex3Dfetch(stRTGI_RadianceVolume, int3(p, layer + 6)); 
        float4 sh_b = tex3Dfetch(stRTGI_RadianceVolume, int3(p, layer + 12));  

        w *= 0.1 + (sh_r.x + sh_g.x + sh_b.x);  

        sh[0] += w * sh_r;
        sh[1] += w * sh_g;
        sh[2] += w * sh_b;
        wsum += w;
    }

    tex3Dstore(stRTGI_RadianceVolume, int3(i.dispatchthreadid.xy, layer + 1),      sh[0] / wsum);
    tex3Dstore(stRTGI_RadianceVolume, int3(i.dispatchthreadid.xy, layer + 1 + 6),  sh[1] / wsum);
    tex3Dstore(stRTGI_RadianceVolume, int3(i.dispatchthreadid.xy, layer + 1 + 12), sh[2] / wsum);
}

void PropagateIrradianceVolumeCS0(in CSIN i){radiance_volume_propagate(i, 0);}
void PropagateIrradianceVolumeCS1(in CSIN i){radiance_volume_propagate(i, 1);}
void PropagateIrradianceVolumeCS2(in CSIN i){radiance_volume_propagate(i, 2);}
void PropagateIrradianceVolumeCS3(in CSIN i){radiance_volume_propagate(i, 3);}
void PropagateIrradianceVolumeCS4(in CSIN i){radiance_volume_propagate(i, 4);}

/*=============================================================================
	Diffuse
=============================================================================*/

TraceContext _TraceContextDiffuse(in CSIN i, in uint2 working_size)
{
    TraceContext o;   
         
    uint2 jitter_texel = (i.dispatchthreadid.xy & 63u) + uint2(FRAMECOUNT & 15u, (FRAMECOUNT >> 4) & 7u) * 64u;
    float3 seed_data = tex2Dfetch(sRTGI_STBN128_s, jitter_texel).xyz;
    o.jitter.x = seed_data.x; 
    o.texel = i.groupid.xy * 32 + int2(seed_data.yz * 255.0 + 0.5);    

    //need to recompute for the shuffled position
    //jitter_texel = (o.texel & 63u) + uint2(FRAMECOUNT & 15u, (FRAMECOUNT >> 4) & 7u) * 64u;
    o.jitter.yz = tex2Dfetch(sRTGI_STBN128, jitter_texel).xy;     

    o.uv        = pixel_idx_to_uv(o.texel, working_size); 
    o.depth     = Depth::get_linear_depth(o.uv);
    o.pos       = Camera::uv_to_proj(o.uv, Camera::depth_to_z(o.depth));
    o.normal    = Deferred::get_normals(o.uv);
    o.viewdir   = normalize(o.pos);
    o.geonormal = Deferred::get_geometry_normals(o.uv);
    o.pos *= 0.998; 

    return o;
}

float diffuse_sample_curve(float x)
{   
    float k = 5.0;
    return (exp2(k * x) - 1) / (exp2(k) - 1); 
}

float diffuse_sample_curve_inverse(float x)
{
    float k = 5.0;
    return log2(x * exp2(k) - x + 1) / k;
}

//quantized
#define FLOAT_TO_UINT_QUANTIZATION_SCALE     65536.0
#define NUM_DIRECTIONS                       64 //DO NOT CHANGE
#define TILE_DIMENSIONS                      8  //DO NOT CHANGE

groupshared float tgsm_pdf[1024];
groupshared float tgsm_cdf[1024];
groupshared uint  tgsm_pdf_accum[1024];

uint2 bitfieldocclusion64(float2 h_frontback, inout uint2 global_occlusion)
{
    float2 minh = linearstep(float2(0, 0.5), float2(0.5, 1), h_frontback.x);
    float2 maxh = linearstep(float2(0, 0.5), float2(0.5, 1), h_frontback.y);

    uint2 a = uint2(minh * 32);
    //uint3 b = ceil(saturate(maxh - minh) * 32);
    uint2 b = uint2(maxh * 32) - a;

    uint2 occlusion = ((1u << b) - 1u) << a;
    occlusion.x = b.x == 32 ? 0xFFFFFFFFu : occlusion.x; //full occlusion
    occlusion.y = b.y == 32 ? 0xFFFFFFFFu : occlusion.y; //full occlusion

    uint2 local_bitfield = global_occlusion & ~occlusion;
    uint2 changed_bits = local_bitfield ^ global_occlusion;
    global_occlusion = local_bitfield;
    return changed_bits;
}


float4 dir_to_sh(float3 v) 
{
    const float c0 = 0.5 * sqrt(1.0  / PI);
    const float c1 =       sqrt(0.75 / PI);
    return float4(c0, -c1 * v.y, c1 * v.z, -c1 * v.x);
}

//defaults to cosine convolution
float4 dir_to_irradiance_probe(float4 sh, const float sharpness = 1)
{
	const float c0 = 2 - sharpness;
	const float c1 = sharpness * 0.66666;
    return sh * float4(c0, c1.xxx);
}

float3 linear_eval_irradiance(float4 sh_r, float4 sh_g, float4 sh_b, float3 v, float sharpness)
{
    float4 sh_dir = dir_to_sh(v);
    sh_dir = dir_to_irradiance_probe(sh_dir, sharpness);//cosine conv
    return float3(dot(sh_r, sh_dir), dot(sh_g, sh_dir), dot(sh_b, sh_dir));
}

float4 trace_diffuse_cdf_cubic(TraceContext ctx)
{ 
    if(can_earlyout(ctx.depth))
         return 0;

    ctx.jitter.x = frac(ctx.jitter.x + Hash::uint_to_unorm(Hash::uhash(ctx.texel.x + ctx.texel.y * 195345)) / 255.0);  
    ctx.jitter.y = frac(ctx.jitter.y + Hash::uint_to_unorm(Hash::uhash(ctx.texel.y + ctx.texel.x * 195345)) / 255.0);  

    static const int quality_preset_steps[6] = {0, 4, 12, 18, 32, 40};//you think you want to tamper with this, but you don't  
    static const int quality_preset_rays[6] = {0, 1,  1,  1,  1,  1};//you think you want to tamper with this, but you don't  
   
    uint num_slices  = quality_preset_rays[DIFFUSE_GI_Q];
    uint sample_count = quality_preset_steps[DIFFUSE_GI_Q];

    float3 slice_dir = 0; sincos(ctx.jitter.x * PI / num_slices, slice_dir.x, slice_dir.y);  

    float slicesum = 1e-6;
    float T = RT_Z_THICKNESS * RT_Z_THICKNESS;  //arbitrary thickness that looks good relative to sample radius

    float mip_bias = log2(BUFFER_WIDTH_DLSS) - 5.0;

    float3 v = -ctx.viewdir;
    float3 n = ctx.normal; 

    int2 block_id = (ctx.texel % 32u) / TILE_DIMENSIONS;
    int num_blocks = 32 / TILE_DIMENSIONS;
    int flat_block_id = block_id.x + block_id.y * num_blocks;
    int block_start = flat_block_id * NUM_DIRECTIONS;

    float4 result = 0;    

    [loop]
    for(int slice_id = 0; slice_id < num_slices; slice_id++)
    {        
        float fi = float(slice_id + ctx.jitter.x) / num_slices;  
       
        int idx = block_start;
        idx = fi >= tgsm_cdf[idx + 32] ? idx + 32 : idx;
        idx = fi >= tgsm_cdf[idx + 16] ? idx + 16 : idx;
        idx = fi >= tgsm_cdf[idx +  8] ? idx +  8 : idx;      
        idx = fi >= tgsm_cdf[idx +  4] ? idx +  4 : idx;
        idx = fi >= tgsm_cdf[idx +  2] ? idx +  2 : idx;
        idx = fi >= tgsm_cdf[idx +  1] ? idx +  1 : idx;

        int local_idx = idx - block_start; 
        float cdf_this_bin = tgsm_cdf[idx];
        float cdf_next_bin = local_idx == (NUM_DIRECTIONS - 1) ? 1.0 : tgsm_cdf[idx + 1];
        float relative_pos_in_bracket = linearstep(cdf_this_bin, cdf_next_bin, fi);

        int idx_next_bin = (local_idx == (NUM_DIRECTIONS - 1)) ? block_start : idx + 1; //avoids modulo

        float pdf0 = tgsm_pdf[idx];
        float pdf1 = tgsm_pdf[idx_next_bin]; 
  
        //normalize removed here, check if bugs appear, see BAK Test 67
        float x = relative_pos_in_bracket;
        float icdf_this_bracket = (sqrt(lerp(pdf0*pdf0, pdf1*pdf1, x)) - pdf0) / (pdf1 - pdf0);//(-P + sqrt(max(0, P*P + (Q*Q - P*P) * x))) / (Q - P);

        float remapped_pos_in_bracket = abs(pdf1 - pdf0) < 1e-3 ? x : icdf_this_bracket; //avoid numerical instability  
        float pdf = lerp(pdf0, pdf1, remapped_pos_in_bracket);     

        float weight_this_bin = 1.0 - remapped_pos_in_bracket;
        float weight_next_bin = remapped_pos_in_bracket;           
        fi = (local_idx + remapped_pos_in_bracket) / NUM_DIRECTIONS;

        //actual body starts here
        sincos(fi * PI, slice_dir.y, slice_dir.x);        
      
        float3 ortho_dir = slice_dir - dot(slice_dir.xy, v.xy) * v; //z = 0 so no need for full dot3
        
        float3 slice_n = cross(ortho_dir, v);
        slice_n *= rsqrt(dot(slice_n, slice_n));  

        float2 scaled_dir = slice_dir.xy * BUFFER_ASPECT_RATIO_DLSS; //verified 110125

        float sin_n = dot(slice_n, n); //cos between slice normal and normal == sin between normal projected on slice vs normal itself
        float3 n_proj_on_slice = n - slice_n * sin_n;
        float proj_n_len = sqrt(saturate(1 - sin_n * sin_n));
        float cosn = saturate(dot(n_proj_on_slice, v) * rcp(proj_n_len+1e-6));
       
        float normal_angle = Math::fast_acos(cosn);
        normal_angle = dot(ortho_dir, n_proj_on_slice) > 0 ? normal_angle : -normal_angle;
        float sliceweight = max(0, (cosn + normal_angle * sin(normal_angle)) * proj_n_len);

        uint2 occlusion_bitfield = 0xFFFFFFFF;
   
        float2 initial_step = slice_dir.xy * BUFFER_PIXEL_SIZE_DLSS;
        float4 slice_result = 0.0;

        [unroll]
        for(int side = 0; side < 2; side++)
        {    
            float2 limit_uv = Math::aabb_hit_01(ctx.uv, scaled_dir);
            float2 uv_delta = abs(limit_uv - ctx.uv);

            float dist_to_edge = length(uv_delta / BUFFER_ASPECT_RATIO_DLSS);
            int num_samples_this_dir = 1 + int(diffuse_sample_curve_inverse(dist_to_edge) * sample_count);           

            [loop]         
            for(int _sample = 0; _sample <= num_samples_this_dir; _sample++)
            { 
                float2 s = saturate((_sample + float2(0, 0.5) + ctx.jitter.y * 0.5) / sample_count); //yes actually sample count
                s.x = diffuse_sample_curve(s.x);
                s.y = diffuse_sample_curve(s.y); 
                s = min(s, dist_to_edge);  

                float mip = (log2(s.y) + mip_bias);   
                mip += ctx.jitter.z - 0.5;                       

                float4 tap_uvs;
                tap_uvs.xy = ctx.uv + initial_step + scaled_dir * s.x;
                tap_uvs.zw = ctx.uv + initial_step + scaled_dir * s.y;
                //if(!all(saturate(tap_uvs[1] - tap_uvs[1] * tap_uvs[1]))) break;

                float2 zvals;
                zvals.x = tex2Dlod(sRTGI_ZSrcTex, tap_uvs.xy, min(mip, 5)).x;
                zvals.y = tex2Dlod(sRTGI_ZSrcTex, tap_uvs.zw, min(mip, 5)).x;
  
                [unroll]
                for(int pair = 0; pair < 2; pair++)
                {
                    float2 tap_uv = tap_uvs.xy;
                    float zz = zvals.x;
           
                    tap_uvs.xy = tap_uvs.zw;
                    zvals.x = zvals.y;    
   
                    float3 Lp = Camera::uv_to_proj(tap_uv, zz);               

                    float3 L1 = Lp - ctx.pos;
                    float3 L2 = L1 + Lp * T; //* (1 + T)

                    float L1L1 = dot(L1, L1);
                    float L2L2 = dot(L2, L2);

                    L1 *= rsqrt(dot(L1, L1)); //we need normalized L1 later
                    float2 h = float2(dot(L1, v), dot(L2, v) * rsqrt(dot(L2, L2))); //divide by length rather than normalize vector first, faster on scalar hardware

                    h = side ? (h * 0.25 + 0.25) : (h.yx * -0.25 + 0.75);
                    h.x = tex2Dlod(sRTGI_HorizonLUT, float2(h.x, normal_angle / PI + 0.5), 0).x;
                    h.y = tex2Dlod(sRTGI_HorizonLUT, float2(h.y, normal_angle / PI + 0.5), 0).x;   
                        
                    h = saturate(h + QMC::roberts1(slice_id, ctx.jitter.z) / 64.0);
                    uint2 changed_bits = bitfieldocclusion64(h, occlusion_bitfield); 

                    [branch]
                    if(any(changed_bits) && dot(L1, ctx.geonormal) > 0) //we need the latter to avoid self-occlusion weirdness               
                    {
                        float3 uvz = (min(max(mip - 2, 0), 5) + float3(0, 6, 12) + 0.5) / 18.0;    
                        float4 shr = tex3Dlod(sRTGI_RadianceVolume, float4(tap_uv, uvz.x, 0));
                        float4 shg = tex3Dlod(sRTGI_RadianceVolume, float4(tap_uv, uvz.y, 0));
                        float4 shb = tex3Dlod(sRTGI_RadianceVolume, float4(tap_uv, uvz.z, 0)); 

                        float2 bits = countbits(changed_bits);
                        float hit = (bits.x + bits.y) / 64.0; 
                           
                        float4 hit_rgba;                        
                        hit_rgba.rgb = max(4 * SphericalHarmonics::linear_eval_irradiance(shr, shg, shb, -L1, 2), 0);      
                        hit_rgba.a = 1; 
                        slice_result += hit_rgba * hit * sliceweight;           
                    }                              
                }          
            }
     
            scaled_dir = -scaled_dir;
            initial_step = -initial_step;
        }

        slice_result.w = 1 - slice_result.w; //works better for the importance sampling
     
        float target_pdf = dot(slice_result.rgb, float3(0.2125, 0.7126, 0.0722));

        //target_pdf = TURN_ON_THE_MAGIC ? target_pdf : 1.0; 
        atomicAdd(tgsm_pdf_accum[idx],          uint(target_pdf / pdf * (1.0 - relative_pos_in_bracket) * FLOAT_TO_UINT_QUANTIZATION_SCALE));
        atomicAdd(tgsm_pdf_accum[idx_next_bin], uint(target_pdf / pdf *        relative_pos_in_bracket  * FLOAT_TO_UINT_QUANTIZATION_SCALE));      
        result += slice_result / (pdf * NUM_DIRECTIONS + 1e-4);                 
    }
   
    result /= num_slices;
    return result;
}

void TraceWrapCubicCS(in CSIN i)
{    
    if(!DIFFUSE_GI_Q) return;

    int num_blocks = 32 / TILE_DIMENSIONS;
 
    //these are for the builder threads only, for writing the CDF we use the ids based off the shuffled pixels
    int id_in_block = i.threadid % NUM_DIRECTIONS;
    int block_start = i.threadid - id_in_block;
    int block_end   = block_start + (NUM_DIRECTIONS - 1);
    int2 pdf_storage_pos = i.groupid.xy * 32 + int2(i.threadid % 32, i.threadid / 32);

    float prev_pdf = tex2Dfetch(stRTGI_STSG_Cache, pdf_storage_pos).x;
    tgsm_pdf_accum[i.threadid] = 0;   
    tgsm_pdf[i.threadid] = prev_pdf + 0.005; //choke, do not change  
    barrier();

    //init cubic prefix sum nodes, then perform sklansky style prefix sum
    if(id_in_block == 0)
        tgsm_cdf[i.threadid] = 0;
    else 
        tgsm_cdf[i.threadid] = (tgsm_pdf[i.threadid - 1] + tgsm_pdf[i.threadid]) * 0.5;
    
    barrier();
        
    [unroll]
    for(uint b = 1, m = 0; b < NUM_DIRECTIONS; barrier())
    {
        uint b2 = b * 2; uint m2 = b2 - 1; 
        if(i.threadid & b)       
            tgsm_cdf[i.threadid] += tgsm_cdf[(i.threadid & ~m2) + m];
        b = b2, m = m2;              
    }
    
    //normalize both PDF and CDF
    //the exclusive prefix sum for cubic interpolation is missing 0.5x the first and last entry
    float pdf_integral = tgsm_cdf[block_end]
                       + 0.5 * tgsm_pdf[block_start]
                       + 0.5 * tgsm_pdf[block_end];    
    barrier(); 
    tgsm_pdf[i.threadid] /= pdf_integral;
    tgsm_cdf[i.threadid] /= pdf_integral;   
    barrier();

    //actually perform the GI trace
    TraceContext ctx = _TraceContextDiffuse(i, BUFFER_SCREEN_SIZE_DLSS);

    float4 gi = 0.0;
    if(check_boundaries(ctx.texel, BUFFER_SCREEN_SIZE_DLSS))     
        gi = trace_diffuse_cdf_cubic(ctx); 
    gi.rgb = linear_to_ycocg(gi.rgb);

    int2 write_id = ctx.texel & 31u;
    int write_thread = write_id.x + write_id.y * 32;

    tgsm_cdf[write_thread] = gi.x;barrier();gi.x = tgsm_cdf[i.threadid];barrier();   
    tgsm_cdf[write_thread] = gi.y;barrier();gi.y = tgsm_cdf[i.threadid];barrier(); 
    tgsm_cdf[write_thread] = gi.z;barrier();gi.z = tgsm_cdf[i.threadid];barrier(); 
    tgsm_cdf[write_thread] = gi.w;barrier();gi.w = tgsm_cdf[i.threadid];barrier(); 

    tex2Dstore(stRTGI_Aux0, i.dispatchthreadid.xy, gi);
    barrier();

    //read back the collected PDF values of current frame and normalize
    float curr_pdf = float(tgsm_pdf_accum[i.threadid]) / FLOAT_TO_UINT_QUANTIZATION_SCALE;
    tgsm_pdf[i.threadid] = curr_pdf;
    barrier();
    
    [unroll]for(int stride = NUM_DIRECTIONS / 2; stride > 0; stride >>= 1)
    {
        if(id_in_block < stride)
            tgsm_pdf[i.threadid] += tgsm_pdf[i.threadid + stride];
        barrier();
    }

    curr_pdf /= tgsm_pdf[block_start] + 1e-8; 

    //output interpolated PDF
    float integrated_pdf = lerp(prev_pdf, curr_pdf, 0.1);
    tex2Dstore(stRTGI_STSG_Cache, pdf_storage_pos, integrated_pdf);    
}

/*=============================================================================
	Specular
=============================================================================*/

TraceContext _TraceContextDiffuseSpecular(int2 texel, in uint2 working_size)
{
    TraceContext o;
    o.texel     = texel;
    o.jitter    = tex2Dfetch(sRTGI_STBN128, (texel & 63u) + uint2(FRAMECOUNT & 15u, (FRAMECOUNT >> 4) & 7u) * 64u).xyz;   
    o.uv        = pixel_idx_to_uv(o.texel, working_size); 
    o.depth     = Depth::get_linear_depth(o.uv);
    o.pos       = Camera::uv_to_proj(o.uv, Camera::depth_to_z(o.depth));
    o.normal    = Deferred::get_normals(o.uv);
    o.viewdir   = normalize(o.pos);
    o.geonormal = Deferred::get_geometry_normals(o.uv);
    o.pos *= 0.998; 

    return o;
}

float hyperbolize_depth(float z)
{
    float f = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
    return f * (z * rcp(1 + z * (f - 1)));
}

float linearize_depth(float x)
{
    x /= RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - x * (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - 1.0); 
    return x;
}

float2 transform_to_storage(float2 minmax_z)
{
    minmax_z = abs(minmax_z); //flip sign since we did min() for both min and max
    //minmax_z *= 1.001; //bias Z a bit here, we can't do that later on delinearized depth

    float thickness = RT_Z_THICKNESS * RT_Z_THICKNESS * minmax_z.y;//RT_Z_THICKNESS * RT_Z_THICKNESS * (1 + minmax_z.x * 0.01);

    minmax_z.y = Camera::z_to_depth(minmax_z.y + thickness);        
    minmax_z.y = hyperbolize_depth(minmax_z.y);
    minmax_z.x = Camera::z_to_depth(minmax_z.x);
    minmax_z.x = hyperbolize_depth(minmax_z.x);

    return minmax_z;   
}

groupshared float2 z_tgsm[32*32];

void SpecularHiZDownsampleCS(in CSIN i)
{
     //remap 32x32 threads to morton order
    i.dispatchthreadid.xy = i.groupid.xy * 32u + morton_idx_to_xy(i.threadid);

    //reducing 32x32 to 1x1 equals 32² -> 16² -> 8² -> 4² -> 2² -> 1² = 5 mipmaps
    //so to create 7 mipmaps, we need to downsample 2 times i.e. each thread needs to reduce 4x4 pixels first
    float2 local_minmax = 1e10; //min / max of thread-local 4x4 block. .y is negated to compute min directly

    [unroll]
    for(int quad = 0; quad < 4; quad++)
    {
        //repeat logic inside the 4x4 block, i.e. order pixels by morton index
        //here we tex2Dgather each 2x2 subblock, but for a regular reduce pass, they'd be sampled directly
        uint2 quad_offset = morton_idx_to_xy(quad);
        uint2 global_pos = i.dispatchthreadid.xy * 4 + quad_offset * 2;

        float2 quad_topleft_uv = saturate((global_pos + 0.5) * BUFFER_PIXEL_SIZE_DLSS);
        float2 corrected_uv = Depth::correct_uv(quad_topleft_uv);
        corrected_uv.y -= BUFFER_PIXEL_SIZE_DLSS.y * 0.5;    //shift upwards since gather looks down and right

#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
    corrected_uv.y -= BUFFER_PIXEL_SIZE_DLSS.y * 0.5;    //shift upwards since gather looks down and right
    float4 quad_texels = tex2DgatherR(DepthInput, corrected_uv).wzyx;  
#else
    float4 quad_texels = tex2DgatherR(DepthInput, corrected_uv);
#endif
        quad_texels = Depth::linearize(quad_texels);
        //gather order is wack      
        
        quad_texels.w = Camera::depth_to_z(quad_texels.w);       
        tex2Dstore(stRTGI_HiZMipChain0, global_pos + uint2(0, 0), transform_to_storage(quad_texels.ww).xyyy);
        quad_texels.x = Camera::depth_to_z(quad_texels.x);
        tex2Dstore(stRTGI_HiZMipChain0, global_pos + uint2(0, 1), transform_to_storage(quad_texels.xx).xyyy);
        quad_texels.z = Camera::depth_to_z(quad_texels.z);
        tex2Dstore(stRTGI_HiZMipChain0, global_pos + uint2(1, 0), transform_to_storage(quad_texels.zz).xyyy);
        quad_texels.y = Camera::depth_to_z(quad_texels.y);
        tex2Dstore(stRTGI_HiZMipChain0, global_pos + uint2(1, 1), transform_to_storage(quad_texels.yy).xyyy);

        //if we were doing a regular single pass downsample, we could skip everything until here, where we reduce the 2x2 quad and write it

        float2 quad_minmax = float2(minc(quad_texels), maxc(quad_texels));
        tex2Dstore(stRTGI_HiZMipChain1, global_pos / 2, transform_to_storage(quad_minmax).xyxy);

        local_minmax = min(local_minmax, float2(quad_minmax.x, -quad_minmax.y));
    }

    tex2Dstore(stRTGI_HiZMipChain2, i.dispatchthreadid.xy, transform_to_storage(local_minmax).xyxy);
    z_tgsm[i.threadid] = local_minmax;
    barrier();

    if(!(i.threadid & 3))
    {
        [unroll]for(int j = 1; j < 4; j++) local_minmax = min(local_minmax, z_tgsm[i.threadid + j * 1]);
        tex2Dstore(stRTGI_HiZMipChain3, i.dispatchthreadid.xy / 2, transform_to_storage(local_minmax).xyxy);
        z_tgsm[i.threadid] = local_minmax;
    }
    barrier();
    if(!(i.threadid & 15))
    {
        [unroll]for(int j = 1; j < 4; j++) local_minmax = min(local_minmax, z_tgsm[i.threadid + j * 4]);        
        tex2Dstore(stRTGI_HiZMipChain4, i.dispatchthreadid.xy / 4, transform_to_storage(local_minmax).xyxy);
        z_tgsm[i.threadid] = local_minmax;
    }
    barrier();
    if(!(i.threadid & 63))
    {
        [unroll]for(int j = 1; j < 4; j++) local_minmax = min(local_minmax, z_tgsm[i.threadid + j * 16]);
        tex2Dstore(stRTGI_HiZMipChain5, i.dispatchthreadid.xy / 8, transform_to_storage(local_minmax).xyxy);
        z_tgsm[i.threadid] = local_minmax;
    }
    barrier();
    if(!(i.threadid & 255))
    {
        [unroll]for(int j = 1; j < 4; j++) local_minmax = min(local_minmax, z_tgsm[i.threadid + j * 64]);
        tex2Dstore(stRTGI_HiZMipChain6, i.dispatchthreadid.xy / 16, transform_to_storage(local_minmax).xyxy);
        z_tgsm[i.threadid] = local_minmax;
    }
    barrier();
    if(!(i.threadid & 1023))
    {
        [unroll]for(int j = 1; j < 4; j++) local_minmax = min(local_minmax, z_tgsm[i.threadid + j * 256]);        
        tex2Dstore(stRTGI_HiZMipChain7, i.dispatchthreadid.xy / 32, transform_to_storage(local_minmax).xyxy);
        //z_tgsm[i.threadid] = local_minmax;
    }
    //barrier();
}

float4 trace_hiz(TraceContext ctx, float3 raydir_vs)
{  
    float3 origin_vs = ctx.pos + ctx.normal * ctx.pos.z * 0.005;
    float3 end_vs = origin_vs + raydir_vs;
 
    float3 origin_ss = float3(Camera::proj_to_uv(origin_vs), hyperbolize_depth(Camera::z_to_depth(origin_vs.z)));
    float3 end_ss = float3(Camera::proj_to_uv(end_vs), hyperbolize_depth(Camera::z_to_depth(end_vs.z)));

    float3 delta_ss = normalize(end_ss - origin_ss); 
    float3 step = Math::fast_sign(delta_ss);
    float2 step_offset = BUFFER_PIXEL_SIZE_DLSS * step.xy * 0.999; //nudge a bit inside to fix some outlines
    step = saturate(step);
    float3 delta_ss_inv = rcp(delta_ss);
    delta_ss_inv = abs(delta_ss_inv) < 0.000001.xxx ? 0.0.xxx : delta_ss_inv;
    
    float curr_t = 0; 
    int curr_mip = 0;

    [loop]
    for(int j = 0; j < 1024 && curr_mip >= 0; j++)
    {
        float2 curr_uv        = origin_ss.xy + delta_ss.xy * curr_t; 
        if(!Math::inside_screen(curr_uv)) break;

        float2 curr_layer_res = BUFFER_SCREEN_SIZE_DLSS * exp2(-curr_mip); 
        float2 curr_texel     = floor(curr_uv * curr_layer_res);

        float2 zminmax = tex2Dfetch(sRTGI_HiZMipChain, int2(curr_texel), curr_mip).xy;  
        float2 tminmax_z = (zminmax - origin_ss.z) * delta_ss_inv.z; 

        float2 t = ((curr_texel + step.xy) / curr_layer_res + step_offset - origin_ss.xy) * delta_ss_inv.xy;
        float tmin_xy = min(t.x, t.y);   

        [flatten]
        if(tminmax_z.x < tmin_xy && curr_t <= tminmax_z.y)
        {
            curr_t = max(curr_t, tminmax_z.x);
            --curr_mip;
        }
        else
        {
            curr_t = tmin_xy;
            curr_mip = min(++curr_mip, 7);           
        }
    }
 
    float3 hitp_ss = origin_ss + delta_ss * curr_t;

    //convert to view space to figure out exact ray length

    float3 hitp_vs;    
    hitp_vs.z = Camera::depth_to_z(linearize_depth(hitp_ss.z));
    hitp_vs = Camera::uv_to_proj(hitp_ss.xy, hitp_vs.z);

    //ray-ray intersection + vector algebra bonanza to get rid of cross products etc.
    float A = dot(origin_vs, raydir_vs);
    float B = dot(hitp_vs, raydir_vs);
    float C = dot(hitp_vs, origin_vs);
    float D = dot(hitp_vs, hitp_vs); 
    float hit_t_vs = (B * C - D * A) * rcp(D - B * B);

    bool hit = curr_mip < 0 ? 1 : 0;
    return float4(hitp_ss.xy, hit_t_vs, hit);//uv, t, hit
}

#define GGX_GROUP_SIZE 16

void SpecularTraceCS(in CSIN i)
{
    if(!SPECULAR_GI_Q) return;
    i.dispatchthreadid.xy = i.groupid.xy * GGX_GROUP_SIZE + morton_idx_to_xy(i.threadid);
    TraceContext ctx = _TraceContextDiffuseSpecular(i.dispatchthreadid.xy, BUFFER_SCREEN_SIZE_DLSS); 
    if(can_earlyout(ctx.depth)) return;

    static const int quality_preset_rays[5] = {0, 1, 2, 4, 8};//you think you want to tamper with this, but you don't  
    int num_rays = quality_preset_rays[SPECULAR_GI_Q];

    float3 V = -ctx.viewdir;
    float3 N = ctx.normal;
    float NdotV = saturate(dot(V, N) - 0.001) + 0.001;
    float alpha = GGX_ALPHA;

    float4 result = 0;
    float4 first_hit_data = 0;

    float3 strat = QMC::get_stratificator(num_rays);
    bool fake_raytracing = true;//USE_FAKE_RAY_TRACING;//true; //REDDIT WAS RIGHT OMGOMGOMG CAUGHT IN 8K 
    
    [loop]
    for(int r = 0; r < num_rays; r++)    
    {
        float2 rand = QMC::roberts2(r, ctx.jitter.xy);    

        float pdf_ratio;
        float3 H = BXDF::GGX::sample_vndf_bounded_iso(V, N, alpha, rand.xy, 0.7, pdf_ratio);
        float3 L = reflect(-V, H);   
 
        float VdotH = saturate(dot(V, H));
        float NdotL = saturate(dot(L, N)); 

        float F0 = 0.04;
        float F = BXDF::fresnel_schlick(VdotH, F0);
        float G2overG1 = BXDF::GGX::smith_G2_over_G1_heightcorrelated(alpha, NdotL, NdotV);             
        float estimator = pdf_ratio * F * G2overG1;

        estimator *= saturate(L.z); //only allow forward rays, makes it easier in HiZ tracing too
        estimator *= step(0, dot(L, ctx.geonormal)); 

        if(!(estimator > 0.001)) continue; //if we do it this way, NaNs are also avoided as x > NaN is always false       

        float4 hit_data = 0;
        
        if(!fake_raytracing || r == 0)
        {
            hit_data = trace_hiz(ctx, L);
            first_hit_data = hit_data;
        }
        else
        {
            //at last, fake ray tracing. The haters were right after all!
            float hit_t = first_hit_data.z;
            float3 virtual_hitp = ctx.pos + L * hit_t;
            float2 virtual_hit_uv = Camera::proj_to_uv(virtual_hitp);  
            hit_data = float4(virtual_hit_uv, hit_t, first_hit_data.w);      
        } 

        if(hit_data.w > 0.5)
        {
            float3 hit_n = Deferred::get_geometry_normals(hit_data.xy);
            float facing = saturate(dot(-hit_n, L) * 32);  
            float3 irradiance = unpack_hdr(tex2Dlod(ColorInput, hit_data.xy, 0).rgb);
            result.rgb += irradiance * facing * estimator * hit_data.w;
            result.w += hit_data.z;
        }
    }

    result /= num_rays; 

    //can't be arsed anymore...
    if(isnan(dot(result, 1)) || isinf(dot(result, 1))) result = 0;

    result.rgb /= get_brdf(NdotV, alpha);
    result.rgb = linear_to_ycocg(result.rgb);
    tex2Dstore(stRTGI_Aux1, i.dispatchthreadid.xy, result);
}

/*=============================================================================
	Temporal Reproj etc.
=============================================================================*/

groupshared float4 moments_tgsm[32*32];

void compute_spatial_moments(in CSIN i, sampler s_curr, sampler s_prev, storage st_output)
{
    int2 grid_start = i.groupid.xy * 16;
    int2 grid_offset = i.groupthreadid.xy;
    float3 lc = float3(0.299, 0.587, 0.114);

    [unroll]for(int x = 0; x <= 16; x += 16) 
    [unroll]for(int y = 0; y <= 16; y += 16) 
    {
        int2 p = grid_start + grid_offset + (int2(x, y) - 8); 

        float4 m;        
        m.x = tex2Dfetch(s_curr, p).x; //TODO gather4
        m.z = tex2Dfetch(s_prev, p).x; 
        m.yw = m.xz * m.xz;

        int2 offset_in_smem = grid_offset + int2(x, y);
        moments_tgsm[offset_in_smem.y * 32 + offset_in_smem.x] = m;
    }
    barrier();

    //for proper gaussian blur, the entire horizontal strip also beyond the tile boundary 
    //needs to perform a blur. So each thread performs the blur for 2 texels.

    //for vertical blur, we process the entire 32x16 horizontal strip
    int2 pos_in_smem_L = grid_offset + int2(0,  8);
    int2 pos_in_smem_R = grid_offset + int2(16, 8);

    int flat_pos_in_smem_L = pos_in_smem_L.y * 32 + pos_in_smem_L.x;
    int flat_pos_in_smem_R = pos_in_smem_R.y * 32 + pos_in_smem_R.x;

    float4 blur_result_L = 0;
    { 
        float wsum = 0;
        
        [unroll]
        for(int y = -5; y <= 5; y++)
        {
            float g = exp(-(y*y)/(5.0*5.0)*2.3 * 0.5);           
            float4 m = moments_tgsm[flat_pos_in_smem_L + y * 32];  
            blur_result_L += m * g;   
            wsum += g; 
        }

        blur_result_L /= wsum;
    }

    float4 blur_result_R = 0;
    {    
        float wsum = 0;

        [unroll]
        for(int y = -5; y <= 5; y++)
        {
            float g = exp(-(y*y)/(5.0*5.0)*2.3 * 0.5);
            float4 m = moments_tgsm[flat_pos_in_smem_R + y * 32];  
            blur_result_R += m * g;
            wsum += g;             
                        
        }
        blur_result_R /= wsum;
    }

    barrier();
    //write back to smem
    moments_tgsm[flat_pos_in_smem_L] = blur_result_L;
    moments_tgsm[flat_pos_in_smem_R] = blur_result_R;
    barrier();
    //now we only need to perform the horizonal blur for the central tile.

    int2 pos_in_smem = grid_offset + int2(8, 8);
    int flat_pos_in_smem = pos_in_smem.y * 32 + pos_in_smem.x;
    float4 blur_result = 0;

    {
        float wsum = 0;
        [unroll]
        for(int x = -5; x <= 5; x++)
        {
            float g = exp(-(x*x)/(5.0*5.0)*2.3 * 0.5);      
            float4 m = moments_tgsm[flat_pos_in_smem + x];  
            blur_result += m * g; 
            wsum += g;       
        }

        blur_result /= wsum;        
    }

    float curr_variance = max(0, blur_result.y - blur_result.x * blur_result.x);
    float prev_variance = max(0, blur_result.w - blur_result.z * blur_result.z);

    curr_variance = sqrt(curr_variance);
    prev_variance = sqrt(prev_variance);

    blur_result.y = curr_variance;
    blur_result.w = prev_variance;

    tex2Dstore(st_output, i.dispatchthreadid.xy, blur_result); 
}

void SpatialMomentsDiffCS(in CSIN i)
{
    compute_spatial_moments(i, sRTGI_Aux0, sRTGI_AccumDiff, stRTGI_SpatialMomentsDiff);
}

void SpatialMomentsSpecCS(in CSIN i)
{
    compute_spatial_moments(i, sRTGI_Aux1, sRTGI_AccumSpec, stRTGI_SpatialMomentsSpec);
}

float4 bilinear_split(float2 uv, float2 texsize)
{
    return float4(floor(uv * texsize - 0.5), frac(uv * texsize - 0.5));
}

float4 get_bilinear_weights(float4 bilinear)
{
    float4 w = float4(bilinear.zw, 1 - bilinear.zw);
    return w.zxzx * w.wwyy;
}

void TemporalIntegrateNewPS(in VSOUT i, out PSOUT3 o)
{
    float2 prev_uv = i.uv + Deferred::get_motion(i.uv);
    //prev_uv = i.uv + BUFFER_PIXEL_SIZE_DLSS * float2(0, 1);
    bool inside_screen = Math::inside_screen(prev_uv); 
    bool2 valid_history = inside_screen;

    float3 n = Deferred::get_normals(i.uv);
    float z = Camera::depth_to_z(Depth::get_linear_depth(i.uv)); 

    float4 prev_diff = 0;//rgb, variance
    float4 prev_spec = 0;//rgb, variance
    float  prev_rtao = 0;//ao, duh

    [branch]
    if(inside_screen)
    {
        int2 prev_bilinear_texel = floor(prev_uv * BUFFER_SCREEN_SIZE_DLSS - 0.5);
        float2 prev_bilinear = frac(prev_uv * BUFFER_SCREEN_SIZE_DLSS - 0.5);

        float4 bilinear_weights; 
        bilinear_weights.x = (1 - prev_bilinear.x) * (1 - prev_bilinear.y);
        bilinear_weights.y =      prev_bilinear.x  * (1 - prev_bilinear.y);
        bilinear_weights.z = (1 - prev_bilinear.x) *      prev_bilinear.y;
        bilinear_weights.w =      prev_bilinear.x  *      prev_bilinear.y;

        //float4 prev_rtao_00_10_01_11;
        float4 prevgbuf00 = tex2Dfetch(sRTGI_GBufferPrev, prev_bilinear_texel + int2(0, 0));
        float4 prevgbuf10 = tex2Dfetch(sRTGI_GBufferPrev, prev_bilinear_texel + int2(1, 0));
        float4 prevgbuf01 = tex2Dfetch(sRTGI_GBufferPrev, prev_bilinear_texel + int2(0, 1));
        float4 prevgbuf11 = tex2Dfetch(sRTGI_GBufferPrev, prev_bilinear_texel + int2(1, 1));

        float4 prevz = tex2DgatherR(sRTGI_GBufferPrev, prev_uv).wzxy;//depth is in .x
           
        float4 zdelta = abs(prevz - z) / max(1e-6, max(prevz, z));
        float4 wz = exp2(-zdelta * 32.0);

        float4 ndelta;
        ndelta.x = dot(n, Math::octahedral_dec(prevgbuf00.yz)); //gbuffer is depth, normal XY oct, RTAO
        ndelta.y = dot(n, Math::octahedral_dec(prevgbuf10.yz));
        ndelta.z = dot(n, Math::octahedral_dec(prevgbuf01.yz));
        ndelta.w = dot(n, Math::octahedral_dec(prevgbuf11.yz));      

        float4 wn_spec = step(0, ndelta);
        float4 bilateral_weights_spec = wn_spec * wz;
        float4 kernel_weights_spec = bilateral_weights_spec * bilinear_weights;
        float kernel_wsum_spec = dot(1, kernel_weights_spec);
        kernel_weights_spec /= 1e-6 + kernel_wsum_spec;

        if(kernel_wsum_spec > 0.1)
        {
            prev_spec += tex2Dfetch(sRTGI_AccumSpec, prev_bilinear_texel + int2(0, 0)) * kernel_weights_spec.x;
            prev_spec += tex2Dfetch(sRTGI_AccumSpec, prev_bilinear_texel + int2(1, 0)) * kernel_weights_spec.y;
            prev_spec += tex2Dfetch(sRTGI_AccumSpec, prev_bilinear_texel + int2(0, 1)) * kernel_weights_spec.z;
            prev_spec += tex2Dfetch(sRTGI_AccumSpec, prev_bilinear_texel + int2(1, 1)) * kernel_weights_spec.w;     
        }
        else 
        {
            valid_history.y = false;
        }

        float limit = 95.0;
        float lowlimit = 85.0;      

        float4 wn_diff = linearstep(limit, lowlimit, degrees(ndelta));     

        float4 bilateral_weights_diff = wn_diff * wz;
        float4 kernel_weights_diff = bilateral_weights_diff * bilinear_weights;               
        float kernel_wsum_diff = dot(1, kernel_weights_diff);
        kernel_weights_diff /= 1e-6 + kernel_wsum_diff;

        //use prevous reproj and interpolate
        [branch]
        if(kernel_wsum_diff > 0.01)
        {
            prev_diff += tex2Dfetch(sRTGI_AccumDiff, prev_bilinear_texel + int2(0, 0)) * kernel_weights_diff.x;
            prev_diff += tex2Dfetch(sRTGI_AccumDiff, prev_bilinear_texel + int2(1, 0)) * kernel_weights_diff.y;
            prev_diff += tex2Dfetch(sRTGI_AccumDiff, prev_bilinear_texel + int2(0, 1)) * kernel_weights_diff.z;
            prev_diff += tex2Dfetch(sRTGI_AccumDiff, prev_bilinear_texel + int2(1, 1)) * kernel_weights_diff.w; 
      
            //get RTAO from alpha of previous gbuffer
            prev_rtao = dot(float4(prevgbuf00.w, prevgbuf10.w, prevgbuf01.w, prevgbuf11.w), kernel_weights_diff);    
        }        
        else //try to find _some_ fill-in data
        {
            float best_score = 0;
            float2 candidate_best_uv = i.uv;

            [loop]for(int j = 0; j < 16; j++)
            {
                float2 fi = float2(QMC::roberts1(j), j / 16.0 + 0.5 / 16.0);
                fi = QMC::roberts2(FRAMECOUNT % 16, fi);
                
                float2 offs = BXDF::sample_disc(fi);
                offs *= BUFFER_PIXEL_SIZE_DLSS * 10.0;

                float4 prev_gbuffer = tex2Dlod(sRTGI_GBufferPrev, i.uv + offs, 0);  

                float3 tap_n = Math::octahedral_dec(prev_gbuffer.yz);
                float tap_z = prev_gbuffer.x;          

                float wz = abs(tap_z - z) / max3(tap_z, z, 1e-6);
                wz = exp2(-wz * 32.0);
                float wn = Math::fast_acos(saturate(dot(n, tap_n))); 
                float weight_diff = exp(-wn * 5) * wz;//different, more relaxed weight here. We just want to fill in the blanks

                if(weight_diff > best_score)
                {
                    best_score = weight_diff;
                    candidate_best_uv = i.uv + offs;
                }
            }

            [branch]
            if(best_score > 0.05)
            {
                prev_uv = candidate_best_uv;
                prev_diff = tex2Dlod(sRTGI_AccumDiff, prev_uv, 0);
                prev_spec = tex2Dlod(sRTGI_AccumSpec, prev_uv, 0);
                prev_rtao = tex2Dlod(sRTGI_GBufferPrev, prev_uv, 0).a;        
            }
            else //no substitute found, rip.
            {
                valid_history.x = false;
            }
        }       
    }

    //fill in the data for gbuffer already
    o.t2.x = z;
    o.t2.yz = Math::octahedral_enc(n);

    int mip = inside_screen ? 0 : 3;

    //[branch]
    //if(valid_history)
    {
        float4 tmpcurr = tex2Dlod(sRTGI_Aux0, i.uv, mip); //currently, AO is still in alpha here

        float3 curr_diff = tmpcurr.rgb;
        float3 curr_spec = tex2Dlod(sRTGI_Aux1, i.uv, mip).rgb;
        float curr_rtao  = tmpcurr.w;

        //diff
        if(valid_history.x && DIFFUSE_GI_Q)
        {
            float X = prev_diff.x;
            float Y = curr_diff.x; 

            float2 currdata = tex2Dlod(sRTGI_SpatialMomentsDiff, i.uv, 0).xy;
            float2 prevdata = tex2Dlod(sRTGI_SpatialMomentsDiff, prev_uv, 0).zw;

            float bias = abs(currdata.x - prevdata.x);
            float var_x = prevdata.y * prevdata.y;
            float var_y = currdata.y * currdata.y; 
            float denom = exp2(-32.0) + var_x + var_y + bias * bias; //yes it actually needs such a ridiculous epsilon

            float alpha = saturate(1.0 - var_y / denom);
            alpha = clamp(alpha, 0.01, 0.15);

            float temporal_var = (X - Y) * (lerp(X, Y, alpha) - Y);
            temporal_var *= alpha * 0.5; //this makes it equivalent to spatial variance
            temporal_var *= VARIANCE_FP16_QUANTIZATION_SCALE;

            //diff
            o.t0 = lerp(prev_diff, float4(curr_diff, temporal_var), alpha);

            //rtao
            o.t2.w = lerp(prev_rtao, curr_rtao, alpha); //reuse diffuse alpha for this
        }
        else 
        {           
            float Y = curr_diff.x;     
            o.t0.xyz = curr_diff.rgb;
            o.t0.w = Y * Y * VARIANCE_FP16_QUANTIZATION_SCALE;  //in case of no temporal history, this substitutes a value that is plausible
            o.t2.w = curr_rtao;//rtao -> alpha of gbuffer
        }
        //spec
        if(valid_history.y && SPECULAR_GI_Q)
        {
            float X = prev_spec.x;
            float Y = curr_spec.x;

            float2 currdata = tex2Dlod(sRTGI_SpatialMomentsSpec, i.uv, 0).xy;
            float2 prevdata = tex2Dlod(sRTGI_SpatialMomentsSpec, prev_uv, 0).zw;

            float bias = abs(currdata.x - prevdata.x);
            float var_x = prevdata.y * prevdata.y;
            float var_y = currdata.y * currdata.y; 
            float denom = exp2(-32.0) + var_x + var_y + bias * bias; //yes it actually needs such a ridiculous epsilon

            float alpha = saturate(1.0 - var_y / denom);
            //alpha = lerp(1, alpha, saturate(4 * sqrt(GGX_ALPHA)));            
            alpha = clamp(alpha,0.02, 0.99);

            float temporal_var = (X - Y) * (lerp(X, Y, alpha) - Y);
            temporal_var *= alpha * 0.5; //this makes it equivalent to spatial variance
            temporal_var *= VARIANCE_FP16_QUANTIZATION_SCALE;

            //diff
            o.t1 = lerp(prev_spec, float4(curr_spec, temporal_var), alpha);
        }
        else 
        {
            float Y = curr_spec.x;
            o.t1.xyz = curr_spec;
            o.t1.w = Y * Y * VARIANCE_FP16_QUANTIZATION_SCALE;  //in case of no temporal history, this substitutes a value that is plausible
        }         
    }   
}

void UpdateHistoryCS(in CSIN i)
{
    if(DIFFUSE_GI_Q)
    {
        copy_batch4(i, 16, sRTGI_Aux2, stRTGI_AccumDiff);
    }
    if(SPECULAR_GI_Q)
    {
        copy_batch4(i, 16, sRTGI_Aux3, stRTGI_AccumSpec);
    }
    //gbuffer, always
    {
        copy_batch4(i, 16, sRTGI_Aux4, stRTGI_GBufferPrev);
    }
}

/*=============================================================================
	Denoise
=============================================================================*/

float sg_overlap(float3 eta1, float3 eta2, float alpha1, float alpha2, float beta)
{
    float lambda1 = 2.0 / (alpha1*alpha1);
    float lambda2 = 2.0 / (alpha2*alpha2);
    
    float u = rcp(lambda1 + lambda2);
    float v = lambda1 * lambda2 * u;
    return exp(beta * 0.5 * log(4 * u * v) + beta * v * (dot(eta1, eta2) - 1));
}

void atrous_pass(in int2 center_texel, 
                 sampler s_diff, 
                 sampler s_spec, 
                 sampler s_gbuf,
                 const int it,
                 out PSOUT3 filter_out)
{
    const int scale = exp2(it);
    const int2 offsets[8] = 
    {
        int2(-1, -1) * scale, int2(0, -1) * scale, int2(1, -1) * scale,
        int2(-1,  0) * scale,                      int2(1,  0) * scale,
        int2(-1,  1) * scale, int2(0,  1) * scale, int2(1,  1) * scale
    };

    float2 center_uv = pixel_idx_to_uv(center_texel, BUFFER_SCREEN_SIZE_DLSS);
    float4 center_gbuf = tex2Dfetch(s_gbuf, center_texel);
    float4 center_diff = tex2Dfetch(s_diff, center_texel);
    float4 center_spec = tex2Dfetch(s_spec, center_texel);

    filter_out.t0 = center_diff;
    filter_out.t1 = center_spec;
    filter_out.t2 = center_gbuf;    

    float3 center_pos       = Camera::uv_to_proj(center_uv, center_gbuf.x);
    float3 center_normal    = Math::octahedral_dec(center_gbuf.yz);
    float3 center_geonormal = Deferred::get_geometry_normals(center_uv);
    float alpha             = GGX_ALPHA;
    float3 eta1             = BXDF::GGX::dominant_direction(center_normal, -normalize(center_pos), alpha);

    if(can_earlyout(Camera::z_to_depth(center_gbuf.x))) 
    {
        filter_out.t0 = float4(0, 0, 0, 1);
        filter_out.t1 = float4(0, 0, 0, 0); 
        filter_out.t2 = center_gbuf;
        return;
    }

    float denoised_ao = center_gbuf.w; //we store it there lmao
    float ao_wsum = 1;

    float2 gw[8];

    [unroll]
    for(int j = 0; j < 8; j++)
    {
        float4 gbuf = tex2Dfetch(s_gbuf, center_texel + offsets[j]);
        float2 uv = pixel_idx_to_uv(center_texel + offsets[j], BUFFER_SCREEN_SIZE_DLSS);
        float3 pos = Camera::uv_to_proj(uv, gbuf.x);

        float3 deltav = pos - center_pos;
        float plane_dist = abs(dot(deltav, center_geonormal));
        float eucli_dist = length(deltav);
        float dist = lerp(plane_dist, eucli_dist, 0.25) / center_pos.z;

        float wz = dist * 100.0;
        wz = exp2(-wz * wz);

        float3 normal = Math::octahedral_dec(gbuf.yz);

        float3 eta2 = BXDF::GGX::dominant_direction(normal, -normalize(pos), alpha);//technically alpha of sample but we use it same everywhere
        float wn_spec = sg_overlap(eta1, eta2, alpha, alpha, 6.0); 

        float cos_theta = dot(normal, center_normal);
        float wn_diff = saturate(exp((cos_theta - 1) * 64.0));

        float2 this_gw = float2(wn_diff, wn_spec) * wz;
        this_gw = lerp(0.001, 1, saturate(this_gw));

        gw[j] = this_gw;

        //also filter the AO here
        float ao = gbuf.w;
        denoised_ao += this_gw.x * ao;
        ao_wsum += this_gw.x;
    }

    filter_out.t2.xyz = center_gbuf.xyz;
    filter_out.t2.w = denoised_ao / ao_wsum;

    float sharpness = saturate(1-pow(FILTER_SMOOTHNESS, 0.1))*0.1;

    //diff
    [branch]
    if(DIFFUSE_GI_Q)
    {
        float center_var = center_diff.w / VARIANCE_FP16_QUANTIZATION_SCALE;
        float wsum = 1;
        filter_out.t0 = 0;
        float2 Yminmax = float2(1000, -1000);

        [loop]
        for(int j = 0; j < 8; j++)
        {
            int2 texel = center_texel + offsets[j];
            if(any(texel < 0) || any(texel >= BUFFER_SCREEN_SIZE_DLSS)) continue;

            float4 tap_diff = tex2Dfetch(s_diff, texel);
            float tap_var = tap_diff.w / VARIANCE_FP16_QUANTIZATION_SCALE;

            float s1 = exp2(-32.0) + center_var;
            float s2 = exp2(-32.0) + tap_var;
            float m1 = center_diff.x;
            float m2 = tap_diff.x;    

            float w = sqrt(s1 / (s1 + s2)) * exp(-0.5 * (m2-m1)*(m2-m1)/(s1 + s2) * sharpness) * 1.414; //center w/ center yields 0.707, so to make it equal, scale this weight by 1.414
            w *= gw[j].x;

            filter_out.t0 += tap_diff * float4(w.xxx, w * w);
            wsum += w;

            Yminmax = float2(min(Yminmax.x, tap_diff.x), max(Yminmax.y, tap_diff.x));
        }

        if(it < 2.5)
        {
            float ratio = clamp(center_diff.x, Yminmax.x, Yminmax.y) / (1e-6 + center_diff.x);
            center_diff.rgb *= ratio;
        }      
    
        filter_out.t0 += center_diff;   
        filter_out.t0 /= wsum;
        filter_out.t0.w /= wsum; //schied et al 2017    
    }
    //spec
    [branch]
    if(SPECULAR_GI_Q)
    {
        float center_var = center_spec.w / VARIANCE_FP16_QUANTIZATION_SCALE;
        float wsum = 1;
        filter_out.t1 = 0;

        float2 Yminmax = float2(1000, -1000);

        [loop]
        for(int j = 0; j < 8; j++)
        {
            int2 texel = center_texel + offsets[j];
            if(any(texel < 0) || any(texel >= BUFFER_SCREEN_SIZE_DLSS)) continue;

            float4 tap_spec = tex2Dfetch(s_spec, texel);
            float tap_var = tap_spec.w / VARIANCE_FP16_QUANTIZATION_SCALE;

            float s1 = exp2(-32.0) + center_var;
            float s2 = exp2(-32.0) + tap_var;
            float m1 = center_spec.x;
            float m2 = tap_spec.x;   

            float w = sqrt(s1 / (s1 + s2)) * exp(-0.5 * (m2-m1)*(m2-m1)/(s1 + s2) * sharpness) * 1.414;
            w *= gw[j].y;

            filter_out.t1 += tap_spec * float4(w.xxx, w * w);
            wsum += w;

            Yminmax = float2(min(Yminmax.x, tap_spec.x), max(Yminmax.y, tap_spec.x));
        }

        float ratio = clamp(center_spec.x, Yminmax.x, Yminmax.y) / (1e-6 + center_spec.x);
        if(it < 2.5) center_spec.rgb *= ratio;
        filter_out.t1 += center_spec;
        filter_out.t1 /= wsum;
        filter_out.t1.w /= wsum; //schied et al 2017       
    }

    [branch]//last iteration postamble
    if(it == 5)
    {   
        //apply fade and overall scaling here. No ambient yet since that is constant for every pixel.
        float fade = 1 - get_fade_factor(Camera::z_to_depth(center_gbuf.x));
        float rtao = saturate(filter_out.t2.w);
        rtao = lerp(1, rtao, saturate(RT_AO_AMOUNT * 0.1)) * saturate(RT_AMBIENT_LEVEL);
        rtao = lerp(rtao, 1, fade);        

        float3 diff_gi = filter_out.t0.rgb;
        diff_gi *= RT_IL_AMOUNT * RT_IL_AMOUNT;
        diff_gi = lerp(diff_gi, 0, fade);
        filter_out.t0 = float4(diff_gi, rtao);

        float3 spec_gi = filter_out.t1.rgb;
        spec_gi *= RT_SPEC_AMOUNT;
        float ndotv = saturate(dot(-normalize(center_pos), center_normal) - 0.001) + 0.001;  
        spec_gi *= get_brdf(ndotv, alpha); 
        spec_gi = lerp(spec_gi, 0, fade);
        filter_out.t1.rgb = spec_gi; 
    }
}

void DenoisePS0(in VSOUT i, out PSOUT3 o){atrous_pass(i.vpos.xy, sRTGI_Aux2, sRTGI_Aux3, sRTGI_Aux4, 0, o);}
void DenoisePS1(in VSOUT i, out PSOUT3 o){atrous_pass(i.vpos.xy, sRTGI_Aux0, sRTGI_Aux1, sRTGI_Aux5, 1, o);}
void DenoisePS2(in VSOUT i, out PSOUT3 o){atrous_pass(i.vpos.xy, sRTGI_Aux2, sRTGI_Aux3, sRTGI_Aux4, 2, o);}
void DenoisePS3(in VSOUT i, out PSOUT3 o){atrous_pass(i.vpos.xy, sRTGI_Aux0, sRTGI_Aux1, sRTGI_Aux5, 3, o);}
void DenoisePS4(in VSOUT i, out PSOUT3 o){atrous_pass(i.vpos.xy, sRTGI_Aux2, sRTGI_Aux3, sRTGI_Aux4, 4, o);}
void DenoisePS5(in VSOUT i, out PSOUT3 o){atrous_pass(i.vpos.xy, sRTGI_Aux0, sRTGI_Aux1, sRTGI_Aux5, 5, o);}

/*=============================================================================
	TAAU Compatibility Layer
=============================================================================*/

#ifdef _MARTYSMODS_TAAU_SCALE

texture RTGI_TAAU_DiffuseBeta   { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
texture RTGI_TAAU_DiffuseCov    { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
sampler sRTGI_TAAU_DiffuseBeta  { Texture = RTGI_TAAU_DiffuseBeta; };
sampler sRTGI_TAAU_DiffuseCov   { Texture = RTGI_TAAU_DiffuseCov; };
storage stRTGI_TAAU_DiffuseBeta  { Texture = RTGI_TAAU_DiffuseBeta; };
storage stRTGI_TAAU_DiffuseCov   { Texture = RTGI_TAAU_DiffuseCov; };

texture RTGI_TAAU_SpecularBeta   { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
texture RTGI_TAAU_SpecularCov    { Width = BUFFER_WIDTH_DLSS; Height = BUFFER_HEIGHT_DLSS; Format = RGBA16F; };
sampler sRTGI_TAAU_SpecularBeta  { Texture = RTGI_TAAU_SpecularBeta; };
sampler sRTGI_TAAU_SpecularCov   { Texture = RTGI_TAAU_SpecularCov; };
storage stRTGI_TAAU_SpecularBeta  { Texture = RTGI_TAAU_SpecularBeta; };
storage stRTGI_TAAU_SpecularCov   { Texture = RTGI_TAAU_SpecularCov; };

void taau_resolve(in VSOUT i, 
                  sampler s_prev_beta, 
                  sampler s_prev_cov, 
                  sampler s_curr, 
                  out float4 new_beta, 
                  out float4 new_cov)
{
    float2 prev_uv = i.uv + Deferred::get_motion(i.uv);
    float4 m1 = 0;
    float4 m2 = 0;

    int r = 2;

    [unroll]for(int x = -r; x <= r; x++)
    [unroll]for(int y = -r; y <= r; y++)
    {
        float4 tap = tex2Dfetch(s_curr, int2(i.vpos.xy) + int2(x, y));
        m1 += tap; m2 += tap * tap;
    }

    m1 /= (r*2+1)*(r*2+1); m2 /= (r*2+1)*(r*2+1);

    float4 curr_mean = m1;
    float4 curr_sigma = sqrt(abs(m2 - m1 * m1));

    float lambda = 0.9;

    float4 old_beta = tex2D(s_prev_beta, prev_uv);
    float4 old_cov  = tex2D(s_prev_cov, prev_uv);
    float4 curr_value = tex2D(s_curr, i.uv);

    float fallback = 1000;

    if(!Math::inside_screen(prev_uv))
    {
        [flatten]if(abs(old_cov.x) < 1e-7) old_beta.x = curr_value.x, old_cov.x = fallback;//10.0;
        [flatten]if(abs(old_cov.y) < 1e-7) old_beta.y = curr_value.y, old_cov.y = fallback;//10.0;
        [flatten]if(abs(old_cov.z) < 1e-7) old_beta.z = curr_value.z, old_cov.z = fallback;//10.0;
        [flatten]if(abs(old_cov.w) < 1e-7) old_beta.w = curr_value.w, old_cov.w = fallback;//10.0;
    }

    float4 predicted_value = old_beta;
    float4 deviations_from_target = abs(predicted_value - curr_mean) / max(1e-7, curr_sigma);          
    float4 clamped = clamp(predicted_value, curr_mean - curr_sigma, curr_mean + curr_sigma);  

    [unroll]
    for(int j = 0; j < 4; j++)
    {
        [branch]
        if(predicted_value[j] != clamped[j])
        {
            float clamp_strength = (deviations_from_target[j] - 1) / (deviations_from_target[j] + 1e-5);
            predicted_value[j] = old_beta[j] = clamped[j];
            old_cov[j] = lerp(old_cov[j], fallback, clamp_strength);
        }
    }

    float4 error = curr_value - predicted_value;
    float4 Q_t = old_cov / (lambda + old_cov);

    new_beta = old_beta + Q_t * error;
    new_cov = (old_cov - Q_t * old_cov) / lambda;
}

void TAAUResolvePS(in VSOUT i, out PSOUT4 o)
{
    o.t0 = o.t1 = o.t2 = o.t3 = 0;
    if(DIFFUSE_GI_Q)
        taau_resolve(i, sRTGI_TAAU_DiffuseBeta, sRTGI_TAAU_DiffuseCov, sRTGI_Aux2, o.t0, o.t1);   
    if(SPECULAR_GI_Q)
        taau_resolve(i, sRTGI_TAAU_SpecularBeta, sRTGI_TAAU_SpecularCov, sRTGI_Aux3, o.t2, o.t3);       
}

void TAAUUpdateHistoryCS(in CSIN i)
{
    if(DIFFUSE_GI_Q)
    {
        copy_batch4(i, 16, sRTGI_Aux0, stRTGI_TAAU_DiffuseBeta);
        copy_batch4(i, 16, sRTGI_Aux1, stRTGI_TAAU_DiffuseCov);
    }
    if(SPECULAR_GI_Q)
    {
        copy_batch4(i, 16, sRTGI_Aux4, stRTGI_TAAU_SpecularBeta);
        copy_batch4(i, 16, sRTGI_Aux5, stRTGI_TAAU_SpecularCov);
    }   
}

#endif //_MARTYSMODS_TAAU_SCALE

/*=============================================================================
	Blending
=============================================================================*/

void BlendPS(in VSOUT i, out float3 o : SV_Target0)
{ 
#ifdef _MARTYSMODS_TAAU_SCALE
    float4 diff = tex2Dlod(sRTGI_Aux0, i.uv, 0);   
    float3 spec = tex2Dlod(sRTGI_Aux4, i.uv, 0).rgb;
#else 
    float4 diff = tex2Dlod(sRTGI_Aux2, i.uv, 0);   
    float3 spec = tex2Dlod(sRTGI_Aux3, i.uv, 0).rgb;
#endif

    diff.rgb = max(0, ycocg_to_linear(diff.rgb));
    spec.rgb = max(0, ycocg_to_linear(spec.rgb)); 
    float rtao = diff.w;

    float3 albedo = Deferred::get_albedo(i.uv);
    float3 color = unpack_hdr(tex2D(ColorInput, i.uv).rgb);

    if(RT_DEBUG_VIEW == 1)
    {
        color = albedo = 0.4444;
    }
    else if(RT_DEBUG_VIEW == 2)
    {
        color = albedo = 0;
        spec.rgb *= 4; 
    }

    o = color;    

    if(DIFFUSE_GI_Q && RT_DEBUG_VIEW != 2)
    {
        o = color * rtao + diff.rgb * albedo;
    }
    if(SPECULAR_GI_Q && RT_DEBUG_VIEW != 1)
    {
        o += spec;
    }

    o = pack_hdr(o);

    if(RT_DEBUG_VIEW == 3)
    {
        float2 scaled_uv = i.uv * 5.0;
        int2 layer = int2(scaled_uv);
        scaled_uv = frac(scaled_uv);

        if(layer.x == 0)
        {    
#ifdef _MARTYSMODS_TAAU_SCALE
            float3 tiled_diff = max(0, ycocg_to_linear(tex2Dlod(sRTGI_Aux0, scaled_uv, 0).rgb));
            float3 tiled_spec = max(0, ycocg_to_linear(tex2Dlod(sRTGI_Aux4, scaled_uv, 0).rgb)); 
#else 
            float3 tiled_diff = max(0, ycocg_to_linear(tex2Dlod(sRTGI_Aux2, scaled_uv, 0).rgb));
            float3 tiled_spec = max(0, ycocg_to_linear(tex2Dlod(sRTGI_Aux3, scaled_uv, 0).rgb)); 
#endif
            float3 tiled_color = unpack_hdr(tex2Dlod(ColorInput, scaled_uv, 0).rgb);

            o = layer.y == 0 ? Debug::viridis(Depth::get_linear_depth(scaled_uv)) 
                : layer.y == 1 ? pack_hdr(tiled_diff + tiled_spec)
                : layer.y == 2 ? Deferred::get_normals(scaled_uv) * 0.5 * float3(1,-1,-1) + 0.5
                : layer.y == 3 ? showmotion(Deferred::get_motion(scaled_uv))
                : layer.y == 4 ? Deferred::get_albedo(scaled_uv)
                : o;
        }
    }   
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_RTGI
<
    ui_label = "iMMERSE Pro: 光线追踪全局光照";
    ui_tooltip =        
        "                                MartysMods - RTGI                                 \n"
        "                     MartysMods Epic ReShade Effects (iMMERSE)                    \n"
        "               Official versions only via https://patreon.com/mcflypg             \n"
        "__________________________________________________________________________________\n"
        "\n"
        "RTGI为您的游戏添加完全动态、逼真且沉浸式的光线追踪光照，\n"
        "可以增强现有光照或完全重新照亮场景，具体取决于使用情况。\n"
        "\n"
        "请确保iMMERSE LAUNCHPAD已启用并位于效果列表顶部！\n"
        "\n"
        "\n"
        "访问 https://martysmods.com 获取更多信息。                                \n"
        "\n"       
        "__________________________________________________________________________________\n"
        "版本: 1.00";
>
{    
    pass { ComputeShader = DiffuseZDownsampleCS<32, 32>;        DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS,  32*4); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS,  32*4); GenerateMipMaps = false;} 
    pass { ComputeShader = InitRadianceVolumeCS<16, 16>;        DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS>>2, 16); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS>>2, 16);} 
    pass { ComputeShader = PropagateIrradianceVolumeCS0<16, 16>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS>>2, 16); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS>>2, 16);} 
    pass { ComputeShader = PropagateIrradianceVolumeCS1<16, 16>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS>>2, 16); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS>>2, 16);} 
    pass { ComputeShader = PropagateIrradianceVolumeCS2<16, 16>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS>>2, 16); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS>>2, 16);} 
    pass { ComputeShader = PropagateIrradianceVolumeCS3<16, 16>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS>>2, 16); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS>>2, 16);} 
    pass { ComputeShader = PropagateIrradianceVolumeCS4<16, 16>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS>>2, 16); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS>>2, 16);}    
    pass { ComputeShader = TraceWrapCubicCS<32, 32>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS, 32);DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS, 32); }      
    pass { ComputeShader = SpecularHiZDownsampleCS<32, 32>;     DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS, 32*4);  DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS, 32*4);  GenerateMipMaps = false;}
    pass { ComputeShader = SpecularTraceCS<GGX_GROUP_SIZE, GGX_GROUP_SIZE>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS, GGX_GROUP_SIZE);DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS, GGX_GROUP_SIZE); } 
    pass { ComputeShader = SpatialMomentsDiffCS<16, 16>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS, 16);DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS, 16); }  
    pass { ComputeShader = SpatialMomentsSpecCS<16, 16>;DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS, 16);DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS, 16); }  
    pass { VertexShader = MainVS; PixelShader = TemporalIntegrateNewPS; RenderTarget0 = RTGI_Aux2;       RenderTarget1 = RTGI_Aux3;       RenderTarget2 = RTGI_Aux4;}        
    pass { ComputeShader = UpdateHistoryCS<16, 16>;  DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS,  16*2); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS,  16*2); } 
    pass { VertexShader = MainVS; PixelShader = DenoisePS0; RenderTarget0 = RTGI_Aux0; RenderTarget1 = RTGI_Aux1; RenderTarget2 = RTGI_Aux5; }
    pass { VertexShader = MainVS; PixelShader = DenoisePS1; RenderTarget0 = RTGI_Aux2; RenderTarget1 = RTGI_Aux3; RenderTarget2 = RTGI_Aux4; } 
    pass { VertexShader = MainVS; PixelShader = DenoisePS2; RenderTarget0 = RTGI_Aux0; RenderTarget1 = RTGI_Aux1; RenderTarget2 = RTGI_Aux5; }        
    pass { VertexShader = MainVS; PixelShader = DenoisePS3; RenderTarget0 = RTGI_Aux2; RenderTarget1 = RTGI_Aux3; RenderTarget2 = RTGI_Aux4; }
    pass { VertexShader = MainVS; PixelShader = DenoisePS4; RenderTarget0 = RTGI_Aux0; RenderTarget1 = RTGI_Aux1; RenderTarget2 = RTGI_Aux5; }
    pass { VertexShader = MainVS; PixelShader = DenoisePS5; RenderTarget0 = RTGI_Aux2; RenderTarget1 = RTGI_Aux3; RenderTarget2 = RTGI_Aux4; }
#ifdef _MARTYSMODS_TAAU_SCALE
    pass { VertexShader = MainVS; PixelShader = TAAUResolvePS;       RenderTarget0 = RTGI_Aux0; RenderTarget1 = RTGI_Aux1;  RenderTarget2 = RTGI_Aux4; RenderTarget3 = RTGI_Aux5;}
    pass { ComputeShader = TAAUUpdateHistoryCS<16, 16>;  DispatchSizeX = CEIL_DIV(BUFFER_WIDTH_DLSS,  16*2); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT_DLSS,  16*2); } 
#endif //_MARTYSMODS_TAAU_SCALE
    pass { VertexShader = MainVS; PixelShader = BlendPS; }
}

