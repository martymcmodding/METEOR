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

    SceneWeaver

    Author:         Pascal Gilcher

    More info:      https://martysmods.com
                    https://patreon.com/mcflypg
                    https://github.com/martymcmodding  	

=============================================================================*/

#define SECTION_HOTSAMPLE "Hotsampling"
#define SECTION_LETTERBOX "Letterbox"
#define SECTION_CANVAS    "Canvas"

uniform int UISPACING0 <ui_type = "radio";ui_label = "\n\n";ui_text = "";>;


uniform int UIHELP_HOTSAMPLE <
	ui_type = "radio";
	ui_label = " ";	
	ui_text = "During hotsampling, the lower part of the game window extends beyond\n"
              "the screen edges. This effect rescales the image to fit the screen.\n"
              "Automatically disabled in screenshots, so you may leave it enabled.\n\n"
              "Enable METEOR: SceneWeaver (Hotsampling) to use this feature\n"
              "and move the technique to the bottom of your stack, but before Canvas.";
	ui_category = SECTION_HOTSAMPLE;
>;
uniform int HOTSAMPLING_TARGET_RESOLUTION_X <
	ui_type = "drag";
	ui_min = 480; ui_max = 8192;
    ui_units = "px";
	ui_label = "Your screen width";
    ui_tooltip = "The shader will resize the viewport of the game to this resolution.\nThis will make the preview always fill the screen, independent of the hotsampling factor.";
    ui_category = SECTION_HOTSAMPLE;    
> = 3440;

uniform int UISPACING1 <ui_type = "radio";ui_label = "\n\n\n";ui_text = "";ui_category = SECTION_HOTSAMPLE;>;

uniform int UIHELP_LETTERBOX <
	ui_type = "radio";
	ui_label = " ";	
	ui_text = "Adds cinematic black bars to the image, to assist you when framing a shot.\n"
              "Enable METEOR: SceneWeaver (Letterbox) to use this feature.";
	ui_category = SECTION_LETTERBOX;
>;

uniform int LETTERBOX_PRESET <
	ui_type = "combo";
    ui_label = "Preset";
	ui_items = " Custom \0 1:1 \0 5:4 \0 4:3 \0 3:2 \0 16:10 \0 Golden Ratio \0 16:9 \0 1.85:1 \0 2:1 \0 2.35:1 \0 ";
    ui_tooltip = "Select a desired aspect ratio for the letterbox or create your own.";
    ui_category = SECTION_LETTERBOX;
> = 0;

uniform int2 LETTERBOX_CUSTOMRATIO <
	ui_type = "slider";
    ui_min = 1;
    ui_max = 20;
    ui_label = "Custom Ratio";
    ui_tooltip = "Set the letterbox preset to Custom and pick your own aspect ratio.";
    ui_category = SECTION_LETTERBOX;
> = int2(1, 1);

uniform int UISPACING2 <ui_type = "radio";ui_label = "\n\n\n";ui_text = "";ui_category = SECTION_LETTERBOX;>;


uniform int UIHELP_CANVAS <
	ui_type = "radio";
	ui_label = " ";	
	ui_text = "This feature masks the cinematic black bars with a more neutral canvas\n"
              "color and offers various tools to assist you when framing a screenshot.\n" 
              "Automatically disabled in screenshots,so only the black bars remain.\n\n"      
              "Enable METEOR: SceneWeaver (Canvas) to use this feature\n"
              "and move the technique to the very bottom of your stack.";
	ui_category = SECTION_CANVAS;
>;

uniform float CANVAS_ZOOM <
    ui_type = "drag";
    ui_label = "Zoom Out";
    ui_min = 0.0;
    ui_max = 100.0;
    ui_step = 1.0;
    ui_units = "%%";
    ui_tooltip = "Viewing the image from a distance can help you spot issues in the composition.";
    ui_category = SECTION_CANVAS;
> = 0.0;

uniform int CANVAS_ROTATE <
	ui_type = "slider";
    ui_min = -1;
    ui_max = 1;
    ui_label = "Rotation";  
    ui_tooltip = "Hotsampling a portrait sideways results in fewer cropped pixels but requires\n"
                 "turning your head all the time. This feature saves your neck and your time."; 
    ui_category = SECTION_CANVAS;
> = 0;

uniform float CANVAS_BG <
    ui_type = "drag";
    ui_label = "Canvas Brightness";
    ui_min = 0.0;
    ui_max = 100.0;
    ui_step = 1.0;
    ui_units = "%%";
    ui_category = SECTION_CANVAS;
    ui_tooltip = "A more neutral grey background color makes judging the overall exposure of the\n"
                 "shot a lot easier than a black or white background.";
> = 40.0;

uniform int CANVAS_GRID <
	ui_type = "combo";
    ui_label = "Grid";
	ui_items = " None \0 Rule of Thirds \0 Golden Spiral (Top Left) \0 Golden Spiral (Top Right) \0 Golden Spiral (Bottom Left) \0 Golden Spiral (Bottom Right) \0 Golden Spiral (Top Left Alt) \0 Golden Spiral (Top Right Alt) \0 Golden Spiral (Bottom Left Alt) \0 Golden Spiral (Bottom Right Alt) \0 ";
    ui_tooltip = "Select an overlay grid to help you with the composition of your shot.";
    ui_category = SECTION_CANVAS;
> = 0;

uniform float CANVAS_RULEOFTHIRDS_ALPHA <
    ui_type = "drag";
    ui_label = "Grid Opacity";
    ui_min = 0.0;
    ui_max = 100.0;
    ui_step = 1.0;
    ui_units = "%%";
    ui_category = SECTION_CANVAS;    
> = 30.0;
/*
uniform float4 tempF1 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);
uniform float4 tempF2 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);
uniform float4 tempF3 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);
*/
/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

#include ".\MartysMods\mmx_global.fxh"
#include ".\MartysMods\mmx_math.fxh"

//uniform bool OVERLAY_OPEN < source = "overlay_open"; >;

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex; };

texture2D HotsampleStateTex	 {Format = R8;};
sampler2D sHotsampleStateTex {Texture = HotsampleStateTex;};

#ifndef PHI 
 #define PHI 1.61803398874989484820459
#endif

#define CANVAS_RULEOFTHIRDS 1 
#define CANVAS_GS_TL        2
#define CANVAS_GS_TR        3
#define CANVAS_GS_BL        4
#define CANVAS_GS_BR        5
#define CANVAS_GS_TL_ALT    6
#define CANVAS_GS_TR_ALT    7
#define CANVAS_GS_BL_ALT    8
#define CANVAS_GS_BR_ALT    9


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

float lanczos2( float x )
{  
    //normalized sinc can be approximated with prod[i=1->N] 1 - x²/i²
    //and since lanczos2 uses 2 times sinc, once with half the phase, most of the terms
    //occur twice, so they can be squared at the end.

    //this is visually indistinguishable from real lanczos, meanwhile 33% faster
    float t = saturate(x * x * 0.25);//mul, mul_sat
    float res = 1 - 4.0/9.0 * t;//mad
    res = res - res * t;//mad
    res *= res;//mul
    res = res - res * t; //mad
    res *= 1 - 4 * t;//mad, mul
    return res;
    //const float tau = 2.0;
    //return abs(x) > 2.0 ? 0.0 : sinc(x / tau) * sinc(x);
}

float2 rotate(float2 v, float ang)
{
    float2 sc; sincos(radians(ang), sc.x, sc.y);
    float2x2 rot = float2x2(sc.y, -sc.x, sc.x, sc.y);
    return mul(v, rot);
}

float get_target_aspect(uint idx)
{
    float aspects[11] = {float(LETTERBOX_CUSTOMRATIO.x) / float(LETTERBOX_CUSTOMRATIO.y), 
                        1, 
                        5.0/4.0, 
                        4.0/3.0, 
                        3.0/2.0,
                        16.0/10.0,
                        PHI, 
                        16.0/9.0, 
                        1.85, 
                        2.0, 
                        2.35};
    return aspects[idx];
}

float2 transform(float2 uv)
{
    float dest  = get_target_aspect(LETTERBOX_PRESET);
    float curr  = BUFFER_ASPECT_RATIO.y;    

    float4 scalemad;
    scalemad.xy = curr > dest ? float2(curr / dest, 1) : float2(1, dest / curr);
    scalemad.zw = 0.5 - 0.5 * scalemad.xy;
    return uv * scalemad.xy + scalemad.zw; 
}

float2 transform_inverse(float2 uv)
{
    float dest  = get_target_aspect(LETTERBOX_PRESET);
    float curr  = BUFFER_ASPECT_RATIO.y;   

    float4 scalemad;
    scalemad.xy = curr < dest ? float2(1, curr * curr) : float2(dest * rcp(curr), dest * curr) * max(1, rcp(dest * curr));
    scalemad.zw = 0.5 - 0.5 * scalemad.xy;
    return uv * scalemad.xy + scalemad.zw; 
}

float sdf_goldenspiral(float2 p)
{
    const float a = 0.8541019;//1 - 1/phi^4
    const float b = 0.3063489;//ln(phi)/(pi/2)
    
    float r = length(p);
    float t = -atan2(p.y, p.x); 
    
    float n = (log(r / a) / b - t) / TAU;    
    float2 d = a * exp(b * (t + TAU * floor(n + float2(1, 0)))) - r; 
    
    return minc(abs(d));
}

/*=============================================================================
	Shader Entry Points - Hotsampling
=============================================================================*/

VSOUT MainVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv.xy); o.uv.zw = o.uv.xy;
    return o;
}

void MainPS(in VSOUT i, out float4 o : SV_Target)
{   
    int2 dst_texel = int2(i.vpos.xy);
    float scaling = BUFFER_WIDTH / float(min(BUFFER_WIDTH, HOTSAMPLING_TARGET_RESOLUTION_X));
    if(any(i.uv.xy * scaling >= 1.0))
    {
        o = 0;
        return;
    }

    o = 0;

    int2 kernelsize = ceil(scaling*2.0);
    kernelsize = min(kernelsize, 10);
    float2 src_texel_center = floor((dst_texel + 0.5) * scaling);
    float2 src_texel;
    float2 otdtc;
    float2 w;

    [loop]
    for(int y = -kernelsize.y; y < kernelsize.y; y++)
    {
        src_texel.y = src_texel_center.y + y;
        otdtc.y = src_texel.y / scaling - dst_texel.y;
        w.y = lanczos2(otdtc.y);

        [loop]
        for(int x = -kernelsize.x; x < kernelsize.x; x++)
        {
            src_texel.x = src_texel_center.x + x;
            otdtc.x = src_texel.x / scaling - dst_texel.x;
            w.x = lanczos2(otdtc.x);

            float3 t = tex2Dfetch(ColorInput, src_texel).rgb;
            o += float4(t * t, 1) * w.x * w.y;
        } 
    }        

    o.rgb /= o.w;
    o = sqrt(saturate(o));
}

float4 HotsamplingStateVS(in uint id : SV_VertexID) : SV_Position {return float4(0,0,0,1);}
void SetHotsamplingStatePS(in float4 vpos : SV_Position, out float o : SV_Target0){o = 1;}
void ResetHotsamplingStatePS(in float4 vpos : SV_Position, out float o : SV_Target0){o = 0;}
bool is_hotsampling_enabled(){return tex2Dfetch(sHotsampleStateTex, int2(0,0)).r > 0.5;}

/*=============================================================================
	Shader Entry Points - Letterbox/Canvas
=============================================================================*/

VSOUT LetterboxVS(in uint id : SV_VertexID)
{    
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv.xy); o.uv.zw = o.uv.xy;
    o.uv.xy = transform(o.uv.xy);  
    return o;
}

void LetterboxPS(in VSOUT i, out float4 o : SV_Target)
{
    if(Math::inside_screen(i.uv.xy))
        discard;
    o = 0;
}

VSOUT CanvasVS(in uint id : SV_VertexID)
{    
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv.xy);

    if(CANVAS_ROTATE)
    {
        o.uv = rotate(o.uv.xy - 0.5, CANVAS_ROTATE * 90.0).xyxy + 0.5;
        o.uv.xy = transform_inverse(o.uv.xy);
    }   

    o.uv.zw = transform(o.uv.xy);  
    o.uv = (o.uv - 0.5) * exp2(CANVAS_ZOOM * 0.01) + 0.5;

    if(is_hotsampling_enabled())
    {
        float scaling = BUFFER_WIDTH / float(min(BUFFER_WIDTH, HOTSAMPLING_TARGET_RESOLUTION_X));      
        o.vpos.xy += float2(1, -1);
        o.vpos.xy /= scaling;
        o.vpos.xy -= float2(1, -1);
        o.uv.xy /= scaling;
    }
    
    // if(CANVAS_OVERLAY_TOG && !OVERLAY_OPEN)
    //    o.vpos = 0;
    return o;
}

void CanvasPS(in VSOUT i, out float3 o : SV_Target)
{
    o = tex2Dlod(ColorInput, i.uv.xyyy).rgb;    
    float scaling = BUFFER_WIDTH / float(min(BUFFER_WIDTH, HOTSAMPLING_TARGET_RESOLUTION_X));
    if(is_hotsampling_enabled() && any(i.vpos.xy >= BUFFER_SCREEN_SIZE / scaling))
    {
        discard;
    }
    
    if(CANVAS_GRID == CANVAS_RULEOFTHIRDS)
    {
        float4 griduv   = (i.uv.zwzw - float2(1,2).xxyy / 3.0);
        float2 aa       = float2(length(fwidth(griduv.xy)), length(fwidth(griduv.zw)));
        float4 gridline = smoothstep(aa.xxyy, 0, abs(griduv));

        o = lerp(o, dot(o, 0.3333) < 0.5, saturate(dot(gridline, 1)) * CANVAS_RULEOFTHIRDS_ALPHA * 0.01);
    }
    else if(CANVAS_GRID >= CANVAS_GS_TL && CANVAS_GRID <= CANVAS_GS_BR_ALT)
    {
        float2 gruv = i.uv.zw * 2.0 - 1.0;

        switch(CANVAS_GRID)
        {            
            case CANVAS_GS_TL: gruv = float2(-gruv.x, -gruv.y); break;
            case CANVAS_GS_TR: gruv = float2( gruv.x, -gruv.y); break;           
            case CANVAS_GS_BL: gruv = float2(-gruv.x,  gruv.y); break;
            case CANVAS_GS_BR: gruv = float2( gruv.x,  gruv.y); break;
            case CANVAS_GS_TL_ALT: gruv = float2(-gruv.y, -gruv.x); break;
            case CANVAS_GS_TR_ALT: gruv = float2(-gruv.y,  gruv.x); break;           
            case CANVAS_GS_BL_ALT: gruv = float2( gruv.y, -gruv.x); break;
            case CANVAS_GS_BR_ALT: gruv = float2( gruv.y,  gruv.x); break;         
        }

        gruv -= rsqrt(5.0);
        gruv.x *= PHI;

        float sdf = sdf_goldenspiral(gruv);
        float dx = max(sdf_goldenspiral(gruv + ddx(gruv)), sdf_goldenspiral(gruv - ddx(gruv))) - sdf;
        float dy = max(sdf_goldenspiral(gruv + ddy(gruv)), sdf_goldenspiral(gruv - ddy(gruv))) - sdf;
        sdf *= rsqrt(dx * dx + dy * dy);

        sdf = smoothstep(sqrt(2), 0, sdf);
        o = lerp(o, dot(o, 0.3333) < 0.5, sdf * CANVAS_RULEOFTHIRDS_ALPHA * 0.01);
    }

    o = lerp(CANVAS_BG * 0.01, o, all(saturate(i.uv.zw - i.uv.zw * i.uv.zw)));
}

/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_SceneWeaver_Hotsampling
<
    enabled_in_screenshot = false;
    ui_label = "METEOR: SceneWeaver (Hotsampling)";
    ui_tooltip =        
        "                         MartysMods - SceneWeaver                       \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"
        "Various features for hotsampling and framing a screenshot.                    \n"
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
    }
    //Set flag here so it doesn't matter which order the techniques are
    pass
	{
		VertexShader = HotsamplingStateVS;
		PixelShader = SetHotsamplingStatePS;
		RenderTarget = HotsampleStateTex;
		PrimitiveTopology = POINTLIST;
		VertexCount = 1;
    }
}

technique MartysMods_SceneWeaver_Letterbox
<
    ui_label = "METEOR: SceneWeaver (Letterbox)";
    ui_tooltip =        
        "                         MartysMods - SceneWeaver                       \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"
        "Various features for hotsampling and framing a screenshot.                    \n"
        "\n"
        "\n"
        "Visit https://martysmods.com for more information.                            \n"
        "\n"       
        "______________________________________________________________________________";
>
{
    pass
    {
        VertexShader = LetterboxVS;
        PixelShader  = LetterboxPS;
    }    
}

technique MartysMods_SceneWeaver_Canvas
<
    enabled_in_screenshot = false;
    ui_label = "METEOR: SceneWeaver (Canvas)";
    ui_tooltip =        
        "                         MartysMods - SceneWeaver                       \n"
        "                   Marty's Extra Effects for ReShade (METEOR)                 \n"
        "______________________________________________________________________________\n"
        "\n"
        "Various features for hotsampling and framing a screenshot.                    \n"
        "\n"
        "\n"
        "Visit https://martysmods.com for more information.                            \n"
        "\n"       
        "______________________________________________________________________________";
>
{
    pass
    {
        VertexShader = CanvasVS;
        PixelShader  = CanvasPS;
    }
    //Clear flag here so it doesn't matter which order the techniques are
    pass
	{
		VertexShader = HotsamplingStateVS;
		PixelShader = ResetHotsamplingStatePS;
		RenderTarget = HotsampleStateTex;
		PrimitiveTopology = POINTLIST;
		VertexCount = 1;
    }
}

