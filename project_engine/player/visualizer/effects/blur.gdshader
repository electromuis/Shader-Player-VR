// @title Blur
// Blurs the whole picture: `radius` is the blur's reach as a fraction of
// the picture's height. Cheap at a low resolution, where it's all blur
// anyway: a video layer at 25% with this, behind the screen, is a glow
// around the video. Colour is weighted by alpha, so cut-out parts don't
// darken what's next to them, and it spreads past the picture's edge.
// @reach radius
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float radius : hint_range(0.0, 0.5, 0.005) = 0.12;

const int SAMPLES = 128;
const float GOLDEN_ANGLE = 2.39996323;

void fragment() {
	if (radius <= 0.0) {
		COLOR = texture(input_tex, UV);
	} else {
		vec2 scale = vec2(radius / display_aspect, radius) * picture_rect.w;
		// Gaussian-weighted disc on a golden-angle spiral, turned per pixel so
		// the sparse taps average out instead of showing as a pattern.
		float spin = 6.2831853 * fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		vec3 sum_rgb = vec3(0.0);
		float sum_a = 0.0;
		float sum_w = 0.0;
		for (int i = 0; i < SAMPLES; i++) {
			float t = (float(i) + 0.5) / float(SAMPLES);
			float d = sqrt(t);
			float ang = float(i) * GOLDEN_ANGLE + spin;
			vec4 s = texture(input_tex, UV + vec2(cos(ang), sin(ang)) * d * scale);
			float w = exp(-3.0 * d * d);
			sum_rgb += s.rgb * s.a * w;
			sum_a += s.a * w;
			sum_w += w;
		}
		COLOR = vec4(sum_a > 0.0 ? sum_rgb / sum_a : vec3(0.0), sum_a / sum_w);
	}
}
