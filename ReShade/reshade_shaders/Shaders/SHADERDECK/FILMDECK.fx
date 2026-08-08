///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///                                                                                             ///
///    8888888888 8888888 888      888b     d888 8888888b.  8888888888  .d8888b.  888    d8P    ///
///    888          888   888      8888b   d8888 888  "Y88b 888        d88P  Y88b 888   d8P     ///
///    888          888   888      88888b.d88888 888    888 888        888    888 888  d8P      ///
///    8888888      888   888      888Y88888P888 888    888 8888888    888        888d88K       ///
///    888          888   888      888 Y888P 888 888    888 888        888        8888888b      ///
///    888          888   888      888  Y8P  888 888    888 888        888    888 888  Y88b     ///
///    888          888   888      888   "   888 888  .d88P 888        Y88b  d88P 888   Y88b    ///
///    888        8888888 88888888 888       888 8888888P"  8888888888  "Y8888P"  888    Y88b   ///
///                                                                                             ///
///    FILM EMULATION SUITE FOR RESHADE                                                         ///
///    <> BY TREYM                                                                              ///
///                                                                                             ///
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////

/*  ///////////////////////////////////////////////////////////////////////////////////////////  **
**  ///////////////////////////////////////////////////////////////////////////////////////////  **

    DO NOT REDISTRIBUTE WITHOUT PERMISION!
    
    Welcome to FILMDECK, the spiritual successor to Film Workshop!

**  ///////////////////////////////////////////////////////////////////////////////////////////  **
**  ///////////////////////////////////////////////////////////////////////////////////////////  */


// FILE SETUP /////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#define   CATEGORIZE
#include "ReShade.fxh"
#include "Include/Lib/Common.fxh"
#include "Include/FILMDECK/Setup.fxh"


// USER INTERFACE /////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////

#define CATEGORY "简介" /////////////////
/////////////////////////////////////////////////
UICL_MSG      (TUT1, 0,
"   欢迎使用 FILMDECK!\n\n"

"     FILMDECK 旨在帮助用户快速轻松地实现\n"
"   电影级色彩效果。这是通过模拟电影行业\n"
"   调色师使用的一种色彩分级工作流程来实现的。\n\n"

"     当电影使用真实胶片拍摄时，实现最终效果\n"
"   需要多个步骤。首先，相机中捕获的底片必须\n"
"   经过数字扫描，以便在达芬奇调色软件等工具\n"
"   中进行处理。\n\n"

"     扫描后，胶片素材与任何其他高端数字电影\n"
"   摄影机素材类似，可以用相同方式进行调色。\n"
"   通常在调色链末端会使用胶片冲印LUT，以便\n"
"   调色师了解其工作在最终结果中的呈现效果。\n"
"   这些LUT通常由制作最终胶片冲印的实验室提供。\n\n"

"     如果素材将被'冲印'，调色完成后将移除\n"
"   冲印模拟LUT，数字文件将被发送至胶片冲印\n"
"   设备，在如柯达2383等胶片冲印介质上进行冲印。\n\n"

"     对于FILMDECK而言，由于我们完全在数字\n"
"   领域工作，我们将模拟底片和冲印阶段的\n"
"   色彩响应，以及中间的调色阶段。\n"
"   这种工作流程的优势在于，您只需简单混合搭配\n"
"   不同的底片和冲印组合，即可实现丰富的变化效果。\n\n"

"   内部渲染顺序:\n"
"       胶片光晕\n"
"       胶片底片\n"
"       色彩分级\n"
"       胶片冲印\n\n"

"   使用方法:\n"
"       选择一个胶片底片，选择一个胶片冲印，然后\n"
"       调整您的色彩分级。\n\n\n"

"   祝调色愉快，\n"
"   TreyM")
#undef CATEGORY /////////////////////////////////
/////////////////////////////////////////////////


#define CATEGORY "胶片设置" ////////////////////
//////////////////////////////////////////////////
#if (CUSTOM_PRESET_ENABLED == 0)
UICL_COMBO    (FILM_NEGATIVE, "底片",       "",  NEGATIVE_DEFAULT, 0,
                  NEGATIVE_LIST)
UICL_COMBO    (FILM_FORMATN, "底片格式", "", 1, 0,
                    "16毫米\0"
                    "超级35\0"
                    "35毫米全画幅\0")
UICL_INT_S    (GRAIN_N,       "底片颗粒", "", 0, 100, 50, 0)
UICL_FLOAT_S  (NEG_EXP,       "底片曝光",    "", -4.0, 4.0,   0.0,   0)
UICL_INT_S    (N_TEMP,        "底片色温", "", -100, 100, 0, 0)
UICL_COMBOOL  (AUTO_TEMP,     "使用胶片底片白平衡", "", 0, 0)
UICL_MSG      (WBMASG, 0,
" 这将强制FILMDECK根据所选\n"
" 胶片底片的实际白平衡对图像\n"
" 进入底片配置文件时进行白平衡。")

UICL_COMBO    (FILM_PRINT, "冲印",     "",  PRINT_DEFAULT, 0,
                  PRINT_LIST)
UICL_COMBO    (FILM_FORMATP, "冲印格式", "", 2, 0,
                   "16毫米\0"
                   "超级35\0"
                   "35毫米全画幅\0")
UICL_INT_S    (GRAIN_P,       "冲印颗粒", "", 0, 100, 50, 0)
UICL_FLOAT_S  (PRT_EXP,       "冲印曝光",       "", -4.0, 4.0,   0.0,   0)
UICL_INT_S    (P_TEMP,        "冲印色温", "", -100, 100, 0, 0)
#ifdef __PATREON_NAG
    UICL_MSG      (PATREON2,       0, __PATREON_NAG)
#endif
#else
UICL_COMBO    (FILM_NEGATIVE, "底片",     "",  NEGATIVE_DEFAULT, 0,
                  CUSTOM_LIST_N)
UICL_COMBO    (FILM_FORMATN, "底片格式", "", 1, 0,
                   "16毫米\0"
                   "超级35\0"
                   "35毫米全画幅\0")
UICL_INT_S    (GRAIN_N,       "底片颗粒", "", 0, 100, 50, 0)
UICL_FLOAT_S  (NEG_EXP,       "底片曝光",    "", -4.0, 4.0,   0.0,   0)
UICL_INT_S    (N_TEMP,        "底片色温", "", -100, 100, 0, 0)
UICL_COMBOOL  (AUTO_TEMP,     "使用胶片底片白平衡", "", 1, 0)
UICL_MSG      (WBMASG, 0,
" 这将强制FILMDECK根据所选\n"
" 胶片底片的实际白平衡对图像\n"
" 进入底片配置文件时进行白平衡。")

UICL_COMBO    (FILM_PRINT, "冲印",     "",  PRINT_DEFAULT, 0,
                  CUSTOM_LIST_P)
UICL_COMBO    (FILM_FORMATP, "冲印格式", "", 2, 0,
                   "16毫米\0"
                   "超级35\0"
                   "35毫米全画幅\0")
UICL_INT_S    (GRAIN_P,       "冲印颗粒", "", 0, 100, 50, 0)
UICL_FLOAT_S  (PRT_EXP,       "冲印曝光",       "", -4.0, 4.0,   0.0,   0)
UICL_INT_S    (P_TEMP,        "冲印色温", "", -100, 100, 0, 0)
#ifdef __PATREON_NAG
    UICL_MSG      (PATREON2,       0, __PATREON_NAG)
#endif
#endif


#undef CATEGORY /////////////////////////////////
/////////////////////////////////////////////////


#define CATEGORY "色彩分级" ////////////////////////
/////////////////////////////////////////////////
UICL_INT_S    (ENABLE_GRADE, "快速切换",    "",    0,   1,   1, 0)

UICL_INT_S    (SATURATION,   "饱和度",      "",    0, 200, 100, 5)

UICL_COLOR    (GAIN,         "高光",      "",  0.5, 0.5, 0.5, 5)
UICL_COLOR    (GAMMA,        "中间调",        "",  0.5, 0.5, 0.5, 0)
UICL_COLOR    (LIFT,         "阴影",         "",  0.5, 0.5, 0.5, 0)

#define HSL_TOOLTIP \
"请谨慎操作，不要推得太过！\n" \
"您只能将色相偏移到相邻色相\n" \
"当前值的范围内。\n\n" \
"使用控件编辑最简单，\n" \
"点击彩色方块可打开它。"
UICL_COLOR    (GREYS,        "灰色",            "为灰色调着色",  0.50, 0.50, 0.50, 5)
UICL_COLOR    (HUERed,       "红色",             HSL_TOOLTIP,        0.75, 0.25, 0.25, 0)
UICL_COLOR    (HUEOrange,    "橙色",          HSL_TOOLTIP,        0.75, 0.50, 0.25, 0)
UICL_COLOR    (HUEYellow,    "黄色",          HSL_TOOLTIP,        0.75, 0.75, 0.25, 0)
UICL_COLOR    (HUEGreen,     "绿色",           HSL_TOOLTIP,        0.25, 0.75, 0.25, 0)
UICL_COLOR    (HUECyan,      "青色",            HSL_TOOLTIP,        0.25, 0.75, 0.75, 0)
UICL_COLOR    (HUEBlue,      "蓝色",            HSL_TOOLTIP,        0.25, 0.25, 0.75, 0)
UICL_COLOR    (HUEPurple,    "紫色",          HSL_TOOLTIP,        0.50, 0.25, 0.75, 0)
UICL_COLOR    (HUEMagenta,   "品红",         HSL_TOOLTIP,        0.75, 0.25, 0.75, 0)

UICL_INT_S    (CONTRAST,     "对比度",        "", -100, 100,   0, 5)
UICL_FLOAT_S  (OUT_GAMMA,    "伽马",           "中间调亮度", 0.01, 2.0, 1.0, 0)
UICL_INT2_S   (LEVELS,       "色阶",          "黑点 | 白点", -100, 100,   0, 0, 0)

UICL_COMBOOL  (CLIP_CAL,     "裁切参考线",  "", 0, 5)
UICL_COMBOOL  (GREY_CAL,     "灰度校准", "", 0, 0)
UICL_MSG      (CALMSG, 0,
" 这些工具将帮助您进行色彩分级\n"
" 平衡。裁切参考线将显示黑点\n"
" 和白点裁切的位置，灰度校准\n"
" 参考线会在图像中接近完美灰色\n"
" 饱和度的任何位置亮起绿色。")
#undef CATEGORY /////////////////////////////////
/////////////////////////////////////////////////


#define CATEGORY "其他选项" /////////////////
/////////////////////////////////////////////////
UICL_COMBO    (PUSH_MODE,     "曝光推动",   "",  0, 0,
                  "按ISO自动\0"
                  "手动\0")
UICL_INT_S    (AUTO_PUSH,     "自动推动范围", "", 0, 100, 100, 0)
UICL_FLOAT_S  (PUSH,          "手动推动",          "",  0.0, 3.0,   0.0,   0)
UICL_MSG      (PUSHMSG, 0,
" 曝光推动会对胶片底片进行欠曝\n"
" 同时在胶片冲印中增加曝光进行补偿。\n"
" 这会影响色彩响应和颗粒响应。\n"
" 需要同时激活底片和冲印。")

#if (ENABLE_HALATION)
UICL_COMBO    (ENABLE_HAL,    "启用光晕",      "", 1, 0,
                  "禁用\0"
                  "按胶片底片自动\0"
                  "手动\0")
UICL_INT_S    (HAL_AMT,       "手动光晕强度",   "",  0,   100,   33,    0)
UICL_INT_S    (HAL_SEN,       "手动光晕灵敏度", "",  10,  100,   85,    0)
UICL_INT_S    (HAL_WDT,       "手动光晕大小",        "",  10,  100,   75,    0)
UICL_MSG      (HALMSG, 0,
" 光晕是一种胶片伪影，会导致高光\n"
" 周围发出红色光晕。这种效果实际上\n"
" 与泛光或其他镜头伪影无关。")
#endif

UICL_COMBO    (ENABLE_RES,    "使用胶片格式分辨率",  "", 1, 0,
                  "禁用\0"
                  "按胶片格式自动\0"
                  "手动\0")
UICL_INT_S    (RESOLUTION,    "手动胶片分辨率",      "",  0.0, 200.0, 100.0, 0)
UICL_MSG      (RESMSG, 0,
" 启用此选项将允许FILMDECK根据\n"
" 所选胶片格式（16毫米、超级35\n"
" 或35毫米）调整图像的整体柔和度")

UICL_COMBOOL  (ENABLE_GW,     "片门抖动", "可能引起晕动症！", 0, 0)
UICL_INT_S    (WEAVE_AMT,     "片门抖动强度", "可能引起晕动症！", 0, 100, 50, 0)
UICL_MSG      (WVMSG, 0,
" 片门抖动是胶片在快速通过放映机时\n"
" 轻微错位的效果。在FILMDECK中，\n"
" 这表现为轻微的左右晃动。请注意，\n"
" 它可能在游戏中引起晕动症。")

UICL_COMBOOL  (ENABLE_FLK,    "画面闪烁", "", 0, 0)
UICL_INT_S    (FLK_INT,       "闪烁强度", "", 0, 100, 50, 0)
UICL_MSG      (FLKMSG, 0,
" 这会启用非常微妙的画面闪烁，\n"
" 模拟胶片放映机效果。请注意，\n"
" 它可能会引起头痛。")

#undef CATEGORY /////////////////////////////////
/////////////////////////////////////////////////


#define CATEGORY "预处理器说明" ////////////
/////////////////////////////////////////////////
UICL_MSG      (INFO1, 0,
"   ENABLE_GRAIN_DISPLACEMENT\n"
"       启用后FILMDECK会根据胶片颗粒\n"
"       纹理轻微扭曲图像。这能提供\n"
"       更真实的效果。")
UICL_MSG      (INFO2, 0,
"   ENABLE_HALATION\n"
"       启用后会在明亮高光周围产生\n"
"       红色光晕，可基于所选胶片底片\n"
"       或手动设置。禁用可提升性能。")
UICL_MSG      (INFO3, 0,
"   FORCE_8_BIT_OUTPUT\n"
"       强制FILMDECK将输出抖动为8位。\n"
"       当您使用8位显示器但游戏使用\n"
"       RGB10A2颜色缓冲区时很有用。")
UICL_MSG      (INFO4, 0,
"   SWAPCHAIN_PRECISION\n"
"       1 = 使用游戏内部位深度（不推荐）\n"
"       2 = RGBA16 - 16位（默认模式）\n"
"       3 = RGBA16F - 16位浮点")
#undef CATEGORY /////////////////////////////////
/////////////////////////////////////////////////


// FUNCTIONS //////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#include "Include/Functions/AVGen.fxh"
#include "Include/Functions/3DLUT.fxh"
#include "Include/Functions/Contrast.fxh"
#include "Include/Functions/BlendingModes.fxh"
#include "Include/Functions/GaussianBlurBounds.fxh"
#include "Include/Functions/Grain.fxh"
#include "Include/Functions/HSLShift.fxh"
#include "Include/Functions/TriDither.fxh"


// RENDERTARGETS //////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
RENDERTARGET(Swapchain1, BUFFER_WIDTH, BUFFER_HEIGHT, INTERNAL_DEPTH,     MIRROR)
RENDERTARGET(Swapchain2, BUFFER_WIDTH, BUFFER_HEIGHT, INTERNAL_DEPTH,     MIRROR)


// SHADERS ////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
VOID (Downscale, float4 scaled)
{
    // FILM SOFTENING ///////////////////////////
    /////////////////////////////////////////////
    if ((ENABLE_RES > 0) && ((FILM_NEGATIVE > 0) || (FILM_PRINT > 0)))
    {
        scaled = tex2Dbicub(TextureColor, SCALE(uv, 0.5)); // Linearized cbuffer
    }

    else
    {
        scaled = tex2D(TextureColor, uv); // Linearized cbuffer
    }

    scaled = SRGBToLinear(scaled);
}

VOID (Upscale, float4 color)
{
    float4 soften, blur1;
    float  mask, res, halsen;

    // LINEAR CBUFFER ///////////////////////////
    /////////////////////////////////////////////
    color  = SRGBToLinear(tex2D(TextureColor, uv));


    // FILM PROFILE ARRAY ///////////////////////
    /////////////////////////////////////////////
    #include FILM_PROFILES


    // FILM SOFTENING ///////////////////////////
    /////////////////////////////////////////////
    if ((ENABLE_RES > 0) && ((FILM_NEGATIVE > 0) || (FILM_PRINT > 0))) // We blend in linearspace to avoid darkening the edges where
    {                                                                  // softening is most noticeable
        res    = (ENABLE_RES == 1)
               ? lerp(0.0, 1.0, lerp(0.5, (FILM_FORMATN * 0.25), (FILM_NEGATIVE > 0)) + lerp(0.5, (FILM_FORMATP * 0.25), (FILM_PRINT > 0)))
               : (RESOLUTION * 0.005);
        soften = tex2Dbicub(TextureSwapchain1, SCALE(uv, (1.0 / 0.5)));
        mask   = pow(smoothstep(0.1, 1.0, GetLuma(LinearToSRGB(color.rgb))), 0.75);
        mask   = lerp(lerp(0.25, 1.0, mask), 0.0, res);
        color  = lerp(color, soften, mask);
    }


    // HALATION PREP ////////////////////////////
    /////////////////////////////////////////////
    #if (ENABLE_HALATION)
    if ((ENABLE_HAL > 0) && (FILM_NEGATIVE > 0))
    {
        halsen  = (ENABLE_HAL < 2)
                ? (NegativeProfile[FILM_NEGATIVE - 1].halation.y * 0.01)
                : (HAL_SEN * 0.01);
        // Pre-apply the negative lut to grab the correct colors for halation
        color.a = GetLuma(MultiLUT_Linear(tex2Dbicub(TextureColor, SCALE(uv, 0.25)).rgb, NegativeAtlas, FILM_NEGATIVE - 1));
        // Crush and linearize the result
        color.a = pow(SRGBToLinear(color.aaa).x, lerp(20.0, 4.0, halsen));
    }
    #endif
}

#if (ENABLE_HALATION)
VOID (Halate1, float4 color)
{
    float halation, width;

    // FILM PROFILE ARRAY ///////////////////////
    /////////////////////////////////////////////
    #include FILM_PROFILES


    // INPUT IMAGE //////////////////////////////
    /////////////////////////////////////////////
    color = tex2D(TextureSwapchain2, uv);


    // HALATION HORIZONTAL BLUR /////////////////
    /////////////////////////////////////////////
    if ((ENABLE_HAL > 0) && (FILM_NEGATIVE > 0))
    {
        width    = (ENABLE_HAL == 1)
                 ? (NegativeProfile[FILM_NEGATIVE - 1].halation.z * 0.01)
                 : (HAL_WDT * 0.01);
        halation = HalateH(color.a, TextureSwapchain2, width, BoundsMid, uv);
    }

    else
    {
        halation = 0.0;
    }

    color.a = halation;
}

VOID (Halate2, float4 color)
{
    float halation, width;

    // FILM PROFILE ARRAY ///////////////////////
    /////////////////////////////////////////////
    #include FILM_PROFILES


    // INPUT IMAGE //////////////////////////////
    /////////////////////////////////////////////
    color = tex2D(TextureSwapchain1, uv);


    // HALATION VERTICAL BLUR ///////////////////
    /////////////////////////////////////////////
    if ((ENABLE_HAL > 0) && (FILM_NEGATIVE > 0))
    {
        width    = (ENABLE_HAL == 1)
                 ? (NegativeProfile[FILM_NEGATIVE - 1].halation.z * 0.01)
                 : (HAL_WDT * 0.01);
        halation = HalateV(color.a, TextureSwapchain1, width, BoundsMid, uv);
    }

    else
    {
        halation = 0.0;
    }

    color.a = halation;
}
#endif

#if (ENABLE_GRAIN_DISPLACEMENT)
VOID (GrainDisplacement, float4 color)
{
    float  dist;
    float3 grain;

    dist      = lerp(150.0, 275.0, FILM_FORMATN * 0.5);

    grain     = GetGrainTexture(FILM_FORMATN, 1.0, uv) - 0.5;
    grain    *= (pow(GRAIN_N * 0.01, 0.333)) / (dist * (1440.0 / (BUFFER_HEIGHT * 1.0)));

    color.rgb = tex2D(TextureSwapchain2, uv + float2(grain.x / BUFFER_ASPECT_RATIO, grain.y)).rgb;
    color.a   = tex2D(TextureSwapchain2, uv).a;
}
#endif

VOID (FilmDeck, float4 film)
{
    float  dist, luma, pmask, avg, ntemp, ptemp;
    float3 halate;
    float3 orig, lift, gamma, gain, grain, grey, hsl;


    // INPUT TEXTURES ///////////////////////////
    /////////////////////////////////////////////
    #if (ENABLE_GRAIN_DISPLACEMENT)
    dist   = lerp(150.0, 275.0, FILM_FORMATP * 0.5);
    grain  = GetGrainTexture(FILM_FORMATP, -1.0, uv) - 0.5;
    grain *= (pow(GRAIN_P * 0.01, 0.333)) / (dist * (1440.0 / (BUFFER_HEIGHT * 1.0)));
    film   = tex2D(TextureSwapchain1, uv + float2(grain.z / BUFFER_ASPECT_RATIO, grain.y)).rgb;
    #else
    film = tex2D(TextureSwapchain2, uv); // Buffer from film softening stage
    #endif
    avg  = pow(GetLuma(avGen::get()), 0.75); // Scene average luma


    // FILM PROFILE ARRAY ///////////////////////
    /////////////////////////////////////////////
    #include FILM_PROFILES


    // HALATION /////////////////////////////////
    /////////////////////////////////////////////
    #if (ENABLE_HALATION)
    if ((ENABLE_HAL > 0) && (FILM_NEGATIVE > 0))
    {
        // Apply film halation (blended in linearspace)
        #if (ENABLE_GRAIN_DISPLACEMENT)
        halate.r = tex2Dbicub(TextureSwapchain1, SCALE(uv, 4.0)).a;
        #else
        halate.r = tex2Dbicub(TextureSwapchain2, SCALE(uv, 4.0)).a;
        #endif
        halate.y = (ENABLE_HAL == 1)
                 ? (NegativeProfile[FILM_NEGATIVE - 1].halation.x * 0.02)
                 : (HAL_AMT * 0.02);
        film.r   = lerp(film.r, BlendScreen(film.r, halate.r), halate.y);
    }
    #endif


    // EXPOSURE & PUSHING ///////////////////////
    /////////////////////////////////////////////
    // Normally, this would apply evenly to the entire image
    // but since I'm working with non-HDR input data,
    // I mask for luminance to preserve highlights
    // The effect is only applied to the shadows and mids
    pmask = GetLuma(SRGBToLinear(tex2D(TextureColor, uv)));
    if (FILM_NEGATIVE > 0)\
    {
        film *= exp2(NEG_EXP);

        if ((PUSH_MODE < 1) && (FILM_PRINT > 0)) // Automatic push
        {
            film *= lerp(1.0, lerp(lerp(NegativeProfile[FILM_NEGATIVE - 1].iso / 800.0, 1.0, avg), 1.0, pmask), AUTO_PUSH * 0.01);
        }

        else if (FILM_PRINT > 0) // Manual push
        {
            film *= exp2(lerp(-PUSH, 0.0, pmask));
        }
    }

    film = LinearToSRGB(saturate(film));


    if (FILM_NEGATIVE > 0)
    {
        // WHITE BALANCE ////////////////////////
        /////////////////////////////////////////
        ntemp = (N_TEMP > 0)
              ? lerp(6500.0, 40000.0, abs(N_TEMP * 0.01))
              : lerp(6500.0,  2000.0, abs(N_TEMP * 0.01));

        luma  = GetLuma(film.rgb);

        if ((AUTO_TEMP) && (FILM_NEGATIVE > 0))
        {
            film.rgb = lerp(WhiteBalance(film.rgb, ntemp, NegativeProfile[FILM_NEGATIVE - 1].temp), film.rgb, luma);
        }

        else
        {
            film.rgb = lerp(WhiteBalance(film.rgb, ntemp, 6500), film.rgb, luma);
        }


        // FILM GRAIN ///////////////////////////
        /////////////////////////////////////////
        film.rgb = FilmGrain(saturate(film.rgb), FILM_FORMATN, 1.0, GRAIN_N, uv);


        // FILM NEGATIVE LUT ////////////////////
        /////////////////////////////////////////
        #if (CUSTOM_PRESET_ENABLED != 0)
            if (FILM_NEGATIVE <= NEGATIVE_COUNT)
            {
                film.rgb = FilmNegative(saturate(film.rgb), 0, FILM_NEGATIVE - 1).rgb;
            }

            else
            {
                film.rgb = FilmNegative(saturate(film.rgb), 1, (FILM_NEGATIVE - NEGATIVE_COUNT) - 1).rgb;
            }
        #else
            film.rgb = FilmNegative(saturate(film.rgb), 0, FILM_NEGATIVE - 1).rgb;
        #endif
    }


    // COLOR GRADING //////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    if (ENABLE_GRADE)
    {
        // SATURATION ///////////////////////////
        /////////////////////////////////////////
        film.rgb = RGBToHSL(film.rgb);
        film.y   = (SATURATION < 100)
                 ? (lerp(0.0, film.y, SATURATION * 0.01))
                 : (pow(film.y, lerp(1.0, 0.66, (SATURATION - 100) * 0.01)));
        film.rgb = HSLToRGB(film.rgb);


        // LIFT GAMMA GAIN //////////////////////
        /////////////////////////////////////////
        lift     = (LIFT  - 0.5) * 0.5;
        gamma    = (GAMMA + 0.5);
        gain     = (GAIN  + 0.5);
        film.rgb = pow(saturate(gain * (film.rgb + lift * (1 - film.rgb))), 1.0 / gamma);


        // GREY COLORIZE ////////////////////////
        /////////////////////////////////////////
        hsl      = RGBToHSL(film.rgb);
        grey     = (GREYS * 2.0);
        film.rgb = saturate(lerp(film.rgb, film.rgb * grey, saturate(pow(1-hsl.y, 10.0) * pow(smoothstep(0.66, 0.0, hsl.z), 1.0))));


        // HUE SHIFT ////////////////////////////
        /////////////////////////////////////////
        film.rgb = HSLShift(film.rgb);


        // CONTRAST /////////////////////////////
        /////////////////////////////////////////
        film.rgb = ContrastCurve(film.rgb, CONTRAST);
    }


    // EXPOSURE & PUSHING ///////////////////////
    /////////////////////////////////////////////
    // Normally, this would apply evenly to the entire image
    // but since we're working with non-HDR input data,
    // We'll mask for luminance to preserve highlights
    // The effect is only applied to the shadows and mids
    film.rgb   = SRGBToLinear(film.rgb);
    if (FILM_PRINT > 0)
    {
        film      *= exp2(PRT_EXP);

        if ((PUSH_MODE < 1) && (FILM_NEGATIVE > 0)) // Automatic push
        {
            film /= lerp(1.0, lerp(lerp(NegativeProfile[FILM_NEGATIVE - 1].iso / 800.0, 1.0, avg), 1.0, pmask), AUTO_PUSH * 0.01);
        }

        else if (FILM_NEGATIVE > 0) // Manual push
        {
            film *= exp2(lerp(PUSH, 0.0, pmask));
        }
    }


    if (FILM_PRINT > 0)
    {
        // WHITE BALANCE ////////////////////////
        /////////////////////////////////////////
        ptemp    = (P_TEMP > 0)
                 ? lerp(6500.0, 40000.0, abs(P_TEMP * 0.01))
                 : lerp(6500.0,  2000.0, abs(P_TEMP * 0.01));
        luma     = GetLuma(film.rgb);
        film.rgb = lerp(WhiteBalance(saturate(film.rgb), ptemp, 6500), film.rgb, luma);

        // FILM GRAIN ///////////////////////////////
        /////////////////////////////////////////////
        film     = LinearToSRGB(film);
        film.rgb = FilmGrain(saturate(film.rgb), FILM_FORMATP, -0.75, GRAIN_P, uv);


        // FILM PRINT LUT ///////////////////////////
        /////////////////////////////////////////////
        #if (CUSTOM_PRESET_ENABLED != 0)
            if (FILM_PRINT <= PRINT_COUNT)
            {
                film.rgb = FilmPrint(saturate(film.rgb), 0, FILM_PRINT - 1).rgb;
            }

            else
            {
                film.rgb = FilmPrint(saturate(film.rgb), 1, (FILM_PRINT - PRINT_COUNT) - 1).rgb;
            }
        #else
            film.rgb = FilmPrint(saturate(film.rgb), 0, FILM_PRINT - 1).rgb;
        #endif
    }

    else
    {
        film.rgb = LinearToSRGB(film.rgb);
    }

    if (ENABLE_GRADE)
    {
        // OUTPUT LEVELS ////////////////////////
        /////////////////////////////////////////
        film = pow(film, 1.0 / OUT_GAMMA);
        film = saturate(lerp(LEVELS.x / 255.0, (LEVELS.y + 255) / 255.0, film));


        // CALIBRATION GUIDES ///////////////////
        /////////////////////////////////////////
        if (CLIP_CAL)
        {
            film.rgb = lerp(film.rgb, float3(1, 0, 0), (GetLuma(film.rgb) > (254.0 / 255.0)));
            film.rgb = lerp(film.rgb, float3(0, 0, 1), (GetLuma(film.rgb) == 0.0));
        }

        hsl = RGBToHSV(film.rgb);

        if (GREY_CAL)
        {
            hsl.z    = SRGBToLinear(hsl.zzz).x;
            film.rgb = lerp(film.rgb, float3(0, 1, 0), smoothstep(0.15, 0.05, hsl.y) * (1 - smoothstep(0.055, 0.0, hsl.z) - smoothstep(0.305, 1.0, hsl.z)));
        }
    }


    // FINAL DITHER /////////////////////////////
    /////////////////////////////////////////////
    film.rgb += TriDither(film.rgb, uv, FORCE_8_BIT_OUTPUT ? 8 : BUFFER_COLOR_BIT_DEPTH);
}

VOID (GateWeave, float4 color)
{
    float animate;

    animate = (ENABLE_GW)
            ? ((cos(Timer * (1.0 / 24.0)) * 0.0001) * (WEAVE_AMT * 0.015))
            : 0.0;

    color   = tex2D(TextureColor, uv + float2(animate, 0.0));

    if (ENABLE_FLK)
    {
        color = lerp(color, color * lerp(1.0, 0.975, FLK_INT * 0.01), ((cos(Timer * pi) + 1) * 0.5));
    }

    #if (LET_ME_COOK != 0)
        color.rgb = BlendScreen(color.rgb, tex2D(TextureCook, uv).rgb);
    #endif
}


// TECHNIQUES /////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
technique FILMDECK < ui_label = "FILMDECK"; ui_tooltip = "胶片模拟"; >
{
    pass // ADAPTATION TEXTURE GENERATION ///////
    {
        VertexShader = avGen::vs_main;
        PixelShader  = avGen::ps_main;
        RenderTarget = avGen::texLod;
    }

    pass // FILM SOFTENING //////////////////////
    {
        VertexShader = VS_Tri;
        PixelShader  = PS_Downscale;
        RenderTarget = RT_Swapchain1;
    }

    pass // FILM SOFTENING //////////////////////
    {
        VertexShader = VS_Tri;
        PixelShader  = PS_Upscale;
        RenderTarget = RT_Swapchain2;
    }

    #if (ENABLE_HALATION)
    pass // HALATION ////////////////////////////
    {
        VertexShader = VS_Tri;
        PixelShader  = PS_Halate1;
        RenderTarget = RT_Swapchain1;
    }

    pass // HALATION ////////////////////////////
    {
        VertexShader = VS_Tri;
        PixelShader  = PS_Halate2;
        RenderTarget = RT_Swapchain2;
    }
    #endif

    #if (ENABLE_GRAIN_DISPLACEMENT)
    pass // GRAIN DISPLACEMENT //////////////////
    {
        VertexShader = VS_Tri;
        PixelShader  = PS_GrainDisplacement;
        RenderTarget = RT_Swapchain1;
    }
    #endif

    pass // FILM PASS ///////////////////////////
    {
        VertexShader = VS_Tri;
        PixelShader  = PS_FilmDeck;
    }

    pass // GATE WEAVE //////////////////////////
    {
        VertexShader = VS_Tri;
        PixelShader  = PS_GateWeave;
    }
}