class_name FloatingPanel
extends Node3D

## World-space UI panel with tabs (Camera / Files / Config / Presets).
## Toggled with the `toggle_menu` command (F2 / ≡ by default). On show,
## positions itself in front of the active camera at `distance_m`, facing
## the viewer. Both desktop mouse
## (via camera raycast → viewport push_input) and VR controllers (via
## XRToolsFunctionPointer, wired in Phase 4b) drive the same Control tree.
## In VR, holding the right grip drags it (begin_drag / end_drag).

const CONTENT_SCENE := preload("res://player/ui/floating_panel_content.tscn")
const VP2D3D_SCENE := preload("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn")
## Transparent objects draw in render-priority order before distance; UI
## panels sit above everything else (0) so a big or curved shader layer
## that sorts oddly never paints over them.
const UI_RENDER_PRIORITY := 100

@export var distance_m: float = 1.2
@export_range(0.5, 3.0) var world_width: float = 1.4
@export var viewport_px: Vector2 = Vector2(900, 600)

var _vp2d3d: XRToolsViewport2DIn3D
var _static_body: StaticBody3D
var _mouse_camera: Camera3D
var _mouse_last: Vector2 = Vector2.ZERO
var _mouse_over_panel: bool = false
## Buttons pressed on the panel and not yet released there. While any is
## held the panel keeps the mouse (like an OS pointer grab): motion stays
## forwarded off its edges and the release always reaches the viewport, so
## a dragged slider can't stay stuck to the cursor.
var _held_buttons: Array[MouseButton] = []
var _drag_by: Node3D  # controller currently carrying the panel, or null
var _drag_offset: Vector3  # panel position in the carrying controller's frame


func _ready() -> void:
	visible = false
	_vp2d3d = VP2D3D_SCENE.instantiate()
	_vp2d3d.scene = CONTENT_SCENE
	_vp2d3d.viewport_size = viewport_px
	var aspect := viewport_px.x / maxf(viewport_px.y, 1.0)
	_vp2d3d.screen_size = Vector2(world_width, world_width / aspect)
	_vp2d3d.material = ui_material()
	add_child(_vp2d3d)
	_static_body = _vp2d3d.get_node_or_null("StaticBody3D")
	# Embed any popup windows (confirm dialogs, tooltips, etc.) inside the
	# SubViewport so they render inline on the 3D quad instead of opening as
	# native OS windows outside the headset. Note: FileDialog specifically is
	# NOT usable this way — its modal grab freezes the root viewport; the
	# Files tab uses an inline ItemList browser instead.
	var sub := _vp2d3d.get_node_or_null("Viewport") as SubViewport
	if sub != null:
		sub.gui_embed_subwindows = true


## The panel's quad (an XRToolsViewport2DIn3D), e.g. for CameraFx to leave
## alone.
func panel_quad() -> Node3D:
	return _vp2d3d


## Material for an XRToolsViewport2DIn3D panel: what it builds itself for
## unshaded + transparent, drawn at UI_RENDER_PRIORITY.
static func ui_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.render_priority = UI_RENDER_PRIORITY
	return m


## Attach the desktop camera whose mouse cursor should drive panel input.
func set_mouse_camera(cam: Camera3D) -> void:
	_mouse_camera = cam


## Return the 2D control tree hosted in the panel's SubViewport. Deferred:
## XRToolsViewport2DIn3D instantiates its scene during its own _ready +
## a post-draw frame, so callers should poll (see main.gd:_bind_panel_content).
func content() -> Node:
	var sub := _vp2d3d.get_node_or_null("Viewport") as SubViewport
	if sub == null:
		return null
	for c in sub.get_children():
		return c
	return null


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		show_in_front_of(_active_camera())


## Currently-rendering camera from the viewport (VR camera when in VR,
## desktop camera otherwise). Falls back to the stored mouse camera if
## the viewport has none for some reason.
func _active_camera() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	return cam if cam != null else _mouse_camera


func show_in_front_of(cam: Camera3D) -> void:
	if cam == null:
		return
	var cam_xform := cam.global_transform
	var forward := -cam_xform.basis.z
	global_position = cam_xform.origin + forward * distance_m
	_face(cam_xform.origin)
	visible = true


## Carry the panel with `by` (a controller) until end_drag(), keeping it at
## the same offset from the controller and turned toward the viewer.
func begin_drag(by: Node3D) -> void:
	if not visible or by == null:
		return
	_drag_by = by
	_drag_offset = by.global_transform.affine_inverse() * global_position


func end_drag() -> void:
	_drag_by = null


## Face `target` (Y-up billboard). look_at points -Z at the target; the quad's
## front is +Z, so turn around.
func _face(target: Vector3) -> void:
	if global_position.is_equal_approx(target):
		return
	look_at(target, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)


func hide_panel() -> void:
	# Hidden panels don't forward input, so a button still held now (e.g. the
	# click that picked a video and closed us) would never see its release and
	# stay stuck down in the SubViewport. Release it here instead.
	_release_held()
	close_popups()
	_mouse_over_panel = false
	_drag_by = null
	visible = false


## Close any dropdown (or other popup) open in the panel, as cancelled.
## Returns whether one was open. A click on the panel outside it already
## closes it; this covers Escape and clicks that miss the panel.
func close_popups() -> bool:
	var sub := _vp2d3d.get_node_or_null("Viewport") as SubViewport if _vp2d3d != null else null
	if sub == null:
		return false
	var closed := false
	for w in sub.get_embedded_subwindows():
		if w is Popup and w.visible:
			w.hide()
			closed = true
	return closed


func _process(_delta: float) -> void:
	if not visible:
		return
	if _drag_by != null:
		global_position = _drag_by.global_transform * _drag_offset
		var cam := _active_camera()
		if cam != null:
			_face(cam.global_position)
	# The desktop mouse only drives the panel while the desktop camera is the
	# one rendering; in VR its stray motion would fight the controller laser.
	if _mouse_camera == null or _static_body == null or not _mouse_camera.current:
		_release_held()
		_mouse_over_panel = false
		return
	_forward_mouse()
	# A release that something else consumed before _unhandled_input (or
	# that happened while unfocused) still has to reach the viewport.
	for button in _held_buttons.duplicate():
		if not Input.is_mouse_button_pressed(button):
			_release(button)


func _forward_mouse() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var mouse_pos := viewport.get_mouse_position()
	var space := _mouse_camera.get_world_3d().direct_space_state
	var from := _mouse_camera.project_ray_origin(mouse_pos)
	var to := from + _mouse_camera.project_ray_normal(mouse_pos) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to, _static_body.collision_layer)
	var hit := space.intersect_ray(query)
	var at: Variant = null
	if not hit.is_empty() and hit.collider == _static_body:
		_mouse_over_panel = true
		at = hit.position
	else:
		_mouse_over_panel = false
		# Mid-drag, follow the cursor across the panel's plane beyond its edges.
		if not _held_buttons.is_empty():
			at = _panel_plane().intersects_ray(from, to - from)
	if at == null:
		return
	var vp_pos: Vector2 = _static_body.global_to_viewport(at)
	if vp_pos != _mouse_last:
		var motion := InputEventMouseMotion.new()
		motion.position = vp_pos
		motion.global_position = vp_pos
		motion.relative = vp_pos - _mouse_last
		motion.button_mask = _button_mask()
		_push(motion)
		_mouse_last = vp_pos


## The quad's plane, from the same shape global_to_viewport() measures in.
func _panel_plane() -> Plane:
	var t := (_static_body.get_node("CollisionShape3D") as Node3D).global_transform
	return Plane(t.basis.z.normalized(), t.origin)


## Escape or a click off the panel cancels an open dropdown, and does
## nothing else (no mouse look, no media key). Keys aren't forwarded to the
## panel, so its popups never see Escape themselves.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var mb := event as InputEventMouseButton
	var click_off := mb != null and mb.pressed and not _mouse_over_panel and _held_buttons.is_empty() \
			and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	var cancel := event.is_action_pressed("ui_cancel") or click_off
	if cancel and close_popups():
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var held := mb.button_index in _held_buttons
		if not _mouse_over_panel and not (held and not mb.pressed):
			return
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed and not held:
				_held_buttons.append(mb.button_index)
			elif not mb.pressed:
				_held_buttons.erase(mb.button_index)
		var out := InputEventMouseButton.new()
		out.button_index = mb.button_index
		out.pressed = mb.pressed
		# Forward double-click so widgets like ItemList / Tree that discriminate
		# single vs. double see the correct flag.
		out.double_click = mb.double_click
		out.position = _mouse_last
		out.global_position = _mouse_last
		out.button_mask = _button_mask()
		_push(out)
		get_viewport().set_input_as_handled()


## Send a release for `button` to the viewport and stop holding it.
func _release(button: MouseButton) -> void:
	_held_buttons.erase(button)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = _mouse_last
	up.global_position = _mouse_last
	up.button_mask = _button_mask()
	_push(up)


func _release_held() -> void:
	for button in _held_buttons.duplicate():
		_release(button)


func _button_mask() -> int:
	var mask := 0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		mask |= MOUSE_BUTTON_MASK_LEFT
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		mask |= MOUSE_BUTTON_MASK_RIGHT
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		mask |= MOUSE_BUTTON_MASK_MIDDLE
	return mask


func _push(event: InputEvent) -> void:
	var sub := _vp2d3d.get_node_or_null("Viewport") as SubViewport
	if sub != null:
		sub.push_input(event)
