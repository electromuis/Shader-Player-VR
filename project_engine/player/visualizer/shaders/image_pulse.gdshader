// @title Image pulse
// A picture from an images/ folder that moves with the music: the bass
// punches it in, the mids ripple it, the highs split its colours and the
// level flashes it. Outside the picture (and a transparent one) is black,
// so the Add or Black blend puts it over what's behind.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform sampler2D image : source_color, hint_default_transparent, filter_linear_mipmap, repeat_enable;
uniform int fit : hint_enum("Contain", "Cover", "Tile") = 0;
uniform float scale : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float spin : hint_range(-1.0, 1.0, 0.01) = 0.0;

group_uniforms reactive;
uniform float punch : hint_range(0.0, 0.5, 0.01) = 0.15;
uniform float ripple : hint_range(0.0, 0.1, 0.001) = 0.02;
uniform float split : hint_range(0.0, 0.05, 0.001) = 0.01;
uniform float flash : hint_range(0.0, 2.0, 0.01) = 0.5;
group_uniforms;

// The image at `p` (screen heights from the centre, y up) over black, its
// half-size `half_ext` in the same units; nothing outside unless tiled.
vec3 sample_image(vec2 p, vec2 half_ext) {
	vec2 uv = p / (2.0 * half_ext) + 0.5;
	uv.y = 1.0 - uv.y;
	vec4 c = texture(image, uv);
	if (fit != 2 && (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)) {
		return vec3(0.0);
	}
	return c.rgb * c.a;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	float screen_aspect = iResolution.x / iResolution.y;
	vec2 size = vec2(textureSize(image, 0));
	float image_aspect = size.x / max(size.y, 1.0);
	// Half-size in screen heights: fit the width or the height.
	vec2 half_ext = vec2(image_aspect, 1.0) * 0.5;
	bool wider = image_aspect > screen_aspect;
	if ((fit == 0 && wider) || (fit == 1 && !wider)) {
		half_ext *= screen_aspect / image_aspect;
	}
	half_ext *= scale * (1.0 + punch * audio_bass);

	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float a = spin * iTime;
	p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	float r = length(p);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	p += dir * sin(r * 30.0 - iTime * 6.0) * ripple * audio_mid;

	vec2 shift = dir * split * audio_high;
	vec3 c = vec3(sample_image(p + shift, half_ext).r,
			sample_image(p, half_ext).g,
			sample_image(p - shift, half_ext).b);
	fragColor = vec4(c * (1.0 + flash * audio_level), 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
