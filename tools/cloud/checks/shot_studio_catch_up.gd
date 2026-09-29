extends SceneTree

## Studio catching up with the player (TODO 20), driven in the real main
## scene: a screen's Blend and Fit video shape, Image overlay's image (a
## file from outside the piece, bundled) and its mode (a hint_enum, as a
## choice), a layer on the Video source, and the camera effects ("$camera":
## Kaleidoscope added, its strength keyed, its lane on the timeline). Prints
## what the runner shows; rendered, saves studio_catch_up_*.png to OUT_DIR.

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func test_cards() -> void:
	var reg: ObjectRegistry = studio.runner.registry()
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(StudioThumbnailer.test_card())


## The desktop inspector cropped out of the window, and the whole window.
func shot(name: String, whole := false) -> void:
	if not rendered:
		return
	test_cards()
	await frames(12)
	var img := root.get_texture().get_image()
	if whole:
		img.save_png(out.path_join("studio_catch_up_%s.png" % name))
		return
	var r := Rect2i(studio.inspector.get_global_rect())
	img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(out.path_join("studio_catch_up_%s.png" % name))


func row(ins: StudioInspector, key: String) -> Dictionary:
	for r in ins._rows:
		if r.field.key == key:
			return r
	return {}


func _initialize() -> void:
	var work := OS.get_environment("WORK").path_join("studio_catch_up")
	var dir := work.path_join("piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.make_dir_recursive_absolute(work.path_join("mine"))
	for f in ["clip.json", "images/logo.png"]:
		DirAccess.remove_absolute(dir.path_join(f))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	# An image from outside the piece: a ring.
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var d := Vector2(x - 128, y - 128).length()
			img.set_pixel(x, y, Color(1.0, 0.8, 0.2, 1.0) if d > 70 and d < 110 else Color(0, 0, 0, 0))
	var logo := work.path_join("mine/ring.png")
	img.save_png(logo)

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(40.0)
	var m: EditModel = studio.model
	var edits: StudioConfigEdits = studio.edits
	var ins: StudioInspector = studio.inspector
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2.2, 9)
	cam.look_at(Vector3(0, 2.0, 0))
	studio.stage.seek_to(1.0)

	# 1. The screen: Blend, Fit video shape, Image overlay's image and mode.
	studio.tools.select("main_screen")
	await frames(6)
	ins._set_now(row(ins, "blend").field, "add")
	await frames(4)
	print("blend add: '%s' → config %s, screen %s" % [m.undo_label(), m.config_of("main_screen").get("blend"),
			reg.get_node_by_id("main_screen").get_display_material().get_shader_parameter("display_blend")])
	edits.add_effect("main_screen", "res://player/visualizer/effects/image_overlay.gdshader")
	ins.set_section_open("effect0", true)
	await frames(6)
	ins._set_now(row(ins, "effect0/image").field, logo)
	await frames(4)
	print("image: '%s' → %s, bundled %s" % [m.undo_label(), m.config_of("main_screen").effects[0].params.get("image"),
			FileAccess.file_exists(dir.path_join("images/ring.png"))])
	ins._set_now(row(ins, "effect0/mode").field, 3)
	await frames(4)
	var screen: Screen = reg.get_node_by_id("main_screen")
	print("mode Screen: '%s' → config %s, shows '%s'" % [m.undo_label(), m.config_of("main_screen").effects[0].params.get("mode"),
			(row(ins, "effect0/mode").controls[0] as Button).text])
	print("effect params on stage: image %s, mode %s" % [screen._effect_params[0].get("image"), screen._effect_params[0].get("mode")] if screen._effect_params.size() > 0 else "none")
	ins.set_section_open("Transform", false)
	ins.set_section_open("Surface", false)
	ins._menu = "field:effect0/fit"
	ins.request_rebuild()
	await frames(6)
	await shot("1_screen")
	ins._menu = ""
	ins.request_rebuild()
	if rendered:
		# The headset panel, Blend's choices open.
		studio.inspector_panel.visible = true
		studio._place_inspector_panel()
		await frames(6)
		var vr_view: StudioInspector = studio._vr_inspector()
		vr_view.set_section_open("Transform", false)
		vr_view.set_section_open("Surface", false)
		vr_view._menu = "field:blend"
		vr_view.request_rebuild()
		await frames(8)
		var sub: SubViewport = studio.inspector_panel.get_node("Viewport")
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await frames(6)
		sub.get_texture().get_image().save_png(out.path_join("studio_catch_up_1b_headset.png"))
		vr_view._menu = ""
		studio.inspector_panel.visible = false

	# 2. A layer on the video, behind the screen, added as light.
	m.add_object({"type": "event", "t": 0.0, "action": "spawn", "id": "glow_back", "prefab": "layer", "parent": "main_screen",
			"transform": {"position": [0.0, 0.0, -2.0], "scale": [1.3, 1.3, 1.3]}, "config": {}})
	print("video source: %s ('%s')" % [edits.set_layer_shader("glow_back", VisualizerShaders.VIDEO), m.undo_label()])
	await frames(4)
	studio.tools.select("glow_back")
	await frames(6)
	var layer: Visualizer = reg.get_node_by_id("glow_back")
	print("layer: shader '%s', video source %s" % [layer.get_shader_key(), layer._video_source])
	ins.set_section_open("Transform", false)
	await frames(4)
	await shot("2_layer")

	# 3. Camera effects: from the inspector's empty state, Kaleidoscope, its
	# strength keyed at 1 s and 5 s.
	studio.tools.select("")
	await frames(6)
	var cam_button: Button = null
	for c in ins._list.get_children():
		if c is Button and (c as Button).text.begins_with("✦"):
			cam_button = c
	print("empty state offers the camera: %s" % (cam_button != null))
	if cam_button != null:
		cam_button.pressed.emit()
	await frames(6)
	print("selected '%s', title '%s'" % [studio.tools.selected, ins._title.text])
	print("add kaleidoscope: %s ('%s')" % [edits.add_effect(EditModel.CAMERA, "builtin:kaleidoscope"), m.undo_label()])
	ins.set_section_open("effect0", true)
	await frames(6)
	var strength: Dictionary = row(ins, "effect0/strength").field
	print("strength key: '%s'" % edits.commit(EditModel.CAMERA, strength, 0.2, 1.0, true))
	print("strength key: '%s'" % edits.commit(EditModel.CAMERA, strength, 1.0, 5.0, true))
	studio.stage.seek_to(3.0)
	await frames(4)
	var fx: Dictionary = studio.runner.camera_effect()
	print("runner at 3 s: %s strength %.2f; camera fx running %s" % [fx.get("key"), fx.get("strength", -1.0), studio.stage.camera_fx.is_running()])
	var lanes := StudioTimeline.lanes(m, 40.0).map(func(l): return l.id)
	print("lanes: ", lanes)
	await shot("3_camera")
	await shot("4_window", true)
	var check := m.check()
	print("valid: %s" % check.get("ok", false))
	print("CATCH UP DONE")
	quit()
