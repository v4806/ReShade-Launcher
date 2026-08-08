#include "lilium__include/colour_space.fxh"


#if (defined(IS_ANALYSIS_CAPABLE_API) \
  && defined(IS_HDR_CSP))


uniform uint INPUT_TRC
<
  ui_label    = "输入伽马/传递函数";
  ui_tooltip  = "\"带 SDR 黑色电平模拟的线性 (scRGB)\" 修复 sRGB<->gamma 2.2 的不匹配";
  ui_type     = "combo";
  ui_items    = "2.2\0"
                "2.4\0"
                "线性 (scRGB)\0"
                "带 SDR 黑色电平模拟的线性 (scRGB)\0"
                "sRGB\0"
                "PQ\0";
> = 0;

#define TRC_GAMMA_22                    0
#define TRC_GAMMA_24                    1
#define TRC_LINEAR                      2
#define TRC_LINEAR_WITH_BLACK_FLOOR_EMU 3
#define TRC_SRGB                        4
#define TRC_PQ                          5

uniform uint OVERBRIGHT_HANDLING
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

uniform float SDR_WHITEPOINT_NITS
<
  ui_label   = "SDR/标准动态范围 白点";
  ui_tooltip = "仅在输入伽马不是 PQ 时有效！";
  ui_type    = "drag";
  ui_units   = " 尼特";
  ui_min     = 1.f;
  ui_max     = 300.f;
  ui_step    = 1.f;
> = 80.f;

uniform bool ENABLE_GAMMA_ADJUST
<
  ui_label   = "启用伽马调整";
  ui_tooltip = "仅在输入伽马不是 PQ 时有效！";
> = false;

uniform float GAMMA_ADJUST
<
  ui_label   = "伽马调整";
  ui_tooltip = "仅在输入伽马不是 PQ 时有效！";
  ui_type    = "drag";
  ui_min     = -1.f;
  ui_max     =  1.f;
  ui_step    =  0.001f;
> = 0.f;

uniform bool ENABLE_CLAMPING
<
  ui_category = "截断";
  ui_label    = "启用截断";
> = false;

uniform float CLAMP_NEGATIVE_TO
<
  ui_category = "截断";
  ui_label    = "将负值截断至";
  ui_type     = "drag";
  ui_min      = -125.f;
  ui_max      = 0.f;
  ui_step     = 0.1f;
> = -125.f;

uniform float CLAMP_POSITIVE_TO
<
  ui_category = "截断";
  ui_label    = "将正值截断至";
  ui_type     = "drag";
  ui_min      = 1.f;
  ui_max      = 125.f;
  ui_step     = 0.1f;
> = 125.f;


// convert BT.709 to BT.2020
float3 ConditionallyConvertBt709ToBt2020(float3 Colour)
{
#if (ACTUAL_COLOUR_SPACE == CSP_HDR10 \
  || ACTUAL_COLOUR_SPACE == CSP_PS5)
  Colour = Csp::Mat::Bt709To::Bt2020(Colour);
#endif
  return Colour;
}

// convert HDR10 to linear BT.2020
float3 ConditionallyLineariseHdr10(float3 Colour)
{
#if (ACTUAL_COLOUR_SPACE != CSP_HDR10)
  Colour = Csp::Trc::PqTo::Linear(Colour);
#endif
  return Colour;
}

// convert linear BT.2020 to HDR10
float3 ConditionallyConvertLinearBt2020ToHdr10(float3 Colour)
{
#if (ACTUAL_COLOUR_SPACE == CSP_HDR10)
  Colour = Csp::Trc::LinearTo::Pq(Colour);
#endif
  return Colour;
}

// convert BT.2020 to BT.709
float3 ConditionallyConvertBt2020To709(float3 Colour)
{
#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)
  Colour = Csp::Mat::Bt2020To::Bt709(Colour);
#endif
  return Colour;
}


void PS_MapSdrIntoHdr(
      float4 Position : SV_Position,
  out float4 Output   : SV_Target0)
{
  float4 inputColour = tex2Dfetch(SamplerBackBuffer, int2(Position.xy));

  float3 colour = inputColour.rgb;

  static const bool inputTrcIsPq = INPUT_TRC == TRC_PQ;

  switch(INPUT_TRC)
  {
    case TRC_GAMMA_22:
    {
      BRANCH(x)
      if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_S_CURVE)
      {
        colour = Csp::Trc::ExtendedGamma22SCurveTo::Linear(colour);
      }
      else if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_LINEAR)
      {
        colour = Csp::Trc::ExtendedGamma22LinearTo::Linear(colour);
      }
      else if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_APPLY_GAMMA)
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
    case TRC_GAMMA_24:
    {
      BRANCH(x)
      if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_S_CURVE)
      {
        colour = Csp::Trc::ExtendedGamma24SCurveTo::Linear(colour);
      }
      else if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_LINEAR)
      {
        colour = Csp::Trc::ExtendedGamma24LinearTo::Linear(colour);
      }
      else if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_APPLY_GAMMA)
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
    case TRC_LINEAR:
    {
      BRANCH(x)
      if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_CLAMP)
      {
        colour = saturate(colour);
      }
    }
    break;
    case TRC_LINEAR_WITH_BLACK_FLOOR_EMU:
    {
      BRANCH(x)
      if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_S_CURVE)
      {
        colour = Csp::Trc::ExtendedGamma22SCurveTo::Linear(Csp::Trc::LinearTo::Srgb(colour));
      }
      else if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_LINEAR)
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
      else if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_APPLY_GAMMA)
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
    case TRC_SRGB:
    {
      BRANCH(x)
      if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_S_CURVE)
      {
        colour = Csp::Trc::ExtendedSrgbSCurveTo::Linear(colour);
      }
      else if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_LINEAR)
      {
        colour = Csp::Trc::ExtendedSrgbLinearTo::Linear(colour);
      }
      else if (OVERBRIGHT_HANDLING == OVERBRIGHT_HANDLING_APPLY_GAMMA)
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
    case TRC_PQ:
    {
      //scRGB
      colour = ConditionallyLineariseHdr10(colour);
      colour = ConditionallyConvertBt2020To709(colour);

#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)
      colour *= 125.f;
#elif (ACTUAL_COLOUR_SPACE == CSP_PS5)
      colour *= 100.f;
#endif
    }
    break;
    default:
      break;
  }

  if (ENABLE_CLAMPING)
  {
    colour = clamp(colour, CLAMP_NEGATIVE_TO, CLAMP_POSITIVE_TO);
  }

  if (ENABLE_GAMMA_ADJUST
   && !inputTrcIsPq)
  {
    colour = Csp::Trc::ExtendedGammaAdjust(colour, 1.f + GAMMA_ADJUST);
  }

//  if (dot(Bt709ToXYZ[1].rgb, colour) < 0.f)
//    colour = float3(0.f, 0.f, 0.f);

  if (!inputTrcIsPq)
  {

#if (ACTUAL_COLOUR_SPACE == CSP_SCRGB)

    colour *= (SDR_WHITEPOINT_NITS / 80.f);

#elif (ACTUAL_COLOUR_SPACE == CSP_HDR10)

    colour *= (SDR_WHITEPOINT_NITS / 10000.f);

#elif (ACTUAL_COLOUR_SPACE == CSP_PS5)

    colour *= (SDR_WHITEPOINT_NITS / 100.f);

#endif

    //HDR10
    colour = ConditionallyConvertBt709ToBt2020(colour);
    colour = ConditionallyConvertLinearBt2020ToHdr10(colour);
  }

  //colour = fixNAN(colour);

  Output = float4(colour, inputColour.a);
}


technique lilium__map_SDR_into_HDR
<
  ui_label = "Lilium's 将 SDR/标准动态范围 映射到 HDR/高动态范围";
>
{
  pass PS_MapSdrIntoHdr
  {
    VertexShader = VS_PostProcessWithoutTexCoord;
     PixelShader = PS_MapSdrIntoHdr;
  }
}

#else //is hdr API and hdr colour space

ERROR_STUFF

technique lilium__map_SDR_into_HDR
<
  ui_label = "Lilium's 将 SDR/标准动态范围 映射到 HDR/高动态范围 (错误)";
>
VS_ERROR

#endif //is hdr API and hdr colour space
