// @title Glow (fast soften)
// Glow with `soften` as a separable Gaussian in extra prepass steps (for
// comparing against Glow's 24-tap soften in the full-size pass).
// @prepass_passes 7
// A halo around the picture, made from the picture itself and brightened,
// and a brightening just inside its edge. The halo draws in a transparent
// margin the screen adds around the picture.
// @reach pick(intensity > 0.0, Vector2(aspect, 1.0) * (radius + soften), 0.0)
//
// Sizes are fractions of the picture, per axis. At `intensity` 0 there's no
// halo at all, so screens can sit edge to edge. It follows the picture's
// outline, rounded by a Rounded corners effect before it.
//
// Halo: `radius` is how far it reaches; it fades out smoothly to there.
//
// Looks — the halo's colour is a blend of these (weights, normalised):
//   mirror — the picture reflected outward at its edge
//   repeat — the picture copied outward next to itself, unflipped: past
//            one edge it carries on from the opposite one (fanning round
//            the corners, so the sides' copies meet there without a seam)
//   diffuse — the picture hazing out evenly, like light spilling from
//            it (what's left with every weight at 0)
//   smear  — the nearest edge colour pushed straight out, in streaks
//
// Colour: `bloom` lets bright parts of the picture dominate, `saturation`
// is eased in over the halo's first stretch.
//
// Softness: `blur` is how blurred the looks are at the halo's reach (less
// at the border; `border_blur` scales that), over `samples` taps.
// `soften` blurs the finished halo to merge its layers.
//
// Picture edge: a band `edge_width` in from the edge, where `edge_brighten`
// brightens the picture's own colours (keeping its detail) and `edge_fade`
// blends it into the halo's colour (1: fully at the border), so it runs
// into the halo without a step. The picture itself is never blurred.
//
// The halo is soft, so it's worked out in the prepass at `prepass_scale` of
// the pass's size; the full-size pass keeps the picture sharp and lays it
// over the (upscaled, softened) halo.
shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

group_uniforms halo;
uniform float intensity : hint_range(0.0, 4.0, 0.01) = 1.6;
uniform vec3 tint : source_color = vec3(1.0);
uniform float radius : hint_range(0.01, 2.0, 0.01) = 0.64;
group_uniforms looks;
uniform float mirror : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float diffuse : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float repeat : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float smear : hint_range(0.0, 1.0, 0.01) = 0.1;
group_uniforms colour;
uniform float bloom=2;// : hint_range(0.0, 3.0, 0.05) = 0.0;
uniform float saturation : hint_range(0.0, 3.0, 0.01) = 1.0;
group_uniforms softness;
uniform float blur : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float border_blur : hint_range(0.5, 4.0, 0.05) = 1.0;
uniform float soften : hint_range(0.0, 0.3, 0.005) = 0.0;
uniform int samples : hint_range(8, 96) = 24;
group_uniforms picture_edge;
uniform float edge_width : hint_range(0.001, 0.5, 0.001) = 0.08;
uniform float edge_brighten : hint_range(0.0, 2.0, 0.01) = 0.3;
uniform float edge_fade = 1.0;
group_uniforms;
uniform float prepass_scale : hint_range(0.1, 1.0, 0.05) = 0.35;
uniform sampler2D prepass_tex : filter_linear, repeat_disable;
uniform bool prepass = false;
uniform int pass_index = 0;
uniform int pass_count = 1;

const float GOLDEN_ANGLE = 2.39996323;
const int SOFTEN_SAMPLES = 24;
// The blur at the border, as a fraction of `blur` (it reaches all of it at `radius`).
const float EDGE_SPREAD = 0.1;
// Saturation reaches its full amount this far into the halo (a fraction of `radius`).
const float SATURATION_RAMP = 0.3;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Picture coordinates mirrored back into 0..1 at its edges.
vec2 fold(vec2 q) {
	return 1.0 - abs(mod(q, 2.0) - 1.0);
}

// The picture around p (mirrored back in where p is outside it),
// Gaussian-blurred over a disc `spread` across.
vec3 disc(vec2 p, float spread, vec2 vmin, vec2 size, vec2 texel) {
	vec3 sum = vec3(0.0);
	float sum_w = 0.0;
	for (int i = 0; i < samples; i++) {
		float d = sqrt((float(i) + 0.5) / float(samples));
		float ang = float(i) * GOLDEN_ANGLE;
		vec2 sp = clamp(fold(p + vec2(cos(ang), sin(ang)) * d * spread), texel, 1.0 - texel);
		vec3 col = texture(input_tex, vmin + sp * size).rgb;
		float w = exp(-3.0 * d * d);
		if (bloom > 0.0) {
			w *= pow(luma(col) + 0.02, bloom);
		}
		sum += col * w;
		sum_w += w;
	}
	return sum / max(sum_w, 0.00001);
}

// The picture's colour averaged over a disc round `p` reaching `reach`,
// counting only what's on the picture (by its alpha): it varies smoothly
// from point to point, so unlike the looks sampled from the edge point it
// has no streaks.
vec3 haze(vec2 p, float reach, vec2 vmin, vec2 size) {
	vec3 sum = vec3(0.0);
	float sum_w = 0.0;
	for (int i = 0; i < samples; i++) {
		float d = sqrt((float(i) + 0.5) / float(samples));
		float ang = float(i) * GOLDEN_ANGLE;
		vec2 sp = p + vec2(cos(ang), sin(ang)) * d * reach;
		if (any(lessThan(sp, vec2(0.0))) || any(greaterThan(sp, vec2(1.0)))) {
			continue;
		}
		vec4 col = texture(input_tex, vmin + sp * size);
		float w = exp(-3.0 * d * d) * col.a;
		if (bloom > 0.0) {
			w *= pow(luma(col.rgb) + 0.02, bloom);
		}
		sum += col.rgb * w;
		sum_w += w;
	}
	return sum / max(sum_w, 0.00001);
}

// The halo's colour `x` out from outline point `ep`, whose outward
// direction is `n` (t: 0 at the border, 1 at `radius`).
vec3 halo_colour(vec2 ep, vec2 n, float x, float t, float spread, vec2 vmin, vec2 size, vec2 texel) {
	vec3 sum = vec3(0.0);
	float total = 0.0;
	// With no look weighted at all, the halo is just the haze.
	float wd = mirror + repeat + smear + diffuse > 0.0 ? diffuse : 1.0;
	if (wd > 0.0) {
		// Out to twice the distance, so the disc reaches as far into the
		// picture as it sits outside it.
		sum += wd * haze(ep + n * x, 2.0 * x + spread, vmin, size);
		total += wd;
	}
	if (mirror > 0.0) {
		// As far in as out (disc() folds it back past the far side).
		sum += mirror * disc(ep - n * x, spread, vmin, size, texel);
		total += mirror;
	}
	if (repeat > 0.0) {
		// Like mirror, but counted from the far side: 1 - x in along the
		// outline's normal. Off a straight side that's the picture shifted
		// over; round a corner the normal turns, so the copy fans round.
		sum += repeat * disc(ep - n * (1.0 - x), spread, vmin, size, texel);
		total += repeat;
	}
	if (smear > 0.0) {
		sum += smear * disc(ep, spread, vmin, size, texel);
		total += smear;
	}
	vec3 c = sum / total;
	float s = mix(1.0, saturation, smoothstep(0.0, SATURATION_RAMP, t));
	return max(mix(vec3(luma(c)), c, s), vec3(0.0));
}

// The prepass halo at `uv`, Gaussian-blurred over a disc `soften` across.
// Colour is averaged by coverage, so empty texels don't darken it; where a
// tap lands on the picture it counts as covered (the picture's opaque there).
vec4 halo_at(vec2 uv, vec2 vmin, vec2 size) {
	// Softened in the prepass steps already.
	return texture(prepass_tex, uv);
}

// The 9-tap kernel as 5 linear-filtered reads (glsl-fast-gaussian-blur).
const float OFF1 = 1.3846153846;
const float OFF2 = 3.2307692308;
const float W0 = 0.2270270270;
const float W1 = 0.3162162162;
const float W2 = 0.0702702703;

// Prepass step `pass_index` (1..) of the soften: across, down, ... with a
// shrinking step, the variances adding up to Glow's soften disc (weights
// exp(-3 d^2) out to `soften`: sigma = soften / sqrt(6), per axis of the
// picture). The halo step leaves colour premultiplied and alpha as
// coverage; the last step divides it back out.
vec4 soften_step(vec2 uv, vec2 size) {
	int s = pass_index - 1;
	int n = pass_count - 1;
	int axis = s % 2;
	float sum = 0.0;
	for (int i = axis; i < n; i += 2) {
		float k = float(n - i);
		sum += k * k;
	}
	float unit_var = 2.0 * (W1 * OFF1 * OFF1 + W2 * OFF2 * OFF2);
	float sigma = max(soften, 0.0) / sqrt(6.0) * (axis == 0 ? size.x : size.y);
	float step_uv = sigma / sqrt(unit_var * max(sum, 1.0)) * float(n - s);
	vec2 dir = axis == 0 ? vec2(step_uv, 0.0) : vec2(0.0, step_uv);
	vec4 c = texture(input_tex, uv) * W0;
	c += (texture(input_tex, uv + dir * OFF1) + texture(input_tex, uv - dir * OFF1)) * W1;
	c += (texture(input_tex, uv + dir * OFF2) + texture(input_tex, uv - dir * OFF2)) * W2;
	if (pass_index == pass_count - 1) {
		c.rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
	}
	return c;
}

void fragment() {
	vec2 vmin = picture_rect.xy;
	vec2 size = max(picture_rect.zw, vec2(0.0001));
	// Keeps edge samples off the transparent texels around the picture.
	vec2 texel = 0.5 / (vec2(textureSize(input_tex, 0)) * size);
	vec2 p = (UV - vmin) / size;  // picture coordinates, 0..1 inside
	vec2 ep;  // nearest point on the picture's outline
	vec2 n;   // outward there
	float sd = picture_outline(p, ep, n);
	float dist = sd > 0.0 ? length(p - ep) : 0.0;  // how far outside
	float e = max(-sd, 0.0);  // how far inside

	if (prepass && pass_index > 0) {
		COLOR = soften_step(UV, size);
	} else if (prepass) {
		// The halo outside; inside, near the border, the colour the picture
		// fades into there (the halo's at the nearest border point), which
		// also backs the picture's own soft edge (a Rounded corners feather).
		vec4 out_c = vec4(0.0);
		float border_spread = blur * EDGE_SPREAD * border_blur;
		if (intensity > 0.0) {
			if (sd > 0.0) {
				float t = clamp(dist / max(radius, 0.0001), 0.0, 1.0);
				vec3 halo = halo_colour(ep, n, dist, t, mix(border_spread, blur, t), vmin, size, texel);
				float falloff = 1.0 - smoothstep(0.0, 1.0, t);
				falloff *= falloff;
				// Coverage fades with intensity, so a screen at 0 has no dark rim.
				out_c = vec4(halo * tint * intensity, falloff * clamp(intensity, 0.0, 1.0));
			} else if (e < (edge_fade > 0.0 ? edge_width * 1.5 : 0.0) + 0.02) {
				out_c = vec4(halo_colour(ep, n, 0.0, 0.0, border_spread, vmin, size, texel) * tint * intensity, 1.0);
			}
		}
		// Premultiplied, with coverage as alpha (the picture counts as
		// covered), for the soften steps.
		COLOR = vec4(out_c.rgb * out_c.a, inside_picture(p) ? 1.0 : out_c.a);
	} else if (sd > 0.0) {
		COLOR = halo_at(UV, vmin, size);
	} else {
		vec4 c = texture(input_tex, UV);
		float edge = 1.0 - smoothstep(0.0, max(edge_width, 0.0001), e);
		vec3 rgb = c.rgb + c.rgb * tint * edge * edge_brighten;
		// Fades into the colour the halo starts with, so there's no step at
		// the border (none at intensity 0: no halo).
		float k = edge * edge_fade * clamp(intensity, 0.0, 1.0);
		if (k > 0.0 || c.a < 1.0) {
			vec4 h = halo_at(UV, vmin, size);
			rgb = mix(rgb, h.rgb, k);
			// Where the picture is see-through (its soft edge), the halo
			// shows behind it.
			float a = c.a + h.a * (1.0 - c.a);
			rgb = a > 0.0 ? (rgb * c.a + h.rgb * h.a * (1.0 - c.a)) / a : vec3(0.0);
			c.a = a;
		}
		COLOR = vec4(rgb, c.a);
	}
}
