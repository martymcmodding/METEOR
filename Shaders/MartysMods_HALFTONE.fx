/*=============================================================================
                                                           
 888b     d888 8888888888 88888888888 8888888888 .d88888b.  8888888b.  
 8888b   d8888 888            888     888       d88P" "Y88b 888   Y88b 
 88888b.d88888 888            888     888       888     888 888    888 
 888Y88888P888 8888888        888     8888888   888     888 888   d88P 
 888 Y888P 888 888            888     888       888     888 8888888P"  
 888  Y8P  888 888            888     888       888     888 888 T88b   
 888   "   888 888            888     888       Y88b. .d88P 888  T88b  
 888       888 8888888888     888     8888888888 "Y88888P"  888   T88b 

  Marty's Extra Effects for ReShade                                                          
                                                                            
    Copyright (c) Pascal Gilcher. All rights reserved.
    
    * Unauthorized copying of this file, via any medium is strictly prohibited
 	* Proprietary and confidential

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.

===============================================================================

    Halftone Effect

    Author:         Pascal Gilcher

    More info:      https://martysmods.com
                    https://patreon.com/mcflypg
                    https://github.com/martymcmodding  	

=============================================================================*/

/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform float DOT_SCALE <
    ui_type = "drag";
    ui_label = "Grid Scale";
    ui_min = 1.0;
    ui_max = 4.0;
> = 2.0;

/*=============================================================================
	Textures, Samplers, Globals
=============================================================================*/

texture ColorInputTex : COLOR;
sampler ColorInput { Texture = ColorInputTex; };

texture FBMNoise { Width = 128; Height = 128; Format = RG8; };
sampler sFBMNoise { Texture = FBMNoise;	AddressU = WRAP; AddressV = WRAP; };

#include "MartysMods\mmx_global.fxh"

/*=============================================================================
	Vertex Shader
=============================================================================*/

struct VSOUT
{
	float4 vpos : SV_Position;
    float2 uv : TEXCOORD0;
};

VSOUT MainVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv); 
    return o;
}

float4 rgb_to_cmyk(float3 c)
{
	float k = 1 - max(max(c.r, c.g), c.b);
    return float4((1 - c.rgb - k) / (1 - k), k);
}

float3 cmyk_to_rgb(float4 c)
{
	return (1 - c.rgb) * (1 - c.a);
}

float draw_circle_aa(float x, float t)
{
	float ddxy = fwidth(x) * 0.71;
	return linearstep(-ddxy, ddxy, x - t);
}

float2 rotate(float2 v, float phi)
{
    float2 t; sincos(phi, t.x, t.y);
    return mul(v, float2x2(t.y, -t.x, t.xy));
}

float2 hash(float2 p)
{
	p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
	return frac(sin(p) * 43758.5453123) * 2 - 1;
}

//iquilezles simplex noise
float noise(float2 p)
{
    const float G = 0.211324865;
	float2 skewed = floor(p + dot(p, 0.366025404));
    float2 d0 = p - skewed + dot(skewed, G);
    float2 side; side.x = d0.x > d0.y; side.y = !side.x;
    float2 d1 = d0 - side + G;
	float2 d2 = d0 + G * 2 - 1;
    float3 weights = saturate(0.5 - float3(dot(d0, d0), dot(d1, d1), dot(d2, d2))); weights*= weights; weights*= weights;
	float3 surflets = float3(dot(d0, hash(skewed)), dot(d1, hash(skewed + side)), dot(d2, hash(skewed + 1.0)));
    return dot(surflets * weights, 70.0);
}

/*=============================================================================
	Pixel Shaders
=============================================================================*/

//need continuous noise to hide moire but calculating any kind of 
//value noise in-place makes it go 10 times slower LOL
void NoiseGenPS(in VSOUT i, out float2 o : SV_Target0)
{  
    float2 jitter;
    jitter.x = noise(i.vpos.xy);
    jitter.y = noise(i.vpos.xy + 157.44);
    jitter.x += noise(0.25 * i.vpos.xy);
    jitter.y += noise(0.25 * i.vpos.xy + 44.27);
    jitter.x += noise(0.0625 * i.vpos.xy);
    jitter.y += noise(0.0625 * i.vpos.xy + 259.4);
    o = jitter * 0.5 * 0.25 + 0.5;
}

void MainPS(in VSOUT i, out float3 o : SV_Target0) 
{     
    float3 rgb = tex2D(ColorInput, i.uv).rgb;
    float4 cmyk = rgb_to_cmyk(rgb);

    float2 p = i.vpos.xy / DOT_SCALE * 0.2;
    float jitter_w = max(0, 1 - DOT_SCALE * 0.2);

    float4 ang = float4(0.5617993, 1.7217304, 0.5, 1.285398);
    float4 grid;

    [unroll]
    for(int j = 0; j < 4; j++)
    {
        float2 gridcoord = rotate(p, ang[j]);
        float2 jitter = tex2Dlod(sFBMNoise, gridcoord / 128, 0).xy - 0.5;

        float2 sector_uv = frac(gridcoord) + jitter * jitter_w;
        float r = length(sector_uv * 2 - 1);        

        grid[j] = draw_circle_aa(r * 0.78, sqrt(cmyk[j]));
    }

    o = cmyk_to_rgb(1 - grid);
}


/*=============================================================================
	Techniques
=============================================================================*/

technique MartyMods_Halftone
<
    ui_label = "METEOR Halftone";
    ui_tooltip =        
        "                            MartysMods - Halftone                             \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"
        "Simulates halftone printing. That's it. Does what it says on the box.         \n"
        "\n"
        "\n"
        "Visit https://martysmods.com for more information.                            \n"
        "\n"       
        "______________________________________________________________________________";
>
{	
    pass { VertexShader = MainVS;PixelShader  = NoiseGenPS; RenderTarget = FBMNoise; }
	pass { VertexShader = MainVS;PixelShader  = MainPS; }    
}
