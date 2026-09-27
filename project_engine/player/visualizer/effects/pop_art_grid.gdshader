// @title Pop-art grid
// Warhol-style pop art: the picture tiled `tiles` × `tiles`, each copy
// posterised into its own bold colour pair.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float tiles : hint_range(1.0, 6.0, 1.0) = 2.0;
uniform float levels : hint_range(2.0, 8.0, 1.0) = 3.0;
uniform float hue_speed : hint_range(0.0, 1.0, 0.01) = 0.05;

void fragment() {
	vec2 size = max(picture_rect.zw, vec2(0.0001));
	vec2 p = (UV - picture_rect.xy) / size;
	vec2 cell = floor(p * tiles);
	vec2 q = fract(p * tiles);
	vec4 c = texture(input_tex, picture_rect.xy + q * size);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float step_l = floor(l * levels + 0.5) / levels;
	float h = (cell.x + cell.y * tiles) * 0.29 + TIME * hue_speed;
	vec3 dark = 0.5 + 0.5 * cos(6.28318 * (h + vec3(0.0, 0.33, 0.67)));
	vec3 light = 0.5 + 0.5 * cos(6.28318 * (h + 0.45 + vec3(0.0, 0.33, 0.67)));
	vec3 col = mix(dark * 0.25, light, step_l);
	col = mix(col, vec3(1.0), step(0.95, step_l) * 0.5);
	COLOR = vec4(col, texture(input_tex, UV).a);
}
