// @title Match video brightness
// @idle strength <= 0.0
// Scales the picture's brightness to follow the playing video's: when the
// video goes dark the picture dims with it, when it's bright the picture
// brightens. Put it on a layer so it sits with the video instead of
// glaring over a dark scene.
//
// `relative` on: the picture's own average brightness is brought to the
// video's (times `level`), so a dim shader and a bright one both end up
// as bright as the video. Off: the picture is just multiplied by the
// video's brightness (times `level`), keeping its own bright and dark.
// `strength` blends from the picture as it was (0) to fully matched (1);
// `max_gain` caps how far a dark picture gets boosted.
//
// `match_by` picks what counts as brightness: Luma (weighted to how bright
// each colour looks, so saturated blue counts as dark), Value (HSV: the
// brightest channel, so any fully saturated colour counts as bright),
// Lightness (HSL: halfway between the brightest and darkest channel) or
// Average (of the three channels).
//
// Both averages are taken over a grid of `samples` × `samples` taps (the
// whole video frame, both eyes of a stereo one; the picture weighted by
// its alpha, so see-through parts don't count), in a tiny prepass that the
// full-size pass reads once. They're stored as square roots, which keeps
// the dark end precise in an 8-bit pass.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform bool relative = true;
uniform int match_by : hint_enum("Luma", "Value (HSV)", "Lightness (HSL)", "Average") = 0;
uniform float level : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float max_gain : hint_range(1.0, 16.0, 0.1) = 4.0;
uniform int samples : hint_range(4, 32) = 12;
// The measuring prepass's size: the averages come out the same at any.
uniform float prepass_scale : hint_range(0.05, 1.0, 0.05) = 0.05;
// The playing video's whole frame (see effect_prelude.gdshaderinc).
uniform sampler2D video_tex : hint_default_transparent, filter_linear, repeat_disable;
uniform sampler2D prepass_tex : filter_nearest, repeat_disable;
uniform bool prepass = false;

// The picked brightness measure (see match_by). Each scales with the
// colour, so multiplying by the gain moves it by just that.
float brightness(vec3 c) {
	switch (match_by) {
		case 1:
			return max(max(c.r, c.g), c.b);
		case 2:
			return 0.5 * (max(max(c.r, c.g), c.b) + min(min(c.r, c.g), c.b));
		case 3:
			return (c.r + c.g + c.b) / 3.0;
		default:
			return dot(c, vec3(0.2126, 0.7152, 0.0722));
	}
}

// The prepass: (sqrt of the video's mean brightness, sqrt of the picture's,
// whether there's a video at all, 1). Every texel holds the same values.
vec4 measure() {
	float n = float(samples);
	float video = 0.0;
	float video_a = 0.0;
	float pic = 0.0;
	float pic_a = 0.0;
	for (int y = 0; y < samples; y++) {
		for (int x = 0; x < samples; x++) {
			vec2 g = (vec2(float(x), float(y)) + 0.5) / n;
			vec4 v = texture(video_tex, g);
			video += brightness(v.rgb) * v.a;
			video_a += v.a;
			vec4 c = texture(input_tex, picture_rect.xy + g * picture_rect.zw);
			pic += brightness(c.rgb) * c.a;
			pic_a += c.a;
		}
	}
	float has_video = video_a > 0.0 ? 1.0 : 0.0;
	return vec4(sqrt(video / max(video_a, 0.0001)), sqrt(pic / max(pic_a, 0.0001)), has_video, 1.0);
}

void fragment() {
	if (prepass) {
		COLOR = measure();
	} else {
		vec4 c = texture(input_tex, UV);
		vec4 m = texture(prepass_tex, vec2(0.5));
		float video = m.r * m.r;
		float pic = m.g * m.g;
		float gain = relative ? video * level / max(pic, 0.0001) : video * level;
		// Without a video there's nothing to match: leave the picture be.
		gain = mix(1.0, min(gain, max_gain), strength * m.b);
		COLOR = vec4(c.rgb * gain, c.a);
	}
}
