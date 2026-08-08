/*
  DisplayDepth by CeeJay.dk (with many updates and additions by the Reshade community)

  Visualizes the depth buffer. The distance of pixels determine their brightness.
  Close objects are dark. Far away objects are bright.
  Use this to configure the depth input preprocessor definitions (RESHADE_DEPTH_INPUT_*).
*/

#include "ReShade.fxh"

// -- Basic options --
#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
#define TEXT_UPSIDE_DOWN "1"
#define TEXT_UPSIDE_DOWN_ALTER "0"
#else
#define TEXT_UPSIDE_DOWN "0"
#define TEXT_UPSIDE_DOWN_ALTER "1"
#endif
#if RESHADE_DEPTH_INPUT_IS_REVERSED
#define TEXT_REVERSED "1"
#define TEXT_REVERSED_ALTER "0"
#else
#define TEXT_REVERSED "0"
#define TEXT_REVERSED_ALTER "1"
#endif
#if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
#define TEXT_LOGARITHMIC "1"
#define TEXT_LOGARITHMIC_ALTER "0"
#else
#define TEXT_LOGARITHMIC "0"
#define TEXT_LOGARITHMIC_ALTER "1"
#endif

// "ui_text" was introduced in ReShade 4.5, so cannot show instructions in older versions

uniform int iUIPresentType <
    ui_label = "显示类型";
    ui_label_ja_jp = "画面効果";
    ui_type = "combo";
    ui_items = "深度图\0法线图\0两者都显示 (左右分割)\0";
    ui_items_ja_jp = "深度マップ\0法線マップ\0両方を表示 (左右分割)\0";
#if __RESHADE__ < 40500
    ui_tooltip =
#else
    ui_text =
#endif
        "正确的设置需要在点击上方'编辑全局预处理器定义'按钮后打开的对话框中进行设置。\n"
        "\n"
        "RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN 当前设置为 " TEXT_UPSIDE_DOWN "。\n"
        "如果深度图显示为上下颠倒，请将其设置为 " TEXT_UPSIDE_DOWN_ALTER "。\n"
        "\n"
        "RESHADE_DEPTH_INPUT_IS_REVERSED 当前设置为 " TEXT_REVERSED "。\n"
        "如果深度图中近处物体是亮的而远处物体是暗的，请将其设置为 " TEXT_REVERSED_ALTER "。\n"
        "如果你能看到法线但深度视图全黑，也可以尝试此设置。\n"
        "\n"
        "RESHADE_DEPTH_INPUT_IS_LOGARITHMIC 当前设置为 " TEXT_LOGARITHMIC "。\n"
        "如果法线图有条带伪影（额外的条纹），请将其设置为 " TEXT_LOGARITHMIC_ALTER "。";
    ui_text_ja_jp =
#if ADDON_ADJUST_DEPTH
        "Adjust Depthアドオンのインストールを検出しました。\n"
        "'設定に保存して反映する'ボタンをクリックすると、このエフェクトで調節した全ての変数が共通設定に反映されます。\n"
        "または、上の'プリプロセッサの定義を編集'ボタンをクリックした後に開くダイアログで直接編集する事もできます。";
#else
        "調節が終わったら、上の'プリプロセッサの定義を編集'ボタンをクリックした後に開くダイアログに入力する必要があります。\n"
        "\n"
        "RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWNは現在" TEXT_UPSIDE_DOWN "に設定されています。\n"
        "深度マップが上下逆さまに表示されている場合は" TEXT_UPSIDE_DOWN_ALTER "に変更して下さい。\n"
        "\n"
        "RESHADE_DEPTH_INPUT_IS_REVERSEDは現在" TEXT_REVERSED "に設定されています。\n"
        "画面効果が深度マップのとき、近くの形状がより白く、遠くの形状がより黒い場合は" TEXT_REVERSED_ALTER "に変更して下さい。\n"
        "また、法線マップで形が判別出来るが、深度マップが真っ暗に見えるという場合も、この設定の変更を試して下さい。\n"
        "\n"
        "RESHADE_DEPTH_INPUT_IS_LOGARITHMICは現在" TEXT_LOGARITHMIC "に設定されています。\n"
        "画面効果に実際のレンダリングと合致しない縞模様がある場合は" TEXT_LOGARITHMIC_ALTER "に変更して下さい。";
#endif
    ui_tooltip_ja_jp =
        "'深度マップ'は、形状の遠近を白黒で表現します。正しい見え方では、近くの形状ほど黒く、遠くの形状ほど白くなります。\n"
        "'法線マップ'は、形状を滑らかに表現します。正しい見え方では、全体的に青緑風で、地平線を見たときに地面が緑掛かった色合いになります。\n"
        "'両方を表示 (左右分割)'が選択された場合は、左に法線マップ、右に深度マップを表示します。";
> = 2;

uniform bool bUIShowOffset <
    ui_label = "将深度图混合到图像中 (帮助找到正确的偏移)";
    ui_label_ja_jp = "透かし比較";
    ui_tooltip_ja_jp = "補正作業を支援するために、画面効果を半透過で適用します。";
> = false;

uniform bool bUIUseLivePreview <
    ui_category = "预览设置";
    ui_category_ja_jp = "基本的な補正";
#if __RESHADE__ <= 50902
    ui_category_closed = true;
#elif !ADDON_ADJUST_DEPTH
    ui_category_toggle = true;
#endif
    ui_label = "显示实时预览并忽略预处理器定义";
    ui_label_ja_jp = "プリプロセッサの定義を無視 (補正プレビューをオン)";
    ui_tooltip = "启用此选项可使用当前预设设置进行预览，而不是使用全局预处理器设置。";
    ui_tooltip_ja_jp =
        "共通設定に保存されたプリプロセッサの定義ではなく、これより下のプレビュー設定を使用するには、これを有効にします。\n"
#if ADDON_ADJUST_DEPTH
        "設定の準備が出来たら、'設定に保存して反映する'ボタンをクリックしてから、このチェックボックスをオフにして下さい。"
#else
        "設定の準備が出来たら、上の'プリプロセッサの定義を編集'ボタンをクリックした後に開くダイアログに入力して下さい。"
#endif
        "\n\n"
        "プレビューをオンにした場合と比較して画面効果がまったく同じになれば、正しく設定が反映されています。";
> = false;

#if __RESHADE__ <= 50902
uniform int iUIUpsideDown <
#else
uniform bool iUIUpsideDown <
#endif
    ui_category = "预览设置";
    ui_label = "上下颠倒";
    ui_label_ja_jp = "深度バッファの上下反転を修正";
#if __RESHADE__ <= 50902
    ui_type = "combo";
    ui_items = "关\0开\0";
#endif
    ui_text_ja_jp =
        "\n"
#if ADDON_ADJUST_DEPTH
        "項目にカーソルを合わせると、設定が必要な状況の説明が表示されます。"
#else
        "項目にカーソルを合わせると、設定が必要な状況の説明と、プリプロセッサの定義が表示されます。"
#endif
    ;
    ui_tooltip_ja_jp =
        "深度マップが上下逆さまに表示されている場合は変更して下さい。"
#if !ADDON_ADJUST_DEPTH
        "\n\n"
        "定義名は次の通りです。文字は完全に一致する必要があり、半角大文字の英字とアンダーバーを用いなければなりません。\n"
        "RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=値\n"
        "定義値は次の通りです。オンの場合は1、オフの場合は0を指定して下さい。\n"
        "RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=1\n"
        "RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=0"
#endif
        ;
> = RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN;

#if __RESHADE__ <= 50902
uniform int iUIReversed <
#else
uniform bool iUIReversed <
#endif
    ui_category = "预览设置";
    ui_label = "反向";
    ui_label_ja_jp = "深度バッファの奥行反転を修正";
#if __RESHADE__ <= 50902
    ui_type = "combo";
    ui_items = "关\0开\0";
#endif
    ui_tooltip_ja_jp =
        "画面効果が深度マップのとき、近くの形状が明るく、遠くの形状が暗い場合は変更して下さい。\n"
        "また、法線マップで形が判別出来るが、深度マップが真っ暗に見えるという場合も、この設定の変更を試して下さい。"
#if !ADDON_ADJUST_DEPTH
        "\n\n"
        "定義名は次の通りです。文字は完全に一致する必要があり、半角大文字の英字とアンダーバーを用いなければなりません。\n"
        "RESHADE_DEPTH_INPUT_IS_REVERSED=値\n"
        "定義値は次の通りです。オンの場合は1、オフの場合は0を指定して下さい。\n"
        "RESHADE_DEPTH_INPUT_IS_REVERSED=1\n"
        "RESHADE_DEPTH_INPUT_IS_REVERSED=0"
#endif
        ;
> = RESHADE_DEPTH_INPUT_IS_REVERSED;

#if __RESHADE__ <= 50902
uniform int iUILogarithmic <
#else
uniform bool iUILogarithmic <
#endif
    ui_category = "预览设置";
    ui_label = "对数";
    ui_label_ja_jp = "深度バッファを対数分布として扱うように修正";
#if __RESHADE__ <= 50902
    ui_type = "combo";
    ui_items = "关\0开\0";
#endif
    ui_tooltip = "如果显示的表面法线有条纹，请更改此设置。";
    ui_tooltip_ja_jp =
        "画面効果に実際のゲーム画面と合致しない縞模様がある場合は変更して下さい。"
#if !ADDON_ADJUST_DEPTH
        "\n\n"
        "定義名は次の通りです。文字は完全に一致する必要があり、半角大文字の英字とアンダーバーを用いなければなりません。\n"
        "RESHADE_DEPTH_INPUT_IS_LOGARITHMIC=値\n"
        "定義値は次の通りです。オンの場合は1、オフの場合は0を指定して下さい。\n"
        "RESHADE_DEPTH_INPUT_IS_LOGARITHMIC=1\n"
        "RESHADE_DEPTH_INPUT_IS_LOGARITHMIC=0"
#endif
        ;
> = RESHADE_DEPTH_INPUT_IS_LOGARITHMIC;

// -- Advanced options --

uniform float2 fUIScale <
    ui_category = "预览设置";
    ui_label = "缩放";
    ui_label_ja_jp = "拡大率";
    ui_type = "drag";
    ui_text =
        "\n"
        " * 高级选项\n"
        "\n"
        "以下设置也需要通过上方的'编辑全局预处理器定义'进行设置才能生效。\n"
        "你可以使用下面的控件预览它们如何影响深度图。\n"
        "\n"
        "不过，很少需要更改这些设置，因为它们的默认值几乎适用于所有游戏。\n\n";
    ui_text_ja_jp =
        "\n"
        " * その他の補正 (不定形またはその他)\n"
        "\n"
        "これより下は、深度バッファが不定形など、特別なケース向けの設定です。\n"
        "通常はこれより上の'基本的な補正'のみでほとんどのゲームに適合します。\n"
        "また、これらの設定は画質の向上にはまったく役に立ちません。\n\n";
    ui_tooltip =
        "最好使用'显示类型'->'深度图'并在下面的选项中启用'偏移'来设置缩放。\n"
        "使用这些值：\nRESHADE_DEPTH_INPUT_X_SCALE=<左边的值>\nRESHADE_DEPTH_INPUT_Y_SCALE=<右边的值>\n"
        "\n"
        "如果你知道游戏深度缓冲区的正确分辨率，那么这个缩放值就是\n"
        "正确分辨率与ReShade认为的分辨率之间的比值。\n"
        "例如：\n"
        "如果它认为分辨率是1920x1080，但实际上是1280x720，那么正确的缩放是(1.5, 1.5)\n"
        "因为1920/1280=1.5，1080/720也是1.5，所以x和y的正确缩放都是1.5";
    ui_tooltip_ja_jp =
        "深度バッファの解像度がクライアント解像度と異なる場合に変更して下さい。\n"
        "このスケール値は、深度バッファの解像度とクライアント解像度との単純な比率になります。\n"
        "深度バッファの解像度が1280×720でクライアント解像度が1920×1080の場合、横の比率が1920÷1280、縦の比率が1080÷720となります。\n"
        "計算した結果を設定すると、値はそれぞれX_SCALE=1.5、Y_SCALE=1.5となります。"
#if !ADDON_ADJUST_DEPTH
        "\n\n"
        "定義名は次の通りです。文字は完全に一致する必要があり、半角大文字の英字とアンダーバーを用いなければなりません。\n"
        "RESHADE_DEPTH_INPUT_X_SCALE=横の値\n"
        "RESHADE_DEPTH_INPUT_Y_SCALE=縦の値\n"
        "定義値は次の通りです。横の値はX_SCALE、縦の値はY_SCALEに指定して下さい。\n"
        "RESHADE_DEPTH_INPUT_X_SCALE=1.0\n"
        "RESHADE_DEPTH_INPUT_Y_SCALE=1.0"
#endif
        ;
    ui_min = 0.0; ui_max = 2.0;
    ui_step = 0.001;
> = float2(RESHADE_DEPTH_INPUT_X_SCALE, RESHADE_DEPTH_INPUT_Y_SCALE);

uniform int2 iUIOffset <
    ui_category = "预览设置";
    ui_label = "偏移";
    ui_label_ja_jp = "位置オフセット";
    ui_type = "slider";
    ui_tooltip =
        "最好使用'显示类型'->'深度图'并在下面的选项中启用'偏移'来设置像素偏移。\n"
        "使用这些值：\nRESHADE_DEPTH_INPUT_X_PIXEL_OFFSET=<左边的值>\nRESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET=<右边的值>";
    ui_tooltip_ja_jp =
        "深度バッファにレンダリングされた物体の形状が画面効果と重なり合っていない場合に変更して下さい。\n"
        "この値は、ピクセル単位で指定します。"
#if !ADDON_ADJUST_DEPTH
        "\n\n"
        "定義名は次の通りです。文字は完全に一致する必要があり、半角大文字の英字とアンダーバーを用いなければなりません。\n"
        "RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET=横の値\n"
        "RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET=縦の値\n"
        "定義値は次の通りです。横の値はX_PIXEL_OFFSET、縦の値はY_PIXEL_OFFSETに指定して下さい。\n"
        "RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET=0.0\n"
        "RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET=0.0"
#endif
        ;
    ui_min = -BUFFER_SCREEN_SIZE;
    ui_max = BUFFER_SCREEN_SIZE;
    ui_step = 1;
> = int2(RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET, RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET);

uniform float fUIFarPlane <
    ui_category = "预览设置";
    ui_label = "远平面";
    ui_label_ja_jp = "遠点距離";
    ui_type = "drag";
    ui_tooltip =
        "RESHADE_DEPTH_LINEARIZATION_FAR_PLANE=<值>\n"
        "在大多数情况下不需要更改此值。";
    ui_tooltip_ja_jp =
        "深度マップの色合いが距離感と合致しない、法線マップの表面が平面に見える、などの場合に変更して下さい。\n"
        "遠点距離を1000に設定すると、ゲームの描画距離が1000メートルであると見なします。\n\n"
        "このプレビュー画面はあくまでプレビューであり、ほとんどの場合、深度バッファは深度マップの色数より遥かに高い精度で表現されています。\n"
        "例えば、10m前後の距離の形状が純粋な黒に見えるからという理由で値を変更しないで下さい。"
#if !ADDON_ADJUST_DEPTH
        "\n\n"
        "定義名は次の通りです。文字は完全に一致する必要があり、半角大文字の英字とアンダーバーを用いなければなりません。\n"
        "RESHADE_DEPTH_LINEARIZATION_FAR_PLANE=値\n"
        "定義値は次の通りです。\n"
        "RESHADE_DEPTH_LINEARIZATION_FAR_PLANE=1000.0"
#endif
        ;
    ui_min = 0.0; ui_max = 1000.0;
    ui_step = 0.1;
> = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;

uniform float fUIDepthMultiplier <
    ui_category = "预览设置";
    ui_label = "深度乘数";
    ui_label_ja_jp = "深度乗数";
    ui_type = "drag";
    ui_tooltip = "RESHADE_DEPTH_MULTIPLIER=<值>";
    ui_tooltip_ja_jp =
        "特定のエミュレータソフトウェアにおける深度バッファを修正するため、特別に追加された変数です。\n"
        "この値は僅かな変更でも計算式を破壊するため、設定すべき値を知らない場合は変更しないで下さい。"
#if !ADDON_ADJUST_DEPTH
        "\n\n"
        "定義名は次の通りです。文字は完全に一致する必要があり、半角大文字の英字とアンダーバーを用いなければなりません。\n"
        "RESHADE_DEPTH_MULTIPLIER=値\n"
        "定義値は次の通りです。\n"
        "RESHADE_DEPTH_MULTIPLIER=1.0"
#endif
        ;
    ui_min = 0.0; ui_max = 1000.0;
    ui_step = 0.001;
> = RESHADE_DEPTH_MULTIPLIER;

float GetLinearizedDepth(float2 texcoord)
{
    if (!bUIUseLivePreview)
    {
        return ReShade::GetLinearizedDepth(texcoord);
    }
    else
    {
        if (iUIUpsideDown) // RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
            texcoord.y = 1.0 - texcoord.y;

        texcoord.x /= fUIScale.x; // RESHADE_DEPTH_INPUT_X_SCALE
        texcoord.y /= fUIScale.y; // RESHADE_DEPTH_INPUT_Y_SCALE
        texcoord.x -= iUIOffset.x * BUFFER_RCP_WIDTH; // RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
        texcoord.y += iUIOffset.y * BUFFER_RCP_HEIGHT; // RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET

        float depth = tex2Dlod(ReShade::DepthBuffer, float4(texcoord, 0, 0)).x * fUIDepthMultiplier;

        const float C = 0.01;
        if (iUILogarithmic) // RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
            depth = (exp(depth * log(C + 1.0)) - 1.0) / C;

        if (iUIReversed) // RESHADE_DEPTH_INPUT_IS_REVERSED
            depth = 1.0 - depth;

        const float N = 1.0;
        depth /= fUIFarPlane - depth * (fUIFarPlane - N);

        return depth;
    }
}

float3 GetScreenSpaceNormal(float2 texcoord)
{
    float3 offset = float3(BUFFER_PIXEL_SIZE, 0.0);
    float2 posCenter = texcoord.xy;
    float2 posNorth  = posCenter - offset.zy;
    float2 posEast   = posCenter + offset.xz;

    float3 vertCenter = float3(posCenter - 0.5, 1) * GetLinearizedDepth(posCenter);
    float3 vertNorth  = float3(posNorth - 0.5,  1) * GetLinearizedDepth(posNorth);
    float3 vertEast   = float3(posEast - 0.5,   1) * GetLinearizedDepth(posEast);

    return normalize(cross(vertCenter - vertNorth, vertCenter - vertEast)) * 0.5 + 0.5;
}

void PS_DisplayDepth(in float4 position : SV_Position, in float2 texcoord : TEXCOORD, out float3 color : SV_Target)
{
    float3 depth = GetLinearizedDepth(texcoord).xxx;
    float3 normal = GetScreenSpaceNormal(texcoord);

    // Ordered dithering
#if 1
    const float dither_bit = 8.0; // Number of bits per channel. Should be 8 for most monitors.
    // Calculate grid position
    float grid_position = frac(dot(texcoord, (BUFFER_SCREEN_SIZE * float2(1.0 / 16.0, 10.0 / 36.0)) + 0.25));
    // Calculate how big the shift should be
    float dither_shift = 0.25 * (1.0 / (pow(2, dither_bit) - 1.0));
    // Shift the individual colors differently, thus making it even harder to see the dithering pattern
    float3 dither_shift_RGB = float3(dither_shift, -dither_shift, dither_shift); // Subpixel dithering
    // Modify shift acording to grid position.
    dither_shift_RGB = lerp(2.0 * dither_shift_RGB, -2.0 * dither_shift_RGB, grid_position);
    depth += dither_shift_RGB;
#endif

    color = depth;
    if (iUIPresentType == 1)
        color = normal;
    if (iUIPresentType == 2)
        color = lerp(normal, depth, step(BUFFER_WIDTH * 0.5, position.x));

    if (bUIShowOffset)
    {
        float3 color_orig = tex2D(ReShade::BackBuffer, texcoord).rgb;

        // Blend depth and back buffer color with 'overlay' so the offset is more noticeable
        color = lerp(2 * color * color_orig, 1.0 - 2.0 * (1.0 - color) * (1.0 - color_orig), max(color.r, max(color.g, color.b)) < 0.5 ? 0.0 : 1.0);
    }
}

technique DisplayDepth <
    ui_tooltip =
        "此着色器帮助你设置正确的深度输入预处理器设置。\n"
        "要设置这些设置，请点击'编辑全局预处理器定义'并在那里设置 - 而不是在此着色器中。\n"
        "然后这些设置将对所有着色器生效，包括这个。\n"
        "\n"
        "默认情况下，计算的法线和深度会并排显示。\n"
        "法线（左侧）应该看起来平滑，当看向地平线时地面应该是绿色的。\n"
        "深度（右侧）应该显示近处物体较暗，远处物体逐渐变亮。\n";
    ui_tooltip_ja_jp =
        "これは、深度バッファの入力をReShade側の計算式に合わせる調節をするための、設定作業の支援に特化した特殊な扱いのエフェクトです。\n"
        "初期状態では「両方を表示」が選択されており、左に法線マップ、右に深度マップが表示されます。\n"
        "\n"
        "法線マップ(左側)は、形状を滑らかに表現します。正しい設定では、全体的に青緑風で、地平線を見たときに地面が緑を帯びた色になります。\n"
        "深度マップ(右側)は、形状の遠近を白黒で表現します。正しい設定では、近くの形状ほど黒く、遠くの形状ほど白くなります。\n"
        "\n"
#if ADDON_ADJUST_DEPTH
        "設定を完了するには、DisplayDepth.fxエフェクトの変数の一覧にある'設定に保存して反映する'ボタンをクリックして下さい。\n"
#else
        "設定を完了するには、エフェクト変数の編集画面にある'プリプロセッサの定義を編集'ボタンをクリックした後に開くダイアログに入力して下さい。\n"
#endif
        "すると、インストール先のゲームに対して共通の設定として保存され、他のプリセットでも正しく表示されるようになります。";
>

{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_DisplayDepth;
    }
}
