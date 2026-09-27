extends SceneTree

var bridge: VideoBridge
var screen: Screen
var vis: Visualizer
var frames := 0
var phase := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2, 8)
	root.add_child(cam)
	bridge = VideoBridge.new()
	root.add_child(bridge)
	bridge.video_loaded.connect(func(_d, _f): bridge.play())
	bridge.load_video(ProjectSettings.globalize_path("res://../scripts/forest_tunnel/video.mp4"))
	screen = load("res://player/prefabs/screen.tscn").instantiate()
	root.add_child(screen)
	screen.set_source_texture(bridge.get_output_texture())
	vis = Visualizer.new()
	root.add_child(vis)
	vis.bind_video(bridge.get_output_texture())
	vis.set_shader(VisualizerShaders.VIDEO)
	vis.set_effects([{"shader": VisualizerShaders.BLUR, "params": {"radius": 0.1}}])
	process_frame.connect(_tick)

func _all_viewports(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is SubViewport:
			out.append(c)
		_all_viewports(c, out)

func _report(label: String) -> void:
	var vps: Array = []
	_all_viewports(root, vps)
	var total := 0.0
	print("== ", label, "  frame ", bridge.frame_size())
	for vp in vps:
		var active: bool = vp.render_target_update_mode != SubViewport.UPDATE_DISABLED
		var t := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		total += t
		print("  %-45s %10s %s  gpu %.3f ms" % [str(root.get_path_to(vp)), str(vp.size), "on " if active else "off", t])
	var main_t := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	print("  root gpu %.3f ms, subviewports %.3f ms, fps %d" % [main_t, total, Engine.get_frames_per_second()])

func _enable_measure() -> void:
	var vps: Array = []
	_all_viewports(root, vps)
	for vp in vps:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)

func _tick() -> void:
	frames += 1
	if frames == 120:
		_enable_measure()
	if frames == 240:
		_report("resolution 1.0")
		vis.set_resolution_scale(0.25)
		screen.set_resolution_scale(0.25)
	if frames == 260:
		_enable_measure()
	if frames == 380:
		_report("resolution 0.25")
		quit()
