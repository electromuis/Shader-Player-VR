extends RefCounted

## Keys keep their values (TODO 61): a key of 0, then a key of 1 later on,
## must leave the first key at 0 whichever way they're made, in every key
## mode. With keys on change Off, a change between keys of an animated
## setting or channel is held unkeyed (shown, not written) until the
## diamond or A keys it, or it's dropped.

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 30.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn", "cube": "res://player/prefabs/cube.tscn"},
	"shaders": {},
	"tracks": [
		{"type": "event", "t": 0, "action": "spawn", "id": "scr", "prefab": "screen", "config": {"opacity": 0.0}},
		{"type": "event", "t": 0, "action": "spawn", "id": "box", "prefab": "cube",
			"transform": {"position": [0, 1, 0], "rotation_deg": [0, 0, 0], "scale": [1, 1, 1]}},
	],
}


static func _edits(tc: TestCase) -> StudioConfigEdits:
	var r := EditModel.from_text(JSON.stringify(DOC), "")
	tc.assert_ok(r, "document loads")
	var e := StudioConfigEdits.new()
	e.model = r.get("model")
	return e


static func _field(e: StudioConfigEdits, key: String) -> Dictionary:
	for s in e.sections("scr", null, "screen"):
		for f in s.fields:
			if f.key == key:
				return f
	return {}


static func _keys(e: StudioConfigEdits, field: Dictionary) -> Array:
	var ti := e.track_of("scr", field)
	return e.model.tracks()[ti].keyframes.map(func(k): return [k.t, k.value]) if ti >= 0 else []


## The report: key 0 with the diamond, change the value to 1 later on (Off),
## key it with the diamond. The first key keeps its 0.
static func test_the_first_key_keeps_its_value(tc: TestCase) -> void:
	var e := _edits(tc)
	var opacity := _field(e, "opacity")
	tc.assert_false(opacity.is_empty(), "the opacity field")
	tc.assert_has(e.toggle_key("scr", opacity, 2.0), "Key scr opacity at 0:02.00")
	tc.assert_eq(_keys(e, opacity), [[2.0, 0.0]])
	# Off, between keys (after the only one): nothing written yet.
	tc.assert_has(e.commit("scr", opacity, 1.0, 5.0, false, false), "Not keyed: scr opacity 1.00")
	tc.assert_eq(_keys(e, opacity), [[2.0, 0.0]], "the key at 2 s keeps its 0")
	tc.assert_eq(e.key_state("scr", opacity, 5.0), "unkeyed", "the diamond says so")
	tc.assert_eq(e.value_of("scr", opacity, 5.0), 1.0, "and the inspector shows the change")
	tc.assert_eq(e.toggle_key("scr", opacity, 5.0), "Key scr opacity at 0:05.00", "the diamond keys it")
	tc.assert_eq(_keys(e, opacity), [[2.0, 0.0], [5.0, 1.0]])
	tc.assert_true(e.unkeyed.is_empty())
	tc.assert_eq(e.key_state("scr", opacity, 5.0), "key")
	tc.assert_eq(e.value_of("scr", opacity, 2.0), 0.0)
	tc.assert_eq(e.value_of("scr", opacity, 3.5), 0.5, "the fade between them")
	# Undo takes the second key away, and only it.
	e.model.undo()
	tc.assert_eq(_keys(e, opacity), [[2.0, 0.0]])


## The same two keys in the other key modes, and typed straight onto keys.
static func test_two_keys_in_every_mode(tc: TestCase) -> void:
	for mode in ["animated", "all"]:
		var e := _edits(tc)
		var opacity := _field(e, "opacity")
		var auto_key: bool = mode == "all"
		e.toggle_key("scr", opacity, 2.0)
		tc.assert_has(e.commit("scr", opacity, 1.0, 5.0, auto_key, not auto_key), "Key scr opacity at 0:05.00", mode)
		tc.assert_eq(_keys(e, opacity), [[2.0, 0.0], [5.0, 1.0]], mode)
		# Back on the first key: a change edits that key, the other stays.
		tc.assert_has(e.commit("scr", opacity, 0.25, 2.0, auto_key, not auto_key), "Key scr opacity at 0:02.00", mode)
		tc.assert_eq(_keys(e, opacity), [[2.0, 0.25], [5.0, 1.0]], mode)
		# And down to 0 again: 0 is a value like any other.
		e.commit("scr", opacity, 0.0, 2.02, auto_key, not auto_key)
		tc.assert_eq(_keys(e, opacity), [[2.0, 0.0], [5.0, 1.0]], mode + ": set back to 0, on the key near it")
	# Off, on a key: that key.
	var e := _edits(tc)
	var opacity := _field(e, "opacity")
	e.toggle_key("scr", opacity, 2.0)
	e.commit("scr", opacity, 1.0, 5.0, false, false)
	e.toggle_key("scr", opacity, 5.0)
	tc.assert_has(e.commit("scr", opacity, 0.7, 5.0, false, false), "Key scr opacity at 0:05.00")
	tc.assert_eq(_keys(e, opacity), [[2.0, 0.0], [5.0, 0.7]])


## An unkeyed change dropped (the playhead moved on) leaves nothing behind:
## no step, no key, the curve's value shows again.
static func test_an_unkeyed_change_is_dropped_cleanly(tc: TestCase) -> void:
	var e := _edits(tc)
	var opacity := _field(e, "opacity")
	e.toggle_key("scr", opacity, 2.0)
	e.commit("scr", opacity, 1.0, 5.0, false, false)
	e.toggle_key("scr", opacity, 5.0)
	var steps := e.model.undo_label()
	tc.assert_has(e.commit("scr", opacity, 0.4, 3.0, false, false), "Not keyed")
	tc.assert_eq(e.model.undo_label(), steps, "no undo step for it")
	tc.assert_eq(e.value_of("scr", opacity, 3.0), 0.4)
	tc.assert_eq(e.drop_unkeyed(), "scr opacity")
	tc.assert_eq(e.value_of("scr", opacity, 3.0), 1.0 / 3.0, "the curve again")
	tc.assert_eq(e.key_state("scr", opacity, 3.0), "animated")
	tc.assert_eq(_keys(e, opacity), [[2.0, 0.0], [5.0, 1.0]])
	tc.assert_eq(e.drop_unkeyed(), "", "nothing left")
	# Only at its own time: elsewhere the field shows its curve.
	e.commit("scr", opacity, 0.9, 3.0, false, false)
	tc.assert_eq(e.value_of("scr", opacity, 4.0), 2.0 / 3.0)
	# key_unkeyed (A) keys it where it was made.
	tc.assert_true(e.model.batch("Key", func(): e.key_unkeyed("scr")))
	tc.assert_eq(_keys(e, opacity), [[2.0, 0.0], [3.0, 0.9], [5.0, 1.0]])


## Moves: key the box at 0 m, move it up later on (Off): nothing written
## until A keys it; the first key stays where it was.
static func test_a_move_between_keys_waits_for_a_key(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var tools := StudioEditTools.new()
	tools.model = m
	tools.runner = ScriptRunner.new()
	var at_rest := {"position": [0.0, 1.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]}
	tc.assert_has(e.toggle_transform_key("box", "position", 2.0, at_rest), "Key box position at 0:02.00")
	tools.runner.playhead = 5.0
	var up := {"position": [0.0, 3.0, 0.0], "rotation_deg": [0.0, 30.0, 0.0], "scale": [1.0, 1.0, 1.0]}
	tc.assert_eq(tools._commit("box", at_rest, up), "Move box; its position not keyed yet (Key it: A, I)")
	var pos := func(): return m.tracks()[m.find_track("transform", "box", "position")].keyframes.map(func(k): return [k.t, k.value])
	tc.assert_eq(pos.call(), [[2.0, [0.0, 1.0, 0.0]]], "the first key stays")
	tc.assert_eq(m.tracks()[m.spawn_index("box")].transform.rotation_deg, [0.0, 30.0, 0.0], "a still channel is set")
	tc.assert_true(tools.is_unkeyed("box", "position"))
	tc.assert_false(tools.is_unkeyed("box", "rotation_deg"))
	tc.assert_true(tools.runner.held.has("box"), "held on show")
	tc.assert_true(m.batch("Key box", func(): tools.key_unkeyed("box")))
	tc.assert_eq(pos.call(), [[2.0, [0.0, 1.0, 0.0]], [5.0, [0.0, 3.0, 0.0]]])
	tc.assert_false(tools.runner.held.has("box"), "the runner has it again")
	# Dropped: nothing written, the runner has it back.
	tools.runner.playhead = 8.0
	tools._commit("box", up, {"position": [4.0, 3.0, 0.0], "rotation_deg": [0.0, 30.0, 0.0], "scale": [1.0, 1.0, 1.0]})
	tc.assert_eq(tools.drop_unkeyed(), "box position")
	tc.assert_eq(pos.call(), [[2.0, [0.0, 1.0, 0.0]], [5.0, [0.0, 3.0, 0.0]]])
	tc.assert_false(tools.runner.held.has("box"))
	# Keys on change Animated: straight to a key, the others stay.
	tools.key_animated = true
	tools._commit("box", up, {"position": [4.0, 3.0, 0.0], "rotation_deg": [0.0, 30.0, 0.0], "scale": [1.0, 1.0, 1.0]})
	tc.assert_eq(pos.call(), [[2.0, [0.0, 1.0, 0.0]], [5.0, [0.0, 3.0, 0.0]], [8.0, [4.0, 3.0, 0.0]]])
	tc.assert_true(tools.unkeyed.is_empty())
	tools.runner.free()
	tools.free()
