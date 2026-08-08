/*------------------.
| :: Description :: |
'-------------------/
	it moves pixels one side or another in an alternating pattern
	not spectecular, but it does the job as a corruption effect, or turn on the horizontal bar effect for some of the visual flair interlaced video can provide
	also X and Y are seperate effects so you can throw some other shaders inbetween, may be funny with edge detection or blur perhaps
*/


/*---------------.
| :: Includes :: |
'---------------*/


#include "ReShadeUI.fxh"
#include "ReShade.fxh"


/*------------------.
| :: UI Settings :: |
'------------------*/
uniform int SectionSizeX < __UNIFORM_SLIDER_INT1
	ui_min = 1;
	ui_max = 50;
	ui_label = "水平分段位移";
	ui_tooltip = "以像素为单位，如果分辨率极高可在代码中修改最大值";
> = 2;

uniform int SectionSizeY < __UNIFORM_SLIDER_INT1
	ui_min = 1;
	ui_max = 50;
	ui_label = "垂直分段位移";
	ui_tooltip = "以像素为单位，如果分辨率极高可在代码中修改最大值";
> = 2;

uniform int sizX < __UNIFORM_SLIDER_INT1
	ui_min = 0;
	ui_max = 50;
	ui_label = "垂直位移量";
	ui_tooltip = "以像素为单位，如果分辨率极高可在代码中修改最大值";
> = 0;

uniform int sizY < __UNIFORM_SLIDER_INT1
	ui_min = 0;
	ui_max = 50;
	ui_label = "水平位移量";
	ui_tooltip = "以像素为单位，如果分辨率极高可在代码中修改最大值";
> = 20;

uniform bool flipx < 
	ui_label= "翻转水平位移";
	ui_tooltip = "改变摆动方向，适用于对齐";
> = FALSE;

uniform bool flipy < 
	ui_label= "翻转垂直位移";
	ui_tooltip = "改变摆动方向，适用于对齐";
> = FALSE;
/*-------------------------.
| :: Sampler and timers :: |
'-------------------------*/

#define AnnSampler ReShade::BackBuffer

/*-------------.
| :: Effect :: |
'-------------*/
float3 PS_PixelShift(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	//get coordinates in a easy to use per pixel term
	int2 PixelBlock = int2(SectionSizeX, SectionSizeY);
	int2 pointint = trunc((texcoord/ (PixelBlock*BUFFER_PIXEL_SIZE )));
	//this is a terribly squeezed together function, lets call this optimisation
	//it samples colour from shifted coordinates 
	//return(tex2D(AnnSampler,texcoord+ BUFFER_PIXEL_SIZE*((flipx+pointint.x)%2)*float2(0,1)*sizX+ BUFFER_PIXEL_SIZE*((flipy+pointint.y)%2)*float2(1,0)*sizY  -BUFFER_PIXEL_SIZE*trunc(float2(sizY,sizX)/2-0.001)).rgb);
	return(tex2D(AnnSampler,texcoord+ BUFFER_PIXEL_SIZE*((flipx+pointint.x)%2)*float2(0,1)*sizX+ BUFFER_PIXEL_SIZE*((flipy+pointint.y)%2)*float2(1,0)*sizY  -BUFFER_PIXEL_SIZE*trunc(float2(sizY,sizX)/2-0.001)).rgb);
}

float3 PS_PixelShiftX(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	//get coordinates in a easy to use per pixel term
	int pointint = trunc((texcoord.x/ (SectionSizeX*BUFFER_PIXEL_SIZE.x )));
	//this is a terribly squeezed together function, lets call this optimisation
	//it samples colour from shifted coordinates 
	//return(tex2D(AnnSampler,texcoord+ BUFFER_PIXEL_SIZE*((flipx+pointint.x)%2)*float2(0,1)*sizX+ BUFFER_PIXEL_SIZE*((flipy+pointint.y)%2)*float2(1,0)*sizY  -BUFFER_PIXEL_SIZE*trunc(float2(sizY,sizX)/2-0.001)).rgb);
	return(tex2D(AnnSampler,texcoord+ BUFFER_PIXEL_SIZE*((flipx+pointint)%2)*float2(0,1)*sizX  -BUFFER_PIXEL_SIZE*float2(0,trunc(sizX/2-0.001))).rgb);
}
float3 PS_PixelShiftY(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target{  
	//get coordinates in a easy to use per pixel term
	int pointint = trunc((texcoord.y/ (SectionSizeY*BUFFER_PIXEL_SIZE.y )));
	//this is a terribly squeezed together function, lets call this optimisation
	//it samples colour from shifted coordinates 
	//return(tex2D(AnnSampler,texcoord+ BUFFER_PIXEL_SIZE*((flipx+pointint.x)%2)*float2(0,1)*sizX+ BUFFER_PIXEL_SIZE*((flipy+pointint.y)%2)*float2(1,0)*sizY  -BUFFER_PIXEL_SIZE*trunc(float2(sizY,sizX)/2-0.001)).rgb);
	return(tex2D(AnnSampler,texcoord+ BUFFER_PIXEL_SIZE*((flipx+pointint)%2)*float2(1,0)*sizY  -BUFFER_PIXEL_SIZE*float2(trunc(sizY/2-0.001),0)).rgb);
}

/*-----------------.
| :: Techniques :: |
'-----------------*/
technique PixelShifterX
{
	pass PixelShift{
		VertexShader=PostProcessVS;
		PixelShader=PS_PixelShiftX;
	}
}

technique PixelShifterY
{
	pass PixelShift{
		VertexShader=PostProcessVS;
		PixelShader=PS_PixelShiftY;
	}
}

technique PixelShift_W_Duping
{
	pass PixelShift{
		VertexShader=PostProcessVS;
		PixelShader=PS_PixelShift;
	}
}
