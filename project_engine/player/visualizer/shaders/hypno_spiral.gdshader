// @title Hypno spiral
// A rainbow logarithmic spiral that winds inward forever.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float arms : hint_range(1.0, 12.0, 1.0) = 5.0;
uniform float twist : hint_range(0.5, 10.0, 0.1) = 4.0;
uniform float speed : hint_range(0.0, 4.0, 0.01) = 1.5;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float r = length(p);
	float a = atan(p.y, p.x);
	float s = a * arms + log(r + 0.001) * twist * 2.0 - iTime * speed;
	float band = sin(s);
	float hue = log(r + 0.001) * 0.3 - iTime * 0.1 + a / 6.28318;
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (hue + vec3(0.0, 0.33, 0.67)));
	col *= smoothstep(-0.2, 0.2, band) * 0.85 + 0.15;
	col *= smoothstep(0.0, 0.08, r);
	col += 0.15 * audio_bass * react * (1.0 - smoothstep(0.0, 0.5, r));
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
