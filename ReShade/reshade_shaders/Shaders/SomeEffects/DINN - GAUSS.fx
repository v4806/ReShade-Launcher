/*------------------.
| :: Description :: |
'-------------------/

	Ann's dumb shader
	includes the blue noise pattern from here
	https://momentsingraphics.de/BlueNoise.html
	i'm cool with you using it for whatever, if it's like a commercial thing, dm me, i'd like to know and credit would be nice
	io_person
	
*/

/*---------------.
| :: Includes :: |
'---------------*/

#include "ReShadeUI.fxh"
#include "ReShade.fxh"
//#include "shared/cShade.fxh"
//#include "shared/cBlur.fxh"
//credit for this effect goes to the people who made cshade, papadanku
/*------------------.
| :: UI Settings :: |
'------------------*/

uniform int PixelationSizeX < __UNIFORM_SLIDER_INT1
	ui_min = 1;
	ui_max = 50;
	ui_label = "X轴大小";
	ui_tooltip = "新像素的水平大小";
	ui_category = "像素选项";
> = 3;

uniform int PixelationSizeY < __UNIFORM_SLIDER_INT1
	ui_min = 1;
	ui_max = 50;
	ui_label = "Y轴大小";
	ui_tooltip = "新像素的垂直大小";
	ui_category = "像素选项";
> = 3;

uniform float SIG < __UNIFORM_SLIDER_FLOAT1
	ui_label = "模糊程度";
	ui_category = "模糊";
	ui_label= "适当模糊可减少闪烁";
	ui_min = 0.00; ui_max = 20.0;
> = 2.0;

uniform bool greyscale  <
	ui_label = "灰度";
	ui_category = "灰度";
	ui_tooltip = "将图像转为灰度，大多数其他选项需要此功能";
> = 1;

uniform bool colmod  < 
	ui_label = "图像单色";
	ui_category = "灰度";
	ui_tooltip = "用单一颜色替换图像，可查看边缘检测效果而不受背景色影响";
> = 0;

uniform float monocol < __UNIFORM_SLIDER_FLOAT1
	ui_label = "单色值";
	ui_category = "灰度";
	ui_tooltip = "选择用于替换图像的单色颜色";
	ui_min = 0.0; ui_max = 1.0;
> = 0.0;

uniform bool dither  <
	ui_label = "抖动";
	ui_category = "灰度";
	ui_tooltip = "对分层灰度进行抖动";
> = 1;

uniform float3 Greyscale_vector < __UNIFORM_COLOR_FLOAT3
	ui_label = "自定义转换值";
	ui_category = "灰度";
	ui_tooltip = "沿此向量转换灰度";
> = float3(1., 1., 1.);

uniform float3 dinnwhite < __UNIFORM_COLOR_FLOAT3
	ui_label = "白色替换色";
	ui_category = "灰度";
	ui_tooltip = "白色将被替换为此颜色";
> = float3(1., 1., 1.);

uniform float3 dinnblack < __UNIFORM_COLOR_FLOAT3
	ui_label = "黑色替换色";
	ui_category = "灰度";
	ui_tooltip = "黑色将被替换为此颜色";
> = float3(0., 0., 0.);

uniform float Colour_Bleed < __UNIFORM_SLIDER_FLOAT1
	ui_label = "灰度饱和度";
	ui_category = "灰度";
	ui_tooltip = "让一些颜色透过灰度显示";
	ui_min = 0.0; ui_max = 1.0;
> = 0.0;

uniform int GreyLevel < __UNIFORM_SLIDER_INT1
	ui_min = 1;
	ui_max = 50;
	ui_label = "灰度色阶";
	ui_tooltip = "设置灰度色阶数，1表示无色阶";
	ui_category = "灰度";
> = 2;

uniform bool ordered  <
	ui_label = "有序抖动";
	ui_category = "灰度";
	ui_tooltip = "使用有序抖动";
> = 0;

uniform int orderedmask  < __UNIFORM_SLIDER_INT1
	ui_min = 2;
	ui_max = 4;
	ui_label = "有序抖动遮罩选择";
	ui_category = "灰度";
	ui_tooltip = "使用有序抖动";
> = 2;

uniform float DithDeg < __UNIFORM_SLIDER_FLOAT1
	ui_label = "抖动范围";
	ui_category = "灰度";
	ui_tooltip = "值越高，通过抖动表现的色调越多";
	ui_min = 0.01; ui_max = 5.0;
> = 2.0;

uniform bool EdgeDetect < 
	ui_label = "边缘";
	ui_category = "边缘";
	ui_tooltip = "引入高斯差分边缘检测，以下选项用于调整细节";
> = TRUE;

uniform float SIG1 < __UNIFORM_SLIDER_FLOAT1
	ui_label = "小模糊";
	ui_category = "边缘";
	ui_tooltip = "去除边缘的小噪点";
	ui_min = 0.00; ui_max = 5.0;
> = 1.5;

uniform float SIG2 < __UNIFORM_SLIDER_FLOAT1
	ui_label = "大模糊";
	ui_category = "边缘";
	ui_tooltip = "添加更粗的边缘";
	ui_min = 0.00; ui_max = 5.0;
> = 4.5;

uniform float CONT < __UNIFORM_SLIDER_FLOAT1
	ui_label = "边缘强度";
	ui_category = "边缘";
	ui_tooltip = "增大大模糊以提高灵敏度";
	ui_min = 0.80; ui_max = 2.00;
> = 1.0;

uniform float threshold < __UNIFORM_SLIDER_FLOAT1
	ui_label = "边缘阈值";
	ui_category = "边缘";
	ui_tooltip = "边缘所需的最小级别";
	ui_min = 0.00; ui_max = 2.0;
> = 0.03;

uniform float3 dotedge < __UNIFORM_COLOR_FLOAT3
	ui_label = "边缘点积";
	ui_category = "边缘";
	ui_tooltip = "沿此颜色向量检测边缘";
> = float3(1., 1., 1.);

uniform float inter < __UNIFORM_SLIDER_FLOAT1
	ui_label = "截距暗度";
	ui_category = "边缘";
	ui_tooltip = "暗度调整，值越低所有颜色越敏感";
	ui_min = 0.; ui_max = 7.0;
> = 0.8;

uniform float slope < __UNIFORM_SLIDER_FLOAT1
	ui_label = "斜率暗度";
	ui_category = "边缘";
	ui_tooltip = "暗度调整，值越高亮部越不敏感";
	ui_min = 0.0; ui_max = 5.;
> = 0.5;

uniform float range < __UNIFORM_SLIDER_FLOAT1
	ui_label = "插值范围";
	ui_category = "边缘";
	ui_tooltip = "从完全效果到无效果所需的边缘量";
	ui_min = 0.0; ui_max = 3.;
> = 0.1;

uniform bool diag  <
	ui_label = "诊断";
	ui_category = "帮助";
	ui_tooltip = "生成黑白渐变斜坡";
> = 0;

/*-------------------------.
| :: Sampler and timers :: |
'-------------------------*/

#define AnnSampler ReShade::BackBuffer

texture BlueNoise < source ="HDR_LA_3.png" ; > { Width = 256; Height = 256; };
sampler BlueNoiseSamp { Texture = BlueNoise; AddressU = REPEAT;	AddressV = REPEAT;	AddressW = REPEAT;};

texture BLURSTORE {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler2D BLURSTOREs { Texture = BLURSTORE; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

texture smallblur {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler2D SmallBlurM { Texture = smallblur; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

texture bigblur {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler2D BigBlurM { Texture = bigblur; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

#define DITHER_MATRIX1 float3x3(0.75,-0.75,0.25,-0.5,-1,0,0.5,-0.25,1)
#define DITHER_MATRIX2 float4x4(0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5)
/*-------------.
| :: Effect :: |
'-------------*/
float3 BlurPass( float2 Tex, bool Horizontal, float SIGMA, sampler SAMP){
	//this function blurs in one direction based on the bool Horizontal
	float2 Direction = Horizontal ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 PixelSize = (1.0 / float2(BUFFER_WIDTH, BUFFER_HEIGHT)) * Direction;
    float KernelSize = SIGMA * 3.0;
	if(SIGMA == 0.0)
		{
			//skips the for loop when no blurring is actually specified, saves on time
			return tex2Dlod(SAMP, float4(Tex, 0.0, 0.0)).rgb;
		}
		else
		{	
			float GausConst = rsqrt(2.0 * acos(-1.0) * (SIGMA * SIGMA));
			// Sample and weight center first to get even number sides
	        float TotalWeight = GausConst;
	        float3 OutputColor = tex2D(SAMP, Tex).rgb * TotalWeight;
	
	        for(float i = 1.0; i < KernelSize; i += 2.0)
	        {
	            //float LinearOffset = CBlur_GetGaussianOffset(i, SIGMA, LinearWeight);
	   		 float Weight1 = GausConst * exp(-(i * i) / (2.0 * SIGMA * SIGMA));         
				float Weight2 = GausConst * exp(-((i+1.0) * (i+1.0)) / (2.0 * SIGMA * SIGMA));         
				float LinearWeight = Weight1+Weight2;
	            float LinearOffset = i+Weight2/LinearWeight;
				OutputColor += tex2Dlod(SAMP, float4(Tex - LinearOffset * PixelSize, 0.0, 0.0)).rgb * LinearWeight;
	            OutputColor += tex2Dlod(SAMP, float4(Tex + LinearOffset * PixelSize, 0.0, 0.0)).rgb * LinearWeight;
	            TotalWeight += LinearWeight * 2.0;
	        }
	
	        // Normalize intensity to prevent altered output
	        return OutputColor / TotalWeight;
		}
}

//this function makes the final image out of the previously calculated gaussians
float3 finisher( float2 tex ){
	float2 PixelBlock = float2(float(PixelationSizeX), float(PixelationSizeY));
	int2 pointint = trunc((BUFFER_SCREEN_SIZE / PixelBlock) * tex);
	float2 Pointer = pointint * (PixelBlock / BUFFER_SCREEN_SIZE);
	float2 POINT = Pointer + trunc(PixelBlock/2.)*BUFFER_PIXEL_SIZE;
	float3 col = tex2D(AnnSampler, POINT).rgb;
	int2 cellp = pointint % 2;
	//defines variables
	if(greyscale){
		//converts to greyscale, quantizes, adds dither
		float gry = dot(col, Greyscale_vector);
		if(diag){
			gry = Pointer.x;
		}else if(colmod){
			gry = monocol;
		}
		if (GreyLevel > 1) {
			if (dither){	
			if(ordered){
				if(orderedmask==2){
					gry = gry+((cellp.x)+(cellp.x==cellp.y)*2.-1.5)/((GreyLevel-1)*6./DithDeg);
				}else if(orderedmask==3){
					gry = gry +1.5*DITHER_MATRIX1[pointint.x % 3][pointint.y % 3] /((GreyLevel-1)*6./DithDeg);
				}else{
					gry = gry + 1.5*(DITHER_MATRIX2[pointint.x % 4][pointint.y % 4]/7.5-1 )/((GreyLevel-1)*6./DithDeg);
				}
				}else{
				gry = gry+(tex2Dlod(BlueNoiseSamp, float4(pointint/float2(256,256),0.0,0.0) ).r*DithDeg-0.5*DithDeg)/(GreyLevel-1.);
			}
			}
			if(EdgeDetect){
			float edge = smoothstep(0,1,( abs((dot((tex2Dlod(SmallBlurM ,float4(POINT,0.0,0.0))-CONT*tex2Dlod(BigBlurM,float4(POINT,0.0,0.0))).rgb, dotedge))/(dot(tex2Dlod(SmallBlurM ,float4(POINT,0.0,0.0)).rgb, dotedge)*slope+inter))- threshold) /range);
			gry = gry-sign(gry-0.5)*edge;
			}
		gry = saturate((trunc(gry*GreyLevel))/(GreyLevel-1.));
		}
	col = saturate(lerp(lerp(dinnblack, dinnwhite,gry), col, Colour_Bleed));
	}
return col;
}


float3 PS_ANN2(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	float3 color = finisher(texcoord);
	return color.rgb;
}
float3 PS_BLURh(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	float3 color = BlurPass(texcoord, TRUE, SIG, AnnSampler);
  	return color.rgb;
}
float3 PS_BLURv(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	float3 color = BlurPass(texcoord, FALSE, SIG, AnnSampler);
	return color.rgb;
}
float3 PS_DIFFhb(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	float3 color = BlurPass(texcoord, TRUE, SIG1, AnnSampler);
	return color.rgb;
}
float3 PS_DIFFvb(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	float3 color = BlurPass(texcoord, FALSE, SIG1, BLURSTOREs);
	return color.rgb;
}
float3 PS_DIFFhs(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	float3 color = BlurPass(texcoord, TRUE, SIG2, AnnSampler);
	return color.rgb;
}
float3 PS_DIFFvs(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	float3 color = BlurPass(texcoord, FALSE, SIG2, BLURSTOREs);
	return color.rgb;
}


/*-----------------.
| :: Techniques :: |
'-----------------*/
technique DINNDIFF
{
	pass BLURh2{
		VertexShader=PostProcessVS;
		PixelShader=PS_DIFFhb;
		RenderTarget = BLURSTORE; 
	}
	pass BLURv2{
		VertexShader=PostProcessVS;
		PixelShader=PS_DIFFvb;
		RenderTarget = bigblur; 
	}
	pass BLURh2s{
		VertexShader=PostProcessVS;
		PixelShader=PS_DIFFhs;
		RenderTarget = BLURSTORE; 
	}
	pass BLURv2s{
		VertexShader=PostProcessVS;
		PixelShader=PS_DIFFvs;
		RenderTarget = smallblur; 
	}
	pass BLURh{
		VertexShader=PostProcessVS;
		PixelShader=PS_BLURh;
	}
	pass BLURv{
		VertexShader=PostProcessVS;
		PixelShader=PS_BLURv;
	}
	pass ANN2{
		VertexShader=PostProcessVS;
		PixelShader=PS_ANN2;
	}
}
