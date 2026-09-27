// @title Sphere lattice
// Raymarched infinite lattice of glossy spheres, each a different hue,
// pulsing with the bass as the camera drifts through.
// @resolution 1280x720
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 3.0, 0.01) = 0.6;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

vec3 cell_of(vec3 p) {
	return floor(p / 2.0 + 0.5);
}

float map(vec3 p) {
	vec3 q = mod(p + 1.0, 2.0) - 1.0;
	vec3 c = cell_of(p);
	float pulse = 0.3 + 0.08 * sin(iTime * 3.0 + dot(c, vec3(1.0, 2.0, 3.0))) + audio_bass * react * 0.12;
	return length(q) - pulse;
}

vec3 normal_at(vec3 p) {
	vec2 e = vec2(0.001, 0.0);
	return normalize(vec3(map(p + e.xyy) - map(p - e.xyy), map(p + e.yxy) - map(p - e.yxy), map(p + e.yyx) - map(p - e.yyx)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float t0 = iTime * speed;
	vec3 ro = vec3(1.0 + sin(t0 * 0.7), 1.0 + cos(t0 * 0.5), t0 * 2.0);
	float a = t0 * 0.2;
	vec3 rd = normalize(vec3(uv, 1.0));
	rd.xy = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * rd.xy;
	float t = 0.0;
	for (int i = 0; i < 80; i++) {
		float d = map(ro + rd * t);
		if (d < 0.001 || t > 30.0) {
			break;
		}
		t += d;
	}
	vec3 col = vec3(0.02, 0.0, 0.05);
	if (t < 30.0) {
		vec3 p = ro + rd * t;
		vec3 n = normal_at(p);
		vec3 c = cell_of(p);
		vec3 hue = 0.5 + 0.5 * cos(6.28318 * (dot(c, vec3(0.13, 0.21, 0.07)) + iTime * 0.1 + vec3(0.0, 0.33, 0.67)));
		vec3 l = normalize(vec3(0.5, 0.8, -0.3));
		float diff = max(dot(n, l), 0.0);
		float spec = pow(max(dot(reflect(rd, n), l), 0.0), 32.0);
		float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
		col = hue * (0.2 + diff) + spec + rim * hue.zxy;
		col = mix(col, vec3(0.02, 0.0, 0.05), 1.0 - exp(-t * 0.06));
	}
	fragColor = vec4(pow(col, vec3(0.9)), 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
