extends SceneTree

## Studio's motion paths (TODO 16), driven in the real Studio: a piece with
## a still screen, a screen that moves over four keys, a cube that moves too
## and a viewer ride. Selects each in turn and says what's drawn; rendered,
## saves studio_paths_*.png to OUT_DIR ("clean": Studio's panels hidden).

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
	root.get_texture().get_image().save_png(out.path_join("studio_paths_%s.png" % name))


func key(t: float, v: Array, interp := "cubic") -> Dictionary:
	return {"t": t, "value": v, "interp": interp}


func spawn(id: String, prefab: String, pos: Array, scale: float) -> Dictionary:
	return {"type": "event", "t": 0.0, "action": "spawn", "id": id, "prefab": prefab,
			"transform": {"position": pos, "rotation_deg": [0.0, 0.0, 0.0], "scale": [scale, scale, scale]}}


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_paths/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	var piece := {
		"format_version": 2,
		"meta": {"title": "Paths"},
		"media": {"video": "clip.mp4", "duration": 20.0},
		"prefabs": {"screen": "res://player/prefabs/screen.tscn", "cube": "res://player/prefabs/cube.tscn"},
		"tracks": [
			spawn("main_screen", "screen", [0.0, 2.0, -2.0], 0.2),
			spawn("screen_2", "screen", [-3.0, 1.5, 0.0], 0.08),
			spawn("cube_1", "cube", [3.0, 0.5, 0.0], 0.4),
			{"type": "transform", "target": "screen_2", "channel": "position", "keyframes": [
				key(0.0, [-3.0, 1.5, 0.0]), key(4.0, [-2.0, 0.6, 2.0]), key(8.0, [0.0, 0.5, 2.5]),
				key(12.0, [1.5, 1.8, 1.0])]},
			{"type": "transform", "target": "cube_1", "channel": "position", "keyframes": [
				key(0.0, [3.0, 0.5, 0.0]), key(6.0, [3.5, 1.5, 2.0]), key(14.0, [2.0, 0.5, 3.5])]},
			{"type": "transform", "target": "$viewer", "channel": "position", "keyframes": [
				key(2.0, [0.0, 2.0, 8.0]), key(9.0, [-1.5, 2.2, 5.0]), key(16.0, [1.0, 2.0, 3.5])]},
		],
	}
	f = FileAccess.open(dir.path_join("clip.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(piece, "  "))
	f.close()
	DirAccess.remove_absolute(dir.path_join("clip.json.autosave"))
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	studio = load("res://studio/studio.tscn").instantiate()
	studio._cli_desktop = true
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.json"))
	await frames(6)
	studio.stage.seek_to(5.0)
	var cam = studio.stage.desktop_camera
	var ui: CanvasLayer = studio.get_node("UI")
	cam.set_view(Vector3(0.5, 4.2, 11.0), Vector3(-18, 0, 0))
	var tools: StudioEditTools = studio.tools
	await frames(4)
	print("playhead ", studio.runner.playhead)
	await shot("1_nothing_selected")

	tools.select("main_screen")
	print("still screen selected: path keys ", tools.path_keys().size())
	await shot("2_still_selected")

	tools.select("screen_2")
	print("moving screen selected: path keys ", tools.path_keys().map(func(k): return k.t))
	await shot("3_moving_selected")
	ui.visible = false
	await shot("4_moving_clean")
	studio.stage.seek_to(8.0)
	await shot("5_on_a_key_clean")
	cam.set_view(Vector3(-8.0, 2.5, 3.0), Vector3(-8, -75, 0))
	await shot("6_from_the_side_clean")
	cam.set_view(Vector3(0.5, 4.2, 11.0), Vector3(-18, 0, 0))

	tools.select("$viewer")
	await shot("7_viewer_clean")

	studio.studio_settings.all_paths = false
	tools.select("cube_1")
	print("all paths off: ", not tools.all_paths)
	await shot("8_cube_only_clean")
	studio.studio_settings.all_paths = true
	ui.visible = true
	print("key labels: ", [0.0, 4.0, 5.93, 80.5].map(func(t): return StudioEditTools.key_time_text(t)))
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	quit(0)
