extends RefCounted

## Studio's performance recording (M6): thinning a recorded stream to keys
## (StudioKeyThinning), replacing a track's keys over a take
## (EditModel.replace_keys), takes of an armed slider and of a grabbed
## object (StudioRecorder: pre-roll, latch, punch-in, the loop coming back
## round, holding the inspector's commit off), tap tempo and the piece's
## beat grid (StudioTimeline.tap_tempo, EditModel.set_beats).

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 30.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn"},
	"shaders": {"glow": "res://player/visualizer/effects/glow.gdshader"},
	"tracks": [
		{"type": "event", "t": 0, "action": "spawn", "id": "scr", "prefab": "screen",
			"config": {"effects": [{"shader": "glow", "params": {"intensity": 1.0}}]}},
		{"type": "shader_param", "target": "scr.effect0", "param": "intensity", "keyframes": [
			{"t": 0, "value": 1.0}, {"t": 1, "value": 1.5}, {"t": 5, "value": 0.5}, {"t": 6, "value": 1.0}]},
	],
}


static func _model(tc: TestCase) -> EditModel:
	var r := EditModel.from_text(JSON.stringify(DOC), "")
	tc.assert_ok(r)
	return r.get("model")


static func _field(tc: TestCase, m: EditModel, key: String) -> Dictionary:
	var edits := StudioConfigEdits.new()
	edits.model = m
	for s in edits.sections("scr", null, "screen"):
		for f in s.get("fields", []):
			if f.key == key:
				return f
	tc.fail("no field %s" % key)
	return {}


## Worst miss of linear keys against the samples.
static func _worst(keys: Array, samples: Array) -> float:
	var worst := 0.0
	for s in samples:
		var v = Interpolation.evaluate(keys, float(s[0]))
		if typeof(v) == TYPE_ARRAY:
			for c in v.size():
				worst = maxf(worst, absf(float(v[c]) - float(s[1][c])))
		else:
			worst = maxf(worst, absf(float(v) - float(s[1])))
	return worst


static func test_thinning_keeps_the_shape_with_few_keys(tc: TestCase) -> void:
	var sine: Array = []
	for i in 361:  # 4 s at 90 Hz
		var t := i / 90.0
		sine.append([t, sin(t * TAU * 0.5)])
	var keys := StudioKeyThinning.thin(sine, 0.01)
	tc.assert_true(keys.size() < 60, "%d keys for 361 samples (two cycles at 1 %%)" % keys.size())
	tc.assert_true(_worst(keys, sine) <= 0.0105, "within tolerance: %f" % _worst(keys, sine))
	tc.assert_eq([keys[0].t, keys.back().t], [0.0, 4.0], "ends kept")
	# Hold, ramp, hold: four keys.
	var ramp: Array = []
	for i in 301:
		var t := i / 100.0
		ramp.append([t, clampf(t - 1.0, 0.0, 1.0)])
	tc.assert_eq(StudioKeyThinning.thin(ramp, 0.001).map(func(k): return [k.t, k.value]), [[0.0, 0.0], [1.0, 0.0], [2.0, 1.0], [3.0, 1.0]])
	# Arrays: per component, each against its own tolerance.
	var path: Array = []
	for i in 101:
		var t := i / 50.0
		path.append([t, [t, sin(t * 3.0) * 0.2, 1.0]])
	var pk := StudioKeyThinning.thin(path, [0.01, 0.01, 0.01])
	tc.assert_true(pk.size() < 30 and _worst(pk, path) <= 0.0105, "%d keys, %f" % [pk.size(), _worst(pk, path)])
	tc.assert_eq(StudioKeyThinning.thin([[1.0, 2.0]], 0.1), [{"t": 1.0, "value": 2.0}], "one sample, one key")
	tc.assert_eq(StudioKeyThinning.thin([], 0.1), [])


static func test_replace_keys_over_a_range(tc: TestCase) -> void:
	var m := _model(tc)
	var ti := m.find_track("shader_param", "scr.effect0", "intensity")
	tc.assert_true(m.replace_keys("shader_param", "scr.effect0", "intensity", 0.5, 5.0, [{"t": 2.0, "value": 3.0}, {"t": 4.0, "value": 2.0}]))
	tc.assert_eq(m.tracks()[ti].keyframes.map(func(k): return [k.t, k.value]), [[0.0, 1.0], [2.0, 3.0], [4.0, 2.0], [6.0, 1.0]],
			"keys in the range replaced, the rest kept")
	tc.assert_true(m.replace_keys("transform", "scr", "position", 1.0, 2.0, [{"t": 1.0, "value": [0, 1, 0]}]), "a new track")
	tc.assert_eq(m.find_track("transform", "scr", "position") >= 0, true)
	m.undo()
	m.undo()
	tc.assert_eq(m.tracks()[ti].keyframes.size(), 4, "undone")
	tc.assert_false(m.replace_keys("shader_param", "scr.effect0", "intensity", 0.0, 1.0, []), "nothing to write")


static func test_a_take_of_an_armed_slider(tc: TestCase) -> void:
	var m := _model(tc)
	var field := _field(tc, m, "effect0/intensity")
	var edits := StudioConfigEdits.new()
	edits.model = m
	var rec := StudioRecorder.new()
	rec.model = m
	edits.recorder = rec
	tc.assert_true(StudioRecorder.can_arm(field))
	rec.set_armed("scr", field, true)
	tc.assert_true(rec.is_armed("scr", field))
	tc.assert_eq(rec.begin(2.0, 4.0), 0.0, "the pre-roll starts 2 s early")
	rec.tick(0.5)
	rec.touch_param("scr", field, 1.2)  # touched in the pre-roll
	tc.assert_eq(rec.tick(1.5), "")
	tc.assert_false(rec.has_samples(), "nothing before the take's start")
	tc.assert_true(rec.owns_param("scr", field))
	tc.assert_eq(edits.commit("scr", field, 9.0, 1.5, false), "", "letting go of the slider writes nothing while it records")
	var end := ""
	var t := 2.0
	while end == "":
		rec.touch_param("scr", field, 1.2 + (minf(t, 4.0) - 2.0))  # a steady sweep up
		end = rec.tick(t)
		t += 1.0 / 60.0
	tc.assert_eq(end, "end", "the out point ends it")
	var label := rec.finish()
	tc.assert_has(label, "Record scr intensity from 0:02.00 to 0:04.00")
	var kfs: Array = m.tracks()[m.find_track("shader_param", "scr.effect0", "intensity")].keyframes
	tc.assert_eq(kfs.map(func(k): return [snappedf(k.t, 0.01), snappedf(k.value, 0.01)]), [[0.0, 1.0], [1.0, 1.5], [2.0, 1.2], [4.0, 3.2], [5.0, 0.5], [6.0, 1.0]],
			"a straight sweep is two keys; the keys either side stay (punch-in)")
	tc.assert_false(rec.is_active())
	tc.assert_eq(m.undo(), label, "one undo step")
	tc.assert_eq(m.tracks()[m.find_track("shader_param", "scr.effect0", "intensity")].keyframes.size(), 4)
	# Arming follows the object; a take with nothing touched writes nothing.
	rec.begin(0.0)
	rec.tick(0.0)
	rec.tick(1.0)
	tc.assert_eq(rec.finish(), "", "untouched: nothing")
	rec.prune([])
	tc.assert_false(rec.is_armed("scr", field), "gone with its object")


static func test_a_take_of_a_grab_and_the_loop_coming_round(tc: TestCase) -> void:
	var m := _model(tc)
	var rec := StudioRecorder.new()
	rec.model = m
	var node := Node3D.new()
	node.position = Vector3(0, 1, 0)
	rec.begin(1.0)
	rec.touch_transform("scr", node)
	tc.assert_true(rec.owns_transform("scr"))
	for i in 61:
		var t := 1.0 + i / 30.0
		node.position = Vector3(t - 1.0, 1.0, 0.0)  # carried 2 m to the right
		tc.assert_eq(rec.tick(t), "")
	tc.assert_eq(rec.tick(1.0), "wrapped", "playback jumped back: the take ends")
	rec.finish()
	var pos := m.find_track("transform", "scr", "position")
	tc.assert_true(pos >= 0)
	tc.assert_eq(m.tracks()[pos].keyframes.map(func(k): return [k.t, k.value]), [[1.0, [0.0, 1.0, 0.0]], [3.0, [2.0, 1.0, 0.0]]])
	tc.assert_eq(m.find_track("transform", "scr", "rotation_deg"), -1, "channels that didn't change aren't written")
	tc.assert_eq(m.find_track("transform", "scr", "scale"), -1)
	node.free()
	# Dropping a take writes nothing.
	rec.begin(0.0)
	var n2 := Node3D.new()
	rec.touch_transform("scr", n2)
	rec.tick(0.0)
	n2.position = Vector3(5, 0, 0)
	rec.tick(0.5)
	rec.cancel()
	tc.assert_false(rec.is_active())
	tc.assert_eq(m.tracks()[pos].keyframes.size(), 2)
	n2.free()


static func test_tap_tempo_and_the_piece_grid(tc: TestCase) -> void:
	var spb := 60.0 / 124.0
	var taps: Array = []
	for n in [8, 9, 10]:
		taps.append(0.61 + n * spb)
	tc.assert_eq(StudioTimeline.tap_tempo(taps), null, "three taps: not yet")
	taps = []
	var jitter := [0.012, -0.008, 0.005, -0.01, 0.004]
	for i in 5:
		taps.append(0.61 + (8 + i) * spb + jitter[i])
	var g := StudioTimeline.tap_tempo(taps)
	tc.assert_true(g != null)
	tc.assert_true(absf(g.bpm - 124.0) < 0.6, "tempo %.1f" % g.bpm)
	var off := g.beat_at(0.61) - roundf(g.beat_at(0.61))
	tc.assert_true(absf(off) < 0.05, "on the beat (%.3f of a beat off)" % off)
	var m := _model(tc)
	tc.assert_true(m.set_beats(g.to_dict(), "Tap"))
	tc.assert_eq(BeatGrid.from_dict(m.document().media.beats).bpm, g.bpm)
	tc.assert_ok(ScriptFormat.load_from_dict(m.document().duplicate(true), "<memory>"), "still valid")
	tc.assert_true(m.set_beats(null))
	tc.assert_false(m.document().media.has("beats"))
	m.undo()
	m.undo()
	tc.assert_false(m.document().media.has("beats"), "undone to none")
