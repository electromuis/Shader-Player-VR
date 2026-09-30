// @title Edge blur
// @idle radius <= 0.0
// Softens the edges of whatever is already cut out by alpha (by Key black,
// an Oval mask, or a shader's own transparency): alpha is blurred over
// `radius`, the width of the soft edge as a fraction of the picture's
// height. With `inward` the fade stays inside the original shape (the edge
// goes to 0, `radius` in is fully back); without, it's centred on the edge
// and also spreads out, taking the nearby visible colour. Solid areas are
// untouched. The picture's own border counts as an edge too (past it is
// transparent), so inward softens a plain rectangle.
// The blur is a separable Gaussian (fast_gaussian.gdshaderinc) in six
// passes, all but the last at `pass_scale` of the size; the last lays the
// blurred alpha over the full-size picture.
// @passes pick(radius > 0.0, 6, 1)
// @reach pick(inward, 0.0, radius * 0.5)
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/effect_prelude.gdshaderinc"
#include "res://addons/vj_editor/visualizer/fast_gaussian.gdshaderinc"

uniform bool inward = true;
uniform float radius : hint_range(0.0, 0.5, 0.005) = 0.05;
uniform float pass_scale : hint_range(0.1, 1.0, 0.05) = 0.5;
uniform int pass_index = 0;
uniform int pass_count = 1;
// The picture this effect started from (the chain sets it on every pass).
uniform sampler2D pass_source_tex : filter_linear, repeat_disable;

void fragment() {
	float r = inward ? radius : radius * 0.5;
	if (r <= 0.0) {
		COLOR = texture(input_tex, UV);
	} else {
		// sigma = r / sqrt(8) (weights exp(-4 d^2) out to `r`), in UV,
		// in picture-height units so the edge is the same width both ways.
		vec2 sigma = vec2(1.0 / display_aspect, 1.0) * r * picture_rect.w / sqrt(8.0);
		vec4 b = gaussian_taps(input_tex, UV, gaussian_step_dir(pass_index, pass_count, sigma), pass_index == 0, true);
		if (pass_index < pass_count - 1) {
			COLOR = b;
		} else {
			vec4 c = pass_count > 1 ? texture(pass_source_tex, UV) : texture(input_tex, UV);
			float blurred = b.a;
			if (inward) {
				// A straight edge blurs to 0.5 on the edge itself; remap so
				// that's 0 and never add alpha where there was none.
				COLOR = vec4(c.rgb, min(c.a, clamp(blurred * 2.0 - 1.0, 0.0, 1.0)));
			} else {
				// Outside the original shape there's no colour of its own,
				// so use the alpha-weighted average of what's nearby.
				vec3 near = gaussian_unpremultiply(b).rgb;
				COLOR = vec4(mix(near, c.rgb, c.a), blurred);
			}
		}
	}
}
