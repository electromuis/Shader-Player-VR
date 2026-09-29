extends SceneTree

## Studio M4 end to end, on a copy of moving_screen given a song (the beat
## tests' synthetic track: 124 BPM, downbeat at 0.61 s, as song.wav): the
## waveform and beat grid come from the audio, a key on the cube is dragged
## on the ribbon onto a beat (snapping on), given an ease out, a passage is
## looped while playing, the ribbon scrubs and zooms, undo / redo, then
## save and the player plays the retimed key. The ribbon's own pointer
## input is driven (the events a click or a drag sends). Headless
## (HEADLESS=1) it prints; rendered it also saves studio_m4_*.png to
## OUT_DIR: the desktop with the ribbon, the ribbon close up, and the
## headset band (its picture, and at waist height in the world).

var studio: Node
var tools: StudioEditTools
var ribbon: StudioTimelineRibbon
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


## A pointer event on the ribbon's canvas at `at` (its own coordinates).
func pointer(at: Vector2, pressed := true, button := MOUSE_BUTTON_LEFT, motion := false) -> void:
	var ev: InputEvent
	if motion:
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
	ev.position = at
	ribbon._canvas_input(ev)
	await frames(2)


## Where the ribbon draws the selection's row `label` at time `t`.
func row_point(label: String, t: float) -> Vector2:
	for item in ribbon._layout:
		if item.kind == "prop" and item.row.label == label:
			return Vector2(ribbon._gutter + ribbon.view.x_of(t), item.y + item.h * 0.5)
	return Vector2(-1, -1)


func cube_keys(ch: String) -> Array:
	var ti: int = studio.model.find_track("transform", "cube_1", ch)
	return studio.model.tracks()[ti].keyframes.map(func(k): return [snappedf(float(k.t), 0.001), k.get("interp", "linear")]) if ti >= 0 else []


func put_card() -> void:
	var img := Image.create(640, 360, false, Image.FORMAT_RGB8)
	for y in 360:
		for x in 640:
			var c := Color.from_hsv(float(x) / 640.0, 0.8, 0.35 + 0.65 * float(y) / 360.0)
			if (x / 40 + y / 40) % 2 == 0 and y > 250:
				c = Color(0.95, 0.95, 0.95)
			img.set_pixel(x, y, c)
	var card := ImageTexture.create_from_image(img)
	var reg: ObjectRegistry = studio.runner.registry()
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(card)


func shot(name: String) -> void:
	if not rendered:
		return
	put_card()
	await frames(12)
	root.get_texture().get_image().save_png(out.path_join("studio_m4_%s.png" % name))


func copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))


func _initialize() -> void:
	var repo := OS.get_environment("REPO")
	var piece_dir := OS.get_environment("WORK").path_join("studio_m4_piece")
	copy_dir(repo.path_join("scripts/moving_screen"), piece_dir)
	var piece := piece_dir.path_join("video.json")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(piece))
	doc.media.video = "song.wav"
	var f := FileAccess.open(piece, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  ") + "\n")
	f.close()
	print("song: ", load("res://tests/test_beats.gd")._synth_track().save_to_wav(piece_dir.path_join("song.wav")) == OK)

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	tools = studio.tools
	ribbon = studio.ribbon
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	print("open: ", studio.open_piece(piece))
	studio.runner.set_video_duration(24.0)
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2, 8)
	cam.look_at(Vector3(-0.3, 1.6, 0))
	for i in 600:  # the waveform and the beat grid come off worker threads
		await process_frame
		var g: BeatGrid = studio.stage.beats.grid
		if not studio.waveform.is_loading() and g != null and not studio.stage.beats.is_analyzing():
			break
	var grid: BeatGrid = studio.stage.beats.grid
	print("waveform: %d peaks (%.1f s)" % [studio.waveform.peaks.size(), studio.waveform.peaks.size() / StudioWaveform.RATE],
			", loudest near a kick: ", snappedf(studio.waveform.peak_between(5.85, 6.0), 0.01), ", between kicks: ", snappedf(studio.waveform.peak_between(6.1, 6.25), 0.01))
	print("beat grid: %.1f BPM, downbeat %.3f s" % [grid.bpm, grid.offset] if grid != null and grid.is_valid() else "no grid")
	print("ribbon: visible ", ribbon.visible, ", lanes ", ribbon._lanes.map(func(l): return [l.id, l.spans]))

	# Key the cube at 5.3 s (I), then drag its position key onto a beat.
	studio.stage.seek_to(5.3)
	tools.select("cube_1")
	await key(KEY_I)
	await frames(3)
	print("rows: ", ribbon._rows.get(tools.selected, []).map(func(r): return "%s (%d)" % [r.label, r.keys.size()]))
	await key(KEY_G, false, true)  # snapping on: keys land on beats
	var from := row_point("Position", 5.3)
	await pointer(from)
	print("pressed the key: selected ", ribbon.selected_key, )
	await pointer(row_point("Position", 5.8), true, MOUSE_BUTTON_LEFT, true)
	await pointer(row_point("Position", 6.05), true, MOUSE_BUTTON_LEFT, true)
	print("dragging: at %.3f s (snapped)" % ribbon._drag.get("t", -1.0))
	await shot("1_dragging")
	await pointer(row_point("Position", 6.05), false)
	print("let go: '", studio.message, "' position keys ", cube_keys("position"), ", selected ", ribbon.selected_key)
	var beat: float = grid.time_of_beat(roundf(grid.beat_at(6.05))) if grid != null and grid.is_valid() else -1.0
	print("on the beat at %.3f: %s" % [beat, absf(cube_keys("position")[0][0] - beat) < 0.002])

	# Its interpolation: ease out (a bezier preset).
	await frames(3)
	for b in ribbon._key_bar.get_children():
		if (b as Button).text == "Ease out":
			(b as Button).pressed.emit()
	await frames(3)
	var ti: int = studio.model.find_track("transform", "cube_1", "position")
	print("ease out: '", studio.message, "' interp ", studio.model.tracks()[ti].keyframes[0].get("interp"), ", out handle ",
			studio.model.tracks()[ti].keyframes[0].get("out", "none (last key)"))

	# A second key 1.5 m to the right at 10 s, so the ease has a segment.
	var p0: Array = studio.model.tracks()[ti].keyframes[0].value
	studio.model.set_key("transform", "cube_1", "position", 10.0, [p0[0] + 1.5, p0[1], p0[2]])
	await frames(3)
	ribbon.selected_key = {"ti": ti, "ki": 0}
	ribbon._set_interp("ease_out")
	await frames(2)
	print("with a next key: interp ", studio.model.tracks()[ti].keyframes[0].get("interp"), ", out ",
			studio.model.tracks()[ti].keyframes[0].get("out"), ", next in ", studio.model.tracks()[ti].keyframes[1].get("in"))

	# Undo / redo the retime.
	await key(KEY_Z, true)
	await key(KEY_Z, true)
	print("ctrl+z twice: '", studio.message, "' position keys ", cube_keys("position"))
	await key(KEY_Z, true, true)
	await key(KEY_Z, true, true)
	print("redo twice: position keys ", cube_keys("position"))

	# Scrub on the ruler, zoom with the wheel over it.
	await pointer(Vector2(ribbon._gutter + ribbon.view.x_of(12.0), ribbon._ruler * 0.5))
	await pointer(Vector2(ribbon._gutter + ribbon.view.x_of(12.0), ribbon._ruler * 0.5), false)
	print("click on the ruler at 12 s: playhead %.2f" % studio.runner.playhead)
	var span_before: float = ribbon.view.span
	await pointer(Vector2(ribbon._gutter + ribbon.view.x_of(6.0), ribbon._ruler + 10), true, MOUSE_BUTTON_WHEEL_UP)
	await pointer(Vector2(ribbon._gutter + ribbon.view.x_of(6.0), ribbon._ruler + 10), true, MOUSE_BUTTON_WHEEL_UP)
	print("wheel up twice over the waveform: span %.1f -> %.1f s" % [span_before, ribbon.view.span])

	# Loop 4 s to 7 s and play: it comes back round.
	studio.stage.seek_to(4.0)
	await key(KEY_BRACKETLEFT)
	studio.stage.seek_to(7.0)
	await key(KEY_BRACKETRIGHT)
	await key(KEY_L)
	print("loop: '", studio.message, "' on ", studio.loop.on, " (%.2f to %.2f)" % [studio.loop.a, studio.loop.b])
	studio.stage.seek_to(12.0)
	await key(KEY_SPACE)
	print("play from 12 s while looping: starts at %.2f" % studio.runner.playhead)
	var wrapped := false
	var last: float = studio.runner.playhead
	var highest := 0.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 4500:
		await process_frame
		highest = maxf(highest, studio.runner.playhead)
		if studio.runner.playhead < last - 1.0:
			wrapped = true
		last = studio.runner.playhead
	await key(KEY_SPACE)
	print("played 4.5 s: came back round ", wrapped, ", never past %.2f (out point 7.00)" % highest)
	ribbon.view.fit()
	studio.stage.seek_to(5.0)
	tools.select("main_screen")
	await frames(4)
	ribbon.selected_key = {}
	tools.select("cube_1")
	await frames(4)
	ribbon.selected_key = {"ti": ti, "ki": 0}
	await shot("0_desktop")

	# The headset band.
	studio.ribbon_panel.visible = true
	studio._place_ribbon_panel()
	await frames(6)
	var vr_ribbon: StudioTimelineRibbon = studio._vr_ribbon()
	print("headset ribbon: ", vr_ribbon != null, ", big ", vr_ribbon.vr if vr_ribbon != null else false,
			", panel at ", studio.ribbon_panel.global_position.snapped(Vector3(0.01, 0.01, 0.01)))
	if rendered and vr_ribbon != null:
		vr_ribbon.selected_key = {"ti": ti, "ki": 0}
		var sub: SubViewport = studio.ribbon_panel.get_node("Viewport")
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await frames(8)
		sub.get_texture().get_image().save_png(out.path_join("studio_m4_2_headset_ribbon.png"))
		ribbon.visible = false
		studio.inspector.visible = false
		# About where your eyes are, looking down at it.
		cam.global_position = Vector3(0.0, 2.05, 8.3)
		cam.look_at(Vector3(0.0, 1.45, 7.4))
		await shot("3_headset_world")

	await key(KEY_S, true)
	print("save: '", studio.message, "' valid ", ScriptFormat.load_from_file(piece).ok)
	var saved: Array = cube_keys("position")
	studio.queue_free()
	await frames(3)

	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var preg: ObjectRegistry = main.runner.registry()
	main.open_file(piece, false)
	main.runner.set_video_duration(24.0)
	main.runner.seek(beat)
	await frames(3)
	var at_key := (preg.get_node_by_id("cube_1") as Node3D).position
	main.runner.seek(beat + 1.0)
	await frames(3)
	var later := (preg.get_node_by_id("cube_1") as Node3D).position
	print("player: keys ", saved, ", cube at the beat ", at_key.snapped(Vector3(0.01, 0.01, 0.01)), ", a second on ", later.snapped(Vector3(0.01, 0.01, 0.01)))
	print("STUDIO M4 DONE")
	quit()
