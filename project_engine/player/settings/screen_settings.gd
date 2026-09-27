class_name ScreenSettings
extends RefCounted

## User-facing screen preferences applied to a wrapper `ScreenMount` node
## that parents `main_screen`. Because these live on the mount and the
## runner's transform tracks write to the child, offsets never drift with
## script animation.
##
## Units:
##   size       — scale multiplier on the mount (dimensionless), about
##                the screen's centre (the `pivot` passed in), so resizing
##                doesn't shift the screen up or down
##   distance   — meters pushed along -Z (positive = further from viewer)
##   height     — meters added to Y (positive = up)
##   tilt       — degrees the screen orbits around the viewer's eye
##                (positive = swings up overhead and faces down, for
##                reclined viewing; it stays at the same distance)
##   surface    — where the picture sits: {shader: ScreenGeometry surface
##                key, params: {uniform: value}, placement: "fixed" /
##                "around" / "infinity"}; not a mount transform — main.gd
##                pushes it to the screen (see Screen.set_surface). Earlier
##                presets' curvature / vertical_curvature (0..1) become a
##                Pillow's arcs (× 180°)
##   vertex_effects — vertex effects moving the surface, in order:
##                [{shader: ScreenGeometry key, params}] like `effects`
##   opacity    — 0..1, likewise a display-shader value, not a transform
##   resolution — RESOLUTION_MIN..RESOLUTION_MAX multiplier on the pixel
##                size the shader and effect passes render at (see
##                Screen.set_resolution_scale); lower is cheaper and softer
##   effects    — effect shaders run in order over the picture:
##                [{shader: VisualizerShaders key ("" = none picked),
##                params: {uniform: value}}] (see Screen.set_effects)

signal changed

const RESOLUTION_MIN := 0.1
const RESOLUTION_MAX := 2.0
## Effects or vertex effects added, removed or re-picked, the surface
## re-picked or re-placed, or everything replaced by from_dict: controls
## built from them need rebuilding. `changed` fires too.
signal structure_changed

## The effect lists (the `list` argument of the effect methods).
const EFFECTS := "effects"
const VERTEX_EFFECTS := "vertex_effects"

var size: float = 1.0: set = _set_size
var distance: float = 0.0: set = _set_distance
var height: float = 0.0: set = _set_height
var tilt: float = 0.0: set = _set_tilt
var surface: Dictionary = ScreenGeometry.default_surface()
var opacity: float = 1.0: set = _set_opacity
var resolution: float = 1.0: set = _set_resolution
var effects: Array[Dictionary] = []
var vertex_effects: Array[Dictionary] = []


func from_dict(d: Dictionary) -> void:
	# Bypass setters so we emit `changed` once at the end, not four times.
	size = float(d.get("size", 1.0))
	distance = float(d.get("distance", 0.0))
	height = float(d.get("height", 0.0))
	tilt = float(d.get("tilt", 0.0))
	if typeof(d.get("surface")) == TYPE_DICTIONARY:
		surface = ScreenGeometry.normalized_surface(d["surface"])
	else:
		surface = ScreenGeometry.default_surface()
		surface.params = {
			"arc_x": float(d.get("curvature", 0.0)) * 180.0,
			"arc_y": float(d.get("vertical_curvature", 0.0)) * 180.0,
		}
	opacity = float(d.get("opacity", 1.0))
	resolution = float(d.get("resolution", 1.0))
	_read_effects(effects, d.get("effects", []))
	_read_effects(vertex_effects, d.get("vertex_effects", []))
	# The built-in oval mask of an earlier version becomes an Oval mask effect.
	var mask = d.get("mask", {})
	if typeof(mask) == TYPE_DICTIONARY and bool(mask.get("enabled", false)):
		effects.append({"shader": VisualizerShaders.OVAL_MASK, "params": {
			"outside": bool(mask.get("outside", true)),
			"size": float(mask.get("size", 1.0)),
			"ratio": float(mask.get("ratio", 16.0 / 9.0)),
			"blur": float(mask.get("feather", 0.2)),
			"level": float(mask.get("level", 0)),
		}})
	structure_changed.emit()
	changed.emit()


func to_dict() -> Dictionary:
	return {
		"size": size,
		"distance": distance,
		"height": height,
		"tilt": tilt,
		"surface": surface.duplicate(true),
		"opacity": opacity,
		"resolution": resolution,
		"effects": effects.duplicate(true),
		"vertex_effects": vertex_effects.duplicate(true),
	}


static func _read_effects(out: Array[Dictionary], list: Variant) -> void:
	out.clear()
	if typeof(list) != TYPE_ARRAY:
		return
	for e in list:
		# Earlier versions' Padding: the margin is automatic now.
		if typeof(e) == TYPE_DICTIONARY and String(e.get("shader", "")) != VisualizerShaders.LEGACY_PADDING:
			var params = e.get("params", {})
			out.append({
				"shader": String(e.get("shader", "")),
				"params": params.duplicate() if typeof(params) == TYPE_DICTIONARY else {},
			})


## Pick a surface (a ScreenGeometry key); params and placement go back to
## its defaults.
func set_surface_shader(key: String) -> void:
	if key == surface.shader:
		return
	surface = ScreenGeometry.normalized_surface({"shader": key})
	structure_changed.emit()
	changed.emit()


## "fixed" / "around" / "infinity"; one the surface doesn't support is
## ignored.
func set_surface_placement(placement: String) -> void:
	if placement == surface.placement or not placement in ScreenGeometry.placements_for(surface.shader):
		return
	surface.placement = placement
	structure_changed.emit()
	changed.emit()


func set_surface_param(param: String, value: Variant) -> void:
	if surface.params.get(param) == value:
		return
	surface.params[param] = value
	changed.emit()


## Replace the whole surface ({shader, params, placement}).
func set_surface(value: Dictionary) -> void:
	var s := ScreenGeometry.normalized_surface(value)
	if s == surface:
		return
	surface = s
	structure_changed.emit()
	changed.emit()


## The effect list named `list` (EFFECTS or VERTEX_EFFECTS).
func effect_list(list: String = EFFECTS) -> Array[Dictionary]:
	return vertex_effects if list == VERTEX_EFFECTS else effects


## Append an effect running `key` ("" = none picked yet).
func add_effect(key: String = "", list: String = EFFECTS) -> void:
	effect_list(list).append({"shader": key, "params": {}})
	structure_changed.emit()
	changed.emit()


func remove_effect(index: int, list: String = EFFECTS) -> void:
	var l := effect_list(list)
	if index < 0 or index >= l.size():
		return
	l.remove_at(index)
	structure_changed.emit()
	changed.emit()


## Move effect `index` by `step` places (-1 = up, runs earlier). No-op at
## the ends of the list.
func move_effect(index: int, step: int, list: String = EFFECTS) -> void:
	var l := effect_list(list)
	var to := index + step
	if index < 0 or index >= l.size() or to < 0 or to >= l.size() or step == 0:
		return
	var effect: Dictionary = l[index]
	l.remove_at(index)
	l.insert(to, effect)
	structure_changed.emit()
	changed.emit()


## Re-pick effect `index`'s shader; its params go back to the defaults.
func set_effect_shader(index: int, key: String, list: String = EFFECTS) -> void:
	var l := effect_list(list)
	if index < 0 or index >= l.size() or l[index].shader == key:
		return
	l[index] = {"shader": key, "params": {}}
	structure_changed.emit()
	changed.emit()


func set_effect_param(index: int, param: String, value: Variant, list: String = EFFECTS) -> void:
	var l := effect_list(list)
	if index < 0 or index >= l.size():
		return
	var params: Dictionary = l[index].params
	if params.get(param) == value:
		return
	params[param] = value
	changed.emit()


## Apply size + position offsets to a mount node. Called whenever the
## settings change or the mount is (re)created. `viewer` is the viewer's eye
## in the mount's parent space: tilt orbits the screen around it (about the
## viewer's right axis, from `viewer_yaw_deg`), so the screen keeps facing
## the viewer at the same distance instead of pitching in place. `pivot` is
## the screen's centre in the mount's space, which size scales about.
func apply_to_mount(mount: Node3D, viewer: Vector3 = Vector3.ZERO, viewer_yaw_deg: float = 0.0,
		pivot: Vector3 = Vector3.ZERO) -> void:
	if mount == null:
		return
	mount.transform = mount_transform(viewer, viewer_yaw_deg, pivot)


## The mount transform apply_to_mount sets. Separate for tests.
func mount_transform(viewer: Vector3 = Vector3.ZERO, viewer_yaw_deg: float = 0.0,
		pivot: Vector3 = Vector3.ZERO) -> Transform3D:
	var scaled := Transform3D(Basis(), pivot) 			* Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3.ZERO) 			* Transform3D(Basis(), -pivot)
	var offset := Transform3D(Basis(), Vector3(0.0, height, -distance)) * scaled
	var right := Basis(Vector3.UP, deg_to_rad(viewer_yaw_deg)) * Vector3.RIGHT
	# Positive rotation about the right axis lifts a point in front of the
	# viewer (-Z) and turns its +Z face down toward them.
	var orbit := Transform3D(Basis(), viewer) 			* Transform3D(Basis(right, deg_to_rad(tilt)), Vector3.ZERO) 			* Transform3D(Basis(), -viewer)
	return orbit * offset


func _set_size(v: float) -> void:
	if v == size:
		return
	size = v
	changed.emit()


func _set_distance(v: float) -> void:
	if v == distance:
		return
	distance = v
	changed.emit()


func _set_height(v: float) -> void:
	if v == height:
		return
	height = v
	changed.emit()


func _set_tilt(v: float) -> void:
	if v == tilt:
		return
	tilt = v
	changed.emit()


func _set_opacity(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if v == opacity:
		return
	opacity = v
	changed.emit()


func _set_resolution(v: float) -> void:
	v = clampf(v, RESOLUTION_MIN, RESOLUTION_MAX)
	if v == resolution:
		return
	resolution = v
	changed.emit()
