// @title Lava lamp
// Metaballs merging and splitting like a lava lamp, in hot neon gradients.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 3.0, 0.01) = 0.6;
uniform int blobs : hint_range(3, 16) = 10;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float t = iTime * speed;
	float field = 0.0;
	vec2 grad = vec2(0.0);
	for (int i = 0; i < blobs; i++) {
		float fi = float(i);
		vec2 c = vec2(sin(t * (0.5 + fi * 0.13) + fi * 2.1) * 0.7, sin(t * (0.3 + fi * 0.07) + fi * 1.3) * 0.4);
		float r = 0.12 + 0.04 * sin(fi * 3.0) + audio_bass * react * 0.03;
		vec2 d = p - c;
		// Gaussian blobs: smooth everywhere, so the shading has no hot spots.
		float k = exp(-dot(d, d) / (r * r));
		field += k;
		grad += -2.0 * k * d / (r * r);
	}
	float edge = smoothstep(0.42, 0.48, field);
	vec3 bg = mix(vec3(0.15, 0.0, 0.3), vec3(0.0, 0.05, 0.2), p.y + 0.5);
	vec3 hot = 0.5 + 0.5 * cos(6.28318 * (field * 0.15 + p.y * 0.5 + iTime * 0.05 + vec3(0.0, 0.2, 0.4)));
	hot = mix(vec3(1.0, 0.2, 0.5), hot, 0.6);
	vec3 n = normalize(vec3(-grad * 0.08, 1.0));
	float light = max(dot(n, normalize(vec3(-0.4, 0.5, 0.8))), 0.0);
	vec3 col = bg + hot * smoothstep(0.05, 0.45, field) * 0.35;
	col = mix(col, hot * (0.35 + 0.8 * light), edge);
	col += pow(light, 24.0) * edge * 0.7;
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
