class_name EffectSwitch
extends RefCounted

## An effect switched on and off over time: a `shader_param` track with
## param `enabled` on `<id>.effect<N>`, `<id>.vertex<N>` or
## `$camera.effect<N>`, whose keys are true / false (numbers read as on
## when above 0). Each key holds until the next; one carrying
## `"transition": {"type": "fade", "duration": s}` fades over s seconds from
## the key on (the effect's mix going to or from 0). The effect keeps its
## place in the stack while off, so `effect<N>` targets never shift.
##
## level() is what the player applies: 0 (off) .. 1 (on), multiplying the
## effect's mix.

const PARAM := "enabled"


## Whether `value` (a key's) means on.
static func is_on(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL: return value
		TYPE_INT, TYPE_FLOAT: return float(value) > 0.0
		TYPE_STRING: return value not in ["", "false", "off", "0"]
	return true


## A key's fade duration (seconds; 0 = a hard switch).
static func fade_of(key: Dictionary) -> float:
	var tr = key.get("transition")
	if typeof(tr) == TYPE_DICTIONARY and tr.get("type", "") == "fade":
		return maxf(float(tr.get("duration", 0.0)), 0.0)
	return 0.0


## How much the effect shows at `t` (0..1). Before the first key it's that
## key's state.
static func level(keyframes: Array, t: float) -> float:
	if keyframes.is_empty():
		return 1.0
	var i := -1
	for k in keyframes.size():
		if typeof(keyframes[k]) == TYPE_DICTIONARY and float(keyframes[k].get("t", 0.0)) <= t:
			i = k
	if i < 0:
		return 1.0 if is_on(keyframes[0].get("value", true)) else 0.0
	return _level_after(keyframes, i, t)


## The level at `t`, `i` being the last key at or before it.
static func _level_after(keyframes: Array, i: int, t: float) -> float:
	var key: Dictionary = keyframes[i]
	var target := 1.0 if is_on(key.get("value", true)) else 0.0
	var d := fade_of(key)
	var kt := float(key.get("t", 0.0))
	if d <= 0.0 or t >= kt + d or i == 0:
		return target
	# From wherever the previous key left it (maybe mid-fade itself).
	var from := _level_after(keyframes, i - 1, kt)
	return lerpf(from, target, clampf((t - kt) / d, 0.0, 1.0))
