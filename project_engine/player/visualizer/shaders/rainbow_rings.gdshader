// @title Rainbow rings
// Concentric rings, each lit by its own band of the spectrum.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float rings : hint_range(4.0, 64.0, 1.0) = 24.0;
uniform float gain : hint_range(0.0, 4.0, 0.01) = 1.5;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float r = length(p) * 1.25;
	float idx = floor(r * rings);
	float f = fract(r * rings);
	float band = pow(idx / rings, 1.5);
	float lvl = texture(iChannel0, vec2(band, 0.25)).x * gain;
	float wob = sin(atan(p.y, p.x) * 6.0 + iTime * 2.0 + idx) * 0.1 * lvl;
	float ring = smoothstep(0.5, 0.0, abs(f - 0.5 + wob) - 0.15);
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (idx / rings * 1.5 - iTime * 0.1 + vec3(0.0, 0.33, 0.67)));
	col *= ring * (0.25 + lvl + 0.2 * sin(iTime + idx * 0.7));
	col *= step(r, 1.0 + 0.5 / rings);
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
