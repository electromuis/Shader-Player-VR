extends SceneTree

## Studio M5 end to end: start from a plain video and build a scene only
## from the shelf, then play the folder somewhere else. Studio opens with
## no piece (the shelf on its Open tab); the Open tab's file browser picks
## $WORK/studio_m5/piece/clip.mp4, which has no script, so an empty piece is
## made. From the shelf: a screen (dropped on the floor ahead: it stands at
## eye height), a user effect and Glow onto the screen, a user layer shader
## (on the floor to the left), a user prefab (on the floor, at 4 s), and a cube carried
## by the right hand in the headset way (let go of the trigger). Undo /
## redo a drop, drag the prefab's lane ends on the ribbon (on at 2 s, gone
## at 20 s), delete the cube, save; then copy the piece's folder elsewhere,
## remove the user library, and the player plays it there. Headless
## (HEADLESS=1) it prints; rendered it also saves studio_m5_*.png to
## OUT_DIR, and copies the shelf's thumbnails.

var studio: Node
var tools: StudioEditTools
var shelf: StudioAssetShelf
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"
var clock := 1000.0

const STRIPES := """// @resolution 640x360
void mainImage(out vec4 c, in vec2 f) {
	vec2 uv = f / iResolution.xy;
	float bass = texture(iChannel0, vec2(0.02, 0.25)).x;
	float s = step(0.5, fract(uv.x * 8.0 + iTime * 0.5 + bass));
	c = vec4(mix(vec3(0.05, 0.1, 0.35), vec3(0.2, 0.9, 1.0), s) * (0.6 + 0.4 * uv.y), 1.0);
}
"""
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
const PILLAR := """[gd_scene load_steps=3 format=3]

[sub_resource type="StandardMaterial3D" id="1"]
albedo_color = Color(0.95, 0.6, 0.2, 1)
emission_enabled = true
emission = Color(0.6, 0.3, 0.05, 1)

[sub_resource type="CylinderMesh" id="2"]
material = SubResource("1")
top_radius = 0.25
bottom_radius = 0.35
height = 2.4

[node name="Pillar" type="MeshInstance3D"]
mesh = SubResource("2")
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


func copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for d in DirAccess.get_directories_at(from):
		copy_tree(from.path_join(d), to.path_join(d))


func key(code: Key, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		studio.stage.router.handle_key(ev)
	await frames(2)


## A pointing transform from the desktop camera through pixel `at`.
func ray_at(at: Vector2) -> Transform3D:
	var cam: Camera3D = studio.stage.desktop_camera
	var dir := cam.project_ray_normal(at)
	return Transform3D(Basis.looking_at(dir, Vector3.UP), cam.project_ray_origin(at))


func asset(type: String, label: String) -> Dictionary:
	for a in studio.library.of_type(type):
		if a.label == label:
			return a
	return {}


## Press a shelf card as the mouse would (on its tab).
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


## Carry `a` from its card and let go at pixel `at` of the view.
func drop(a: Dictionary, at: Vector2) -> bool:
	await press_card(a)
	var ok: bool = studio.drop_held_at(ray_at(at))
	await frames(4)
	print("drop %s: '%s'" % [a.label, studio.message])
	return ok


func put_card() -> void:
	var reg: ObjectRegistry = studio.runner.registry() if studio != null and is_instance_valid(studio) else null
	if reg == null:
		return
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(StudioThumbnailer.test_card())


func shot(name: String) -> void:
	if not rendered:
		return
	put_card()
	await frames(12)
	root.get_texture().get_image().save_png(out.path_join("studio_m5_%s.png" % name))


func wait_thumbnails() -> void:
	for i in 900:
		await process_frame
		if not studio.thumbnailer.is_busy():
			break
	await frames(4)


func ribbon_point(id: String, t: float) -> Vector2:
	var r: StudioTimelineRibbon = studio.ribbon
	for item in r._layout:
		if item.kind == "lane" and item.id == id:
			return Vector2(r._gutter + r.view.x_of(t), item.y + item.h * 0.5)
	return Vector2(-1, -1)


func ribbon_drag(from: Vector2, to: Vector2) -> void:
	var r: StudioTimelineRibbon = studio.ribbon
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = from
	r._canvas_input(ev)
	var mv := InputEventMouseMotion.new()
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	mv.position = to
	r._canvas_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	r._canvas_input(up)
	await frames(3)


func spans(id: String) -> Array:
	for lane in StudioTimeline.lanes(studio.model, 30.0):
		if lane.id == id:
			return lane.spans
	return []


func _initialize() -> void:
	var work := OS.get_environment("WORK")
	var base := work.path_join("studio_m5")
	rm(base)
	rm(work.path_join("studio_m5_elsewhere"))
	var piece_dir := base.path_join("piece")
	var lib := base.path_join("library")
	write(piece_dir.path_join("clip.mp4"), "a plain video (a stand-in: nothing here decodes video)")
	write(lib.path_join("shaders/stripes.glsl"), STRIPES)
	write(lib.path_join("shaders/red_edge.gdshader"), RED_EDGE)
	write(lib.path_join("prefabs/pillar.tscn"), PILLAR)

	studio = load("res://studio/studio.tscn").instantiate()
	studio.library.library_dirs.append(lib)  # as --library does
	root.add_child(studio)
	await frames(10)
	tools = studio.tools
	shelf = studio.shelf
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 1.7, 6)
	cam.look_at(Vector3(0, 1.4, 0))
	print("no piece: '", studio.message, "' shelf visible ", shelf.visible, ", tab ", shelf.tab)

	# The Open tab's browser: go to the piece's folder, pick the video.
	await frames(4)
	var files: Node = shelf._files
	files._navigate_to(piece_dir)
	await frames(3)
	var at := -1
	for i in files._entries.size():
		if String(files._entries[i].get("path", "")).get_file() == "clip.mp4":
			at = i
	print("browser lists clip.mp4: ", at >= 0)
	await shot("0_open_tab")
	files._on_item_activated(at)
	await frames(6)
	studio.runner.set_video_duration(30.0)
	var piece: String = studio.model.path if studio.model != null else ""
	print("new piece: '", studio.message, "' ", piece.get_file(), " exists ", FileAccess.file_exists(piece),
			", tracks ", studio.model.tracks().size() if studio.model != null else -1, ", shelf tab ", shelf.tab)
	await frames(4)
	print("shelf objects: ", studio.library.of_type("object").map(func(a): return "%s (%s)" % [a.label, a.source]))
	print("shelf layers (not built-in): ", studio.library.of_type("layer").filter(func(a): return a.source != "builtin").map(func(a): return a.label))
	print("shelf effects (not built-in): ", studio.library.of_type("effect").filter(func(a): return a.source != "builtin").map(func(a): return a.label))
	await wait_thumbnails()
	await shot("1_new_piece_shelf")

	# A screen on the floor ahead (it stands at eye height, facing us).
	var vp := root.get_visible_rect().size
	await drop(asset("object", "Screen"), Vector2(vp.x * 0.5, vp.y * 0.72))
	var ms: Dictionary = studio.model.tracks()[studio.model.spawn_index("main_screen")] if studio.model.spawn_index("main_screen") >= 0 else {}
	print("main_screen: ", ms.get("transform", {}), ", on stage ", reg.get_node_by_id("main_screen") != null)
	# Effects onto the screen: the user's red edge, then Glow.
	await drop(asset("effect", "Red edge"), Vector2(vp.x * 0.5, vp.y * 0.45))
	await drop(asset("effect", "Glow"), Vector2(vp.x * 0.5, vp.y * 0.45))
	print("effects on main_screen: ", studio.model.effects_of("main_screen").map(func(e): return e.shader))
	# A user layer on the floor to the left (it stands at eye height).
	await drop(asset("layer", "Stripes"), Vector2(vp.x * 0.12, vp.y * 0.8))
	# An effect dropped on nothing: not added.
	await drop(asset("effect", "Glow"), Vector2(vp.x * 0.95, vp.y * 0.1))
	# The user's prefab on the floor to the right, at 4 s.
	studio.stage.seek_to(4.0)
	await drop(asset("object", "Pillar"), Vector2(vp.x * 0.8, vp.y * 0.8))
	# Undo / redo that drop.
	await key(KEY_Z, true)
	print("ctrl+z: '", studio.message, "' pillar there ", studio.model.spawn_index("pillar") >= 0)
	await key(KEY_Z, true, true)
	print("redo: pillar there ", studio.model.spawn_index("pillar") >= 0, ", on stage ", reg.get_node_by_id("pillar") != null)

	# The headset way: the right hand carries a cube; letting go of the
	# trigger off the shelf drops it where the laser points.
	var cube := asset("object", "Cube")
	studio.stage.router.feed_button("R.trigger", true, clock)
	await press_card(cube)
	studio._held_hand = "R"
	var hand: XRController3D = studio.stage.xr_rig.right_controller
	hand.global_transform = Transform3D(Basis.looking_at(Vector3(0.75, 0.12, -1.0).normalized(), Vector3.UP), Vector3(0.2, 1.3, 4.6))
	await frames(3)
	print("carrying: '", studio.message, "' ghost shown ", studio._ghost.visible)
	await shot("2_carrying_cube")
	studio.stage.router.feed_button("R.trigger", false, clock + 0.5)
	await frames(4)
	print("let go of the trigger: '", studio.message, "' cube there ", studio.model.spawn_index("cube") >= 0)
	print("objects: ", studio.model.object_ids())

	# Lane ends on the ribbon: the pillar comes on at 2 s and goes at 20 s.
	studio.stage.seek_to(10.0)
	tools.select("pillar")
	await frames(4)
	print("pillar lane before: ", spans("pillar"))
	await ribbon_drag(ribbon_point("pillar", 4.0), ribbon_point("pillar", 2.0))
	print("drag its start: '", studio.message, "' ", spans("pillar"))
	await ribbon_drag(ribbon_point("pillar", 30.0), ribbon_point("pillar", 20.0))
	print("drag its end: '", studio.message, "' ", spans("pillar"))

	# Delete the cube (Delete), then look at the result.
	tools.select("cube")
	await key(KEY_DELETE)
	print("delete: '", studio.message, "' objects ", studio.model.object_ids())
	tools.select("main_screen")
	shelf.show_tab("layer")
	await key(KEY_N)  # the inspector out of the way, to see the scene
	await wait_thumbnails()
	await shot("3_built")
	await key(KEY_N)
	shelf.show_tab("effect")
	await frames(3)
	await wait_thumbnails()
	await shot("4_effects_tab")

	# The headset shelf.
	studio.shelf_panel.visible = true
	studio._place_shelf_panel()
	await frames(6)
	var vr_shelf: StudioAssetShelf = studio._vr_shelf()
	print("headset shelf: ", vr_shelf != null, ", big ", vr_shelf.vr if vr_shelf != null else false)
	if rendered and vr_shelf != null:
		vr_shelf.show_tab("object")
		var sub: SubViewport = studio.shelf_panel.get_node("Viewport")
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await frames(10)
		sub.get_texture().get_image().save_png(out.path_join("studio_m5_5_headset_shelf.png"))
	studio.shelf_panel.visible = false

	await key(KEY_S, true)
	print("save: '", studio.message, "' valid ", ScriptFormat.load_from_file(piece).ok)
	var doc = JSON.parse_string(FileAccess.get_file_as_string(piece))
	print("file: prefabs ", doc.prefabs, ", shaders ", doc.shaders)
	print("piece folder: ", Array(DirAccess.get_files_at(piece_dir)), " prefabs/", Array(DirAccess.get_files_at(piece_dir.path_join("prefabs"))),
			" shaders/", Array(DirAccess.get_files_at(piece_dir.path_join("shaders"))))
	if rendered:
		for a in studio.library.assets():
			var f := StudioThumbnailer.cache_path(a)
			if FileAccess.file_exists(f):
				DirAccess.copy_absolute(ProjectSettings.globalize_path(f), out.path_join("thumb_%s_%s.png" % [a.type, String(a.label).to_snake_case()]))
	studio.queue_free()
	await frames(3)

	# Somewhere else, without the library: the player plays the copy.
	var elsewhere := work.path_join("studio_m5_elsewhere/piece")
	copy_tree(piece_dir, elsewhere)
	rm(lib)
	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var preg: ObjectRegistry = main.runner.registry()
	main.open_file(elsewhere.path_join("clip.json"), false)
	main.runner.set_video_duration(30.0)
	main.runner.seek(10.0)
	await frames(6)
	var layer = preg.get_node_by_id("stripes")
	var scr = preg.get_node_by_id("main_screen")
	print("player elsewhere at 10 s: ", preg.all_ids(), ", layer shader ", layer.get_shader_key().replace(work, "$WORK") if layer != null else "none",
			", screen effects ", scr._effect_keys.map(func(k): return String(k).replace(work, "$WORK")) if scr != null else [],
			", loaded ", scr._effect_shaders.map(func(s): return s != null) if scr != null else [])
	main.runner.seek(25.0)
	await frames(4)
	print("at 25 s the pillar is gone: ", preg.get_node_by_id("pillar") == null)
	main.runner.seek(10.0)
	if rendered:
		main.stage.desktop_camera.global_position = Vector3(0, 1.7, 6)
		main.stage.desktop_camera.look_at(Vector3(0, 1.4, 0))
		for id in preg.all_ids():
			var n = preg.get_node_by_id(id)
			if n is Screen:
				n.set_source_texture(StudioThumbnailer.test_card())
		await frames(14)
		root.get_texture().get_image().save_png(out.path_join("studio_m5_6_player_elsewhere.png"))
	print("STUDIO M5 DONE")
	quit()
