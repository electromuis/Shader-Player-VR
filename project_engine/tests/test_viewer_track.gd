extends RefCounted

## The script's viewer (M7): "$viewer" transform tracks and cut events as
## one track (ViewerTrack): poses along smooth moves, cuts (event cuts,
## step keys, the first key) with their transitions, "cuts only", motion
## speed; and the format's rules for it (ScriptFormat) and the setting.

static func _vt(tracks: Array) -> ViewerTrack:
	var vt := ViewerTrack.new()
	vt.build(tracks)
	return vt


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


const RIDE := [
	{"type": "transform", "target": "$viewer", "channel": "position", "keyframes": [
		{"t": 10.0, "value": [0, 2, 8]},
		{"t": 20.0, "value": [0, 2, -12]},
		{"t": 30.0, "value": [0, 12, -12], "interp": "step"},
		{"t": 40.0, "value": [5, 2, 0], "transition": {"type": "fade_to_black", "duration": 1.0}}]},
	{"type": "transform", "target": "$viewer", "channel": "rotation_deg", "keyframes": [
		{"t": 10.0, "value": [0, 0, 0]}, {"t": 20.0, "value": [0, 90, 0]}]},
	{"type": "event", "t": 25.0, "action": "vr_cut", "to": {"position": [1, 2, 3], "rotation_deg": [0, 45, 0]}},
]


static func test_a_ride_glides_and_cuts_jump(tc: TestCase) -> void:
	var vt := _vt(RIDE)
	tc.assert_false(vt.is_empty())
	tc.assert_eq(vt.start_time(), 10.0)
	tc.assert_eq(vt.pose_at(5.0), {}, "home before the first key")
	var mid := vt.pose_at(15.0)
	tc.assert_eq(_v(mid.position), [0.0, 2.0, -2.0], "halfway along the ride")
	tc.assert_eq(snappedf(mid.rotation_deg.y, 0.01), 45.0)
	tc.assert_eq(_v(vt.pose_at(24.9).position), [0.0, 2.0, -12.0], "held: a cut comes next")
	tc.assert_eq(_v(vt.pose_at(25.0).position), [1.0, 2.0, 3.0], "the event cut joins the track")
	tc.assert_eq(snappedf(vt.pose_at(26.0).rotation_deg.y, 0.01), 45.0)
	tc.assert_eq(vt.cuts_between(0.0, 60.0).map(func(c): return c.t), [10.0, 25.0, 40.0], "first key, event cut, step-reached key")
	tc.assert_eq(vt.cuts_between(39.0, 40.0)[0].transition, {"type": "fade_to_black", "duration": 1.0})
	tc.assert_eq(vt.cuts_between(10.0, 24.0), [], "none inside the glide")
	tc.assert_true(vt.is_cut_at(25.0))
	tc.assert_true(vt.has_motion())
	var m := vt.motion_at(15.0)
	tc.assert_eq([snappedf(m.speed, 0.01), snappedf(m.turn, 0.01)], [2.0, 9.0], "2 m/s, 9°/s")
	tc.assert_eq(vt.motion_at(40.0).speed, 0.0, "a cut isn't speed")


static func test_cuts_only_holds_and_fades(tc: TestCase) -> void:
	var vt := _vt(RIDE)
	tc.assert_eq(_v(vt.pose_at(15.0, true).position), [0.0, 2.0, 8.0], "held at the key before")
	tc.assert_eq(_v(vt.pose_at(20.0, true).position), [0.0, 2.0, -12.0])
	var cuts := vt.cuts_between(0.0, 60.0, true)
	tc.assert_eq(cuts.map(func(c): return c.t), [10.0, 20.0, 25.0, 30.0, 40.0], "every key")
	tc.assert_eq(cuts[1].transition, {"type": "fade_to_black", "duration": ViewerTrack.FADE_SECONDS}, "faded")
	tc.assert_eq(cuts[4].transition.duration, 1.0, "a key's own transition stays")


static func test_old_scripts_cuts_only(tc: TestCase) -> void:
	var vt := _vt([
		{"type": "event", "t": 44.5, "action": "vr_cut", "to": {"position": [0, 2, 8], "rotation_deg": [0, 0, 0]},
			"transition": {"type": "fade_to_black", "duration": 1.0}},
		{"type": "event", "t": 0.0, "action": "vr_cut", "to": {"position": [1, 2, 6], "rotation_deg": [0, 20, 0]}},
		{"type": "event", "t": 3.0, "action": "spawn", "id": "x", "prefab": "cube"},
	])
	tc.assert_eq(_v(vt.pose_at(0.0).position), [1.0, 2.0, 6.0])
	tc.assert_eq(_v(vt.pose_at(30.0).position), [1.0, 2.0, 6.0], "held until the next cut (no glide between cuts)")
	tc.assert_eq(snappedf(vt.pose_at(30.0).rotation_deg.y, 0.01), 20.0)
	tc.assert_eq(_v(vt.pose_at(50.0).position), [0.0, 2.0, 8.0])
	tc.assert_false(vt.has_motion(), "cuts only")
	tc.assert_eq(vt.cuts_between(-0.001, 50.0).map(func(c): return [c.t, c.transition.get("duration", 0.0)]), [[0.0, 0.0], [44.5, 1.0]])
	tc.assert_true(_vt([]).is_empty())
	tc.assert_eq(_vt([]).pose_at(3.0), {})


static func test_format_rules_for_the_viewer(tc: TestCase) -> void:
	var base := {"format_version": 2, "media": {"video": "v.mp4"}, "prefabs": {"cube": "res://player/prefabs/cube.tscn"}, "tracks": []}
	var doc: Dictionary = base.duplicate(true)
	doc.tracks = RIDE.duplicate(true)
	tc.assert_ok(ScriptFormat.load_from_dict(doc), "a viewer track is valid in format 2")
	doc = base.duplicate(true)
	doc.tracks = [{"type": "transform", "target": "$viewer", "channel": "scale", "keyframes": [{"t": 0, "value": [1, 1, 1]}]}]
	tc.assert_err(ScriptFormat.load_from_dict(doc), "not scale")
	doc.tracks = [{"type": "transform", "target": "$other", "channel": "position", "keyframes": [{"t": 0, "value": [1, 1, 1]}]}]
	tc.assert_err(ScriptFormat.load_from_dict(doc), "reserved")
	doc.tracks = [{"type": "event", "t": 0, "action": "spawn", "id": "$viewer", "prefab": "cube"}]
	tc.assert_err(ScriptFormat.load_from_dict(doc), "reserved")
	doc.tracks = [{"type": "transform", "target": "$viewer", "channel": "position", "keyframes": [
		{"t": 0, "value": [1, 1, 1], "transition": {"type": "spin"}}]}]
	tc.assert_err(ScriptFormat.load_from_dict(doc), "transition")
	doc.tracks = [{"type": "event", "t": 1, "action": "vr_cut", "to": {"position": [0, 2, 8]}, "transition": {"type": "fade_to_black", "duration": -1}}]
	tc.assert_err(ScriptFormat.load_from_dict(doc), "duration")
	var r := ScriptFormat.load_from_dict(base.duplicate(true).merged({"tracks": RIDE.duplicate(true)}, true))
	tc.assert_ok(r)
	tc.assert_eq(ViewerTrack.from_timeline(r.get("data")).cuts_between(0.0, 60.0).size(), 3, "from a loaded timeline")


static func test_the_cuts_only_setting_saves(tc: TestCase) -> void:
	var s := PlayerSettings.new()
	tc.assert_false(s.script_camera_cuts_only, "off by default")
	s.script_camera_cuts_only = true
	var d := s.to_dict()
	tc.assert_eq(d.get("script_camera_cuts_only"), true)
	var s2 := PlayerSettings.new()
	s2.from_dict(d)
	tc.assert_true(s2.script_camera_cuts_only and s2.allow_script_camera)
	s2.from_dict({})
	tc.assert_false(s2.script_camera_cuts_only, "older settings files: off")
