extends RefCounted

## Effects' mix and blend (EffectBlend, TODO 59) and switching them on and
## off over time (EffectSwitch, TODO 58): the format, the screen's chain,
## the runner and camera effects, and Studio's inspector and timeline.

const EffectBlend := preload("res://player/visualizer/effect_blend.gd")
const GLOW := "res://player/visualizer/effects/glow.gdshader"
const OVAL := "res://player/visualizer/effects/oval_mask.gdshader"

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 30.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn"},
	"shaders": {"glow": GLOW, "oval_mask": OVAL},
	"tracks": [
		{"type": "event", "t": 0, "action": "spawn", "id": "scr", "prefab": "screen", "config": {
			"effects": [{"shader": "glow", "params": {"intensity": 1.5}, "mix": 0.5, "blend": "add"},
				{"shader": "oval_mask", "params": {"size": 0.5}}],
			"vertex_effects": [{"shader": "ripple", "mix": 0.25}]}},
		{"type": "shader_param", "target": "scr.effect1", "param": "enabled", "keyframes": [
			{"t": 0, "value": true, "interp": "step"},
			{"t": 10, "value": false, "interp": "step", "transition": {"type": "fade", "duration": 2}},
			{"t": 20, "value": true, "interp": "step"}]},
	],
}


static func _doc() -> Dictionary:
	return DOC.duplicate(true)


static func _keys(pairs: Array) -> Array:
	return pairs.map(func(p): return {"t": p[0], "value": p[1], "interp": "step",
			"transition": {"type": "fade", "duration": p[2]}} if p.size() > 2 else {"t": p[0], "value": p[1], "interp": "step"})


static func _near(tc: TestCase, a: float, b: float, msg: String) -> void:
	tc.assert_true(absf(a - b) < 1e-4, "%s: %s, expected %s" % [msg, a, b])


# ---------- the player ----------

static func test_switch_levels(tc: TestCase) -> void:
	_near(tc, EffectSwitch.level([], 3.0), 1.0, "no keys: on")
	var kfs := _keys([[5.0, false], [10.0, true, 2.0], [20.0, false, 4.0], [21.0, true, 1.0]])
	_near(tc, EffectSwitch.level(kfs, 0.0), 0.0, "before the first key: its state")
	_near(tc, EffectSwitch.level(kfs, 7.0), 0.0, "off")
	_near(tc, EffectSwitch.level(kfs, 10.0), 0.0, "a fade starts at its key")
	_near(tc, EffectSwitch.level(kfs, 11.0), 0.5, "half way in")
	_near(tc, EffectSwitch.level(kfs, 15.0), 1.0, "in")
	_near(tc, EffectSwitch.level(kfs, 20.5), 0.875, "fading out over 4 s")
	_near(tc, EffectSwitch.level(kfs, 21.0), 0.75, "the fade out a quarter done")
	_near(tc, EffectSwitch.level(kfs, 21.5), 0.875, "back in from where the fade out had got to")
	_near(tc, EffectSwitch.level(kfs, 30.0), 1.0, "held after the last key")
	tc.assert_true(EffectSwitch.is_on(1) and not EffectSwitch.is_on(0.0) and not EffectSwitch.is_on(false))


static func test_format(tc: TestCase) -> void:
	tc.assert_ok(ScriptFormat.load_from_dict(_doc()), "mix, blend and on / off keys load")
	var bad := _doc()
	bad.tracks[0].config.effects[0].mix = 1.5
	tc.assert_err(ScriptFormat.load_from_dict(bad), "mix must be a number from 0 to 1")
	bad = _doc()
	bad.tracks[0].config.effects[0].blend = "burn"
	tc.assert_err(ScriptFormat.load_from_dict(bad), "blend must be one of")
	bad = _doc()
	bad.tracks[0].config.vertex_effects[0]["blend"] = "add"
	tc.assert_err(ScriptFormat.load_from_dict(bad), "effects only")
	bad = _doc()
	bad.tracks[1].keyframes[1].transition = {"type": "fade_to_black", "duration": 1}
	tc.assert_err(ScriptFormat.load_from_dict(bad), "\"type\": \"fade\"")
	bad = _doc()
	bad.tracks[1].keyframes[0].value = "yes"
	tc.assert_err(ScriptFormat.load_from_dict(bad), "value must be true or false")
	var cam := _doc()
	cam["camera"] = {"effects": [{"shader": "builtin:kaleidoscope", "blend": "screen"}]}
	tc.assert_ok(ScriptFormat.load_from_dict(cam), "a camera effect's blend")
	cam.camera.effects[0].blend = "nope"
	tc.assert_err(ScriptFormat.load_from_dict(cam), "camera.effects[0].blend")


static func test_blend_modes_in_order(tc: TestCase) -> void:
	# effect_blend() numbers the modes as MODES does.
	var code := EffectBlend.FUNCTIONS
	tc.assert_eq(EffectBlend.MODES.size(), 9)
	for i in range(1, EffectBlend.MODES.size()):
		tc.assert_true(code.contains("if (eb_mode == %d)" % i), "mode %d (%s) is handled" % [i, EffectBlend.MODES[i]])
	tc.assert_eq(EffectBlend.index_of("screen"), 4)
	tc.assert_eq(EffectBlend.index_of("bogus"), 0, "unknown: normal")
	tc.assert_eq(EffectBlend.LABELS.size(), EffectBlend.MODES.size())
	tc.assert_true(EffectBlend.pass_shader().code.contains("effect_mix("), "the pass shader")
	tc.assert_true(CameraFxShaders.build_source("// @camera\nvec3 camera_fx(vec2 uv) { return view_color(uv); }\n")
			.contains("effect_blend(base.rgb, camera_fx(uv), pc.fx_blend)"), "camera effects blend too")


static func test_screen_blend_pass(tc: TestCase) -> void:
	var screen: Screen = load("res://player/prefabs/screen.tscn").instantiate()
	screen.notification(Node.NOTIFICATION_READY)
	screen.set_source_texture(ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8)))
	var blends := func() -> Array: return screen._passes.filter(func(p): return p.blend).map(func(p): return p.effect)
	var effects := func() -> Array:
		var out: Array = []
		for p in screen._passes:
			if p.effect >= 0 and not p.blend and not out.has(p.effect):
				out.append(p.effect)
		return out
	screen.set_effects([{"shader": OVAL}, {"shader": OVAL, "mix": 0.5}, {"shader": OVAL, "blend": "multiply"}])
	tc.assert_eq(effects.call(), [0, 1, 2])
	tc.assert_eq(blends.call(), [1, 2], "a blend pass after the one that mixes and the one that blends")
	var last: Dictionary = screen._passes[-1]
	tc.assert_eq(last.material.get_shader_parameter("blend_mode"), 3)
	tc.assert_eq(last.material.get_shader_parameter("mix_amount"), 1.0)
	var before: Dictionary = screen._passes[-2]
	tc.assert_true(before.effect == 2 and not before.blend, "right after the effect's own pass")
	var fx_tex = last.material.get_shader_parameter("effect_tex")
	tc.assert_true(fx_tex is ViewportTexture and fx_tex != last.material.get_shader_parameter("input_tex"),
			"reads the effect's output as well as its input")
	screen.set_effect_param(0, "mix", 0.3)
	tc.assert_eq(blends.call(), [0, 1, 2], "mixing it adds its pass")
	tc.assert_eq(screen._passes.filter(func(p): return p.blend and p.effect == 0)[0].material.get_shader_parameter("mix_amount"), 0.3)
	screen.set_effect_param(1, "enabled", 0.5)
	_near(tc, screen.effect_amount(1), 0.25, "the switch level multiplies the mix")
	screen.set_effect_param(1, "enabled", false)
	tc.assert_eq(effects.call(), [0, 2], "switched off: skipped")
	screen.set_effect_param(1, "enabled", true)
	screen.set_effect_param(2, "blend", "normal")
	screen.set_effect_param(1, "mix", 1.0)
	screen.set_effect_param(0, "mix", 1.0)
	tc.assert_eq(blends.call(), [], "all plain again: no blend passes")
	tc.assert_eq(effects.call(), [0, 1, 2], "and all three run")
	# Vertex effects: a mix uniform each, times the switch.
	screen.set_vertex_effects([{"shader": "ripple", "mix": 0.5}])
	_near(tc, float(screen.get_display_material().get_shader_parameter("vfx0_mix")), 0.5, "vertex mix")
	screen.set_vertex_effect_param(0, "enabled", false)
	_near(tc, float(screen.get_display_material().get_shader_parameter("vfx0_mix")), 0.0, "vertex switched off")
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


static func test_runner_switches_and_mixes(tc: TestCase) -> void:
	var runner := _runner(_doc())
	runner.seek(5.0)
	var scr = runner.registry().get_node_by_id("scr")
	tc.assert_true(scr is Screen, "the screen spawned")
	_near(tc, scr.effect_amount(0), 0.5, "the entry's mix")
	tc.assert_eq(scr._effect_blend[0], EffectBlend.index_of("add"))
	_near(tc, scr.effect_amount(1), 1.0, "on")
	runner.seek(11.0)
	runner._evaluate_continuous_tracks()
	_near(tc, scr.effect_amount(1), 0.5, "fading out")
	runner.seek(15.0)
	runner._evaluate_continuous_tracks()
	_near(tc, scr.effect_amount(1), 0.0, "off, still in its place")
	tc.assert_eq(scr._effect_keys.size(), 2)
	runner.seek(25.0)
	runner._evaluate_continuous_tracks()
	_near(tc, scr.effect_amount(1), 1.0, "back on")
	_near(tc, scr._vertex_effects[0].mix, 0.25, "the vertex effect's mix")
	runner.free()


static func test_camera_effect_switch_and_blend(tc: TestCase) -> void:
	var doc := _doc()
	doc["camera"] = {"effects": [{"shader": "builtin:kaleidoscope", "strength": 0.8, "blend": "screen"}]}
	doc.tracks.append({"type": "shader_param", "target": "$camera.effect0", "param": "enabled",
			"keyframes": _keys([[0.0, true], [4.0, false, 2.0]])})
	var runner := _runner(doc)
	runner.seek(1.0)
	var e := runner.camera_effect()
	_near(tc, e.strength, 0.8, "on")
	tc.assert_eq(e.blend, "screen")
	tc.assert_false(e.params.has("enabled"), "not a shader param")
	runner.seek(5.0)
	_near(tc, runner.camera_effect().strength, 0.4, "fading out: the level multiplies the strength")
	runner.seek(9.0)
	_near(tc, runner.camera_effect().strength, 0.0, "off")
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


static func test_studio_mix_and_blend_fields(tc: TestCase) -> void:
	var e := _edits(tc)
	var s := e.sections("scr", null, "screen")
	var mix := _field(s, "effect0/mix")
	var blend := _field(s, "effect0/blend")
	tc.assert_eq(mix.config, ["effects", 0, "mix"])
	tc.assert_eq(mix.slot, "effect0")
	tc.assert_eq(blend.values, EffectBlend.MODES)
	tc.assert_eq(e.value_of("scr", mix, 0.0), 0.5, "from the entry")
	tc.assert_eq(e.value_of("scr", blend, 0.0), "add")
	tc.assert_eq(e.value_of("scr", _field(s, "effect1/mix"), 0.0), 1.0, "the default")
	tc.assert_false(_field(s, "vertex0/mix").is_empty(), "vertex effects mix")
	tc.assert_true(_field(s, "vertex0/blend").is_empty(), "but don't blend")
	tc.assert_eq(e.commit("scr", blend, "screen", 3.0, false), "Set scr blend")
	tc.assert_eq(e.model.effects_of("scr")[0].blend, "screen")
	tc.assert_eq(e.commit("scr", mix, 0.0, 3.0, true), "Key scr mix at 0:03.00", "auto-key keys the mix")
	tc.assert_true(e.model.find_track("shader_param", "scr.effect0", "mix") >= 0)
	_valid(tc, e.model, "valid after mixing")


static func test_studio_switch(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	# The oval has on / off keys: the switch shows them, and keys.
	tc.assert_true(e.switch_on("scr", 1, 5.0))
	tc.assert_true(e.switch_on("scr", 1, 11.0), "still fading")
	tc.assert_false(e.switch_on("scr", 1, 15.0))
	tc.assert_eq(e.switch_state("scr", 1, 10.02), "key")
	tc.assert_eq(e.switch_state("scr", 1, 5.0), "animated")
	tc.assert_eq(e.switch_state("scr", 0, 5.0), "static")
	tc.assert_eq(e.set_switch("scr", 1, false, 25.0, false), "Key scr's oval_mask off at 0:25.00",
			"one that has keys keys, auto-key or not")
	tc.assert_false(e.switch_on("scr", 1, 26.0))
	# Without keys and auto-key: the config, for the whole piece.
	tc.assert_eq(e.set_switch("scr", 0, false, 5.0, false), "Turn scr's glow off")
	tc.assert_eq(m.effects_of("scr")[0].enabled, false)
	tc.assert_true(m.find_track("shader_param", "scr.effect0", "enabled") >= 0, "the oval's keys follow it up to effect0")
	m.undo()
	# With auto-key: off from the playhead, on before it.
	tc.assert_eq(e.set_switch("scr", 0, false, 8.0, true), "Key scr's glow off at 0:08.00")
	var ti := e.switch_track("scr", 0)
	var kfs: Array = m.tracks()[ti].keyframes
	tc.assert_eq(kfs.map(func(k): return [k.t, k.value]), [[0.0, true], [8.0, false]])
	tc.assert_true(e.switch_on("scr", 0, 7.0) and not e.switch_on("scr", 0, 9.0))
	tc.assert_eq(m.effects_of("scr")[0].get("enabled", true), true, "still counted: effect0 stays")
	m.undo()
	tc.assert_eq(e.switch_track("scr", 0), -1, "one undo step")
	# Off in the config and switched on with auto-key: on in the config,
	# off until the playhead.
	m.set_effect_enabled("scr", 0, false)
	tc.assert_eq(e.set_switch("scr", 0, true, 6.0, true), "Key scr's glow on at 0:06.00")
	tc.assert_true(m.effects_of("scr")[0].get("enabled", true))
	tc.assert_eq(m.tracks()[e.switch_track("scr", 0)].keyframes.map(func(k): return [k.t, k.value]), [[0.0, false], [6.0, true]])
	_valid(tc, m, "valid after switching")
	# A key's fade.
	var oval := e.switch_track("scr", 1)
	tc.assert_true(m.set_key_fade(oval, 2, 0.5))
	tc.assert_eq(m.tracks()[oval].keyframes[2].transition, {"type": "fade", "duration": 0.5})
	tc.assert_true(m.set_key_fade(oval, 2, 0.0))
	tc.assert_false(m.tracks()[oval].keyframes[2].has("transition"), "a cut")
	tc.assert_false(m.set_key_fade(oval, 2, 0.0), "nothing to change")
	_valid(tc, m, "valid after fades")


static func test_timeline_switch_rows(tc: TestCase) -> void:
	var e := _edits(tc)
	var rows := StudioTimeline.property_rows(e.model, "scr")
	var switch: Array = rows.filter(func(r): return r.get("switch", false))
	tc.assert_eq(switch.size(), 1)
	tc.assert_eq(switch[0].label, "Oval mask on / off")
	tc.assert_eq(switch[0].keys.size(), 3)
