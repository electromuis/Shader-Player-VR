// @title Hex pulse
// A honeycomb that lights up in waves from the centre, each ring of cells
// driven by its own band of the spectrum.
shader_type canvas_item;
#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"

uniform float cells : hint_range(3.0, 30.0, 0.5) = 10.0;
uniform float gain : hint_range(0.0, 4.0, 0.01) = 1.5;

// Offset from the nearest hex centre (xy) and that hex's id (zw).
vec4 hex_coords(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - c.xy * s, p - (c.zw + 0.5) * s);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, c.xy) : vec4(h.zw, c.zw + 0.5);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y * cells;
	vec4 h = hex_coords(p);
	vec2 hs = abs(h.xy);
	float edge = 0.5 - max(dot(hs, normalize(vec2(1.0, 1.7320508))), hs.x);
	vec2 centre = h.zw * vec2(1.0, 1.7320508);
	float dist = length(centre) / cells;
	float lvl = texture(iChannel0, vec2(clamp(dist * 0.8, 0.0, 1.0), 0.25)).x * gain;
	float wave = 0.5 + 0.5 * sin(dist * 20.0 - iTime * 4.0);
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (dist * 1.5 - iTime * 0.1 + vec3(0.0, 0.33, 0.67)));
	float fill = clamp(lvl * wave + 0.08, 0.0, 1.5);
	vec3 outc = col * fill * smoothstep(0.0, 0.08, edge);
	outc += col * smoothstep(0.06, 0.0, edge) * 0.8;
	fragColor = vec4(outc, 1.0);
}

#include "res://player/visualizer/shadertoy_main.gdshaderinc"
