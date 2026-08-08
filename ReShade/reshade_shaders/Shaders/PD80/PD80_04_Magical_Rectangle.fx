/*
    Description : PD80 04 Magical Rectangle for Reshade https://reshade.me/
    Author      : prod80 (Bas Veth)
    License     : MIT, Copyright (c) 2020 prod80


    MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "PD80_00_Noise_Samplers.fxh"
#include "PD80_00_Blend_Modes.fxh"
#include "PD80_00_Color_Spaces.fxh"
#include "PD80_00_Base_Effects.fxh"

namespace pd80_magicalrectangle
{
    //// PREPROCESSOR DEFINITIONS ///////////////////////////////////////////////////

    //// UI ELEMENTS ////////////////////////////////////////////////////////////////
    uniform int shape < __UNIFORM_COMBO_INT1
        ui_label = "形状";
        ui_tooltip = "形状";
        ui_category = "形状操作";
        ui_items = "方形\0圆形\0";
        > = 0;
    uniform bool invert_shape <
        ui_label = "反转形状";
        ui_tooltip = "反转形状";
        ui_category = "形状操作";
        > = false;
    uniform uint rotation <
        ui_type = "slider";
        ui_label = "旋转角度";
        ui_tooltip = "旋转角度";
        ui_category = "形状操作";
        ui_min = 0;
        ui_max = 360;
        > = 45;
    uniform float2 center <
        ui_type = "slider";
        ui_label = "中心";
        ui_tooltip = "中心";
        ui_category = "形状操作";
        ui_min = 0.0;
        ui_max = 1.0;
        > = float2( 0.5, 0.5 );
    uniform float ret_size_x <
        ui_type = "slider";
        ui_label = "水平尺寸";
        ui_tooltip = "水平尺寸";
        ui_category = "形状操作";
        ui_min = 0.0;
        ui_max = 0.5;
        > = 0.125;
    uniform float ret_size_y <
        ui_type = "slider";
        ui_label = "垂直尺寸";
        ui_tooltip = "垂直尺寸";
        ui_category = "形状操作";
        ui_min = 0.0;
        ui_max = 0.5;
        > = 0.125;
    uniform float depthpos <
        ui_type = "slider";
        ui_label = "深度位置";
        ui_tooltip = "深度位置";
        ui_category = "形状操作";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.0;
    uniform float smoothing <
        ui_type = "slider";
        ui_label = "边缘平滑";
        ui_tooltip = "边缘平滑";
        ui_category = "形状操作";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.01;
    uniform float depth_smoothing <
        ui_type = "slider";
        ui_label = "深度平滑";
        ui_tooltip = "深度平滑";
        ui_category = "形状操作";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.002;
    uniform float dither_strength <
        ui_type = "slider";
        ui_label = "抖动强度";
        ui_tooltip = "抖动强度";
        ui_category = "形状操作";
        ui_min = 0.0f;
        ui_max = 10.0f;
        > = 0.0;
    uniform float3 reccolor <
        ui_text = "-------------------------------------\n"
                  "使用不透明度和混合模式进行调整\n"
                  "形状控制形状着色\n"
                  "图像控制底层图像\n"
                  "-------------------------------------";
        ui_type = "color";
        ui_label = "形状: 颜色";
        ui_tooltip = "形状: 颜色";
        ui_category = "形状着色";
        > = float3( 0.5, 0.5, 0.5 );
    uniform float mr_exposure <
        ui_type = "slider";
        ui_label = "图像: 曝光";
        ui_tooltip = "图像: 曝光";
        ui_category = "形状着色";
        ui_min = -4.0;
        ui_max = 4.0;
        > = 0.0;
    uniform float mr_contrast <
        ui_type = "slider";
        ui_label = "图像: 对比度";
        ui_tooltip = "图像: 对比度";
        ui_category = "形状着色";
        ui_min = -1.0;
        ui_max = 1.0;
        > = 0.0;
    uniform float mr_brightness <
        ui_type = "slider";
        ui_label = "图像: 亮度";
        ui_tooltip = "图像: 亮度";
        ui_category = "形状着色";
        ui_min = -1.0;
        ui_max = 1.0;
        > = 0.0;
    uniform float mr_hue <
        ui_type = "slider";
        ui_label = "图像: 色相";
        ui_tooltip = "图像: 色相";
        ui_category = "形状着色";
        ui_min = -1.0;
        ui_max = 1.0;
        > = 0.0;
    uniform float mr_saturation <
        ui_type = "slider";
        ui_label = "图像: 饱和度";
        ui_tooltip = "图像: 饱和度";
        ui_category = "形状着色";
        ui_min = -1.0;
        ui_max = 1.0;
        > = 0.0;
    uniform float mr_vibrance <
        ui_type = "slider";
        ui_label = "图像: 自然饱和度";
        ui_tooltip = "图像: 自然饱和度";
        ui_category = "形状着色";
        ui_min = -1.0;
        ui_max = 1.0;
        > = 0.0;
    uniform bool enable_gradient <
        ui_label = "启用渐变";
        ui_tooltip = "启用渐变";
        ui_category = "形状渐变";
        > = false;
    uniform bool gradient_type <
        ui_label = "渐变类型";
        ui_tooltip = "渐变类型";
        ui_category = "形状渐变";
        > = false;
    uniform float gradient_curve <
        ui_type = "slider";
        ui_label = "渐变曲线";
        ui_tooltip = "渐变曲线";
        ui_category = "形状渐变";
        ui_min = 0.001;
        ui_max = 2.0;
        > = 0.25;
    uniform float intensity_boost <
        ui_type = "slider";
        ui_label = "强度增强";
        ui_tooltip = "强度增强";
        ui_category = "强度增强";
        ui_min = 1.0;
        ui_max = 4.0;
        > = 1.0;
    uniform int blendmode_1 < __UNIFORM_COMBO_INT1
        ui_label = "混合模式";
        ui_tooltip = "混合模式";
        ui_category = "形状混合";
        ui_items = "默认\0变暗\0正片叠底\0线性加深\0颜色加深\0变亮\0滤色\0颜色减淡\0线性减淡\0叠加\0柔光\0亮光\0线性光\0点光\0实色混合\0反射\0发光\0色相\0饱和度\0颜色\0明度\0";
        > = 0;
    uniform float opacity <
        ui_type = "slider";
        ui_label = "不透明度";
        ui_tooltip = "不透明度";
        ui_category = "形状混合";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 1.0;
    //// TEXTURES ///////////////////////////////////////////////////////////////////
    texture texMagicRectangle { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };

    //// SAMPLERS ///////////////////////////////////////////////////////////////////
    sampler samplerMagicRectangle { Texture = texMagicRectangle; };

    //// DEFINES ////////////////////////////////////////////////////////////////////
    #define ASPECT_RATIO float( BUFFER_WIDTH * BUFFER_RCP_HEIGHT )

    //// FUNCTIONS //////////////////////////////////////////////////////////////////
    uniform bool hasdepth < source = "bufready_depth"; >;

    float3 hue( float3 res, float shift, float x )
    {
        float3 hsl = RGBToHSL( res.xyz );
        hsl.x = frac( hsl.x + ( shift + 1.0f ) / 2.0f - 0.5f );
        hsl.xyz = HSLToRGB( hsl.xyz );
        return lerp( res.xyz, hsl.xyz, x );
    }

    float curve( float x )
    {
        return x * x * x * ( x * ( x * 6.0f - 15.0f ) + 10.0f );
    }

    //// VERTEX SHADER //////////////////////////////////////////////////////////////
    /*
    Adding texcoord2 in vextex shader which is a rotated texcoord
    */
    void PPVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD, out float2 texcoord2 : TEXCOORD2)
    {
        PostProcessVS(id, position, texcoord);
        float2 uv;
        uv.x         = ( id == 2 ) ? 2.0 : 0.0;
	    uv.y         = ( id == 1 ) ? 2.0 : 0.0;
        uv.xy        -= center.xy;
        uv.y         /= ASPECT_RATIO;
        float dim    = ceil( sqrt( BUFFER_WIDTH * BUFFER_WIDTH + BUFFER_HEIGHT * BUFFER_HEIGHT )); // Diagonal size
        float maxlen = min( BUFFER_WIDTH, BUFFER_HEIGHT );
        dim          = dim / maxlen; // Scalar
        uv.xy        /= dim;
        float sin    = sin( radians( rotation ));
        float cos    = cos( radians( rotation ));
        texcoord2.x  = ( uv.x * cos ) + ( uv.y * (-sin));
        texcoord2.y  = ( uv.x * sin ) + ( uv.y * cos );
        texcoord2.xy += float2( 0.5f, 0.5f ); // Transform back
    }

    //// PIXEL SHADERS //////////////////////////////////////////////////////////////
    float4 PS_Layer_1( float4 pos : SV_Position, float2 texcoord : TEXCOORD, float2 texcoord2 : TEXCOORD2 ) : SV_Target
    {
        float4 color      = tex2D( ReShade::BackBuffer, texcoord );
        // Depth stuff
        float depth       = ReShade::GetLinearizedDepth( texcoord ).x;
        // Sizing
        float dim         = ceil( sqrt( BUFFER_WIDTH * BUFFER_WIDTH + BUFFER_HEIGHT * BUFFER_HEIGHT )); // Diagonal size
        float maxlen      = max( BUFFER_WIDTH, BUFFER_HEIGHT );
        dim               = dim / maxlen; // Scalar with screen diagonal
        float2 uv         = texcoord2.xy;
        uv.xy             = uv.xy * 2.0f - 1.0f; // rescale to -1..0..1 range
        uv.xy             /= ( float2( ret_size_x + ret_size_x * smoothing, ret_size_y + ret_size_y * smoothing ) * dim ); // scale rectangle
        switch( shape )
        {
            case 0: // square
            { uv.xy       = uv.xy; } break;
            case 1: // circle
            { uv.xy       = lerp( dot( uv.xy, uv.xy ), dot( uv.xy, -uv.xy ), gradient_type ); } break;
        }
        uv.xy             = ( uv.xy + 1.0f ) / 2.0f; // scale back to 0..1 range
        
        // Using smoothstep to create values from 0 to 1, 1 being the drawn shape around center
        // First makes bottom and left side, then flips coord to make top and right side: x | 1 - x
        // Do some funky stuff with gradients
        // Finally make a depth fade
        float2 bl         = smoothstep( 0.0f, 0.0f + smoothing, uv.xy );
        float2 tr         = smoothstep( 0.0f, 0.0f + smoothing, 1.0f - uv.xy );
        if( enable_gradient )
        {
            if( gradient_type )
            {
                bl        = smoothstep( 0.0f, 0.0f + smoothing, uv.xy ) * pow( abs( uv.y ), gradient_curve );
            }
            tr            = smoothstep( 0.0f, 0.0f + smoothing, 1.0f - uv.xy ) * pow( abs( uv.x ), gradient_curve );
        }
        float depthfade   = smoothstep( depthpos - depth_smoothing, depthpos + depth_smoothing, depth );
        depthfade         = lerp( 1.0f, depthfade, hasdepth );
        // Combine them all
        float R           = bl.x * bl.y * tr.x * tr.y * depthfade;
        R                 = ( invert_shape ) ? 1.0f - R : R;
        // Blend the borders
        float intensity   = RGBToHSV( reccolor.xyz ).z;
        color.xyz         = lerp( color.xyz, saturate( color.xyz * saturate( 1.0f - R ) + R * intensity ), R );
        // Add to color, use R for Alpha
        return float4( color.xyz, R );
    }	

    float4 PS_Blend(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float4 orig       = tex2D( ReShade::BackBuffer, texcoord );
        float3 color;
        float4 layer_1    = saturate( tex2D( samplerMagicRectangle, texcoord ));
        // Dither
        // Input: sampler, texcoord, variance(int), enable_dither(bool), dither_strength(float), motion(bool), swing(float)
        float4 dnoise     = dither( samplerRGBNoise, texcoord.xy, 7, 1, dither_strength, 1, 0.5f );
        layer_1.xyz       = saturate( layer_1.xyz + dnoise.xyz );

        orig.xyz          = exposure( orig.xyz, mr_exposure * layer_1.w );
        orig.xyz          = con( orig.xyz, mr_contrast * layer_1.w );
        orig.xyz          = bri( orig.xyz, mr_brightness * layer_1.w );
        orig.xyz          = hue( orig.xyz, mr_hue, layer_1.w );
        orig.xyz          = sat( orig.xyz, mr_saturation * layer_1.w );
        orig.xyz          = vib( orig.xyz, mr_vibrance * layer_1.w );
        orig.xyz          = saturate( orig.xyz );
        // Doing some HSL color space conversions to colorize
        layer_1.xyz       = saturate( layer_1.xyz * intensity_boost );
        layer_1.xyz       = RGBToHSV( layer_1.xyz );
        float2 huesat     = RGBToHSV( reccolor.xyz ).xy;
        layer_1.xyz       = HSVToRGB( float3( huesat.xy, layer_1.z ));
        layer_1.xyz       = saturate( layer_1.xyz );
        // Blend mode with background
        color.xyz         = blendmode( orig.xyz, layer_1.xyz, blendmode_1, saturate( layer_1.w ) * opacity );
        // Output to screen
        return float4( color.xyz, 1.0f );
    }

    //// TECHNIQUES /////////////////////////////////////////////////////////////////
    technique prod80_04_Magical_Rectangle
    < ui_tooltip = "魔法矩形\n\n"
                   "这个着色器在屏幕上创建一个可以在3D空间中操作的矩形形状。\n"
                   "它可以按深度混合、模糊边缘、改变颜色、改变混合模式、改变形状等。\n"
                   "它允许你以各种方式操作场景的部分。包括：添加雾气、\n"
                   "移除雾气、改变云层、创建背景、绘制光晕、添加对比度、改变色相等，\n"
                   "这些是其他着色器无法做到的。\n\n"
                   "此着色器需要访问深度缓冲区才能完全发挥功能！";>
    {
        pass prod80_pass0
        {
            VertexShader   = PPVS;
            PixelShader    = PS_Layer_1;
            RenderTarget   = texMagicRectangle;
        }
        pass prod80_pass1
        {
            VertexShader   = PPVS;
            PixelShader    = PS_Blend;
        }
    }
}


