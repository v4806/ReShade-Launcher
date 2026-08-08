/**
 * Deband shader by haasn
 * https://github.com/haasn/gentoo-conf/blob/xor/home/nand/.mpv/shaders/deband-pre.glsl
 *
 * Copyright (c) 2015 Niklas Haas
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Modified and optimized for ReShade by JPulowski
 * https://reshade.me/forum/shader-presentation/768-deband
 *
 * Do not distribute without giving credit to the original author(s).
 *
 * 1.0  - Initial release
 * 1.1  - Replaced the algorithm with the one from MPV
 * 1.1a - Minor optimizations
 *      - Removed unnecessary lines and replaced them with ReShadeFX intrinsic counterparts
 * 2.0  - Replaced "grain" with CeeJay.dk's ordered dithering algorithm and enabled it by default
 *      - The configuration is now more simpler and straightforward
 *      - Some minor code changes and optimizations
 *      - Improved the algorithm and made it more robust by adding some of the madshi's
 *        improvements to flash3kyuu_deband which should cause an increase in quality. Higher
 *        iterations/ranges should now yield higher quality debanding without too much decrease
 *        in quality.
 *      - Changed licensing text and original source code URL
 * 3.0  - Replaced the entire banding detection algorithm with modified standard deviation and
 *        Weber ratio analyses which give more accurate and error-free results compared to the
 *        previous algorithm
 *      - Added banding map debug view
 *      - Added and redefined UI categories
 *      - Added depth detection (credits to spiro) which should be useful when banding only
 *        occurs in the sky texture for example
 *      - Fixed a bug in random number generation which was causing artifacts on the upper left
 *        side of the screen
 *      - Dithering is now applied only when debanding a pixel as it should be which should
 *        reduce the overall noise in the final texture
 *      - Minor code optimizations
 * 3.1  - Switched to chroma-based analysis from luma-based analysis which was causing artifacts
 *        under some scenarios
 *      - Changed parts of the code which was causing compatibility issues on some renderers
 */

#include "ReShadeUI.fxh"
#include "ReShade.fxh"

uniform bool enable_weber <
    ui_category = "色带分析";
    ui_label = "韦伯比";
    ui_tooltip = "韦伯比分析计算每个局部像素的强度与所有局部像素的平均背景强度的比值。";
    ui_type = "radio";
> = true;

uniform bool enable_sdeviation <
    ui_category = "色带分析";
    ui_label = "标准差";
    ui_tooltip = "修改后的标准差分析，计算附近像素与当前像素（而非平均值）的强度偏差。";
    ui_type = "radio";
> = true;

uniform bool enable_depthbuffer <
    ui_category = "色带分析";
    ui_label = "深度检测";
    ui_tooltip = "允许在分析色带时使用深度信息，只有在特定深度的像素才会被分析。（例如：只对天空去色带）";
    ui_type = "radio";
> = false;

uniform float t1 <
    ui_category = "色带分析";
    ui_label = "标准差阈值";
    ui_max = 0.5;
    ui_min = 0.0;
    ui_step = 0.001;
    ui_tooltip = "低于此阈值的标准差将被标记为可能存在色带的平坦区域。";
    ui_type = "slider";
> = 0.007;

uniform float t2 <
    ui_category = "色带分析";
    ui_label = "韦伯比阈值";
    ui_max = 2.0;
    ui_min = 0.0;
    ui_step = 0.01;
    ui_tooltip = "低于此阈值的韦伯比将被标记为可能存在色带的平坦区域。";
    ui_type = "slider";
> = 0.04;

uniform float banding_depth <
    ui_category = "色带分析";
    ui_label = "色带深度";
    ui_max = 1.0;
    ui_min = 0.0;
    ui_step = 0.001;
    ui_tooltip = "低于此深度阈值的像素不会被处理，直接返回原样。";
    ui_type = "slider";
> = 1.0;

uniform float range <
    ui_category = "色带检测和去除";
    ui_label = "半径";
    ui_max = 32.0;
    ui_min = 1.0;
    ui_step = 1.0;
    ui_tooltip = "每次迭代半径线性增加。较高的半径会发现更多渐变，但较低的半径会更积极地平滑。";
    ui_type = "slider";
> = 24.0;

uniform int iterations <
    ui_category = "色带检测和去除";
    ui_label = "迭代次数";
    ui_max = 4;
    ui_min = 1;
    ui_tooltip = "每个样本执行的去色带步骤数。每一步减少更多色带，但需要计算时间。";
    ui_type = "slider";
> = 1;

uniform int debug_output <
    ui_category = "调试";
    ui_items = "无\0模糊(LPF)图像\0色带图\0";
    ui_label = "调试视图";
    ui_tooltip = "模糊(LPF)图像：调整半径和迭代次数时很有用，确保所有色带区域都足够模糊。\n色带图：调整分析参数时很有用，连续的绿色区域表示平坦（即色带）区域。";
    ui_type = "combo";
> = 0;

// Reshade uses C rand for random, max cannot be larger than 2^15-1
uniform int drandom < source = "random"; min = 0; max = 32767; >;

float rand(float x)
{
    return frac(x / 41.0);
}

float permute(float x)
{
    return ((34.0 * x + 1.0) * x) % 289.0;
}

float3 PS_Deband(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 ori = tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0.0, 0.0)).rgb;

    if (enable_depthbuffer && (ReShade::GetLinearizedDepth(texcoord) < banding_depth))
        return ori;

    // Initialize the PRNG by hashing the position + a random uniform
    float3 m = float3(texcoord + 1.0, (drandom / 32767.0) + 1.0);
    float h = permute(permute(permute(m.x) + m.y) + m.z);

    // Compute a random angle
    float dir  = rand(permute(h)) * 6.2831853;
    float2 o;
    sincos(dir, o.y, o.x);
    
    // Distance calculations
    float2 pt;
    float dist;

    for (int i = 1; i <= iterations; ++i) {
        dist = rand(h) * range * i;
        pt = dist * BUFFER_PIXEL_SIZE;
    
        h = permute(h);
    }
    
    // Sample at quarter-turn intervals around the source pixel
    float3 ref[4] = {
        tex2Dlod(ReShade::BackBuffer, float4(mad(pt,                  o, texcoord), 0.0, 0.0)).rgb, // SE
        tex2Dlod(ReShade::BackBuffer, float4(mad(pt,                 -o, texcoord), 0.0, 0.0)).rgb, // NW
        tex2Dlod(ReShade::BackBuffer, float4(mad(pt, float2(-o.y,  o.x), texcoord), 0.0, 0.0)).rgb, // NE
        tex2Dlod(ReShade::BackBuffer, float4(mad(pt, float2( o.y, -o.x), texcoord), 0.0, 0.0)).rgb  // SW
    };

    // Calculate weber ratio
    float3 mean = (ori + ref[0] + ref[1] + ref[2] + ref[3]) * 0.2;
    float3 k = abs(ori - mean);
    for (int j = 0; j < 4; ++j) {
        k += abs(ref[j] - mean);
    }

    k = k * 0.2 / mean;

    // Calculate std. deviation
    float3 sd = 0.0;

    for (int j = 0; j < 4; ++j) {
        sd += pow(ref[j] - ori, 2);
    }

    sd = sqrt(sd * 0.25);

    // Generate final output
    float3 output;

    if (debug_output == 2)
        output = float3(0.0, 1.0, 0.0);
    else
        output = (ref[0] + ref[1] + ref[2] + ref[3]) * 0.25;

    // Generate a binary banding map
    bool3 banding_map = true;

    if (debug_output != 1) {
        if (enable_weber)
            banding_map = banding_map && k <= t2 * iterations;

        if (enable_sdeviation)
            banding_map = banding_map && sd <= t1 * iterations;
    }

	/*------------------------.
	| :: Ordered Dithering :: |
	'------------------------*/
	//Calculate grid position
	float grid_position = frac(dot(texcoord, (BUFFER_SCREEN_SIZE * float2(1.0 / 16.0, 10.0 / 36.0)) + 0.25));

	//Calculate how big the shift should be
	float dither_shift = 0.25 * (1.0 / (pow(2, BUFFER_COLOR_BIT_DEPTH) - 1.0));

	//Shift the individual colors differently, thus making it even harder to see the dithering pattern
	float3 dither_shift_RGB = float3(dither_shift, -dither_shift, dither_shift); //subpixel dithering

	//modify shift acording to grid position.
	dither_shift_RGB = lerp(2.0 * dither_shift_RGB, -2.0 * dither_shift_RGB, grid_position); //shift acording to grid position.
    
    return banding_map ? output + dither_shift_RGB : ori;
}

technique Deband <
ui_tooltip = "通过尝试近似原始颜色值来缓解色带问题。";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Deband;
    }
}