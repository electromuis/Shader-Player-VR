extends SceneTree

## Benchmarks a camera preset in the real player: runs main.tscn in desktop
## mode (no VR), starting with `--preset` (a preset .json, as in the
## presets folder; the player reads the same argument, so no other preset
## loads first), plays `--video`, waits `--warmup` and measures for
## `--seconds`. Prints frames per second, frame times (average and
## percentiles), the GPU time per frame summed over every viewport (the
## screen, the layers and each effect pass), the passes that cost most and
## the render thread's CPU time for all of them.
## Vsync is off so frames run as fast as they can. Needs a real renderer
## (not --headless). The window is the desktop view, not a headset's two
## eyes, so the display part is lighter than in VR; the effect passes are
## the same size either way. Pass `--xr-mode off`: with a headset connected
## OpenXR otherwise starts anyway and its runtime holds a desktop-only app
## to about 10 fps.
##   godot --xr-mode off --path project_engine --script res://tools/bench_preset.gd -- \
##       --preset <preset.json> --video <video file> [--seconds 10] [--warmup 3] [--top 8]

var _args: PackedStringArray
var _main: Node


func _init() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	var i := _args.find(name)
	return _args[i + 1] if i >= 0 and i + 1 < _args.size() else fallback


func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var preset_path := _arg("--preset", "")
	var video := _arg("--video", "")
	var seconds := float(_arg("--seconds", "10"))
	var warmup := float(_arg("--warmup", "3"))
	var top := int(_arg("--top", "8"))
	var preset = JSON.parse_string(FileAccess.get_file_as_string(preset_path)) if preset_path != "" else null
	if typeof(preset) != TYPE_DICTIONARY or typeof(preset.get("screen")) != TYPE_DICTIONARY:
		printerr("bench_preset: --preset must name a preset .json (with a `screen` block)")
		quit(1)
		return
	if not FileAccess.file_exists(video):
		printerr("bench_preset: --video must name a video file")
		quit(1)
		return
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		printerr("bench_preset: OpenXR is running, which caps frames at ~10 fps: add --xr-mode off")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_main = load("res://player/main.tscn").instantiate()
	_main._cli_force_desktop = true
	root.add_child(_main)
	await process_frame
	_main.open_file(video)
	await _wait(warmup)

	var frame_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var cpu_ms: Array[float] = []  # render-thread CPU, all viewports
	var viewport_count := 0
	var per_pass := {}  # viewport path -> total GPU ms
	var measured := {}  # viewport rid -> true once measuring is on
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(seconds * 1e6):
		# Passes come and go with the effects: switch measuring on for new ones.
		var viewports := _viewports()
		for vp in viewports:
			var rid := vp.get_viewport_rid()
			if not measured.has(rid):
				RenderingServer.viewport_set_measure_render_time(rid, true)
				measured[rid] = true
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		var total := 0.0
		var cpu := 0.0
		viewport_count = viewports.size()
		for vp in viewports:
			if not is_instance_valid(vp):
				continue
			var t := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
			total += t
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid())
			var key := _label(vp)
			per_pass[key] = per_pass.get(key, 0.0) + t
		gpu_ms.append(total)
		cpu_ms.append(cpu)
	# The first frames only turn measuring on.
	var skip := mini(3, frame_ms.size() - 1)
	frame_ms = frame_ms.slice(skip)
	gpu_ms = gpu_ms.slice(skip)
	cpu_ms = cpu_ms.slice(skip)
	_report(preset_path, frame_ms, gpu_ms, per_pass, top)
	print("render CPU  avg %.3f ms per frame over %d viewports" % [_avg(cpu_ms), viewport_count])
	quit()


static func _avg(values: Array[float]) -> float:
	var sum := 0.0
	for v in values:
		sum += v
	return sum / maxi(1, values.size())


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


## The window's viewport and every SubViewport under the player.
func _viewports() -> Array[Viewport]:
	var out: Array[Viewport] = [root]
	for n in _main.find_children("*", "SubViewport", true, false):
		out.append(n as Viewport)
	return out


## A viewport's place in the player, shortened: "<owner>/<viewport>", the
## owner being the Screen (or layer) it belongs to.
func _label(vp: Viewport) -> String:
	if vp == root:
		return "window (3D scene, display quads, UI)"
	var path := String(_main.get_path_to(vp))
	var effect := ""
	var mat := _pass_material(vp)
	if mat != null and mat.shader != null:
		var file := mat.shader.resource_path.get_file()
		effect = " [%s]" % (file if file != "" else "chain_copy / generated")
	return path + effect


func _pass_material(vp: Viewport) -> ShaderMaterial:
	for c in vp.get_children():
		if c is CanvasItem and (c as CanvasItem).material is ShaderMaterial:
			return (c as CanvasItem).material
	return null


func _report(preset_path: String, frame_ms: Array[float], gpu_ms: Array[float], per_pass: Dictionary, top: int) -> void:
	var n := frame_ms.size()
	if n == 0:
		print("bench_preset: no frames measured")
		return
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var total_time := 0.0
	for f in frame_ms:
		total_time += f
	var gpu_total := 0.0
	for g in gpu_ms:
		gpu_total += g
	var lines: Array[String] = []
	lines.append("== bench_preset: %s ==" % preset_path.get_file())
	lines.append("frames      %d in %.1f s  (%.1f fps)" % [n, total_time / 1000.0, n / (total_time / 1000.0)])
	lines.append("frame ms    avg %.2f  p50 %.2f  p95 %.2f  p99 %.2f  max %.2f" % [total_time / n,
			sorted[n / 2], sorted[mini(n - 1, int(n * 0.95))], sorted[mini(n - 1, int(n * 0.99))], sorted[-1]])
	lines.append("GPU ms      avg %.3f per frame (all viewports)" % (gpu_total / n))
	var keys := per_pass.keys()
	keys.sort_custom(func(a, b): return per_pass[a] > per_pass[b])
	lines.append("costliest viewports (avg GPU ms per frame):")
	for k in keys.slice(0, top):
		lines.append("  %7.3f  %s" % [per_pass[k] / n, k])
	print("\n".join(lines))
