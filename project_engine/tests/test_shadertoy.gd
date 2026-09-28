extends RefCounted

## Shadertoy shaders as layers: reading the site's JSON (ShadertoyShader),
## what runs and what's lost, the fixes for Godot's shading language, the
## .gdshader it writes, the collection (ShadertoyLibrary) and the receiver
## the Chrome extension posts to (ShadertoyReceiver). Whether the result
## compiles is checked by rendering: tools/cloud/checks/shot_shadertoy.gd.

const TMP_DIR := "user://test_shadertoy_tmp"

const SHADER := {
	"ver": "0.1",
	"info": {"id": "AbC123", "name": "Beat Tunnel!", "username": "someone", "description": "d",
		"tags": ["tunnel", "music"], "likes": 7, "viewed": 100, "date": "1411752810"},
	"renderpass": [
		{"type": "common", "name": "Common", "inputs": [], "code": "float twice(float x) { return x * 2.0; }"},
		{"type": "image", "name": "Image", "code": "void mainImage(out vec4 o, in vec2 u) { o = vec4(twice(iTime)); }",
			"inputs": [
				{"channel": 1, "type": "musicstream", "filepath": "https://soundcloud.com/x"},
				{"channel": 2, "type": "texture", "filepath": "/media/a/n.png"},
				{"channel": 3, "type": "video", "filepath": "/media/a/v.webm"},
			]},
	],
}


static func test_parse_formats(tc: TestCase) -> void:
	var st := ShadertoyShader.parse(SHADER)
	tc.assert_eq(st.id, "AbC123")
	tc.assert_eq(st.name, "Beat Tunnel!")
	tc.assert_eq(st.author, "someone")
	tc.assert_eq(st.url, "https://www.shadertoy.com/view/AbC123")
	tc.assert_eq(st.passes.size(), 2)
	tc.assert_eq(st.passes[1].inputs[0], {"channel": 1, "type": "musicstream", "src": "https://soundcloud.com/x"})
	tc.assert_eq(ShadertoyShader.parse({"Shader": SHADER}).id, "AbC123", "the API's wrapper")
	tc.assert_eq(ShadertoyShader.parse([SHADER]).id, "AbC123", "the site's list")
	tc.assert_eq(ShadertoyShader.parse(JSON.stringify(SHADER)).id, "AbC123", "text")
	tc.assert_eq(ShadertoyShader.parse({"nope": 1}), {})
	tc.assert_eq(ShadertoyShader.parse("not json"), {})
	var pasted := ShadertoyShader.parse(ShadertoyShader.from_code("void mainImage(out vec4 o, in vec2 u) { o = vec4(1.0); }", "Mine"))
	tc.assert_true(pasted.id.begins_with("local_"))
	tc.assert_eq(pasted.name, "Mine")
	tc.assert_eq(pasted.url, "", "pasted code has no page")
	tc.assert_eq(ShadertoyShader.file_stem(st), "beat_tunnel_AbC123")


static func test_analyze(tc: TestCase) -> void:
	var a := ShadertoyShader.analyze(ShadertoyShader.parse(SHADER))
	tc.assert_true(a.ok)
	tc.assert_eq(a.channels, {1: "audio", 3: "video"})
	tc.assert_eq(a.warnings.size(), 2, "the texture and the video")
	tc.assert_has(" ".join(a.warnings), "iChannel2 (texture)")
	var multi: Dictionary = SHADER.duplicate(true)
	multi.renderpass.append({"type": "buffer", "name": "Buffer A", "inputs": [], "code": ""})
	multi.renderpass.append({"type": "sound", "name": "Sound", "inputs": [], "code": ""})
	a = ShadertoyShader.analyze(ShadertoyShader.parse(multi))
	tc.assert_false(a.ok)
	tc.assert_has(a.errors[0], "Buffer A")
	tc.assert_has(" ".join(a.warnings), "sound output")
	var no_image := {"info": {"id": "x"}, "renderpass": [{"type": "buffer", "code": ""}]}
	tc.assert_has(" ".join(ShadertoyShader.analyze(ShadertoyShader.parse(no_image)).errors), "no Image pass")
	var mouse := ShadertoyShader.parse(ShadertoyShader.from_code("void mainImage(out vec4 o, in vec2 u) { o = iMouse; }"))
	tc.assert_has(" ".join(ShadertoyShader.analyze(mouse).warnings), "iMouse")


static func test_fix_matrices(tc: TestCase) -> void:
	var code := ShadertoyShader.fix_code(
			"const mat2 m = mat2(1.6, 1.2, -1.2, 1.6);\n"
			+ "mat3 n = mat3(1, 0, 0, 0, 1, 0, 0, 0, 1);\n"
			+ "mat2 r(float c, float s) { return mat2(c, -s, s, c); }\n"
			+ "mat2 k(vec2 a) { return mat2(a, -a.y, a.x) * mat2(vec2(1.0), vec2(0.0)) * mat2(1.0); }\n"
			+ "mat2 q(float t) { return mat2(cos(t), sin(mat2(t, 0, 0, t)[0].x), 0.0, 1.0); }\n")
	tc.assert_has(code, "const mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));", "numbers become columns, in constants too")
	tc.assert_has(code, "mat3(vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1))")
	tc.assert_has(code, "return mat2(vec2(c, -s), vec2(s, c));")
	tc.assert_has(code, "_st_mat2(a, -a.y, a.x)", "vec2 + two numbers goes through the helper")
	tc.assert_has(code, "mat2 _st_mat2(vec2 a, float b, float c)", "which is defined")
	tc.assert_has(code, "mat2(vec2(1.0), vec2(0.0)) * mat2(1.0)", "columns and a single value stay")
	tc.assert_has(code, "mat2(vec2(cos(t), sin(mat2(vec2(t, 0), vec2(0, t))[0].x)), vec2(0.0, 1.0))", "nested")


static func test_fix_globals(tc: TestCase) -> void:
	var src := "vec3 sun = normalize(vec3(1.0));\n" \
			+ "float t;\nfloat speed = 2.0, phase;\n" \
			+ "#define T2 (t * 2.0)\n" \
			+ "float wave() { return sin(t * speed) + T2; }\n" \
			+ "float twice(float x) { return x * 2.0 + wave(); }\n" \
			+ "void mainImage(out vec4 o, in vec2 u) {\n\tt = iTime;\n\tphase += 1.0;\n\to = vec4(twice(sun.x) + phase);\n}\n"
	tc.assert_eq(ShadertoyShader.mutable_globals(src), ["sun", "t", "speed", "phase"], "every non-const global")
	var code := ShadertoyShader.fix_code(src)
	tc.assert_has(code, "const vec3 sun = normalize", "never assigned: const")
	tc.assert_has(code, "struct _StGlobals {\n\tfloat t;\n\tfloat speed;\n\tfloat phase;\n};")
	tc.assert_has(code, "float wave(inout _StGlobals _g) { return sin(_g.t * _g.speed) + T2; }")
	tc.assert_has(code, "float twice(inout _StGlobals _g, float x) { return x * 2.0 + wave(_g); }")
	tc.assert_has(code, "#define T2 (_g.t * 2.0)", "macros see them too")
	tc.assert_has(code, "_StGlobals _g;\n\t_g.t = 0.0;\n\t_g.speed = 2.0;\n\t_g.phase = 0.0;", "mainImage starts them, 0 without a value")
	tc.assert_has(code, "_g.t = iTime;")
	tc.assert_has(code, "twice(_g, sun.x) + _g.phase")
	tc.assert_eq(ShadertoyShader.mutable_globals(code), [], "none left")
	# A function with its own `t`: moving them would be wrong, so they stay.
	var shadowed := "float t;\nfloat f(float t) { return t; }\nvoid mainImage(out vec4 o, in vec2 u) { t = 1.0; o = vec4(f(t)); }\n"
	tc.assert_eq(ShadertoyShader.mutable_globals(ShadertoyShader.fix_code(shadowed)), ["t"])
	var arr := "float h[4];\nvoid mainImage(out vec4 o, in vec2 u) { h[0] = 1.0; o = vec4(h[0]); }\n"
	tc.assert_eq(ShadertoyShader.mutable_globals(ShadertoyShader.fix_code(arr)), ["h"], "arrays stay")


static func test_fix_statements(tc: TestCase) -> void:
	var code := ShadertoyShader.fix_code(
			"#version 300 es\nprecision highp float;\n"
			+ "float sample = 1.0;\n"
			+ "vec2 f(vec4 v) { float a = 1.0, b = 2.0; v.x = a, v.y = b; for (int i = 0, j = 1; i < 2; i++) {} return v.xy; }\n"
			+ "vec2 g() { int i = 2; int j = 3; ivec2 c = ivec2(.7, 0); return vec2(i, j + 1) + vec2(1, 2) + vec2(c); }\n"
			+ "float h() { return iChannelTime[0]; }\n")
	tc.assert_false(code.contains("#version") or code.contains("precision"), "version / precision lines go")
	tc.assert_has(code, "float sample_st = 1.0;", "Godot's keywords renamed")
	tc.assert_has(code, "float a = 1.0, b = 2.0;", "declarations keep their commas")
	tc.assert_has(code, "v.x = a; v.y = b;", "assignments get split")
	tc.assert_has(code, "for (int i = 0, j = 1; i < 2; i++)")
	tc.assert_has(code, "vec2(float(i), float(j + 1)) + vec2(1, 2)", "int variables in a vec, not literals")
	tc.assert_has(code, "ivec2(int(.7), 0)")
	tc.assert_has(code, "#define iChannelTime")


static func test_to_gdshader(tc: TestCase) -> void:
	var code := ShadertoyShader.to_gdshader(ShadertoyShader.parse(SHADER), "res://player/visualizer")
	tc.assert_true(code.begins_with("// Beat Tunnel! by someone\n// https://www.shadertoy.com/view/AbC123\n"))
	tc.assert_has(code, "CC BY-NC-SA")
	tc.assert_has(code, "// @shadertoy AbC123")
	tc.assert_has(code, "// @iChannel1 audio\n// @iChannel3 video\nshader_type canvas_item;")
	tc.assert_has(code, "// Note: iChannel2 (texture) isn't available")
	tc.assert_has(code, '#include "res://player/visualizer/shadertoy_prelude.gdshaderinc"')
	tc.assert_true(code.find("float twice") < code.find("void mainImage"), "Common before Image")
	tc.assert_true(code.ends_with('#include "res://player/visualizer/shadertoy_main.gdshaderinc"\n'))
	var hints := VisualizerShaders.parse_hints(code)
	tc.assert_eq(hints.channels, {0: "audio", 1: "audio", 3: "video"}, "the player reads the channel hints")


static func test_library(tc: TestCase) -> void:
	_clear()
	var lib := ShadertoyLibrary.new(TMP_DIR)
	tc.assert_eq(lib.entries(), [])
	var st := lib.add([SHADER], PackedByteArray([1, 2, 3]))
	tc.assert_eq(st.id, "AbC123")
	tc.assert_true(FileAccess.file_exists(TMP_DIR.path_join("beat_tunnel_AbC123.json")))
	tc.assert_eq(FileAccess.get_file_as_bytes(TMP_DIR.path_join("beat_tunnel_AbC123.jpg")), PackedByteArray([1, 2, 3]))
	var renamed: Dictionary = SHADER.duplicate(true)
	renamed.info.name = "Renamed"
	lib.add(JSON.stringify({"Shader": renamed}))
	tc.assert_false(FileAccess.file_exists(TMP_DIR.path_join("beat_tunnel_AbC123.json")), "the old copy goes")
	tc.assert_eq(lib.entries().size(), 1)
	tc.assert_eq(lib.find("AbC123").shader.name, "Renamed")
	tc.assert_eq(lib.find("AbC123").thumbnail, "", "no thumbnail this time")
	lib.add(ShadertoyShader.from_code("void mainImage(out vec4 o, in vec2 u) { o = vec4(1.0); }"))
	tc.assert_eq(lib.entries().size(), 2)
	tc.assert_eq(lib.add({"nope": 1}), {})
	tc.assert_true(lib.remove("AbC123"))
	tc.assert_false(lib.remove("AbC123"))
	tc.assert_eq(lib.entries().size(), 1)
	_clear()


static func test_receiver(tc: TestCase) -> void:
	_clear()
	var rx := ShadertoyReceiver.new()
	rx.library = ShadertoyLibrary.new(TMP_DIR)
	rx.app_name = "Test"
	rx.port = 47811
	var host := {"host": "127.0.0.1:47811"}
	tc.assert_eq(ShadertoyReceiver.parse_request("GET /vj/ping HTTP/1.1\r\nHost: x".to_ascii_buffer()), {}, "headers not all here")
	var req := ShadertoyReceiver.parse_request("POST /vj/shadertoy HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345".to_ascii_buffer())
	tc.assert_eq(req, {}, "body not all here")
	req = ShadertoyReceiver.parse_request("GET /vj/ping HTTP/1.1\r\nHost: 127.0.0.1:47811\r\n\r\n".to_ascii_buffer())
	tc.assert_eq(req.headers, host)
	tc.assert_eq(rx.handle(req), [200, {"app": "Test", "version": ShadertoyReceiver.VERSION}])
	tc.assert_true(rx.last_ping_msec >= 0)
	var bad_origin := {"method": "GET", "path": "/vj/ping", "headers": {"host": host.host, "origin": "https://evil.example"}}
	tc.assert_eq(rx.handle(bad_origin)[0], 403, "web pages can't")
	tc.assert_eq(rx.handle({"method": "GET", "path": "/vj/ping", "headers": {"host": "evil.example:47811"}})[0], 403, "other hosts can't")
	var got: Array = []
	rx.received.connect(func(st): got.append(st.id))
	var body := JSON.stringify({"shader": [SHADER], "thumbnail": Marshalls.raw_to_base64(PackedByteArray([9, 9]))})
	var post := {"method": "POST", "path": "/vj/shadertoy", "body": body.to_utf8_buffer(),
			"headers": {"host": host.host, "origin": "chrome-extension://abc", "content-type": "application/json"}}
	var res := rx.handle(post)
	tc.assert_eq(res[0], 200)
	tc.assert_eq(res[1].id, "AbC123")
	tc.assert_eq(res[1].errors, [])
	tc.assert_eq(res[1].warnings.size(), 2)
	tc.assert_eq(got, ["AbC123"])
	tc.assert_eq(FileAccess.get_file_as_bytes(TMP_DIR.path_join("beat_tunnel_AbC123.jpg")), PackedByteArray([9, 9]))
	post.headers["content-type"] = "text/plain"
	tc.assert_eq(rx.handle(post)[0], 415, "JSON only (a page's form post isn't)")
	post.headers["content-type"] = "application/json"
	post.body = '{"shader": {"x": 1}}'.to_utf8_buffer()
	tc.assert_eq(rx.handle(post)[0], 400)
	tc.assert_eq(rx.handle({"method": "GET", "path": "/", "headers": host})[0], 404)
	rx.free()
	_clear()


static func _clear() -> void:
	if DirAccess.dir_exists_absolute(TMP_DIR):
		for f in DirAccess.get_files_at(TMP_DIR):
			DirAccess.remove_absolute(TMP_DIR.path_join(f))
		DirAccess.remove_absolute(TMP_DIR)
