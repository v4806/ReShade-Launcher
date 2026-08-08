//Original code by Marty McFly

//Check for updates here: https://github.com/originalnicodr/CorgiFX

#include "ReShade.fxh"

uniform bool FlipH <
	ui_label = "水平翻转";
    ui_category = "控制";
> = false;

uniform bool FlipV <
	ui_label = "垂直翻转";
    ui_category = "控制";
> = false;

float4 FlipPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    if (FlipH) {texcoord.x = 1-texcoord.x;}//horizontal flip
    if (FlipV) {texcoord.y = 1-texcoord.y;} //vertical flip
    float4 color = tex2D(ReShade::BackBuffer, texcoord);
    return color;
}

technique Flip
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = FlipPass;
    }
}