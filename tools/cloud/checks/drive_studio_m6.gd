extends SceneTree

## Studio M6 end to end, on a copy of moving_screen with the beat tests'
## synthetic song (124 BPM, downbeat 0.61 s, as song.wav): arm the glow's
## intensity with its record dot in the inspector, loop 4–12 s and record
## (Shift+R): after the pre-roll, the inspector's own slider is dragged in
## time with the music (a pump on every beat) until the loop's out point
## ends the take. Then punch in a fix (loop 6–8 s, the slider held flat),
## record a grab of the cube (a hand carrying it while it plays), adjust
## the beat grid on the ribbon (nudge, tempo, undo, tap tempo), save, and
## the player plays the take back: its glow intensity matches the piece's
## curve at every beat. Headless (HEADLESS=1) it prints; rendered it also
## saves studio_m6_*.png to OUT_DIR.

var studio: Node
var tools: StudioEditTools
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"
var clock := 2000.0

const FIELD := "effect1/intensity"  # moving_screen: padding, then glow


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


func copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))


func put_card() -> void:
	var reg: ObjectRegistry = studio.runner.registry()
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(StudioThumbnailer.test_card())


func shot(name: String) -> void:
	if not rendered:
		return
	put_card()
	await frames(6)
	root.get_texture().get_image().save_png(out.path_join("studio_m6_%s.png" % name))


## The inspector's row for the glow intensity.
func row() -> Dictionary:
	for r in studio.inspector._rows:
		if r.field.key == FIELD:
			return r
	return {}


## The knob sweep: a pump on every beat (up at the beat, down by the next).
func pump(grid: BeatGrid, t: float) -> float:
	var b := grid.beat_at(t)
	return 0.4 + 2.0 * maxf(0.0, 1.0 - (b - floorf(b)) * 1.6)


func glow_keys() -> Array:
	var ti: int = studio.model.find_track("shader_param", "main_screen.effect1", "intensity")
	return studio.model.tracks()[ti].keyframes if ti >= 0 else []


## Play a take, driving the slider with `value(t)` from `drag_from` on,
## until Studio ends it. Returns the frames driven.
func record_slider(value: Callable, drag_from: float, picture: String = "") -> int:
	var slider: Range = null
	var dragging := false
	var n := 0
	await key(KEY_R, false, true)
	print("record: '", studio.message, "' chip '", studio._rec_chip(), "'")
	var shot_taken := picture == ""
	while studio.recorder.is_active():
		var t: float = studio.runner.playhead
		if t >= drag_from:
			if not dragging:
				slider = row().controls[0]  # as it is now: seeking can rebuild the inspector
				slider.drag_started.emit()
				dragging = true
			slider.value = value.call(t)
			n += 1
		if rendered and not shot_taken and studio.recorder.state == StudioRecorder.State.RECORDING and t > drag_from + 4.0:
			shot_taken = true
			await shot(picture)
		await process_frame
	if dragging and is_instance_valid(slider):  # the take's end rebuilds the inspector
		slider.drag_ended.emit(true)
	await frames(3)
	return n


func _initialize() -> void:
	var repo := OS.get_environment("REPO")
	var piece_dir := OS.get_environment("WORK").path_join("studio_m6_piece")
	copy_dir(repo.path_join("scripts/moving_screen"), piece_dir)
	var piece := piece_dir.path_join("video.json")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(piece))
	doc.media.video = "song.wav"
	var f := FileAccess.open(piece, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  ") + "\n")
	f.close()
	load("res://tests/test_beats.gd")._synth_track().save_to_wav(piece_dir.path_join("song.wav"))

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	tools = studio.tools
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	print("open: ", studio.open_piece(piece))
	studio.runner.set_video_duration(24.0)
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2, 8)
	cam.look_at(Vector3(-0.3, 1.6, 0))
	for i in 600:
		await process_frame
		if not studio.waveform.is_loading() and studio.stage.beats.grid != null and not studio.stage.beats.is_analyzing():
			break
	var grid: BeatGrid = studio.stage.beats.grid
	print("beat grid: %.1f BPM, downbeat %.3f s" % [grid.bpm, grid.offset])

	# Arm the glow's intensity with its record dot.
	tools.select("main_screen")
	studio.inspector.set_section_open("effect1", true)
	await frames(6)
	var r := row()
	var dot: Button = r.dot
	dot.pressed.emit()
	await frames(3)
	print("armed: '", studio.message, "' ", studio.recorder.armed.keys())
	var before: Array = glow_keys().duplicate(true)
	print("glow intensity keys before: ", before.size())

	# Loop 4–12 s and record a pump on every beat.
	studio.loop.set_in(4.0)
	studio.loop.set_out(12.0)
	studio.loop.on = true
	studio.stage.seek_to(9.0)
	var driven: int = await record_slider(func(t): return pump(grid, t), 2.5, "1_recording")
	print("take: '", studio.message, "', slider moved on %d frames" % driven, ", stopped at %.2f" % studio.runner.playhead)
	var kfs := glow_keys()
	var inside := kfs.filter(func(k): return k.t >= 4.0 - 0.001 and k.t <= 12.0 + 0.001)
	print("keys: %d in 4–12 s (from %d samples), %d outside" % [inside.size(), driven, kfs.size() - inside.size()])
	# How tight: the curve against the pump, away from the instant jumps.
	var worst := 0.0
	var t := 4.1
	while t < 11.9:
		var ph: float = grid.beat_at(t) - floorf(grid.beat_at(t))
		if ph > 0.06 and ph < 0.94:
			worst = maxf(worst, absf(float(Interpolation.evaluate(kfs, t)) - pump(grid, t)))
		t += 0.013
	print("curve vs the pump between beats: worst %.3f (a frame at 60 Hz of the fall is %.3f)" % [worst, 2.0 * 1.6 / (60.0 / grid.bpm) / 60.0])
	var peaks := []
	for n in range(ceili(grid.beat_at(4.2)), floori(grid.beat_at(11.8)) + 1):
		peaks.append(snappedf(float(Interpolation.evaluate(kfs, grid.time_of_beat(n) + 0.03)), 0.01))
	print("30 ms after each beat (the pump there: %.2f): " % pump(grid, grid.time_of_beat(20) + 0.03), peaks)
	studio.ribbon.view.fit()
	await shot("2_take")

	# Punch in a fix: loop 6–8 s, the slider held at 1.0.
	var at5 := float(Interpolation.evaluate(kfs, 5.0))
	var at10 := float(Interpolation.evaluate(kfs, 10.0))
	studio.loop.set_in(6.0)
	studio.loop.set_out(8.0)
	await record_slider(func(_t): return 1.0, 0.0)
	kfs = glow_keys()
	print("punch-in: '", studio.message, "'")
	print("  6–8 s now: ", [6.3, 7.0, 7.7].map(func(x): return snappedf(float(Interpolation.evaluate(kfs, x)), 0.001)),
			", 5 s and 10 s unchanged: ", is_equal_approx(float(Interpolation.evaluate(kfs, 5.0)), at5), " ", is_equal_approx(float(Interpolation.evaluate(kfs, 10.0)), at10))
	await key(KEY_Z, true)
	print("ctrl+z: '", studio.message, "' 7 s back to %.3f" % float(Interpolation.evaluate(glow_keys(), 7.0)))
	await key(KEY_Z, true, true)
	print("redo: 7 s %.3f" % float(Interpolation.evaluate(glow_keys(), 7.0)))

	# A grab take: carry the cube 1.5 m to the right while it plays.
	studio.loop.on = false
	studio.stage.seek_to(9.0)
	var cube: Node3D = reg.get_node_by_id("cube_1")
	var hand := Transform3D(Basis(), cube.global_position + Vector3(0, 0, 1.0))
	await key(KEY_R, false, true)
	var grabbed := false
	var carried_from := 0.0
	while studio.runner.playhead < 13.0:
		var ph: float = studio.runner.playhead
		if studio.recorder.state == StudioRecorder.State.RECORDING:
			if not grabbed:
				grabbed = tools.grab("cube_1", "R", hand)
				carried_from = ph
			var u := clampf((ph - carried_from) / 3.0, 0.0, 1.0)
			tools.move_hand("R", hand.translated(Vector3(1.5 * u, 0, 0)))
		await process_frame
	tools.release_hand("R")
	var cube_rest := cube.position
	await key(KEY_R, false, true)
	var pos: int = studio.model.find_track("transform", "cube_1", "position")
	var pk: Array = studio.model.tracks()[pos].keyframes if pos >= 0 else []
	print("grab take: '", studio.message, "' position keys in 9–13 s: ",
			pk.filter(func(k): return k.t >= 9.0 and k.t <= 13.0).size(), ", held where let go until the end: ", cube_rest.snapped(Vector3(0.01, 0.01, 0.01)))

	# The beat grid by hand on the ribbon.
	var rb: StudioTimelineRibbon = studio.ribbon
	rb._grid_button.button_pressed = true
	await frames(2)
	rb._nudge_grid(0.01, 0.0)
	rb._nudge_grid(0.0, 0.1)
	await frames(2)
	print("grid nudged: '", studio.message, "' media.beats ", studio.model.document().media.get("beats"), ", clock %.1f BPM %.3f" % [studio.stage.beats.grid.bpm, studio.stage.beats.grid.offset])
	await key(KEY_Z, true)
	await key(KEY_Z, true)
	print("undone twice: media.beats ", studio.model.document().media.get("beats"), ", clock %.1f BPM %.3f" % [studio.stage.beats.grid.bpm, studio.stage.beats.grid.offset])
	var spb := 60.0 / 124.0
	for n in range(20, 26):
		studio.stage.seek_to(0.61 + n * spb + [0.01, -0.012, 0.004, 0.0, -0.006, 0.009][n - 20])
		rb.tap()
	await frames(2)
	var b061: float = studio.stage.beats.grid.beat_at(0.61)
	print("tapped 6 times: '", studio.message, "' clock %.1f BPM, 0.61 s is %.3f of a beat off the grid" % [studio.stage.beats.grid.bpm, b061 - roundf(b061)])
	studio.stage.seek_to(8.0)
	await shot("3_grid")

	await key(KEY_S, true)
	print("save: '", studio.message, "' valid ", ScriptFormat.load_from_file(piece).ok)
	var saved := glow_keys().duplicate(true)
	studio.queue_free()
	await frames(3)

	# The player plays the take back.
	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var preg: ObjectRegistry = main.runner.registry()
	main.open_file(piece, false)
	main.runner.set_video_duration(24.0)
	var diff := 0.0
	var checked := 0
	for n in range(ceili(grid.beat_at(4.2)), floori(grid.beat_at(11.8)) + 1):
		var bt := grid.time_of_beat(n) + 0.05
		main.runner.seek(bt)
		await frames(1)
		var scr: Screen = preg.get_node_by_id("main_screen")
		var got := float(scr._effect_params[1].get("intensity", -1.0))
		diff = maxf(diff, absf(got - float(Interpolation.evaluate(saved, bt))))
		checked += 1
	print("player: glow intensity at %d beats (+50 ms), worst difference from the piece %.4f" % [checked, diff])
	print("STUDIO M6 DONE")
	quit()
