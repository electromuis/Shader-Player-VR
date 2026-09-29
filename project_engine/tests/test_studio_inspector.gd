extends RefCounted

## Studio's inspector (M3): config edits across spawns, the effects stack
## (renumbering `effect<N>` tracks, parking a switched-off effect's tracks),
## StudioConfigEdits (fields, values, key diamonds, what a change writes),
## shader colour hints, and live previews in the runner.

const GLOW := "res://player/visualizer/effects/glow.gdshader"
const PADDING := "res://player/visualizer/effects/padding.gdshader"
const OVAL := "res://player/visualizer/effects/oval_mask.gdshader"
const CROP := "res://player/visualizer/effects/crop.gdshader"

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 30.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn", "cube": "res://player/prefabs/cube.tscn"},
	"shaders": {"padding": PADDING, "glow": GLOW, "oval_mask": OVAL},
	"tracks": [
		{"type": "event", "t": 0, "action": "spawn", "id": "scr", "prefab": "screen", "config": {"curvature": 0.3,
			"effects": [{"shader": "padding", "params": {"amount": 1.0}},
				{"shader": "glow", "params": {"intensity": 1.6, "radius": 0.64, "tint": [1, 1, 1]}},
				{"shader": "oval_mask", "params": {"size": 0.5}}]}},
		{"type": "event", "t": 10, "action": "despawn", "target": "scr"},
		{"type": "event", "t": 20, "action": "spawn", "id": "scr", "prefab": "screen", "config": {"curvature": 0.3,
			"effects": [{"shader": "padding", "params": {"amount": 1.0}},
				{"shader": "glow", "params": {"intensity": 1.6, "radius": 0.64, "tint": [1, 1, 1]}},
				{"shader": "oval_mask", "params": {"size": 0.5}}]}},
		{"type": "event", "t": 0, "action": "spawn", "id": "box", "prefab": "cube", "config": {"modifiers": {"speed": 2.0}}},
		{"type": "shader_param", "target": "scr.effect1", "param": "intensity", "keyframes": [
			{"t": 0, "value": 1.0}, {"t": 4, "value": 3.0}]},
		{"type": "shader_param", "target": "scr.effect2", "param": "size", "keyframes": [
			{"t": 0, "value": 0.5}, {"t": 4, "value": 0.9}]},
		{"type": "shader_param", "target": "scr.display", "param": "opacity", "keyframes": [
			{"t": 2, "value": 1.0}]},
	],
}


static func _model(tc: TestCase, doc: Dictionary = DOC) -> EditModel:
	var r := EditModel.from_text(JSON.stringify(doc), "")
	tc.assert_ok(r, "document loads")
	return r.get("model")


## [target, param] of every shader_param track, sorted.
static func _param_tracks(m: EditModel) -> Array:
	var out: Array = []
	for t in m.tracks():
		if t.get("type") == "shader_param":
			out.append("%s:%s" % [t.target, t.param])
	out.sort()
	return out


static func _shaders_of(m: EditModel, spawn: int) -> Array:
	return m.tracks()[m.spawn_indices("scr")[spawn]].config.get("effects", []).map(func(e): return e.shader)


static func _valid(tc: TestCase, m: EditModel, msg: String) -> void:
	tc.assert_ok(ScriptFormat.load_from_dict(JSON.parse_string(m.to_text()), "<test>"), msg)


static func test_config_edits_every_spawn_that_shares_it(tc: TestCase) -> void:
	var doc: Dictionary = DOC.duplicate(true)
	doc.tracks[2].config.curvature = 0.7  # the second spawn has its own
	var m := _model(tc, doc)
	var s := m.spawn_indices("scr")
	tc.assert_eq(s.size(), 2)
	tc.assert_true(m.set_config("scr", "curvature", 0.5))
	tc.assert_eq(m.tracks()[s[0]].config.curvature, 0.5)
	tc.assert_eq(m.tracks()[s[1]].config.curvature, 0.7, "a spawn's own value stays")
	tc.assert_true(m.set_config("scr", ["effects", 1, "params", "radius"], 0.9, "Set scr glow radius"))
	tc.assert_eq(m.undo_label(), "Set scr glow radius")
	for i in s:
		tc.assert_eq(m.tracks()[i].config.effects[1].params.radius, 0.9, "both spawns share the effects")
	tc.assert_false(m.set_config("scr", ["effects", 7, "params", "radius"], 0.9), "no such effect")
	tc.assert_true(m.set_config("scr", ["effects", 0, "params", "extra"], 2.0), "a new param in an array entry")
	m.undo()
	m.undo()
	m.undo()
	tc.assert_eq(JSON.stringify(m.document()), JSON.stringify(_model(tc, doc).document()), "all undone")


static func test_effects_move_renumbers_tracks(tc: TestCase) -> void:
	var m := _model(tc)
	tc.assert_true(m.move_effect("scr", 2, 1))  # oval above glow
	tc.assert_eq(_shaders_of(m, 0), ["padding", "oval_mask", "glow"])
	tc.assert_eq(_shaders_of(m, 1), ["padding", "oval_mask", "glow"], "the later spawn too")
	tc.assert_eq(_param_tracks(m), ["scr.display:opacity", "scr.effect1:size", "scr.effect2:intensity"])
	tc.assert_eq(m.undo_label(), "Move scr's oval_mask up")
	m.undo()
	tc.assert_eq(JSON.stringify(m.document()), JSON.stringify(_model(tc).document()), "undone")
	tc.assert_false(m.move_effect("scr", 0, 3), "out of range")
	_valid(tc, m, "valid")


static func test_effect_off_parks_its_tracks(tc: TestCase) -> void:
	var m := _model(tc)
	tc.assert_true(m.set_effect_enabled("scr", 1, false))  # glow off
	var fx: Array = m.effects_of("scr")
	tc.assert_eq(fx[1].enabled, false)
	tc.assert_eq(fx[1].tracks.size(), 1, "glow's intensity track went into the effect")
	tc.assert_eq(fx[1].tracks[0].param, "intensity")
	tc.assert_false(fx[1].tracks[0].has("target"))
	tc.assert_eq(_param_tracks(m), ["scr.display:opacity", "scr.effect1:size"], "oval is effect1 now")
	tc.assert_eq(EditModel.effect_slot(fx, 1), -1)
	tc.assert_eq(EditModel.effect_slot(fx, 2), 1)
	_valid(tc, m, "a parked track is valid")
	var r := ScriptFormat.load_from_dict(JSON.parse_string(m.to_text()), "<test>")
	tc.assert_eq(r.data.continuous_tracks().size(), 2, "the player doesn't see parked tracks")
	# Move the off effect to the end, then switch it back on.
	tc.assert_true(m.move_effect("scr", 1, 2))
	tc.assert_eq(_param_tracks(m), ["scr.display:opacity", "scr.effect1:size"], "off effects don't count")
	tc.assert_true(m.set_effect_enabled("scr", 2, true))
	tc.assert_eq(_param_tracks(m), ["scr.display:opacity", "scr.effect1:size", "scr.effect2:intensity"])
	tc.assert_false(m.effects_of("scr")[2].has("tracks"), "unparked")
	tc.assert_false(m.effects_of("scr")[2].has("enabled"), "on is the default")
	tc.assert_false(m.set_effect_enabled("scr", 2, true), "already on")
	for i in 3:
		m.undo()
	tc.assert_eq(JSON.stringify(m.document()), JSON.stringify(_model(tc).document()), "all undone")


static func test_add_and_remove_effects(tc: TestCase) -> void:
	var m := _model(tc)
	tc.assert_true(m.add_effect("scr", CROP, {}, 0))
	tc.assert_eq(m.document().shaders.crop, CROP, "named in shaders")
	tc.assert_eq(_shaders_of(m, 0), ["crop", "padding", "glow", "oval_mask"])
	tc.assert_eq(_param_tracks(m), ["scr.display:opacity", "scr.effect2:intensity", "scr.effect3:size"])
	tc.assert_eq(m.undo_label(), "Add crop to scr")
	tc.assert_true(m.add_effect("scr", GLOW), "a second glow")
	tc.assert_eq(_shaders_of(m, 0).back(), "glow", "same key: no new shader entry")
	tc.assert_eq(m.document().shaders.size(), 4)
	tc.assert_true(m.remove_effect("scr", 2))  # the first glow, with its track
	tc.assert_eq(_shaders_of(m, 0), ["crop", "padding", "oval_mask", "glow"])
	tc.assert_eq(_param_tracks(m), ["scr.display:opacity", "scr.effect2:size"])
	tc.assert_true(m.add_effect("box", GLOW), "any object with a spawn can get a list")
	tc.assert_eq(m.effects_of("box").size(), 1)
	_valid(tc, m, "valid")
	for i in 4:
		m.undo()
	tc.assert_eq(JSON.stringify(m.document()), JSON.stringify(_model(tc).document()), "all undone")
	tc.assert_true(m.add_effect("scr", "user://shaders/My Fx.gdshader"))
	tc.assert_eq(m.document().shaders["My Fx"], "user://shaders/My Fx.gdshader")
	var m2 := _model(tc)
	for i in 3:
		m2.remove_effect("scr", 0)
	tc.assert_false(m2.config_of("scr").has("effects"), "an empty list goes")
	tc.assert_eq(_param_tracks(m2), ["scr.display:opacity"])


static func test_set_layer_shader(tc: TestCase) -> void:
	var doc: Dictionary = DOC.duplicate(true)
	doc.prefabs["layer"] = "res://player/prefabs/layer.tscn"
	doc.tracks.append({"type": "event", "t": 0, "action": "spawn", "id": "lay", "prefab": "layer",
		"config": {"shader": "ring", "params": {"x": 1}}})
	doc.shaders["ring"] = "res://player/visualizer/shaders/light_ring.gdshader"
	var m := _model(tc, doc)
	tc.assert_true(m.set_shader("lay", "res://player/visualizer/shaders/laser_fan.gdshader"))
	tc.assert_eq(m.config_of("lay").shader, "laser_fan")
	tc.assert_eq(m.config_of("lay").params, {"x": 1.0}, "params stay")
	tc.assert_true(m.set_shader("lay", "res://player/visualizer/shaders/light_ring.gdshader"))
	tc.assert_eq(m.config_of("lay").shader, "ring", "an existing key is reused")


static func test_hints_colours_and_groups(tc: TestCase) -> void:
	var h := VisualizerShaders.hints_for(GLOW)
	var tint: Array = h.colors.filter(func(c): return c.name == "tint")
	tc.assert_eq(tint.size(), 1, "glow's tint is a colour")
	tc.assert_eq(tint[0].default, Color(1, 1, 1))
	tc.assert_false(tint[0].alpha)
	tc.assert_eq(tint[0].group, "halo")
	var by_name := {}
	for p in h.params:
		by_name[p.name] = p
	tc.assert_eq(by_name.intensity.group, "halo")
	tc.assert_eq(by_name.edge_width.group, "picture_edge")
	tc.assert_eq(by_name.prepass_scale.group, "", "after a bare group_uniforms")
	var c := VisualizerShaders.parse_hints("uniform vec4 a : source_color = vec4(0.5, 0.25, 1.0, 0.0);\nuniform vec3 b : source_color;\nuniform vec3 plain = vec3(1.0);")
	tc.assert_eq(c.colors.size(), 2, "only source_color vectors")
	tc.assert_eq(c.colors[0].default, Color(0.5, 0.25, 1.0, 0.0))
	tc.assert_true(c.colors[0].alpha)
	tc.assert_eq(c.colors[1].default, Color(1, 1, 1))


static func _edits(tc: TestCase, doc: Dictionary = DOC) -> StudioConfigEdits:
	var e := StudioConfigEdits.new()
	e.model = _model(tc, doc)
	return e


static func _field(sections: Array, key: String) -> Dictionary:
	for s in sections:
		for f in s.fields:
			if f.key == key:
				return f
	return {}


static func test_inspector_fields_for_a_screen(tc: TestCase) -> void:
	var e := _edits(tc)
	var sections := e.sections("scr", null, "screen")
	var titles: Array = sections.map(func(s): return s.title)
	tc.assert_eq(titles, ["Transform", "Surface", "Display", "Padding", "Glow", "Oval mask", "Modifiers"],
			"Reactive only for objects: screens spin and pulse with vertex effects")
	tc.assert_eq(_edits(tc).sections("box", null, "object").back().title, "Reactive")
	var glow: Dictionary = sections[4]
	tc.assert_eq(glow.kind, "effect")
	tc.assert_eq(glow.list, "effects")
	tc.assert_eq(glow.index, 1)
	tc.assert_true(glow.enabled)
	var tint := _field(sections, "effect1/tint")
	tc.assert_eq(tint.type, "color")
	tc.assert_eq(tint.slot, "effect1")
	tc.assert_eq(tint.config, ["effects", 1, "params", "tint"])
	tc.assert_true(_field(sections, "effect1/samples").type == "int", "int hints")
	tc.assert_true(_field(sections, "mod_opacity").is_empty(), "a screen fades by its display opacity")
	tc.assert_false(_field(_edits(tc).sections("box", null, "object"), "mod_opacity").is_empty())
	# Values at the playhead: track, else config, else the shader's default.
	tc.assert_eq(e.value_of("scr", _field(sections, "effect1/intensity"), 2.0), 2.0, "from the track")
	tc.assert_eq(e.value_of("scr", _field(sections, "effect1/radius"), 2.0), 0.64, "from the config")
	tc.assert_eq(e.value_of("scr", _field(sections, "effect1/mirror"), 2.0), 0.5, "the shader's default")
	tc.assert_eq(e.value_of("scr", tint, 0.0), [1.0, 1.0, 1.0])
	tc.assert_eq(e.value_of("scr", _field(sections, "shape/arc_x"), 0.0), 54.0, "an earlier curvature shows as its Pillow")
	tc.assert_eq(sections[1].shader, ScreenGeometry.PILLOW)
	tc.assert_eq(e.value_of("box", _field(sections, "speed"), 0.0), 2.0)
	# Diamonds.
	tc.assert_eq(e.key_state("scr", _field(sections, "effect1/intensity"), 4.0), "key")
	tc.assert_eq(e.key_state("scr", _field(sections, "effect1/intensity"), 4.03), "key", "near enough")
	tc.assert_eq(e.key_state("scr", _field(sections, "effect1/intensity"), 3.0), "animated")
	tc.assert_eq(e.key_state("scr", _field(sections, "effect1/radius"), 3.0), "static")
	tc.assert_eq(e.key_state("scr", _field(sections, "render_scale"), 3.0), "none")
	# A switched-off effect's params can't be keyed.
	e.model.set_effect_enabled("scr", 1, false)
	var off := e.sections("scr", null, "screen")
	tc.assert_false(off[4].enabled)
	tc.assert_eq(_field(off, "effect1/radius").slot, "")
	tc.assert_eq(_field(off, "effect2/size").slot, "effect1", "oval moved up a slot")


static func test_inspector_changes_follow_auto_key(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var s := e.sections("scr", null, "screen")
	var radius := _field(s, "effect1/radius")
	# Auto-key off, a still value: the config (both spawns).
	tc.assert_eq(e.commit("scr", radius, 1.2, 3.0, false), "Set scr radius")
	for i in m.spawn_indices("scr"):
		tc.assert_eq(m.tracks()[i].config.effects[1].params.radius, 1.2)
	tc.assert_eq(e.commit("scr", radius, 1.2, 3.0, false), "", "no change, no step")
	# Auto-key off, animated, between keys: held unkeyed (2.0 -> 2.5 at 2 s).
	var intensity := _field(s, "effect1/intensity")
	tc.assert_has(e.commit("scr", intensity, 2.5, 2.0, false), "Not keyed: scr intensity 2.50")
	var kfs: Array = m.tracks()[e.track_of("scr", intensity)].keyframes
	tc.assert_eq(kfs.map(func(k): return k.value), [1.0, 3.0], "the keys stay")
	tc.assert_eq(e.value_of("scr", intensity, 2.0), 2.5, "shown")
	# Auto-key on: a key at the playhead; one near it is replaced.
	tc.assert_eq(e.commit("scr", intensity, 0.2, 1.0, true), "Key scr intensity at 0:01.00")
	tc.assert_eq(m.tracks()[e.track_of("scr", intensity)].keyframes.size(), 3)
	tc.assert_eq(e.commit("scr", intensity, 0.4, 1.02, true), "Key scr intensity at 0:01.00", "lands on the key near it")
	tc.assert_eq(m.tracks()[e.track_of("scr", intensity)].keyframes.map(func(k): return k.value), [1.0, 0.4, 3.0])
	tc.assert_true(e.unkeyed.is_empty(), "a key of the field replaces its unkeyed change")
	# Auto-key on for a still value makes its track.
	tc.assert_eq(e.commit("scr", radius, 0.3, 5.0, true), "Key scr radius at 0:05.00")
	tc.assert_true(m.find_track("shader_param", "scr.effect1", "radius") >= 0)
	# Colours: config as an array; keys as arrays too.
	var tint := _field(s, "effect1/tint")
	tc.assert_eq(e.commit("scr", tint, Color(1, 0.5, 0), 0.0, false), "Set scr tint")
	tc.assert_eq(m.config_of("scr").effects[1].params.tint, [1.0, 0.5, 0.0])
	var flash := _field(s, "flash")
	tc.assert_eq(e.commit("box", flash, Color(1, 0, 0, 0.5), 0.0, true), "Key box flash at 0:00.00")
	tc.assert_eq(m.tracks()[e.track_of("box", flash)].keyframes[0].value, [1.0, 0.0, 0.0, 0.5])
	# Config-only fields ignore auto-key.
	tc.assert_eq(e.commit("scr", _field(s, "render_scale"), 0.5, 0.0, true), "Set scr render scale")
	tc.assert_eq(m.config_of("scr").render_scale, 0.5)
	_valid(tc, m, "valid")


static func test_inspector_diamonds_toggle_keys(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var s := e.sections("scr", null, "screen")
	var size := _field(s, "effect2/size")
	tc.assert_eq(e.toggle_key("scr", size, 4.02), "Delete scr size key at 0:04.00")
	tc.assert_eq(m.tracks()[e.track_of("scr", size)].keyframes.size(), 1)
	tc.assert_eq(e.toggle_key("scr", size, 2.0), "Key scr size at 0:02.00")
	tc.assert_eq(m.tracks()[e.track_of("scr", size)].keyframes.map(func(k): return [k.t, k.value]), [[0.0, 0.5], [2.0, 0.5]],
			"keyed with the value it has there")
	var arc := _field(s, "shape/arc_x")
	tc.assert_eq(e.toggle_key("scr", arc, 1.0), "Key scr arc x at 0:01.00")
	tc.assert_eq(m.tracks()[e.track_of("scr", arc)].target, "scr.shape")
	tc.assert_eq(m.tracks()[e.track_of("scr", arc)].keyframes[0].value, 54.0, "from the earlier curvature")
	tc.assert_eq(e.toggle_key("scr", arc, 1.0), "Delete scr arc x key at 0:01.00")
	tc.assert_eq(e.track_of("scr", arc), -1, "the last key takes its track")

	tc.assert_eq(e.toggle_key("scr", _field(s, "render_scale"), 1.0), "", "can't be keyed")
	var now := {"position": [0.0, 1.0, 2.0], "rotation_deg": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]}
	tc.assert_eq(e.transform_state("box", "position", 3.0), "static")
	tc.assert_eq(e.toggle_transform_key("box", "position", 3.0, now), "Key box position at 0:03.00")
	tc.assert_eq(e.transform_state("box", "position", 3.0), "key")
	tc.assert_eq(e.transform_state("box", "position", 5.0), "animated")
	tc.assert_eq(e.toggle_transform_key("box", "position", 3.0, now), "Delete box position key at 0:03.00")


static func test_preview_holds_the_track(tc: TestCase) -> void:
	var stage := Node3D.new()
	var runner := ScriptRunner.new()
	runner.live_reload = false
	stage.add_child(runner)
	runner._stage = stage
	runner._registry = ObjectRegistry.new()
	runner.add_child(runner._registry)
	runner._prefabs = PrefabLibrary.new()
	var doc := {
		"format_version": 2, "media": {"video": "x.mp4", "duration": 20.0},
		"prefabs": {"cube": "res://player/prefabs/cube.tscn"},
		"tracks": [
			{"type": "event", "t": 0, "action": "spawn", "id": "a", "prefab": "cube"},
			{"type": "shader_param", "target": "a.modifiers", "param": "speed", "keyframes": [
				{"t": 0, "value": 1.0}, {"t": 10, "value": 3.0}]},
		],
	}
	var e := _edits(tc, doc)
	e.runner = runner
	e.model.changed.connect(func(structural: bool): runner.apply_edit(e.model.timeline(), structural))
	runner.load_timeline(e.model.timeline())
	runner.seek(5.0)
	var node := runner.registry().get_node_by_id("a")
	var speed := _field(e.sections("a", node), "speed")
	tc.assert_eq(node.get_meta("_vj_mods").speed, 2.0, "from the track")
	e.preview("a", speed, 3.5)
	tc.assert_eq(node.get_meta("_vj_mods").speed, 3.5, "live")
	runner.seek(6.0)
	tc.assert_eq(node.get_meta("_vj_mods").speed, 3.5, "held: the track doesn't write over it")
	e.end_preview("a", speed, true)
	tc.assert_eq(node.get_meta("_vj_mods").speed, 2.2, "let go without a change: the piece's value again")
	e.preview("a", speed, 0.5)
	tc.assert_eq(e.commit("a", speed, 0.5, runner.playhead, true), "Key a speed at 0:06.00")
	e.end_preview("a", speed)
	runner.seek(6.0)
	tc.assert_eq(node.get_meta("_vj_mods").speed, 0.5, "keyed")
	stage.free()
