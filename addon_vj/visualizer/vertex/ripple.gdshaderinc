// @title Ripple
// Ripple: waves pushing the screen toward / away from the viewer, as
// circles from the centre or as waves running across. Distances in metres.
// @hint Waves off the surface; Audio makes them follow the music.
uniform float amplitude : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float wavelength : hint_range(0.1, 10.0, 0.05) = 2.0;
uniform float speed : hint_range(-5.0, 5.0, 0.05) = 1.0;
uniform bool circles = true;
uniform float audio : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform int band : hint_range(0, 3) = 1;

vec3 deform(vec3 p, vec2 uv, vec2 half_m) {
	float d = circles ? length(p.xy) : p.x;
	float amp = vfx_react(amplitude, audio, band);
	p.z += amp * sin(TAU * (d / max(wavelength, 0.01) - speed * TIME));
	return p;
}
