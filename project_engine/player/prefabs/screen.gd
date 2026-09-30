class_name Screen
extends Node3D

## Scripted VJ screen. Runs an artist-supplied shader over a video texture
## inside a SubViewport at reduced resolution, then samples the result on a
## 3D quad. Expensive per-fragment work (e.g. glow blurs) is done at a
## fraction of the visible pixel count; the display quad is a cheap
## unshaded blit with alpha.
##
## Data flow:
##   VideoBridge viewport texture
##          |
##          v  set_source_texture()  ->  shader uniform `screen_tex`
##   Canvas (ColorRect + artist ShaderMaterial) in RenderViewport
##          |
##          v  ViewportTexture
##   Effect chain (set_effects): one SubViewport pass per effect shader,
##   each reading the previous output as `input_tex` (an effect that mixes
##   or blends gets an EffectBlend pass after it); for stereo
##   projections, one chain per eye. A chain starts with a chain_copy pass
##   (the eye, averaged down to the render size)
##          |
##          v
##   Mesh (display shader: stereo eye split, and in its vertex() the
##   vertex effects and the surface; see ScreenGeometry)
##
## Without an artist shader (the player's default screen for plain videos)
## the RenderViewport is skipped and the display (or the first effect)
## samples the video texture directly. Effect passes run at the
## RenderViewport's size, except from the first effect that draws past the
## picture's edge (a `@reach`, see VisualizerShaders.reach_of): a
## chain_copy pass before it puts the picture in a transparent margin as
## wide as that effect and the ones after it reach (summed, at their
## current params; none at infinity, where the picture fills its arc), and
## the passes from there and the flat quad (_pad_scale) grow by it, so the
## picture keeps its size and nothing is cut off. Each pass is told where
## the unpadded picture sits in it (`picture_rect`), and past a Rounded
## corners effect its outline's shape (`picture_shape`).
##
## Passes that read only a VideoBridge's frame (no artist shader, and no
## effect that animates by itself, VisualizerShaders.is_animated) render on
## demand like the bridge: when it redraws the frame (its redraw_serial) or
## the chain changes, not on every display frame. Otherwise they render
## every frame. Screens process after other nodes (PROCESS_PRIORITY), so a
## frame the decoder or a script track changed this frame renders now.
##
## Nothing runs for what can't be seen: an effect at mix 0, switched off
## or at params its `@idle` hint says leave the picture as it is
## (VisualizerShaders.is_idle; only with the normal blend) is left out of
## the chain, and while the screen is at opacity 0 or hidden (_showing)
## its artist pass and effect passes stop and its mesh isn't drawn.
##
## An effect that declares `prepass_tex` (VisualizerShaders.has_prepass) gets
## a prepass: the same shader with `prepass` on, at `prepass_scale` of the
## pass's size, whose output it reads as `prepass_tex`. Heavy, soft work
## (a glow's halo) goes there, so only the sharp parts run at full size.
##
## The source layout (a VideoProjection key: how the frame is read, i.e.
## its stereo split) is separate from the surface (where the picture sits:
## set_surface, set_vertex_effects). A 180°/360° video is a Dome at infinity:
## centred on the camera, taking only this node's rotation (so tilt and yaw
## still orient the video, but mount size/distance can't shrink it around
## the viewer).
##
## A 3D layer shader (one with mainVR, set_vr_source) skips all of that:
## its code runs in the display shader itself, per eye on the mesh (see
## screen_display.gdshaderinc), with no artist pass or effect chain. Its
## uniforms are then the display material's (get_display_material).

const _SOURCE_TEX_UNIFORM := "screen_tex"
const _BASE_RENDER_RES := Vector2i(1920, 1080)
const _COPY_SHADER := preload("res://player/prefabs/chain_copy.gdshader")
const EffectBlend := preload("res://player/visualizer/effect_blend.gd")
const _QUAD_ASPECT := 16.0 / 9.0
const _MESH_HALF := Vector2(16.0, 9.0)  # the quad mesh's half size (screen.tscn)
const _FLAT_CULL_MARGIN := 20.0
const _CURVED_CULL_MARGIN := 16384.0  # curved or moving: can reach far past the quad
## _passes' `effect` for the chain_copy passes.
const _SOURCE_COPY := -1
const _MARGIN_COPY := -2
## How the picture goes over what's behind it (see set_blend and
## screen_display.gdshaderinc's display_blend), in its order.
const BLENDS := ["normal", "add", "black"]
const BLEND_LABELS := {"normal": "Normal", "add": "Add (light)", "black": "Black transparent"}
## After the decoder, the bridge and the script runner (see _update_chain_redraw).
const PROCESS_PRIORITY := 100

## The viewer's home eye (where reset view puts them), in world space:
## surfaces placed around the viewer centre on it. Set by main.gd.
static var viewer_eye := Vector3(0.0, 2.0, 8.0)

@onready var mesh: MeshInstance3D = $Mesh
@onready var render_viewport: SubViewport = $RenderViewport
@onready var canvas: ColorRect = $RenderViewport/Canvas

var _display_material: ShaderMaterial
var _vr_source: String = ""  # a 3D layer shader's code in the display shader (set_vr_source)
var _source_texture: Texture2D  # last-received source; re-applied whenever the material or texture changes
var _video_texture: Texture2D  # the playing video, for effects' `video_tex` (see set_video_texture)
var _projection: String = "flat"  # the source layout
var _swap_eyes: bool = false
## {shader, params, placement} (ScreenGeometry.normalized_surface).
var _surface: Dictionary = ScreenGeometry.default_surface()
## [{shader, params, mix, level}] like the effects, run in order before the
## surface (mix: how far each moves the surface, 0..1; level: its
## EffectSwitch level, multiplying the mix).
var _vertex_effects: Array[Dictionary] = []
var _audio: AudioAnalyzer
var _uses_audio: bool = false  # a vertex effect reads the audio
var _fit_aspect: bool = false
var _frame_aspect: float = 0.0
## set_effects state: per effect, its key, loaded shader (null = none
## picked or missing, skipped) and uniform values.
var _effect_keys: Array[String] = []
var _effect_shaders: Array[Shader] = []
var _effect_params: Array[Dictionary] = []
## Per effect: its mix (0..1) and blend mode (an EffectBlend.MODES index)
## from the entry or a track, and its switch level (0..1, EffectSwitch: an
## `enabled` track), which multiplies the mix.
var _effect_mix: Array[float] = []
var _effect_blend: Array[int] = []
var _effect_level: Array[float] = []
## Built passes: [{material, viewport, effect, prepass, blend, step, count}]
## per eye chain (effect _SOURCE_COPY / _MARGIN_COPY: a chain_copy pass
## starting the chain / adding the margin; prepass: an effect's prepass,
## just before the effect's own pass; blend: the EffectBlend pass after an
## effect that mixes or blends; step of count: its place in a multi-pass
## effect or prepass, -1 of 1 otherwise).
var _passes: Array[Dictionary] = []
## _pass_counts() when the passes were built: a params change that alters
## it rebuilds them.
var _built_counts: Array = []
## No active effect animates by itself (see _chain_serial).
var _chain_static: bool = false
## The input's redraw serial the passes last rendered for; -1 = rendering
## every frame.
var _chain_seen: int = -1
var _base_scale: Vector3 = Vector3.ONE  # the quad's scale before the margin
var _pad_scale: Vector2 = Vector2.ONE  # the quad's growth from the margin
var _chain_holder: Node
var _requested_size: Vector2i  # set_render_size's, before _resolution_scale
var _resolution_scale: float = 1.0
## configure() keys a script set ("effects", "opacity", ...): the viewer's
## screen settings leave those alone (see is_scripted).
var _scripted: Dictionary = {}
var _opacity: float = 1.0
## Whether the passes run and the mesh draws (_showing, applied by
## _update_showing).
var _shown: bool = true


func _ready() -> void:
	add_to_group(VisualizerShaders.RELOAD_GROUP)
	process_priority = PROCESS_PRIORITY
	render_viewport.transparent_bg = true
	render_viewport.disable_3d = true
	_requested_size = render_viewport.size

	_display_material = ShaderMaterial.new()
	mesh.material_override = _display_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild_display_shader()
	_chain_holder = Node.new()
	_chain_holder.name = "Effects"
	add_child(_chain_holder)

	_wire_source_texture()
	_apply_projection()


func _process(_delta: float) -> void:
	_update_showing()
	_update_chain_redraw()
	if _display_material == null:
		return
	if _placement() == ScreenGeometry.Placement.AROUND:
		_display_material.set_shader_parameter("viewer_distance", _viewer_distance())
	if _uses_audio and _audio != null:
		_display_material.set_shader_parameter("vfx_audio",
				Vector4(_audio.level, _audio.bass, _audio.mid, _audio.high))


## The shared analyzer, for vertex effects that follow the music.
func bind_audio(audio: AudioAnalyzer) -> void:
	_audio = audio


## A vertex effect reads the audio, so the analyzer must run.
func uses_audio() -> bool:
	return _uses_audio


func set_shader_material(mat: ShaderMaterial) -> void:
	canvas.material = mat
	_wire_source_texture()


func get_shader_material() -> ShaderMaterial:
	return canvas.material as ShaderMaterial


## Run a 3D layer shader's code (VisualizerShaders.vr_source; "" = none) in
## the display shader, per eye on the mesh. Its uniforms are set on
## get_display_material(); leave the artist material null alongside it.
func set_vr_source(code: String) -> void:
	if code == _vr_source:
		return
	_vr_source = code
	_rebuild_display_shader()


## The mesh's material: a 3D layer shader's uniforms go here.
func get_display_material() -> ShaderMaterial:
	return _display_material


## Wire the source video texture into the artist shader (or straight into
## the display pass when there is none).
## Safe to call in any order relative to set_shader_material() and _ready().
func set_source_texture(tex: Texture2D) -> void:
	_source_texture = tex
	_wire_source_texture()


## The playing video's frame, which effects read as `video_tex` (see
## effect_prelude.gdshaderinc). Without one they get the source texture:
## a screen's source is the video.
func set_video_texture(tex: Texture2D) -> void:
	_video_texture = tex
	for p in _passes:
		p.material.set_shader_parameter("video_tex", _effect_video())
	_chain_changed()


func _effect_video() -> Texture2D:
	return _video_texture if _video_texture != null else _source_texture


func set_render_scale(scale: float) -> void:
	var s := clampf(scale, 0.05, 2.0)
	set_render_size(Vector2i(Vector2(_BASE_RENDER_RES) * s))


## Pixel size of the artist pass and the effect passes, before the
## resolution scale.
func set_render_size(size: Vector2i) -> void:
	_requested_size = size
	_apply_render_size()


## Multiplier on the render size (ScreenSettings.resolution): the user's
## quality / speed trade-off, on top of whatever a script or shader asked for.
func set_resolution_scale(scale: float) -> void:
	scale = clampf(scale, ScreenSettings.RESOLUTION_MIN, ScreenSettings.RESOLUTION_MAX)
	if scale == _resolution_scale:
		return
	_resolution_scale = scale
	_apply_render_size()


func _apply_render_size() -> void:
	var size := Vector2i((Vector2(_requested_size) * _resolution_scale).round())
	size = size.clamp(Vector2i.ONE * 16, Vector2i.ONE * 4096)
	if size == render_viewport.size:
		return
	render_viewport.size = size
	_apply_effect_params()  # resizes the passes


## Effect shaders run in order over the output: [{shader: key, params:
## {uniform: value}, enabled, mix, blend}] (ScreenSettings.effects; one
## switched off keeps its slot and runs nothing; mix and blend: see
## EffectBlend). Changing only params updates the running passes; a
## different list of shaders rebuilds them.
func set_effects(effects: Array) -> void:
	var keys: Array[String] = []
	var params: Array[Dictionary] = []
	var mixes: Array[float] = []
	var blends: Array[int] = []
	for e in effects:
		keys.append(String(e.get("shader", "")) if ScreenSettings.is_enabled(e) else "")
		var p = e.get("params", {})
		# Copies: set_effect_param writes into them.
		params.append(p.duplicate() if typeof(p) == TYPE_DICTIONARY else {})
		mixes.append(EffectBlend.mix_of(e))
		blends.append(EffectBlend.index_of(e.get("blend", "normal")))
	_effect_params = params
	_effect_mix = mixes
	_effect_blend = blends
	if _effect_level.size() != keys.size():
		_effect_level.clear()
		for k in keys:
			_effect_level.append(1.0)
	if keys == _effect_keys:
		_params_changed()
		return
	_effect_keys = keys
	_effect_shaders.clear()
	for k in keys:
		_effect_shaders.append(VisualizerShaders.load_shader(k))
	_wire_source_texture()


## Load the effect and display shaders again (VisualizerShaders.reload_all),
## keeping their params. The artist shader is its layer's to reload.
func reload_shaders() -> void:
	_effect_shaders.clear()
	for k in _effect_keys:
		_effect_shaders.append(VisualizerShaders.load_shader(k))
	_rebuild_display_shader()
	_wire_source_texture()


## One uniform of effect `index` (a `shader_param` track on
## `<id>.effect<N>`), or its `mix`, `blend` or switch level (`enabled`, see
## EffectSwitch; a bool or 0..1).
func set_effect_param(index: int, param: String, value: Variant) -> void:
	if index < 0 or index >= _effect_params.size():
		return
	match param:
		"mix":
			var m := clampf(float(value), 0.0, 1.0)
			if m == _effect_mix[index]:
				return
			_effect_mix[index] = m
		"blend":
			var b := EffectBlend.index_of(value)
			if b == _effect_blend[index]:
				return
			_effect_blend[index] = b
		EffectSwitch.PARAM:
			var l := clampf(float(value), 0.0, 1.0)
			if l == _effect_level[index]:
				return
			_effect_level[index] = l
		_:
			_effect_params[index][param] = value
	_params_changed()


## How much of effect `index` shows (its mix times its switch level).
func effect_amount(index: int) -> float:
	if index < 0 or index >= _effect_mix.size():
		return 0.0
	return _effect_mix[index] * _effect_level[index]


## Whether effect `index` runs: it has a shader, shows at all, and isn't
## idle at its params (a blend other than normal changes the picture even
## when the effect gives it back unchanged).
func _effect_active(index: int) -> bool:
	if _effect_shaders[index] == null or effect_amount(index) <= 0.0:
		return false
	return _effect_blend[index] != 0 or not VisualizerShaders.is_idle(_effect_keys[index],
			_effect_params[index] if index < _effect_params.size() else {})


## Whether effect `index` needs a blend pass after it.
func _effect_blends(index: int) -> bool:
	return _effect_active(index) and (_effect_blend[index] != 0 or effect_amount(index) < 1.0)


## Source layout: a VideoProjection key (not "auto"). Only its stereo split
## matters here; its field of view picks a surface in main.gd.
func set_source_layout(key: String) -> void:
	_projection = key
	_apply_projection()


func get_source_layout() -> String:
	return _projection


## Right eye first (`_RL` files): each eye gets the other half.
func set_swap_eyes(on: bool) -> void:
	_swap_eyes = on
	_set_display_param("swap_eyes", on)


## Where the picture sits: {shader: surface key or built-in name, params,
## placement} (see ScreenGeometry).
func set_surface(surface: Dictionary) -> void:
	var s := ScreenGeometry.normalized_surface(surface)
	if s == _surface:
		return
	var rebuild: bool = s.shader != _surface.shader or s.placement != _surface.placement
	_surface = s
	if rebuild:
		_rebuild_display_shader()
	else:
		_apply_geometry_params()


func get_surface() -> Dictionary:
	return _surface.duplicate(true)


## One param of the surface (a `shader_param` track on `<id>.shape`; not
## `<id>.surface`, which is the artist shader's).
func set_surface_param(param: String, value: Variant) -> void:
	_surface.params[param] = value
	_apply_geometry_params()


## Vertex effects run in order before the surface: [{shader: key, params,
## enabled}] (ScreenSettings.vertex_effects; one switched off keeps its slot
## and moves nothing). Changing only params updates uniforms; a different
## list of shaders builds a new display shader.
func set_vertex_effects(effects: Array) -> void:
	var list: Array[Dictionary] = []
	for e in effects:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var p = e.get("params", {})
		var key := String(e.get("shader", "")) if ScreenSettings.is_enabled(e) else ""
		list.append({"shader": ScreenGeometry.resolve_builtin(key),
				"params": p.duplicate() if typeof(p) == TYPE_DICTIONARY else {},
				"mix": EffectBlend.mix_of(e), "level": 1.0})
	var same := list.size() == _vertex_effects.size()
	for i in mini(list.size(), _vertex_effects.size()):
		same = same and list[i].shader == _vertex_effects[i].shader
	_vertex_effects = list
	if same:
		_apply_geometry_params()
	else:
		_rebuild_display_shader()


## One param of vertex effect `index` (a `shader_param` track on
## `<id>.vertex<N>`), or its `mix` or switch level (`enabled`).
func set_vertex_effect_param(index: int, param: String, value: Variant) -> void:
	if index < 0 or index >= _vertex_effects.size():
		return
	if param == "mix" or param == EffectSwitch.PARAM:
		_vertex_effects[index]["mix" if param == "mix" else "level"] = clampf(float(value), 0.0, 1.0)
		_set_display_param(ScreenGeometry.vertex_prefix(index) + "mix",
				_vertex_effects[index].mix * _vertex_effects[index].level)
		return
	_vertex_effects[index].params[param] = value
	_set_display_param(ScreenGeometry.vertex_prefix(index) + param, value)


## Whether the ray from `from` along `dir` hits the picture (its surface;
## vertex effects ignored). Never at infinity: that surrounds the viewer.
func ray_hit(from: Vector3, dir: Vector3) -> bool:
	if mesh == null or not mesh.is_visible_in_tree():
		return false
	return ScreenGeometry.ray_hits(from, dir, mesh.global_transform, _MESH_HALF,
			_picture_half(), _surface, _viewer_distance())


## Full video frame aspect (width / height). With fit_aspect enabled the
## quad letterboxes/pillarboxes to one eye's aspect inside its 16:9 box.
func set_content_aspect(frame_aspect: float) -> void:
	_frame_aspect = frame_aspect
	_apply_aspect()


## Earlier scripts' bend (`curvature`: 0 = flat, 1 = half-cylinder): the
## Pillow's arc_x (arc_y for set_vertical_curvature), switching to a Pillow.
func set_curvature(amount: float) -> void:
	_set_pillow_arc("arc_x", clampf(amount, 0.0, 1.0) * 180.0)


func set_vertical_curvature(amount: float) -> void:
	_set_pillow_arc("arc_y", clampf(amount, 0.0, 1.0) * 180.0)


func _set_pillow_arc(param: String, degrees: float) -> void:
	if _surface.shader != ScreenGeometry.PILLOW:
		set_surface(ScreenGeometry.default_surface())
	set_surface_param(param, degrees)


## 0..1 fade of the screen.
func set_opacity(amount: float) -> void:
	_opacity = clampf(amount, 0.0, 1.0)
	_set_display_param("opacity", _opacity)
	_update_showing()


## Whether anything of the screen can be seen: not at opacity 0 or hidden
## (out of the tree it counts as shown).
func _showing() -> bool:
	return _opacity > 0.0 and (not is_inside_tree() or is_visible_in_tree())


## Stop the passes and the mesh's drawing while the screen can't be seen
## (the mesh stays visible, for picking and bounds: it's taken off every
## render layer), and start them again when it can.
func _update_showing() -> void:
	var shown := _showing()
	if shown == _shown or render_viewport == null:
		return
	_shown = shown
	mesh.layers = 1 if shown else 0
	_set_artist_update()
	if shown:
		_chain_seen = -1  # every frame until _update_chain_redraw says otherwise
		_set_passes_update(SubViewport.UPDATE_ALWAYS)
	else:
		_set_passes_update(SubViewport.UPDATE_DISABLED)


## The artist pass renders every frame while there is one and the screen
## shows.
func _set_artist_update() -> void:
	var on := get_shader_material() != null and _shown
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## How the picture goes over what's behind it: one of BLENDS (unknown ones
## are normal). "add" adds its light (black adds nothing), "black" makes
## black see-through by alpha = the brightest channel.
func set_blend(mode: String) -> void:
	_set_display_param("display_blend", maxi(BLENDS.find(mode), 0))


## Target for `shader_param` tracks (`<id>.<slot>`). Slot "display" drives
## the display pass (`opacity`, `blend` (a BLENDS name), and earlier scripts' `curvature` /
## `vertical_curvature`), "shape" the surface's params, "effect<N>" the
## Nth effect and "vertex<N>" the Nth vertex effect (from 0); any other
## slot is the artist shader.
func set_material_param(slot: String, param: String, value: Variant) -> void:
	if slot == "shape":
		set_surface_param(param, value)
		return
	if slot.begins_with("vertex") and slot.substr(6).is_valid_int():
		set_vertex_effect_param(int(slot.substr(6)), param, value)
		return
	if slot == "display":
		match param:
			"curvature": set_curvature(float(value))
			"vertical_curvature": set_vertical_curvature(float(value))
			"opacity": set_opacity(float(value))
			"blend": set_blend(String(value))
		return
	if slot.begins_with("effect") and slot.substr(6).is_valid_int():
		set_effect_param(int(slot.substr(6)), param, value)
		return
	var mat := get_shader_material()
	if mat != null:
		mat.set_shader_parameter(param, ImageLibrary.value(value))


## Called by the runner with the object's `config` block.
## Recognised keys: render_scale (float), fit_aspect (bool), opacity
## (float), blend (a BLENDS name), surface ({shader, params, placement}, see set_surface),
## effects and vertex_effects ([{shader: path, params}], see set_effects /
## set_vertex_effects), and earlier scripts' curvature / vertical_curvature
## (a Pillow's arcs). Shader is supplied via `mat`, with its shader_params
## already baked in by the runner.
func configure(cfg: Dictionary, mat: ShaderMaterial) -> void:
	if mat != null:
		set_shader_material(mat)
	if cfg.has("render_scale"):
		set_render_scale(float(cfg["render_scale"]))
	if cfg.has("fit_aspect"):
		_fit_aspect = bool(cfg["fit_aspect"])
		_apply_aspect()
	if typeof(cfg.get("surface")) == TYPE_DICTIONARY:
		set_surface(cfg["surface"])
		_scripted["surface"] = true
	if cfg.has("curvature"):
		set_curvature(float(cfg["curvature"]))
		_scripted["surface"] = true
	if cfg.has("vertical_curvature"):
		set_vertical_curvature(float(cfg["vertical_curvature"]))
		_scripted["surface"] = true
	if typeof(cfg.get("vertex_effects")) == TYPE_ARRAY:
		set_vertex_effects(cfg["vertex_effects"])
		_scripted["vertex_effects"] = true
	if cfg.has("opacity"):
		set_opacity(float(cfg["opacity"]))
		_scripted["opacity"] = true
	if cfg.has("blend"):
		set_blend(String(cfg["blend"]))
		_scripted["blend"] = true
	if typeof(cfg.get("effects")) == TYPE_ARRAY:
		set_effects(cfg["effects"])
		_scripted["effects"] = true


## Whether the script's config set `key` (see configure).
func is_scripted(key: String) -> bool:
	return _scripted.has(key)


func _wire_source_texture() -> void:
	if canvas == null or _display_material == null:
		return
	var mat := get_shader_material()
	var out: Texture2D
	# Passthrough (no artist pass): don't pay for the intermediate viewport
	# at all.
	_set_artist_update()
	if mat == null:
		out = _source_texture
	else:
		out = render_viewport.get_texture()
		if _source_texture != null:
			mat.set_shader_parameter(_SOURCE_TEX_UNIFORM, _source_texture)
	_build_chains(out)


## (Re)build the effect passes after `src` and point the display at the
## result. Stereo frames get a chain per eye, each starting with a crop to
## that eye, so effects see one eye's picture (an oval stays an oval).
func _build_chains(src: Texture2D) -> void:
	if _chain_holder == null:
		return
	for c in _chain_holder.get_children():
		_chain_holder.remove_child(c)
		c.queue_free()
	_passes.clear()
	_chain_seen = -1  # new passes render every frame until _update_chain_redraw
	_built_counts = _pass_counts()
	var active: Array[int] = []
	_chain_static = true
	for i in _effect_shaders.size():
		if _effect_active(i):
			active.append(i)
			_chain_static = _chain_static and not VisualizerShaders.is_animated(_effect_shaders[i])
	if active.is_empty() or src == null:
		_set_display_param("frame_tex", src)
		_set_display_param("eyes_split", false)
		_apply_effect_params()  # no padding left
		return
	var stereo := VideoProjection.stereo_of(_projection)
	var eyes: Array[Rect2] = [Rect2(0, 0, 1, 1)]
	if stereo == 1:
		eyes = [Rect2(0, 0, 0.5, 1), Rect2(0.5, 0, 0.5, 1)]
	elif stereo == 2:
		eyes = [Rect2(0, 0, 1, 0.5), Rect2(0, 0.5, 1, 0.5)]
	var margin_at := _margin_index()
	var outs: Array[Texture2D] = []
	for rect in eyes:
		var tex := src
		# The artist pass already renders one picture at the render size.
		if eyes.size() > 1 or src == _source_texture:
			tex = _add_pass(_COPY_SHADER, tex, _SOURCE_COPY)
			_passes[-1].material.set_shader_parameter("rect",
					Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
		for i in active:
			if i == margin_at:
				tex = _add_pass(_COPY_SHADER, tex, _MARGIN_COPY)
			var before := tex
			tex = _add_pass(_effect_shaders[i], tex, i)
			if _effect_blends(i):
				var fx := tex
				tex = _new_pass(EffectBlend.pass_shader(), before, i, false)
				_passes[-1].blend = true
				_passes[-1].material.set_shader_parameter("effect_tex", fx)
		outs.append(tex)
	_set_display_param("frame_tex", outs[0])
	_set_display_param("frame_tex_right", outs[-1])
	_set_display_param("eyes_split", outs.size() > 1)
	if not _shown:
		_set_passes_update(SubViewport.UPDATE_DISABLED)
	_apply_effect_params()


func _add_pass(shader: Shader, input: Texture2D, effect: int) -> Texture2D:
	var counts: Array = _built_counts[effect] if effect >= 0 else [1, 1]
	var steps: int = counts[0]
	if steps > 1:
		# `@passes`: the same shader N times, each on the one before; all
		# of them also get the effect's own input as `pass_source_tex`.
		var tex := input
		for s in steps:
			tex = _new_pass(shader, tex, effect, false)
			_mark_step(s, steps)
			_passes[-1].material.set_shader_parameter("pass_source_tex", input)
		return tex
	var pre: Texture2D = null
	if effect >= 0 and VisualizerShaders.has_prepass(shader):
		pre = _new_pass(shader, input, effect, true)
		# `@prepass_passes`: more prepass steps, each on the one before.
		var pre_steps: int = counts[1]
		for s in pre_steps:
			_mark_step(s, pre_steps)
			if s < pre_steps - 1:
				pre = _new_pass(shader, pre, effect, true)
	var out := _new_pass(shader, input, effect, false)
	if pre != null:
		_passes[-1].material.set_shader_parameter("prepass_tex", pre)
	return out


func _new_pass(shader: Shader, input: Texture2D, effect: int, prepass: bool) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = render_viewport.size  # padding resizes it in _apply_effect_params
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("input_tex", input)
	mat.set_shader_parameter("video_tex", _effect_video())
	if prepass:
		mat.set_shader_parameter("prepass", true)
	rect.material = mat
	vp.add_child(rect)
	_chain_holder.add_child(vp)
	_passes.append({"material": mat, "viewport": vp, "effect": effect, "prepass": prepass,
			"blend": false, "step": -1, "count": 1})
	return vp.get_texture()


## The last pass made is step `step` of `count` (a multi-pass effect's or
## prepass's), and its shader is told so.
## The SubViewports this screen draws in, for GpuCost: [{viewport, part,
## effect, key}], part "shader" (the artist pass), "effect" (an effect's
## pass, prepass or blend pass; effect: its index, key: its shader) or
## "copy" (a chain_copy pass). Only while they render: none while the
## screen can't be seen.
func gpu_passes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _shown:
		return out
	if render_viewport != null and render_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		out.append({"viewport": render_viewport, "part": "shader", "effect": -1, "key": ""})
	for p in _passes:
		var i: int = p.effect
		if i >= 0:
			out.append({"viewport": p.viewport, "part": "effect", "effect": i, "key": _effect_keys[i]})
		else:
			out.append({"viewport": p.viewport, "part": "copy", "effect": i, "key": ""})
	return out


func _mark_step(step: int, count: int) -> void:
	_passes[-1].step = step
	_passes[-1].count = count
	_passes[-1].material.set_shader_parameter("pass_index", step)
	_passes[-1].material.set_shader_parameter("pass_count", count)


## [passes, prepass passes, runs, blend pass] per effect at the current
## params, mix and switch (see VisualizerShaders.passes_of, _effect_active,
## _effect_blends).
func _pass_counts() -> Array:
	var out := []
	for i in _effect_keys.size():
		var params: Dictionary = _effect_params[i] if i < _effect_params.size() else {}
		var shaders_known := i < _effect_shaders.size()
		out.append([VisualizerShaders.passes_of(_effect_keys[i], params),
				VisualizerShaders.passes_of(_effect_keys[i], params, true),
				shaders_known and _effect_active(i), shaders_known and _effect_blends(i)])
	return out


## After a params change: rebuild the passes if an effect's pass count
## follows the params and changed, else just push the params.
func _params_changed() -> void:
	if _pass_counts() != _built_counts:
		_wire_source_texture()
	else:
		_apply_effect_params()


## Push effect params and each pass's shape: display_aspect, and from the
## margin copy on the grown pass size and quad (walked per eye chain, in
## units of the unpadded picture's height).
func _apply_effect_params() -> void:
	_chain_changed()
	var base := _display_aspect()
	var margin := _margin(base)
	var w := base
	var h := 1.0
	var px := Vector2(render_viewport.size) if render_viewport != null else Vector2.ONE
	var shape := Vector2.ZERO
	for p in _passes:
		var i: int = p.effect
		if i == _SOURCE_COPY:
			w = base
			h = 1.0
			shape = Vector2.ZERO
			px = Vector2(render_viewport.size)
			(p.viewport as SubViewport).size = pass_size(px)
			continue
		if i == _MARGIN_COPY:
			var grown := pad(base, px, margin)
			w = grown.w
			h = grown.h
			px = grown.px
			p.material.set_shader_parameter("place", picture_rect(base, w, h))
			(p.viewport as SubViewport).size = pass_size(px)
			continue
		var mat: ShaderMaterial = p.material
		if p.blend:
			mat.set_shader_parameter("blend_mode", _effect_blend[i])
			mat.set_shader_parameter("mix_amount", effect_amount(i))
			(p.viewport as SubViewport).size = pass_size(px)
			continue
		var params: Dictionary = _effect_params[i] if i < _effect_params.size() else {}
		for k in params:
			mat.set_shader_parameter(k, ImageLibrary.value(params[k]))
		var key: String = _effect_keys[i] if i < _effect_keys.size() else ""
		mat.set_shader_parameter("display_aspect", w / h)
		mat.set_shader_parameter("picture_rect", picture_rect(base, w, h))
		mat.set_shader_parameter("picture_shape", shape)
		if key == VisualizerShaders.ROUNDED_CORNERS and not p.prepass:
			shape = Vector2(float(params.get("roundness", _param_default(key, "roundness"))),
					float(params.get("bulge", _param_default(key, "bulge"))))
		var size := px
		if p.prepass:
			size *= clampf(float(params.get("prepass_scale", _param_default(key, "prepass_scale", 1.0))), 0.05, 1.0)
		elif not p.prepass and p.step >= 0 and p.step < p.count - 1:
			# A multi-pass effect's steps before its last run at `pass_scale`.
			size *= clampf(float(params.get("pass_scale", _param_default(key, "pass_scale", 1.0))), 0.05, 1.0)
		(p.viewport as SubViewport).size = pass_size(size)
	if _passes.is_empty():
		w = base
		h = 1.0
	_pad_scale = Vector2(w / base, h)
	if mesh != null:
		mesh.scale = _base_scale * Vector3(_pad_scale.x, _pad_scale.y, 1.0)
	_set_display_param("picture_half", _picture_half())


## The picture (`base` wide, 1 high) rendered at `px` pixels, with
## `margin` (x, y; in its heights) added on each side. -> {w, h, px}
static func pad(base: float, px: Vector2, margin: Vector2) -> Dictionary:
	var w := base + 2.0 * maxf(margin.x, 0.0)
	var h := 1.0 + 2.0 * maxf(margin.y, 0.0)
	return {"w": w, "h": h, "px": px * Vector2(w / base, h)}


## Render the passes once when their input frame or they themselves
## changed, if they can render on demand (_chain_serial); else every frame.
func _update_chain_redraw() -> void:
	if _passes.is_empty() or not _shown:
		return
	var serial := _chain_serial()
	if serial < 0:
		if _chain_seen >= 0:
			_chain_seen = -1
			_set_passes_update(SubViewport.UPDATE_ALWAYS)
		return
	if serial != _chain_seen:
		_chain_seen = serial
		_set_passes_update(SubViewport.UPDATE_ONCE)


## The passes' params, sizes or inputs changed: on demand, render them this
## frame (a resized pass would otherwise show its cleared texture).
func _chain_changed() -> void:
	if _chain_seen >= 0 and _shown:
		_set_passes_update(SubViewport.UPDATE_ONCE)


## The redraw serial of everything the passes read, or -1 if it may change
## on any frame (an artist shader, an animated effect, or an input that
## isn't a VideoBridge's frame; see VideoBridge.redraw_serial_of).
func _chain_serial() -> int:
	if not _chain_static or get_shader_material() != null:
		return -1
	var serial := VideoBridge.redraw_serial_of(_source_texture)
	var video := _effect_video()
	if serial >= 0 and video != _source_texture:
		var v := VideoBridge.redraw_serial_of(video)
		serial = serial + v if v >= 0 else -1
	return serial


func _set_passes_update(mode: SubViewport.UpdateMode) -> void:
	for p in _passes:
		(p.viewport as SubViewport).render_target_update_mode = mode


## The first effect (index) drawing past the picture's edge, which the
## margin copy goes before; -1 if none does.
func _margin_index() -> int:
	for i in _effect_shaders.size():
		if _effect_active(i) and VisualizerShaders.has_reach(_effect_keys[i]):
			return i
	return -1


## The margin (x, y; per side, in picture heights) around a picture `base`
## wide: what the effects from _margin_index() on reach, summed. None at
## infinity, where the picture already fills its arc.
func _margin(base: float) -> Vector2:
	var from := _margin_index()
	if from < 0 or _placement() == ScreenGeometry.Placement.INFINITY:
		return Vector2.ZERO
	var total := Vector2.ZERO
	for i in range(from, _effect_shaders.size()):
		if _effect_active(i):
			total += VisualizerShaders.reach_of(_effect_keys[i],
					_effect_params[i] if i < _effect_params.size() else {}, base)
	return total


## Where the unpadded picture (`base` wide, 1 high) sits in a pass `w` × `h`
## (the margin centres it), as UV x, y, width, height: `picture_rect`.
static func picture_rect(base: float, w: float, h: float) -> Vector4:
	return Vector4(0.5 - 0.5 * base / w, 0.5 - 0.5 / h, base / w, 1.0 / h)


## A pass's viewport size for `px` pixels, shrunk to fit 4096.
static func pass_size(px: Vector2) -> Vector2i:
	if px.x > 4096.0 or px.y > 4096.0:
		px *= 4096.0 / maxf(px.x, px.y)
	return Vector2i(px.round()).max(Vector2i.ONE * 16)


## The default of effect `key`'s uniform `param`, from its hints.
static func _param_default(key: String, param: String, fallback: float = 0.0) -> float:
	for spec in VisualizerShaders.hints_for(key).params:
		if spec.name == param:
			return float(spec.default)
	return fallback


## Width / height of the flat quad's picture, without padding.
func _display_aspect() -> float:
	return _QUAD_ASPECT * _base_scale.x / maxf(_base_scale.y, 0.001)


func _apply_projection() -> void:
	if _display_material == null:
		return
	_set_display_param("stereo", VideoProjection.stereo_of(_projection))
	_apply_aspect()
	if not _passes.is_empty():
		_wire_source_texture()  # eye chains follow the stereo layout


func _set_display_param(param: String, value: Variant) -> void:
	if _display_material != null:
		_display_material.set_shader_parameter(param, value)


func _placement() -> int:
	return ScreenGeometry.placement_index(String(_surface.placement))


## The unpadded picture's half size in mesh units.
func _picture_half() -> Vector2:
	return _MESH_HALF / _pad_scale


## Metres from the screen's centre to the viewer's home eye (at infinity:
## the camera-centred surface's radius).
func _viewer_distance() -> float:
	if _placement() == ScreenGeometry.Placement.INFINITY:
		return ScreenGeometry.INFINITY_RADIUS
	if mesh == null or not mesh.is_inside_tree():
		return 8.0
	return maxf(mesh.global_position.distance_to(viewer_eye), 0.1)


## A display shader for the current vertex effects and surface, then its
## params. At infinity the screen draws first among transparent things, so
## it stays behind UI panels and other screens like a skybox.
func _rebuild_display_shader() -> void:
	if _display_material == null:
		return
	var keys: Array = []
	_uses_audio = false
	for e in _vertex_effects:
		keys.append(e.shader)
		_uses_audio = _uses_audio or bool(ScreenGeometry.hints_for(e.shader).audio)
	var infinity := _placement() == ScreenGeometry.Placement.INFINITY
	_display_material.shader = ScreenGeometry.build_shader(keys, _surface.shader, _vr_source)
	_display_material.render_priority = Material.RENDER_PRIORITY_MIN if infinity else 0
	_apply_geometry_params()
	_apply_effect_params()  # padding is off at infinity


## Push the surface's and vertex effects' params (defaults for missing
## ones) and the geometry inputs.
func _apply_geometry_params() -> void:
	if _display_material == null:
		return
	var curved := _placement() != ScreenGeometry.Placement.FIXED or not _vertex_effects.is_empty()
	var sp := ScreenGeometry.full_params(_surface.shader, _surface.params)
	for k in sp:
		_display_material.set_shader_parameter(ScreenGeometry.SURFACE_PREFIX + k, sp[k])
		if typeof(sp[k]) in [TYPE_FLOAT, TYPE_INT] and k.begins_with("arc") and float(sp[k]) > 0.0:
			curved = true
	for i in _vertex_effects.size():
		var vp := ScreenGeometry.full_params(_vertex_effects[i].shader, _vertex_effects[i].params)
		for k in vp:
			_display_material.set_shader_parameter(ScreenGeometry.vertex_prefix(i) + k, vp[k])
		_display_material.set_shader_parameter(ScreenGeometry.vertex_prefix(i) + "mix",
				_vertex_effects[i].mix * _vertex_effects[i].level)
	_display_material.set_shader_parameter("placement", _placement())
	_display_material.set_shader_parameter("viewer_distance", _viewer_distance())
	_display_material.set_shader_parameter("picture_half", _picture_half())
	if mesh != null:
		# The quad's bounds don't cover a bent or moving surface.
		mesh.extra_cull_margin = _CURVED_CULL_MARGIN if curved else _FLAT_CULL_MARGIN


func _apply_aspect() -> void:
	if mesh == null:
		return
	if not _fit_aspect or _frame_aspect <= 0.0:
		_base_scale = Vector3.ONE
	else:
		var a := VideoProjection.eye_aspect(_projection, _frame_aspect)
		if a >= _QUAD_ASPECT:
			_base_scale = Vector3(1.0, _QUAD_ASPECT / a, 1.0)
		else:
			_base_scale = Vector3(a / _QUAD_ASPECT, 1.0, 1.0)
	_apply_effect_params()  # sets mesh.scale, padding included
