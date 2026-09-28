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
	# 3D layer shaders (mainVR) in the display shader: with and without
	# fragDepth, flat, curved and at infinity.
	var four := "user://compile_check_vr.glsl"
	var f := FileAccess.open(four, FileAccess.WRITE)
	f.store_string("void mainVR(out vec4 c, in vec2 p, in vec3 ro, in vec3 rd) { c = vec4(rd * 0.5 + 0.5, 1.0) * texture(iChannel0, vec2(0.1, 0.25)).x; }\n")
	f.close()
	var gyroid := VisualizerShaders.BUILTIN_ROOT + "shaders/gyroid_tunnel.gdshader"
	for key in [gyroid, ProjectSettings.globalize_path(four)]:
		for surface in [ScreenGeometry.default_surface(), {"shader": "pillow", "params": {"arc_x": 90.0}},
				{"shader": "dome", "placement": "infinity"}]:
			var layer := Visualizer.new()
			layer.at_origin = true
			root.add_child(layer)
			layer.set_shader(key)
			layer.set_surface(surface)
			for _f in 3:
				await process_frame
			print("rendered 3D %s on %s" % [key.get_file(), JSON.stringify(surface)])
			layer.queue_free()
	print("done")
	quit(0)
