extends SceneTree

## Dropping shelf cards on the desktop (TODO 13), in the real Studio: the
## Screen and Cube cards carried over the floor near and far, the carried
## preview with its footprint and distance, then dropped: each lands on the
## floor under the cursor. Prints where things land; rendered, saves
## studio_drop_*.png to OUT_DIR.

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
	root.get_texture().get_image().save_png(out.path_join("studio_drop_%s.png" % name))


func ray_at(at: Vector2) -> Transform3D:
	var cam: Camera3D = studio.stage.desktop_camera
	var dir := cam.project_ray_normal(at)
	return Transform3D(Basis.looking_at(dir, Vector3.UP), cam.project_ray_origin(at))


func object(label: String) -> Dictionary:
	for a in studio.library.of_type("object"):
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


## Carry `a` to the window point `at` (a fraction of its size) and shoot.
func carry(a: Dictionary, at: Vector2, name: String) -> void:
	await press_card(a)
	# The per-frame carry follows the real mouse; aim by hand instead.
	studio.set_process(false)
	var vp := Vector2(root.size)
	studio.show_carry(ray_at(at * vp))
	studio._ghost.visible = true
	studio._show_status()
	print("%s at %s: '%s'" % [a.label, at, studio.message])
	await shot(name)


func drop(at: Vector2) -> void:
	var vp := Vector2(root.size)
	var head: Vector3 = studio.stage.viewer_transform().origin
	studio.drop_held_at(ray_at(at * vp))
	studio.set_process(true)
	var id: String = studio.tools.selected
	var n: Node3D = studio.runner.registry().get_node_by_id(id)
	var p := n.global_position
	print("  dropped: '%s' -> %s at (%.2f, %.2f, %.2f), %.1f m away" % [studio.message, id, p.x, p.y, p.z,
			Vector2(p.x - head.x, p.z - head.z).length()])


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_drop/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(30.0)
	studio.stage.desktop_camera.set_view(Vector3(0, 1.7, 12), Vector3(-14, 0, 0))
	studio.status_view.show_hints(false)
	studio.shelf_on = true
	studio._show_shelf()
	studio.shelf.show_tab("object")
	await frames(4)
	var screen := object("Screen")
	var cube := object("Cube")
	# Near, below the main screen: it used to stick to the main screen's
	# face, 12 m off.
	await carry(screen, Vector2(0.72, 0.7), "1_screen_near")
	await drop(Vector2(0.72, 0.7))
	await carry(cube, Vector2(0.45, 0.62), "2_cube_mid")
	await drop(Vector2(0.45, 0.62))
	await carry(cube, Vector2(0.3, 0.52), "3_cube_far")
	await drop(Vector2(0.3, 0.52))
	# Above the horizon: on the main screen's face, as before.
	await carry(cube, Vector2(0.62, 0.3), "4_cube_on_screen")
	await drop(Vector2(0.62, 0.3))
	# An effect goes onto the thing it's on: just the card, no footprint.
	studio.shelf.show_tab("effect")
	await frames(2)
	await carry(studio.library.of_type("effect")[0], Vector2(0.55, 0.3), "5_effect_on_screen")
	studio._drop_held()
	studio.set_process(true)
	await shot("6_after")
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	quit(0)
