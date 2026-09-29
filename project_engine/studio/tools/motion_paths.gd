class_name StudioMotionPaths
extends Node3D

## Draws motion paths so they're easy to see (TODO 16): each path is a band
## facing the camera, a set number of pixels wide wherever it is, with a
## diamond at each key and the key's time beside it. StudioEditTools says
## what to draw each frame (begin, path, keys, end); this only draws.
##
## Widths and sizes are in pixels of the view (for the camera drawing the
## frame), so a path far away stays as easy to see as one near by. Labels
## that would crowd each other are left out, and so are diamonds closer than
## a few pixels (a baked track has a key every frame or so).

## Labels closer than this to one already shown are left out (pixels).
const LABEL_GAP := 56.0
## Diamonds closer than this to the one before are left out (pixels).
const DIAMOND_GAP := 7.0
## Where a key's label sits from its diamond (pixels, right and up).
const LABEL_OFFSET := Vector2(12.0, 12.0)
const LABEL_OUTLINE := Color(0.06, 0.08, 0.11, 0.9)

var _mesh := ImmediateMesh.new()
var _mesh_instance: MeshInstance3D
var _labels: Array[Label3D] = []
var _used := 0
var _verts := PackedVector3Array()
var _colors := PackedColorArray()
## The camera this frame: where it is, its right and up, and how many
## metres a pixel is one metre away.
var _cam_pos := Vector3.ZERO
var _cam_right := Vector3.RIGHT
var _cam_up := Vector3.UP
var _px := 0.001
var _ortho := false
## Labels shown this frame, as directions from the camera (for LABEL_GAP).
var _label_dirs: Array[Vector3] = []


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	_mesh_instance.top_level = true
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = 16384.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 49  # under the selection's lines (50)
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


## Start a frame, for `camera` (null: nothing is drawn this frame).
func begin(camera: Camera3D) -> bool:
	_verts.clear()
	_colors.clear()
	_used = 0
	_label_dirs.clear()
	if camera == null:
		return false
	var xf := camera.global_transform
	_cam_pos = xf.origin
	_cam_right = xf.basis.x.normalized()
	_cam_up = xf.basis.y.normalized()
	var h := maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
	_ortho = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	if _ortho:
		_px = camera.size / h  # no perspective: the same everywhere (see _scale)
	else:
		_px = 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / h
	return true


## Finish the frame: the bands and diamonds drawn, unused labels hidden.
func end() -> void:
	_mesh.clear_surfaces()
	if not _verts.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in _verts.size():
			_mesh.surface_set_color(_colors[i])
			_mesh.surface_add_vertex(_verts[i])
		_mesh.surface_end()
	for i in range(_used, _labels.size()):
		_labels[i].visible = false


## A path through `points` ([world point, joined to the one before]),
## `width` pixels wide. Points at or before `split` (an index; -1 for none)
## are drawn in `before`, the rest in `color`.
func path(points: Array, color: Color, width: float, split: int = -1, before: Color = Color()) -> void:
	for i in range(1, points.size()):
		if not points[i][1]:
			continue
		_band(points[i - 1][0], points[i][0], before if i <= split else color, width)


## Diamonds at `marks` ([{world, color, size (pixels), label (optional),
## keep (optional: shown however crowded)}]),
## the crowded ones left out (their labels too).
func keys(marks: Array) -> void:
	var last_dir := Vector3.ZERO
	for m in marks:
		var p: Vector3 = m.world
		var dir := (p - _cam_pos).normalized()
		var keep := bool(m.get("keep", false))
		if last_dir != Vector3.ZERO and not keep and last_dir.angle_to(dir) < DIAMOND_GAP * _px:
			continue
		last_dir = dir
		_diamond(p, m.color, float(m.size))
		if String(m.get("label", "")) != "":
			label(p, m.label, m.color, true)


## A time or name beside `at` (pixels right and up of it with `offset`), in
## `color`. With `thin`, left out when another label is too close.
func label(at: Vector3, text: String, color: Color, thin: bool = false) -> void:
	var dir := (at - _cam_pos).normalized()
	if thin:
		for d in _label_dirs:
			if d.angle_to(dir) < LABEL_GAP * _px:
				return
	_label_dirs.append(dir)
	var l := _label()
	var s := _scale(at)
	l.global_position = at + (_cam_right * LABEL_OFFSET.x + _cam_up * LABEL_OFFSET.y) * s
	l.text = text
	l.modulate = Color(color, 1.0)
	l.visible = true


## A band from `a` to `b`, `width` pixels wide, facing the camera.
func _band(a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var along := b - a
	if along.length_squared() < 1e-10:
		return
	var mid := (a + b) * 0.5
	var side := along.cross(mid - _cam_pos)
	if side.length_squared() < 1e-12:
		return
	side = side.normalized()
	var sa := side * (_scale(a) * width * 0.5)
	var sb := side * (_scale(b) * width * 0.5)
	_tri(a - sa, a + sa, b + sb, color)
	_tri(a - sa, b + sb, b - sb, color)


## A diamond facing the camera at `p`, `size` pixels across, with a dark rim.
func _diamond(p: Vector3, color: Color, size: float) -> void:
	var s := _scale(p)
	var r := _cam_right * s
	var u := _cam_up * s
	var outer := size * 0.5 + 1.5
	var rim := Color(LABEL_OUTLINE, minf(color.a, 0.9))
	_quad(p + u * outer, p + r * outer, p - u * outer, p - r * outer, rim)
	var inner := size * 0.5
	_quad(p + u * inner, p + r * inner, p - u * inner, p - r * inner, color)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(a, b, c, color)
	_tri(a, c, d, color)


func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_verts.append(a)
	_verts.append(b)
	_verts.append(c)
	_colors.append(color)
	_colors.append(color)
	_colors.append(color)


## Metres per pixel at `p`.
func _scale(p: Vector3) -> float:
	if _ortho:
		return _px
	return maxf(p.distance_to(_cam_pos), 0.05) * _px


func _label() -> Label3D:
	if _used < _labels.size():
		_used += 1
		return _labels[_used - 1]
	var l := Label3D.new()
	l.top_level = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 26
	l.outline_size = 16
	l.outline_modulate = Color(LABEL_OUTLINE, 1.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.no_depth_test = true
	l.render_priority = 52
	l.outline_render_priority = 51
	l.layers = _mesh_instance.layers  # a helper's layer, like the rest
	add_child(l)
	_labels.append(l)
	_used += 1
	return l
