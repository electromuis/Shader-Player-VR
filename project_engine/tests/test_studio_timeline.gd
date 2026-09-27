extends RefCounted

## Studio's timeline (M4): the view's mapping, zoom and scroll, lanes,
## property rows, cuts, beat ticks and snapping (StudioTimeline), key
## interpolation and bezier presets (EditModel.set_key_interp), and the
## waveform's reduction (StudioWaveform.reduce).

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 60.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn", "group": "res://player/prefabs/group.tscn"},
	"shaders": {"glow": "res://player/visualizer/effects/glow.gdshader"},
	"tracks": [
		{"type": "event", "t": 0, "action": "spawn", "id": "rig", "prefab": "group"},
		{"type": "event", "t": 2, "action": "spawn", "id": "scr", "prefab": "screen", "parent": "rig",
			"config": {"effects": [{"shader": "glow"}]}},
		{"type": "event", "t": 20, "action": "despawn", "target": "rig"},
		{"type": "event", "t": 30, "action": "spawn", "id": "rig", "prefab": "group"},
		{"type": "event", "t": 10, "action": "vr_cut", "to": {"position": [0, 2, 8]}},
		{"type": "shader_param", "target": "scr.effect0", "param": "intensity", "keyframes": [
			{"t": 2, "value": 0.0}, {"t": 6, "value": 2.0}]},
		{"type": "transform", "target": "scr", "channel": "position", "keyframes": [
			{"t": 2, "value": [0, 1, 0]}, {"t": 4, "value": [2, 1, 0], "interp": "ease"}, {"t": 8, "value": [2, 3, 0]}]},
	],
}


static func _model(tc: TestCase) -> EditModel:
	var r := EditModel.from_text(JSON.stringify(DOC), "")
	tc.assert_ok(r)
	return r.get("model")


static func _r(v: float) -> float:
	return snappedf(v, 0.0001)


## Numbers (nested) as text to 4 places, to compare without float noise.
static func _s(v) -> String:
	if typeof(v) == TYPE_ARRAY:
		return "[%s]" % ", ".join(v.map(func(x): return _s(x)))
	return "%.4f" % float(v)


static func test_view_maps_zooms_and_scrolls(tc: TestCase) -> void:
	var v := StudioTimeline.new()
	v.duration = 60.0
	v.width = 600.0
	v.fit()
	tc.assert_eq(v.span, 60.0)
	tc.assert_eq(v.x_of(30.0), 300.0)
	tc.assert_eq(v.t_of(150.0), 15.0)
	v.zoom(2.0, 15.0)
	tc.assert_eq(v.span, 30.0)
	tc.assert_eq(_r(v.x_of(15.0)), 150.0, "the time under the zoom stays put")
	v.scroll(100.0)
	tc.assert_eq(v.start, 30.0, "no further than the end")
	v.zoom(0.1, 40.0)
	tc.assert_eq(v.span, 60.0, "no wider than the piece")
	tc.assert_eq(v.start, 0.0)
	v.zoom(1000.0, 10.0)
	tc.assert_eq(v.span, StudioTimeline.MIN_SPAN)
	v.follow(40.0)
	tc.assert_true(40.0 >= v.start and 40.0 <= v.start + v.span, "follows the playhead")


static func test_lanes_and_rows(tc: TestCase) -> void:
	var m := _model(tc)
	var lanes := StudioTimeline.lanes(m, 60.0)
	tc.assert_eq(lanes.map(func(l): return l.id), ["rig", "scr"])
	tc.assert_eq(lanes[0].spans, [[0.0, 20.0], [30.0, 60.0]], "despawned, then back")
	tc.assert_eq(lanes[1].spans, [[2.0, 20.0]], "goes with its parent")
	tc.assert_eq(lanes[1].depth, 1)
	var rows := StudioTimeline.property_rows(m, "scr")
	tc.assert_eq(rows.map(func(r): return r.label), ["Position", "Glow intensity"])
	tc.assert_eq(rows[0].keys.map(func(k): return [k.t, k.interp]), [[2.0, "linear"], [4.0, "ease"], [8.0, "linear"]])
	tc.assert_eq(StudioTimeline.cuts(m), [10.0])
	tc.assert_eq(StudioTimeline.property_rows(m, "rig"), [])


static func test_beat_ticks_thin_out_and_snap(tc: TestCase) -> void:
	var g := BeatGrid.make(120.0, 0.25)  # a beat every 0.5 s, bars of 2 s
	var close := StudioTimeline.ticks(g, 0.0, 4.0, 100.0)
	tc.assert_eq(close.map(func(k): return k.t), [0.25, 0.75, 1.25, 1.75, 2.25, 2.75, 3.25, 3.75])
	tc.assert_eq(close.map(func(k): return k.bar), [true, false, false, false, true, false, false, false])
	var far := StudioTimeline.ticks(g, 0.0, 40.0, 5.0)  # 2.5 px a beat: bars only (10 px)
	tc.assert_true(far.all(func(k): return k.bar), "only bars")
	tc.assert_eq(_r(far[1].t - far[0].t), 2.0)
	var farther := StudioTimeline.ticks(g, 0.0, 200.0, 1.0)  # bars 2 px: every 4 bars (8 px)
	tc.assert_eq(_r(farther[1].t - farther[0].t), 8.0)
	tc.assert_eq(StudioTimeline.snap(1.9, g), 1.75)
	tc.assert_eq(StudioTimeline.snap(1.2, null), 1.2, "no grid: as it is")
	tc.assert_eq(StudioTimeline.ticks(null, 0.0, 4.0, 100.0), [])


static func test_key_interpolation_and_presets(tc: TestCase) -> void:
	var m := _model(tc)
	var ti := m.find_track("shader_param", "scr.effect0", "intensity")
	tc.assert_true(m.set_key_interp(ti, 0, "ease_out"))
	var kfs: Array = m.tracks()[ti].keyframes
	tc.assert_eq(kfs[0].interp, "bezier")
	tc.assert_eq(kfs[0].out, [0.0, 0.0])
	tc.assert_eq(_s(kfs[1]["in"]), _s([-1.68, 0.0]), "0.42 of 4 s back, flat")
	tc.assert_eq(m.undo_label(), "Ease Out at 0:02.00")
	tc.assert_ok(ScriptFormat.load_from_dict(JSON.parse_string(m.to_text()), "<t>"), "valid")
	# The curve is an ease out: fast at first, flat at the end.
	var early = Interpolation.evaluate(kfs, 3.0)
	tc.assert_true(float(early) > 0.7, "ahead of linear (0.5) a quarter in (%s)" % early)
	tc.assert_true(m.set_key_interp(ti, 0, "overshoot"))
	var peak := 0.0
	for i in 41:
		peak = maxf(peak, float(Interpolation.evaluate(m.tracks()[ti].keyframes, 2.0 + i * 0.1)))
	tc.assert_true(peak > 2.05, "overshoots the key (peak %.3f)" % peak)
	tc.assert_true(m.set_key_interp(ti, 0, "step"))
	kfs = m.tracks()[ti].keyframes
	tc.assert_eq(kfs[0].interp, "step")
	tc.assert_false(kfs[0].has("out"), "handles go")
	tc.assert_false(kfs[1].has("in"))
	tc.assert_true(m.set_key_interp(ti, 0, "linear"))
	tc.assert_false(m.tracks()[ti].keyframes[0].has("interp"), "linear is the default")
	tc.assert_false(m.set_key_interp(ti, 0, "wobbly"))
	# Arrays: a pair per element.
	var pi := m.find_track("transform", "scr", "position")
	tc.assert_true(m.set_key_interp(pi, 1, "ease_in"))
	tc.assert_eq(_s(m.tracks()[pi].keyframes[1].out), _s([[1.68, 0.0], [1.68, 0.0], [1.68, 0.0]]))
	tc.assert_ok(ScriptFormat.load_from_dict(JSON.parse_string(m.to_text()), "<t>"), "valid")


static func test_retime_onto_a_beat(tc: TestCase) -> void:
	var m := _model(tc)
	var g := BeatGrid.make(120.0, 0.0)
	var ti := m.find_track("shader_param", "scr.effect0", "intensity")
	tc.assert_true(m.move_key(ti, 1, StudioTimeline.snap(6.3, g)))
	tc.assert_eq(m.tracks()[ti].keyframes[1].t, 6.5)


static func test_loop_region(tc: TestCase) -> void:
	var l := StudioLoop.new()
	tc.assert_false(l.is_set())
	l.set_in(10.0)
	tc.assert_eq([l.a, l.b], [10.0, 14.0], "an out point comes with it")
	l.set_out(12.0)
	tc.assert_eq([l.a, l.b], [10.0, 12.0])
	l.set_out(5.0)
	tc.assert_eq([l.a, l.b], [1.0, 5.0], "the in point moves before it")
	tc.assert_eq(l.next_time(6.0), -1.0, "not looping yet")
	l.on = true
	tc.assert_eq(l.next_time(4.9), -1.0)
	tc.assert_eq(l.next_time(5.0), 1.0, "back to the in point")
	tc.assert_eq(l.start_time(3.0), -1.0, "inside: from there")
	tc.assert_eq(l.start_time(8.0), 1.0, "outside: from the in point")


static func test_waveform_reduces_to_peaks(tc: TestCase) -> void:
	var level := PackedFloat32Array()
	for i in 400:  # 4 s at 100 fps: a burst every second
		level.append(0.8 if i % 100 < 5 else 0.05)
	var peaks := StudioWaveform.reduce(level, 100.0)
	tc.assert_eq(peaks.size(), 200, "50 a second")
	tc.assert_eq(peaks[0], 1.0, "loudest is 1")
	tc.assert_eq(_r(peaks[10]), _r(0.05 / 0.8), "the rest in proportion")
	var w := StudioWaveform.new()
	w.peaks = peaks
	tc.assert_eq(w.peak_between(0.9, 1.1), 1.0)
	tc.assert_true(w.peak_between(0.3, 0.6) < 0.1)
	w.free()
