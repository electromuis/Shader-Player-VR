// @title Silk ribbons
// Glowing silk ribbons weaving across the screen, each riding the waveform.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform int ribbons : hint_range(2, 20) = 10;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = fragCoord / iResolution.xy;
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	vec3 col = vec3(0.0);
	float wave = (texture(iChannel0, vec2(uv.x, 0.75)).x - 0.5) * react;
	for (int i = 0; i < ribbons; i++) {
		float fi = float(i) / float(ribbons);
		float y = 0.25 * sin(p.x * (2.0 + fi * 3.0) + iTime * (0.6 + fi) + fi * 6.28)
				+ 0.1 * sin(p.x * 7.0 - iTime * 1.3 + fi * 12.0)
				+ wave * 0.3 * sin(fi * 20.0);
		float w = 0.004 + 0.012 * (0.5 + 0.5 * sin(p.x * 4.0 + iTime + fi * 9.0));
		float d = abs(p.y - y);
		vec3 c = 0.5 + 0.5 * cos(6.28318 * (fi + p.x * 0.2 + iTime * 0.05 + vec3(0.0, 0.33, 0.67)));
		col += c * w / (d + w * 0.5) * 0.35;
	}
	col = 1.0 - exp(-col * 1.2);
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
