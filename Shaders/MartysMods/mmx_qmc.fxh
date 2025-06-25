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

//All things quasirandom
#include "mmx_global.fxh"

namespace QMC
{

/*=============================================================================
    Generalized golden ratio sequences (Dr. Martin Roberts)
=============================================================================*/

#if _BITWISE_SUPPORTED
// improved golden ratio sequences v2 (P. Gilcher, 2023)
// https://www.shadertoy.com/view/csdGWX
float roberts1(in uint idx, in float seed = 0.5)
{
    uint useed = uint(seed * exp2(32.0));
    uint phi = 2654435769u;
    return float(phi * idx + useed) * exp2(-32.0);
}

float2 roberts2(in uint idx, in float2 seed = 0.5)
{
    uint2 useed = uint2(seed * exp2(32.0)); 
    uint2 phi = uint2(3242174889u, 2447445413u);
    return float2(phi * idx + useed) * exp2(-32.0);  
}

float3 roberts3(in uint idx, in float3 seed = 0.5)
{
    uint3 useed = uint3(seed * exp2(32.0)); 
    uint3 phi = uint3(776648141u, 1412856951u, 2360945575u);
    return float3(phi * idx + useed) * exp2(-32.0);  
}
#else //DX9 is a jackass, nothing new...
//improved golden ratio sequences v1 (P. Gilcher, 2022)
//PG22 improved golden ratio sequences (https://www.shadertoy.com/view/mts3zN)
//these just use complementary coefficients and produce identical (albeit flipped)
//patterns, and run into numerical problems 2x-3x later than the canonical coefficients
float  roberts1(float idx, float  seed = 0.5) {return frac(seed + idx * 0.38196601125);}
float2 roberts2(float idx, float2 seed = 0.5) {return frac(seed + idx * float2(0.245122333753, 0.430159709002));}
float3 roberts3(float idx, float3 seed = 0.5) {return frac(seed + idx * float3(0.180827486604, 0.328956393296, 0.450299522098));}

#endif //_BITWISE_SUPPORTED

/*=============================================================================
  Sobol (https://diglib.eg.org/items/57f2cdeb-69d9-434e-8cf8-37b63e7e69d9 with my own shenanigans)     
=============================================================================*/

#if _BITWISE_SUPPORTED //can't use it on DX9 (the jackass)

uint P(uint v) //XORs every bit with all the ones below it        
{                                          
    v ^=  v                << 16;
    v ^= (v & 0x00FF00FFu) <<  8;
    v ^= (v & 0x0F0F0F0Fu) <<  4;
    v ^= (v & 0x33333333u) <<  2;
    v ^= (v & 0x55555555u) <<  1;
    return v;
}

uint JPJ(uint v) 
{    
    //reversebits(P(reversebits(v)))                            
    v ^=  v                >> 16;
    v ^= (v & 0xFF00FF00u) >>  8;
    v ^= (v & 0xF0F0F0F0u) >>  4;
    v ^= (v & 0xCCCCCCCCu) >>  2;
    v ^= (v & 0xAAAAAAAAu) >>  1;
    return v;
}

//PG: (v & (0xFFFFFFFFu >> m)) is buggy on OpenGL, replaced with (v << m) >> m
uint JPJ(uint v, int m) 
{   //only scramble the leading bits   
    return (JPJ(v >> (32 - m)) << (32 - m)) | ((v << m) >> m);       
}

uint G(uint x, int m) 
{
    uint v = JPJ(x >> (32 - m));
    v ^=  v >> 1;
    // Inverse of lower LP matrix
    return (v << (32 - m)) | ((x << m) >> m);
}

uint mmdX(uint x, int m) 
{
    uint v = JPJ(x >> (32 - m));
    int padding = (m - 6) >> 1;
    v ^= (v & (0x10u << padding)) >> 1;
    return (v << (32 - m)) | ((x << m) >> m);
}

uint mmdY(uint y, int m) 
{
    uint v = JPJ(y >> (32 - m));
    int padding = (m - 6) >> 1;
    v ^= ((v & (0x30u << padding)) >> 1) ^ ((v & (0x08u << padding)) >> 2);
    return (v << (32 - m)) | ((y << m) >> m);
}

void optimize_lstar(inout uint2 p, int logn)
{
    p.x =   G(p.x, logn);
    p.y = JPJ(p.y, logn);
}

void optimize_distance(inout uint2 p, int logn)
{
    p.x = mmdX(p.x, logn);
    p.y = mmdY(p.y, logn);
}

//laine-karras permutation hash (https://psychopath.io/post/2021_01_30_building_a_better_lk_hash)
uint lk_hash(uint x, uint seed) 
{
    x ^= x * 0x3D20ADEAu;
    x += seed;
    x *= (seed >> 16) | 1u;
    x ^= x * 0x05526C56u;
    x ^= x * 0x53A22864u;
    return x;
}

uint owen_scramble(uint p, uint seed) 
{
    return reversebits(lk_hash(reversebits(p), seed));
}

uint2 sobol_raw(uint i)
{
    uint x = reversebits(i); //J
    uint y = P(x);
    return uint2(x, y);
}

float2 sobol(uint i)
{    
    return sobol_raw(i) * exp2(-32.0);
}

float2 scrambled_sobol(uint i, uint2 seed = uint2(1337u, 1338u))
{
    uint2 p = sobol_raw(i);
    p.x = owen_scramble(p.x, seed.x);
    p.y = owen_scramble(p.y, seed.y); 
    return float2(p) * exp2(-32.0);
}

float2 shuffled_scrambled_sobol(uint i, uint seed)
{
    //reversebits and the end of owen scrambling and the J(x) cancels out
    uint x = lk_hash(reversebits(i), seed); 
    uint y = P(x);

    //no need to use per-pixel unique seeds here, since the shuffling already handles decorrelation
    return float2(owen_scramble(x, 80085u), owen_scramble(y, 420u)) * exp2(-32.0);   
}

#endif //_BITWISE_SUPPORTED

//this bins random numbers into sectors, to cover a 2D domain evenly
//given a known number of samples. For e.g. 4x4 samples it rescales all
//per-sample random numbers to make sure each lands in its own grid cell
//for non-square numbers the distribution is imperfect but still usable

//calculate the coefficients used in the operation
float3 get_stratificator(int n_samples)
{
    float3 stratificator;
    stratificator.xy = rcp(float2(ceil(sqrt(n_samples)), n_samples));
    stratificator.z = stratificator.y / stratificator.x;
    return stratificator;
}

float2 get_stratified_sample(float2 per_sample_rand, float3 stratificator, int i)
{
    float2 stratified_sample = frac(i * stratificator.xy + stratificator.xz * per_sample_rand);
    return stratified_sample;
}

} //namespace