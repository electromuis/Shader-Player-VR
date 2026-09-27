// @title Fast blur
// Blurs the whole picture like Blur (`radius` is its reach as a fraction of
// the picture's height, the same Gaussian), but as a separable blur: six
// one-direction passes, alternating across and down with a shrinking step
// (glsl-fast-gaussian-blur's 9-tap kernel, 5 reads each; the wide early
// steps spread it, the later ones fill in between), all but the last at
// `pass_scale` of the size. Smooth where Blur's 128 scattered taps get
// grainy. Colour is weighted by alpha, and it spreads past the picture's
// edge.
// @passes 6
// @reach radius
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float radius : hint_range(0.0, 0.5, 0.005) = 0.12;
uniform float pass_scale : hint_range(0.1, 1.0, 0.05) = 0.5;
uniform int pass_index = 0;
uniform int pass_count = 1;

// The 9-tap kernel as 5 linear-filtered reads: offsets and weights.
const float OFF1 = 1.3846153846;
const float OFF2 = 3.2307692308;
const float W0 = 0.2270270270;
const float W1 = 0.3162162162;
const float W2 = 0.0702702703;

vec4 tap(vec2 uv) {
	vec4 c = texture(input_tex, uv);
	// The first pass premultiplies, so see-through texels don't darken it.
	if (pass_index == 0) {
		c.rgb *= c.a;
	}
	return c;
}

void fragment() {
	// Blur's Gaussian (weights exp(-3 d^2) out to `radius`): sigma = radius
	// / sqrt(6), in UV; the passes along each axis add their variances.
	float sigma = radius * picture_rect.w / sqrt(6.0);
	int axis = pass_index % 2;  // 0: across, 1: down
	float sum = 0.0;
	for (int i = axis; i < pass_count; i += 2) {
		float k = float(pass_count - i);
		sum += k * k;
	}
	float unit_var = 2.0 * (W1 * OFF1 * OFF1 + W2 * OFF2 * OFF2);
	float step_uv = sigma / (axis == 0 ? display_aspect : 1.0) / sqrt(unit_var * max(sum, 1.0));
	vec2 dir = (axis == 0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0)) * step_uv * float(pass_count - pass_index);
	vec4 c = tap(UV) * W0;
	c += (tap(UV + dir * OFF1) + tap(UV - dir * OFF1)) * W1;
	c += (tap(UV + dir * OFF2) + tap(UV - dir * OFF2)) * W2;
	if (pass_index == pass_count - 1) {
		c.rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
	}
	COLOR = c;
}
