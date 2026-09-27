// @title Aurora veil
// Aurora curtains rippling over a starry night; the highs make them shimmer.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float intensity : hint_range(0.0, 3.0, 0.01) = 1.2;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = fragCoord / iResolution.xy;
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float t = iTime * speed * 0.3;
	vec3 col = mix(vec3(0.0, 0.02, 0.06), vec3(0.03, 0.0, 0.1), uv.y);
	// Stars.
	vec2 sg = floor(fragCoord / 3.0);
	float s = hash(sg);
	col += step(0.997, s) * (0.5 + 0.5 * sin(iTime * 3.0 + s * 100.0));
	// Curtains: several layers, each a wavy band with vertical rays.
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float x = p.x * (1.0 + fi * 0.2) + fi * 1.7;
		float wave = 0.1 * sin(x * 2.0 + t * (1.0 + fi * 0.3)) + 0.06 * sin(x * 5.0 - t * 1.7) + 0.05 * noise(vec2(x * 3.0, t));
		float y = p.y - (0.05 + fi * 0.06) - wave;
		float band = exp(-max(y, 0.0) * 5.0) * smoothstep(-0.03, 0.02, y);
		float rays = 0.5 + 0.5 * noise(vec2(x * 30.0, t * 3.0 + fi));
		rays = pow(rays, 2.0) * (1.0 + audio_high * react * 2.0);
		vec3 c = 0.5 + 0.5 * cos(6.28318 * (fi * 0.12 + y * 1.5 + t * 0.2 + vec3(0.3, 0.6, 0.9)));
		col += c * band * rays * 0.35 * intensity;
	}
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
