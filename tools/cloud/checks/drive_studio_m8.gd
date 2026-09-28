extends SceneTree

## Studio M8, looks: style a screen (the user's red edge and Glow, a
## curved surface, a tint), save its look (Ctrl+L; the inspector has the
## button too), find it on the shelf's Looks tab with a snapshot of the
## screen as its card, then drop it on a plain screen (which takes it,
## keeping its place and size) and on the floor (a new screen with it).
## Undo / redo. Haptics: the pulses a grab with snapping, the key button,
## a refused drop and a take ask for (undone after). Save, and the player
## plays the piece with the looks. The
## library (and so the looks) is $WORK/studio_m8/library, not the user's.
## Headless (HEADLESS=1) it prints; rendered it also saves studio_m8_*.png
## to OUT_DIR.

var studio: Node
var tools: StudioEditTools
var shelf: StudioAssetShelf
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"

const RED_EDGE := """shader_type canvas_item;
#include "res://player/visualizer/effect_prelude.gdshaderinc"

uniform float width : hint_range(0.0, 0.3, 0.005) = 0.06;
uniform vec3 edge : source_color = vec3(1.0, 0.25, 0.3);

void fragment() {
	vec4 c = texture(input_tex, UV);
	float d = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	COLOR = vec4(mix(edge, c.rgb, smoothstep(width * 0.6, width, d)), c.a);
}
"""


func frames(n: int) -> void:
	for i in n:
		await process_frame


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func key(code: Key, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		studio.stage.router.handle_key(ev)
	await frames(2)


func ray_at(at: Vector2) -> Transform3D:
	var cam: Camera3D = studio.stage.desktop_camera
	var dir := cam.project_ray_normal(at)
	return Transform3D(Basis.looking_at(dir, Vector3.UP), cam.project_ray_origin(at))


func asset(type: String, label: String) -> Dictionary:
	for a in studio.library.of_type(type):
		if a.label == label:
			return a
	return {}


func press_card(a: Dictionary) -> void:
	if shelf.tab != a.type:
		shelf.show_tab(a.type)
		await frames(3)
	var card := shelf.card(a.id)
	if card == null:
		print("no card for ", a.label)
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	card.gui_input.emit(ev)
	await frames(2)


func drop(a: Dictionary, at: Vector2) -> bool:
	await press_card(a)
	var ok: bool = studio.drop_held_at(ray_at(at))
	await frames(4)
	print("drop %s: '%s'" % [a.label, studio.message])
	return ok


## Screens show the test card (nothing decodes video here).
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
	await frames(12)
	root.get_texture().get_image().save_png(out.path_join("studio_m8_%s.png" % name))


func effects(id: String) -> Array:
	var doc: Dictionary = studio.model.document()
	return studio.model.effects_of(id).map(func(e): return "%s%s" % [String(doc.shaders.get(e.shader, e.shader)).get_file(), "" if e.get("enabled", true) else " (off)"])


func _initialize() -> void:
	var work := OS.get_environment("WORK")
	var base := work.path_join("studio_m8")
	rm(base)
	var piece_dir := base.path_join("piece")
	var lib := base.path_join("library")
	write(piece_dir.path_join("clip.mp4"), "a plain video (a stand-in: nothing here decodes video)")
	write(lib.path_join("shaders/red_edge.gdshader"), RED_EDGE)

	studio = load("res://studio/studio.tscn").instantiate()
	studio.library.library_dirs.insert(0, lib)  # looks go to the first library folder
	root.add_child(studio)
	await frames(10)
	tools = studio.tools
	shelf = studio.shelf
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	studio.open_piece(piece_dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(30.0)
	var m: EditModel = studio.model
	print("new piece: ", m.path.get_file() if m != null else "none")
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2.2, 14)
	cam.look_at(Vector3(0, 1.4, 0))
	await frames(3)

	# Three screens on the floor: left, middle, right (they stand at eye height).
	var vp := root.get_visible_rect().size
	for x in [0.5, 0.2, 0.8]:
		await drop(asset("object", "Screen"), Vector2(vp.x * x, vp.y * 0.78))
	# Side by side, 4.5 m apart, a little up the room (dropping picks a
	# spot; here they're lined up for the pictures).
	var xs := {"screen": -6.0, "main_screen": -2.0, "screen_2": 2.0}
	for id in xs:
		m.set_spawn_transform(id, {"position": [xs[id], 1.7, 0.0], "rotation_deg": [0.0, 0.0, 0.0], "scale": [0.12, 0.12, 0.12]})
	cam.global_position = Vector3(-2.0, 2.4, 10.5)
	cam.look_at(Vector3(-2.0, 1.5, 0))
	await frames(4)
	print("objects: ", m.object_ids())
	# Style main_screen (the middle one): the user's red edge and Glow, a
	# curved surface, a warm tint.
	tools.select("main_screen")
	await drop(asset("effect", "Red edge"), Vector2(vp.x * 0.5, vp.y * 0.5))
	await drop(asset("effect", "Glow"), Vector2(vp.x * 0.5, vp.y * 0.5))
	m.set_config("main_screen", "surface", {"shader": "pillow", "placement": "fixed", "params": {"arc_x": 70.0, "arc_y": 20.0}})
	m.set_config("main_screen", ["modifiers", "tint"], [1.0, 0.8, 0.6])
	m.set_config("main_screen", ["effects", 1, "params"], {"intensity": 0.6, "radius": 0.3})
	await frames(6)
	print("main_screen: effects ", effects("main_screen"), ", config keys ", m.config_of("main_screen").keys())
	await shot("1_styled")

	# Save its look (Ctrl+L), then look at the shelf's Looks tab.
	await key(KEY_L, true)
	print("save look: '", studio.message, "'")
	var looks: Array = studio.library.of_type("look")
	print("looks on the shelf: ", looks.map(func(a): return "%s (%s)" % [a.label, a.kind]))
	print("look file: ", Array(DirAccess.get_files_at(lib.path_join("looks"))))
	await frames(20)  # the snapshot
	shelf.show_tab("look")
	await frames(6)
	await shot("2_looks_tab")

	# The look onto the left screen (it takes it), and on the floor in front
	# (a new screen with it).
	var look := asset("look", looks[0].label if not looks.is_empty() else "")
	var left_at := cam.unproject_position((reg.get_node_by_id("screen") as Node3D).global_position)
	print("hint over the left screen: '", studio._drop_hint(look, StudioAssetDrop.aim(ray_at(left_at).origin,
			-ray_at(left_at).basis.z, tools.candidates())), "'")
	var left_xf = m.tracks()[m.spawn_index("screen")].transform.duplicate(true)
	await drop(look, left_at)
	print("screen now: effects ", effects("screen"), ", same place and size ", m.tracks()[m.spawn_index("screen")].transform == left_xf,
			", same config as main_screen ", m.config_of("screen") == m.config_of("main_screen"))
	await key(KEY_Z, true)
	print("ctrl+z: '", studio.message, "' effects ", effects("screen"))
	await key(KEY_Z, true, true)
	print("redo: effects ", effects("screen"))
	await drop(look, cam.unproject_position(Vector3(6.0, 0.0, 0.5)))  # the floor right of the row
	cam.global_position = Vector3(0, 3.0, 14)
	cam.look_at(Vector3(0, 1.4, 0))
	var added: String = tools.selected
	print("added: ", added, " effects ", effects(added), ", scale ", m.tracks()[m.spawn_index(added)].transform.scale if m.spawn_index(added) >= 0 else [])
	tools.select("")
	await key(KEY_N)  # the inspector out of the way
	await shot("3_looks_applied")
	await key(KEY_N)

	# Haptics: what the hands feel. "In the headset" is faked here, so the
	# pulses go through to the controllers' calls (no XR runtime to feel
	# them). A grab of screen_2 carried 30 cm with snapping on, the key
	# button, a card let go on nothing, and a take through its pre-roll.
	var hx: StudioHaptics = studio.haptics
	hx.in_vr = func(): return true
	var n0 := hx.count
	var s2: Node3D = reg.get_node_by_id("screen_2")
	var hand := Transform3D(Basis(), s2.global_position + Vector3(0, 0, 2))
	tools.snap = true
	tools.grab("screen_2", "R", hand)
	for i in 6:
		tools.move_hand("R", hand.translated(Vector3(0.06 * i, 0, 0)))
	var moved := tools.release_hand("R")
	var keyed := tools.key_selection()
	await press_card(asset("effect", "Glow"))
	studio._held_hand = "R"
	studio.drop_held_at(ray_at(Vector2(vp.x * 0.5, vp.y * 0.05)))  # the sky: refused
	print("haptics: ", hx.kinds_since(n0), ", all sent ", hx.log.slice(hx.log.size() - (hx.count - n0)).all(func(e): return e.sent),
			" (moved: '", moved, "', keyed: '", keyed, "')")
	await key(KEY_Z, true)
	await key(KEY_Z, true)
	tools.snap = false
	n0 = hx.count
	await key(KEY_R, false, true)  # record: 2 s of pre-roll, then it records
	for i in 600:
		await process_frame
		if studio.runner.playhead >= studio.recorder.from + 0.2:
			break
	var during := hx.kinds_since(n0)
	await key(KEY_R, false, true)
	print("take: pulses during it ", during, ", after stopping ", hx.kinds_since(n0), " ('", studio.message, "')")
	hx.in_vr = func(): return false
	studio.stage.seek_to(0.0)
	await frames(3)

	await key(KEY_S, true)
	var piece: String = m.path
	print("save: '", studio.message, "' valid ", ScriptFormat.load_from_file(piece).ok)
	print("piece shaders/: ", Array(DirAccess.get_files_at(piece_dir.path_join("shaders"))))
	studio.queue_free()
	await frames(3)

	# The player plays it.
	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var preg: ObjectRegistry = main.runner.registry()
	main.open_file(piece, false)
	main.runner.set_video_duration(30.0)
	main.runner.seek(3.0)
	await frames(6)
	for id in preg.all_ids():
		var n = preg.get_node_by_id(id)
		if n is Screen:
			print("player %s: effects %s, loaded %s" % [id, n._effect_keys.map(func(k): return String(k).get_file()), n._effect_shaders.map(func(s): return s != null)])
	if rendered:
		main.stage.desktop_camera.global_position = Vector3(0, 3.0, 14)
		main.stage.desktop_camera.look_at(Vector3(0, 1.4, 0))
		for id in preg.all_ids():
			var n = preg.get_node_by_id(id)
			if n is Screen:
				n.set_source_texture(StudioThumbnailer.test_card())
		await frames(14)
		root.get_texture().get_image().save_png(out.path_join("studio_m8_4_player.png"))
	print("STUDIO M8 DONE")
	quit()
