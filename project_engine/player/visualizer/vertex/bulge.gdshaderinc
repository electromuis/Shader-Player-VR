// @title Bulge
// Bulge: a round swelling toward the viewer (negative amount: a dent away),
// `radius` metres across, centred at centre_x / centre_y (-1..1 across the
// picture).
// @hint A swelling (or with a negative amount, a dent) around a point.
uniform float amount : hint_range(-2.0, 2.0, 0.01) = 0.5;
uniform float radius : hint_range(0.1, 10.0, 0.05) = 2.0;
uniform float centre_x : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float centre_y : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float audio : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform int band : hint_range(0, 3) = 1;

vec3 deform(vec3 p, vec2 uv, vec2 half_m) {
	vec2 c = vec2(centre_x, centre_y) * half_m;
	float d = length(p.xy - c) / max(radius, 0.01);
	p.z += vfx_react(amount, audio, band) * exp(-4.0 * d * d);
	return p;
}
