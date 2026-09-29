extends RefCounted

## Studio's asset shelf (M5): a new piece for a plain video
## (EditModel.new_piece), what the library offers (StudioAssetLibrary),
## bundling user assets into the piece (StudioBundle), dropping cards into
## the world (StudioAssetDrop: where they land and what they write), the
## inspector's menus offering user shaders, and lane ends (spawn / despawn
## retiming: StudioTimeline.lanes' ends and span_limits, the model's
## commands).

const TMP_DIR := "user://test_studio_assets_tmp"
const LAYER_GLSL := "void mainImage(out vec4 c, in vec2 f) { c = vec4(f.x / iResolution.x, 0.0, 0.5, 1.0); }\n"
const EFFECT := "shader_type canvas_item;\n#include \"res://player/visualizer/effect_prelude.gdshaderinc\"\n#include \"tint_inc.gdshaderinc\"\n\nuniform float amount : hint_range(0.0, 1.0) = 0.5;\n\nvoid fragment() {\n\tCOLOR = texture(input_tex, UV) * tint(amount);\n}\n"
const EFFECT_INC := "vec4 tint(float a) { return vec4(1.0, 1.0 - a, 1.0 - a, 1.0); }\n"
const CAMERA := "// @camera\nvec3 camera_fx(vec2 uv) { return vec3(uv, 0.0); }\n"
const PREFAB := "[gd_scene load_steps=2 format=3]\n\n[sub_resource type=\"BoxMesh\" id=\"1\"]\nsize = Vector3(2, 4, 2)\n\n[node name=\"Thing\" type=\"MeshInstance3D\"]\nmesh = SubResource(\"1\")\n"
const SCREEN_BOX := AABB(Vector3(-16, -9, 0), Vector3(32, 18, 0))


## A clean folder with a library (lib/: a layer, an effect with an include,
## a camera effect, a prefab), a piece folder with a video (piece/clip.mp4)
## and its own prefab and shader. Returns the absolute folder.
static func _setup() -> String:
	var root := ProjectSettings.globalize_path(TMP_DIR)
	_rm(root)
	for d in ["lib/shaders", "lib/prefabs", "piece/prefabs", "piece/shaders"]:
		DirAccess.make_dir_recursive_absolute(root.path_join(d))
	_write(root.path_join("lib/shaders/my_layer.glsl"), LAYER_GLSL)
	_write(root.path_join("lib/shaders/my_fx.gdshader"), EFFECT)
	_write(root.path_join("lib/shaders/tint_inc.gdshaderinc"), EFFECT_INC)
	_write(root.path_join("lib/shaders/cam.glsl"), CAMERA)
	_write(root.path_join("lib/prefabs/thing.tscn"), PREFAB)
	_write(root.path_join("piece/clip.mp4"), "not really a video")
	_write(root.path_join("piece/prefabs/own.tscn"), PREFAB)
	_write(root.path_join("piece/shaders/own_layer.glsl"), LAYER_GLSL)
	return root


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


static func _library(root: String) -> StudioAssetLibrary:
	var lib := StudioAssetLibrary.new()
	lib.shader_dirs = []  # not the user's real folders
	lib.library_dirs = [root.path_join("lib")]
	lib.piece_dir = root.path_join("piece")
	return lib


static func _asset(lib: StudioAssetLibrary, type: String, label: String) -> Dictionary:
	for a in lib.of_type(type):
		if a.label == label:
			return a
	return {}


static func _new_model(tc: TestCase, root: String) -> EditModel:
	var r := EditModel.new_piece(root.path_join("piece/clip.mp4"))
	tc.assert_ok(r)
	return r.get("model")


static func test_new_piece_for_a_plain_video(tc: TestCase) -> void:
	var root := _setup()
	var m := _new_model(tc, root)
	var path := root.path_join("piece/clip.json")
	tc.assert_eq(m.path, path)
	tc.assert_true(FileAccess.file_exists(path), "written straight away")
	tc.assert_true(ScriptFormat.load_from_file(path).ok, "a valid script")
	var doc := m.document()
	tc.assert_eq(int(doc.format_version), 2)
	tc.assert_eq(doc.media.video, "clip.mp4", "the video named relatively")
	tc.assert_eq(doc.prefabs, EditModel.BUILTIN_PREFABS)
	tc.assert_eq(doc.tracks, [])
	tc.assert_eq(doc.meta.title, "clip")
	tc.assert_false(DefaultScreen.wants_default(m.timeline()), "no default screen: what you add is what there is")
	tc.assert_false(m.is_dirty())
	tc.assert_err(EditModel.new_piece(root.path_join("piece/clip.mp4")), "already there")


static func test_library_lists_assets_by_type(tc: TestCase) -> void:
	var root := _setup()
	var lib := _library(root)
	var objects := lib.of_type("object").map(func(a): return [a.label, a.source])
	tc.assert_eq(objects, [["Screen", "builtin"], ["Cube", "builtin"], ["Thing", "user"], ["Own", "piece"]])
	var layers := lib.of_type("layer")
	tc.assert_eq(layers.slice(0, VisualizerShaders.builtins(false).size()).map(func(a): return a.path),
			VisualizerShaders.builtins(false).map(func(b): return b.key), "built-ins first")
	var extra := layers.slice(VisualizerShaders.builtins(false).size()).map(func(a): return [a.label, a.source])
	tc.assert_eq(extra, [["My layer", "user"], ["Own layer", "piece"]], "a camera effect isn't a layer")
	var effects := lib.of_type("effect").slice(VisualizerShaders.builtins(true).size())
	tc.assert_eq(effects.map(func(a): return [a.label, a.source]), [["My fx", "user"]])
	tc.assert_eq(_asset(lib, "object", "Screen").scale, StudioAssetLibrary.SCREEN_SCALE)
	var ids := {}
	for a in lib.assets():
		tc.assert_false(ids.has(a.id), "ids are unique: %s" % a.id)
		ids[a.id] = true
	# Watching: a new file changes the signature.
	var before := lib.signature()
	tc.assert_eq(lib.signature(), before, "steady while nothing changes")
	_write(root.path_join("lib/shaders/another.glsl"), LAYER_GLSL)
	tc.assert_true(lib.signature() != before, "a new file shows")
	tc.assert_eq(lib.of_type("layer").back().label, "Own layer")
	tc.assert_true(lib.of_type("layer").any(func(a): return a.label == "Another"))


static func test_bundling_copies_user_assets_into_the_piece(tc: TestCase) -> void:
	var root := _setup()
	var piece := root.path_join("piece")
	var b := StudioBundle.bundle(piece, "res://player/visualizer/effects/glow.gdshader")
	tc.assert_eq([b.ok, b.path, b.copied], [true, "res://player/visualizer/effects/glow.gdshader", false], "the player's own stays")
	b = StudioBundle.bundle(piece, piece.path_join("shaders/own_layer.glsl"))
	tc.assert_eq([b.path, b.copied], ["shaders/own_layer.glsl", false], "the piece's own: named relatively")
	b = StudioBundle.bundle(piece, root.path_join("lib/shaders/my_fx.gdshader"))
	tc.assert_eq([b.ok, b.path, b.copied], [true, "shaders/my_fx.gdshader", true])
	tc.assert_eq(FileAccess.get_file_as_string(piece.path_join("shaders/my_fx.gdshader")), EFFECT)
	tc.assert_true(FileAccess.file_exists(piece.path_join("shaders/tint_inc.gdshaderinc")), "its include came along")
	b = StudioBundle.bundle(piece, root.path_join("lib/shaders/my_fx.gdshader"))
	tc.assert_eq([b.path, b.copied], ["shaders/my_fx.gdshader", false], "not copied twice")
	DirAccess.make_dir_recursive_absolute(root.path_join("other"))
	_write(root.path_join("other/my_fx.gdshader"), EFFECT.replace("0.5", "0.7"))
	b = StudioBundle.bundle(piece, root.path_join("other/my_fx.gdshader"))
	tc.assert_eq(b.path, "shaders/my_fx_2.gdshader", "a different file of the same name")
	b = StudioBundle.bundle(piece, root.path_join("lib/prefabs/thing.tscn"))
	tc.assert_eq([b.path, b.copied], ["prefabs/thing.tscn", true])
	tc.assert_eq(FileAccess.get_file_as_string(piece.path_join("prefabs/thing.tscn")), PREFAB, "no outside files: copied as it is")
	tc.assert_false(StudioBundle.bundle(piece, root.path_join("lib/nothing.glsl")).ok)
	tc.assert_eq(StudioBundle.relative_to(piece.path_join("a/b.txt"), piece), "a/b.txt")
	tc.assert_eq(StudioBundle.relative_to(root.path_join("x.txt"), piece), "")


static func test_where_a_card_lands(tc: TestCase) -> void:
	var head := Vector3(0, 1.7, 4)
	var screen_xf := Transform3D(Basis.from_scale(Vector3.ONE * 0.12), Vector3(0, 2, 0))
	var cands := [{"id": "main_screen", "xf": screen_xf, "bounds": SCREEN_BOX}]
	var down := StudioAssetDrop.aim(head, Vector3(0, -1.7, -2).normalized(), [])
	tc.assert_true(down.floor)
	tc.assert_eq(Vector3(down.point).snapped(Vector3.ONE * 0.001), Vector3(0, 0, 2))
	var at_screen := StudioAssetDrop.aim(head, Vector3(0, 0.3, -4).normalized(), cands)
	tc.assert_eq([at_screen.on, at_screen.floor], ["main_screen", false])
	tc.assert_eq(snappedf(at_screen.point.z, 0.001), 0.0, "on its face")
	# Pointed at the screen but down at the floor: the floor under the
	# pointer, beyond it (it used to stick to the screen's face).
	var past := StudioAssetDrop.aim(head, Vector3(0, -0.3, -4).normalized(), cands)
	tc.assert_eq([past.on, past.floor], ["main_screen", true], "still on it, for effects")
	tc.assert_eq(Vector3(past.point).snapped(Vector3.ONE * 0.01), Vector3(0, 0, 4 - 4 * 1.7 / 0.3).snapped(Vector3.ONE * 0.01))
	var too_far := StudioAssetDrop.aim(head, Vector3(0, -0.01, -4).normalized(), cands)
	tc.assert_eq([too_far.floor, snappedf(too_far.point.z, 0.001)], [false, 0.0], "floor beyond reach: its face")
	var up := StudioAssetDrop.aim(head, Vector3(0, 1, -1).normalized(), [])
	tc.assert_eq([up.on, up.floor, snappedf(Vector3(up.point).distance_to(head), 0.001)], ["", false, StudioAssetDrop.AIR_DISTANCE])
	# Screens stand at eye height; cubes sit on the floor; all face you.
	var screen := {"kind": "screen", "scale": 0.12}
	var p := StudioAssetDrop.placement(screen, {"point": Vector3(1, 0, 2), "floor": true}, head, SCREEN_BOX, false)
	tc.assert_eq(p.position, [1.0, 1.7, 2.0])
	tc.assert_eq(snappedf(p.rotation_deg[1], 0.01), snappedf(rad_to_deg(atan2(-1.0, 2.0)), 0.01), "turned to you")
	var cube := {"kind": "cube", "scale": 0.5}
	p = StudioAssetDrop.placement(cube, {"point": Vector3(1, 0, 2), "floor": true}, head, AABB(Vector3.ONE * -0.5, Vector3.ONE), false)
	tc.assert_eq(p.position[1], 0.25, "on the floor")
	p = StudioAssetDrop.placement(cube, {"point": Vector3(1, -3, 2), "floor": false}, head, AABB(Vector3.ONE * -0.5, Vector3.ONE), false)
	tc.assert_eq(p.position[1], 0.25, "never below it")
	p = StudioAssetDrop.placement(cube, {"point": Vector3(1.234, 1.567, 2.01), "floor": false}, head, AABB(Vector3.ONE * -0.5, Vector3.ONE), true)
	tc.assert_eq(p.position.map(func(v): return snappedf(v, 0.001)), [1.2, 1.6, 2.0], "snapped to 10 cm")
	tc.assert_eq(fmod(absf(p.rotation_deg[1]), 15.0), 0.0, "and 15°")


static func test_dropping_cards_adds_and_bundles(tc: TestCase) -> void:
	var root := _setup()
	var lib := _library(root)
	var m := _new_model(tc, root)
	var edits := StudioConfigEdits.new()
	edits.model = m
	var drop := StudioAssetDrop.new()
	drop.model = m
	drop.edits = edits
	var head := Vector3(0, 1.7, 4)
	var floor := {"point": Vector3(0, 0, 0), "on": "", "floor": true}
	var r := drop.drop(_asset(lib, "object", "Screen"), floor, head, 3.25, false)
	tc.assert_eq([r.ok, r.id], [true, "main_screen"], "the first screen is main_screen")
	var ev: Dictionary = m.tracks()[m.spawn_index("main_screen")]
	tc.assert_eq([ev.t, ev.prefab, ev.transform.position, ev.transform.scale], [3.25, "screen", [0.0, 1.7, 0.0], [0.12, 0.12, 0.12]])
	tc.assert_eq(drop.drop(_asset(lib, "object", "Screen"), floor, head, 0.0, false).id, "screen", "then screen, screen_2, ...")
	tc.assert_eq(m.undo(), "Add Screen", "one undo step")
	tc.assert_eq(m.object_ids(), ["main_screen"])
	# What a card does where it points (the carried preview shows it).
	var on_screen := {"point": Vector3.ZERO, "on": "main_screen", "floor": false}
	tc.assert_eq([drop.adds(_asset(lib, "object", "Screen"), on_screen), drop.adds(_asset(lib, "effect", "My fx"), on_screen),
			drop.adds(_asset(lib, "layer", "My layer"), on_screen), drop.adds(_asset(lib, "effect", "My fx"), floor)],
			[true, false, true, false])
	tc.assert_eq(drop.bounds_for(_asset(lib, "object", "Screen")), StudioAssetDrop.BUILTIN_BOUNDS["res://player/prefabs/screen.tscn"])
	# A user layer shader: bundled, named, a layer spawned with it.
	r = drop.drop(_asset(lib, "layer", "My layer"), floor, head, 0.0, false)
	tc.assert_eq([r.ok, r.id], [true, "my_layer"])
	var cfg := m.config_of("my_layer")
	tc.assert_eq(m.document().shaders.get(cfg.get("shader", "")), "shaders/my_layer.glsl")
	tc.assert_true(FileAccess.file_exists(root.path_join("piece/shaders/my_layer.glsl")), "copied into the piece")
	tc.assert_eq(m.tracks()[m.spawn_index("my_layer")].prefab, "layer")
	tc.assert_eq(edits.kind_for("my_layer"), "layer")
	tc.assert_false(drop.adds(_asset(lib, "layer", "Own layer"), {"point": Vector3.ZERO, "on": "my_layer", "floor": false}), "a layer on a layer")
	var cards := lib.of_type("layer").filter(func(a): return a.label == "My layer")
	tc.assert_eq(cards.map(func(a): return [a.source, a.in_piece]), [["user", true]], "one card for it and its copy")
	# A layer card on a layer: its shader changes instead.
	r = drop.drop(_asset(lib, "layer", "Own layer"), {"point": Vector3.ZERO, "on": "my_layer", "floor": false}, head, 0.0, false)
	tc.assert_eq([r.ok, m.object_ids().size()], [true, 2])
	tc.assert_eq(m.document().shaders.get(m.config_of("my_layer").shader), "shaders/own_layer.glsl", "the piece's own: no copy")
	# Effects go on screens and layers only.
	var fx := _asset(lib, "effect", "My fx")
	tc.assert_false(drop.drop(fx, floor, head, 0.0, false).ok, "not on the floor")
	r = drop.drop(fx, {"point": Vector3.ZERO, "on": "main_screen", "floor": false}, head, 0.0, false)
	tc.assert_eq([r.ok, r.id], [true, "main_screen"])
	var effects := m.effects_of("main_screen")
	tc.assert_eq(m.document().shaders.get(effects.back().shader), "shaders/my_fx.gdshader")
	# A user prefab: named after its file, placed on the floor by its box.
	r = drop.drop(_asset(lib, "object", "Thing"), {"point": Vector3(2, 0, 0), "on": "", "floor": true}, head, 0.0, false)
	tc.assert_eq([r.ok, m.document().prefabs.get("thing")], [true, "prefabs/thing.tscn"])
	tc.assert_eq(m.tracks()[m.spawn_index("thing")].transform.position[1], 2.0, "its 4 m box stands on the floor")
	tc.assert_true(m.save().ok, "saves valid")
	tc.assert_true(ScriptFormat.load_from_file(m.path).ok)
	# The inspector's menus offer the user's shaders too, bundled when picked.
	edits.library = lib
	tc.assert_true(edits.effect_options().any(func(o): return o.label == "My fx (yours)" or o.label == "My Fx"), "listed")
	_write(root.path_join("lib/shaders/second_fx.gdshader"), EFFECT.replace("0.5", "0.2"))
	var opt: Array = edits.effect_options().filter(func(o): return o.label == "Second fx (yours)")
	tc.assert_eq(opt.size(), 1)
	tc.assert_true(edits.add_effect("main_screen", opt[0].key))
	tc.assert_eq(m.document().shaders.get(m.effects_of("main_screen").back().shader), "shaders/second_fx.gdshader")


static func test_lane_ends_retime_spawns_and_despawns(tc: TestCase) -> void:
	var doc := {
		"format_version": 2, "media": {"video": "clip.mp4"},
		"prefabs": EditModel.BUILTIN_PREFABS,
		"tracks": [
			{"type": "event", "t": 2, "action": "spawn", "id": "rig", "prefab": "group"},
			{"type": "event", "t": 2, "action": "spawn", "id": "scr", "prefab": "screen", "parent": "rig"},
			{"type": "event", "t": 5, "action": "spawn", "id": "late", "prefab": "cube", "parent": "rig"},
			{"type": "event", "t": 20, "action": "despawn", "target": "rig"},
			{"type": "event", "t": 8, "action": "spawn", "id": "cube", "prefab": "cube"},
		],
	}
	var r := EditModel.from_text(JSON.stringify(doc), "")
	tc.assert_ok(r)
	var m: EditModel = r.get("model")
	var lanes := StudioTimeline.lanes(m, 60.0)
	tc.assert_eq(lanes[0].ends, [{"spawn": 0, "despawn": 3}], "rig: its own despawn")
	tc.assert_eq(lanes[1].ends, [{"spawn": 1, "despawn": -1}], "scr: ended by its parent")
	tc.assert_eq(lanes[3].ends, [{"spawn": 4, "despawn": -1}], "cube: to the end")
	tc.assert_eq(StudioTimeline.span_limits(lanes, lanes[2], 0, 60.0), [2.0, 20.0], "inside its parent's time")
	tc.assert_eq(StudioTimeline.span_limits(lanes, lanes[3], 0, 60.0), [0.0, 60.0])
	# The group comes on later: its child that came with it follows, the later one doesn't.
	tc.assert_true(m.set_spawn_time(0, 4.0))
	tc.assert_eq([m.tracks()[0].t, m.tracks()[1].t, m.tracks()[2].t], [4.0, 4.0, 5.0])
	tc.assert_eq(m.undo_label(), "rig comes on at 0:04.00")
	tc.assert_true(m.set_despawn_time(3, 30.0))
	tc.assert_eq(m.tracks()[3].t, 30.0)
	tc.assert_true(m.add_despawn("cube", 12.0))
	lanes = StudioTimeline.lanes(m, 60.0)
	tc.assert_eq(lanes[3].spans, [[8.0, 12.0]])
	tc.assert_true(m.remove_despawn(lanes[3].ends[0].despawn))
	tc.assert_eq(StudioTimeline.lanes(m, 60.0)[3].spans, [[8.0, 60.0]], "stays on to the end")
	tc.assert_false(m.set_spawn_time(3, 1.0), "not a spawn")
	tc.assert_false(m.set_despawn_time(0, 1.0), "not a despawn")
	for i in 4:
		m.undo()
	tc.assert_eq([m.tracks()[0].t, m.tracks()[1].t, m.tracks()[3].t, m.tracks().size()], [2.0, 2.0, 20.0, 5], "all undone")


const WOBBLE := """// @title Wobble
// @hint Sways the picture.
uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.2;

vec3 deform(vec3 p, vec2 uv, vec2 half_m) {
	return p + vec3(0.0, 0.0, sin(p.x + TIME) * amount);
}
"""


static func test_vertex_tab_lists_and_drops_vertex_effects(tc: TestCase) -> void:
	var root := _setup()
	DirAccess.make_dir_recursive_absolute(root.path_join("lib/shaders/vertex"))
	_write(root.path_join("lib/shaders/vertex/wobble.gdshaderinc"), WOBBLE)
	var lib := _library(root)
	var cards := lib.of_type("vertex")
	var builtins := ScreenGeometry.builtins(ScreenGeometry.VERTEX_DIR)
	tc.assert_eq(cards.slice(0, builtins.size()).map(func(a): return a.label), builtins.map(func(b): return b.label), "built-ins first")
	tc.assert_true(cards.any(func(a): return a.label == "Spin") and cards.any(func(a): return a.label == "Pulse"), "Spin and Pulse are there")
	tc.assert_eq(cards.slice(builtins.size()).map(func(a): return [a.label, a.source]), [["Wobble", "user"]])
	tc.assert_true(StudioAssetLibrary.TYPES.has("vertex") and StudioAssetLibrary.TYPE_LABELS.vertex == "Vertex", "a tab")
	var m := _new_model(tc, root)
	var edits := StudioConfigEdits.new()
	edits.model = m
	edits.library = lib
	var drop := StudioAssetDrop.new()
	drop.model = m
	drop.edits = edits
	var head := Vector3(0, 1.7, 4)
	drop.drop(_asset(lib, "object", "Screen"), {"point": Vector3.ZERO, "on": "", "floor": true}, head, 0.0, false)
	var on_screen := {"point": Vector3.ZERO, "on": "main_screen", "floor": false}
	var spin := _asset(lib, "vertex", "Spin")
	tc.assert_false(drop.drop(spin, {"point": Vector3.ZERO, "on": "", "floor": true}, head, 0.0, false).ok, "not on the floor")
	var r := drop.drop(spin, on_screen, head, 0.0, false)
	tc.assert_eq([r.ok, r.id], [true, "main_screen"])
	tc.assert_eq(m.effects_of("main_screen", EditModel.VERTEX_EFFECTS).map(func(e): return e.shader), ["spin"], "a built-in goes by name")
	tc.assert_eq(m.effects_of("main_screen"), [], "not a pixel effect")
	tc.assert_eq(m.undo_label(), "Add spin to main_screen", "one undo step")
	r = drop.drop(_asset(lib, "vertex", "Wobble"), on_screen, head, 0.0, false)
	tc.assert_true(r.ok)
	tc.assert_true(FileAccess.file_exists(root.path_join("piece/shaders/vertex/wobble.gdshaderinc")), "copied into shaders/vertex/")
	tc.assert_eq(m.effects_of("main_screen", EditModel.VERTEX_EFFECTS).size(), 2)
	tc.assert_eq(lib.of_type("vertex").filter(func(a): return a.label == "Wobble").map(func(a): return [a.source, a.in_piece]),
			[["user", true]], "one card for it and its copy")
	tc.assert_true(edits.effect_options(EditModel.VERTEX_EFFECTS).any(func(o): return o.label == "Wobble"), "the inspector's menu lists it")
	tc.assert_true(m.save().ok, "saves valid")
	tc.assert_true(ScriptFormat.load_from_file(m.path).ok)


## Card loops (TODO 18): only layers and effects get one; a preview copy's
## TIME reads its own uniform, not the stage's; a strip's frames; stills
## told from loops that move. Drawing them needs a renderer (see
## checks/shot_studio_loops.gd).
static func test_card_loops(tc: TestCase) -> void:
	var code := StudioThumbnailer.preview_code("shader_type canvas_item;\n#include \"%s\"\nvoid fragment() { COLOR.r = TIME; }\n" % VisualizerShaders.MEDIA_TIME)
	var lines := code.split("\n")
	tc.assert_eq(lines.slice(0, 4), PackedStringArray(["shader_type canvas_item;", "#define VJ_MEDIA_TIME",
			"uniform float vj_preview_time;", "#define TIME vj_preview_time"]), "before the media time include, which then does nothing")
	tc.assert_eq(StudioThumbnailer.preview_code("no shader type"), "no shader type")
	var thumbs := StudioThumbnailer.new()
	tc.assert_eq(thumbs.loop({"id": "x", "type": "object", "path": "res://player/prefabs/cube.tscn"}), null, "objects have none")
	thumbs.free()
	var strip := ImageTexture.create_from_image(Image.create(StudioThumbnailer.SIZE.x * 20, StudioThumbnailer.SIZE.y, false, Image.FORMAT_RGB8))
	tc.assert_eq(StudioThumbnailer.frames_of(strip), 20)
	tc.assert_eq(StudioThumbnailer.frames_of(null), 0)
	var a := Image.create(64, 40, false, Image.FORMAT_RGB8)
	a.fill(Color(0.5, 0.5, 0.5))
	var b := a.duplicate() as Image
	tc.assert_true(StudioThumbnailer.difference(a, b) == 0.0)
	b.set_pixel(2, 2, Color(0.5, 0.5, 0.504))
	tc.assert_true(StudioThumbnailer.difference(a, b) < StudioThumbnailer.STILL_DIFFERENCE, "a rounding speck is a still")
	b.fill_rect(Rect2i(0, 0, 32, 40), Color(0.2, 0.6, 0.9))
	tc.assert_true(StudioThumbnailer.difference(a, b) > StudioThumbnailer.STILL_DIFFERENCE, "half the picture changed moves")
	tc.assert_true(StudioThumbnailer.loop_path({"type": "layer", "path": "res://a.glsl"}) !=
			StudioThumbnailer.cache_path({"type": "layer", "path": "res://a.glsl"}), "kept beside the still")
