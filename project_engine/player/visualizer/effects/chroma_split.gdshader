// @title Chroma split
// @idle amount <= 0.0
// Splits red, green and blue apart, radially from the centre and in a slow
// orbit, for rainbow fringes on every edge.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float amount : hint_range(0.0, 0.1, 0.001) = 0.015;
uniform float radial : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float orbit_speed : hint_range(0.0, 3.0, 0.01) = 0.5;

void fragment() {
	vec2 d = UV - 0.5;
	float ang = TIME * orbit_speed * 6.28318;
	vec2 orbit = vec2(cos(ang), sin(ang)) / vec2(display_aspect, 1.0);
	vec2 off = mix(orbit, d * 2.0, radial) * amount;
	vec4 r = texture(input_tex, UV + off);
	vec4 g = texture(input_tex, UV);
	vec4 b = texture(input_tex, UV - off);
	COLOR = vec4(r.r, g.g, b.b, max(g.a, max(r.a, b.a)));
}
