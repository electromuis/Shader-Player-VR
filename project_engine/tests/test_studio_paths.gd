extends RefCounted

## Motion paths (TODO 16): what StudioEditTools samples for a path (none
## for something that doesn't move), kept until its keys change; the keys'
## time labels; the setting for other objects' faint paths.


static func _key(t: float, v: Array) -> Dictionary:
	return {"t": t, "value": v}


static func _tracks() -> Array:
	return [
		{"type": "event", "t": 0, "action": "spawn", "id": "still", "prefab": "cube"},
		{"type": "event", "t": 0, "action": "spawn", "id": "one_key", "prefab": "cube"},
		{"type": "event", "t": 0, "action": "spawn", "id": "moving", "prefab": "cube"},
		{"type": "transform", "target": "one_key", "channel": "position", "keyframes": [_key(2.0, [1.0, 1.0, 1.0])]},
		{"type": "transform", "target": "moving", "channel": "rotation_deg", "keyframes": [_key(0.0, [0.0, 0.0, 0.0]), _key(4.0, [0.0, 90.0, 0.0])]},
		{"type": "transform", "target": "moving", "channel": "position", "keyframes": [_key(1.0, [0.0, 1.0, 0.0]), _key(3.0, [2.0, 1.0, 0.0])]},
		{"type": "transform", "target": "$viewer", "channel": "position", "keyframes": [_key(0.0, [0.0, 2.0, 8.0]), _key(5.0, [0.0, 2.0, 3.0])]},
	]


static func test_paths_only_for_things_that_move(tc: TestCase) -> void:
	var tools := StudioEditTools.new()
	var tracks := _tracks()
	tc.assert_eq(tools._sampled_path("still", tracks), {}, "no position track: no path")
	tc.assert_eq(tools._sampled_path("one_key", tracks), {}, "one key: it doesn't move")
	var p := tools._sampled_path("moving", tracks)
	tc.assert_eq(p.keys.map(func(k): return k[0]), [1.0, 3.0], "the position track's keys, not rotation's")
	tc.assert_eq(p.points[0], [Vector3(0, 1, 0), false, 1.0], "starts at the first key")
	tc.assert_eq(p.points.back(), [Vector3(2, 1, 0), true, 3.0], "ends at the last")
	tc.assert_true(p.points[p.points.size() / 2][0].x > 0.9 and p.points[p.points.size() / 2][0].x < 1.1, "linear in between")
	var v := tools._sampled_path("$viewer", tracks)
	tc.assert_eq(v.keys.map(func(k): return k[1]), [Vector3(0, 2, 8), Vector3(0, 2, 3)], "the viewer's ride")
	tools.free()


static func test_paths_are_sampled_again_when_keys_change(tc: TestCase) -> void:
	var tools := StudioEditTools.new()
	var tracks := _tracks()
	var a := tools._sampled_path("moving", tracks)
	tc.assert_true(is_same(tools._sampled_path("moving", tracks), a), "kept while the keys are the same")
	tracks[3] = {"type": "transform", "target": "one_key", "channel": "position", "keyframes": [_key(2.0, [1.0, 1.0, 1.0]), _key(3.0, [1.0, 2.0, 1.0])]}
	tc.assert_true(is_same(tools._sampled_path("moving", tracks), a), "another object's keys don't matter")
	tc.assert_eq(tools._sampled_path("one_key", tracks).keys.size(), 2, "a second key: now it moves")
	tracks[5] = tracks[5].duplicate(true)
	tracks[5].keyframes[1].value = [4.0, 1.0, 0.0]
	tc.assert_eq(tools._sampled_path("moving", tracks).points.back()[0], Vector3(4, 1, 0), "a moved key: sampled again")
	tools.free()


static func test_key_time_labels(tc: TestCase) -> void:
	tc.assert_eq([0.0, 4.0, 5.93, 59.96, 80.5, 3600.0].map(func(t): return StudioEditTools.key_time_text(t)),
			["0:00", "0:04", "0:05.9", "1:00", "1:20.5", "60:00"])


static func test_all_paths_setting(tc: TestCase) -> void:
	var s := StudioSettings.new("user://_tmp_paths_settings.json")
	tc.assert_true(s.all_paths and s.is_default("all_paths"), "on by default")
	s.all_paths = false
	var back := StudioSettings.new("user://_tmp_paths_settings.json")
	back.load_from_disk()
	tc.assert_eq(back.all_paths, false, "saved")
	back.reset("all_paths")
	tc.assert_true(back.all_paths)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://_tmp_paths_settings.json"))
