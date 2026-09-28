// @title Liquid warp
// Makes the picture ripple and swirl like it's under moving water.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float strength : hint_range(0.0, 0.1, 0.001) = 0.02;
uniform float scale : hint_range(1.0, 30.0, 0.1) = 6.0;
uniform float speed : hint_range(0.0, 4.0, 0.01) = 1.0;

void fragment() {
	vec2 p = UV * vec2(display_aspect, 1.0) * scale;
	float t = TIME * speed;
	vec2 w = vec2(sin(p.y + t + sin(p.x * 0.7 - t * 0.6)), cos(p.x + t * 0.8 + sin(p.y * 0.9 + t * 0.5)));
	w += 0.5 * vec2(sin(p.y * 2.1 - t * 1.3), cos(p.x * 1.9 + t * 1.1));
	vec2 uv = UV + w * strength / vec2(display_aspect, 1.0);
	vec4 c = texture(input_tex, uv);
	// A caustic sheen where the warp bunches up.
	c.rgb += vec3(0.6, 0.8, 1.0) * pow(max(w.x * w.y, 0.0), 3.0) * 0.08;
	COLOR = c;
}
