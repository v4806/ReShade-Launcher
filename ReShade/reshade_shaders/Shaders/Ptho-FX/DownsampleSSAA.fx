/**
	DownsampleSSAA version 1.0
	by PthoEastCoast

	Makes it look as if the image was downsampled from it's native resolution to a custom lower resolution. 
	Giving the impression of rendering at a lower resolution but with higher image quality comparable to supersampling.
	It blurs the original image and then pixelates the image after blurring.
	For best image quality - run the game at the native resolution of your display. (higher render resolution = higher quality anti-aliasing/pixelation when downsampling)
**/

#include "ReShadeUI.fxh"

uniform int UpscalingSetting
<
	ui_type = "combo";
	ui_items =	"最近邻" "\0"
				"双线性" "\0"
				"加权双线性 1" "\0"
				"加权双线性 2" "\0"
				"加权双线性 3" "\0"
				"加权双线性 4" "\0";
	ui_label = "图像放大设置";
	ui_tooltip = "设置用于放大降采样图像的方法。\n"
	"最近邻提供像素锐利的图像。\n"
	"双线性通过混合相邻像素提供平滑图像。\n"
	"加权双线性 1-4 将提供比双线性更锐利的图像。";
> = 4;

uniform int VerticalResolution 
< __UNIFORM_SLIDER_INT1
	ui_min = 240.0; ui_max = 1080.0;
	ui_tooltip = "设置降采样图像的垂直分辨率（水平分辨率会自动计算）";
> = 480.0;

uniform int DownsampleBlurFactor
< __UNIFORM_SLIDER_INT1
	ui_min = 0.0; ui_max = 5.0;
	ui_tooltip = "设置降采样时应用于图像的模糊程度。（较低的值产生更锐利但锯齿更明显的图像。较高的值产生更平滑但更模糊的图像。）";
> = 1.0;

#include "ReShade.fxh"

#define numOfSamplesRight 14.0

texture BoxBlurHTex < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
texture BoxBlurVTex < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };

sampler BoxBlurHSampler{ Texture = BoxBlurHTex; };
sampler BoxBlurVSampler{ Texture = BoxBlurVTex; };

float4 BoxBlurHorizontalPass(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD) : COLOR
{
	float aspectRatio = 1.0 / BUFFER_ASPECT_RATIO;
	float pixelUVSize = (1.0 / (float)VerticalResolution) * aspectRatio;
	float smoothScale = (float)DownsampleBlurFactor * 0.05 + 0.25;
	float uvDistBetweenSamples = (pixelUVSize * smoothScale) / numOfSamplesRight;

	float4 accumulatedColor = float4(0.0, 0.0, 0.0, 1.0);

	for (float i = -numOfSamplesRight; i <= numOfSamplesRight; i++)
	{
		accumulatedColor = accumulatedColor + tex2D( ReShade::BackBuffer, texcoord + float2(i * uvDistBetweenSamples, 0.0) );
	}
	accumulatedColor = accumulatedColor * (1.0 / (numOfSamplesRight * 2.0 + 1.0));

	return accumulatedColor;
}

float4 BoxBlurVerticalPass(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD) : COLOR
{
	float pixelUVSize = 1.0 / (float)VerticalResolution;
	float smoothScale = (float)DownsampleBlurFactor * 0.05 + 0.25;
	float uvDistBetweenSamples = (pixelUVSize * smoothScale) / numOfSamplesRight;

	float4 accumulatedColor = float4(0.0, 0.0, 0.0, 1.0);

	for (float i = -numOfSamplesRight; i <= numOfSamplesRight; i++)
	{
		accumulatedColor = accumulatedColor + tex2D( BoxBlurHSampler, texcoord + float2(0.0, i * uvDistBetweenSamples) );
	}
	accumulatedColor = accumulatedColor * (1.0 / (numOfSamplesRight * 2.0 + 1.0));

	return accumulatedColor;
}

float3 PixelationPass(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD) : COLOR
{
	float aspectRatio = 1.0 / BUFFER_ASPECT_RATIO;
	float PixelUVSize = 1.0 / (float)VerticalResolution;

	float pixelUVSizeX = PixelUVSize * aspectRatio;
	float pixelUVSizeY = PixelUVSize;

	float texcoordDistFromPixelX = texcoord.x % pixelUVSizeX;
	float texcoordDistFromPixelY = texcoord.y % pixelUVSizeY;

	float2 thisCoord;
	thisCoord.x = texcoord.x - texcoordDistFromPixelX;
	thisCoord.y = texcoord.y - texcoordDistFromPixelY;
	float3 thisPixelColor = tex2D(BoxBlurVSampler, thisCoord).rgb;

	if (UpscalingSetting == 0)
	{
		return thisPixelColor;
	}

	float2 nextCoordUp;
	nextCoordUp.x = thisCoord.x;
	nextCoordUp.y = thisCoord.y + pixelUVSizeY;
	float3 nextPixelColorUp = tex2D(BoxBlurVSampler, nextCoordUp).rgb;

	float2 nextCoordRight;
	nextCoordRight.x = thisCoord.x + pixelUVSizeX;
	nextCoordRight.y = thisCoord.y;
	float3 nextPixelColorRight = tex2D(BoxBlurVSampler, nextCoordRight).rgb;

	float2 nextCoordUpRight;
	nextCoordUpRight.x = thisCoord.x + pixelUVSizeX;
	nextCoordUpRight.y = thisCoord.y + pixelUVSizeY;
	float3 nextPixelColorUpRight = tex2D(BoxBlurVSampler, nextCoordUpRight).rgb;

	float tx = texcoordDistFromPixelX / pixelUVSizeX;
	float ty = texcoordDistFromPixelY / pixelUVSizeY;

	float powerAmount = 0.75 + UpscalingSetting * 0.25;
		
	tx = tx < 0.5 ? pow( abs(tx), powerAmount ) : pow( abs(tx), 1.0 / powerAmount );
	ty = ty < 0.5 ? pow( abs(ty), powerAmount ) : pow( abs(ty), 1.0 / powerAmount );

	float3 lerpCurrentToRight = lerp(thisPixelColor, nextPixelColorRight, tx);
	float3 lerpUpToUpRight = lerp(nextPixelColorUp, nextPixelColorUpRight, tx);

	float3 pixelColor = lerp(lerpCurrentToRight, lerpUpToUpRight, ty);

	return pixelColor;
}

technique DownsampleSSAA
{
	pass BoxBlurHorizontalPass
	{
		VertexShader = PostProcessVS;
		PixelShader = BoxBlurHorizontalPass;
		RenderTarget = BoxBlurHTex;
	}
	pass BoxBlurVerticalPass
	{
		VertexShader = PostProcessVS;
		PixelShader = BoxBlurVerticalPass;
		RenderTarget = BoxBlurVTex;
	}
	pass PixelationPass
	{
		VertexShader = PostProcessVS;
		PixelShader = PixelationPass;
	}
}
