extends RefCounted

## Visualizer plane: settings/preset round trip, shader discovery and the
## Shadertoy wrapper, and the analyzer's texture layout.

const TEST_DIR := "user://test_visualizer_tmp"


static func _wipe() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(TEST_DIR)


static func _fresh_dir() -> String:
	_wipe()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	return ProjectSettings.globalize_path(TEST_DIR)


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


static func test_layer_round_trip(t: TestCase) -> void:
	var s := LayerSettings.new()
	s.distance = 1.5
	s.shader = "res://x.gdshader"
	s.set_param("speed", 2.0)
	s.add_effect(VisualizerShaders.KEY_BLACK)
	var copy := LayerSettings.new()
	copy.from_dict(s.to_dict())
	t.assert_eq(copy.shader, "res://x.gdshader")
	t.assert_eq(copy.distance, 1.5)
	t.assert_eq(copy.params.get("speed"), 2.0)
	t.assert_false(copy.lock_to_screen)
	t.assert_eq(copy.effects.size(), 1)
	copy.shader = "res://y.gdshader"
	t.assert_true(copy.params.is_empty(), "a new shader starts from its defaults")
	copy.from_dict({})
	t.assert_eq(copy.shader, "", "missing shader = blank")


static func test_video_blur_layer_becomes_video_with_blur(t: TestCase) -> void:
	var s := LayerSettings.new()
	s.from_dict({
		"shader": VisualizerShaders.LEGACY_VIDEO_BLUR,
		"params": {"radius": 0.025, "brightness": 1.0},
		"resolution": 2.0,
		"effects": [{"shader": VisualizerShaders.OVAL_MASK, "params": {"size": 0.8}}],
	})
	t.assert_eq(s.shader, VisualizerShaders.VIDEO)
	t.assert_true(s.params.is_empty(), "the old shader's params don't carry over")
	t.assert_eq(s.effects.size(), 2)
	t.assert_eq(s.effects[0].shader, VisualizerShaders.BLUR, "blur comes first")
	t.assert_eq(s.effects[0].params.get("radius"), 0.025)
	t.assert_eq(s.effects[1].shader, VisualizerShaders.OVAL_MASK, "its effects follow")
	t.assert_eq(s.resolution, 0.5, "270 px of 1080 at the old resolution")
	var other := {"shader": "res://x.gdshader", "resolution": 2.0}
	t.assert_eq(LayerSettings.migrate_video_blur(other), other, "other layers stay")


static func test_stack_count(t: TestCase) -> void:
	var stack := LayerStack.new()
	var fired := [0]
	stack.layers_changed.connect(func(): fired[0] += 1)
	t.assert_eq(stack.count(), 0, "starts empty")
	stack.set_count(3)
	var first := stack.layers[0]
	stack.set_count(2)
	t.assert_eq(stack.count(), 2)
	t.assert_true(stack.layers[0] == first, "shrinking keeps the rest")
	stack.set_count(99)
	t.assert_eq(stack.count(), LayerStack.MAX_LAYERS)
	stack.set_count(LayerStack.MAX_LAYERS)
	t.assert_eq(fired[0], 3, "no signal without a change")


static func test_preset_stores_layers(t: TestCase) -> void:
	_wipe()
	var store := PresetStore.new(TEST_DIR)
	var stack := LayerStack.new()
	stack.set_count(2)
	stack.layers[0].shader = "res://a.gdshader"
	stack.layers[1].height = 0.4
	store.save_preset(2, "Layers", ScreenSettings.new().to_dict(), stack.to_array())
	var loaded := LayerStack.new()
	t.assert_true(store.apply(2, ScreenSettings.new(), loaded))
	t.assert_eq(loaded.count(), 2)
	t.assert_eq(loaded.layers[0].shader, "res://a.gdshader")
	t.assert_eq(loaded.layers[1].height, 0.4)
	store.save_preset(3, "None", ScreenSettings.new().to_dict())
	t.assert_false(store.load_preset(3).has("layers"), "no empty list written")
	t.assert_true(store.apply(3, ScreenSettings.new(), loaded))
	t.assert_eq(loaded.count(), 0)
	_wipe()


static func test_legacy_presets_become_layers(t: TestCase) -> void:
	var old := PresetStore.layers_of({"visualizer": {"shader": "res://v.gdshader", "size": 2.0}})
	t.assert_eq(old.size(), 1)
	var l := LayerSettings.new()
	l.from_dict(old[0])
	t.assert_eq(l.shader, "res://v.gdshader")
	t.assert_eq(l.size, 2.0)
	t.assert_eq(l.distance, 0.0, "a foreground keeps its place")
	t.assert_eq(l.effects.size(), 1, "the old plane was keyed")
	t.assert_eq(l.effects[0].shader, VisualizerShaders.KEY_BLACK)
	var two := PresetStore.layers_of({
		"background": {"shader": "res://b.gdshader", "key_black": false,
				"mask": {"enabled": true}},
		"foreground": {"shader": "res://f.gdshader", "key_black": true},
		"visualizer": {"shader": "res://ignored.gdshader"},
	})
	t.assert_eq(two.size(), 2)
	var b := LayerSettings.new()
	b.from_dict(two[0])
	t.assert_eq(b.distance, LayerSettings.LEGACY_BEHIND, "background pushed behind the video")
	t.assert_eq(b.effects.size(), 1)
	t.assert_eq(b.effects[0].shader, VisualizerShaders.OVAL_MASK)
	var f := LayerSettings.new()
	f.from_dict(two[1])
	t.assert_eq(f.effects[0].shader, VisualizerShaders.KEY_BLACK)
	t.assert_eq(PresetStore.layers_of({"foreground": {"shader": ""}}).size(), 0, "off layers dropped")


static func test_parse_hints(t: TestCase) -> void:
	var h := VisualizerShaders.parse_hints("""shader_type canvas_item;
// @resolution 1024x1024
uniform float speed : hint_range(0.0, 4.0, 0.5) = 1.0;
uniform int count : hint_range(1, 32) = 1.0 * 8;
uniform bool mirror = true;
uniform float plain = 0.3;
uniform vec3 tint : source_color = vec3(1.0);
uniform sampler2D iChannel0;
""")
	t.assert_eq(h.resolution, Vector2i(1024, 1024))
	t.assert_eq(h.params.size(), 3, "range floats/ints and bools only")
	t.assert_eq(h.params[0].name, "speed")
	t.assert_eq(h.params[0].max, 4.0)
	t.assert_eq(h.params[0].step, 0.5)
	t.assert_eq(h.params[0].default, 1.0)
	t.assert_eq(h.params[1].type, "int")
	t.assert_eq(h.params[1].step, 1.0, "ints step by 1")
	t.assert_eq(h.params[1].default, 8.0, "defaults are evaluated")
	t.assert_eq(h.params[2].default, true)
	t.assert_eq(VisualizerShaders.parse_hints("").resolution, Vector2i.ZERO, "no hint")
	t.assert_eq(h.params[0].group, "", "no group_uniforms")


static func test_reach_follows_params(t: TestCase) -> void:
	var a := 2.0
	t.assert_eq(VisualizerShaders.reach_of(VisualizerShaders.BLUR, {"radius": 0.2}, a), Vector2(0.2, 0.2))
	t.assert_eq(VisualizerShaders.reach_of(VisualizerShaders.EDGE_BLUR, {"inward": true, "radius": 0.2}, a),
			Vector2.ZERO, "inward stays inside")
	t.assert_eq(VisualizerShaders.reach_of(VisualizerShaders.EDGE_BLUR, {"inward": false, "radius": 0.2}, a),
			Vector2(0.1, 0.1), "outward: half the width")
	t.assert_true(VisualizerShaders.reach_of(VisualizerShaders.GLOW, {"radius": 0.5, "soften": 0.0}, a)
			.is_equal_approx(Vector2(1.0, 0.5)), "glow: fractions of the picture per axis")
	t.assert_eq(VisualizerShaders.reach_of(VisualizerShaders.GLOW, {"intensity": 0.0}, a), Vector2.ZERO, "no halo")
	t.assert_eq(VisualizerShaders.reach_of(VisualizerShaders.KEY_BLACK, {}, a), Vector2.ZERO, "none declared")
	t.assert_false(VisualizerShaders.has_reach(VisualizerShaders.KEY_BLACK))
	t.assert_eq(VisualizerShaders.reach_of(VisualizerShaders.BLUR, {"radius": 100.0}, a),
			Vector2.ONE * VisualizerShaders.MAX_REACH, "capped")


static func test_expression_hints(t: TestCase) -> void:
	var fast := VisualizerShaders.BLUR
	var soft := VisualizerShaders.GLOW
	t.assert_eq(VisualizerShaders.passes_of(fast, {}), 6, "default radius")
	t.assert_eq(VisualizerShaders.passes_of(fast, {"radius": 0.0}), 1, "follows the params")
	t.assert_eq(VisualizerShaders.passes_of(soft, {"soften": 0.04}, true), 7, "prepass steps")
	t.assert_eq(VisualizerShaders.passes_of(soft, {"soften": 0.0}, true), 1)
	t.assert_eq(VisualizerShaders.passes_of(soft, {"soften": 0.04}), 1, "no @passes: one")
	t.assert_eq(VisualizerShaders.passes_of(VisualizerShaders.KEY_BLACK, {}), 1)
	t.assert_true(VisualizerShaders.eval_hint(VisualizerShaders.KEY_BLACK, "reach", {}) == null, "none declared")
	var h := VisualizerShaders.parse_hints("// @passes max(2, n)\n// @passes 9\n// @reach 0.1\nuniform int n : hint_range(1, 8) = 3;\n")
	t.assert_eq(h.expressions, {"passes": "max(2, n)", "reach": "0.1"}, "the first of each")


static func test_screen_rebuilds_when_pass_count_changes(t: TestCase) -> void:
	var screen: Screen = load("res://player/prefabs/screen.tscn").instantiate()
	screen.notification(Node.NOTIFICATION_READY)
	screen.set_source_texture(ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8)))
	screen.set_effects([{"shader": VisualizerShaders.BLUR}])
	var steps := func() -> Array: return screen._passes.filter(func(p): return p.effect == 0).map(func(p): return p.step)
	t.assert_eq(steps.call(), [0, 1, 2, 3, 4, 5])
	var blur_passes: Array = screen._passes.filter(func(p): return p.effect == 0)
	var ratio := Vector2((blur_passes[-1].viewport as SubViewport).size) / Vector2((blur_passes[0].viewport as SubViewport).size)
	t.assert_true(ratio.is_equal_approx(Vector2(2, 2)) or (ratio - Vector2(2, 2)).length() < 0.01,
			"all but the last at pass_scale (0.5)")
	screen.set_effect_param(0, "radius", 0.0)
	t.assert_eq(steps.call(), [-1], "one ordinary pass at radius 0 (the shader's defaults: pass 0 of 1)")
	screen.set_effect_param(0, "radius", 0.2)
	t.assert_eq(steps.call().size(), 6, "back to six")
	screen.free()


static func test_legacy_padding_dropped(t: TestCase) -> void:
	var s := ScreenSettings.new()
	s.from_dict({"effects": [{"shader": VisualizerShaders.LEGACY_PADDING, "params": {"amount": 1.0}},
			{"shader": VisualizerShaders.GLOW}]})
	t.assert_eq(s.effects.map(func(e): return e.shader), [VisualizerShaders.GLOW])
	t.assert_true(VisualizerShaders.load_shader(VisualizerShaders.LEGACY_PADDING) == null, "scripts' old key: skipped")


static func test_parse_hints_groups(t: TestCase) -> void:
	var h := VisualizerShaders.parse_hints("""
uniform bool a = false;
group_uniforms halo;
uniform bool b = false;
group_uniforms halo.edge;
uniform bool c = false;
group_uniforms;
uniform bool d = false;
""")
	t.assert_eq(h.params.map(func(p): return p.group), ["", "halo", "halo.edge", ""])


static func test_parse_hints_channels_and_height_only(t: TestCase) -> void:
	var h := VisualizerShaders.parse_hints("""
// @iChannel1 video
// @iChannel2 webcam
// @resolution 270
""")
	t.assert_eq(h.channels, {0: "audio", 1: "video"}, "unknown sources skipped, audio default kept")
	t.assert_eq(h.resolution, Vector2i(0, 270), "height only")
	t.assert_eq(VisualizerShaders.parse_hints("// @iChannel0 video").channels, {0: "video"})
	t.assert_eq(VisualizerShaders.parse_hints("").channels, {0: "audio"})


static func test_builtin_effects(t: TestCase) -> void:
	for b in VisualizerShaders.builtins(true):
		var shader := VisualizerShaders.load_shader(b.key)
		t.assert_true(shader != null, "built-in %s" % b.label)
		t.assert_true(VisualizerShaders.is_effect_code(shader.code), "%s is an effect" % b.label)
	var names: Array = VisualizerShaders.hints_for(VisualizerShaders.OVAL_MASK).params.map(func(p): return p.name)
	t.assert_eq(names, ["outside", "size", "ratio", "blur", "level"])
	names = VisualizerShaders.hints_for(VisualizerShaders.EDGE_BLUR).params.map(func(p): return p.name)
	t.assert_eq(names, ["inward", "radius", "pass_scale"])
	names = VisualizerShaders.hints_for(VisualizerShaders.GLOW).params.map(func(p): return p.name)
	t.assert_eq(names, ["intensity", "radius", "mirror", "diffuse", "repeat",
			"smear", "bloom", "saturation", "blur", "border_blur", "soften", "samples",
			"edge_width", "edge_brighten", "edge_fade", "fade_width", "prepass_scale"])
	t.assert_true(VisualizerShaders.has_prepass(VisualizerShaders.load_shader(VisualizerShaders.GLOW)), "glow has a prepass")
	t.assert_true(not VisualizerShaders.has_prepass(VisualizerShaders.load_shader(VisualizerShaders.EDGE_BLUR)), "edge blur has none")
	names = VisualizerShaders.hints_for(VisualizerShaders.CROP).params.map(func(p): return p.name)
	t.assert_eq(names, ["left", "top", "width", "height"])
	names = VisualizerShaders.hints_for(VisualizerShaders.ROUNDED_CORNERS).params.map(func(p): return p.name)
	t.assert_eq(names, ["roundness", "bulge", "feather"])
	names = VisualizerShaders.hints_for(VisualizerShaders.KEEP_CENTER).params.map(func(p): return p.name)
	t.assert_eq(names, ["zoom", "center", "softness", "horizontal", "vertical"])


static func test_list_options_builtins_then_user_files(t: TestCase) -> void:
	var dir := _fresh_dir()
	_write(dir.path_join("b_ring.glsl"), "// @title Big ring\nvoid mainImage(out vec4 c, in vec2 p) { c = vec4(1.0); }")
	_write(dir.path_join("a_native.gdshader"), "shader_type canvas_item;")
	_write(dir.path_join("notes.md"), "not a shader")
	_write(dir.path_join("c_fx.gdshader"), "shader_type canvas_item;\nuniform sampler2D input_tex;")
	var dirs: Array[String] = [dir, dir.path_join("missing")]
	var opts := VisualizerShaders.list_options(dirs)
	var n := VisualizerShaders.builtins().size()
	t.assert_eq(opts.size(), n + 2, "built-ins + two shaders, .md and the effect skipped")
	t.assert_eq(String(opts[0].key), String(VisualizerShaders.builtins()[0].key))
	t.assert_eq(String(opts[n].label), "A native", "no @title: the file name")
	t.assert_eq(String(opts[n + 1].key), dir.path_join("b_ring.glsl"))
	t.assert_eq(String(opts[n + 1].label), "Big ring", "@title")
	var fx := VisualizerShaders.list_options(dirs, true)
	var m := VisualizerShaders.builtins(true).size()
	t.assert_eq(fx.size(), m + 1, "built-in effects + the user's")
	t.assert_eq(String(fx[m].label), "C fx")
	_wipe()


static func test_override_paths(t: TestCase) -> void:
	var dir := _fresh_dir()
	DirAccess.make_dir_recursive_absolute(dir.path_join("effects"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("sources"))
	_write(dir.path_join("effects/glow.gdshader"), "shader_type canvas_item;")
	_write(dir.path_join("sources/light_ring.gdshader"), "shader_type canvas_item;")
	_write(dir.path_join("effect_prelude.gdshaderinc"), "")
	t.assert_eq(VisualizerShaders.override_path(VisualizerShaders.GLOW, dir), dir.path_join("effects/glow.gdshader"))
	t.assert_eq(VisualizerShaders.override_path("res://player/visualizer/shaders/light_ring.gdshader", dir),
			dir.path_join("sources/light_ring.gdshader"))
	t.assert_eq(VisualizerShaders.override_path(VisualizerShaders.EFFECT_PRELUDE, dir), dir.path_join("effect_prelude.gdshaderinc"))
	t.assert_eq(VisualizerShaders.override_path(VisualizerShaders.CROP, dir), "", "no file, no override")
	t.assert_eq(VisualizerShaders.override_path("res://elsewhere/x.gdshader", dir), "")
	for f in ["effects/glow.gdshader", "sources/light_ring.gdshader", "effect_prelude.gdshaderinc"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir.path_join("effects"))
	DirAccess.remove_absolute(dir.path_join("sources"))
	_wipe()


static func test_relative_includes_are_inlined(t: TestCase) -> void:
	var dir := _fresh_dir()
	_write(dir.path_join("common.gdshaderinc"), "uniform float from_include : hint_range(0.0, 1.0) = 0.5;")
	var path := dir.path_join("fx.gdshader")
	_write(path, "shader_type canvas_item;\n#include \"common.gdshaderinc\"\n#include \"%s\"\n" % VisualizerShaders.EFFECT_PRELUDE)
	var shader := VisualizerShaders.load_shader(path)
	t.assert_true(shader != null, "loaded")
	t.assert_has(shader.code, "uniform float from_include", "relative include pasted in")
	t.assert_has(shader.code, "#include \"%s\"" % VisualizerShaders.EFFECT_PRELUDE, "res:// include left to Godot")
	_wipe()


static func test_prepass_needs_a_declaration(t: TestCase) -> void:
	var s := Shader.new()
	s.code = "shader_type canvas_item;\n// An effect that declares `uniform sampler2D prepass_tex` also gets a\nuniform sampler2D input_tex;\n"
	t.assert_false(VisualizerShaders.has_prepass(s), "a comment (inlined prelude) isn't a declaration")
	s.code += "uniform sampler2D prepass_tex : filter_linear;\n"
	t.assert_true(VisualizerShaders.has_prepass(s))
	t.assert_true(VisualizerShaders.has_prepass(VisualizerShaders.load_shader(VisualizerShaders.GLOW)))
	t.assert_false(VisualizerShaders.has_prepass(VisualizerShaders.load_shader(VisualizerShaders.BLUR)))


static func test_load_shadertoy_file_wraps_code(t: TestCase) -> void:
	var dir := _fresh_dir()
	var path := dir.path_join("x.glsl")
	_write(path, "void mainImage(out vec4 c, in vec2 p) { c = vec4(1.0); }")
	var shader := VisualizerShaders.load_shader(path)
	t.assert_true(shader != null, "loaded")
	t.assert_true(shader.code.begins_with("shader_type canvas_item;"), "shader type first")
	t.assert_has(shader.code, VisualizerShaders.PRELUDE)
	t.assert_has(shader.code, "void mainImage")
	t.assert_true(shader.code.find(VisualizerShaders.MAIN) > shader.code.find("void mainImage"),
			"fragment() comes after mainImage")
	t.assert_true(VisualizerShaders.load_shader(dir.path_join("nope.glsl")) == null, "missing file")
	t.assert_true(VisualizerShaders.load_shader("") == null, "off")
	_wipe()


static func test_builtins_are_found_with_titles(t: TestCase) -> void:
	var labels: Array = VisualizerShaders.builtins().map(func(b): return b.label)
	t.assert_true("Light ring" in labels, "layer title from its @title")
	t.assert_true("Glow" in VisualizerShaders.builtins(true).map(func(b): return b.label), "effect")
	t.assert_false(VisualizerShaders.builtins().any(func(b): return String(b.key).ends_with(".uid")), "only shaders")
	var sorted := labels.duplicate()
	sorted.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(b) < 0)
	t.assert_eq(labels, sorted, "by title")
	t.assert_eq(ScreenGeometry.builtins(ScreenGeometry.SURFACES_DIR).map(func(b): return b.label), ["Dome", "Pillow"])
	t.assert_eq(VisualizerShaders.title_of("// @title  Spaced out  \nshader_type canvas_item;", "x.gdshader"), "Spaced out")
	t.assert_eq(VisualizerShaders.title_of("", "res://a/light_ring.gdshader"), "Light ring")


static func test_builtins_load(t: TestCase) -> void:
	for b in VisualizerShaders.builtins():
		t.assert_true(VisualizerShaders.load_shader(b.key) != null, "built-in %s" % b.label)


static func test_analyzer_texture_layout(t: TestCase) -> void:
	var a := AudioAnalyzer.new()
	var img := a.texture.get_image()
	t.assert_eq(img.get_size(), Vector2i(AudioAnalyzer.BINS, 2))
	t.assert_eq(img.get_pixel(0, 0).r, 0.0, "silent spectrum")
	t.assert_true(absf(img.get_pixel(100, 1).r - 0.5) < 0.01, "silent waveform sits at 0.5")
	t.assert_false(a.attach("no such bus"), "unknown bus")
	a.free()


static func test_margin_step(t: TestCase) -> void:
	var a := 16.0 / 9.0
	var g := Screen.pad(a, Vector2(320, 180), Vector2(0.5, 0.5))
	t.assert_eq(g.h, 2.0, "half a height each side")
	t.assert_eq(g.w, a + 1.0)
	t.assert_eq(Screen.pass_size(g.px), Vector2i(500, 360), "pixels grow with it")
	var wide := Screen.pad(a, Vector2(320, 180), Vector2(1.0, 0.0))
	t.assert_eq([wide.w, wide.h], [a + 2.0, 1.0], "per axis")
	t.assert_eq(Screen.pass_size(Vector2(8192, 2048)), Vector2i(4096, 1024), "capped at 4096")
	t.assert_eq(Screen.pad(a, Vector2(320, 180), Vector2(-1.0, -1.0)).h, 1.0, "negative is none")
	t.assert_eq(Screen.picture_rect(a, a, 1.0), Vector4(0, 0, 1, 1), "unpadded: the whole pass")
	var r := Screen.picture_rect(a, g.w, g.h)
	t.assert_true(r.is_equal_approx(Vector4(0.5 / (a + 1.0), 0.25, a / (a + 1.0), 0.5)), "padded: centred, margin around it")
