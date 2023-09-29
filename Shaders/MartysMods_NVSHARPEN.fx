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

    Port of NVSharpen from NIS Library
    With some artistic liberties that is

    All third party code belongs to its respective authors

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

uniform float SHARP_AMT <
	ui_type = "drag";
    ui_label = "Sharpen Intensity";
	ui_min = 0.0; 
    ui_max = 1.0;
> = 0.5;

uniform float DETECT_THRESH_MULT <
	ui_type = "drag";
    ui_label = "Edge Detection Threshold";
	ui_min = 0.0; 
    ui_max = 1.0;
> = 0.3;

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

//do NOT change anything here. "hurr durr I changed this and now it works"
//you ARE breaking things down the line, if the shader does not work without changes
//here, it's by design.

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex;  SRGBTexture = true;};

#include "MartysMods\mmx_global.fxh"

struct VSOUT
{
	float4                  vpos        : SV_Position;
    float2                  uv          : TEXCOORD0;
};

/*=============================================================================
	Functions
=============================================================================*/

#define kSupportSize        5
#define kContrastBoost      1.0
#define kEps                (1.0f / 255.0f)
//#define sharpen_slider 0.5 //-0.5 to 0.5

static const float kDetectRatio = 2 * 1127.f / 1024.f;
#define kDetectThres (64.0f / 1024.0f * saturate(DETECT_THRESH_MULT * DETECT_THRESH_MULT))
static const float kMinContrastRatio = 2.0f;
static const float kMaxContrastRatio = 10.0f;

static const float kSharpStartY = 0.45f;
static const float kSharpEndY = 0.9f;

static const float kRatioNorm = 1.0f / (kMaxContrastRatio - kMinContrastRatio);
static const float kSharpScaleY = 1.0f / (kSharpEndY - kSharpStartY);

struct NVSharpenParams
{
    float kSharpStrengthMin;
    float kSharpStrengthMax;
    float kSharpLimitMin;
    float kSharpLimitMax;
    float kSharpStrengthScale;
    float kSharpLimitScale;
};

NVSharpenParams setup()
{
    float sharpen_slider = saturate(SHARP_AMT) - 0.5;

    float LimitScale = sharpen_slider > 0 ? 1.25 : 1;
    float MaxScale = sharpen_slider > 0 ? 1.25 : 1.75;
    float MinScale = sharpen_slider > 0 ? 1.25 : 1;

    NVSharpenParams params;

    params.kSharpStrengthMin    = max(0.0f, 0.4f + sharpen_slider * MinScale * 1.2f);
    params.kSharpStrengthMax    = 1.6f + sharpen_slider * MaxScale * 1.8f;
    params.kSharpLimitMin       = max(0.1f, 0.14f + sharpen_slider * LimitScale * 0.32f);
    params.kSharpLimitMax       = 0.5f + sharpen_slider * LimitScale * 0.6f;
    params.kSharpStrengthScale  = params.kSharpStrengthMax - params.kSharpStrengthMin;
    params.kSharpLimitScale     = params.kSharpLimitMax - params.kSharpLimitMin;

    return params;
}

float CalcLTIFast(const float y[5])
{
    const float a_min = min(min(y[0], y[1]), y[2]);
    const float a_max = max(max(y[0], y[1]), y[2]);

    const float b_min = min(min(y[2], y[3]), y[4]);
    const float b_max = max(max(y[2], y[3]), y[4]);

    const float a_cont = a_max - a_min;
    const float b_cont = b_max - b_min;

    const float cont_ratio = max(a_cont, b_cont) / (min(a_cont, b_cont) + kEps);
    return (1.0f - saturate((cont_ratio - kMinContrastRatio) * kRatioNorm)) * kContrastBoost;
}


float EvalUSM(float pxl[5], float sharpnessStrength, float sharpnessLimit)
{
    // USM profile
    float y_usm = -0.6001f * pxl[1] + 1.2002f * pxl[2] - 0.6001f * pxl[3];
    // boost USM profile
    y_usm *= sharpnessStrength;
    // clamp to the limit
    y_usm = min(sharpnessLimit, max(-sharpnessLimit, y_usm));
    // reduce ringing
    y_usm *= CalcLTIFast(pxl);

    return y_usm;
}


float4 GetDirUSM(float p[25], NVSharpenParams params)
{
     // sharpness boost & limit are the same for all directions
    const float scaleY = 1.0f - saturate((p[5*2+2] - kSharpStartY) * kSharpScaleY);
    // scale the ramp to sharpen as a function of luma
    const float sharpnessStrength = scaleY * params.kSharpStrengthScale + params.kSharpStrengthMin;
    // scale the ramp to limit USM as a function of luma
    const float sharpnessLimit = (scaleY * params.kSharpLimitScale + params.kSharpLimitMin) * p[5*2+2];

    float4 rval;
    // 0 deg filter
    float interp0Deg[5];
    {
        [unroll]for (int i = 0; i < 5; ++i)
        {
            interp0Deg[i] = p[i*5+2];
        }
    }

    rval.x = EvalUSM(interp0Deg, sharpnessStrength, sharpnessLimit);

    // 90 deg filter
    float interp90Deg[5];
    {
        [unroll]for (int i = 0; i < 5; ++i)
        {
            interp90Deg[i] = p[2*5+i];
        }
    }

    rval.y = EvalUSM(interp90Deg, sharpnessStrength, sharpnessLimit);

    //45 deg filter
    float interp45Deg[5];
    interp45Deg[0] = p[1*5+1];
    interp45Deg[1] = lerp(p[2*5+1], p[1*5+2], 0.5f);
    interp45Deg[2] = p[2*5+2];
    interp45Deg[3] = lerp(p[3*5+2], p[2*5+3], 0.5f);
    interp45Deg[4] = p[3*5+3];

    rval.z = EvalUSM(interp45Deg, sharpnessStrength, sharpnessLimit);

    //135 deg filter
    float interp135Deg[5];
    interp135Deg[0] = p[3*5+1];
    interp135Deg[1] = lerp(p[3*5+2], p[2*5+1], 0.5f);
    interp135Deg[2] = p[2*5+2];
    interp135Deg[3] = lerp(p[2*5+3], p[1*5+2], 0.5f);
    interp135Deg[4] = p[1*5+3];

    rval.w = EvalUSM(interp135Deg, sharpnessStrength, sharpnessLimit);
    return rval;
}

float4 GetEdgeMap(float p[25], int i, int j)
{
    float g_0 = abs(p[(0 + i)*5+(0 + j)] + p[(0 + i)*5+(1 + j)] + p[(0 + i)*5+(2 + j)] - p[(2 + i)*5+(0 + j)] - p[(2 + i)*5+(1 + j)] - p[(2 + i)*5+(2 + j)]);
    float g_45 = abs(p[(1 + i)*5+(0 + j)] + p[(0 + i)*5+(0 + j)] + p[(0 + i)*5+(1 + j)] - p[(2 + i)*5+(1 + j)] - p[(2 + i)*5+(2 + j)] - p[(1 + i)*5+(2 + j)]);
    float g_90 = abs(p[(0 + i)*5+(0 + j)] + p[(1 + i)*5+(0 + j)] + p[(2 + i)*5+(0 + j)] - p[(0 + i)*5+(2 + j)] - p[(1 + i)*5+(2 + j)] - p[(2 + i)*5+(2 + j)]);
    float g_135 = abs(p[(1 + i)*5+(0 + j)] + p[(2 + i)*5+(0 + j)] + p[(2 + i)*5+(1 + j)] - p[(0 + i)*5+(1 + j)] - p[(0 + i)*5+(2 + j)] - p[(1 + i)*5+(2 + j)]);

    float g_0_90_max = max(g_0, g_90);
    float g_0_90_min = min(g_0, g_90);
    float g_45_135_max = max(g_45, g_135);
    float g_45_135_min = min(g_45, g_135);

    float e_0_90 = 0;
    float e_45_135 = 0;

    if (g_0_90_max + g_45_135_max == 0)
    {
        return float4(0, 0, 0, 0);
    }

    e_0_90 = min(g_0_90_max / (g_0_90_max + g_45_135_max), 1.0f);
    e_45_135 = 1.0f - e_0_90;

    bool c_0_90 = (g_0_90_max > (g_0_90_min * kDetectRatio)) && (g_0_90_max > kDetectThres) && (g_0_90_max > g_45_135_min);
    bool c_45_135 = (g_45_135_max > (g_45_135_min * kDetectRatio)) && (g_45_135_max > kDetectThres) && (g_45_135_max > g_0_90_min);
    bool c_g_0_90 = g_0_90_max == g_0;
    bool c_g_45_135 = g_45_135_max == g_45;

    float f_e_0_90 = (c_0_90 && c_45_135) ? e_0_90 : 1.0f;
    float f_e_45_135 = (c_0_90 && c_45_135) ? e_45_135 : 1.0f;

    float weight_0 = (c_0_90 && c_g_0_90) ? f_e_0_90 : 0.0f;
    float weight_90 = (c_0_90 && !c_g_0_90) ? f_e_0_90 : 0.0f;
    float weight_45 = (c_45_135 && c_g_45_135) ? f_e_45_135 : 0.0f;
    float weight_135 = (c_45_135 && !c_g_45_135) ? f_e_45_135 : 0.0f;

    return float4(weight_0, weight_90, weight_45, weight_135);
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

void MainPS(in VSOUT i, out float3 o : SV_Target0)
{  
    NVSharpenParams params = setup();

    float p[25];

    [unroll]for(int x = 0; x < 5; x++)
    [unroll]for(int y = 0; y < 5; y++)
    {
        float lum = dot(tex2D(ColorInput, i.uv, int2(x-2, y-2)).rgb, float3(0.2126, 0.7152, 0.0722));
        int idx = x *5 + y;
        p[idx] = lum;
    }

    // get directional filter bank output
    float4 dirUSM = GetDirUSM(p, params);

    // generate weights for directional filters
    float4 w = GetEdgeMap(p, kSupportSize / 2 - 1, kSupportSize / 2 - 1);

    // final USM is a weighted sum filter outputs   
    float usmY = (dirUSM.x * w.x + dirUSM.y * w.y + dirUSM.z * w.z + dirUSM.w * w.w);

    float4 op = tex2D(ColorInput, i.uv);

    op.rgb += usmY;
    op.rgb = saturate(op.rgb);
    o = op.rgb;
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_NvidiaSharpen
<
    ui_label = "METEOR NVSharpen";
    ui_tooltip =        
        "                             MartysMods - NVSharpen                           \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"

        "This is a port of Nvidia's NVSharpen filter from the NIS Library, made compatible\n"
        "with DirectX 9 as well.                                                       \n"       
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
		PixelShader  = MainPS; 
        SRGBWriteEnable = true; 
	}      
}