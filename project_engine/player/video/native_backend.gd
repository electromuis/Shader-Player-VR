class_name NativeVideoBackend
extends VideoBackend

## The OS's own media framework as a hardware decoder, through the
## godot-native-video extension (addons/native_video): Media Foundation on
## Windows, AVFoundation on macOS. H.264 / HEVC in MP4 / MOV; frames reach
## the GPU without FFmpeg (zero-copy under the D3D12 driver, one readback
## per frame under Vulkan). `view` is a stock VideoStreamPlayer playing a
## NativeVideoStream.
##
## A paused VideoStreamPlayer stops updating its playback, so a seek made
## while paused would never show. Paused here is instead speed 0 with the
## sound off: the extension keeps presenting frames, seeks included, while
## its clock stands still.
##
## The extension opens the file on the main thread, when the stream is set
## (tens of ms for a local file), and it aborts the whole process on an MP4
## carrying a timecode track. can_play therefore only takes local files
## whose tracks are all video or sound (see mp4_track_handlers); the rest go
## to another backend.

const STREAM_CLASS := "NativeVideoStream"
const EXTENSIONS := ["mp4", "mov", "m4v"]
## Track handlers the extension copes with.
const SAFE_HANDLERS := ["vide", "soun"]
const BUS_NAME := "NativeVideo"
## An opened video that shows no frame by then counts as failed.
const FIRST_FRAME_TIMEOUT_MSEC := 5000

var _player: VideoStreamPlayer
var _volume: float = 1.0
var _playing: bool = false
var _loaded: bool = false
var _opened_msec: int = -1  # when the open was made, until its first frame shows


static func is_available() -> bool:
	return ClassDB.class_exists(STREAM_CLASS)


static func can_play(path: String) -> bool:
	if not is_available() or DefaultScreen.is_url(path) \
			or not path.get_extension().to_lower() in EXTENSIONS:
		return false
	return tracks_are_safe(mp4_track_handlers(path))


## A video track and nothing the extension trips over (see SAFE_HANDLERS).
static func tracks_are_safe(handlers: PackedStringArray) -> bool:
	if not handlers.has("vide"):
		return false
	for h in handlers:
		if not h in SAFE_HANDLERS:
			return false
	return true


## Handler type of each track in an MP4 / MOV ("vide", "soun", "tmcd",
## "text", ...), read from moov/trak/mdia/hdlr. Empty if the file can't be
## read or has no moov box.
static func mp4_track_handlers(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	f.big_endian = true
	for moov in _boxes(f, 0, f.get_length(), "moov"):
		for trak in _boxes(f, moov[0], moov[1], "trak"):
			for mdia in _boxes(f, trak[0], trak[1], "mdia"):
				for hdlr in _boxes(f, mdia[0], mdia[1], "hdlr"):
					f.seek(hdlr[0] + 8)  # past version / flags and pre_defined
					out.append(f.get_buffer(4).get_string_from_ascii())
	return out


## [payload start, end] of each `type` box directly inside [from, to).
static func _boxes(f: FileAccess, from: int, to: int, type: String) -> Array:
	var found := []
	var pos := from
	while pos + 8 <= to:
		f.seek(pos)
		var size := f.get_32()
		var kind := f.get_buffer(4).get_string_from_ascii()
		var header := 8
		if size == 1:
			size = f.get_64()
			header = 16
		elif size == 0:
			size = to - pos  # runs to the end
		if size < header:
			break  # corrupt
		if kind == type:
			found.append([pos + header, mini(pos + size, to)])
		pos += size
	return found


func _init() -> void:
	_player = VideoStreamPlayer.new()
	_player.name = "VideoStreamPlayer"
	_player.expand = true
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view = _player


func _ready() -> void:
	# Its own bus, like gozen's, so sound analysis taps only the video.
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS_NAME)
	AudioServer.set_bus_send(idx, &"Master")
	_player.bus = AudioServer.get_bus_name(idx)


func _exit_tree() -> void:
	close()
	var idx := AudioServer.get_bus_index(_player.bus)
	if idx > 0:
		AudioServer.remove_bus(idx)


func load_video(path: String) -> void:
	close()
	var stream: VideoStream = ClassDB.instantiate(STREAM_CLASS)
	stream.file = path
	_player.stream = stream  # opens it
	if _player.get_stream_length() <= 0.0:
		_player.stream = null
		load_failed.emit.call_deferred()
		return
	_apply_play_state()
	_player.play()
	_opened_msec = Time.get_ticks_msec()


func close() -> void:
	_opened_msec = -1
	_loaded = false
	_player.stop()
	_player.stream = null


func play() -> void:
	_playing = true
	if _loaded:
		_resume()
		_apply_play_state()


func pause() -> void:
	_playing = false
	if _loaded:
		_apply_play_state()


func seek_seconds(t: float) -> void:
	if not _loaded:
		return
	_resume()
	_player.stream_position = clampf(t, 0.0, duration_seconds())


func is_playing() -> bool:
	return _loaded and _playing and _player.is_playing()


func resolution() -> Vector2i:
	var tex := _player.get_video_texture()
	return Vector2i(tex.get_size()) if _loaded and tex != null else Vector2i.ZERO


func duration_seconds() -> float:
	return _player.get_stream_length() if _loaded else 0.0


func playhead_seconds() -> float:
	return _player.stream_position if _loaded else 0.0


func set_volume(v: float) -> void:
	_volume = v
	_apply_play_state()


func audio_bus_name() -> String:
	return String(_player.bus)


func audio_gain() -> float:
	return _volume


func _process(_delta: float) -> void:
	if _opened_msec < 0:
		return
	var tex := _player.get_video_texture()
	if tex != null and tex.get_size().x > 0:
		_opened_msec = -1
		_loaded = true
		# The clock creeps a little before the first frame shows.
		_player.stream_position = 0.0
		loaded.emit()
	elif Time.get_ticks_msec() - _opened_msec > FIRST_FRAME_TIMEOUT_MSEC:
		push_warning("NativeVideoBackend: no frame from %s." % _player.stream.file)
		close()
		load_failed.emit()


## Speed 0 and silent while paused; see the class comment.
func _apply_play_state() -> void:
	var on := _playing and _loaded
	_player.speed_scale = 1.0 if on else 0.0
	_player.volume = _volume if on else 0.0


## At the end the player stops, and play() on a stopped player starts
## over from 0: restart it where it was.
func _resume() -> void:
	if not _player.is_playing():
		var t := _player.stream_position
		_player.play()
		_player.stream_position = t
