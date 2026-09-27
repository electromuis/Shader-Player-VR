@tool
extends Node

## Editor preview of a screen's or layer's effects (its VJEffect children):
## one SubViewport pass per effect shader, each reading the previous output
## as `input_tex`, like the player's Screen does. The authored materials
## are never rendered directly; each pass runs a copy, re-synced every
## frame so scrubbing an effect param shows. Before the first effect that
## draws past the picture's edge (its shader has a `// @reach`), a
## chain_copy pass puts the picture in a transparent margin as wide as the
## effects from there reach, summed; those passes grow by it, and
## `pad_scale` is how much the quad grows to keep the picture the same size
## (see the player's Screen and VisualizerShaders.reach_of). Each pass gets
## `picture_rect` (and past a Rounded corners effect `picture_shape`), and
## an effect declaring `prepass_tex` gets a prepass at `prepass_scale` of
## its size, as in the player's Screen.

const COPY_SHADER := preload("res://addons/vj_editor/builtin_prefabs/chain_copy.gdshader")
const ROUNDED_CORNERS_FILE := "rounded_corners.gdshader"
## Uniforms the chain sets itself; never copied from the authored material.
const CHAIN_INPUTS := ["input_tex", "display_aspect", "picture_rect", "picture_shape", "prepass_tex", "prepass"]
const MAX_REACH := 4.0  # per side, in picture heights (as the player's)

## The quad's growth from the margin, as (width, height) factors.
var pad_scale: Vector2 = Vector2.ONE

static var _reach_re := RegEx.create_from_string("(?m)^\\s*//\\s*@reach\\s+(.+?)\\s*$")
static var _reach_cache := {}  # shader code -> [Expression or null, input names]
static var _reach_helpers := _ReachHelpers.new()

var _sources: Array[ShaderMaterial] = []
## {material, viewport, source (null: the margin copy), prepass}
var _passes: Array[Dictionary] = []
var _built: Array = []  # [material, shader] per source when built, to notice changes
var _margin_from: int = -1  # the first source with a @reach (-1 = none)


## (Re)build the passes after `src` for `materials` (nulls and materials
## without a shader are skipped). Returns the texture to display.
func build(src: Texture2D, materials: Array[ShaderMaterial], px: Vector2i, aspect: float) -> Texture2D:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_passes.clear()
	_sources.clear()
	_built.clear()
	for m in materials:
		_built.append([m, m.shader if m != null else null])
		if m != null and m.shader != null:
			_sources.append(m)
	_margin_from = -1
	for i in _sources.size():
		if _reach_expression(_sources[i].shader)[0] != null:
			_margin_from = i
			break
	var tex := src
	for i in _sources.size():
		var m := _sources[i]
		if i == _margin_from:
			tex = _add_pass(null, tex, false)
		var pre: Texture2D = null
		if m.shader.code.contains("prepass_tex"):
			pre = _add_pass(m, tex, true)
		var out := _add_pass(m, tex, false)
		if pre != null:
			_passes[-1].material.set_shader_parameter("prepass_tex", pre)
		tex = out
	sync(px, aspect)
	return tex


func _add_pass(source: ShaderMaterial, input: Texture2D, prepass: bool) -> Texture2D:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial
	if source == null:
		mat = ShaderMaterial.new()
		mat.shader = COPY_SHADER
	else:
		mat = source.duplicate() as ShaderMaterial
		mat.set_shader_parameter("prepass", prepass)
	mat.set_shader_parameter("input_tex", input)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	_passes.append({"material": mat, "viewport": vp, "source": source, "prepass": prepass})
	return vp.get_texture()


## Whether `materials` still matches what was built (same materials in the
## same order, same shaders).
func is_current(materials: Array[ShaderMaterial]) -> bool:
	if materials.size() != _built.size():
		return false
	for i in materials.size():
		var m := materials[i]
		if m != _built[i][0] or (m.shader if m != null else null) != _built[i][1]:
			return false
	return true


## Copy the authored params into the passes and size them: `px` is the
## picture's pixel size and `aspect` its width / height before padding.
func sync(px: Vector2i, aspect: float) -> void:
	var margin := Vector2.ZERO
	if _margin_from >= 0:
		for i in range(_margin_from, _sources.size()):
			margin += reach_of(_sources[i], aspect)
	var w := aspect
	var h := 1.0
	var size := Vector2(px)
	var shape := Vector2.ZERO
	for p in _passes:
		var src: ShaderMaterial = p.source
		var mat: ShaderMaterial = p.material
		var vp: SubViewport = p.viewport
		if src == null:
			w = aspect + 2.0 * margin.x
			h = 1.0 + 2.0 * margin.y
			size *= Vector2(w / aspect, h)
			mat.set_shader_parameter("place", Vector4(0.5 - 0.5 * aspect / w, 0.5 - 0.5 / h, aspect / w, 1.0 / h))
			vp.size = _fit(size)
			continue
		for u in src.shader.get_shader_uniform_list():
			if not CHAIN_INPUTS.has(u.name):
				mat.set_shader_parameter(u.name, src.get_shader_parameter(u.name))
		mat.set_shader_parameter("display_aspect", w / h)
		mat.set_shader_parameter("picture_rect", Vector4(0.5 - 0.5 * aspect / w, 0.5 - 0.5 / h, aspect / w, 1.0 / h))
		mat.set_shader_parameter("picture_shape", shape)
		if src.shader.resource_path.get_file() == ROUNDED_CORNERS_FILE and not p.prepass:
			shape = Vector2(float(_uniform(src, "roundness", 0.0)), float(_uniform(src, "bulge", 0.0)))
		var fit := size
		if p.prepass:
			fit *= clampf(float(_uniform(src, "prepass_scale", 1.0)), 0.05, 1.0)
		vp.size = _fit(fit)
	pad_scale = Vector2(w / aspect, h)


## A pass's viewport size for `px` pixels, shrunk to fit 4096.
static func _fit(px: Vector2) -> Vector2i:
	if px.x > 4096.0 or px.y > 4096.0:
		px *= 4096.0 / maxf(px.x, px.y)
	return Vector2i(px.round()).max(Vector2i.ONE * 16)


## How far the effect `mat` draws past the picture's edge at its current
## params, from its shader's `@reach` (see the player's
## VisualizerShaders.reach_of): (x, y) per side in picture heights, for a
## picture `aspect` wide.
static func reach_of(mat: ShaderMaterial, aspect: float) -> Vector2:
	var parsed: Array = _reach_expression(mat.shader)
	var e: Expression = parsed[0]
	if e == null:
		return Vector2.ZERO
	var values: Array = [aspect]
	for n in parsed[1]:
		values.append(_uniform(mat, n, 0.0))
	var v = e.execute(values, _reach_helpers, false)
	if e.has_execute_failed():
		return Vector2.ZERO
	match typeof(v):
		TYPE_FLOAT, TYPE_INT:
			v = Vector2(v, v)
		TYPE_VECTOR2:
			pass
		_:
			return Vector2.ZERO
	return (v as Vector2).clamp(Vector2.ZERO, Vector2.ONE * MAX_REACH)


## [the parsed `@reach` of `shader` (null: none), its uniform names in input
## order], cached by code.
static func _reach_expression(shader: Shader) -> Array:
	if shader == null:
		return [null, []]
	var code := shader.code
	if not _reach_cache.has(code):
		var entry: Array = [null, []]
		var m := _reach_re.search(code)
		if m != null:
			var names := PackedStringArray(["aspect"])
			for u in shader.get_shader_uniform_list():
				names.append(u.name)
			var e := Expression.new()
			if e.parse(m.get_string(1), names) == OK:
				entry = [e, names.slice(1)]
			else:
				push_warning("%s: can't read @reach: %s" % [shader.resource_path.get_file(), e.get_error_text()])
		_reach_cache[code] = entry
	return _reach_cache[code]


## Functions a `@reach` expression can call besides Godot's built-ins
## (Expression's own `a if c else b` always gives `a`).
class _ReachHelpers:
	func pick(condition: bool, if_true: Variant, if_false: Variant) -> Variant:
		return if_true if condition else if_false


## `name`'s value on `mat`, else the shader's default, else `fallback`.
static func _uniform(mat: ShaderMaterial, name: String, fallback: Variant) -> Variant:
	var v = mat.get_shader_parameter(name)
	if v == null:
		v = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), name)
	return v if v != null else fallback
