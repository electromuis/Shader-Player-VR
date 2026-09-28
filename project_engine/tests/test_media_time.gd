extends RefCounted

## Shader time follows the video (MediaTime, media_time.gdshaderinc): what
## the loader makes of each kind of shader. That they compile and stop
## while paused is checked by rendering: tools/cloud/checks/drive_shader_time.gd.

const TMP_DIR := "user://test_media_time_tmp"
const INCLUDE := "#include \"res://player/visualizer/media_time.gdshaderinc\""


static func _write(name: String, code: String) -> String:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(code)
	f.close()
	return path


static func test_the_global_exists(tc: TestCase) -> void:
	tc.assert_true(ProjectSettings.has_setting("shader_globals/vj_time"), "project.godot declares vj_time")
	MediaTime.set_seconds(12.5)
	tc.assert_eq(MediaTime.seconds, 12.5)
	tc.assert_true(MediaTime.engine_seconds() >= 0.0, "engine seconds")


static func test_preludes_include_it(tc: TestCase) -> void:
	for p in [VisualizerShaders.PRELUDE, VisualizerShaders.EFFECT_PRELUDE, ScreenGeometry.DISPLAY_INCLUDE]:
		tc.assert_has(FileAccess.get_file_as_string(p), INCLUDE)
	var inc := FileAccess.get_file_as_string(VisualizerShaders.MEDIA_TIME)
	tc.assert_has(inc, "#ifndef VJ_FREE_TIME")
	tc.assert_has(inc, "#define TIME vj_time")


static func test_builtins_stay_cached(tc: TestCase) -> void:
	# A built-in with a prelude is Godot's own resource, as before.
	for key in [VisualizerShaders.builtins()[0].key, VisualizerShaders.GLOW]:
		tc.assert_true(VisualizerShaders.load_shader(key) == load(key), "%s is the cached resource" % key)


static func test_custom_shaders_get_media_time(tc: TestCase) -> void:
	# A .gdshader with no prelude: the include goes right after shader_type.
	var plain := _write("plain.gdshader", "// @title Plain\nshader_type canvas_item;\nvoid fragment() { COLOR = vec4(fract(TIME)); }\n")
	var code := VisualizerShaders.load_shader(plain).code
	tc.assert_true(code.begins_with("// @title Plain\nshader_type canvas_item;\n" + INCLUDE + "\nvoid fragment()"), code)
	# Shadertoy code: before the prelude (whose own include then does nothing).
	var toy := _write("toy.glsl", "void mainImage(out vec4 c, in vec2 f) { c = vec4(fract(iTime)); }\n")
	code = VisualizerShaders.load_shader(toy).code
	tc.assert_true(code.begins_with("shader_type canvas_item;\n" + INCLUDE + "\n#include \"%s\"" % VisualizerShaders.PRELUDE), code)
	# An effect of the user's.
	var fx := _write("fx.gdshader", "shader_type canvas_item;\n#include \"%s\"\nvoid fragment() { COLOR = texture(input_tex, UV) * fract(TIME); }\n" % VisualizerShaders.EFFECT_PRELUDE)
	code = VisualizerShaders.load_shader(fx).code
	tc.assert_eq(code.count(INCLUDE), 1, "one include of its own")
	tc.assert_false(code.contains("VJ_FREE_TIME"), "not free")
	DirAccess.remove_absolute(plain)
	DirAccess.remove_absolute(toy)
	DirAccess.remove_absolute(fx)


static func test_free_time_opts_out(tc: TestCase) -> void:
	tc.assert_true(VisualizerShaders.is_free_time("// @free_time\nshader_type canvas_item;"), "at a line's start")
	tc.assert_true(VisualizerShaders.is_free_time("shader_type canvas_item;\n  //  @free_time  keeps running\n"), "spaced")
	tc.assert_false(VisualizerShaders.is_free_time("// a shader with a `// @free_time` line keeps TIME"), "a mention in a comment")
	tc.assert_false(VisualizerShaders.is_free_time(FileAccess.get_file_as_string(VisualizerShaders.MEDIA_TIME)), "the include's own comments")
	var free := _write("free.gdshader", "shader_type canvas_item;\n// @free_time\nvoid fragment() { COLOR = vec4(fract(TIME)); }\n")
	var code := VisualizerShaders.load_shader(free).code
	tc.assert_true(code.begins_with("shader_type canvas_item;\n#define VJ_FREE_TIME\n"), code)
	tc.assert_false(code.contains(INCLUDE), "no include")
	# Shadertoy code with the header: defined before the prelude's include.
	var toy := _write("free.glsl", "// @free_time\nvoid mainImage(out vec4 c, in vec2 f) { c = vec4(fract(iTime)); }\n")
	code = VisualizerShaders.load_shader(toy).code
	tc.assert_true(code.find("#define VJ_FREE_TIME") < code.find(VisualizerShaders.PRELUDE), "defined before the prelude")
	DirAccess.remove_absolute(free)
	DirAccess.remove_absolute(toy)
	# Camera effects: CameraFx gives the effect engine seconds instead.
	var fx := CameraFx.new()
	var key := "builtin:hue_cycle"
	fx.show_effect(key, {}, 1.0)
	MediaTime.set_seconds(3.0)
	fx._process(0.0)
	tc.assert_eq(fx.effect.time, 3.0, "a camera effect's iTime is the video's")
	fx.free()
