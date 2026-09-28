class_name Visualizer
extends Node3D

## One shader layer: a sound-reactive shader drawn on its own screen, with
## the layer's effects after it. This node is the layer's mount
## (LayerSettings positions it, as ScreenSettings does the ScreenMount).
## The Stage parents it under the ScreenMount, via an anchor that carries the
## main screen's script motion, so the layer moves with the screen and its
## settings offset it from there. The Screen child sits where the default
## main screen does, so default settings put it just in front of the video: see-through things draw
## back to front by depth, and each layer is nudged ORDER_STEP × (its stack
## position + 1) toward the viewer (set_order) so equal placements still
## stack in list order. Distance moves it behind.
##
## Locked (set_locked), the layer ignores its mount and tracks the main
## screen's transform every frame, centred on it at its own size and moved
## `distance` back along the screen's facing, so it follows the screen's
## sliders and any script animation.
##
## The shader renders at its `// @resolution` hint, or
## VisualizerShaders.DEFAULT_RESOLUTION (half of full HD: Shadertoy-style
## effects are fragment heavy, and VR renders at 90 Hz for two eyes),
## times the layer's resolution setting (set_resolution_scale). The
## screen takes the resolution's shape, inside the usual 16:9 box.
##
## A shader tagged `// @iChannelN video` reads the playing video's frame
## (bind_video). Its layer then takes the video's shape instead, like the
## main screen does (set_video_layout): it renders at the frame's aspect
## (at the hinted or default height) and a stereo video's output is split
## per eye as a flat stereo screen, so locked at size 1 it lines up with
## the video.
## One tagged `// @iChannelN image` reads the image its `iChannelN` param
## names (a path, see ImageLibrary), as do its other texture params.
## The source VisualizerShaders.VIDEO is the video itself, with no shader:
## the layer's Screen shows it as the main screen does (the same source
## layout, swap and shape, the effects per eye), and its effects render at
## the main screen's base size times the layer's resolution. So a video
## layer locked at size 1 is a copy of the main screen, and at a low
## resolution with a Blur effect it's a cheap soft glow.
## A 3D shader (one with mainVR, see VisualizerShaders.is_vr_code) has no
## render pass: the Screen runs it on its mesh per eye (Screen.set_vr_source),
## so its uniforms (params, audio, iChannels, iResolution) go on the
## Screen's display material, and its effects don't apply. The
## `@resolution` still sets the screen's shape and iResolution.
## The AudioAnalyzer is shared, so the Stage runs it while any layer
## is_running(). So is the BeatClock, whose grid sets the beat uniforms.
##
## A script's layers are the same node, spawned from prefabs/layer.tscn
## (`at_origin`): the quad then sits at this node's own transform, like a
## screen prefab's, and the runner sets it up through configure().

const SCREEN_SCENE := preload("res://player/prefabs/screen.tscn")
const _AUDIO_RES := Vector3(AudioAnalyzer.BINS, 2.0, 1.0)
const ORDER_STEP := 0.01  # metres

## Put the quad at this node's origin at scale 1 (scripted layers) instead
## of where the default main screen sits.
@export var at_origin: bool = false

var _screen: Screen
var _material: ShaderMaterial  # the shader's; the Screen's display material when _vr
var _vr: bool = false  # a 3D shader (mainVR), run by the Screen's display shader
var _shader_key: String = ""
var _hints: Dictionary = {}  # VisualizerShaders.parse_hints() of the shader
var _param_specs: Array = []  # the shader's hinted uniforms (VisualizerShaders.parse_hints)
var _audio: AudioAnalyzer
var _beats: BeatClock
var _video: Texture2D
var _video_projection: String = "flat"  # the main screen's source layout
var _video_swap: bool = false
var _video_stereo: int = VideoProjection.Stereo.MONO
var _video_source: bool = false  # the source is VisualizerShaders.VIDEO
var _video_aspect: float = 0.0  # full frame width / height; 0 = not known yet
var _home: Transform3D  # the Screen child's transform while unlocked
var _follow: Node3D
var _locked: bool = false
var _locked_size: float = 1.0
var _locked_distance: float = 0.0
var _nudge: float = ORDER_STEP  # toward the viewer, from the stack position


func _ready() -> void:
	add_to_group(VisualizerShaders.RELOAD_GROUP)
	_screen = SCREEN_SCENE.instantiate()
	_screen.name = "Screen"
	if not at_origin:
		_screen.position = Vector3(DefaultScreen.POSITION[0], DefaultScreen.POSITION[1], DefaultScreen.POSITION[2])
		_screen.scale = Vector3.ONE * DefaultScreen.SCALE
	add_child(_screen)
	_home = _screen.transform
	set_order(0)
	_screen.set_render_size(VisualizerShaders.DEFAULT_RESOLUTION)
	visible = false


func bind_audio(audio: AudioAnalyzer) -> void:
	_audio = audio
	if _screen != null:
		_screen.bind_audio(audio)
	_bind_channels()


func bind_beats(beats: BeatClock) -> void:
	_beats = beats


func bind_video(tex: Texture2D) -> void:
	_video = tex
	if _screen != null:
		_screen.set_video_texture(tex)
	if _video_source:
		_screen.set_source_texture(tex)
	_bind_channels()


## The main screen's projection key and swap, and the video's full frame
## aspect (0 = none loaded), for a video source and shaders that read the
## video.
func set_video_layout(projection: String, frame_aspect: float, swap: bool = false) -> void:
	if projection == _video_projection and swap == _video_swap 			and is_equal_approx(frame_aspect, _video_aspect):
		return
	_video_projection = projection
	_video_swap = swap
	_video_stereo = VideoProjection.stereo_of(projection)
	_video_aspect = frame_aspect
	if _video_source:
		_configure_video_source()
	elif _material != null and uses_video():
		_configure_screen()


## The loaded shader samples the video.
func uses_video() -> bool:
	return _hints.get("channels", {}).values().has("video")


## A shader is loaded (or a vertex effect follows the music), so the layer
## needs live audio.
func is_running() -> bool:
	return _material != null or _screen.uses_audio()


## Switch to the shader at `key` (a VisualizerShaders key, or VIDEO for the
## video itself); "" hides the layer. Re-selecting the current key does
## nothing.
func set_shader(key: String) -> void:
	if key == _shader_key:
		return
	_shader_key = key
	if _vr:
		# The display material outlives the shader: drop its values.
		for spec in _param_specs:
			_material.set_shader_parameter(spec.name, null)
	_material = null
	_hints = {}
	_param_specs = []
	_video_source = key == VisualizerShaders.VIDEO
	var shader: Shader = null if _video_source else VisualizerShaders.load_shader(key)
	_vr = shader != null and VisualizerShaders.is_vr_code(shader.code)
	if _video_source:
		_configure_video_source()
	else:
		_screen.set_source_texture(null)
	_screen.set_vr_source(VisualizerShaders.vr_source(shader.code) if _vr else "")
	if shader != null:
		_hints = VisualizerShaders.parse_hints(shader.code)
		_param_specs = _hints.params
		if _vr:
			_material = _screen.get_display_material()
		else:
			_material = ShaderMaterial.new()
			_material.shader = shader
		_configure_screen()
	elif key != "" and not _video_source:
		push_warning("Visualizer: can't load shader %s" % key)
	# A null material also stops the Screen's render viewport (a 3D shader
	# has none: it runs on the mesh).
	_screen.set_shader_material(null if _vr else _material)
	visible = _material != null or _video_source


## Load the layer's shader again (VisualizerShaders.reload_all), keeping the
## values of params it still has. Its Screen reloads its own effects.
func reload_shaders() -> void:
	if _shader_key == "" or _video_source:
		return
	var old := {}
	if _material != null:
		for spec in _param_specs:
			old[spec.name] = _material.get_shader_parameter(spec.name)
	var key := _shader_key
	_shader_key = ""
	set_shader(key)
	if _material == null:
		return
	for spec in _param_specs:
		if old.get(spec.name) != null:
			_material.set_shader_parameter(spec.name, ImageLibrary.reloaded(old[spec.name]))
	_bind_channels()


func get_shader_key() -> String:
	return _shader_key


## Values for the shader's hinted uniforms; ones not in `params` go back
## to the shader's defaults.
func set_params(params: Dictionary) -> void:
	if _material == null:
		return
	for spec in _param_specs:
		_material.set_shader_parameter(spec.name, ImageLibrary.value(params.get(spec.name, spec.default)))
	_bind_channels()


func set_effects(effects: Array) -> void:
	_screen.set_effects(effects)


## A scripted layer's `config` from the runner, shader keys already turned
## into files: shader, params, effects, vertex_effects, surface, opacity,
## blend, resolution (and earlier scripts' curvature / vertical_curvature). `_mat`
## is unused (the layer builds its own material, since the shader may be
## Shadertoy code).
func configure(cfg: Dictionary, _mat: ShaderMaterial) -> void:
	set_shader(String(cfg.get("shader", "")))
	var params = cfg.get("params", {})
	set_params(params if typeof(params) == TYPE_DICTIONARY else {})
	var effects = cfg.get("effects", [])
	set_effects(effects if typeof(effects) == TYPE_ARRAY else [])
	set_opacity(float(cfg.get("opacity", 1.0)))
	set_blend(String(cfg.get("blend", "normal")))
	var vfx = cfg.get("vertex_effects", [])
	set_vertex_effects(vfx if typeof(vfx) == TYPE_ARRAY else [])
	if typeof(cfg.get("surface")) == TYPE_DICTIONARY:
		set_surface(cfg["surface"])
	else:
		set_surface(ScreenGeometry.default_surface())
		_screen.set_curvature(float(cfg.get("curvature", 0.0)))
		_screen.set_vertical_curvature(float(cfg.get("vertical_curvature", 0.0)))
	set_resolution_scale(float(cfg.get("resolution", 1.0)))


## Target for `shader_param` tracks (`<id>.<slot>`): "display", "shape",
## "effect<N>" and "vertex<N>" go to the layer's screen (see
## Screen.set_material_param), any other slot (e.g. "layer") to the layer's
## shader.
func set_material_param(slot: String, param: String, value: Variant) -> void:
	if slot in ["display", "shape"] or slot.begins_with("effect") or slot.begins_with("vertex"):
		_screen.set_material_param(slot, param, value)
	elif _material != null:
		_material.set_shader_parameter(param, ImageLibrary.value(value))
		if param.begins_with("iChannel"):
			_bind_channels()


## Stack position (0 = first): how far the layer is nudged toward the
## viewer, so later layers sort in front at equal placement.
func set_order(index: int) -> void:
	_nudge = ORDER_STEP * (index + 1)
	if not _locked:
		_place_home()


## Where the picture sits (see Screen.set_surface).
func set_surface(surface: Dictionary) -> void:
	_screen.set_surface(surface)


func set_vertex_effects(effects: Array) -> void:
	_screen.set_vertex_effects(effects)


func set_opacity(amount: float) -> void:
	_screen.set_opacity(amount)


## One of Screen.BLENDS (see Screen.set_blend).
func set_blend(mode: String) -> void:
	_screen.set_blend(mode)


## Multiplier on the shader's (and its effects') render size.
func set_resolution_scale(scale: float) -> void:
	_screen.set_resolution_scale(scale)
	if _material != null:
		var res := _screen.render_viewport.size
		_material.set_shader_parameter("iResolution", Vector3(res.x, res.y, 1.0))


## The screen a locked layer centres on (the main screen; re-set when it
## is respawned).
func set_follow_target(node: Node3D) -> void:
	_follow = node


## Lock onto the follow target at `size` times its size, `distance`
## metres behind it, or go back to the mount's placement.
func set_locked(on: bool, size: float, distance: float = 0.0) -> void:
	_locked = on
	_locked_size = size
	_locked_distance = distance
	if not on:
		_place_home()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _locked:
		_track_follow_target()
	if _material == null:
		return  # a video layer: no shader to feed
	if _beats != null:
		var u := _beats.uniforms()
		for k in u:
			_material.set_shader_parameter(k, u[k])
	if _audio == null:
		return
	_material.set_shader_parameter("audio_level", _audio.level)
	_material.set_shader_parameter("audio_bass", _audio.bass)
	_material.set_shader_parameter("audio_mid", _audio.mid)
	_material.set_shader_parameter("audio_high", _audio.high)


## Render size, shape and stereo split for the loaded shader.
func _configure_screen() -> void:
	var video := uses_video()
	var aspect := 16.0 / 9.0
	if video and _video_aspect > 0.0:
		aspect = _video_aspect
	var res: Vector2i = _hints.resolution
	if res == Vector2i.ZERO:
		res = VisualizerShaders.DEFAULT_RESOLUTION
		if video:
			res.x = 0
	if res.x == 0:
		res.x = roundi(res.y * aspect)
	_screen.set_render_size(res)
	res = _screen.render_viewport.size  # after clamping
	_screen.configure({"fit_aspect": true}, null)
	_screen.set_source_layout(_flat_projection() if video else "flat")
	_screen.set_content_aspect(aspect if video else float(res.x) / res.y)
	_material.set_shader_parameter("iResolution", Vector3(res.x, res.y, 1.0))
	_material.set_shader_parameter("video_stereo", _video_stereo if video else 0)
	_bind_channels()


## The video as the Screen's source, laid out like the main screen, at the
## main screen's base render size (before the resolution scale).
func _configure_video_source() -> void:
	_screen.set_render_scale(1.0)
	_screen.configure({"fit_aspect": true}, null)
	_screen.set_source_layout(_video_projection)
	_screen.set_swap_eyes(_video_swap)
	if _video_aspect > 0.0:
		_screen.set_content_aspect(_video_aspect)
	_screen.set_source_texture(_video)


## Point each iChannel at its tagged source (unbound when not available;
## an image channel keeps the texture its param set).
func _bind_channels() -> void:
	if _material == null:
		return
	var sizes := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var channels: Dictionary = _hints.get("channels", {})
	for i in 4:
		var tex: Texture2D = null
		match channels.get(i, ""):
			"image":
				tex = _material.get_shader_parameter("iChannel%d" % i)
				if tex != null:
					sizes[i] = Vector3(tex.get_width(), tex.get_height(), 1.0)
			"audio":
				tex = _audio.texture if _audio != null else null
				sizes[i] = _AUDIO_RES
			"video":
				tex = _video
				if _video != null:
					sizes[i] = Vector3(_video.get_width(), _video.get_height(), 1.0)
		_material.set_shader_parameter("iChannel%d" % i, tex)
	_material.set_shader_parameter("iChannelResolution", sizes)


## The flat projection with the video's stereo layout.
func _flat_projection() -> String:
	match _video_stereo:
		VideoProjection.Stereo.SBS:
			return "flat_sbs"
		VideoProjection.Stereo.TB:
			return "flat_tb"
	return "flat"


## Unlocked placement: where the mount puts it, nudged toward the viewer.
func _place_home() -> void:
	if _screen == null:
		return
	var t := _home
	t.origin.z += _nudge
	_screen.transform = t


func _track_follow_target() -> void:
	if not is_instance_valid(_follow) or not _follow.is_inside_tree():
		return
	var t := _follow.global_transform
	t.origin += t.basis.z.normalized() * (_nudge - _locked_distance)
	t.basis = t.basis * Basis.from_scale(Vector3.ONE * _locked_size)
	_screen.global_transform = t
