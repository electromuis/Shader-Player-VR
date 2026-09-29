extends RefCounted

## Player features Studio catches up on (TODO 20), and the player's side of
## it: blend and fit aspect in the inspector, hint_enum params as choices,
## image params (picked, bundled into the piece, keyed as steps), a layer's
## Video source, the script's camera effects as "$camera"; string keys
## holding in Interpolation, colour params as the player's layers and
## Camera tab take them.

const TMP_DIR := "user://test_studio_catch_up_tmp"
const IMAGE_OVERLAY := "res://player/visualizer/effects/image_overlay.gdshader"
const GLOW := "res://player/visualizer/effects/glow.gdshader"
const CAMERA_TAB := preload("res://player/ui/camera_tab.gd")

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 30.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn", "layer": "res://player/prefabs/layer.tscn"},
	"shaders": {"image_overlay": IMAGE_OVERLAY},
	"tracks": [
		{"type": "event", "t": 0, "action": "spawn", "id": "scr", "prefab": "screen", "config": {
			"effects": [{"shader": "image_overlay", "params": {}}]}},
		{"type": "event", "t": 0, "action": "spawn", "id": "lay", "prefab": "layer", "parent": "scr", "config": {}},
	],
}


static func _edits(tc: TestCase, path: String = "", doc: Dictionary = DOC) -> StudioConfigEdits:
	var r := EditModel.from_text(JSON.stringify(doc), path)
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


static func test_strings_hold_between_keys(tc: TestCase) -> void:
	var kfs := [{"t": 0, "value": "normal"}, {"t": 2, "value": "add"}]
	tc.assert_eq(Interpolation.evaluate(kfs, 1.9), "normal", "linear or not, a string holds")
	tc.assert_eq(Interpolation.evaluate(kfs, 2.0), "add")
	kfs[0]["interp"] = "ease"
	tc.assert_eq(Interpolation.evaluate(kfs, 1.0), "normal")
	tc.assert_eq(Interpolation.evaluate([{"t": 0, "value": 0.0}, {"t": 2, "value": 1.0}], 1.0), 0.5, "numbers still blend")


static func test_colours_reach_uniforms(tc: TestCase) -> void:
	tc.assert_eq(ImageLibrary.value([1, 0.5, 0]), Vector3(1, 0.5, 0), "a colour as presets keep it")
	tc.assert_eq(ImageLibrary.value([1, 0.5, 0, 0.25]), Vector4(1, 0.5, 0, 0.25))
	tc.assert_eq(ImageLibrary.value(0.5), 0.5)
	tc.assert_eq(ImageLibrary.value(""), null, "no image picked")
	# The Camera tab lists a shader's colours among its sliders, in order.
	var specs := CAMERA_TAB.param_specs(VisualizerShaders.hints_for(GLOW))
	var names: Array = specs.map(func(s): return s.name)
	tc.assert_true("tint" in names, "Glow's tint gets a row")
	var tint: Dictionary = specs[names.find("tint")]
	tc.assert_eq(tint.type, "color")
	tc.assert_eq(tint.default, [1.0, 1.0, 1.0])
	tc.assert_false(tint.alpha)
	var at: Array = specs.map(func(s): return int(s.get("at", 0)))
	var sorted := at.duplicate()
	sorted.sort()
	tc.assert_eq(at, sorted, "in the shader's order")


static func test_blend_and_fit_aspect(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var s := e.sections("scr", null, "screen")
	var blend := _field(s, "blend")
	tc.assert_eq(blend.type, "choice")
	tc.assert_eq(blend.values, ["normal", "add", "black"])
	tc.assert_eq(blend.slot, "display", "keyed like opacity")
	tc.assert_eq(e.value_of("scr", blend, 0.0), "normal")
	tc.assert_eq(StudioConfigEdits.choice_label(blend, "black"), "Black transparent")
	tc.assert_eq(e.commit("scr", blend, "add", 0.0, false), "Set scr blend")
	tc.assert_eq(m.config_of("scr").blend, "add")
	tc.assert_eq(e.commit("scr", blend, "black", 4.0, true), "Key scr blend at 0:04.00")
	var kfs: Array = m.tracks()[e.track_of("scr", blend)].keyframes
	tc.assert_eq(kfs[0].get("interp"), "step", "a choice can't be in between")
	tc.assert_eq(e.commit("scr", blend, "normal", 8.0, false), "Key scr blend at 0:08.00", "animated: keys, never scaled")
	tc.assert_eq(e.value_of("scr", blend, 6.0), "black")
	var fit := _field(s, "fit_aspect")
	tc.assert_eq(fit.type, "bool")
	tc.assert_eq(e.key_state("scr", fit, 0.0), "none", "config only")
	tc.assert_eq(e.commit("scr", fit, true, 0.0, true), "Set scr fit to video")
	tc.assert_eq(m.config_of("scr").fit_aspect, true)
	tc.assert_false(_field(e.sections("lay", null, "layer"), "blend").is_empty(), "layers blend too")
	tc.assert_true(_field(e.sections("lay", null, "layer"), "fit_aspect").is_empty(), "a layer has no video shape")
	_valid(tc, m, "valid")


static func test_enum_and_image_params(tc: TestCase) -> void:
	var root := ProjectSettings.globalize_path(TMP_DIR)
	_rm(root)
	DirAccess.make_dir_recursive_absolute(root.path_join("piece"))
	DirAccess.make_dir_recursive_absolute(root.path_join("mine"))
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(root.path_join("mine/logo.png"))
	var e := _edits(tc, root.path_join("piece/clip.json"))
	var m := e.model
	var s := e.sections("scr", null, "screen")
	var mode := _field(s, "effect0/mode")
	tc.assert_eq(mode.type, "choice", "a hint_enum is a choice")
	tc.assert_eq(mode.options, ["Over", "Add", "Multiply", "Screen", "Mask"])
	tc.assert_eq(mode.values, [0, 1, 2, 3, 4])
	tc.assert_eq(e.value_of("scr", mode, 0.0), 0)
	tc.assert_eq(e.commit("scr", mode, 3, 2.0, true), "Key scr mode at 0:02.00")
	tc.assert_eq(m.tracks()[e.track_of("scr", mode)].keyframes[0].value, 3.0)
	tc.assert_eq(m.tracks()[e.track_of("scr", mode)].keyframes[0].interp, "step")
	tc.assert_eq(e.value_of("scr", mode, 5.0), 3)
	var image := _field(s, "effect0/image")
	tc.assert_eq(image.type, "texture")
	tc.assert_eq(image.default, "")
	tc.assert_eq(e.value_of("scr", image, 0.0), "")
	# A picked image from elsewhere is copied into the piece's images/.
	tc.assert_eq(e.commit("scr", image, root.path_join("mine/logo.png"), 0.0, false), "Set scr image")
	tc.assert_eq(m.config_of("scr").effects[0].params.image, "images/logo.png")
	tc.assert_true(FileAccess.file_exists(root.path_join("piece/images/logo.png")), "bundled")
	var opts: Array = e.image_options("images/logo.png")
	tc.assert_eq(opts[0], {"key": "", "label": "None"})
	tc.assert_true(opts.any(func(o): return o.key == "images/logo.png"), "the piece's own, named as the piece names it")
	tc.assert_eq(opts.filter(func(o): return o.key == "images/logo.png").size(), 1, "once")
	# Keyed, it steps (the runner resolves it against the piece's folder).
	tc.assert_eq(e.commit("scr", image, "", 6.0, true), "Key scr image at 0:06.00")
	tc.assert_eq(m.tracks()[e.track_of("scr", image)].keyframes[0].interp, "step")
	_valid(tc, m, "valid")
	var data := m.timeline()
	tc.assert_eq(data.resolve("images/logo.png"), root.path_join("piece/images/logo.png"))
	_rm(root)


static func test_layer_video_source(tc: TestCase) -> void:
	var e := _edits(tc)
	var opts := e.layer_shader_options()
	tc.assert_eq(opts[0], {"key": VisualizerShaders.VIDEO, "label": "Video"}, "the video first")
	tc.assert_true(e.set_layer_shader("lay", VisualizerShaders.VIDEO))
	tc.assert_eq(e.model.config_of("lay").shader, "video")
	tc.assert_false(e.model.document().shaders.has("video"), "not a file: nothing named")
	tc.assert_eq(e.model.undo_label(), "Set lay's source to the video")
	_valid(tc, e.model, "valid")


static func test_camera_effects(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var cam := EditModel.CAMERA
	tc.assert_eq(e.kind_for(cam), "camera")
	tc.assert_eq(e.sections(cam), [], "none yet")
	tc.assert_false(StudioTimeline.lanes(m, 30.0).any(func(l): return l.id == cam), "no lane without effects")
	var opts := e.effect_options(EditModel.EFFECTS, cam)
	tc.assert_true(opts.any(func(o): return o.key == "builtin:kaleidoscope"), "the built-ins")
	tc.assert_true(e.add_effect(cam, "builtin:kaleidoscope"))
	tc.assert_eq(m.document().camera, {"effects": [{"shader": "kaleidoscope", "params": {}}]})
	tc.assert_eq(m.document().shaders.kaleidoscope, "builtin:kaleidoscope")
	var s := e.sections(cam)
	tc.assert_eq(s.size(), 1)
	tc.assert_eq(s[0].title, "Kaleidoscope")
	var strength := _field(s, "effect0/strength")
	tc.assert_eq(strength.slot, "effect0")
	tc.assert_eq(strength.config, ["effects", 0, "strength"])
	tc.assert_eq(e.value_of(cam, strength, 0.0), 1.0)
	var segments := _field(s, "effect0/segments")
	tc.assert_false(segments.is_empty(), "its sliders")
	tc.assert_eq(e.commit(cam, segments, 8.0, 0.0, false), "Set the camera segments")
	tc.assert_eq(m.document().camera.effects[0].params.segments, 8.0)
	tc.assert_eq(e.commit(cam, strength, 0.5, 4.0, true), "Key the camera strength at 0:04.00")
	tc.assert_true(m.find_track("shader_param", "$camera.effect0", "strength") >= 0)
	# A second effect moved above it: the track follows the kaleidoscope.
	tc.assert_true(e.add_effect(cam, "builtin:hue_cycle"))
	tc.assert_true(m.move_effect(cam, 1, 0))
	tc.assert_true(m.find_track("shader_param", "$camera.effect1", "strength") >= 0, "renumbered")
	tc.assert_eq(m.effects_of(cam).map(func(x): return x.shader), ["hue_cycle", "kaleidoscope"])
	# The lane and its row.
	var lanes := StudioTimeline.lanes(m, 30.0)
	tc.assert_eq(lanes[0].id, cam, "a lane, all through")
	tc.assert_eq(lanes[0].spans, [[0.0, 30.0]])
	var rows := StudioTimeline.property_rows(m, cam)
	tc.assert_eq(rows.size(), 1)
	tc.assert_eq(rows[0].label, "Kaleidoscope strength")
	_valid(tc, m, "valid")
	# What the player runs: the first that's on.
	var runner := ScriptRunner.new()
	runner.timeline = m.timeline()
	tc.assert_eq(runner.camera_effect().key, "builtin:hue_cycle")
	tc.assert_true(m.set_effect_enabled(cam, 0, false))
	runner.timeline = m.timeline()
	tc.assert_eq(runner.camera_effect().key, "builtin:kaleidoscope")
	runner.free()
	# Removing them all takes the block with them; undo puts it all back.
	tc.assert_true(m.remove_effect(cam, 1))
	tc.assert_true(m.remove_effect(cam, 0))
	tc.assert_false(m.document().has("camera"))
	tc.assert_eq(m.find_track("shader_param", "$camera.effect0", "strength"), -1, "its track went with it")
	while m.can_undo():
		m.undo()
	tc.assert_false(m.document().has("camera"), "back to the start")
	tc.assert_false(m.is_dirty())


static func test_camera_preview_in_the_runner(tc: TestCase) -> void:
	var stage := Node3D.new()
	var runner := ScriptRunner.new()
	runner.live_reload = false
	stage.add_child(runner)
	runner._stage = stage
	runner._registry = ObjectRegistry.new()
	runner.add_child(runner._registry)
	runner._prefabs = PrefabLibrary.new()
	# No screens: they only spawn in a scene tree.
	var e := _edits(tc, "", {"format_version": 2, "media": {"video": "x.mp4", "duration": 20.0}, "tracks": []})
	e.runner = runner
	e.model.changed.connect(func(structural: bool): runner.apply_edit(e.model.timeline(), structural))
	e.add_effect(EditModel.CAMERA, "builtin:kaleidoscope")
	e.commit(EditModel.CAMERA, _field(e.sections(EditModel.CAMERA), "effect0/strength"), 0.4, 0.0, false)
	runner.load_timeline(e.model.timeline())
	runner.seek(1.0)
	var strength := _field(e.sections(EditModel.CAMERA), "effect0/strength")
	tc.assert_eq(runner.camera_effect().strength, 0.4, "the config's")
	e.preview(EditModel.CAMERA, strength, 0.9)
	tc.assert_eq(runner.camera_effect().strength, 0.9, "live")
	e.end_preview(EditModel.CAMERA, strength, true)
	tc.assert_eq(runner.camera_effect().strength, 0.4, "let go: the piece's again")
	stage.free()


static func _rm(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
