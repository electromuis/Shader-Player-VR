class_name StudioRecorder
extends RefCounted

## Performance recording: move things and turn knobs while the music
## plays, and the moves become keys (see "VR Studio — Plan.md", Keyframes
## and timing).
##
## A take runs from a pre-roll (PRE_ROLL before where it starts: the loop's
## in point, else the playhead) and records from `from` until it's stopped,
## or, while looping, until the loop's out point (punch-in: only that
## passage is replaced). What it records ("latch"): each armed property
## (the inspector's record dots) from the moment you first touch it, and
## any object you grab, from when you grab it. Once touched, the recorder
## holds it: letting go keeps the last value until the take ends, and the
## playing curve doesn't fight you. Every frame from `from` on, each
## touched thing's value is sampled; a slider moved this frame is sampled
## at the playhead it was moved at, so the take isn't a frame late.
##
## When the take ends (finish), each stream is thinned to keys
## (StudioKeyThinning) and replaces that property's keys over the time it
## was recorded (EditModel.replace_keys), all as one undo step; a transform
## channel that didn't change isn't written. The app calls tick() every
## frame while a take runs; tick says when the take should end (the loop
## came back round, or the out point passed).

const PRE_ROLL := 2.0
## Thinning tolerances: sliders a half percent of their range; colours;
## position, turn and size.
const PARAM_TOLERANCE := 0.005
const COLOR_TOLERANCE := 0.004
const TRANSFORM_TOLERANCE := {"position": 0.005, "rotation_deg": 0.5, "scale": 0.002}
## A playhead this far behind the last sample means playback jumped back.
const WRAP_SECONDS := 0.05

enum State { IDLE, PRE_ROLL, RECORDING }

var model: EditModel
var runner: ScriptRunner
var state: State = State.IDLE
## Where the take records from, and to (-1: until stopped).
var from := 0.0
var until := -1.0

## Armed properties: "<id>|<field key>" -> {id, field}.
var armed: Dictionary = {}
## What's being recorded: key -> {kind: "param" / "transform", id, field
## or node, latest, samples: [[t, value]]}.
var _streams: Dictionary = {}
var _last_t := -INF


# ---------- arming ----------

static func arm_key(id: String, field: Dictionary) -> String:
	return "%s|%s" % [id, field.key]


## Whether a field can be recorded (it has a track to write: a slot).
static func can_arm(field: Dictionary) -> bool:
	return String(field.get("slot", "")) != "" and field.get("type", "") in ["float", "int", "color", "vec3"]


func set_armed(id: String, field: Dictionary, on: bool) -> void:
	if on and can_arm(field):
		armed[arm_key(id, field)] = {"id": id, "field": field}
	else:
		armed.erase(arm_key(id, field))


func is_armed(id: String, field: Dictionary) -> bool:
	return armed.has(arm_key(id, field))


## Forget arming for objects that are gone.
func prune(ids: Array) -> void:
	for k in armed.keys():
		if not ids.has(armed[k].id):
			armed.erase(k)


# ---------- the take ----------

func is_active() -> bool:
	return state != State.IDLE


## Get ready to record from `start` (to `end`, or -1). Returns where
## playback should start: the pre-roll.
func begin(start: float, end: float = -1.0) -> float:
	_release_all()
	_streams.clear()
	from = maxf(start, 0.0)
	until = end if end > from else -1.0
	_last_t = -INF
	state = State.PRE_ROLL
	return maxf(from - PRE_ROLL, 0.0)


## An armed field was moved to `value` (JSON form: a number, or an array).
func touch_param(id: String, field: Dictionary, value) -> void:
	if not is_active() or not is_armed(id, field):
		return
	var k := arm_key(id, field)
	if not _streams.has(k):
		_streams[k] = {"kind": "param", "id": id, "field": field, "samples": []}
	_streams[k].latest = value
	_streams[k].moved_at = runner.playhead if runner != null else -1.0


## An object was grabbed: record its transform from now on.
func touch_transform(id: String, node: Node3D) -> void:
	if not is_active() or node == null:
		return
	var k := "%s|transform" % id
	if not _streams.has(k):
		_streams[k] = {"kind": "transform", "id": id, "node": node, "samples": []}
		if runner != null:
			runner.held[id] = true


## Whether the take holds this field / object (so letting go writes
## nothing: finish() will).
func owns_param(id: String, field: Dictionary) -> bool:
	return is_active() and is_armed(id, field)


func owns_transform(id: String) -> bool:
	return is_active() and _streams.has("%s|transform" % id)


## Whether anything has been recorded yet.
func has_samples() -> bool:
	return _streams.values().any(func(s): return not s.samples.is_empty())


## One frame at playhead `t`. Returns "" to carry on, or why the take
## should end: "end" (the out point passed), "wrapped" (playback jumped
## back, as looping does).
func tick(t: float) -> String:
	if not is_active():
		return ""
	if state == State.RECORDING and t < _last_t - WRAP_SECONDS:
		return "wrapped"
	if state == State.PRE_ROLL and t >= from:
		state = State.RECORDING
	if state != State.RECORDING:
		return ""
	var end := until >= 0.0 and t >= until
	if end:
		t = until
	for s in _streams.values():
		var v = _value_now(s)
		if v == null:
			continue
		var at := t
		var moved := float(s.get("moved_at", -1.0))
		if moved >= 0.0:
			s.moved_at = -1.0
			var prev: float = s.samples.back()[0] if not s.samples.is_empty() else from
			at = clampf(moved, prev, t)
		s.samples.append([at, v])
	_last_t = t
	return "end" if end else ""


func _value_now(s: Dictionary):
	if s.kind == "param":
		return s.get("latest")
	var node: Node3D = s.node
	if not is_instance_valid(node):
		return null
	return GrabMath.to_dict(node.transform)


## End the take: write what was recorded as one undo step. Returns its
## undo label ("" if nothing was written).
func finish() -> String:
	if not is_active():
		return ""
	state = State.IDLE
	var takes: Array = []  # [type, target, name, t0, t1, keys]
	for s in _streams.values():
		if s.samples.size() < 1:
			continue
		var t0: float = s.samples[0][0]
		var t1: float = s.samples.back()[0]
		if s.kind == "param":
			var field: Dictionary = s.field
			var keys := StudioKeyThinning.thin(s.samples, _param_tolerance(field))
			takes.append([ScriptFormat.TRACK_SHADER_PARAM, "%s.%s" % [s.id, field.slot], String(field.param), t0, t1, keys])
		else:
			for ch in ["position", "rotation_deg", "scale"]:
				var ch_samples: Array = s.samples.map(func(p): return [p[0], p[1][ch]])
				var tol = TRANSFORM_TOLERANCE[ch]
				if ch == "scale":
					tol = tol * maxf(Interpolation.to_vec3(ch_samples[0][1]).length() / sqrt(3.0), 0.01)
				if not _moved(ch_samples, tol):
					continue
				takes.append([ScriptFormat.TRACK_TRANSFORM, s.id, ch, t0, t1, StudioKeyThinning.thin(ch_samples, tol)])
	_release_all()
	var label := ""
	if not takes.is_empty():
		label = "Record %s from %s to %s" % [_what(takes), StudioStatus.timecode(_earliest(takes)), StudioStatus.timecode(_latest(takes))]
		model.batch(label, func():
			for tk in takes:
				model.replace_keys(tk[0], tk[1], tk[2], tk[3], tk[4], tk[5]))
	if label == "" and runner != null:
		runner.apply_edit(model.timeline(), false)  # show the piece again
	_streams.clear()
	return label


## Drop the take: nothing is written, the piece plays as it was.
func cancel() -> void:
	if not is_active():
		return
	state = State.IDLE
	_release_all()
	_streams.clear()
	if runner != null and model != null:
		runner.apply_edit(model.timeline(), false)


## The time recorded so far ([from, to]; empty before it starts).
func recorded_span() -> Array:
	if state != State.RECORDING:
		return []
	return [from, maxf(_last_t, from)]


func _release_all() -> void:
	if runner == null:
		return
	for s in _streams.values():
		if s.kind == "param":
			runner.held_params.erase("%s.%s:%s" % [s.id, s.field.slot, s.field.param])
		else:
			runner.held.erase(String(s.id))


static func _param_tolerance(field: Dictionary):
	if field.get("type") == "color":
		return COLOR_TOLERANCE
	var span := absf(float(field.get("max", 1.0)) - float(field.get("min", 0.0)))
	return maxf(span, 1e-3) * PARAM_TOLERANCE


static func _moved(samples: Array, tol: float) -> bool:
	var first := Interpolation.to_vec3(samples[0][1])
	for p in samples:
		if Interpolation.to_vec3(p[1]).distance_to(first) > tol:
			return true
	return false


static func _what(takes: Array) -> String:
	var names := {}
	for tk in takes:
		names[String(tk[1]).split(".")[0] + ("" if tk[0] == ScriptFormat.TRACK_TRANSFORM else " " + String(tk[2]))] = true
	return ", ".join(names.keys())


static func _earliest(takes: Array) -> float:
	return takes.map(func(tk): return tk[3]).min()


static func _latest(takes: Array) -> float:
	return takes.map(func(tk): return tk[4]).max()
