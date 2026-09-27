class_name StudioLoop
extends RefCounted

## Studio's loop region, for rehearsing a passage: in and out points (not
## saved with the piece) and whether playback loops between them. Studio
## asks where playback should be each frame (next_time); the ribbon draws
## and drags the points.

## Shortest loop (seconds).
const MIN_LENGTH := 0.25

var on := false
var a := 0.0
var b := 0.0


func is_set() -> bool:
	return b - a >= MIN_LENGTH


## Set the in point; an out point before it (or none) moves after it.
func set_in(t: float) -> void:
	a = maxf(t, 0.0)
	if b < a + MIN_LENGTH:
		b = a + 4.0 if b <= a else a + MIN_LENGTH


## Set the out point; an in point after it moves before it.
func set_out(t: float) -> void:
	b = maxf(t, MIN_LENGTH)
	if a > b - MIN_LENGTH:
		a = maxf(b - 4.0, 0.0)


## Where playback at `t` should go on to: back to the in point once it
## reaches the out point, while looping; -1 = carry on.
func next_time(t: float) -> float:
	if not on or not is_set():
		return -1.0
	return a if t >= b else -1.0


## Where to start playing from `t`: inside the loop stays, outside goes to
## its in point (while looping); -1 = from where it is.
func start_time(t: float) -> float:
	if not on or not is_set():
		return -1.0
	return -1.0 if t >= a and t < b else a
