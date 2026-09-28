// @title Kaliset coral
// Kali's abs-fold fractal with orbit-trap colouring: glowing filigree coral
// that slowly breathes. The bass pushes the fold.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float zoom : hint_range(0.3, 3.0, 0.01) = 1.0;
uniform int iterations : hint_range(4, 32) = 14;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

vec3 pal(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y * 1.4 / zoom;
	float t = iTime * 0.15;
	vec2 k = vec2(0.9 + 0.1 * sin(t), 0.55 + 0.1 * cos(t * 1.3)) + audio_bass * react * 0.03;
	float trap_line = 1e9;
	float trap_ring = 1e9;
	float at = 0.0;
	for (int i = 0; i < iterations; i++) {
		p = abs(p) / dot(p, p) - k;
		float l = abs(p.y);
		if (l < trap_line) {
			trap_line = l;
			at = float(i);
		}
		trap_ring = min(trap_ring, abs(length(p) - 0.6));
	}
	vec3 col = pal(at * 0.08 + t) * exp(-trap_line * 12.0);
	col += pal(at * 0.08 + t + 0.5) * exp(-trap_ring * 25.0) * 0.8;
	col = pow(col, vec3(1.2)) * 1.3;
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
