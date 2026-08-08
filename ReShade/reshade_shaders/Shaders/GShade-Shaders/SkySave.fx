// Made by Marot Satil for GShade, a fork of ReShade.
// You can follow me via @MarotSatil on Twitter, but I don't use it all that much and if you message me directly it's very likely to get flagged as spam.
// If you have questions about this shader or need to contact me for any other reason, reaching out to me via the username Marot on Discord is likely a better bet.
//
// This shader was designed to do exactly what the name implies, save all pixels further than a certain distance away
// from the camera (SkySave) and then restore them after other techniques have been applied (SkyRestore).
//
// Copyright © 2024 Marot Satil
// This work is free. You can redistribute it and/or modify it under the
// terms of the Do What The Fuck You Want To Public License, Version 2,
// as published by Sam Hocevar.
//
//            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
//                    Version 2, December 2004
//
// Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
//
// Everyone is permitted to copy and distribute verbatim or modified
// copies of this license document, and changing it is allowed as long
// as the name is changed.
//
//            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
//   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
//
//  0. You just DO WHAT THE FUCK YOU WANT TO.
//

#include "ReShade.fxh"

texture SkySave_Tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler SkySave_Sampler { Texture = SkySave_Tex; };

uniform float fSkySaveDepth <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "深度";
> = 0.999;

uniform bool fSkySaveInvertDepth <
	ui_label = "反转深度";
> = false;

void PS_SkySave(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float4 color : SV_Target)
{
	color = tex2D(ReShade::BackBuffer, texcoord);

	color.a = step(fSkySaveDepth, fSkySaveInvertDepth ? 1.0 - ReShade::GetLinearizedDepth(texcoord) : ReShade::GetLinearizedDepth(texcoord));
}

void PS_SkyRestore(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float4 color : SV_Target)
{
    color = tex2D(ReShade::BackBuffer, texcoord);
    const float4 keep = tex2D(SkySave_Sampler, texcoord);

    color.rgb = lerp(color.rgb, keep.rgb, keep.a).rgb;
}

technique SkySave <
    ui_tooltip = "将此放置在加载顺序中您希望保存天空以便稍后使用SkyRestore恢复的位置。\n"
                 "要使用此技术，您还必须启用\"SkyRestore\"。\n";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SkySave;
        RenderTarget = SkySave_Tex;
    }
}

technique SkyRestore <
    ui_tooltip = "将此放置在加载顺序中您希望恢复先前由SkySave保存的天空的位置。\n"
                 "要使用此技术，您还必须启用\"SkySave\"。\n";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SkyRestore;
    }
}
