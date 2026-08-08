/*

  [  a n a g r a m a  ]

                         */

// This Program ("Anamorpho") contains Work by Jakub Maksymilian Fober,
// who has released it to the Public Domain.

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/* § User Interface. */

uniform uint HELP < __UNIFORM_RADIO_INT1
  ui_spacing = 4;
  ui_label = " ";
  ui_category = " 使用说明";
  ui_category_closed = true;
  ui_text = "i.  要使用 Anamorpho，您必须将 Squeeze 技术放在您想要采用变形宽银幕格式的着色器的最顶部。这些应该是处理颜色或仅添加后处理效果的着色器，而不是基于深度的着色器，如 GI、AO 等。\n"
            "\n"
            "ii. 然后，在所有这些着色器都放在 Squeeze 技术之后，启用 Desqueeze 技术。一旦两者都启用，图像应该恢复正常并看起来应有的样子，只是所需的效果已经以类似于变形镜头下的行为方式进行了变形。\n"
            "\n"
            "    此过程会导致轻微的模糊（尤其是在较高的挤压系数下），因此建议以更高的分辨率运行以获得最佳效果。";
>;

uniform float SqueezeFactor < __UNIFORM_DRAG_FLOAT1
  ui_spacing = 4;
  ui_min = 1.333;
  ui_max = 2;
  ui_label = " 挤压系数";
> = BUFFER_ASPECT_RATIO;

uniform float2 FilmDimensions < __UNIFORM_DRAG_FLOAT2
  ui_min = float2(4,3);
  ui_label = " 胶片尺寸";
  ui_units = "mm";
  ui_tooltip = "允许您选择变形过程中使用的模拟胶片尺寸。\n"
               "在启用裁剪时非常有用。";
  ui_spacing = 4;
> = float2(21.95,18.6);

uniform bool Letterbox < __UNIFORM_COMBO_BOOL1
  ui_label = " 裁剪";
  ui_tooltip = "添加信箱（或护栏框）以模拟所选胶片的变形宽高比。";
> = false;

/* § Textures and Samplers. */

sampler2D back_buffer
{
  Texture = ReShade::BackBufferTex;
  AddressU = MIRROR;
  AddressV = BORDER;
  
  SRGBTexture = true;
};

bool border(float2 texcoord)
{
  const float film_aspect_ratio = SqueezeFactor*(FilmDimensions.x / FilmDimensions.y);
  const float aspect_ratio = BUFFER_ASPECT_RATIO;
    
  if (aspect_ratio == film_aspect_ratio || !Letterbox) 
    return true;
  else if (film_aspect_ratio > aspect_ratio) {
    // letterbox
    float b = 0.5 - aspect_ratio / (2*film_aspect_ratio);
    return (texcoord.y > b && texcoord.y < (1-b));
  } else {
    // pillarbox
    float b = 0.5 - film_aspect_ratio / (2*aspect_ratio);
    return (texcoord.x > b && texcoord.x < (1-b));
  }
}

/* § Shaders. */

float3 SqueezePS(in float4 _ : SV_Position, in float2 texcoord : TEXCOORD) : SV_Target
{
  if (BUFFER_ASPECT_RATIO < 1)
    discard;

  float2 uv = float2(SqueezeFactor, 1) * texcoord;
  return tex2D(back_buffer, uv).rgb;
}

float3 DesqueezePS(in float4 _ : SV_Position, in float2 texcoord : TEXCOORD) : SV_Target
{
  if (BUFFER_ASPECT_RATIO < 1)
    discard;
  
  float2 uv = float2(1/SqueezeFactor, 1) * texcoord;
  return tex2D(back_buffer, uv).rgb * border(texcoord);
}

technique AnamorphoSqueeze
<
  ui_label = "变形宽银幕|挤压 [放在顶部]";
  ui_tooltip = "变形过程模拟程序 Anamorpho 的第一部分（您必须同时使用第二部分）。\n"
               "适合专业人士使用。\n"
               "属于 Anagrama 着色器合集 [nullfrctl/reshade-shaders]。\n"
               "\n"
               "(C) 2024 Santiago Velasquez. 保留所有权利。";
>
{
  pass
  {
    VertexShader = PostProcessVS;
    PixelShader  = SqueezePS;
    SRGBWriteEnable = true;
  }
}

technique AnamorphoDesqueeze
<
  ui_label = "变形宽银幕|解除挤压 [放在底部]";
  ui_tooltip = "变形过程模拟程序 Anamorpho 的第二部分（您必须同时使用第一部分）。\n"
               "适合专业人士使用。\n"
               "属于 Anagrama 着色器合集 [nullfrctl/reshade-shaders]。\n"
               "\n"
               "(C) 2024 Santiago Velasquez. 保留所有权利。";
>
{
  pass
  {
    VertexShader = PostProcessVS;
    PixelShader  = DesqueezePS;
    SRGBWriteEnable = true;
  }
}