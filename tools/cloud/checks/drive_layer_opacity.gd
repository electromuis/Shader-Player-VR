extends SceneTree

## Repro for "animating a shader layer's opacity doesn't work": a piece with
## a shader layer, its opacity keyed from the inspector (1 at 0 s, 0 at 5 s,
## auto-key on), then seeks and playback, printing the display opacity the
## layer's screen shows. Rendered, it saves layer_opacity_*.png.

var studio: Node
var view: StudioInspector
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


func row(field_key: String) -> Dictionary:
	for r in view._rows:
		if r.field.key == field_key:
			return r
	return {}


func drag(field_key: String, value: float) -> void:
	var r := row(field_key)
	if r.is_empty():
		print("  (no row ", field_key, "; rows: ", view._rows.map(func(x): return x.field.key), ")")
		return
	var s: HSlider = r.controls[0]
	s.drag_started.emit()
	s.value = value
	s.drag_ended.emit(true)
	await frames(3)


func opacity() -> Variant:
	var n = studio.runner.registry().get_node_by_id("lay")
	if n == null:
		return "gone"
	var scr: Screen = n._screen
	return snappedf(float(scr._display_material.get_shader_parameter("opacity")), 0.001)


func shot(name: String) -> void:
	if not rendered:
		return
	var hidden: Array = []
	for c in studio.find_children("*", "CanvasLayer", true, false):
		if c.visible:
			c.visible = false
			hidden.append(c)
	studio.tools.select("")
	await frames(10)
	root.get_texture().get_image().save_png(out.path_join("layer_opacity_%s.png" % name))
	for c in hidden:
		c.visible = true
	studio.tools.select("lay")
	await frames(3)


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("layer_opacity_piece")
	DirAccess.make_dir_recursive_absolute(dir)
	var doc := {
		"format_version": 2, "media": {"video": "clip.mp4", "duration": 20.0},
		"prefabs": {"layer": "res://player/prefabs/layer.tscn", "screen": "res://player/prefabs/screen.tscn"},
		"shaders": {"ring": "res://player/visualizer/shaders/light_ring.gdshader"},
		"tracks": [
			{"type": "event", "t": 0, "action": "spawn", "id": "lay", "prefab": "layer",
				"transform": {"position": [0, 2, 0], "scale": [0.12, 0.12, 0.12]}, "config": {"shader": "ring"}},
		],
	}
	var f := FileAccess.open(dir.path_join("clip.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  "))
	f.close()

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	view = studio.inspector
	print("open: ", studio.open_piece(dir.path_join("clip.json")))
	studio.runner.set_video_duration(20.0)
	studio.stage.seek_to(0.0)
	await frames(5)
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2, 5)
	cam.look_at(Vector3(0, 2, 0))
	studio.tools.select("lay")
	await frames(6)
	print("rows: ", view._rows.map(func(x): return x.field.key))
	print("opacity at start: ", opacity())
	# The user's way (their log): auto-key off, key with the diamond, then
	# drag the slider while on that key.
	print("auto-key: ", studio.tools.auto_key, ", keys on change animated: ", studio.tools.key_animated)
	row("opacity").diamond.pressed.emit()
	await frames(4)
	print("diamond at 0 s: '", studio.message, "'")
	studio.stage.seek_to(5.0)
	await frames(4)
	row("opacity").diamond.pressed.emit()
	await frames(4)
	print("diamond at 5 s: '", studio.message, "'")
	await drag("opacity", 0.0)
	print("drag 0.0 on the 5 s key: '", studio.message, "'")
	studio.stage.seek_to(8.0)
	await frames(4)
	await drag("opacity", 0.3)
	print("drag 0.3 at 8 s, off any key (held unkeyed, TODO 61): '", studio.message, "'")
	for t in studio.model.tracks():
		if t.get("type") == "shader_param":
			print("track ", t.target, ":", t.param, " ", t.keyframes.map(func(k): return [k.t, k.value]))
	for t in [0.0, 2.5, 5.0]:
		studio.stage.seek_to(t)
		await frames(4)
		print("seek ", t, ": opacity ", opacity())
		await shot("seek_%s" % t)
	studio.stage.seek_to(0.0)
	await frames(3)
	await key(KEY_TAB)  # to Play mode
	await key(KEY_SPACE)
	print("playing: ", studio.runner.playing, " hold ", studio.runner.hold)
	for i in 6:
		await create_timer(0.5).timeout
		print("play t=", snappedf(studio.runner.playhead, 0.01), ": opacity ", opacity())
	quit()
