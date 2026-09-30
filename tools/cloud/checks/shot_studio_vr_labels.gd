extends SceneTree

## The headset inspector's long labels (TODO 56): selects the main screen and
## saves the panel's own viewport to OUT_DIR/studio_vr_labels.png, so "Render
## scale" and the other long labels can be read in full.

var studio: Node
var out := OS.get_environment("OUT_DIR")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_vr_labels/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.spscript"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.tools.select("main_screen")
	studio.inspector_panel.visible = true
	studio._place_inspector_panel()
	await frames(8)
	var iv = studio._vr_inspector()
	print("inspector min ", iv.get_combined_minimum_size(), " size ", iv.size)
	var wide: Array = []
	var stack: Array = [iv]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Control and n.get_combined_minimum_size().x > 700:
			wide.append("%s %s %d" % [n.get_class(), n.name, n.get_combined_minimum_size().x])
		for c in n.get_children():
			stack.append(c)
	print("wide: ", wide)
	var vp := studio.inspector_panel.get_node("Viewport") as SubViewport
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await frames(8)
	if DisplayServer.get_name() != "headless":
		vp.get_texture().get_image().save_png(out.path_join("studio_vr_labels.png"))
	quit(0)
