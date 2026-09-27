class_name VideoBridge
extends Node

## The video frame the screens sample, decoder-agnostic, so main.gd doesn't
## touch decoder internals. Decoding is a VideoBackend's job:
##   gozen   GozenVideoBackend — FFmpeg (gde_gozen): every format, local
##           files and network streams
##   native  NativeVideoBackend — the OS's media framework (godot-native-
##           video): hardware decode of local MP4 / MOV, Windows and macOS
## set_decoder picks the preferred one; a video it can't play (or a platform
## without it) goes to the other. Each backend is created on first use and
## kept.
##
## Design: decoders draw into Controls (gozen's VideoPlayback renders with a
## `shader_type canvas_item` YUV→RGB shader), which won't run on a 3D mesh
## directly, so the bridge hosts the active backend's view inside a
## SubViewport and exposes its ViewportTexture — one texture whichever
## backend is playing. Consumers (spawned Screen prefabs) sample that
## texture through their own artist shader; the bridge itself owns no 3D
## geometry.
##
## Opens and slow seeks run off the main thread (see the backends).
## `busy_changed` reports them so main.gd can hold the timeline clock, and a
## "Seeking..." / "Loading..." card is drawn into the video frame itself
## (once per eye for stereo layouts, see set_overlay_stereo) when one takes
## long enough to notice. While a video opens, set_loading_thumbnail can put
## its thumbnail in the frame (under the "Loading..." card) instead of the
## old video's frame.

signal video_loaded(duration_seconds: float, framerate: float)
signal video_load_failed
## True while the frame on screen isn't the one playback should show: a
## video is opening or a seek is in flight.
signal busy_changed(busy: bool)
## The video's sound moved to another AudioServer bus (a video played by
## another backend); see audio_bus_name.
signal audio_bus_changed

## Decoder keys, in PlayerSettings.VIDEO_DECODERS order.
const BACKENDS := {
	"gozen": preload("res://player/video/gozen_backend.gd"),
	"native": preload("res://player/video/native_backend.gd"),
}
## Quick seeks finish without flashing the overlay.
const OVERLAY_DELAY_MSEC := 150

var _viewport: SubViewport
var _placeholder: Control  # shown on the screen until a video has loaded
var _placeholder_title: Label
var _placeholder_hint: Label
var _overlay: Control  # "Seeking..." card over the video, see _show_overlay
var _thumb: ColorRect  # the loading video's thumbnail on black, see set_loading_thumbnail
var _thumb_image: TextureRect
var _overlay_stereo: int = VideoProjection.Stereo.MONO
var _decoder: String = "gozen"  # preferred backend key
var _backends: Dictionary = {}  # key -> VideoBackend, created on first use
var _active: VideoBackend  # the one playing the current video, null before any
var _loaded: bool = false
var _loading: bool = false  # a video was asked for and isn't ready yet
var _load_path: String = ""  # the video asked for most recently
var _volume: float = 1.0
var _busy_reported: bool = false  # last busy_changed value
var _busy_since_msec: int = 0
var _overlay_text: String = ""  # what the overlay's labels say, "" = none


## Whether any decoder is loaded on this platform.
static func is_available() -> bool:
	for script in BACKENDS.values():
		if script.is_available():
			return true
	return false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "VideoViewport"
	_viewport.size = Vector2i(1280, 720)  # resized to actual video resolution on load
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport.disable_3d = true
	add_child(_viewport)

	_placeholder = _build_placeholder()
	_viewport.add_child(_placeholder)
	_placeholder_title = _placeholder.get_child(0).get_child(0)
	_placeholder_hint = _placeholder.get_child(0).get_child(1)
	_thumb = ColorRect.new()
	_thumb.name = "LoadingThumbnail"
	_thumb.color = Color.BLACK
	_thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.visible = false
	_viewport.add_child(_thumb)
	_thumb_image = TextureRect.new()
	_thumb_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_thumb_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.add_child(_thumb_image)
	_overlay = Control.new()
	_overlay.name = "BusyOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_viewport.add_child(_overlay)
	# The preferred backend now, so its audio bus exists for analysis.
	_switch_to(_pick_backend(""))


## Neutral "no video" card so the screen is visible against a dark skybox
## before anything is opened (the decoder output alone reads black).
static func _build_placeholder() -> Control:
	var bg := PanelContainer.new()
	bg.name = "Placeholder"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.18, 0.22)
	style.border_color = Color(0.35, 0.55, 0.9)
	style.set_border_width_all(12)
	bg.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 24)
	bg.add_child(rows)
	for line in [["No video", 96, Color(0.85, 0.9, 1.0)],
			["Open the menu to pick a file", 44, Color(0.6, 0.66, 0.75)]]:
		var label := Label.new()
		label.text = line[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", line[1])
		label.add_theme_color_override("font_color", line[2])
		rows.add_child(label)
	return bg


## Returns the ViewportTexture that carries the decoded video. Safe to
## call before a video has loaded — the texture shows the placeholder card
## until VideoPlayback starts rendering.
func get_output_texture() -> Texture2D:
	return _viewport.get_texture() if _viewport != null else null


func load_video(os_path: String) -> void:
	_loaded = false
	_loading = true
	_load_path = os_path
	_thumb.visible = false  # the caller sets this video's, if it has one
	var backend := _pick_backend(os_path)
	_switch_to(backend)
	if backend == null:
		_fail_load()
		return
	backend.load_video(os_path)
	if _placeholder.visible:
		_set_placeholder_text("Loading...", os_path.get_file().uri_decode())
		_update_busy()
	else:
		_update_busy("Loading...")


## Preferred decoder, a BACKENDS key. Returns true if the current video
## would now play on another backend (reopen it to switch).
func set_decoder(key: String) -> bool:
	if not BACKENDS.has(key):
		key = "gozen"
	_decoder = key
	return _load_path != "" and _key_of(_active) != _key_of(_pick_backend(_load_path))


## Key of the backend playing the current video ("" before any).
func active_decoder() -> String:
	return _key_of(_active)


## Show `tex` (the thumbnail of the video now opening) in the frame until
## it has loaded. Ignored once the video is ready or has failed, so a
## thumbnail that arrives late is harmless.
func set_loading_thumbnail(tex: Texture2D) -> void:
	if tex == null or not _loading:
		return
	_thumb_image.texture = tex
	_thumb.visible = true
	# The placeholder card is covered now; say "Loading..." on the overlay.
	_placeholder.visible = false
	_update_busy("Loading...")


## How the frame is split between the eyes (VideoProjection.Stereo), so the
## overlay card sits in the middle of each eye's view instead of on the seam.
func set_overlay_stereo(stereo: int) -> void:
	if stereo == _overlay_stereo:
		return
	_overlay_stereo = stereo
	var text := _overlay_text
	_show_overlay("")
	_show_overlay(text)


func play() -> void:
	if _active != null:
		_active.play()


func pause() -> void:
	if _active != null:
		_active.pause()


## Asynchronous on some backends: the frame (and audio) jump once the
## decoder gets there.
func seek_seconds(t: float) -> void:
	if _active != null and _loaded:
		_active.seek_seconds(t)


func is_busy() -> bool:
	return _loading or (_active != null and _active.is_seeking())


## The preferred backend if it can play `path` ("" = no video in mind), else
## any other that can; null if none.
func _pick_backend(path: String) -> VideoBackend:
	var keys: Array = [_decoder]
	for key in BACKENDS:
		if key != _decoder:
			keys.append(key)
	for key in keys:
		var script: GDScript = BACKENDS[key]
		if script.is_available() and (path == "" or script.can_play(path)):
			return _backend(key)
	return null


func _backend(key: String) -> VideoBackend:
	if not _backends.has(key):
		var backend: VideoBackend = BACKENDS[key].new()
		backend.name = key.capitalize() + "Backend"
		add_child(backend)
		_viewport.add_child(backend.view)
		_viewport.move_child(backend.view, 0)  # under the placeholder and cards
		backend.view.visible = false
		backend.set_volume(_volume)
		backend.loaded.connect(_on_backend_loaded.bind(backend))
		backend.load_failed.connect(_on_backend_failed.bind(backend))
		backend.seeking_changed.connect(_on_backend_seeking.bind(backend))
		_backends[key] = backend
	return _backends[key]


func _key_of(backend: VideoBackend) -> String:
	for key in _backends:
		if _backends[key] == backend:
			return key
	return ""


func _switch_to(backend: VideoBackend) -> void:
	if backend == _active:
		return
	if _active != null:
		_active.close()
		_active.view.visible = false
	var bus := audio_bus_name()
	_active = backend
	if _active != null:
		_active.view.visible = true
	if audio_bus_name() != bus:
		audio_bus_changed.emit()


func _process(_delta: float) -> void:
	if _overlay_text != "" and not _overlay.visible 			and Time.get_ticks_msec() - _busy_since_msec >= OVERLAY_DELAY_MSEC:
		_overlay.visible = true


## Call after changing _loading or a seek starting / ending. `text` is the overlay card's;
## "" shows none (the placeholder card says it instead).
func _update_busy(text: String = "") -> void:
	var busy := is_busy()
	if busy != _busy_reported:
		_busy_reported = busy
		_busy_since_msec = Time.get_ticks_msec()
		busy_changed.emit(busy)
	_show_overlay(text if busy else "")


## Rebuilds the overlay: a dimmed frame with `text` centred in each eye's
## part of it, or nothing for "". It becomes visible from _process once
## the wait has lasted OVERLAY_DELAY_MSEC.
func _show_overlay(text: String) -> void:
	if text == _overlay_text:
		return
	_overlay_text = text
	_overlay.visible = false
	for c in _overlay.get_children():
		_overlay.remove_child(c)
		c.queue_free()
	if text == "":
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)
	var eyes: Array[Rect2] = [Rect2(0, 0, 1, 1)]
	match _overlay_stereo:
		VideoProjection.Stereo.SBS:
			eyes = [Rect2(0, 0, 0.5, 1), Rect2(0.5, 0, 0.5, 1)]
		VideoProjection.Stereo.TB:
			eyes = [Rect2(0, 0, 1, 0.5), Rect2(0, 0.5, 1, 0.5)]
	var eye_h := _viewport.size.y * eyes[0].size.y
	for r in eyes:
		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.anchor_left = r.position.x
		label.anchor_top = r.position.y
		label.anchor_right = r.end.x
		label.anchor_bottom = r.end.y
		label.add_theme_font_size_override("font_size", maxi(24, int(eye_h / 12.0)))
		label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", maxi(4, int(eye_h / 120.0)))
		_overlay.add_child(label)


func _set_placeholder_text(title: String, hint: String) -> void:
	_placeholder_title.text = title
	_placeholder_hint.text = hint


## Linear 0..1 volume, applied to every backend.
func set_volume(v: float) -> void:
	_volume = clampf(v, 0.0, 1.0)
	for backend in _backends.values():
		backend.set_volume(_volume)


## Name of the AudioServer bus the video's sound plays on ("" if none),
## for analysis effects. Changes with the backend: audio_bus_changed.
func audio_bus_name() -> String:
	return _active.audio_bus_name() if _active != null else ""


## Linear gain set_volume applied to the audio before it reaches the bus.
func audio_gain() -> float:
	return _active.audio_gain() if _active != null else 1.0


## Native video resolution (the output texture's size), or ZERO before load.
func frame_size() -> Vector2i:
	return _viewport.size if (_viewport != null and _loaded) else Vector2i.ZERO


func is_playing() -> bool:
	return _loaded and _active.is_playing()


## A video was asked for and hasn't loaded (or failed) yet.
func is_loading() -> bool:
	return _loading


func duration_seconds() -> float:
	return _active.duration_seconds() if _loaded else 0.0


func playhead_seconds() -> float:
	return _active.playhead_seconds() if _loaded else 0.0


func _on_backend_loaded(backend: VideoBackend) -> void:
	if backend != _active:
		return
	_loaded = true
	_loading = false
	_placeholder.visible = false
	_thumb.visible = false
	# Match the SubViewport size to the video's native resolution so we
	# don't scale up or down.
	var size := backend.resolution()
	if size.x > 0 and size.y > 0:
		_viewport.size = size
	_update_busy()
	print("Video decoder: %s" % _key_of(backend))
	video_loaded.emit(duration_seconds(), backend.framerate())


func _on_backend_failed(backend: VideoBackend) -> void:
	if backend == _active:
		_fail_load()


func _on_backend_seeking(seeking: bool, backend: VideoBackend) -> void:
	if backend == _active:
		_update_busy("Seeking..." if seeking else "")


func _fail_load() -> void:
	_loading = false
	_thumb.visible = false
	_set_placeholder_text("Could not open video", _load_path.get_file().uri_decode())
	_placeholder.visible = true
	_update_busy()
	video_load_failed.emit()
