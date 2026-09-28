extends SceneTree

## Studio M7 end to end, on a copy of forest_tunnel: key a ride with V from
## where the camera stands (the seat at 46 s, into the tunnel at 48 s,
## through it by 54 s, turning) and cut home at 56 s with Shift+V; select
## the Viewer lane on the ribbon (the inspector shows the viewer, the ride's
## path is drawn, the too-fast stretch is red); arm the ride and record a
## second one over a loop at 60–66 s by flying (the camera carried along an
## arc while it plays); preview in Play mode (the camera rides the script)
## and back in Edit (flying freely: a seek doesn't move it); save, and the
## player rides it. Headless (HEADLESS=1) it prints; rendered it also saves
## studio_m7_*.png to OUT_DIR.

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(code: Key, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		studio.stage.router.handle_key(ev)
	await frames(2)


func copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for d in DirAccess.get_directories_at(from):
		copy_tree(from.path_join(d), to.path_join(d))


func cam() -> Camera3D:
	return studio.stage.desktop_camera


func v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


func where() -> String:
	return "%s yaw %.1f" % [v(cam().global_position), cam().rotation_degrees.y]


## Stand at `pos` facing `yaw` at `t`, and press `code`.
func key_at(t: float, pos: Vector3, yaw: float, shift := false) -> void:
	studio.stage.seek_to(t)
	await frames(2)
	cam().set_view(pos, Vector3(0, yaw, 0))
	await key(KEY_V, false, shift)
	print("%s at %.1f s from %s: '%s'" % ["Shift+V" if shift else "V", t, where(), studio.message])


func shot(name: String) -> void:
	if rendered:
		await frames(8)
		root.get_texture().get_image().save_png(out.path_join("studio_m7_%s.png" % name))


func viewer_keys(ch: String) -> Array:
	var ti: int = studio.model.find_track("transform", "$viewer", ch)
	return studio.model.tracks()[ti].keyframes if ti >= 0 else []


func _initialize() -> void:
	var repo := OS.get_environment("REPO")
	var dir := OS.get_environment("WORK").path_join("studio_m7_piece")
	copy_tree(repo.path_join("scripts/forest_tunnel"), dir)
	var piece := dir.path_join("video.json")

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	var tools: StudioEditTools = studio.tools
	print("open: ", studio.open_piece(piece))
	studio.runner.set_video_duration(180.0)
	await frames(4)
	print("Edit mode follows the script: ", studio.stage.drive_viewer)

	# Key a ride from where the camera stands, and cut home.
	await key_at(46.0, Vector3(0, 2, 8), 0.0)
	await key_at(48.0, Vector3(0, 3, -30), 0.0)
	await key_at(54.0, Vector3(0, 3, -130), 20.0)
	await key_at(56.0, Vector3(0, 2, 8), 0.0, true)
	print("viewer position keys: ", viewer_keys("position").map(func(k): return [k.t, k.value, k.get("interp", "linear"), k.get("transition", {}).get("duration", 0)]))
	print("cuts on the ribbon: ", StudioTimeline.cuts(studio.model))

	# The Viewer lane: select it by its name, see the warning.
	var rb: StudioTimelineRibbon = studio.ribbon
	rb.view.start = 40.0
	rb.view.span = 30.0
	studio.stage.seek_to(50.0)
	await frames(4)
	var lane: Dictionary = rb._lanes[0]
	print("first lane: ", lane.id, " spans ", lane.spans, " too fast: ", lane.warn.map(func(w): return [snappedf(w[0], 0.1), snappedf(w[1], 0.1)]))
	for item in rb._layout:
		if item.kind == "lane" and item.id == "$viewer":
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = Vector2(20, item.y + item.h * 0.5)
			rb._canvas_input(ev)
	await frames(6)
	print("selected: ", tools.selected, ", inspector: '", studio.inspector._title.text, "' — ",
			studio.inspector._viewer_state.text.replace("\n", " / ") if studio.inspector._viewer_state != null else "")
	print("ribbon rows: ", rb._rows.map(func(r): return "%s (%d)" % [r.label, r.keys.size()]))
	# Look at the ride from above and to the side.
	cam().set_view(Vector3(-28, 22, -30), Vector3(-32, -62, 0))
	await shot("1_viewer_selected")

	# Record a second ride by flying: an arc at 60–66 s.
	await key(KEY_V, true, true)
	print("arm: '", studio.message, "' armed ", studio.recorder.arm_viewer)
	studio.loop.set_in(60.0)
	studio.loop.set_out(66.0)
	studio.loop.on = true
	studio.stage.seek_to(60.0)
	await key(KEY_R, false, true)
	while studio.recorder.is_active():
		var t: float = studio.runner.playhead
		var u := clampf((t - 60.0) / 6.0, 0.0, 1.0)
		var a := u * PI * 0.5
		cam().set_view(Vector3(-10.0 + 10.0 * cos(a), 2.5, 8.0 - 10.0 * sin(a)) + Vector3(0, 0, 0), Vector3(0, rad_to_deg(a), 0))
		await process_frame
	studio.loop.on = false
	var pos := viewer_keys("position").filter(func(k): return k.t >= 60.0 and k.t <= 66.0 + 0.01)
	var rot := viewer_keys("rotation_deg").filter(func(k): return k.t >= 60.0 and k.t <= 66.0 + 0.01)
	print("ride take: '", studio.message, "' %d position keys, %d turn keys in 60-66 s, ends at %s facing %.1f" % [pos.size(), rot.size(),
			str(pos.back().value) if not pos.is_empty() else "-", rot.back().value[1] if not rot.is_empty() else 0.0])
	await key(KEY_V, true, true)  # disarm

	# Play mode rides the script; Edit flies freely.
	cam().set_view(Vector3(7, 2, 7), Vector3(0, 40, 0))
	await key(KEY_TAB)
	print("Play: follows the script ", studio.stage.drive_viewer, ", camera ", where())
	studio.stage.seek_to(49.5)
	await frames(2)
	studio.runner.play()
	while studio.runner.playhead < 51.5:
		await process_frame
	var vt: ViewerTrack = studio.runner.viewer
	var pose := vt.pose_at(studio.runner.playhead)
	print("Play at %.2f s: camera %s, the ride %s: off by %.3f m" % [studio.runner.playhead, where(), v(pose.position), cam().global_position.distance_to(pose.position)])
	await shot("2_play_in_the_tunnel")
	studio.runner.pause()
	await key(KEY_TAB)
	var here := cam().global_position
	studio.stage.seek_to(20.0)
	await frames(2)
	print("Edit: follows the script ", studio.stage.drive_viewer, ", a seek left the camera where it was: ", cam().global_position.is_equal_approx(here))

	await key(KEY_S, true)
	print("save: '", studio.message, "' valid ", ScriptFormat.load_from_file(piece).ok)
	studio.queue_free()
	await frames(3)

	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.stage.settings.allow_script_camera = true
	main.stage.settings.script_camera_cuts_only = false
	main.open_file(piece, false)
	main.runner.set_video_duration(180.0)
	main.runner.seek(49.0)
	main.runner.play()
	while main.runner.playhead < 50.5:
		await process_frame
	main.runner.pause()
	var ppose: Dictionary = main.runner.viewer.pose_at(main.runner.playhead)
	var pc: Camera3D = main.stage.desktop_camera
	print("player at %.2f s: camera %s, the ride %s: off by %.3f m" % [main.runner.playhead, v(pc.global_position), v(ppose.position), pc.global_position.distance_to(ppose.position)])
	print("STUDIO M7 DONE")
	quit()
