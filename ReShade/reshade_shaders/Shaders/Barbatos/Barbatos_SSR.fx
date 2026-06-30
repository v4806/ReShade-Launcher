/*-------------------|
| :: Description ::  |
'--------------------|

    Barbatos SSR - Screen Space Reflections

    Version: 0.1.1
    Author: Barbatos Bachiko
    Original SSRT by jebbyk: https://github.com/jebbyk/SSRT-for-reshade/

    License: GNU Affero General Public License v3.0
    (https://github.com/jebbyk/SSRT-for-reshade/blob/main/LICENSE)

    History:
    0.1.1 - add denoising and fix normal map
*/

#include "ReShade.fxh"
#include "Blending.fxh"
#define fmod(x, y) (frac((x)*rcp(y)) * (y))
#ifndef USE_MARTY_LAUNCHPAD_MOTION
#define USE_MARTY_LAUNCHPAD_MOTION 0
#endif

#ifndef USE_VORT_MOTION
#define USE_VORT_MOTION 0
#endif

#define PI 3.1415927
#define PI2 (2.0 * PI)
#define FAR_PLANE RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
#define GetDepth(coords) (ReShade::GetLinearizedDepth(coords) * DepthMultiplier)

// Ray Marching Constants
#define MAX_TRACE_DISTANCE 2.0
static const int STEPS_PER_RAY = 128;
static const int REFINEMENT_STEPS = 5;

// Adaptive Step Constants
#define STEP_SCALE 0.7
#define MIN_STEP_SIZE 0.001
#define MAX_STEP_SIZE 1.0

//----------|
// :: UI :: |
//----------|

uniform float SPIntensity <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 3.0;
    ui_step = 0.01;
    ui_category = "反射设置";
    ui_label = "强度";
    ui_tooltip = "控制反射的整体亮度和强度。";
> = 1.1;

uniform float NormalBias <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    ui_category = "反射设置";
    ui_label = "法线偏移";
    ui_tooltip = "通过比较命中表面法线与原始表面法线来防止自反射伪影。";
> = 0.0;

uniform float Roughness <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    ui_category = "反射设置";
    ui_label = "粗糙度";
    ui_tooltip = "根据表面粗糙度控制反射的模糊程度。值越高反射越模糊。";
> = 0.0;  

uniform float FadeStart <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    ui_category = "反射设置";
    ui_label = "淡出起始距离";
    ui_tooltip = "反射开始淡出的距离。";
> = 0.0;

uniform float FadeEnd <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 5.0;
    ui_step = 0.010;
    ui_category = "反射设置";
    ui_label = "淡出结束距离";
    ui_tooltip = "反射完全消失的距离。";
> = 4.999;

uniform int SmoothMode <
    ui_label = "平滑法线模式";
    ui_type = "combo";
    ui_items = "关闭\0快速 (13x13)\0中等 (16x16)\0高质量 (31x31)\0";
    ui_category = "表面和法线";
> = 2;

uniform float Smooth_Threshold <
    ui_label = "平滑法线阈值";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_category = "表面和法线";
> = 0.5;

uniform float BumpIntensity <
    ui_label = "凹凸贴图强度";
    ui_type = "drag";
    ui_category = "表面和法线";
    ui_min = 0.0; ui_max = 1.0;
> = 0.4;

uniform float GeoCorrectionIntensity <
    ui_type = "drag";
    ui_min = -0.1; ui_max = 1.0;
    ui_step = 0.01;
    ui_category = "表面和法线";
    ui_label = "几何校正强度";
    ui_tooltip = "使用亮度在表面上创建额外的几何细节。";
> = -0.01;

uniform float DepthMultiplier <
    ui_type = "drag";
    ui_min = 0.1; ui_max = 5.0;
    ui_step = 0.1;
    ui_category = "表面和法线";
    ui_label = "深度倍增器";
> = 1.0;

uniform bool EnableDenoising <
    ui_category = "降噪";
    ui_label = "启用降噪";
    ui_tooltip = "启用双边上采样滤波器以减少噪点并上采样反射。";
> = false;

uniform int DenoiseIterations <
    ui_type = "slider";
    ui_min = 1; ui_max = 5;
    ui_category = "降噪";
    ui_label = "降噪迭代次数（核大小）";
    ui_tooltip = "降噪处理的次数。";
> = 2;

uniform float DenoiseStrength <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    ui_category = "降噪";
    ui_label = "降噪强度";
> = 1.0;

uniform float DenoiseEdgeThreshold <
    ui_type = "drag";
    ui_min = 0.001; ui_max = 0.2;
    ui_step = 0.001;
    ui_category = "降噪";
    ui_label = "降噪边缘阈值";
    ui_tooltip = "防止边缘模糊。值越低对边缘越敏感。";
> = 0.02;

uniform bool EnableTemporal <
    ui_category = "时间滤波";
    ui_label = "启用时间累积";
    ui_tooltip = "将当前帧的反射与前一帧混合以减少噪点和闪烁。";
> = true;

uniform float AccumFramesSG <
    ui_type = "slider";
    ui_min = 1.0; ui_max = 32.0;
    ui_step = 1.0;
    ui_category = "时间滤波";
    ui_label = "时间累积帧数";
    ui_tooltip = "累积的帧数。值越高越平滑，但可能在移动物体上产生更多重影。";
> = 4.0;

BLENDING_COMBO(BlendMode, "混合模式", "最终反射如何与原始图像混合。\n'正常'模式使用基于亮度的自定义Alpha混合。", "混合和输出", false, 0, 6)

uniform float3 Adjustments <
    ui_type = "drag";
    ui_category = "混合和输出";
    ui_label = "饱和度 / 曝光 / 对比度";
    ui_tooltip = "调整最终反射的颜色属性。";
> = float3(1.5, 1.0, 1.1);

uniform bool EnableACES <
    ui_category = "混合和输出";
    ui_label = "启用ACES色调映射";
    ui_tooltip = "对反射应用ACES色调映射以获得更电影化的外观。";
> = false;

uniform bool AssumeSRGB <
    ui_category = "混合和输出";
    ui_label = "假设sRGB输入";
    ui_tooltip = "假设输入颜色为sRGB空间并对其进行线性化。除非您知道游戏输出非线性颜色，否则请保持禁用。";
> = false;

uniform float fSSRRenderScale <
    ui_type = "drag";
    ui_min = 0.1; ui_max = 1.0;
    ui_step = 0.01;
    ui_category = "性能和品质";
    ui_label = "渲染比例";
    ui_tooltip = "以较低分辨率渲染反射以提高性能。0.5表示半分辨率。";
> = 0.8;

uniform float ThicknessThreshold <
    ui_type = "drag";
    ui_min = 0.001; ui_max = 0.01;
    ui_step = 0.001;
    ui_category = "性能和品质";
    ui_label = "厚度阈值";
    ui_tooltip = "确定表面的'厚度'。帮助光线不穿过薄物体。";
> = 0.010;

uniform float JitterAmount <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    ui_category = "性能和品质";
    ui_label = "抖动量";
> = 0.01;

uniform float JitterScale <
    ui_type = "drag";
    ui_min = 0.1; ui_max = 2.0;
    ui_step = 0.1;
    ui_category = "性能和品质";
    ui_label = "抖动比例";
> = 0.1;

uniform float VerticalFOV <
    ui_type = "drag";
    ui_min = 15.0; ui_max = 120.0;
    ui_step = 0.1;
    ui_category = "高级";
    ui_label = "垂直视野";
> = 37.0;

uniform int ViewMode <
    ui_type = "combo";
    ui_items = "无\0运动向量\0最终反射\0法线\0深度\0原始反射\0降噪后反射\0";
    ui_category = "调试";
    ui_label = "调试视图模式";
> = 0;

uniform int FRAME_COUNT < source = "framecount"; >;

//----------------|
// :: Textures :: |
//----------------|

#if USE_MARTY_LAUNCHPAD_MOTION
    namespace Deferred {
        texture MotionVectorsTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex; };
    }
    float2 SampleMotionVectors(float2 texcoord) {
        return tex2Dlod(Deferred::sMotionVectorsTex, float4(texcoord, 0, 0)).rg;
    }
#elif USE_VORT_MOTION
    texture2D MotVectTexVort { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler2D sMotVectTexVort { Texture = MotVectTexVort; MagFilter=POINT;MinFilter=POINT;MipFilter=POINT;AddressU=Clamp;AddressV=Clamp; };
    float2 SampleMotionVectors(float2 texcoord) {
        return tex2Dlod(sMotVectTexVort, float4(texcoord, 0, 0)).rg;
    }
#else
texture texMotionVectors
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RG16F;
};
sampler sTexMotionVectorsSampler
{
    Texture = texMotionVectors;
    MagFilter = POINT;
    MinFilter = POINT;
    MipFilter = POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};
float2 SampleMotionVectors(float2 texcoord)
{
    return tex2Dlod(sTexMotionVectorsSampler, float4(texcoord, 0, 0)).rg;
}
#endif

namespace SSRTNEW
{
    texture Reflection
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };
    sampler sReflection
    {
        Texture = Reflection;
    };

    texture DenoiseTex
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };
    sampler sDenoiseTex
    {
        Texture = DenoiseTex;
    };

    texture Temp
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };
    sampler sTemp
    {
        Texture = Temp;
    };

    texture History
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };
    sampler sHistory
    {
        Texture = History;
    };
    
    texture TNormal
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16F;
    };
    sampler sNormal
    {
        Texture = TNormal;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    texture NormTex_Pass1
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16f;
    };
    sampler sNormTex_Pass1
    {
        Texture = NormTex_Pass1;
    };

    texture NormTex_Pass2
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16f;
    };
    sampler sNormTex_Pass2
    {
        Texture = NormTex_Pass2;
    };

    //-----------------|
    // :: Structs     ::|
    //-----------------|

    struct Ray
    {
        float3 origin;
        float3 direction;
    };

    struct HitResult
    {
        bool found;
        float3 viewPos;
        float2 uv;
    };

    //-------------------|
    // :: Functions     ::|
    //-------------------|
    
#define DX9_MODE (RESHADE_API_D3D9)

    float IGN(float2 n)
    {
        float f = 0.06711056 * n.x + 0.00583715 * n.y;
        return frac(52.9829189 * frac(f));
    }
    
    //Licence GNU 2 from https://github.com/AlucardDH/dh-reshade-shaders/blob/master/Shaders/dh_uber_rt.fx
    bool isScaledProcessed(float2 coords)
    {
        return coords.x >= 0 && coords.y >= 0 && coords.x <= fSSRRenderScale && coords.y <= fSSRRenderScale;
    }

    float2 upCoordsSSR(float2 coords)
    {
        float2 result = coords / fSSRRenderScale;
#if !DX9_MODE
        int random = int(IGN(coords * 1000.0) * 255.0);
        int steps = ceil(1.0 / fSSRRenderScale);
        int count = steps * steps;
        int index = random % count;
        int2 delta = int2(index / steps, index % steps) - steps / 2;
        result += delta * ReShade::PixelSize;
#endif
        return result;
    }
    //End
    
    float3 IGN3dts(float2 texcoord, float HL)
    {
        float3 OutColor;
        float2 seed = texcoord * BUFFER_SCREEN_SIZE + fmod((float) FRAME_COUNT, HL) * 5.588238;
        OutColor.r = IGN(seed);
        OutColor.g = IGN(seed + 91.534651 + 189.6854);
        OutColor.b = IGN(seed + 167.28222 + 281.9874);
        return OutColor;
    }

    float3 RGBToYCoCg(float3 rgb)
    {
        float Y = dot(rgb, float3(0.25, 0.5, 0.25));
        float Co = dot(rgb, float3(0.5, 0, -0.5));
        float Cg = dot(rgb, float3(-0.25, 0.5, -0.25));
        return float3(Y, Co, Cg);
    }

    float3 YCoCgToRGB(float3 ycocg)
    {
        float r = ycocg.x + ycocg.y - ycocg.z;
        float g = ycocg.x + ycocg.z;
        float b = ycocg.x - ycocg.y - ycocg.z;
        return float3(r, g, b);
    }

    float3 HSVToRGB(float3 c)
    {
        const float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
    }

    float GetLuminance(float3 linearColor)
    {
        return dot(linearColor, float3(0.2126, 0.7152, 0.0722));
    }

    float3 LinearizeSRGB(float3 color)
    {
        return pow(color, 2.2);
    }

    float3 ACES(float3 color)
    {
        if (!EnableACES)
            return color;
        
        const float3x3 ACES_INPUT_MAT = float3x3(
            0.59719, 0.35458, 0.04823,
            0.07600, 0.90834, 0.01566,
            0.02840, 0.13383, 0.83777
        );
        const float3x3 ACES_OUTPUT_MAT = float3x3(
            1.60475, -0.53108, -0.07367,
            -0.10208, 1.10813, -0.00605,
            -0.00327, -0.07276, 1.07602
        );
        
        float3 v = mul(ACES_INPUT_MAT, color);
        float3 a = v * (v + 0.0245786) - 0.000090537;
        float3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
        float3 result = mul(ACES_OUTPUT_MAT, (a / b));
        
        return pow(saturate(result), 1.0 / 2.2);
    }
    
    float3 UVToViewPos(float2 uv, float view_z)
    {
        float2 clip_pos = uv * 2.0 - 1.0;
        float proj_scale_y = 1.0 / tan(radians(VerticalFOV * 0.5));
        float proj_scale_x = proj_scale_y / ReShade::AspectRatio;

        float3 view_pos;
        view_pos.x = clip_pos.x / proj_scale_x * view_z;
        view_pos.y = -clip_pos.y / proj_scale_y * view_z;
        view_pos.z = view_z;

        return view_pos;
    }

    float2 ViewPosToUV(float3 view_pos)
    {
        float proj_scale_y = 1.0 / tan(radians(VerticalFOV * 0.5));
        float proj_scale_x = proj_scale_y / ReShade::AspectRatio;

        float2 clip_pos;
        clip_pos.x = view_pos.x * proj_scale_x / view_pos.z;
        clip_pos.y = -view_pos.y * proj_scale_y / view_pos.z;

        return clip_pos * 0.5 + 0.5;
    }

    float3 GVPFUV(float2 uv)
    {
        float depth = GetDepth(uv);
        return UVToViewPos(uv, depth);
    }
    
    float3 Normal(float2 texcoord)
    {
        const float2 p = ReShade::PixelSize;
        float3 u, d, l, r, u2, d2, l2, r2;

        u = GVPFUV(texcoord + float2(0, p.y));
        d = GVPFUV(texcoord - float2(0, p.y));
        l = GVPFUV(texcoord - float2(p.x, 0));
        r = GVPFUV(texcoord + float2(-p.x, 0));

        u2 = GVPFUV(texcoord + float2(0, p.y * 2.0));
        d2 = GVPFUV(texcoord - float2(0, p.y * 2.0));
        l2 = GVPFUV(texcoord + float2(p.x * 2.0, 0));
        r2 = GVPFUV(texcoord + float2(p.x * 2.0, 0));

        u2 = u + (u - u2);
        d2 = d + (d - d2);
        l2 = l + (l - l2);
        r2 = r + (r - r2);

        float3 c = GVPFUV(texcoord);

        float3 v = u - c;
        float3 h = r - c;

        if (abs(d2.z - c.z) < abs(u2.z - c.z))
            v = c - d;
        if (abs(l2.z - c.z) < abs(r2.z - c.z))
            h = c - l;
        return normalize(cross(v, h));
    }

    float lum(in float3 color)
    {
        return 0.333333 * (color.r + color.g + color.b);
    }

    float3 Bump(float2 texcoord, float height)
    {
        float2 p = ReShade::PixelSize;
    
        float3 sX = tex2Dlod(ReShade::BackBuffer, float4(texcoord + float2(p.x, 0), 0, 0)).rgb;
        float3 sY = tex2Dlod(ReShade::BackBuffer, float4(texcoord + float2(0, p.y), 0, 0)).rgb;
        float3 sC = tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0, 0)).rgb;
    
        float LC = rcp(max(lum(sX + sY + sC), 0.001)) * height;
        LC = min(LC, 4.0);
    
        sX *= LC;
        sY *= LC;
        sC *= LC;
    
        float dX = GetDepth(texcoord + float2(p.x, 0));
        float dY = GetDepth(texcoord + float2(0, p.y));
        float dC = GetDepth(texcoord);
    
        float3 XB = sC - sX;
        float3 YB = sC - sY;
    
        float depthFactorX = saturate(1.0 - abs(dX - dC) * 1000.0);
        float depthFactorY = saturate(1.0 - abs(dY - dC) * 1000.0);
    
        float3 bump = float3(lum(XB) * depthFactorX, lum(YB) * depthFactorY, 1.0);
        return normalize(bump);
    }

    float3 blend_normals(float3 n1, float3 n2)
    {
        n1 += float3(0, 0, 1);
        n2 *= float3(-1, -1, 1);
        return n1 * dot(n1, n2) / n1.z - n2;
    }

    float3 GeometryCorrection(float2 texcoord, float3 normal)
    {
        if (GeoCorrectionIntensity == 0.0)
            return normal;

        float lumCenter = GetLuminance(tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0, 0)).rgb);
        float lumRight = GetLuminance(tex2Doffset(ReShade::BackBuffer, texcoord, int2(1, 0)).rgb);
        float lumDown = GetLuminance(tex2Doffset(ReShade::BackBuffer, texcoord, int2(0, 1)).rgb);

        float3 bumpNormal = normalize(float3(lumRight - lumCenter, lumDown - lumCenter, 1.0));

        return normalize(normal + bumpNormal * GeoCorrectionIntensity);
    }

    float3 SampleNormal(float2 coords)
    {
        float3 normal = (tex2Dlod(sNormal, float4(coords, 0, 0)).xyz - 0.5) * 2.0;
        return normalize(normal);
    }

    float3 JitterRay(float2 uv, float amount, float scale)
    {
        float noiseX = frac(sin(dot(uv + FRAME_COUNT * 0.0001, float2(12.9898, 78.233))) * 43758.5453);
        float noiseY = frac(sin(dot(uv + FRAME_COUNT * 0.0001 + 0.1, float2(12.9898, 78.233))) * 43758.5453);
        float noiseZ = frac(sin(dot(uv + FRAME_COUNT * 0.0001 + 0.2, float2(12.9898, 78.233))) * 43758.5453);
        float3 noise = float3(noiseX, noiseY, noiseZ) * 2.0 - 1.0; 
        return noise * amount * scale; 
    }
    
    HitResult TraceRay(Ray r)
    {
        HitResult result;
        result.found = false;

        float stepSize = MIN_STEP_SIZE;
        float totalDist = 0.0;
        float3 prevPos = r.origin;
        float depthBias = NormalBias * 0.005;

        [loop]
        for (int i = 0; i < STEPS_PER_RAY; ++i)
        {
            float3 currPos = prevPos + r.direction * stepSize;
            totalDist += stepSize;

            float2 uvCurr = ViewPosToUV(currPos);
            if (any(uvCurr < 0.0) || any(uvCurr > 1.0) || totalDist > MAX_TRACE_DISTANCE)
                break;

            float sceneDepth = GetDepth(uvCurr);
            float thickness = abs(currPos.z - sceneDepth);

            if (currPos.z < sceneDepth - depthBias || thickness > ThicknessThreshold)
            {
                prevPos = currPos;
                float distToDepth = abs(currPos.z - sceneDepth);
                stepSize = clamp(distToDepth * STEP_SCALE, MIN_STEP_SIZE, MAX_STEP_SIZE);
                continue;
            }
            
            float3 lo = prevPos, hi = currPos;
            [unroll]
            for (int ref_step = 0; ref_step < REFINEMENT_STEPS; ++ref_step)
            {
                float3 mid = 0.5 * (lo + hi);
                float midDepth = GetDepth(ViewPosToUV(mid));
                if (mid.z >= midDepth)
                    hi = mid;
                else
                    lo = mid;
            }
            result.viewPos = hi;
            result.uv = ViewPosToUV(result.viewPos);
            result.found = true;
            return result;
        }
        return result;
    }

    //--------------------|
    // :: Pixel Shaders ::|
    //--------------------|

    void PS_GBuffer_NoSmooth(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 outNormal : SV_Target)
    {
        if (SmoothMode != 0)
            discard;
        outNormal.rgb = Normal(uv.xy);
        outNormal.a = GetDepth(uv.xy);
        outNormal.rgb = blend_normals(Bump(uv, -SmoothMode), outNormal.rgb);
        outNormal.rgb = GeometryCorrection(uv, outNormal.rgb);
        outNormal.rgb = outNormal.rgb * 0.5 + 0.5;
    }

    void PS_GBuffer_WithSmooth(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 outNormal : SV_Target)
    {
        if (SmoothMode == 0)
            discard;
        outNormal.rgb = Normal(uv.xy);
        outNormal.a = GetDepth(uv.xy);
    }

    void PS_SmoothNormals_H(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 outNormal : SV_Target)
    {
        if (SmoothMode == 0)
            discard;
        float4 color = tex2Dlod(sNormTex_Pass1, float4(uv, 0, 0));
        float4 s, s1;
        float sc;
        
        float SNWidth = (SmoothMode == 1) ? 5.5 : (SmoothMode == 2) ? 2.5 : 1.0;
        int SNSamples = (SmoothMode == 1) ? 1 : (SmoothMode == 2) ? 3 : 30;

        float2 p = ReShade::PixelSize * SNWidth;
        float T = rcp(max(Smooth_Threshold * saturate(2 * (1 - color.a)), 0.0001));
        
        for (int x = -SNSamples; x <= SNSamples; x++)
        {
            s = tex2Dlod(sNormTex_Pass1, float4(uv.xy + float2(x * p.x, 0), 0, 0));
            float diff = dot(0.333, abs(s.rgb - color.rgb)) + abs(s.a - color.a) * (FAR_PLANE * Smooth_Threshold);
            diff = 1 - saturate(diff * T);
            s1 += s * diff;
            sc += diff;
        }
        outNormal = s1.rgba / sc;
    }

    void PS_SmoothNormals_V(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 outNormal : SV_Target)
    {
        if (SmoothMode == 0)
            discard;
        float4 color = tex2Dlod(sNormTex_Pass2, float4(uv, 0, 0));
        float4 s, s1;
        float sc;

        float SNWidth = (SmoothMode == 1) ? 5.5 : (SmoothMode == 2) ? 2.5 : 1.0;
        int SNSamples = (SmoothMode == 1) ? 1 : (SmoothMode == 2) ? 3 : 30;

        float2 p = ReShade::PixelSize * SNWidth;
        float T = rcp(max(Smooth_Threshold * saturate(2 * (1 - color.a)), 0.0001));
        
        for (int x = -SNSamples; x <= SNSamples; x++)
        {
            s = tex2Dlod(sNormTex_Pass2, float4(uv + float2(0, x * p.y), 0, 0));
            float diff = dot(0.333, abs(s.rgb - color.rgb)) + abs(s.a - color.a) * (FAR_PLANE * Smooth_Threshold);
            diff = 1 - saturate(diff * T * 2);
            s1 += s * diff;
            sc += diff;
        }
        
        s1.rgba = s1.rgba / sc;
        s1.rgb = blend_normals(Bump(uv, -BumpIntensity), s1.rgb);
        s1.rgb = GeometryCorrection(uv, s1.rgb);
        outNormal = float4(s1.rgb * 0.5 + 0.5, s1.a);
    }
    
    void PS_TraceReflections(float4 pos : SV_Position, float2 uv : TEXCOORD, out float4 outReflection : SV_Target)
    {
        if (!isScaledProcessed(uv))
        {
            outReflection = 0;
            return;
        }

        float2 screen_uv = upCoordsSSR(uv);
        float depth = GetDepth(screen_uv);
        float3 viewPos = UVToViewPos(screen_uv, depth);
        float3 viewDir = -normalize(viewPos);
        float3 normal = SampleNormal(screen_uv);

        float3 eyeDir = -viewDir;
        
        Ray r;
        r.origin = viewPos;

        float3 noise = JitterRay(uv, JitterAmount, JitterScale);
        float3 raydirG = normalize(reflect(eyeDir, normal));
        float3 raydirR = normalize(noise);

        float roughnessFactor = pow(Roughness, 2.0);
        r.direction = normalize(lerp(raydirG, raydirR, roughnessFactor));

        if (JitterAmount > 0.0)
        {
            float3 originJitter = JitterRay(uv, JitterAmount, JitterScale);
            r.origin += originJitter * ReShade::PixelSize.x;
        }
        
        HitResult hit = TraceRay(r);

        float3 reflectionColor = 0;
        if (hit.found)
        {
            float3 hitNormal = SampleNormal(hit.uv);
            if (distance(hitNormal, normal) >= NormalBias)
            {
                float distFactor = saturate(1.0 - length(hit.viewPos - viewPos) / MAX_TRACE_DISTANCE);
                reflectionColor = tex2Dlod(ReShade::BackBuffer, float4(hit.uv, 0, 0)).rgb * distFactor;
            }
        }
        else
        {
            float adaptiveDist = depth * 1.2 + 0.012;
            float3 fbViewPos = viewPos + r.direction * adaptiveDist;
            float2 uvFb = saturate(ViewPosToUV(fbViewPos));
            bool isSky = GetDepth(uvFb) >= 1.0;
            float3 fbColor = tex2Dlod(ReShade::BackBuffer, float4(uvFb, 0, 0)).rgb;

            if (isSky)
            {
                reflectionColor = fbColor;
            }
            else
            {
                float depthFactor = saturate(1.0 - depth / MAX_TRACE_DISTANCE);
                float vertical_fade = 1.0 - screen_uv.y;
                reflectionColor = fbColor * depthFactor * vertical_fade;
            }
        }

        float fresnel = pow(1.0 - saturate(dot(eyeDir, normal)), 3.0);
        float angleWeight = pow(saturate(dot(-viewDir, r.direction)), 2.0);
        float fadeRange = max(FadeEnd - FadeStart, 0.001);
        float depthFade = saturate((FadeEnd - depth) / fadeRange);
        depthFade *= depthFade;

        reflectionColor *= fresnel * angleWeight * depthFade;
        outReflection = float4(reflectionColor, depth);
    }

    void PS_Denoise(float4 pos : SV_Position, float2 uv : TEXCOORD, out float4 outDenoised : SV_Target)
    {
        if (!EnableDenoising)
        {
            outDenoised = tex2Dlod(sReflection, float4(uv * fSSRRenderScale, 0, 0));
            outDenoised.a = GetDepth(uv);
            return;
        }

        float3 centerNormal = SampleNormal(uv);
        float centerDepth = GetDepth(uv);

        float totalWeight = 0.0;
        float3 totalColor = 0.0;
        
        const int radius = DenoiseIterations;

        for (int y = -radius; y <= radius; y++)
        {
            for (int x = -radius; x <= radius; x++)
            {
                float2 offset = float2(x, y) * ReShade::PixelSize;
                float2 sample_uv_full = uv + offset;
                float2 sample_uv_sparse = sample_uv_full * fSSRRenderScale;

                if (sample_uv_sparse.x > fSSRRenderScale || sample_uv_sparse.y > fSSRRenderScale || any(sample_uv_sparse < 0))
                    continue;

                float4 sampleData = tex2Dlod(sReflection, float4(sample_uv_sparse, 0, 0));
                float3 sampleColor = sampleData.rgb;
                
                if (dot(sampleColor, sampleColor) < 0.001)
                    continue;

                float sampleDepth = GetDepth(sample_uv_full);
                float3 sampleNormal = SampleNormal(sample_uv_full); 

                float depthWeight = saturate(1.0 - abs(centerDepth - sampleDepth) / (DenoiseEdgeThreshold * centerDepth + 0.001));
                float normalWeight = pow(saturate(dot(centerNormal, sampleNormal)), 32.0);
                float spaceWeight = 1.0 - saturate(length(offset * 100));

                float weight = depthWeight * normalWeight * spaceWeight * DenoiseStrength;

                totalColor += sampleColor * weight;
                totalWeight += weight;
            }
        }

        if (totalWeight > 0.0)
        {
            outDenoised = float4(totalColor / totalWeight, centerDepth);
        }
        else
        {
            outDenoised = tex2Dlod(sReflection, float4(uv * fSSRRenderScale, 0, 0));
            outDenoised.a = centerDepth;
        }
    }

    void PS_Accumulate(float4 pos : SV_Position, float2 uv : TEXCOORD, out float4 outBlended : SV_Target)
    {
        float3 currentSpec = tex2Dlod(sDenoiseTex, float4(uv, 0, 0)).rgb;

        if (!EnableTemporal)
        {
            outBlended = float4(currentSpec, 1.0);
            return;
        }

        float2 motion = SampleMotionVectors(uv);
        float2 reprojected_uv = uv + motion;

        float currentDepth = GetDepth(uv);
        float historyDepth = GetDepth(reprojected_uv);

        bool validHistory = all(saturate(reprojected_uv) == reprojected_uv) &&
                                      FRAME_COUNT > 1 &&
                                      abs(historyDepth - currentDepth) < 0.01;

        float3 blendedSpec = currentSpec;
        if (validHistory)
        {
            float3 historySpec = tex2Dlod(sHistory, float4(reprojected_uv, 0, 0)).rgb;

            float3 minBox = RGBToYCoCg(currentSpec), maxBox = minBox;
            [unroll]
            for (int y = -1; y <= 1; y++)
            {
                for (int x = -1; x <= 1; x++)
                {
                    if (x == 0 && y == 0)
                        continue;
                    float2 neighbor_uv = uv + float2(x, y) * ReShade::PixelSize;
                    float3 neighborSpec = RGBToYCoCg(tex2Dlod(sDenoiseTex, float4(neighbor_uv, 0, 0)).rgb);
                    minBox = min(minBox, neighborSpec);
                    maxBox = max(maxBox, neighborSpec);
                }
            }
            
            float3 clampedHistorySpec = clamp(RGBToYCoCg(historySpec), minBox, maxBox);
            float alpha = 1.0 / min(FRAME_COUNT, AccumFramesSG);
            blendedSpec = YCoCgToRGB(lerp(clampedHistorySpec, RGBToYCoCg(currentSpec), alpha));
        }
        
        outBlended = float4(blendedSpec, 1.0);
    }

    void PS_UpdateHistory(float4 pos : SV_Position, float2 uv : TEXCOORD, out float4 outHistory : SV_Target)
    {
        outHistory = tex2Dlod(sTemp, float4(uv, 0, 0));
    }

    void PS_Output(float4 pos : SV_Position, float2 uv : TEXCOORD, out float4 outColor : SV_Target)
    {
        if (ViewMode != 0)
        {
            switch (ViewMode)
            {
                case 1: // Motion vectors
                    float2 motion = SampleMotionVectors(uv);
                    float velocity = length(motion) * 100.0;
                    float angle = atan2(motion.y, motion.x);
                    float3 hsv = float3((angle / PI2) + 0.5, 1.0, saturate(velocity));
                    outColor = float4(HSVToRGB(hsv), 1.0);
                    return;
                case 2: // Final Reflection
                    outColor = float4(tex2Dlod(sTemp, float4(uv, 0, 0)).rgb, 1.0);
                    return;
                case 3: // Normals
                    outColor = float4(SampleNormal(uv) * 0.5 + 0.5, 1.0);
                    return;
                case 4: // Depth
                    outColor = GetDepth(uv).xxxx;
                    return;
                case 5: // Raw Reflection
                    outColor = float4(tex2Dlod(sReflection, float4(uv * fSSRRenderScale, 0, 0)).rgb, 1.0);
                    return;
                case 6: // Denoised Reflection
                    outColor = float4(tex2Dlod(sDenoiseTex, float4(uv, 0, 0)).rgb, 1.0);
                    return;
            }
        }

        float3 originalColor = tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb;
        float3 specularGI = tex2Dlod(sTemp, float4(uv, 0, 0)).rgb;

        specularGI *= Adjustments.y; // Exposure
        if (AssumeSRGB)
            specularGI = LinearizeSRGB(specularGI);
        if (EnableACES)
            specularGI = ACES(specularGI);
        
        float luminance = GetLuminance(specularGI);
        specularGI = lerp(luminance.xxx, specularGI, Adjustments.x); // Saturation
        specularGI = (specularGI - 0.5) * Adjustments.z + 0.5; // Contrast

        specularGI *= SPIntensity;

        float3 finalColor;

        if (BlendMode == 0)
        {
            float giLuminance = GetLuminance(saturate(specularGI));
            finalColor = lerp(originalColor.rgb, specularGI, giLuminance);
        }
        else
        {
            finalColor = ComHeaders::Blending::Blend(BlendMode, originalColor.rgb, specularGI, 1.0);
        }

        outColor = float4(finalColor, 1.0);
    }

//-------------------|
// :: Technique     ::|
//-------------------|
    technique Barbatos_SSR
    {
        pass GBuffer_NoSmooth
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_GBuffer_NoSmooth;
            RenderTarget = TNormal;
        }
        pass GBuffer_WithSmooth
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_GBuffer_WithSmooth;
            RenderTarget = NormTex_Pass1;
        }
        pass SmoothNormals_H
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_SmoothNormals_H;
            RenderTarget = NormTex_Pass2;
        }
        pass SmoothNormals_V
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_SmoothNormals_V;
            RenderTarget = TNormal;
        }
        pass TraceReflections
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_TraceReflections;
            RenderTarget = Reflection;
            ClearRenderTargets = true;
        }
        pass Denoise
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_Denoise;
            RenderTarget = DenoiseTex;
        }
        pass Accumulate
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_Accumulate;
            RenderTarget = Temp;
        }
        pass UpdateHistory
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_UpdateHistory;
            RenderTarget = History;
        }
        pass Output
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_Output;
        }
    }
}
