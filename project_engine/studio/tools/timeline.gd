class_name StudioTimeline
extends RefCounted

## What Studio's timeline ribbon shows and how its pixels map to time, as
## pure logic (the ribbon, studio/ui/timeline_ribbon.gd, draws it; tests
## drive it directly).
##
## The view: `start` seconds at the left edge, `span` seconds across
## `width` pixels, zoomed about a point and scrolled, kept within the
## piece. Lanes: each object's time on stage (spawn → despawn, a respawn
## starts a new span, a parent's despawn ends its children's). The
## selection's rows: one per animated property, with its keys. Cut markers,
## beat and bar ticks thinned to what fits, and snapping a time to the
## nearest beat.

## Narrowest and widest view (seconds across the ribbon).
const MIN_SPAN := 1.0
const MAX_SPAN := 3600.0
## Ticks closer than this (pixels) are thinned out.
const MIN_TICK_PX := 7.0

var start := 0.0
var span := 30.0
var width := 1000.0
## The piece's length (the view stays within it).
var duration := 30.0


# ---------- the view ----------

func x_of(t: float) -> float:
	return (t - start) / span * width


func t_of(x: float) -> float:
	return start + x / width * span


func px_per_second() -> float:
	return width / span


## Everything in view.
func fit() -> void:
	span = clampf(maxf(duration, MIN_SPAN), MIN_SPAN, MAX_SPAN)
	start = 0.0


## Zoom by `factor` (> 1 zooms in) keeping time `about` where it is.
func zoom(factor: float, about: float) -> void:
	if factor <= 0.0:
		return
	var frac := (about - start) / span
	span = clampf(span / factor, MIN_SPAN, clampf(duration, MIN_SPAN, MAX_SPAN))
	start = about - frac * span
	_clamp()


func scroll(seconds: float) -> void:
	start += seconds
	_clamp()


## Scroll just enough to show `t` (with a margin of a tenth of the view).
func follow(t: float) -> void:
	var margin := span * 0.1
	if t < start + margin:
		start = t - margin
	elif t > start + span - margin:
		start = t - span + margin
	_clamp()


func _clamp() -> void:
	start = clampf(start, 0.0, maxf(duration - span, 0.0))


# ---------- what's on it ----------

## [{id, depth, spans: [[from, to]]}] for every object, in file order;
## depth = how many parents it has.
static func lanes(model: EditModel, until: float) -> Array:
	var ids: Array = model.object_ids()
	var parent := {}
	var events: Array = []
	for i in model.tracks().size():
		var t: Dictionary = model.tracks()[i]
		if t.get("type") != "event":
			continue
		events.append([float(t.get("t", 0.0)), i, t])
		if t.get("action") == "spawn" and not parent.has(t.get("id")):
			parent[t.get("id")] = String(t.get("parent", ""))
	events.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var open := {}  # id -> since
	var spans := {}
	for id in ids:
		spans[id] = []
	var close := func(id: String, at: float, rec: Callable) -> void:
		if open.has(id):
			spans[id].append([open[id], at])
			open.erase(id)
		for child in ids:
			if parent.get(child, "") == id:
				rec.call(child, at, rec)
	for e in events:
		var t: float = e[0]
		var ev: Dictionary = e[2]
		match ev.get("action"):
			"spawn":
				var id := String(ev.get("id", ""))
				close.call(id, t, close)  # a respawn starts afresh (children too)
				open[id] = t
			"despawn":
				close.call(String(ev.get("target", "")), t, close)
	for id in open:
		spans[id].append([open[id], maxf(until, open[id])])
	var out: Array = []
	for id in ids:
		var depth := 0
		var p: String = parent.get(id, "")
		while p != "" and depth < 32:
			depth += 1
			p = parent.get(p, "")
		out.append({"id": id, "depth": depth, "spans": spans[id]})
	return out


## The selection's animated properties: [{ti, label, keys: [{ki, t,
## interp}]}], transforms first.
static func property_rows(model: EditModel, id: String) -> Array:
	var rows: Array = []
	var effects := model.effects_of(id)
	for ti in model.tracks().size():
		var t: Dictionary = model.tracks()[ti]
		var target := String(t.get("target", ""))
		var label := ""
		if t.get("type") == ScriptFormat.TRACK_TRANSFORM and target == id:
			label = {"position": "Position", "rotation_deg": "Rotation", "scale": "Scale"}.get(t.get("channel"), str(t.get("channel")))
		elif t.get("type") == ScriptFormat.TRACK_SHADER_PARAM and target.begins_with(id + "."):
			label = "%s %s" % [_slot_label(target.substr(id.length() + 1), effects, model), String(t.get("param", "")).replace("_", " ")]
		else:
			continue
		var keys: Array = []
		var kfs: Array = t.get("keyframes", [])
		for ki in kfs.size():
			keys.append({"ki": ki, "t": float(kfs[ki].get("t", 0.0)), "interp": String(kfs[ki].get("interp", "linear"))})
		rows.append({"ti": ti, "label": label, "keys": keys, "transform": t.get("type") == ScriptFormat.TRACK_TRANSFORM})
	rows.sort_custom(func(a, b): return a.transform and not b.transform or (a.transform == b.transform and a.ti < b.ti))
	return rows


## "effect1" → "Glow" (the effect in that slot), "display" → "Display".
static func _slot_label(slot: String, effects: Array, model: EditModel) -> String:
	if slot.begins_with("effect") and slot.substr(6).is_valid_int():
		var n := int(slot.substr(6))
		for i in effects.size():
			if EditModel.effect_slot(effects, i) == n:
				var key := String(effects[i].get("shader", ""))
				var shaders = model.document().get("shaders", {})
				return StudioConfigEdits.effect_label(key, String(shaders.get(key, "")) if typeof(shaders) == TYPE_DICTIONARY else "")
		return "Effect %d" % (n + 1)
	return slot.capitalize()


## Times of the viewer's cuts.
static func cuts(model: EditModel) -> Array:
	var out: Array = []
	for t in model.tracks():
		if t.get("type") == "event" and t.get("action") in ["vr_cut", "vr_teleport"]:
			out.append(float(t.get("t", 0.0)))
	out.sort()
	return out


## Beat ticks between t0 and t1: [{t, bar}], thinned so neighbours are at
## least MIN_TICK_PX apart (every beat, else bars, else every 2^n bars).
static func ticks(grid: BeatGrid, t0: float, t1: float, px_per_s: float) -> Array:
	var out: Array = []
	if grid == null or not grid.is_valid() or t1 <= t0:
		return out
	var beat_px := grid.seconds_per_beat() * px_per_s
	var every: int = 1
	if beat_px < MIN_TICK_PX:
		every = grid.beats_per_bar
		while beat_px * every < MIN_TICK_PX and every < 1 << 20:
			every *= 2
	var first := int(floorf(grid.beat_at(t0) / every)) * every
	var n := first
	while true:
		var t := grid.time_of_beat(n)
		if t > t1:
			break
		if t >= t0:
			out.append({"t": t, "bar": posmod(n, grid.beats_per_bar) == 0})
		n += every
	return out


## `t` on the nearest beat (with `grid`), else as it is.
static func snap(t: float, grid: BeatGrid) -> float:
	if grid == null or not grid.is_valid():
		return t
	return grid.time_of_beat(roundf(grid.beat_at(t)))
