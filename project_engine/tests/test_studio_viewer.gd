extends RefCounted

## Studio's viewer tools (M7): keying the viewer and cutting to it
## (EditModel.key_viewer), the viewer's lane and comfort warnings
## (StudioTimeline), and recording a ride (StudioRecorder with the viewer
## armed).

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 60.0},
	"prefabs": {"cube": "res://player/prefabs/cube.tscn"},
	"tracks": [{"type": "event", "t": 0, "action": "spawn", "id": "c", "prefab": "cube"}],
}


static func _model(tc: TestCase) -> EditModel:
	var r := EditModel.from_text(JSON.stringify(DOC), "")
	tc.assert_ok(r)
	return r.get("model")


static func _keys(m: EditModel, ch: String) -> Array:
	var ti := m.find_track("transform", "$viewer", ch)
	return m.tracks()[ti].keyframes if ti >= 0 else []


static func test_keying_and_cutting_the_viewer(tc: TestCase) -> void:
	var m := _model(tc)
	tc.assert_true(m.key_viewer(10.0, [0.0, 2.0, 8.0], 0.0))
	tc.assert_true(m.key_viewer(20.0, [0.0, 2.0, -12.0], 90.0))
	tc.assert_eq(m.undo_label(), "Key the viewer at 0:20.00")
	var vt := ViewerTrack.new()
	vt.build(m.tracks())
	tc.assert_eq(vt.pose_at(15.0).position, Vector3(0, 2, -2), "glides between keys")
	tc.assert_eq(_keys(m, "rotation_deg").map(func(k): return k.value), [[0.0, 0.0, 0.0], [0.0, 90.0, 0.0]])
	# A cut: the key before holds, the new key has its fade.
	tc.assert_true(m.key_viewer(30.0, [5.0, 2.0, 0.0], 180.0, true, {"type": "fade_to_black", "duration": 0.5}))
	tc.assert_eq(m.undo_label(), "Cut the viewer to here at 0:30.00")
	var pos := _keys(m, "position")
	tc.assert_eq([pos[1].get("interp"), pos[2].get("transition", {}).get("duration")], ["step", 0.5])
	vt.build(m.tracks())
	tc.assert_eq(vt.pose_at(29.0).position, Vector3(0, 2, -12), "holds until the cut")
	tc.assert_eq(vt.cuts_between(0.0, 60.0).map(func(c): return c.t), [10.0, 30.0])
	tc.assert_eq(StudioTimeline.cuts(m), [10.0, 30.0], "the ribbon's cut markers")
	# Keying over the cut as a glide undoes the jump.
	tc.assert_true(m.key_viewer(30.0, [5.0, 2.0, 0.0], 180.0))
	pos = _keys(m, "position")
	tc.assert_eq([pos[1].get("interp", "linear"), pos[2].has("transition")], ["linear", false])
	tc.assert_ok(ScriptFormat.load_from_dict(m.document().duplicate(true)), "valid")
	m.undo()
	m.undo()
	tc.assert_eq(_keys(m, "position").size(), 2, "one undo step each")
	tc.assert_eq(StudioTimeline.property_rows(m, "$viewer").map(func(r): return r.label), ["Position", "Rotation"], "its rows on the ribbon")


static func test_the_viewer_lane_and_comfort(tc: TestCase) -> void:
	var m := _model(tc)
	tc.assert_eq(StudioTimeline.lanes(m, 60.0).map(func(l): return l.id), ["c"], "no viewer lane while the piece doesn't move the viewer")
	m.key_viewer(10.0, [0.0, 2.0, 8.0], 0.0)
	m.key_viewer(20.0, [0.0, 2.0, 0.0], 0.0)  # 0.8 m/s: fine
	m.key_viewer(22.0, [0.0, 2.0, -20.0], 0.0)  # 10 m/s: too fast
	m.key_viewer(30.0, [0.0, 2.0, -20.0], 180.0)  # 22.5°/s: fine
	m.key_viewer(31.0, [0.0, 2.0, -20.0], 270.0)  # 90°/s: too fast
	var lanes := StudioTimeline.lanes(m, 60.0)
	tc.assert_eq(lanes[0].id, "$viewer")
	tc.assert_eq(lanes[0].spans, [[10.0, 60.0]])
	var warn: Array = lanes[0].warn.map(func(w): return [snappedf(w[0], 0.1), snappedf(w[1], 0.1)])
	tc.assert_eq(warn.size(), 2, "two stretches: %s" % [warn])
	tc.assert_true(warn[0][0] >= 19.9 and warn[0][1] <= 22.2, "the fast stretch: %s" % [warn[0]])
	tc.assert_true(warn[1][0] >= 29.9 and warn[1][1] <= 31.2, "the fast turn: %s" % [warn[1]])


static func test_recording_a_ride(tc: TestCase) -> void:
	var m := _model(tc)
	var rec := StudioRecorder.new()
	rec.model = m
	rec.arm_viewer = true
	var now := {"t": 0.0}
	# Flying 2 m/s forward while turning left through 180° and on (past the
	# ±180 seam).
	rec.viewer_pose = func(): return {"position": Vector3(0, 2, -2.0 * (now.t - 4.0)), "yaw": wrapf(60.0 * (now.t - 4.0), -180.0, 180.0)}
	tc.assert_eq(rec.begin(4.0, 8.0), 2.0)
	var end := ""
	var t := 2.0
	while end == "":
		now.t = minf(t, 8.0)
		end = rec.tick(t)
		t += 1.0 / 72.0
	var label := rec.finish()
	tc.assert_has(label, "Record the ride from 0:04.0")
	var pos := _keys(m, "position")
	tc.assert_eq(pos.size(), 2, "a straight flight: two keys")
	tc.assert_true(absf(pos[0].t - 4.0) < 0.02 and absf(pos[0].value[2]) < 0.05, "from the first frame of the take: %s" % [pos[0]])
	tc.assert_eq([pos[1].t, pos[1].value], [8.0, [0.0, 2.0, -8.0]])
	var rot := _keys(m, "rotation_deg")
	tc.assert_eq(snappedf(rot.back().value[1], 0.1), 240.0, "the turn unwrapped (240°, not -120°)")
	var vt := ViewerTrack.new()
	vt.build(m.tracks())
	tc.assert_eq(snappedf(vt.pose_at(7.0).rotation_deg.y, 0.5), 180.0, "no spin the long way round")
	tc.assert_eq(m.undo(), label, "one undo step")
	tc.assert_eq(_keys(m, "position"), [])


static func test_grabbing_a_paths_keys(tc: TestCase) -> void:
	var m := _model(tc)
	m.key_viewer(10.0, [0.0, 2.0, 8.0], 0.0)
	m.key_viewer(20.0, [0.0, 2.0, 0.0], 0.0)
	var tools := StudioEditTools.new()
	tools.model = m
	tools.select("$viewer")
	tc.assert_eq(tools.path_keys().map(func(k): return k.world), [Vector3(0, 2, 8), Vector3(0, 2, 0)])
	var eye := Vector3(3, 2, 4)
	tc.assert_eq(tools.pick_key(eye, Vector3(0, 2, 2.5) - eye), {}, "a miss")
	var k := tools.pick_key(eye, Vector3(0, 2, 0) - eye)
	tc.assert_eq([k.get("ki"), k.get("t")], [1, 20.0], "the key the ray points at")
	var hand := Transform3D(Basis(), eye)
	tools.grab_key(k, "M", hand)
	tc.assert_true(tools.is_grabbing_key())
	tools.move_key_hand("M", hand.translated(Vector3(1.234, 0, -1)))
	tc.assert_eq(tools.release_key("M"), "Move the viewer's key at 0:20.00")
	tc.assert_eq(m.tracks()[m.find_track("transform", "$viewer", "position")].keyframes[1].value, [1.234, 2.0, -1.0], "carried with the hand")
	tc.assert_eq(m.undo(), "Move the viewer's key at 0:20.00", "one undo step")
	# Snapped, on an object's own path (no parent: world space).
	m.set_key("transform", "c", "position", 5.0, [1.0, 1.0, 1.0])
	m.set_key("transform", "c", "position", 9.0, [3.0, 1.0, 1.0])
	tools.select("c")
	tools.snap = true
	k = tools.pick_key(Vector3(3, 1, 5), Vector3(0, 0, -1))
	tc.assert_eq(k.get("ki"), 1)
	tools.grab_key(k, "R", Transform3D(Basis(), Vector3(3, 1, 5)))
	tools.move_key_hand("R", Transform3D(Basis(), Vector3(3.47, 1.52, 5)))
	tools.select("")  # changing the selection drops it
	tc.assert_false(tools.is_grabbing_key())
	tools.select("c")
	tools.grab_key(k, "R", Transform3D(Basis(), Vector3(3, 1, 5)))
	tools.move_key_hand("R", Transform3D(Basis(), Vector3(3.47, 1.52, 5)))
	tools.release_key("R")
	tc.assert_eq(m.tracks()[m.find_track("transform", "c", "position")].keyframes[1].value, [3.5, 1.5, 1.0], "snapped to 10 cm")
	tools.free()
