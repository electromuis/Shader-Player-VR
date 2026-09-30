// @title Blur
// @idle radius <= 0.0
// Blurs the whole picture: `radius` is the blur's reach as a fraction of
// the picture's height (a Gaussian, sigma radius / sqrt(6)). Cheap at a low
// resolution, where it's all blur anyway: a video layer at 25% with this,
// behind the screen, is a glow around the video. A separable blur: six
// one-direction passes, alternating across and down with a shrinking step
// (glsl-fast-gaussian-blur's 9-tap kernel, 5 reads each; the wide early
// steps spread it, the later ones fill in between), all but the last at
// `pass_scale` of the size (one plain pass at radius 0). Colour is
// weighted by alpha, and it spreads past the picture's edge.
// @passes pick(radius > 0.0, 6, 1)
// @reach radius
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/effect_prelude.gdshaderinc"
#include "res://addons/vj_editor/visualizer/fast_gaussian.gdshaderinc"

uniform float radius : hint_range(0.0, 0.5, 0.005) = 0.12;
uniform float pass_scale : hint_range(0.1, 1.0, 0.05) = 0.5;
uniform int pass_index = 0;
uniform int pass_count = 1;

void fragment() {
	// sigma = radius / sqrt(6) (weights exp(-3 d^2) out to `radius`), in UV.
	vec2 sigma = vec2(1.0 / display_aspect, 1.0) * radius * picture_rect.w / sqrt(6.0);
	// The first pass weights colour by alpha, so see-through texels don't
	// darken it; the last divides it back out.
	vec4 c = gaussian_taps(input_tex, UV, gaussian_step_dir(pass_index, pass_count, sigma), pass_index == 0, false);
	COLOR = pass_index == pass_count - 1 ? gaussian_unpremultiply(c) : c;
}
