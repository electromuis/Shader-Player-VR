// @title Gyroid tunnel
// Raymarched flight through a gyroid: an endless cave of saddle surfaces
// striped in neon, with a haze that pulses to the bass. Heavy: renders at 720p.
// In 3D (mainVR) the screen is a window into the cave, `world_scale` cave
// units per metre, with the flight's camera at the screen's centre.
// @resolution 1280x720
shader_type canvas_item;
#include "res://addons/vj_editor/visualizer/shadertoy_prelude.gdshaderinc"

uniform float speed : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float thickness : hint_range(0.02, 0.6, 0.01) = 0.12;
uniform float react : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float world_scale : hint_range(0.01, 0.5, 0.005) = 0.05;

const float FAR = 12.0;

vec2 path(float z) {
	return vec2(sin(z * 0.3), cos(z * 0.25)) * 0.6;
}

float map(vec3 p) {
	float g = (abs(dot(sin(p * 3.0), cos(p.yzx * 3.0))) - thickness) / 3.0;
	// Keep a tunnel open along the flight path.
	float tunnel = 0.45 - length(p.xy - path(p.z));
	return max(g, tunnel);
}

vec3 normal_at(vec3 p) {
	vec2 e = vec2(0.002, 0.0);
	return normalize(vec3(map(p + e.xyy) - map(p - e.xyy), map(p + e.yxy) - map(p - e.yxy), map(p + e.yyx) - map(p - e.yyx)));
}

// The flight's camera at time z: position, then right, up and forward.
mat4 flight(float z) {
	vec3 ro = vec3(path(z), z);
	vec3 fw = normalize(vec3(path(z + 1.0), z + 1.0) - ro);
	vec3 rt = normalize(cross(vec3(sin(z * 0.1), 1.0, 0.0), fw));
	return mat4(vec4(ro, 1.0), vec4(rt, 0.0), vec4(cross(fw, rt), 0.0), vec4(fw, 0.0));
}

// Colour along the ray from `ro` along `rd`; `t` gets the distance marched.
vec3 render(vec3 ro, vec3 rd, out float t) {
	t = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 100; i++) {
		float d = map(ro + rd * t);
		glow += exp(-abs(d) * 40.0);
		if (d < 0.001 || t > FAR) {
			break;
		}
		t += d * 0.9;
	}
	vec3 p = ro + rd * t;
	vec3 n = normal_at(p);
	vec3 base = 0.5 + 0.5 * cos(6.28318 * (p.z * 0.15 + dot(sin(p * 3.0), vec3(0.2)) + vec3(0.0, 0.33, 0.67)));
	float diff = 0.5 + 0.5 * dot(n, -rd);
	float stripes = 0.6 + 0.4 * sin((p.x + p.y + p.z) * 25.0);
	vec3 col = base * diff * stripes;
	col += pow(1.0 - diff, 3.0) * base.zxy * 1.5;
	vec3 haze = 0.5 + 0.5 * cos(iTime * 0.4 + vec3(4.0, 2.0, 0.0));
	col = mix(col, haze * 0.3, 1.0 - exp(-t * 0.2));
	col += haze * glow * 0.012 * (1.0 + audio_bass * react);
	return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
	mat4 cam = flight(iTime * speed);
	vec3 rd = normalize(cam[3].xyz + (uv.x * cam[1].xyz + uv.y * cam[2].xyz) * 0.9);
	float t;
	fragColor = vec4(render(cam[0].xyz, rd, t), 1.0);
}

void mainVR(out vec4 fragColor, out float fragDepth, in vec2 fragCoord, in vec3 fragRayOri, in vec3 fragRayDir) {
	mat4 cam = flight(iTime * speed);
	// Start at the window (the screen's plane), so no cave sits between it
	// and the viewer, however far away they stand.
	float t0 = fragRayDir.z < -1e-4 ? max(-fragRayOri.z / fragRayDir.z, 0.0) : 0.0;
	// Screen frame (x right, y up, z toward the viewer) to cave space.
	mat3 to_cave = mat3(cam[1].xyz, cam[2].xyz, -cam[3].xyz);
	vec3 ro = cam[0].xyz + to_cave * ((fragRayOri + fragRayDir * t0) * world_scale);
	vec3 rd = normalize(to_cave * fragRayDir);
	float t;
	fragColor = vec4(render(ro, rd, t), 1.0);
	fragDepth = t0 + t / world_scale;
}

#include "res://addons/vj_editor/visualizer/shadertoy_main.gdshaderinc"
