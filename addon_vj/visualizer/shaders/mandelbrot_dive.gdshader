// @title Mandelbrot dive
// A continuous zoom into the Mandelbrot set's seahorse valley, smoothly coloured.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float zoom_speed : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform int max_iter : hint_range(64, 512) = 256;
uniform float color_cycle : hint_range(0.0, 2.0, 0.01) = 0.3;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	// Float precision runs out around e^-12, so the dive loops.
	float zt = 3.0 + mod(iTime * zoom_speed, 9.0);
	float z = exp(-zt);
	vec2 c = vec2(-0.743643887, 0.131825904) + p * z * 2.5;
	vec2 w = vec2(0.0);
	float n = 0.0;
	for (int i = 0; i < max_iter; i++) {
		w = vec2(w.x * w.x - w.y * w.y, 2.0 * w.x * w.y) + c;
		if (dot(w, w) > 256.0) {
			break;
		}
		n += 1.0;
	}
	vec3 col = vec3(0.0);
	if (n < float(max_iter)) {
		float sn = n - log2(log2(dot(w, w))) + 4.0;
		col = 0.5 + 0.5 * cos(6.28318 * (sn * 0.03 + iTime * color_cycle * 0.2 + vec3(0.0, 0.33, 0.67)));
		col *= 0.3 + 0.7 * smoothstep(0.0, 12.0, sn);
	}
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
