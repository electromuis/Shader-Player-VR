// @title False colour
// Maps the picture's brightness through a cycling rainbow, like a thermal
// camera on acid. `bands` repeats the rainbow over the brightness range.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float bands : hint_range(0.5, 8.0, 0.01) = 1.5;
uniform float speed : hint_range(0.0, 2.0, 0.01) = 0.15;
uniform float mix_amount : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	vec4 c = texture(input_tex, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 fc = 0.5 + 0.5 * cos(6.28318 * (l * bands - TIME * speed + vec3(0.0, 0.33, 0.67)));
	fc *= 0.3 + 0.9 * l;
	COLOR = vec4(mix(c.rgb, fc, mix_amount), c.a);
}
