// @title Neon edges
// Traces the picture's edges in glowing rainbow neon over a darkened copy
// of it (`keep` 0: edges only, on black).
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float glow : hint_range(0.0, 8.0, 0.01) = 3.0;
uniform float width : hint_range(0.5, 4.0, 0.01) = 1.0;
uniform float keep : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float hue_speed : hint_range(0.0, 2.0, 0.01) = 0.2;

float luma_at(vec2 uv) {
	return dot(texture(input_tex, uv).rgb, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 px = width / vec2(textureSize(input_tex, 0));
	float tl = luma_at(UV + px * vec2(-1.0, -1.0));
	float t = luma_at(UV + px * vec2(0.0, -1.0));
	float tr = luma_at(UV + px * vec2(1.0, -1.0));
	float l = luma_at(UV + px * vec2(-1.0, 0.0));
	float r = luma_at(UV + px * vec2(1.0, 0.0));
	float bl = luma_at(UV + px * vec2(-1.0, 1.0));
	float b = luma_at(UV + px * vec2(0.0, 1.0));
	float br = luma_at(UV + px * vec2(1.0, 1.0));
	float gx = tr + 2.0 * r + br - tl - 2.0 * l - bl;
	float gy = bl + 2.0 * b + br - tl - 2.0 * t - tr;
	float e = length(vec2(gx, gy));
	vec4 c = texture(input_tex, UV);
	vec2 d = (UV - 0.5) * vec2(display_aspect, 1.0);
	vec3 neon = 0.5 + 0.5 * cos(6.28318 * (atan(gx, gy) / 6.28318 + length(d) - TIME * hue_speed + vec3(0.0, 0.33, 0.67)));
	vec3 col = c.rgb * keep + neon * e * glow;
	COLOR = vec4(col, c.a);
}
