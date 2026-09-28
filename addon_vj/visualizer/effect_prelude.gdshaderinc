// Effect shader prelude (see VisualizerShaders). Include right after
// `shader_type canvas_item;`. An effect runs on a layer's (or the video
// screen's) output, after the layer's shader and any earlier effects:
//   input_tex       — that output; sample it at UV
//   display_aspect  — width / height of the screen it ends up on, for
//                     shapes that must stay round
//   picture_rect    — where the picture itself sits in this pass, as UV
//                     x, y, width, height: all of it, unless the screen
//                     added a margin around it (for this effect or an
//                     earlier one that draws past the picture's edge: a
//                     `@reach` hint, see VisualizerShaders)
//   picture_shape   — the picture's outline from a Rounded corners effect
//                     before this one, as (roundness, bulge) (see
//                     outline(); 0, 0: rectangle); picture_outline() gives
//                     the outline
// An effect that declares `uniform sampler2D prepass_tex` also gets a
// prepass: the same shader with `uniform bool prepass` on runs first, at
// `prepass_scale` (a float uniform, default 1) of this pass's size, and its
// output arrives as `prepass_tex`. Put heavy, soft work there.
// One that declares `uniform sampler2D video_tex` gets the playing video's
// whole frame (both eyes of a stereo one), on a layer as on a screen;
// give it hint_default_transparent to tell when there's no video (alpha 0).
// Any other `uniform sampler2D` is an image picked in the effect's controls
// (files in an `images/` folder; see ImageLibrary); hint_default_transparent
// tells when none is picked.
// COLOR is written as-is with straight (not premultiplied) alpha, which the
// display pass uses as the screen's transparency.
// Uniforms with a hint_range (or bools) get controls in the Camera tab.

render_mode blend_disabled;

uniform sampler2D input_tex : filter_linear, repeat_disable;
uniform float display_aspect = 1.7777778;
uniform vec4 picture_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 picture_shape = vec2(0.0);

// The outline is a superellipse, |x/w|^n + |y/h|^n = 1, with n = 2 /
// roundness: a rectangle at 0 (n huge), bulging out through squircles
// (0.5: n = 4) to the inscribed oval at 1 (n = 2).
float outline_exponent(float roundness) {
	return 2.0 / clamp(roundness, 0.001, 1.0);
}

// The outline's level at `a` (>= 0; 1 on the outline) and its gradient
// there. `bulge` bows the sides out like an old CRT's: each side keeps its
// middle on the rectangle's edge while its ends, and so the corners, are
// pulled in (by bulge / (1 + bulge) of the half-size). The superellipse
// divides by the larger coordinate first so big exponents don't overflow.
float outline_level(vec2 a, vec2 half_ext, float n, float bulge, out vec2 grad) {
	vec2 s = a / half_ext;
	vec2 k = 1.0 + bulge * s.yx * s.yx;
	vec2 u = s * k;
	float m = max(max(u.x, u.y), 0.000001);
	vec2 q = u / m;
	float f = max(m * pow(pow(q.x, n) + pow(q.y, n), 1.0 / n), 0.000001);
	vec2 gu = pow(u / f, vec2(n - 1.0));
	// Chain rule through the bow: u.x = s.x * (1 + bulge * s.y^2), etc.
	vec2 cross = 2.0 * bulge * s.x * s.y * gu.yx;
	grad = (gu * k + cross) / half_ext;
	return f;
}

// Point `pos` (from the centre) against a rectangle of half-size `half_ext`
// shaped by `shape` = (roundness, bulge) (see outline_exponent and
// outline_level), all in the same units: returns the signed distance to the
// outline (negative inside), and sets `edge` to the outline point it's
// nearest and `normal` to the outward direction there (outside: from `edge`
// to `pos`).
float outline(vec2 pos, vec2 half_ext, vec2 shape, out vec2 edge, out vec2 normal) {
	vec2 sg = vec2(pos.x < 0.0 ? -1.0 : 1.0, pos.y < 0.0 ? -1.0 : 1.0);
	vec2 a = abs(pos);
	half_ext = max(half_ext, vec2(0.0001));
	float n = outline_exponent(shape.x);
	float bulge = max(shape.y, 0.0);
	vec2 grad;
	float f0 = outline_level(a, half_ext, n, bulge, grad);
	// Newton steps onto the outline, along the gradient: a couple settle a
	// point off a nearly straight side, the rest one past a sharp corner or
	// round a bowed side.
	vec2 e = a;
	for (int i = 0; i < 4; i++) {
		float f = outline_level(e, half_ext, n, bulge, grad);
		e = max(e - grad * (f - 1.0) / max(dot(grad, grad), 0.000001), vec2(0.0));
	}
	outline_level(e, half_ext, n, bulge, grad);
	float sd = (f0 > 1.0 ? 1.0 : -1.0) * length(a - e);
	vec2 out_dir = a - e;
	normal = sd > 0.0 && dot(out_dir, out_dir) > 0.0 ? normalize(out_dir)
			: dot(grad, grad) > 0.0 ? normalize(grad) : vec2(0.0, 1.0);
	edge = e * sg;
	normal *= sg;
	return sd;
}

// Whether `p` (picture coordinates, see picture_outline) is inside the
// picture's outline: a single level test, far cheaper than
// picture_outline() where only in or out matters.
bool inside_picture(vec2 p) {
	vec2 grad;
	return outline_level(abs(p - 0.5), vec2(0.5), outline_exponent(picture_shape.x),
			max(picture_shape.y, 0.0), grad) <= 1.0;
}

// outline() for the picture (shaped by `picture_shape`), with p in picture
// coordinates (0..1 inside picture_rect) and distances in fractions of the
// picture, per axis.
float picture_outline(vec2 p, out vec2 edge, out vec2 normal) {
	float sd = outline(p - 0.5, vec2(0.5), picture_shape, edge, normal);
	edge += 0.5;
	return sd;
}
