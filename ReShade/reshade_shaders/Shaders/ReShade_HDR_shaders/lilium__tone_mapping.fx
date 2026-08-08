
#ifndef SHOW_ADAPTIVE_MAX_NITS
  #define SHOW_ADAPTIVE_MAX_NITS NO
#endif

#include "lilium__include/tone_mappers.fxh"

#if (SHOW_ADAPTIVE_MAX_NITS == YES)
  #include "lilium__include/draw_text_fix.fxh"
#endif


#if (defined(IS_COMPUTE_CAPABLE_API) \
  && defined(IS_HDR_CSP))

#if 0
  #include "lilium__include/HDR_black_floor_fix.fxh"
#endif


//#define BT2446A_MOD1_ENABLE


#undef CIE_DIAGRAM
#undef IGNORE_NEAR_BLACK_VALUES_FOR_CSP_DETECTION


namespace RuntimeValues
{
  uniform float Frametime
  <
    source = "frametime";
  >;
}

namespace Ui
{
  namespace Tm
  {
    namespace Global
    {
      uniform uint TmMethod
      <
        ui_category = "全局";
        ui_label    = "色调映射方法";
        ui_tooltip  = "BT.2390 EETF："
                 "\n" "  是高光压缩器。"
                 "\n" "  仅根据"拐点开始"压缩高光。"
                 "\n" "  决定高光压缩从何处开始。"
                 "\n" "BT.2446 方法 A："
                 "\n" "  与其他色调映射器相比，此方法尝试压缩图像的整个亮度范围"
                 "\n" "  而不仅仅是压缩高光。"
                 "\n" "  最初设计用于将 1000 尼特色调映射到 100 尼特"
                 "\n" "  因此无法处理过大的亮度差异压缩。"
                 "\n" "  例如 10000 尼特到 800 尼特，因为它试图压缩整个亮度范围。"
                 "\n" "Dice："
                 "\n" "  工作原理类似于 BT.2390。"
                 "\n" "  压缩曲线略有不同，速度稍快。";
        ui_type     = "combo";
        ui_items    = "BT.2390 EETF\0"
                      "BT.2446 方法 A\0"
                      "Dice\0"
      #ifdef BT2446A_MOD1_ENABLE
                      "BT.2446A mod1\0"
      #endif
                      ;
      > = 0;

#define TM_METHOD_BT2390       0
#define TM_METHOD_BT2446A      1
#define TM_METHOD_DICE         2
#define TM_METHOD_BT2446A_MOD1 3

      uniform uint Mode
      <
        ui_category = "全局";
        ui_label    = "色调映射模式";
        ui_tooltip  = "  静态：仅根据指定的最大亮度进行色调映射"
                 "\n" "自适应：最大亮度会随时间适应实际的最大亮度"
                 "\n" "          别忘了开启"自适应模式"技术！";
        ui_type     = "combo";
        ui_items    = "静态\0"
                      "自适应\0";
      > = 0;

#define TM_MODE_STATIC   0
#define TM_MODE_ADAPTIVE 1

      uniform float TargetBrightness
      <
        ui_category = "全局";
        ui_label    = "目标亮度";
        ui_type     = "drag";
        ui_units    = " 尼特";
        ui_min      = 0.f;
        ui_max      = 10000.f;
        ui_step     = 5.f;
      > = 600.f;
    } //Global

    namespace StaticMode
    {
      uniform float MaxNits
      <
        ui_category = "静态色调映射";
        ui_label    = "最大色调映射亮度";
        ui_tooltip  = "超过此值的所有内容将被裁剪！";
        ui_type     = "drag";
        ui_units    = " 尼特";
        ui_min      = 0.f;
        ui_max      = 10000.f;
        ui_step     = 5.f;
      > = 10000.f;
    } //StaticMode

    namespace Bt2390
    {
      uniform uint ProcessingModeBt2390
      <
        ui_category = "BT.2390 EETF";
        ui_label    = "处理模式";
        ui_tooltip  = "ICtCp：在 ICtCp 空间处理（最佳质量）"
                 "\n" "YRGB：根据亮度处理 RGB"
                 "\n" "RGB：单独处理每个通道";
        ui_type     = "combo";
        ui_items    = "ICtCp\0"
                      "YRGB\0"
                      "RGB\0";
      > = 0;

      uniform bool EnableBlowingOutHighlightsBt2390
      <
        ui_category = "BT.2390 EETF";
        ui_label    = "启用高光过曝";
        ui_tooltip  = "为 ICtCp 模式启用高光过曝效果。";
      > = true;

      uniform float OldBlackPoint
      <
        ui_category = "BT.2390 EETF";
        ui_label    = "原黑色点";
        ui_type     = "slider";
        ui_units    = " 尼特";
        ui_min      = 0.f;
        ui_max      = 0.5f;
        ui_step     = 0.000001f;
      > = 0.f;

      uniform float NewBlackPoint
      <
        ui_category = "BT.2390 EETF";
        ui_label    = "新黑色点";
        ui_type     = "slider";
        ui_units    = " 尼特";
        ui_min      = -0.1f;
        ui_max      = 0.1f;
        ui_step     = 0.0001f;
      > = 0.f;

      uniform float KneeOffset
      <
        ui_category = "BT.2390 EETF";
        ui_label    = "拐点偏移";
        ui_tooltip  = "调整亮度压缩曲线开始的位置。"
                 "\n" "值越高，压缩开始得越早。"
                 "\n" "0.5 是规范默认值。";
        ui_type     = "drag";
        ui_min      = 0.5f;
        ui_max      = 1.0f;
        ui_step     = 0.001f;
      > = 0.5f;
    } //Bt2390

    namespace Dice
    {
      uniform uint ProcessingModeDice
      <
        ui_category = "Dice";
        ui_label    = "processing mode";
        ui_tooltip  = "ICtCp: process in ICtCp space (best quality)"
                 "\n" "YRGB:  process RGB according to brightness";
        ui_type     = "combo";
        ui_items    = "ICtCp\0"
                      "YRGB\0";
      > = 0;

      uniform bool EnableBlowingOutHighlightsDice
      <
        ui_category = "Dice";
        ui_label    = "enable blowing out highlights";
        ui_tooltip  = "Enables blowing out highlights for the ICtCp mode.";
      > = true;

      uniform float ShoulderStart
      <
        ui_category = "Dice";
        ui_label    = "shoulder start";
        ui_tooltip  = "Set this to where the brightness compression curve starts."
                 "\n" "In % of the target brightness."
                 "\n" "example:"
                 "\n" "With \"target brightness\" set to \"1000 nits\" and \"shoulder start\" to \"50%\"."
                 "\n" "The brightness compression will start at 500 nits.";
        ui_type     = "drag";
        ui_units    = "%%";
        ui_min      = 10.f;
        ui_max      = 50.f;
        ui_step     = 0.1f;
      > = 25.f;

//      uniform uint WorkingColourSpace
//      <
//        ui_category = "Dice";
//        ui_label    = "processing colour space";
//        ui_tooltip  = "AP0_D65: AP0 primaries with D65 white point"
//                 "\n" "AP0_D65 technically covers every humanly perceivable colour."
//                 "\n" "It's meant for future use if we ever move past the BT.2020 colour space."
//                 "\n" "Just use BT.2020 for now.";
//        ui_type     = "combo";
//        ui_items    = "BT.2020\0"
//                      "AP0_D65\0";
//      > = 0;
    } //Dice

    namespace AdaptiveMode
    {
      uniform float MaxNitsCap
      <
        ui_category = "adaptive tone mapping";
        ui_label    = "cap maximum brightness";
        ui_tooltip  = "Caps maximum brightness that the adaptive maximum brightness can reach."
                 "\n" "Everything above this value will be clipped!";
        ui_type     = "drag";
        ui_units    = " nits";
        ui_min      = 0.f;
        ui_max      = 10000.f;
        ui_step     = 10.f;
      > = 10000.f;

      uniform float TimeToAdapt
      <
        ui_category = "adaptive tone mapping";
        ui_label    = "adaption to maximum brightness";
        ui_tooltip  = "Time it takes to adapt to the current maximum brightness";
        ui_type     = "drag";
        ui_min      = 0.5f;
        ui_max      = 3.f;
        ui_step     = 0.1f;
      > = 1.0f;

      uniform float FinalAdaptStart
      <
        ui_category = "adaptive tone mapping";
        ui_label    = "final adaption starting point";
        ui_tooltip  = "If the difference between the \"maximum brightness\""
                 "\n" "and the \"adaptive maximum brightness\" is smaller than this percentage"
                 "\n" "use the \"final adaption steps\"."
                 "\n" "For flickery games use 90% or lower.";
        ui_type     = "drag";
        ui_units    = "%%";
        ui_min      = 80.f;
        ui_max      = 99.f;
        ui_step     = 0.1f;
      > = 95.f;

      uniform float FinalAdaptSteps
      <
        ui_category = "adaptive tone mapping";
        ui_label    = "final adaption steps";
        ui_tooltip  = "For flickery games use 7.00 or lower.";
        ui_type     = "drag";
        ui_min      = 1.f;
        ui_max      = 10.f;
        ui_step     = 0.05f;
      > = 7.5f;

      uniform float FinalAdaptSpeed
      <
        ui_category = "adaptive tone mapping";
        ui_label    = "final adaption speed";
        ui_tooltip  = "For flickery games use 5.00 or lower.";
        ui_type     = "drag";
        ui_min      = 1.f;
        ui_max      = 10.f;
        ui_step     = 0.05f;
      > = 7.5f;
    } //AdaptiveMode
  }
}

#ifdef BT2446A_MOD1_ENABLE
uniform float TEST_H
<
  ui_category = "mod1";
  ui_label    = "testH";
  ui_type     = "drag";
  ui_min      = -10000.f;
  ui_max      =  10000.f;
  ui_step     =  10.f;
> = 0.f;

uniform float TEST_S
<
  ui_category = "mod1";
  ui_label    = "testS";
  ui_type     = "drag";
  ui_min      = -10000.f;
  ui_max      =  10000.f;
  ui_step     =  10.f;
> = 0.f;
#endif


//static const uint numberOfAdaptiveValues = 1000;
//texture2D TextureAdaptiveNitsValues
//{
//   Width = numberOfAdaptiveValues;
//  Height = 2;
//
//  MipLevels = 0;
//
//  Format = R32F;
//};
//
//sampler2D SamplerAdaptiveNitsValues
//{
//  Texture = TextureAdaptiveNitsValues;
//
//  SRGBTexture = false;
//};
//
//storage2D StorageAdaptiveNitsValues
//{
//  Texture = TextureAdaptiveNitsValues;
//
//  MipLevel = 0;
//};


// Vertex shader generating a triangle covering the entire screen.
// Calculate values only "once" (3 times because it's 3 vertices)
// for the pixel shader.
void VS_PrepareToneMapping(
  in                  uint   VertexID : SV_VertexID,
  out                 float4 Position : SV_Position,
  out                 float2 TexCoord : TEXCOORD0,
  out nointerpolation float4 TmParms0 : TmParms0,
  out nointerpolation float3 TmParms1 : TmParms1)
{
  TexCoord.x = (VertexID == 2) ? 2.f
                               : 0.f;
  TexCoord.y = (VertexID == 1) ? 2.f
                               : 0.f;
  Position = float4(TexCoord * float2(2.f, -2.f) + float2(-1.f, 1.f), 0.f, 1.f);

  TmParms0 = 0.f;
  TmParms1 = 0.f;

#define usedMaxNits TmParms0.x

//  if (Ui::Tm::Global::Mode == TM_MODE_STATIC)
//  {
    usedMaxNits = Ui::Tm::StaticMode::MaxNits;
//  }
//  else
//  {
//    usedMaxNits = tex2Dfetch(SamplerConsolidated, COORDS_ADAPTIVE_NITS);
//  }

  usedMaxNits = max(usedMaxNits, Ui::Tm::Global::TargetBrightness);

  if (Ui::Tm::Global::TmMethod == TM_METHOD_BT2390)
  {

#define bt2390SrcMinPq              TmParms0.y
#define bt2390SrcMaxPq              TmParms0.z
#define bt2390SrcMinMaxPq           TmParms0.yz
#define bt2390SrcMaxPqMinusSrcMinPq TmParms0.w
#define bt2390MinLum                TmParms1.x
#define bt2390MaxLum                TmParms1.y
#define bt2390MinMaxLum             TmParms1.xy
#define bt2390KneeStart             TmParms1.z

    // source min brightness (Lb) in PQ
    // source max brightness (Lw) in PQ
    bt2390SrcMinMaxPq = Csp::Trc::NitsTo::Pq(float2(Ui::Tm::Bt2390::OldBlackPoint,
                                                    usedMaxNits));

    // target min brightness (Lmin) in PQ
    // target max brightness (Lmax) in PQ
    float2 tgtMinMaxPQ = Csp::Trc::NitsTo::Pq(float2(Ui::Tm::Bt2390::NewBlackPoint,
                                                     Ui::Tm::Global::TargetBrightness));

    // this is needed often so precalculate it
    bt2390SrcMaxPqMinusSrcMinPq = bt2390SrcMaxPq - bt2390SrcMinPq;

    bt2390MinMaxLum = (tgtMinMaxPQ - bt2390SrcMinPq) / bt2390SrcMaxPqMinusSrcMinPq;

    // knee start (KS)
    bt2390KneeStart = 1.5f
                    * bt2390MaxLum
                    - Ui::Tm::Bt2390::KneeOffset;

  }
  else if (Ui::Tm::Global::TmMethod == TM_METHOD_DICE)
  {

#define diceTargetNitsInPq    TmParms0.y
#define diceShoulderStartInPq TmParms0.z
#define diceUnused0           TmParms0.w
#define diceUnused1           TmParms1 //.xyz

    diceTargetNitsInPq = Csp::Trc::NitsTo::Pq(Ui::Tm::Global::TargetBrightness);
    diceShoulderStartInPq =
      Csp::Trc::NitsTo::Pq(Ui::Tm::Dice::ShoulderStart
                         / 100.f
                         * Ui::Tm::Global::TargetBrightness);

    diceUnused0 = 0.f;
    diceUnused1 = float3(0.f, 0.f, 0.f);
  }

}


void PS_ToneMapping(
  in                  float4 Position : SV_Position,
  in                  float2 TexCoord : TEXCOORD0,
  in  nointerpolation float4 TmParms0 : TmParms0,
  in  nointerpolation float3 TmParms1 : TmParms1,
  out                 float4 Output   : SV_Target0)
{
  float4 inputColour = tex2Dfetch(SamplerBackBuffer, int2(Position.xy));

  float3 hdr = inputColour.rgb;

  switch (Ui::Tm::Global::TmMethod)
  {
    case TM_METHOD_BT2446A:
    {
      Tmos::Bt2446A(hdr,
                    usedMaxNits,
                    Ui::Tm::Global::TargetBrightness);
    }
    break;
    case TM_METHOD_BT2390:
    {
      Tmos::Bt2390::Eetf(hdr,
                         Ui::Tm::Bt2390::ProcessingModeBt2390,
                         bt2390SrcMinPq,
                         bt2390SrcMaxPq,
                         bt2390SrcMaxPqMinusSrcMinPq,
                         bt2390MinLum,
                         bt2390MaxLum,
                         bt2390KneeStart,
                         Ui::Tm::Bt2390::EnableBlowingOutHighlightsBt2390);
    }
    break;
    case TM_METHOD_DICE:
    {
      Tmos::Dice::ToneMapper(hdr,
                             Ui::Tm::Dice::ProcessingModeDice,
                             diceTargetNitsInPq,
                             diceShoulderStartInPq,
                             Ui::Tm::Dice::EnableBlowingOutHighlightsDice);
    }
    break;

#ifdef BT2446A_MOD1_ENABLE

    case TM_METHOD_BT2446A_MOD1:
    {
      //move test parameters to vertex shader if this ever gets released
      float testH = clamp(TEST_H + usedMaxNits,                      0.f, 10000.f);
      float testS = clamp(TEST_S + Ui::Tm::Global::TargetBrightness, 0.f, 10000.f);

      Tmos::Bt2446A_MOD1(hdr,
                         usedMaxNits,
                         Ui::Tm::Global::TargetBrightness,
                         Ui::Tm::Bt2446A::LumaPostAdjust,
                         Ui::Tm::Bt2446A::GamutCompression,
                         testH,
                         testS);
    } break;

#endif
  }

  Output = float4(hdr, inputColour.a);


#define FINAL_ADAPT_STOP 0.9979f

#if (SHOW_ADAPTIVE_MAX_NITS == YES)

  uint text_maxNits[26] = { __m, __a, __x, __C, __L, __L, __Colon, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __n, __i, __t, __s };
  uint text_avgdNits[35] = { __a, __v, __e, __r, __a, __g, __e, __d, __Space,
                             __m, __a, __x, __C, __L, __L, __Colon, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __n, __i, __t, __s };
  uint text_adaptiveMaxNits[35] = { __a, __d, __a, __p, __t, __i, __v, __e, __Space,
                                   __m, __a, __x, __C, __L, __L, __Colon, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __Space, __n, __i, __t, __s };
  uint text_finalAdaptMode[17] = { __f, __i, __n, __a, __l, __Space, __a, __d, __a, __p, __t, __Space, __m, __o, __d, __e, __Colon };

  float actualMaxNits = tex2Dfetch(SamplerConsolidated, COORDS_MAX_NITS_VALUE);

  float avgMaxNitsInPq = tex2Dfetch(SamplerConsolidated, COORDS_AVERAGED_MAX_NITS);
  float avgMaxNits     = Csp::Trc::PqTo::Nits(avgMaxNitsInPq);

  float adaptiveMaxNits     = tex2Dfetch(SamplerConsolidated, COORDS_ADAPTIVE_NITS);
  float adaptiveMaxNitsInPq = Csp::Trc::NitsTo::Pq(adaptiveMaxNits);

  float absDiff = abs(avgMaxNitsInPq - adaptiveMaxNitsInPq);

  float finalAdaptMode =
    absDiff < abs((avgMaxNitsInPq - FINAL_ADAPT_STOP * avgMaxNitsInPq))
  ? 2.f
  : absDiff < abs((avgMaxNitsInPq - Ui::Tm::AdaptiveMode::FinalAdaptStart / 100.f * avgMaxNitsInPq))
  ? 1.f
  : 0.f;

  DrawTextString(float2(10.f * 15.f, 20.f * 40.f),        30, 1, TexCoord, text_maxNits,         26, Output, FONT_BRIGHTNESS);
  DrawTextString(float2(       15.f, 20.f * 40.f + 30.f), 30, 1, TexCoord, text_avgdNits,        35, Output, FONT_BRIGHTNESS);
  DrawTextString(float2(       15.f, 20.f * 40.f + 60.f), 30, 1, TexCoord, text_adaptiveMaxNits, 35, Output, FONT_BRIGHTNESS);
  DrawTextString(float2(        0.f, 20.f * 40.f + 90.f), 30, 1, TexCoord, text_finalAdaptMode,  17, Output, FONT_BRIGHTNESS);

  DrawTextDigit(float2(24.f * 15.f, 20.f * 40.f),        30, 1, TexCoord,  6, actualMaxNits,   Output, FONT_BRIGHTNESS);
  DrawTextDigit(float2(24.f * 15.f, 20.f * 40.f + 30.f), 30, 1, TexCoord,  6, avgMaxNits,      Output, FONT_BRIGHTNESS);
  DrawTextDigit(float2(24.f * 15.f, 20.f * 40.f + 60.f), 30, 1, TexCoord,  6, adaptiveMaxNits, Output, FONT_BRIGHTNESS);
  DrawTextDigit(float2(19.f * 15.f, 20.f * 40.f + 90.f), 30, 1, TexCoord, -1, finalAdaptMode,  Output, FONT_BRIGHTNESS);

#endif

}


//void CS_CalcAdaptiveNits(uint3 ID : SV_DispatchThreadID)
//{
//  static const float currentMaxNitsInPqAveraged = (tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_0)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_1)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_2)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_3)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_4)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_5)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_6)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_7)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_8)
//                                                 + tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_9)) / 10.f;
//
//#if (SHOW_ADAPTIVE_MAX_NITS == YES)
//
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGED_MAX_NITS, currentMaxNitsInPqAveraged);
//
//#endif
//
//  static const float currentMaxNitsInPq =
//    Csp::Trc::NitsTo::Pq(tex2Dfetch(StorageConsolidated, COORDS_MAX_NITS_VALUE));
//
//  static const float currentAdaptiveMaxNitsInPq =
//    Csp::Trc::NitsTo::Pq(tex2Dfetch(StorageConsolidated, COORDS_ADAPTIVE_NITS));
//
//  static const uint curSlot = tex2Dfetch(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_CUR);
//
//  //clamp to our 10 slots
//  static const uint newSlot = (curSlot + 1) % 10;
//
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_CUR, newSlot);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_0
//                                + int2(newSlot, 0), currentMaxNitsInPq);
//
//  static const float absFrametime = abs(RuntimeValues::Frametime);
//
//  static const float curDiff = currentMaxNitsInPqAveraged
//                             * 1.0005f
//                             - currentAdaptiveMaxNitsInPq;
//
//  static const float absCurDiff = abs(curDiff);
//
//  float adapt;
//
//  //check if we are at the point where no adaption is needed anymore
//  if (absCurDiff < abs(currentMaxNitsInPqAveraged
//                     - FINAL_ADAPT_STOP * currentMaxNitsInPqAveraged))
//  {
//    //always be slightly above the max Nits
//    adapt = 0.000015f;
//  }
//  //check if we are at the point of "final adaption"
//  else if (absCurDiff < abs(currentMaxNitsInPqAveraged
//                          - Ui::Tm::AdaptiveMode::FinalAdaptStart / 100.f * currentMaxNitsInPqAveraged))
//  {
//    float actualFinalAdapt = absFrametime
//                           * (Ui::Tm::AdaptiveMode::FinalAdaptSteps / 10000.f)
//                           * (Ui::Tm::AdaptiveMode::FinalAdaptSpeed / 1000.f);
//
//    adapt = sign(curDiff) * actualFinalAdapt;
//  }
//  //normal adaption
//  else
//  {
//    adapt = curDiff * (absFrametime / (Ui::Tm::AdaptiveMode::TimeToAdapt * 1000.f));
//  }
//  //else
//  //  adapt = adapt > 0.f ? adapt + ADAPT_OFFSET : adapt - ADAPT_OFFSET;
//
//  barrier();
//
//  tex2Dstore(StorageConsolidated,
//             COORDS_ADAPTIVE_NITS,
//             min(Csp::Trc::PqTo::Nits(currentAdaptiveMaxNitsInPq + adapt),
//                 Ui::Tm::AdaptiveMode::MaxNitsCap));
//
//}
//
//
//void CS_ResetAveragedMaxNits(uint3 ID : SV_DispatchThreadID)
//{
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_0, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_1, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_2, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_3, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_4, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_5, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_6, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_7, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_8, 10000.f);
//  tex2Dstore(StorageConsolidated, COORDS_AVERAGE_MAX_NITS_9, 10000.f);
//}


//technique lilium__tone_mapping_adaptive_maxNits_OLD
//<
//  enabled = false;
//>
//{
//  pass PS_CalcNitsPerPixel
//  {
//    VertexShader = VS_PostProcess;
//     PixelShader = PS_CalcNitsPerPixel;
//    RenderTarget = TextureNitsValues;
//  }
//
//  pass CS_GetMaxNits0
//  {
//    ComputeShader = CS_GetMaxNits0 <THREAD_SIZE1, 1>;
//    DispatchSizeX = DISPATCH_X1;
//    DispatchSizeY = 1;
//  }
//
//  pass CS_GetMaxNits1
//  {
//    ComputeShader = CS_GetMaxNits1 <1, 1>;
//    DispatchSizeX = 1;
//    DispatchSizeY = 1;
//  }
//
//  pass CS_CalcAdaptiveNits
//  {
//    ComputeShader = CS_CalcAdaptiveNits <1, 1>;
//    DispatchSizeX = 1;
//    DispatchSizeY = 1;
//  }
//}

//technique lilium__reset_averaged_max_nits_values
//<
//  enabled = true;
//  hidden  = true;
//  timeout = 1;
//>
//{
//  pass CS_ResetAveragedMaxNits
//  {
//    ComputeShader = CS_ResetAveragedMaxNits <1, 1>;
//    DispatchSizeX = 1;
//    DispatchSizeY = 1;
//  }
//}

technique lilium__tone_mapping_adaptive_maximum_brightness
<
  ui_label   = "Lilium's tone mapping adaptive mode";
  ui_tooltip = "enable this to use the adaptive tone mapping mode";
  enabled    = false;
>
{
//  pass PS_CalcNitsPerPixel
//  {
//    VertexShader = VS_PostProcess;
//     PixelShader = PS_CalcNitsPerPixel;
//    RenderTarget = TextureNitsValues;
//  }
//
//  pass CS_GetMaxNits0_NEW
//  {
//    ComputeShader = CS_GetMaxNits0_NEW <THREAD_SIZE1, 1>;
//    DispatchSizeX = DISPATCH_X1;
//    DispatchSizeY = 2;
//  }
//
//  pass CS_GetMaxNits1_NEW
//  {
//    ComputeShader = CS_GetMaxNits1_NEW <1, 1>;
//    DispatchSizeX = 2;
//    DispatchSizeY = 2;
//  }
//
//  pass CS_GetFinalMaxNits_NEW
//  {
//    ComputeShader = CS_GetFinalMaxNits_NEW <1, 1>;
//    DispatchSizeX = 1;
//    DispatchSizeY = 1;
//  }
//
//  pass CS_CalcAdaptiveNits
//  {
//    ComputeShader = CS_CalcAdaptiveNits <1, 1>;
//    DispatchSizeX = 1;
//    DispatchSizeY = 1;
//  }
}

technique lilium__tone_mapping
<
  ui_label = "Lilium's tone mapping";
>
{
  pass PS_ToneMapping
  {
    VertexShader = VS_PrepareToneMapping;
     PixelShader = PS_ToneMapping;
  }
}

#else //is hdr API and hdr colour space

ERROR_STUFF

technique lilium__tone_mapping
<
  ui_label = "Lilium's tone mapping (ERROR)";
>
VS_ERROR

#endif //is hdr API and hdr colour space
