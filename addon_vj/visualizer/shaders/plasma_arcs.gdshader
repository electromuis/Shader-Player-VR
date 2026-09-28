// @title Plasma arcs
// Electric arcs crackling between wandering poles; louder is wilder.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform int bolts : hint_range(1, 8) = 5;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	vec3 col = vec3(0.01, 0.0, 0.03);
	float jitter = 0.08 + audio_level * react * 0.12;
	for (int i = 0; i < bolts; i++) {
		float fi = float(i);
		float ang = fi * 6.28318 / float(bolts) + iTime * 0.3;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 perp = vec2(-dir.y, dir.x);
		float along = dot(p, dir);
		float across = dot(p, perp);
		float s = along * 8.0;
		float tt = floor(iTime * 12.0) + fi * 17.0;
		float off = (noise(s + tt) - 0.5) * jitter * 2.0 + (noise(s * 4.0 + tt * 1.3) - 0.5) * jitter * 0.6;
		float env = smoothstep(0.0, 0.1, along) * smoothstep(0.9, 0.5, along);
		float d = abs(across - off * env);
		vec3 c = 0.5 + 0.5 * cos(6.28318 * (fi / float(bolts) + iTime * 0.05 + vec3(0.0, 0.33, 0.67)));
		col += (c * 0.004 / (d + 0.002) + vec3(1.0) * 0.0015 / (d + 0.001)) * env;
	}
	float core = length(p);
	col += vec3(0.8, 0.7, 1.0) * 0.03 / (core + 0.02) * (1.0 + audio_bass * react);
	col = 1.0 - exp(-col);
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
