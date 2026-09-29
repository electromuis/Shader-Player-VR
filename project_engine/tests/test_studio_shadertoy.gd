extends RefCounted

## The shelf's Shadertoy tab (TODO 17): the collection as shelf assets
## (StudioAssetLibrary), a card made into a layer or an effect in the
## library's shaders/ (StudioShadertoy.make), what a paste is, the site's
## search and send links, and the tab's filter. The tab itself is driven in
## tools/cloud/checks/shot_studio_shadertoy.gd.

const TMP_DIR := "user://test_studio_shadertoy_tmp"
const LAYER := {
	"info": {"id": "Lay3r1", "name": "Neon Rings", "username": "iq", "tags": ["rings", "neon"]},
	"renderpass": [{"type": "image", "name": "Image", "inputs": [{"channel": 0, "type": "music"}],
		"code": "void mainImage(out vec4 o, in vec2 f) { o = vec4(texture(iChannel0, vec2(f.x / iResolution.x, 0.25)).x); }"}],
}
const POST := {
	"info": {"id": "Post12", "name": "Scanlines", "username": "me", "tags": ["post"]},
	"renderpass": [{"type": "image", "name": "Image", "inputs": [{"channel": 0, "type": "video"}],
		"code": "void mainImage(out vec4 o, in vec2 f) { o = texture(iChannel0, f / iResolution.xy) * (0.8 + 0.2 * sin(f.y)); }"}],
}
const MULTI := {
	"info": {"id": "Mult1p", "name": "Fluid", "username": "x"},
	"renderpass": [{"type": "buffer", "name": "Buffer A", "inputs": [], "code": "void mainImage(out vec4 o, in vec2 f) { o = vec4(0.0); }"},
		{"type": "image", "name": "Image", "inputs": [{"channel": 0, "type": "buffer"}],
			"code": "void mainImage(out vec4 o, in vec2 f) { o = texture(iChannel0, f / iResolution.xy); }"}],
}


static func _setup() -> StudioAssetLibrary:
	var root := ProjectSettings.globalize_path(TMP_DIR)
	_rm(root)
	DirAccess.make_dir_recursive_absolute(root.path_join("lib"))
	var st := ShadertoyLibrary.new(root.path_join("st"))
	st.add(LAYER, PackedByteArray([0xff, 0xd8, 0xff]))
	st.add(POST)
	st.add(MULTI)
	var lib := StudioAssetLibrary.new()
	lib.shader_dirs = []
	lib.library_dirs = [root.path_join("lib")]
	lib.shadertoy_dir = root.path_join("st")
	return lib


static func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


static func _card(lib: StudioAssetLibrary, name: String) -> Dictionary:
	for a in lib.of_type("shadertoy"):
		if a.label == name:
			return a
	return {}


static func test_the_collection_is_a_shelf_tab(tc: TestCase) -> void:
	var lib := _setup()
	tc.assert_true(StudioAssetLibrary.TYPES.has("shadertoy") and StudioAssetLibrary.TYPE_LABELS.shadertoy == "Shadertoy", "a tab")
	var cards := lib.of_type("shadertoy")
	tc.assert_eq(cards.map(func(a): return a.label).size(), 3)
	var rings := _card(lib, "Neon Rings")
	tc.assert_eq([rings.kind, rings.source, rings.author, rings.tags], ["shadertoy", "user", "iq", ["rings", "neon"]])
	tc.assert_eq(rings.path.get_file(), "neon_rings_Lay3r1.json")
	tc.assert_eq(rings.picture.get_file(), "neon_rings_Lay3r1.jpg", "the site's thumbnail")
	tc.assert_eq(_card(lib, "Scanlines").picture, "", "none sent")
	tc.assert_eq(lib.of_type("layer").size(), VisualizerShaders.builtins(false).size(), "not layers yet")
	var before := lib.signature()
	ShadertoyLibrary.new(lib.shadertoy_dir).add(ShadertoyShader.from_code("void mainImage(out vec4 o, in vec2 f) { o = vec4(1.0); }", "Mine"))
	tc.assert_true(lib.signature() != before, "a shader arriving shows")
	tc.assert_eq(lib.of_type("shadertoy").size(), 4)
	_rm(ProjectSettings.globalize_path(TMP_DIR))


static func test_a_card_becomes_a_layer_or_an_effect(tc: TestCase) -> void:
	var lib := _setup()
	var dir: String = lib.library_dirs[0]
	var rings := _card(lib, "Neon Rings")
	var r := StudioShadertoy.make(rings, false, dir)
	tc.assert_ok(r)
	tc.assert_eq(r.path, dir.path_join("shaders/neon_rings_Lay3r1.gdshader"))
	tc.assert_eq(r.asset, {"id": "layer:" + r.path, "type": "layer", "kind": "layer", "label": "Neon Rings", "path": r.path,
			"source": "user", "in_piece": false, "scale": StudioAssetLibrary.SCREEN_SCALE, "picture": rings.picture})
	tc.assert_eq(FileAccess.get_file_as_string(r.path), ShadertoyShader.to_gdshader(ShadertoyShader.parse(LAYER), "res://player/visualizer"))
	var listed := lib.of_type("layer").filter(func(a): return a.path == r.path)
	tc.assert_eq(listed.size(), 1, "one of your layers now")
	tc.assert_eq([listed[0].id, listed[0].label], [r.asset.id, "Neon Rings"], "the same asset as the library lists")
	tc.assert_true(StudioBundle.bundle(ProjectSettings.globalize_path(TMP_DIR).path_join("piece"), r.path).ok, "a piece can take it")

	var post := _card(lib, "Scanlines")
	var e := StudioShadertoy.make(post, true, dir)
	tc.assert_ok(e)
	tc.assert_eq(e.path.get_file(), "scanlines_Post12_effect.gdshader")
	tc.assert_eq([e.asset.type, e.asset.kind, e.asset.label], ["effect", "effect", "Scanlines"])
	tc.assert_true(lib.of_type("effect").any(func(a): return a.id == e.asset.id), "one of your effects")
	tc.assert_false(lib.of_type("layer").any(func(a): return a.path == e.path), "not a layer")

	# Made again: the file stays as it is (it may have been edited).
	var f := FileAccess.open(r.path, FileAccess.WRITE)
	f.store_string("// edited\n")
	f.close()
	tc.assert_ok(StudioShadertoy.make(rings, false, dir))
	tc.assert_eq(FileAccess.get_file_as_string(r.path), "// edited\n")

	var multi := StudioShadertoy.make(_card(lib, "Fluid"), false, dir)
	tc.assert_false(multi.ok)
	tc.assert_has(multi.error, "several passes")
	tc.assert_false(FileAccess.file_exists(dir.path_join("shaders/fluid_Mult1p.gdshader")), "nothing written")
	_rm(ProjectSettings.globalize_path(TMP_DIR))


static func test_paste_search_and_filter(tc: TestCase) -> void:
	var lib := _setup()
	var st := ShadertoyLibrary.new(lib.shadertoy_dir)
	tc.assert_eq(StudioShadertoy.paste("https://www.shadertoy.com/view/XsXXDn", st), {"kind": "link", "id": "XsXXDn"})
	tc.assert_eq(StudioShadertoy.send_url("XsXXDn"), "https://www.shadertoy.com/view/XsXXDn#vj-send")
	var code := StudioShadertoy.paste("void mainImage(out vec4 o, in vec2 f) { o = vec4(0.5); }", st)
	tc.assert_eq(code.kind, "added")
	tc.assert_true(code.shader.id.begins_with("local_"))
	var json := StudioShadertoy.paste(JSON.stringify([{"info": {"id": "J50n12", "name": "From JSON"},
			"renderpass": [{"type": "image", "code": "void mainImage(out vec4 o, in vec2 f) { o = vec4(1.0); }"}]}]), st)
	tc.assert_eq([json.kind, json.shader.name], ["added", "From JSON"])
	tc.assert_eq(st.entries().size(), 5)
	tc.assert_eq(StudioShadertoy.paste("hello", st), {"kind": "none"})
	tc.assert_eq(StudioShadertoy.paste('{"not": "a shader"}', st), {"kind": "none"})

	tc.assert_eq(StudioShadertoy.search_url("  neon tunnel "), "https://www.shadertoy.com/results?query=neon%20tunnel")
	tc.assert_eq(StudioShadertoy.search_url(""), "https://www.shadertoy.com/browse")

	var rings := _card(lib, "Neon Rings")
	for q in ["", "neon", "RINGS", "iq", "neon iq"]:
		tc.assert_true(StudioShadertoy.matches(rings, q), "'%s' finds it" % q)
	for q in ["tunnel", "neon tunnel"]:
		tc.assert_false(StudioShadertoy.matches(rings, q), "'%s' doesn't" % q)
	_rm(ProjectSettings.globalize_path(TMP_DIR))
