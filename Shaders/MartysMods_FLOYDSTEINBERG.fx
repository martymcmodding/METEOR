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

    Floyd-Steinberg dithering
    Welcome to jackass

    It's actually not that slow lmao

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

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

//do NOT change anything here. "hurr durr I changed this and now it works"
//you ARE breaking things down the line, if the shader does not work without changes
//here, it's by design.

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex;  };

#include "MartysMods\mmx_global.fxh"

struct VSOUT
{
	float4                  vpos        : SV_Position;
    float2                  uv          : TEXCOORD0;
};

texture ColorMapU { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = R32I; };
sampler<int> sColorMapU { Texture = ColorMapU; };
storage<int> stColorMapU { Texture = ColorMapU; };

texture ColorMapOut { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = R32I; };
sampler<int> sColorMapOut { Texture = ColorMapOut; };
storage<int> stColorMapOut { Texture = ColorMapOut; };

struct CSIN 
{
    uint3 groupthreadid     : SV_GroupThreadID;         //XYZ idx of thread inside group
    uint3 groupid           : SV_GroupID;               //XYZ idx of group inside dispatch
    uint3 dispatchthreadid  : SV_DispatchThreadID;      //XYZ idx of thread inside dispatch
    uint threadid           : SV_GroupIndex;            //flattened idx of thread inside group
};

/*=============================================================================
	Functions
=============================================================================*/

float2 pixel_idx_to_uv(uint2 pos, float2 texture_size)
{
    float2 inv_texture_size = rcp(texture_size);
    return pos * inv_texture_size + 0.5 * inv_texture_size;
}

bool check_boundaries(uint2 pos, uint2 dest_size)
{
    return all(pos < dest_size) && all(pos >= uint2(0, 0));
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

void ToGreyCS(in CSIN i)
{
    if(!check_boundaries(i.dispatchthreadid.xy, BUFFER_SCREEN_SIZE))    
        return;
    float3 c = tex2Dlod(ColorInput, pixel_idx_to_uv(i.dispatchthreadid.xy, BUFFER_SCREEN_SIZE), 0).rgb;
    c = c*0.283799*((2.52405+c)*c);   
    float greyv = dot(float3(0.2125, 0.7154, 0.0721), c);

    int igrey = int(greyv  * 255.99);
    tex2Dstore(stColorMapU, i.dispatchthreadid.xy, igrey);
}

#define NUMTHREADS 1024
groupshared int4 diffused_errors[NUMTHREADS];


groupshared int diffused_errors_packed[NUMTHREADS];

int4 unpack_errors(int _packed)
{
    int4 unpacked;
    unpacked.x = (_packed >> 24) & 0xFF; //first byte
    unpacked.y = (_packed >> 16) & 0xFF; //second byte
    unpacked.z = (_packed >> 8) & 0xFF;  //third byte
    unpacked.w = _packed & 0xFF;         //fourth byte
    return unpacked - 127;
}

int pack_errors(int4 errors)
{
    //pack the four error values into a single int
    return (errors.x + 127) << 24 | (errors.y + 127) << 16 | (errors.z + 127) << 8 | (errors.w + 127);
}

void FloydSteinbergCS(in CSIN i)
{   
    [loop]
    for(int stripe_id = 0; stripe_id <= BUFFER_HEIGHT / NUMTHREADS; stripe_id++)
    {
        //diffused_errors[i.threadid] = 0;
        diffused_errors_packed[i.threadid] = 0x7F7F7F7F;//
        barrier();

        int2 launch_pos;
        launch_pos.y = stripe_id * NUMTHREADS + i.threadid;
        launch_pos.x = -2 * i.threadid;  //offset the starting position so each row has the proper row offset     

        [loop]
        for(int j = 0; j < BUFFER_WIDTH + NUMTHREADS * 2; j++)
        {
            int error = 0;
            bool in_working_area = launch_pos.x >= 0 && launch_pos.y < BUFFER_HEIGHT;

            [branch]
            if(in_working_area)
            {
                int4 next_errors = unpack_errors(diffused_errors_packed[i.threadid]);//diffused_errors[i.threadid];
                int grey = tex2Dfetch(stColorMapU, launch_pos.xy).x + next_errors.x;
                int rounded = grey > 127 ? 255 : 0;
                error = grey - rounded;                         

                tex2Dstore(stColorMapOut, launch_pos.xy, rounded); //faster to store on a separate buffer                
                //diffused_errors[i.threadid] = int4(next_errors.y + (error * 7) / 16, next_errors.zw, 0); //cycle the diffusion errors ahead
                diffused_errors_packed[i.threadid] = pack_errors(int4(next_errors.y + (error * 7) / 16, next_errors.zw, 0)); 
            }

            barrier();

            [branch]
            if(in_working_area)
            {               
                [branch]
                if(i.threadid == (NUMTHREADS - 1))
                {                    
                    atomicAdd(stColorMapU, launch_pos.xy + int2(-1, 1), (error * 3) / 16);
                    atomicAdd(stColorMapU, launch_pos.xy + int2(0, 1),  (error * 5) / 16);
                    atomicAdd(stColorMapU, launch_pos.xy + int2(1, 1),  (error * 1) / 16);
                }
                else 
                {
                    int addpacked = ((error * 3) / 16)  << 24 | (((error * 5) / 16) << 16) | (((error * 1) / 16) << 8) | 0;
                    atomicAdd(diffused_errors_packed[i.threadid + 1], addpacked);              

                    /*atomicAdd(diffused_errors[i.threadid + 1].x, (error * 3) / 16);
                    atomicAdd(diffused_errors[i.threadid + 1].y, (error * 5) / 16);
                    atomicAdd(diffused_errors[i.threadid + 1].z, (error * 1) / 16); */   
                }
                
            }
            barrier();
            launch_pos.x++;
        }
    }  
}

void MainPS(in VSOUT i, out float4 o : SV_Target0)
{
   o = tex2D(sColorMapOut, i.uv).x / 255.0;
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_FloydSteinbergDither
{    
    pass
	{
		ComputeShader = ToGreyCS<32, 32>;
        DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, 32); 
        DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, 32);
	} 
    pass
	{
		ComputeShader = FloydSteinbergCS<1, NUMTHREADS>;
        DispatchSizeX = 1; 
        DispatchSizeY = 1;
	} 
    pass
	{
		VertexShader = MainVS;
		PixelShader  = MainPS;  
	}        
}