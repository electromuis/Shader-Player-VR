class_name GozenVideoBackend
extends VideoBackend

## FFmpeg decoding through gde_gozen's VideoPlayback: every container and
## codec FFmpeg knows, local files and network streams. `view` is the
## VideoPlayback itself (a Control drawing through a canvas_item YUV→RGB
## shader).
##
## Opening a video runs off the main thread. VideoPlayback.set_video_path
## starts the open on a worker but then waits for it on the very next frame,
## so the app still stalled for the whole open (hundreds of ms locally, far
## more over DLNA). Instead this opens the GoZenVideo and its audio on its
## own worker, polls for completion, and hands both to update_video().
## Opening another video meanwhile doesn't wait: the stale result is dropped.
## A failed open is retried once (network streams fail now and then) before
## load_failed is reported.
##
## Seeking runs off the main thread too. FFmpeg's seek (find the keyframe,
## decode up to the target) can take a second or more — longer over the
## network — and done inline it froze the whole app, headset included, on
## every scrub step. A seek now runs as a WorkerThreadPool task while the
## decoder is paused; requests arriving meanwhile collapse into one follow-up
## seek to the latest position.
##
## VideoPlayback's own audio sync never runs (it waits for its frame-time
## remainder, always under one frame, to pass 1.2 s), so the sound drifted
## until the next seek. _resync_audio does the check instead: past
## AUDIO_DRIFT_MAX it moves the sound to the frame, as a seek would.

const PLAYBACK_SCRIPT_PATH := "res://addons/gde_gozen/video_playback.gd"
const PROBE_CLASS := "GoZenVideo"
## Tries at opening a video (and its audio) before giving up.
const OPEN_ATTEMPTS := 2
## Sound further off the picture than this (seconds) is moved back to it.
const AUDIO_DRIFT_MAX := 0.1
const AUDIO_CHECK_MSEC := 500
## Left alone this long after starting, while the audio output fills up.
const AUDIO_SETTLE_MSEC := 1000

## Try FFmpeg's hardware decoders first, from the next open on.
var prefer_hw_decoding: bool = false

var _vp: Node  # VideoPlayback (Control), also `view`
var _loaded: bool = false
var _load_path: String = ""  # the video asked for most recently
var _load_task: int = -1
var _open_path: String = ""  # what _load_task is opening
var _open_attempt: int = 0  # which try _load_task is, from 1
var _opened: Array = []  # [GoZenVideo or null, AudioStream or null], set by the worker
## Worker tasks whose result no longer matters (a seek on a replaced video);
## still reaped, since every task must be waited on.
var _stale_tasks: Array[int] = []
## Whether playback should run once any seek completes (the decoder itself
## is paused while seeking).
var _want_playing: bool = false
var _seek_task: int = -1
var _seek_frame: int = 0
var _seek_error: int = OK  # written by the worker, read after it completes
var _pending_frame: int = -1  # latest request made during a seek; -1 = none
var _next_audio_check_msec: int = 0


static func is_available() -> bool:
	return ClassDB.class_exists(PROBE_CLASS) and ResourceLoader.exists(PLAYBACK_SCRIPT_PATH)


static func can_play(_path: String) -> bool:
	return is_available()


func _init() -> void:
	_vp = load(PLAYBACK_SCRIPT_PATH).new()
	_vp.name = "VideoPlayback"
	_vp.enable_audio = true
	_vp.enable_auto_play = false
	_vp.anchor_right = 1.0
	_vp.anchor_bottom = 1.0
	_vp.video_loaded.connect(_on_video_loaded)
	view = _vp


func _exit_tree() -> void:
	_wait_for_seek()
	for t in _stale_tasks + ([_load_task] if _load_task != -1 else []):
		WorkerThreadPool.wait_for_task_completion(t)


func load_video(path: String) -> void:
	_drop_seek()
	_loaded = false
	_load_path = path
	_vp.close()  # stop the old video and its sound now
	if _load_task == -1:
		_start_open()
	# else: _finish_open sees the newer path and opens that instead.


func close() -> void:
	_drop_seek()
	_loaded = false
	_load_path = ""
	_vp.close()


func play() -> void:
	_want_playing = true
	if _loaded and _seek_task == -1:
		_start_playback()


func pause() -> void:
	_want_playing = false
	if _loaded and _seek_task == -1:
		_vp.pause()


## Asynchronous: the frame (and audio) jump once the decoder gets there.
func seek_seconds(t: float) -> void:
	if not _loaded:
		return
	var fps: float = _vp.get_video_framerate()
	if fps <= 0.0:
		return
	var frame := clampi(roundi(t * fps), 0, maxi(_vp.get_video_frame_count() - 1, 0))
	if _seek_task != -1:
		_pending_frame = frame
		return
	_start_seek(frame)
	seeking_changed.emit(true)


func is_seeking() -> bool:
	return _seek_task != -1


func is_playing() -> bool:
	return _loaded and _vp.is_playing


func resolution() -> Vector2i:
	return _vp.video.get_resolution() if _loaded else Vector2i.ZERO


func duration_seconds() -> float:
	return _vp.get_video_length_float() if _loaded else 0.0


func playhead_seconds() -> float:
	return _vp.get_current_playback_position_float() if _loaded else 0.0


func framerate() -> float:
	return _vp.get_video_framerate() if _loaded else 0.0


## Applied to gozen's AudioStreamPlayer.
func set_volume(v: float) -> void:
	if _vp.audio_player != null:
		_vp.audio_player.volume_db = linear_to_db(v) if v > 0.0 else -80.0


func audio_bus_name() -> String:
	return String(_vp.audio_player.bus) if _vp.audio_player != null else ""


func audio_gain() -> float:
	return db_to_linear(_vp.audio_player.volume_db) if _vp.audio_player != null else 1.0


## A seek in flight belongs to the video being replaced; the worker holds
## its own reference to that decoder, so let it finish unobserved.
func _drop_seek() -> void:
	if _seek_task != -1:
		_stale_tasks.append(_seek_task)
		_seek_task = -1
		seeking_changed.emit(false)
	_pending_frame = -1


func _start_seek(frame: int) -> void:
	if _vp.is_playing:
		_vp.pause()
	_seek_frame = frame
	_seek_task = WorkerThreadPool.add_task(_seek_worker.bind(_vp.video, frame))


## Worker thread: only touches the decoder, which the main thread leaves
## alone while _seek_task is set (VideoPlayback is paused).
func _seek_worker(video: Object, frame: int) -> void:
	_seek_error = video.seek_frame(frame)


func _start_open(retry: bool = false) -> void:
	_open_attempt = _open_attempt + 1 if retry else 1
	_open_path = _load_path
	_opened = []
	_load_task = WorkerThreadPool.add_task(_open_worker.bind(_open_path))


## Worker thread: the slow part of a load (probing the file / stream).
func _open_worker(path: String) -> void:
	# ClassDB and base types, never the gozen class names: exports load gozen
	# at runtime (GoZenLoader), after GDScript has listed the classes it can
	# compile against, so naming one fails or crashes.
	var video: Resource = ClassDB.instantiate("GoZenVideo")
	# Decode on the GPU where the codec allows (NVDEC, D3D11VA, ...) if
	# asked; gozen falls back to software by itself. Older gozen builds lack
	# the flag.
	if video.has_method("set_prefer_hw_decoding"):
		video.set_prefer_hw_decoding(prefer_hw_decoding)
	# open() doesn't always report failure (e.g. a missing file); is_open() does.
	if video.open(path) or not video.is_open():
		video = null
	var audio: AudioStream = null
	if video != null:
		# A stream that dropped the audio probe would otherwise play silent;
		# a local file without sound isn't worth a second probe.
		var tries := OPEN_ATTEMPTS if DefaultScreen.is_url(path) else 1
		for i in tries:
			var stream: AudioStream = ClassDB.instantiate("AudioStreamFFmpeg")
			if stream.open(path, -1) == OK:
				audio = stream
				break
	_opened = [video, audio]


func _finish_open() -> void:
	if _load_path == "":
		return  # closed while opening
	if _open_path != _load_path:
		_start_open()  # superseded while opening
		return
	var video: Object = _opened[0]
	var audio: AudioStream = _opened[1]
	_opened = []
	if video == null and _open_attempt < OPEN_ATTEMPTS:
		push_warning("GozenVideoBackend: could not open %s, retrying." % _load_path)
		_start_open(true)
		return
	if video == null:
		load_failed.emit()
		return
	if video.has_method("get_hw_device"):
		var hw: String = video.get_hw_device()
		print("Video decoding: %s" % (hw if hw != "" else "software"))
	# No audio track: say so, or update_video retries the open on this thread.
	_vp.enable_audio = audio != null
	_vp.update_video(video, audio)  # → video_loaded → _on_video_loaded


func _process(_delta: float) -> void:
	_resync_audio()
	for t in _stale_tasks.duplicate():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_stale_tasks.erase(t)
	if _load_task != -1 and WorkerThreadPool.is_task_completed(_load_task):
		WorkerThreadPool.wait_for_task_completion(_load_task)
		_load_task = -1
		_finish_open()
	if _seek_task == -1 or not WorkerThreadPool.is_task_completed(_seek_task):
		return
	WorkerThreadPool.wait_for_task_completion(_seek_task)
	_seek_task = -1
	_vp.current_frame = _seek_frame
	if _seek_error:
		push_warning("GozenVideoBackend: seek to frame %d failed." % _seek_frame)
	else:
		_vp._set_frame_image()
	if _pending_frame >= 0:
		var next := _pending_frame
		_pending_frame = -1
		_start_seek(next)
		return
	seeking_changed.emit(false)
	if _want_playing:
		_start_playback()


## play() also moves the audio to current_frame.
func _start_playback() -> void:
	_vp.play()
	_next_audio_check_msec = Time.get_ticks_msec() + AUDIO_SETTLE_MSEC


func _resync_audio() -> void:
	if not _loaded or _seek_task != -1 or not _vp.is_playing 			or Time.get_ticks_msec() < _next_audio_check_msec:
		return
	_next_audio_check_msec = Time.get_ticks_msec() + AUDIO_CHECK_MSEC
	var player: AudioStreamPlayer = _vp.audio_player
	if not _vp.enable_audio or player == null or not player.playing or player.stream_paused:
		return
	var fps: float = _vp.get_video_framerate()
	if fps <= 0.0:
		return
	# The same reckoning VideoPlayback.play() starts the sound with.
	var picture: float = (_vp.current_frame + 1) / fps
	var drift := player.get_playback_position() + AudioServer.get_time_since_last_mix() - picture
	if absf(drift) > AUDIO_DRIFT_MAX:
		print("Video audio drifted %.0f ms; resyncing." % (drift * 1000.0))
		player.seek(picture)
		_next_audio_check_msec = Time.get_ticks_msec() + AUDIO_SETTLE_MSEC


func _wait_for_seek() -> void:
	if _seek_task != -1:
		WorkerThreadPool.wait_for_task_completion(_seek_task)
		_seek_task = -1


func _on_video_loaded() -> void:
	_loaded = true
	loaded.emit()
