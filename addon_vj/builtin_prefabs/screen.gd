@tool
class_name VJScreen
extends "res://addons/vj_editor/modifiers/vj_object.gd"

## Video screen prefab for the VJ authoring project. Runs an artist shader
## over a video texture inside a SubViewport at reduced resolution, then
## its effects (VJEffect children, effect.gd) in their own passes, then
## samples the result on a 3D quad, bent by its surface and moved by its
## vertex effects (VJVertexEffect children, vertex_effect.gd). Mirrors the
## runtime Screen used by the player so what the artist sees in the
## template project roughly matches what the audience sees: the display
## shader is built the same way, from the same snippets
## (screen_shader_code.gd, visualizer/surfaces/, visualizer/vertex/).
##
## There's no video decoder in the authoring project, so the source is a
## still: the owning VJScene's `preview_image`, or a generated three-column
## test card. The player swaps in the live video via `set_source_texture()`.
## Without an artist shader the source goes straight to the effects, as in
## the player; glows, crops and masks are all effects.
##
## Everything animatable lives on this root node so AnimationPlayer tracks
## don't need editable children:
##   main_screen:shader_material:shader_parameter/<name>  → shader_param (slot "surface")
##   main_screen:arc_x / :arc_y / :auto_height / :keep_row_width / :straight_rows / :radius
##                                                        → shader_param (slot "shape")
##   main_screen:opacity (and earlier scenes' :curvature / :vertical_curvature)
##                                                        → shader_param (slot "display")
##   main_screen/<effect>:material:shader_parameter/<name> → shader_param (slot "effect<N>")
##   main_screen/<vertex effect>:params/<name>            → shader_param (slot "vertex<N>")
##
## VJLayer (layer.gd) extends this with a layer shader in place of the
## artist shader; the _authored_material / _render_size / _input_uniforms /
## _bind_inputs / _base_scale hooks are where they differ.
##
## The modifier and reactive fields come from VJObject; `opacity` among them
## is this screen's display fade (exported as `config.opacity` and
## `<id>.display` tracks), not a mesh transparency.

const _SOURCE_TEX_UNIFORM := "screen_tex"
const _BASE_RENDER_RES := Vector2i(1920, 1080)
const _QUAD_ASPECT := 16.0 / 9.0
const _Code := preload("res://addons/vj_editor/builtin_prefabs/screen_shader_code.gd")
const _DISPLAY_INCLUDE := "res://addons/vj_editor/builtin_prefabs/screen_display.gdshaderinc"
const SURFACES_DIR := "res://addons/vj_editor/visualizer/surfaces/"
## The placements each built-in surface supports (as its `@placements`).
const SURFACE_PLACEMENTS := {"pillow": ["fixed", "around"], "dome": ["fixed", "around", "infinity"]}
const _MESH_HALF := Vector2(16.0, 9.0)  # the quad mesh's half size (screen.tscn)
## Where the player puts the viewer: the fallback when the scene has no
## VJViewer (surfaces around the viewer centre on it).
const _HOME_EYE := Vector3(0.0, 2.0, 8.0)
## Stands in for a missing artist shader in the preview (never exported).
const _PASSTHROUGH_CODE := "shader_type canvas_item;
uniform sampler2D screen_tex : source_color, filter_linear;
void fragment() { COLOR = texture(screen_tex, UV); }
"
const _EffectChain := preload("res://addons/vj_editor/builtin_prefabs/effect_chain.gd")
const _EffectScript := preload("res://addons/vj_editor/builtin_prefabs/effect.gd")
const _VertexEffectScript := preload("res://addons/vj_editor/builtin_prefabs/vertex_effect.gd")
## The effect slots scenes used before effects became child nodes. Still
## loaded and saved (not shown) so Tools > VJ: Convert effect slots to
## nodes can move them; the preview and export ignore them.
const LEGACY_EFFECT_SLOTS := ["effect_1", "effect_2", "effect_3", "effect_4"]

## The artist shader, optional (none shows the video as is). Exported as
## `config.shader` + `config.shader_params`. Give each instance its own
## material.
@export var shader_material: ShaderMaterial:
	set(value):
		shader_material = value
		_apply_material()

## Fraction of the base 1920×1080 render target used for the artist shader.
## Lower = faster (fewer fragments) but softer. Surfaced to the exporter as
## `config.render_scale`.
@export_range(0.05, 2.0, 0.05) var render_scale: float = 1.0:
	set(value):
		render_scale = clampf(value, 0.05, 2.0)
		_apply_render_scale()

@export_group("Surface")
## Where the picture sits. Pillow bends the screen left-to-right (arc x)
## and top-to-bottom (arc y), 0 / 0 flat; the picture never distorts, its
## size sets the coverage. Dome puts it on part of a sphere, arc x wide,
## the height following the picture's shape (auto height) or arc y (the
## picture stretches). Exported as `config.surface`.
@export_enum("pillow", "dome") var surface: String = "pillow":
	set(value):
		surface = value
		_apply_display()

## Fixed: bent at the screen. Around viewer: the viewer (the VJViewer, else
## the player's home eye) at the centre; the Pillow's arcs then follow from
## its size, the Dome's size is unused. At infinity (Dome only): follows
## the camera, drawn behind everything (for 180° / 360° video). A
## placement the surface doesn't support is fixed.
@export_enum("fixed", "around", "infinity") var placement: String = "fixed":
	set(value):
		placement = value
		_apply_display()

## Degrees. Animate the arcs and flags for `<id>.shape` tracks.
@export_range(0.0, 360.0, 1.0) var arc_x: float = 0.0:
	set(value):
		arc_x = value
		_sync_display()

@export_range(0.0, 180.0, 1.0) var arc_y: float = 0.0:
	set(value):
		arc_y = value
		_sync_display()

## Dome: the height follows the picture's shape (off: arc y).
@export var auto_height: bool = true:
	set(value):
		auto_height = value
		_sync_display()

## Dome: widen rows toward the top and bottom so they keep their width.
@export var keep_row_width: bool = false:
	set(value):
		keep_row_width = value
		_sync_display()

## Dome: 0..1, lower the rows toward the equator away from the middle so
## they look straight from the centre instead of curving into spiky corners.
@export_range(0.0, 1.0, 0.01) var straight_rows: float = 0.0:
	set(value):
		straight_rows = value
		_sync_display()

## Dome around the viewer: the sphere's radius in metres (0: as far as the
## screen is from the viewer).
@export_range(0.0, 500.0, 0.5) var radius: float = 0.0:
	set(value):
		radius = value
		_sync_display()

## Earlier scenes' bends (0..1 of a half-turn), kept so they load and their
## `:curvature` tracks play: the Pillow's arcs / 180. Not saved.
var curvature: float:
	get:
		return arc_x / 180.0
	set(value):
		arc_x = clampf(value, 0.0, 1.0) * 180.0

var vertical_curvature: float:
	get:
		return arc_y / 180.0
	set(value):
		arc_y = clampf(value, 0.0, 1.0) * 180.0

var _display_material: ShaderMaterial
var _source_texture: Texture2D
## What the canvas actually renders with: a private copy of
## shader_material, so the preview texture never gets saved into the
## author's scene. Params are mirrored every frame (AnimationPlayer
## scrubbing writes to shader_material).
var _render_material: ShaderMaterial
var _param_names: Array[StringName] = []
var _chain: Node  # effect_chain.gd; internal, never saved
var _legacy_effects: Dictionary = {}  # LEGACY_EFFECT_SLOTS name -> ShaderMaterial
var _display_key: Array = []  # what the display shader was built from

static var _test_card: ImageTexture
static var _passthrough: Shader


func _ready() -> void:
	var viewport := _render_viewport()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true

	_display_material = ShaderMaterial.new()
	($Mesh as MeshInstance3D).material_override = _display_material
	_chain = _EffectChain.new()
	_chain.name = "_EffectPasses"
	add_child(_chain)

	_apply_render_scale()
	_apply_display()
	_apply_material()
	_rebuild_effects()
	super._ready()


func _process(_delta: float) -> void:
	var authored_material := _authored_material()
	var authored: Shader = authored_material.shader if authored_material != null else null
	var rendered: Shader = _render_material.shader if _render_material != null else null
	if rendered == _passthrough:
		rendered = null
	if rendered != authored:
		_apply_material()
	elif authored != null:
		for p in _param_names:
			_render_material.set_shader_parameter(p, authored_material.get_shader_parameter(p))
	if _chain == null:
		return
	if not _chain.is_current(effect_materials()):
		_rebuild_effects()
	else:
		_chain.sync(_render_size(), _picture_aspect())
		_apply_mesh_scale()
	# Vertex effects added, removed, re-picked or reordered; params scrub.
	if _display_key != _display_build_key():
		_apply_display()
	else:
		_sync_display()


## Opacity fades the display pass (see the class notes).
func _opacity_changed() -> void:
	_apply_display()


## What reaches the meshes under this screen: everything but opacity, which
## the display pass does.
func modifier_values() -> Dictionary:
	var values := super.modifier_values()
	values.erase("opacity")
	return values


func get_shader_material() -> ShaderMaterial:
	# Works before _ready too (the exporter instantiates without a tree).
	return shader_material


func set_shader_material(mat: ShaderMaterial) -> void:
	shader_material = mat


## The VJEffect children that take part, in order.
func effect_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for c in get_children():
		if c.get_script() == _EffectScript and c.is_active():
			out.append(c)
	return out


## The VJVertexEffect children that take part, in order.
func vertex_effect_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for c in get_children():
		if c.get_script() == _VertexEffectScript and c.is_active():
			out.append(c)
	return out


## The surface as the player takes it ({shader: "pillow" / "dome", params,
## placement}), params limited to the ones that surface reads.
func surface_config() -> Dictionary:
	var params := {"arc_x": arc_x}
	if surface == "dome":
		params["auto_height"] = auto_height
		params["arc_y"] = arc_y
		params["keep_row_width"] = keep_row_width
		params["straight_rows"] = straight_rows
		if radius > 0.0:
			params["radius"] = radius
	else:
		params["arc_y"] = arc_y
	return {"shader": surface, "params": params, "placement": _placement()}


## effect_nodes()' materials.
func effect_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for e in effect_nodes():
		out.append(e.material)
	return out


## The old effect_1..4 values still on this node (slot name -> material).
func legacy_effects() -> Dictionary:
	return _legacy_effects


func _set(property: StringName, value: Variant) -> bool:
	if String(property) in LEGACY_EFFECT_SLOTS:
		if value == null:
			_legacy_effects.erase(String(property))
		else:
			_legacy_effects[String(property)] = value
		notify_property_list_changed()
		return true
	return false


func _get(property: StringName) -> Variant:
	if String(property) in LEGACY_EFFECT_SLOTS:
		return _legacy_effects.get(String(property))
	return null


func _get_property_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in LEGACY_EFFECT_SLOTS:
		if _legacy_effects.has(slot):
			out.append({"name": slot, "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE,
					"hint_string": "ShaderMaterial", "usage": PROPERTY_USAGE_STORAGE})
	return out


## Live source (the player's video). Null falls back to the preview still.
func set_source_texture(tex: Texture2D) -> void:
	_source_texture = tex
	_apply_material()


func set_render_scale(scale: float) -> void:
	render_scale = scale


## Re-read the preview still (VJScene calls this when it changes).
func refresh_preview() -> void:
	_apply_material()


func _render_viewport() -> SubViewport:
	return get_node_or_null("RenderViewport") as SubViewport


func _canvas() -> ColorRect:
	return get_node_or_null("RenderViewport/Canvas") as ColorRect


func _apply_material() -> void:
	var canvas := _canvas()
	if canvas == null:
		return
	_param_names.clear()
	_render_material = null
	var authored := _authored_material()
	if authored != null and authored.shader != null:
		_render_material = authored.duplicate() as ShaderMaterial
		var inputs := _input_uniforms()
		for u in authored.shader.get_shader_uniform_list():
			if not inputs.has(u.name):
				_param_names.append(StringName(u.name))
	elif _input_uniforms().has(_SOURCE_TEX_UNIFORM):
		if _passthrough == null:
			_passthrough = Shader.new()
			_passthrough.code = _PASSTHROUGH_CODE
		_render_material = ShaderMaterial.new()
		_render_material.shader = _passthrough
	if _render_material != null:
		_bind_inputs(_render_material)
	canvas.material = _render_material
	_apply_render_scale()


# ---------- hooks (VJLayer overrides these) ----------

## The material the canvas renders (a copy of), or null for the source as
## is.
func _authored_material() -> ShaderMaterial:
	return shader_material


## Pixel size the shader renders at.
func _render_size() -> Vector2i:
	return Vector2i(Vector2(_BASE_RENDER_RES) * render_scale)


## Uniforms fed by the preview rather than mirrored from shader_material.
func _input_uniforms() -> Array:
	return [_SOURCE_TEX_UNIFORM]


func _bind_inputs(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(_SOURCE_TEX_UNIFORM, _source_texture if _source_texture != null else _preview_texture())


## The quad's scale before padding: a screen always fills its 16:9 box.
func _base_scale() -> Vector2:
	return Vector2.ONE


# ---------- display ----------

func _apply_render_scale() -> void:
	var viewport := _render_viewport()
	if viewport != null:
		viewport.size = _render_size()


## The placement, or fixed where the surface doesn't support it.
func _placement() -> String:
	return placement if placement in SURFACE_PLACEMENTS.get(surface, ["fixed"]) else "fixed"


func _display_build_key() -> Array:
	var key: Array = [surface, _placement()]
	for v in vertex_effect_nodes():
		key.append(v.effect)
		key.append(v.code())
	return key


## Rebuild the display shader (surface, placement or vertex effects
## changed), then push the values.
func _apply_display() -> void:
	if _display_material == null:
		return
	_display_key = _display_build_key()
	var sources: Array = []
	for v in vertex_effect_nodes():
		sources.append(v.code())
	var path := SURFACES_DIR + surface + ".gdshaderinc"
	var surface_code := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var shader := Shader.new()
	shader.code = _Code.build(_DISPLAY_INCLUDE, sources, surface_code)
	_display_material.shader = shader
	_display_material.render_priority = Material.RENDER_PRIORITY_MIN if _placement() == "infinity" else 0
	_sync_display()


## Push the surface's, vertex effects' and display values (every frame, so
## scrubbing shows).
func _sync_display() -> void:
	if _display_material == null:
		return
	var mat := _display_material
	mat.set_shader_parameter("opacity", clampf(opacity, 0.0, 1.0))
	var sc := surface_config()
	for k in sc.params:
		mat.set_shader_parameter(_Code.SURFACE_PREFIX + k, sc.params[k])
	var nodes := vertex_effect_nodes()
	for i in nodes.size():
		var values: Dictionary = nodes[i].param_values()
		for k in values:
			mat.set_shader_parameter(_Code.vertex_prefix(i) + k, values[k])
	var place: int = _Code.PLACEMENTS.find(sc.placement)
	mat.set_shader_parameter("placement", place)
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	var distance := _Code.INFINITY_RADIUS
	if place != 2 and mesh != null and mesh.is_inside_tree():
		distance = maxf(mesh.global_position.distance_to(_viewer_eye()), 0.1)
	mat.set_shader_parameter("viewer_distance", distance)
	var pad: Vector2 = _chain.pad_scale if _chain != null else Vector2.ONE
	mat.set_shader_parameter("picture_half", _MESH_HALF / pad)
	if mesh != null:
		var curved := place != 0 or not nodes.is_empty() or arc_x > 0.0 or (surface == "pillow" and arc_y > 0.0)
		mesh.extra_cull_margin = 16384.0 if curved else 16.0


## The scene's VJViewer, else the player's home eye.
func _viewer_eye() -> Vector3:
	var node := get_parent()
	while node != null and not node.has_method("get_preview_texture"):
		node = node.get_parent()
	if node != null:
		for c in node.get_children():
			if c is Camera3D and c.get_script() != null and c.get_script().get_global_name() == &"VJViewer":
				return (c as Node3D).global_position
	return _HOME_EYE


func _rebuild_effects() -> void:
	if _chain == null or _display_material == null:
		return
	var out: Texture2D = _chain.build(_render_viewport().get_texture(), effect_materials(),
			_render_size(), _picture_aspect())
	_display_material.set_shader_parameter("frame_tex", out)
	_apply_mesh_scale()


## Width / height of the picture on the quad, before padding.
func _picture_aspect() -> float:
	var b := _base_scale()
	return _QUAD_ASPECT * b.x / maxf(b.y, 0.001)


func _apply_mesh_scale() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or _chain == null:
		return
	var s: Vector2 = _base_scale() * _chain.pad_scale
	mesh.scale = Vector3(s.x, s.y, 1.0)


func _preview_texture() -> Texture2D:
	# The VJScene root, however deep this screen sits (groups, layers).
	var node := get_parent()
	while node != null and not node.has_method("get_preview_texture"):
		node = node.get_parent()
	if node != null:
		var tex: Texture2D = node.get_preview_texture()
		if tex != null:
			return tex
	return _get_test_card()


## Three tinted columns with 1/2/3 bars, so UV sub-rects (split screens)
## are easy to read in the preview.
static func _get_test_card() -> ImageTexture:
	if _test_card != null:
		return _test_card
	var w := 480
	var h := 270
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var tints := [Color(0.85, 0.3, 0.3), Color(0.3, 0.8, 0.4), Color(0.3, 0.45, 0.9)]
	for y in h:
		for x in w:
			var col := mini(x * 3 / w, 2)
			var c: Color = tints[col].darkened(0.55 * float(y) / h)
			if x % 30 == 0 or y % 30 == 0:
				c = c.lightened(0.35)
			img.set_pixel(x, y, c)
	for col in 3:
		var cx := col * w / 3 + w / 6
		for bar in col + 1:
			var bx := cx - col * 9 + bar * 18 - 4
			img.fill_rect(Rect2i(bx, h / 2 - 30, 8, 60), Color.WHITE)
	_test_card = ImageTexture.create_from_image(img)
	return _test_card
