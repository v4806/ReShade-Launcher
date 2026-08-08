/*

  [  a n a g r a m a  ]

                         */

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "sampling.fxh"

/* § User Interface. */

uniform float Blend < __UNIFORM_SLIDER_FLOAT1
  ui_min = 0;
  ui_max = 1;
  ui_label = " 混合";
  ui_tooltip = "在模糊效果和原始图像之间进行混合。可用于镜头扩散效果。";
  ui_spacing = 4;
> = 0.5;

uniform float W < __UNIFORM_DRAG_FLOAT1
  ui_min = 1;
  ui_max = 3;
  ui_label = " 对数 HDR 白点";
  ui_tooltip = "以 10^n 比例表示的最大可达 HDR 值。";
> = 2;

uniform float2 Offset < __UNIFORM_DRAG_FLOAT2
  ui_min = 1;
  ui_label = " 偏移";
  ui_tooltip = "改变模糊计算中'像素'的大小。较大的值会产生更宽的模糊效果。";
  ui_spacing = 4;
> = 1;

uniform bool Aphysical < __UNIFORM_COMBO_BOOL1
  ui_label = " 非物理混合";
  ui_spacing = 4;
  ui_tooltip = "以类似于游戏通常（错误地）混合泛光的方式混合模糊：叠加式。\n"
               "此模式不是叠加式，但同样允许使用阈值[见下方]。";
> = false;

uniform float Threshold < __UNIFORM_DRAG_FLOAT1
  ui_min = 0;
  ui_label = " 非物理阈值";
  ui_tooltip = "模糊效果识别的光量阈值。非物理正确。";
> = 10;

uniform bool Dither <
  ui_label = " 去色带";
  ui_spacing = 4;
> = true;

/* § Textures and Samplers. */

sampler2D back_buffer
{
  Texture = ReShade::BackBufferTex;
  SRGBTexture = true;
};

// We can re-use textures due to the linear nature of dual filter blur.

namespace T
{
  texture2D Z
  {
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA16F;
  };

  texture2D I
  {
    Width  = BUFFER_WIDTH  / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
  };

  texture2D II
  {
    Width  = BUFFER_WIDTH  / 4;
    Height = BUFFER_HEIGHT / 4;
    Format = RGBA16F;
  };

  texture2D III
  {
    Width  = BUFFER_WIDTH  / 8;
    Height = BUFFER_HEIGHT / 8;
    Format = RGBA16F;
  };

  texture2D IV
  {
    Width  = BUFFER_WIDTH  / 16;
    Height = BUFFER_HEIGHT / 16;
    Format = RGBA16F;
  };

  texture2D V
  {
    Width  = BUFFER_WIDTH  / 32;
    Height = BUFFER_HEIGHT / 32;
    Format = RGBA16F;
  };

  texture2D VI
  {
    Width  = BUFFER_WIDTH  / 64;
    Height = BUFFER_HEIGHT / 64;
    Format = RGBA16F;
  };

  texture2D blue_noise
  <
    source = "blue_noise.dds";
  >
  {
    Width = 512;
    Height = 512;
    Format = R8;
  };
}

#define MIRROR AddressU = MIRROR; AddressV = MIRROR

sampler2D Z   { Texture = T::Z;   MIRROR; };
sampler2D I   { Texture = T::I;   MIRROR; };
sampler2D II  { Texture = T::II;  MIRROR; };
sampler2D III { Texture = T::III; MIRROR; };
sampler2D IV  { Texture = T::IV;  MIRROR; };
sampler2D V   { Texture = T::V;   MIRROR; };
sampler2D VI  { Texture = T::VI;  MIRROR; };

sampler2D blue_noise  
{
  Texture = T::blue_noise;
  AddressU = REPEAT;
  AddressV = REPEAT;
};

/* § Functions. */

// Z fetch.
float3 Zf(float4 p)
{
  return fetch(Z,p).rgb;
}

float3 tone_map(float3 c) { return c / (1+c); }
float3 inverse_tone_map(float3 c) { return -(c / (c-(1+pow(10,-W)))); }

/* § Shaders. */

namespace d
{
  float3 I(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::downsample(::Z, t, 1, Offset);
  }

  float3 II(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::downsample(::I, t, 2, Offset);
  }

  float3 III(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::downsample(::II, t, 3, Offset);
  }

  float3 IV(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::downsample(::III, t, 4, Offset);
  }

  float3 V(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::downsample(::IV, t, 5, Offset);
  }

  float3 VI(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::downsample(::V, t, 6, Offset);
  }
}

namespace u
{
  float3 I(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::upsample(::VI, t, 6, Offset);
  }

  float3 II(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::upsample(::V, t, 5, Offset);
  }

  float3 III(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::upsample(::IV, t, 4, Offset);
  }

  float3 IV(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::upsample(::III, t, 3, Offset);
  }

  float3 V(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::upsample(::II, t, 2, Offset);
  }

  float3 VI(float4 _ : SV_Position, float2 t : TEXCOORD) : SV_Target
  {
    return ::Dual::upsample(::I, t, 1, Offset);
  }
}

float3 InverseToneMapPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
  float3 c = inverse_tone_map(fetch(back_buffer, position).rgb);

  if (Aphysical)
  {  
    float br = max(c.r,max(c.g,c.b));
    c *= max(0, br - Threshold) / max(br, 1e-5);
  }
  
  return c;
}

float3 BlendPS(in float4 position : SV_Position, in float2 texcoord : TEXCOORD) : SV_Target
{
  if(Dither)
    position.xy += fetch(blue_noise, position).rr - 0.5;

  float3 hdr  = inverse_tone_map(fetch(back_buffer, position).rgb);
  float3 blur = Zf(position);

  float3 color;
  
  if (Aphysical)
    color = lerp(hdr, (hdr + (blur / (1 + blur))), Blend);
  else
    color = lerp(hdr, blur, Blend);
    
  return tone_map(color);
}

technique Blur
<
  ui_label = "模糊（镜头扩散）";
  ui_tooltip = "一个简单、快速的模糊着色器，适合模拟镜头扩散效果。\n"
               "属于 Anagrama 着色器合集 [nullfrctl/reshade-shaders]。\n"
               "\n"
               "(C) 2024 Santiago Velasquez. 保留所有权利。";
>
{
  /* Initialization. */

  pass
  {
    VertexShader = PostProcessVS;
    PixelShader  = InverseToneMapPS;
    RenderTarget = T::Z;
    ClearRenderTargets = true;
  }

  /* Downsampling. */

  pass d_I
  {
    VertexShader = PostProcessVS;
    PixelShader  = d::I;
    RenderTarget = T::I;
  }

  pass d_II
  {
    VertexShader = PostProcessVS;
    PixelShader  = d::II;
    RenderTarget = T::II;
  }

  pass d_III
  {
    VertexShader = PostProcessVS;
    PixelShader  = d::III;
    RenderTarget = T::III;
  }

  pass d_IV
  {
    VertexShader = PostProcessVS;
    PixelShader  = d::IV;
    RenderTarget = T::IV;
  }

  pass d_V
  {
    VertexShader = PostProcessVS;
    PixelShader  = d::V;
    RenderTarget = T::V;
  }

  pass d_VI
  {
    VertexShader = PostProcessVS;
    PixelShader  = d::VI;
    RenderTarget = T::VI;
  }

  /* Upsample */

  pass u_I
  {
    VertexShader = PostProcessVS;
    PixelShader  = u::I;
    RenderTarget = T::V;
  }

  pass u_II
  {
    VertexShader = PostProcessVS;
    PixelShader  = u::II;
    RenderTarget = T::IV;
  }

  pass u_III
  {
    VertexShader = PostProcessVS;
    PixelShader  = u::III;
    RenderTarget = T::III;
  }

  pass u_IV
  {
    VertexShader = PostProcessVS;
    PixelShader  = u::IV;
    RenderTarget = T::II;
  }

  pass u_V
  {
    VertexShader = PostProcessVS;
    PixelShader  = u::V;
    RenderTarget = T::I;
  }

  pass u_VI
  {
    VertexShader = PostProcessVS;
    PixelShader  = u::VI;
    RenderTarget = T::Z;
  }

  /* Finalization. */

  pass
  {
    VertexShader = PostProcessVS;
    PixelShader  = BlendPS;
    SRGBWriteEnable = true;
  }
}