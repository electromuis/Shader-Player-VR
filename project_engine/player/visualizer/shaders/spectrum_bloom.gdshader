// @title Spectrum bloom
// The spectrum wrapped into a blooming circle: a rainbow flower whose
// petals are the frequencies, with the waveform traced around its heart.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float gain : hint_range(0.0, 4.0, 0.01) = 1.5;
uniform float symmetry : hint_range(1.0, 8.0, 1.0) = 2.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.28318 + 0.5;
	// Fold the angle so the spectrum repeats `symmetry` times, mirrored.
	float fa = abs(fract(a * symmetry + iTime * 0.02) * 2.0 - 1.0);
	float lvl = texture(iChannel0, vec2(pow(fa, 1.5) * 0.8, 0.25)).x * gain;
	float wave = texture(iChannel0, vec2(fa, 0.75)).x - 0.5;
	float outer = 0.15 + lvl * 0.25;
	vec3 c = 0.5 + 0.5 * cos(6.28318 * (fa + iTime * 0.1 + vec3(0.0, 0.33, 0.67)));
	vec3 col = c * smoothstep(outer, outer - 0.01, r) * smoothstep(0.1, outer, r) * 1.2;
	col += c * 0.004 / max(abs(r - outer), 0.002);
	float wr = 0.08 + wave * 0.08;
	col += vec3(1.0) * 0.002 / max(abs(r - wr), 0.001);
	col += c.zxy * 0.02 / (r + 0.02) * lvl;
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
