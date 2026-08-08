//Stochastic Screen Space Ray Tracing
//Written by MJ_Ehsan for Reshade
//Version 1.6 - Denoise
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
float GetWeights(float wn, float wd, float clum, float slum, float lT)
{
	float wl = abs(clum - slum) * lT;
	return clamp(exp(-wl - wd) * wn,1e-6, 1);
}

struct FilterStruct
{
	float depth;
	float3 normals;
	float4 cur;
	float4 sum;
};

struct WeightStruct
{
	float cur;
	float sum;
	float luma;
	float depth;
	float normals;
};
    
void Filter(in int size, in sampler Tex, in float2 texcoord, out float4 FinalColor)
{
	float resolutionScale = getResolutionScale();
	bool checkFX = checkFXdiscard(texcoord.y);
	if(texcoord.x > resolutionScale || texcoord.y > resolutionScale || checkFX)discard;
	
	float rcpResolutionScale = rcp(resolutionScale);
	static const float effectBorder = 0.5 * resolutionScale;
	
	FinalColor = 0;

	FilterStruct CenterData;
	
	float  resScale2 = resolutionScale*resolutionScale;
	float2 NDsampling_uvMuliplier = rcpResolutionScale * float2(1,2);
	GetNormalAndDepth(frac(texcoord.xy * NDsampling_uvMuliplier)*resScale2, CenterData.normals, CenterData.depth);
	const float FadeFac = getDepthFade(CenterData.depth);
	
	if(UI_Sthreshold == 0 || CenterData.depth >= SkyDepth || FadeFac < 0.01)FinalColor = tex2Dlod(Tex, float4(texcoord,0,0));
	else
	{
		float  Roughness = sqrt(GetRoughTex(texcoord * float2(1,2) - float2(0,resolutionScale)));
		Roughness = max(Roughness, 1e-6);
		if(texcoord.y < 0.5*resolutionScale) Roughness = 1;
		
		float2 p = pix * float2(1,0.5);
		p *= size;
		
		float HL = tex2D(sRT_HLTex0, texcoord).r;
		float depth_mul = Spatial_Filter_DepthT * (dot(normalize(UVtoPos(frac(texcoord * float2(1,2) / resolutionScale))), CenterData.normals) + 0.001);
		
		CenterData.cur = tex2Dlod(Tex, float4(texcoord, 0, 0));
		
		float Variance = GetVariance(texcoord, Tex, HL.r) * (texcoord.y < effectBorder ? 1 : Roughness); Variance += 1e-6;
		const float lum_threshold    = Spatial_Filter_LuminanceT / Variance;
		float geometryThresholdloosen = 1;
		
		const float depth_threshold  = depth_mul * geometryThresholdloosen;
		const float normal_threshold = Spatial_Filter_NormalT * geometryThresholdloosen;
		
		FilterStruct NeighborData;
		WeightStruct w;
		NeighborData.sum = CenterData.cur;
		w.sum = 1;
		float4 Min = 1e+7, Max = -1e+7;
		
		geometryThresholdloosen = 1;
		const float depth_threshold_2  = depth_mul * geometryThresholdloosen;
		const float normal_threshold_2 = Spatial_Filter_NormalT * geometryThresholdloosen;

		static const int r = Spatial_Filter_Radius;
		w.cur = 1;
		bool isInside = 1;
		float4 offset = float4(0,0,0,0);
		
		if(texcoord.y < effectBorder)
		{
			[unroll]for(int xx = -r; xx <= r; xx++){
			[unroll]for(int yy = -r; yy <= r; yy++){
				if(xx==0&&yy==0)continue;
				offset.xy = mad(float2(xx,yy), p, texcoord);
				isInside = !(offset.x < 0 || offset.x > resolutionScale || offset.y < 0 || offset.y >= effectBorder);
				
				GetNormalAndDepth((offset.xy * NDsampling_uvMuliplier)*resScale2, NeighborData.normals, NeighborData.depth);
				NeighborData.cur = tex2Dlod(Tex, offset);
				
				w.normals = dot(NeighborData.normals, CenterData.normals);
				w.depth   = abs(NeighborData.depth - CenterData.depth);
				
				Min = isInside ? min(Min, NeighborData.cur) : Min;
				Max = isInside ? max(Max, NeighborData.cur) : Max;
				
				w.cur = isInside * GetWeights(pow(w.normals, normal_threshold), w.depth * depth_threshold, CenterData.cur.x, NeighborData.cur.x, lum_threshold);
				NeighborData.sum += NeighborData.cur * float4(w.cur.xxx, w.cur * w.cur);
				w.sum += w.cur;
			}}
		}
		else
		{
			[unroll]for(int xx = -r; xx <= r; xx++){
			[unroll]for(int yy = -r; yy <= r; yy++){
				if(xx==0&&yy==0)continue;
				offset.xy = mad(float2(xx,yy), p, texcoord);
				isInside = !(offset.x < 0 || offset.x > resolutionScale || offset.y <= effectBorder || offset.y > resolutionScale);
				
				GetNormalAndDepth(frac(offset.xy * NDsampling_uvMuliplier)*resScale2, NeighborData.normals, NeighborData.depth);
				NeighborData.cur = tex2Dlod(Tex, offset);
				
				w.normals = dot(NeighborData.normals, CenterData.normals);
				w.depth   = abs(NeighborData.depth - CenterData.depth);
				
				Min = isInside ? min(Min, NeighborData.cur) : Min;
				Max = isInside ? max(Max, NeighborData.cur) : Max;
				
				w.cur = isInside * GetWeights(pow(w.normals, normal_threshold), w.depth * depth_threshold, CenterData.cur.x, NeighborData.cur.x, lum_threshold);
				NeighborData.sum += NeighborData.cur * float4(w.cur.xxx, w.cur * w.cur);
				w.sum += w.cur;
			}}
		}
		NeighborData.sum /= (float4(w.sum.xxx, w.sum * w.sum) + 1e-7);
		if(size<=4)NeighborData.sum.rgb = clamp(NeighborData.sum.rgb, Min.rgb, Max.rgb);
		FinalColor = max(NeighborData.sum, -1e+7);
	}
}

void dontFilter(in int size, in sampler Tex, in float2 texcoord, out float4 FinalColor){FinalColor = tex2D(Tex, texcoord);}