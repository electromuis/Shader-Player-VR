extends SceneTree

## TODO 61, driven through the real Studio: keys keep their values. Keys on
## change Off (the default). A layer's opacity: 0 keyed with the diamond at
## 2 s, the slider to 1 at 5 s (held unkeyed: the orange diamond, the layer
## shows 1, nothing written), the diamond keys it; a change at 8 s dropped
## by a seek. A cube: keyed with A at 2 s, grabbed up at 5 s (held unkeyed:
## it stays where it was let go), A keys it. Prints the keys after each
## step; rendered, it saves keying_*.png (the whole window, inspector in).

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


func diamond(field_key: String) -> void:
	row(field_key).diamond.pressed.emit()
	await frames(4)


func diamond_look(field_key: String) -> String:
	var b: Button = row(field_key).diamond
	var c: Color = b.get_theme_color("font_color")
	return "%s %s" % [b.text, "orange" if c == StudioInspector.UNKEYED else ("red" if c == StudioInspector.RECORD else "dim")]


func opacity() -> Variant:
	var n = studio.runner.registry().get_node_by_id("lay")
	if n == null:
		return "gone"
	var scr: Screen = n._screen
	return snappedf(float(scr._display_material.get_shader_parameter("opacity")), 0.001)


func keys(target: String, name: String) -> Array:
	for t in studio.model.tracks():
		if t.get("target") == target and (t.get("param") == name or t.get("channel") == name):
			return t.keyframes.map(func(k): return [k.t, k.value])
	return []


func seek(t: float) -> void:
	studio.stage.seek_to(t)
	await frames(4)


func shot(name: String) -> void:
	if not rendered:
		return
	await frames(10)
	root.get_texture().get_image().save_png(out.path_join("keying_%s.png" % name))


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("keying_piece")
	DirAccess.make_dir_recursive_absolute(dir)
	var doc := {
		"format_version": 2, "media": {"video": "clip.mp4", "duration": 20.0},
		"prefabs": {"layer": "res://player/prefabs/layer.tscn", "cube": "res://player/prefabs/cube.tscn"},
		"shaders": {"ring": "res://player/visualizer/shaders/light_ring.gdshader"},
		"tracks": [
			{"type": "event", "t": 0, "action": "spawn", "id": "lay", "prefab": "layer",
				"transform": {"position": [0, 2, 0], "scale": [0.12, 0.12, 0.12]}, "config": {"shader": "ring"}},
			{"type": "event", "t": 0, "action": "spawn", "id": "box", "prefab": "cube",
				"transform": {"position": [1.5, 1, 0], "scale": [0.4, 0.4, 0.4]}},
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
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0.7, 2, 5)
	cam.look_at(Vector3(0.7, 1.5, 0))
	var tools: StudioEditTools = studio.tools
	print("auto-key: ", tools.auto_key, ", keys on change animated: ", tools.key_animated)

	# The report: 0 keyed at 2 s, 1 keyed at 5 s.
	tools.select("lay")
	await seek(2.0)
	await drag("opacity", 0.0)
	print("drag 0 at 2 s (still): '", studio.message, "'")
	await diamond("opacity")
	print("diamond at 2 s: '", studio.message, "' keys ", keys("lay.display", "opacity"))
	await seek(5.0)
	await drag("opacity", 1.0)
	print("drag 1 at 5 s: '", studio.message, "'")
	print("  keys ", keys("lay.display", "opacity"), ", diamond ", diamond_look("opacity"), ", layer shows ", opacity(),
			", slider ", row("opacity").controls[0].value)
	await frames(30)
	print("  30 frames on: layer shows ", opacity(), " (held), dirty ", studio.model.is_dirty(), " undo '", studio.model.undo_label(), "'")
	view._scroll.ensure_control_visible(row("opacity").diamond)
	await shot("1_unkeyed")
	await diamond("opacity")
	print("diamond at 5 s: '", studio.message, "' keys ", keys("lay.display", "opacity"), ", diamond ", diamond_look("opacity"))
	view._scroll.ensure_control_visible(row("opacity").diamond)
	await shot("2_keyed")
	for t in [2.0, 3.5, 5.0]:
		await seek(t)
		print("seek ", t, ": layer shows ", opacity())

	# A change dropped by moving on.
	await seek(8.0)
	await drag("opacity", 0.3)
	print("drag 0.3 at 8 s: '", studio.message, "', layer shows ", opacity())
	await seek(3.5)
	print("seek 3.5: '", studio.message, "', layer shows ", opacity(), ", keys ", keys("lay.display", "opacity"))

	# Moves: the cube keyed with A at 2 s, grabbed up 1 m at 5 s, A.
	tools.select("box")
	await seek(2.0)
	await key(KEY_I)
	print("I (A) at 2 s: '", studio.message, "' position keys ", keys("box", "position"))
	await seek(5.0)
	var reg: ObjectRegistry = studio.runner.registry()
	var p: Vector3 = reg.get_node_by_id("box").global_position
	tools.grab("box", "R", Transform3D(Basis(), p + Vector3(0, 0, 2)))
	tools.move_hand("R", Transform3D(Basis(), p + Vector3(0, 1, 2)))
	tools.release()
	await frames(10)
	print("grab up at 5 s: '", studio.message, "' position keys ", keys("box", "position"))
	print("  cube at ", reg.get_node_by_id("box").position, " (held where let go), unkeyed ", tools.unkeyed.keys())
	await shot("3_move_unkeyed")
	await key(KEY_I)
	print("I (A) at 5 s: '", studio.message, "' position keys ", keys("box", "position"))
	for t in [2.0, 5.0]:
		await seek(t)
		print("seek ", t, ": cube at ", reg.get_node_by_id("box").position)

	# Undo steps: the A at 5 s, then the key at 2 s.
	await key(KEY_Z, true)
	print("undo: '", studio.message, "' position keys ", keys("box", "position"))
	print("save: ", studio.model.save().ok, ", opacity keys in the file ",
			(JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("clip.json"))).tracks as Array)
			.filter(func(t): return t.get("param") == "opacity").map(func(t): return t.keyframes))
	quit()
