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

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex; };

texture2D CollapsedLaplacian	      { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler2D sCollapsedLaplacian		  { Texture = CollapsedLaplacian;};

texture2D GaussianPyramid0	      { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler2D sGaussianPyramid0		  { Texture = GaussianPyramid0; };
texture2D GaussianPyramid1	      { Width = BUFFER_WIDTH>>1; Height = BUFFER_HEIGHT>>1; Format = R16F; };
sampler2D sGaussianPyramid1		  { Texture = GaussianPyramid1; };
texture2D GaussianPyramid2	      { Width = BUFFER_WIDTH>>2; Height = BUFFER_HEIGHT>>2; Format = R16F; };
sampler2D sGaussianPyramid2		  { Texture = GaussianPyramid2; };
texture2D GaussianPyramid3	      { Width = BUFFER_WIDTH>>3; Height = BUFFER_HEIGHT>>3; Format = R16F; };
sampler2D sGaussianPyramid3		  { Texture = GaussianPyramid3; };
texture2D GaussianPyramid4	      { Width = BUFFER_WIDTH>>4; Height = BUFFER_HEIGHT>>4; Format = R16F; };
sampler2D sGaussianPyramid4		  { Texture = GaussianPyramid4; };
texture2D GaussianPyramid5	      { Width = BUFFER_WIDTH>>5; Height = BUFFER_HEIGHT>>5; Format = R16F;  };
sampler2D sGaussianPyramid5		  { Texture = GaussianPyramid5; };

texture2D WorkingPyramid0	      { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler2D sWorkingPyramid0		  { Texture = WorkingPyramid0; };
texture2D WorkingPyramid1	      { Width = BUFFER_WIDTH>>1; Height = BUFFER_HEIGHT>>1; Format = RGBA16F; };
sampler2D sWorkingPyramid1		  { Texture = WorkingPyramid1; };
texture2D WorkingPyramid2	      { Width = BUFFER_WIDTH>>2; Height = BUFFER_HEIGHT>>2; Format = RGBA16F; };
sampler2D sWorkingPyramid2		  { Texture = WorkingPyramid2; };
texture2D WorkingPyramid3	      { Width = BUFFER_WIDTH>>3; Height = BUFFER_HEIGHT>>3; Format = RGBA16F; };
sampler2D sWorkingPyramid3		  { Texture = WorkingPyramid3; };
texture2D WorkingPyramid4	      { Width = BUFFER_WIDTH>>4; Height = BUFFER_HEIGHT>>4; Format = RGBA16F; };
sampler2D sWorkingPyramid4		  { Texture = WorkingPyramid4; };
texture2D WorkingPyramid5	      { Width = BUFFER_WIDTH>>5; Height = BUFFER_HEIGHT>>5; Format = RGBA16F; };
sampler2D sWorkingPyramid5		  { Texture = WorkingPyramid5; };

struct VSOUT
{
	float4                  vpos        : SV_Position;
    float2                  uv          : TEXCOORD0;    
};

#include ".\MartysMods\mmx_global.fxh"
#include ".\MartysMods\mmx_math.fxh"

/*=============================================================================
	Functions
=============================================================================*/

float remap_func(float x, float gaussian, float alpha)
{
    const float range = 10.0;
    float tx = x - gaussian;
    x += exp(-tx * tx * abs(tx) * range * range) * tx * alpha;
    return x;
}

//Optimized Bspline bicubic filtering
//FXC assembly: 37->25 ALU, 5->3 registers
//One texture coord known early, better for latency
float4 sample_bicubic(sampler s, float2 iuv, int2 size, int mip)
{
    size /= int(round(exp2(mip)));

    float4 uv;
	uv.xy = iuv * size;

    float2 center = floor(uv.xy - 0.5) + 0.5;
	float4 d = float4(uv.xy - center, 1 + center - uv.xy);
	float4 d2 = d * d;
	float4 d3 = d2 * d;

    float4 o = d2 * 0.12812 + d3 * 0.07188; //approx |err|*255 < 0.2 < bilinear precision
	uv.xy = center - o.zw;
	uv.zw = center + 1 + o.xy;
	uv /= size.xyxy;

    float4 w = 0.16666666 + d * 0.5 + 0.5 * d2 - d3 * 0.3333333;
	w = w.wwyy * w.zxzx;

    return w.x * tex2Dlod(s, uv.xy, mip)
	     + w.y * tex2Dlod(s, uv.zy, mip)
		 + w.z * tex2Dlod(s, uv.xw, mip)
		 + w.w * tex2Dlod(s, uv.zw, mip);
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

float4 gaussian5x5(sampler s, float2 uv, int it)
{    
    float2 o = BUFFER_PIXEL_SIZE * exp2(it);
    float3 c = float3(-1.23888, 0.404756, 2.0);
    float3 w = float3(0.29777, 0.56, 0.14224);
    float4 g = 0;

    [unroll]
    for(uint j = 0; j < 9; j++)
    {
        float4 t = tex2Dlod(s, uv + o * float2(c[j/3u], c[j%3u]), 0);
        g += t * w[j/3u] * w[j%3u]; 
    }

    return g;
}

float4 init_remapped_pyramid(float2 uv, float4 lambdas)
{
    float grey = get_luma(tex2D(ColorInput, uv).rgb); 

    float4 remapped;
    remapped.x = remap_func(grey, lambdas.x, STRENGTH);
    remapped.y = remap_func(grey, lambdas.y, STRENGTH);
    remapped.z = remap_func(grey, lambdas.z, STRENGTH);
    remapped.w = remap_func(grey, lambdas.w, STRENGTH);
    return remapped;
}

#define TOTAL_INTERVALS 15.0 //no touchy >:(

float4 collapse_laplacians(float2 uv, float4 lambdas)
{
    float4 layers[6] = 
    {
        tex2D(sWorkingPyramid0, uv),
        tex2D(sWorkingPyramid1, uv),
        sample_bicubic(sWorkingPyramid2, uv, BUFFER_SCREEN_SIZE >>2, 0),
        sample_bicubic(sWorkingPyramid3, uv, BUFFER_SCREEN_SIZE >>3, 0),
        sample_bicubic(sWorkingPyramid4, uv, BUFFER_SCREEN_SIZE >>4, 0),
        sample_bicubic(sWorkingPyramid5, uv, BUFFER_SCREEN_SIZE >>5, 0)
    };

    float gaussians[6] = 
    {
        tex2D(sGaussianPyramid0, uv).x,
        tex2D(sGaussianPyramid1, uv).x,
        sample_bicubic(sGaussianPyramid2, uv, BUFFER_SCREEN_SIZE >>2, 0).x,
        sample_bicubic(sGaussianPyramid3, uv, BUFFER_SCREEN_SIZE >>3, 0).x,
        sample_bicubic(sGaussianPyramid4, uv, BUFFER_SCREEN_SIZE >>4, 0).x,
        sample_bicubic(sGaussianPyramid5, uv, BUFFER_SCREEN_SIZE >>5, 0).x
    };

    float collapsed = 0;

    [loop]
    for(int j = 0; j < 5; j++)
    {
        float gaussian = gaussians[j];
        float4 laplacians = layers[j] - layers[j + 1];
        float3 is_in_interval = step(lambdas.xyz, gaussian) - step(lambdas.yzw, gaussian);

        float3 lerps = linearstep(lambdas.xyz, lambdas.yzw, gaussian);    
        float laplacian_in_curr_interval = dot(lerp(laplacians.xyz, laplacians.yzw, lerps), is_in_interval);
        collapsed += laplacian_in_curr_interval;        
    }

    return collapsed;
}

void InitialPyramidPS0(in VSOUT i, out float4 o : SV_Target0){o = get_luma(tex2D(ColorInput, i.uv).rgb);}
void DownsampleGaussianPyramidPS0(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sGaussianPyramid0, i.uv, 0);}
void DownsampleGaussianPyramidPS1(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sGaussianPyramid1, i.uv, 1);}
void DownsampleGaussianPyramidPS2(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sGaussianPyramid2, i.uv, 2);}
void DownsampleGaussianPyramidPS3(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sGaussianPyramid3, i.uv, 3);}
void DownsampleGaussianPyramidPS4(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sGaussianPyramid4, i.uv, 4);}
void DownsampleGaussianPyramidPS5(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sGaussianPyramid5, i.uv, 5);}

void WriteResidualPS(in VSOUT i, out float4 o : SV_Target0){o = sample_bicubic(sGaussianPyramid5, i.uv, BUFFER_SCREEN_SIZE >> 5, 0).x; }

void InitHybridPSWave0(in VSOUT i, out float4 o : SV_Target0){o = init_remapped_pyramid(i.uv, float4(0,1,2,3) / TOTAL_INTERVALS);}
void DownsampleHybridPyramidPS0Wave0(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid0, i.uv, 0);}
void DownsampleHybridPyramidPS1Wave0(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid1, i.uv, 1);}
void DownsampleHybridPyramidPS2Wave0(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid2, i.uv, 2);}
void DownsampleHybridPyramidPS3Wave0(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid3, i.uv, 3);}
void DownsampleHybridPyramidPS4Wave0(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid4, i.uv, 4);}
void BlendPyramidPSWave0(in VSOUT i, out float4 o : SV_Target0){o = collapse_laplacians(i.uv, float4(0,1,2,3) / TOTAL_INTERVALS);}

void InitHybridPSWave1(in VSOUT i, out float4 o : SV_Target0){o = init_remapped_pyramid(i.uv, float4(3,4,5,6) / TOTAL_INTERVALS);}
void DownsampleHybridPyramidPS0Wave1(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid0, i.uv, 0);}
void DownsampleHybridPyramidPS1Wave1(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid1, i.uv, 1);}
void DownsampleHybridPyramidPS2Wave1(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid2, i.uv, 2);}
void DownsampleHybridPyramidPS3Wave1(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid3, i.uv, 3);}
void DownsampleHybridPyramidPS4Wave1(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid4, i.uv, 4);}
void BlendPyramidPSWave1(in VSOUT i, out float4 o : SV_Target0){o = collapse_laplacians(i.uv, float4(3,4,5,6) / TOTAL_INTERVALS);}

void InitHybridPSWave2(in VSOUT i, out float4 o : SV_Target0){o = init_remapped_pyramid(i.uv, float4(6,7,8,9) / TOTAL_INTERVALS);}
void DownsampleHybridPyramidPS0Wave2(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid0, i.uv, 0);}
void DownsampleHybridPyramidPS1Wave2(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid1, i.uv, 1);}
void DownsampleHybridPyramidPS2Wave2(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid2, i.uv, 2);}
void DownsampleHybridPyramidPS3Wave2(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid3, i.uv, 3);}
void DownsampleHybridPyramidPS4Wave2(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid4, i.uv, 4);}
void BlendPyramidPSWave2(in VSOUT i, out float4 o : SV_Target0){o = collapse_laplacians(i.uv, float4(6,7,8,9) / TOTAL_INTERVALS);}

void InitHybridPSWave3(in VSOUT i, out float4 o : SV_Target0){o = init_remapped_pyramid(i.uv, float4(9,10,11,12) / TOTAL_INTERVALS);}
void DownsampleHybridPyramidPS0Wave3(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid0, i.uv, 0);}
void DownsampleHybridPyramidPS1Wave3(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid1, i.uv, 1);}
void DownsampleHybridPyramidPS2Wave3(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid2, i.uv, 2);}
void DownsampleHybridPyramidPS3Wave3(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid3, i.uv, 3);}
void DownsampleHybridPyramidPS4Wave3(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid4, i.uv, 4);}
void BlendPyramidPSWave3(in VSOUT i, out float4 o : SV_Target0){o = collapse_laplacians(i.uv, float4(9,10,11,12) / TOTAL_INTERVALS);}

void InitHybridPSWave4(in VSOUT i, out float4 o : SV_Target0){o = init_remapped_pyramid(i.uv, float4(12,13,14,15) / TOTAL_INTERVALS);}
void DownsampleHybridPyramidPS0Wave4(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid0, i.uv, 0);}
void DownsampleHybridPyramidPS1Wave4(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid1, i.uv, 1);}
void DownsampleHybridPyramidPS2Wave4(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid2, i.uv, 2);}
void DownsampleHybridPyramidPS3Wave4(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid3, i.uv, 3);}
void DownsampleHybridPyramidPS4Wave4(in VSOUT i, out float4 o : SV_Target0){o = gaussian5x5(sWorkingPyramid4, i.uv, 4);}
void BlendPyramidPSWave4(in VSOUT i, out float4 o : SV_Target0){o = collapse_laplacians(i.uv, float4(12,13,14,15) / TOTAL_INTERVALS);}

void MainPS(in VSOUT i, out float3 o : SV_Target0)
{
    o = tex2D(ColorInput, i.uv).rgb;
    float luma = get_luma(o);
    o = degamma(o);
    o *= tex2D(sCollapsedLaplacian, i.uv).x / (luma + 1e-6);
    o = regamma(o);
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_LocalLaplacian
<
    ui_label = "METEOR Local Laplacian";
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
    pass    {VertexShader = MainVS;PixelShader = InitialPyramidPS0;RenderTarget = GaussianPyramid0; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleGaussianPyramidPS0;RenderTarget = GaussianPyramid1; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleGaussianPyramidPS1;RenderTarget = GaussianPyramid2; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleGaussianPyramidPS2;RenderTarget = GaussianPyramid3; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleGaussianPyramidPS3;RenderTarget = GaussianPyramid4; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleGaussianPyramidPS4;RenderTarget = GaussianPyramid5; } 

    //residual MUST NOT be remapped!
    pass    {VertexShader = MainVS;PixelShader = WriteResidualPS;RenderTarget = CollapsedLaplacian; }  

    pass    {VertexShader = MainVS;PixelShader = InitHybridPSWave0;RenderTarget = WorkingPyramid0; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS0Wave0;RenderTarget = WorkingPyramid1; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS1Wave0;RenderTarget = WorkingPyramid2; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS2Wave0;RenderTarget = WorkingPyramid3; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS3Wave0;RenderTarget = WorkingPyramid4; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS4Wave0;RenderTarget = WorkingPyramid5; } 
    pass    {VertexShader = MainVS;PixelShader = BlendPyramidPSWave0; RenderTarget = CollapsedLaplacian; BlendEnable = true;BlendOp = ADD;SrcBlend = ONE;DestBlend = ONE; } 

    pass    {VertexShader = MainVS;PixelShader = InitHybridPSWave1;RenderTarget = WorkingPyramid0; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS0Wave1;RenderTarget = WorkingPyramid1; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS1Wave1;RenderTarget = WorkingPyramid2; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS2Wave1;RenderTarget = WorkingPyramid3; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS3Wave1;RenderTarget = WorkingPyramid4; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS4Wave1;RenderTarget = WorkingPyramid5; } 
    pass    {VertexShader = MainVS;PixelShader = BlendPyramidPSWave1; RenderTarget = CollapsedLaplacian; BlendEnable = true;BlendOp = ADD;SrcBlend = ONE;DestBlend = ONE; } 

    pass    {VertexShader = MainVS;PixelShader = InitHybridPSWave2;RenderTarget = WorkingPyramid0; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS0Wave2;RenderTarget = WorkingPyramid1; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS1Wave2;RenderTarget = WorkingPyramid2; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS2Wave2;RenderTarget = WorkingPyramid3; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS3Wave2;RenderTarget = WorkingPyramid4; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS4Wave2;RenderTarget = WorkingPyramid5; } 
    pass    {VertexShader = MainVS;PixelShader = BlendPyramidPSWave2; RenderTarget = CollapsedLaplacian; BlendEnable = true;BlendOp = ADD;SrcBlend = ONE;DestBlend = ONE; } 

    pass    {VertexShader = MainVS;PixelShader = InitHybridPSWave3;RenderTarget = WorkingPyramid0; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS0Wave3;RenderTarget = WorkingPyramid1; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS1Wave3;RenderTarget = WorkingPyramid2; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS2Wave3;RenderTarget = WorkingPyramid3; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS3Wave3;RenderTarget = WorkingPyramid4; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS4Wave3;RenderTarget = WorkingPyramid5; } 
    pass    {VertexShader = MainVS;PixelShader = BlendPyramidPSWave3; RenderTarget = CollapsedLaplacian; BlendEnable = true;BlendOp = ADD;SrcBlend = ONE;DestBlend = ONE; } 

    pass    {VertexShader = MainVS;PixelShader = InitHybridPSWave4;RenderTarget = WorkingPyramid0; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS0Wave4;RenderTarget = WorkingPyramid1; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS1Wave4;RenderTarget = WorkingPyramid2; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS2Wave4;RenderTarget = WorkingPyramid3; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS3Wave4;RenderTarget = WorkingPyramid4; }  
    pass    {VertexShader = MainVS;PixelShader = DownsampleHybridPyramidPS4Wave4;RenderTarget = WorkingPyramid5; } 
    pass    {VertexShader = MainVS;PixelShader = BlendPyramidPSWave4; RenderTarget = CollapsedLaplacian; BlendEnable = true;BlendOp = ADD;SrcBlend = ONE;DestBlend = ONE; } 

    pass    {VertexShader = MainVS;PixelShader = MainPS;}    
}