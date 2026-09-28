// @title Plasma bloom
// Classic sine plasma, banded through a rainbow palette; the bass swells it.
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float scale : hint_range(0.5, 12.0, 0.1) = 6.0;
uniform float bands : hint_range(0.2, 4.0, 0.01) = 1.2;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

vec3 pal(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y * scale;
	float t = iTime * speed;
	float v = sin(p.x + t);
	v += sin((p.y + t) * 0.5);
	v += sin((p.x + p.y + t) * 0.5);
	vec2 c = p + vec2(sin(t / 3.0), cos(t / 2.0)) * scale * 0.5;
	v += sin(sqrt(dot(c, c) + 1.0) + t);
	v *= 1.0 + audio_bass * react * 0.5;
	vec3 col = pal(v * bands * 0.5 + t * 0.1);
	col *= 0.55 + 0.45 * sin(v * 3.14159 * bands * 2.0);
	col = pow(col, vec3(0.8));
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
