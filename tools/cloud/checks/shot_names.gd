extends SceneTree

## The names (TODO 72, 73) in the real Studio: its window title, Studio with
## nothing open (the status, the shelf's Open tab listing a folder with an
## SPScript, a video and a stray .json), then a new SPScript made for a
## video (`clip.mp4` → `clip.spscript`). Prints what happened; rendered,
## saves names_*.png (the window) to OUT_DIR.

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
	root.get_texture().get_image().save_png(out.path_join("names_%s.png" % name))


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("names/songs")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for f in ["clip.mp4", "other.spscript", "notes.json"]:
		var w := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		w.store_string("{}" if f.ends_with("json") else "a stand-in")
		w.close()
	studio = load("res://studio/studio.tscn").instantiate()
	studio._cli_desktop = true  # as --desktop
	root.add_child(studio)
	await frames(10)
	print("project name: ", ProjectSettings.get_setting("application/config/name"))
	print("window title: ", root.title)
	print("user dir: ", OS.get_user_data_dir())
	print("status: ", studio.message)
	studio.shelf.show_tab(StudioAssetShelf.OPEN_TAB)
	studio.shelf._files._navigate_to(dir)
	await frames(4)
	await shot("0_nothing_open")

	print("open clip.mp4: ", studio.open_piece(dir.path_join("clip.mp4")))
	await frames(6)
	print("status: ", studio.message)
	print("made: ", FileAccess.file_exists(dir.path_join("clip.spscript")), ", Save as suggests '", studio.shelf._save_name.text, "'")
	print("Save as target: ", studio.shelf.save_as_target().get_file())
	await shot("1_new_spscript")
	quit()
