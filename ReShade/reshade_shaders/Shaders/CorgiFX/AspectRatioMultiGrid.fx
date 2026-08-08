// Based and inspired on AspectRatioComposition by Daodan317081 (https://github.com/Daodan317081/reshade-shaders)
// and AspectRatioSuite by luluco250 (https://github.com/luluco250/FXShaders/)

//Made by originalnicodr

namespace AspectRatioMultiGrid
{

#include "ReShade.fxh"

#ifndef CUSTOM_ASPECT_RATIO_MAX
	#define CUSTOM_ASPECT_RATIO_MAX 25
#endif


#ifndef ASPECT_RATIO_LIST_VALUES
#define ASPECT_RATIO_LIST_VALUES 2, 3/2., 4/3., 5/4., 21/9., 1, 4/5., 3/4., 2/3.
#endif


#ifndef ASPECT_RATIO_LIST_UI_VALUES
#define ASPECT_RATIO_LIST_UI_VALUES " 2\0 3/2\0 4/3\0 5/4\0 21/9\0 1\0 4/5\0 3/4\0 2/3\0"
#endif

static const float ASPECT_RATIOS[] = {ASPECT_RATIO_LIST_VALUES, 0.0};

/******************************************************************************
	Uniforms
******************************************************************************/

uniform bool HideOnScreenshot <
	ui_label = "截图时隐藏";
	ui_tooltip = "截图时不绘制宽高比黑边和网格。";
> = false;

uniform int ARMode <
	ui_category = "宽高比";
	ui_label = "宽高比模式";
	ui_tooltip = "选择宽高比的设置方式。";
	ui_type = "combo";
	ui_items = "关\0列表\0自定义\0";
> = 0;

uniform int ARFromList<
	ui_category = "宽高比";
	ui_label = "从列表选择宽高比";
	ui_tooltip = "要编辑列表中的值，请修改预处理器定义中的\n'ASPECT_RATIO_LIST_VALUES' 和 'ASPECT_RATIO_LIST_UI_VALUES'。\n前者应该是用逗号分隔的值（如果是除法，在末尾加点表示浮点数），\n后者应该是用'\\0'和空格分隔的值。";
	ui_type = "combo";
	ui_items = ASPECT_RATIO_LIST_UI_VALUES;
> = 0;

#ifdef CUSTOM_ASPECT_RATIO_FLOAT
uniform float fUIAspectRatio <
	ui_category = "宽高比";
	ui_label = "自定义宽高比";
	ui_tooltip = "要使用 int2 控制宽高比，\n请从预处理器中移除 'CUSTOM_ASPECT_RATIO_FLOAT'";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 25.0;
	ui_step = 0.01;
> = 1.0;
#else
uniform int2 iUIAspectRatio <
	ui_category = "宽高比";
	ui_label = "自定义宽高比";
	ui_tooltip = "要使用浮点数控制宽高比，\n请在预处理器中添加 'CUSTOM_ASPECT_RATIO_FLOAT'。\n可选: 'CUSTOM_ASPECT_RATIO_MAX=xyz'";
	ui_type = "slider";
	ui_min = 0; ui_max = CUSTOM_ASPECT_RATIO_MAX;
> = int2(16, 9);
#endif

uniform float3 ARColor <
	ui_category = "宽高比";
	ui_label = "边栏颜色";
    ui_type = "color";
> = float3(0.0, 0.0, 0.0);

uniform float AROpacity <
	ui_category = "宽高比";
	ui_label = "边栏不透明度";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
> = 1.0;

uniform float3 gridColor <
	ui_category = "网格";
	ui_label = "颜色";
    ui_type = "color";
> = float3(0.0, 0.0, 0.0);

uniform bool gridInverseColor <
	ui_category = "网格";
	ui_label = "网格反色";
	ui_tooltip = "反转网格后面像素的颜色，\n使网格与游戏画面形成完全对比。";
> = false;

uniform float gridOpacity <
	ui_category = "网格";
	ui_label = "不透明度";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
> = 1.0;

uniform float  gridLinesWidth<
	ui_category = "网格";
	ui_label = "线条宽度（像素）";
	ui_min = 1.0; ui_max = 5.0;
	ui_type = "slider";
	ui_step = 0.001;
> = 1.0;

uniform bool RuleofThirds <
	ui_category = "网格";
	ui_label = "三分法";
> = false;

uniform bool RuleofFifths <
	ui_category = "网格";
	ui_label = "五分法";
> = false;

uniform bool Triangles1 <
	ui_category = "网格";
	ui_label = "三角形 - 1";
> = false;

uniform bool Triangles2 <
	ui_category = "网格";
	ui_label = "三角形 - 2";
> = false;

uniform bool Diagonals <
	ui_category = "网格";
	ui_label = "对角线";
> = false;

uniform bool Diamond <
	ui_category = "网格";
	ui_label = "菱形";
> = false;

uniform bool Special1 <
	ui_category = "网格";
	ui_label = "交叉 - 1";
> = false;

uniform bool Special2 <
	ui_category = "网格";
	ui_label = "交叉 - 2";
> = false;

uniform bool Special3 <
	ui_category = "网格";
	ui_label = "交叉 - 3";
> = false;

uniform bool FibonacciBottomRight <
	ui_category = "网格";
	ui_label = "黄金比例 - 右下";
> = false;

uniform bool FibonacciBottomLeft <
	ui_category = "网格";
	ui_label = "黄金比例 - 左下";
> = false;

uniform bool FibonacciTopRight <
	ui_category = "网格";
	ui_label = "黄金比例 - 右上";
> = false;

uniform bool FibonacciTopLeft <
	ui_category = "网格";
	ui_label = "黄金比例 - 左上";
> = false;

uniform bool CustomGrid <
	ui_category = "自定义网格";
	ui_label = "自定义网格";
	ui_category_closed = true;
> = false;

uniform float4 CustomGridLine1 <
	ui_category = "自定义网格";
	ui_label = "线条 1";
	ui_type = "slider";
	ui_step = 0.001;
	ui_min = 0; ui_max = 1;
> = float4(0, 0, 0.667, 1);

uniform float4 CustomGridLine2 <
	ui_category = "自定义网格";
	ui_label = "线条 2";
	ui_type = "slider";
	ui_step = 0.001;
	ui_min = 0; ui_max = 1;
> = float4(1, 0, 0.333, 1);

uniform float4 CustomGridLine3 <
	ui_category = "自定义网格";
	ui_label = "线条 3";
	ui_type = "slider";
	ui_step = 0.001;
	ui_min = 0; ui_max = 1;
> = float4(1, 1, 0.333, 0);

uniform float4 CustomGridLine4 <
	ui_category = "自定义网格";
	ui_label = "线条 4";
	ui_type = "slider";
	ui_step = 0.001;
	ui_min = 0; ui_max = 1;
> = float4(0, 1, 0.666, 0);

uniform bool UseWhiteBackground <
	ui_category = "自定义网格";
	ui_label = "白色背景";
	ui_tooltip = "如果自定义网格需要超过4条线，可以开启此选项，\n对结果图像截图，将该图像用作自定义网格，\n然后通过更改上面的线条位置与其他自定义网格组合。";
> = false;

uniform bool CustomGridImage <
	ui_category = "自定义网格";
	ui_label = "自定义网格图像";
	ui_tooltip = "要更改使用的图像，请修改纹理文件夹中的'customGrid.png'文件，\n或在预处理器定义'CUSTOM_GRID_IMAGE'中更改纹理名称。\n确保使用的图像具有白色背景和黑色线条。";
> = false;

/******************************************************************************
	Functions
******************************************************************************/

#define linearstep(_a, _b, _x) saturate(((_x) - (_a)) * rcp((_b) - (_a)))

//Credits to gPlatl: https://www.shadertoy.com/view/MlcGDB
float segmentsdf(float2 P, float2 A, float2 B) 
{
    float2 g = B - A;
    float2 h = P - A;

	float2 scale = rcp(float2(ddx(P.x), ddy(P.y)));
	g *= abs(scale);
	h *= abs(scale);

	float2 df = h - g * saturate(dot(g, h) / dot(g, g));

    return dot(df, df);
}

float shade_line(float sdf, float r)
{
	return linearstep(r + 0.5, r - 0.5, sqrt(max(0, sdf)));
}

void triangles(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 0), float2(1, 1))); //diagonal
    sdf = min(sdf, segmentsdf(texcoord, float2(0, 1), float2(1/4., 1/4.))); //line1
	sdf = min(sdf, segmentsdf(texcoord, float2(1, 0), float2(3/4., 3/4.))); //line2
}

void diagonals(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 0), float2(1, 1))); //diagonal1
	sdf = min(sdf, segmentsdf(texcoord, float2(1, 0), float2(0, 1))); //diagonal2	
}

void special(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 0), float2(4/9., 1))); //d1
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 1), float2(4/9., 0))); //d2
	sdf = min(sdf, segmentsdf(texcoord, float2(1, 0), float2(5/9., 1))); //d3
	sdf = min(sdf, segmentsdf(texcoord, float2(1, 1), float2(5/9., 0))); //d4	
}


void special2(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 0), float2(0.5, 1))); //d1
	sdf = min(sdf, segmentsdf(texcoord, float2(0.5, 1), float2(1, 0))); //d2
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 1), float2(0.5, 0))); //d3
	sdf = min(sdf, segmentsdf(texcoord, float2(0.5, 0), float2(1, 1))); //d4	
}

void special3(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 0), float2(1, 0.5))); //d1
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 0.5), float2(1, 0))); //d2
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 0.5), float2(1, 1))); //d3
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 1), float2(1, 0.5))); //d4	
}


void diamond(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 0.5), float2(0.5, 1))); //d1
	sdf = min(sdf, segmentsdf(texcoord, float2(0.5, 1), float2(1, 0.5))); //d2
	sdf = min(sdf, segmentsdf(texcoord, float2(1, 0.5), float2(0.5, 0))); //d3
	sdf = min(sdf, segmentsdf(texcoord, float2(0.5, 0), float2(0, 0.5))); //d4	
}

void ruleOfThirds(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, float2(1/3., 0), float2(1/3., 1))); //d1
	sdf = min(sdf, segmentsdf(texcoord, float2(2/3., 0), float2(2/3., 1))); //d2
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 1/3.), float2(1, 1/3.))); //d3
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 2/3.), float2(1, 2/3.))); //d4	
}

void ruleOfFifths(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, float2(1/5., 0), float2(1/5., 1))); //ly1
	sdf = min(sdf, segmentsdf(texcoord, float2(2/5., 0), float2(2/5., 1))); //ly2
	sdf = min(sdf, segmentsdf(texcoord, float2(3/5., 0), float2(3/5., 1))); //ly3
	sdf = min(sdf, segmentsdf(texcoord, float2(4/5., 0), float2(4/5., 1))); //ly4
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 1/5.), float2(1, 1/5.))); //lx1
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 2/5.), float2(1, 2/5.))); //lx2
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 3/5.), float2(1, 3/5.))); //lx3
	sdf = min(sdf, segmentsdf(texcoord, float2(0, 4/5.), float2(1, 4/5.))); //lx4
}

void customGrid(inout float sdf, float2 texcoord){
	sdf = min(sdf, segmentsdf(texcoord, CustomGridLine1.zw, CustomGridLine1.xy));//l1
	sdf = min(sdf, segmentsdf(texcoord, CustomGridLine2.zw, CustomGridLine2.xy));//l2
	sdf = min(sdf, segmentsdf(texcoord, CustomGridLine3.zw, CustomGridLine3.xy));//l3
	sdf = min(sdf, segmentsdf(texcoord, CustomGridLine4.zw, CustomGridLine4.xy));//l4
}

#ifndef CUSTOM_GRID_IMAGE
#define CUSTOM_GRID_IMAGE "customGrid.png"//Put your image file name here or remplace the original file
#endif

texture	customGridTex <source= CUSTOM_GRID_IMAGE; > { Width = 1920; Height = 1080; MipLevels = 1; Format = RGBA8; };

uniform bool SCREENSHOT < source = "screenshot"; >;

sampler	customGridSampler
{
	Texture = customGridTex;
	AddressU = BORDER;
	AddressV = BORDER;
};

void customGridImage(float sdf, float2 texcoord){
	float grid = 1 - tex2D(customGridSampler, texcoord).r;
	sdf = lerp(sdf, 0, grid);
}


//Kitbash of this https://www.shadertoy.com/view/wtlGD4
//with some scaling and code to remove the buggy line
void fibonacci(inout float sdf, float2 texcoord){
	texcoord.x *= 1.618;
	texcoord *= 0.896;

	texcoord += 0.618 * float2(-0.65, -0.402);
	float l = length(texcoord);
	float a = atan2(texcoord.y, -texcoord.x);
	float tv = log(l) / (4.0 * log(1.618));
	float v = tv - a / 6.283 - 1.0;

	float2 dfdx = ddx(tv);
	float2 dfdy = ddy(tv);

	float t = abs(frac(v) - 0.5) * rsqrt(dot(dfdx, dfdx) + dot(dfdy, dfdy));
	sdf = min(sdf, t);
}

float DrawAR(float aspectRatio, float2 texcoord){
	float2 vpos = texcoord*BUFFER_SCREEN_SIZE;
	float borderSize;
	float retVal = 0;

	if(aspectRatio < BUFFER_ASPECT_RATIO)
	{
		borderSize = (BUFFER_WIDTH - BUFFER_HEIGHT * aspectRatio) / 2.0;

		if(vpos.x < borderSize || vpos.x > (BUFFER_WIDTH - borderSize))
			retVal = 1;
	}
	else
	{
		borderSize = (BUFFER_HEIGHT - BUFFER_WIDTH / aspectRatio) / 2.0;

		if(vpos.y < borderSize || vpos.y > (BUFFER_HEIGHT - borderSize))
			retVal = 1;
	}
	
	return retVal;
}

float2 texcoordRemapAR(float aspectRatio, float2 texcoord){
	float2 vpos = texcoord*BUFFER_SCREEN_SIZE;
	float borderSize;

	if(aspectRatio < BUFFER_ASPECT_RATIO)
	{
		borderSize = (BUFFER_WIDTH - BUFFER_HEIGHT * aspectRatio) / 2.0;

		float w = BUFFER_HEIGHT * aspectRatio;
		float x = texcoord.x*BUFFER_WIDTH/w - borderSize/w;
		return float2(x,texcoord.y);
	}
	else
	{
		borderSize = (BUFFER_HEIGHT - BUFFER_WIDTH / aspectRatio) / 2.0;

		float h = BUFFER_WIDTH / aspectRatio;
		float y = texcoord.y*BUFFER_HEIGHT/h - borderSize/h;
		return float2(texcoord.x, y);
	}
}

float getAR(){
	float ar;
	switch(ARMode){
		case 0:{
			ar = BUFFER_ASPECT_RATIO;
		}break;
		case 1:{
			ar = ASPECT_RATIOS[ARFromList];
		}break;
		case 2:{
			ar = (float)iUIAspectRatio.x/(float)iUIAspectRatio.y;
		}break;
	}
	return ar;
}

#if (__RENDERER__ >= 0xb000)
#define BRANCH [branch]
#else
#define BRANCH 
#endif

float3 AspectRatioMultiGrid_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 backbuffer = tex2D(ReShade::BackBuffer, texcoord).rgb;
	if (SCREENSHOT && HideOnScreenshot) {
		return backbuffer;
	}

    float3 color = UseWhiteBackground ? float3(1,1,1) : backbuffer;
	float3 realGridColor = gridInverseColor ? smoothstep(0, 1, 1 - color) : gridColor;
	float ar = getAR();
	float2 remappedTexcoord = texcoordRemapAR(ar, texcoord);

	float lines = 0;
	float line_sdf = 1000000;
	BRANCH if(RuleofThirds) 			ruleOfThirds(line_sdf, remappedTexcoord);
	BRANCH if(RuleofFifths) 			ruleOfFifths(line_sdf, remappedTexcoord);
	BRANCH if(Triangles1) 				triangles(line_sdf, remappedTexcoord);
	BRANCH if(Triangles2) 				triangles(line_sdf, float2(1-remappedTexcoord.x,remappedTexcoord.y));
	BRANCH if(Diagonals) 				diagonals(line_sdf, remappedTexcoord);
	BRANCH if(Diamond) 				diamond(line_sdf, remappedTexcoord);
	BRANCH if(Special1) 				special(line_sdf, remappedTexcoord);
	BRANCH if(Special2) 				special2(line_sdf, remappedTexcoord);
	BRANCH if(Special3) 				special3(line_sdf, remappedTexcoord);
	BRANCH if(FibonacciTopLeft) 	fibonacci(line_sdf, remappedTexcoord);
	BRANCH if(FibonacciTopRight) 	fibonacci(line_sdf, float2(1-remappedTexcoord.x,remappedTexcoord.y));
	BRANCH if(FibonacciBottomLeft) 		fibonacci(line_sdf, float2(remappedTexcoord.x,1-remappedTexcoord.y));
	BRANCH if(FibonacciBottomRight) 		fibonacci(line_sdf, float2(1-remappedTexcoord.x,1-remappedTexcoord.y));
	BRANCH if(CustomGrid) 				customGrid(line_sdf, remappedTexcoord);
	BRANCH if(CustomGridImage) 		customGridImage(line_sdf, remappedTexcoord);

	lines = shade_line(line_sdf, gridLinesWidth);

	color = lerp(color, realGridColor, gridOpacity * saturate(lines));

	if (ARMode != 0){
		float aspectRatioBars = DrawAR(ar, texcoord);
		color = lerp(color, ARColor, min(AROpacity, aspectRatioBars));
	}

	return color;
}

technique AspectRatioMultiGrid
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = AspectRatioMultiGrid_PS;
	}
}

}
