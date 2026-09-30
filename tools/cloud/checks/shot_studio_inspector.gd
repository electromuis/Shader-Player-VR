extends SceneTree

## Studio's inspector after the to-do's second pass, driven in the real
## main scene: the header's line, the transform as typed numbers (a typed
## x, Uniform scale, the rotation row's sliders and a ↺), the Surface
## section (a Pillow's arcs), ↺ on a setting, pixel and vertex effects as
## compact lists (a drop reordering them, the master switch), Spin added as
## a vertex effect. Prints what happened; rendered, saves
## studio_inspector_*.png to OUT_DIR (the desktop panel cropped, and the
## headset panel).

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


## The desktop inspector, cropped out of the window.
func shot(name: String) -> void:
	if not rendered:
		return
	test_cards()
	await frames(12)
	var ins: Control = studio.inspector
	var img := root.get_texture().get_image()
	var r := Rect2i(ins.get_global_rect())
	img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(out.path_join("studio_inspector_%s.png" % name))


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_inspector/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.spscript"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(55.0)
	var m: EditModel = studio.model
	var edits: StudioConfigEdits = studio.edits
	var v := EditModel.VERTEX_EFFECTS
	# The mockup's screen: a Pillow, three pixel effects (Oval mask off), two vertex effects.
	m.set_config("main_screen", ["surface"], {"shader": "pillow", "params": {"arc_x": 70.0, "arc_y": 20.0}, "placement": "fixed"})
	for fx in ["res://player/visualizer/effects/padding.gdshader", "res://player/visualizer/effects/glow.gdshader",
			"res://player/visualizer/effects/oval_mask.gdshader"]:
		edits.add_effect("main_screen", fx)
	m.set_effect_enabled("main_screen", 2, false)
	edits.add_effect("main_screen", ScreenGeometry.RIPPLE, v)
	edits.add_effect("main_screen", ScreenGeometry.TWIST, v)
	m.set_key("shader_param", "main_screen.vertex0", "amplitude", 0.0, 0.1)
	m.set_key("shader_param", "main_screen.vertex0", "amplitude", 8.0, 0.3)
	m.set_key("shader_param", "main_screen.effect1", "intensity", 2.0, 0.6)
	m.set_key("shader_param", "main_screen.display", "opacity", 4.0, 1.0)
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2.4, 10)
	cam.look_at(Vector3(0, 2.0, 0))
	studio.stage.seek_to(2.0)
	studio.tools.select("main_screen")
	var ins: StudioInspector = studio.inspector
	ins.open_channel("rotation_deg")
	ins.set_section_open("effect1", true)
	await frames(8)
	print("header: '%s' / '%s'" % [ins._title.text, ins._kind.text])
	var titles: Array = []
	for c in ins._list.get_children():
		if c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) is Button:
			titles.append((c.get_child(0) as Button).text)
	print("sections: ", titles)
	print("effect rows: ", ins._fx_rows.map(func(r): return "%s%d %s" % [r.list.left(1), r.index, r.glyph.text]))

	# Typed numbers: x, and a uniform scale. A spawn change respawns the
	# object, so the node is looked up again after each.
	var spawn := func() -> Dictionary: return m.tracks()[m.spawn_index("main_screen")].transform
	var now := func() -> Dictionary: return GrabMath.to_dict(reg.get_node_by_id("main_screen").transform)
	ins._typed_axis("position", 0, -2.0)
	await frames(3)
	print("typed x -2: '%s' → position %s, spawn %s" % [m.undo_label(), now.call().position, spawn.call().get("position")])
	var s0: Array = now.call().scale
	ins._typed_axis("scale", 1, s0[1] * 2.0)
	await frames(3)
	print("uniform scale ×2: %s → %s, spawn %s ('%s')" % [s0, now.call().scale, spawn.call().get("scale"), m.undo_label()])
	m.undo()
	await frames(3)
	ins._typed_axis("rotation_deg", 1, 35.0)
	await frames(3)
	print("rotation y 35: %s, spawn %s ('%s')" % [now.call().rotation_deg, spawn.call().get("rotation_deg"), m.undo_label()])
	await frames(4)

	# ↺ on the Pillow's arc across.
	var arc: Dictionary = {}
	for r in ins._rows:
		if r.field.key == "shape/arc_x":
			arc = r
	print("arc across %s, ↺ enabled %s" % [arc.value.text, not (arc.reset as Button).disabled])
	await shot("1_mockup")
	if rendered:
		studio.inspector_panel.visible = true
		studio._place_inspector_panel()
		await frames(6)
		var vr_view: StudioInspector = studio._vr_inspector()
		vr_view.open_channel("rotation_deg")
		vr_view.set_section_open("effect1", true)
		await frames(8)
		var sub: SubViewport = studio.inspector_panel.get_node("Viewport")
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await frames(6)
		sub.get_texture().get_image().save_png(out.path_join("studio_inspector_2_headset.png"))
		vr_view._scroll.scroll_vertical = 100000
		await frames(6)
		sub.get_texture().get_image().save_png(out.path_join("studio_inspector_3_headset_end.png"))
		studio.inspector_panel.visible = false
	(arc.reset as Button).pressed.emit()
	await frames(2)
	print("↺ arc across: '%s' → %s" % [studio.message, m.config_of("main_screen").surface.params])

	# A drop: Oval mask onto Padding's row; the master switch; Spin added.
	print("drop oval on padding: %s → %s, Glow still unfolded: %s" % [ins.drop_effect("effects", 2, 0),
			m.effects_of("main_screen").map(func(e): return e.shader), ins._open_fx["effects"] == 2])
	await frames(4)
	print("vertex all off: %s ('%s')" % [m.set_all_effects_enabled("main_screen", false, v), m.undo_label()])
	m.undo()
	print("add spin: %s → %s" % [edits.add_effect("main_screen", ScreenGeometry.SPIN, v),
			m.effects_of("main_screen", v).map(func(e): return e.shader)])
	await frames(4)
	var shown: Array = studio.runner.registry().get_node_by_id("main_screen")._vertex_effects.map(func(e): return e.shader.get_file().get_basename())
	print("screen runs vertex effects: ", shown)
	ins.set_section_open("vertex2", true)
	ins.set_section_open("Transform", false)
	ins.set_section_open("Surface", false)
	ins.set_section_open("Display", false)
	await frames(6)
	await shot("4_lists")
	print("save: ", m.save().get("ok", false), " valid ", ScriptFormat.load_from_file(dir.path_join("clip.spscript")).ok)
	print("STUDIO INSPECTOR DONE")
	quit()
