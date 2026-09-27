// @title Stained glass
// Stained glass: drifting Voronoi cells in jewel colours with glowing leads.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float cells : hint_range(2.0, 20.0, 0.5) = 6.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = fragCoord / iResolution.y * cells;
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(ip + g);
			o = 0.5 + 0.45 * sin(iTime * 0.8 + 6.28318 * o);
			float d = length(g + o - fp);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = ip + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float h = hash2(id).x;
	float lvl = texture(iChannel0, vec2(h * 0.6, 0.25)).x;
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (h + iTime * 0.05 + vec3(0.0, 0.33, 0.67)));
	col *= 0.5 + 0.5 * (1.0 - d1) + lvl * react;
	float edge = d2 - d1;
	col = mix(vec3(1.0, 0.95, 0.8) * 1.5, col, smoothstep(0.0, 0.06, edge));
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
