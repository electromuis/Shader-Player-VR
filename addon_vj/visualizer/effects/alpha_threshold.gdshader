// @title Alpha threshold
// Hides the faint parts: alpha below `threshold` becomes 0, the rest keeps
// its own alpha. Above the threshold it fades back in over `feather` (in
// alpha) so the cut's edge stays soft; feather 0 gives a hard cut. Cleans
// up the haze a Key black or a blur leaves.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/effect_prelude.gdshaderinc"

uniform float threshold : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float feather : hint_range(0.0, 1.0, 0.01) = 0.1;

void fragment() {
	vec4 c = texture(input_tex, UV);
	float keep = smoothstep(threshold, threshold + max(feather, 0.0001), c.a);
	COLOR = vec4(c.rgb, c.a * keep);
}
