/*--------------------.
| :: Description ::  |
'--------------------/

    Extruded Video Image
    
    Version: 1.0.1
    Author: Converted from Shadertoy, adapted by for reshade by Barbatos
    Original by Shane: https://www.shadertoy.com/view/3stXzB
    
    About: Creates an extruded, voxel-like 3D effect from the screen buffer
    using raymarching.
    
    Changelog:
    1.0.1: little fix
*/

#include "ReShade.fxh"

//----------|
// :: UI :: |
//----------|

uniform float ExtrusionScale <
    ui_type = "drag";
    ui_min = 0.01; ui_max = 2.0;
    ui_step = 0.01;
    ui_category = "挤出设置";
    ui_label = "挤出比例";
    ui_tooltip = "根据亮度控制方块挤出的程度。";
> = 0.15;

uniform float GridScale <
    ui_type = "drag";
    ui_min = 0.001; ui_max = 0.2;
    ui_step = 0.001;
    ui_category = "挤出设置";
    ui_label = "网格比例";
    ui_tooltip = "网格单元的大小。值越小 = 细节越多。";
> = 0.0625;

uniform bool EnableSubdivision <
    ui_category = "挤出设置";
    ui_label = "启用细分";
    ui_tooltip = "在需要时细分方块以获得更高细节。";
> = false;

uniform float SubdivisionThreshold <
    ui_type = "drag";
    ui_min = 0.01; ui_max = 0.5;
    ui_step = 0.01;
    ui_category = "挤出设置";
    ui_label = "细分阈值";
    ui_tooltip = "细分的高度差阈值。";
> = 0.067;

uniform bool EnableSparkles <
    ui_category = "视觉效果";
    ui_label = "启用闪烁";
    ui_tooltip = "为方块添加动画闪烁效果。";
> = true;

uniform bool EnableGrayscale <
    ui_category = "视觉效果";
    ui_label = "灰度模式";
    ui_tooltip = "以灰度渲染效果。";
> = false;

uniform float SparkleIntensity <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 5.0;
    ui_step = 0.1;
    ui_category = "视觉效果";
    ui_label = "闪烁强度";
    ui_tooltip = "控制闪烁效果的亮度。";
> = 1.5;

uniform float CameraSpeed <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 2.0;
    ui_step = 0.1;
    ui_category = "相机";
    ui_label = "相机移动速度";
    ui_tooltip = "自动相机移动的速度。";
> = 0.5;

uniform float CameraDistance <
    ui_type = "drag";
    ui_min = 1.0; ui_max = 2.0;
    ui_step = 0.1;
    ui_category = "相机";
    ui_label = "相机距离";
    ui_tooltip = "相机与中心的距离。";
> = 2.0;

uniform float FOV <
    ui_type = "drag";
    ui_min = 0.5; ui_max = 2.0;
    ui_step = 0.1;
    ui_category = "相机";
    ui_label = "视场角";
    ui_tooltip = "相机视场角。";
> = 1.0;

uniform int QualityPreset <
    ui_type = "combo";
    ui_items = "低\0中\0高\0极高\0";
    ui_category = "性能";
    ui_label = "质量预设";
    ui_tooltip = "调整光线行进质量与性能之间的平衡。";
> = 1;

uniform bool EnableShadows <
    ui_category = "光照";
    ui_label = "启用软阴影";
    ui_tooltip = "启用软阴影计算。";
> = true;

uniform bool EnableAO <
    ui_category = "光照";
    ui_label = "启用环境光遮蔽";
    ui_tooltip = "启用环境光遮蔽以获得更好的深度感知。";
> = true;

uniform float LightIntensity <
    ui_type = "drag";
    ui_min = 0.1; ui_max = 3.0;
    ui_step = 0.1;
    ui_category = "光照";
    ui_label = "光照强度";
    ui_tooltip = "整体光照强度。";
> = 1.0;

uniform float3 LightColor <
    ui_type = "color";
    ui_category = "光照";
    ui_label = "光照颜色";
> = float3(1.0, 0.9, 0.8);

uniform float Timer < source = "timer"; >;

#define FAR 20.0
#define PI 3.14159265359

//------------------|
// :: Functions ::  |
//------------------|

// Quality settings
int GetMaxIterations()
{
    int iterations[4] = { 32, 48, 64, 96 };
    return iterations[QualityPreset];
}

int GetShadowIterations()
{
    int iterations[4] = { 8, 12, 16, 24 };
    return iterations[QualityPreset];
}

float2x2 rot2(float a)
{
    float c = cos(a);
    float s = sin(a);
    return float2x2(c, -s, s, c);
}

float hash21(float2 p)
{
    return frac(sin(dot(p, float2(27.609, 57.583))) * 43758.5453);
}

float3 getTex(float2 p)
{
    // Stretch to fit screen aspect ratio
    p *= float2(BUFFER_HEIGHT / (float) BUFFER_WIDTH, 1.0);
    p = frac(p / 2.0 - 0.5);
    
    float3 tx = tex2Dlod(ReShade::BackBuffer, float4(p, 0, 0)).rgb;
    return tx * tx; // Rough sRGB to linear conversion
}

float hm(float2 p)
{
    float3 color = getTex(p);
    return dot(color, float3(0.299, 0.587, 0.114));
}

float opExtrusion(float sdf, float pz, float h)
{
    float2 w = float2(sdf, abs(pz) - h);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

float sBoxS(float2 p, float2 b, float sf)
{
    return length(max(abs(p) - b + sf, 0.0)) - sf;
}

// Global variables for object tracking
static float objID;
static float2 gID;

float4 blocks(float3 q3)
{
    float scale = GridScale;
    float2 l = float2(scale, scale);
    float2 s = l * 2.0;
    
    float d = 1e5;
    float2 p, ip;
    float2 id = float2(0, 0);
    float2 cntr = float2(0, 0);
    
    // Four block corner positions
    float2 ps4[4] =
    {
        float2(-l.x, l.y),
        l,
        -l,
        float2(l.x, -l.y)
    };
    
    float boxID = 0.0;
    
    for (int i = 0; i < 4; i++)
    {
        cntr = ps4[i] / 2.0;
        p = q3.xy - cntr;
        ip = floor(p / s) + 0.5;
        p -= ip * s;
        
        float2 idi = ip * s + cntr;
        
        float h = hm(idi);
        if (!EnableSubdivision)
        {
            h = floor(h * 15.999) / 15.0 * ExtrusionScale;
        }
        
        if (EnableSubdivision)
        {
            float4 h4;
            int sub = 0;
            
            h4[0] = hm(idi + ps4[0] / 4.0);
            if (abs(h4[0] - h) > SubdivisionThreshold)
                sub = 1;

            h4[1] = hm(idi + ps4[1] / 4.0);
            if (abs(h4[1] - h) > SubdivisionThreshold)
                sub = 1;

            h4[2] = hm(idi + ps4[2] / 4.0);
            if (abs(h4[2] - h) > SubdivisionThreshold)
                sub = 1;

            h4[3] = hm(idi + ps4[3] / 4.0);
            if (abs(h4[3] - h) > SubdivisionThreshold)
                sub = 1;
            
            h = floor(h * 15.999) / 15.0 * ExtrusionScale;
            h4 = floor(h4 * 15.999) / 15.0 * ExtrusionScale;
            
            if (sub == 1)
            {
                float4 d4, di4;
                
                // Iteration 0
                d4[0] = sBoxS(p - ps4[0] / 4.0, l / 4.0 - 0.05 * scale, 0.005);
                di4[0] = opExtrusion(d4[0], (q3.z + h4[0]), h4[0]);
                if (di4[0] < d)
                {
                    d = di4[0];
                    id = idi + ps4[0] / 4.0;
                }

                // Iteration 1
                d4[1] = sBoxS(p - ps4[1] / 4.0, l / 4.0 - 0.05 * scale, 0.005);
                di4[1] = opExtrusion(d4[1], (q3.z + h4[1]), h4[1]);
                if (di4[1] < d)
                {
                    d = di4[1];
                    id = idi + ps4[1] / 4.0;
                }

                // Iteration 2
                d4[2] = sBoxS(p - ps4[2] / 4.0, l / 4.0 - 0.05 * scale, 0.005);
                di4[2] = opExtrusion(d4[2], (q3.z + h4[2]), h4[2]);
                if (di4[2] < d)
                {
                    d = di4[2];
                    id = idi + ps4[2] / 4.0;
                }

                // Iteration 3
                d4[3] = sBoxS(p - ps4[3] / 4.0, l / 4.0 - 0.05 * scale, 0.005);
                di4[3] = opExtrusion(d4[3], (q3.z + h4[3]), h4[3]);
                if (di4[3] < d)
                {
                    d = di4[3];
                    id = idi + ps4[3] / 4.0;
                }
                // -- End of unrolled loop --
            }
            else
            {
                float di2D = sBoxS(p, l / 2.0 - 0.05 * scale, 0.015);
                float di = opExtrusion(di2D, (q3.z + h), h);
                
                if (di < d)
                {
                    d = di;
                    id = idi;
                }
            }
        }
        else
        {
            float di2D = sBoxS(p, l / 2.0 - 0.05 * scale, 0.015);
            float di = opExtrusion(di2D, (q3.z + h), h);
            
            if (di < d)
            {
                d = di;
                id = idi;
            }
        }
    }
    
    return float4(d, id, boxID);
}

float map(float3 p)
{
    float fl = -p.z + 0.1;
    float4 d4 = blocks(p);
    gID = d4.yz;
    
    objID = fl < d4.x ? 1.0 : 0.0;
    return min(fl, d4.x);
}

float trace(float3 ro, float3 rd)
{
    float t = 0.0;
    float d;
    int maxIter = GetMaxIterations();
    
    for (int i = 0; i < maxIter; i++)
    {
        d = map(ro + rd * t);
        if (abs(d) < 0.001 || t > FAR)
            break;
        t += d * 0.7;
    }
    
    return min(t, FAR);
}

float3 getNormal(float3 p, float t)
{
    const float2 e = float2(0.001, 0);
    return normalize(float3(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

float softShadow(float3 ro, float3 lp, float3 n, float k)
{
    if (!EnableShadows)
        return 1.0;
    
    int maxIterationsShad = GetShadowIterations();
    
    ro += n * 0.0015;
    float3 rd = lp - ro;
    
    float shade = 1.0;
    float t = 0.0;
    float end = max(length(rd), 0.0001);
    rd /= end;
    
    for (int i = 0; i < maxIterationsShad; i++)
    {
        float d = map(ro + rd * t);
        shade = min(shade, k * d / t);
        t += clamp(d, 0.01, 0.25);
        
        if (d < 0.0 || t > end)
            break;
    }
    
    return max(shade, 0.0);
}

float calcAO(float3 p, float3 n)
{
    if (!EnableAO)
        return 1.0;
    
    float sca = 3.0;
    float occ = 0.0;
    
    for (int i = 0; i < 5; i++)
    {
        float hr = float(i + 1) * 0.15 / 5.0;
        float d = map(p + n * hr);
        occ += (hr - d) * sca;
        sca *= 0.7;
    }
    
    return clamp(1.0 - occ, 0.0, 1.0);
}

//-------------------|
// :: Pixel Shader ::|
//-------------------|

float4 PS_ExtrudedVideo(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    // Convert screen coordinates
    float2 screenUV = (uv * ReShade::ScreenSize - ReShade::ScreenSize * 0.5) / ReShade::ScreenSize.y;
    
    // Camera setup
    float time = Timer * 0.001 * CameraSpeed;
    float3 lk = float3(0, 0, 0);
    float3 ro = lk + float3(
        -0.5 * 0.3 * cos(time / 2.0),
        -0.5 * 0.2 * sin(time / 2.0),
        -CameraDistance
    );
    
    // Light positioning
    float3 lp = ro + float3(1.5, 2.0, -1.0);
    
    // Ray direction calculation
    float3 fwd = normalize(lk - ro);
    float3 rgt = normalize(float3(fwd.z, 0.0, -fwd.x));
    float3 up = cross(fwd, rgt);
    
    float3 rd = normalize(fwd + FOV * screenUV.x * rgt + FOV * screenUV.y * up);
    
    // Raymarch to the scene
    float t = trace(ro, rd);
    
    // Save IDs
    float2 svGID = gID;
    float svObjID = objID;
    
    float3 col = float3(0, 0, 0);
    
    // The ray hit the surface
    if (t < FAR)
    {
        float3 sp = ro + rd * t;
        float3 sn = getNormal(sp, t);
        
        float3 texCol;
        
        // Extruded grid coloring
        if (svObjID < 0.5)
        {
            float3 tx = getTex(svGID);
            
            if (EnableGrayscale)
            {
                texCol = float3(1, 1, 1) * dot(tx, float3(0.299, 0.587, 0.114));
            }
            else
            {
                texCol = tx;
            }
            
            // Sparkle effects
            if (EnableSparkles)
            {
                float rnd = frac(sin(dot(svGID, float2(141.13, 289.97))) * 43758.5453);
                float rnd2 = frac(sin(dot(svGID + 0.037, float2(141.13, 289.97))) * 43758.5453);
                rnd = smoothstep(0.9, 0.95, cos(rnd * 6.283 + time * 2.0) * 0.5 + 0.5);
                
                float3 rndCol = 0.5 + 0.45 * cos(6.2831 * lerp(0.0, 0.3, rnd2) + float3(0, 1, 2) / 1.1);
                rndCol = lerp(rndCol, rndCol.xzy, screenUV.y * 0.75 + 0.5);
                rndCol = lerp(float3(1, 1, 1), rndCol * SparkleIntensity * 10.0,
                                rnd * smoothstep(1.0 - (1.0 / 15.0 + 0.001), 1.0, 1.0 - texCol.x));
                
                texCol *= rndCol;
            }
            
            texCol = smoothstep(0.0, 1.0, texCol);
        }
        else
        {
            texCol = float3(0, 0, 0);
        }
        
        // Lighting calculations
        float3 ld = lp - sp;
        float lDist = max(length(ld), 0.001);
        ld /= lDist;
        
        float sh = softShadow(sp, lp, sn, 8.0);
        float ao = calcAO(sp, sn);
        sh = min(sh + ao * 0.25, 1.0);
        
        float atten = 1.0 / (1.0 + lDist * 0.05);
        float diff = max(dot(sn, ld), 0.0);
        float spec = pow(max(dot(reflect(ld, sn), rd), 0.0), 16.0);
        float fre = pow(clamp(dot(sn, rd) + 1.0, 0.0, 1.0), 2.0);
        
        // Combine lighting terms
        col = texCol * (diff + ao * 0.3 + LightColor * diff * fre * 16.0 + float3(1, 0.5, 0.2) * spec * 2.0);
        col *= ao * sh * atten * LightIntensity;
    }
    
    // Gamma correction
    col = sqrt(max(col, 0.0));
    
    return float4(col, 1.0);
}

//----------------|
// :: Technique ::|
//----------------|

technique ExtrudedVideoImage < ui_tooltip = "从屏幕缓冲区创建挤出的体素风格3D效果"; >
{
    pass ExtrudedVideo
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_ExtrudedVideo;
    }
}

