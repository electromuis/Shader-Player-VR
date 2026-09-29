@tool
class_name ShadertoyShader
extends RefCounted

## Shadertoy shaders turned into VJ layer shaders. Pure (no editor calls):
## the authoring addon has a copy (addon_vj/shadertoy/, kept identical by
## tests/test_addon_shader_copies.gd) for its Shadertoy dock, and Studio can
## use it as is. The include folder is a parameter (the player's
## `res://player/visualizer` or the addon's copy of it).
##
## Input is the shader's JSON as the site has it: one shader
## `{"info": {...}, "renderpass": [...]}`, the paid API's `{"Shader": {...}}`,
## or an array of them (the site's own /shadertoy endpoint, which the Chrome
## extension in tools/shadertoy_extension uses; the first is taken). Plain
## pasted code (a mainImage) works too, through from_code().
##
## A layer runs one pass: the Image pass, with Common in front of it.
## Audio inputs (music, soundcloud, mic) read the player's audio texture and
## video / webcam the playing video (`// @iChannelN audio|video`); textures,
## keyboard, cubemaps and buffers aren't available (analyze() says which).
##
## A shader can be an effect instead (to_effect_gdshader): a post-process
## that reads a picture (its video, webcam or texture channel) gets the
## picture of the screen or layer it's on there, the right way up.

const SITE := "https://www.shadertoy.com"
const PRELUDE_FILE := "shadertoy_prelude.gdshaderinc"
const MAIN_FILE := "shadertoy_main.gdshaderinc"
const EFFECT_PRELUDE_FILE := "effect_prelude.gdshaderinc"
## What an effect gets of Shadertoy's inputs, after the effect prelude
## (which has input_tex, the picture, and TIME following the video).
const EFFECT_INPUTS := """uniform vec4 iMouse = vec4(0.0);
uniform vec4 iDate = vec4(0.0);
uniform float iSampleRate = 44100.0;
uniform vec3 iChannelResolution[4];
#define iResolution vec3(vec2(textureSize(input_tex, 0)), 1.0)
#define iTime TIME
#define iGlobalTime TIME
#define iTimeDelta (1.0 / 60.0)
#define iFrameRate 60.0
#define iFrame int(TIME * 60.0)
#define texture2D texture

// The picture, as Shadertoy has it: the bottom row at v = 0.
vec4 _st_input(vec2 uv) { return texture(input_tex, vec2(uv.x, 1.0 - uv.y)); }
vec4 _st_input(vec2 uv, float bias) { return texture(input_tex, vec2(uv.x, 1.0 - uv.y), bias); }
vec4 _st_input_lod(vec2 uv, float lod) { return textureLod(input_tex, vec2(uv.x, 1.0 - uv.y), lod); }
vec4 _st_input_fetch(ivec2 p, int lod) {
	ivec2 s = textureSize(input_tex, lod);
	return texelFetch(input_tex, ivec2(p.x, s.y - 1 - p.y), lod);
}"""
const EFFECT_MAIN := """void fragment() {
	vec4 st_color = vec4(0.0, 0.0, 0.0, 1.0);
	mainImage(st_color, vec2(UV.x, 1.0 - UV.y) * iResolution.xy);
	COLOR = vec4(st_color.rgb, texture(input_tex, UV).a);
}"""
## The input types an effect can take its picture from, best first.
const PICTURE_TYPES := ["video", "webcam", "texture"]
const AUDIO_TYPES := ["music", "musicstream", "mic"]
const VIDEO_TYPES := ["video", "webcam"]
## Words Godot's shading language keeps for itself that GLSL doesn't; a
## Shadertoy identifier with one of these names gets `_st` appended.
const GODOT_RESERVED := ["sample", "input", "output", "varying", "instance", "global", "render_mode",
		"shader_type", "group_uniforms", "source_color", "hint_range", "repeat_enable",
		"repeat_disable", "filter_linear", "filter_nearest", "SCREEN_UV", "COLOR", "UV", "TIME",
		"PI", "TAU", "E", "VERTEX", "FRAGCOORD", "TEXTURE", "POINT_COORD"]


## The shader in `data` (a JSON string or its parsed value), normalised:
## {id, name, author, description, tags, date, likes, views, url, passes:
## [{type, name, code, inputs: [{channel, type, src}]}]}; {} if it isn't one.
static func parse(data) -> Dictionary:
	if data is String:
		data = read_json(data)
	if data is Array:
		data = data[0] if not data.is_empty() else null
	if data is Dictionary and data.has("Shader"):
		data = data.Shader
	if not (data is Dictionary and data.get("info") is Dictionary and data.get("renderpass") is Array):
		return {}
	var info: Dictionary = data.info
	var id := String(info.get("id", ""))
	var passes: Array = []
	for rp in data.renderpass:
		if not rp is Dictionary:
			continue
		var inputs: Array = []
		for inp in rp.get("inputs", []):
			if inp is Dictionary:
				inputs.append({
					"channel": int(inp.get("channel", 0)),
					"type": String(inp.get("type", inp.get("ctype", ""))),
					"src": String(inp.get("filepath", inp.get("src", ""))),
				})
		passes.append({
			"type": String(rp.get("type", "")),
			"name": String(rp.get("name", "")),
			"code": String(rp.get("code", "")),
			"inputs": inputs,
		})
	var tags: Array = []
	for t in info.get("tags", []):
		tags.append(String(t))
	return {
		"id": id,
		"name": String(info.get("name", id)),
		"author": String(info.get("username", "")),
		"description": String(info.get("description", "")),
		"tags": tags,
		"date": int(info.get("date", 0)),
		"likes": int(info.get("likes", 0)),
		"views": int(info.get("viewed", 0)),
		"url": view_url(id) if id != "" and not id.begins_with("local_") else "",
		"passes": passes,
	}


## A shader's JSON for pasted code (its mainImage), in the site's shape, so
## it's stored and parsed like one from the site. Its id is `local_` and a
## hash of the code.
static func from_code(code: String, name: String = "") -> Dictionary:
	var id := "local_%s" % code.sha1_text().substr(0, 8)
	return {
		"info": {"id": id, "name": name if name != "" else "Pasted shader", "username": "",
				"description": "", "tags": [], "date": str(int(Time.get_unix_time_from_system()))},
		"renderpass": [{"type": "image", "name": "Image", "code": code, "inputs": [], "outputs": []}],
	}


## `text` parsed, or null when it isn't JSON (without logging an error, as
## JSON.parse_string does: pasted code isn't JSON, and that's fine).
static func read_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func view_url(id: String) -> String:
	return "%s/view/%s" % [SITE, id]


## The shader id in a link to its page (`…shadertoy.com/view/<id>`, or
## /embed/); "" if `text` isn't one.
static func id_from_link(text: String) -> String:
	var m := RegEx.create_from_string("^\\s*(?:https?://)?(?:www\\.)?shadertoy\\.com/(?:view|embed)/([A-Za-z0-9]+)").search(text)
	return m.get_string(1) if m != null else ""


static func thumbnail_url(id: String) -> String:
	return "%s/media/shaders/%s.jpg" % [SITE, id]


## Whether it runs as a layer, and what's lost: {ok, errors, edits,
## warnings, channels: {N: "audio" | "video"}}. Errors mean it can't work
## (no Image pass, or it needs a buffer pass); edits, that it won't compile
## until the .gdshader is edited by hand; warnings, that it runs without
## something. `as_effect`: the same for it as an effect
## (to_effect_gdshader); `channels` is then empty.
static func analyze(st: Dictionary, as_effect: bool = false) -> Dictionary:
	if as_effect:
		return _analyze_effect(st)
	var out := {"ok": true, "errors": [], "edits": [], "warnings": [], "channels": {}}
	var image := _pass(st, "image")
	if image.is_empty():
		out.errors.append("it has no Image pass")
	var extra: Array = []
	for p in st.get("passes", []):
		match p.type:
			"buffer", "cubemap":
				extra.append(p.name if p.name != "" else p.type)
			"sound":
				out.warnings.append("its sound output (%s) isn't played" % (p.name if p.name != "" else "Sound"))
	if not extra.is_empty():
		out.errors.append("it renders in several passes (%s); a layer runs one" % ", ".join(extra))
	if not image.is_empty():
		for inp in image.inputs:
			var ch := "iChannel%d" % inp.channel
			if inp.type in AUDIO_TYPES:
				out.channels[inp.channel] = "audio"
			elif inp.type in VIDEO_TYPES:
				out.channels[inp.channel] = "video"
				out.warnings.append("%s (%s) shows the playing video instead" % [ch, inp.type])
			elif inp.type == "buffer":
				pass  # already an error: its buffer pass
			else:
				out.warnings.append("%s (%s) isn't available: it reads black" % [ch, inp.type if inp.type != "" else "input"])
		var code := source_code(st)
		if RegEx.create_from_string("\\biMouse\\b").search(code) != null:
			out.warnings.append("it uses the mouse (iMouse), which stays at 0")
		var globals := mutable_globals(code)
		if not globals.is_empty():
			out.edits.append("it changes global variables (%s), which Godot shaders can't have: pass them to the functions that use them, or make them const" % ", ".join(globals))
	out.ok = out.errors.is_empty()
	return out


static func _analyze_effect(st: Dictionary) -> Dictionary:
	var layer := analyze(st)
	var out := {"ok": layer.ok, "errors": layer.errors, "edits": layer.edits, "warnings": [], "channels": {}}
	for w in layer.warnings:
		if not String(w).begins_with("iChannel"):
			out.warnings.append(w)
	var input := input_channel(st)
	if input < 0:
		out.warnings.append("it doesn't read a picture: as an effect it covers the one beneath")
	var types := {}
	for inp in _pass(st, "image").get("inputs", []):
		types[inp.channel] = inp.type
	for ch in _channels_used(source_code(st)):
		if ch == input:
			continue
		var type: String = types.get(ch, "")
		if type in AUDIO_TYPES:
			out.warnings.append("iChannel%d (%s) isn't available in an effect: it reads black" % [ch, type])
		elif type != "buffer":
			out.warnings.append("iChannel%d%s is an image you pick in the effect's controls (black until you do)"
					% [ch, " (%s)" % type if type != "" else ""])
	return out


## The channel an effect reads its picture from: the Image pass's video or
## webcam input, else its first texture; for pasted code (which says
## nothing about its inputs) the first channel it reads. -1 if none.
static func input_channel(st: Dictionary) -> int:
	var image := _pass(st, "image")
	if image.is_empty():
		return -1
	for type in PICTURE_TYPES:
		for inp in image.inputs:
			if inp.type == type:
				return inp.channel
	if image.inputs.is_empty():
		var used := _channels_used(source_code(st))
		return used[0] if not used.is_empty() else -1
	return -1


## The iChannelN numbers the code mentions, in order.
static func _channels_used(code: String) -> Array:
	var out: Array = []
	for m in RegEx.create_from_string("\\biChannel([0-3])\\b").search_all(_blank_comments(code)):
		var ch := int(m.get_string(1))
		if not ch in out:
			out.append(ch)
	out.sort()
	return out


## Common + Image, fixed up for Godot's shading language (see fix_code).
static func source_code(st: Dictionary) -> String:
	var parts: Array = []
	var common := _pass(st, "common")
	if not common.is_empty() and common.code.strip_edges() != "":
		parts.append("// ---- Common ----\n" + common.code.strip_edges())
	var image := _pass(st, "image")
	if not image.is_empty():
		parts.append("// ---- Image ----\n" + image.code.strip_edges())
	return fix_code("\n\n".join(parts))


## What GLSL ES allows and Godot's shading language doesn't, mended where
## it's mechanical:
## - `#version` / `precision` lines go
## - identifiers named like Godot's keywords or built-ins are renamed
## - matrices built from numbers (`mat2(c, -s, s, c)`) are built from
##   columns instead, which Godot wants (also in constants); a mat2 from
##   a vec2 and two numbers goes through a helper function
## - globals that are set once where they're declared become const, and
##   those changed later move into a struct handed to every function
##   (_lift_globals; mutable_globals lists any it had to leave)
## - assignments joined by commas (`a = 1., b = 2.;`) become statements
## - vectors built from the other number type, which GLSL converts and
##   Godot doesn't: `vec2(i, j)` with int variables gets float(), and
##   `ivec2(.7, 0)` int() (only where the types are plain to see: literals,
##   and variables declared in the same function)
## - the Shadertoy uniforms the prelude lacks are defined
static func fix_code(code: String) -> String:
	code = RegEx.create_from_string("(?m)^[ \\t]*#version[^\\n]*\\n?").sub(code, "", true)
	code = RegEx.create_from_string("(?m)^[ \\t]*precision\\s+\\w+\\s+\\w+\\s*;[^\\n]*\\n?").sub(code, "", true)
	for word in GODOT_RESERVED:
		code = RegEx.create_from_string("\\b%s\\b" % word).sub(code, word + "_st", true)
	var helpers := {}
	code = _fix_matrices(code, helpers)
	code = _constify_globals(code)
	code = _lift_globals(code)
	code = _split_comma_assignments(code)
	code = _fix_vector_casts(code)
	var head: Array = []
	if RegEx.create_from_string("\\biChannelTime\\b").search(code) != null:
		head.append("#define iChannelTime float[4](TIME, TIME, TIME, TIME)")
	if helpers.has("mat2"):
		head.append("mat2 _st_mat2(vec2 a, float b, float c) { return mat2(a, vec2(b, c)); }")
		head.append("mat2 _st_mat2(float a, float b, vec2 c) { return mat2(vec2(a, b), c); }")
		head.append("mat2 _st_mat2(float a, vec2 b, float c) { return mat2(vec2(a, b.x), vec2(b.y, c)); }")
	if not head.is_empty():
		code = "\n".join(head) + "\n\n" + code
	return code


## The names of global variables the code changes (declared outside any
## function without `const`); Godot shaders have no such thing.
static func mutable_globals(code: String) -> Array:
	var out: Array = []
	for g in _globals(code):
		for v in g.vars:
			out.append(v.name)
	return out


## `matN(...)` calls rewritten as described in fix_code; `helpers` gets
## "mat2" when a helper is used.
static func _fix_matrices(code: String, helpers: Dictionary) -> String:
	var re := RegEx.create_from_string("(?<![\\w.])mat([234])\\s*\\(")
	var out := ""
	var pos := 0
	while true:
		var m := re.search(code, pos)
		if m == null:
			break
		var open := m.get_end() - 1
		var close := _matching(code, open)
		if close < 0:
			break
		var n := int(m.get_string(1))
		var args: Array = []
		for a in _split_args(code.substr(open + 1, close - open - 1)):
			args.append(_fix_matrices(a, helpers).strip_edges())
		out += code.substr(pos, m.get_start() - pos)
		if args.size() == n * n:
			var cols: Array = []
			for c in n:
				cols.append("vec%d(%s)" % [n, ", ".join(args.slice(c * n, c * n + n))])
			out += "mat%d(%s)" % [n, ", ".join(cols)]
		elif n == 2 and args.size() == 3:
			helpers["mat2"] = true
			out += "_st_mat2(%s)" % ", ".join(args)
		else:
			out += "mat%d(%s)" % [n, ", ".join(args)]
		pos = close + 1
	return out + code.substr(pos)


## float() / int() around constructor arguments of the other number type
## (see fix_code), function by function.
static func _fix_vector_casts(code: String) -> String:
	var clean := _blank_comments(code)
	var ctor := RegEx.create_from_string("(?<![\\w.])(vec|ivec|uvec)[234]\\s*\\(")
	var edits: Array = []
	for f in _top_level(code).filter(func(it): return it.kind == "func"):
		var scope := clean.substr(f.params_open, f.body_close - f.params_open)
		var types := {}
		for m in RegEx.create_from_string("(?<![\\w.])(int|uint|float)\\s+([A-Za-z_]\\w*)").search_all(scope):
			types[m.get_string(2)] = "float" if m.get_string(1) == "float" else "int"
		for m in ctor.search_all(clean, f.body_open, f.body_close):
			var open := m.get_end() - 1
			var close := _matching(clean, open)
			if close < 0:
				continue
			var want := "float" if m.get_string(1) == "vec" else "int"
			var pos := open + 1
			for a: String in _split_args(clean.substr(open + 1, close - open - 1)):
				if _number_type(a, types) not in ["", want]:
					var lead := a.length() - a.lstrip(" \t\r\n").length()
					var trail := a.length() - a.rstrip(" \t\r\n").length()
					edits.append([pos + lead, pos + a.length() - trail, want])
				pos += a.length() + 1
	edits.sort_custom(func(a, b): return a[0] > b[0])
	for e in edits:
		code = code.substr(0, e[0]) + "%s(%s)" % [e[2], code.substr(e[0], e[1] - e[0])] + code.substr(e[1])
	return code


## "int" or "float" for an argument that's plainly one (numbers, variables
## in `types`, + - * / and brackets), else "".
static func _number_type(arg: String, types: Dictionary) -> String:
	if not RegEx.create_from_string("^[\\w\\s.+\\-*/()]+$").search(arg.strip_edges()):
		return ""
	var found := ""
	for m in RegEx.create_from_string("(?<![\\w.])(?:([A-Za-z_]\\w*)|(\\d+\\.\\d*(?:[eE][-+]?\\d+)?|\\.\\d+(?:[eE][-+]?\\d+)?|\\d+[eE][-+]?\\d+)|(\\d+)u?)(?![\\w.])").search_all(arg):
		var t := ""
		if m.get_string(1) != "":
			t = types.get(m.get_string(1), "")
			if t == "":
				return ""  # unknown: a function, a vector, a field…
		elif m.get_string(2) != "":
			t = "float"
		else:
			continue  # an integer literal fits either
		if found != "" and t != found:
			return ""
		found = t
	return found


## `a = x, b = y;` → `a = x; b = y;` (Godot has no comma operator). Only
## statements whose every part is an assignment, outside brackets, so
## declarations (`float a = 1., b;`) and for headers stay as they are.
static func _split_comma_assignments(code: String) -> String:
	var clean := _blank_comments(code)
	var assign := RegEx.create_from_string("^\\s*[A-Za-z_][\\w.]*(?:\\[[^\\]]*\\])?(?:\\.\\w+)?\\s*[-+*/]?=(?!=)")
	var out := ""
	var pos := 0
	var start := 0
	var depth := 0
	for i in clean.length():
		var ch := clean[i]
		if ch == "(" or ch == "[":
			depth += 1
		elif ch == ")" or ch == "]":
			depth -= 1
		elif depth == 0 and (ch == "{" or ch == "}"):
			start = i + 1
		elif depth == 0 and ch == ";":
			var parts := _split_args(clean.substr(start, i - start))
			var all_assign := parts.size() > 1
			for part in parts:
				all_assign = all_assign and assign.search(part) != null
			if all_assign:
				var offset := start
				for p in parts.size() - 1:
					offset += parts[p].length()
					out += code.substr(pos, offset - pos) + ";"
					offset += 1
					pos = offset
			start = i + 1
	return out + code.substr(pos)


## Globals given a value where they're declared and never assigned after
## get `const`.
static func _constify_globals(code: String) -> String:
	var globals := _globals(code)
	for i in range(globals.size() - 1, -1, -1):  # from the end, so offsets hold
		var g: Dictionary = globals[i]
		var fixed := true
		for v in g.vars:
			fixed = fixed and v.init != "" and not _assigned(code, v.name, g.end)
		if fixed:
			code = code.substr(0, g.start) + "const " + code.substr(g.start)
	return code


## Globals that are changed (Godot shaders have none) moved into a struct,
## `_StGlobals _g`, that mainImage makes and every other function takes as
## its first parameter (`inout`); their uses become `_g.<name>`, and
## mainImage gives them their start values (0 when the declaration has
## none, as GLSL does). Left as it is when that can't be done safely: an
## array or a struct among them, or a function with a variable of the same
## name as one of them.
static func _lift_globals(code: String) -> String:
	var items := _top_level(code)
	var globals: Array = items.filter(func(it): return it.kind == "var" and it.qual == "")
	if globals.is_empty():
		return code
	var funcs: Array = items.filter(func(it): return it.kind == "func")
	var main_image: Dictionary = {}
	var names: Array = []
	var fields: Array = []
	var inits: Array = []
	for g in globals:
		if not _ZERO.has(g.type):
			return code
		for v in g.vars:
			if v.array != "":
				return code
			names.append(v.name)
			fields.append("\t%s %s;" % [g.type, v.name])
			inits.append([v.name, v.init if v.init != "" else _ZERO[g.type]])
	var fnames: Array = []
	for f in funcs:
		if f.name == "mainImage":
			main_image = f
		elif not f.name in fnames:
			fnames.append(f.name)
	if main_image.is_empty():
		return code
	var clean := _blank_comments(code)
	for f in funcs:
		var scope := clean.substr(f.params_open, f.body_close - f.params_open)
		for n in names:
			if RegEx.create_from_string("(?<![\\w.])(?!return\\b|else\\b|case\\b)[A-Za-z_]\\w*\\s+%s\\s*[=;,)\\[]" % n).search(scope) != null:
				return code
	var uses := RegEx.create_from_string("(?<![\\w.])(%s)\\b(\\s*\\()?" % "|".join(names + fnames))
	# [start, end, text] edits on `code`, applied from the end.
	var edits: Array = []
	var rewrite := func(from: int, to: int) -> void:
		for m in uses.search_all(clean, from, to):
			var word := m.get_string(1)
			if names.has(word) and m.get_string(2) == "":
				edits.append([m.get_start(1), m.get_end(1), "_g." + word])
			elif fnames.has(word) and m.get_string(2) != "":
				var after := clean.substr(m.get_end()).strip_edges(true, false)
				edits.append([m.get_end(), m.get_end(), "_g" if after.begins_with(")") else "_g, "])
	for g in globals:
		edits.append([g.start, g.end, ""])
	for f in funcs:
		if f != main_image:
			var empty := clean.substr(f.params_open + 1, f.params_close - f.params_open - 1).strip_edges() in ["", "void"]
			if empty:
				edits.append([f.params_open + 1, f.params_close, "inout _StGlobals _g"])
			else:
				edits.append([f.params_open + 1, f.params_open + 1, "inout _StGlobals _g, "])
		rewrite.call(f.body_open, f.body_close)
	for m in RegEx.create_from_string("(?m)^[ \\t]*#define\\b[^\\n]*").search_all(clean):
		rewrite.call(m.get_start(), m.get_end())
	var setup := "\n\t_StGlobals _g;"
	for init in inits:
		var value: String = init[1]
		value = RegEx.create_from_string("(?<![\\w.])(%s)\\b(?!\\s*\\()" % "|".join(names)).sub(value, "_g.$1", true)
		setup += "\n\t_g.%s = %s;" % [init[0], value.strip_edges()]
	edits.append([main_image.body_open + 1, main_image.body_open + 1, setup])
	edits.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	for e in edits:
		code = code.substr(0, e[0]) + e[2] + code.substr(e[1])
	return "struct _StGlobals {\n%s\n};\n\n%s" % ["\n".join(fields), code]


## A zero of each built-in type, for globals declared without a value.
const _ZERO := {
	"float": "0.0", "int": "0", "uint": "0u", "bool": "false",
	"vec2": "vec2(0.0)", "vec3": "vec3(0.0)", "vec4": "vec4(0.0)",
	"ivec2": "ivec2(0)", "ivec3": "ivec3(0)", "ivec4": "ivec4(0)",
	"uvec2": "uvec2(0u)", "uvec3": "uvec3(0u)", "uvec4": "uvec4(0u)",
	"bvec2": "bvec2(false)", "bvec3": "bvec3(false)", "bvec4": "bvec4(false)",
	"mat2": "mat2(0.0)", "mat3": "mat3(0.0)", "mat4": "mat4(0.0)",
}


## Top-level variable declarations that aren't const or uniform:
## [{type, vars: [{name, array, init}], start, end}] (offsets into `code`).
static func _globals(code: String) -> Array:
	return _top_level(code).filter(func(it): return it.kind == "var" and it.qual == "")


## What's outside functions: functions {kind: "func", name, params_open,
## params_close, body_open, body_close} and variable declarations
## {kind: "var", qual ("" or const / uniform), type, vars: [{name, array,
## init}], start, end}, with offsets into `code`. Preprocessor lines,
## structs and prototypes are skipped.
static func _top_level(code: String) -> Array:
	var clean := _blank_comments(code)
	var func_re := RegEx.create_from_string("([A-Za-z_]\\w*)\\s*\\(([^()]*)\\)\\s*$")
	var decl_re := RegEx.create_from_string(
			"^\\s*((?:(?:const|uniform|highp|mediump|lowp)\\s+)*)([A-Za-z_]\\w*)\\s+([A-Za-z_][\\s\\S]*)$")
	var var_re := RegEx.create_from_string("^\\s*([A-Za-z_]\\w*)\\s*(\\[[^\\]]*\\])?\\s*(?:=([\\s\\S]*))?$")
	var not_types := ["struct", "return", "precision", "varying", "in", "out", "inout", "layout"]
	var out: Array = []
	var start := 0
	var i := 0
	while i < clean.length():
		var ch := clean[i]
		if ch == "#" and clean.substr(start, i - start).strip_edges() == "":
			# A preprocessor line (with its backslash continuations).
			var nl := clean.find("\n", i)
			while nl > 0 and clean.substr(0, nl).strip_edges(false, true).ends_with("\\"):
				nl = clean.find("\n", nl + 1)
			i = clean.length() if nl < 0 else nl
			start = i + 1
		elif ch == "{":
			var close := _matching_brace(clean, i)
			if close < 0:
				break
			var head := clean.substr(start, i - start)
			var m := func_re.search(head)
			if m != null and not head.strip_edges().begins_with("struct"):
				out.append({"kind": "func", "name": m.get_string(1),
						"params_open": start + m.get_start(2) - 1, "params_close": start + m.get_end(2),
						"body_open": i, "body_close": close})
			i = close
			start = i + 1
		elif ch == ";":
			var stmt := clean.substr(start, i - start)
			var m := decl_re.search(stmt)
			if m != null and not m.get_string(2) in not_types:
				var vars: Array = []
				for d in _split_args(m.get_string(3)):
					var v := var_re.search(d)
					if v == null:
						vars = []  # a prototype or something else
						break
					vars.append({"name": v.get_string(1), "array": v.get_string(2), "init": v.get_string(3).strip_edges()})
				if not vars.is_empty():
					var lead := stmt.length() - stmt.lstrip(" \t\r\n").length()
					var qual := m.get_string(1)
					out.append({"kind": "var", "type": m.get_string(2), "vars": vars, "start": start + lead, "end": i + 1,
							"qual": "const" if qual.contains("const") else "uniform" if qual.contains("uniform") else ""})
			start = i + 1
		i += 1
	return out


## The index of the brace closing the one at `open`, or -1.
static func _matching_brace(code: String, open: int) -> int:
	var depth := 0
	for i in range(open, code.length()):
		if code[i] == "{":
			depth += 1
		elif code[i] == "}":
			depth -= 1
			if depth == 0:
				return i
	return -1


## Whether `name` is assigned (=, +=, ++, …) anywhere after `from`.
static func _assigned(code: String, name: String, from: int) -> bool:
	var re := RegEx.create_from_string(
			"(?<![\\w.])%s\\s*(?:\\[[^\\]]*\\])?\\s*(?:\\.\\w+\\s*)?(?:[-+*/%%&|^]?=(?!=)|\\+\\+|--)|(?:\\+\\+|--)\\s*%s\\b" % [name, name])
	return re.search(_blank_comments(code), from) != null


## `code` with its comments replaced by spaces (same length, so offsets hold).
static func _blank_comments(code: String) -> String:
	var re := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/")
	var out := ""
	var pos := 0
	for m in re.search_all(code):
		out += code.substr(pos, m.get_start() - pos) + " ".repeat(m.get_end() - m.get_start())
		pos = m.get_end()
	return out + code.substr(pos)


## The index of the bracket closing the one at `open`, or -1.
static func _matching(code: String, open: int) -> int:
	var depth := 0
	for i in range(open, code.length()):
		var ch := code[i]
		if ch == "(" or ch == "[":
			depth += 1
		elif ch == ")" or ch == "]":
			depth -= 1
			if depth == 0:
				return i
	return -1


## Splits an argument list at its top-level commas.
static func _split_args(s: String) -> Array:
	var out: Array = []
	var depth := 0
	var start := 0
	for i in s.length():
		var ch := s[i]
		if ch == "(" or ch == "[":
			depth += 1
		elif ch == ")" or ch == "]":
			depth -= 1
		elif ch == "," and depth == 0:
			out.append(s.substr(start, i - start))
			start = i + 1
	if s.strip_edges() != "" or not out.is_empty():
		out.append(s.substr(start))
	return out


## The .gdshader for a layer: a header naming the shader, its author and
## licence, the channel hints, and the code between the Shadertoy includes
## in `include_dir` (e.g. "res://addons/vj_editor/visualizer").
static func to_gdshader(st: Dictionary, include_dir: String) -> String:
	var a := analyze(st)
	var lines := _header(st, a)
	var channels: Dictionary = a.channels
	var keys := channels.keys()
	keys.sort()
	for ch in keys:
		if not (ch == 0 and channels[ch] == "audio"):  # iChannel0 is audio already
			lines.append("// @iChannel%d %s" % [ch, channels[ch]])
	lines.append("shader_type canvas_item;")
	lines.append('#include "%s"' % include_dir.path_join(PRELUDE_FILE))
	lines.append("")
	lines.append(source_code(st))
	lines.append("")
	lines.append('#include "%s"' % include_dir.path_join(MAIN_FILE))
	return "\n".join(lines) + "\n"


## The .gdshader for an effect (see the top of this file): the same header,
## the code after the effect prelude in `include_dir` with Shadertoy's
## inputs (EFFECT_INPUTS), and its reads of the picture's channel
## (input_channel) turned into reads of the picture. Other channels it reads
## become image params (black until one is picked).
static func to_effect_gdshader(st: Dictionary, include_dir: String) -> String:
	var lines := _header(st, analyze(st, true))
	var code := source_code(st)
	var input := input_channel(st)
	lines.append("shader_type canvas_item;")
	lines.append('#include "%s"' % include_dir.path_join(EFFECT_PRELUDE_FILE))
	lines.append("")
	lines.append(EFFECT_INPUTS)
	for ch in _channels_used(code):
		if ch != input:
			lines.append("uniform sampler2D iChannel%d : repeat_enable, filter_linear;" % ch)
	lines.append("")
	lines.append(_read_picture(code, input))
	lines.append("")
	lines.append(EFFECT_MAIN)
	return "\n".join(lines) + "\n"


## `code` with its reads of iChannel`ch` made reads of the picture
## (EFFECT_INPUTS' _st_input functions, which turn it the Shadertoy way up).
static func _read_picture(code: String, ch: int) -> String:
	if ch < 0:
		return code
	var c := "iChannel%d" % ch
	for pair in [["\\btexture(?:2D)?\\s*\\(\\s*%s\\s*,\\s*" % c, "_st_input("],
			["\\btextureLod\\s*\\(\\s*%s\\s*,\\s*" % c, "_st_input_lod("],
			["\\btexelFetch\\s*\\(\\s*%s\\s*,\\s*" % c, "_st_input_fetch("],
			["\\biChannelResolution\\s*\\[\\s*%d\\s*\\]" % ch, "iResolution"],
			["\\b%s\\b" % c, "input_tex"]]:
		code = RegEx.create_from_string(pair[0]).sub(code, pair[1], true)
	return code


## The comment lines a converted shader starts with: its name, author, page
## and licence, its title for pickers, its id and what analyze() found.
static func _header(st: Dictionary, a: Dictionary) -> Array:
	var lines: Array = []
	var name := String(st.get("name", "Shadertoy shader"))
	lines.append("// %s%s" % [name, " by " + st.author if st.get("author", "") != "" else ""])
	if st.get("url", "") != "":
		lines.append("// " + st.url)
		lines.append("// Licence: the author's. Shadertoy's default is CC BY-NC-SA 3.0 (credit")
		lines.append("// them, no commercial use, share alike) unless the page says otherwise.")
	lines.append("// @title " + name)
	lines.append("// @shadertoy " + String(st.get("id", "")))
	for w in a.warnings:
		lines.append("// Note: " + w)
	for e in a.edits:
		lines.append("// Needs editing: " + e)
	for e in a.errors:
		lines.append("// Won't run: " + e)
	return lines


## A file name for the shader: its name in snake case plus the id, so two
## shaders called "Tunnel" don't overwrite each other.
static func file_stem(st: Dictionary) -> String:
	var name := String(st.get("name", "")).to_lower()
	name = RegEx.create_from_string("[^a-z0-9]+").sub(name, "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	name = name.substr(0, 40).trim_suffix("_")
	var id := String(st.get("id", ""))
	return "%s_%s" % [name, id] if name != "" else id


static func _pass(st: Dictionary, type: String) -> Dictionary:
	for p in st.get("passes", []):
		if p.type == type:
			return p
	return {}
