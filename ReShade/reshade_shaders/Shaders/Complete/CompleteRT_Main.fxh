//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 1.6 - Main
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
///////////////Include/////////////////////

#include "ReShade.fxh"
#include "CompleteRT_UI.fxh"
#include "CompleteRT_Configs.fxh"
#include "CompleteFX_Common.fxh"

///////////////Include/////////////////////
///////////////PreProcessor-Definitions////
///////////////PreProcessor-Definitions////
///////////////Textures-Samplers///////////
#define POINT_FILTER MipFilter = Point; MinFilter = Point; MagFilter = Point;
//1
//Blue noise texture from CompleteFX_Common.fxh
//2
#define sTexColor ReShade::BackBuffer
//3
#define LDepth ReShade::GetLinearizedDepth
//4
#if !C_RT_USE_LAUNCHPAD_MOTIONS
texture texMotionVectors     { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler SamplerMotionVectors { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; POINT_FILTER };
float2 sampleMotion(float2 texcoord){return tex2D(SamplerMotionVectors, texcoord).rg;}
#else
namespace Deferred
{
	texture MotionVectorsTex        { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RG16F;     };
	sampler sMotionVectorsTex       { Texture = MotionVectorsTex; };
}
float2 sampleMotion(float2 texcoord){return tex2D(Deferred::sMotionVectorsTex, texcoord).rg;}
#endif
//5
texture RT_FilterTex0  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT*2; Format = TexP; };
sampler sRT_FilterTex0 { Texture = RT_FilterTex0; POINT_FILTER };
//6
texture RT_FilterTex1  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT*2; Format = TexP;};
sampler sRT_FilterTex1 { Texture = RT_FilterTex1; POINT_FILTER };
//7
texture RT_HistoryTex0  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT*2; Format = RGBA32f; };
sampler sRT_HistoryTex0 { Texture = RT_HistoryTex0; };
//8
texture RT_HistoryTex1  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT*2; Format = TexP; };
sampler sRT_HistoryTex1 { Texture = RT_HistoryTex1; };
//9
texture RT_NormTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sRT_NormTex { Texture = RT_NormTex; POINT_FILTER };
//10
texture RT_RoughnessTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16f; };
sampler sRT_RoughnessTex { Texture = RT_RoughnessTex; POINT_FILTER };
//11
texture RT_HLTex0  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT*2; Format = RG16f; };
sampler sRT_HLTex0 { Texture = RT_HLTex0; };
//12
texture RT_HLTex1  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT*2; Format = RGBA16f; };
sampler sRT_HLTex1 { Texture = RT_HLTex1; };
//13
texture RT_LowResDepthTex  { Width = BUFFER_WIDTH * RES_M; Height = BUFFER_HEIGHT * RES_M; Format = R16f; };
sampler sRT_LowResDepthTex { Texture = RT_LowResDepthTex; POINT_FILTER };
//14
texture RT_HQNormTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16f; };
sampler sRT_HQNormTex { Texture = RT_HQNormTex; POINT_FILTER };
//15
texture RT_ThicknessTex { Width = BUFFER_WIDTH * RES_M; Height = BUFFER_HEIGHT * RES_M; Format = R8; };
sampler sRT_ThicknessTex { Texture = RT_ThicknessTex; POINT_FILTER };
//16
texture RT_TReservoirHistory  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = TexP; };
sampler sRT_TReservoirHistory { Texture = RT_TReservoirHistory; POINT_FILTER };

///////////////Textures-Samplers///////////
///////////////UI//////////////////////////
///////////////UI//////////////////////////
///////////////Functions///////////////////


int getReuseSampleCount()
{
#if __RENDERER__ >= 0xa000
 #if C_RT_UI_DIFFICULTY == 1
	return UI_ReuseSamples * 21;
 #else
	return DiffuseRM_Preset[UI_QualityPreset].z;
 #endif
#else
	return 1;
#endif
}

float getResolutionScale()
{
#if C_RT_UI_DIFFICULTY
	float s = UI_ResolutionScale == 1 ? 0.314 : 1.0;
	s = UI_ResolutionScale;
#else
	float s = Resolution_preset[UI_QualityPreset];
#endif
	
	float depthResolutionScale = float(tex2Dsize(ReShade::DepthBuffer).x) / float(BUFFER_WIDTH);
	if(!UI_DepthBasedResolution) depthResolutionScale = 1;
	
	s = min(s, depthResolutionScale);
	
	return clamp(s, 1e-6, 1);
}

bool getDiffuseOrSpecular(float uvY)
{
	return uvY <= (0.5*getResolutionScale());
}

bool checkFXdiscard(float uvY)
{
	bool FX = getDiffuseOrSpecular(uvY);
	if((FX && !UI_GIAOEnable)||(!FX && !UI_ReflectionEnable))return 1;
	return 0;
}

float GetRoughTex(float2 uv)
{
	if(UI_ReflectionEnable)
	{
		if(!NO_ROUGH_TEX) return tex2D(sRT_RoughnessTex, uv).r + 1e-7;
		else return UI_Roughness + 1e-7; 
	}
	else return 1e-7;//RoughnessTex
}

float4 SobelBump(float2 texcoord, float height, float3 normals)
{
	
	texcoord.y *= 2;
	if(height == 0 && UI_Roughness == 0) return float4(0,0,1,0);
	float2 p = min(pix * 1.5, pix * 100 / (clamp(LDepth(texcoord), 1e-7, 1.0) * FAR_PLANE + 1));
	
	float2 kernelWeight[9] = {
	float2(-1,-1),float2(0,-2),float2(1,-1),
	float2(-2, 0),float2(0, 0),float2(2, 0),
	float2(-1, 1),float2(0, 2),float2(1, 1)};
	
	float2 sampleOffset[9] = {
	float2(-1,-1),float2(0,-1),float2(1,-1),
	float2(-1, 0),float2(0, 0),float2(1, 0),
	float2(-1, 1),float2(0, 1),float2(1, 1)};
	
	float centerdepth = LDepth(texcoord);
	
	float2 sobel;
	float M1,M2;
	for(int idx = 0; idx < 9; idx++)
	{
		float4 col = tex2Dlod(sTexColor, float4(sampleOffset[idx] * p + texcoord,0,0));
		col.x = lum(col.xyz);
		sobel += col.xx * kernelWeight[idx];
	}
	
	float2 s = sobel;
	
	float3 bump = float3(s.xy * height, 1);
	if(length(bump.xy) > Bump_Mapping_EdgeThreshold) bump = float3(0,0,1);
	bump = normalize(bump);
	
	float roughness = sqrt(length(s));
	float minR = UI_Roughness * UI_Roughness;
	float maxR = sqrt(UI_Roughness);
	roughness  = roughness * (maxR - minR) + minR;
	
	float groundFactor = UI_RainRoughness ? (dot(normals, float3(-1,1,-1)) * 0.5 + 0.5) : 0;
	groundFactor *= groundFactor;
	groundFactor = (1 - groundFactor) * (1 - (minR * minR)) + minR * minR;
	
	roughness *= groundFactor;
	return float4(bump, roughness);
}

float3 BlendBump(float3 n1, float3 n2)
{
	n1.z++;
	return n1 * dot(n1, n2) / n1.z - n2;
}

bool IsSaturated(float2 coord)
{
	return coord.x > 1 || coord.x < 0 || coord.y > 1 || coord.y < 0;
}

#define VARIANCE_INTERSECTION_MAX_T 1
float3 ClipToAABB( float3 inHistoryColor, float3 inCurrentColor, float3 inBBCenter, float3 inBBExtents )
{
	float3 direction = inCurrentColor - inHistoryColor;
	direction = direction == 0 ? 1e-7 : direction;
	const float3 intersection = ((inBBCenter - sign(direction) * inBBExtents) - inHistoryColor) / direction;
	const float3 possibleT = (intersection >= 0.0f) ? intersection : VARIANCE_INTERSECTION_MAX_T + 1.0f;
	const float3 t = min(VARIANCE_INTERSECTION_MAX_T, min(possibleT.x, min(possibleT.y, possibleT.z)));
	
	return float3(t < VARIANCE_INTERSECTION_MAX_T ? (inHistoryColor + direction * t) : inHistoryColor);
}

float GetVariance(float2 texcoord, sampler color, float HL)
{
	float Input = tex2D(color, texcoord).a + 1e-3;
	float resolutionScale = getResolutionScale();
	float mul;
	if(UI_FilterQuality)
		mul = 1.0 + max(0, 4.0 - HL);
	else
		mul = 1.0 + max(0, 4.0 - HL);// * 2.0;
	return sqrt(Input) * mul;
}

void GetNormalAndDepth(in float2 texcoord, out float3 normal, out float depth)
{
	texcoord /= getResolutionScale();
	float4 Geometry = tex2Dlod(sRT_NormTex, float4(texcoord,0,0));
	normal = DecodeNormals(Geometry.xy);
	depth  = max(1e-7, DecodeDepth(Geometry.zw));
}

float getDepthFade(float depth)
{
	float close_plane = 0.3 * sqrt(UI_DepthFade);
	depth = saturate(depth - close_plane);
	if(UI_FadeMode==0)
	return saturate(pow(abs(UI_DepthFade * UI_DepthFade * UI_DepthFade * UI_DepthFade), depth));
	if(UI_FadeMode==1)
	return saturate((1 - depth / max(1e-7, InvTonemapper(UI_DepthFade))));
	return 0;
}

float3 getUniformLambert(in float3 seed, float3 N, out float weight)
{
    float r = sqrt(1.0 - seed.x * seed.x);
    float phi = 2.0 * PI * seed.y;
    
    float3  B = normalize( cross( N, float3(0.0,1.0,1.0) ) );
	float3  T = cross( B, N );
	
    float3 l = normalize(r * sin(phi) * B + seed.x * N + r * cos(phi) * T);
    // Sample weight
    float pdf = dot(l, N);
    weight = 0.5 / (pdf + 1e-6);
    weight = saturate(weight);
    float3 noise = -l;
    return noise;
}

//cosine weighted hemisphere
float3 getCosineLambert(in float3 noise, float3 normal, out float weight)
{
	noise *= 0.999; //to make sure it's [0,1) and not [0,1]   
    float cosTheta2 = noise.x;
    float cosTheta = sqrt(cosTheta2);
    float sinTheta = sqrt(1.0 - cosTheta2);
	
    float phi = 2.0 * PI * noise.y;
    
    // Spherical to cartesian
    float3 t = normalize(cross(normal.yzx, normal));
    float3 b = cross(normal, t);
    
	float3 l = (t * cos(phi) + b * sin(phi)) * sinTheta + normal * cosTheta;
    
    // Sample weight
    float pdf = dot(l, normal);
    weight = 0.5 / (pdf + 1e-6);
    weight = saturate(weight);
    noise = -l;
    return noise;
}

void getGGX_t_b(in float3 normal, out float3 t, out float3 b)
{
	t = normalize(cross(normal.yzx, normal.xyz));
	b = cross(normal.xyz, t);
}

float3 sampleGGXVNDF(float3 V_, float alpha_x, float alpha_y, float U1, float U2)
{
	// stretch view
	float3 V = normalize(float3(alpha_x * V_.x, alpha_y * V_.y, V_.z));
	// orthonormal basis
	float3 T1 = (V.z < 0.9999) ? normalize(cross(V, float3(0,0,1))) : float3(1,0,0);
	float3 T2 = cross(T1, V);
	// sample point with polar coordinates (r, phi)
	float a = 1.0 / (1.0 + V.z);
	float r = sqrt(U1);
	float phi = (U2<a) ? U2/a * PI : PI + (U2-a)/(1.0-a) * PI;
	float P1 = r*cos(phi);
	float P2 = r*sin(phi)*((U2<a) ? 1.0 : V.z);
	// compute normal
	float3 N = P1*T1 + P2*T2 + sqrt(max(0.0, 1.0- P1*P1- P2*P2))*V;
	// unstretch
	N = normalize(float3(alpha_x*N.x, alpha_y*N.y, max(0.0, N.z)));
	return N;
}
	 
//optimized for multisampling
float3 getHemisphereGGXSample(float2 noise, float3 normal, float3 eyedir, float alpha, float alpha2, float3 t, float3 b, out float weight)
{
	float3 l;
	if(alpha >= 1e-3)
	{
	    float epsilon = clamp(noise.x, 0.001, 1.);
	    float cosTheta2 = (1. - epsilon) / (epsilon * (alpha2 - 1.) + 1.);
	    float cosTheta = sqrt(cosTheta2);
	    float sinTheta = sqrt(1. - cosTheta2);
	    
	    float phi = 2.0 * PI * noise.y;
	    
		float3 microNormal = (t * cos(phi) + b * sin(phi)) * sinTheta + normal * cosTheta;
	    l = reflect(-eyedir, microNormal.xyz);
    
	    // Sample weight
	    float den = (alpha2 - 1.) * cosTheta2 + 1.;
	    float D = alpha2 / (PI * den * den);
	    float pdf = D * cosTheta / (4. * dot(microNormal, eyedir));
	    weight = (.5 / PI) / max(pdf, 1e-6);
		weight = max(weight, 1e-6);
		weight *= (dot(l, normal) >= 0.0);
    }
    else
    {
    	l = reflect(-eyedir, normal);
    	weight = 1;
    }
    return -l;
}

float3 getTemporalJitter()
{
	float2 Jitter = halton2_3[int(Frame % 64)] * 2 - 1;
	Jitter *= (rcp(getResolutionScale())-1);
	float  jitterLength = length(Jitter);
	
	Jitter  = Jitter * pix * float2(1,0.5) * TS_JitterUpscale;
	return float3(Jitter, jitterLength);
}

float2 getTemporalJitterNormalized()
{
	float2 Jitter = halton2_3[int(Frame % 64)];
	return Jitter;
}

#define checkNaN(var) (!(var<0 || var==0 || var>0))

///////////////Functions///////////////////
///////////////Vertex Shader///////////////
///////////////Vertex Shader///////////////
///////////////Pixel Shader////////////////

struct i
{
	float4 vpos : SV_Position;
	float2 uv : TexCoord0;
};

float3 ComputeNormal(float2 texcoord, float yScale)
{
	float2 p = pix * float2(1,yScale);
	float3 u2,d2,l2,r2;
	
	const float3 u = UVtoPos( texcoord + float2( 0, p.y));
	const float3 d = UVtoPos( texcoord - float2( 0, p.y));
	const float3 l = UVtoPos( texcoord + float2( p.x, 0));
	const float3 r = UVtoPos( texcoord - float2( p.x, 0));
	
	p *= 2;
	
	u2 = UVtoPos( texcoord + float2( 0, p.y));
	d2 = UVtoPos( texcoord - float2( 0, p.y));
	l2 = UVtoPos( texcoord + float2( p.x, 0));
	r2 = UVtoPos( texcoord - float2( p.x, 0));
	
	u2 = u + (u - u2);
	d2 = d + (d - d2);
	l2 = l + (l - l2);
	r2 = r + (r - r2);
	
	const float3 c = UVtoPos( texcoord);
	
	float3 v = u-c; float3 h = r-c;
	
	if( abs(d2.z-c.z) < abs(u2.z-c.z) ) v = c-d;
	if( abs(l2.z-c.z) < abs(r2.z-c.z) ) h = c-l;
	
	return normalize(cross( v, h));
}

void GBuffer1(i i, out float4 Geometry : SV_Target0)
{
	float resolutionScale = getResolutionScale();
	if(i.uv.x >= 1 || i.uv.y >= 0.5)
		Geometry = float4(1,0,0,0);
	else
	{
		i.uv.y *= 2;
		
		Geometry.xyz = ComputeNormal(i.uv);
		Geometry.w = clamp(LDepth(i.uv), 1e-7, 1.0);
	}
}
static const bool UI_denoiseNormals = 0;
void SmoothNormals
(
	i i
	, out float4 Geometry      : SV_Target0
	, out float4 Roughness     : SV_Target1
	, out float4 HQNormals     : SV_Target2
)
{
	float resolutionScale = getResolutionScale();
	if(i.uv.x >= resolutionScale || i.uv.y >= resolutionScale) discard;
	i.uv.y *= 0.5;
	i.uv /= resolutionScale;
	i.uv += getTemporalJitter().xy;
	float4 csample = tex2Dlod(sRT_FilterTex0, float4(i.uv,0,0));
	Geometry = csample;
	
#if C_RT_UI_DIFFICULTY == 0
	int Q_Preset[6] = {0,0,0,3,6,10};
	int UI_SmoothNormals = Q_Preset[UI_QualityPreset];
#endif
	
	float2 offset;
	float angle = PI2 / SN_DirCount;
	float2 p = pix * float2(1,0.5);
	float2 step = p * SN_Radius / UI_SmoothNormals;
	float  wSum = 0;
	
	float2 denoiseOffsets[8] = {float2(-p.x,0),float2(p.x,0),float2(0,p.y),float2(0,-p.y),//cross
	                            -p.xy,p.xy,float2(p.x,-p.y),float2(-p.y,p.y)};//box
	
	if(UI_denoiseNormals)
	[unroll]for(int n; n < 8; n++)
	{
		float4 nsample = tex2Dlod(sRT_FilterTex0, float4(i.uv + denoiseOffsets[n], 0, 0));
		if(abs(csample.w - nsample.w) < SN_DThreshold)
		{
			wSum++;
			Geometry.xyz += nsample.xyz;
		}
	}
	
	Geometry.xyz = normalize(Geometry.xyz);
	csample = Geometry;
	wSum = 0;
	
	if(SMOOTHNORMALS_ENABLED && UI_SmoothNormals >= 1)
	{
		[loop]for(float direction = 0; direction < PI2; direction += angle)
		{
			sincos(direction, offset.x, offset.y);
			offset *= step;
			
			[loop]for(float distance = 1; distance <= UI_SmoothNormals; distance ++)
			{
				float4 nsample = tex2Dlod(sRT_FilterTex0, float4(mad(offset, distance, i.uv), 0, 0));
				float dnormals = dot(csample.xyz, nsample.xyz);
				
				if(dnormals > SN_NThreshold && abs(csample.w - nsample.w) < SN_DThreshold)
				{
					wSum++;
					Geometry.xyz += nsample.xyz;
				}
				else break;
			}
		}
		Geometry.xyz = normalize(Geometry.xyz);
	}
	
	float4 BumpNRoughness = SobelBump(i.uv, UI_BumpStrength, Geometry.xyz);
	
	Geometry.xyz = BlendBump(Geometry.xyz, BumpNRoughness.xyz);
	HQNormals = Geometry;
	
	Roughness = BumpNRoughness.w;
	
	Geometry.xy  = EncodeNormals(Geometry.xyz);
	Geometry.zw  = EncodeDepth(Geometry.w);
}

void CopyGBufferLowRes(i i, out float Depth : SV_Target0)
{
	float resolutionScale = getResolutionScale();
	i.uv /= resolutionScale;
	
	if(i.uv.x>=1||i.uv.y>=1)discard;
	Depth = clamp(LDepth(i.uv), 1e-7, 1.0 - 1e-7);
	Depth.x *= FAR_PLANE;
}

#define LDepthLoRes(texcoord) tex2Dlod(sRT_LowResDepthTex, float4(texcoord.xy, 0, 0)).x

void ThicknessEstimation(i i, out float Thickness : SV_Target0)
{
	float resolutionScale = getResolutionScale();
	
	if(i.uv.x>=1||i.uv.y>=1)discard;
	float2 p = pix; p *= resolutionScale;
	
	float Depth = LDepthLoRes(i.uv);
	float normalizedDepth = Depth / FAR_PLANE;
	if(normalizedDepth < SkyDepth && UI_GIAOEnable && 
#if C_RT_UI_DIFFICULTY == 0
	ThicknessEstimation_preset[UI_QualityPreset]
#else	
	UI_ThicknessEstimation
#endif
	)
	{
		
		
		float4 eyedir = float4(normalize(UVtoPos(i.uv)), 0);
		float3 normals; GetNormalAndDepth(i.uv*resolutionScale, normals, eyedir.w);
		float  facing = 1.1 - dot(eyedir.xyz, normals);
		float T = facing * 10;
		float thickness = 1000;
		float delta=1;
		
		float2 offset[4] = {float2(-p.x,0),float2(p.x,0),float2(0,p.y),float2(0,-p.y)};
		
		[unroll]for(int direction = 0; direction < 4; direction++)
		{
			float D = 1;
			[loop]for(D = 1; D <= 64; D *= 2)
			{
				float sDepth = LDepthLoRes(offset[direction] * D + i.uv);
				if(sDepth - Depth <= T * D)delta = D;
				else break;
			}
			
			thickness = min(delta, thickness);
		}
		Thickness = thickness * UI_RayDepth * normalizedDepth * 0.5;
	}
	else
		Thickness = 1e+5;
		
	Thickness = min(Thickness, 255.0) / 255.0;
}

void Sky(i i, out float4 SkyColor : SV_Target0)
{
	if(UI_SkyColorIntensity <= 0)discard;
	if(i.vpos.x >= 1 || i.vpos.y >= 1)discard;
	SkyColor = 1;

	float4 Color = 1e-6;
	float resolutionScale = getResolutionScale();
	
	if(UI_SkyColorMode)
	{
		static const float2 screen_size   = BUFFER_SCREEN_SIZE;
		static const float2 search_iter   = float2(floor(9.0 * CFX_AspectRatio), 9.0);
		static const float2 search_offset = screen_size * 0.5 / search_iter;
		static const float  skyThreshold  = SkyDepth * FAR_PLANE - 1;
		float2 p = pix;
		
		[unroll]for(float x = 1.0; x <= search_iter.x; x++){
		[unroll]for(float y = 1.0; y <= search_iter.y; y++)
		{
			float2 pixel = search_offset * float2(x,y) * p;
			
			float depth = LDepthLoRes(pixel * resolutionScale.xx).x;
			if(depth > skyThreshold)
				Color += float4(tex2Dlod(sTexColor, float4(pixel,0,0)).rgb, 1);
		}}
		if(Color.a == 0)Color.rgba = 1e-6;
		else
		{
			Color.rgb /= Color.a;
			Color.a   /= float(search_iter.x * search_iter.y + 1e-6);
		}
	}
	
	if(i.vpos.x < 1 && i.vpos.x >= 0 && i.vpos.y < 1 && i.vpos.y >= 0)
	{
		SkyColor.a = lerp(1, 0.9, Color.a);
		
		SkyColor.rgb = Color.rgb;
		if(UI_SkyColorMode)SkyColor.rgb *= UI_SkyColorTint;
		else SkyColor = float4(UI_SkyColorTint, 0);
		SkyColor = max(SkyColor, 1e-3);
	}
}

float4 getSkyColor()
{
	float4 SkyColor = tex2Dfetch(sRT_HLTex1, 0);
	SkyColor.rgb = InvTonemapper(SkyColor.rgb);
	SkyColor.rgb = ClampLuma(SkyColor.rgb, LUM_MAX) * UI_SkyColorIntensity;
	return SkyColor;
}

#include "CompleteRT_RayMarch.fxh"

float3 getNoise(float2 uv, float2 HL, bool mode)
{
	float h = mode ? UI_MaxFrames : HL.g;
	
	float3 bn = BN3dts(uv, h);
	if(h > 64) 
	return frac(bn + floor(Frame / 64) * 3.1415925635);
	return bn;
}

float Jacobian(in float3 reuseHitPos, in float2 tap_uv, in float3 samplPos, in float rcpResolutionScale)
{
	float3 samplRay     = samplPos - reuseHitPos;
	float3 reuseHitNorm = DecodeNormals(tex2Dlod(sRT_NormTex, float4(PostoUV(reuseHitPos),0,0)).xy);
	float3 reusePos     = UVtoPos(tap_uv * rcpResolutionScale);
	float3 reuseRay     = reusePos - reuseHitPos;
	
	float a1 = abs(dot(reuseHitNorm, samplRay));
	float a2 = length(reusePos - reuseHitPos); a2 *= a2;
	float b1 = abs(dot(reuseHitNorm, reuseRay));
	float b2 = length(samplPos - reuseHitPos); b2 *= b2;
	
	return  (b1 * b2) / (a1 * a2);
}

void GetDiffuseNoise(in float3 normals, in float2 uv, inout float3 ReuseNoise, out float weight, out float3 reuseHitPos, out float w)
{
	w=1;
	reuseHitPos = 0;
	float resolutionScale = getResolutionScale();
	float2 p = pix * float2(1, 0.5) * BUFFER_HEIGHT * resolutionScale * 0.1;
	
	float3 RandomNoise = frac(ReuseNoise);
	float3 samplNorm   = normals;
	float  totalWeight = 0;
	
	float3 initDir = getCosineLambert(RandomNoise.xyz, samplNorm, weight);
	ReuseNoise = initDir;
	float J = 1;

	if(getReuseSampleCount() > 1)
	{
		
		float rcpResolutionScale = rcp(resolutionScale);
		
		uv *= resolutionScale;
		
		float3 center_normal;
		float  center_depth;
		GetNormalAndDepth(uv * resolutionScale, center_normal, center_depth);
		float3 samplPos = UVtoPos(uv / resolutionScale);
		float4 center     = tex2Dlod(sRT_TReservoirHistory, float4(uv,0,0));
		
		reuseHitPos = center.yzw;
		float sampleCount = min(64, getReuseSampleCount());
		float rcpSampleCountX2PI = 2.0 * PI / sampleCount;
		
		int validSample = 0;
		int DiskSamples = 0;
		float HL = tex2Dlod(sRT_HLTex1, float4(uv*float2(1,0.5),0,0)).r;
		int requiredValids = 3;
		
		static const float PI2div3 = PI2/3;
		[loop]for(int x; x < sampleCount; x++)
		{
			float2 poisson = poissonDisk[x];
			float rot = (frac(poisson.x + RandomNoise.z) + DiskSamples) * PI2div3;
			
			float2 offset;
			sincos(rot, offset.x, offset.y);
			offset *= frac(poisson.y + RandomNoise.y);
			
			float2 tap_uv  = offset * p + uv;
			if(tap_uv.x >= resolutionScale || tap_uv.x <= 0 || tap_uv.y >= resolutionScale || tap_uv.y <= 0) continue;
			
			float3 normal; float depth;
			GetNormalAndDepth(tap_uv * resolutionScale, normal, depth);
			
			if(dot(center_normal, normal) > 0.9 && abs(center_depth - depth) < 0.05)
			{
				float4 reservoir = tex2Dlod(sRT_TReservoirHistory, float4(tap_uv, 0, 0));
				float sJacobian  = Jacobian(reservoir.yzw, tap_uv, samplPos, rcpResolutionScale);
				reservoir.x *= sJacobian;

				w += reservoir.x;
				validSample ++;
				
				if(frac(1.618 * x + RandomNoise.x) < (reservoir.x / w))
				{
					J = sJacobian;
					reuseHitPos = reservoir.yzw;
					totalWeight = w;
				}
			}
			if(validSample >= requiredValids)break;
			DiskSamples++;
			if(DiskSamples >= requiredValids && validSample < requiredValids)
			{
				DiskSamples = 0;
				p *= 0.5;
			}
		}
		float3 samplRay = samplPos - reuseHitPos;
		
		ReuseNoise = -normalize(samplRay);
		
		if(dot(-ReuseNoise, samplNorm) <= 0)
		{
			ReuseNoise = initDir;
			J = 1;
			totalWeight = 1;
		}
		
		
	}
	w = totalWeight * J;
	float cosTheta = dot(-ReuseNoise, samplNorm);
	float pdf      = cosTheta / J;
	weight = 0.5 * (totalWeight) / (pdf + 1e-6);
	weight = clamp(weight, 1e-6, 1 - 1e-6);
}

float4 ProcessDiffuse(inout float4 FinalColor, in float2 uv, in float HL, in float HitDistance, in float3 position, in bool IsHit, in float weight, in float FadeFac)
{
	if(getReuseSampleCount() > 1)
		HitDistance = tex2Dfetch(sRT_HLTex0, uv * BUFFER_SCREEN_SIZE * getResolutionScale()).x;
		
	HitDistance *= getResolutionScale();
	if(IsHit)
	{
		FinalColor.rgb = max(ClampLuma(FinalColor.rgb, LUM_MAX),0) * UI_Exposure * 2.0f;
		FinalColor.rgb  = AdjustSaturation(FinalColor.rgb, UI_Saturation);
	}
	else if(UI_SkyColorIntensity > 0)
		FinalColor.rgb = max(0,getSkyColor().rgb);
	else FinalColor.rgb = 0;
	
	float AORadius = min(0.99, UI_AORadius * UI_AORadius * 0.99) * getResolutionScale();
	float3 AO = (HitDistance / FAR_PLANE) >= AORadius;AO *= UI_AmbientLight * 0.8 + 0.2;
	FinalColor.rgb = FinalColor.rgb * lerp(1.0, AO, 0.8 * saturate(UI_AOIntensity)) + AO;
	
	return FinalColor;
}

float4 ProcessDiffuse_NoRT()
{
	float4 FinalColor = 1;
	FinalColor.rgb = getSkyColor().rgb;
	
	float ambientLightIntensity = UI_AmbientLight * 0.8 + 0.2;
	FinalColor.rgb += ambientLightIntensity;
	
	return FinalColor;
}

void RayMarchPrep(i i, out float4 FinalColor : SV_Target0, out float AO : SV_Target1)
{
	if(!UI_GIAOEnable || (getReuseSampleCount() <= 1))discard;
	
	i.uv.y *= 2;
	float resolutionScale = getResolutionScale();
	if(i.uv.x > resolutionScale || i.uv.y > resolutionScale)discard;
	float2 jitter = getTemporalJitter().xy;
	float2 jitterUV = i.uv + jitter;
	i.uv /= resolutionScale;
	jitterUV /= resolutionScale;
	
	float depth = clamp(LDepth(jitterUV), 1e-7, 1.0);
	float3 normal = tex2D(sRT_HQNormTex, i.uv * resolutionScale).xyz;
	const float FadeFac = getDepthFade(depth);
	float  HL = tex2D(sRT_HLTex1, jitterUV * resolutionScale * float2(1.0, 0.5)).r;
	
	
	FinalColor = float4(1,0,0,1);
	
	if(FadeFac >= 0.01 && depth <= SkyDepth)
	{		   
		float3 position  = UVtoPos(jitterUV);
		float3 eyedir    = normalize(position);
		
		float weight;
		
		float4 reflection;
		float IsHit;
		float HitDistance;
		float3 noise = getNoise(jitterUV, HL, 1);
		float3 raydir = getCosineLambert(noise.xyz, normal, weight);
		
		DoRayMarch(1, noise.z, position, raydir, reflection.rgb, HitDistance, IsHit);
		FinalColor.rgb  = max(ClampLuma(reflection.rgb, LUM_MAX),0);
		FinalColor.rgb  = FinalColor.rgb * IsHit * weight;
		HitDistance = IsHit ? HitDistance : FAR_PLANE;
		FinalColor.r = toYCC(FinalColor.rgb).r;
		
		FinalColor.yzw = raydir * HitDistance + position;
		
		AO = HitDistance;
	
		float pastResScale = tex2Dfetch(sRT_HistoryTex0, 1).x / resolutionScale;
		float2 history_uv    = i.uv + sampleMotion(i.uv) * resolutionScale;
		{
			i.uv *= resolutionScale;
			i.uv.y /= 2.0;
			
			static const float rcpResolutionScale = rcp(resolutionScale);
			static const float2 p = pix * float2(1,0.5);
			float2 MotionVectors = sampleMotion(frac(i.uv * rcp(resolutionScale) * float2(1,2))) * resolutionScale * float2(1,0.5);
			float2 PastUV  = i.uv + MotionVectors;
			PastUV =  i.uv.y < (0.5 * resolutionScale) ?
				clamp(PastUV, 1e-7, float2(1, 0.5) * resolutionScale - p) :
				clamp(PastUV, float2(0,0.5) * resolutionScale, resolutionScale - p);
			
			float4 HistoryIn = tex2D(sRT_HLTex1, PastUV * pastResScale);
			float3 normal;
			float  depth;
			float2 NDsampling_uvMuliplier = rcpResolutionScale * float2(1,2);
			GetNormalAndDepth(frac(i.uv * NDsampling_uvMuliplier)*resolutionScale*resolutionScale, normal, depth);
			
			const float  facing  = saturate(dot(normal.xyz, normalize(UVtoPos(i.uv * rcpResolutionScale))));
			
			const float2 past_ogcolor = HistoryIn.z;
			const float  curr_ogcolor = dot(1, toYCC(tex2D(sTexColor, frac(i.uv * rcpResolutionScale * float2(1,2))).rgb).gb);
			const float  past_depth   = HistoryIn.w;
			
			bool mask =
			    abs(depth - past_depth) * facing   < Temporal_Filter_DepthT
			 && abs(curr_ogcolor - past_ogcolor.x) < (Temporal_Filter_MVErrorT * .33333)
			;
			
			bool inbound = getDiffuseOrSpecular(i.uv.y) ?
			(PastUV.x < (resolutionScale - p.x) && PastUV.x > 0.5 * p.x) && (PastUV.y < (resolutionScale * 0.5 - p.y) && PastUV.y > 0.5 * p.y):
			(PastUV.x < (resolutionScale - p.x) && PastUV.x > 0.5 * p.x) && (PastUV.y < (resolutionScale - p.y) && PastUV.y > (p.y + resolutionScale) * 0.5);
		
			mask = mask && inbound;
			mask = mask && (HL.x - 1);
			if(PastUV.x < p.x*2 && PastUV.y < p.y*2)mask = 0; //data pixel for the past res scale should be ignored
			
			if(mask > 0)
			{
				float4 TReservoir = tex2D(sRT_TReservoirHistory, PastUV * pastResScale * float2(1.0, 2.0));
				TReservoir.x *= 0.95;
				float w = TReservoir.x + FinalColor.x;
				float RandomNoise = getNoise(jitterUV, HL.x, 1).x;
				if(sqrt(RandomNoise.x) < (TReservoir.x / w))
					FinalColor = TReservoir;
			}
		}
	}
}

void TemporalReservoir_CopyBuffer(i i, out float4 TReservoir : SV_Target0)
{
	if(!UI_GIAOEnable || (getReuseSampleCount() <= 1))discard;
	TReservoir = tex2D(sRT_FilterTex0, i.uv * float2(1.0, 0.5));
}


void RayMarchDiffuse_PS(i i, out float4 FinalColor : SV_Target0)
{
	float resolutionScale = getResolutionScale();
	i.uv.y *= 2;
	
	if(i.uv.x > resolutionScale || i.uv.y > resolutionScale)discard;
	
	if(!UI_GIAOEnable)
		FinalColor = float4(ProcessDiffuse_NoRT().rgb, clamp(LDepth(i.uv), 1e-7, 1.0));
	else
	{
		float2 jitterUV = i.uv + getTemporalJitter().xy;
		i.uv /= resolutionScale;
		jitterUV /= resolutionScale;
		
		float depth;
		float3 normal;
		normal = tex2D(sRT_HQNormTex, i.uv * resolutionScale).xyz;
		depth  = clamp(LDepth(i.uv), 1e-7, 1.0);
		
		const float FadeFac = getDepthFade(depth);
	
		FinalColor = float4(1,0,0,1);
		
		if(FadeFac >= 0.01 && depth <= SkyDepth)
		{
			float  HL = tex2D(sRT_HLTex1, jitterUV * float2(1,0.5)).r;
			float3 noise = getNoise(jitterUV, HL, 1);
			
			float3 DiffuseNoise = noise, ReservoireHitPos = 0;
			float weight, ReservoireLum = 1;
			if(getReuseSampleCount() > 1)
				GetDiffuseNoise(normal, i.uv, DiffuseNoise, weight, ReservoireHitPos, ReservoireLum);
			else DiffuseNoise = getCosineLambert(noise.xyz, normal, weight);
			
			float3 position  = UVtoPos(i.uv);
			float3 eyedir    = normalize(position);
			
			float3 raydir;
			float4 reflection;
			float IsHit;
			float HitDistance;
			
			raydir = DiffuseNoise;
			
			DoRayMarch(1, noise, position, raydir, reflection.rgb, HitDistance, IsHit);
			FinalColor.rgb = max(ClampLuma(reflection.rgb, LUM_MAX),0);
			FinalColor /= ReservoireLum;
			ProcessDiffuse(FinalColor, i.uv, HL.x, HitDistance, position, IsHit, weight, FadeFac);
			
			FinalColor.a   = depth;
			FinalColor.rgb = toYCC(FinalColor.rgb);
		}
	}
}

void RayMarchSpecular_PS(i i, out float4 FinalColor : SV_Target0)
{
	if(!UI_ReflectionEnable)discard;
	
	float resolutionScale = getResolutionScale();
	i.uv.y *= 2;
	if(i.uv.y < resolutionScale)discard;
	
	i.uv.y -= resolutionScale;
	
	if(i.uv.x > resolutionScale || i.uv.y > resolutionScale)discard;
	float2 jitter = getTemporalJitter().xy;
	i.uv += jitter;
	i.uv /= resolutionScale;
	
	float depth = clamp(LDepth(i.uv), 1e-7, 1.0);
	const float FadeFac = getDepthFade(depth);

	FinalColor = float4(1,0,0,1);
	
	if(FadeFac >= 0.01 && depth <= SkyDepth)
	{
		float  HL = tex2D(sRT_HLTex1, i.uv).r;
		float3 noise = getNoise(i.uv, HL, 1);
		
		float3 position  = UVtoPos(i.uv);
		float3 eyedir    = normalize(position);
		
		float3 raydir;
		float4 reflection;
		float IsHit;
		float HitDistance;
		
		DoRayMarch(0, noise, position, raydir, reflection.rgb, HitDistance, IsHit);
		FinalColor.rgb = max(ClampLuma(reflection.rgb, LUM_MAX),0);
		
		if(!IsHit)FinalColor.rgb = tex2D(sTexColor, i.uv).rgb;
		
		FinalColor.a   = depth;
		FinalColor.rgb = toYCC(FinalColor.rgb);
	}
}

void TemporalFilter
(
	i i
	,out float2 HistoryLengthAndTM2 : SV_Target0
	,out float4 FinalColor    : SV_Target1
)
{
	if(checkFXdiscard(i.uv.y))discard;
	
	float resolutionScale = getResolutionScale();
	float rcpResolutionScale = rcp(resolutionScale);
	
	bool renderRegion = i.uv.x > resolutionScale || i.uv.y > resolutionScale;
	if(renderRegion)discard;
	
	static const float2 p = pix * float2(1,0.5);
	const float2 MotionVectors = sampleMotion(frac(i.uv * rcp(resolutionScale) * float2(1,2))) * resolutionScale * float2(1,0.5);
	
	
	float  pastResScale = tex2Dfetch(sRT_HistoryTex0, 1).x * rcpResolutionScale;
	float2 PastUV  = i.uv + MotionVectors;
	PastUV =  i.uv.y < (0.5 * resolutionScale) ?
		clamp(PastUV, 1e-7, float2(1, 0.5) * resolutionScale - p) :
		clamp(PastUV, float2(0,0.5) * resolutionScale, resolutionScale - p);
	
	float4 HistoryIn = tex2D(sRT_HLTex1, PastUV * pastResScale);
	float3 normal;
	float  depth;
	float2 NDsampling_uvMuliplier = rcpResolutionScale * float2(1,2);
	GetNormalAndDepth(frac(i.uv * NDsampling_uvMuliplier)*resolutionScale*resolutionScale, normal, depth);
	
	const float  facing  = saturate(dot(normal.xyz, normalize(UVtoPos(i.uv * rcpResolutionScale))));
	
	const float2 past_ogcolor = HistoryIn.z;
	const float  curr_ogcolor = dot(1, toYCC(tex2D(sTexColor, frac(i.uv * rcpResolutionScale * float2(1,2))).rgb).gb);
	const float  past_depth   = HistoryIn.w;
	
	float4 Current;
	float4 History;
	if(!UI_FilterQuality)
	{
		Current = tex2D(sRT_FilterTex1, i.uv);
		History = tex2D(sRT_HistoryTex0, PastUV * pastResScale);
	}
	else
	{
		Current = tex2D(sRT_FilterTex1, i.uv);
		History = SampleTextureCatmullRom9t(sRT_HistoryTex0, PastUV * pastResScale, BUFFER_SCREEN_SIZE * float2(1,2));
	}
	History = tex2D(sRT_HistoryTex0, PastUV * pastResScale);
	History.rgb = toYCC(clamp(toRGB(History.rgb), 1e-7, 1e+7));
	
	float3 M1 = Current.rgb, M2 = Current.rgb * Current.rgb;
	float3 spatialVar;
	float4 Clamped_History;

	static const float r = VarianceEstimationSearchRadius;
	static const float area = pow(r * 2.0 + 1.0, 2.0);
	
	float mask;
	
	static const float depth_mul = Spatial_Filter_DepthT * (dot(normalize(UVtoPos(frac(i.uv * rcpResolutionScale * float2(1,2)))), normal.xyz) + 0.001);
	const float FadeFac = getDepthFade(depth);
	float wSum = 1;
	float4 sCurrent; float weight;
	if(FadeFac > 0.01 && depth < SkyDepth)
	{
		static const float effectBorder = 0.5 * resolutionScale;
		float2 suv = i.uv;
		[loop]for(int xx = -r; xx <= r; xx++){
		[loop]for(int yy = -r; yy <= r; yy++)
		{
			if(xx==0&&yy==0)continue;
			float2 uv = mad(p, int2(xx, yy), suv);
			
			sCurrent = tex2Dlod(sRT_FilterTex1, float4(uv,0,0));
			weight = exp(-abs(sCurrent.a - Current.a) * depth_mul);
			bool isInside = suv.y >= effectBorder ?
				!(uv.x < 0 || uv.x > resolutionScale || uv.y <= effectBorder || uv.y > resolutionScale) :
				!(uv.x < 0 || uv.x > resolutionScale || uv.y < 0 || uv.y >= effectBorder);
			weight *= isInside;
			
			M1 += sCurrent.rgb * weight;
			M2 += sCurrent.rgb * sCurrent.rgb * weight;	
			
			wSum += weight;
		}}

		M1 /= wSum;
		M2 /= wSum;
	
		spatialVar = sqrt(abs(M1 * M1 - M2));
		
		mask =
		    abs(depth - past_depth) * facing   < Temporal_Filter_DepthT
		 && abs(curr_ogcolor - past_ogcolor.x) < (Temporal_Filter_MVErrorT * .33333)
		;
	}
	else
	{
		mask = 0;
		Clamped_History = float4(1,0,0,1);
	}
	bool inbound = getDiffuseOrSpecular(i.uv.y) ?
	(PastUV.x < (resolutionScale - p.x) && PastUV.x > 0.5 * p.x) && (PastUV.y < (resolutionScale * 0.5 - p.y) && PastUV.y > 0.5 * p.y):
	(PastUV.x < (resolutionScale - p.x) && PastUV.x > 0.5 * p.x) && (PastUV.y < (resolutionScale - p.y) && PastUV.y > (p.y + resolutionScale) * 0.5);
	mask *= inbound;
	if(PastUV.x < p.x*2 && PastUV.y < p.y*2)mask = 0; 
	
	HistoryLengthAndTM2 = HistoryIn.xy;
	
	float HistoryLength = HistoryLengthAndTM2.x * mask;
	HistoryLength  = min(HistoryLength, UI_MaxFrames);
	
	float TM2 = HistoryLengthAndTM2.y;
	
	const float MVSpeed = length(MotionVectors)*100;
	
	float ClampLerp = (getDiffuseOrSpecular(i.uv.y)) ? 
		clamp(MVSpeed, Temporal_Filter_MinClamp, Temporal_Filter_MaxClamp) : 
		1;
		
	float3 PreClamp = History.rgb;
	spatialVar.rgb *= 0.5;
	History.rgb = ClipToAABB(History.rgb, Current.rgb, M1.rgb, spatialVar.rgb);
	History.rgb = clamp(History.rgb, M1.rgb - spatialVar.rgb, M1.rgb + spatialVar.rgb);
	float ClampAmount = abs(lerp(PreClamp.r, History.r, saturate(ClampLerp)) - PreClamp.r);
	
	HistoryLength *= saturate(exp(-ClampAmount * Temporal_Filter_LuminanceT ));
	HistoryLength++;
	
	if(HistoryLength > 4)TM2 = lerp(TM2, Current.x * Current.x, rcp(HistoryLength));//GI lum M2
	else TM2 = M2.x;
	TM2 = max(1e-6, TM2);
	
	FinalColor.rgb  = lerp(History.rgb, Current.rgb, rcp(HistoryLength.r + 1e-7));
	float M1xM1 = (HistoryLength > 4 ? FinalColor.r : M1.r); M1xM1 *= M1xM1;
	FinalColor.a    = abs(TM2 - M1xM1);
	
	HistoryLengthAndTM2 = float2(HistoryLength, TM2);
}

#include "CompleteRT_Denoise.fxh"

#define FilterPassOutput \
out float4 FinalColor : SV_Target0

#define FilterFunctionInsOuts0(size) \
size, sRT_FilterTex0, i.uv, FinalColor

#define FilterFunctionInsOuts1(size) \
size, sRT_FilterTex1, i.uv, FinalColor

void SpatialFilter0(i i, FilterPassOutput){ if(checkFXdiscard(i.uv.y))discard; if(SF0)Filter(FilterFunctionInsOuts0(pow(Spatial_Filter_Base,0)));else dontFilter(FilterFunctionInsOuts0(1)); }		
void SpatialFilter1(i i, FilterPassOutput){ if(checkFXdiscard(i.uv.y))discard; if(SF1)Filter(FilterFunctionInsOuts1(pow(Spatial_Filter_Base,1)));else dontFilter(FilterFunctionInsOuts0(2));  }
void SpatialFilter2(i i, FilterPassOutput){ if(checkFXdiscard(i.uv.y))discard; if(SF2)Filter(FilterFunctionInsOuts0(pow(Spatial_Filter_Base,2)));else dontFilter(FilterFunctionInsOuts0(4));  }
void SpatialFilter3(i i, FilterPassOutput){ if(checkFXdiscard(i.uv.y))discard; if(SF3)Filter(FilterFunctionInsOuts1(pow(Spatial_Filter_Base,3)));else dontFilter(FilterFunctionInsOuts0(8));  }

void SpatialFilter4(i i, FilterPassOutput)
{
	if(checkFXdiscard(i.uv.y))discard;
	
	if(SF4)Filter(FilterFunctionInsOuts0(16));
	else dontFilter(FilterFunctionInsOuts0(16));
	
	float resolutionScale = getResolutionScale();
	float rcpResolutionScale = rcp(resolutionScale);
	
	float depth = LDepth(frac(i.uv * float2(1,2) * rcpResolutionScale));
	float  FadeFac = depth > SkyDepth ? 0 : getDepthFade(depth);
	
	if(getDiffuseOrSpecular(i.uv.y))
		FinalColor = lerp(float4(1,0,0,0), FinalColor, FadeFac);
	else
	{
		static const float2 scaledUV = frac(i.uv*float2(1,2) * rcpResolutionScale);
		float4 CNormals = tex2Dlod(sRT_HQNormTex, float4(scaledUV*resolutionScale,0,0));
		float3 Eyedir   = normalize(UVtoPos(scaledUV));
		float3 LightDir = reflect(Eyedir, CNormals.xyz);
		float3 HalfVec  = normalize(LightDir + Eyedir);
		float  dotLH    = saturate(dot(LightDir, HalfVec));
		
		if(UI_FixOutlines)
		{
			float2 suv = frac(i.uv * float2(1,2) * rcpResolutionScale);
			float2 p = pix;
			[unroll]for(float xx = -p.x; xx <= p.x; xx += p.x){
			[unroll]for(float yy = -p.y; yy <= p.y; yy += p.y)
			{
				if(xx==0&&yy==0)continue;
				float2 offset = float2(xx,yy);
				float4 Normals = tex2Dlod(sRT_HQNormTex, float4(suv * resolutionScale + offset,0,0));
				
				if(!(abs(Normals.w - CNormals.w) < 0.01||dot(Normals.xyz, CNormals.xyz) > 0.9))
				{
					float3 Eyedir  = normalize(UVtoPos(suv + offset));
					
					float3 LightDir = reflect(Eyedir, Normals.xyz);
					float3 HalfVec  = normalize(LightDir + Eyedir);
					dotLH = min(dotLH, saturate(dot(LightDir, HalfVec)));
				}
			}}
		}
		
		float  F0 = saturate(UI_SpecularIntensity * 0.1);
		float intensity = UI_SpecularIntensity*UI_SpecularIntensity+1e-6;
		float Fresnel = F0 + (1.0 - F0) * pow(dotLH, 5.0 / intensity);
		Fresnel = saturate(Fresnel * FadeFac);
		
		if(UI_Debug != 7)
			FinalColor.a = Fresnel;
	}
}

void HistoryBuffer0
(
	i i
	,out float4 ColorHistory   : SV_Target0
)
{
	float4 HistoryIn = tex2D(sRT_HLTex0, i.uv);
	if(checkFXdiscard(i.uv.y)) HistoryIn = 0;
	
	if(HistoryIn.r <= Temporal_Filter_Recurrence_MaxFrames)
		ColorHistory = tex2D(sRT_FilterTex1, i.uv);
	else
		ColorHistory = tex2D(sRT_FilterTex0, i.uv);
	
	float resolutionScale = getResolutionScale();
	
	if(i.vpos.x < 2 && i.vpos.y < 2)ColorHistory = resolutionScale;  
}

float4 tex2Dbilateral(in sampler Tex, in float2 uv, in float2 Jitter)
{
	float2 cDepthUV = uv;
	float  resolutionScale = getResolutionScale();
	uv -= Jitter * resolutionScale;
	float2 textureSize = tex2Dsize(Tex);
	float2 texelSize = rcp(textureSize);
	
	float2 texPos = uv * textureSize + 0.5;
	float2 texOffset = frac(texPos);
	float2 invOffset = 1 - texOffset;
	
	float2 texPos00 = ((texPos - texOffset) - 0.5) * texelSize;
	float2 texPos10 = texPos00 + float2(texelSize.x,0);        
	float2 texPos01 = texPos00 + float2(0,texelSize.y);        
	float2 texPos11 = float2(texPos10.x, texPos01.y);          
		
	float texWeight00 = invOffset.x * invOffset.y;
	float texWeight10 = texOffset.x * invOffset.y;
	float texWeight01 = invOffset.x * texOffset.y;
	float texWeight11 = texOffset.x * texOffset.y;
	
	float rcpResolutionScale = rcp(resolutionScale);
	float4 depth;
	depth.x = LDepth(frac(texPos00 * float2(1,2)) * rcpResolutionScale);
	depth.y = LDepth(frac(texPos10 * float2(1,2)) * rcpResolutionScale);
	depth.z = LDepth(frac(texPos01 * float2(1,2)) * rcpResolutionScale);
	depth.w = LDepth(frac(texPos11 * float2(1,2)) * rcpResolutionScale);
	
	float  cDepth = LDepth(frac(cDepthUV * float2(1,2)) * rcpResolutionScale);
	static const float depthThreshold = 400.0;
	float4 depthW = saturate(exp(-abs(depth - cDepth.xxxx) * depthThreshold));
	depthW = max(1e-6,depthW);
	
	texWeight00 *= depthW.x;
	texWeight10 *= depthW.y;
	texWeight01 *= depthW.z;
	texWeight11 *= depthW.w;
	
	float4 outColor;
	outColor += tex2D(Tex, texPos00) * texWeight00;
	outColor += tex2D(Tex, texPos10) * texWeight10;
	outColor += tex2D(Tex, texPos01) * texWeight01;
	outColor += tex2D(Tex, texPos11) * texWeight11;
	
	outColor /= (texWeight00+texWeight10+texWeight01+texWeight11);
	
	return outColor;
}
	
float4 TemporalStabilize(in float2 uv, in sampler samplerHistory, in sampler samplerCurrent)
{
	float  resolutionScale = getResolutionScale();
	float rcpResolutionScale = rcp(resolutionScale);
	
	float2 p = pix * float2(1, 0.5);
	
	const float2 MotionVectors = sampleMotion(frac(uv * float2(1,2))) * float2(1,0.5);
	float2 PastUV  = uv + MotionVectors;
	PastUV =  uv.y < 0.5 ?
		clamp(PastUV, 1e-7, float2(1, 0.5) - p) :
		clamp(PastUV, float2(0,0.5), 1 - p);
	
	const float  depth = clamp(LDepth(frac(uv * float2(1,2))), 1e-7, 1.0);
	
	float  FadeFac = getDepthFade(depth);
	float4 current = tex2D(samplerCurrent, uv);
	if(depth > SkyDepth || FadeFac < 0.01)current = float4(1,0,0,0);
	
	float4 history = SampleTextureCatmullRom9t(samplerHistory, PastUV, tex2Dsize(samplerHistory));
	
	float4 Max = current, Min = current;
	float4 M1 = current, M2 = current * current;
	
	float4 SCurrent;
	
	float2 texelSize = rcp(tex2Dsize(samplerCurrent));
	float r = 1;
	float rcpArea = rcp(mad(r,2,1) * mad(r,2,1));
	
	[unroll]for(int x = -r; x <= r; x++){
	[unroll]for(int y = -r; y <= r; y++)
	{
		if(x==0&&y==0)continue;
		
		SCurrent = tex2Dlod(samplerCurrent, float4(float2(x,y) * texelSize + uv,0,0));

		Max = max(SCurrent, Max);
		Min = min(SCurrent, Min);
		
		M1 += SCurrent;
		M2 += SCurrent * SCurrent;
	}}
	float4 chistory = history;
	M1 *= rcpArea;
	M2 *= rcpArea;
	
	float4 StandardDeviation = sqrt(abs(M1 * M1 - M2)) * 2;
	float4 current_sharp = current + (current - M1) * (1 - resolutionScale) * TS_Sharpness;
	
	if(TS_Clamp)
	{
		chistory = clamp(history, Min, Max);
		chistory.rgb = ClipToAABB(chistory.rgb, current.rgb, M1.rgb, StandardDeviation.rgb);
	}
	
	float4 diff = saturate((abs(chistory - history)));
	diff.r = diff.g + diff.b;
	uv *= resolutionScale;
	uv = clamp(uv, 0.0, resolutionScale - 1e-6);
	bool inBound = getDiffuseOrSpecular(uv.y) ?
		(PastUV.x < (1 - p.x) && PastUV.x > 0.5 * p.x) && (PastUV.y < (1 * 0.5 - p.y) && PastUV.y > 0.5 * p.y):
		(PastUV.x < (1 - p.x) && PastUV.x > 0.5 * p.x) && (PastUV.y < (1 - p.y) && PastUV.y > (p.y + 1) * 0.5);

	
	float4 LerpFac = TSIntensity * inBound;
	
	if(history.x==0 || !inBound)LerpFac = 0;
	float4 col = lerp(current_sharp, chistory, LerpFac);
	return col;
}

float4 TemporalUpscale(in float2 uv, in sampler samplerHistory, in sampler samplerCurrent)
{
	float  resolutionScale = getResolutionScale();
	float rcpResolutionScale = rcp(resolutionScale);
	
	float2 p = pix * float2(1, 0.5);
	
	const float2 MotionVectors = sampleMotion(frac(uv * float2(1,2))) * float2(1,0.5);
	float2 PastUV  = uv + MotionVectors;
	PastUV =  uv.y < 0.5 ?
		clamp(PastUV, 1e-7, float2(1, 0.5) - p) :
		clamp(PastUV, float2(0,0.5), 1 - p);
	
	const float2 Jitter = getTemporalJitter().xy;
	const float2 nJitter  = getTemporalJitterNormalized();
	const float2 pixelGridCoord = (((uv - Jitter)*BUFFER_SCREEN_SIZE*float2(1,2))%rcpResolutionScale)*2*resolutionScale-1;//[0,rcpResolutionScale)
	float  pixelWeight = resolutionScale >= 1 ? 1 : distance(0, pixelGridCoord)*2;
	
	const float  depth = clamp(LDepth(frac(uv * float2(1,2))), 1e-7, 1.0);
	
	float  FadeFac = getDepthFade(depth);
			float2 currentUV = clamp(uv * resolutionScale , 0.0, resolutionScale - 1e-6);
	float4 current = tex2Dbilateral(samplerCurrent, currentUV, Jitter);
	currentUV -= Jitter * resolutionScale;
	if(depth > SkyDepth || FadeFac < 0.01)current = float4(1,0,0,0);
	
	float4 history = SampleTextureCatmullRom9t(samplerHistory, PastUV, tex2Dsize(samplerHistory));
	
	float4 Max = current, Min = current;
	float4 M1 = current, M2 = current * current;
	float w = 1;
	
	float4 SCurrent; float SDepth, cDepth = depth*FAR_PLANE;
	
	float2 texelSize = rcp(tex2Dsize(samplerCurrent));
	float r = resolutionScale >= 0.85 ? 1 : 2;
	float rcpArea = rcp(mad(r,2,1) * mad(r,2,1));
	
	float depthThreshold = FAR_PLANE * saturate(0.0001 / (length(MotionVectors) * 2.0 + 1e-6));
	float2 depthScale = rcpResolutionScale * float2(1,2);
	
	[loop]for(int x = -r; x <= r; x++){
	[loop]for(int y = -r; y <= r; y++)
	{
		if(x==0&&y==0)continue;
		
		SCurrent = tex2Dlod(samplerCurrent, float4(float2(x,y) * texelSize + currentUV,0,0));
		SDepth = LDepthLoRes(frac((float2(x,y) * texelSize + currentUV) * depthScale) * resolutionScale.xx);
		if(abs(SDepth-cDepth) < depthThreshold)
		{
			Max = max(SCurrent, Max);
			Min = min(SCurrent, Min);
			
			M1 += SCurrent;
			M2 += SCurrent * SCurrent;
			
			w++;
		}
	}}
	float4 chistory = history;
	w = rcp(w);
	M1 *= w;
	M2 *= w;
	
	float4 StandardDeviation = sqrt(abs(M1 * M1 - M2)) * 2;
	float4 current_sharp = current + (current - M1) * (1 - resolutionScale) * TS_Sharpness;
	
	if(TS_Clamp)
	{
		chistory = clamp(history, Min, Max);
		chistory.rgb = ClipToAABB(chistory.rgb, current.rgb, M1.rgb, StandardDeviation.rgb);
	}
	
	float4 diff = saturate((abs(chistory - history)));
	diff.r = diff.g + diff.b;
	uv *= resolutionScale;
	uv = clamp(uv, 0.0, resolutionScale - 1e-6);
	bool inBound = getDiffuseOrSpecular(uv.y) ?
		(PastUV.x < (1 - p.x) && PastUV.x > 0.5 * p.x) && (PastUV.y < (1 * 0.5 - p.y) && PastUV.y > 0.5 * p.y):
		(PastUV.x < (1 - p.x) && PastUV.x > 0.5 * p.x) && (PastUV.y < (1 - p.y) && PastUV.y > (p.y + 1) * 0.5);

	
	float4 LerpFac = TSIntensity * inBound;
	{
		float4 x = LerpFac;
		float4 tw = rcp(1-x);
		float4 pw = x * tw;
		float4 cw = tw - pw;
		float4 gridScale = rcp(resolutionScale * resolutionScale);
		float4 nc = cw * gridScale;
		float4 np = pw * gridScale;
		float4 C  = nc / (nc + pw);
		float4 P  = (np / (np + cw));
		LerpFac = lerp(C, P, saturate(pixelWeight));
	}
	if(history.x==0 || !inBound)LerpFac = 0;
	float4 col = lerp(current_sharp, chistory, LerpFac);
	return col;
}

void TemporalStabilizer(i i, FilterPassOutput)
{
	if(checkFXdiscard(i.uv.y * getResolutionScale()))discard;
	if(getResolutionScale() >= 1)
		FinalColor = TemporalStabilize(i.uv, sRT_HistoryTex1, sRT_FilterTex1);
	else
		FinalColor = TemporalUpscale(i.uv, sRT_HistoryTex1, sRT_FilterTex1);
}

void TemporalStabilizer_CopyBuffer(i i, FilterPassOutput, out float4 HistoryOut : SV_Target1)
{
	FinalColor = tex2D(sRT_FilterTex0, i.uv);
	
	if(!(i.vpos.x >= 1 || i.vpos.y >= 1))discard;
	
	float2 scaledUV = frac(i.uv * float2(1,2) / getResolutionScale());
	float3 col = tex2D(sTexColor, scaledUV).rgb;
	col = toYCC(col);
	
	float4 HistoryIn = tex2D(sRT_HLTex0, i.uv);
	if(checkFXdiscard(i.uv.y)) HistoryIn = 0;
	
	HistoryIn.z = col.y + col.z;
	HistoryIn.w = LDepth(scaledUV);
	
	HistoryOut = HistoryIn;
}

static const float UI_PostSharpness = 0;
float4 sampleLighting_Sharpen(in sampler Tex, in float2 uv)
{
	float4 FinalColor = tex2D(Tex, uv);
	if(UI_PostSharpness==0 || getResolutionScale()>= 1)return FinalColor;
	
	float a = FinalColor.a;
	float4 M1 = FinalColor, Min = 1e+6, Max = -1e+6;
	float wsum = 1;
	[unroll]for(int xx = -1; xx <= 1; xx++){
	[unroll]for(int yy = -1; yy <= 1; yy++)
	{
		if(xx==0&&yy==0)continue;
		float4 sColor = tex2Doffset(Tex, uv, int2(xx,yy));
		M1 += sColor;
		Max = max(Max, sColor);
		Min = min(Min, sColor);
	}}
	M1 /= 9.0;
	
	FinalColor = FinalColor + (FinalColor - M1) * UI_PostSharpness;
	FinalColor = clamp(FinalColor, Min, Max);
	
	return float4(FinalColor.rgb, a);
}

void Output(i i, out float3 FinalColor : SV_Target0)
{
	FinalColor = 0;
	float  resolutionScale = getResolutionScale();
	float2 p = pix * float2(1, 0.5);
	float3 Background = tex2D(sTexColor, i.uv).rgb;
	float  Depth      = clamp(LDepth(i.uv), 1e-7, 1.0);
	float  debug      = UI_Debug;
	if(debug == 1)Background = 0.5;
	if(debug <= 1)
	{
		FinalColor = Background;
		if(UI_ReflectionEnable)
		{
			float4 Reflection = sampleLighting_Sharpen(sRT_HistoryTex1, (i.uv * float2(1,0.5) + float2(0,0.5)));
			
			Reflection.rgb = max(0, toRGB(Reflection.rgb));
			Reflection.rgb = Tonemapper(Reflection.rgb);
			Reflection.rgb = RITM(Reflection.rgb);
			
			float Fresnel = saturate(Reflection.a);
			FinalColor = RTM(lerp(RITM(Background), Reflection.rgb, Fresnel));
		}
		if(UI_GIAOEnable)
		{
			float4 IL = sampleLighting_Sharpen(sRT_HistoryTex1, i.uv * float2(1,0.5)).rgba;
			float  BoostedAO = UI_AOIntensity == 0 ? 1 : pow(abs(IL.r), UI_AOIntensity * 2.0);
			float  AOwCurve = 1 - saturate((IL.r / (1 + IL.r)) * 2);
			AOwCurve = IL.r <= 1;
			IL.r = lerp(IL.r, BoostedAO, saturate(AOwCurve + 1e-6));
			
			IL.rgb = toRGB(IL.rgb);
			IL.rgb = Tonemapper(IL.rgb);
			IL.rgb = RITM(IL.rgb);
			
			FinalColor = RTM(IL.rgb * RITM(FinalColor));
		}
		else if(UI_SkyColorIntensity > 0 || UI_AmbientLight < 1)
		{
			float4 AL = tex2Dfetch(sRT_FilterTex1, 1);	
			FinalColor = RTM(AL.rgb * RITM(FinalColor));
		}
	}
	else if(debug == 2)
	{	
		float3 SDRBackbuffer = tex2D(sTexColor, i.uv).rgb;
		FinalColor  = lum(SDRBackbuffer) > UI_MaskDirect ? 0 : SDRBackbuffer;
		FinalColor *= UI_MaskSky ? Depth < SkyDepth : 1;
		FinalColor  = sqrt(InvTonemapper(FinalColor) / LUM_MAX);
	}
	else if(debug == 3) FinalColor = sqrt(Depth);
	else if(debug == 4) FinalColor = tex2D(sRT_HQNormTex, i.uv*resolutionScale).xyz * 0.5 + 0.5;
	else if(debug == 5) FinalColor = tex2D(sRT_HLTex1, i.uv * resolutionScale).r/UI_MaxFrames;
	else if(debug == 6) FinalColor = GetRoughTex(i.uv * resolutionScale).x;
	else if(debug == 7) FinalColor = RTM(GetVariance(i.uv, sRT_HistoryTex1, tex2D(sRT_FilterTex1, i.uv * resolutionScale).a) / 2);
	else if(debug == 8) FinalColor = float3(abs(sampleMotion(i.uv)*100).rg,0);
	else if(debug == 9) FinalColor = tex2D(sRT_TReservoirHistory, i.uv * resolutionScale).xxx;
	else if(debug ==10) FinalColor = (tex2D(sRT_ThicknessTex,i.uv * resolutionScale).x);
	else FinalColor = 0;
	
	if(Depth <= 0.0001 || Depth > 1) FinalColor = Background;
}
///////////////Pixel Shader////////////////
///////////////Techniques//////////////////
///////////////Techniques//////////////////