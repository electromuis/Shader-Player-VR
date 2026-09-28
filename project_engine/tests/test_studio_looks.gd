extends RefCounted

## Looks (M8): saving an object's setup to the library (StudioLooks.save:
## its shaders copied there, a switched-off effect's tracks left out),
## the shelf listing them (StudioAssetLibrary), and dropping one
## (StudioAssetDrop): on something of its kind it takes the setup in one
## undo step (EditModel.replace_config: the piece names the look's shaders,
## effect tracks go when the effects change, other tracks stay), anywhere
## else a new object with it at its saved size, in another piece too.

const Assets := preload("res://tests/test_studio_assets.gd")


static func _piece(tc: TestCase, root: String, folder: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(root.path_join(folder))
	Assets._write(root.path_join(folder).path_join("clip.mp4"), "not really a video")
	var r := EditModel.new_piece(root.path_join(folder).path_join("clip.mp4"))
	tc.assert_ok(r)
	var m: EditModel = r.get("model")
	var edits := StudioConfigEdits.new()
	edits.model = m
	var drop := StudioAssetDrop.new()
	drop.model = m
	drop.edits = edits
	return {"model": m, "edits": edits, "drop": drop}


const HEAD := Vector3(0, 1.7, 4)
const FLOOR := {"point": Vector3(0, 0, 0), "on": "", "floor": true}


static func _on(id: String) -> Dictionary:
	return {"point": Vector3.ZERO, "on": id, "floor": false}


## A screen with a user effect (bundled into the piece), a built-in one
## switched off with a kept track, a dome surface, a ripple and a tint.
static func _styled_screen(tc: TestCase, root: String) -> Dictionary:
	var p := _piece(tc, root, "piece")
	var m: EditModel = p.model
	var lib := Assets._library(root)
	tc.assert_true(p.drop.drop(Assets._asset(lib, "object", "Screen"), FLOOR, HEAD, 0.0, false).ok)
	tc.assert_true(p.drop.drop(Assets._asset(lib, "effect", "My fx"), _on("main_screen"), HEAD, 0.0, false).ok)
	var glow: Dictionary = VisualizerShaders.builtins(true)[0]
	tc.assert_true(m.add_effect("main_screen", glow.key))
	tc.assert_true(m.set_key(ScriptFormat.TRACK_SHADER_PARAM, "main_screen.effect1", "amount", 2.0, 0.5))
	tc.assert_true(m.set_effect_enabled("main_screen", 1, false), "switched off: its track kept in its entry")
	tc.assert_true(m.set_config("main_screen", "surface", {"shader": "dome", "placement": "fixed", "params": {"arc_x": 90.0}}))
	tc.assert_true(m.set_config("main_screen", "vertex_effects", [{"shader": "ripple", "params": {"amplitude": 0.2}}]))
	tc.assert_true(m.set_config("main_screen", ["modifiers", "tint"], [1.0, 0.5, 0.5]))
	p["glow"] = glow
	p["lib"] = lib
	return p


static func test_saving_a_look(tc: TestCase) -> void:
	var root := Assets._setup()
	var p := _styled_screen(tc, root)
	var m: EditModel = p.model
	tc.assert_true(m.effects_of("main_screen")[1].has("tracks"), "the switched-off effect keeps its track")
	var r := StudioLooks.save(m, "main_screen", "screen", root.path_join("lib"))
	tc.assert_ok(r)
	tc.assert_eq(r.label, "Screen: My Fx", "named after its switched-on effects")
	tc.assert_eq(r.path, root.path_join("lib/looks/screen_my_fx.json"))
	var raw = JSON.parse_string(FileAccess.get_file_as_string(r.path))
	tc.assert_eq(raw.kind, "screen")
	tc.assert_eq(raw.prefab, "res://player/prefabs/screen.tscn")
	tc.assert_eq(raw.scale, [0.12, 0.12, 0.12])
	var fx_key := String(raw.config.effects[0].shader)
	tc.assert_eq(raw.shaders.get(fx_key), "shaders/my_fx.gdshader", "the piece's copy named in the library (the same file there: reused)")
	tc.assert_eq(raw.shaders.get(String(raw.config.effects[1].shader)), p.glow.key, "the player's own as it is")
	tc.assert_eq(raw.shaders.size(), 2, "built-in names (dome, ripple) aren't files")
	tc.assert_false(raw.config.effects[1].has("tracks"), "no animation in a look")
	tc.assert_eq(raw.config.surface.shader, "dome")
	tc.assert_eq(raw.config.modifiers.tint, [1.0, 0.5, 0.5])
	tc.assert_true(m.effects_of("main_screen")[1].has("tracks"), "the piece is untouched")
	# Read back: files as absolute paths.
	var look := StudioLooks.read(r.path)
	tc.assert_eq(look.shaders[fx_key], root.path_join("lib/shaders/my_fx.gdshader"))
	tc.assert_eq(look.label, "Screen: My Fx")
	tc.assert_eq(StudioLooks.read(root.path_join("lib/shaders/my_fx.gdshader")), {}, "not a look")
	# Saved again: a second file; the shelf lists both.
	tc.assert_eq(StudioLooks.save(m, "main_screen", "screen", root.path_join("lib")).path, root.path_join("lib/looks/screen_my_fx_2.json"))
	var lib: StudioAssetLibrary = p.lib
	var looks := lib.of_type("look")
	tc.assert_eq(looks.map(func(a): return [a.label, a.kind, a.source]), [["Screen: My Fx", "screen", "user"], ["Screen: My Fx", "screen", "user"]])
	tc.assert_eq(looks[0].scale, 0.12)
	# Labels for the other kinds.
	tc.assert_eq(StudioLooks.label_for("layer", {"shader": "tunnel"}, {"tunnel": "res://x/tunnel.gdshader"}), "Layer: Tunnel")
	tc.assert_eq(StudioLooks.label_for("object", {}, {}, "res://player/prefabs/cube.tscn"), "Cube")
	tc.assert_eq(StudioLooks.file_name_for("Screen: Glow + Mirror"), "screen_glow_mirror")
	tc.assert_true(StudioLooks.save(m, "nothing", "screen", root.path_join("lib")).ok == false, "an object that isn't there")


static func test_putting_a_look_on_objects(tc: TestCase) -> void:
	var root := Assets._setup()
	var styled := _styled_screen(tc, root)
	var saved := StudioLooks.save(styled.model, "main_screen", "screen", root.path_join("lib"))
	tc.assert_ok(saved)
	# Another piece, somewhere else: a plain screen with an effect of its
	# own (keyed), moving, and a cube.
	var p := _piece(tc, root, "other")
	var m: EditModel = p.model
	var lib := Assets._library(root)
	lib.piece_dir = root.path_join("other")
	var card := Assets._asset(lib, "look", "Screen: My Fx")
	tc.assert_false(card.is_empty(), "on the shelf")
	tc.assert_true(p.drop.drop(Assets._asset(lib, "object", "Screen"), FLOOR, HEAD, 0.0, false).ok)
	tc.assert_true(m.add_effect("main_screen", styled.glow.key))
	tc.assert_true(m.set_key(ScriptFormat.TRACK_SHADER_PARAM, "main_screen.effect0", "amount", 1.0, 0.3))
	tc.assert_true(m.set_key(ScriptFormat.TRACK_TRANSFORM, "main_screen", "position", 1.0, [0.0, 1.7, -2.0]))
	tc.assert_true(p.drop.drop(Assets._asset(lib, "object", "Cube"), {"point": Vector3(3, 0, 0), "on": "", "floor": true}, HEAD, 0.0, false).ok)
	var before := m.to_text()
	var xf_before = m.tracks()[m.spawn_index("main_screen")].transform.duplicate(true)
	# On a screen: it takes the setup.
	var r: Dictionary = p.drop.drop(card, _on("main_screen"), HEAD, 0.0, false)
	tc.assert_eq([r.ok, r.id], [true, "main_screen"])
	var cfg := m.config_of("main_screen")
	var shaders: Dictionary = m.document().shaders
	tc.assert_eq(shaders.get(cfg.effects[0].shader), "shaders/my_fx.gdshader", "the look's shader copied into this piece")
	tc.assert_true(FileAccess.file_exists(root.path_join("other/shaders/my_fx.gdshader")))
	tc.assert_eq(shaders.get(cfg.effects[1].shader), styled.glow.key)
	tc.assert_false(cfg.effects[1].get("enabled", true), "switched off, as saved")
	tc.assert_eq([cfg.surface.shader, cfg.vertex_effects[0].shader, cfg.modifiers.tint], ["dome", "ripple", [1.0, 0.5, 0.5]])
	tc.assert_eq(m.tracks()[m.spawn_index("main_screen")].transform, xf_before, "it keeps its place and size")
	tc.assert_eq(m.find_track(ScriptFormat.TRACK_SHADER_PARAM, "main_screen.effect0", "amount"), -1, "its old effect's track went with it")
	tc.assert_true(m.find_track(ScriptFormat.TRACK_TRANSFORM, "main_screen", "position") >= 0, "its movement stays")
	tc.assert_true(m.undo().begins_with("Put the look Screen: My Fx on main_screen"), "one undo step")
	tc.assert_eq(m.to_text(), before, "undo puts it all back (the shaders' names too)")
	m.redo()
	tc.assert_eq(m.config_of("main_screen"), cfg)
	tc.assert_false(p.drop.drop(card, _on("main_screen"), HEAD, 0.0, false).ok, "already has it")
	# On the cube (not a screen), and on the floor: new screens with it.
	r = p.drop.drop(card, _on("cube"), HEAD, 2.0, false)
	tc.assert_eq([r.ok, r.id], [true, "screen"])
	r = p.drop.drop(card, FLOOR, HEAD, 2.0, false)
	tc.assert_eq([r.ok, r.id], [true, "screen_2"])
	var ev: Dictionary = m.tracks()[m.spawn_index("screen_2")]
	tc.assert_eq([ev.t, ev.prefab, ev.transform.scale, ev.transform.position], [2.0, "screen", [0.12, 0.12, 0.12], [0.0, 1.7, 0.0]])
	tc.assert_eq(m.config_of("screen_2"), cfg, "the same setup, named the same way")
	tc.assert_eq(m.undo(), "Add Screen: My Fx", "one undo step")
	m.redo()
	# It saves, and the player takes it.
	tc.assert_ok(m.save())
	tc.assert_ok(ScriptFormat.load_from_file(m.path))
	# A look that can't be read.
	Assets._write(root.path_join("lib/looks/broken.json"), "{\"look\": 1}")
	tc.assert_eq(lib.of_type("look").size(), 1, "a file that isn't a look isn't on the shelf")
	var bad := {"id": "look:x", "type": "look", "kind": "screen", "label": "Broken", "path": root.path_join("lib/looks/broken.json"), "source": "user", "scale": 1.0}
	tc.assert_false(p.drop.drop(bad, FLOOR, HEAD, 0.0, false).ok)


static func test_replace_config(tc: TestCase) -> void:
	var r := EditModel.from_text(JSON.stringify({"format_version": 2, "media": {"video": "v.mp4"}, "prefabs": {"screen": "res://player/prefabs/screen.tscn"},
		"shaders": {"a": "shaders/a.gdshader", "b": "shaders/b.gdshader"},
		"tracks": [
			{"type": "event", "t": 0.0, "action": "spawn", "id": "s", "prefab": "screen", "config": {"effects": [{"shader": "a"}]}},
			{"type": "event", "t": 5.0, "action": "despawn", "target": "s"},
			{"type": "event", "t": 8.0, "action": "spawn", "id": "s", "prefab": "screen", "config": {"effects": [{"shader": "a"}]}},
			{"type": "shader_param", "target": "s.effect0", "param": "x", "keyframes": [{"t": 0.0, "value": 1.0}]},
			{"type": "shader_param", "target": "s.modifiers", "param": "opacity", "keyframes": [{"t": 0.0, "value": 1.0}]},
		]}))
	tc.assert_ok(r)
	var m: EditModel = r.model
	tc.assert_true(m.replace_config("s", {"effects": [{"shader": "a", "params": {"x": 2.0}}], "opacity": 0.5}))
	tc.assert_eq(m.tracks()[0].config, {"effects": [{"shader": "a", "params": {"x": 2.0}}], "opacity": 0.5})
	tc.assert_eq(m.tracks()[2].config, m.tracks()[0].config, "every spawn with the same config")
	tc.assert_true(m.find_track("shader_param", "s.effect0", "x") >= 0, "the same effects: their tracks stay")
	tc.assert_true(m.replace_config("s", {"effects": [{"shader": "b"}]}))
	tc.assert_eq(m.find_track("shader_param", "s.effect0", "x"), -1, "other effects: their tracks go")
	tc.assert_true(m.find_track("shader_param", "s.modifiers", "opacity") >= 0, "other tracks stay")
	tc.assert_true(m.replace_config("s", {}))
	tc.assert_false(m.tracks()[0].has("config"), "{} removes it")
	tc.assert_false(m.replace_config("s", {}), "nothing changes")
	tc.assert_false(m.replace_config("nobody", {"opacity": 1.0}))
