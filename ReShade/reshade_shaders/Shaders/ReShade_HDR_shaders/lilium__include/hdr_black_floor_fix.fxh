#pragma once

#include "colour_space.fxh"


#if (defined(IS_ANALYSIS_CAPABLE_API) \
  && defined(IS_HDR_CSP))


// TODO:
// add as post adjustment in tone mapping and inverse tone mapping


namespace Ui
{
  namespace HdrBlackFloorFix
  {
    namespace Gamma22Emu
    {
      uniform bool EnableGamma22Emu
      <
        ui_category = "SDR/标准动态范围 黑色电平模拟";
        ui_label    = "启用 SDR/标准动态范围 黑色电平模拟";
        ui_tooltip  = "模拟使用 gamma 2.2 的 SDR 显示器上黑色电平的表现。";
      > = false;

      uniform uint ProcessingColourSpace
      <
        ui_category = "SDR/标准动态范围 黑色电平模拟";
        ui_label    = "处理色彩空间";
        ui_tooltip  = "使用 BT.709 不会将受影响的颜色推出 BT.709 范围。"
                 "\n" "使用 DCI-P3 可能将受影响的颜色推入 DCI-P3 范围。"
                 "\n" "使用 BT.2020 可能将受影响的颜色推入 DCI-P3 和 BT.2020 范围。";
        ui_type     = "combo";
        ui_items    = "BT.709\0"
                      "DCI-P3\0"
                      "BT.2020\0";
      > = 0;

#define HDR_BF_FIX_CSP_BT709  0
#define HDR_BF_FIX_CSP_DCI_P3 1
#define HDR_BF_FIX_CSP_BT2020 2

      uniform float WhitePoint
      <
        ui_category = "SDR/标准动态范围 黑色电平模拟";
        ui_label    = "处理截止点";
        ui_tooltip  = "应处理多少低范围区域。";
        ui_type     = "drag";
        ui_units    = " 尼特";
        ui_min      = 40.f;
        ui_max      = 300.f;
        ui_step     = 0.5f;
      > = 80.f;

      uniform bool OnlyLowerBlackLevels
      <
        ui_category = "SDR/标准动态范围 黑色电平模拟";
        ui_label    = "仅降低黑色电平";
        ui_tooltip  = "gamma 2.2 模拟会降低黑色电平并略微提升高光。"
                 "\n" "此选项仅启用黑色电平的降低。";
      > = false;
    }

    namespace Lowering
    {
      uniform bool EnableLowering
      <
        ui_category = "黑色电平降低";
        ui_label    = "启用黑色电平降低";
      > = false;

      uniform uint ProcessingMode
      <
        ui_category = "黑色电平降低";
        ui_label    = "黑色电平降低处理模式";
        ui_type     = "combo";
        ui_tooltip  = "ICtCp:     在 ICtCp 空间处理（最佳质量）"
                 "\n" "YCbCr:     在 YCbCr 空间处理"
                 "\n" "YRGB:      根据亮度处理 RGB"
                 "\n" "RGB in PQ: 根据亮度处理 PQ 编码的 RGB"
                 "\n" "RGB:       根据亮度处理 RGB（不同方法）";
        ui_items    = "ICtCp\0"
                      "YCbCr\0"
                      "YRGB\0"
                      "RGB in PQ/PQ编码的RGB\0"
                      "RGB\0";
      > = 0;

#define PRO_MODE_ICTCP     0
#define PRO_MODE_YCBCR     1
#define PRO_MODE_YRGB      2
#define PRO_MODE_RGB_IN_PQ 3
#define PRO_MODE_RGB       4

      uniform float OldBlackPoint
      <
        ui_category  = "黑色电平降低";
        ui_label     = "原黑色点";
        ui_type      = "slider";
        ui_units     = " 尼特";
        ui_min       = 0.f;
        ui_max       = 0.5f;
        ui_step      = 0.0000001f;
      > = 0.f;

      uniform float RollOffStoppingPoint
      <
        ui_category  = "黑色电平降低";
        ui_label     = "渐变停止点";
        ui_tooltip   = "使用多少低图像范围"
                  "\n" "从新黑色点渐变过渡。";
        ui_type      = "drag";
        ui_units     = " 尼特";
        ui_min       = 1.f;
        ui_max       = 20.f;
        ui_step      = 0.01f;
      > = 10.f;

      uniform float NewBlackPoint
      <
        ui_category  = "黑色电平降低";
        ui_label     = "新黑色点";
        ui_tooltip   = "可以为负值以获得真正的 0 黑色点。"
                  "\n" "因为某些处理模式无法在所有情况下达到真正的 0。";
        ui_type      = "drag";
        ui_units     = " 尼特";
        ui_min       = -0.1f;
        ui_max       = 0.1f;
        ui_step      = 0.0000001f;
      > = 0.f;
    }
  }
}


float3 Gamma22Emulation(
  const float3 Colour,
  const float  WhitePointNormalised)
{
  float3 correctCspColour;

#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)

  if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_DCI_P3)
  {
    correctCspColour = Csp::Mat::Bt709To::DciP3(Colour);
  }
  else if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT2020)
  {
    correctCspColour = Csp::Mat::Bt709To::Bt2020(Colour);
  }

#elif defined(IS_HDR10_LIKE_CSP)

  if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT709)
  {
    correctCspColour = Csp::Mat::Bt2020To::Bt709(Colour);
  }
  else if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_DCI_P3)
  {
    correctCspColour = Csp::Mat::Bt2020To::DciP3(Colour);
  }

#endif //IS_XXX_LIKE_CSP

  else
  {
    correctCspColour = Colour;
  }

  const bool3 isInProcessingRange = correctCspColour < WhitePointNormalised;
  const bool3 isAbove0            = correctCspColour >  0.f;

  const bool3 needsProcessing = isInProcessingRange && isAbove0;

  float3 processedColour = correctCspColour;

  if (needsProcessing.r)
  {
    processedColour.r = pow(Csp::Trc::LinearTo::Srgb(correctCspColour.r / WhitePointNormalised), 2.2f) * WhitePointNormalised;

    if (Ui::HdrBlackFloorFix::Gamma22Emu::OnlyLowerBlackLevels
     && processedColour.r > correctCspColour.r)
    {
      processedColour.r = correctCspColour.r;
    }
  }
  if (needsProcessing.g)
  {
    processedColour.g = pow(Csp::Trc::LinearTo::Srgb(correctCspColour.g / WhitePointNormalised), 2.2f) * WhitePointNormalised;

    if (Ui::HdrBlackFloorFix::Gamma22Emu::OnlyLowerBlackLevels
     && processedColour.g > correctCspColour.g)
    {
      processedColour.g = correctCspColour.g;
    }
  }
  if (needsProcessing.b)
  {
    processedColour.b = pow(Csp::Trc::LinearTo::Srgb(correctCspColour.b / WhitePointNormalised), 2.2f) * WhitePointNormalised;

    if (Ui::HdrBlackFloorFix::Gamma22Emu::OnlyLowerBlackLevels
     && processedColour.b > correctCspColour.b)
    {
      processedColour.b = correctCspColour.b;
    }
  }

  return processedColour;
}

#define BLACK_POINT_ADAPTION(T)                            \
  T BlackPointAdaption(                                    \
    const T     C1,                                        \
    const float OldBlackPoint,                             \
    const float RollOffMinusOldBlackPoint,                 \
    const float MinLum)                                    \
  {                                                        \
    T C2;                                                  \
                                                           \
    /*E1*/                                                 \
    C2 = (C1 - OldBlackPoint) / RollOffMinusOldBlackPoint; \
                                                           \
    /*E3*/                                                 \
    C2 += MinLum * pow((1.f - C2), 4.f);                   \
                                                           \
    /*E4*/                                                 \
    return C2 * RollOffMinusOldBlackPoint + OldBlackPoint; \
  }

BLACK_POINT_ADAPTION(float)
BLACK_POINT_ADAPTION(float3)


float GetNits(const float3 Colour)
{
  if (Ui::HdrBlackFloorFix::Gamma22Emu::EnableGamma22Emu)
  {
    if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT709)
    {
      return dot(Colour, Csp::Mat::Bt709ToXYZ[1].rgb);
    }
    else if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_DCI_P3)
    {
      return dot(Colour, Csp::Mat::DciP3ToXYZ[1].rgb);
    }
    else //if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT2020)
    {
      return dot(Colour, Csp::Mat::Bt2020ToXYZ[1].rgb);
    }
  }

#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)

  return dot(Colour, Csp::Mat::Bt709ToXYZ[1].rgb);

#elif defined(IS_HDR10_LIKE_CSP)

  return dot(Colour, Csp::Mat::Bt2020ToXYZ[1].rgb);

#endif
}


void ConvertToWorkingCsp(inout float3 Colour)
{
  if (Ui::HdrBlackFloorFix::Gamma22Emu::EnableGamma22Emu)
  {
    if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT709)
    {
      Colour = Csp::Mat::Bt709To::Bt2020(Colour);
    }
    else if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_DCI_P3)
    {
      Colour = Csp::Mat::DciP3To::Bt2020(Colour);
    }
  }
#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)

  Colour = Csp::Mat::Bt709To::Bt2020(Colour);

#endif
}


float3 ConvertToOutputCspAfterProcessing(const float3 Colour)
{
  float3 outputColour;

#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)

  outputColour  = Csp::Mat::Bt2020To::Bt709(Colour);
  outputColour *= 125.f;

#elif (ACTUAL_COLOUR_SPACE == CSP_HDR10)

  outputColour = Csp::Trc::LinearTo::Pq(Colour);

#elif (ACTUAL_COLOUR_SPACE == CSP_HLG)

  outputColour = Csp::Trc::LinearTo::Hlg(Colour);

#endif //ACTUAL_COLOUR_SPACE ==

  return outputColour;
}


float3 ConvertToOutputCspWithoutProcessing(const float3 Colour)
{

  if (Ui::HdrBlackFloorFix::Gamma22Emu::EnableGamma22Emu)
  {
    float3 outputColour;

#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)

    if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_DCI_P3)
    {
      outputColour = Csp::Mat::DciP3To::Bt709(Colour);
    }
    else if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT2020)
    {
      outputColour = Csp::Mat::Bt2020To::Bt709(Colour);
    }

    outputColour *= 125.f;

#elif defined(IS_HDR10_LIKE_CSP)

    if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT709)
    {
      outputColour = Csp::Mat::Bt709To::Bt2020(Colour);
    }
    else if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_DCI_P3)
    {
      outputColour = Csp::Mat::DciP3To::Bt2020(Colour);
    }

#if (ACTUAL_COLOUR_SPACE == CSP_HDR10)

    outputColour = Csp::Trc::LinearTo::Pq(outputColour);

#elif (ACTUAL_COLOUR_SPACE == CSP_HLG)

    outputColour = Csp::Trc::LinearTo::Hlg(outputColour);

#endif
    return outputColour;

#endif

  }

#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)

  return Colour * 125.f;

#elif (ACTUAL_COLOUR_SPACE == CSP_HDR10)

  return Csp::Trc::LinearTo::Pq(Colour);

#elif (ACTUAL_COLOUR_SPACE == CSP_HLG)

  return Csp::Trc::LinearTo::Hlg(Colour);

#endif
}


float3 LowerBlackFloor(
        float3 Rgb,
  const float  RollOffStoppingPoint,
  const float  OldBlackPoint,
  const float  RollOffMinusOldBlackPoint,
  const float  MinLum)
{
  // ICtCp mode
  if (Ui::HdrBlackFloorFix::Lowering::ProcessingMode == PRO_MODE_ICTCP)
  {
    //to L'M'S'
    float3 pqLms;

    if (Ui::HdrBlackFloorFix::Gamma22Emu::EnableGamma22Emu)
    {
      if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT709)
      {
        pqLms = Csp::Ictcp::Bt709To::PqLms(Rgb);
      }
      else if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_DCI_P3)
      {
        pqLms = Csp::Ictcp::DciP3To::PqLms(Rgb);
      }
      else //if (Ui::HdrBlackFloorFix::Gamma22Emu::ProcessingColourSpace == HDR_BF_FIX_CSP_BT2020)
      {
        pqLms = Csp::Ictcp::Bt2020To::PqLms(Rgb);
      }
    }
    else
    {
#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)

      pqLms = Csp::Ictcp::Bt709To::PqLms(Rgb);

#elif defined(IS_HDR10_LIKE_CSP)

      pqLms = Csp::Ictcp::Bt2020To::PqLms(Rgb);

#endif
    }

    //Intensity
    float i1 = 0.5f * pqLms.x + 0.5f * pqLms.y;

    if (i1 <= RollOffStoppingPoint)
    {
      float i2 = BlackPointAdaption(i1,
                                    OldBlackPoint,
                                    RollOffMinusOldBlackPoint,
                                    MinLum);

      //to RGB
      float3 outputRgb = Csp::Ictcp::IctcpTo::Bt2020(float3(i2,
                                                            dot(pqLms, Csp::Ictcp::PqLmsToIctcp[1]),
                                                            dot(pqLms, Csp::Ictcp::PqLmsToIctcp[2])));

      outputRgb = max(outputRgb, 0.f);

      return ConvertToOutputCspAfterProcessing(outputRgb);
    }
    else
    {
      return ConvertToOutputCspWithoutProcessing(Rgb);
    }
  }
  // YCbCr mode
  else if (Ui::HdrBlackFloorFix::Lowering::ProcessingMode == PRO_MODE_YCBCR)
  {
    ConvertToWorkingCsp(Rgb);
    float3 inputInPq = Csp::Trc::LinearTo::Pq(Rgb);

    float y1 = dot(inputInPq, Csp::Ycbcr::KBt2020);

    if (y1 <= RollOffStoppingPoint)
    {
      float y2 = BlackPointAdaption(y1,
                                    OldBlackPoint,
                                    RollOffMinusOldBlackPoint,
                                    MinLum);

      //to RGB
      float3 outputRgb = Csp::Ycbcr::YcbcrTo::RgbBt2020(float3(y2,
                                                               (inputInPq.b - y1) / Csp::Ycbcr::KbBt2020,
                                                               (inputInPq.r - y1) / Csp::Ycbcr::KrBt2020));

      outputRgb = max(outputRgb, 0.f);

#if (ACTUAL_COLOUR_SPACE != CSP_HDR10)

      outputRgb = Csp::Trc::PqTo::Linear(outputRgb);
      outputRgb = ConvertToOutputCspAfterProcessing(outputRgb);

#endif
      return outputRgb;
    }
    else
    {
      return ConvertToOutputCspWithoutProcessing(Rgb);
    }
  }
  // YRGB mode
  else if (Ui::HdrBlackFloorFix::Lowering::ProcessingMode == PRO_MODE_YRGB)
  {
    float y1 = GetNits(Rgb);

    float y1InPq = Csp::Trc::LinearTo::Pq(y1);

    if (y1InPq <= RollOffStoppingPoint)
    {
      float y2 = BlackPointAdaption(y1InPq,
                                    OldBlackPoint,
                                    RollOffMinusOldBlackPoint,
                                    MinLum);

      y2 = Csp::Trc::PqTo::Linear(y2);

      float3 outputRgb = y2 / y1 * Rgb;

      return ConvertToOutputCspWithoutProcessing(outputRgb);
    }
    else
    {
      return ConvertToOutputCspWithoutProcessing(Rgb);
    }
  }
  // RGB in PQ mode
  else if (Ui::HdrBlackFloorFix::Lowering::ProcessingMode == PRO_MODE_RGB_IN_PQ)
  {
    float nits = GetNits(Rgb);

    if (nits <= RollOffStoppingPoint)
    {
      ConvertToWorkingCsp(Rgb);
      float3 rgbInPq1 = Csp::Trc::LinearTo::Pq(Rgb);

      float3 rgbInPq2 = BlackPointAdaption(rgbInPq1,
                                           OldBlackPoint,
                                           RollOffMinusOldBlackPoint,
                                           MinLum);

      float3 outputRgb = max(rgbInPq2, 0.f);

#if (ACTUAL_COLOUR_SPACE != CSP_HDR10)

      outputRgb = Csp::Trc::PqTo::Linear(outputRgb);
      outputRgb = ConvertToOutputCspAfterProcessing(outputRgb);

#endif
      return outputRgb;
    }
    else
    {
      return ConvertToOutputCspWithoutProcessing(Rgb);
    }
  }
  // RBG mode
  else // if (Ui::HdrBlackFloorFix::Lowering::ProcessingMode == PRO_MODE_RGB)
  {
    if (GetNits(Rgb) <= RollOffStoppingPoint)
    {
      ConvertToWorkingCsp(Rgb);

      float3 rgb2 = BlackPointAdaption(Rgb,
                                       OldBlackPoint,
                                       RollOffMinusOldBlackPoint,
                                       MinLum);

      float3 outputRgb = max(rgb2, 0.f);

      return ConvertToOutputCspAfterProcessing(outputRgb);
    }
    else
    {
      return ConvertToOutputCspWithoutProcessing(Rgb);
    }
  }

}

#endif //is hdr API and hdr colour space
