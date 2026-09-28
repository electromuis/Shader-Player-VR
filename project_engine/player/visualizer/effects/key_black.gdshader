// @title Key black
// Shows black as transparent: alpha is the brightest channel and colour is
// un-premultiplied by it, so over what's behind, black adds nothing and
// bright stays solid. For laying Shadertoy output over the video, when later
// effects need the alpha (an Edge blur, say); otherwise the layer's Blend
// "Black transparent" does the same without the extra pass.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

void fragment() {
	vec4 c = texture(input_tex, UV);
	// The brightest channel, not luma: rgb / k then stays within 0..1, so
	// saturated blues and reds keep their full strength.
	float k = max(max(c.r, c.g), c.b);
	COLOR = vec4(c.rgb / max(k, 0.0001), k * c.a);
}
