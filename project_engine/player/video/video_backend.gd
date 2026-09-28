class_name VideoBackend
extends Node

## One way of decoding video, for VideoBridge. The bridge owns what the
## screens sample (a SubViewport) and the cards drawn over the picture; a
## backend supplies `view`, the Control that draws the decoded video into
## that viewport, plus playback control and the video's sound.
##
## Subclasses also define two static functions the bridge calls before
## instantiating one:
##   is_available() -> bool       the decoder is loaded on this platform
##   can_play(path) -> bool       it can open this file / URL

## The video opened and its first frame is ready: resolution(),
## duration_seconds() etc. are valid.
signal loaded
signal load_failed
## A seek started or finished, for backends whose seeks take a while.
signal seeking_changed(seeking: bool)
## A new frame was drawn into `view` (backends that set draws_on_demand).
signal frame_changed

## Draws the video, sized to fill its parent. The bridge adds it to its
## viewport and hides it while another backend is in use.
var view: Control
## True when frame_changed says when the picture changes, so the bridge can
## render its viewport only then; false: it renders every frame.
var draws_on_demand := false


## Starts opening `path` (absolute OS path or URL); ends in `loaded` or
## `load_failed`. Opening another meanwhile replaces it.
func load_video(_path: String) -> void:
	pass


## Stops the current video and its sound.
func close() -> void:
	pass


func play() -> void:
	pass


func pause() -> void:
	pass


func seek_seconds(_t: float) -> void:
	pass


func is_seeking() -> bool:
	return false


func is_playing() -> bool:
	return false


## Native size of the decoded frame, ZERO before load.
func resolution() -> Vector2i:
	return Vector2i.ZERO


func duration_seconds() -> float:
	return 0.0


func playhead_seconds() -> float:
	return 0.0


## Frames per second, 0 when the decoder doesn't say.
func framerate() -> float:
	return 0.0


## Linear 0..1.
func set_volume(_v: float) -> void:
	pass


## AudioServer bus the video's sound plays on ("" if none).
func audio_bus_name() -> String:
	return ""


## Linear gain set_volume applies before the sound reaches the bus.
func audio_gain() -> float:
	return 1.0


## Media seconds of the sound being heard now (for the beat clock), or -1
## when that isn't known (paused, seeking, no sound, or the backend can't
## tell): then the playhead stands in.
func audio_seconds() -> float:
	return -1.0
