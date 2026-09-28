// @title Truchet neon
// Neon Truchet tiles: quarter-circle arcs linking into endless flowing paths.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float tiles : hint_range(3.0, 30.0, 0.5) = 10.0;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = fragCoord / iResolution.y * tiles + vec2(iTime * 0.3, iTime * 0.2);
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	if (hash(id) > 0.5) {
		f.x = -f.x;
	}
	// Distance to the nearer of the tile's two arcs (corners (.5,.5) / (-.5,-.5)).
	vec2 c = f - sign(f.x + f.y + 0.0001) * 0.5;
	float d = abs(length(c) - 0.5);
	float ang = atan(c.y, c.x);
	float flow = sin(ang * 8.0 * (mod(id.x + id.y, 2.0) * 2.0 - 1.0) + iTime * 6.0);
	float w = 0.06 + audio_bass * react * 0.05;
	float line = smoothstep(w, w * 0.4, d);
	float glow = 0.02 / (d + 0.02);
	vec3 col = 0.5 + 0.5 * cos(6.28318 * ((id.x + id.y) * 0.05 + iTime * 0.1 + vec3(0.0, 0.33, 0.67)));
	vec3 outc = col * glow * 0.4 + mix(col, vec3(1.0), 0.5) * line * (0.7 + 0.3 * flow);
	fragColor = vec4(outc, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
