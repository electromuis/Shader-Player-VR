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

## [{id, depth, parent, spans: [[from, to]], ends: [{spawn, despawn}]}]
## for every object, in file order; depth = how many parents it has. The
## viewer ("$viewer"), when the piece moves it, comes first: its span from
## its first key, `warn` the stretches too fast for comfort (comfort()). Each
## span's ends are the track indices of the events that make it: its spawn,
## and the despawn of this object that ends it (-1 when it runs to the end,
## or its parent's despawn or its own respawn ends it).
static func lanes(model: EditModel, until: float) -> Array:
	var out := _object_lanes(model, until)
	var vt := ViewerTrack.new()
	vt.build(model.tracks())
	if not vt.is_empty():
		out.push_front({"id": ScriptFormat.VIEWER, "depth": 0, "parent": "", "spans": [[vt.start_time(), maxf(until, vt.start_time())]],
				"ends": [{"spawn": -1, "despawn": -1}], "warn": comfort(vt, vt.start_time(), until)})
	return out


static func _object_lanes(model: EditModel, until: float) -> Array:
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
	var open := {}  # id -> [since, spawn index]
	var spans := {}
	var ends := {}
	for id in ids:
		spans[id] = []
		ends[id] = []
	var close := func(id: String, at: float, by: int, rec: Callable) -> void:
		if open.has(id):
			spans[id].append([open[id][0], at])
			ends[id].append({"spawn": open[id][1], "despawn": by})
			open.erase(id)
		for child in ids:
			if parent.get(child, "") == id:
				rec.call(child, at, -1, rec)
	for e in events:
		var t: float = e[0]
		var ev: Dictionary = e[2]
		match ev.get("action"):
			"spawn":
				var id := String(ev.get("id", ""))
				close.call(id, t, -1, close)  # a respawn starts afresh (children too)
				open[id] = [t, e[1]]
			"despawn":
				close.call(String(ev.get("target", "")), t, e[1], close)
	for id in open:
		spans[id].append([open[id][0], maxf(until, open[id][0])])
		ends[id].append({"spawn": open[id][1], "despawn": -1})
	var out: Array = []
	for id in ids:
		var depth := 0
		var p: String = parent.get(id, "")
		while p != "" and depth < 32:
			depth += 1
			p = parent.get(p, "")
		out.append({"id": id, "depth": depth, "parent": parent.get(id, ""), "spans": spans[id], "ends": ends[id]})
	return out


## How far span `si` of `lane` can stretch, as [earliest start, latest
## end]: not into its neighbours, and inside its parent's time on stage.
static func span_limits(all_lanes: Array, lane: Dictionary, si: int, until: float) -> Array:
	var span: Array = lane.spans[si]
	var lo := 0.0
	var hi := maxf(until, span[1])
	if si > 0:
		lo = lane.spans[si - 1][1]
	if si + 1 < lane.spans.size():
		hi = lane.spans[si + 1][0]
	for other in all_lanes:
		if other.id == lane.parent:
			for ps in other.spans:
				if ps[0] <= span[0] + EditModel.SAME_TIME and span[0] < ps[1]:
					lo = maxf(lo, ps[0])
					hi = minf(hi, ps[1])
	return [lo, hi]


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
	var vt := ViewerTrack.new()
	vt.build(model.tracks())
	return vt.cuts_between(-INF, INF).map(func(c): return float(c.t))


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
## Comfort limits for the viewer's motion (see "Animating the viewer").
const COMFORT_SPEED := 3.0  # m/s
const COMFORT_TURN := 30.0  # °/s


## The stretches of `vt` between `t0` and `t1` where the viewer moves faster
## than COMFORT_SPEED or turns faster than COMFORT_TURN: [[from, to]],
## sampled every `step` seconds.
static func comfort(vt: ViewerTrack, t0: float, t1: float, step: float = 0.1) -> Array:
	var out: Array = []
	var t := t0
	var open := -1.0
	while t <= t1 + 1e-6:
		var m := vt.motion_at(t)
		var bad: bool = m.speed > COMFORT_SPEED or m.turn > COMFORT_TURN
		if bad and open < 0.0:
			open = t
		elif not bad and open >= 0.0:
			out.append([open, t])
			open = -1.0
		t += step
	if open >= 0.0:
		out.append([open, t1])
	return out


## Tap tempo: taps further apart than this start over.
const TAP_GAP := 2.0
## Taps needed before they set a grid.
const TAPS := 4


## The grid tapped out by `taps` (playhead times, in order): the tempo from
## their average spacing, the downbeat where the taps fit best (on the last
## tap's beat). null until there are TAPS of them.
static func tap_tempo(taps: Array, beats_per_bar: int = 4) -> BeatGrid:
	if taps.size() < TAPS:
		return null
	var span := float(taps.back()) - float(taps[0])
	if span <= 0.0:
		return null
	var bpm := snappedf(60.0 * (taps.size() - 1) / span, 0.1)
	var spb := 60.0 / bpm
	var last := float(taps.back())
	var phase := 0.0
	for t in taps:
		var d := float(t) - last
		phase += d - roundf(d / spb) * spb
	return BeatGrid.make(bpm, last + phase / taps.size(), beats_per_bar)


static func snap(t: float, grid: BeatGrid) -> float:
	if grid == null or not grid.is_valid():
		return t
	return grid.time_of_beat(roundf(grid.beat_at(t)))
