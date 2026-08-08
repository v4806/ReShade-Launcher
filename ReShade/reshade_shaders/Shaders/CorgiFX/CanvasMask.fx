//CanvasMasking by originalnicodr, based in the AdaptiveFog shader by otis wich also use his code from Emphasize.fx, and inspired by the BeforeAfterWithDepth shader from Jacob Maximilian Fober
//Check for updates here: https://github.com/originalnicodr/CorgiFX

///////////////////////////////////////////////////////////////////
// Simple depth-based fog powered with bloom to fake light diffusion.
// The bloom is borrowed from SweetFX's bloom by CeeJay.
//
// As Reshade 3 lets you tweak the parameters in-game, the mouse-oriented
// feature of the v2 Adaptive Fog is no longer needed: you can select the
// fog color in the reshade settings GUI instead.
//
///////////////////////////////////////////////////////////////////
// By Otis / Infuse Project
///////////////////////////////////////////////////////////////////

#include "ReShadeUI.fxh"
#include "ReShade.fxh"

uniform float AlphaA <
	ui_label = "透明度渐变A";
	ui_category = "渐变控制";
	ui_type = "color";
> = 1.0;

uniform float AlphaB <
	ui_label = "透明度渐变B";
	ui_category = "渐变控制";
	ui_type = "color";
> = 0.0;

uniform int GradientType <
	ui_label = "遮罩类型";
	ui_category = "渐变控制";
	ui_type = "combo";
	ui_items = "线性\0径向\0条带\0菱形\0";
> = 0;

uniform float Scale <
	ui_label = "渐变锐度";
	ui_category = "渐变控制";
	ui_type = "drag";
	ui_min = -10.0; ui_max = 10.0; ui_step = 0.01;
> = 1.0;

uniform float Axis <
	ui_label = "角度";
	ui_category = "线性渐变控制";
	ui_type = "drag";
	ui_step = 0.1;
	ui_min = -180.0; ui_max = 180.0;
> = 0.0;

uniform float Offset <
	ui_label = "位置";
	ui_category = "线性渐变控制";
	ui_type = "drag";
	ui_step = 0.002;
	ui_min = -0.5; ui_max = 0.5;
> = 0.0;

uniform float Size <
	ui_label = "大小";
	ui_category = "径向渐变控制";
	ui_type = "drag";
	ui_step = 0.002;
	ui_min = 0.0; ui_max = 1.0;
	ui_category_closed = true;
> = 0.0;

uniform float2 Originc <
	ui_label = "位置";
	ui_category = "径向渐变控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = -1.5; ui_max = 2;
> = float2(0.5, 0.5);

uniform float2 Modifierc <
	ui_label = "修改器";
	ui_category = "径向渐变控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.000; ui_max = 10.000;
> = float2(1.0, 1.0);

uniform float AnguloR <
	ui_label = "角度";
	ui_category = "径向渐变控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0; ui_max = 360;
> = 0.0;

uniform float SizeS <
	ui_label = "大小";
	ui_category = "条带渐变控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0; ui_max = 100;
	ui_category_closed = true;
> = 0.0;

uniform float2 PositionS <
	ui_label = "位置";
	ui_category = "条带渐变控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0; ui_max = 1;
> = float2(0.5, 0.5);

uniform float AnguloS <
	ui_label = "角度";
	ui_category = "条带渐变控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0; ui_max = 360;
> = 0.0;



uniform float Sized <
	ui_label = "大小";
	ui_type = "drag";
	ui_step = 0.002;
	ui_min = 0.0; ui_max = 7.0;
	ui_category = "菱形渐变控制";
	ui_category_closed = true;
> = 0.0;

uniform float2 Origind <
	ui_category = "菱形渐变控制";
	ui_label = "位置";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = -1.5; ui_max = 2;
> = float2(0.5, 0.5);

uniform float2 Modifierd <
	ui_category = "菱形渐变控制";
	ui_label = "修改器";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.000; ui_max = 10.000;
> = float2(1.0, 1.0);

uniform float Angulod <
	ui_category = "菱形渐变控制";
	ui_label = "角度";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0; ui_max = 360;
> = 0.0;



uniform int FogType <
	ui_type = "combo";
	ui_label = "雾类型";
	ui_category = "雾控制";
	ui_items = "自适应雾\0强调雾\0深度切片雾\0";
	ui_category_closed = true;
> = false;

uniform bool FlipFog <
	ui_label = "翻转雾";
	ui_category = "雾控制";
> = false;

uniform float MaxFogFactor <
	ui_label = "最大雾因子";
	ui_category = "自适应雾控制";
	ui_type = "drag";
	ui_min = 0.000; ui_max=1.000;
	ui_step = 0.001;
	ui_tooltip = "最大雾因子。1.0使远处物体完全被雾覆盖，较低的值会让它们透过雾隐约可见。";
> = 1.0;

uniform float FogCurve <
	ui_label = "雾曲线因子";
	ui_category = "自适应雾控制";
	ui_type = "drag";
	ui_step = 0.01;
	ui_min = 0.00; ui_max=175.00;
	ui_tooltip = "控制远处物体被雾覆盖的速度曲线。低值使雾效果轻微，高值使雾效果快速生效。最大值会使雾外的物体几乎不可见。";
> = 70.0;

uniform float FogStart <
	ui_label = "雾起始因子";
	ui_category = "自适应雾控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.000; ui_max=1.000;
	ui_tooltip = "雾的起始位置。0.0在相机处，1.0在地平线，0.5在地平线中间。此点之前不会出现雾。";
> = 0.180;

uniform float FocusDepth <
	ui_category = "强调雾控制";
	ui_category_closed = true;
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.000; ui_max = 1.000;
	ui_tooltip = "焦点的手动对焦深度。范围从0.0（相机为焦平面）到1.0（地平线为焦平面）。";
> = 0.180;

uniform float FocusRangeDepth <
	ui_category = "强调雾控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.0; ui_max = 1.000;
	ui_tooltip = "手动对焦深度周围应强调的范围深度。此范围外将进行弱化处理。";
> = 0.010;

uniform float FocusEdgeDepth <
	ui_category = "强调雾控制";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.000; ui_max = 1.000;
	ui_tooltip = "焦点范围边缘的深度。0.00表示无深度，效果在焦点范围边缘立即生效；\n1.00表示效果在焦点范围边缘到地平线之间平滑过渡。";
> = 0.070;

uniform float FogCurveE <
	ui_label = "锐度";
	ui_type = "drag";
	ui_min = 0.00; ui_max=1;
	ui_step = 0.01;
	ui_category = "强调雾控制";
> = 0;

uniform bool Spherical <
	ui_category = "强调雾控制";
	ui_tooltip = "在焦点周围使用球形强调而非2D平面";
> = false;

uniform int Sphere_FieldOfView <
	ui_category = "强调雾控制";
	ui_type = "drag";
	ui_min = 1; ui_max = 180;
	ui_tooltip = "指定当前游戏使用的估计视野角度。范围从1度到180度（半个场景）。\n普通游戏通常使用60到90之间的值。";
> = 75;

uniform float Sphere_FocusHorizontal <
	ui_category = "强调雾控制";
	ui_type = "drag";
	ui_min = 0; ui_max = 1;
	ui_tooltip = "指定焦点在水平轴上的位置。0表示屏幕左边缘，1表示屏幕右边缘。";
> = 0.5;

uniform float Sphere_FocusVertical <
	ui_category = "强调雾控制";
	ui_type = "drag";
	ui_min = 0; ui_max = 1;
	ui_tooltip = "指定焦点在垂直轴上的位置。0表示屏幕上边缘，1表示屏幕下边缘。";
> = 0.5;

uniform float depth_near <
		ui_category_closed = true;
        ui_type = "drag";
        ui_label = "深度近平面";
        ui_tooltip = "深度近平面";
        ui_category = "深度切片雾控制";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.0;
uniform float depthpos <
        ui_type = "drag";
        ui_label = "深度位置";
        ui_tooltip = "深度位置";
        ui_category = "深度切片雾控制";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.200;
uniform float depth_far <
        ui_type = "drag";
        ui_label = "深度远平面";
        ui_tooltip = "深度远平面";
        ui_category = "深度切片雾控制";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.0;
uniform float depth_smoothing <
        ui_type = "drag";
        ui_label = "深度平滑";
        ui_tooltip = "深度平滑";
        ui_category = "深度切片雾控制";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.005;

uniform bool ShowDebug <
    //ui_category = ;
    ui_label = "调试视图";
	ui_tooltip = "以灰度显示遮罩。";
> = false;


uniform float2 FogRotationAngle  <
	ui_category_closed = true;
	ui_text = "雾旋转（目前仅适用于自适应雾）";
    ui_label = "雾旋转角度";
	ui_type = "drag";
	ui_min = -50; ui_max = 50; ui_step = 0.01;
	ui_category = "实验性";
> = float2(0, 0);

uniform float2 FogRotationCenter  <
    ui_label = "旋转中心";
	ui_type = "drag";
	ui_min = 0; ui_max = 1;
	ui_category = "实验性";
> = float2(0.5, 0.5);

#ifndef M_PI
	#define M_PI 3.1415927
#endif

//Aux function for strip gradient
float DistToLine(float2 pt1, float2 pt2, float2 testPt)
{
  float2 lineDir = pt2 - pt1;
  float2 perpDir = float2(lineDir.y, -lineDir.x);
  float2 dirToPt1 = pt1 - testPt;
  return abs(dot(normalize(perpDir), dirToPt1));
}

//rotate vector spec
float2 rotate(float2 v,float2 o, float a){
	float2 v2= v-o;
	v2=float2((cos(a) * v2.x-sin(a)*v2.y),sin(a)*v2.x +cos(a)*v2.y);
	v2=v2+o;
	return v2;
}

texture BeforeTarget { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
sampler BeforeSampler { Texture = BeforeTarget; };

//Emphasize algorithm from Otis
float CalculateDepthDiffCoC(float2 texcoord : TEXCOORD)
{
	const float scenedepth = ReShade::GetLinearizedDepth(texcoord);
	const float scenefocus =  FocusDepth;
	const float desaturateFullRange = FocusRangeDepth+FocusEdgeDepth;
	float depthdiff;
	
	if(Spherical == true)
	{
		texcoord.x = (texcoord.x-Sphere_FocusHorizontal)*ReShade::ScreenSize.x;
		texcoord.y = (texcoord.y-Sphere_FocusVertical)*ReShade::ScreenSize.y;
		const float degreePerPixel = Sphere_FieldOfView / ReShade::ScreenSize.x;
		const float fovDifference = sqrt((texcoord.x*texcoord.x)+(texcoord.y*texcoord.y))*degreePerPixel;
		float fovt=cos(fovDifference*(2*M_PI/360));
		depthdiff = sqrt((scenedepth*scenedepth)+(scenefocus*scenefocus)-(2*scenedepth*scenefocus*fovt-2*scenedepth*scenefocus*(1-FogCurveE)));
		//depthdiff = sqrt((scenedepth*scenedepth)+(scenefocus*scenefocus)-(2*scenedepth*scenefocus));
	}
	else
	{
		depthdiff = abs(scenedepth-scenefocus);
	}

	if (depthdiff > desaturateFullRange)
		return saturate(1.0);
	else
		return saturate(smoothstep(0, desaturateFullRange, (depthdiff*(1-FogCurveE))));
}

//credits to prod80
float PS_DepthSlice(float2 texcoord : TEXCOORD)
{
    float4 color      = tex2D( ReShade::BackBuffer, texcoord );
    float depth       = ReShade::GetLinearizedDepth( texcoord ).x;
    float depth_np    = depthpos - depth_near;
    float depth_fp    = depthpos + depth_far;
    float dn          = smoothstep( depth_np - depth_smoothing, depth_np, depth );
    float df          = 1.0f - smoothstep( depth_fp, depth_fp + depth_smoothing, depth );
    
    float opacity    = 1.0f - ( dn * df );
	return opacity;
}

void BeforePS(float4 vpos : SV_Position, float2 UvCoord : TEXCOORD, out float3 Image : SV_Target)
{
	// Grab screen texture
	Image = tex2D(ReShade::BackBuffer, UvCoord).rgb;
}


void AfterPS(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target){
    fragment.rgba = tex2D(ReShade::BackBuffer, texcoord).rgb;

	const float depth = ReShade::GetLinearizedDepth(texcoord).r;
	float fogFactor;
	switch(FogType){
		case 0:{

			//float2 uv = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / float2( 512.0f, 512.0f ); // create multiplier on texcoord so that we can use 1px size reads on gaussian noise texture (since much smaller than screen)
		    //uv.xy = uv.xy * texcoord.xy;

			float2 rotationfactor=float2(0.5,0.5)-(texcoord - FogRotationCenter)*FogRotationAngle;
			fogFactor= clamp(((rotationfactor.x + rotationfactor.y)*depth - FogStart) * FogCurve, 0.0, MaxFogFactor);
			break;
		}
		case 1:{
			fogFactor= 1-CalculateDepthDiffCoC(texcoord.xy);
			break;
		}
		case 2:{
			fogFactor= PS_DepthSlice(texcoord.xy);
			break;
		}
	}

	if (FlipFog) fogFactor = 1 - fogFactor;

    switch (GradientType){
		case 0: {
	        float2 origin = float2(0.5, 0.5);
	        float2 uvtest= float2(texcoord.x-origin.x,texcoord.y-origin.y);
	        float angulo=radians(Axis);
            uvtest = float2(cos(angulo) * uvtest.x-sin(angulo)*uvtest.y, sin(angulo)*uvtest.y +cos(angulo)*uvtest.x)+Offset;
	        float gradient= (Scale<0) ? saturate(uvtest.x*(-pow(2,abs(Scale)))+Offset): saturate(uvtest.x*pow(2,abs(Scale))+Offset);
	        fragment=lerp(tex2D(BeforeSampler, texcoord).rgb, tex2D(ReShade::BackBuffer, texcoord).rgb, fogFactor*lerp(AlphaA, AlphaB, gradient));
			
			if (ShowDebug){
				fragment=fogFactor*lerp(AlphaA, AlphaB, saturate(gradient));
			}
			break;
        }
        case 1:{
			float distfromcenter=distance(float2(Originc.x*Modifierc.x, Originc.y*Modifierc.y), float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT)*Modifierc.x,texcoord.y*Modifierc.y));
			float angulo=radians(AnguloR);
			float2 uvtemp=float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT),texcoord.y);
			float dist2 = distance(Originc*Modifierc,rotate(uvtemp,Originc,angulo)*Modifierc);
			float gradient=(Scale<0) ? saturate((dist2-Size)*(-pow(2,abs(Scale)))) : saturate((dist2-Size)*(pow(2,abs(Scale))));
			fragment=lerp(tex2D(BeforeSampler, texcoord).rgb, tex2D(ReShade::BackBuffer, texcoord).rgb, fogFactor*lerp(AlphaA, AlphaB, gradient));
			
			if (ShowDebug){
				fragment=fogFactor*lerp(AlphaA, AlphaB, saturate(gradient));
			}

			break;
        }
        case 2:{
            float2 ubs = texcoord;
			ubs.y = 1.0 - ubs.y;
			float gradient = saturate((DistToLine(PositionS, float2(PositionS.x-sin(radians(AnguloS)),PositionS.y-cos(radians(AnguloS))), ubs) * 2.0)*(pow(2,Scale+2))-SizeS);
			fragment=lerp(tex2D(BeforeSampler, texcoord).rgb, tex2D(ReShade::BackBuffer, texcoord).rgb, fogFactor*lerp(AlphaA, AlphaB, gradient));
			
			if (ShowDebug){
				fragment=fogFactor*lerp(AlphaA, AlphaB, saturate(gradient));
			}
			break;
        }
		case 3:{
			float angle=radians(Angulod);
			//mod=float2(saturate(mod.x),saturate(mod.y));
			//float2 uv=rotate(texcoord,Origind,radians(45));
			float2 uv=rotate(float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT)*Modifierd.x,texcoord.y*Modifierd.y),Origind*Modifierd,radians(45));
			uv=rotate(uv,Origind*Modifierd,radians(Angulod));
			float gradient = 1 - pow(max(abs((uv.x - Origind.x*Modifierd.x)/Sized), abs((uv.y - Origind.y*Modifierd.y)/Sized)),exp(Scale+3));
			//float2 uv=rotate(float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT),texcoord.y),Origind,radians(45+Angulod));
			
			//float2 uv=rotate(float2(texcoord.x*Modifierd.x,texcoord.y*Modifierd.y),Origind,radians(45));
			//uv=rotate(float2(((uv.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT),uv.y*Modifierd.y),Origind,angle);
			//float gradient = 1 - pow(max(abs((uv.x - Origind.x)/Sized), abs((uv.y - Origind.y)/Sized)),exp(Scale));


			//float2 uv=rotate(float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT)*Modifierd.x,texcoord.y*Modifierd.y),Origind,angle);
			//float gradient = 1 - pow(max(abs((uv.x - Origind.x)/Sized), abs((uv.y - Origind.y)/Sized)),exp(Scale));
			fragment=lerp(tex2D(BeforeSampler, texcoord).rgb, tex2D(ReShade::BackBuffer, texcoord).rgb, fogFactor*lerp(AlphaA, AlphaB, saturate(gradient)));
			if (ShowDebug){
				fragment=fogFactor*lerp(AlphaA, AlphaB, saturate(gradient));
			}
			break;
		}
    }
}

technique BeforeCanvasMask < ui_tooltip = "Place this technique before effects you want compare.\nThen move technique 'After'"; >
{
	pass Before
	{
		VertexShader = PostProcessVS;
		PixelShader = BeforePS;
		RenderTarget = BeforeTarget;
	}
}
technique AfterCanvasMask < ui_tooltip = "Place this technique after effects you want compare.\nThen move technique 'Before'"; >
{
	pass After
	{
		VertexShader = PostProcessVS;
		PixelShader = AfterPS;
	}
}
