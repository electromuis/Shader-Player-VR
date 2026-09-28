extends SceneTree

## Studio's desktop window with its status and shortcut table, at the
## default UI scale, hidden (H), and at 150% (the Config tab's UI scale,
## shared with the player). Saves studio_hints_*.png to OUT_DIR.

var studio: Node
var out := OS.get_environment("OUT_DIR")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	var piece_dir := OS.get_environment("WORK").path_join("studio_hints/piece")
	DirAccess.make_dir_recursive_absolute(piece_dir)
	var f := FileAccess.open(piece_dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	studio.open_piece(piece_dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(30.0)
	var settings: PlayerSettings = studio._settings
	studio._on_command(&"studio_toggle_hints")
	await frames(12)
	print("hints hidden: status %s, shelf top %s" % [studio.status_view.size, studio.shelf.offset_top])
	root.get_texture().get_image().save_png(out.path_join("studio_hints_hidden.png"))
	studio._on_command(&"studio_toggle_hints")
	for scale in [1.0, 1.5]:
		settings.ui_scale = scale
		await frames(12)
		print("ui_scale %s: content_scale_factor %s, status %s" % [scale, root.content_scale_factor, studio.status_view.size])
		root.get_texture().get_image().save_png(out.path_join("studio_hints_%d.png" % roundi(scale * 100.0)))
	settings.ui_scale = 1.0
	quit()
