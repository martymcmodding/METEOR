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

    Simple and fast long exposure shader

    Author:         Pascal Gilcher

    More info:      https://martysmods.com
                    https://patreon.com/mcflypg
                    https://github.com/martymcmodding  	

=============================================================================*/

uniform bool TAKE_SHOT <
    ui_label = "Start Capture";
> = false;

uniform float EXPOSURE_TIME <
	ui_type = "drag";
	ui_min = 0.05; ui_max = 50.0;
	ui_label = "Exposure Time [s]";
> = 1.0;

uniform bool SHOW_PROGRESS_BAR <
    ui_label = "Show Progress Bar";
> = true;

uniform bool USE_HDR_CAPTURE <
    ui_label = "HDR Capture";
> = false;

uniform float HDR_WHITEPOINT <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 12.0;
	ui_label = "HDR Log Whitepoint";
    ui_tooltip = "Higher values result in stronger trails caused by bright pixels.";
> = 2.0;

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

#include ".\MartysMods\mmx_global.fxh"

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex; };

texture AccumTex      		{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;  Format = RGBA32F; };
sampler sAccumTex	    	{ Texture = AccumTex; 	};
texture StateTex      	    { Width = 1;   Height = 1;  Format = RG32F;};
sampler sStateTex	        { Texture = StateTex; MipFilter = POINT; MagFilter = POINT; MinFilter = POINT;	};

//#undef _COMPUTE_SUPPORTED

#if _COMPUTE_SUPPORTED
storage stAccumTex	    	{ Texture = AccumTex; 	};
storage stStateTex	    	{ Texture = StateTex; 	};
#endif 

uniform float TIMER < source = "timer"; >;
uniform uint FRAMECOUNT  < source = "framecount"; >;

struct VSOUT
{
	float4 vpos : SV_Position;
    float4 uv   : TEXCOORD0;
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

float3 sdr_to_hdr(float3 c, float w)
{
    float a = 1 + exp2(-w);       
    c = c * sqrt(1e-6 + dot(c, c)); 
    c /= 1.733;
    c = c / (a - c);    
    return c;
}

float3 hdr_to_sdr(float3 c, float w)
{
    float a = 1 + exp2(-w);
    c = a * c * rcp(1 + c);
    c *= 1.733;
    c = c * rsqrt(sqrt(dot(c, c))+0.0001); 
    return c;
}

/*=============================================================================
	Shader Entry Points
=============================================================================*/

#if _COMPUTE_SUPPORTED
void AccumCS(in CSIN i)
{
    [branch]
    if(!TAKE_SHOT)
    {
        [branch]
        if(i.dispatchthreadid.x + i.dispatchthreadid.y == 0)
           tex2Dstore(stStateTex, int2(0, 0), float4(TIMER, FRAMECOUNT % 16777216, 0, 0));//well if you're REALLY unlucky this goes wrong...
        return;
    } 

    [branch]
    if(any(i.dispatchthreadid.xy >= BUFFER_SCREEN_SIZE)) 
        return; 

    float2 state = tex2Dfetch(stStateTex, int2(0, 0)).xy;  
    bool accumulate = ((TIMER - state.x) < EXPOSURE_TIME * 1000.0); //ms to s

    [branch]if(!accumulate) return;

    float weight = saturate(rcp(FRAMECOUNT - state.y + 1e-7));  
    float4 curr  = tex2Dfetch(ColorInput, i.dispatchthreadid.xy);

    [flatten]if(USE_HDR_CAPTURE) curr.rgb = sdr_to_hdr(curr.rgb, exp2(HDR_WHITEPOINT));

     float4 accum = tex2Dfetch(stAccumTex, i.dispatchthreadid.xy);
    accum = lerp(accum, curr, weight);
    tex2Dstore(stAccumTex, i.dispatchthreadid.xy, accum);    
}
#endif

float4 StateTrackVS(in uint id : SV_VertexID) : SV_Position
{    
    return float4(TAKE_SHOT, TAKE_SHOT, 0, 1); //faster than discard because this kills the write in the geometry stage
}

void StateTrackPS(in float4 vpos : SV_Position, out float2 state : SV_Target)
{ 
    state = float2(TIMER, FRAMECOUNT % 16777216); //well if you're REALLY unlucky this goes wrong...
}

VSOUT AccumVS(in uint id : SV_VertexID)
{    
    VSOUT o;
    o.uv.x = id == 2 ? 2.0 : 0.0;
	o.uv.y = id == 1 ? -1.0 : 1.0;    

    float2 state = tex2Dfetch(sStateTex, int2(0, 0), 0).xy;
    bool accumulate = ((TIMER - state.x) * 0.001 < EXPOSURE_TIME) && TAKE_SHOT;
    //should be rcp(1 + diff) but for some reason, the last capture appears as a ghost
    //so this one omits the very first frame but at least works.
    float weight = rcp(FRAMECOUNT - state.y + 1e-6); 

    o.uv.zw = weight;

    o.vpos.xy = accumulate ? o.uv.xy * float2(2, -2) + float2(-1, 1) : 0;
    o.vpos.zw = float2(0, 1);

    return o;
}

void AccumPS(in VSOUT i, out float4 o : SV_Target)
{ 
    float3 col = tex2D(ColorInput, i.uv.xy).rgb;
    if(USE_HDR_CAPTURE) col = sdr_to_hdr(col, exp2(HDR_WHITEPOINT));
    o = float4(col, i.uv.w);    
}

VSOUT MainVS(in uint id : SV_VertexID)
{    
    VSOUT o;
    o.uv.x = id == 2 ? 2.0 : 0.0;
	o.uv.y = id == 1 ? -1.0 : 1.0;  
    float2 state = tex2Dfetch(sStateTex, int2(0, 0)).xy;
    o.vpos.xy = state.x == 0 || !TAKE_SHOT ? 0 : o.uv.xy * float2(2, -2) + float2(-1, 1); //don't produce a blackscreen when someone left the capture open and reloaded shaders
    o.vpos.zw = float2(0, 1);
    return o;
}

void MainPS(in VSOUT i, out float3 o : SV_Target)
{   
    o = tex2D(sAccumTex, i.uv.xy).rgb;
    if(USE_HDR_CAPTURE) o = hdr_to_sdr(o, exp2(HDR_WHITEPOINT));

    [branch]
    if(SHOW_PROGRESS_BAR)
    {
        float progress = saturate((TIMER -  tex2Dfetch(sStateTex, int2(0, 0)).x) * 0.001 / EXPOSURE_TIME);
        float3 window = smoothstep(float3(-0.1, -0.1, -0.01), float3(0.1, -0.1 + progress * 0.2, 0.01), i.uv.xxy - 0.5);

        float bar = all(saturate(window.yz - window.yz * window.yz));
        float bg = all(saturate(window.xz - window.xz * window.xz));

        o = progress < 1.0 ? o * (1 - bg * 0.5) + bar : o;
    }
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_LongExposure
<
    ui_label = "METEOR Long Exposure";
    ui_tooltip =        
        "                           MartysMods - Long Exposure                         \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"

        "Simple long exposure shader. Simply click on 'Start Capture' and the shader will\n"
        "stack the frames over the specified exposure time.                            \n"
        "\n"
        "\n"
        "Visit https://martysmods.com for more information.                            \n"
        "\n"       
        "______________________________________________________________________________";
>
{
#if _COMPUTE_SUPPORTED
    pass { ComputeShader = AccumCS<16, 16>; DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, 16); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, 16); }
#else 
    pass
    {
        VertexShader = StateTrackVS;
        PixelShader  = StateTrackPS;        
        PrimitiveTopology = POINTLIST;
		VertexCount = 1;
        RenderTarget = StateTex;
    }
    pass
    {
        VertexShader = AccumVS;
        PixelShader  = AccumPS;
        RenderTarget = AccumTex;
        BlendEnable = true;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
    }
#endif
    pass
    {
        VertexShader = MainVS;
        PixelShader  = MainPS;
    }
}
