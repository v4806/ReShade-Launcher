//CanvasFog shader by originalnicodr, a modified version of Adaptive fog by Otis wich also use his code from Emphasize.fx, all credits goes to him
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
// 3D emphasis code by SirCobra. 

#include "Reshade.fxh"
#include "ReShadeUI.fxh"

  ////////////
 /// MENU ///
////////////

uniform float4 ColorA <
	ui_label = "颜色 (A)";
    ui_type = "color";
	ui_category = "颜色A控制";
> = float4(1.0, 0.0, 0.0, 1.0);

uniform bool UseColorPickerA<
	ui_text = "颜色A取色器选项";
	ui_label = "使用颜色A取色器";
	ui_category = "颜色A控制";
	ui_tooltip = "从屏幕选择颜色来替代颜色A。注意仍然使用颜色A的透明度通道。";
> = false;

uniform float2 axisColorASelectAxis <
	ui_category = "颜色A控制";
	ui_label = "颜色A取色器位置";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.000; ui_max = 1.000;
> = float2(0.5, 0.5);

uniform bool drawColorASelectON <
	ui_category = "颜色A控制";
	ui_label = "绘制颜色A取色器位置";
    ui_tooltip = "仅在使用取色器时可见";
> = false;

uniform float4 ColorB <
	ui_label = "颜色 (B)";
	ui_type = "color";
	ui_category = "颜色B控制";
> = float4(0.0, 0.0, 1.0, 0.0);

uniform bool UseColorPickerB<
	ui_text = "颜色B取色器选项";
	ui_label = "使用颜色B取色器";
	ui_category = "颜色B控制";
	ui_tooltip = "从屏幕选择颜色来替代颜色B。注意仍然使用颜色B的透明度通道。";
> = false;

uniform float2 axisColorBSelectAxis <
	ui_category = "颜色B控制";
	ui_label = "颜色B取色器位置";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.000; ui_max = 1.000;
> = float2(0.5, 0.5);

uniform bool drawColorBSelectON <
	ui_category = "颜色B控制";
	ui_label = "绘制颜色B取色器位置";
    ui_tooltip = "仅在使用取色器时可见";
> = false;

uniform bool UseHSVGradient <
	ui_label = "使用HSV渐变";
> = false;

uniform bool Flip <
	ui_label = "翻转颜色";
> = false;


uniform int GradientType <
	ui_type = "combo";
	ui_label = "渐变类型";
	ui_category = "渐变控制";
	ui_items = "线性\0径向\0条带\0菱形\0";
> = 0;

uniform int BlendM <
	ui_type = "combo";
	ui_label = "混合模式";
	ui_tooltip = "选择渐变与屏幕的混合模式。";
	ui_items = "正常\0正片叠底\0滤色\0叠加\0变暗\0变亮\0颜色减淡\0颜色加深\0强光\0柔光\0差值\0排除\0色相\0饱和度\0颜色\0明度\0线性加深\0线性减淡\0亮光\0线性光\0点光\0实色混合\0反射\0发光\0";
	ui_category = "渐变控制";
> = 0;

uniform float Scale <
	ui_label = "渐变锐度";
	ui_type = "drag";
	ui_min = -10.0; ui_max = 10.0; ui_step = 0.0001;
	ui_category = "渐变控制";
> = 1.0;

uniform float Axis <
	ui_label = "角度";
	ui_type = "drag";
	ui_step = 0.1;
	ui_min = -180.0; ui_max = 180.0;
	ui_category = "线性渐变控制";
> = 0.0;

uniform float Offset <
	ui_type = "drag";
	ui_label = "位置";
	ui_step = 0.001;
	ui_min = -0.5; ui_max = 0.5;
	ui_category = "线性渐变控制";
> = 0.0;

uniform float Size <
	ui_label = "大小";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.0; ui_max = 1.0;
	ui_category = "径向渐变控制";
	ui_category_closed = true;
> = 0.0;

uniform float2 Originc <
	ui_category = "径向渐变控制";
	ui_label = "位置";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = -1.5; ui_max = 2;
> = float2(0.5, 0.5);

uniform float2 Modifierc <
	ui_category = "径向渐变控制";
	ui_label = "修改器";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0.000; ui_max = 10.000;
> = float2(1.0, 1.0);

uniform float AnguloR <
	ui_category = "径向渐变控制";
	ui_label = "角度";
	ui_type = "drag";
	ui_step = 0.1;
	ui_min = 0; ui_max = 360;
> = 0.0;

uniform float SizeS <
	ui_category = "条带渐变控制";
	ui_label = "大小";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0; ui_max = 100;
	ui_category_closed = true;
> = 0.0;

uniform float2 PositionS <
	ui_category = "条带渐变控制";
	ui_label = "位置";
	ui_type = "drag";
	ui_step = 0.001;
	ui_min = 0; ui_max = 1;
> = float2(0.5, 0.5);

uniform float AnguloS <
	ui_category = "条带渐变控制";
	ui_label = "角度";
	ui_type = "drag";
	ui_step = 0.1;
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
	ui_label = "反转雾";
	ui_category = "雾控制";
> = false;

uniform float MaxFogFactor <
	ui_type = "drag";
	ui_min = 0.000; ui_max=1.000;
	ui_tooltip = "最大雾因子。1.0使远处物体完全被雾覆盖，较低的值会让它们透过雾隐约可见。";
	ui_step = 0.001;
	ui_category = "自适应雾控制";
> = 1.0;

uniform float FogCurve <
	ui_type = "drag";
	ui_min = 0.00; ui_max=175.00;
	ui_step = 0.01;
	ui_tooltip = "控制远处物体被雾覆盖的速度曲线。低值使雾效果轻微，高值使雾效果快速生效。最大值会使雾外的物体几乎不可见。";
	ui_category = "自适应雾控制";
> = 170;

uniform float FogStart <
	ui_type = "drag";
	ui_min = 0.000; ui_max=1.000;
	ui_step = 0.001;
	ui_category = "自适应雾控制";
	ui_tooltip = "雾的起始位置。0.0在相机处，1.0在地平线，0.5在地平线中间。此点之前不会出现雾。";
> = 0.2;

uniform float FocusDepth <
	ui_type = "drag";
	ui_min = 0.000; ui_max = 1.000;
	ui_step = 0.001;
	ui_tooltip = "焦点的手动对焦深度。范围从0.0（相机为焦平面）到1.0（地平线为焦平面）。";
	ui_category = "强调雾控制";
	ui_category_closed = true;
> = 0.100;

uniform float FocusRangeDepth <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.000;
	ui_step = 0.001;
	ui_tooltip = "手动对焦深度周围应强调的范围深度。此范围外将进行弱化处理。";
	ui_category = "强调雾控制";
> = 1.0;

uniform float FocusEdgeDepth <
	ui_type = "drag";
	ui_min = 0.000; ui_max = 1.000;
	ui_tooltip = "焦点范围边缘的深度。0.00表示无深度，效果在焦点范围边缘立即生效；\n1.00表示效果在焦点范围边缘到地平线之间平滑过渡。";
	ui_category = "强调雾控制";
	ui_step = 0.001;
> = 0.150;

uniform float FogCurveE <
	ui_label = "锐度";
	ui_type = "drag";
	ui_min = 0.00; ui_max=1;
	ui_step = 0.01;
	ui_category = "强调雾控制";
> = 0;


uniform bool Spherical <
	ui_label = "启用球形模式";
	ui_text= "球形模式";
	ui_tooltip = "在焦点周围使用球形强调而非2D平面";
	ui_category = "强调雾控制";
> = false;

uniform int Sphere_FieldOfView <
	ui_type = "drag";
	ui_min = 1; ui_max = 180;
	ui_tooltip = "指定当前游戏使用的估计视野角度。范围从1度到180度（半个场景）。\n普通游戏通常使用60到90之间的值。";
	ui_category = "强调雾控制";
> = 75;

uniform float Sphere_FocusHorizontal <
	ui_type = "drag";
	ui_min = 0; ui_max = 1;
	ui_tooltip = "指定焦点在水平轴上的位置。0表示屏幕左边缘，1表示屏幕右边缘。";
	ui_category = "强调雾控制";
> = 0.5;

uniform float Sphere_FocusVertical <
	ui_type = "drag";
	ui_min = 0; ui_max = 1;
	ui_tooltip = "指定焦点在垂直轴上的位置。0表示屏幕上边缘，1表示屏幕下边缘。";
	ui_category = "强调雾控制";
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

uniform float FogRotationDepth  <
    ui_label = "雾深度因子";
	ui_type = "drag";
	ui_min = 0; ui_max = 1;
	ui_category = "实验性";
> = 0;

uniform float FogRotationDepthVisibility  <
    ui_label = "雾旋转可见度";
	ui_type = "drag";
	ui_min = 0; ui_max = 25;
	ui_step = 0.5;
	ui_category = "实验性";
> = 25;

uniform bool UseFogTexture <
	ui_label = "使用雾纹理";
	ui_category = "实验性";
> = false;
uniform bool UseFogTextureDepth <
	ui_label = "使纹理随深度缩小";
	ui_category = "实验性";
> = false;

uniform float FogTextureSize <
	ui_type = "drag";
	ui_type = "雾纹理大小";
	ui_category = "实验性";
	ui_min = 0.0; ui_max = 5.0;
> = 1;



#ifndef M_PI
	#define M_PI 3.1415927
#endif

//Blending modes functions

// Screen blending mode
float3 Screen(float3 LayerA, float3 LayerB)
{ return 1.0 - (1.0 - LayerA) * (1.0 - LayerB); }

// Multiply blending mode
float3 Multiply(float3 LayerA, float3 LayerB)
{ return LayerA * LayerB; }

// Darken blending mode
float3 Darken(float3 LayerA, float3 LayerB)
{ return min(LayerA,LayerB); }

// Lighten blending mode
float3 Lighten(float3 LayerA, float3 LayerB)
{ return max(LayerA,LayerB); }

// Color Dodge blending mode (by prod80)
float3 ColorDodge(float3 LayerA, float3 LayerB)
{ return LayerB>=1.0f ? LayerB:saturate(LayerA/(1.0f-LayerB));}

// Color Burn blending mode (by prod80)
float3 ColorBurn(float3 LayerA, float3 LayerB)
{ return LayerB<=0.0f ? LayerB:saturate(1.0f-((1.0f-LayerA)/LayerB)); }

// Hard light blending mode
float3 HardLight(float3 LayerA, float3 LayerB)
{ return (LayerB.r <= 0.5 && LayerB.g <=0.5 && LayerB.b <= 0.5) ? clamp(Multiply(LayerA,2*LayerB),0,1) : clamp(Multiply(LayerA,2*LayerB-1),0,1);}

float3 Aux(float3 x)
{ return (x.r<=0.25 && x.g<=0.25 && x.b<=0.25) ? ((16.0*x-12.0)*x+4)*x : sqrt(x);}

// Soft light blending mode
float3 SoftLight(float3 LayerA, float3 LayerB)
{ return (LayerB.r <= 0.5 && LayerB.g <=0.5 && LayerB.b <= 0.5) ? clamp(LayerA-(1.0-2*LayerB)*LayerA*(1-LayerA),0,1) : clamp(LayerA+(2*LayerB-1.0)*(Aux(LayerA)-LayerA),0,1);}


// Difference blending mode
float3 Difference(float3 LayerA, float3 LayerB)
{ return LayerA-LayerB; }

// Exclusion blending mode
float3 Exclusion(float3 LayerA, float3 LayerB)
{ return LayerA+LayerB-2*LayerA*LayerB; }

// Overlay blending mode (by prod80)
float3 Overlay(float3 c, float3 b)
{ return c<0.5f ? 2.0f*c*b:(1.0f-2.0f*(1.0f-c)*(1.0f-b));}


float Lum(float3 c){
	return (0.3*c.r+0.59*c.g+0.11*c.b);}

float min3 (float a, float b, float c){
	return min(a,(min(b,c)));
}

float max3 (float a, float b, float c){
	return max(a,(max(b,c)));
}

float Sat(float3 c){
	return max3(c.r,c.g,c.b)-min3(c.r,c.g,c.b);}

float3 ClipColor(float3 c){
	float l=Lum(c);
	float n=min3(c.r,c.g,c.b);
	float x=max3(c.r,c.g,c.b);
	float cr=c.r;
	float cg=c.g;
	float cb=c.b;
	if (n<0){
		cr=l+(((cr-l)*l)/(l-n));
		cg=l+(((cg-l)*l)/(l-n));
		cb=l+(((cb-l)*l)/(l-n));
	}
	if (x>1){
		cr=l+(((cr-l)*(1-l))/(x-l));
		cg=l+(((cg-l)*(1-l))/(x-l));
		cb=l+(((cb-l)*(1-l))/(x-l));
	}
	return float3(cr,cg,cb);
}

float3 SetLum(float3 c, float l){
	float d= l-Lum(c);
	return float3(c.r+d,c.g+d,c.b+d);
}

float3 SetSat(float3 c, float s){
	float cr=c.r;
	float cg=c.g;
	float cb=c.b;
	if (cr==max3(cr,cg,cb) && cb==min3(cr,cg,cb)){//caso r->max g->mid b->min
		if (cr>cb){
			cg=(((cg-cb)*s)/(cr-cb));
			cr=s;
		}
		else{
			cg=0;
			cr=0;
		}
		cb=0;
	}
	else{
		if (cr==max3(cr,cg,cb) && cg==min3(cr,cg,cb)){//caso r->max b->mid g->min
			if (cr>cg){
				cb=(((cb-cg)*s)/(cr-cg));
				cr=s;
			}
			else{
				cb=0;
				cr=0;
			}
			cg=0;
		}
		else{
			if (cg==max3(cr,cg,cb) && cb==min3(cr,cg,cb)){//caso g->max r->mid b->min
				if (cg>cb){
					cr=(((cr-cb)*s)/(cg-cb));
					cg=s;
				}
				else{
					cr=0;
					cg=0;
				}
				cb=0;
			}
			else{
				if (cg==max3(cr,cg,cb) && cr==min3(cr,cg,cb)){//caso g->max b->mid r->min
					if (cg>cr){
						cb=(((cb-cr)*s)/(cg-cr));
						cg=s;
					}
					else{
						cb=0;
						cg=0;
					}
					cr=0;
				}
				else{
					if (cb==max3(cr,cg,cb) && cg==min3(cr,cg,cb)){//caso b->max r->mid g->min
						if (cb>cg){
							cr=(((cr-cg)*s)/(cb-cg));
							cb=s;
						}
						else{
							cr=0;
							cb=0;
						}
						cg=0;
					}
					else{
						if (cb==max3(cr,cg,cb) && cr==min3(cr,cg,cb)){//caso b->max g->mid r->min
							if (cb>cr){
								cg=(((cg-cr)*s)/(cb-cr));
								cb=s;
							}
							else{
								cg=0;
								cb=0;
							}
							cr=0;
						}
					}
				}
			}
		}
	}
	return float3(cr,cg,cb);
}

float3 Hue(float3 b, float3 s){
	return SetLum(SetSat(s,Sat(b)),Lum(b));
}

float3 Saturation(float3 b, float3 s){
	return SetLum(SetSat(b,Sat(s)),Lum(b));
}

float3 ColorM(float3 b, float3 s){
	return SetLum(s,Lum(b));
}

float3 Luminosity(float3 b, float3 s){
	return SetLum(b,Lum(s));
}

float3 rgb2hsv(float3 c) {
    const float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);

	float4 p;
	if (c.g < c.b)
		p = float4(c.bg, K.wz);
	else
		p = float4(c.gb, K.xy);

	float4 q;
	if (c.r < p.x)
		q = float4(p.xyw, c.r);
	else
		q = float4(c.r, p.yzx);

    const float d = q.x - min(q.w, q.y);
    const float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsv2rgb(float3 c) {
    const float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    const float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}


//Blend functions priveded by prod80

// Linearburn
float3 Linearburn(float3 c, float3 b) 	{ return max(c+b-1.0f, 0.0f);}
// Lineardodge
float3 Lineardodge(float3 c, float3 b) 	{ return min(c+b, 1.0f);}
// Vividlight
float3 Vividlight(float3 c, float3 b) 	{ return b<0.5f ? ColorBurn(c, (2.0f*b)):ColorDodge(c, (2.0f*(b-0.5f)));}
// Linearlight
float3 Linearlight(float3 c, float3 b) 	{ return b<0.5f ? Linearburn(c, (2.0f*b)):Lineardodge(c, (2.0f*(b-0.5f)));}
// Pinlight
float3 Pinlight(float3 c, float3 b) 	{ return b<0.5f ? Darken(c, (2.0f*b)):Lighten(c, (2.0f*(b-0.5f)));}
// Hard Mix
float3 Hardmix(float3 c, float3 b)      { return Vividlight(c,b)<0.5f ? float3(0.0,0.0,0.0):float3(1.0,1.0,1.0);}
// Reflect
float3 Reflect(float3 c, float3 b)      { return b>=0.999999f ? b:saturate(c*c/(1.0f-b));}
// Glow
float3 Glow(float3 c, float3 b)         { return Reflect(b, c);}


//Aux function for strip gradient
float DistToLine(float2 pt1, float2 pt2, float2 testPt)
{
  float2 lineDir = pt2 - pt1;
  float2 perpDir = float2(lineDir.y, -lineDir.x);
  float2 dirToPt1 = pt1 - testPt;
  return abs(dot(normalize(perpDir), dirToPt1));
}

//rotate vector around point
float2 rotate(float2 v,float2 o, float a){
	float2 v2= v-o;
	v2=float2((cos(a) * v2.x-sin(a)*v2.y),sin(a)*v2.x +cos(a)*v2.y);
	v2=v2+o;
	return v2;
}


//Otis algorithm
float CalculateDepthDiffCoC(float2 texcoord : TEXCOORD)
{
	const float scenedepth = ReShade::GetLinearizedDepth(texcoord);
	const float scenefocus =  FocusDepth;
	const float desaturateFullRange = FocusRangeDepth*FocusEdgeDepth;//used + before
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

float hue_lerp(float h1, float h2, float v){
	float lowerHue = min(h1,h2);
	float higherHue = max(h1,h2);

	float maxCCW = higherHue - lowerHue;
	float maxCW = (lowerHue+1) - higherHue;

	//Clockwise
	if (maxCW > maxCCW){
		return lerp(lowerHue, higherHue, v);
	}
	else{
		return lerp(lowerHue+1,higherHue,v)%1;
	}
}

float3 hsv_lerp(float3 c1, float3 c2, float p){
	float h = hue_lerp(c1.x, c2.x, p);
	float s = lerp(c1.y, c2.y, p);
	float v = lerp(c1.z, c2.z, p);
	
	return float3(h,s,v);
}

//Function used to blend the gradients and the screen
float3 Blender(float3 CA, float3 CB, float2 texcoord, float gradient, float fogFactor){

	float3 gradientColour;

	if (UseHSVGradient) {
		CA = rgb2hsv(CA);
		CB = rgb2hsv(CB);
		gradientColour = hsv_lerp(CA.xyz, CB.xyz, Flip ? 1 - gradient : gradient);
		gradientColour = hsv2rgb(gradientColour);
	}
	else {
		gradientColour = lerp(CA.xyz, CB.xyz, Flip ? 1 - gradient : gradient);
	}

	float3 fragment = tex2D(ReShade::BackBuffer, texcoord).rgb;
	//float3 prefragment=lerp(tex2D(ReShade::BackBuffer, texcoord).rgb, lerp(tex2D(Otis_BloomSampler, texcoord).rgb, lerp(CA.rgb, CB.rgb, Flip ? 1 - gradient : gradient), fogFactor), fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));
	float3 prefragment=lerp(tex2D(ReShade::BackBuffer, texcoord).rgb, gradientColour, fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));

	switch (BlendM){
		case 0:{fragment=prefragment;break;}
		case 1:{fragment=lerp(fragment.rgb,Multiply(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 2:{fragment=lerp(fragment.rgb,Screen(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 3:{fragment=lerp(fragment.rgb,Overlay(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 4:{fragment=lerp(fragment.rgb,Darken(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 5:{fragment=lerp(fragment.rgb,Lighten(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 6:{fragment=lerp(fragment.rgb,ColorDodge(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 7:{fragment=lerp(fragment.rgb,ColorBurn(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 8:{fragment=lerp(fragment.rgb,HardLight(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 9:{fragment=lerp(fragment.rgb,SoftLight(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 10:{fragment=lerp(fragment.rgb,Difference(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 11:{fragment=lerp(fragment.rgb,Exclusion(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 12:{fragment=lerp(fragment.rgb,Hue(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 13:{fragment=lerp(fragment.rgb,Saturation(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 14:{fragment=lerp(fragment.rgb,ColorM(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 15:{fragment=lerp(fragment.rgb,Luminosity(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 16:{fragment=lerp(fragment.rgb,Linearburn(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 17:{fragment=lerp(fragment.rgb,Lineardodge(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 18:{fragment=lerp(fragment.rgb,Vividlight(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 19:{fragment=lerp(fragment.rgb,Linearlight(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 20:{fragment=lerp(fragment.rgb,Pinlight(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 21:{fragment=lerp(fragment.rgb,Hardmix(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 22:{fragment=lerp(fragment.rgb,Reflect(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
		case 23:{fragment=lerp(fragment.rgb,Glow(fragment.rgb,prefragment),fogFactor*lerp(ColorA.a, ColorB.a, Flip ? 1 - gradient : gradient));break;}
	}
	return fragment;
}

uniform float Timer < source = "timer"; >;

//cellular noise

// Cellular noise ("Worley noise") in 2D in GLSL.
// Copyright (c) Stefan Gustavson 2011-04-19. All rights reserved.
// This code is released under the conditions of the MIT license.
// See LICENSE file for details.
// https://github.com/stegu/webgl-noise

// Modulo 289 without a division (only multiplications)
float3 mod289(float3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

float2 mod289(float2 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

// Modulo 7 without a division
float3 mod7(float3 x) {
  return x - floor(x * (1.0 / 7.0)) * 7.0;
}

// Permutation polynomial: (34x^2 + x) mod 289
float3 permute(float3 x) {
  return mod289((34.0 * x + 1.0) * x);
}


// Cellular noise, returning F1 and F2 in a float2.
// Standard 3x3 search window for good F1 and F2 values
/*
float2 cellular(float2 P) {
#define K 0.142857142857 // 1/7
#define Ko 0.428571428571 // 3/7
#define jitter 1.0 // Less gives more regular pattern
	float2 Pi = mod289(floor(P));
 	float2 Pf = frac(P);
	float3 oi = float3(-1.0, 0.0, 1.0);
	float3 of = float3(-0.5, 0.5, 1.5);
	float3 px = permute(Pi.x + oi);
	float3 p = permute(px.x + Pi.y + oi); // p11, p12, p13
	float3 ox = frac(p*K) - Ko;
	float3 oy = mod7(floor(p*K))*K - Ko;
	float3 dx = Pf.x + 0.5 + jitter*ox;
	float3 dy = Pf.y - of + jitter*oy;
	float3 d1 = dx * dx + dy * dy; // d11, d12 and d13, squared
	p = permute(px.y + Pi.y + oi); // p21, p22, p23
	ox = frac(p*K) - Ko;
	oy = mod7(floor(p*K))*K - Ko;
	dx = Pf.x - 0.5 + jitter*ox;
	dy = Pf.y - of + jitter*oy;
	float3 d2 = dx * dx + dy * dy; // d21, d22 and d23, squared
	p = permute(px.z + Pi.y + oi); // p31, p32, p33
	ox = frac(p*K) - Ko;
	oy = mod7(floor(p*K))*K - Ko;
	dx = Pf.x - 1.5 + jitter*ox;
	dy = Pf.y - of + jitter*oy;
	float3 d3 = dx * dx + dy * dy; // d31, d32 and d33, squared
	// Sort out the two smallest distances (F1, F2)
	float3 d1a = min(d1, d2);
	d2 = max(d1, d2); // Swap to keep candidates for F2
	d2 = min(d2, d3); // neither F1 nor F2 are now in d3
	d1 = min(d1a, d2); // F1 is now in d1
	d2 = max(d1a, d2); // Swap to keep candidates for F2
	d1.xy = (d1.x < d1.y) ? d1.xy : d1.yx; // Swap if smaller
	d1.xz = (d1.x < d1.z) ? d1.xz : d1.zx; // F1 is in d1.x
	d1.yz = min(d1.yz, d2.yz); // F2 is now not in d2.yz
	d1.y = min(d1.y, d1.z); // nor in  d1.z
	d1.y = min(d1.y, d2.x); // F2 is in d1.y, we're done.
	return sqrt(d1.xy);
}
*/

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


//Gaussian Noise
texture texFogNoise				< source = "fognoise.jpg"; > { Width = 512; Height = 512; Format = RGBA8; };
sampler SamplerFogNoise				{ Texture = texFogNoise; MipFilter = POINT; MinFilter = POINT; MagFilter = POINT; AddressU = WRAP; AddressV = WRAP; AddressW = WRAP;};


void PS_Otis_Original_BlendFogWithNormalBuffer(float4 vpos: SV_Position, float2 texcoord: TEXCOORD, out float4 fragment: SV_Target0)
{
    // Grab screen texture
	fragment.rgba = tex2D(ReShade::BackBuffer, texcoord).rgb;
	float3 originalColor= fragment.rgb;
	

	const float depth = ReShade::GetLinearizedDepth(texcoord).r;
	float fogFactor;
	switch(FogType){
		case 0:{
			float2 rotationfactor=float2(0.5,0.5)-(texcoord - FogRotationCenter)*FogRotationAngle;
			fogFactor= clamp(((rotationfactor.x + rotationfactor.y)*depth*(1-FogRotationDepth) - FogStart) * FogCurve, 0.0, saturate(MaxFogFactor*FogRotationDepthVisibility*depth));
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

	if (fogFactor!=0 && UseFogTexture){
		float2 uv = float2(BUFFER_WIDTH/BUFFER_HEIGHT, 1);// / float2( 512.0f, 512.0f ); // create multiplier on texcoord so that we can use 1px size reads on gaussian noise texture (since much smaller than screen)
		//uv = float2(BUFFER_WIDTH, BUFFER_HEIGHT);// / float2( 512.0f, 512.0f );
		uv.xy = uv.xy * texcoord.xy*FogTextureSize;

		if (UseFogTextureDepth) uv = uv*(1-depth);
		
		float noise = tex2D(SamplerFogNoise, uv).x; // read, uv is scaled, sampler is set to tile noise texture (WRAP)
			
		fogFactor= saturate(fogFactor-(1-fogFactor)*noise);
	}

	if (FlipFog) fogFactor = 1-fogFactor;

	//Takes the color sampled or the one from the color picker

	float3 ColorAreal= UseColorPickerA ? tex2D(ReShade::BackBuffer, axisColorASelectAxis).rgb : ColorA.rgb;
	float3 ColorBreal= UseColorPickerB ? tex2D(ReShade::BackBuffer, axisColorBSelectAxis).rgb : ColorB.rgb;
	
	switch (GradientType){
		case 0: {
			float2 origin = float2(0.5, 0.5);
			float2 uvtest= float2(texcoord.x-origin.x,texcoord.y-origin.y);
			float angle=radians(Axis);
    		uvtest = float2(cos(angle) * uvtest.x-sin(angle)*uvtest.y, sin(angle)*uvtest.y +cos(angle)*uvtest.x)+Offset;
			float gradient= (Scale<0) ? saturate(uvtest.x*(-pow(2,abs(Scale)))+Offset) : saturate(uvtest.x*pow(2,abs(Scale))+Offset);
			fragment= Blender(ColorAreal, ColorBreal, texcoord, gradient, fogFactor);
			break;
		}
		case 1: {
			float distfromcenter=distance(float2(Originc.x*Modifierc.x, Originc.y*Modifierc.y), float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT)*Modifierc.x,texcoord.y*Modifierc.y));
			float angle=radians(AnguloR);
			float2 uvtemp=float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT),texcoord.y);
			float dist = distance(Originc*Modifierc,rotate(uvtemp,Originc,angle)*Modifierc);
			float gradient= (Scale<0) ? saturate((dist-Size)*(-exp(abs(Scale)))) : saturate((dist-Size)*(exp(abs(Scale))));
			fragment= Blender(ColorAreal, ColorBreal, texcoord, gradient, fogFactor);
			break;
		}
		case 2: {
			float2 ubs = texcoord;
			ubs.y = 1.0 - ubs.y;
			float gradient = saturate((DistToLine(PositionS, float2(PositionS.x-sin(radians(AnguloS)),PositionS.y-cos(radians(AnguloS))), ubs) * 2.0)*(pow(2,Scale-SizeS+2))-SizeS);//the pow is for smoother sliders
			fragment= Blender(ColorAreal, ColorBreal, texcoord, gradient, fogFactor);
			break;
		}
		case 3:{
			float angle=radians(Angulod);
			float2 mod=rotate(Modifierd,float2(1,1),radians(45));

			//float2 uv=rotate(float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT),texcoord.y),Origind,radians(Angulod));
			//uv=rotate(uv,Origind,radians(45));
			//float gradient = 1 - pow(max(abs((uv.x*mod.x - Origind.x*mod.x)/Sized), abs((uv.y*mod.y - Origind.y*mod.y)/Sized)),exp(Scale));


			//funca pero modificadores no giran
			float2 uv=rotate(float2(((texcoord.x*BUFFER_WIDTH-(BUFFER_WIDTH-BUFFER_HEIGHT)/2)/BUFFER_HEIGHT)*Modifierd.x,texcoord.y*Modifierd.y),Origind*Modifierd,radians(45));
			uv=rotate(uv,Origind*Modifierd,radians(Angulod));
			float gradient = 1 - pow(max(abs((uv.x - Origind.x*Modifierd.x)/Sized), abs((uv.y - Origind.y*Modifierd.y)/Sized)),exp(Scale+3));
			fragment= Blender(ColorAreal, ColorBreal, texcoord, saturate(gradient), fogFactor);
			break;
		}
	}

	if(UseColorPickerA && drawColorASelectON){
		fragment=lerp(fragment,float4(1.0, 0.0, 0.0, 1.0),(abs(texcoord.x - axisColorASelectAxis.x)<0.0005 || abs(texcoord.y - axisColorASelectAxis.y)<0.001 ) ? 1 : 0);
	}

	if(UseColorPickerB && drawColorBSelectON){
		fragment=lerp(fragment,float4(0.0, 1.0, 0.0, 1.0),(abs(texcoord.x - axisColorBSelectAxis.x)<0.0005 || abs(texcoord.y - axisColorBSelectAxis.y)<0.001 ) ? 1 : 0);
	}
}

  //////////////
 /// OUTPUT ///
//////////////

technique CanvasFog
{
	pass Otis_AFG_PassBlend
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_Original_BlendFogWithNormalBuffer;
	}
}
