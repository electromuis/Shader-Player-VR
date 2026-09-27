// @title Oil slick
// Thin-film interference: oil on water, swirling in iridescent bands.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float thickness : hint_range(0.5, 6.0, 0.01) = 2.5;
uniform float speed : hint_range(0.0, 2.0, 0.01) = 0.3;
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
		p = p * 2.02 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

// Approximate thin-film colour for an optical thickness d.
vec3 film(float d) {
	return 0.5 + 0.5 * cos(6.28318 * d * vec3(1.0, 1.15, 1.32));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = fragCoord / iResolution.y * 2.0;
	float t = iTime * speed;
	vec2 w = vec2(fbm(p + t), fbm(p - t + 4.0));
	float h = fbm(p * 1.3 + w * 2.0 + t * 0.5);
	float d = h * thickness * (1.0 + audio_bass * react * 0.3);
	vec3 col = film(d);
	col = mix(vec3(0.02, 0.02, 0.05), col, smoothstep(0.2, 0.5, h));
	col = pow(col, vec3(1.3)) * 1.3;
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
