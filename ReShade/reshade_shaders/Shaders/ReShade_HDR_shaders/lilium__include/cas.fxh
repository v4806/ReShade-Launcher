// Original functions are part of the FidelityFX SDK.
//
// Copyright (C)2023 Advanced Micro Devices, Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the “Software”), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and /or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


#include "cas_helpers.fxh"


uniform int CAS_ABOUT
<
  ui_category = "关于 CAS/对比度自适应锐化";
  ui_label    = " ";
  ui_type     = "radio";
  ui_text     = "AMD FidelityFX 对比度自适应锐化 1.1"
           "\n" "FidelityFX 对比度自适应锐化 (CAS) 是一种低开销的自适应锐化算法，可选上采样。"
                "该技术由 Timothy Lottes（FXAA 创造者）开发，旨在提供自然的锐化效果而不产生瑕疵。";
>;

uniform bool SHARPEN_ONLY
<
  ui_label   = "仅锐化模式";
  ui_tooltip = "如果取消勾选，将使用 CAS 的上采样路径。"
          "\n" "处理方式略有不同。"
          "\n" "但不会进行任何实际的上采样！";
> = true;

uniform float SHARPEN_AMOUNT
<
  ui_label   = "锐化强度";
  ui_tooltip = "即使值为 0 也会应用一点锐化效果！";
  ui_type    = "drag";
  ui_min     = 0.f;
  ui_max     = 1.f;
  ui_step    = 0.001f;
> = 0.f;

uniform float APPLY_AMOUNT
<
  ui_label   = "锐化应用量";
  ui_tooltip = "最终图像应用多少锐化效果。";
  ui_type    = "drag";
  ui_min     = 0.f;
  ui_max     = 1.f;
  ui_step    = 0.001f;
> = 1.f;


float3 CasSharpenOnly(
  const SPixelsToProcess Ptp,
  const float            Peak)
{
  // Load a collection of samples in a 3x3 neighorhood, where e is the current pixel.
  // a b c
  // d e f
  // g h i

  static const float3 a = PrepareForProcessing(Ptp.a);
  static const float3 b = PrepareForProcessing(Ptp.b);
  static const float3 c = PrepareForProcessing(Ptp.c);
  static const float3 d = PrepareForProcessing(Ptp.d);
  static const float3 e = PrepareForProcessing(Ptp.e);
  static const float3 f = PrepareForProcessing(Ptp.f);
  static const float3 g = PrepareForProcessing(Ptp.g);
  static const float3 h = PrepareForProcessing(Ptp.h);
  static const float3 i = PrepareForProcessing(Ptp.i);

  // Soft min and max.
  //  a b c             b
  //  d e f * 0.5  +  d e f * 0.5
  //  g h i             h
  // These are 2.0x bigger (factored out the extra multiply).
  float3 minRgb = MIN3(MIN3(d, e, f), b, h);
  float3 maxRgb = MAX3(MAX3(d, e, f), b, h);

  minRgb += MIN3(MIN3(minRgb, a, c), g, i);
  maxRgb += MAX3(MAX3(maxRgb, a, c), g, i);

  // Smooth minimum distance to signal limit divided by smooth max.
  float3 rcpMaxRgb = rcp(maxRgb);

  // Shaping amount of sharpening.
  float3 amplifyRgb = sqrt(saturate(min(minRgb, 2.f - maxRgb) * rcpMaxRgb));

  // Filter shape.
  //  0 w 0
  //  w 1 w
  //  0 w 0

  float3 weight = amplifyRgb * Peak;

  float3 rcpWeight = rcp(1.f + 4.f * weight);

  float3 output = saturate(((b + d + f + h) * weight + e) * rcpWeight);

  output = lerp(e, output, APPLY_AMOUNT);

  return PrepareForOutput(output);
}


float3 CasSharpenAndUpscale(
  const SPixelsToProcess Ptp,
  const float            Peak)
{
  //  a b c d
  //  e f g h
  //  i j k l
  //  m n o p
  // Working these 4 results.
  //  +-----+-----+
  //  |     |     |
  //  |  f..|..g  |
  //  |  .  |  .  |
  //  +-----+-----+
  //  |  .  |  .  |
  //  |  j..|..k  |
  //  |     |     |
  //  +-----+-----+

  static const float3 a = PrepareForProcessing(Ptp.a);
  static const float3 b = PrepareForProcessing(Ptp.b);
  static const float3 c = PrepareForProcessing(Ptp.c);
  static const float3 e = PrepareForProcessing(Ptp.d);
  static const float3 f = PrepareForProcessing(Ptp.e);
  static const float3 g = PrepareForProcessing(Ptp.f);
  static const float3 i = PrepareForProcessing(Ptp.h);
  static const float3 j = PrepareForProcessing(Ptp.i);
  static const float3 k = PrepareForProcessing(Ptp.g);


  // Soft min and max.
  // These are 2.0x bigger (factored out the extra multiply).
  //  a b c             b
  //  e f g * 0.5  +  e f g * 0.5  [F]
  //  i j k             j
  float3 minRgb = MIN3(MIN3(b, e, f), g, j);
  float3 mxfRgb = MAX3(MAX3(b, e, f), g, j);

  minRgb += MIN3(MIN3(minRgb, a, c), i, k);
  mxfRgb += MAX3(MAX3(mxfRgb, a, c), i, k);

  // Smooth minimum distance to signal limit divided by smooth max.
  float3 rcpMfRgb = rcp(mxfRgb);

  // Shaping amount of sharpening.
  float3 ampfRgb = sqrt(saturate(min(minRgb, 2.f - mxfRgb) * rcpMfRgb));

  // Filter shape.
  //  0 w 0
  //  w 1 w
  //  0 w 0

  float3 wfRgb = ampfRgb * Peak;

  // Thin edges to hide bilinear interpolation (helps diagonals).
  static const float thinB = 1.f / 32.f;

  float s = rcp(thinB + mxfRgb.g - minRgb.g);

  // Final weighting.
  //    b c
  //  e f g h
  //  i j k l
  //    n o
  //  _____  _____  _____  _____
  //         fs        gt
  //
  //  _____  _____  _____  _____
  //  fs      s gt  fs  t     gt
  //         ju        kv
  //  _____  _____  _____  _____
  //         fs        gt
  //  ju      u kv  ju  v     kv
  //  _____  _____  _____  _____
  //
  //         ju        kv

  float3 wfRgb_x_s = wfRgb * s;

  float3 rcpWeight = rcp(4.f * wfRgb_x_s + s);

  float3 output = saturate(((b + e + g + j) * wfRgb_x_s.g + (f * s)) * rcpWeight);

  output = lerp(f, output, APPLY_AMOUNT);

  return PrepareForOutput(output);
}
