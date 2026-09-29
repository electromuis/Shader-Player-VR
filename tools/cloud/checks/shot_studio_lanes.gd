extends SceneTree

## The timeline's lanes (TODO 64), in the real Studio on a copy of
## forest_tunnel (13 objects, more than the desktop strip shows): the
## lanes' scroll bar down the right, and the triangle before each animated
## object's name that shows or hides its property rows. Driven with the
## ribbon's own pointer events: open a second object's rows, fold the
## selection's, drag the scroll bar's thumb to the bottom, press beside it,
## the wheel over the lanes. Prints what each step did; rendered, saves
## studio_lanes_*.png (the ribbon, cropped) to OUT_DIR.

var studio: Node
var ribbon: StudioTimelineRibbon
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


## A pointer event on the ribbon's canvas at `at` (its own coordinates).
func pointer(at: Vector2, pressed := true, button := MOUSE_BUTTON_LEFT, motion := false) -> void:
	var ev: InputEvent
	if motion:
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
	ev.position = at
	ribbon._canvas_input(ev)
	await frames(2)


func click(at: Vector2) -> void:
	await pointer(at)
	await pointer(at, false)


## Where lane `id`'s open / fold triangle is, on the canvas (it must be in
## the layout: drawn at least once).
func fold_at(id: String) -> Vector2:
	for item in ribbon._layout:
		if item.kind == "lane" and item.id == id:
			return Vector2(item.fold - ribbon._fold * 0.5, item.y + item.h * 0.5)
	return Vector2(-1, -1)


func state() -> String:
	var open := ribbon._rows.keys().filter(func(id): return ribbon.is_open(id))
	return "open %s, %d px of lanes, scrolled %.0f of %.0f" % [open, ribbon._lanes_height(), ribbon._vscroll, ribbon._vscroll_max()]


func shot(name: String) -> void:
	if not rendered:
		return
	await frames(6)
	var img := root.get_texture().get_image()
	img.get_region(Rect2i(ribbon.get_global_rect())).save_png(out.path_join("studio_lanes_%s.png" % name))


func copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))


func _initialize() -> void:
	var repo := OS.get_environment("REPO")
	var piece_dir := OS.get_environment("WORK").path_join("studio_lanes_piece")
	copy_dir(repo.path_join("scripts/forest_tunnel"), piece_dir)
	copy_dir(repo.path_join("scripts/forest_tunnel/prefabs"), piece_dir.path_join("prefabs"))

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	ribbon = studio.ribbon
	print("open: ", studio.open_piece(piece_dir.path_join("video.json")))
	studio.runner.set_video_duration(170.0)
	studio.stage.seek_to(40.0)
	await frames(12)
	var animated: Array = ribbon._rows.keys()
	print("lanes: %d, with property rows: %s" % [ribbon._lanes.size(), animated])
	var first: String = animated[0]
	var second: String = animated[1]
	studio.tools.select(first)
	await frames(4)
	print("selected %s: %s" % [first, state()])
	await shot("1_selected")

	print("the triangle of %s: '%s'; its name: '%s'" % [second, ribbon.hit(fold_at(second)).get("kind", ""),
			ribbon.hit(fold_at(second) + Vector2(ribbon._fold * 2.0, 0)).get("kind", "")])
	await click(fold_at(second))
	print("opened %s: %s (still selected: %s)" % [second, state(), studio.tools.selected])
	await shot("2_two_open")

	var rs: Array = ribbon._vbar_rects()
	var thumb: Rect2 = rs[1]
	print("thumb %s in %s: '%s'" % [thumb, rs[0], ribbon.hit(thumb.get_center()).get("kind", "")])
	await pointer(thumb.get_center())
	await pointer(thumb.get_center() + Vector2(0, rs[0].size.y * 0.5), true, MOUSE_BUTTON_LEFT, true)
	await pointer(Vector2(thumb.get_center().x, rs[0].end.y + 40), true, MOUSE_BUTTON_LEFT, true)
	await shot("3_dragging_down")
	await pointer(Vector2(thumb.get_center().x, rs[0].end.y + 40), false)
	print("thumb dragged past the bottom: ", state())
	for i in 3:
		await pointer(Vector2(ribbon._gutter + 200, ribbon._lanes_bottom() - 30), true, MOUSE_BUTTON_WHEEL_UP)
	print("the wheel up three times over the lanes: ", state())
	await click(Vector2(thumb.get_center().x, rs[0].position.y + 2))
	print("pressed at the top of the track: ", state())

	await click(fold_at(first))
	print("folded %s (the selection): %s" % [first, state()])
	await shot("4_selection_folded")
	studio.tools.select(second)
	await frames(4)
	studio.tools.select(first)
	await frames(4)
	print("reselected %s: stays folded %s" % [first, not ribbon.is_open(first)])

	# A key in the open, unselected object's row can be picked.
	for item in ribbon._layout:
		if item.kind == "prop" and not item.row.keys.is_empty():
			var at := Vector2(ribbon._gutter + ribbon.view.x_of(item.row.keys[0].t), item.y + item.h * 0.5)
			var h := ribbon.hit(at)
			print("a key of %s: '%s'" % [item.row.label, h.get("kind", "")])
			break
	# All folded: the lanes still overflow the desktop strip, so the thumb stays.
	await click(fold_at(second))
	await frames(2)
	print("all folded: %s, thumb %s, hit there '%s'" % [state(), ribbon._vbar_rects()[1].size,
			ribbon.hit(Vector2(ribbon._right() + 4, ribbon._lanes_bottom() - 10)).get("kind", "")])
	await shot("5_all_folded")
	quit(0)
