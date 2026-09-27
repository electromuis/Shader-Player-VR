extends SceneTree

## Renders a screen with every built-in surface, placement and vertex
## effect, so the GPU driver compiles each generated display shader.
## Needs a real renderer (not --headless); watch the output for SHADER ERROR.
##   godot --path <project> --script res://tests/shader_compile_check.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 8)
	root.add_child(cam)
	var configs: Array = []
	for surface in [ScreenGeometry.PILLOW, ScreenGeometry.DOME]:
		for placement in ScreenGeometry.placements_for(surface):
			configs.append({"surface": {"shader": surface, "params": {"arc_x": 120.0, "arc_y": 40.0}, "placement": placement}})
	var all_vfx: Array = []
	for v in ScreenGeometry.builtins(ScreenGeometry.VERTEX_DIR):
		all_vfx.append({"shader": v.key, "params": {}})
	configs.append({"surface": {"shader": "dome"}, "vertex_effects": all_vfx})
	configs.append({"surface": {"shader": "pillow", "params": {"arc_x": 90.0}}, "vertex_effects": all_vfx})
	var i := 0
	for cfg in configs:
		var screen: Screen = load("res://player/prefabs/screen.tscn").instantiate()
		screen.scale = Vector3.ONE * 0.25
		root.add_child(screen)
		screen.set_source_texture(ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8)))
		screen.configure(cfg, null)
		for _f in 3:
			await process_frame
		print("rendered %d: %s" % [i, JSON.stringify(cfg)])
		screen.queue_free()
		i += 1
	print("done")
	quit(0)
