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

    Local Laplacian Filtering
    
    If you want to have perfect local contrast enhancement at a ridiculous 
    performance cost, this is the shader for you!
    Local Laplacians are normally not realtime capable, this should be the
    fastest implementation at the time of release.


    Author:         Pascal Gilcher

    More info:      https://martysmods.com
                    https://patreon.com/mcflypg
                    https://github.com/martymcmodding  	

=============================================================================*/


/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform float STRENGTH < 
    ui_label = "Local Contrast Strength"; 
    ui_type = "drag";
    ui_min = -1.0;
    ui_max = 1.0;
> = 0.0;

uniform int INTERP <
    ui_type = "combo";
    ui_label = "Pyramid Upscaling";
    ui_items = "Bilinear\0Bicubic\0";
> = 0;

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex; };

struct VSOUT
{
	float4                  vpos        : SV_Position;
    float2                  uv          : TEXCOORD0;    
};

#include ".\MartysMods\mmx_global.fxh"
#include ".\MartysMods\mmx_texture.fxh"


#define RESOLUTION_DIV  2

#define TILE_WIDTH     (BUFFER_WIDTH / RESOLUTION_DIV)
#define TILE_HEIGHT    (BUFFER_HEIGHT / RESOLUTION_DIV)

//this is really awkward but we cannot use any of the common preprocessor integer log2 macros
//as the preprocessor runs out of stack space with them. So we have to do it manually like this
#if TILE_HEIGHT < 128
    #define LOWEST_MIP  6
#elif TILE_HEIGHT < 256
    #define LOWEST_MIP  7
#elif TILE_HEIGHT < 512
    #define LOWEST_MIP  8
#elif TILE_HEIGHT < 1024
    #define LOWEST_MIP  9
#elif TILE_HEIGHT < 2048
    #define LOWEST_MIP  10
#elif TILE_HEIGHT < 4096
    #define LOWEST_MIP  11
#elif TILE_HEIGHT < 8192
    #define LOWEST_MIP  12
#elif TILE_HEIGHT < 16384
    #define LOWEST_MIP  13
#else 
    #error "Unsupported resolution"
#endif

//smallest mip we want to generate, N less than the lowest possible mip
//DO NOT CHANGE THIS -3 THING IT WILL BRICK IT TO SHITS, AND I WILL SHIT BRICKS (on you)
//remember to add additional textures etc for this
#define TARGET_MIP        ((LOWEST_MIP) - 2)
#define TARGET_MIP_SCALE  (1 << (TARGET_MIP))

#define ATLAS_TILES_X   2
#define ATLAS_TILES_Y   3

//rounded up tile resolution such that it can be cleanly divided by 2 TARGET_MIP'th times
#define ATLAS_TILE_RESOLUTION_X  CEIL_DIV(TILE_WIDTH, TARGET_MIP_SCALE) * TARGET_MIP_SCALE
#define ATLAS_TILE_RESOLUTION_Y  CEIL_DIV(TILE_HEIGHT, TARGET_MIP_SCALE) * TARGET_MIP_SCALE

//tile res * num tiles + 2x padding of lowest res texel on each side of the tile. In theory we'd only need the one on the inside, but the code is simpler this way
#define ATLAS_RESOLUTION_X ((ATLAS_TILE_RESOLUTION_X) * (ATLAS_TILES_X))
#define ATLAS_RESOLUTION_Y ((ATLAS_TILE_RESOLUTION_Y) * (ATLAS_TILES_Y))

texture GaussianPyramidAtlasTexLevel0 { Width = (ATLAS_RESOLUTION_X)>>0; Height = (ATLAS_RESOLUTION_Y)>>0; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel0 { Texture = GaussianPyramidAtlasTexLevel0;};

#if TARGET_MIP >= 1
texture GaussianPyramidAtlasTexLevel1Tmp { Width = (ATLAS_RESOLUTION_X)>>1; Height = (ATLAS_RESOLUTION_Y)>>0; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel1Tmp { Texture = GaussianPyramidAtlasTexLevel1Tmp;};
texture GaussianPyramidAtlasTexLevel1 { Width = (ATLAS_RESOLUTION_X)>>1; Height = (ATLAS_RESOLUTION_Y)>>1; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel1 { Texture = GaussianPyramidAtlasTexLevel1;};
#endif
#if TARGET_MIP >= 2
texture GaussianPyramidAtlasTexLevel2Tmp { Width = (ATLAS_RESOLUTION_X)>>2; Height = (ATLAS_RESOLUTION_Y)>>1; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel2Tmp { Texture = GaussianPyramidAtlasTexLevel2Tmp;};
texture GaussianPyramidAtlasTexLevel2 { Width = (ATLAS_RESOLUTION_X)>>2; Height = (ATLAS_RESOLUTION_Y)>>2; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel2 { Texture = GaussianPyramidAtlasTexLevel2;};
#endif
#if TARGET_MIP >= 3
texture GaussianPyramidAtlasTexLevel3Tmp { Width = (ATLAS_RESOLUTION_X)>>3; Height = (ATLAS_RESOLUTION_Y)>>2; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel3Tmp { Texture = GaussianPyramidAtlasTexLevel3Tmp;};
texture GaussianPyramidAtlasTexLevel3 { Width = (ATLAS_RESOLUTION_X)>>3; Height = (ATLAS_RESOLUTION_Y)>>3; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel3 { Texture = GaussianPyramidAtlasTexLevel3;};
#endif
#if TARGET_MIP >= 4
texture GaussianPyramidAtlasTexLevel4Tmp { Width = (ATLAS_RESOLUTION_X)>>4; Height = (ATLAS_RESOLUTION_Y)>>3; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel4Tmp { Texture = GaussianPyramidAtlasTexLevel4Tmp;};
texture GaussianPyramidAtlasTexLevel4 { Width = (ATLAS_RESOLUTION_X)>>4; Height = (ATLAS_RESOLUTION_Y)>>4; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel4 { Texture = GaussianPyramidAtlasTexLevel4;};
#endif
#if TARGET_MIP >= 5
texture GaussianPyramidAtlasTexLevel5Tmp { Width = (ATLAS_RESOLUTION_X)>>5; Height = (ATLAS_RESOLUTION_Y)>>4; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel5Tmp { Texture = GaussianPyramidAtlasTexLevel5Tmp;};
texture GaussianPyramidAtlasTexLevel5 { Width = (ATLAS_RESOLUTION_X)>>5; Height = (ATLAS_RESOLUTION_Y)>>5; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel5 { Texture = GaussianPyramidAtlasTexLevel5;};
#endif
#if TARGET_MIP >= 6
texture GaussianPyramidAtlasTexLevel6Tmp { Width = (ATLAS_RESOLUTION_X)>>6; Height = (ATLAS_RESOLUTION_Y)>>5; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel6Tmp { Texture = GaussianPyramidAtlasTexLevel6Tmp;};
texture GaussianPyramidAtlasTexLevel6 { Width = (ATLAS_RESOLUTION_X)>>6; Height = (ATLAS_RESOLUTION_Y)>>6; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel6 { Texture = GaussianPyramidAtlasTexLevel6;};
#endif
#if TARGET_MIP >= 7
texture GaussianPyramidAtlasTexLevel7Tmp { Width = (ATLAS_RESOLUTION_X)>>7; Height = (ATLAS_RESOLUTION_Y)>>6; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel7Tmp { Texture = GaussianPyramidAtlasTexLevel7Tmp;};
texture GaussianPyramidAtlasTexLevel7 { Width = (ATLAS_RESOLUTION_X)>>7; Height = (ATLAS_RESOLUTION_Y)>>7; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel7 { Texture = GaussianPyramidAtlasTexLevel7;};
#endif
#if TARGET_MIP >= 8
texture GaussianPyramidAtlasTexLevel8Tmp { Width = (ATLAS_RESOLUTION_X)>>8; Height = (ATLAS_RESOLUTION_Y)>>7; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel8Tmp { Texture = GaussianPyramidAtlasTexLevel8Tmp;};
texture GaussianPyramidAtlasTexLevel8 { Width = (ATLAS_RESOLUTION_X)>>8; Height = (ATLAS_RESOLUTION_Y)>>8; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel8 { Texture = GaussianPyramidAtlasTexLevel8;};
#endif
#if TARGET_MIP >= 9
texture GaussianPyramidAtlasTexLevel9Tmp { Width = (ATLAS_RESOLUTION_X)>>9; Height = (ATLAS_RESOLUTION_Y)>>8; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel9Tmp { Texture = GaussianPyramidAtlasTexLevel9Tmp;};
texture GaussianPyramidAtlasTexLevel9 { Width = (ATLAS_RESOLUTION_X)>>9; Height = (ATLAS_RESOLUTION_Y)>>9; Format = RGBA16F;};
sampler sGaussianPyramidAtlasTexLevel9 { Texture = GaussianPyramidAtlasTexLevel9;};
#endif

texture CollapsedLaplacianPyramidTex { Width = ATLAS_TILE_RESOLUTION_X; Height = ATLAS_TILE_RESOLUTION_Y; Format = RG16F;};
sampler sCollapsedLaplacianPyramidTex { Texture = CollapsedLaplacianPyramidTex;};

/*=============================================================================
	Functions
=============================================================================*/
/*
float get_optimal_exposure_bias(float c)
{
    float3 bounds = float3(-16, 16, 0);

    c *= c;
    c /= 1.0001 - c;   

    [loop]
    for(int j = 0; j < 32; j++)
    {   
        float tc = c * exp2(bounds.z);
        float luma = tc / (1 + tc);
        luma = sqrt(luma);
        bounds.xy = luma > 0.5 ? bounds.xz : bounds.zy;
        bounds.z = dot(bounds.xy, 0.5);
    }

    return bounds.z;
}*/

float remap_function(float x, float gaussian, float alpha)
{   
    //first channel of first tile is unaltered gaussian pyramid
    [flatten]if(gaussian < 0) return x;

/*
    //gaussian is the average brightness.
    float optimal_bias = get_optimal_exposure_bias(gaussian);

    x *= x;
    x /= 1.0001 - x;
    x *= exp2(optimal_bias);
    x /= 1.0 + x;
    x = sqrt(x);
    return x;
*/

    alpha = alpha > 0 ? 2 * alpha : alpha;
    gaussian = saturate(gaussian);
    float delta = x - gaussian;
    float w = saturate(1 - x * 2);
    w *= w;     
    return x + alpha * delta * exp(-delta * delta * 100.0) * saturate(1 - w * w);
}

#define degamma(_v) ((_v)*0.283799*((2.52405+(_v))*(_v)))
#define regamma(_v) (1.14374*(-0.126893*(_v)+sqrt(_v)))

float get_luma(float3 c)
{
    return regamma(dot(degamma(c), float3(0.2126, 0.7152, 0.0722)));
}

/*=============================================================================
	Shader Entry Points
=============================================================================*/

VSOUT MainVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv.xy);
    return o;
}

void InitPyramidAtlasPS(in VSOUT i, out float4 o : SV_Target0)
{
    //figure out 1D tile ID
    int2 tile_id = floor(i.uv * float2(ATLAS_TILES_X, ATLAS_TILES_Y));
    int tile_id_1d = tile_id.y * ATLAS_TILES_X + tile_id.x;

    //now, figure out remapping values per each tile
    //the 1st channel of the 1st tile is unchanged as we need an unaltered gaussian pyramid
    //x4 -> channels
    int num_remapping_intervals = ATLAS_TILES_X * ATLAS_TILES_Y * 4;//24
    int4 curr_remapping_intervals = tile_id_1d * 4 + int4(0, 1, 2, 3); //0 to 23
    curr_remapping_intervals--; //-1 to 22
    num_remapping_intervals--; //23

    //remap to 0 to 1
    //if this is below 0, it's the first tile and first channel, which we don't alter
    float4 normalized_remapping_intervals = float4(curr_remapping_intervals) / (num_remapping_intervals - 1);

    float2 tile_uv = frac(i.uv * float2(ATLAS_TILES_X, ATLAS_TILES_Y));
    float grey = get_luma(tex2D(ColorInput, tile_uv).rgb);   

    float4 remapped;
    remapped.x = remap_function(grey, normalized_remapping_intervals.x, STRENGTH);
    remapped.y = remap_function(grey, normalized_remapping_intervals.y, STRENGTH);
    remapped.z = remap_function(grey, normalized_remapping_intervals.z, STRENGTH);
    remapped.w = remap_function(grey, normalized_remapping_intervals.w, STRENGTH);

    remapped = saturate(remapped);
    o = remapped;   
}

//need pixel accurate blur since we need to mask pixel centers.
float4 tile_downsample_new(sampler s, float2 uv, const bool horizontal)
{
    float2 num_tiles = float2(ATLAS_TILES_X, ATLAS_TILES_Y);
    const float2 tile_uv_size = rcp(num_tiles);
    float2 tile_mid_uv = (floor(uv * num_tiles) + 0.5) * tile_uv_size;  

    float2 texelsize = rcp(tex2Dsize(s, 0));   
    float2 axis = horizontal ? float2(texelsize.x, 0) : float2(0, texelsize.y);

    float4 result = 0;
    float weightsum = 0;
  
    [unroll]for(int j = -4; j < 4; j++)
    {
        float offset = (j + 0.5);
        float w = exp(-offset * offset * 0.13);
        float2 tap_uv = uv + axis * offset;
        float4 tap = tex2Dlod(s, tap_uv, 0);

        //this compiles out
        if(horizontal) 
            w *= step(abs(tap_uv.x - tile_mid_uv.x), tile_uv_size.x * 0.5 - texelsize.x * 0.125); 
        else 
            w *= step(abs(tap_uv.y - tile_mid_uv.y), tile_uv_size.y * 0.5 - texelsize.y * 0.125);

        tap *= tap;
       
        result += tap * w;
        weightsum += w;
    }

    result *= rcp(weightsum);
    result = sqrt(result);
    return result;
}


#if TARGET_MIP >= 1
void DownsamplePyramidsPS0H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel0, i.uv, true);}
void DownsamplePyramidsPS0V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel1Tmp, i.uv, false);}
#endif
#if TARGET_MIP >= 2
void DownsamplePyramidsPS1H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel1, i.uv, true);}
void DownsamplePyramidsPS1V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel2Tmp, i.uv, false);}
#endif
#if TARGET_MIP >= 3
void DownsamplePyramidsPS2H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel2, i.uv, true);}
void DownsamplePyramidsPS2V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel3Tmp, i.uv, false);}
#endif
#if TARGET_MIP >= 4
void DownsamplePyramidsPS3H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel3, i.uv, true);}
void DownsamplePyramidsPS3V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel4Tmp, i.uv, false);}
#endif
#if TARGET_MIP >= 5
void DownsamplePyramidsPS4H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel4, i.uv, true);}
void DownsamplePyramidsPS4V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel5Tmp, i.uv, false);}
#endif
#if TARGET_MIP >= 6
void DownsamplePyramidsPS5H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel5, i.uv, true);}
void DownsamplePyramidsPS5V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel6Tmp, i.uv, false);}
#endif
#if TARGET_MIP >= 7
void DownsamplePyramidsPS6H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel6, i.uv, true);}
void DownsamplePyramidsPS6V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel7Tmp, i.uv, false);}
#endif
#if TARGET_MIP >= 8
void DownsamplePyramidsPS7H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel7, i.uv, true);}
void DownsamplePyramidsPS7V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel8Tmp, i.uv, false);}
#endif
#if TARGET_MIP >= 9
void DownsamplePyramidsPS8H(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel8, i.uv, true);}
void DownsamplePyramidsPS8V(in VSOUT i, out float4 o : SV_Target0){o = tile_downsample_new(sGaussianPyramidAtlasTexLevel9Tmp, i.uv, false);}
#endif

float sample_pyramid(sampler s, float2 uv, int pyramid_index)
{
    const int2 num_tiles = int2(ATLAS_TILES_X, ATLAS_TILES_Y);
    float2 tile_res = tex2Dsize(s, 0) / num_tiles;
    float2 texelsize = rcp(tile_res);

    //clamp to avoid bilinear interpolation across tiles
    uv = clamp(uv, texelsize, 1 - texelsize);

    int tile_id_1d = pyramid_index / 4;
    int channel = pyramid_index % 4;

    int2 tile_id = int2(tile_id_1d % ATLAS_TILES_X, tile_id_1d / ATLAS_TILES_X);
    float2 tile_start = float2(tile_id) / num_tiles;
    float2 tile_end = float2(tile_id + 1) / num_tiles;

    float2 tile_uv = lerp(tile_start, tile_end, uv);
    float pyramid = 0;
    
    if(INTERP == 0)
    {
        pyramid = tex2Dlod(s, tile_uv, 0)[channel];
    }
    else 
    {
        pyramid = Texture::sample2D_bspline_auto(s, tile_uv)[channel];
    }

    return pyramid;
}

float eval_laplacian(sampler s_i, sampler s_iplus1, float2 uv, int level)
{
    float G = sample_pyramid(s_i, uv, 0); 

    const float num_remapping_intervals = ATLAS_TILES_X * ATLAS_TILES_Y * 4 - 1; //23 intervals
    float denormalizedG = G * (num_remapping_intervals - 1);//0-22

    int lo_idx = floor(denormalizedG);
    int hi_idx = ceil(denormalizedG);
    float interpolant = frac(denormalizedG);    

    //0 is reserved for the plain gaussian pyramid, so it's now 1 to 23
    lo_idx++;
    hi_idx++; 

    float layer_a = lerp(sample_pyramid(s_i,      uv, lo_idx), sample_pyramid(s_i,      uv, hi_idx), interpolant);  
    float layer_b = lerp(sample_pyramid(s_iplus1, uv, lo_idx), sample_pyramid(s_iplus1, uv, hi_idx), interpolant);      
    return ((level + 1) == TARGET_MIP) ? layer_a : layer_a - layer_b;     
}

void CollapseTiledPyramidPS(in VSOUT i, out float2 o : SV_Target0)
{
    float collapsed = 0;

//laplacian layers
#if TARGET_MIP >= 1
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel0, sGaussianPyramidAtlasTexLevel1, i.uv, 0);
#endif 
#if TARGET_MIP >= 2  
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel1, sGaussianPyramidAtlasTexLevel2, i.uv, 1); 
#endif 
#if TARGET_MIP >= 3
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel2, sGaussianPyramidAtlasTexLevel3, i.uv, 2);
#endif 
#if TARGET_MIP >= 4
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel3, sGaussianPyramidAtlasTexLevel4, i.uv, 3);
#endif 
#if TARGET_MIP >= 5    
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel4, sGaussianPyramidAtlasTexLevel5, i.uv, 4);
#endif 
#if TARGET_MIP >= 6    
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel5, sGaussianPyramidAtlasTexLevel6, i.uv, 5);
#endif
#if TARGET_MIP >= 7    
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel6, sGaussianPyramidAtlasTexLevel7, i.uv, 6);
#endif  
#if TARGET_MIP >= 8    
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel7, sGaussianPyramidAtlasTexLevel8, i.uv, 7);
#endif 
#if TARGET_MIP >= 9    
    collapsed += eval_laplacian(sGaussianPyramidAtlasTexLevel8, sGaussianPyramidAtlasTexLevel9, i.uv, 8);
#endif 

    o.x = collapsed;
    o.y = get_luma(tex2D(ColorInput, i.uv).rgb);
}

void GuidedUpsamplingPS(in VSOUT i, out float3 o : SV_Target0)
{    
     float2 gaussian_sigma0dot7 = float2(0.5424, 0.2288);

    float4 moments = 0; //guide, guide^2, guide*signal, signal
    float ws = 0.0;
    
    [unroll]for(int y = -1; y <= 1; y++)
    [unroll]for(int x = -1; x <= 1; x++)  
    {
        float2 offs = float2(x, y);
        float2 t = tex2D(sCollapsedLaplacianPyramidTex, i.uv + offs * BUFFER_PIXEL_SIZE * RESOLUTION_DIV).xy;
        float w = gaussian_sigma0dot7[abs(x)] * gaussian_sigma0dot7[abs(y)];
        moments += float4(t.y, t.y * t.y, t.y * t.x, t.x) * w;
        ws += w;
    }    

    moments /= ws;
    
    float A = (moments.z - moments.x * moments.w) / (max(moments.y - moments.x * moments.x, 0.0) + 0.00001);
    float B = moments.w - A * moments.x;

    o = tex2D(ColorInput, i.uv).rgb;
    
    float luma = get_luma(o);    
    float adjusted_luma = A * luma + B;

    o = degamma(o);
    o = o / (1.1 - o);
    float ratioooo = adjusted_luma / (luma + 1e-6);
    o *= ratioooo;
    o = 1.1 * o / (1.0 + o);
    o = regamma(o);   
}

/*=============================================================================
	Techniques
=============================================================================*/


technique MartysMods_LocalLaplacian
<
    ui_label = "METEOR: Local Laplacian";
    ui_tooltip =        
        "                          MartysMods - Local Laplacian                        \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"

        "METEOR Local Laplacian is an implementation of the 'Fast Local Laplacian'.   \n"
        "FLL is state of the art in terms of local contrast enhancement and the backbone\n"
        "of ADOBE Lightroom's Clarity/Texture/Dehaze feature.                          \n"
        "METEOR Local Laplacian is the only realtime capable implementation so far.   \n"
        "\n"
        "\n"
        "Visit https://martysmods.com for more information.                            \n"
        "\n"       
        "______________________________________________________________________________";
>
{    
    pass    {VertexShader = MainVS;PixelShader = InitPyramidAtlasPS; RenderTarget = GaussianPyramidAtlasTexLevel0; } 

#if TARGET_MIP >= 1
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS0H; RenderTarget = GaussianPyramidAtlasTexLevel1Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS0V; RenderTarget = GaussianPyramidAtlasTexLevel1; } 
#endif
#if TARGET_MIP >= 2
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS1H; RenderTarget = GaussianPyramidAtlasTexLevel2Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS1V; RenderTarget = GaussianPyramidAtlasTexLevel2; } 
#endif
#if TARGET_MIP >= 3 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS2H; RenderTarget = GaussianPyramidAtlasTexLevel3Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS2V; RenderTarget = GaussianPyramidAtlasTexLevel3; } 
#endif
#if TARGET_MIP >= 4 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS3H; RenderTarget = GaussianPyramidAtlasTexLevel4Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS3V; RenderTarget = GaussianPyramidAtlasTexLevel4; } 
#endif
#if TARGET_MIP >= 5 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS4H; RenderTarget = GaussianPyramidAtlasTexLevel5Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS4V; RenderTarget = GaussianPyramidAtlasTexLevel5; } 
#endif
#if TARGET_MIP >= 6 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS5H; RenderTarget = GaussianPyramidAtlasTexLevel6Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS5V; RenderTarget = GaussianPyramidAtlasTexLevel6; } 
#endif
#if TARGET_MIP >= 7 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS6H; RenderTarget = GaussianPyramidAtlasTexLevel7Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS6V; RenderTarget = GaussianPyramidAtlasTexLevel7; } 
#endif
#if TARGET_MIP >= 8 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS7H; RenderTarget = GaussianPyramidAtlasTexLevel8Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS7V; RenderTarget = GaussianPyramidAtlasTexLevel8; } 
#endif 
#if TARGET_MIP >= 9 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS8H; RenderTarget = GaussianPyramidAtlasTexLevel9Tmp; } 
    pass    {VertexShader = MainVS;PixelShader = DownsamplePyramidsPS8V; RenderTarget = GaussianPyramidAtlasTexLevel9; } 
#endif
    
    pass    {VertexShader = MainVS;PixelShader = CollapseTiledPyramidPS; RenderTarget = CollapsedLaplacianPyramidTex; }
    pass    {VertexShader = MainVS;PixelShader = GuidedUpsamplingPS; }
}




