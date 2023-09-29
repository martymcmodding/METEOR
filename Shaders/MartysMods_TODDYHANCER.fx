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

    Genuine copy of Toddyhancer mod
    It sucks ass but everyone drooled over it, so here you go

    It's a SweetFX preset, okay?

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
// -- Sharpening --
#define sharp_strength      2.07   
#define sharp_clamp         0.048  
#define offset_bias         1.7   

#define Red   8.0  //[1.0 to 15.0]
#define Green 8.0  //[1.0 to 15.0]
#define Blue  8.0  //[1.0 to 15.0]

#define ColorGamma    2.5  //[0.1 to 2.5] Adjusts the colorfulness of the effect in a manner similar to Vibrance. 1.0 is neutral.
#define DPXSaturation 2.0  //[0.0 to 8.0] Adjust saturation of the effect. 1.0 is neutral.

#define RedC   0.34  //[0.60 to 0.20]
#define GreenC 0.30  //[0.60 to 0.20]
#define BlueC  0.30  //[0.60 to 0.20]

#define Blend 0.2    //[0.00 to 1.00] How strong the effect should be.

#define Gamma       .38  //[0.000 to 2.000] Adjust midtones. 1.000 is neutral. This setting does exactly the same as the one in Lift Gamma Gain, only with less control.
#define Exposure    -2.60  //[-1.000 to 1.000] Adjust exposure
#define Saturation  .50  //[-1.000 to 1.000] Adjust saturation
#define Bleach      .9  //[0.000 to 1.000] Brightens the shadows and fades the colors
#define Defog       0.00  //[0.000 to 1.000] How much of the color tint to remove
#define FogColor float3(0.00, 0.50, 0.15) //[0.00 to 2.55, 0.00 to 2.55, 0.00 to 2.55] What color to remove - default is blue

#define Vibrance     0.20  //[-1.00 to 1.00] Intelligently saturates (or desaturates if you use negative values) the pixels depending on their original saturation.
#define Vibrance_RGB_balance float3(1.00, 1.00, 1.00) //[-10.00 to 10.00,-10.00 to 10.00,-10.00 to 10.00] A per channel multiplier to the Vibrance strength so you can give more boost to certain colors over others

#define Curves_mode        2 //[0|1|2] Choose what to apply contrast to. 0 = Luma, 1 = Chroma, 2 = both Luma and Chroma. Default is 0 (Luma)
#define Curves_contrast 1.2 //[-1.00 to 1.00] The amount of contrast you want

// -- Advanced curve settings --
#define Curves_formula     1 //[1|2|3|4|5|6|7|8|9|10|11] The contrast s-curve you want to use.
                             //1 = Sine, 2 = Abs split, 3 = Smoothstep, 4 = Exp formula, 5 = Simplified Catmull-Rom (0,0,1,1), 6 = Perlins Smootherstep
                             //7 = Abs add, 8 = Techicolor Cinestyle, 9 = Parabola, 10 = Half-circles. 11 = Polynomial split.
                             //Note that Technicolor Cinestyle is practically identical to Sine, but runs slower. In fact I think the difference might only be due to rounding errors.
                             //I prefer 2 myself, but 3 is a nice alternative with a little more effect (but harsher on the highlight and shadows) and it's the fastest formula.

#define ColorTone float3(1.1, 1.00, 1.0) //[0.00 to 2.55, 0.00 to 2.55, 0.00 to 2.55] What color to tint the image
#define GreyPower  0.40                    //[0.00 to 1.00] How much desaturate the image before tinting it
#define SepiaPower 0.40                    //[0.00 to 1.00] How much to tint the image


/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

//do NOT change anything here. "hurr durr I changed this and now it works"
//you ARE breaking things down the line, if the shader does not work without changes
//here, it's by design.

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex;  };

#include "MartysMods/mmx_global.fxh"

struct VSOUT
{
	float4                  vpos        : SV_Position;
    float2                  uv          : TEXCOORD0;
};

/*=============================================================================
	Functions
=============================================================================*/

static const float3x3 RGB = float3x3
(
    2.67147117265996,-1.26723605786241,-0.410995602172227,
    -1.02510702934664,1.98409116241089,0.0439502493584124,
    0.0610009456429445,-0.223670750812863,1.15902104167061
);

static const float3x3 XYZ = float3x3
(
    0.500303383543316,0.338097573222739,0.164589779545857,
    0.257968894274758,0.676195259144706,0.0658358459823868,
    0.0234517888692628,0.1126992737203,0.866839673124201
);

float4 DPXPass(float4 InputColor)
{

	float DPXContrast = 0.1;

	float DPXGamma = 1.0;

	float RedCurve = Red;
	float GreenCurve = Green;
	float BlueCurve = Blue;
	
	float3 RGB_Curve = float3(Red,Green,Blue);
	float3 RGB_C = float3(RedC,GreenC,BlueC);

	float3 B = InputColor.rgb;
	//float3 Bn = B; // I used InputColor.rgb instead.

	B = pow(abs(B), 1.0/DPXGamma);

    B = B * (1.0 - DPXContrast) + (0.5 * DPXContrast);


    //B = (1.0 /(1.0 + exp(- RGB_Curve * (B - RGB_C))) - (1.0 / (1.0 + exp(RGB_Curve / 2.0))))/(1.0 - 2.0 * (1.0 / (1.0 + exp(RGB_Curve / 2.0))));
	
    float3 Btemp = (1.0 / (1.0 + exp(RGB_Curve / 2.0)));	  
	  B = ((1.0 / (1.0 + exp(-RGB_Curve * (B - RGB_C)))) / (-2.0 * Btemp + 1.0)) + (-Btemp / (-2.0 * Btemp + 1.0));


     //TODO use faster code for conversion between RGB/HSV  -  see http://www.chilliant.com/rgb2hsv.html
	   float value = max(max(B.r, B.g), B.b);
	   float3 color = B / value;
	
	   color = pow(abs(color), 1.0/ColorGamma);
	
	   float3 c0 = color * value;

	   c0 = mul(XYZ, c0);

	   float luma = dot(c0, float3(0.30, 0.59, 0.11)); //Use BT 709 instead?

 	   //float3 chroma = c0 - luma;
	   //c0 = chroma * DPXSaturation + luma;
	   c0 = (1.0 - DPXSaturation) * luma + DPXSaturation * c0;
	   
	   c0 = mul(RGB, c0);
	
	InputColor.rgb = lerp(InputColor.rgb, c0, Blend);

	return InputColor;
}

float4 TonemapPass( float4 colorInput )
{
	float3 color = colorInput.rgb;

	color = saturate(color - Defog * FogColor); // Defog
	
	color *= pow(2.0f, Exposure); // Exposure
	
	color = pow(color, Gamma);    // Gamma -- roll into the first gamma correction in main.h ?

	//#define BlueShift 0.00	//Blueshift
	//float4 d = color * float4(1.05f, 0.97f, 1.27f, color.a);
	//color = lerp(color, d, BlueShift);
	
	float3 lumCoeff = float3(0.2126, 0.7152, 0.0722);
	float lum = dot(lumCoeff, color.rgb);
	
	float3 blend = lum.rrr; //dont use float3
	
	float L = saturate( 10.0 * (lum - 0.45) );
  	
	float3 result1 = 2.0f * color.rgb * blend;
	float3 result2 = 1.0f - 2.0f * (1.0f - blend) * (1.0f - color.rgb);
	
	float3 newColor = lerp(result1, result2, L);
	//float A2 = Bleach * color.rgb; //why use a float for A2 here and then multiply by color.rgb (a float3)?
	float3 A2 = Bleach * color.rgb; //
	float3 mixRGB = A2 * newColor;
	
	color.rgb += ((1.0f - A2) * mixRGB);
	
	//float3 middlegray = float(color.r + color.g + color.b) / 3;
	float3 middlegray = dot(color,(1.0/3.0)); //1fps slower than the original on nvidia, 2 fps faster on AMD
	
	float3 diffcolor = color - middlegray; //float 3 here
	colorInput.rgb = (color + diffcolor * Saturation)/(1+(diffcolor*Saturation)); //saturation
	
	return colorInput;
}


float4 VibrancePass( float4 colorInput )
{
  #ifndef Vibrance_RGB_balance //for backwards compatibility with setting presets for older version.
    #define Vibrance_RGB_balance float3(1.00, 1.00, 1.00)
  #endif
  
  #define Vibrance_coeff float3(Vibrance_RGB_balance * Vibrance)

	float4 color = colorInput; //original input color
  float3 lumCoeff = float3(0.212656, 0.715158, 0.072186);  //Values to calculate luma with

	float luma = dot(lumCoeff, color.rgb); //calculate luma (grey)


	float max_color = max(colorInput.r, max(colorInput.g,colorInput.b)); //Find the strongest color
	float min_color = min(colorInput.r, min(colorInput.g,colorInput.b)); //Find the weakest color

	float color_saturation = max_color - min_color; //The difference between the two is the saturation

/*
	float3 sort = colorInput.rgb;
	float2 sort1 = (sort.r > sort.g) ? sort.gr : sort.rg;
	float2 sort2 = (sort.g > sort.b) ? sort.bg : sort.gb;

	sort.gb = (sort1.g > sort2.g) ? float2(sort2.g,sort1.g) : float2(sort1.g,sort2.g); //max is now stored in .b
	sort.r = (sort1.r < sort2.r) ? sort1.r : sort2.r; //sorted : min is .r , med is .g and max is .b
	
	float color_saturation = sort.b - sort.r; //The difference between the two is the saturation
*/

/*	
	float3 sort = colorInput.rgb;
	sort.rg = (sort.r > sort.g) ? sort.gr : sort.rg;
	sort.gb = (sort.g > sort.b) ? sort.bg : sort.gb; //max is now stored in .b
	sort.rg = (sort.r > sort.g) ? sort.gr : sort.rg; //sorted : min is .r , med is .g and max is .b
	
	float color_saturation = sort.b - sort.r; //The difference between the two is the saturation
*/


/*
	float4 sort = colorInput;
	sort.rg = (sort.r > sort.g) ? sort.gr : sort.rg;
	sort.gb = (sort.g > sort.b) ? sort.bg : sort.gb; //max is now stored in .b
	
	float color_saturation = sort.b - min(sort.r,sort.g); //The difference between the two is the saturation
*/

  //color.rgb = lerp(luma, color.rgb, (1.0 + (Vibrance * (1.0 - color_saturation)))); //extrapolate between luma and original by 1 + (1-saturation) - simple

  //color.rgb = lerp(luma, color.rgb, (1.0 + (Vibrance * (1.0 - (sign(Vibrance) * color_saturation))))); //extrapolate between luma and original by 1 + (1-saturation) - current
  color.rgb = lerp(luma, color.rgb, (1.0 + (Vibrance_coeff * (1.0 - (sign(Vibrance_coeff) * color_saturation))))); //extrapolate between luma and original by 1 + (1-saturation) - current

  //color.rgb = lerp(luma, color.rgb, 1.0 + (1.0-pow(color_saturation, 1.0 - (1.0-Vibrance))) ); //pow version

	return color; //return the result
	//return color_saturation.xxxx; //Visualize the saturation
}



float4 CurvesPass( float4 colorInput )
{
  float3 lumCoeff = float3(0.2126, 0.7152, 0.0722);  //Values to calculate luma with
  float Curves_contrast_blend = Curves_contrast;
  
  #ifndef PI
    #define PI 3.1415927
  #endif

   /*-----------------------------------------------------------.
  /               Separation of Luma and Chroma                 /
  '-----------------------------------------------------------*/

  // -- Calculate Luma and Chroma if needed --
  #if Curves_mode != 2

    //calculate luma (grey)
    float luma = dot(lumCoeff, colorInput.rgb);

    //calculate chroma
	  float3 chroma = colorInput.rgb - luma;
  #endif

  // -- Which value to put through the contrast formula? --
  // I name it x because makes it easier to copy-paste to Graphtoy or Wolfram Alpha or another graphing program
  #if Curves_mode == 2
	  float3 x = colorInput.rgb; //if the curve should be applied to both Luma and Chroma
	#elif Curves_mode == 1
	  float3 x = chroma; //if the curve should be applied to Chroma
	  x = x * 0.5 + 0.5; //adjust range of Chroma from -1 -> 1 to 0 -> 1
  #else // Curves_mode == 0
    float x = luma; //if the curve should be applied to Luma
  #endif

   /*-----------------------------------------------------------.
  /                     Contrast formulas                       /
  '-----------------------------------------------------------*/

  // -- Curve 1 --
  #if Curves_formula == 1
    x = sin(PI * 0.5 * x); // Sin - 721 amd fps, +vign 536 nv
    x *= x;
    
    //x = 0.5 - 0.5*cos(PI*x);
    //x = 0.5 * -sin(PI * -x + (PI*0.5)) + 0.5;
  #endif

  // -- Curve 2 --
  #if Curves_formula == 2
    x = x - 0.5;  
    x = ( x / (0.5 + abs(x)) ) + 0.5;
    
    //x = ( (x - 0.5) / (0.5 + abs(x-0.5)) ) + 0.5;
  #endif

  // -- Curve 3 --
  #if Curves_formula == 3
    //x = smoothstep(0.0,1.0,x); //smoothstep
    x = x*x*(3.0-2.0*x); //faster smoothstep alternative - 776 amd fps, +vign 536 nv
    //x = x - 2.0 * (x - 1.0) * x* (x- 0.5);  //2.0 is contrast. Range is 0.0 to 2.0
  #endif

  // -- Curve 4 --
  #if Curves_formula == 4
    x = (1.0524 * exp(6.0 * x) - 1.05248) / (exp(6.0 * x) + 20.0855); //exp formula
  #endif

  // -- Curve 5 --
  #if Curves_formula == 5
    //x = 0.5 * (x + 3.0 * x * x - 2.0 * x * x * x); //a simplified catmull-rom (0,0,1,1) - btw smoothstep can also be expressed as a simplified catmull-rom using (1,0,1,0)
    //x = (0.5 * x) + (1.5 -x) * x*x; //estrin form - faster version
    x = x * (x * (1.5-x) + 0.5); //horner form - fastest version

    Curves_contrast_blend = Curves_contrast * 2.0; //I multiply by two to give it a strength closer to the other curves.
  #endif

 	// -- Curve 6 --
  #if Curves_formula == 6
    x = x*x*x*(x*(x*6.0 - 15.0) + 10.0); //Perlins smootherstep
	#endif

	// -- Curve 7 --
  #if Curves_formula == 7
    //x = ((x-0.5) / ((0.5/(4.0/3.0)) + abs((x-0.5)*1.25))) + 0.5;
	x = x - 0.5;
	x = x / ((abs(x)*1.25) + 0.375 ) + 0.5;
	//x = ( (x-0.5) / ((abs(x-0.5)*1.25) + (0.5/(4.0/3.0))) ) + 0.5;
  #endif

  // -- Curve 8 --
  #if Curves_formula == 8
    x = (x * (x * (x * (x * (x * (x * (1.6 * x - 7.2) + 10.8) - 4.2) - 3.6) + 2.7) - 1.8) + 2.7) * x * x; //Techicolor Cinestyle - almost identical to curve 1
  #endif

  // -- Curve 9 --
  #if Curves_formula == 9
    x =  -0.5 * (x*2.0-1.0) * (abs(x*2.0-1.0)-2.0) + 0.5; //parabola
  #endif

  // -- Curve 10 --
  #if Curves_formula == 10 //Half-circles

    #if Curves_mode == 0

			float xstep = step(x,0.5); //tenary might be faster here
			float xstep_shift = (xstep - 0.5);

			/*
			float xstep = (x < 0.5) ? 1.0 : 0.0; //tenary version
			float xstep_shift = (x < 0.5) ? 0.5 : -0.5;
			*/

			float shifted_x = x + xstep_shift;
	  
	  
    #else
			float3 xstep = step(x,0.5);
			float3 xstep_shift = (xstep - 0.5);
	  
			/*
			float3 xstep = float3(0.0,0.0,0.0);
			xstep.r = (x.r < 0.5) ? 1.0 : 0.0;
			xstep.g = (x.g < 0.5) ? 1.0 : 0.0;
			xstep.b = (x.b < 0.5) ? 1.0 : 0.0;
			float3 xstep_shift = float3(0.0,0.0,0.0);
			xstep_shift.r = (x.r < 0.5) ? 0.5 : -0.5;
			xstep_shift.g = (x.g < 0.5) ? 0.5 : -0.5;
			xstep_shift.b = (x.b < 0.5) ? 0.5 : -0.5;
			*/

			float3 shifted_x = x + xstep_shift;
    #endif

	x = abs(xstep - sqrt(-shifted_x * shifted_x + shifted_x) ) - xstep_shift;

  //x = abs(step(x,0.5)-sqrt(-(x+step(x,0.5)-0.5)*(x+step(x,0.5)-0.5)+(x+step(x,0.5)-0.5)))-(step(x,0.5)-0.5); //single line version of the above
    
  //x = 0.5 + (sign(x-0.5)) * sqrt(0.25-(x-trunc(x*2))*(x-trunc(x*2))); //worse
  
  /* // if/else - even worse
  if (x-0.5)
  x = 0.5-sqrt(0.25-x*x);
  else
  x = 0.5+sqrt(0.25-(x-1)*(x-1));
	*/

  //x = (abs(step(0.5,x)-clamp( 1-sqrt(1-abs(step(0.5,x)- frac(x*2%1)) * abs(step(0.5,x)- frac(x*2%1))),0 ,1))+ step(0.5,x) )*0.5; //worst so far
	
	//TODO: Check if I could use an abs split instead of step. It might be more efficient
	
	Curves_contrast_blend = Curves_contrast * 0.5; //I divide by two to give it a strength closer to the other curves.
  #endif
  
    // -- Curve 11 --
  #if Curves_formula == 11 //
  	#if Curves_mode == 0
			float a = 0.0;
			float b = 0.0;
		#else
			float3 a = float3(0.0,0.0,0.0);
			float3 b = float3(0.0,0.0,0.0);
		#endif

    a = x * x * 2.0;
    b = (2.0 * -x + 4.0) * x - 1.0;
    x = (x < 0.5) ? a : b;
  #endif


  // -- Curve 21 --
  #if Curves_formula == 21 //Cubic catmull
    float a = 1.00; //control point 1
    float b = 0.00; //start point
    float c = 1.00; //endpoint
    float d = 0.20; //control point 2
    x = 0.5 * ((-a + 3*b -3*c + d)*x*x*x + (2*a -5*b + 4*c - d)*x*x + (-a+c)*x + 2*b); //A customizable cubic catmull-rom spline
  #endif

  // -- Curve 22 --
  #if Curves_formula == 22 //Cubic Bezier spline
    float a = 0.00; //start point
    float b = 0.00; //control point 1
    float c = 1.00; //control point 2
    float d = 1.00; //endpoint

    float r  = (1-x);
	float r2 = r*r;
	float r3 = r2 * r;
	float x2 = x*x;
	float x3 = x2*x;
	//x = dot(float4(a,b,c,d),float4(r3,3*r2*x,3*r*x2,x3));

	//x = a * r*r*r + r * (3 * b * r * x + 3 * c * x*x) + d * x*x*x;
	//x = a*(1-x)*(1-x)*(1-x) +(1-x) * (3*b * (1-x) * x + 3 * c * x*x) + d * x*x*x;
	x = a*(1-x)*(1-x)*(1-x) + 3*b*(1-x)*(1-x)*x + 3*c*(1-x)*x*x + d*x*x*x;
  #endif

  // -- Curve 23 --
  #if Curves_formula == 23 //Cubic Bezier spline - alternative implementation.
    float3 a = float3(0.00,0.00,0.00); //start point
    float3 b = float3(0.25,0.15,0.85); //control point 1
    float3 c = float3(0.75,0.85,0.15); //control point 2
    float3 d = float3(1.00,1.00,1.00); //endpoint

    float3 ab = lerp(a,b,x);           // point between a and b
    float3 bc = lerp(b,c,x);           // point between b and c
    float3 cd = lerp(c,d,x);           // point between c and d
    float3 abbc = lerp(ab,bc,x);       // point between ab and bc
    float3 bccd = lerp(bc,cd,x);       // point between bc and cd
    float3 dest = lerp(abbc,bccd,x);   // point on the bezier-curve
    x = dest;
  #endif

  // -- Curve 24 --
  #if Curves_formula == 24
    x = 1.0 / (1.0 + exp(-(x * 10.0 - 5.0))); //alternative exp formula
  #endif

   /*-----------------------------------------------------------.
  /                 Joining of Luma and Chroma                  /
  '-----------------------------------------------------------*/

  #if Curves_mode == 2 //Both Luma and Chroma
	float3 color = x;  //if the curve should be applied to both Luma and Chroma
	colorInput.rgb = lerp(colorInput.rgb, color, Curves_contrast_blend); //Blend by Curves_contrast

  #elif Curves_mode == 1 //Only Chroma
	x = x * 2.0 - 1.0; //adjust the Chroma range back to -1 -> 1
	float3 color = luma + x; //Luma + Chroma
	colorInput.rgb = lerp(colorInput.rgb, color, Curves_contrast_blend); //Blend by Curves_contrast

  #else // Curves_mode == 0 //Only Luma
    x = lerp(luma, x, Curves_contrast_blend); //Blend by Curves_contrast
    colorInput.rgb = x + chroma; //Luma + Chroma

  #endif

  //Return the result
  return colorInput;
}


float4 SepiaPass( float4 colorInput )
{
	float3 sepia = colorInput.rgb;
	
	// calculating amounts of input, grey and sepia colors to blend and combine
	float grey = dot(sepia, float3(0.2126, 0.7152, 0.0722));
	
	sepia *= ColorTone;
	
	float3 blend2 = (grey * GreyPower) + (colorInput.rgb / (GreyPower + 1));

	colorInput.rgb = lerp(blend2, sepia, SepiaPower);
	
	// returning the final color
	return colorInput;
}

/*=============================================================================
	Shader Entry Points
=============================================================================*/

VSOUT MainVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv);
    return o;
}

void MainPS(in VSOUT i, out float3 o : SV_Target0)
{  
    float3 ori = tex2D(ColorInput, i.uv).rgb; 
    float3 sharp_strength_luma = (float3(0.2126, 0.7152, 0.0722) * sharp_strength);   

    //luma sharpen pattern 4
    float3 blur_ori = tex2D(ColorInput, i.uv + BUFFER_PIXEL_SIZE *  float2(0.5,-offset_bias)).rgb;  // South South East
    blur_ori += tex2D(ColorInput, i.uv + BUFFER_PIXEL_SIZE *        float2(-offset_bias,-0.5)).rgb; // West South West
    blur_ori += tex2D(ColorInput, i.uv + BUFFER_PIXEL_SIZE *        float2(offset_bias,0.5)).rgb; // East North East
    blur_ori += tex2D(ColorInput, i.uv + BUFFER_PIXEL_SIZE *        float2(-0.5, offset_bias)).rgb; // North North West
    blur_ori *= 0.25;
    sharp_strength_luma *= 0.666;

    float3 sharp = ori - blur_ori; 
    float4 sharp_strength_luma_clamp = float4(sharp_strength_luma * (0.5 / sharp_clamp),0.5);
    float sharp_luma = saturate(dot(float4(sharp,1.0), sharp_strength_luma_clamp)); //Calculate the luma, adjust the strength, scale up and clamp
    sharp_luma = (sharp_clamp * 2.0) * sharp_luma - sharp_clamp; 

    o = ori + sharp_luma;

      //levels
    o = linearstep(10.0/255.0, 1.0, o); //toddyhancer used 10/255 as blackpoint

    o = DPXPass(o.xyzz).xyz;
    o = TonemapPass(o.xyzz).xyz;
    o = VibrancePass(o.xyzz).xyz;
    o = CurvesPass(o.xyzz).xyz;
    o = SepiaPass(o.xyzz).xyz;
}


/*=============================================================================
	Techniques
=============================================================================*/

technique MartysMods_Toddyhancer
{    
    pass
	{
		VertexShader = MainVS;
		PixelShader  = MainPS;
	}      
}