//Made by originalnicodr
//Based on https://www.shadertoy.com/view/3sdyRH by oneshade

namespace MagnifyingGlass
{

#include "ReShade.fxh"

uniform float2 MouseCoords < source = "mousepoint"; >;
uniform bool LeftMouseDown < source = "mousebutton"; keycode = 0; toggle = false; >;
uniform bool SCREENSHOT < source = "screenshot"; >;

#ifndef MAGNIFYING_GLASS_MAX_ZOOM
	#define MAGNIFYING_GLASS_MAX_ZOOM 5
#endif

uniform bool HideOnScreenshot <
	ui_label = "截图时隐藏";
	ui_tooltip = "截图时不绘制放大镜。";
> = false;

uniform float lensZoom <
	ui_category = "镜头";
	ui_label = "缩放倍率";
	ui_type = "slider";
    ui_min = 1; ui_max = MAGNIFYING_GLASS_MAX_ZOOM;
    ui_step = 0.01;
> = 3.0;

uniform float lensRadius <
	ui_category = "镜头";
	ui_label = "镜头半径";
	ui_type = "slider";
    ui_min = 0.0; ui_max = 0.5;
    ui_step = 0.01;
> = 0.1;

uniform bool pointToggle < //this is new
	ui_category = "镜头";
	ui_label = "锐利像素";
	ui_tooltip = "启用此选项可在放大时不模糊像素，\n从而更真实地查看像素的实际外观。";
> = true;

uniform bool showWhenClick <
	ui_category = "镜头";
	ui_label = "点击时显示放大镜";
> = false;

uniform bool useUICoords <
	ui_category = "镜头位置";
	ui_label = "使用坐标而非鼠标位置";
> = false;

uniform float2 magnifyingGlassUICoords <
	ui_category = "镜头位置";
	ui_label = "坐标";
	ui_type = "slider";
    ui_step = 0.01;
    ui_min = 0.0; ui_max = 1.0;
> = float2(0.5, 0.5);

uniform float lensBorderWidth <
	ui_category = "边框";
	ui_label = "镜头边框宽度";
	ui_type = "slider";
    ui_step = 0.001;
    ui_min = 0.0; ui_max = 0.1;
> = 0.003;

uniform float3 lensBorderColor <
	ui_category = "边框";
	ui_label = "边框颜色";
    ui_type = "color";
> = float3(0.0, 0.0, 0.0);

uniform bool invertColorBackground <
	ui_category = "边框";
	ui_label = "使用背景反色作为边框颜色";
> = false;

sampler2D pointBuffer //this is also new
{
	Texture   = ReShade::BackBufferTex;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU  = BORDER;
	AddressV  = BORDER;
};

float3 MagnifyingGlass_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	if (SCREENSHOT && HideOnScreenshot) {
		return color;
	}

    const float halfBorderWidth = lensBorderWidth / 2.0;
	const float innerRadius = lensRadius - halfBorderWidth;
	const float outerRadius = lensRadius + halfBorderWidth;

	float2 magnifyingGlassPos = useUICoords ? magnifyingGlassUICoords : MouseCoords * BUFFER_PIXEL_SIZE;

	float dist = sqrt(pow((texcoord.x - magnifyingGlassPos.x) * BUFFER_ASPECT_RATIO, 2.0) + pow(texcoord.y - magnifyingGlassPos.y, 2.0)); //edited

	float3 realBorderColor = invertColorBackground ? 1 - color : lensBorderColor;

	if (!showWhenClick || LeftMouseDown){
		if (dist <= innerRadius) {
			texcoord = (magnifyingGlassPos + ((texcoord - magnifyingGlassPos) / lensZoom));
			color = pointToggle ? tex2D(pointBuffer, texcoord).rgb : tex2D(ReShade::BackBuffer, texcoord).rgb; //edited
		}
    
		if (dist > innerRadius && dist <= outerRadius) {
			color = realBorderColor;
		}

	}

    return color;
}


technique MagnifyingGlass
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = MagnifyingGlass_PS;
	}
}

}
