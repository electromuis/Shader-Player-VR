class_name ViewerTrack
extends RefCounted

## Where a script puts the viewer over time: smooth moves (rides, drifts)
## and cuts, as one track (see "VR Studio — Plan.md", Animating the viewer).
##
## In the file it's `transform` tracks with target "$viewer" (channels
## `position`, the eye, and `rotation_deg`, of which the headset uses only
## the yaw), plus the older `vr_cut` / `vr_teleport` events, which join the
## same track as keys the viewer jumps to. A key the viewer *jumps* to is a
## cut: one reached by a `step` segment (the key before holds, then the
## viewer is moved), every event cut, and the first key (from the home seat).
## A key may carry a `transition` ({"type": "fade_to_black", "duration": s})
## for its cut. Before the first key the viewer is at home (pose_at gives
## {}).
##
## "Cuts only" (the viewer's comfort setting): nothing glides; the viewer
## holds each key's pose until the next one, and every key is a cut, faded
## (FADE_SECONDS unless the key has its own transition).
##
## Pure: the Stage asks it where the viewer should be, and whether playback
## just passed a cut.

const TARGET := "$viewer"
const FADE_SECONDS := 0.5

## Interpolation-style keyframes per channel ("position", "rotation_deg").
var _keys := {"position": [], "rotation_deg": []}
## The cuts, by time: [{t, transition}].
var _cuts: Array = []
var _cut_times := {}  # t -> true, for quick lookups
var _all_times: Array = []  # every key's time, sorted (cuts-only mode)
var _transitions := {}  # t -> transition of the key there


## The viewer track of a timeline (its "$viewer" tracks and cut events).
static func from_timeline(data: TimelineData) -> ViewerTrack:
	var vt := ViewerTrack.new()
	if data == null:
		return vt
	vt.build(data.tracks)
	return vt


## Build from a script's track list.
func build(tracks: Array) -> void:
	for ch in _keys:
		_keys[ch] = []
	var jumps := {}  # key times the viewer jumps to (event cuts)
	for t in tracks:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if t.get("type") == ScriptFormat.TRACK_TRANSFORM and t.get("target") == TARGET and _keys.has(t.get("channel")):
			for k in t.get("keyframes", []):
				_keys[t.channel].append(k.duplicate(true))
		elif t.get("type") == ScriptFormat.TRACK_EVENT and t.get("action") in ["vr_cut", "vr_teleport"] and typeof(t.get("to")) == TYPE_DICTIONARY:
			var at := float(t.get("t", 0.0))
			jumps[at] = true
			var to: Dictionary = t.to
			var pos := {"t": at, "value": Interpolation.to_vec3(to.get("position", [0, 0, 0]))}
			var rot := {"t": at, "value": Interpolation.to_vec3(to.get("rotation_deg", [0, 0, 0])) if typeof(to.get("rotation_deg")) == TYPE_ARRAY else Vector3.ZERO}
			for k in [pos, rot]:
				k.value = [k.value.x, k.value.y, k.value.z]
				if typeof(t.get("transition")) == TYPE_DICTIONARY:
					k["transition"] = t.transition
			_keys.position.append(pos)
			_keys.rotation_deg.append(rot)
	_cuts = []
	_cut_times = {}
	_transitions = {}
	var times := {}
	var earliest := INF
	for ch in _keys:
		var kfs: Array = _keys[ch]
		kfs.sort_custom(func(a, b): return float(a.t) < float(b.t))
		if not kfs.is_empty():
			earliest = minf(earliest, float(kfs[0].t))
	for ch in _keys:
		var kfs: Array = _keys[ch]
		for i in kfs.size():
			var at := float(kfs[i].t)
			times[at] = true
			if kfs[i].has("transition"):
				_transitions[at] = kfs[i].transition
			# A jump: the first key, an event cut, or reached by a step.
			var jump: bool = at == earliest or jumps.has(at) or (i > 0 and String(kfs[i - 1].get("interp", "linear")) == "step")
			if jumps.has(at) and i > 0:
				kfs[i - 1]["interp"] = "step"  # hold until the cut
				kfs[i - 1].erase("out")
				kfs[i].erase("in")
			if jump:
				_cut_times[at] = true
	for at in _cut_times:
		_cuts.append({"t": at, "transition": _transitions.get(at, {})})
	_cuts.sort_custom(func(a, b): return a.t < b.t)
	_all_times = times.keys()
	_all_times.sort()


func is_empty() -> bool:
	return _keys.position.is_empty() and _keys.rotation_deg.is_empty()


## When the viewer first leaves home (INF with no keys).
func start_time() -> float:
	return _all_times[0] if not _all_times.is_empty() else INF


## Where the viewer is at `t`: {position: Vector3, rotation_deg: Vector3},
## or {} before the first key (at home).
func pose_at(t: float, cuts_only: bool = false) -> Dictionary:
	if is_empty() or t < start_time() - 1e-6:
		return {}
	var out := {}
	for ch in _keys:
		var kfs: Array = _keys[ch]
		if kfs.is_empty():
			out[ch] = Vector3.ZERO
			continue
		var v
		if cuts_only:
			v = kfs[0].value
			for k in kfs:
				if float(k.t) <= t + 1e-6:
					v = k.value
		else:
			v = Interpolation.evaluate(kfs, t)
		out[ch] = Interpolation.to_vec3(v)
	return out


## The cuts playback passes going from `a` to `b` (a < t <= b), in order:
## [{t, transition}]. In cuts-only mode every key is one, faded.
func cuts_between(a: float, b: float, cuts_only: bool = false) -> Array:
	var out: Array = []
	if cuts_only:
		for at in _all_times:
			if at > a and at <= b:
				var tr: Dictionary = _transitions.get(at, {})
				out.append({"t": at, "transition": tr if not tr.is_empty() else {"type": "fade_to_black", "duration": FADE_SECONDS}})
		return out
	for c in _cuts:
		if c.t > a and c.t <= b:
			out.append(c)
	return out


## Whether a cut lands exactly at `t` (within a millisecond).
func is_cut_at(t: float) -> bool:
	for c in _cuts:
		if absf(c.t - t) < 0.001:
			return true
	return false


## How fast the viewer moves at `t` (m/s) and turns (°/s), from the smooth
## motion around it (cuts don't count): {speed, turn}.
func motion_at(t: float, dt: float = 0.05) -> Dictionary:
	var a := pose_at(t - dt)
	var b := pose_at(t + dt)
	if a.is_empty() or b.is_empty() or not cuts_between(t - dt, t + dt).is_empty():
		return {"speed": 0.0, "turn": 0.0}
	return {
		"speed": (b.position as Vector3).distance_to(a.position) / (2.0 * dt),
		"turn": absf(wrapf((b.rotation_deg as Vector3).y - (a.rotation_deg as Vector3).y, -180.0, 180.0)) / (2.0 * dt),
	}


## Whether anything moves the viewer smoothly (not only cuts).
func has_motion() -> bool:
	for ch in _keys:
		var kfs: Array = _keys[ch]
		for i in range(1, kfs.size()):
			if not _cut_times.has(float(kfs[i].t)) and kfs[i].value != kfs[i - 1].value:
				return true
	return false
