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

#define GRAIN_TYPE_ANALOG        0
#define GRAIN_TYPE_DIGITAL       1

uniform float GRAIN_INTENSITY < 
    ui_label = "Intensity"; 
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_category = "Global";
> = 0.85;

uniform bool ANIMATE <
    ui_label = "Animate Grain";
    ui_category = "Global";
> = false;

uniform float GRAIN_SAT <
    ui_type = "drag";
    ui_label = "Noise Saturation";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_category = "Parameters for ISO Noise";
> = 1.0;

uniform bool GRAIN_USE_BAYER <
    ui_label = "Bayer Matrix RGB Weighting";
    ui_tooltip = "Camera Sensors allocate twice as much area to green pixel\n"
                 "thus reducing the noise sigma by sqrt(2) for green.      \n"
                 "This causes the grain to adopt a pink hue in dark areas  \n";
    ui_category = "Parameters for ISO Noise";
> = true;

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
storage stPoissonLookupTex          { Texture = PoissonLookupTex; };

texture GrainIntermediateTex  < pooled = true; > { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F;  };
sampler sGrainIntermediateTex                    { Texture = GrainIntermediateTex; };

uniform uint FRAMECOUNT < source = "framecount"; >;

#include ".\MartysMods\mmx_global.fxh"
#include ".\MartysMods\mmx_math.fxh"

struct VSOUT
{
    float4 vpos : SV_Position;
    float2 uv   : TEXCOORD0;
};

struct CSIN 
{
    uint3 groupthreadid     : SV_GroupThreadID;         
    uint3 groupid           : SV_GroupID;            
    uint3 dispatchthreadid  : SV_DispatchThreadID;     
    uint threadid           : SV_GroupIndex;
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

float2 uint_to_rand_2(uint u)
{
    //move 16 bits into upper 16 bits of mantissa, mask out everything else, set exponent to 1, subtract 1.
    return asfloat((uint2(u << 7u, u >> 9u) & 0x7fff80u) | 0x3f800000u) - 1.0;
}

//low quality advancing random generator, best initialized with something hq
float4 next_rand_lq(inout uint rng)
{
    float4 rand;
    //rng = rng * 1664525u + 1013904223u;//shitty lcg
    rng = lowbias32(rng);
    rand.xy = uint_to_rand_2(rng);    
    //rng = rng * 1664525u + 1013904223u;
    rng = lowbias32(rng);
    rand.zw = uint_to_rand_2(rng);
    return rand;
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
    return g * sqrt(-2.0 * log(1.0 - u.y));//1-u cuz [0,1) -> (0,1] for log(0) = -inf
}

float3 boxmuller(float3 u)
{
    float3 g;    
    g.z = u.y * 2.0 - 1.0;
    sincos(u.x * TAU, g.x, g.y);
    g.xy *= sqrt(saturate(1.0 - g.z * g.z));        
    return g * sqrt(-2.0 * log(1.0 - u.y));
}

uint morton2Dto1D(uint2 p)
{    
    p = (p | (p << 8)) & 0x00FF00FFu;
    p = (p | (p << 4)) & 0x0F0F0F0Fu;
    p = (p | (p << 2)) & 0x33333333u;
    p = (p | (p << 1)) & 0x55555555u;
    return p.x | (p.y << 1);
}

/*=============================================================================
	Shader Entry Points
=============================================================================*/

VSOUT AnalogGrainVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv); //use original fullscreen triangle VS

    if(GRAIN_TYPE != GRAIN_TYPE_ANALOG) 
        o.vpos = asfloat(0x7F800000u); //NaN

    return o;
}

VSOUT DigitalSensorNoiseVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv); //use original fullscreen triangle VS

    if(GRAIN_TYPE != GRAIN_TYPE_DIGITAL) 
        o.vpos = asfloat(0x7F800000u); //NaN

    return o;
}

#define BATCH_SIZE 4

void PoissonTableCS(in CSIN i)
{
    if(GRAIN_TYPE != GRAIN_TYPE_ANALOG) 
        return;

    uint trial = i.dispatchthreadid.y;
   
    uint rng = lowbias32(trial + 2); //so we don't hash 0
    rng = ANIMATE ? rng + FRAMECOUNT : rng; 

    float4 poisson_result[BATCH_SIZE];
    float exposure_level[BATCH_SIZE];

    [unroll]
    for(uint j = 0u; j < BATCH_SIZE; j++)
    {
        uint color_idx = i.dispatchthreadid.x * BATCH_SIZE + j;
        float c = color_idx / (NUM_COLORS - 1.0);
        c = filmic_curve(c, FILM_CURVE_TOE, FILM_CURVE_GAMMA).x; //insert the film curve here, do you see why? ;)
        c = to_linear(c);
        
        exposure_level[j] = c;
        poisson_result[j] = 0;
    }

    uint num_grains = grain_intensity_to_halide_count();

    [loop]
    for(int g = 0; g < num_grains; g++) 
    {
        float4 rand_rgba = next_rand_lq(rng);
        [unroll]
        for(int j = 0; j < BATCH_SIZE; j++)
            poisson_result[j] += step(rand_rgba, exposure_level[j].xxxx);
    }

    [unroll]
    for(uint j = 0u; j < BATCH_SIZE; j++)
    {
        uint color_idx = i.dispatchthreadid.x * BATCH_SIZE + j;
        tex2Dstore(stPoissonLookupTex, int2(color_idx, trial), poisson_result[j] / num_grains);
    }
}

void AnalogGrainPS(in VSOUT i, out float4 o : SV_Target0)
{ 
    uint2 p = uint2(i.vpos.xy);
    uint2 block = p % 32u;
    uint2 tile  = p / 32u;
    uint tile_rng = lowbias32(lowbias32(tile.y) + tile.x);

    if(tile_rng & 1u)
        block.x = 31u - block.x;
    tile_rng >>= 1;
    if(tile_rng & 1u)
        block.y = 31u - block.y;
    tile_rng >>= 1;
    if(tile_rng & 1u)
        block = block.yx;
    tile_rng >>= 1;
    uint row_idx = morton2Dto1D(block);  
    row_idx += tile_rng;
    row_idx %= NUM_TRIALS;

    float3 tcol = tex2Dfetch(ColorInput, p).rgb;
    float3 poisson = 0;

    [branch]
    if(FILM_MODE == FILM_MODE_COLOR)
    {
        poisson.x = tex2Dfetch(sPoissonLookupTex, int2(tcol.x * NUM_COLORS * 0.99999, row_idx), 0).x;
        poisson.y = tex2Dfetch(sPoissonLookupTex, int2(tcol.y * NUM_COLORS * 0.99999, row_idx), 0).y;
        poisson.z = tex2Dfetch(sPoissonLookupTex, int2(tcol.z * NUM_COLORS * 0.99999, row_idx), 0).z;    
    }
    else 
    {
        float tgrey = from_linear(dot(to_linear(tcol), float3(0.2126729, 0.7151522, 0.072175)));
        poisson = tex2Dfetch(sPoissonLookupTex, int2(tgrey * NUM_COLORS * 0.99999, row_idx)).x;         
    }

    o.rgb = poisson;
    o.w = lowbias32(lowbias32(p.y) + p.x) & 1023u; //store well-representable random uint in alpha, for diffusion
    //o = from_linear(o);
}

void FilmDiffusionPS(in VSOUT i, out float3 o : SV_Target0)
{
    float2 gaussian = float2(1, 0.5 * lerp(0.1, 1.0, GRAIN_SIZE));
    float sigma = rsqrt(grain_intensity_to_halide_count());

    float wsum = 0;
    uint2 p = uint2(i.vpos.xy); 
    o = 0;

    [unroll]for(int x = -1; x <= 1; x++)
    [unroll]for(int y = -1; y <= 1; y++)
    {
        uint2 tp = p + int2(x, y);
        float4 texel = tex2Dfetch(sGrainIntermediateTex, tp);
        float3 tcol = texel.rgb;
        uint rng = uint(texel.w);

        float2 rand01 = float2(rng & 31u, rng >> 5u) / 32.0; //demux random bitfield into 2 shitty rng numbers        
        //random displacement to approximate average displacement of grains (gets lower as grains increase, until it converges to a regular lowpass)
        float2 offs = float2(x, y) + boxmuller(rand01) * sigma;
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
    o = tex2Dfetch(ColorInput, uint2(i.vpos.xy)).rgb;  
    o = to_linear(o);

    uint2 p = uint2(i.vpos.xy); 
    uint rng = lowbias32(lowbias32(p.y) + p.x);
    if(ANIMATE) rng += FRAMECOUNT;
    float3 u3 = next_rand_lq(rng).xyz;

    //3D box muller for 3 uncorrelated gaussian distributed noise values
    float3 gaussian = boxmuller(u3);

    [branch]
    if(FILM_MODE == FILM_MODE_COLOR)
    {        
        gaussian.g *= GRAIN_USE_BAYER > 0.5 ? 0.7071 : 1; //monte carlo
        gaussian = lerp(gaussian.xxx, gaussian, GRAIN_SAT);
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
        ComputeShader = PoissonTableCS<NUM_COLORS / BATCH_SIZE, 1>;
        DispatchSizeX = 1; 
        DispatchSizeY = NUM_TRIALS;
    }
    pass
	{
		VertexShader = AnalogGrainVS;        
        PixelShader  = AnalogGrainPS; 
        RenderTarget = GrainIntermediateTex; 
	}
    pass
	{
		VertexShader = AnalogGrainVS;        
        PixelShader  = FilmDiffusionPS;  
	}     
    pass
	{
		VertexShader = DigitalSensorNoiseVS;
		PixelShader  = ApplySensorNoisePS;  
	}
}



