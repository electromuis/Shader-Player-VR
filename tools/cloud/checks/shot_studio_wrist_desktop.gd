extends SceneTree

## The wrist palette on the desktop (TODO 68), in the real Studio: P and the
## status's Wrist button open and close it; mouse clicks (through the whole
## window's input, as a real click) press its tiles and its Save; a mouse
## swipe across it turns the page, while the same drag over the 3D view
## doesn't; a click on it doesn't select in the world; Play hides it, Edit
## brings it back; it gets smaller in a short window. Prints what happened;
## rendered, saves studio_wrist_desktop_*.png (the window) to OUT_DIR. Run
## it rendered, at 1920x1080 (headless, the window is too small to click in).

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
func drag(from: Vector2, to: Vector2) -> void:
	for step in [[from, true], [to, false]]:
		Input.warp_mouse(step[0])
		var mv := InputEventMouseMotion.new()
		mv.position = step[0]
		mv.global_position = step[0]
		root.push_input(mv)
		await frames(1)
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
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
	return "open %s (shown %s) at %s ×%.2f, page %d, auto-key %s, snap %s, selected '%s', button lit %s; '%s'" % [
			studio.wrist_on, w.visible, w.position, w.scale.x, w.page, studio.tools.auto_key, studio.tools.snap,
			studio.tools.selected, studio.status_view._wrist_button.get_meta("open", false), studio.message]


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_wrist_desktop/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
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
	print("closed: ", state())
	await shot("0_closed")

	await key(KEY_P)
	await frames(3)
	print("P: ", state())
	var w: StudioWristPalette = studio.wrist_2d
	var r := w.get_global_rect()
	print("palette rect ", r, ", inspector ", studio.inspector.get_global_rect(), ", timeline top ", studio.ribbon.get_global_rect().position.y)
	await shot("1_open")

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

	# A swipe across it turns the page; the same drag over the 3D view doesn't.
	var mid := r.get_center()
	await drag(mid + Vector2(120, 0), mid - Vector2(120, 0))
	print("swipe left on it: page ", w.page)
	await shot("3_page2")
	await drag(Vector2(300, 500), Vector2(60, 500))
	print("the same drag over the 3D view: page ", w.page)
	await drag(mid - Vector2(120, 0), mid + Vector2(120, 0))
	print("swipe right on it: page ", w.page)

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

	# The status's button closes and opens it.
	await click(studio.status_view._wrist_button)
	print("Wrist button: ", state())
	await shot("4_closed_by_button")
	await click(studio.status_view._wrist_button)
	print("Wrist button again: ", state())

	# The inspector folded: it moves right; a short window: it shrinks.
	studio._on_command(&"studio_toggle_inspector")
	await frames(3)
	print("inspector off: ", state())
	await shot("5_no_inspector")
	studio._on_command(&"studio_toggle_inspector")
	# The shortcuts hidden (H): the status is short, it goes under it, bigger.
	await key(KEY_H)
	await frames(3)
	print("shortcuts hidden: ", state())
	await shot("5b_no_hints")
	await key(KEY_H)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var was := root.size
	root.size = Vector2i(1280, 720)
	await frames(4)
	print("1280x720: ", state())
	await shot("6_small_window")
	root.size = was
	await key(KEY_P)
	print("P again: ", state())
	quit()
