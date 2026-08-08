#ifndef _BIND_SHADER_PARAMS_H
#define _BIND_SHADER_PARAMS_H

/////////////////////////////  GPL LICENSE NOTICE  /////////////////////////////

//  crt-royale: A full-featured CRT shader, with cheese.
//  Copyright (C) 2014 TroggleMonkey <trogglemonkey@gmx.com>
//
//  crt-royale-reshade: A port of TroggleMonkey's crt-royale from libretro to ReShade.
//  Copyright (C) 2020 Alex Gunter <akg7634@gmail.com>
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along with
//  this program; if not, write to the Free Software Foundation, Inc., 59 Temple
//  Place, Suite 330, Boston, MA 02111-1307 USA


/////////////////////////////  SETTINGS MANAGEMENT  ////////////////////////////

///////////////////////////////  BEGIN INCLUDES  ///////////////////////////////
#include "helper-functions-and-macros.fxh"
#include "user-settings.fxh"
#include "derived-settings-and-constants.fxh"
#include "../version-number.fxh"

////////////////////////////////  END INCLUDES  ////////////////////////////////

//  Override some parameters for gamma-management.h and tex2Dantialias.h:
#ifndef _OVERRIDE_DEVICE_GAMMA
    #define _OVERRIDE_DEVICE_GAMMA 1
#endif

#if __RENDERER__ != 0x9000
    #define _DX9_ACTIVE 0
#else
    #define _DX9_ACTIVE 1
#endif

// #ifndef ANTIALIAS_OVERRIDE_BASICS
//     #define ANTIALIAS_OVERRIDE_BASICS 1
// #endif

// #ifndef ANTIALIAS_OVERRIDE_PARAMETERS
//     #define ANTIALIAS_OVERRIDE_PARAMETERS 1
// #endif

#ifndef ADVANCED_SETTINGS
    #define ADVANCED_SETTINGS 0
#endif 

// The width of the game's content
#ifndef CONTENT_WIDTH
	#define CONTENT_WIDTH BUFFER_WIDTH
#endif
// The height of the game's content
#ifndef CONTENT_HEIGHT
	#define CONTENT_HEIGHT BUFFER_HEIGHT
#endif

#if ADVANCED_SETTINGS == 1
    // Using vertex uncropping is marginally faster, but vulnerable to DX9 weirdness.
    // Most users will likely prefer the slower algorithm.
    #ifndef USE_VERTEX_UNCROPPING
        #define USE_VERTEX_UNCROPPING 0
    #endif

    #ifndef NUM_BEAMDIST_COLOR_SAMPLES
        #define NUM_BEAMDIST_COLOR_SAMPLES 1024
    #endif

    #ifndef NUM_BEAMDIST_DIST_SAMPLES
        #define NUM_BEAMDIST_DIST_SAMPLES 120
    #endif

    #ifndef BLOOMAPPROX_DOWNSIZING_FACTOR
        #define BLOOMAPPROX_DOWNSIZING_FACTOR 4.0
    #endif

    // Define this internal value, so ADVANCED_SETTINGS == 0 doesn't cause a redefinition error when
    //   NUM_BEAMDIST_COLOR_SAMPLES defined in the preset file. Also makes it easy to avoid bugs
    //   related to parentheses and order-of-operations when the user defines this arithmetically.
    static const uint num_beamdist_color_samples = uint(NUM_BEAMDIST_COLOR_SAMPLES);
    static const uint num_beamdist_dist_samples = uint(NUM_BEAMDIST_DIST_SAMPLES);
    static const float bloomapprox_downsizing_factor = float(BLOOMAPPROX_DOWNSIZING_FACTOR);
#else
    static const uint USE_VERTEX_CROPPING = 0;
    static const uint num_beamdist_color_samples = 1024;
    static const uint num_beamdist_dist_samples = 120;
    static const float bloomapprox_downsizing_factor = 4.0;
#endif

#ifndef HIDE_HELP_SECTIONS
    #define HIDE_HELP_SECTIONS 0
#endif


// Offset the center of the game's content (horizontal)
#ifndef CONTENT_CENTER_X
	#define CONTENT_CENTER_X 0
#endif
// Offset the center of the game's content (vertical)
#ifndef CONTENT_CENTER_Y
	#define CONTENT_CENTER_Y 0
#endif

// Wrap the content size in parenthesis for internal use, so the user doesn't have to
static const float2 content_size = float2(int(CONTENT_WIDTH), int(CONTENT_HEIGHT));

#ifndef ENABLE_PREBLUR
    #define ENABLE_PREBLUR 1
#endif


static const float2 buffer_size = float2(BUFFER_WIDTH, BUFFER_HEIGHT);


// The normalized center is 0.5 plus the normalized offset
static const float2 content_center = float2(CONTENT_CENTER_X, CONTENT_CENTER_Y) / buffer_size + 0.5;
// The content's normalized diameter d is its size divided by the buffer's size. The radius is d/2.
static const float2 content_radius = content_size / (2.0 * buffer_size);
static const float2 content_scale = content_size / buffer_size;

static const float content_left = content_center.x - content_radius.x;
static const float content_right = content_center.x + content_radius.x;
static const float content_upper = content_center.y - content_radius.y;
static const float content_lower = content_center.y + content_radius.y;

// The xy-offset of the top-left pixel in the content box
static const float2 content_offset = float2(content_left, content_upper);
static const float2 content_offset_from_right = float2(content_right, content_lower);

uniform uint frame_count < source = "framecount"; >;
uniform int overlay_active < source = "overlay_active"; >;

static const float gba_gamma = 3.5; //  Irrelevant but necessary to define.


// === HELP AND INFO ===

uniform int APPEND_VERSION_SUFFIX(version) <
	ui_text = "Version: " DOT_VERSION_STR;
	ui_label = " ";
	ui_type = "radio";
>;

uniform int basic_setup_help <
	ui_text = "1. 如果您的游戏有黑边，请配置内容框。\n"
			  "2. 配置荧光粉遮罩。\n"
              "3. 配置扫描线。\n"
              "4. 配置颜色和效果。\n"
              "5. 配置屏幕几何。\n"
              "6. 配置或禁用预模糊\n\n"
              "- 在预处理器定义中，将 ADVANCED_SETTINGS 设为 1 以访问更多设置。\n";
	ui_category = "基本设置说明";
    ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
    hidden = HIDE_HELP_SECTIONS;
>;

uniform int content_box_help <
	ui_text = "1. 展开预处理器定义部分。\n"
              "2. 将 CONTENT_BOX_VISIBLE 设为 1。\n"
              "3. 使用 \"CONTENT_\" 参数配置内容框。\n"
			  "4. 将内容框与游戏边框对齐。\n"
              "5. 完成后将 CONTENT_BOX_VISIBLE 设为 0。\n\n"
              "需要关注的参数：\n"
              "- CONTENT_HEIGHT 和 CONTENT_WIDTH\n"
              "- CONTENT_CENTER_X 和 CONTENT_CENTER_Y\n"
              "- CONTENT_BOX_INSCRIBED\n\n"
              "技巧 1：\n"
              "\tCONTENT_HEIGHT = BUFFER_HEIGHT\n"
              "\tCONTENT_WIDTH = CONTENT_HEIGHT * 4.0 / 3.0\n"
              "- 适用于游戏垂直填满屏幕且宽高比为 4:3 的情况。\n"
              "- 调整窗口大小时会自动重新缩放。\n\n"
              "技巧 2：\n"
              "\tCONTENT_HEIGHT = CONTENT_WIDTH * 9.0 / 16.0\n"
              "\tCONTENT_WIDTH = 1500\n"
              "- 适用于游戏宽度为 1500 像素且宽高比为 16:9 的情况。\n"
              "- 不会自动重新缩放，但您只需更改宽度即可。\n";
	ui_category = "内容框设置说明";
    ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
    hidden = HIDE_HELP_SECTIONS;
>;


// ==== PHOSPHOR MASK ====
uniform int mask_type <
        #if !HIDE_HELP_SECTIONS
        ui_text    = "选择您想要的阴极射线管类型。\n\n";
        #endif
        ui_label   = "遮罩类型";
        ui_tooltip = "选择荧光粉形状";
        ui_type    = "combo";
        ui_items   = "栅格\0"
                    "槽孔\0"
                    "荫罩\0"
                    "低分辨率栅格\0"
                    "低分辨率槽孔\0"
                    "低分辨率荫罩\0";

    ui_category = "荧光粉遮罩";
    ui_category_closed = true;
> = mask_type_static;

uniform uint mask_size_param <
        ui_label   = "遮罩尺寸参数";
        ui_tooltip = "在使用遮罩三元组尺寸或遮罩三元组数量之间切换";
        ui_type    = "combo";
        ui_items   = "三元组宽度\0"
                    "横向三元组数量\0";
        hidden     = !ADVANCED_SETTINGS;

    ui_spacing = 2;
    ui_category = "荧光粉遮罩";
> = mask_size_param_static;

uniform float mask_triad_width <
        ui_label   = "遮罩三元组宽度";
        ui_tooltip = "三元组的像素宽度";
        ui_type    = "slider";
        ui_min     = 1.0;
        ui_max     = 60.0;
        ui_step    = 0.1;

    ui_category = "荧光粉遮罩";
> = mask_triad_width_static;

uniform float mask_num_triads_across <
        ui_label   = "横向遮罩三元组数量";
        ui_tooltip = "视口中水平方向的三元组数量";
        ui_type    = "drag";
        ui_min     = 1.0;
        ui_max     = 1280.0;
        ui_step    = 1.0;
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "荧光粉遮罩";
> = mask_num_triads_across_static;

uniform float scale_triad_height<
        ui_label   = "三元组高度缩放";
        ui_tooltip = "缩放三元组的高度";
        ui_type    = "drag";
        ui_min     = 0.01;
        ui_max     = 10.0;
        ui_step    = 0.001;

    ui_spacing = 2;
    ui_category = "荧光粉遮罩";
> = 1.0;

uniform float2 phosphor_thickness <
        ui_label   = "荧光粉厚度 XY";
        ui_tooltip = "使荧光粉在各方向显得更厚";
        ui_type    = "drag";
        ui_min     = 0.01;
        ui_max     = 0.99;
        ui_step    = 0.01;
        // hidden     = !ADVANCED_SETTINGS;

    ui_category = "荧光粉遮罩";
> = 0.2;

uniform float2 phosphor_sharpness <
        ui_label   = "荧光粉锐度 XY";
        ui_tooltip = "使荧光粉在各方向显得更清晰";
        ui_type    = "drag";
        ui_min     = 1;
        ui_max     = 100;
        ui_step    = 1;
        // hidden     = !ADVANCED_SETTINGS;

    ui_category = "荧光粉遮罩";
> = 50;

uniform float3 phosphor_offset_x <
        ui_label   = "荧光粉偏移 RGB X";
        ui_tooltip = "微调荧光粉遮罩位置，有助于亚像素对齐。";
        ui_type    = "drag";
        ui_min     = -1;
        ui_max     = 1;
        ui_step    = 0.01;
        // hidden     = !ADVANCED_SETTINGS;

    ui_spacing = 2;
    ui_category = "荧光粉遮罩";
> = 0;

uniform float3 phosphor_offset_y <
        ui_label   = "荧光粉偏移 RGB Y";
        ui_tooltip = "微调荧光粉遮罩位置，有助于亚像素对齐。";
        ui_type    = "drag";
        ui_min     = -1;
        ui_max     = 1;
        ui_step    = 0.01;
        // hidden     = !ADVANCED_SETTINGS;

    ui_category = "荧光粉遮罩";
> = 0;

// static const uint pixel_grid_mode = 0;
// static const float2 pixel_size = 1;
/*
// ==== PIXELATION ===
uniform uint pixel_grid_mode <
        #if !HIDE_HELP_SECTIONS
        ui_text    = "- Fix issues displaying pixel art.\n"
                     "- Force high-res games to look low-res.\n\n";
        #endif
        ui_label   = "Pixel Grid Param";
        ui_tooltip = "Switch between using Pixel Size or Num Pixels";
        ui_type    = "combo";
        ui_items   = "Pixel Size\0"
                    "Content Resolution\0";
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "Pixelation";
    ui_category_closed = true;
> = 0;

uniform float2 pixel_size <
        #if !HIDE_HELP_SECTIONS && !ADVANCED_SETTINGS
        ui_text    = "- Fix issues displaying pixel art.\n"
                     "- Force high-res games to look low-res.\n\n";
        #endif
        ui_label   = "Pixel Size";
        ui_tooltip = "The size of an in-game pixel on screen, in real-world pixels";
        ui_type    = "slider";
        ui_min     = 1.0;
        ui_max     = 30.0;
        ui_step    = 1.0;

    ui_category = "Pixelation";
    ui_category_closed = true;
> = float2(1, 1);

uniform float2 pixel_grid_resolution <
        ui_label   = "Num Pixels";
        ui_tooltip = "The number of in-game pixels displayed on-screen in each direction";
        ui_type    = "drag";
        ui_min     = 1.0;
        ui_max     = 10000.0;
        ui_step    = 1.0;
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "Pixelation";
> = content_size;
uniform float2 pixel_grid_offset <
        ui_label   = "Pixel Grid Offset";
        ui_tooltip = "Shifts the pixel-grid to help with alignment";
        ui_type    = "slider";
        ui_min     = -15.0;
        ui_max     = 15.0;
        ui_step    = 1.0;

    #if ADVANCED_SETTINGS
    ui_spacing = 2;
    #endif
    ui_category = "Pixelation";
> = float2(0, 0);
*/

// ==== SCANLINES ====
uniform uint scanline_thickness <
        #if !HIDE_HELP_SECTIONS
        ui_text    = "配置电子束和隔行扫描。\n\n";
        #endif
        ui_label   = "扫描线厚度";
        ui_tooltip = "设置每条扫描线的高度";
        ui_type    = "slider";
        ui_min     = 1;
        ui_max     = 30;
        ui_step    = 1;

    ui_category = "扫描线";
    ui_category_closed = true;
> = 2;

uniform float scanline_offset <
        ui_label   = "扫描线偏移";
        ui_tooltip = "垂直移动扫描线以帮助对齐";
        ui_type    = "slider";
        ui_min     = -30;
        ui_max     = 30;
        ui_step    = 1;
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "扫描线";
> = 0;

uniform uint beam_shape_mode <
        ui_label   = "电子束形状模式";
        ui_tooltip = "选择要使用的电子束类型。";
        ui_type    = "combo";
        ui_items   = "数字（快速）\0"
                    "线性（简单）\0"
                    "高斯（逼真）\0"
                    "多源高斯（高开销）\0";

    ui_category = "扫描线";
> = 1;

uniform bool enable_interlacing <
        ui_label   = "启用隔行扫描";

    ui_spacing = 5;
    ui_category = "扫描线";
> = false;

uniform bool interlace_back_field_first <
        ui_label   = "先绘制后场";
        ui_tooltip = "先绘制奇数扫描线（通常无效果）";

    ui_category = "扫描线";
> = interlace_back_field_first_static;

uniform uint scanline_deinterlacing_mode <
        ui_label   = "去隔行模式";
        ui_tooltip = "选择去隔行算法（如果需要）。";
        ui_type    = "combo";
        ui_items   = "无\0"
                     "伪逐行\0"
                     "编织\0"
                     "混合编织\0";

    ui_category = "扫描线";
> = 1;

uniform float deinterlacing_blend_gamma <
        ui_label   = "去隔行混合伽马";
        ui_tooltip = "如果去隔行过多改变颜色，请调整此值";
        ui_type    = "slider";
        ui_min     = 0.01;
        ui_max     = 5.0;
        ui_step    = 0.01;

    ui_category = "扫描线";
> = 1.0;

uniform float linear_beam_thickness <
        ui_label   = "线性电子束厚度";
        ui_tooltip = "线性加宽或缩窄电子束";
        ui_type    = "slider";
        ui_min     = 0.01;
        ui_max     = 3.0;
        ui_step    = 0.01;

    ui_spacing = 5;
    ui_category = "扫描线";
> = 1.0;

uniform float gaussian_beam_min_sigma <
        ui_label   = "高斯电子束最小Sigma";
        ui_tooltip = "对于高斯电子束形状，设置暗像素的厚度";
        ui_type    = "drag";
        ui_min     = 0.0;
        ui_step    = 0.01;

    ui_spacing = 5;
    ui_category = "扫描线";
> = gaussian_beam_min_sigma_static;

uniform float gaussian_beam_max_sigma <
        ui_label   = "高斯电子束最大Sigma";
        ui_tooltip = "对于高斯电子束形状，设置亮像素的厚度";
        ui_type    = "drag";
        ui_min     = 0.0;
        ui_step    = 0.01;

    ui_category = "扫描线";
> = gaussian_beam_max_sigma_static;

uniform float gaussian_beam_spot_power <
        ui_label   = "高斯电子束光斑功率";
        ui_tooltip = "对于高斯电子束形状，平衡最小和最大Sigma";
        ui_type    = "drag";
        ui_min     = 0.0;
        ui_step    = 0.01;

    ui_category = "扫描线";
> = gaussian_beam_spot_power_static;

uniform float gaussian_beam_min_shape <
        ui_label   = "高斯电子束最小形状";
        ui_tooltip = "对于高斯电子束形状，设置暗像素的锐度";
        ui_type    = "drag";
        ui_min     = 0.0;
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS;

    ui_spacing = 2;
    ui_category = "扫描线";
> = gaussian_beam_min_shape_static;

uniform float gaussian_beam_max_shape <
        ui_label   = "高斯电子束最大形状";
        ui_tooltip = "对于高斯电子束形状，设置亮像素的锐度";
        ui_type    = "drag";
        ui_min     = 0.0;
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "扫描线";
> = gaussian_beam_max_shape_static;

uniform float gaussian_beam_shape_power <
        ui_label   = "高斯电子束形状功率";
        ui_tooltip = "对于高斯电子束形状，平衡最小和最大形状";
        ui_type    = "drag";
        ui_min     = 0.0;
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "扫描线";
> = gaussian_beam_shape_power_static;

uniform float3 convergence_offset_x <
        ui_label   = "会聚偏移 X RGB";
        ui_tooltip = "水平移动颜色通道";
        ui_type    = "drag";
        ui_min     = -10;
        ui_max     = 10;
        ui_step    = 0.05;
        hidden     = !ADVANCED_SETTINGS;

    ui_spacing = 5;
    ui_category = "扫描线";
> = 0;
uniform float3 convergence_offset_y <
        ui_label   = "会聚偏移 Y RGB";
        ui_tooltip = "垂直移动颜色通道";
        ui_type    = "drag";
        ui_min     = -10;
        ui_max     = 10;
        ui_step    = 0.05;
        hidden     = !ADVANCED_SETTINGS;
    ui_category = "扫描线";
> = 0;

static uint beam_horiz_filter = beam_horiz_filter_static;
static float beam_horiz_sigma = beam_horiz_sigma_static;
static float beam_horiz_linear_rgb_weight = beam_horiz_linear_rgb_weight_static;

// ==== IMAGE COLORIZATION ====
uniform float crt_gamma <
        #if !HIDE_HELP_SECTIONS
        ui_text    = "应用伽马、对比度和模糊。\n\n";
        #endif
        ui_label   = "阴极射线管伽马";
        ui_tooltip = "原始内容的伽马级别";
        ui_type    = "slider";
        ui_min     = 1.0;
        ui_max     = 5.0;
        ui_step    = 0.01;

    ui_category = "颜色和效果";
    ui_category_closed = true;
> = crt_gamma_static;

uniform float lcd_gamma <
        ui_label   = "液晶屏伽马";
        ui_tooltip = "您显示器的伽马级别";
        ui_type    = "slider";
        ui_min     = 1.0;
        ui_max     = 5.0;
        ui_step    = 0.01;

    ui_category = "颜色和效果";
> = lcd_gamma_static;

uniform float levels_contrast <
        ui_label   = "色阶对比度";
        ui_tooltip = "设置阴极射线管的对比度";
        ui_type    = "slider";
        ui_min     = 0.0;
        ui_max     = 4.0;
        ui_step    = 0.01;

    ui_spacing = 5;
    ui_category = "颜色和效果";
> = levels_contrast_static;

uniform float halation_weight <
        ui_label   = "光晕";
        ui_tooltip = "由于电子激发错误荧光粉导致的去饱和";
        ui_type    = "slider";
        ui_min     = 0.0;
        ui_max     = 1.0;
        ui_step    = 0.01;

    ui_spacing = 2;
    ui_category = "颜色和效果";
> = halation_weight_static;

uniform float diffusion_weight <
        ui_label   = "扩散";
        ui_tooltip = "由于屏幕玻璃折射导致的模糊";
        ui_type    = "slider";
        ui_min     = 0.0;
        ui_max     = 1.0;
        ui_step    = 0.01;

    ui_category = "颜色和效果";
> = diffusion_weight_static;

uniform float blur_radius <
        ui_label   = "模糊半径";
        ui_tooltip = "缩放光晕和扩散效果的半径";
        ui_type    = "slider";
        ui_min     = 0.01;
        ui_max     = 5.0;
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "颜色和效果";
> = 1.0;

uniform float bloom_underestimate_levels <
        ui_label   = "泛光低估";
        ui_tooltip = "缩放泛光效果的强度";
        ui_type    = "drag";
        ui_min     = FIX_ZERO(0.0);
        ui_step    = 0.01;

    ui_spacing = 2;
    ui_category = "颜色和效果";
> = bloom_underestimate_levels_static;

uniform float bloom_excess <
        ui_label   = "泛光过量";
        ui_tooltip = "应用于所有颜色的额外泛光";
        ui_type    = "slider";
        ui_min     = 0.0;
        ui_max     = 1.0;
        ui_step    = 0.01;

    ui_category = "颜色和效果";
> = bloom_excess_static;

uniform float2 aa_subpixel_r_offset_runtime <
        ui_label   = "抗锯齿亚像素R偏移 XY";
        ui_type    = "drag";
        ui_min     = -0.5;
        ui_max     = 0.5;
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS || !_RUNTIME_ANTIALIAS_SUBPIXEL_OFFSETS;

    ui_category = "颜色和效果";
> = aa_subpixel_r_offset_static;

static const float aa_cubic_c = aa_cubic_c_static;
static const float aa_gauss_sigma = aa_gauss_sigma_static;


// ==== GEOMETRY ====
uniform uint geom_rotation_mode <
        #if !HIDE_HELP_SECTIONS
        ui_text    = "更改屏幕玻璃的几何形状。\n\n";
        #endif
        ui_label   = "旋转屏幕";
        ui_type    = "combo";
        ui_items   = "0 度\0"
                     "90 度\0"
                     "180 度\0"
                     "270 度\0";

    ui_category = "屏幕几何";
    ui_category_closed = true;
> = 0;
uniform uint geom_mode_runtime <
        ui_label   = "几何模式";
        ui_tooltip = "选择屏幕曲率类型";
        ui_type    = "combo";
        ui_items   = "平面\0"
                    "球面\0"
                    "球面（替代）\0"
                    "柱面（特丽珑）\0";

    ui_category = "屏幕几何";
> = geom_mode_static;

uniform float geom_radius <
        ui_label   = "几何半径";
        ui_tooltip = "选择屏幕曲率半径";
        ui_type    = "slider";
        ui_min     = 1.0 / (2.0 * pi);
        ui_max     = 1024;
        ui_step    = 0.01;

    ui_category = "屏幕几何";
> = geom_radius_static;

uniform float geom_view_dist <
        ui_label   = "观看距离";
        ui_type    = "slider";
        ui_min     = 0.5;
        ui_max     = 1024;
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS;

    ui_spacing = 2;
    ui_category = "屏幕几何";
> = geom_view_dist_static;

uniform float2 geom_tilt_angle <
        ui_label   = "屏幕倾斜角度";
        ui_type    = "drag";
        ui_min     = -pi;
        ui_max     = pi;
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "屏幕几何";
> = geom_tilt_angle_static;

uniform float2 geom_aspect_ratio <
        ui_label   = "屏幕宽高比";
        ui_type    = "drag";
        ui_min     = 1.0;
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS;

    ui_category = "屏幕几何";
> = float2(geom_aspect_ratio_static, 1);
uniform float2 geom_overscan <
        ui_label   = "几何过扫描";
        ui_type    = "drag";
        ui_min     = FIX_ZERO(0.0);
        ui_step    = 0.01;
        hidden     = !ADVANCED_SETTINGS;

    ui_spacing = 2;
    ui_category = "屏幕几何";
> = geom_overscan_static;

// ==== BORDER ====
uniform float border_size <
        #if !HIDE_HELP_SECTIONS
        ui_text    = "在屏幕边缘应用薄晕影。\n\n";
        #endif
        ui_label   = "边框尺寸";
        ui_category_closed = true;
        ui_type    = "slider";
        ui_min     = 0.0;
        ui_max     = 0.5;
        ui_step    = 0.01;

    ui_category = "屏幕边框";
> = border_size_static;

uniform float border_darkness <
        ui_label   = "边框暗度";
        ui_type    = "drag";
        ui_min     = 0.0;
        ui_step    = 0.01;

    ui_category = "屏幕边框";
> = border_darkness_static;

uniform float border_compress <
        ui_label   = "边框压缩";
        ui_type    = "drag";
        ui_min     = 0.0;
        ui_step    = 0.01;

    ui_category = "屏幕边框";
> = border_compress_static;

// ==== PREBLUR ====
#if ENABLE_PREBLUR
    uniform float2 preblur_effect_radius <
            #if !HIDE_HELP_SECTIONS
            ui_text    = "- 对输入图像应用线性模糊。类似于NTSC/复合视频着色器，但速度更快。\n"
                         "- 如果您想使用NTSC着色器或不喜欢此效果，请将ENABLE_PREBLUR设为0来禁用。\n"
                         "- 如果所有这些值都设为0，则不会产生任何效果。考虑禁用此效果以提高性能。\n\n";
            #endif
            ui_type    = "drag";
            ui_min     = 0;
            ui_max     = 100;
            ui_step    = 1;
            ui_label   = "效果半径 XY";
            ui_tooltip = "屏幕上可见效果的半径（以像素为单位）";

        ui_category   = "预模糊";
        ui_category_closed = true;
    > = 0;
    uniform uint2 preblur_sampling_radius <
            ui_type = "drag";
            ui_min = 0;
            ui_max = 100;
            ui_step = 1;
            ui_label = "采样半径 XY";
            ui_tooltip = "每个像素两侧采样的数量";

        ui_category   = "预模糊";
    > = 0;
#else
    static const float2 preblur_effect_radius = 0;
    static const uint2 preblur_sampling_radius = 0;
#endif

//  Provide accessors for vector constants that pack scalar uniforms:
float2 get_aspect_vector(const float geom_aspect_ratio)
{
    //  Get an aspect ratio vector.  Enforce geom_max_aspect_ratio, and prevent
    //  the absolute scale from affecting the uv-mapping for curvature:
    const float geom_clamped_aspect_ratio =
        min(geom_aspect_ratio, geom_max_aspect_ratio);
    const float2 geom_aspect =
        normalize(float2(geom_clamped_aspect_ratio, 1.0));
    return geom_aspect;
}

float2 get_geom_overscan_vector()
{
    return geom_overscan;
}

float2 get_geom_tilt_angle_vector()
{
    return geom_tilt_angle;
}

float3 get_convergence_offsets_x_vector()
{
    return convergence_offset_x;
}

float3 get_convergence_offsets_y_vector()
{
    return convergence_offset_y;
}

float2 get_convergence_offsets_r_vector()
{
    return float2(convergence_offset_x.r, convergence_offset_y.r);
}

float2 get_convergence_offsets_g_vector()
{
    return float2(convergence_offset_x.g, convergence_offset_y.g);
}

float2 get_convergence_offsets_b_vector()
{
    return float2(convergence_offset_x.b, convergence_offset_y.b);
}

float2 get_aa_subpixel_r_offset()
{
    #if _RUNTIME_ANTIALIAS_WEIGHTS
        #if _RUNTIME_ANTIALIAS_SUBPIXEL_OFFSETS
            //  WARNING: THIS IS EXTREMELY EXPENSIVE.
            return aa_subpixel_r_offset_runtime;
        #else
            return aa_subpixel_r_offset_static;
        #endif
    #else
        return aa_subpixel_r_offset_static;
    #endif
}

//  Provide accessors settings which still need "cooking:"
float get_mask_amplify()
{
    static const float mask_grille_amplify = 1.0/mask_grille_avg_color;
    static const float mask_slot_amplify = 1.0/mask_slot_avg_color;
    static const float mask_shadow_amplify = 1.0/mask_shadow_avg_color;

    float mask_amplify;
    [flatten]
    switch (mask_type) {
        case 0:
            mask_amplify = mask_grille_amplify;
            break;
        case 1:
            mask_amplify = mask_slot_amplify;
            break;
        case 2:
            mask_amplify = mask_shadow_amplify;
            break;
        case 3:
            mask_amplify = mask_grille_amplify;
            break;
        case 4:
            mask_amplify = mask_slot_amplify;
            break;
        default:
            mask_amplify = mask_shadow_amplify;
            break;
                    
    }
    
    return mask_amplify;
}

#endif  //  _BIND_SHADER_PARAMS_H