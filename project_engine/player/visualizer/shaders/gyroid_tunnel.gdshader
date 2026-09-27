// @title Gyroid tunnel
// Raymarched flight through a gyroid: an endless cave of saddle surfaces
// striped in neon, with a haze that pulses to the bass. Heavy: renders at 720p.
// @resolution 1280x720
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float thickness : hint_range(0.02, 0.6, 0.01) = 0.12;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

vec2 path(float z) {
	return vec2(sin(z * 0.3), cos(z * 0.25)) * 0.6;
}

float map(vec3 p) {
	float g = (abs(dot(sin(p * 3.0), cos(p.yzx * 3.0))) - thickness) / 3.0;
	// Keep a tunnel open along the flight path.
	float tunnel = 0.45 - length(p.xy - path(p.z));
	return max(g, tunnel);
}

vec3 normal_at(vec3 p) {
	vec2 e = vec2(0.002, 0.0);
	return normalize(vec3(map(p + e.xyy) - map(p - e.xyy), map(p + e.yxy) - map(p - e.yxy), map(p + e.yyx) - map(p - e.yyx)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float z = iTime * speed;
	vec3 ro = vec3(path(z), z);
	vec3 fw = normalize(vec3(path(z + 1.0), z + 1.0) - ro);
	vec3 rt = normalize(cross(vec3(sin(z * 0.1), 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw + (uv.x * rt + uv.y * up) * 0.9);
	float t = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 100; i++) {
		float d = map(ro + rd * t);
		glow += exp(-abs(d) * 40.0);
		if (d < 0.001 || t > 12.0) {
			break;
		}
		t += d * 0.9;
	}
	vec3 p = ro + rd * t;
	vec3 n = normal_at(p);
	vec3 base = 0.5 + 0.5 * cos(6.28318 * (p.z * 0.15 + dot(sin(p * 3.0), vec3(0.2)) + vec3(0.0, 0.33, 0.67)));
	float diff = 0.5 + 0.5 * dot(n, -rd);
	float stripes = 0.6 + 0.4 * sin((p.x + p.y + p.z) * 25.0);
	vec3 col = base * diff * stripes;
	col += pow(1.0 - diff, 3.0) * base.zxy * 1.5;
	vec3 haze = 0.5 + 0.5 * cos(iTime * 0.4 + vec3(4.0, 2.0, 0.0));
	col = mix(col, haze * 0.3, 1.0 - exp(-t * 0.2));
	col += haze * glow * 0.012 * (1.0 + audio_bass * react);
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
