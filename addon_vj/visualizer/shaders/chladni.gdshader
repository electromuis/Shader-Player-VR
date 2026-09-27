// @title Chladni figures
// Chladni plate figures: the sand patterns of a vibrating plate, morphing
// between modes; the spectrum picks which modes ring.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float sharpness : hint_range(0.01, 0.3, 0.005) = 0.12;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float mode(vec2 p, float n, float m) {
	return cos(n * 3.14159 * p.x) * cos(m * 3.14159 * p.y) - cos(m * 3.14159 * p.x) * cos(n * 3.14159 * p.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y * 2.0;
	float t = iTime * 0.25;
	float n1 = 2.0 + floor(mod(t, 5.0));
	float n2 = 3.0 + floor(mod(t * 0.7 + 2.0, 6.0));
	float k = smoothstep(0.3, 0.7, fract(t));
	float b = texture(iChannel0, vec2(0.05, 0.25)).x;
	float h = texture(iChannel0, vec2(0.4, 0.25)).x;
	float v = mix(mode(p, n1, n2), mode(p, n2, n1 + 1.0), k);
	v += (b * 0.3 * mode(p, 1.0, 4.0) + h * 0.3 * mode(p, 5.0, 7.0)) * react;
	float sand = smoothstep(sharpness, 0.0, abs(v));
	vec3 hue = 0.5 + 0.5 * cos(6.28318 * (length(p) * 0.4 + iTime * 0.1 + vec3(0.0, 0.33, 0.67)));
	float glow = exp(-abs(v) * 6.0);
	vec3 col = hue * sand * 1.5 + hue.zxy * glow * 0.35;
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
