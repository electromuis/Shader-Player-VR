// @title Julia morph
// A Julia set whose seed wanders near the Mandelbrot set's edge, with a
// neon glow along its filaments.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 2.0, 0.01) = 0.3;
uniform float react : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float glow : hint_range(0.1, 3.0, 0.01) = 1.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 z = (fragCoord - 0.5 * iResolution.xy) / iResolution.y * 2.8;
	float t = iTime * speed;
	// Circles the main cardioid's rim, where the Julia sets are richest.
	float a = t;
	vec2 w = vec2(cos(a), sin(a)) * 0.5;
	vec2 c = w - vec2(w.x * w.x - w.y * w.y, 2.0 * w.x * w.y) * 1.02;
	c += audio_bass * react * 0.02;
	float n = 0.0;
	for (int i = 0; i < 200; i++) {
		z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
		if (dot(z, z) > 64.0) {
			break;
		}
		n += 1.0;
	}
	vec3 col = vec3(0.0);
	if (n < 200.0) {
		float sn = n - log2(log2(dot(z, z)));
		col = 0.5 + 0.5 * cos(sn * 0.25 + iTime * 0.5 + vec3(0.0, 2.1, 4.2));
		col *= pow(clamp(sn / 40.0, 0.0, 1.0), 0.8) * 1.5 * glow;
	} else {
		col = vec3(0.05, 0.0, 0.1) + 0.3 * (0.5 + 0.5 * cos(length(z) * 8.0 + iTime + vec3(0.0, 2.0, 4.0)));
	}
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
