extends RefCounted

## How an effect's output combines with its input: an effect entry's
## `mix` (0..1: how much of the result shows; 0 = the effect does nothing)
## and `blend` (one of MODES), keyable as `mix` / `blend` on
## `<id>.effect<N>` (see docs/script_format.md).
##   normal — the output replaces the input; below mix 1 they crossfade
##   others — the output's colour blends onto the input like an image
##            editor's layer (the input's shape stays: a mask under
##            `multiply` only darkens), then crossfades by mix
## Screen runs this as a pass after the effect (only while it changes
## anything: a mode other than normal or mix below 1); camera effects run
## GLSL in their compute shader (CameraFxShaders), where `strength` is the
## mix. The authoring addon keeps an identical copy at
## addon_vj/builtin_prefabs/effect_blend.gd (test_addon_shader_copies.gd
## checks), so nothing here names a file; preload it as EffectBlend.

const MODES := ["normal", "add", "subtract", "multiply", "screen", "overlay", "difference", "lighten", "darken"]
const LABELS := {"normal": "Normal", "add": "Add", "subtract": "Subtract", "multiply": "Multiply",
		"screen": "Screen", "overlay": "Overlay", "difference": "Difference", "lighten": "Lighten",
		"darken": "Darken"}
## Effect-entry keys and `effect<N>` track params that aren't the shader's
## uniforms (`enabled`: see EffectSwitch).
const KEYS := ["mix", "blend", "enabled"]

## `vec3 effect_blend(vec3 base, vec3 top, int mode)`: MODES by index, in
## straight colour. Valid in Godot shaders and in GLSL. Every name in it
## starts with `eb_`, since a camera effect's hinted params are #defines.
const FUNCTIONS := """
vec3 effect_blend(vec3 eb_b, vec3 eb_s, int eb_mode) {
	if (eb_mode == 1) return eb_b + eb_s;
	if (eb_mode == 2) return max(eb_b - eb_s, vec3(0.0));
	if (eb_mode == 3) return eb_b * eb_s;
	if (eb_mode == 4) return eb_b + eb_s - eb_b * eb_s;
	if (eb_mode == 5) return mix(2.0 * eb_b * eb_s, 1.0 - 2.0 * (1.0 - eb_b) * (1.0 - eb_s), step(0.5, eb_b));
	if (eb_mode == 6) return abs(eb_b - eb_s);
	if (eb_mode == 7) return max(eb_b, eb_s);
	if (eb_mode == 8) return min(eb_b, eb_s);
	return eb_s;
}

// `eb_fx` (the effect's output) onto `eb_base` (its input), both straight
// alpha: normal takes eb_fx; other modes composite its colour over eb_base
// with the mode (source-over, as CSS mix-blend-mode), then the result
// crossfades with eb_base by `eb_amount`.
vec4 effect_mix(vec4 eb_base, vec4 eb_fx, int eb_mode, float eb_amount) {
	vec4 eb_res = eb_fx;
	if (eb_mode != 0) {
		vec3 eb_c = eb_fx.a * (1.0 - eb_base.a) * eb_fx.rgb + eb_fx.a * eb_base.a * effect_blend(eb_base.rgb, eb_fx.rgb, eb_mode)
				+ (1.0 - eb_fx.a) * eb_base.a * eb_base.rgb;
		float eb_ca = eb_fx.a + eb_base.a * (1.0 - eb_fx.a);
		eb_res = vec4(eb_ca > 0.0 ? eb_c / eb_ca : vec3(0.0), eb_ca);
	}
	float eb_m = clamp(eb_amount, 0.0, 1.0);
	float eb_a = mix(eb_base.a, eb_res.a, eb_m);
	vec3 eb_p = mix(eb_base.rgb * eb_base.a, eb_res.rgb * eb_res.a, eb_m);
	return vec4(eb_a > 0.0 ? eb_p / eb_a : vec3(0.0), eb_a);
}
"""

## The pass Screen adds after a blended effect: `input_tex` its input,
## `effect_tex` its output (the same size and layout).
const PASS_CODE := """shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D input_tex : filter_linear, repeat_disable;
uniform sampler2D effect_tex : filter_linear, repeat_disable;
uniform int blend_mode = 0;
uniform float mix_amount = 1.0;
%s
void fragment() {
	COLOR = effect_mix(texture(input_tex, UV), texture(effect_tex, UV), blend_mode, mix_amount);
}
"""

static var _pass_shader: Shader


## MODES index of `mode` (unknown ones: normal).
static func index_of(mode: Variant) -> int:
	return maxi(MODES.find(String(mode)), 0)


## The blend pass's shader (one, shared).
static func pass_shader() -> Shader:
	if _pass_shader == null:
		_pass_shader = Shader.new()
		_pass_shader.code = PASS_CODE % FUNCTIONS
	return _pass_shader


## An entry's mix (0..1; missing: 1).
static func mix_of(effect: Dictionary) -> float:
	var m = effect.get("mix", 1.0)
	return clampf(float(m), 0.0, 1.0) if typeof(m) in [TYPE_INT, TYPE_FLOAT] else 1.0
