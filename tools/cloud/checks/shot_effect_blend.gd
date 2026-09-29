extends SceneTree

## Effects' blend and mix (TODO 59) and on / off keys with a fade (TODO 58),
## in Studio on the real main scene: a screen per blend mode (a False colour
## effect over the test card), one at mix 0.5, and one whose effect is keyed
## off at 4 s with a 2 s fade. Prints the switch's level through the fade;
## rendered, saves effect_blend_*.png to OUT_DIR: the grid at 1, 5 and 7 s,
## the inspector's Mix and Blend rows, and the timeline's on / off row with
## a key's fade picker.

const EffectBlend := preload("res://player/visualizer/effect_blend.gd")
const FX := "res://player/visualizer/effects/false_color.gdshader"

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"
var labels: Array[Label3D] = []


func frames(n: int) -> void:
	for i in n:
		await process_frame


func test_cards() -> void:
	var reg: ObjectRegistry = studio.runner.registry()
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(StudioThumbnailer.test_card())


## The 3D view without Studio's panels.
func shot_view(name: String) -> void:
	if not rendered:
		return
	test_cards()
	studio.get_node("UI").visible = false
	await frames(12)
	root.get_texture().get_image().save_png(out.path_join("effect_blend_%s.png" % name))
	studio.get_node("UI").visible = true


## A panel of the desktop window, cropped.
func shot_panel(name: String, panel: Control) -> void:
	if not rendered:
		return
	test_cards()
	await frames(12)
	var img := root.get_texture().get_image()
	var r := Rect2i(panel.get_global_rect())
	img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(out.path_join("effect_blend_%s.png" % name))


func seek(t: float) -> void:
	studio.stage.seek_to(t)
	studio.runner._evaluate_continuous_tracks()
	await frames(3)


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("effect_blend/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
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
	studio.runner.set_video_duration(20.0)
	var m: EditModel = studio.model
	var edits: StudioConfigEdits = studio.edits
	if m.spawn_index("main_screen") >= 0:
		m.remove_object("main_screen")
	var prefab := m.name_prefab("res://player/prefabs/screen.tscn")
	var shader := m.name_shader(FX)
	# A screen per mode, then mix 0.5 and the switched one: four columns.
	var cells: Array = []
	for mode in EffectBlend.MODES:
		cells.append({"id": "blend_" + mode, "fx": {"shader": shader, "blend": mode}, "label": EffectBlend.LABELS[mode]})
	cells.append({"id": "mix_half", "fx": {"shader": shader, "mix": 0.5}, "label": "Normal · mix 0.5"})
	cells.append({"id": "switched", "fx": {"shader": shader}, "label": "Keyed off at 4 s, 2 s fade"})
	cells.append({"id": "plain", "fx": {}, "label": "No effect"})
	var width := 32.0 * 0.05
	m.batch("Lay out the grid", func():
		for i in cells.size():
			var c: Dictionary = cells[i]
			var col := i % 4
			var row := i / 4
			var spawn := {"type": "event", "t": 0.0, "action": "spawn", "id": c.id, "prefab": prefab,
				"transform": {"position": [(col - 1.5) * (width + 0.25), 3.4 - row * 1.3, 0.0], "scale": [0.05, 0.05, 0.05]},
				"config": {"effects": [c.fx] if not c.fx.is_empty() else []}}
			m.add_object(spawn))
	await frames(4)
	# The switch: keyed with auto-key at 4 s, then its key given a 2 s fade.
	print("switch: '%s'" % edits.set_switch("switched", 0, false, 4.0, true))
	var ti := edits.switch_track("switched", 0)
	print("fade: %s → %s" % [m.set_key_fade(ti, 1, 2.0), m.tracks()[ti].keyframes])
	await frames(4)
	for c in cells:
		var l := Label3D.new()
		l.text = c.label
		l.font_size = 40
		l.pixel_size = 0.004
		l.outline_size = 8
		root.add_child(l)
		labels.append(l)
	# Frame the grid (the screen mount places and scales it).
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var half_w := 0.0
	for c in cells:
		var n: Node3D = reg.get_node_by_id(c.id)
		lo = lo.min(n.global_position)
		hi = hi.max(n.global_position)
		half_w = 16.0 * n.global_transform.basis.get_scale().x
	var centre := (lo + hi) * 0.5 + Vector3(0, -0.1 * half_w, 0)
	var cam: Camera3D = studio.stage.desktop_camera
	var span := (hi.x - lo.x) + 2.0 * half_w
	cam.global_position = centre + Vector3(0, 0, span * 0.62 / tan(deg_to_rad(cam.fov) * 0.5) / (16.0 / 9.0) * 1.1)
	cam.look_at(centre)
	for t in [1.0, 5.0, 7.0]:
		await seek(t)
		var node: Screen = reg.get_node_by_id("switched")
		print("t %.0f: the switched effect shows %.2f (on in the inspector: %s)" % [t, node.effect_amount(0),
				edits.switch_on("switched", 0, t)])
		for i in cells.size():
			var n: Node3D = reg.get_node_by_id(cells[i].id)
			labels[i].global_position = n.global_position + Vector3(0, -0.62, 0.05) * n.global_transform.basis.get_scale().y / 0.05
		await shot_view("grid_%ds" % int(t))
	var add: Screen = reg.get_node_by_id("blend_add")
	print("add: blend pass after the effect: %s" % add._passes.any(func(p): return p.blend))
	print("normal: no blend pass: %s" % not (reg.get_node_by_id("blend_normal") as Screen)._passes.any(func(p): return p.blend))

	# The inspector: the Add screen's effect unfolded (Mix, Blend first).
	await seek(5.0)
	studio.tools.select("blend_add")
	var ins: StudioInspector = studio.inspector
	ins.set_section_open("Transform", false)
	ins.set_section_open("Surface", false)
	ins.set_section_open("Display", false)
	ins._open_fx["effects"] = 0
	ins._needs_build = true
	await frames(8)
	var rows: Array = ins._rows.filter(func(r): return String(r.field.key).begins_with("effect0/"))
	print("effect rows: ", rows.map(func(r): return "%s=%s" % [r.field.label, edits.value_of("blend_add", r.field, 5.0)]).slice(0, 3))
	await shot_panel("inspector", ins)

	# The timeline: the switched screen's on / off row, its key selected.
	studio.tools.select("switched")
	var ribbon: StudioTimelineRibbon = studio.ribbon
	ribbon.request_refresh()
	await frames(4)
	ribbon.view.start = 0.0
	ribbon.view.span = 12.0
	ribbon.selected_key = {"ti": edits.switch_track("switched", 0), "ki": 1}
	await frames(2)
	var lane_at: int = ribbon._lanes.map(func(l): return l.id).find("switched")
	ribbon._vscroll = maxf(lane_at - 1, 0) * ribbon._lane
	await frames(6)
	print("timeline rows: ", ribbon._rows.map(func(r): return "%s%s" % [r.label, " (switch)" if r.get("switch") else ""]))
	var switched_ins := ins._fx_rows.map(func(r): return r.switch.button_pressed)
	print("inspector switch at 5 s (fading, still on): %s" % switched_ins)
	await shot_panel("timeline", ribbon)
	print("fade picker: %s" % ribbon.set_key_fade(0.5))

	# A camera effect's blend, set through its inspector field.
	studio.tools.select("")
	print("camera effect: %s" % edits.add_effect(EditModel.CAMERA, "builtin:kaleidoscope"))
	await seek(1.0)
	await shot_view("camera_normal")
	var blend := {}
	for s in edits.sections(EditModel.CAMERA):
		for fl in s.fields:
			if fl.key == "effect0/blend":
				blend = fl
	print("camera blend: '%s' → %s" % [edits.commit(EditModel.CAMERA, blend, "difference", 1.0, false),
			studio.runner.camera_effect().get("blend")])
	await frames(4)
	await shot_view("camera_difference")
	print("save: ", m.save().get("ok", false), " valid ", ScriptFormat.load_from_file(dir.path_join("clip.json")).ok)
	print("EFFECT BLEND DONE")
	quit()
