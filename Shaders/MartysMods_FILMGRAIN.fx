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

    Film Grain

    Author:         Pascal Gilcher

    More info:      https://martysmods.com
                    https://patreon.com/mcflypg
                    https://github.com/martymcmodding  	

=============================================================================*/

/*=============================================================================
	Preprocessor settings
=============================================================================*/

/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform int FILM_MODE <
    ui_type = "combo";
    ui_label = "Film Mode";
    ui_items = "Monochrome\0Color\0";
    ui_category = "Global";
> = 0;

#define FILM_MODE_MONOCHROME 0
#define FILM_MODE_COLOR      1

uniform int GRAIN_TYPE <
    ui_type = "combo";
    ui_label = "Grain Type";
    ui_items = "Analog Film Grain\0Digital Sensor Noise\0";
    ui_category = "Global";
> = 0;

uniform bool ANIMATE <
    ui_label = "Animate Grain";
    ui_category = "Global";
> = false;

#define GRAIN_TYPE_ANALOG        0
#define GRAIN_TYPE_DIGITAL       1

uniform float GRAIN_INTENSITY < 
    ui_label = "Intensity"; 
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_category = "Global";
> = 0.85;

uniform float GRAIN_SAT <
    ui_type = "drag";
    ui_label = "Noise Saturation";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_category = "Parameters for ISO Noise";
> = 1.0;

uniform float GRAIN_SIZE <
    ui_type = "drag";
    ui_label = "Grain Size";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_category = "Parameters for Analog Film Grain";
> = 0.3;

uniform float FILM_CURVE_GAMMA <
    ui_type = "drag";
    ui_min = -1.0; ui_max = 1.0;
    ui_label = "Analog Film Gamma";
    ui_category = "Parameters for Analog Film Grain";
> = 0.0;

uniform float FILM_CURVE_TOE <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Analog Film Shadow Emphasis";
    ui_category = "Parameters for Analog Film Grain";
> = 0.0;
/*
uniform float4 tempF1 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform float4 tempF2 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform float4 tempF3 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);
*/
/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

//do NOT change anything here. "hurr durr I changed this and now it works"
//you ARE breaking things down the line, if the shader does not work without changes
//here, it's by design.

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex; };

#define NUM_COLORS 256
#define NUM_TRIALS 1024

texture PoissonLookupTex            { Width = NUM_COLORS;   Height = NUM_TRIALS;   Format = RGBA8;  };
sampler sPoissonLookupTex           { Texture = PoissonLookupTex; };

texture GrainIntermediateTex            { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA8;  };
sampler sGrainIntermediateTex           { Texture = GrainIntermediateTex; };

uniform uint FRAMECOUNT < source = "framecount"; >;

#include ".\MartysMods\mmx_global.fxh"
#include ".\MartysMods\mmx_math.fxh"

struct VSOUT
{
    float4 vpos : SV_Position;
    float2 uv   : TEXCOORD0;
};

/*=============================================================================
	Functions
=============================================================================*/

uint lowbias32(uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

#define WHITE_POINT 15.0

float3 to_hdr(float3 c)
{
    float w = 1 + rcp(1e-6 + WHITE_POINT); 
    c = c / (w - c);    
    return c;
}
float3 from_hdr(float3 c)
{
    float w = 1 + rcp(1e-6 + WHITE_POINT);      
    c = w * c * rcp(1 + c);
    return c;
}

/*
float4 hash42(float2 p)
{
	float4 p4 = frac(p.xyxy * float4(0.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return frac((p4.xxyz+p4.yzzw)*p4.zywx);
}*/

#define to_linear(x)    ((x)*0.283799*((2.52405+(x))*(x)))
#define from_linear(x)  (1.14374*(-0.126893*(x)+sqrt((x))))

float get_grey_value(int2 p)
{
    float3 color = tex2Dfetch(ColorInput, p).rgb;
    color = to_linear(color);
    return dot(color, float3(0.299, 0.587, 0.114));
}

//hand crafted response curve that mimics exposure adjustment pre-tonemap with toe
float3 filmic_curve(float3 x, float toe_strength, float gamma)
{
    //input is [-1, 1]
    gamma = gamma < 0.0 ? gamma * 0.5 : gamma * 6.0;

    x = saturate(x);
    float3 toe = saturate(1 - x);
    toe *= toe;//2
    toe *= toe;//4  
    x = saturate(x - x * toe_strength * toe);
    float3 gx = x * gamma;
    return (gx + x) / (gx + 1);
}

float4 next_rand(inout uint rng)
{
    float4 rand01;
    //need 16 bit rand here to avoid quantization of the output (N values for rand seed == N possible binomial outcomes)
    rng = lowbias32(rng);      
    rand01.xy = frac(((rng >> uint2(0, 16)) & 0xFFFF) * rcp(0xFFFF));
    rng = lowbias32(rng);      
    rand01.zw = frac(((rng >> uint2(0, 16)) & 0xFFFF) * rcp(0xFFFF));
    return rand01;
}

float next_rand_single(inout uint rng)
{   
    rng = lowbias32(rng);      
    return float(rng) * exp2(-32.0);
}

//grain intensity is more intuitive, however halide crystal count is what we need for the simulation
//we simulate up to 128 grains per pixel, lerping to original color for grain intensity < 0.5
//using sqrt for GUI control to make the perceived intensity proportional to slider value
uint grain_intensity_to_halide_count()
{
    return uint(1 + 127 * saturate(2.0 -(1-(1-GRAIN_INTENSITY)*(1-GRAIN_INTENSITY)) * 2.0));
}

float grain_intensity_to_blend()
{
    return saturate((1-(1-GRAIN_INTENSITY)*(1-GRAIN_INTENSITY)) * 2.0);
}

float2 boxmuller(float2 u)
{
    float2 g; sincos(u.x * TAU, g.x, g.y);
    return g * sqrt(-2.0 * log(u.y + 1e-6));
}

float3 boxmuller(float3 u)
{
    float3 g;    
    g.z = u.y * 2.0 - 1.0;
    sincos(u.x * TAU, g.x, g.y);
    g.xy *= sqrt(saturate(1.0 - g.z * g.z));        
    return g * sqrt(-2.0 * log(u.z + 1e-6));
}

/*=============================================================================
	Shader Entry Points
=============================================================================*/

VSOUT MainVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv); //use original fullscreen triangle VS
    return o;
}

void PoissonLUTPS(in VSOUT i, out float4 o : SV_Target0)
{ 
    if(GRAIN_TYPE != GRAIN_TYPE_ANALOG) discard;
    float p = uint(i.vpos.x) / (NUM_COLORS - 1.0);
    p = filmic_curve(p, FILM_CURVE_TOE, FILM_CURVE_GAMMA).x; //insert the film curve here, do you see why? ;)
    p = to_linear(p);
    uint rng = lowbias32(uint(i.vpos.y)+ 2);
    if(ANIMATE) rng += FRAMECOUNT;
    uint num_grains = grain_intensity_to_halide_count();

    o = 0;    
    [loop]for(int g = 0; g < num_grains; g++) 
        o += step(next_rand(rng), p);
        
    o /= num_grains;
}

void ApplyPoissonPS2(in VSOUT i, out float3 o : SV_Target0)
{ 
    if(GRAIN_TYPE != GRAIN_TYPE_ANALOG) discard;

    uint2 p = uint2(i.vpos.xy); 
    uint rng = lowbias32(lowbias32(p.y) + p.x);
    float4 rand01 = next_rand(rng);

    float3 tcol = tex2Dfetch(ColorInput, p).rgb;
    float3 poisson = 0;

    [branch]
    if(FILM_MODE == FILM_MODE_COLOR)
    {             
        poisson.x = tex2Dlod(sPoissonLookupTex, float2(tcol.x, rand01.x), 0).x; 
        poisson.y = tex2Dlod(sPoissonLookupTex, float2(tcol.y, rand01.y), 0).y; 
        poisson.z = tex2Dlod(sPoissonLookupTex, float2(tcol.z, rand01.z), 0).z;
    }
    else 
    {
        float tgrey = from_linear(dot(to_linear(tcol), float3(0.2126729, 0.7151522, 0.072175)));
        poisson = tex2Dlod(sPoissonLookupTex, float2(tgrey, rand01.x), 0).x;          
    }

    o = poisson;
    o = from_linear(o);
}

void FilmDiffusionPS(in VSOUT i, out float3 o : SV_Target0)
{
    if(GRAIN_TYPE != GRAIN_TYPE_ANALOG) discard;

    float2 gaussian = float2(1, 0.5 * lerp(0.1, 1.0, GRAIN_SIZE));
    float sigma = rsqrt(grain_intensity_to_halide_count());

    float wsum = 0;
    uint2 p = uint2(i.vpos.xy); 
     o = 0;

    [unroll]for(int x = -1; x <= 1; x++)
    [unroll]for(int y = -1; y <= 1; y++)
    {
        uint2 tp = p + int2(x, y);
        uint rng = lowbias32(lowbias32(tp.y) + tp.x);
        float4 rand01 = next_rand(rng);
        float3 tcol = tex2Dfetch(sGrainIntermediateTex, tp).rgb;
        tcol = to_linear(tcol);

        //random displacement to approximate average displacement of grains (gets lower as grains increase, until it converges to a regular lowpass)
        float2 offs = float2(x, y) + boxmuller(rand01.zw) * sigma;
        float w = exp(-dot(offs, offs));   
        //lowpass weight    
        w *= gaussian[abs(x)] * gaussian[abs(y)];

        o += tcol * w;
        wsum += w;
    }

    o /= wsum;

    float3 center = tex2Dfetch(ColorInput, p).rgb;  
    center = filmic_curve(center, FILM_CURVE_TOE, FILM_CURVE_GAMMA);  

    [branch]
    if(FILM_MODE == FILM_MODE_COLOR)
    {
        center = to_linear(center);
        o.rgb = lerp(center, o.rgb, grain_intensity_to_blend());
    }
    else 
    {
        float grey = dot(to_linear(center), float3(0.2126729, 0.7151522, 0.072175));
        o.rgb = lerp(grey, o.rgb, grain_intensity_to_blend());
    }
    
    o.rgb = from_linear(o.rgb);    
}

void ApplySensorNoisePS(in VSOUT i, out float3 o : SV_Target0)
{ 
    if(GRAIN_TYPE != GRAIN_TYPE_DIGITAL) discard;
    o = tex2Dfetch(ColorInput, uint2(i.vpos.xy)).rgb;  
    o = to_linear(o);

    uint2 p = uint2(i.vpos.xy); 
    uint rng = lowbias32(lowbias32(p.y) + p.x);
    if(ANIMATE) rng += FRAMECOUNT;
    float3 u3 = next_rand(rng).xyz;

    //3D box muller for 3 uncorrelated gaussian distributed noise values
    float3 gaussian = boxmuller(u3);

    [branch]
    if(FILM_MODE == FILM_MODE_COLOR)
    {
        //variance of 3 added gaussians with sigma 1 is 3, stddev then sqrt(3)
        //that means we need to divide by sqrt of 3 to normalize variance for the desaturated case. Good enough for linear interp :P
        gaussian = lerp(dot(gaussian, 0.333 * sqrt(3.0)), gaussian, GRAIN_SAT);
        o = to_hdr(o);
        o += gaussian * GRAIN_INTENSITY * GRAIN_INTENSITY * 0.35;
        o = from_hdr(o);
    }
    else 
    {
        o = dot(o, float3(0.2126729, 0.7151522, 0.072175));
        o = to_hdr(o);
        o += gaussian.x * GRAIN_INTENSITY * GRAIN_INTENSITY * 0.35;
        o = from_hdr(o);
    }

    o = from_linear(o);
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartyMods_FilmGrain
<
    ui_label = "METEOR Film Grain";
    ui_tooltip =        
        "                            MartysMods - Film Grain                           \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"

        "METEOR Film Grain is a physically based film grain emulation effect. Modeled \n"
        "after extensive offline simulations to produce results as seen in the real world.\n"
        "\n"
        "\n"
        "Visit https://martysmods.com for more information.                            \n"
        "\n"       
        "______________________________________________________________________________";
>
{ 
  
    pass
	{
		VertexShader = MainVS;
		PixelShader  = PoissonLUTPS;  
        RenderTarget = PoissonLookupTex;
    }
    pass
	{
		VertexShader = MainVS;        
        PixelShader  = ApplyPoissonPS2; 
        RenderTarget = GrainIntermediateTex; 
	}
    pass
	{
		VertexShader = MainVS;        
        PixelShader  = FilmDiffusionPS;  
	}     
    pass
	{
		VertexShader = MainVS;
		PixelShader  = ApplySensorNoisePS;  
	}    
}


