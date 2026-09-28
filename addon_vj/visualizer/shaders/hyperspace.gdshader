// @title Hyperspace
// Hyperspace jump: coloured star streaks stretching out of the centre.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float density : hint_range(0.2, 3.0, 0.01) = 1.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.28318 + 0.5;
	vec3 col = vec3(0.0);
	float warp = speed * (1.0 + audio_bass * react * 1.5);
	for (int layer = 0; layer < 4; layer++) {
		float fl = float(layer);
		float lanes = floor(180.0 * density * (1.0 + fl * 0.5));
		float lane = floor(a * lanes);
		float h = hash(lane * 7.13 + fl * 91.7);
		// Each star rides outward along its lane; its depth loops.
		float z = fract(h * 13.0 + iTime * warp * (0.25 + 0.2 * h));
		float head = z * z * 1.2;
		float tail = head - 0.05 - z * 0.35 * warp;
		float along = smoothstep(tail, head, r) * step(r, head);
		float across = 1.0 - abs(fract(a * lanes) - 0.5) * 2.0;
		across = smoothstep(0.4, 1.0, across);
		vec3 sc = 0.6 + 0.4 * cos(6.28318 * (h + iTime * 0.05 + vec3(0.0, 0.33, 0.67)));
		col += sc * along * across * z * 2.0 * step(0.7, hash(lane + fl * 3.3));
	}
	col += vec3(0.4, 0.3, 1.0) * 0.03 / max(r, 0.01) * (1.0 + audio_bass * react);
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
