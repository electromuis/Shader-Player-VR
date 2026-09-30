extends RefCounted

## Generator effects (TODO 79): an effect that mixes a layer shader into the
## picture, the layer shaped by its own effects first. The format, the
## screen's chain, the runner, and Studio's inspector and model.

const EffectBlend := preload("res://player/visualizer/effect_blend.gd")
const OVAL := "res://player/visualizer/effects/oval_mask.gdshader"
const GLOW := "res://player/visualizer/effects/glow.gdshader"
const HEX := "res://player/visualizer/shaders/hex_pulse.gdshader"

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 30.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn"},
	"shaders": {"glow": GLOW, "oval_mask": OVAL, "hex": HEX},
	"tracks": [
		{"type": "event", "t": 0, "action": "spawn", "id": "scr", "prefab": "screen", "config": {
			"effects": [{"shader": "glow"},
				{"shader": "generator", "mix": 0.8, "blend": "add", "generator": {
					"shader": "hex", "params": {"cells": 2.0}, "resolution": 0.5,
					"effects": [{"shader": "oval_mask", "params": {"size": 0.5}}]}}]}},
		{"type": "shader_param", "target": "scr.effect1", "param": "mix", "keyframes": [
			{"t": 0, "value": 0.8}, {"t": 10, "value": 0.0}, {"t": 20, "value": 1.0}]},
		{"type": "shader_param", "target": "scr.effect1.effect0", "param": "size", "keyframes": [
			{"t": 0, "value": 0.5}, {"t": 20, "value": 0.9}]},
	],
}


static func _doc() -> Dictionary:
	return DOC.duplicate(true)


static func _near(tc: TestCase, a: float, b: float, msg: String) -> void:
	tc.assert_true(absf(a - b) < 1e-4, "%s: %s, expected %s" % [msg, a, b])


static func test_format(tc: TestCase) -> void:
	tc.assert_ok(ScriptFormat.load_from_dict(_doc()), "a generator and tracks on its own effects load")
	var bad := _doc()
	bad.tracks[0].config.effects[1].generator.erase("shader")
	tc.assert_err(ScriptFormat.load_from_dict(bad), "generator must be an object with a shader")
	bad = _doc()
	bad.tracks[0].config.effects[1].generator.effects.append({"shader": "generator", "generator": {"shader": "hex"}})
	tc.assert_err(ScriptFormat.load_from_dict(bad), "can't be a generator")
	bad = _doc()
	bad.tracks[0].config.effects[1].generator.effects[0].blend = "burn"
	tc.assert_err(ScriptFormat.load_from_dict(bad), "generator.effects[0].blend")
	bad = _doc()
	bad.tracks[0].config.effects[1].generator.resolution = "big"
	tc.assert_err(ScriptFormat.load_from_dict(bad), "resolution must be a number")
	bad = _doc()
	bad.tracks[0].config["vertex_effects"] = [{"shader": "generator", "generator": {"shader": "hex"}}]
	tc.assert_err(ScriptFormat.load_from_dict(bad), "pixel effects only")
	tc.assert_true(VisualizerShaders.is_generator(_doc().tracks[0].config.effects[1]))
	tc.assert_false(VisualizerShaders.is_generator({"shader": "generator"}), "needs its generator")


static func _screen() -> Screen:
	var screen: Screen = load("res://player/prefabs/screen.tscn").instantiate()
	screen.notification(Node.NOTIFICATION_READY)
	screen.set_source_texture(ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8)))
	return screen


static func _generator_effects() -> Array:
	return [{"shader": OVAL},
		{"shader": "generator", "mix": 0.8, "blend": "add", "generator": {
			"shader": HEX, "params": {"cells": 2.0}, "resolution": 0.5,
			"effects": [{"shader": OVAL, "params": {"size": 0.5}},
				{"shader": "generator", "generator": {"shader": HEX}}]}}]


static func test_screen_mixes_a_generator(tc: TestCase) -> void:
	var screen := _screen()
	screen.set_effects(_generator_effects())
	var gen: Visualizer = screen._generator_nodes[1]
	tc.assert_true(gen != null and gen.offscreen, "an offscreen layer renders it")
	tc.assert_true(screen._generator_nodes[0] == null, "a plain effect has none")
	tc.assert_eq(gen.get_shader_key(), HEX)
	tc.assert_false(gen._screen.mesh.visible, "it draws nothing itself")
	tc.assert_eq(gen._screen._effect_keys, [OVAL, ""] as Array[String], "its own effects; a generator in it is skipped")
	tc.assert_eq(gen._screen.render_viewport.size, Vector2i(screen.render_viewport.size * 0.5),
			"the picture's render size times its resolution")
	var last: Dictionary = screen._passes[-1]
	tc.assert_true(last.effect == 1 and last.blend, "one pass for it, last")
	tc.assert_eq(last.material.shader, EffectBlend.generator_shader())
	tc.assert_true(last.material.get_shader_parameter("effect_tex") == gen.output_texture()
			and gen.output_texture() == gen._screen._passes[-1].viewport.get_texture(),
			"it reads the generator's picture after its own effects")
	tc.assert_true(last.material.get_shader_parameter("input_tex") == screen._passes[-2].viewport.get_texture(),
			"over what the effect before it made")
	tc.assert_eq(last.material.get_shader_parameter("blend_mode"), EffectBlend.index_of("add"))
	_near(tc, last.material.get_shader_parameter("mix_amount"), 0.8, "its mix")
	tc.assert_eq(screen.output_texture(), last.viewport.get_texture())
	# Tracks: its layer shader's params on effect1, its own effects on effect1.effect<M>.
	screen.set_material_param("effect1", "cells", 3.0)
	tc.assert_eq(gen._material.get_shader_parameter("cells"), 3.0, "the layer shader's param")
	screen.set_material_param("effect1.effect0", "size", 0.7)
	tc.assert_eq(gen._screen._effect_params[0].size, 0.7, "its own effect's param")
	screen.set_material_param("effect1.effect0", "mix", 0.5)
	tc.assert_true(gen._screen._passes.any(func(p): return p.blend), "its own effect's mix")
	var old_tex := gen.output_texture()
	screen.set_material_param("effect1.effect0", "mix", 1.0)
	tc.assert_true(gen.output_texture() != old_tex, "its chain rebuilt...")
	tc.assert_eq(screen._passes[-1].material.get_shader_parameter("effect_tex"), gen.output_texture(), "...and the pass follows")
	# At mix 0 it's suspended and costs nothing.
	var passes_before := screen.gpu_passes().size()
	tc.assert_true(passes_before > screen._passes.size(), "its layer's passes count under the host")
	screen.set_effect_param(1, "mix", 0.0)
	tc.assert_true(gen._screen._suspended, "suspended at mix 0")
	tc.assert_eq(gen._screen.render_viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	tc.assert_true(gen._screen._passes.all(func(p): return p.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED))
	tc.assert_false(screen._passes.any(func(p): return p.effect == 1), "no pass for it")
	tc.assert_true(screen.gpu_passes().all(func(p): return p.effect != 1), "nothing timed for it")
	screen.set_effect_param(1, "enabled", false)
	screen.set_effect_param(1, "mix", 1.0)
	tc.assert_true(gen._screen._suspended, "switched off by a track: still suspended")
	screen.set_effect_param(1, "enabled", true)
	tc.assert_false(gen._screen._suspended, "back")
	tc.assert_eq(gen._screen.render_viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	tc.assert_eq(screen._passes[-1].effect, 1)
	tc.assert_eq(screen.gpu_passes().size(), passes_before)
	# Same list again: the same layer, new params; switched off in the config: gone.
	var fx := _generator_effects()
	fx[1].generator.params.cells = 5.0
	screen.set_effects(fx)
	tc.assert_true(screen._generator_nodes[1] == gen, "kept")
	tc.assert_eq(gen._material.get_shader_parameter("cells"), 5.0)
	fx[1]["enabled"] = false
	screen.set_effects(fx)
	tc.assert_true(screen._generator_nodes[1] == null, "switched off: freed")
	tc.assert_false(screen._passes.any(func(p): return p.effect == 1))
	screen.free()


static func test_nested_screen_skips_generators(tc: TestCase) -> void:
	var screen := _screen()
	screen.nested = true
	screen.set_effects(_generator_effects())
	tc.assert_true(screen._generator_nodes.all(func(g): return g == null), "a generator's layer has none of its own")
	tc.assert_eq(screen._effect_keys, [OVAL, ""] as Array[String])
	screen.free()


static func _runner(doc: Dictionary) -> ScriptRunner:
	var runner := ScriptRunner.new()
	runner.live_reload = false
	runner._stage = Node3D.new()
	runner.add_child(runner._stage)
	runner._registry = ObjectRegistry.new()
	runner.add_child(runner._registry)
	runner._prefabs = PrefabLibrary.new()
	runner.load_timeline(ScriptFormat.load_from_dict(doc).data)
	return runner


static func test_runner_resolves_and_animates(tc: TestCase) -> void:
	var runner := _runner(_doc())
	runner.seek(5.0)
	runner._evaluate_continuous_tracks()
	var scr = runner.registry().get_node_by_id("scr")
	tc.assert_true(scr is Screen, "the screen spawned")
	var gen: Visualizer = scr._generator_nodes[1]
	tc.assert_true(gen != null, "its generator")
	tc.assert_eq(gen.get_shader_key(), HEX, "the shaders name resolved to its file")
	tc.assert_eq(gen._screen._effect_keys, [OVAL] as Array[String], "and its own effect's")
	tc.assert_eq(gen._material.get_shader_parameter("cells"), 2.0)
	_near(tc, scr.effect_amount(1), 0.4, "the mix track")
	_near(tc, float(gen._screen._effect_params[0].size), 0.6, "the track on its own effect")
	runner.seek(10.0)
	runner._evaluate_continuous_tracks()
	tc.assert_true(gen._screen._suspended, "mix 0: suspended")
	runner.seek(20.0)
	runner._evaluate_continuous_tracks()
	tc.assert_false(gen._screen._suspended)
	runner.free()


# ---------- Studio ----------

static func _edits(tc: TestCase, doc: Dictionary = _doc()) -> StudioConfigEdits:
	var r := EditModel.from_text(JSON.stringify(doc), "")
	tc.assert_ok(r, "document loads")
	var e := StudioConfigEdits.new()
	e.model = r.get("model")
	return e


static func _field(sections: Array, key: String) -> Dictionary:
	for s in sections:
		for f in s.fields:
			if f.key == key:
				return f
	return {}


static func _valid(tc: TestCase, m: EditModel, msg: String) -> void:
	tc.assert_ok(ScriptFormat.load_from_dict(JSON.parse_string(m.to_text()), "<test>"), msg)


static func _targets(m: EditModel) -> Array:
	var out: Array = []
	for t in m.tracks():
		if t.get("type") == "shader_param":
			out.append("%s:%s" % [t.target, t.param])
	return out


static func test_studio_sections(tc: TestCase) -> void:
	var e := _edits(tc)
	var s := e.sections("scr", null, "screen")
	var gen: Array = s.filter(func(x): return x.get("generator", false))
	tc.assert_eq(gen.size(), 1, "one generator section")
	tc.assert_eq(gen[0].title, "Generator · Hex pulse")
	tc.assert_eq(gen[0].layer, "hex")
	tc.assert_eq(gen[0].fields.slice(0, 3).map(func(f): return f.key), ["effect1/mix", "effect1/blend", "effect1/resolution"])
	var cells := _field(s, "effect1/cells")
	tc.assert_eq(cells.slot, "effect1", "its layer shader's params key on its slot")
	tc.assert_eq(cells.config, ["effects", 1, "generator", "params", "cells"])
	tc.assert_eq(e.value_of("scr", cells, 0.0), 2.0)
	tc.assert_eq(_field(s, "effect1/resolution").slot, "", "resolution is config-only")
	var own: Array = s.filter(func(x): return x.kind == "effect" and x.list == EditModel.generator_list(1))
	tc.assert_eq(own.size(), 1, "its own effect's section, right after it")
	tc.assert_eq(s.find(own[0]), s.find(gen[0]) + 1)
	var size := _field(s, "effect1.0/size")
	tc.assert_eq(size.slot, "effect1.effect0")
	tc.assert_eq(size.config, ["effects", 1, "generator", "effects", 0, "params", "size"])
	_near(tc, e.value_of("scr", size, 10.0), 0.7, "from its track")
	# Writing: the config, and keys on the nested slot.
	tc.assert_eq(e.commit("scr", cells, 7.0, 3.0, false), "Set scr cells")
	tc.assert_eq(e.model.effects_of("scr")[1].generator.params.cells, 7.0)
	tc.assert_eq(e.commit("scr", _field(s, "effect1.0/blur"), 0.4, 3.0, true), "Key scr blur at 0:03.00")
	tc.assert_true(e.model.find_track("shader_param", "scr.effect1.effect0", "blur") >= 0)
	tc.assert_eq(e.commit("scr", _field(s, "effect1/resolution"), 0.75, 3.0, true), "Set scr resolution",
			"config-only even with auto-key")
	# Its own effect's switch keys on its nested target.
	tc.assert_eq(e.set_switch("scr", 0, false, 5.0, true, EditModel.generator_list(1)), "Key scr's oval_mask off at 0:05.00")
	tc.assert_true(e.switch_track("scr", 0, EditModel.generator_list(1)) >= 0)
	tc.assert_false(e.switch_on("scr", 0, 6.0, EditModel.generator_list(1)))
	_valid(tc, e.model, "valid after editing")
	# The add menus: a generator for the pixel effects, not inside one.
	tc.assert_eq(e.effect_options()[0].key, VisualizerShaders.GENERATOR)
	tc.assert_false(e.effect_options(EditModel.generator_list(1)).any(func(o): return o.key == VisualizerShaders.GENERATOR))
	tc.assert_false(e.effect_options(EditModel.VERTEX_EFFECTS).any(func(o): return o.key == VisualizerShaders.GENERATOR))
	# The timeline names the rows.
	var labels := StudioTimeline.property_rows(e.model, "scr").map(func(r): return r.label)
	tc.assert_true(labels.has("Generator mix"), str(labels))
	tc.assert_true(labels.has("Generator › Oval mask size"), str(labels))


static func test_studio_model(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var own := EditModel.generator_list(1)
	tc.assert_eq(EditModel.list_owner(own), 1)
	tc.assert_eq(EditModel.list_path(own), ["effects", 1, "generator", "effects"])
	tc.assert_eq(m.effect_target("scr", 0, own), "scr.effect1.effect0")
	tc.assert_eq(m.effects_of("scr", own).size(), 1)
	# Its own list: add, move; tracks on it follow.
	tc.assert_true(e.add_effect("scr", GLOW, own))
	tc.assert_eq(m.effects_of("scr", own).map(func(x): return x.shader), ["oval_mask", "glow"])
	tc.assert_true(m.move_effect("scr", 1, 0, own))
	tc.assert_true(_targets(m).has("scr.effect1.effect1:size"), "the oval's track moved with it: %s" % [_targets(m)])
	m.undo()
	m.undo()
	tc.assert_eq(m.effects_of("scr", own).size(), 1, "undone")
	# The top list: moving the generator carries its own effects' tracks.
	tc.assert_true(m.move_effect("scr", 1, 0))
	tc.assert_eq(_targets(m), ["scr.effect0:mix", "scr.effect0.effect0:size"])
	# Off in the config: its tracks, its own effects' too, park in its entry.
	tc.assert_true(m.set_effect_enabled("scr", 0, false))
	tc.assert_eq(_targets(m), [])
	var parked: Array = m.effects_of("scr")[0].tracks
	tc.assert_eq(parked.map(func(p): return [p.get("sub", ""), p.param]), [["", "mix"], ["effect0", "size"]])
	_valid(tc, m, "valid with parked tracks")
	tc.assert_eq(m.slot_prefix("scr", EditModel.generator_list(0)), "", "no slot while it's off")
	tc.assert_false(e.add_effect("scr", GLOW, EditModel.generator_list(0)), "its list can't change while it's off")
	tc.assert_true(m.set_effect_enabled("scr", 0, true))
	tc.assert_eq(_targets(m), ["scr.effect0:mix", "scr.effect0.effect0:size"], "back")
	# A new generator, its source picked; then removing it takes its tracks.
	tc.assert_true(e.add_effect("scr", VisualizerShaders.GENERATOR))
	var added: Dictionary = m.effects_of("scr")[2]
	tc.assert_eq(added, {"shader": "generator", "generator": {"shader": ""}})
	tc.assert_true(e.set_generator_shader("scr", 2, VisualizerShaders.VIDEO))
	tc.assert_eq(m.effects_of("scr")[2].generator.shader, "video")
	tc.assert_eq(e.layer_label("video"), "Video")
	tc.assert_true(m.set_generator_shader("scr", 2, HEX))
	tc.assert_eq(m.effects_of("scr")[2].generator.shader, "hex", "named by its shaders key")
	tc.assert_false(m.set_generator_shader("scr", 1, HEX), "not a generator")
	tc.assert_true(m.remove_effect("scr", 0))
	tc.assert_eq(_targets(m), [], "gone with it")
	_valid(tc, m, "valid after the stack changes")
