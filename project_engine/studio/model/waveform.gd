class_name StudioWaveform
extends Node

## The piece's sound as a loudness curve for Studio's timeline: decoded
## once on a worker thread (BeatDetector.envelope, through the same streams
## as the beat clock), reduced to RATE peaks per second with the loudest at
## 1, and cached in user://waveforms (keyed by path, size and modified time,
## like the beat grid cache), so opening the piece again is instant.

signal ready_changed

const RATE := 50.0  # peaks per second
const CACHE_DIR := "user://waveforms"
const CACHE_VERSION := 2

## 0..1 peaks, RATE per second; empty until decoded (or if it can't be).
var peaks := PackedFloat32Array()
var path := ""

var _task := -1
var _detector: BeatDetector
var _result: Dictionary = {}


func _exit_tree() -> void:
	_stop()


## Start on `os_path` ("" = none).
func load_for(os_path: String) -> void:
	_stop()
	path = os_path
	peaks = PackedFloat32Array()
	if os_path == "" or DefaultScreen.is_url(os_path) or not FileAccess.file_exists(os_path):
		ready_changed.emit()
		return
	var cached := _load_cache(os_path)
	if not cached.is_empty():
		peaks = cached
		ready_changed.emit()
		return
	_detector = BeatDetector.new()
	_result = {}
	_task = WorkerThreadPool.add_task(_worker.bind(os_path, _detector))


func is_loading() -> bool:
	return _task != -1


## The peak (0..1) over media time t0..t1 (the loudest RATE step in it).
func peak_between(t0: float, t1: float) -> float:
	if peaks.is_empty():
		return 0.0
	var a := clampi(int(t0 * RATE), 0, peaks.size() - 1)
	var b := clampi(int(ceilf(t1 * RATE)), a + 1, peaks.size())
	var m := 0.0
	for i in range(a, b):
		m = maxf(m, peaks[i])
	return m


func _process(_delta: float) -> void:
	if _task == -1 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_detector = null
	if not _result.is_empty():
		peaks = reduce(_result.level, float(_result.fps))
		_save_cache(path, peaks)
	ready_changed.emit()


func _worker(os_path: String, detector: BeatDetector) -> void:
	var stream := BeatClock.open_stream(os_path)
	if stream != null:
		_result = detector.envelope(stream)


func _stop() -> void:
	if _task == -1:
		return
	_detector.cancel()
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_detector = null


## Envelope frames at `fps` to RATE peaks per second, scaled so the loudest
## is 1.
static func reduce(level: PackedFloat32Array, fps: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if level.is_empty() or fps <= 0.0:
		return out
	var per := fps / RATE
	out.resize(int(ceilf(level.size() / per)))
	var top := 0.0
	for i in out.size():
		var a := int(i * per)
		var b := mini(int((i + 1) * per), level.size())
		var m := 0.0
		for j in range(a, maxi(b, a + 1)):
			m = maxf(m, level[mini(j, level.size() - 1)])
		out[i] = m
		top = maxf(top, m)
	if top > 0.0:
		for i in out.size():
			out[i] /= top
	return out


static func _cache_file(os_path: String) -> String:
	var f := FileAccess.open(os_path, FileAccess.READ)
	var size := f.get_length() if f != null else 0
	var key := "%s|%d|%d|%d" % [os_path, size, FileAccess.get_modified_time(os_path), CACHE_VERSION]
	return CACHE_DIR.path_join(key.md5_text() + ".bin")


static func _load_cache(os_path: String) -> PackedFloat32Array:
	var file := _cache_file(os_path)
	if not FileAccess.file_exists(file):
		return PackedFloat32Array()
	return FileAccess.get_file_as_bytes(file).to_float32_array()


static func _save_cache(os_path: String, data: PackedFloat32Array) -> void:
	if os_path == "" or data.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(_cache_file(os_path), FileAccess.WRITE)
	if f != null:
		f.store_buffer(data.to_byte_array())
