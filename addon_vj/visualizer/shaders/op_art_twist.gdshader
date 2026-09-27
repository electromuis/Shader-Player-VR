// @title Op-art twist
// Op-art: a checkerboard twisted into a vortex, with colour bleeding through
// the black squares.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float twist : hint_range(0.0, 10.0, 0.1) = 3.0;
uniform float squares : hint_range(2.0, 30.0, 1.0) = 12.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float r = length(p);
	float a = atan(p.y, p.x);
	float tw = twist * sin(iTime * 0.4) * exp(-r * 2.0) * (1.0 + audio_bass * react * 0.5);
	a += tw;
	vec2 q = vec2(cos(a), sin(a)) * r;
	q *= 1.0 + 0.15 * sin(r * 12.0 - iTime * 3.0);
	vec2 g = floor(q * squares + iTime * 0.2);
	float check = mod(g.x + g.y, 2.0);
	vec3 hue = 0.5 + 0.5 * cos(6.28318 * (r * 0.8 - iTime * 0.15 + vec3(0.0, 0.33, 0.67)));
	vec3 col = mix(hue * 0.25, vec3(1.0) * 0.9 + hue * 0.3, check);
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
