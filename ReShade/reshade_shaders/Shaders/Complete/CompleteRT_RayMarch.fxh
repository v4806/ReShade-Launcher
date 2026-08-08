//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 1.6 - Ray marching
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
static const bool UI_FixFlickering = 1;
void DoRayMarch_Specular(float3 noise, float3 position, out float3 Reflection, out bool IsHit) 
{
	float2 UVraypos; float Error;
	const float bias = -position.z * rcp(FAR_PLANE * getResolutionScale())*4;
	
	float2 p = pix; float plength = length(p);
	float resolutionScale = getResolutionScale();
	float2 uv = PostoUV(position);
	float  Roughness = tex2D(sRT_RoughnessTex, uv * resolutionScale).x;
	float3 normals   = tex2D(sRT_HQNormTex, uv * resolutionScale - getTemporalJitter().xy).xyz;
	
	float SampleCount, BackSteps, RaySteps;
#if C_RT_UI_DIFFICULTY == 0
	float3 Q_Preset = Roughness.x < 0.01 ? ReflectionRM_PresetSmooth[UI_QualityPreset] : ReflectionRM_presetRough[UI_QualityPreset];
	RaySteps    = Q_Preset.x;
	BackSteps   = Q_Preset.y;
	SampleCount = Q_Preset.z;
#else
	RaySteps    = min(240, UI_ReflectionRaySteps);
	BackSteps   = floor(RaySteps * 0.15);
	SampleCount = UI_SampleCount;
#endif
	float RayInc = 1 + 1 / sqrt(RaySteps);
	
	float rcpRaySteps = rcp(RaySteps);
	
	float l;
	float sl = 1;
	
	[loop]for(int i = 0; i < RaySteps; i++)
	{
		l += sl;
		sl *= RayInc;
	}
	float slmul = rcp(length(l.xxx)) * FAR_PLANE * 2.55 * STEPNOISE;
	
	float ThicknessMul = -UI_ReflectionRayDepth;
	
	float3 eyedir = normalize(position);
	float weight = 0;
	float weightSum = 1e-6;
	Reflection = 0;
	IsHit = 0;
	float rcpRayInc = rcp(RayInc);
	
	float2 backBufferJitter =  -getTemporalJitter().xy / resolutionScale;
	
	float alpha = Roughness.x * Roughness.x;
	float alpha2 = alpha * alpha;
	float3 t, b;
	getGGX_t_b(normals, t, b);
	[loop]for(int s = 1; s <= SampleCount; s++)
	{
		bool isThisHit = 0;
		float3 seed = frac(s * PI + noise);
		float3 raydir = getHemisphereGGXSample(seed.xy, normals, eyedir, alpha, alpha2, t, b, weight);
		weight = weight >= 1e-6;
		if(weight < 1e-6) continue;
		float j = 0;
		float3 rcpRayIncXDir = rcpRayInc * raydir;
		float steplength = seed.z * slmul + 1;

		float3 raypos   = raydir * max(plength, steplength) + position;
		float hit_step = steplength;
		
		[loop]for(int i = 0; i < RaySteps; i++)
		{
			UVraypos = PostoUV(raypos);
			if(IsSaturated(UVraypos))break;
			float depth = LDepthLoRes(UVraypos * resolutionScale.xx).x;
			Error = depth - raypos.z;
			
			if(Error < bias && (Error > ThicknessMul * max(1,hit_step)))
			{
				i = 0;
				j++;
				if(j <= BackSteps)
				{
					raypos -= steplength * rcpRayIncXDir;
					steplength *= rcpRaySteps;
				}
				else break;
			}
			
			raypos = mad(raydir, steplength, raypos);
			if(raypos.z < 0.0)break;
			steplength *= RayInc;
			if(j == 0 || UI_FixFlickering)hit_step = steplength;
		}
		isThisHit = j > 0 && weight;
		float HitDistance = isThisHit ? distance(raypos, position) : FAR_PLANE;
		
		float3 sampleColor = tex2Dlod(sTexColor, float4(UVraypos.xy + backBufferJitter,0,0)).rgb;
		sampleColor = InvTonemapper(sampleColor);
		
		Reflection += max(ClampLuma(sampleColor * isThisHit, LUM_MAX), 0);
		weightSum = isThisHit + weightSum;
		
		IsHit = IsHit || isThisHit;
	}
	Reflection /= weightSum;
}


void DoRayMarch_Diffuse(float3 noise, float3 position, float3 raydir, out float3 Reflection, out float HitDistance, out bool IsHit) 
{
	float Error; bool hit;
	const float bias = -position.z * rcp(FAR_PLANE * getResolutionScale())*4;
	float2 p = pix;
	float resolutionScale = getResolutionScale();
	float2 backBufferJitter =  -getTemporalJitter().xy / resolutionScale;
	float plength = length(p*float2(1,2)/resolutionScale);
	
	float RaySteps, RayLength;
#if C_RT_UI_DIFFICULTY == 0
	RaySteps = DiffuseRM_Preset[UI_QualityPreset].x;
	RayLength = DiffuseRM_Preset[UI_QualityPreset].y;
#else
	RaySteps = min(1648, UI_RaySteps);
	RayLength = UI_RayLength * 1.3;
#endif
	float steplength = (1+(noise.x * STEPNOISE));
	float RayInc = 1 + 1 / sqrt(RaySteps);
	float l;
	float sl = 1;
	
	[loop]for(int i = 0; i < RaySteps; i++)
	{
		l += sl;
		sl *= RayInc;
	}
	steplength /= length(float3(l.xxx));
	steplength *= (RayLength * RayLength * FAR_PLANE * 1.5);
	steplength  = max(plength, steplength);
	
	float2 UVraypos;
	float3 raypos    = raydir * steplength * 2 + position;
	float  thickness = -UI_RayDepth*5;
	IsHit = 0;
	[loop]for(int i = 0; i < RaySteps; i++)
	{
		UVraypos = PostoUV(raypos)*resolutionScale;
		if(UVraypos.x >= 1 || UVraypos.y >= 1 || UVraypos.y <= 0 || UVraypos.x <= 0) break;
		
		float2 depth = LDepthLoRes(UVraypos);
		
		Error = depth.x - raypos.z;
		
		if(Error < bias)
		{
			if(UI_ThicknessEstimation)
				thickness = -tex2Dlod(sRT_ThicknessTex, float4(UVraypos, 0, 0)).x*255;
			if(Error > thickness)
			{
				IsHit = 1;
				break;
			}
		}
		
		raypos = mad(raydir, steplength, raypos);
		if(raypos.z < 0.0)break;
		steplength *= RayInc;
	}
	float3 HitNormal = tex2D(sRT_HQNormTex, UVraypos).xyz;
	float  HitFacing = dot(raydir, HitNormal);
	HitDistance = IsHit ? distance(raypos, position) : FAR_PLANE;
	
	UVraypos.xy /= resolutionScale;
	float lod = HitDistance * rcp(FAR_PLANE) * 60;
	Reflection = tex2Dlod(sTexColor, float4(UVraypos.xy + backBufferJitter,0,0)).rgb;
	Reflection = InvTonemapper(Reflection) * IsHit * (HitFacing > 0);
	
	if(UI_MaskSky)
		Reflection *= LDepth(UVraypos) < SkyDepth;
		
	if(UI_MaskDirect < 1)
	{
		float SDRReflection = lum(tex2Dlod(sTexColor, float4(UVraypos,0,0)).rgb);
		Reflection *= SDRReflection < UI_MaskDirect;
	}
}

void DoRayMarch(bool mode, float3 noise, float3 position, float3 raydir, out float3 Reflection, out float HitDistance, out bool IsHit) 
{
	Reflection = 0;
	HitDistance = 0;
	IsHit = 0;
	if(mode == 1) DoRayMarch_Diffuse (noise, position, raydir, Reflection, HitDistance, IsHit);
	else
	if(mode == 0) DoRayMarch_Specular(noise, position, Reflection, IsHit);
}