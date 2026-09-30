extends RefCounted

## Groups (TODO 14) and the outliner's tree (TODO 15): StudioGrouping's
## group / ungroup / set_parent keep every object where it was on stage at
## every moment (keys converted into the new space), one undo step each,
## and the piece stays valid.

const TIMES := [0.0, 1.0, 2.5, 4.0, 6.0, 9.0]


static func _model() -> EditModel:
	var doc := {
		"format_version": 2,
		"media": {"video": "clip.mp4", "duration": 10.0},
		"prefabs": {"screen": "res://player/prefabs/screen.tscn", "cube": "res://player/prefabs/cube.tscn"},
		"tracks": [
			{"type": "event", "t": 0, "action": "spawn", "id": "left", "prefab": "screen",
				"transform": {"position": [-2.0, 1.7, -4.0], "rotation_deg": [0.0, 20.0, 0.0], "scale": [0.12, 0.12, 0.12]}},
			{"type": "event", "t": 1, "action": "spawn", "id": "right", "prefab": "screen",
				"transform": {"position": [2.0, 1.7, -4.0], "scale": [0.12, 0.12, 0.12]}},
			{"type": "event", "t": 0, "action": "spawn", "id": "cube", "prefab": "cube", "transform": {"position": [0.0, 0.5, -3.0]}},
			{"type": "event", "t": 0, "action": "spawn", "id": "pip", "prefab": "cube", "parent": "cube",
				"transform": {"position": [0.0, 1.0, 0.0], "scale": [0.5, 0.5, 0.5]}},
			{"type": "event", "t": 7, "action": "despawn", "target": "right"},
			# right rises along a bezier; left turns a full circle.
			{"type": "transform", "target": "right", "channel": "position", "interp": "bezier", "keyframes": [
				{"t": 1.0, "value": [2.0, 1.7, -4.0], "out": [[0.5, 0.0], [0.5, 0.6], [0.5, 0.0]]},
				{"t": 5.0, "value": [2.0, 3.0, -4.0], "in": [[-0.5, 0.0], [-0.5, -0.2], [-0.5, 0.0]]}]},
			{"type": "transform", "target": "left", "channel": "rotation_deg", "keyframes": [
				{"t": 0.0, "value": [0.0, 20.0, 0.0]}, {"t": 8.0, "value": [0.0, 380.0, 0.0]}]},
		],
	}
	var r := EditModel.from_text(JSON.stringify(doc, "  "), "")
	return r.model


## Where each object is on stage at each of TIMES.
static func _places(model: EditModel, ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = TIMES.map(func(t): return StudioGrouping.world_at(model, id, t))
	return out


static func _same_places(tc: TestCase, a: Dictionary, b: Dictionary, what: String, eps: float = 1e-4) -> void:
	for id in a:
		for i in a[id].size():
			var x: Transform3D = a[id][i]
			var y: Transform3D = b[id][i]
			var d := x.origin.distance_to(y.origin)
			for c in 3:
				d = maxf(d, (x.basis[c] - y.basis[c]).length())
			if d > eps:
				tc.fail("%s: %s at %s moved (%s → %s)" % [what, id, TIMES[i], x, y])
				return


static func test_tree(tc: TestCase) -> void:
	var m := _model()
	var rows := StudioGrouping.tree(m)
	tc.assert_eq(rows.map(func(r): return [r.id, r.depth]), [["left", 0], ["right", 0], ["cube", 0], ["pip", 1]])
	tc.assert_eq(rows[2].children, 1)
	tc.assert_eq(StudioGrouping.descendants(m, "cube"), ["pip"])
	tc.assert_true(StudioGrouping.is_inside(m, "pip", "cube"))
	tc.assert_false(StudioGrouping.is_group(m, "cube"))


static func test_group_keeps_everything_in_place(tc: TestCase) -> void:
	var m := _model()
	var ids := ["left", "right", "cube", "pip"]
	var before := _places(m, ids)
	var text := m.to_text()
	var r := StudioGrouping.group(m, ["left", "right"], 2.5)
	tc.assert_ok(r)
	tc.assert_eq(r.id, "group")
	tc.assert_true(StudioGrouping.is_group(m, "group"), "the built-in group prefab, named in prefabs")
	tc.assert_eq(StudioGrouping.children_of(m, "group"), ["left", "right"])
	var g: Dictionary = m.tracks()[m.spawn_index("group")]
	tc.assert_eq(g.t, 0.0, "spawns with the first of them")
	tc.assert_true(m.spawn_index("group") < m.spawn_index("left"), "and before them in the file")
	# Their average at 2.5 s: right has risen to about 2.05 there.
	var p := Interpolation.to_vec3(g.transform.position)
	tc.assert_true(absf(p.x) < 0.001 and p.z == -4.0 and p.y > 1.8 and p.y < 2.0, "in the middle: %s" % p)
	tc.assert_false(g.transform.has("rotation_deg") or g.transform.has("scale"), "not turned or scaled")
	_same_places(tc, before, _places(m, ids), "grouped")
	# The bezier's handles don't change with a move.
	var ti := m.find_track(ScriptFormat.TRACK_TRANSFORM, "right", "position")
	tc.assert_eq(m.tracks()[ti].keyframes[0].out, [[0.5, 0.0], [0.5, 0.6], [0.5, 0.0]], "handles kept")
	tc.assert_true(m.check().ok, "valid: %s" % m.check())
	tc.assert_eq(m.undo_label(), "Group left, right as group")
	m.undo()
	tc.assert_eq(m.to_text(), text, "one undo step takes it all back")


static func test_moving_the_group_moves_them(tc: TestCase) -> void:
	var m := _model()
	StudioGrouping.group(m, ["left", "right"], 0.0)
	var before := StudioGrouping.world_at(m, "left", 0.0).origin
	m.set_key(ScriptFormat.TRACK_TRANSFORM, "group", "position", 0.0, [0.0, 1.7, -4.0])
	m.set_key(ScriptFormat.TRACK_TRANSFORM, "group", "position", 4.0, [0.0, 2.7, -4.0])
	tc.assert_true(StudioGrouping.world_at(m, "left", 4.0).origin.is_equal_approx(before + Vector3(0, 1, 0)), "carried up 1 m")


static func test_group_refuses(tc: TestCase) -> void:
	var m := _model()
	tc.assert_err(StudioGrouping.group(m, ["left", "pip"], 0.0), "different groups")
	tc.assert_err(StudioGrouping.group(m, [ScriptFormat.VIEWER], 0.0), "can't go in a group")
	tc.assert_err(StudioGrouping.group(m, [], 0.0), "Select something")
	# Something inside another of them just comes along.
	tc.assert_ok(StudioGrouping.group(m, ["cube", "pip"], 0.0))
	tc.assert_eq(StudioGrouping.children_of(m, "group"), ["cube"])
	tc.assert_eq(StudioGrouping.parent_of(m, "pip"), "cube")


static func test_ungroup_a_turned_group(tc: TestCase) -> void:
	var m := _model()
	StudioGrouping.group(m, ["left", "right"], 0.0)
	# Turn, lift and scale the group, and have it leave at 6 s.
	m.set_spawn_transform("group", {"position": [1.0, 2.0, -5.0], "rotation_deg": [0.0, 30.0, 0.0], "scale": [2.0, 2.0, 2.0]})
	m.add_despawn("group", 6.0)
	m.set_config("group", ["modifiers", "opacity"], 0.5)
	var ids := ["left", "right"]
	var before := _places(m, ids)
	var r := StudioGrouping.ungroup(m, "group", 3.0)
	tc.assert_ok(r)
	tc.assert_eq(r.ids, ids)
	tc.assert_has(r.note, "modifiers")
	tc.assert_eq(m.spawn_index("group"), -1, "gone")
	tc.assert_eq(StudioGrouping.parent_of(m, "left"), "")
	# Where the group was, both still are (6 s and later: they've left).
	var until := {}
	for id in ids:
		until[id] = before[id].slice(0, 4)
	var after := _places(m, ids)
	for id in ids:
		after[id] = after[id].slice(0, 4)
	_same_places(tc, until, after, "ungrouped", 2e-3)
	# They leave with it: left gets a despawn at 6 s; right had its own at 7.
	var goes := m.tracks().filter(func(e): return e.get("action") == "despawn").map(func(e): return [e.target, e.t])
	tc.assert_true(goes.has(["left", 6.0]), "left goes when the group went: %s" % [goes])
	tc.assert_true(goes.has(["right", 6.0]), "and right, which had been there till 7: %s" % [goes])
	# left's full turn is still a full turn (not unwrapped the short way).
	var ti := m.find_track(ScriptFormat.TRACK_TRANSFORM, "left", "rotation_deg")
	var kfs: Array = m.tracks()[ti].keyframes
	tc.assert_true(absf(float(kfs[1].value[1]) - float(kfs[0].value[1]) - 360.0) < 0.01, "a spin stays a spin: %s" % [kfs])
	tc.assert_true(m.check().ok, "valid: %s" % m.check())


static func test_ungroup_an_empty_group(tc: TestCase) -> void:
	var m := _model()
	var r := StudioGrouping.group(m, ["cube"], 0.0)
	StudioGrouping.set_parent(m, "cube", "", 0.0)
	tc.assert_eq(StudioGrouping.children_of(m, r.id), [])
	tc.assert_ok(StudioGrouping.ungroup(m, r.id, 0.0), "an empty group just goes")
	tc.assert_eq(m.spawn_index(r.id), -1)
	tc.assert_err(StudioGrouping.ungroup(m, "left", 0.0), "nothing in it")


static func test_set_parent(tc: TestCase) -> void:
	var m := _model()
	var ids := ["left", "right", "cube", "pip"]
	var before := _places(m, ids)
	var g: String = StudioGrouping.group(m, ["left"], 0.0).id
	# The group is turned: dragging right in converts its keys into it.
	m.set_spawn_transform(g, {"position": [-2.0, 1.7, -4.0], "rotation_deg": [0.0, 90.0, 0.0]})
	var moved := _places(m, ["left"])
	tc.assert_ok(StudioGrouping.set_parent(m, "right", g, 2.0))
	tc.assert_eq(StudioGrouping.parent_of(m, "right"), g)
	var not_left := before.duplicate()
	not_left.erase("left")
	_same_places(tc, not_left, _places(m, ["right", "cube", "pip"]), "put in")
	tc.assert_eq(m.undo_label(), "Put right in %s" % g)
	# Out again, to the stage.
	tc.assert_ok(StudioGrouping.set_parent(m, "right", "", 2.0))
	_same_places(tc, not_left, _places(m, ["right", "cube", "pip"]), "taken out")
	tc.assert_eq(m.undo_label(), "Take right out of %s" % g)
	_same_places(tc, moved, _places(m, ["left"]), "left untouched")
	# Refused: into itself or its own child, already there, a group that
	# isn't on stage yet.
	tc.assert_err(StudioGrouping.set_parent(m, "cube", "pip", 0.0), "inside itself")
	tc.assert_err(StudioGrouping.set_parent(m, "pip", "cube", 0.0), "already in cube")
	m.set_spawn_time(m.spawn_index(g), 3.0)
	tc.assert_err(StudioGrouping.set_parent(m, "cube", g, 0.0), "isn't on stage at 0:00.00")
	tc.assert_true(m.check().ok, "valid: %s" % m.check())


static func test_a_child_spawns_after_its_new_parent(tc: TestCase) -> void:
	var m := _model()
	# A group that comes later in the file, at the same time as left.
	m.add_object({"id": "late", "prefab": "cube", "t": 0.0})
	tc.assert_true(m.spawn_index("late") > m.spawn_index("left"))
	tc.assert_ok(StudioGrouping.set_parent(m, "left", "late", 0.0))
	tc.assert_true(m.spawn_index("late") < m.spawn_index("left"), "left's spawn moved after late's")
	# The runner's order at the same time is the file's: late, then left.
	var data := m.timeline()
	var order: Array = data.tracks.filter(func(e): return e.get("action") == "spawn").map(func(e): return e.id)
	tc.assert_true(order.find("late") < order.find("left"), "%s" % [order])
