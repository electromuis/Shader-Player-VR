// @title Twist
// Twist: turns each row about the screen's vertical centre line, the top
// one way and the bottom the other, `angle` degrees at the edges. Falloff
// shapes how the turn grows from the middle (1 = evenly, higher = mostly
// near the edges).
// @hint Turns rows the opposite way top and bottom.
uniform float angle : hint_range(-180.0, 180.0, 1.0) = 30.0;
uniform float falloff : hint_range(0.2, 4.0, 0.05) = 1.0;
uniform float audio : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform int band : hint_range(0, 3) = 1;

vec3 deform(vec3 p, vec2 uv, vec2 half_m) {
	float f = clamp(p.y / half_m.y, -1.0, 1.0);
	float a = radians(vfx_react(angle, audio, band)) * sign(f) * pow(abs(f), falloff);
	// About the vertical axis: +z is toward the viewer.
	return vec3(p.x * cos(a) - p.z * sin(a), p.y, p.x * sin(a) + p.z * cos(a));
}
