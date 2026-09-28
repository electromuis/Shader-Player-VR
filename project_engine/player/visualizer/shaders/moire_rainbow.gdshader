// @title Moiré rainbow
// Interfering ring patterns from wandering centres, split into RGB so the
// moire shimmers in rainbow fringes.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float frequency : hint_range(10.0, 200.0, 1.0) = 80.0;
uniform float speed : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float rings(vec2 p, float t, float off) {
	vec2 a = vec2(sin(t * 0.7), cos(t * 0.5)) * 0.4;
	vec2 b = vec2(cos(t * 0.6 + 1.0), sin(t * 0.8)) * 0.4;
	float f = frequency * (1.0 + off);
	return sin(length(p - a) * f) * sin(length(p - b) * f);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float t = iTime * speed;
	float spread = 0.01 + audio_bass * react * 0.02;
	vec3 col = vec3(rings(p, t, -spread), rings(p, t, 0.0), rings(p, t, spread));
	col = smoothstep(-0.1, 0.4, col);
	col *= 0.6 + 0.4 * cos(6.28318 * (length(p) - t * 0.1 + vec3(0.0, 0.33, 0.67)));
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
