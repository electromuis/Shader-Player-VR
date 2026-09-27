class_name VisualizerShaders
extends RefCounted

## Shaders for the shader layers. A key is a file path ("" = none):
##   *.glsl / *.frag / *.txt — Shadertoy code pasted as-is (its mainImage);
##                             wrapped with the compatibility includes on load
##   *.gdshader              — a Godot canvas_item shader, used as-is (it can
##                             include the same two files itself, as the
##                             built-ins do)
## A .gdshader that uses `input_tex` (usually by including EFFECT_PRELUDE)
## is an effect instead: it runs on a layer's or the screen's output, after
## the layer's shader, and gets none of the Shadertoy inputs.
##
## Hints, read from the source:
##   // @resolution 1024x1024  — pixel size a layer shader renders at (and
##                               its screen's shape); default DEFAULT_RESOLUTION,
##                               or that height at the video's shape when the
##                               shader reads the video. `@resolution 270`
##                               gives just the height (x = 0), the width
##                               following that same shape
##   // @title Light ring      — the name in pickers (title_of); without one,
##                               the file name
##   // @iChannel1 video       — what a layer's iChannelN samples (one of
##                               CHANNEL_SOURCES); iChannel0 is "audio" unless
##                               tagged otherwise
##   Expression hints (EXPRESSION_HINTS): the value is a Godot Expression
##   over the effect's params (its hinted uniforms, current values) and
##   `aspect` (the picture's width / height), with the built-ins (max(),
##   min(), ...) and pick(condition, if_true, if_false) for choices; see
##   eval_hint. So `// @passes pick(radius > 0.0, 6, 1)` follows a slider.
##   // @reach radius * 0.5    — how far an effect draws past the picture's
##                               edge, in picture heights (a Vector2 for x
##                               and y apart; reach_of). Screen adds that
##                               margin around the picture so it isn't cut
##                               off
##   // @passes 6              — an effect run that many times, each pass on
##                               the one before (`input_tex`), told which by
##                               `uniform int pass_index` (from 0) and
##                               `pass_count`; all but the last at its
##                               `pass_scale` (a float uniform, default 1) of
##                               the size. For separable blurs (Fast blur)
##   // @prepass_passes 7      — the same for an effect's prepass (see
##                               Screen): step 0 is the prepass proper, the
##                               rest run on it at the prepass's size, and
##                               the effect reads the last as `prepass_tex`
##                               (Glow (fast soften) blurs its halo there)
##   A pass count changing with the params rebuilds the Screen's passes.
##   uniform float x : hint_range(0.0, 1.0, 0.01) = 0.5;
##                             — a slider in the Camera tab (int too); a
##                               plain `uniform bool` gets a checkbox
##
## Built-ins ship with the player: every shader in BUILTIN_ROOT's shaders/
## (layers) and effects/ folders (builtins()). User shaders are discovered in
## `shaders/` in AppPaths.save_dir() and a `shaders/` folder next to the
## executable (and its
## `sources/` and `effects/` subfolders), like skyboxes.
##
## The release package also carries the built-ins there as editable files:
## a file at a built-in's place under shaders_dir() (see override_path) is
## used instead of the res:// copy, includes too, so the key stays the
## res:// path and presets and scripts keep working.

const BUILTIN_ROOT := "res://player/visualizer/"
const PRELUDE := "res://player/visualizer/shadertoy_prelude.gdshaderinc"
const MAIN := "res://player/visualizer/shadertoy_main.gdshaderinc"
const EFFECT_PRELUDE := "res://player/visualizer/effect_prelude.gdshaderinc"
const SHADERTOY_EXTENSIONS := ["glsl", "frag", "txt"]
const GODOT_EXTENSIONS := ["gdshader"]
const DEFAULT_RESOLUTION := Vector2i(960, 540)
## @iChannelN sources: the live audio texture, or the playing video's whole
## frame (both eyes of a stereo video; see Visualizer).
const CHANNEL_SOURCES := ["audio", "video"]

## Not a file: a layer whose source is the playing video itself, drawn like
## the main screen (see Visualizer). Pickers list it apart from the files.
const VIDEO := "video"
## The layer shader that was a blurred copy of the video, now a VIDEO layer
## with a Blur effect (LayerSettings.from_dict migrates it).
const LEGACY_VIDEO_BLUR := "res://player/visualizer/shaders/video_blur.gdshader"

const KEY_BLACK := "res://player/visualizer/effects/key_black.gdshader"
const BLUR := "res://player/visualizer/effects/blur.gdshader"
const OVAL_MASK := "res://player/visualizer/effects/oval_mask.gdshader"
const EDGE_BLUR := "res://player/visualizer/effects/edge_blur.gdshader"
## Effect uniforms the chain sets itself (see effect_prelude.gdshaderinc),
## never controls.
const CHAIN_INPUTS := ["prepass"]
## The Padding effect of earlier versions: margins are automatic now (see
## `@reach`), so Screen skips it and ScreenSettings drops it.
const LEGACY_PADDING := "res://player/visualizer/effects/padding.gdshader"
## Largest margin reach_of gives, per side, in picture heights.
const MAX_REACH := 4.0
## Most passes a `@passes` effect gets.
const MAX_PASSES := 16
## The hints whose value is an expression over the effect's params (see
## eval_hint).
const EXPRESSION_HINTS := ["reach", "passes", "prepass_passes"]
## eval_hint results kept per shader before starting over.
const MAX_CACHED_RESULTS := 256
const GLOW := "res://player/visualizer/effects/glow.gdshader"
const CROP := "res://player/visualizer/effects/crop.gdshader"
const ROUNDED_CORNERS := "res://player/visualizer/effects/rounded_corners.gdshader"
const KEEP_CENTER := "res://player/visualizer/effects/keep_center.gdshader"
## Nodes that load shaders (Screens and layers), each with a
## `reload_shaders()` that reload_all() calls.
const RELOAD_GROUP := "shader_users"


## key -> parse_hints() result; cleared by list_options so edits show up.
static var _hints_cache := {}
static var _include_re := RegEx.create_from_string("#include\\s+\"([^\"]+)\"")
static var _prepass_re := RegEx.create_from_string("(?m)^\\s*uniform\\s+sampler2D\\s+prepass_tex\\b")
static var _title_re := RegEx.create_from_string("(?m)^\\s*//\\s*@title\\s+(.+?)\\s*$")
static var _expression_hint_re := RegEx.create_from_string(
		"(?m)^\\s*//\\s*@(%s)\\s+(.+?)\\s*$" % "|".join(EXPRESSION_HINTS))
static var _hint_helpers := _HintHelpers.new()
## Set by reload_all(): from then on built-ins and their res:// includes are
## read from their files, not Godot's resource cache, so edits show up.
static var _builtins_fresh := false


## [{key, label}] for the built-in layer shaders, or effects when `effects`.
static func builtins(effects: bool = false) -> Array[Dictionary]:
	return builtin_options(BUILTIN_ROOT.path_join("effects" if effects else "shaders"), "gdshader")


## [{key, label}] for the files ending in `extension` in the res:// folder
## `dir`, by title (title_of; an override's title wins).
static func builtin_options(dir: String, extension: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in DirAccess.get_files_at(dir):
		if String(f).get_extension() != extension:
			continue
		var key := dir.path_join(f)
		var file := override_path(key)
		out.append({"key": key, "label": title_of(FileAccess.get_file_as_string(key if file == "" else file), key)})
	out.sort_custom(func(a, b): return String(a.label).naturalnocasecmp_to(b.label) < 0)
	return out


## The `// @title` in `code` (the file's own, not its includes'), else the
## file name at `path`, spaced out ("light_ring.gdshader" -> "Light ring").
static func title_of(code: String, path: String) -> String:
	var m := _title_re.search(code)
	if m != null:
		return m.get_string(1)
	var name := path.get_file().get_basename().replace("_", " ")
	return name.left(1).to_upper() + name.substr(1)


## The `shaders` folder next to the executable.
static func shaders_dir() -> String:
	return AppPaths.exe_dir().path_join("shaders")


## Folders scanned for user shaders. Missing folders are skipped.
static func search_dirs() -> Array[String]:
	var out: Array[String] = [ProjectSettings.globalize_path(AppPaths.save_path("shaders"))]
	var root := shaders_dir()
	out.append(root)
	out.append(root.path_join("sources"))
	out.append(root.path_join("effects"))
	return out


## The file under `root` standing in for the built-in at `res_path`, or ""
## if there's none: BUILTIN_ROOT's includes go in `root` itself, effects/ in
## `root/effects`, shaders/ in `root/sources`.
static func override_path(res_path: String, root: String = shaders_dir()) -> String:
	if not res_path.begins_with(BUILTIN_ROOT):
		return ""
	var rel := res_path.trim_prefix(BUILTIN_ROOT)
	if rel.begins_with("shaders/"):
		rel = "sources/" + rel.trim_prefix("shaders/")
	var path := root.path_join(rel)
	return path if FileAccess.file_exists(path) else ""


## [{key, label}] for a dropdown: built-ins first, then discovered files —
## layer shaders, or effects when `effects`. Doesn't include a "none" entry.
static func list_options(dirs: Array[String] = search_dirs(), effects: bool = false) -> Array[Dictionary]:
	_hints_cache.clear()
	var out: Array[Dictionary] = []
	# A built-in's override is listed as the built-in, not again as a file.
	var overrides := {}
	for b in builtins() + builtins(true):
		var o := override_path(b.key)
		if o != "":
			overrides[o] = true
	out.append_array(builtins(effects))
	for dir in dirs:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			var ext := String(f).get_extension().to_lower()
			var path := dir.path_join(f)
			if overrides.has(path):
				continue
			if not (ext in GODOT_EXTENSIONS or ext in SHADERTOY_EXTENSIONS):
				continue
			var code := FileAccess.get_file_as_string(path)
			if (ext in GODOT_EXTENSIONS and is_effect_code(code)) == effects:
				out.append({"key": path, "label": title_of(code, path)})
	return out


## The shader for `key`, or null if it can't be read. User files and
## overrides are read fresh each time, so re-selecting one picks up edits.
static func load_shader(key: String) -> Shader:
	if key == "" or key == LEGACY_PADDING:
		return null
	var ext := key.get_extension().to_lower()
	if not (ext in GODOT_EXTENSIONS or ext in SHADERTOY_EXTENSIONS):
		return null
	var path := override_path(key)
	if path == "" and key.begins_with("res://") and not _builtins_fresh:
		var builtin := load(key) as Shader
		if builtin == null:
			return null
		# Its includes may still be overridden.
		var expanded := expand_includes(builtin.code, key.get_base_dir())
		return builtin if expanded == builtin.code else _from_code(expanded)
	if path == "":
		path = key
	if not FileAccess.file_exists(path):
		return null
	var code := FileAccess.get_file_as_string(path)
	if ext in SHADERTOY_EXTENSIONS:
		code = wrap_shadertoy(code)
	return _from_code(expand_includes(code, path.get_base_dir()))


## Pick up shader files edited while running: built-ins are read fresh
## from now on (see builtins_fresh), the caches are dropped and every node
## in RELOAD_GROUP loads its shaders again.
static func reload_all(tree: SceneTree) -> void:
	_builtins_fresh = true
	_hints_cache.clear()
	ScreenGeometry.clear_caches()
	tree.call_group(RELOAD_GROUP, "reload_shaders")


## Whether built-ins are read from their files (after reload_all()) rather than
## through Godot's resource cache.
static func builtins_fresh() -> bool:
	return _builtins_fresh


## `code` with each #include of a file on disk pasted in, since a Shader
## made from code can't resolve those: an overridden built-in include, or a
## path relative to `base_dir` (the including file's folder). Other res://
## includes stay, for Godot to resolve (pasted in too after reload_all(), as
## Godot's copy may be stale).
static func expand_includes(code: String, base_dir: String, _seen: Array = []) -> String:
	var out := ""
	var last := 0
	for m in _include_re.search_all(code):
		var inc := m.get_string(1)
		if inc.is_relative_path():
			inc = base_dir.path_join(inc).simplify_path()
		var file := override_path(inc)
		if file == "" and (_builtins_fresh or not inc.begins_with("res://")):
			file = inc
		var text := m.get_string(0) if inc == m.get_string(1) else "#include \"%s\"" % inc
		if file != "" and not file in _seen and FileAccess.file_exists(file):
			text = expand_includes(FileAccess.get_file_as_string(file), file.get_base_dir(), _seen + [file])
		out += code.substr(last, m.get_start() - last) + text
		last = m.get_end()
	return out + code.substr(last)


static func _from_code(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = code
	return shader


## Godot shader source around pasted Shadertoy code.
static func wrap_shadertoy(source: String) -> String:
	return "shader_type canvas_item;\n#include \"%s\"\n\n%s\n\n#include \"%s\"\n" % [PRELUDE, source, MAIN]


static func is_effect_code(code: String) -> bool:
	return code.contains("input_tex") or code.contains(EFFECT_PRELUDE.get_file())


## Whether an effect wants a prepass (it declares `prepass_tex`; see
## effect_prelude.gdshaderinc and Screen). A real declaration, not a
## mention: an inlined prelude's comments name it too (expand_includes).
static func has_prepass(shader: Shader) -> bool:
	return shader != null and _prepass_re.search(shader.code) != null


## parse_hints() for the shader at `key` (cached); {} hints if unreadable.
static func hints_for(key: String) -> Dictionary:
	if not _hints_cache.has(key):
		var shader := load_shader(key)
		_hints_cache[key] = parse_hints(shader.code if shader != null else "")
	return _hints_cache[key]


## {resolution: Vector2i (ZERO = none given, x 0 = height only), channels: {index: source}
## (always has 0), params: [{name, type ("float" / "int" / "bool"), group,
## min, max, step, default}], expressions: {hint name: source} for the
## EXPRESSION_HINTS given (the first of each), and eval_hint's caches
## (parsed, results)} from shader source. Only uniforms with a
## hint_range, and bools, become params; `group` is the `group_uniforms` they
## sit under ("" for none); unknown channel sources are skipped.
static func parse_hints(code: String) -> Dictionary:
	var out := {"resolution": Vector2i.ZERO, "channels": {0: "audio"}, "params": [],
			"expressions": {}, "parsed": {}, "results": {}}
	for m in _expression_hint_re.search_all(code):
		if not out.expressions.has(m.get_string(1)):
			out.expressions[m.get_string(1)] = m.get_string(2)
	var res_re := RegEx.create_from_string("@resolution\\s+(\\d+)(?:\\s*[xX×]\\s*(\\d+))?")
	var m := res_re.search(code)
	if m != null:
		if m.get_string(2) == "":
			out.resolution = Vector2i(0, int(m.get_string(1)))
		else:
			out.resolution = Vector2i(int(m.get_string(1)), int(m.get_string(2)))
	var ch_re := RegEx.create_from_string("@iChannel([0-3])\\s+(\\w+)")
	for c in ch_re.search_all(code):
		var source := c.get_string(2).to_lower()
		if source in CHANNEL_SOURCES:
			out.channels[int(c.get_string(1))] = source
	var uni_re := RegEx.create_from_string(
			"(?m)^\\s*uniform\\s+(float|int|bool)\\s+(\\w+)\\s*(?::\\s*([^=;]*))?(?:=\\s*([^;]+))?;")
	var range_re := RegEx.create_from_string("hint_range\\s*\\(([^)]*)\\)")
	var group_re := RegEx.create_from_string("(?m)^\\s*group_uniforms\\s*([\\w.]*)\\s*;")
	var groups := group_re.search_all(code)
	for u in uni_re.search_all(code):
		var type := u.get_string(1)
		if u.get_string(2) in CHAIN_INPUTS:
			continue
		# The last `group_uniforms` before it ("" after a bare one, or none).
		var group := ""
		for g in groups:
			if g.get_start() > u.get_start():
				break
			group = g.get_string(1)
		var p := {"name": u.get_string(2), "type": type, "group": group}
		var default_src := u.get_string(4).strip_edges()
		if type == "bool":
			p.default = default_src == "true"
		else:
			var r := range_re.search(u.get_string(3))
			if r == null:
				continue
			var nums := r.get_string(1).split(",")
			p.min = _eval(nums[0], 0.0)
			p.max = _eval(nums[1], 1.0) if nums.size() > 1 else 1.0
			p.step = _eval(nums[2], 0.0) if nums.size() > 2 else (1.0 if type == "int" else 0.01)
			p.default = _eval(default_src, p.min) if default_src != "" else p.min
		out.params.append(p)
	return out


## Whether the effect at `key` declares a `@reach` (so it may draw past the
## picture's edge; how far depends on its params, see reach_of).
static func has_reach(key: String) -> bool:
	return key != "" and hints_for(key).expressions.has("reach")


## How far the effect at `key` draws past the picture's edge with `params`
## (missing ones at their defaults), from its `@reach`: (x, y) margins per
## side in picture heights, for a picture `aspect` wide. ZERO without one, or
## if it doesn't evaluate to a number or Vector2.
static func reach_of(key: String, params: Dictionary, aspect: float) -> Vector2:
	var v = eval_hint(key, "reach", params, aspect)
	match typeof(v):
		TYPE_FLOAT, TYPE_INT:
			v = Vector2(v, v)
		TYPE_VECTOR2:
			pass
		_:
			return Vector2.ZERO
	return (v as Vector2).clamp(Vector2.ZERO, Vector2.ONE * MAX_REACH)


## How many passes the effect at `key` runs with `params` (its `@passes`;
## 1 without), or its prepass with `prepass` (`@prepass_passes`).
static func passes_of(key: String, params: Dictionary, prepass: bool = false) -> int:
	var v = eval_hint(key, "prepass_passes" if prepass else "passes", params)
	if not (typeof(v) in [TYPE_FLOAT, TYPE_INT]):
		return 1
	return clampi(roundi(float(v)), 1, MAX_PASSES)


## The value of the effect at `key`'s expression hint `name` (see
## EXPRESSION_HINTS) with `params` (missing ones at their defaults) and
## `aspect` (the picture's width / height); null without one, or if it
## doesn't parse or run. Parsed once, and the results kept per params (they
## change on every slider step, or every frame when a script animates them).
static func eval_hint(key: String, name: String, params: Dictionary, aspect: float = 16.0 / 9.0) -> Variant:
	if key == "":
		return null
	var hints := hints_for(key)
	if not hints.expressions.has(name):
		return null
	var values: Array = [aspect]
	for spec in hints.params:
		values.append(params.get(spec.name, spec.default))
	var results: Dictionary = hints.results
	var cache_key := hash([name, values])
	if results.has(cache_key):
		return results[cache_key]
	var parsed: Dictionary = hints.parsed
	if not parsed.has(name):
		var names := PackedStringArray(["aspect"])
		for spec in hints.params:
			names.append(spec.name)
		var e := Expression.new()
		if e.parse(hints.expressions[name], names) != OK:
			push_warning("%s: can't read @%s: %s" % [key.get_file(), name, e.get_error_text()])
			e = null
		parsed[name] = e
	var expression: Expression = parsed[name]
	var v = null
	if expression != null:
		v = expression.execute(values, _hint_helpers, false)
		if expression.has_execute_failed():
			v = null
	if results.size() >= MAX_CACHED_RESULTS:
		results.clear()
	results[cache_key] = v
	return v


## Functions a hint expression can call besides Godot's built-ins
## (Expression's own `a if c else b` always gives `a`).
class _HintHelpers:
	func pick(condition: bool, if_true: Variant, if_false: Variant) -> Variant:
		return if_true if condition else if_false


## A number from shader source ("0.5", "1.0 / 3.0", "-2"), or `fallback`.
static func _eval(src: String, fallback: float) -> float:
	var e := Expression.new()
	if e.parse(src.strip_edges()) != OK:
		return fallback
	var v = e.execute()
	if e.has_execute_failed() or not (typeof(v) in [TYPE_FLOAT, TYPE_INT]):
		return fallback
	return float(v)
