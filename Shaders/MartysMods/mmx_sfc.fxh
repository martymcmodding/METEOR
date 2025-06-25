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

namespace SFC 
{

/*=============================================================================
	Morton Z-Order
=============================================================================*/

#if _BITWISE_SUPPORTED 

//N unused but so I have the same signature as the DX9 version
//except when I don't want to supply it in exclusively non-DX9 shaders
uint2 morton_i_to_xy(uint i, uint N = 0) 
{    
    uint2 p = uint2(i, i >> 1);
    p &= 0x55555555;   
    p = (p ^ (p >> 1)) & 0x33333333; 
    p = (p ^ (p >> 2)) & 0x0F0F0F0F; 
    p = (p ^ (p >> 4)) & 0x00FF00FF; 
    p = (p ^ (p >> 8)) & 0x0000FFFF;
    return p;
}

uint morton_xy_to_i(uint2 p)
{    
    p = (p | (p << 8)) & 0x00FF00FF;
    p = (p | (p << 4)) & 0x0F0F0F0F;
    p = (p | (p << 2)) & 0x33333333;
    p = (p | (p << 1)) & 0x55555555;
    return p.x | (p.y << 1);
}

#else 

uint2 morton_i_to_xy(uint i, uint N)
{
    uint2 p = 0;   
    for(int bit = 0; bit < 2*int(log2(sqrt(float(N)))); bit += 2)
    {
        uint2 state = floor(i * exp2(-float2(bit, bit + 1)));        
        p += step(0.25, frac(state * 0.5)) * exp2(bit / 2);
    }    
    return p;
}

#endif

/*=============================================================================
	Hilbert
=============================================================================*/

#if _BITWISE_SUPPORTED 
//PG25: my own hand-rolled one
uint2 hilbert_i_to_xy(uint i, uint N)
{
    uint2 p = 0; uint2 r;
    for(uint s = 1u; s < N; s += s)
    {
        r.y = i;  i >>= 1;
        r.y ^= i;
        r.x = i;  i >>= 1;       
        r &= 1u; 
        p = r.y ? p : (r.x == 1u ? (s - 1u - p.yx) : p.yx);            
        p += s * r;
    }
    return p;
}
#endif

/*=============================================================================
	H-Curve - my own algorithms
=============================================================================*/

#if _BITWISE_SUPPORTED 
//https://www.shadertoy.com/view/mtjSWc 
uint2 h_curve_i_to_xy(uint i, uint N)
{
    uint2 p = 0; 
        
    while((N>>=2) >= 16u)
    {    
        uint2 q;
        q.x = i / N;
        q.y = q.x >> 1; 
        p = 2u * p + (uint2(q.y, q.x ^ q.y) & 1u);
        i += ((q.x * 2u + 5u) & 7u) * (N >> 3);
    }  

    p = p * 4u + ((uint2(0xAFFA5005, 0x41BEBE41) >> (2u * i)) & 3u);
    return p;    
}

//N: amount of digits alone one axis, i.e. 16 for 16x16.
uint h_curve_xy_to_i(uint2 p, uint N)
{
    uint i = (p.x&2u)<<2u|((p.x^p.y)&2u)<<1u|(p.y^(~p.x<<1u))&2u|(p.x^p.y)&1u;

    p *= 4u; 
    uint2 t;        
    for(uint k = 16u; k < N*N; k *= 4u)
    {  
        t = p & k;            
        t = 2u * t + t.x ^ t.y;        
        i = ((i + ((3u * k) >> 3u) + (t.y >> 2u)) & (k - 1u)) | t.x;  
        p *= 2u; 
    }
    return i;
}

#endif

}