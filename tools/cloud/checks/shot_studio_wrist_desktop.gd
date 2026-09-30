extends SceneTree

## The wrist palette on the desktop (TODO 68), in the real Studio: the top
## left corner shows the status or the wrist palette, switched by its two
## tabs or P; mouse clicks (through the whole window's input, as a real
## click) press its tiles; a mouse swipe across it turns the page, while the
## same drag over the 3D view doesn't; a click on it doesn't select in the
## world; right-drag look keeps turning with the cursor over it; the shelf
## moves under it; Play hides it, Edit brings it back; it gets smaller in a
## short window. Prints what happened; rendered, saves
## studio_wrist_desktop_*.png (the window) to OUT_DIR. Run it rendered, at
## 1920x1080 (headless, the window is too small to click in).

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
	root.get_texture().get_image().save_png(out.path_join("studio_wrist_desktop_%s.png" % name))


func key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.pressed = pressed
		studio.stage.router.handle_key(ev)
	await frames(2)


## A press at `from` and a let-go at `to`, window pixels, through the
## window's own input (GUI first, then the 3D view). The real cursor goes
## there too: a stray motion of it would take the press off the button.
func drag(from: Vector2, to: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for step in [[from, true], [to, false]]:
		Input.warp_mouse(step[0])
		var mv := InputEventMouseMotion.new()
		mv.position = step[0]
		mv.global_position = step[0]
		root.push_input(mv)
		await frames(1)
		var b := InputEventMouseButton.new()
		b.button_index = button
		b.position = step[0]
		b.global_position = step[0]
		b.pressed = step[1]
		root.push_input(b)
		await frames(2)


func click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	await drag(at, at)
	if OS.get_environment("DEBUG") != "":
		print("  click at ", at, " on ", c, ": hovered ", root.gui_get_hovered_control())


func state() -> String:
	var w: StudioWristPalette = studio.wrist_2d
	return "palette %s (shown %s) at %s ×%.2f, status shown %s, tabs shown %s, shelf top %d, page %d, auto-key %s, snap %s, selected '%s'; '%s'" % [
			studio.wrist_on, w.visible, w.position, w.scale.x, studio.status_view.visible, studio.corner_tabs.visible,
			studio.shelf.get_global_rect().position.y, w.page, studio.tools.auto_key, studio.tools.snap,
			studio.tools.selected, studio.message]


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_wrist_desktop/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.spscript"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	studio._cli_desktop = true  # as --desktop: a PC with an OpenXR runtime would go into VR
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(185.0)
	studio.tools.auto_key = false
	studio.tools.key_animated = false
	studio.tools.snap = false
	studio.tools.select("main_screen")
	studio.stage.seek_to(83.4)
	await frames(4)
	print("P is bound to: ", studio.stage.router.bindings.bindings_on("studio_edit", "key:P").map(func(x): return x[0]))
	print("status: ", state())
	await shot("0_status")

	await key(KEY_P)
	await frames(3)
	print("P: ", state())
	var w: StudioWristPalette = studio.wrist_2d
	var r := w.get_global_rect()
	print("palette rect ", r, ", shelf ", studio.shelf.get_global_rect())
	await shot("1_palette")

	# Clicks on tiles.
	await click(w.tile(&"studio_toggle_autokey"))
	await click(w.tile(&"studio_toggle_snap"))
	print("clicked Auto-key, Snap: ", state())
	var lit := []
	for id in w._tiles:
		if w._tiles[id].lit:
			lit.append(String(id).trim_prefix("studio_"))
	print("lit: ", lit, "; line '", w._line.text, "'")
	# Hover help from a mouse move over a tile.
	var mv := InputEventMouseMotion.new()
	mv.position = w.tile(&"studio_record").get_global_rect().get_center()
	mv.global_position = mv.position
	Input.warp_mouse(mv.position)
	root.push_input(mv)
	await frames(3)
	print("pointer on Record: line '", w._line.text, "'")
	await shot("2_clicked_hover")

	# A click on the palette's header doesn't reach the world (a click on
	# empty space there would deselect).
	await click(w._title)
	print("click on the header: selected '", studio.tools.selected, "'")

	# A swipe across it turns the page; the same drag over the 3D view (the
	# sky: it deselects) doesn't.
	var mid := r.get_center()
	await drag(mid + Vector2(120, 0), mid - Vector2(120, 0))
	print("swipe left on it: page ", w.page)
	await shot("3_page2")
	await drag(Vector2(1100, 120), Vector2(860, 120))
	print("the same drag over the 3D view: page ", w.page)
	studio.tools.select("main_screen")
	await drag(mid - Vector2(120, 0), mid + Vector2(120, 0))
	print("swipe right on it: page ", w.page)

	# Right-drag look: pressed in the 3D view, the moves (the captured cursor
	# reported over the palette) still turn the view.
	var cam: Camera3D = studio.stage.desktop_camera
	var yaw := cam.rotation.y
	Input.warp_mouse(Vector2(1100, 120))
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_RIGHT
	b.position = Vector2(1100, 120)
	b.pressed = true
	# Through Input, as a real mouse: the camera checks the button is held.
	Input.parse_input_event(b)
	await frames(2)
	for i in 5:
		var look := InputEventMouseMotion.new()
		look.position = mid
		look.button_mask = MOUSE_BUTTON_MASK_RIGHT
		look.relative = Vector2(-40, 0)
		Input.parse_input_event(look)
		await frames(1)
	b = b.duplicate()
	b.pressed = false
	Input.parse_input_event(b)
	await frames(2)
	print("right-drag look over the palette: turned %.1f°, mouse mode %d" % [rad_to_deg(cam.rotation.y - yaw), Input.mouse_mode])

	# Undo from page 1 undoes (a real change first).
	studio.model.set_spawn_transform("main_screen", {"position": [0.0, 2.2, -12.0], "rotation_deg": [0.0, 0.0, 0.0], "scale": [0.12, 0.12, 0.12]})
	await frames(2)
	await click(w.tile(&"studio_undo"))
	print("clicked Undo: '", studio.message, "', dirty ", studio.model.is_dirty())

	# The switch: Play hides it (as on the wrist), Edit brings it back.
	await click(w._play_half)
	print("clicked Play: mode ", studio.mode, ", ", state())
	await key(KEY_TAB)
	print("Tab back to Edit: ", state())

	# The corner's tabs switch back and forth; the open one's tab closes it
	# (TODO 74), and opens it again.
	await click(studio.corner_tabs.get_child(0))
	print("Status tab: ", state())
	await click(studio.corner_tabs.get_child(0))
	print("Status tab again (closes it): ", state())
	await shot("3b_corner_closed")
	await click(studio.corner_tabs.get_child(0))
	print("Status tab again (opens it): ", state())
	await click(studio.corner_tabs.get_child(1))
	print("Wrist tab: ", state())
	await click(studio.corner_tabs.get_child(1))
	print("Wrist tab again (closes it): ", state())
	await key(KEY_P)
	print("P (opens the status): ", state())
	await click(studio.corner_tabs.get_child(1))
	print("Wrist tab: ", state())

	# The shelf folded: the palette takes the room; a short window: smaller.
	studio._on_command(&"studio_toggle_shelf")
	await frames(3)
	print("shelf off: ", state())
	await shot("4_no_shelf")
	studio._on_command(&"studio_toggle_shelf")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var was := root.size
	root.size = Vector2i(1280, 720)
	await frames(4)
	print("1280x720: ", state())
	await shot("5_small_window")
	root.size = was
	await key(KEY_P)
	print("P again: ", state())
	quit()
