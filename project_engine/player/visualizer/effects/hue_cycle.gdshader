// @title Hue cycle
// Rotates the picture's hues over time, in waves across it, and boosts
// saturation: a slow acid colour shift.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 2.0, 0.01) = 0.2;
uniform float spread : hint_range(0.0, 3.0, 0.01) = 0.5;
uniform float saturation : hint_range(0.0, 3.0, 0.01) = 1.6;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 c = texture(input_tex, UV);
	vec3 hsv = rgb2hsv(c.rgb);
	vec2 d = (UV - 0.5) * vec2(display_aspect, 1.0);
	hsv.x = fract(hsv.x + TIME * speed + length(d) * spread);
	hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
	COLOR = vec4(hsv2rgb(hsv), c.a);
}
