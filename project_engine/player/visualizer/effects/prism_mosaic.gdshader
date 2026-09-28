// @title Prism mosaic
// Breaks the picture into glowing rounded tiles, each tinted by a rainbow
// wave washing across the grid.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float tile_size : hint_range(0.005, 0.1, 0.001) = 0.025;
uniform float tint : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float gap : hint_range(0.0, 0.45, 0.01) = 0.12;
uniform float wave_speed : hint_range(0.0, 3.0, 0.01) = 0.5;

void fragment() {
	vec2 grid = vec2(display_aspect, 1.0) / tile_size;
	vec2 cell = floor(UV * grid);
	vec2 f = fract(UV * grid) - 0.5;
	vec4 c = texture(input_tex, (cell + 0.5) / grid);
	vec3 wave = 0.5 + 0.5 * cos(6.28318 * ((cell.x + cell.y) * 0.02 - TIME * wave_speed + vec3(0.0, 0.33, 0.67)));
	vec3 col = mix(c.rgb, c.rgb * wave * 1.8, tint);
	// Rounded tile with a soft bevel.
	vec2 a = abs(f);
	float d = length(max(a - (0.5 - gap - 0.1), 0.0)) - 0.1;
	float inside = smoothstep(0.02, -0.02, d);
	float bevel = 1.0 + 0.4 * (f.x - f.y) * inside;
	COLOR = vec4(col * inside * bevel, c.a);
}
