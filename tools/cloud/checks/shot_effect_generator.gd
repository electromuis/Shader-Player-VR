extends SceneTree

## Generator effects (TODO 79) in Studio on the real main scene: screens
## showing the test card with a generator mixing the Hex pulse layer shader
## in, shaped by its own effects (none, an oval mask, key black and a
## mask), in different blends and mixes, and one whose mix is keyed to 0 at
## 4 s. Prints what runs; rendered, saves effect_generator_*.png to OUT_DIR:
## the grid at 1 and 5 s, and the inspector's generator section.

const EffectBlend := preload("res://player/visualizer/effect_blend.gd")
const HEX := "res://player/visualizer/shaders/hex_pulse.gdshader"
const OVAL := "res://player/visualizer/effects/oval_mask.gdshader"
const KEY := "res://player/visualizer/effects/key_black.gdshader"
const ROUND := "res://player/visualizer/effects/rounded_corners.gdshader"

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"
var labels: Array[Label3D] = []
var hex_key := ""


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
	root.get_texture().get_image().save_png(out.path_join("effect_generator_%s.png" % name))
	studio.get_node("UI").visible = true


## A panel of the desktop window, cropped.
func shot_panel(name: String, panel: Control) -> void:
	if not rendered:
		return
	test_cards()
	await frames(12)
	var img := root.get_texture().get_image()
	var r := Rect2i(panel.get_global_rect())
	img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(out.path_join("effect_generator_%s.png" % name))


func seek(t: float) -> void:
	studio.stage.seek_to(t)
	studio.runner._evaluate_continuous_tracks()
	await frames(3)


func generator(effects: Array, extra: Dictionary = {}) -> Dictionary:
	var e := {"shader": VisualizerShaders.GENERATOR,
		"generator": {"shader": hex_key, "params": {"cells": 6.0}, "effects": effects}}
	e.merge(extra)
	return e


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("effect_generator/piece")
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
	var names := {"hex": m.name_shader(HEX), "oval": m.name_shader(OVAL), "key": m.name_shader(KEY), "round": m.name_shader(ROUND)}
	hex_key = names.hex
	var oval := {"shader": names.oval, "params": {"size": 0.8, "level": 1.0, "blur": 0.3}}
	var cells: Array = [
		{"id": "plain", "fx": [], "label": "No effect"},
		{"id": "gen_plain", "fx": [generator([])], "label": "Generator · Normal"},
		{"id": "gen_oval", "fx": [generator([oval])], "label": "Masked by an oval"},
		{"id": "gen_add", "fx": [generator([oval], {"blend": "add"})], "label": "Oval · Add"},
		{"id": "gen_key", "fx": [generator([{"shader": names.key}, oval], {"mix": 0.7})], "label": "Key black + oval · mix 0.7"},
		{"id": "gen_multiply", "fx": [generator([], {"blend": "multiply"})], "label": "Multiply"},
		{"id": "gen_round", "fx": [{"shader": names.round, "params": {"roundness": 0.6}},
				generator([{"shader": names.key}], {"blend": "screen"})], "label": "Rounded, then Screen"},
		{"id": "gen_keyed", "fx": [generator([oval])], "label": "Mix keyed to 0 at 4 s"},
	]
	var width := 32.0 * 0.05
	m.batch("Lay out the grid", func():
		for i in cells.size():
			var c: Dictionary = cells[i]
			var col := i % 4
			var row := i / 4
			var spawn := {"type": "event", "t": 0.0, "action": "spawn", "id": c.id, "prefab": prefab,
				"transform": {"position": [(col - 1.5) * (width + 0.25), 3.4 - row * 1.3, 0.0], "scale": [0.05, 0.05, 0.05]},
				"config": {"effects": c.fx}}
			m.add_object(spawn))
	m.set_key(ScriptFormat.TRACK_SHADER_PARAM, "gen_keyed.effect0", "mix", 0.0, 1.0)
	m.set_key(ScriptFormat.TRACK_SHADER_PARAM, "gen_keyed.effect0", "mix", 4.0, 0.0)
	# Its own effect animated through effect0.effect0: the oval grows.
	m.set_key(ScriptFormat.TRACK_SHADER_PARAM, "gen_oval.effect0.effect0", "size", 0.0, 0.4)
	m.set_key(ScriptFormat.TRACK_SHADER_PARAM, "gen_oval.effect0.effect0", "size", 5.0, 1.0)
	await frames(4)
	for c in cells:
		var l := Label3D.new()
		l.text = c.label
		l.font_size = 40
		l.pixel_size = 0.004
		l.outline_size = 8
		root.add_child(l)
		labels.append(l)
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
	for t in [1.0, 5.0]:
		await seek(t)
		var keyed: Screen = reg.get_node_by_id("gen_keyed")
		var gen = keyed._generator_nodes[0]
		print("t %.0f: keyed generator mix %.2f, suspended %s, its pass there %s" % [t, keyed.effect_amount(0),
				gen._screen._suspended, keyed._passes.any(func(p): return p.effect == 0)])
		var grown: Screen = reg.get_node_by_id("gen_oval")
		print("t %.0f: the oval's size through effect0.effect0: %.2f" % [t, float(grown._generator_nodes[0]._screen._effect_params[0].size)])
		for i in cells.size():
			var n: Node3D = reg.get_node_by_id(cells[i].id)
			labels[i].global_position = n.global_position + Vector3(0, -0.62, 0.05) * n.global_transform.basis.get_scale().y / 0.05
		await shot_view("grid_%ds" % int(t))
	var round: Screen = reg.get_node_by_id("gen_round")
	print("rounded then generator: passes %s" % [round._passes.map(func(p): return p.effect)])
	var cost := round.gpu_passes()
	print("gpu passes of gen_round: %d (%s)" % [cost.size(), cost.map(func(p): return "%s:%d" % [p.part, p.effect])])
	studio.set_meta("cells", cells)
	await inspector_shots()
	print("save: ", m.save().get("ok", false), " valid ", ScriptFormat.load_from_file(dir.path_join("clip.json")).ok)
	print("EFFECT GENERATOR DONE")
	quit()


## The inspector on gen_key: its generator unfolded (its source, settings
## and own effects, the oval open), then the add menu with the generator
## first. Then adds a generator through the inspector's own menus.
func inspector_shots() -> void:
	await seek(1.0)
	studio.tools.select("gen_key")
	var ins: StudioInspector = studio.inspector
	var edits: StudioConfigEdits = studio.edits
	for title in ["Transform", "Surface", "Display", "Vertex effects", "Modifiers"]:
		ins.set_section_open(title, false)
	ins._open_fx["effects"] = 0
	ins._open_fx[EditModel.generator_list(0)] = 1
	ins._needs_build = true
	await frames(8)
	var own := ins._fx_rows.filter(func(r): return r.list == EditModel.generator_list(0))
	print("generator rows: top %d, its own %d; fields: %s" % [ins._fx_rows.size() - own.size(), own.size(),
			ins._rows.map(func(r): return String(r.field.key)).filter(func(k): return k.begins_with("effect0"))])
	await shot_panel("inspector", ins)
	ins._open_fx["effects"] = -1
	ins._menu = "add_effect"
	ins._needs_build = true
	await frames(8)
	await shot_panel("add_menu", ins)
	# Add one through the menus: the generator, its source, an own effect.
	var m: EditModel = studio.model
	studio.tools.select("plain")
	await frames(4)
	var before := m.effects_of("plain").size()
	ins._menu = "add_effect"
	ins._needs_build = true
	await frames(6)
	_press(ins, "AddEffectChoices", "✦ Generator")
	await frames(6)
	print("added: %s, source menu open: %s" % [m.effects_of("plain").slice(before), ins._menu])
	_press(ins, "GeneratorSourceChoices", "Hex pulse")
	await frames(6)
	ins._menu = "add_effect/%d" % before
	ins._needs_build = true
	await frames(6)
	_press(ins, "AddGeneratorEffectChoices", "Oval mask")
	await frames(6)
	print("after the menus: %s" % [m.effects_of("plain")[before]])
	var plain: Screen = studio.runner.registry().get_node_by_id("plain")
	print("plain's generator runs: %s" % [plain._passes.any(func(p): return p.effect == before and p.blend)])
	await shot_view("added")


## Press the button labelled `text` (its start) in the inspector's `grid`.
func _press(ins: StudioInspector, grid: String, text: String) -> void:
	var g := ins.find_child(grid, true, false)
	if g == null:
		print("no %s" % grid)
		return
	for b in g.get_children():
		if b is Button and String(b.text).begins_with(text):
			b.pressed.emit()
			return
	print("no %s in %s" % [text, grid])
