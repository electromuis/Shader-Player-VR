// @title Kaleido smoke
// Coloured smoke seen through a turning kaleidoscope.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float segments : hint_range(3.0, 16.0, 1.0) = 6.0;
uniform float speed : hint_range(0.0, 2.0, 0.01) = 0.5;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float hash(vec2 p) {
	p = 50.0 * fract(p * 0.3183099 + vec2(0.71, 0.113));
	return fract(p.x * p.y * (p.x + p.y));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p;
		a *= 0.5;
	}
	return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float t = iTime * speed;
	float r = length(p);
	float a = atan(p.y, p.x) + t * 0.3;
	float seg = 6.28318 / segments;
	a = abs(mod(a, seg) - seg * 0.5);
	vec2 q = vec2(cos(a), sin(a)) * r * 3.0;
	float f = fbm(q + vec2(t, -t * 0.7) + fbm(q * 2.0 - t) * (1.0 + audio_bass * react));
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (f * 2.0 + r - t * 0.2 + vec3(0.0, 0.33, 0.67)));
	col *= smoothstep(0.2, 0.8, f) * 1.5;
	col += vec3(1.0, 0.9, 0.7) * pow(f, 6.0) * 3.0;
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
