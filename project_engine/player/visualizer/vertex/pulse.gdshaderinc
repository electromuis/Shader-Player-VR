// @title Pulse
// Pulse: grows the whole picture about its centre with the music, by up to
// `amount` (0.2 = 20% bigger) on a loud `band` (0 level, 1 bass, 2 mids,
// 3 highs); `depth` also pushes it toward the viewer (metres at full level).
// @hint Swells the picture with the music.
uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float depth : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform int band : hint_range(0, 3) = 1;

vec3 deform(vec3 p, vec2 uv, vec2 half_m) {
	float level = vfx_band(band);
	return vec3(p.xy * (1.0 + amount * level), p.z + depth * level);
}
