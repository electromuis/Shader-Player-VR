// @title Kaleido tunnel
// A kaleidoscopic tunnel: polar coordinates folded into mirrored segments,
// rushing toward you. The mids speed it up.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float segments : hint_range(2.0, 16.0, 1.0) = 8.0;
uniform float speed : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

vec3 pal(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float r = length(p);
	float a = atan(p.y, p.x);
	float seg = 6.28318 / segments;
	a = abs(mod(a + iTime * 0.2, seg) - seg * 0.5);
	float z = 0.3 / max(r, 0.001) + iTime * speed * (1.0 + audio_mid * react);
	vec2 q = vec2(a * 3.0, z);
	float pat = sin(q.x * 6.0 + sin(q.y * 2.0) * 2.0) * sin(q.y * 4.0 + q.x * 2.0);
	pat += 0.5 * sin(q.x * 13.0 - q.y * 3.0);
	vec3 col = pal(pat * 0.3 + z * 0.1);
	col *= smoothstep(0.0, 0.25, r) * (0.6 + 0.6 * pat);
	col += vec3(1.0, 0.6, 1.0) * 0.02 / max(r, 0.02) * (0.5 + audio_bass * react);
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
