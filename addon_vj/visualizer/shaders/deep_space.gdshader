// @title Deep space (360°)
// The Space skybox as a layer: two star layers, a faint galactic band and
// coloured nebulae, the whole sky turning slowly round a tilted pole. Drawn
// in latitude / longitude, so on a 360° Dome at infinity it wraps with no
// seam; stars twinkle and brighten with the highs.
// @resolution 2048x1024
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

// Degrees per second the sky turns.
uniform float speed : hint_range(0.0, 5.0, 0.05) = 0.4;
uniform float stars : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float nebula : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float twinkle : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float react : hint_range(0.0, 2.0, 0.01) = 0.5;

const vec3 POLE = vec3(0.34, 0.9, 0.27);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// `v` turned by `angle` round the unit axis `k` (Rodrigues).
vec3 rotate(vec3 v, vec3 k, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

// One star per lit grid cell on the direction sphere; `density` is the
// fraction of cells that get one. Each is a soft dot at least `px` radians
// wide, so stars don't flicker as they drift across pixels.
vec3 star_layer(vec3 d, float scale, float density, float px) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < 1.0 - density) {
		return vec3(0.0);
	}
	vec3 jitter = vec3(hash13(cell + 1.3), hash13(cell + 2.7), hash13(cell + 5.1)) - 0.5;
	float dist = length(p - (cell + 0.5 + jitter * 0.4)) / scale;
	float brightness = exp(-pow(dist / px, 2.0)) * (h - (1.0 - density)) / density;
	brightness *= 1.0 + twinkle * sin(iTime * (1.5 + 3.0 * hash13(cell + 7.7)) + h * 60.0);
	vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.7, 0.8, 1.0), hash13(cell + 9.1));
	return tint * brightness * 2.5;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	// Longitude / latitude as the Dome lays them out: x = -180°..180°
	// (0 straight ahead), y = -90° (bottom)..90° (top).
	vec2 uv = fragCoord / iResolution.xy;
	float lon = (uv.x * 2.0 - 1.0) * PI;
	float lat = (uv.y - 0.5) * PI;
	vec3 d = vec3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon));
	d = rotate(d, normalize(POLE), -radians(speed) * iTime);
	// One pixel's angle (vertically; narrower sideways toward the poles).
	float px = PI / iResolution.y;

	vec3 col = vec3(0.004, 0.005, 0.012);
	float n1 = fbm(d * 2.5);
	float n2 = fbm(d * 3.5 + 7.0);
	col += (vec3(0.30, 0.07, 0.38) * pow(n1, 4.0) + vec3(0.04, 0.16, 0.34) * pow(n2, 4.0)) * 1.2 * nebula;
	float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.8, 0.5))), 2.0) * 14.0);
	col += vec3(0.14, 0.12, 0.11) * band * fbm(d * 8.0) * nebula;

	vec3 s = star_layer(d, 60.0, 0.08, px * 0.9) + star_layer(d, 140.0, 0.05, px * 0.7) * 0.5;
	col += s * stars * (1.0 + audio_high * react * 2.0);
	fragColor = vec4(col, 1.0);
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
