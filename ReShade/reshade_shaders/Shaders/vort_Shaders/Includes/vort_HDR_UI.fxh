/*******************************************************************************
    Author: Vortigern

    License: MIT, Copyright (c) 2023 Vortigern

    MIT License

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*******************************************************************************/

#pragma once

#ifndef V_ENABLE_BLOOM
    #define V_ENABLE_BLOOM 0
#endif

#ifndef V_ENABLE_SHARPEN
    #define V_ENABLE_SHARPEN 0
#endif

#ifndef V_ENABLE_COLOR_GRADING
    #define V_ENABLE_COLOR_GRADING 0
#endif

#ifndef V_ENABLE_PALETTE
    #define V_ENABLE_PALETTE 0
#endif

#if IS_SRGB
    #ifndef V_ENABLE_LUT
        #define V_ENABLE_LUT 0
    #endif
#else
    #undef V_ENABLE_LUT
    #define V_ENABLE_LUT 0
#endif

#if V_ENABLE_BLOOM
    #ifndef V_BLOOM_DEBUG
        #define V_BLOOM_DEBUG 0
    #endif
#endif

UI_FLOAT("", UI_Tonemap_Mod, "色调映射调整", "较低的值增加HDR范围", 1.001, 1.5, 1.04)

#if V_ENABLE_LUT
    #define CAT_LUT "LUT设置"

    UI_LIST(CAT_LUT, UI_CC_LUTNum, "LUT名称", "使用哪个LUT", " Agfa_Precisa_100\0 Agfa_Ultra_Color_100\0 Agfa_Vista_200\0 Creative_Anime\0 Creative_BleachBypass1\0 Creative_BleachBypass2\0 Creative_BleachBypass3\0 Creative_BleachBypass4\0 Creative_CandleLight\0 Creative_ColorNegative\0 Creative_CrispWarm\0 Creative_CrispWinter\0 Creative_DropBlues\0 Creative_EdgyEmber\0 Creative_FallColors\0 Creative_FoggyNight\0 Creative_FuturisticBleak1\0 Creative_FuturisticBleak2\0 Creative_FuturisticBleak3\0 Creative_FuturisticBleak4\0 Creative_HorrorBlue\0 Creative_LateSunset\0 Creative_Moonlight\0 Creative_NightFromDay\0 Creative_RedBlueYellow\0 Creative_Smokey\0 Creative_SoftWarming\0 Creative_TealMagentaGold\0 Creative_TealOrange\0 Creative_TealOrange1\0 Creative_TealOrange2\0 Creative_TealOrange3\0 Creative_TensionGreen1\0 Creative_TensionGreen2\0 Creative_TensionGreen3\0 Creative_TensionGreen4\0 Fuji_160C\0 Fuji_400H\0 Fuji_800Z\0 Fuji_Astia_100F\0 Fuji_Astia_100_Generic\0 Fuji_FP-100c\0 Fuji_FP-100c_Cool\0 Fuji_FP-100c_Negative\0 Fuji_Provia_100F\0 Fuji_Provia_100_Generic\0 Fuji_Provia_400F\0 Fuji_Provia_400X\0 Fuji_Sensia_100\0 Fuji_Superia_100\0 Fuji_Superia_1600\0 Fuji_Superia_200\0 Fuji_Superia_200_XPRO\0 Fuji_Superia_400\0 Fuji_Superia_800\0 Fuji_Superia_HG_1600\0 Fuji_Superia_Reala_100\0 Fuji_Superia_X-Tra_800\0 Fuji_Velvia_100_Generic\0 Fuji_Velvia_50\0 Kodak_E-100_GX_Ektachrome_100\0 Kodak_Ektachrome_100_VS\0 Kodak_Ektachrome_100_VS_Generic\0 Kodak_Ektar_100\0 Kodak_Elite_100_XPRO\0 Kodak_Elite_Chrome_200\0 Kodak_Elite_Chrome_400\0 Kodak_Elite_Color_200\0 Kodak_Elite_Color_400\0 Kodak_Elite_ExtraColor_100\0 Kodak_Kodachrome_200\0 Kodak_Kodachrome_25\0 Kodak_Kodachrome_64\0 Kodak_Kodachrome_64_Generic\0 Kodak_Portra_160\0 Kodak_Portra_160_NC\0 Kodak_Portra_160_VC\0 Kodak_Portra_400\0 Kodak_Portra_400_NC\0 Kodak_Portra_400_UC\0 Kodak_Portra_400_VC\0 Kodak_Portra_800\0 Kodak_Portra_800_HC\0 Lomography_Redscale_100\0 Lomography_X-Pro_Slide_200\0 Polaroid_669\0 Polaroid_669_Cold\0 Polaroid_690\0 Polaroid_690_Cold\0 Polaroid_690_Warm\0 Polaroid_Polachrome\0 Polaroid_PX-100UV+_Cold\0 Polaroid_PX-100UV+_Warm\0 Polaroid_PX-680\0 Polaroid_PX-680_Cold\0 Polaroid_PX-680_Warm\0 Polaroid_PX-70\0 Polaroid_PX-70_Cold\0 Polaroid_PX-70_Warm\0", 0)
    UI_FLOAT(CAT_LUT, UI_CC_LUTChroma, "LUT色度", "改变LUT的色度强度", 0.0, 1.0, 1.0)
    UI_FLOAT(CAT_LUT, UI_CC_LUTLuma, "LUT亮度", "改变LUT的亮度强度", 0.0, 1.0, 1.0)
#endif

#if V_ENABLE_PALETTE
    #define CAT_CPS "色彩调色板交换"

    UI_BOOL(CAT_CPS, UI_CPS_ShowPalette, "显示调色板", "在左上角显示颜色", false)
    UI_FLOAT3(CAT_CPS, UI_CPS_HSV, "基础HSV", "基础色相、饱和度和明度", 0.0, 1.0, 0.5)
    UI_LIST(CAT_CPS, UI_CPS_Harmony, "色彩和谐", "使用哪种和谐方式", "类似色\0互补色\0", 1)
    UI_FLOAT(CAT_CPS, UI_CPS_Blend, "混合量", "调色板与图像混合的程度", 0.0, 2.0, 1.0)
#endif

#if V_ENABLE_BLOOM
    #define CAT_BLOOM "泛光"

    UI_FLOAT(CAT_BLOOM, UI_Bloom_Intensity, "泛光强度", "控制泛光的数量", 0.0, 1.0, 0.02)
    UI_FLOAT(CAT_BLOOM, UI_Bloom_Radius, "泛光半径", "影响泛光的大小/缩放", 0.0, 1.0, 0.8)
#endif

#if V_ENABLE_SHARPEN
    #define CAT_SHARP "锐化"

    UI_BOOL(CAT_SHARP, UI_CC_ShowSharpening, "仅显示锐化", "", false)
    UI_FLOAT(CAT_SHARP, UI_CC_SharpenLimit, "锐化限制", "控制要锐化的像素", 0.0, 0.1, 0.02)
    UI_FLOAT(CAT_SHARP, UI_CC_SharpenStrength, "锐化强度", "控制锐化强度", 0.0, 2.0, 1.0)
#endif

#if V_ENABLE_COLOR_GRADING
    #define CAT_CC "色彩分级"

    UI_FLOAT(CAT_CC, UI_CC_WBTemp, "色温", "改变白平衡色温", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_WBTint, "色调偏移", "改变白平衡色调", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_Contrast, "对比度", "改变图像对比度", -1.0, 1.0, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_Saturation, "饱和度", "改变所有颜色的饱和度", -1.0, 1.0, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_HueShift, "色相偏移", "改变所有颜色的色相", -0.5, 0.5, 0.0)
    UI_COLOR(CAT_CC, UI_CC_ColorFilter, "颜色滤镜", "将每个颜色乘以此颜色", 1.0);
    UI_COLOR(CAT_CC, UI_CC_RGBMixerRed, "RGB混合器-红", "修改红色", float3(0.75, 0.5, 0.5))
    UI_COLOR(CAT_CC, UI_CC_RGBMixerGreen, "RGB混合器-绿", "修改绿色", float3(0.5, 0.75, 0.5))
    UI_COLOR(CAT_CC, UI_CC_RGBMixerBlue, "RGB混合器-蓝", "修改蓝色", float3(0.5, 0.5, 0.75))

    UI_FLOAT(CAT_CC, UI_CC_ShadowsLumi, "阴影亮度", "主要改变阴影的亮度", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_MidtonesLumi, "中间调亮度", "主要改变中间调的亮度", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_HighlightsLumi, "高光亮度", "主要改变高光的亮度", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_OffsetLumi, "偏移亮度", "改变整个曲线的亮度", -0.5, 0.5, 0.0)

    UI_COLOR(CAT_CC, UI_CC_ShadowsColor, "阴影颜色", "主要改变阴影的颜色", 0.5)
    UI_COLOR(CAT_CC, UI_CC_MidtonesColor, "中间调颜色", "主要改变中间调的颜色", 0.5)
    UI_COLOR(CAT_CC, UI_CC_HighlightsColor, "高光颜色", "主要改变高光的颜色", 0.5)
    UI_COLOR(CAT_CC, UI_CC_OffsetColor, "偏移颜色", "改变整个曲线的颜色", 0.5)
#endif

UI_HELP(
_vort_HDR_Help_,
"V_ENABLE_BLOOM - 0 或 1\n"
"开关泛光效果。\n"
"\n"
"V_ENABLE_SHARPEN - 0 或 1\n"
"开关锐化和远景模糊。\n"
"\n"
"V_ENABLE_LUT - 0 或 1\n"
"开关LUT的使用\n"
"\n"
"V_ENABLE_PALETTE - 0 或 1\n"
"开关色彩调色板生成\n"
"\n"
"V_ENABLE_COLOR_GRADING - 0 或 1\n"
"开关所有色彩分级效果\n"
"\n"
"V_BLOOM_DEBUG - 0 或 1\n"
"显示4个明亮方块以查看泛光效果并根据需要调整UI。\n"
"\n"
"V_USE_ACES - 0 或 1\n"
"是否使用完整的ACES色调映射器（性能消耗很高）\n"
"\n"
"V_HAS_DEPTH - 0 或 1\n"
"游戏是否有深度（2D或3D游戏）\n"
"\n"
"V_USE_HW_LIN - 0 或 1\n"
"开关硬件线性化（性能更好）。\n"
"如果因某些错误（如旧版REST插件）导致颜色问题，请禁用。\n"
)
