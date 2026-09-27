// @title Rounded corners
// Rounds the picture's outline, cutting away in alpha what falls outside.
// `roundness` 0 is the plain rectangle; raising it bulges the corners in
// smoothly (a squircle at 0.5) until at 1 the picture is the oval that fits
// inside it. `bulge` bows the sides out, pulling the corners in, like an
// old CRT's screen (roundness 0.25, bulge 0.08 or so). `feather` is the
// width of the soft edge, in picture heights; for a wide, blurry edge put
// an Edge blur after it. Effects after it (a Glow) follow the rounded
// outline. With a margin (for Glow) the outline is the picture's, not the margin's.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/effect_prelude.gdshaderinc"

uniform float roundness : hint_range(0.0, 1.0, 0.005) = 0.3;
uniform float bulge : hint_range(0.0, 0.5, 0.005) = 0.0;
uniform float feather : hint_range(0.0, 0.3, 0.001) = 0.003;

void fragment() {
	vec4 c = texture(input_tex, UV);
	vec2 size = max(picture_rect.zw, vec2(0.0001));
	// The picture's half-size and this point's offset from its centre, in
	// picture heights.
	vec2 half_ext = vec2(display_aspect * size.x / size.y, 1.0) * 0.5;
	vec2 pos = ((UV - picture_rect.xy) / size - 0.5) * half_ext * 2.0;
	vec2 edge;
	vec2 normal;
	float d = outline(pos, half_ext, vec2(roundness, bulge), edge, normal);
	float mask = clamp(0.5 - d / max(feather, 0.0005), 0.0, 1.0);
	COLOR = vec4(c.rgb, c.a * mask);
}
