// @title Apollonian gasket
// Apollonian gasket by circle inversion: endless nested bubbles in candy colours.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float zoom : hint_range(0.3, 3.0, 0.01) = 1.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y * 2.2 / zoom;
	float a = iTime * 0.05;
	p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	p += vec2(0.2 * sin(iTime * 0.13), 0.2 * cos(iTime * 0.11));
	float scale = 1.0;
	float trap = 1e9;
	float k = 1.2 + 0.08 * sin(iTime * 0.3) + audio_bass * react * 0.05;
	for (int i = 0; i < 10; i++) {
		p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
		float r2 = dot(p, p);
		trap = min(trap, r2);
		float f = k / r2;
		p *= f;
		scale *= f;
	}
	float d = 0.25 * abs(p.y) / scale;
	float edge = smoothstep(0.004, 0.0, d);
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (log(trap + 0.01) * 0.2 + iTime * 0.05 + vec3(0.0, 0.33, 0.67)));
	col = col * (0.3 + 0.7 * sqrt(clamp(trap, 0.0, 1.0))) + edge * 0.8;
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
