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
## The sound is the clock. It plays on through a hitch, but the picture
## only moves by the frame's delta, which Godot also cuts short (to about
## 150 ms), so after a long frame the picture is behind the sound. Pulling
## the sound back to the picture (as this did before) made every hitch an
## audible jump back and forth. _follow_sound sets the picture's clock
## from the sound instead, before VideoPlayback runs each frame: it skips
## the frames it's behind, or waits when it's ahead (Godot hands out the
## stalled time over the frames after a hitch, so delta alone overshoots).
## Further behind than CATCH_UP_SEEK it seeks on a worker to where the sound
## will be, the sound playing on meanwhile. Only sound far behind the
## picture (AUDIO_BEHIND_MAX: it stalled) is moved to it. (VideoPlayback's
## own audio sync never runs: it waits for its frame-time remainder, always
## under a frame, to pass 1.2 s.)

const PLAYBACK_SCRIPT_PATH := "res://addons/gde_gozen/video_playback.gd"
const PROBE_CLASS := "GoZenVideo"
## Tries at opening a video (and its audio) before giving up.
const OPEN_ATTEMPTS := 2
## Sound further behind the picture than this (seconds) is moved to it.
const AUDIO_BEHIND_MAX := 0.5
## A picture this many frames off the sound is set to it.
const PICTURE_OFF_FRAMES := 1.5
## A picture further behind than this (seconds) seeks to the sound instead
## of decoding every frame in between on the main thread.
const CATCH_UP_SEEK := 0.5
## How long a catch-up seek is expected to take: it aims that far ahead.
const CATCH_UP_LEAD := 0.1
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
## The seek running is a catch-up with the sound (_follow_sound): the sound
## plays on, and it isn't reported as seeking (the timeline doesn't hold).
var _catching_up: bool = false
var _next_audio_check_msec: int = 0


static func is_available() -> bool:
	return ClassDB.class_exists(PROBE_CLASS) and ResourceLoader.exists(PLAYBACK_SCRIPT_PATH)


static func can_play(_path: String) -> bool:
	return is_available()


func _init() -> void:
	_vp = load(PLAYBACK_SCRIPT_PATH).new()
	_vp.name = "VideoPlayback"
	# Its frames arrive on frame_changed: the bridge redraws only then.
	draws_on_demand = true
	_vp.frame_changed.connect(func(_f): frame_changed.emit())
	_vp.enable_audio = true
	_vp.enable_auto_play = false
	_vp.anchor_right = 1.0
	_vp.anchor_bottom = 1.0
	_vp.video_loaded.connect(_on_video_loaded)
	view = _vp
	# _follow_sound sets VideoPlayback's clock before it runs.
	process_priority = -1


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
	# Also during a seek: a catch-up leaves the sound playing.
	if _loaded:
		_vp.pause()


## Asynchronous: the frame (and audio) jump once the decoder gets there.
func seek_seconds(t: float) -> void:
	if not _loaded:
		return
	var fps: float = _vp.get_video_framerate()
	if fps <= 0.0:
		return
	var frame := clampi(roundi(t * fps), 0, maxi(_vp.get_video_frame_count() - 1, 0))
	if _catching_up:
		# The catch-up becomes a seek of the viewer's: silence and report it.
		_catching_up = false
		_vp.pause()
		_pending_frame = frame
		seeking_changed.emit(true)
		return
	if _seek_task != -1:
		_pending_frame = frame
		return
	_start_seek(frame)
	seeking_changed.emit(true)


func is_seeking() -> bool:
	return _seek_task != -1 and not _catching_up


## The audio player's position, plus time since its last mix, minus the
## output latency: the sound being heard now. Only while it's within
## CATCH_UP_SEEK of the picture, which _follow_sound keeps it to: after a
## seek the sound sometimes starts from the wrong place (on some files
## gde_gozen's audio seek lands near 0) until the resync moves it, and the
## timeline, following this, jumped there and back (TODO 78).
func audio_seconds() -> float:
	if not _loaded or _seek_task != -1 or not _vp.is_playing:
		return -1.0
	var ap: AudioStreamPlayer = _vp.audio_player
	if ap == null or ap.stream == null or not ap.playing or ap.stream_paused:
		return -1.0
	var fps: float = _vp.get_video_framerate()
	if fps <= 0.0:
		return -1.0
	var sound := ap.get_playback_position() + AudioServer.get_time_since_last_mix()
	if absf(sound - _picture_seconds(fps)) > CATCH_UP_SEEK:
		return -1.0
	return sound - AudioServer.get_output_latency()


## The picture's own clock: the reckoning VideoPlayback.play() starts the
## sound with, plus the time owed to the next frame.
func _picture_seconds(fps: float) -> float:
	return (_vp.current_frame + 1) / fps + _vp._time_elapsed


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
		if not _catching_up:
			seeking_changed.emit(false)
	_catching_up = false
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


func _process(delta: float) -> void:
	_follow_sound(delta)
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
	var caught_up := _catching_up
	_catching_up = false
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
	if caught_up:
		# The sound played on: carry on from here without restarting it
		# (_follow_sound skips whatever the seek took longer than aimed).
		if _want_playing:
			_vp._time_elapsed = 0.0
			_vp.is_playing = true
		return
	seeking_changed.emit(false)
	if _want_playing:
		_start_playback()


## play() also moves the audio to current_frame.
func _start_playback() -> void:
	_vp.play()
	_next_audio_check_msec = Time.get_ticks_msec() + AUDIO_SETTLE_MSEC


## Keeps the picture with the sound (see the class notes). Every frame
## once the sound has settled after starting, before VideoPlayback adds
## `delta` to its clock.
func _follow_sound(delta: float) -> void:
	if not _loaded or _seek_task != -1 or not _vp.is_playing 			or Time.get_ticks_msec() < _next_audio_check_msec:
		return
	var player: AudioStreamPlayer = _vp.audio_player
	if not _vp.enable_audio or player == null or not player.playing or player.stream_paused:
		return
	var fps: float = _vp.get_video_framerate()
	if fps <= 0.0:
		return
	var picture: float = _picture_seconds(fps) + delta
	var sound := player.get_playback_position() + AudioServer.get_time_since_last_mix()
	var behind := sound - picture
	if behind > CATCH_UP_SEEK:
		_catch_up(sound + CATCH_UP_LEAD, fps)
	elif behind < -AUDIO_BEHIND_MAX:
		print("Video audio behind the picture by %.0f ms; resyncing." % (-behind * 1000.0))
		player.seek((_vp.current_frame + 1) / fps)
		_next_audio_check_msec = Time.get_ticks_msec() + AUDIO_SETTLE_MSEC
	elif absf(behind) > PICTURE_OFF_FRAMES / fps:
		# VideoPlayback skips the frames it's behind, or waits.
		_vp._time_elapsed += behind


## Seek the picture to `t` on a worker while the sound plays on.
func _catch_up(t: float, fps: float) -> void:
	var last := maxi(_vp.get_video_frame_count() - 1, 0)
	var frame := clampi(roundi(t * fps), 0, last)
	if frame >= last:
		return  # at the end: let it run out
	print("Video picture %.0f ms behind the sound; catching up." % ((t - CATCH_UP_LEAD - (_vp.current_frame + 1) / fps) * 1000.0))
	# The decoder is the worker's until it's done; the sound isn't paused.
	_vp.is_playing = false
	_catching_up = true
	_seek_frame = frame
	_seek_task = WorkerThreadPool.add_task(_seek_worker.bind(_vp.video, frame))


func _wait_for_seek() -> void:
	if _seek_task != -1:
		WorkerThreadPool.wait_for_task_completion(_seek_task)
		_seek_task = -1


func _on_video_loaded() -> void:
	_loaded = true
	loaded.emit()
