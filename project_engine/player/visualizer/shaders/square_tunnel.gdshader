// @title Square tunnel
// A square tunnel of neon frames twisting as it rushes past; each frame
// flashes with its own band.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 4.0, 0.01) = 1.5;
uniform float twist : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float gain : hint_range(0.0, 4.0, 0.01) = 1.5;
uniform float frames : hint_range(1.0, 8.0, 0.1) = 3.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	// Each frame turns by its depth, so the tunnel corkscrews.
	float approx = 0.2 / max(max(abs(p.x), abs(p.y)), 0.001);
	float a = (approx + iTime * speed) * twist;
	vec2 q = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	float sq = max(max(abs(q.x), abs(q.y)), 0.001);
	float z = 0.2 / sq;
	float zz = (z + iTime * speed) * frames;
	float ring = floor(zz);
	float f = fract(zz);
	// Distance to the nearest frame in pixels, so lines stay crisp at any depth.
	float px = min(f, 1.0 - f) / max(fwidth(zz), 1e-4);
	float lvl = texture(iChannel0, vec2(fract(ring * 0.137), 0.25)).x * gain;
	float thick = 1.5 + 4.0 * lvl;
	float line = smoothstep(thick + 1.0, thick, px);
	float glow = exp(-px / (6.0 + 10.0 * lvl));
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (ring * 0.08 + vec3(0.0, 0.33, 0.67)));
	vec3 outc = col * (line + glow * 0.5) * (0.4 + lvl) * exp(-z * 0.05);
	outc += (0.5 + 0.5 * cos(6.28318 * (iTime * 0.1 + vec3(0.0, 0.33, 0.67)))) * 0.01 / sq;
	fragColor = vec4(outc, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
