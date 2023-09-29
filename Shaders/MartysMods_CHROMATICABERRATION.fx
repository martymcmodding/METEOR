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

    The most overengineered chromatic aberration shader ever
    Previously YACA22 - Yet Another Chromatic Aberration '22

    What sets it apart from regular CA and why should I use it?

    All* games do CA wrong. Most of the time they apply it after tonemapping
    which is wrong, it should happen prior to that. Then they simulate a rainbow
    gradient. What produces a rainbow gradient? A single lens element. What
    never has a single lens element? A real camera lens.
    The more sophisticated effects do a linear blur and weight each sample
    by a chroma, dividing by that after. This however creates a hue shift that
    messes up the gradient. The correct method is to adjust the intensities of each
    hue across the spectrum such that the sum of R, G and B components is the same.
    I've done so with an offline simulation, creating a LUT for that.

    *I haven't checked them all but so far, I haven't seen any one doing it right

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

uniform int CHROMA_MODE <
	ui_type = "combo";
    ui_label = "Lens Type";
	ui_items = "Chromatic (single lens)\0Achromatic (doublet)\0Apochromatic (triplet)\0";
> = 0;

uniform float CA_CURVE <
	ui_type = "drag";
    ui_label = "Curve";
	ui_min = -1.0; 
    ui_max = 1.0;
> = 0.0;

uniform float CA_AMT <
	ui_type = "drag";
    ui_label = "Amount";
	ui_min = -1.0; 
    ui_max = 1.0;
> = 0.15;

uniform int CA_QUALITY_PRES <
	ui_type = "combo";
    ui_label = "Quality Preset";
	ui_items = "Low\0Medium\0High\0Very High\0Ultra\0";
> = 1;

uniform bool CA_HDR <
    ui_label = "Use HDR";
> = true;

uniform bool CA_POSTFILTER <
    ui_label = "Use Post Filtering";
> = false;

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

//do NOT change anything here. "hurr durr I changed this and now it works"
//you ARE breaking things down the line, if the shader does not work without changes
//here, it's by design.

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex; };

texture SpectrumLUTNew       < source = "ca_lut_new.png"; > { Width = 256; Height = 18; Format = RGBA8; };
sampler	sSpectrumLUTNew      { Texture = SpectrumLUTNew; };

texture HDRInput <pooled = true;> { Width = BUFFER_WIDTH;         Height = BUFFER_HEIGHT;     Format = RGBA16F; };
sampler	sHDRInput      { Texture = HDRInput; };

#include "MartysMods\mmx_global.fxh"

struct VSOUT
{
	float4 vpos : SV_Position;
    float2 uv : TEXCOORD0;
};

/*=============================================================================
	Functions
=============================================================================*/

float wavelength_to_norm(float lambda)
{
    return saturate((lambda - 400.0) / 300.0);
}

float3 sdr_to_hdr(float3 c)
{ 
    if(!CA_HDR) return c;
    const float W = 4;
    c = c * sqrt(1e-6 + dot(c, c)) / 1.733;
    float a = 1 + exp2(-W);    
    c = c / (a - c); 
    return c;
}

float3 hdr_to_sdr(float3 c)
{    
    if(!CA_HDR) return c;
    const float W = 4;
    float a = 1 + exp2(-W); 
    c = a * c * rcp(1 + c);    
    c *= 1.733;
    c = c * rsqrt(sqrt(dot(c, c))+ 1e-5);
    return c;
}

float3 spectrum_lut_eval(float x, float N)
{
    //https://www.edmundoptics.de/knowledge-center/application-notes/optics/chromatic-and-monochromatic-optical-aberrations/
    //chromatic aberration LUT generated from CIE1931 (Judd_Vos) and optimized with
    //a gradient descent algorithm so that the total sums of each channel are equal
    //as dividing through the RGB sum would cause hue shifts in the gradient.
    //this causes the gradient brightness to deviate a bit from the ground truth
    //but the hues are closer than any other common approximation, as they all
    //contain this flaw.

    //LUTs for achromatic and apo however are not integral-normalized the same
    // way, as this is only possible to do this if each of the channels is the
    //largest for a certain range. A wrong rainbow gradient is much more obvious
    //than these, so it's fine. One could obviously sample the original gradient,
    //but this accumulates error. Calculating the offset per wavelength directly
    //and sampling the original rainbow gradient will cause uneven sample spacing
    //and thus a precomputed LUT is to be favored.

    //LUTs for achromatic and apo also exhibit strong peaks (at the wavelength foci)
    //and therefore are encoded ^0.25 to ensure sufficient color accuracy.
    //All LUTs are preaveraged and normalized, so if sampling it at 8 locations,
    //the gradient is preaveraged into 8 bins for optimal coverage.

    float y = saturate((log2(N) - 4)/log2(256.0));

    y = lerp(0.5, 5.5, y);
    y += CHROMA_MODE * 6;
    y /= 18.0;

    float3 spectrum = tex2Dlod(sSpectrumLUTNew, float2(x, y), 0).rgb;
    spectrum = CHROMA_MODE != 0 ? (spectrum * spectrum) * (spectrum * spectrum) : spectrum;
    return spectrum;
}

void get_params(in VSOUT i, out float2 dir, out float divergence)
{
    float2 uv = i.uv * 2.0 - 1.0;
    uv.x *= BUFFER_ASPECT_RATIO.y;    
    float r = sqrt(dot(uv, uv) / dot(BUFFER_ASPECT_RATIO, BUFFER_ASPECT_RATIO)); // == 1 in screen corner :)

    float curve = exp2(-CA_CURVE * 20.0);

    //this calculates the cosine of the angle of the light path to the center of the lens
    //e.g. vignette commonly scales with cos^4. The rest is just fluff to make the UI behave as expected.
    float cosphi = rsqrt(1 + r * r * curve);
    float scale = rsqrt(1 + curve);

    float ca_divergence = saturate((1 - cosphi)/(1 - scale)); //normalize so intensity at screen corner does not change with curve param
    ca_divergence *= abs(CA_AMT) * 128;    

    divergence = ca_divergence;
    dir = normalize(uv) * sign(CA_AMT);
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

void HDRPS(in VSOUT i, out float3 o : SV_Target0)
{ 
    o = tex2D(ColorInput, i.uv).rgb;
    o = sdr_to_hdr(o);
}

void MainPS(in VSOUT i, out float4 o : SV_Target0)
{
    float divergence; float2 dir;
    get_params(i, dir, divergence); 

    const float3 ca_offsets = float3(0.55, 0.05, 0.53); //location of max energy to center the perceived chroma shift
    float2 ab_madd = float2(divergence, -ca_offsets[CHROMA_MODE] * divergence);

    float3 sum = 0;
    float3 spectral_sum = 0;

    float qscale = CA_QUALITY_PRES / 4.0;
    qscale *= qscale;

    uint _samples = min(64, 8 + ceil(divergence * qscale));

    for(int j = 0; j < _samples; j++)
    {
        float x = float(j + 0.5)/ _samples;
        float3 spectral_rgb = spectrum_lut_eval(x, _samples); 
        float aberration = x * ab_madd.x + ab_madd.y;

        float3 tap = tex2Dlod(sHDRInput, i.uv + dir * aberration * BUFFER_PIXEL_SIZE.x, 0).rgb;
        sum += tap * spectral_rgb;     
        spectral_sum += spectral_rgb;
    }

    o.rgb = sum / spectral_sum;    
    o.rgb =  hdr_to_sdr(o.rgb);

    float sample_spacing_pixels = length(BUFFER_PIXEL_SIZE * divergence) / length(BUFFER_PIXEL_SIZE);
    o.w = sample_spacing_pixels / _samples / 16.0; //pixel radius
/*
    float3 chromas[7] = 
    {
        float3(0.052187, 0, 0.131538),
        float3(0.077535, 0.0891, 0.415847),
        float3(0.017396, 0.2983, 0.428276),
        float3(0.108847, 0.3268,  0.082859),
        float3(0.364314, 0.2372, 0),
        float3(0.294235, 0.0487, 0),
        float3(0.085487, 0, 0)
    };

    o = chromas[uint(i.uv.x * 6.9999)];
*/     
}

void PostPS(in VSOUT i, out float4 o : SV_Target0)
{ 
    float4 center = tex2D(ColorInput, i.uv);
    float gwidth = center.w * 16.0 + 0.01;
    int spacing = round(gwidth);

    o = float4(sdr_to_hdr(center.rgb), 1);

    if(spacing * CA_POSTFILTER == 0)
        discard;

    float divergence; float2 dir;
    get_params(i, dir, divergence); 
    [loop]for(int x = 1; x <= spacing; x++)
    {
        float w = x / gwidth;
        w = exp(-2 * w * w);
        float3 t;
        t = tex2Dlod(ColorInput, i.uv + dir * BUFFER_PIXEL_SIZE * x, 0).rgb;    
        o += float4(sdr_to_hdr(t), 1) * w;
        t = tex2Dlod(ColorInput, i.uv - dir * BUFFER_PIXEL_SIZE * x, 0).rgb;    
        o += float4(sdr_to_hdr(t), 1) * w;
    }    
    o /= o.w;
    o.rgb = hdr_to_sdr(o.rgb);
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_ChromaticAberration
<
    ui_label = "METEOR Chromatic Aberration";
    ui_tooltip =        
        "                        MartysMods - Chromatic Aberration                     \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"
        "A hilariously overengineered chromatic aberration effect.                     \n"
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
		PixelShader  = HDRPS;
        RenderTarget = HDRInput;
	}
    pass
	{
		VertexShader = MainVS;
		PixelShader  = MainPS;  
	}  
     pass
	{
		VertexShader = MainVS;
		PixelShader  = PostPS;  
	}     
}