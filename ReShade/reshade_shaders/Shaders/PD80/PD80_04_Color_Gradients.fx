/*
    Description : PD80 04 Color Gradients for Reshade https://reshade.me/
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

namespace pd80_ColorGradients
{
    //// UI ELEMENTS ////////////////////////////////////////////////////////////////
    uniform int luma_mode < __UNIFORM_COMBO_INT1
        ui_label = "亮度模式";
        ui_tooltip = "亮度模式";
        ui_category = "全局";
        ui_items = "使用平均值\0使用感知亮度\0使用最大值\0";
        > = 0;
    uniform int separation_mode < __UNIFORM_COMBO_INT1
        ui_label = "亮度分离模式";
        ui_tooltip = "亮度分离模式";
        ui_category = "全局";
        ui_items = "强烈分离\0平滑分离\0";
        > = 0;
    uniform bool enable_dither <
        ui_label = "启用抖动";
        ui_tooltip = "启用抖动";
        ui_category = "全局";
        > = true;
    uniform float dither_strength <
        ui_type = "slider";
        ui_label = "抖动强度";
        ui_tooltip = "抖动强度";
        ui_category = "全局";
        ui_min = 0.0f;
        ui_max = 10.0f;
        > = 1.0;
    uniform float CGdesat <
        ui_label = "去饱和基础图像";
        ui_tooltip = "去饱和基础图像";
        ui_category = "混合值";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.0;
    uniform float finalmix <
        ui_label = "与原图混合";
        ui_tooltip = "与原图混合";
        ui_category = "混合值";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.333;
    // Light Scene
    uniform float3 blendcolor_ls_m <
        ui_type = "color";
        ui_label = "颜色";
        ui_tooltip = "亮场景: 中间调颜色";
        ui_category = "亮场景: 中间调颜色";
        > = float3( 0.98, 0.588, 0.0 );
    uniform int blendmode_ls_m < __UNIFORM_COMBO_INT1
        ui_label = "混合模式";
        ui_tooltip = "亮场景: 中间调颜色混合模式";
        ui_category = "亮场景: 中间调颜色";
        ui_items = "默认\0变暗\0正片叠底\0线性加深\0颜色加深\0变亮\0滤色\0颜色减淡\0线性减淡\0叠加\0柔光\0亮光\0线性光\0点光\0实色混合\0反射\0发光\0色相\0饱和度\0颜色\0明度\0";
        > = 10;
    uniform float opacity_ls_m <
        ui_label = "不透明度";
        ui_tooltip = "亮场景: 中间调颜色不透明度";
        ui_category = "亮场景: 中间调颜色";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 1.0;
    uniform float3 blendcolor_ls_s <
        ui_type = "color";
        ui_label = "颜色";
        ui_tooltip = "亮场景: 阴影颜色";
        ui_category = "亮场景: 阴影颜色";
        > = float3( 0.0,  0.365, 1.0 );
    uniform int blendmode_ls_s < __UNIFORM_COMBO_INT1
        ui_label = "混合模式";
        ui_tooltip = "亮场景: 阴影颜色混合模式";
        ui_category = "亮场景: 阴影颜色";
        ui_items = "默认\0变暗\0正片叠底\0线性加深\0颜色加深\0变亮\0滤色\0颜色减淡\0线性减淡\0叠加\0柔光\0亮光\0线性光\0点光\0实色混合\0反射\0发光\0色相\0饱和度\0颜色\0明度\0";
        > = 5;
    uniform float opacity_ls_s <
        ui_label = "不透明度";
        ui_tooltip = "亮场景: 阴影颜色不透明度";
        ui_category = "亮场景: 阴影颜色";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.3;
    // Dark Scene
    uniform bool enable_ds <
        ui_text = "-------------------------------------\n"
                  "根据场景平均亮度启用渐变过渡。\n"
                  "模拟日夜颜色分级。\n"
                  "-------------------------------------";
        ui_label = "启用颜色过渡";
        ui_tooltip = "启用颜色过渡";
        ui_category = "启用颜色过渡";
        > = true;
    uniform float3 blendcolor_ds_m <
        ui_type = "color";
        ui_label = "颜色";
        ui_tooltip = "暗场景: 中间调颜色";
        ui_category = "暗场景: 中间调颜色";
        > = float3( 0.0,  0.365, 1.0 );
    uniform int blendmode_ds_m < __UNIFORM_COMBO_INT1
        ui_label = "混合模式";
        ui_tooltip = "暗场景: 中间调颜色混合模式";
        ui_category = "暗场景: 中间调颜色";
        ui_items = "默认\0变暗\0正片叠底\0线性加深\0颜色加深\0变亮\0滤色\0颜色减淡\0线性减淡\0叠加\0柔光\0亮光\0线性光\0点光\0实色混合\0反射\0发光\0色相\0饱和度\0颜色\0明度\0";
        > = 10;
    uniform float opacity_ds_m <
        ui_label = "不透明度";
        ui_tooltip = "暗场景: 中间调颜色不透明度";
        ui_category = "暗场景: 中间调颜色";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 1.0;
    uniform float3 blendcolor_ds_s <
        ui_type = "color";
        ui_label = "颜色";
        ui_tooltip = "暗场景: 阴影颜色";
        ui_category = "暗场景: 阴影颜色";
        > = float3( 0.0,  0.039, 0.588 );
    uniform int blendmode_ds_s < __UNIFORM_COMBO_INT1
        ui_label = "混合模式";
        ui_tooltip = "暗场景: 阴影颜色混合模式";
        ui_category = "暗场景: 阴影颜色";
        ui_items = "默认\0变暗\0正片叠底\0线性加深\0颜色加深\0变亮\0滤色\0颜色减淡\0线性减淡\0叠加\0柔光\0亮光\0线性光\0点光\0实色混合\0反射\0发光\0色相\0饱和度\0颜色\0明度\0";
        > = 10;
    uniform float opacity_ds_s <
        ui_label = "不透明度";
        ui_tooltip = "暗场景: 阴影颜色不透明度";
        ui_category = "暗场景: 阴影颜色";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 1.0;
    uniform float minlevel <
        ui_label = "纯暗场景级别";
        ui_tooltip = "纯暗场景级别";
        ui_category = "场景亮度自适应";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.125;
    uniform float maxlevel <
        ui_label = "纯亮场景级别";
        ui_tooltip = "纯亮场景级别";
        ui_category = "场景亮度自适应";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.3;
    //// TEXTURES ///////////////////////////////////////////////////////////////////
    texture texLuma { Width = 256; Height = 256; Format = R16F; MipLevels = 8; };
    texture texAvgLuma { Format = R16F; };
    texture texPrevAvgLuma { Format = R16F; };

    //// SAMPLERS ///////////////////////////////////////////////////////////////////
    sampler samplerLuma { Texture = texLuma; };
    sampler samplerAvgLuma { Texture = texAvgLuma; };
    sampler samplerPrevAvgLuma { Texture = texPrevAvgLuma; };

    //// DEFINES ////////////////////////////////////////////////////////////////////
    #define LumCoeff float3(0.212656, 0.715158, 0.072186)
    uniform float Frametime < source = "frametime"; >;
    uniform float2 pingpong < source = "pingpong"; min = 0; max = 128; step = 1; >;

    //// FUNCTIONS //////////////////////////////////////////////////////////////////
    float getLuminance( in float3 x )
    {
        return dot( x, LumCoeff );
    }

    float curve( float x )
    {
        return x * x * ( 3.0f - 2.0f * x );
    }

    //// PIXEL SHADERS //////////////////////////////////////////////////////////////
    float PS_WriteLuma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float4 color     = tex2D( ReShade::BackBuffer, texcoord );
        float luma       = max( max( color.x, color.y ), color.z );
        return luma; //writes to texLuma
    }

    float PS_AvgLuma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float luma       = tex2Dlod( samplerLuma, float4( 0.5f, 0.5f, 0, 8 )).x;
        float prevluma   = tex2D( samplerPrevAvgLuma, float2( 0.5f, 0.5f )).x;
        float avgLuma    = lerp( prevluma, luma, saturate( Frametime * 0.003f ));
        return avgLuma; //writes to texAvgLuma
    }

    float4 PS_ColorGradients(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float4 color     = tex2D( ReShade::BackBuffer, texcoord );
        float sceneluma  = tex2D( samplerAvgLuma, float2( 0.5f, 0.5f )).x;
        float ml         = ( minlevel >= maxlevel ) ? maxlevel - 0.01f : minlevel;
        sceneluma        = smoothstep( ml, maxlevel, sceneluma );
        color.xyz        = saturate( color.xyz );

        // Dither
        // Input: sampler, texcoord, variance(int), enable_dither(bool), dither_strength(float), motion(bool), swing(float)
        float4 dnoise      = dither( samplerRGBNoise, texcoord.xy, 5, enable_dither, dither_strength, 1, 0.5f );
        color.xyz          = saturate( color.xyz + dnoise.xyz ); 
        
        // Weights
        float cWeight;
        switch( luma_mode )
        {
            case 0: // Use average
            {
                cWeight = dot( color.xyz, float3( 0.333333f, 0.333334f, 0.333333f ));
            }
            break;
            case 1: // Use perceived luma
            {
                cWeight = dot( color.xyz, float3( 0.212656f, 0.715158f, 0.072186f ));
            }
            break;
            case 2: // Use max
            {
                cWeight = max( max( color.x, color.y ), color.z );
            }
            break;
        }

        float w_s; float w_h; float w_m;
        switch( separation_mode )
        {
            /*
            Clear cutoff between shadows and highlights
            Maximizes precision at the loss of harsher transitions between contrasts
            Curves look like:

            Shadows                Highlights             Midtones
            ‾‾‾—_   	                         _—‾‾‾         _——‾‾‾——_
                 ‾‾——__________    __________——‾‾         ___—‾         ‾—___
            0.0.....0.5.....1.0    0.0.....0.5.....1.0    0.0.....0.5.....1.0
            
            */
            case 0:
            {
                w_s      = curve( max( 1.0f - cWeight * 2.0f, 0.0f ));
                w_h      = curve( max(( cWeight - 0.5f ) * 2.0f, 0.0f ));
                w_m      = saturate( 1.0f - w_s - w_h );
            } break;

            /*
            Higher degree of blending between individual curves
            F.e. shadows will still have a minimal weight all the way into highlight territory
            Ensures smoother transition areas between contrasts
            Curves look like:

            Shadows                Highlights             Midtones
            ‾‾‾—_                                _—‾‾‾          __---__
                 ‾‾———————_____    _____———————‾‾         ___-‾‾       ‾‾-___
            0.0.....0.5.....1.0    0.0.....0.5.....1.0    0.0.....0.5.....1.0
            
            */
            case 1:
            {
                w_s      = pow( 1.0f - cWeight, 4.0f );
                w_h      = pow( cWeight, 4.0f );
                w_m      = saturate( 1.0f - w_s - w_h );
            } break;
        }

        // Desat original
        // float pLuma      = getLuminance( color.xyz );
        color.xyz        = lerp( color.xyz, cWeight, CGdesat );

        // Coloring
        float3 LS_col;
        float3 DS_col;

        // Light scene
        float3 LS_b_s    = blendmode( color.xyz, blendcolor_ls_s.xyz, blendmode_ls_s, opacity_ls_s );
        float3 LS_b_m    = blendmode( color.xyz, blendcolor_ls_m.xyz, blendmode_ls_m, opacity_ls_m );
        LS_col.xyz       = LS_b_s.xyz * w_s + LS_b_m.xyz * w_m + w_h;

        // Dark Scene
        float3 DS_b_s    = blendmode( color.xyz, blendcolor_ds_s.xyz, blendmode_ds_s, opacity_ds_s );
        float3 DS_b_m    = blendmode( color.xyz, blendcolor_ds_m.xyz, blendmode_ds_m, opacity_ds_m );
        DS_col.xyz       = DS_b_s.xyz * w_s + DS_b_m.xyz * w_m + w_h;

        // Mix
        float3 new_c     = lerp( DS_col.xyz, LS_col.xyz, sceneluma );
        new_c.xyz        = ( enable_ds ) ? new_c.xyz : LS_col.xyz;
        color.xyz        = lerp( color.xyz, new_c.xyz, finalmix );

        return float4( color.xyz, 1.0f );
    }

    float PS_PrevAvgLuma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float avgLuma    = tex2D( samplerAvgLuma, float2( 0.5f, 0.5f )).x;
        return avgLuma; //writes to texPrevAvgLuma
    }

    //// TECHNIQUES /////////////////////////////////////////////////////////////////
    technique prod80_04_ColorGradient
    {
        pass Luma
        {
            VertexShader   = PostProcessVS;
            PixelShader    = PS_WriteLuma;
            RenderTarget   = texLuma;
        }
        pass AvgLuma
        {
            VertexShader   = PostProcessVS;
            PixelShader    = PS_AvgLuma;
            RenderTarget   = texAvgLuma;
        }
        pass ColorGradients
        {
            VertexShader   = PostProcessVS;
            PixelShader    = PS_ColorGradients;
        }
        pass PreviousLuma
        {
            VertexShader   = PostProcessVS;
            PixelShader    = PS_PrevAvgLuma;
            RenderTarget   = texPrevAvgLuma;
        }
    }
}