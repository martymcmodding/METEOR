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

namespace Hash 
{

//PG: found using hash prospector, bias 0.10704308166917044
//if you copy it with those exact coefficients, I will know >:)
uint uhash(uint x)
{
    x ^= x >> 16;
    x *= 0x21f0aaad;
    x ^= x >> 15;
    x *= 0xd35a2d97;
    x ^= x >> 16;
    return x;
}

//32
float  uint_to_unorm  (uint  u){return asfloat((u >> 9u) | 0x3F800000u) - 1.0;}
float2 uint2_to_unorm2(uint2 u){return asfloat((u >> 9u) | 0x3F800000u) - 1.0;}
float3 uint3_to_unorm3(uint3 u){return asfloat((u >> 9u) | 0x3F800000u) - 1.0;}
float4 uint4_to_unorm4(uint4 u){return asfloat((u >> 9u) | 0x3F800000u) - 1.0;}
//16|16
float2 uint_to_unorm2(uint u){return asfloat((uint2(u << 7u, u >> 9u)                     & 0x7FFF80u) | 0x3F800000u) - 1.0;}
//11|11|10
float3 uint_to_unorm3(uint u){return asfloat((uint3(u >> 9u,  u << 2u, u << 13u)          & 0x7FF000u) | 0x3F800000u) - 1.0;}
//8|8|8|8
float4 uint_to_unorm4(uint u){return asfloat((uint4(u >> 9u,  u >> 1u, u << 7u, u << 15u) & 0x7F8000u) | 0x3F800000u) - 1.0;}

float  next1D(inout uint rng_state){rng_state = uhash(rng_state);return uint_to_unorm(rng_state);}
float2 next2D(inout uint rng_state){rng_state = uhash(rng_state);return uint_to_unorm2(rng_state);}
float3 next3D(inout uint rng_state){rng_state = uhash(rng_state);return uint_to_unorm3(rng_state);}
float4 next4D(inout uint rng_state){rng_state = uhash(rng_state);return uint_to_unorm4(rng_state);}

void hash_combine(inout uint state, uint value)
{
    state ^= value + 0x9e3779b9 + (state << 6) + (state >> 2);
}

}