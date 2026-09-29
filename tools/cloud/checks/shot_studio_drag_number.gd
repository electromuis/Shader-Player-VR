extends SceneTree

## TODO 60: dragging the inspector's transform numbers, driven with real
## mouse events in the main scene: a drag on position x (a live preview,
## one undo step on release), Shift for finer, a Uniform scale drag, a
## click without a drag (the number is typed into), and a drag in the
## headset panel's viewport. Prints what happened; rendered, saves
## studio_drag_number_*.png to OUT_DIR (the desktop inspector mid-drag).

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	if not rendered:
		return
	await frames(6)
	var img := root.get_texture().get_image()
	var r := Rect2i(studio.inspector.get_global_rect())
	img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(out.path_join("studio_drag_number_%s.png" % name))


func button(vp: Viewport, at: Vector2, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = at
	e.global_position = at
	e.shift_pressed = shift
	vp.push_input(e, true)


func move(vp: Viewport, from: Vector2, to: Vector2, shift := false) -> void:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = to
	e.global_position = to
	e.relative = to - from
	e.shift_pressed = shift
	vp.push_input(e, true)


## Press on `spin`, move `dx` px sideways in steps, release (rendering
## `shot_name` before the release if given).
func drag(vp: Viewport, spin: SpinBox, dx: float, shift := false, shot_name := "") -> void:
	var at := spin.get_line_edit().get_global_rect().get_center()
	button(vp, at, true, shift)
	await frames(1)
	var steps := 10
	for i in steps:
		var to := at + Vector2(dx / steps, 0.0)
		move(vp, at, to, shift)
		at = to
		await frames(1)
	if shot_name != "":
		await shot(shot_name)
	button(vp, at, false, shift)
	await frames(3)


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_drag_number/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	if studio.stage.xr_mode.is_in_vr():  # a runtime on this machine (SteamVR): the desktop inspector is wanted
		studio.stage.xr_mode.exit_vr()
		await frames(4)
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(55.0)
	var m: EditModel = studio.model
	studio.tools.select("main_screen")
	var ins: StudioInspector = studio.inspector
	await frames(8)
	print("inspector visible: %s" % ins.visible)
	var now := func() -> Dictionary: return GrabMath.to_dict(reg.get_node_by_id("main_screen").transform)
	var spin := func(view: StudioInspector, ch: String, c: int) -> SpinBox:
		for t in view._t_rows:
			if t.channel == ch:
				return t.spins[c]
		return null

	# Position x, 120 px right: 1.2 m, previewed before the release.
	var x0: float = now.call().position[0]
	var undo0 := m.undo_label()
	await drag(root, spin.call(ins, "position", 0), 120.0, false, "1_mid_drag")
	print("drag x +120px: %.2f → %.2f ('%s', was '%s')" % [x0, now.call().position[0], m.undo_label(), undo0])
	m.undo()
	await frames(3)
	print("one undo: x %.2f" % now.call().position[0])

	# Mid-drag preview: nothing written until the release.
	await frames(20)
	var sx: SpinBox = spin.call(ins, "position", 0)
	var at := sx.get_line_edit().get_global_rect().get_center()
	button(root, at, true)
	await frames(1)
	move(root, at, at + Vector2(-60, 0))
	await frames(2)
	print("mid-drag -60px: node x %.2f, spawn written %s, spin shows %.2f" % [now.call().position[0],
			m.tracks()[m.spawn_index("main_screen")].transform.get("position", [0, 0, 0])[0] != x0, sx.value])
	button(root, at + Vector2(-60, 0), false)
	await frames(3)
	print("released: x %.2f ('%s')" % [now.call().position[0], m.undo_label()])

	# Shift: a tenth as far.
	var r0: float = now.call().rotation_deg[1]
	await drag(root, spin.call(ins, "rotation_deg", 1), 100.0, true)
	print("shift drag rotation y +100px: %.1f → %.1f" % [r0, now.call().rotation_deg[1]])

	# Uniform scale: y dragged, x and z follow; never below its step.
	ins.uniform_scale = true
	var s0: Array = now.call().scale
	await drag(root, spin.call(ins, "scale", 1), 100.0)
	print("uniform scale drag +100px: %s → %s" % [s0, now.call().scale])
	await drag(root, spin.call(ins, "scale", 1), -2000.0)
	print("scale dragged far down: %s" % [now.call().scale])

	# A click without a drag: it's typed into, and a typed value is written.
	await frames(20)
	var sz: SpinBox = spin.call(ins, "position", 2)
	var zc := sz.get_line_edit().get_global_rect().get_center()
	button(root, zc, true)
	move(root, zc, zc + Vector2(2, 0))  # under the dead zone
	button(root, zc + Vector2(2, 0), false)
	await frames(2)
	print("click: typing %s, selected '%s'" % [sz.get_line_edit().has_focus(), sz.get_line_edit().get_selected_text()])
	await shot("2_click_types")
	sz.get_line_edit().text = "-3.5"
	sz.get_line_edit().text_submitted.emit("-3.5")
	await frames(3)
	if is_instance_valid(sz):
		sz.get_line_edit().release_focus()
	print("typed z -3.5: %.2f ('%s')" % [now.call().position[2], m.undo_label()])

	# The headset panel: the same drag through its own viewport.
	studio.inspector_panel.visible = true
	studio._place_inspector_panel()
	await frames(6)
	var vr_view: StudioInspector = studio._vr_inspector()
	await frames(4)
	var sub: SubViewport = studio.inspector_panel.get_node("Viewport")
	var y0: float = now.call().position[1]
	await drag(sub, spin.call(vr_view, "position", 1), 50.0)
	print("headset drag y +50px: %.2f → %.2f ('%s')" % [y0, now.call().position[1], m.undo_label()])
	studio.inspector_panel.visible = false
	print("STUDIO DRAG NUMBER DONE")
	quit()
