// @title Droste spiral
// A Droste-style complex-log spiral: tiles that repeat inward forever,
// spinning and zooming without end.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float tiles : hint_range(2.0, 16.0, 2.0) = 6.0;
uniform float speed : hint_range(0.0, 3.0, 0.01) = 0.6;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	// log-polar: (log r, turns); shearing log r by the angle turns rings into
	// one spiral. Every shift across the angle's wrap is a whole number of
	// (even, for the checker) cells, so there's no seam.
	float turns = atan(p.y, p.x) / 6.28318;
	float lr = log(length(p) + 1e-4);
	vec2 s = vec2(lr - turns, turns * tiles + lr * 0.5);
	s.x -= iTime * speed;
	vec2 cell = floor(s * vec2(2.0, 1.0));
	vec2 f = fract(s * vec2(2.0, 1.0)) - 0.5;
	float check = mod(cell.x + cell.y, 2.0);
	float blob = smoothstep(0.33 + audio_bass * react * 0.08, 0.28, length(f * vec2(1.0, 0.8)));
	float hue = cell.x * 0.5 + cell.y / tiles;
	vec3 a = 0.5 + 0.5 * cos(6.28318 * (hue * 0.5 + vec3(0.0, 0.33, 0.67)));
	vec3 b = 0.5 + 0.5 * cos(6.28318 * (hue * 0.5 + 0.5 + vec3(0.0, 0.33, 0.67)));
	vec3 col = mix(a, b, check);
	col = mix(col * 0.6, b.zxy, blob);
	col *= smoothstep(0.0, 0.03, length(p));
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
