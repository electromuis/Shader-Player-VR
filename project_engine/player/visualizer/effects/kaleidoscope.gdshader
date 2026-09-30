// @title Kaleidoscope
// @idle mix_amount <= 0.0
// Folds the picture into a turning kaleidoscope: `segments` mirrored
// wedges around the centre, `zoom` into the source, `spin` turns per second.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float segments : hint_range(2.0, 24.0, 1.0) = 8.0;
uniform float zoom : hint_range(0.2, 4.0, 0.01) = 1.2;
uniform float spin : hint_range(-1.0, 1.0, 0.01) = 0.05;
uniform float mix_amount : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	vec2 size = max(picture_rect.zw, vec2(0.0001));
	vec2 p = (UV - picture_rect.xy) / size;
	float aspect = display_aspect * size.x / size.y;
	vec2 c = (p - 0.5) * vec2(aspect, 1.0);
	float r = length(c) / zoom;
	float a = atan(c.y, c.x) + TIME * spin * 6.28318;
	float seg = 6.28318 / segments;
	a = abs(mod(a, seg) - seg * 0.5);
	vec2 q = vec2(cos(a), sin(a)) * r / vec2(aspect, 1.0) + 0.5;
	// Mirror back in rather than smearing the edge.
	q = 1.0 - abs(mod(q, 2.0) - 1.0);
	vec4 k = texture(input_tex, picture_rect.xy + q * size);
	vec4 o = texture(input_tex, UV);
	COLOR = vec4(mix(o.rgb, k.rgb, mix_amount), o.a);
}
