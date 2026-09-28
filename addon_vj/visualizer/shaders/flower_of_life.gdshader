// @title Flower of life
// A sacred-geometry mandala: overlapping circle petals turning in layers,
// in glowing neon lines.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float petals : hint_range(3.0, 24.0, 1.0) = 12.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float ring(vec2 p, vec2 c, float r) {
	return abs(length(p - c) - r);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 4; layer++) {
		float fl = float(layer);
		float rad = 0.08 + fl * 0.07 + audio_bass * react * 0.01;
		float rot = iTime * 0.1 * (mod(fl, 2.0) * 2.0 - 1.0) * (1.0 + fl * 0.3);
		// Fold into one petal's sector, then draw that petal's circle.
		float a = atan(p.y, p.x) + rot;
		float seg = 6.28318 / petals;
		float k = floor(a / seg + 0.5);
		float ca = k * seg - rot;
		vec2 c = vec2(cos(ca), sin(ca)) * rad;
		float d = min(ring(p, c, rad), ring(p, vec2(cos(ca + seg), sin(ca + seg)) * rad, rad));
		d = min(d, ring(p, vec2(cos(ca - seg), sin(ca - seg)) * rad, rad));
		vec3 c1 = 0.5 + 0.5 * cos(6.28318 * (fl * 0.2 + iTime * 0.05 + length(p) + vec3(0.0, 0.33, 0.67)));
		col += c1 * 0.0025 / (d + 0.002);
	}
	col += vec3(1.0, 0.8, 0.5) * 0.01 / (length(p) + 0.01) * (0.5 + audio_bass * react);
	col *= smoothstep(0.75, 0.4, length(p));
	col = 1.0 - exp(-col);
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
