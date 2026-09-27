// A copy step in a Screen's effect chain (see Screen._build_chains): the
// part `rect` (in UV) of the input, shrunk to this pass's size and put at
// `place` (in UV; transparent around it).
//   - Each chain starts with one: a stereo frame's eye, or all of a mono
//     one, averaged down to the render size, so the first effect reads a
//     clean picture at its own resolution rather than a few taps of a much
//     bigger video (a sparse blur of a 4K frame sparkles).
//   - Before the first effect that draws past the picture (a `@reach`), one
//     puts the picture in the middle of the margin those effects need.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D input_tex : filter_linear, repeat_disable;
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 place = vec4(0.0, 0.0, 1.0, 1.0);

// Taps per axis at most: past that the average thins out a little.
const int MAX_TAPS = 12;

void fragment() {
	vec2 p = (UV - place.xy) / place.zw;
	if (any(lessThan(p, vec2(0.0))) || any(greaterThan(p, vec2(1.0)))) {
		COLOR = vec4(0.0);
	} else {
		// One output pixel's footprint in the input, in UV and in texels.
		vec2 foot = rect.zw * SCREEN_PIXEL_SIZE / place.zw;
		vec2 texels = foot * vec2(textureSize(input_tex, 0));
		// Each linear-filtered tap averages 2 × 2 texels, so a tap per two
		// texels across covers the footprint (1 when it isn't shrinking).
		ivec2 n = clamp(ivec2(ceil(texels * 0.5)), ivec2(1), ivec2(MAX_TAPS));
		vec2 uv = rect.xy + p * rect.zw;
		vec2 step_uv = foot / vec2(n);
		vec3 rgb = vec3(0.0);
		float a = 0.0;
		for (int y = 0; y < n.y; y++) {
			for (int x = 0; x < n.x; x++) {
				vec4 c = texture(input_tex, uv + (vec2(float(x), float(y)) + 0.5 - vec2(n) * 0.5) * step_uv);
				// Colour weighted by alpha, so see-through texels don't darken it.
				rgb += c.rgb * c.a;
				a += c.a;
			}
		}
		COLOR = vec4(a > 0.0 ? rgb / a : vec3(0.0), a / float(n.x * n.y));
	}
}
