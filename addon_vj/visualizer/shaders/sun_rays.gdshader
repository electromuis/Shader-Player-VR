// @title Sun rays
// A radiant sun: rays around a glowing core, each ray's length its band of
// the spectrum, mirrored so it stays symmetric.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float rays : hint_range(8.0, 128.0, 1.0) = 64.0;
uniform float gain : hint_range(0.0, 4.0, 0.01) = 1.5;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	float r = length(p);
	float a = atan(p.y, p.x) / 3.14159;
	float ma = abs(a);
	float idx = floor(ma * rays * 0.5);
	float f = fract(ma * rays * 0.5);
	float lvl = texture(iChannel0, vec2(pow(idx / (rays * 0.5), 1.5) * 0.8, 0.25)).x * gain;
	float len = 0.15 + lvl * 0.3;
	float ray = smoothstep(0.5, 0.2, abs(f - 0.5)) * smoothstep(len, len - 0.05, r) * smoothstep(0.1, 0.14, r);
	vec3 c = 0.5 + 0.5 * cos(6.28318 * (idx / rays + iTime * 0.1 + vec3(0.0, 0.33, 0.67)));
	vec3 col = c * ray * (0.6 + r * 2.0);
	col += vec3(1.0, 0.7, 0.3) * smoothstep(0.12, 0.09, r);
	col += vec3(1.0, 0.4, 0.8) * 0.02 / max(abs(r - 0.11), 0.004) * 0.3;
	col += c * 0.03 / (r + 0.05);
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
