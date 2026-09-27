// @title Cosmic nebula
// Volumetric nebula clouds glowing in magenta, teal and gold, drifting past
// a field of stars.
// @resolution 1280x720
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 2.0, 0.01) = 0.3;
uniform float density : hint_range(0.2, 3.0, 0.01) = 1.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	vec3 ro = vec3(0.0, 0.0, iTime * speed);
	vec3 rd = normalize(vec3(uv, 1.0));
	vec3 col = vec3(0.0);
	float trans = 1.0;
	for (int i = 0; i < 40; i++) {
		float t = 0.2 + float(i) * 0.12;
		vec3 p = ro + rd * t;
		float d = fbm(p * 1.5) - 0.55;
		d = max(d, 0.0) * density * 3.0;
		if (d > 0.0) {
			vec3 c = 0.5 + 0.5 * cos(6.28318 * (fbm(p * 0.7) * 1.5 + t * 0.1 + vec3(0.0, 0.3, 0.6)));
			c *= 1.0 + audio_bass * react * 0.8;
			col += trans * c * c * d * 0.3;
			trans *= exp(-d * 0.3);
		}
		if (trans < 0.02) {
			break;
		}
	}
	vec2 sg = floor(fragCoord / 2.0);
	float s = fract(sin(dot(sg, vec2(12.9898, 78.233))) * 43758.5453);
	col += step(0.998, s) * trans * vec3(1.0);
	col = 1.0 - exp(-col * 1.4);
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
