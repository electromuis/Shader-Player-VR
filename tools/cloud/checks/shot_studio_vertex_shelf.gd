extends SceneTree

## The shelf's Vertex tab in the real Studio: its cards (Spin and Pulse
## among the built-ins) with their pictures, a card carried onto the screen
## the way the mouse does (it joins the screen's vertex effects, one undo
## step), refused on the floor, and the inspector's list showing it. Prints
## what happened; rendered, saves studio_vertex_*.png to OUT_DIR.

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func ray_at(at: Vector2) -> Transform3D:
	var cam: Camera3D = studio.stage.desktop_camera
	var dir := cam.project_ray_normal(at)
	return Transform3D(Basis.looking_at(dir, Vector3.UP), cam.project_ray_origin(at))


func asset(label: String) -> Dictionary:
	for a in studio.library.of_type("vertex"):
		if a.label == label:
			return a
	return {}


func press_card(a: Dictionary) -> void:
	var card: Control = studio.shelf.card(a.id)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	card.gui_input.emit(ev)
	await frames(2)


func test_cards() -> void:
	var reg: ObjectRegistry = studio.runner.registry()
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(StudioThumbnailer.test_card())


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_vertex/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(30.0)
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2.0, 7)
	cam.look_at(Vector3(0, 2.0, 0))
	studio.shelf_on = true
	studio._show_shelf()
	var shelf: StudioAssetShelf = studio.shelf
	shelf.show_tab("vertex")
	await frames(4)
	print("tabs: ", StudioAssetLibrary.TYPES.map(func(t): return StudioAssetLibrary.TYPE_LABELS[t]))
	print("vertex cards: ", studio.library.of_type("vertex").map(func(a): return a.label))
	print("hint: ", shelf._hint.text)
	for i in 900:
		await process_frame
		if not studio.thumbnailer.is_busy():
			break
	await frames(4)

	# Spin on the floor: refused. Then onto main_screen (the middle of the view).
	var middle := Vector2(root.size) / 2.0
	await press_card(asset("Spin"))
	print("let go on the floor: ", studio.drop_held_at(ray_at(Vector2(middle.x, root.size.y - 5))), " '", studio.message, "'")
	await press_card(asset("Spin"))
	print("let go on the screen: ", studio.drop_held_at(ray_at(middle)), " '", studio.message, "'")
	await frames(4)
	var m: EditModel = studio.model
	print("vertex effects: ", m.effects_of("main_screen", EditModel.VERTEX_EFFECTS).map(func(e): return e.shader),
			", undo '", m.undo_label(), "'")
	print("the screen runs: ", reg.get_node_by_id("main_screen")._vertex_effects.map(func(e): return e.shader.get_file().get_basename()))
	studio.tools.select("main_screen")
	studio.inspector.set_section_open("Transform", false)
	await frames(6)
	print("inspector rows: ", studio.inspector._fx_rows.map(func(r): return "%s%d" % [r.list.left(1), r.index]))
	if rendered:
		test_cards()
		await frames(20)
		root.get_texture().get_image().save_png(out.path_join("studio_vertex_1_window.png"))
		var img := root.get_texture().get_image()
		img.get_region(Rect2i(shelf.get_global_rect())).save_png(out.path_join("studio_vertex_2_shelf.png"))
	m.undo()
	print("undo: ", m.effects_of("main_screen", EditModel.VERTEX_EFFECTS))
	print("STUDIO VERTEX SHELF DONE")
	quit()
