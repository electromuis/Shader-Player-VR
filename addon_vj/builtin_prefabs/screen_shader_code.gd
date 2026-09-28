extends RefCounted

## Builds a screen's display shader from its vertex effects and surface
## (`.gdshaderinc` snippets; see ScreenGeometry for what they define), and
## reads a snippet's hinted uniforms. Shared by the player (ScreenGeometry)
## and the authoring addon's preview (VJScreen): the addon keeps an
## identical copy at addon_vj/builtin_prefabs/screen_shader_code.gd
## (project_engine/tests/test_addon_shader_copies.gd checks), so nothing
## here names a file.

const SURFACE_PREFIX := "srf_"
## Radius of the camera-centred surface at infinity, in metres.
const INFINITY_RADIUS := 50.0
const PLACEMENTS := ["fixed", "around", "infinity"]

static var _decl_re := RegEx.create_from_string(
		"(?m)^\\s*(?:uniform\\s+\\w+\\s+(\\w+)|const\\s+\\w+\\s+(\\w+)|(?:void|float|int|bool|[iu]?vec[234]|mat[234])\\s+(\\w+)\\s*\\()")
static var _uniform_re := RegEx.create_from_string(
		"(?m)^\\s*uniform\\s+(float|int|bool)\\s+(\\w+)\\s*(?::\\s*([^=;]*))?(?:=\\s*([^;]+))?;")
static var _range_re := RegEx.create_from_string("hint_range\\s*\\(([^)]*)\\)")
## A mainVR with `out float fragDepth` after its colour (see build).
static var _vr_depth_re := RegEx.create_from_string(
		"(?m)^\\s*void\\s+mainVR\\s*\\(\\s*out\\s+vec4\\s+\\w+\\s*,\\s*out\\s+float\\b")


static func vertex_prefix(index: int) -> String:
	return "vfx%d_" % index


## `code` with every uniform, const and function it declares renamed to
## `prefix` + name, so two stages can both have an `amount`.
static func prefixed(code: String, prefix: String) -> String:
	var names := {}
	for m in _decl_re.search_all(code):
		for g in [1, 2, 3]:
			if m.get_string(g) != "":
				names[m.get_string(g)] = true
	for n in names:
		code = RegEx.create_from_string("\\b%s\\b" % n).sub(code, prefix + n, true)
	return code


## Display shader source: `include` (the display pass's include), the
## vertex effects' sources in order (ones without a `deform(` skipped), the
## surface's (none without a `surface(`), and a vertex() running them.
## `vr_source`, a 3D layer shader's code (its mainVR; no shader_type or
## render_mode), goes before the include with SHADERTOY_VR defined, and
## SHADERTOY_VR_DEPTH when its mainVR has a fragDepth: the include's
## fragment() then calls it, and the screen writes depth.
static func build(include: String, vertex_sources: Array, surface_source: String, vr_source: String = "") -> String:
	var code := "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, blend_premul_alpha%s;\n" \
			% (", depth_draw_always" if vr_source != "" else "")
	if vr_source != "":
		code += "#define SHADERTOY_VR\n"
		if _vr_depth_re.search(vr_source) != null:
			code += "#define SHADERTOY_VR_DEPTH\n"
		code += "\n%s\n\n" % vr_source
	code += "#include \"%s\"\n\n" % include
	var calls := ""
	for i in vertex_sources.size():
		var src := String(vertex_sources[i])
		if not src.contains("deform("):
			continue
		code += prefixed(src, vertex_prefix(i)) + "\n"
		calls += "\tp = %sdeform(p, UV, half_m);\n" % vertex_prefix(i)
	if surface_source.contains("surface("):
		code += prefixed(surface_source, SURFACE_PREFIX) + "\n"
		calls += "\tp = %ssurface(p, UV, half_m);\n" % SURFACE_PREFIX
	return code + """void vertex() {
	// Metres in the screen's own frame, whatever its (and its parents') scale.
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 half_m = picture_half * s.xy;
	vec3 p = vec3(VERTEX.xy * s.xy, 0.0);
%s	if (placement == 2) {
		// Around the camera: only the screen's rotation counts.
		mat3 rot = mat3(MODEL_MATRIX[0].xyz / s.x, MODEL_MATRIX[1].xyz / s.y, MODEL_MATRIX[2].xyz / s.z);
		vec3 world = CAMERA_POSITION_WORLD + rot * (p - vec3(0.0, 0.0, viewer_distance));
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	} else {
		VERTEX = p / s;
	}
}
""" % calls


## A snippet's sliders: [{name, type ("float" / "int" / "bool"), min, max,
## step, default}] for its uniforms with a hint_range, and its bools.
static func uniform_params(code: String) -> Array:
	var out: Array = []
	for u in _uniform_re.search_all(code):
		var type := u.get_string(1)
		var p := {"name": u.get_string(2), "type": type}
		var default_src := u.get_string(4).strip_edges()
		if type == "bool":
			p.default = default_src == "true"
		else:
			var r := _range_re.search(u.get_string(3))
			if r == null:
				continue
			var nums := r.get_string(1).split(",")
			p.min = _eval(nums[0], 0.0)
			p.max = _eval(nums[1], 1.0) if nums.size() > 1 else 1.0
			p.step = _eval(nums[2], 0.0) if nums.size() > 2 else (1.0 if type == "int" else 0.01)
			p.default = _eval(default_src, p.min) if default_src != "" else p.min
			if type == "int":
				p.default = int(p.default)
		out.append(p)
	return out


## `params` with each of `specs`' params filled in (defaults for the
## missing ones).
static func full_params(specs: Array, params: Dictionary) -> Dictionary:
	var out := {}
	for spec in specs:
		out[spec.name] = params.get(spec.name, spec.default)
	return out


## A number from shader source ("0.5", "1.0 / 3.0", "-2"), or `fallback`.
static func _eval(src: String, fallback: float) -> float:
	var e := Expression.new()
	if e.parse(src.strip_edges()) != OK:
		return fallback
	var v = e.execute()
	if e.has_execute_failed() or not (typeof(v) in [TYPE_FLOAT, TYPE_INT]):
		return fallback
	return float(v)
