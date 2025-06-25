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

    Author:         Pascal Gilcher

    More info:      https://martysmods.com
                    https://patreon.com/mcflypg
                    https://github.com/martymcmodding  	

=============================================================================*/

uniform int CAPTURE_MODE <
	ui_type = "combo";
	ui_items = "Click to start capture\0Capture while holding button\0";
    ui_label = "Capture Mode";
> = 0;
#define CAPTURE_MODE_CLICK  0
#define CAPTURE_MODE_HOLD   1 

uniform float EXPOSURE_TIME <
	ui_type = "drag";
	ui_min = 0.05; ui_max = 50.0;
    ui_units = " Seconds";
	ui_label = "Exposure Time";
    //ui_spacing = 4;
> = 1.0;

#define EXPOSURE_TIME_MS (EXPOSURE_TIME * 1000.0)

uniform float HDR_WHITEPOINT <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 12.0;
	ui_label = "Highlight Intensity";    
    ui_tooltip = "Higher values let bright pixels build up more, resulting in stronger motion trails.\n"
                 "This sets the log2 whitepoint used during inverse tonemapping.";
> = 2.0;

uniform bool CLOSE_GAPS <
    ui_label = "Fake Frame Generation\n";
    ui_tooltip = "Inserting fake frames closes gaps between frames.\n\n"
                 "REQUIRES iMMERSE: LAUNCHPAD";
> = false;

uniform bool SHOW_PROGRESS_BAR <
    ui_label = "Display Progress Animation";
> = true;

uniform bool TRIGGER <
    ui_label = "Capture";
    ui_type = "button";
    ui_spacing = 10;
> = false;

uniform bool CLEAR <
    ui_label = "Reset";
    ui_type = "button";
> = false;

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

#include ".\MartysMods\mmx_global.fxh"
#include ".\MartysMods\mmx_deferred.fxh"

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex; };

texture METEORLongExposureCtx       { Format = RGBA32F;};
sampler sMETEORLongExposureCtx	    { Texture = METEORLongExposureCtx; MipFilter = POINT; MagFilter = POINT; MinFilter = POINT; };
texture METEORLongExposureCtxTmp    { Format = RGBA32F;};
sampler sMETEORLongExposureCtxTmp	{ Texture = METEORLongExposureCtxTmp; MipFilter = POINT; MagFilter = POINT; MinFilter = POINT; };

texture METEORLongExposureCache    { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sMETEORLongExposureCache	{ Texture = METEORLongExposureCache; };

//since the flow vectors can fuck up, I capture both interpolated and non-interpolated buffers
texture METEORLongExposureAccumRegular         { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA32F; };
sampler sMETEORLongExposureAccumRegular	       { Texture = METEORLongExposureAccumRegular; };
texture METEORLongExposureAccumInterpolated    { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA32F; };
sampler sMETEORLongExposureAccumInterpolated   { Texture = METEORLongExposureAccumInterpolated; };

uniform float TIMER      < source = "timer"; >;
uniform uint  FRAMECOUNT < source = "framecount"; >;
uniform float FRAMETIME  < source = "frametime"; >;
uniform int ACTIVE_VAR_IDX < source = "overlay_active"; >;

struct VSOUT
{
	float4 vpos : SV_Position;
    float2 uv   : TEXCOORD0;
    float weight : TEXCOORD1;
};

#if _COMPUTE_SUPPORTED

struct CSIN 
{
    uint3 groupthreadid     : SV_GroupThreadID;         
    uint3 groupid           : SV_GroupID;            
    uint3 dispatchthreadid  : SV_DispatchThreadID;     
    uint threadid           : SV_GroupIndex;
};

storage stMETEORLongExposureCtx	{ Texture = METEORLongExposureCtx;  };

#endif


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
	Context 
=============================================================================*/

struct CaptureContext 
{
    float t_elapsed;
    bool state;
    bool display;
};

float get_progress(CaptureContext ctx)
{
    return saturate(ctx.t_elapsed / EXPOSURE_TIME_MS);
}

void advance_context(inout CaptureContext ctx)
{
    [branch]
    if(ctx.state) //state _was_ on current frame and we have accumulated the frame
    {
        ctx.t_elapsed += FRAMETIME;
    }

    switch(CAPTURE_MODE)
    {
        case CAPTURE_MODE_CLICK:
        {
            [branch]
            if(ctx.t_elapsed > EXPOSURE_TIME_MS) //exposure time is exceeded, stop exposing
            {
                ctx.state = false; //disable capturing
            }
            [branch]
            if(TRIGGER)
            {
                ctx.state = true; 
                ctx.display = true; 
                ctx.t_elapsed = 0; 
                
            }
            [branch]
            if(CLEAR)
            {
                ctx.state = false;
                ctx.display = false; 
            }
            break;
        }
        case CAPTURE_MODE_HOLD:
        {
            [branch]
            if(ACTIVE_VAR_IDX == 6)
            {
                ctx.state = true;
                ctx.display = true;  
            }
            else 
            {
                ctx.state = false; 
            }

            [branch]
            if(CLEAR)
            {
                ctx.display = false; 
                ctx.t_elapsed = 0; 
            }
            break;
        }
    }   
}

CaptureContext get_capture_context()
{
    float3 t = tex2Dfetch(sMETEORLongExposureCtx, int2(0, 0)).xyz;
    CaptureContext ctx;
    ctx.t_elapsed = t.x;
    ctx.state = t.y > 0.5;
    ctx.display = t.z > 0.5;   
    return ctx;
}

#if _COMPUTE_SUPPORTED

CaptureContext get_capture_context_rw()
{
    float3 t = tex2Dfetch(stMETEORLongExposureCtx, int2(0, 0)).xyz;
    CaptureContext ctx;
    ctx.t_elapsed = t.x;
    ctx.state = t.y > 0.5;
    ctx.display = t.z > 0.5;
    return ctx;
}

void AdvanceContextCS(in CSIN i)
{
    CaptureContext ctx = get_capture_context_rw();
    advance_context(ctx);
    tex2Dstore(stMETEORLongExposureCtx, int2(0, 0), float4(ctx.t_elapsed, ctx.state, ctx.display, 1));
}

#else  //_COMPUTE_SUPPORTED

float4 AdvanceContextVS(in uint id : SV_VertexID) : SV_Position
{    
    return float4(0.0.xxx, 1);
}

float4 AdvanceContextPS(in float4 vpos : SV_Position) : SV_Target
{  
   CaptureContext ctx = get_capture_context();
   advance_context(ctx);
   return float4(ctx.t_elapsed, ctx.state, ctx.display, 1);
}

float4 UpdatePrevContextPS(in float4 vpos : SV_Position) : SV_Target
{
    return tex2Dfetch(sMETEORLongExposureCtxTmp, vpos.xy);
}

#endif //_COMPUTE_SUPPORTED

/*=============================================================================
	Accumulate - runs before caching.
=============================================================================*/

VSOUT AccumVS(in uint id : SV_VertexID)
{   
    VSOUT o;  
    FullscreenTriangleVS(id, o.vpos, o.uv);

    CaptureContext ctx = get_capture_context();

    [branch]
    if(!ctx.state)
    {
        o.vpos.xy = o.weight = 0;        
    }
    else 
    {
        float delta_t = FRAMETIME + 1e-10;        
        float next_elapsed = ctx.t_elapsed + delta_t;
        o.weight = saturate(delta_t / next_elapsed);
    }

    return o;
}

void AccumPS(in VSOUT i, out PSOUT2 o)
{   
    //regular accumulated frame 
    o.t0 = float4(tex2Dfetch(sMETEORLongExposureCache, int2(i.vpos.xy)).rgb, i.weight);

    //frame w/ interpolation
    o.t1 = 0;

    float2 motion = Deferred::get_motion(i.uv); 
    int n = min(64, int(1 + length(motion * BUFFER_SCREEN_SIZE)));

    [loop]
    for(int j = 0; j < n; j++)
        o.t1 += float4(tex2Dlod(sMETEORLongExposureCache, i.uv + motion * float(j) / n, 0).rgb, 1);

    o.t1.rgb /= o.t1.w;
    o.t1.w = i.weight;
}

/*=============================================================================
	Caching - we need FRAMETIME to blend, which we only have for prev frame
=============================================================================*/

VSOUT CacheVS(in uint id : SV_VertexID)
{   
    VSOUT o;  
    FullscreenTriangleVS(id, o.vpos, o.uv);  
    o.weight = 0; //unused
    return o;
}

void CachePS(in VSOUT i, out float3 o : SV_Target)
{ 
    o = tex2D(ColorInput, i.uv).rgb;  
    o = sdr_to_hdr(o, exp2(HDR_WHITEPOINT));    
}

/*=============================================================================
	Output
=============================================================================*/

VSOUT OutVS(in uint id : SV_VertexID)
{   
    VSOUT o;  
    FullscreenTriangleVS(id, o.vpos, o.uv);

    [branch]
    if(!get_capture_context().display)
    {
        o.vpos.xy = 0;
    }
    return o;
}

void OutPS(in VSOUT i, out float3 o : SV_Target)
{
    o = 0;

    [branch]
    if(CLOSE_GAPS)
    {
        o = tex2Dlod(sMETEORLongExposureAccumInterpolated, i.uv, 0).rgb;
    }
    else 
    {
        o = tex2Dlod(sMETEORLongExposureAccumRegular, i.uv, 0).rgb;
    }   

    o = hdr_to_sdr(o, exp2(HDR_WHITEPOINT));     

    [flatten]
    if(SHOW_PROGRESS_BAR)
    {
        CaptureContext ctx = get_capture_context();

        float3 ca = float3(14,145,248) / 255.0;
        float3 cb = float3(228,47,226) / 255.0;

        float2 duv = i.uv * 2.0 - 1.0;
        duv *= BUFFER_ASPECT_RATIO.yx; 
        float t = ctx.t_elapsed * 0.001;

        [flatten] //gradients...
        if(CAPTURE_MODE == CAPTURE_MODE_HOLD)
        {            
            float scale = 0.2 * t / (0.04 + t);
            [unroll]
            for(int j = 0; j < 10; j++)
            {
                float2 p; sincos(j / 10.0 * 6.283 - scale * 6.283, p.x, p.y);
                float r = frac(-t * 0.8 - j / 10.0);
                float R = length(duv + p * 0.7 * scale) - scale * 0.1 * r;
                float mask = smoothstep(2, 0, R / fwidth(R));
                o = lerp(o, sqrt(lerp(ca * ca, cb * cb, r)), mask);   
            }
        }   
        else 
        {   
            float progress = get_progress(ctx);

            float2 duv = i.uv * 2.0 - 1.0;
            duv *= BUFFER_ASPECT_RATIO.yx;
            float ang = atan2(duv.x, duv.y);
            float ramp = saturate(1 - t * 2.0 / min(1.0, EXPOSURE_TIME));
            ramp *= ramp * ramp;
            ramp = 1-ramp;

            float norm_ang = saturate(ang / TAU + 0.5);
            norm_ang = frac(norm_ang - ramp);
           
            float r = length(duv) - 0.15 * ramp;

            float3 ca = float3(14,145,248) / 255.0;
            float3 cb = float3(228,47,226) / 255.0;

            float3 progresscol = sqrt(lerp(ca * ca, cb * cb, norm_ang));
            o = progress < 1.0 ? lerp(o, step(norm_ang, progress) * progresscol, smoothstep(2.0, 0.0, r / fwidth(r))) : o;
        }
    }     
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_LongExposure
<
    ui_label = "METEOR: Long Exposure";
    ui_tooltip =        
        "                           MartysMods - Long Exposure                         \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"

        "Advanced long exposure shader with frametime normalizing and frame generation.\n"
        "\n"
        "\n"
        "Visit https://martysmods.com for more information.                            \n"
        "\n"       
        "______________________________________________________________________________";
>
{
    pass //captures as long as state == true
    {
        VertexShader = AccumVS;
        PixelShader  = AccumPS;
        RenderTarget0 = METEORLongExposureAccumRegular;
        BlendEnable0 = true;
        SrcBlend0 = SRCALPHA;
        DestBlend0 = INVSRCALPHA;
        RenderTarget1 = METEORLongExposureAccumInterpolated;
        BlendEnable1 = true;
        SrcBlend1 = SRCALPHA;
        DestBlend1 = INVSRCALPHA;
    }
    pass //caches always
    {
        VertexShader = CacheVS;
        PixelShader  = CachePS;
        RenderTarget = METEORLongExposureCache;        
    }
    pass
    {
        VertexShader = OutVS;
        PixelShader  = OutPS;
    }
    //now increment as long as state == true.
#if _COMPUTE_SUPPORTED
    pass 
    { 
        ComputeShader = AdvanceContextCS<1, 1>;
        DispatchSizeX = 1; 
        DispatchSizeY = 1;
    }
#else //_COMPUTE_SUPPORTED
    pass 
    {
        VertexShader = AdvanceContextVS;
        PixelShader  = AdvanceContextPS;
        RenderTarget = METEORLongExposureCtxTmp;
        PrimitiveTopology = POINTLIST;
		VertexCount = 1;
    }
    pass 
    {
        VertexShader = AdvanceContextVS;
        PixelShader  = UpdatePrevContextPS;
        RenderTarget = METEORLongExposureCtx;
        PrimitiveTopology = POINTLIST;
		VertexCount = 1;
    } 
#endif //_COMPUTE_SUPPORTED
}

