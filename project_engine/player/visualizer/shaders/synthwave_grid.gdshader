// @title Synthwave grid
// Retro synthwave: a striped sun over a neon grid racing to the horizon.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	vec3 col = mix(vec3(0.05, 0.0, 0.15), vec3(0.6, 0.05, 0.45), smoothstep(0.5, -0.05, p.y));
	// Sun, cut by stripes that widen toward its bottom.
	vec2 sp = p - vec2(0.0, 0.12);
	float sr = 0.28 + audio_bass * react * 0.03;
	float sun = smoothstep(sr, sr - 0.005, length(sp));
	float stripes = step(0.0, sin((sp.y + iTime * 0.03) * 70.0) + (sp.y + 0.1) * 12.0);
	vec3 sunc = mix(vec3(1.0, 0.1, 0.5), vec3(1.0, 0.9, 0.2), smoothstep(-0.2, 0.25, sp.y));
	col = mix(col, sunc, sun * stripes);
	col += sunc * 0.08 / max(length(sp) - sr + 0.08, 0.02) * 0.3 * step(0.0, p.y);
	// Grid floor.
	if (p.y < 0.0) {
		float z = 0.25 / -p.y;
		vec2 g = vec2(p.x * z, z + iTime * speed * 2.0);
		vec2 gl = abs(fract(g) - 0.5);
		float w = 0.02 * z;
		float line = smoothstep(w + 0.03, w, 0.5 - max(gl.x, gl.y));
		vec3 gc = vec3(0.0, 0.9, 1.0) * (1.0 + audio_high * react * 2.0);
		col = mix(vec3(0.02, 0.0, 0.06), gc, line * exp(-z * 0.08));
		col += vec3(0.8, 0.1, 0.9) * 0.01 / max(-p.y, 0.01);
	}
	fragColor = vec4(col, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
