class_name Stage
extends Node3D

## The rendering core both apps share (the player, and Studio later): the
## world and its lights, the script runner and what it spawns, the video and
## its sound analysis, the screen and shader layers with the viewer's
## screen preferences, camera effects, cuts and fades, and the desktop
## camera / XR rig the viewer sees it through.
##
## The app around it (main.gd for the player) owns files, menus and its own
## commands. It calls setup() once, then drives the runner and listens to
## the signals below; nothing here knows about playlists, DLNA or menus.

## Something worth showing the user (the player's status line).
signal status(msg: String)
## The OS path or URL of the video now playing, "" when it failed to open
## (for timecode clients).
signal media_path_changed(os_path: String)
## A video started opening: the app may show a thumbnail meanwhile
## (video.set_loading_thumbnail).
signal video_opening(os_path: String, thumbnail_url: String)
## Projection picked for this video ("auto" or a key) and what auto detects.
signal source_changed(override: Dictionary, detected: String, detected_swap: bool, swap: bool)
## The camera effect's compile error, "" once it compiles.
signal camera_fx_error_changed(text: String)

const VIDEO_BRIDGE_SCRIPT := preload("res://player/video_bridge.gd")

@onready var runner: ScriptRunner = $ScriptRunner
@onready var xr_mode: XRMode = $XRMode
@onready var xr_rig: XRRig = $XRRig
@onready var desktop_camera: Camera3D = $DesktopCamera
@onready var fade_overlay: FadeOverlay = $Overlay/FadeOverlay
@onready var screen_mount: Node3D = $World/ScreenMount
@onready var floor_mesh: MeshInstance3D = $World/Floor
@onready var world_env: WorldEnvironment = $WorldEnvironment

## The viewer's preferences (volume, skybox, floor, camera effect limits,
## script camera); the app loads them and passes them to setup().
var settings: PlayerSettings
var router: InputRouter
var video: VideoBridge
var audio: AudioAnalyzer
## The current video's beat grid and the music's place in it, for shaders.
var beats: BeatClock
var camera_fx: CameraFx
var preset_store: PresetStore
var screen_settings: ScreenSettings
var layers: LayerStack
## Where to seek once the video reports its length (seek() clamps to the
## timeline duration, which is unknown until then): the player's --start,
## or a live-sync seek that arrived while the video was opening.
var pending_start: float = 0.0
var video_path: String = ""  # OS path or URL of the current video, "" if none

var _camera_fx_running := false
var _camera_fx_error := ""
var _layer_nodes: Array[Visualizer] = []  # parallel to layers.layers
var _layer_links: Array[Callable] = []  # each layer's `changed` handler, to disconnect on rebuild
var _main_screen: Node3D  # what locked layers follow
## Parent of the layer nodes, under the ScreenMount: it carries the main
## screen's own (script-animated) motion, so layers move with the screen
## and their settings place them relative to it.
var _layer_anchor: Node3D
var _skyboxes := SkyboxLibrary.new()
## Where "reset view" puts the viewer: the desktop camera's start pose.
var _home_pos: Vector3
var _home_yaw_deg: float
## The script moved the viewer (a cut or a ride); the next script load returns home
## so position stays stable across videos.
var _script_moved_view: bool = false
## File name projection detection reads: the file's own, or a DLNA item's
## title-derived name when the URL doesn't carry one.
var _video_name: String = ""
## The Camera tab's source layout choices, per video (reset on each load):
## fov / stereo are "auto" or a VideoProjection.FOVS / STEREOS name, swap
## null (auto: an `_RL` tag) or a bool.
var _source_override := {"fov": "auto", "stereo": "auto", "swap": null}
## The screen's surface from before a 180° / 360° video suggested a Dome,
## put back for the next flat one ({} = none held).
var _surface_before_immersive: Dictionary = {}
## The source layout whose suggested surface was applied, so it's applied
## once per video and layout, not over the viewer's own tweaks.
var _suggested_for: String = ""
## A preset .json to start with instead of the startup preset (the app's
## --preset; tools/bench_preset.gd uses it). Set before setup().
var startup_preset_path: String = ""
## The look (active preset, screen values, layers) from before a script
## switched to the locked Script preset; restored for the next plain video.
## Empty while not playing a script.
var _look_before_script: Dictionary = {}


func _ready() -> void:
	# The runner animates the screens first; then _process moves the layer
	# anchor after them, before the layers (children) read it.
	runner.process_priority = -1
	_home_pos = desktop_camera.global_position
	_home_yaw_deg = rad_to_deg(desktop_camera.global_rotation.y)
	Screen.viewer_eye = _home_pos

	comfort_vignette = ComfortVignette.new()
	xr_rig.xr_camera.add_child(comfort_vignette)
	xr_mode.entered_vr.connect(_on_entered_vr)
	xr_mode.exited_vr.connect(_on_exited_vr)

	runner.script_loaded.connect(_on_script_loaded)
	runner.script_load_failed.connect(_on_script_load_failed)
	runner.seeked.connect(_on_runner_seeked)
	runner.play_state_changed.connect(_on_runner_play_state_changed)
	xr_rig.movement.scroll_step.connect(xr_rig.scroll_pointed_panel)


## Bring the stage up with the viewer's settings and the app's input
## bindings (its commands arrive on `router.command`).
func setup(player_settings: PlayerSettings, bindings: InputBindings) -> void:
	settings = player_settings
	_init_input(bindings)
	_init_video()
	_init_screen_settings()
	_init_camera_fx()
	settings.changed.connect(_apply_settings)
	_apply_settings()


func _process(delta: float) -> void:
	_update_layer_anchor()
	_update_camera_fx()
	_drive_viewer()
	_update_comfort(delta)
	# `pulse` reactive objects follow the bass.
	runner.audio_bass = audio.bass if audio != null else 0.0
	if beats != null:
		var heard := video.audio_seconds() if video != null else -1.0
		beats.advance(delta, heard, runner.playhead, runner.playing and not runner.hold)


func _unhandled_input(event: InputEvent) -> void:
	if router != null and event is InputEventKey and router.handle_key(event):
		get_viewport().set_input_as_handled()


## Controller buttons, sticks and keys all arrive as commands (InputRouter,
## with the user's bindings from the Controls tab).
func _init_input(bindings: InputBindings) -> void:
	router = InputRouter.new(bindings)
	router.name = "InputRouter"
	# Before XRMovement reads its axes in the same frame.
	router.process_priority = -10
	add_child(router)
	xr_rig.router = router


## Leave the menus a camera effect should not cover (the app's own panels).
func add_masked_panel(panel: Node3D) -> void:
	camera_fx.mask_panels.append(panel)


## Put the viewer back at the home pose. In VR this moves the headset (not
## just the rig origin) there, cancelling where the user stands/faces in
## their playspace.
func reset_view() -> void:
	if xr_mode.is_in_vr():
		xr_rig.recenter(_home_pos, _home_yaw_deg)
	else:
		desktop_camera.set_view(_home_pos, Vector3(0.0, _home_yaw_deg, 0.0))


## Seek now, and again once the video has opened if it is still opening.
## Where the audience sits at the playhead: where the script's viewer
## track has them, else home. {position: Vector3, yaw_deg: float}.
func seat_pose() -> Dictionary:
	var pose := runner.viewer.pose_at(runner.playhead)
	if not pose.is_empty():
		return {"position": pose.position, "yaw_deg": (pose.rotation_deg as Vector3).y}
	return {"position": _home_pos, "yaw_deg": _home_yaw_deg}


## Put the viewer (the headset in VR, the desktop camera otherwise) at
## `pos`, facing `yaw_deg`, level. In VR `keep_floor` leaves the real floor
## at world height 0 (the audience seat); otherwise the head goes to
## `pos.y` (flying up to something).
func put_viewer(pos: Vector3, yaw_deg: float, keep_floor: bool = true) -> void:
	if xr_mode.is_in_vr():
		xr_rig.recenter(pos, yaw_deg)
		if not keep_floor:
			xr_rig.global_position.y += pos.y - xr_rig.xr_camera.global_position.y
	else:
		desktop_camera.set_view(pos, Vector3(0.0, yaw_deg, 0.0))


## The viewer's eye now: the headset in VR, else the desktop camera.
func viewer_transform() -> Transform3D:
	if xr_mode.is_in_vr():
		return xr_rig.xr_camera.global_transform
	return desktop_camera.global_transform


func seek_to(t: float) -> void:
	runner.seek(t)
	if (video != null and video.is_loading()) or runner.effective_duration() <= 0.0:
		pending_start = t


func _on_entered_vr() -> void:
	# Put the headset where the desktop camera was so the VR view picks up
	# where the desktop view left off — Whirligig / VRChat-style continuity.
	# Y stays at 0 (floor); tracking determines actual eye height.
	var d := desktop_camera.global_position
	var yaw := rad_to_deg(desktop_camera.global_rotation.y)
	xr_rig.set_view(Vector3(d.x, 0.0, d.z), Vector3(0.0, yaw, 0.0))
	desktop_camera.current = false
	xr_rig.set_visuals_enabled(true)
	xr_rig.xr_camera.current = true
	_apply_passthrough()
	# The runtime's own recenter (e.g. holding the Oculus/SteamVR button)
	# should land on our home pose too.
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.has_signal("pose_recentered") and not xr.pose_recentered.is_connected(reset_view):
		xr.pose_recentered.connect(reset_view)
	# Head pose isn't tracked for the first few frames; recenter once it is
	# so the head (not the playspace origin) lands on the desktop pose.
	await get_tree().create_timer(0.3).timeout
	if xr_mode.is_in_vr():
		xr_rig.recenter(d, yaw)


func _on_exited_vr() -> void:
	xr_rig.set_visuals_enabled(false)
	desktop_camera.current = true
	# Pick up where the headset was looking, mirroring _on_entered_vr.
	var head := xr_rig.xr_camera.global_transform
	desktop_camera.set_view(Vector3(head.origin.x, _home_pos.y, head.origin.z),
			Vector3(0.0, rad_to_deg(head.basis.get_euler().y), 0.0))


func _init_screen_settings() -> void:
	_layer_anchor = Node3D.new()
	_layer_anchor.name = "LayerAnchor"
	screen_mount.add_child(_layer_anchor)
	preset_store = PresetStore.new()
	screen_settings = ScreenSettings.new()
	layers = LayerStack.new()
	layers.layers_changed.connect(_rebuild_layers)
	# The startup preset (preset 1, the auto-created default, unless the
	# Presets tab picked another) seeds the sliders and the mount transforms;
	# startup_preset_path names a file to use instead.
	if not _apply_startup_preset() \
			and not preset_store.apply(preset_store.startup_index(), screen_settings, layers):
		preset_store.apply(preset_store.default_preset_index(), screen_settings, layers)
	screen_settings.changed.connect(_apply_screen_settings)
	screen_settings.changed.connect(_apply_screen_display)
	_apply_screen_settings()
	_apply_screen_display()
	_rebuild_layers()


## Load startup_preset_path's screen and layers; false if there's none or
## it isn't a preset.
func _apply_startup_preset() -> bool:
	if startup_preset_path == "":
		return false
	var preset = JSON.parse_string(FileAccess.get_file_as_string(startup_preset_path))
	if typeof(preset) != TYPE_DICTIONARY or typeof(preset.get("screen")) != TYPE_DICTIONARY:
		push_warning("--preset %s: not a preset file" % startup_preset_path)
		return false
	screen_settings.from_dict(preset.screen)
	layers.from_array(PresetStore.layers_of(preset))
	return true


func _apply_screen_settings() -> void:
	if screen_settings == null or screen_mount == null:
		return
	# Tilt orbits the screen around the viewer's home eye position — where
	# reset view puts them — in the mount's parent (World) space.
	var world := screen_mount.get_parent() as Node3D
	var eye := world.to_local(_home_pos) if world != null else _home_pos
	screen_settings.apply_to_mount(screen_mount, eye, _home_yaw_deg, _screen_pivot())
	_place_layers()


## Centre of the default screen in mount space; size scales about it.
static func _screen_pivot() -> Vector3:
	return Vector3(DefaultScreen.POSITION[0], DefaultScreen.POSITION[1], DefaultScreen.POSITION[2])


## Opacity, blend, surface, effects and vertex effects apply to every screen under
## the mount (main and split-off).
func _apply_screen_display() -> void:
	if screen_settings == null or screen_mount == null:
		return
	for screen in _screens_under(screen_mount):
		_apply_display_to(screen)
	_update_audio_active()


## Screens under `node`, groups included; not the ones inside shader
## layers, which follow their layer's settings.
func _screens_under(node: Node) -> Array[Screen]:
	var out: Array[Screen] = []
	for child in node.get_children():
		if child is Visualizer:
			continue
		if child is Screen:
			out.append(child)
		out.append_array(_screens_under(child))
	return out


## The Camera tab's display values, except the ones a script set on this
## screen (its look stays as authored; resolution is always the viewer's).
func _apply_display_to(screen: Node) -> void:
	if not screen is Screen or screen_settings == null:
		return
	screen.set_resolution_scale(screen_settings.resolution)
	if not screen.is_scripted("opacity"):
		screen.set_opacity(screen_settings.opacity)
	if not screen.is_scripted("blend"):
		screen.set_blend(screen_settings.blend)
	if not screen.is_scripted("surface"):
		screen.set_surface(screen_settings.surface)
	if not screen.is_scripted("effects"):
		screen.set_effects(screen_settings.effects)
	if not screen.is_scripted("vertex_effects"):
		screen.set_vertex_effects(screen_settings.vertex_effects)


## One Visualizer node per LayerStack entry, rebuilt whenever the list
## changes (count or a preset); edits within a layer just re-apply it.
func _rebuild_layers() -> void:
	for i in _layer_links.size():
		var old: LayerSettings = _layer_links[i].get_bound_arguments()[0]
		if old.changed.is_connected(_layer_links[i]):
			old.changed.disconnect(_layer_links[i])
	_layer_links.clear()
	for node in _layer_nodes:
		node.queue_free()
	_layer_nodes.clear()
	for i in layers.count():
		var node := Visualizer.new()
		node.name = "Layer%d" % (i + 1)
		_layer_anchor.add_child(node)
		if audio != null:
			node.bind_audio(audio)
		node.bind_beats(beats)
		_apply_video_to_layer(node)
		if _main_screen != null:
			node.set_follow_target(_main_screen)
		_layer_nodes.append(node)
		var link := _apply_layer.bind(layers.layers[i], node)
		layers.layers[i].changed.connect(link)
		_layer_links.append(link)
		_apply_layer(layers.layers[i], node)
	_update_audio_active()


## Draw order is by depth (see Visualizer); the stack position only breaks
## ties between equal placements.
func _apply_layer(layer: LayerSettings, node: Visualizer) -> void:
	var i := layers.layers.find(layer)
	_place_layer(layer, node)
	node.set_order(i)
	node.set_locked(layer.lock_to_screen, layer.size, layer.distance)
	node.set_surface(layer.surface)
	node.set_vertex_effects(layer.vertex_effects)
	node.set_opacity(layer.opacity)
	node.set_blend(layer.blend)
	node.set_resolution_scale(layer.resolution)
	# Off: no source, so the layer hides and its render viewport stops.
	node.set_shader(layer.shader if layer.enabled else "")
	node.set_params(layer.params)
	node.set_effects(layer.effects)
	_update_audio_active()


## Size, distance and height are relative to the screen (the layer's
## parent). Tilt orbits the viewer's eye as seen from the screen, so a
## tilted layer keeps its distance from the viewer like the screen's own
## tilt does; that eye moves whenever the screen does (_place_layers).
func _place_layer(layer: LayerSettings, node: Visualizer) -> void:
	var eye := _layer_anchor.global_transform.affine_inverse() * _home_pos
	var yaw := _home_yaw_deg - rad_to_deg(_layer_anchor.global_rotation.y)
	layer.apply_to_mount(node, eye, yaw, _screen_pivot())


func _place_layers() -> void:
	if layers == null:
		return
	for i in mini(layers.count(), _layer_nodes.size()):
		_place_layer(layers.layers[i], _layer_nodes[i])


## The main screen's motion away from where the default screen sits, which
## the layers inherit. Identity until a script moves (or respawns) it.
func _update_layer_anchor() -> void:
	if _layer_anchor == null:
		return
	var t := Transform3D.IDENTITY
	# In mount space, so a main_screen inside a script's group counts the
	# group's motion too.
	if is_instance_valid(_main_screen) and screen_mount.is_ancestor_of(_main_screen):
		t = screen_mount.global_transform.affine_inverse() * _main_screen.global_transform * _default_screen_transform().affine_inverse()
	if not t.is_equal_approx(_layer_anchor.transform):
		_layer_anchor.transform = t
		_place_layers()


static func _default_screen_transform() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * DefaultScreen.SCALE), _screen_pivot())


## Full-view camera effects (CameraFx) on the world's compositor, so both
## the desktop view and the headset get them. The menus are left alone
## (the wrist HUD here, the app's panels via add_masked_panel).
func _init_camera_fx() -> void:
	camera_fx = CameraFx.new()
	camera_fx.name = "CameraFx"
	add_child(camera_fx)
	camera_fx.attach(world_env)
	camera_fx.audio = audio
	camera_fx.mask_panels = [xr_rig.wrist_panel]


## A playing script's camera effect wins; otherwise the preset's. Called
## every frame (script tracks animate it).
func _update_camera_fx() -> void:
	if camera_fx == null:
		return
	var from_script := runner.camera_effect()
	if not from_script.is_empty():
		camera_fx.show_effect(from_script.key, from_script.params, from_script.strength)
	else:
		var fx := layers.camera_fx
		camera_fx.show_effect(fx.shader, fx.params, fx.strength)
	if camera_fx.is_running() != _camera_fx_running:
		_camera_fx_running = camera_fx.is_running()
		_update_audio_active()
	if camera_fx.error_text() != _camera_fx_error:
		_camera_fx_error = camera_fx.error_text()
		camera_fx_error_changed.emit(_camera_fx_error)


## The analyzer is shared: run it while any layer has a shader, a camera
## effect is on, or a screen's vertex effect follows the music.
func _update_audio_active() -> void:
	if audio == null:
		return
	var running := runner.wants_audio() or (camera_fx != null and camera_fx.is_running())
	for node in _layer_nodes + _script_layers():
		running = running or node.is_running()
	if screen_mount != null:
		for screen in _screens_under(screen_mount):
			running = running or screen.uses_audio()
	audio.set_active(running)


## The shader layers the current script spawned.
func _script_layers() -> Array[Visualizer]:
	var out: Array[Visualizer] = []
	var registry := runner.registry()
	for id in registry.all_ids():
		var node = registry.get_node_by_id(id)
		if is_instance_valid(node) and node is Visualizer:
			out.append(node)
	return out


## The parts of the viewer's settings the stage shows; the app applies the
## rest (window, controls) itself.
func _apply_settings() -> void:
	camera_fx.enabled = settings.camera_fx
	camera_fx.max_strength = settings.camera_fx_max
	floor_mesh.visible = settings.show_floor
	_skyboxes.apply(world_env.environment, settings.skybox)
	_apply_passthrough()
	if video != null:
		video.set_volume(settings.volume)
		if audio != null:
			audio.set_input_gain(video.audio_gain())
		if video.set_decoder(settings.video_decoder):
			_reopen_video()


## The Passthrough skybox in VR: the headset's cameras behind everything.
func _apply_passthrough() -> void:
	if settings == null:
		return
	var want := settings.skybox == SkyboxLibrary.PASSTHROUGH and xr_mode.is_in_vr()
	if want == xr_mode.is_passthrough():
		return
	if not xr_mode.set_passthrough(want) and want:
		status.emit("Passthrough isn't available on this headset or runtime")


## The current video's source layout (a VideoProjection key): the Camera
## tab's choices, else what the file name says.
func _current_projection() -> String:
	var detected := VideoProjection.detect(_video_name)
	var fov := String(_source_override.fov)
	var stereo := String(_source_override.stereo)
	return VideoProjection.compose(
			VideoProjection.fov_of(detected) if fov == "auto" else fov,
			VideoProjection.stereo_name(detected) if stereo == "auto" else stereo)


## Whether the current video is right eye first.
func _current_swap() -> bool:
	if _source_override.swap == null:
		return VideoProjection.detect_swap(_video_name)
	return bool(_source_override.swap)


## A Camera tab source pick for this video: `part` "fov" / "stereo"
## ("auto" or a name) or "swap" (a bool).
func set_source_override(part: String, value: Variant) -> void:
	_source_override[part] = value
	apply_projection()


## Push the source layout + aspect to the main screen (and the layers that
## read the video), the surface it suggests, and report it (source_changed)
## for the app's menu.
func apply_projection() -> void:
	var key := _current_projection()
	_apply_suggested_surface(key)
	if video != null:
		video.set_overlay_stereo(VideoProjection.stereo_of(key))
	var screen := runner.registry().get_node_by_id(DefaultScreen.SCREEN_ID) as Screen
	if screen != null:
		screen.set_source_layout(key)
		screen.set_swap_eyes(_current_swap())
		if video != null:
			var size := video.frame_size()
			if size.y > 0:
				screen.set_content_aspect(float(size.x) / float(size.y))
	for node in _layer_nodes + _script_layers():
		_apply_video_to_layer(node)
	source_changed.emit(_source_override, VideoProjection.detect(_video_name),
			VideoProjection.detect_swap(_video_name), _current_swap())


## A 180° / 360° source puts the screen on the Dome it's made for (once per
## video and layout, so the viewer can still change it); the surface from
## before comes back for the next flat one.
func _apply_suggested_surface(key: String) -> void:
	if key == _suggested_for or screen_settings == null:
		return
	_suggested_for = key
	var suggested := VideoProjection.suggested_surface(key)
	if not suggested.is_empty():
		if _surface_before_immersive.is_empty():
			_surface_before_immersive = screen_settings.surface.duplicate(true)
		screen_settings.set_surface(suggested)
	elif not _surface_before_immersive.is_empty():
		screen_settings.set_surface(_surface_before_immersive)
		_surface_before_immersive = {}


## The video's frame and layout, for video layers and layer shaders
## tagged `@iChannelN video`.
func _apply_video_to_layer(node: Visualizer) -> void:
	if video == null:
		return
	node.bind_video(video.get_output_texture())
	var size := video.frame_size()
	node.set_video_layout(_current_projection(), float(size.x) / size.y if size.y > 0 else 0.0,
			_current_swap())


func _init_video() -> void:
	beats = BeatClock.new()
	beats.name = "BeatClock"
	add_child(beats)
	if not VideoBridge.is_available():
		status.emit("No video decoder loaded — is addons/gde_gozen or addons/native_video installed?")
		return
	video = VIDEO_BRIDGE_SCRIPT.new()
	video.name = "VideoBridge"
	add_child(video)
	video.video_loaded.connect(_on_video_loaded)
	video.video_load_failed.connect(_on_video_load_failed)
	# Freeze the timeline while the picture catches up (opening, seeking), so
	# script events and the scrub bar stay in step with the video.
	video.busy_changed.connect(func(busy: bool): runner.hold = busy)
	video.set_volume(settings.volume)
	# Live analysis of the video's sound for the visualizer plane.
	audio = AudioAnalyzer.new()
	audio.name = "AudioAnalyzer"
	add_child(audio)
	_attach_audio()
	video.audio_bus_changed.connect(_attach_audio)
	audio.set_active(false)
	# Push the video texture into any spawned object that accepts one
	# (e.g. the Screen prefab). Fires both for runner spawns and any
	# externally-registered nodes.
	runner.registry().object_spawned.connect(_on_object_spawned)


## The analyzer follows the video's sound onto its current bus (each
## decoder plays on its own).
func _attach_audio() -> void:
	if not audio.attach(video.audio_bus_name()):
		push_warning("AudioAnalyzer: video audio bus not found; the visualizer won't react to sound.")
	audio.set_input_gain(video.audio_gain())


## Open the current video again where it is (another decoder was chosen).
func _reopen_video() -> void:
	if video_path == "":
		return
	var t: float = runner.playhead
	video.load_video(video_path)
	seek_to(t)


func _on_object_spawned(id: String, node: Node3D) -> void:
	if node == null:
		return
	if screen_mount != null and node.get_parent() == screen_mount.get_parent() and _belongs_in_mount(node):
		# Screens (main_screen and any split-off ones), and the groups and
		# shader layers a script places with them, live under the mount:
		# the runner's per-frame transform tracks write into the mount's
		# local space, and user preferences (size/distance/height on the
		# mount) layer on top without ever fighting animation. Objects
		# spawned inside another one stay there.
		node.reparent(screen_mount, false)
	if node is Screen:
		if audio != null:
			node.bind_audio(audio)
		_apply_display_to(node)
	if node is Visualizer:
		if audio != null:
			node.bind_audio(audio)
		node.bind_beats(beats)
		_apply_video_to_layer(node)
	# A layer's shader and a `pulse` arrive right after this signal.
	_update_audio_active.call_deferred()
	if id == DefaultScreen.SCREEN_ID:
		_main_screen = node
		for layer in _layer_nodes:
			layer.set_follow_target(node)
	if video != null and node.has_method("set_source_texture"):
		node.call("set_source_texture", video.get_output_texture())
	if id == DefaultScreen.SCREEN_ID:
		apply_projection()


static func _belongs_in_mount(node: Node) -> bool:
	return node.has_method("set_source_texture") or node is Visualizer or node.get_meta("vj_group", false)


func _on_script_loaded(data: TimelineData) -> void:
	if not DefaultScreen.is_idle(data):
		status.emit("Loaded: %s" % data.meta.get("title", data.script_path.get_file()))
	if _script_moved_view:
		_script_moved_view = false
		reset_view()
	_viewer_pose = {}
	_viewer_t = -0.001
	_source_override = {"fov": "auto", "stereo": "auto", "swap": null}
	_suggested_for = ""
	_apply_look_for(data)
	# Spawn what the timeline starts with (the screen) now: the clock is
	# held until the video opens, and waiting for its first tick left no
	# screen in the meantime.
	runner.tick(0.0)
	_load_video_for(data)
	apply_projection()


## Scripts play with the locked Script preset (software defaults, no
## effects or layers) so they look as authored, whatever preset the viewer
## uses for plain videos; that look comes back when a plain video loads.
## Runs before the new timeline's screens spawn. A script's own surface
## stays anyway (Screen.is_scripted).
func _apply_look_for(data: TimelineData) -> void:
	var is_script := not data.synthetic
	if is_script and _look_before_script.is_empty():
		var screen := screen_settings.to_dict()
		# The viewer's own surface, not one a 180° / 360° video suggested.
		if not _surface_before_immersive.is_empty():
			screen["surface"] = _surface_before_immersive
			_surface_before_immersive = {}
		_look_before_script = {
			"preset": preset_store.active_index,
			"screen": screen,
			"layers": layers.to_array(),
		}
		preset_store.apply(PresetStore.SCRIPT_PRESET_INDEX, screen_settings, layers)
	elif not is_script and not _look_before_script.is_empty():
		screen_settings.from_dict(_look_before_script["screen"])
		layers.from_array(_look_before_script["layers"])
		preset_store.set_active(int(_look_before_script["preset"]))
		_look_before_script = {}


func _load_video_for(data: TimelineData) -> void:
	var rel: String = data.media.get("video", "")
	var resource_path := data.resolve(rel) if rel != "" else ""
	var os_path := ""
	if DefaultScreen.is_url(resource_path):
		os_path = resource_path
	elif resource_path != "" and FileAccess.file_exists(resource_path):
		# get_path_absolute() resolves both res:// and cwd-relative paths
		# (e.g. `--script ../scripts/x.json`) to a clean absolute OS path —
		# timecode clients match funscripts by this path.
		var f := FileAccess.open(resource_path, FileAccess.READ)
		os_path = f.get_path_absolute().simplify_path() if f != null else ProjectSettings.globalize_path(resource_path)
	elif resource_path != "":
		status.emit("Video not found: %s" % resource_path)
	video_path = os_path
	_video_name = String(data.meta.get("video_name", os_path))
	if beats != null:
		beats.load_for(os_path, BeatGrid.from_dict(data.media.get("beats")))
	media_path_changed.emit(os_path)
	if video == null or os_path == "":
		return
	video.load_video(os_path)
	video_opening.emit(os_path, String(data.meta.get("thumbnail_url", "")))


func _on_video_loaded(duration: float, framerate: float) -> void:
	status.emit("Video loaded: %.2fs%s (%s)" % [duration,
			" @ %.2f fps" % framerate if framerate > 0.0 else "", video.active_decoder()])
	runner.set_video_duration(duration)
	apply_projection()  # aspect is known now
	if pending_start > 0.0:
		runner.seek(pending_start)
		pending_start = 0.0
	if runner.playing:
		video.play()


## The bridge already retried. Stop the clock and withdraw the media from
## timecode clients, so devices don't start on a video that isn't playing.
func _on_video_load_failed() -> void:
	status.emit("Could not open video: %s" % video_path)
	runner.pause()
	media_path_changed.emit("")


func _on_runner_seeked(t: float) -> void:
	if video != null:
		video.seek_seconds(t)
	_follow_viewer_seek(t)


func _on_runner_play_state_changed(is_playing: bool) -> void:
	if video == null:
		return
	if is_playing:
		video.play()
	else:
		video.pause()


# ---------- the script's viewer ----------
# A script moves the viewer along its viewer track (ViewerTrack: "$viewer"
# keys and cut events). At a cut the viewer jumps (through a fade when the
# key asks for one; with "cuts only", at every key, faded). Along a smooth
# move the room glides: the rig in the headset, the desktop camera on the
# desktop, moved each frame by how much the track's pose changed, so the
# viewer can still look and lean around (and walk, in free mode) while
# riding. In the headset only the turn is taken (no pitch or roll), and
# the room is raised by how far the key is above the home eye height.
# Seeking lands where the track says, but moves the viewer only if the pose
# there differs from the one they were given, so a viewer who walked off
# while it holds isn't pulled back by a seek.

## The headset's comfort vignette: it eases in while a ride carries the
## viewer fast (from RIDE_CALM up to RIDE_FULL m/s, or turning up to
## TURN_FULL °/s), or when the app asks (comfort_extra, 0..1, set each
## frame: Studio's flight). Never with "cuts only" (nothing glides).
const RIDE_CALM := 0.5
const RIDE_FULL := 5.0
const TURN_FULL := 45.0
var comfort_vignette: ComfortVignette
var comfort_extra := 0.0

## Whether the stage follows the script's viewer track at all (the app can
## turn it off; the viewer's own setting also has to allow it).
var drive_viewer := true
## The track's pose the viewer was last given ({} = home), and the playhead
## it was for.
var _viewer_pose: Dictionary = {}
var _viewer_t := -0.001


## Put the viewer where the script has them now (home before it first
## moves them), and follow it from here: what an app does when it hands the
## viewer back to the script (Studio going to Play).
func follow_script_viewer() -> void:
	_viewer_pose = {}
	_viewer_t = runner.playhead
	if not _script_camera_on():
		return
	var pose := runner.viewer.pose_at(runner.playhead, settings.script_camera_cuts_only)
	if pose.is_empty():
		reset_view()
	else:
		_snap_camera(pose.position, pose.rotation_deg)
		_viewer_pose = pose


func _script_camera_on() -> bool:
	return drive_viewer and settings != null and settings.allow_script_camera


## Every frame while playing: jumps at cuts passed, glides along moves.
func _drive_viewer() -> void:
	var t := runner.playhead
	if not _script_camera_on() or runner.timeline == null or not runner.playing:
		_viewer_t = t
		return
	var cuts_only := settings.script_camera_cuts_only
	var crossed := runner.viewer.cuts_between(_viewer_t, t, cuts_only)
	_viewer_t = t
	var pose := runner.viewer.pose_at(t, cuts_only)
	if pose.is_empty():
		return
	if not crossed.is_empty():
		_jump_viewer(pose, crossed.back().get("transition", {}))
	elif not _viewer_pose.is_empty():
		_glide_viewer(_viewer_pose, pose)
	_viewer_pose = pose


## After a seek: where the track has the viewer there (home before its
## first key), if that's not where they were put last.
func _follow_viewer_seek(t: float) -> void:
	_viewer_t = t
	if not _script_camera_on():
		return
	var pose := runner.viewer.pose_at(t, settings.script_camera_cuts_only)
	if pose.is_empty():
		if not _viewer_pose.is_empty():
			_viewer_pose = {}
			_script_moved_view = false
			reset_view()
		return
	if _viewer_pose.is_empty() or not _same_pose(pose, _viewer_pose):
		_snap_camera(pose.position, pose.rotation_deg)
	_viewer_pose = pose


## How strong the comfort vignette should be now (0..1): the ride's speed
## and turn while it carries the viewer, or what the app asks for.
func comfort_level() -> float:
	var ride := 0.0
	if _script_camera_on() and runner.playing and runner.timeline != null and not settings.script_camera_cuts_only:
		var m := runner.viewer.motion_at(runner.playhead)
		ride = maxf(inverse_lerp(RIDE_CALM, RIDE_FULL, m.speed), m.turn / TURN_FULL)
	return clampf(maxf(ride, comfort_extra), 0.0, 1.0)


func _update_comfort(delta: float) -> void:
	if comfort_vignette != null:
		comfort_vignette.update(comfort_level() if xr_mode.is_in_vr() else 0.0, delta)


static func _same_pose(a: Dictionary, b: Dictionary) -> bool:
	return (a.position as Vector3).distance_to(b.position) < 0.001 \
			and absf(wrapf((a.rotation_deg as Vector3).y - (b.rotation_deg as Vector3).y, -180.0, 180.0)) < 0.01


## A cut: to `pose`, through `transition` ({} = at once).
func _jump_viewer(pose: Dictionary, transition: Dictionary) -> void:
	var pos: Vector3 = pose.position
	var rot: Vector3 = pose.rotation_deg
	if String(transition.get("type", "")) == "fade_to_black":
		var dur := float(transition.get("duration", 0.5))
		# In VR, fade the in-headset quad so the transition is visible in the
		# headset; also fade the CanvasLayer overlay so the desktop mirror
		# matches. Desktop-only: just the overlay.
		if xr_mode.is_in_vr():
			xr_rig.fade_through(dur, func(): _snap_camera(pos, rot))
			fade_overlay.fade_through(dur, func(): pass)
		else:
			fade_overlay.fade_through(dur, func(): _snap_camera(pos, rot))
	else:
		_snap_camera(pos, rot)


## Along a move: the room goes where the track went from `from` to `to`.
func _glide_viewer(from: Dictionary, to: Dictionary) -> void:
	var d := _pose_xf(to) * _pose_xf(from).affine_inverse()
	if d.is_equal_approx(Transform3D.IDENTITY):
		return
	_script_moved_view = true
	if xr_mode.is_in_vr():
		xr_rig.global_transform = d * xr_rig.global_transform
	else:
		var turn := wrapf((to.rotation_deg as Vector3).y - (from.rotation_deg as Vector3).y, -180.0, 180.0)
		var rot := desktop_camera.rotation_degrees
		desktop_camera.set_view(d * desktop_camera.global_position, Vector3(rot.x, rot.y + turn, 0.0))


## A pose as a level transform (position, turn about the vertical).
static func _pose_xf(pose: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad((pose.rotation_deg as Vector3).y)), pose.position)


## Put the viewer's eye at `pos`, facing `rot_deg` (in the headset: the
## turn only, and the room raised by the key's height above the home eye
## height, so a cut at eye height leaves the floor where it is).
func _snap_camera(pos: Vector3, rot_deg: Vector3) -> void:
	_script_moved_view = true
	if xr_mode.is_in_vr():
		xr_rig.recenter(pos, rot_deg.y)
		xr_rig.global_position.y += pos.y - _home_pos.y
	else:
		desktop_camera.set_view(pos, rot_deg)


func _on_script_load_failed(err: String) -> void:
	status.emit("ERROR: %s" % err)
