// @title Spin
// Spin: turns the whole picture about its centre, `speed_*` degrees a
// second about each axis (x tips it forward, y turns it like a door, z rolls
// it), in that order. `kick` swings it further along its turn with the
// music (up to that many degrees on a loud beat of `band`), on top of the
// steady turn: a shader can't speed up a turn it has been making all along
// without jumping.
// @hint Turns the picture about its centre, degrees a second per axis.
uniform float speed_x : hint_range(-360.0, 360.0, 1.0) = 0.0;
uniform float speed_y : hint_range(-360.0, 360.0, 1.0) = 30.0;
uniform float speed_z : hint_range(-360.0, 360.0, 1.0) = 0.0;
uniform float kick : hint_range(0.0, 90.0, 1.0) = 0.0;
uniform int band : hint_range(0, 3) = 1;

vec3 deform(vec3 p, vec2 uv, vec2 half_m) {
	vec3 speed = vec3(speed_x, speed_y, speed_z);
	vec3 dir = length(speed) > 0.0 ? speed / length(speed) : vec3(0.0);
	vec3 a = radians(speed * TIME + dir * kick * vfx_band(band));
	vec3 q = vec3(p.x, p.y * cos(a.x) - p.z * sin(a.x), p.y * sin(a.x) + p.z * cos(a.x));
	q = vec3(q.x * cos(a.y) + q.z * sin(a.y), q.y, -q.x * sin(a.y) + q.z * cos(a.y));
	return vec3(q.x * cos(a.z) - q.y * sin(a.z), q.x * sin(a.z) + q.y * cos(a.z), q.z);
}
