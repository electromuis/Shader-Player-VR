// A Gaussian blur as a chain of one-direction steps (glsl-fast-gaussian-blur's
// 9-tap kernel, as 5 linear-filtered reads), shared by Blur, Edge blur and
// Glow's soften. Run a step per pass (see VisualizerShaders' `@passes` and
// `@prepass_passes`): steps alternate across (even) and down (odd), each
// shorter than the one before (count - step units: the wide early steps
// spread the blur, the later ones fill in between), and their variances add
// up to the requested sigma on each axis.

const float FG_OFF1 = 1.3846153846;
const float FG_OFF2 = 3.2307692308;
const float FG_W0 = 0.2270270270;
const float FG_W1 = 0.3162162162;
const float FG_W2 = 0.0702702703;

// The offset (in UV) between the taps of step `step` of `count`, for a blur
// of `sigma` (in UV, per axis) over all of them.
vec2 gaussian_step_dir(int step, int count, vec2 sigma) {
	int axis = step % 2;  // 0: across, 1: down
	float sum = 0.0;
	for (int i = axis; i < count; i += 2) {
		float k = float(count - i);
		sum += k * k;
	}
	// Variance of one step per unit of offset.
	float unit_var = 2.0 * (FG_W1 * FG_OFF1 * FG_OFF1 + FG_W2 * FG_OFF2 * FG_OFF2);
	float s = axis == 0 ? sigma.x : sigma.y;
	float len = s / sqrt(unit_var * max(sum, 1.0)) * float(count - step);
	return axis == 0 ? vec2(len, 0.0) : vec2(0.0, len);
}

// A read of `tex` at `uv`; with `clear_outside`, transparent past its edge
// (instead of the edge texel repeated), so the texture's border is an edge.
vec4 gaussian_read(sampler2D tex, vec2 uv, bool clear_outside) {
	bool outside = any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)));
	return clear_outside && outside ? vec4(0.0) : texture(tex, uv);
}

// The 9-tap Gaussian round `uv` along `dir`. With `premultiply` each read's
// colour is weighted by its alpha first (the first step of a blur of
// straight-alpha colour; the last divides it back out, see gaussian_unpremultiply).
// `clear_outside`: see gaussian_read.
vec4 gaussian_taps(sampler2D tex, vec2 uv, vec2 dir, bool premultiply, bool clear_outside) {
	vec4 t0 = gaussian_read(tex, uv, clear_outside);
	vec4 t1 = gaussian_read(tex, uv + dir * FG_OFF1, clear_outside);
	vec4 t2 = gaussian_read(tex, uv - dir * FG_OFF1, clear_outside);
	vec4 t3 = gaussian_read(tex, uv + dir * FG_OFF2, clear_outside);
	vec4 t4 = gaussian_read(tex, uv - dir * FG_OFF2, clear_outside);
	if (premultiply) {
		t0.rgb *= t0.a;
		t1.rgb *= t1.a;
		t2.rgb *= t2.a;
		t3.rgb *= t3.a;
		t4.rgb *= t4.a;
	}
	return t0 * FG_W0 + (t1 + t2) * FG_W1 + (t3 + t4) * FG_W2;
}

// Straight-alpha colour from a premultiplied blur result.
vec4 gaussian_unpremultiply(vec4 c) {
	return vec4(c.a > 0.0 ? c.rgb / c.a : vec3(0.0), c.a);
}
