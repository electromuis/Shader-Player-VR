// @title Glitch bars
// Datamosh-style glitch: sliding neon bars, RGB tearing and blocky noise,
// kicked off by the bass.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float amount : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float hash(vec2 p) {
	p = 50.0 * fract(p * 0.3183099 + vec2(0.71, 0.113));
	return fract(p.x * p.y * (p.x + p.y));
}

vec3 scene(vec2 uv, float t) {
	float bar = floor(uv.y * 24.0);
	float shift = (hash(vec2(bar, floor(t * 8.0))) - 0.5) * 0.3 * amount;
	float x = uv.x + shift * step(0.6, hash(vec2(bar, floor(t * 4.0) + 7.0)));
	vec3 c = 0.5 + 0.5 * cos(6.28318 * (x * 1.5 + bar * 0.05 + t * 0.2 + vec3(0.0, 0.33, 0.67)));
	float stripes = step(0.5, fract(x * 12.0 + t));
	return c * (0.4 + 0.6 * stripes);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = fragCoord / iResolution.xy;
	float t = iTime;
	float kick = amount * (0.3 + audio_bass * react);
	// Blocky displacement.
	vec2 block = floor(uv * vec2(16.0, 9.0));
	float bh = hash(block + floor(t * 6.0));
	if (bh > 1.0 - kick * 0.3) {
		uv.x += (hash(block * 1.7 + floor(t * 6.0)) - 0.5) * 0.2;
	}
	float split = 0.01 * kick;
	vec3 col;
	col.r = scene(uv + vec2(split, 0.0), t).r;
	col.g = scene(uv, t).g;
	col.b = scene(uv - vec2(split, 0.0), t).b;
	col *= 0.85 + 0.15 * sin(fragCoord.y * 3.14159);
	col += step(0.985, hash(floor(fragCoord / 3.0) + t)) * 0.8;
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
