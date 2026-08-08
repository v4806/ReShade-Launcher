#include "lilium__include/inverse_tone_mappers.fxh"


#if (defined(IS_ANALYSIS_CAPABLE_API) \
  && defined(IS_HDR_CSP))


//#include "lilium__include/draw_text_fix.fxh"

//#define ENABLE_DICE

namespace Ui
{
  namespace Itm
  {
    namespace Global
    {
      uniform uint ItmMethod
      <
        ui_category = "全局";
        ui_label    = "逆色调映射方法";
        ui_tooltip  = "BT.2446 方法 A："
                 "\n" "  根据输入和目标亮度扩展图像的整个范围。"
                 "\n" "  最初设计用于将 100 尼特逆色调映射到 1000 尼特"
                 "\n" "  因此无法处理过大的亮度扩展。"
                 "\n" "BT.2446 方法 C："
                 "\n" "  直接映射亮度级别，而不是使用曲线进行扩展。"
                 "\n" "  仅由输入亮度决定目标亮度。"
#ifdef ENABLE_DICE
                 "\n" "Dice 逆向："
                 "\n" "  尚未完成..."
#endif
                 ;
        ui_type     = "combo";
        ui_items    = "BT.2446 方法 A\0"
                      "BT.2446 方法 C\0"
#ifdef ENABLE_DICE
                      "Dice 逆向\0"
#endif
                      ;
      > = 0;

#define ITM_METHOD_BT2446A          0
#define ITM_METHOD_BT2446C          1
#define ITM_METHOD_DICE_INVERSE     2

      uniform uint InputTrc
      <
        ui_category = "全局";
        ui_label    = "输入伽马";
        ui_tooltip  = "\"带 SDR 黑色电平模拟的线性 (scRGB)\" 修复 sRGB<->gamma 2.2 的不匹配";
        ui_type     = "combo";
        ui_items    = "2.2\0"
                      "2.4\0"
                      "线性 (scRGB)\0"
                      "带 SDR 黑色电平模拟的线性 (scRGB)\0"
                      "sRGB\0";
      > = 0;

#define CONTENT_TRC_GAMMA_22                    0
#define CONTENT_TRC_GAMMA_24                    1
#define CONTENT_TRC_LINEAR                      2
#define CONTENT_TRC_LINEAR_WITH_BLACK_FLOOR_EMU 3
#define CONTENT_TRC_SRGB                        4

      uniform uint OverbrightHandling
      <
        ui_label    = "超亮位处理";
        ui_tooltip  = "- 电影式渐变使用伽马函数的逆函数创建平滑过渡"
                 "\n" "- 线性直接取输入值而不做任何修改"
                 "\n" "- 应用伽马正常应用伽马，会导致亮度指数增长，可能不理想"
                 "\n" "- 截断将超亮位截断掉（主要用于测试）";
        ui_type     = "combo";
        ui_items    = "电影式渐变 (S曲线)\0"
                      "线性\0"
                      "应用伽马\0"
                      "截断\0";
      > = 0;

#define OVERBRIGHT_HANDLING_S_CURVE     0
#define OVERBRIGHT_HANDLING_LINEAR      1
#define OVERBRIGHT_HANDLING_APPLY_GAMMA 2
#define OVERBRIGHT_HANDLING_CLAMP       3

      uniform float TargetBrightness
      <
        ui_category = "全局";
        ui_label    = "目标亮度";
        ui_type     = "drag";
        ui_units    = " 尼特";
        ui_min      = 1.f;
        ui_max      = 10000.f;
        ui_step     = 10.f;
      > = 600.f;
    }

    namespace Bt2446A
    {
      uniform uint Bt2446AProcessingMode
      <
        ui_category = "BT.2446 方法 A";
        ui_label    = "处理模式";
        ui_tooltip  = "类YCbCr：完美模拟原始 YCbCr 处理的效果"
                 "\n" "亮度：根据亮度缩放 RGB";
        ui_type     = "combo";
        ui_items    = "亮度（看起来更自然）\0"
                      "类YCbCr（看起来像原版）\0";
      > = 0;

      uniform float Bt2446AInputBrightness
      <
        ui_category = "BT.2446 方法 A";
        ui_label    = "输入白点";
        ui_tooltip  = "将亮度设置为此值以进行逆色调映射处理。"
                 "\n" "控制平均亮度。"
                 "\n"
                 "\n" "如果只想改变平均亮度，"
                 "\n" "请将\"输入白点\"和\"最大输入亮度\""
                 "\n" "调整为相同的值。"
                 "\n"
                 "\n" "如果高于\"最大输入亮度\"，则此值为\"最大输入亮度\"！"
                 "\n" "不能高于\"目标亮度\"！";
        ui_type     = "drag";
        ui_units    = " 尼特";
        ui_min      = 1.f;
        ui_max      = 1200.f;
        ui_step     = 0.1f;
      > = 100.f;

      uniform float Bt2446AMaxInputBrightness
      <
        ui_category = "BT.2446 方法 A";
        ui_label    = "最大输入亮度";
        ui_tooltip  = "控制多少\"超亮\"亮度将在逆色调映射处理的"
                 "\n" "有效范围内被处理。"
                 "\n" "如果超亮值高于此值，它们将呈指数级快速增长！"
                 "\n" "在应用逆色调映射着色器之前，"
                 "\n" "使用\"将 SDR 映射到 HDR\"和\"HDR 分析\"着色器分析一个合适的值。"
                 "\n"
                 "\n" "如果只想改变平均亮度，"
                 "\n" "请将\"输入白点\"和\"最大输入亮度\""
                 "\n" "调整为相同的值。"
                 "\n"
                 "\n" "如果低于\"输入白点\"，则\"输入白点\"为\"最大输入亮度\"！"
                 "\n" "不能高于\"目标亮度\"！";
        ui_type     = "drag";
        ui_units    = " 尼特";
        ui_min      = 1.f;
        ui_max      = 1200.f;
        ui_step     = 0.1f;
      > = 100.f;

      //uniform bool BT2446A_AUTO_REF_WHITE
      //<
      //  ui_category = "BT.2446 Method A";
      //  ui_label    = "automatically calculate \"reference white luminance\"";
      //> = false;

      uniform float GammaIn
      <
        ui_category = "BT.2446 方法 A";
        ui_label    = "逆色调映射前伽马调整";
        ui_type     = "drag";
        ui_min      = -0.4f;
        ui_max      =  0.6f;
        ui_step     =  0.005f;
      > = 0.f;

      uniform float GammaOut
      <
        ui_category = "BT.2446 方法 A";
           ui_label = "逆色调映射后伽马调整";
            ui_type = "drag";
             ui_min = -1.f;
             ui_max =  1.f;
            ui_step =  0.005f;
      > = 0.f;
    }

    namespace Bt2446C
    {
      uniform float Bt2446CInputBrightness
      <
        ui_category = "BT.2446 方法 C";
        ui_label    = "输入亮度";
        ui_tooltip  = "同时控制输出亮度："
                 "\n" "103.2 尼特 ->  400 尼特"
                 "\n" "107.1 尼特 ->  500 尼特"
                 "\n" "110.1 尼特 ->  600 尼特"
                 "\n" "112.6 尼特 ->  700 尼特"
                 "\n" "114.8 尼特 ->  800 尼特"
                 "\n" "116.7 尼特 ->  900 尼特"
                 "\n" "118.4 尼特 -> 1000 尼特";
        ui_type     = "drag";
        ui_units    = " 尼特";
        ui_min      = 1.f;
        ui_max      = 1200.f;
        ui_step     = 0.01f;
      > = 100.f;

      uniform float Alpha
      <
        ui_category = "BT.2446 方法 C";
        ui_label    = "透明度";
        ui_tooltip  = "更好地保留无彩色（无颜色）亮度级别。";
        ui_type     = "drag";
        ui_min      = 0.f;
        ui_max      = 0.33f;
        ui_step     = 0.001f;
      > = 0.33f;

      //uniform float K1
      //<
      //  ui_category = "BT.2446 Method C";
      //     ui_label = "k1";
      //      ui_type = "drag";
      //       ui_min = 0.001f;
      //       ui_max = 1.f;
      //      ui_step = 0.001f;
      //> = 0.83802f;
      //
      //uniform float InflectionPoint
      //<
      //  ui_category = "BT.2446 Method C";
      //     ui_label = "inflection point";
      //      ui_type = "drag";
      //       ui_min = 0.001f;
      //       ui_max = 100.f;
      //      ui_step = 0.001f;
      //> = 58.535046646;

      //uniform bool AchromaticCorrection
      //<
      //  ui_category = "BT.2446 Method C";
      //  ui_label    = "use achromatic correction for really bright elements";
      //> = false;
      //
      //uniform float Sigma
      //<
      //  ui_category = "BT.2446 Method C";
      //     ui_label = "correction factor";
      //      ui_type = "drag";
      //       ui_min = 0.f;
      //       ui_max = 10.f;
      //      ui_step = 0.001f;
      //> = 0.5f;
    }

#ifdef ENABLE_DICE
    namespace Dice
    {
      uniform float DiceInputBrightness
      <
        ui_category = "Dice";
        ui_label    = "输入亮度";
        ui_tooltip  = "不能高于\"目标亮度\"";
        ui_type     = "drag";
        ui_min      = 1.f;
        ui_max      = 400.f;
        ui_step     = 0.1f;
      > = 100.f;

      uniform float ShoulderStart
      <
        ui_category = "Dice";
        ui_label    = "肩部开始点";
        ui_tooltip  = "设置亮度扩展开始的位置";
        ui_type     = "drag";
        ui_units    = "%%";
        ui_min      = 0.1f;
        ui_max      = 100.f;
        ui_step     = 0.1f;
      > = 50.f;
    }
#endif //ENABLE_DICE
  }
}


//uniform uint EXPAND_GAMUT
//<
//  ui_label   = "Vivid HDR";
//  ui_type    = "combo";
//  ui_items   = "no\0"
//               "my expanded colourspace\0"
//               "expand colourspace\0"
//               "brighter highlights\0";
//  ui_tooltip = "interesting gamut expansion things from Microsoft\n"
//               "and me ;)\n"
//               "makes things look more colourful";
//> = 0;


void PS_InverseToneMapping(
      float4 Position : SV_Position,
  out float4 Output   : SV_Target0)
{
  float4 inputColour = tex2Dfetch(SamplerBackBuffer, int2(Position.xy));

  float3 colour = inputColour.rgb;

  switch (Ui::Itm::Global::InputTrc)
  {
    case CONTENT_TRC_GAMMA_22:
    {
      BRANCH(x)
      if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_S_CURVE)
      {
        colour = Csp::Trc::ExtendedGamma22SCurveTo::Linear(colour);
      }
      else if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_LINEAR)
      {
        colour = Csp::Trc::ExtendedGamma22LinearTo::Linear(colour);
      }
      else if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_APPLY_GAMMA)
      {
        colour = sign(colour) * pow(abs(colour), 2.2f);
      }
      else
      {
        colour = saturate(colour);
        colour = pow(colour, 2.2f);
      }
    }
    break;
    case CONTENT_TRC_GAMMA_24:
    {
      BRANCH(x)
      if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_S_CURVE)
      {
        colour = Csp::Trc::ExtendedGamma24SCurveTo::Linear(colour);
      }
      else if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_LINEAR)
      {
        colour = Csp::Trc::ExtendedGamma24LinearTo::Linear(colour);
      }
      else if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_APPLY_GAMMA)
      {
        colour = sign(colour) * pow(abs(colour), 2.4f);
      }
      else
      {
        colour = saturate(colour);
        colour = pow(colour, 2.4f);
      }
    }
    break;
    case CONTENT_TRC_LINEAR:
    {
      BRANCH(x)
      if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_CLAMP)
      {
        colour = saturate(colour);
      }
    }
    break;
    case CONTENT_TRC_LINEAR_WITH_BLACK_FLOOR_EMU:
    {
      BRANCH(x)
      if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_S_CURVE)
      {
        colour = Csp::Trc::ExtendedGamma22SCurveTo::Linear(Csp::Trc::LinearTo::Srgb(colour));
      }
      else if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_LINEAR)
      {
        float3 absColour  = abs(colour);
        float3 signColour = sign(colour);
        [branch]
        if (absColour.r < 1.f)
        {
          colour.r = signColour.r * pow(Csp::Trc::LinearTo::Srgb(absColour.r), 2.2f);
        }
        [branch]
        if (absColour.g < 1.f)
        {
          colour.g = signColour.g * pow(Csp::Trc::LinearTo::Srgb(absColour.g), 2.2f);
        }
        [branch]
        if (absColour.b < 1.f)
        {
          colour.b = signColour.b * pow(Csp::Trc::LinearTo::Srgb(absColour.b), 2.2f);
        }
      }
      else if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_APPLY_GAMMA)
      {
        colour = sign(colour) * pow(Csp::Trc::LinearTo::Srgb(abs(colour)), 2.2f);
      }
      else
      {
        colour = saturate(colour);
        colour = pow(Csp::Trc::LinearTo::Srgb(colour), 2.2f);
      }
    }
    break;
    case CONTENT_TRC_SRGB:
    {
      BRANCH(x)
      if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_S_CURVE)
      {
        colour = Csp::Trc::ExtendedSrgbSCurveTo::Linear(colour);
      }
      else if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_LINEAR)
      {
        colour = Csp::Trc::ExtendedSrgbLinearTo::Linear(colour);
      }
      else if (Ui::Itm::Global::OverbrightHandling == OVERBRIGHT_HANDLING_APPLY_GAMMA)
      {
        colour = sign(colour) * Csp::Trc::SrgbTo::Linear(abs(colour));
      }
      else
      {
        colour = saturate(colour);
        colour = Csp::Trc::SrgbTo::Linear(colour);
      }
    }
    break;
    default:
      break;
  }

  //colour = gamut(colour, EXPAND_GAMUT);

  switch (Ui::Itm::Global::ItmMethod)
  {
    case ITM_METHOD_BT2446A:
    {
      float inputNitsFactor = Ui::Itm::Bt2446A::Bt2446AMaxInputBrightness > Ui::Itm::Bt2446A::Bt2446AInputBrightness
                            ? Ui::Itm::Bt2446A::Bt2446AMaxInputBrightness / Ui::Itm::Bt2446A::Bt2446AInputBrightness
                            : 1.f;

      float referenceWhiteNits = Ui::Itm::Bt2446A::Bt2446AInputBrightness * inputNitsFactor;
            referenceWhiteNits = referenceWhiteNits < Ui::Itm::Global::TargetBrightness
                               ? referenceWhiteNits
                               : Ui::Itm::Global::TargetBrightness;

      colour = Itmos::Bt2446A(colour,
                              Ui::Itm::Bt2446A::Bt2446AProcessingMode,
                              Ui::Itm::Global::TargetBrightness,
                              referenceWhiteNits,
                              inputNitsFactor,
                              Ui::Itm::Bt2446A::GammaIn,
                              Ui::Itm::Bt2446A::GammaOut);
    } break;

    case ITM_METHOD_BT2446C:
    {
      colour = Itmos::Bt2446C(colour,
                              Ui::Itm::Bt2446C::Bt2446CInputBrightness > 153.9f
                            ? 1.539f
                            : Ui::Itm::Bt2446C::Bt2446CInputBrightness / 100.f,
                              0.33f - Ui::Itm::Bt2446C::Alpha);
                              //BT2446C_USE_ACHROMATIC_CORRECTION,
                              //BT2446C_SIGMA);
    } break;

#ifdef ENABLE_DICE

    case ITM_METHOD_DICE_INVERSE:
    {
      float targetNitsNormalised = Ui::Itm::Global::TargetBrightness / 10000.f;
      colour = Itmos::Dice::InverseToneMapper(
                 colour,
                 Csp::Trc::NitsTo::Pq(Ui::Itm::Dice::DiceInputBrightness),
                 Csp::Trc::NitsTo::Pq(Ui::Itm::Dice::ShoulderStart / 100.f * Ui::Itm::Dice::DiceInputBrightness));
    } break;

#endif //ENABLE_DICE
  }

  Output = float4(colour, inputColour.a);
}


technique lilium__inverse_tone_mapping
<
  ui_label = "Lilium's 逆色调映射";
>
{
  pass PS_InverseToneMapping
  {
    VertexShader = VS_PostProcessWithoutTexCoord;
     PixelShader = PS_InverseToneMapping;
  }
}

#else //is hdr API and hdr colour space

ERROR_STUFF

technique lilium__inverse_tone_mapping
<
  ui_label = "Lilium's 逆色调映射 (错误)";
>
VS_ERROR

#endif //is hdr API and hdr colour space
