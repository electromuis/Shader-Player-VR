// @title Liquid marble
// Domain-warped noise (after Inigo Quilez): swirling marbled paint.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 2.0, 0.01) = 0.4;
uniform float warp : hint_range(0.0, 8.0, 0.1) = 2.0;
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
	vec2 p = fragCoord / iResolution.y * 1.2;
	float t = iTime * speed;
	vec2 q = vec2(fbm(p + t), fbm(p + vec2(5.2, 1.3) - t));
	vec2 r = vec2(fbm(p + warp * q + vec2(1.7, 9.2) + t * 0.7), fbm(p + warp * q + vec2(8.3, 2.8) - t * 0.5));
	float f = fbm(p + (warp + audio_bass * react * 2.0) * r);
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (f * 3.0 + length(q) * 1.5 + vec3(0.0, 0.33, 0.67) + t * 0.2));
	col = mix(col, vec3(1.0, 0.2, 0.7), clamp(dot(r, r) * 0.5, 0.0, 1.0) * 0.4);
	col *= 0.2 + f * f * 2.0;
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
