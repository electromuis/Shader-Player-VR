// @title Image overlay
// @idle opacity <= 0.0
// Puts a picture from an images/ folder over the picture: on top (by its
// alpha), added as light, multiplied, screened, or as a mask that keeps
// the picture where the image is bright and opaque.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/effect_prelude.gdshaderinc"

uniform sampler2D image : source_color, hint_default_transparent, filter_linear_mipmap, repeat_enable;
uniform int mode : hint_enum("Over", "Add", "Multiply", "Screen", "Mask") = 0;
uniform int fit : hint_enum("Contain", "Cover", "Stretch", "Tile") = 0;
uniform float scale : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float offset_x : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float offset_y : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	vec4 c = texture(input_tex, UV);
	// Where this pixel is in the picture (0..1), and the picture's shape.
	vec2 pic = (UV - picture_rect.xy) / picture_rect.zw;
	float pic_aspect = display_aspect * picture_rect.z / picture_rect.w;
	vec2 size = vec2(textureSize(image, 0));
	float image_aspect = size.x / max(size.y, 1.0);
	// The image's size as a fraction of the picture's.
	vec2 extent = vec2(1.0);
	if (fit != 2) {
		extent = vec2(image_aspect / pic_aspect, 1.0);
		bool wider = image_aspect > pic_aspect;
		if ((fit == 0 && wider) || (fit == 1 && !wider)) {
			extent /= extent.x;
		}
	}
	extent *= scale;
	vec2 uv = (pic - 0.5 - vec2(offset_x, -offset_y) * 0.5) / extent + 0.5;
	vec4 img = texture(image, uv);
	if (fit != 3 && (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)) {
		img = vec4(0.0);
	}
	vec3 rgb = c.rgb;
	float alpha = c.a;
	if (mode == 0) {
		rgb = mix(c.rgb, img.rgb, img.a);
		alpha = max(c.a, img.a);
	} else if (mode == 1) {
		rgb = c.rgb + img.rgb * img.a;
	} else if (mode == 2) {
		rgb = c.rgb * mix(vec3(1.0), img.rgb, img.a);
	} else if (mode == 3) {
		rgb = 1.0 - (1.0 - c.rgb) * (1.0 - img.rgb * img.a);
	} else {
		alpha = c.a * dot(img.rgb, vec3(0.299, 0.587, 0.114)) * img.a;
	}
	COLOR = mix(c, vec4(rgb, alpha), opacity);
}
