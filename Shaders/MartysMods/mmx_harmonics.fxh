/*=============================================================================

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
 
=============================================================================*/

#pragma once 

#include "mmx_math.fxh"

namespace SphericalHarmonics 
{

float4 dir_to_sh(float3 v) 
{
    const float c0 = 0.5 * sqrt(1.0  / PI);
    const float c1 =       sqrt(0.75 / PI);
    return float4(c0, -c1 * v.y, c1 * v.z, -c1 * v.x);
}

//defaults to cosine convolution
float4 dir_to_irradiance_probe(float4 sh, float sharpness = 1)
{
	const float c0 = 2 - sharpness;
	const float c1 = sharpness * 0.66666;
    return sh * float4(c0, c1.xxx);
}

float3 linear_eval_irradiance(float4 sh_r, float4 sh_g, float4 sh_b, float3 v, float sharpness = 1)
{
    float4 sh_dir = dir_to_sh(v);
    sh_dir = dir_to_irradiance_probe(sh_dir, sharpness);//cosine conv
    return float3(dot(sh_r, sh_dir), dot(sh_g, sh_dir), dot(sh_b, sh_dir));
}

float3 hallucinate_zh3_irradiance(float4 sh_r, float4 sh_g, float4 sh_b, float3 v, float sharpness = 1)
{
    const float3 lum_coeffs = float3(0.2126, 0.7152, 0.0722);
    float3 zonal_axis = (sh_r.wyz * lum_coeffs.x + sh_g.wyz * lum_coeffs.y + sh_b.wyz * lum_coeffs.z) * float3(-1,-1,1);
    //zonal_axis = normalize(zonal_axis);//Deferring the multiply of that since we can just scale the scalar results of ops with this axis
    float invzonalaxislen = rsqrt(dot(zonal_axis, zonal_axis) + 1e-8);
    
    float3 ratio = abs(-float3(sh_r.w, sh_g.w, sh_b.w) * zonal_axis.x 
                     + -float3(sh_r.y, sh_g.y, sh_b.y) * zonal_axis.y 
                     +  float3(sh_r.z, sh_g.z, sh_b.z) * zonal_axis.z);
    ratio /= float3(sh_r.x, sh_g.x, sh_b.x);
    ratio *= invzonalaxislen;

    float3 zonal_l2_coeff = float3(sh_r.x, sh_g.x, sh_b.x) * ((0.6 * ratio + 0.08) * ratio);
    float fZ = dot(zonal_axis, v) * invzonalaxislen;
    float zh_dir = sqrt(5 / (16 * PI)) * (3 * fZ * fZ - 1);
    //cosine conv - technically incorrect to add a sharpness param here but I might need the flexibility.
    return linear_eval_irradiance(sh_r, sh_g, sh_b, v, sharpness) + 0.25 * zonal_l2_coeff * zh_dir;
}

}