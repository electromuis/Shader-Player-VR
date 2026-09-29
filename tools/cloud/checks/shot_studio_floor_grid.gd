extends SceneTree

## Studio's floor grid (TODO 12), driven in the real Studio: 1 m lines on
## the floor in Edit, gone with the Studio tab's Floor grid off and in
## Play, following the camera. Prints what happened; rendered, saves
## studio_floor_grid_*.png to OUT_DIR.

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
	root.get_texture().get_image().save_png(out.path_join("studio_floor_grid_%s.png" % name))


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_floor_grid/piece")
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
	var grid: StudioFloorGrid = studio.floor_grid
	print("edit, setting on: grid visible ", grid.visible)
	await shot("1_edit")

	# Looking down from higher up, off to one side: the lines stay on whole
	# metres as the plane follows.
	studio.stage.desktop_camera.set_view(Vector3(3.4, 4.0, 9.7), Vector3(-40, 20, 0))
	await frames(4)
	print("camera at (3.4, 4, 9.7): grid at ", grid.global_position)
	await shot("2_above")

	# The same without Studio's panels, to see the lines.
	var ui: CanvasLayer = studio.get_node("UI")
	ui.visible = false
	await shot("3_above_clean")
	studio.stage.desktop_camera.set_view(Vector3(0, 1.7, 8), Vector3(-8, 0, 0))
	await shot("4_standing_clean")
	ui.visible = true

	studio.studio_settings.floor_grid = false
	await frames(2)
	print("setting off: grid visible ", grid.visible)
	await shot("5_off")
	studio.studio_settings.floor_grid = true
	await frames(2)
	print("setting on again: grid visible ", grid.visible)

	studio.set_mode(studio.Mode.PLAY)
	await frames(2)
	print("play: grid visible ", grid.visible)
	studio.set_mode(studio.Mode.EDIT)
	await frames(2)
	print("back to edit: grid visible ", grid.visible)
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	quit(0)
