extends SceneTree

## The timeline's scroll bar (TODO 11), in the real Studio: moving_screen
## with a made-up sound outline (a kick every beat at 124 BPM, louder bars
## and a quiet break; no song is opened: GoZen closing one segfaults here,
## TODO 30), a loop set,
## then the bar driven with the ribbon's own pointer events: the right end
## pulled in (zoom), the window dragged (scroll), a press beside it (jump),
## the wheel over it, the left end pulled out again. Prints the view after
## each; rendered, saves studio_scrollbar_*.png (the ribbon, cropped) to
## OUT_DIR.

var studio: Node
var ribbon: StudioTimelineRibbon
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


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


## Time `t` on the scroll bar, on the canvas.
func bar_at(t: float) -> Vector2:
	var r: Rect2 = ribbon._bar_rect()
	return Vector2(ribbon._bar_x(t), r.get_center().y)


## Press at `from`, drag to `to`, let go; `shoot` names a shot taken mid-drag.
func drag(from: Vector2, to: Vector2, shoot := "") -> void:
	print("  press: ", ribbon.hit(from).get("kind", "nothing"))
	await pointer(from)
	await pointer(from.lerp(to, 0.5), true, MOUSE_BUTTON_LEFT, true)
	await pointer(to, true, MOUSE_BUTTON_LEFT, true)
	if shoot != "":
		await shot(shoot)
	await pointer(to, false)


func view() -> String:
	var v: StudioTimeline = ribbon.view
	return "view %.2f → %.2f s (%.2f s across)" % [v.start, v.start + v.span, v.span]


func shot(name: String) -> void:
	if not rendered:
		return
	await frames(6)
	var img := root.get_texture().get_image()
	if name == "1_fit":
		img.save_png(out.path_join("studio_scrollbar_full.png"))
	img.get_region(Rect2i(ribbon.get_global_rect())).save_png(out.path_join("studio_scrollbar_%s.png" % name))


func copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))


func _initialize() -> void:
	var repo := OS.get_environment("REPO")
	var piece_dir := OS.get_environment("WORK").path_join("studio_scrollbar_piece")
	copy_dir(repo.path_join("scripts/moving_screen"), piece_dir)
	var piece := piece_dir.path_join("video.json")

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	ribbon = studio.ribbon
	print("open: ", studio.open_piece(piece))
	studio.runner.set_video_duration(24.0)
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2, 8)
	cam.look_at(Vector3(-0.3, 1.6, 0))
	var peaks := PackedFloat32Array()
	for i in int(24.0 * StudioWaveform.RATE):
		var t := i / StudioWaveform.RATE
		var beat := fposmod(t - 0.61, 60.0 / 124.0) / (60.0 / 124.0)
		var level := 0.25 + 0.75 * exp(-beat * 6.0)
		peaks.append(level * (0.35 if t > 14.0 and t < 17.0 else 1.0) * (0.8 + 0.2 * sin(t * 0.7)))
	studio.waveform.peaks = peaks
	print("waveform: %d peaks" % studio.waveform.peaks.size())
	studio.tools.select("cube_1")
	studio.loop.set_in(6.0)
	studio.loop.set_out(10.0)
	studio.stage.seek_to(7.5)
	await frames(4)
	print("fit: ", view(), ", bar ", ribbon._bar_rect())
	await shot("1_fit")

	print("pull the right end to 8 s:")
	await drag(bar_at(24.0), bar_at(8.0), "2_pulling")
	print("  ", view())
	print("drag the window 6 s later:")
	await drag(bar_at(4.0), bar_at(10.0), "3_scrolling")
	print("  ", view())
	print("press beside it at 20 s:")
	await drag(bar_at(20.0), bar_at(20.0))
	print("  ", view())
	for i in 2:
		await pointer(bar_at(12.0), true, MOUSE_BUTTON_WHEEL_UP)
	print("the wheel over the bar, up twice: ", view())
	print("pull the left end out to 0:")
	await drag(bar_at(ribbon.view.start), bar_at(0.0))
	print("  ", view())
	await shot("4_after")
	# A narrow window can still be moved: its ends only grab from outside it.
	ribbon.view.zoom(100.0, 12.0)
	await frames(2)
	var win: Array = ribbon._bar_window()
	print("narrow (%s): the middle is '%s', just left '%s', just right '%s'" % [view(),
			ribbon.hit(Vector2((win[0] + win[1]) * 0.5, bar_at(0).y)).kind,
			ribbon.hit(Vector2(win[0] - 4, bar_at(0).y)).kind, ribbon.hit(Vector2(win[1] + 4, bar_at(0).y)).kind])
	quit(0)
