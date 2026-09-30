extends SceneTree

## TODO 69 and 25 in the real Studio. 69: a layer card dropped while
## paused just past a millisecond (5.0006 s) spawns by the playhead and
## shows at once. 25: Ctrl+Shift+S opens the shelf's Open tab at its Save
## as line with a free name; saving there goes on with the new file; a name
## that's taken asks "Replace it?" first; saving into another folder brings
## the piece's own shader along and names the video from there. Prints what
## happened; rendered, saves studio_save_as_*.png to OUT_DIR.

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


func press_card(a: Dictionary) -> void:
	var card: Control = studio.shelf.card(a.id)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	card.gui_input.emit(ev)
	await frames(2)


func rm(d: String) -> void:
	for sub in DirAccess.get_directories_at(d):
		rm(d.path_join(sub))
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	DirAccess.remove_absolute(d)


func shoot(name: String, shelf_only: bool) -> void:
	if not rendered:
		return
	await frames(6)
	var img := root.get_texture().get_image()
	if shelf_only:
		img = img.get_region(Rect2i(studio.shelf.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	img.save_png(out.path_join("studio_save_as_%s.png" % name))


func _initialize() -> void:
	var base := OS.get_environment("WORK").path_join("studio_save_as")
	var dir := base.path_join("piece")
	var other := base.path_join("elsewhere")
	rm(base)
	for d in [dir, other]:
		DirAccess.make_dir_recursive_absolute(d)
	DirAccess.make_dir_recursive_absolute(dir.path_join("shaders"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	f = FileAccess.open(dir.path_join("shaders/stripes.glsl"), FileAccess.WRITE)
	f.store_string("void mainImage(out vec4 c, in vec2 p) { c = vec4(vec3(step(0.5, fract(p.x / 40.0))), 1.0); }\n")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	studio._cli_desktop = true
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

	# 69: paused just past a millisecond, a layer card dropped in the space.
	studio.stage.seek_to(5.0006)
	await frames(4)
	studio.shelf_on = true
	studio._show_shelf()
	var shelf: StudioAssetShelf = studio.shelf
	shelf.show_tab("layer")
	await frames(6)
	var stripes := {}
	for a in studio.library.of_type("layer"):
		if a.label.to_lower().contains("stripes"):
			stripes = a
	print("playhead %.4f, playing %s" % [studio.runner.playhead, studio.runner.playing])
	await press_card(stripes)
	var middle := Vector2(root.size) / 2.0
	print("dropped: ", studio.drop_held_at(ray_at(Vector2(middle.x - 250, middle.y - 60))), " '", studio.message, "'")
	await frames(4)
	var m: EditModel = studio.model
	var id := String(m.object_ids().back())
	print("%s spawns at %.4f; on show while paused: %s" % [id, m.tracks()[m.spawn_index(id)].t, reg.get_node_by_id(id) != null])
	await shoot("1_dropped_paused", false)

	# 25: Ctrl+Shift+S.
	studio._on_command(&"studio_save_as")
	await frames(6)
	print("tab: %s, name: '%s', target: %s" % [shelf.tab, shelf._save_name.text, shelf.save_as_target()])
	await shoot("2_open_tab", true)
	shelf.press_save_as()
	await frames(2)
	print("saved as: '%s', path %s, dirty %s, file there %s" % [studio.message, m.path.get_file(), m.is_dirty(), FileAccess.file_exists(m.path)])
	print("clip.spscript still: %s" % FileAccess.file_exists(dir.path_join("clip.spscript")))
	# A taken name asks first.
	shelf._save_name.text = "clip"
	shelf.press_save_as()
	await frames(2)
	print("taken: '%s', button '%s', path still %s" % [studio.message, shelf._save_button.text, m.path.get_file()])
	await shoot("3_replace", true)
	shelf._save_name.text = "clip 2"
	shelf._disarm_save()
	# Another folder.
	shelf._files._navigate_to(other)
	shelf.suggest_save_name()
	await frames(2)
	print("in %s: name '%s'" % [shelf._files.current_dir(), shelf._save_name.text])
	shelf.press_save_as()
	await frames(4)
	print("saved as: '%s', path %s" % [studio.message, m.path])
	print("video named: %s; shader copied: %s" % [m.document().media.video, FileAccess.file_exists(other.path_join("shaders/stripes.glsl"))])
	print("loads: %s; the layer still on show: %s" % [ScriptFormat.load_from_file(m.path).ok, reg.get_node_by_id(id) != null])
	await shoot("4_elsewhere", true)
	print("STUDIO SAVE AS DONE")
	quit()
