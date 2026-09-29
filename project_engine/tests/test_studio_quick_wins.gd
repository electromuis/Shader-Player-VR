extends RefCounted

## Studio's quick wins: new pieces from the template (a screen showing the
## video), keys on change "Animated" (inspector and grabs), previous / next
## key, dragging a lane's block whole (its ends and keys), the status's
## ride-armed line and chips, and folded sections' summaries.

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 30.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn", "cube": "res://player/prefabs/cube.tscn"},
	"shaders": {},
	"tracks": [
		{"type": "event", "t": 2, "action": "spawn", "id": "scr", "prefab": "screen", "config": {"opacity": 1.0}},
		{"type": "event", "t": 10, "action": "despawn", "target": "scr"},
		{"type": "event", "t": 0, "action": "spawn", "id": "box", "prefab": "cube"},
		{"type": "event", "t": 20, "action": "spawn", "id": "late", "prefab": "cube"},
		{"type": "shader_param", "target": "scr.display", "param": "opacity", "keyframes": [
			{"t": 3, "value": 1.0}, {"t": 6, "value": 0.5}]},
		{"type": "transform", "target": "box", "channel": "position", "keyframes": [
			{"t": 1, "value": [0, 1, 0]}, {"t": 4, "value": [2, 1, 0]}]},
		{"type": "transform", "target": "late", "channel": "position", "keyframes": [
			{"t": 22, "value": [0, 1, 0]}]},
	],
}


static func _model(tc: TestCase) -> EditModel:
	var r := EditModel.from_text(JSON.stringify(DOC), "")
	tc.assert_ok(r, "document loads")
	return r.get("model")


static func _field(sections: Array, key: String) -> Dictionary:
	for s in sections:
		for f in s.fields:
			if f.key == key:
				return f
	return {}


static func test_new_piece_from_the_template(tc: TestCase) -> void:
	var dir := ProjectSettings.globalize_path("user://test_quick_wins_tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["clip.json", "bare.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	var template := EditModel.new_piece_template()
	tc.assert_eq(template.tracks[0].id, "main_screen", "the built-in template has a screen")
	var r := EditModel.new_piece(dir.path_join("clip.mp4"), template)
	tc.assert_ok(r)
	var m: EditModel = r.model
	tc.assert_true(m.spawn_index("main_screen") >= 0, "a screen from the start")
	tc.assert_eq(m.document().prefabs.screen, "res://player/prefabs/screen.tscn", "its prefab is named")
	tc.assert_eq(m.document().meta.default_screen, false, "no injected screen on top")
	tc.assert_eq(m.document().media.video, "clip.mp4")
	tc.assert_false(m.is_dirty(), "written straight away")
	var bare := EditModel.new_piece(dir.path_join("bare.mp4"))
	tc.assert_eq(bare.model.object_ids(), [], "no template: empty, as before")
	for f in ["clip.json", "bare.json"]:
		DirAccess.remove_absolute(dir.path_join(f))


static func test_keys_on_change_animated_in_the_inspector(tc: TestCase) -> void:
	var e := StudioConfigEdits.new()
	e.model = _model(tc)
	var s := e.sections("scr", null, "screen")
	var opacity := _field(s, "opacity")
	tc.assert_false(opacity.is_empty(), "the opacity field")
	# Animated: a key at the playhead, the others stay.
	tc.assert_eq(e.commit("scr", opacity, 0.2, 8.0, false, true), "Key scr opacity at 0:08.00")
	var kfs: Array = e.model.tracks()[e.track_of("scr", opacity)].keyframes
	tc.assert_eq(kfs.map(func(k): return [k.t, k.value]), [[3.0, 1.0], [6.0, 0.5], [8.0, 0.2]])
	# A still field is just set.
	var scale := _field(s, "render_scale")
	tc.assert_eq(e.commit("scr", scale, 0.5, 8.0, false, true), "Set scr render scale")
	# Off, between keys: held unkeyed, nothing written.
	tc.assert_has(e.commit("scr", opacity, 0.1, 7.0, false, false), "Not keyed")
	# Off, on a key (within KEY_NEAR): that key changes, the others stay.
	tc.assert_eq(e.commit("scr", opacity, 0.9, 8.02, false, false), "Key scr opacity at 0:08.00")
	kfs = e.model.tracks()[e.track_of("scr", opacity)].keyframes
	tc.assert_eq(kfs.size(), 3, "no second key next to it")
	tc.assert_eq(kfs[2].value, 0.9)
	tc.assert_true(not is_equal_approx(kfs[1].value, 0.9), "the other keys keep their own values")


static func test_keys_on_change_animated_for_grabs(tc: TestCase) -> void:
	var m := _model(tc)
	var tools := StudioEditTools.new()
	tools.model = m
	tools.runner = ScriptRunner.new()
	tools.runner.playhead = 6.0
	tools.key_animated = true
	var before := {"position": [2.0, 1.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]}
	var after := {"position": [2.0, 3.0, 0.0], "rotation_deg": [0.0, 45.0, 0.0], "scale": [1.0, 1.0, 1.0]}
	tools._commit("box", before, after)
	var pos: Array = m.tracks()[m.find_track("transform", "box", "position")].keyframes
	tc.assert_eq(pos.map(func(k): return k.t), [1.0, 4.0, 6.0], "the animated channel gets a key at 6 s")
	tc.assert_eq(pos[0].value, [0.0, 1.0, 0.0], "its other keys stay")
	tc.assert_eq(m.find_track("transform", "box", "rotation_deg"), -1, "a still channel gets no track")
	# Off, on a key: that key is replaced (not a second one beside it).
	tools.key_animated = false
	tools.runner.playhead = 4.03
	var lifted := {"position": [2.0, 5.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]}
	tools._commit("box", before, lifted)
	pos = m.tracks()[m.find_track("transform", "box", "position")].keyframes
	tc.assert_eq(pos.map(func(k): return k.t), [1.0, 4.0, 6.0], "the key at 4 s is the one changed")
	tc.assert_eq(pos[1].value, [2.0, 5.0, 0.0])
	tc.assert_eq(pos[0].value, [0.0, 1.0, 0.0], "the others stay")
	tc.assert_eq(m.tracks()[m.spawn_index("box")].transform.rotation_deg, [0.0, 45.0, 0.0], "it's set")
	tools.runner.free()


static func test_previous_and_next_key(tc: TestCase) -> void:
	var m := _model(tc)
	tc.assert_eq(StudioTimeline.key_times(m, "scr"), [3.0, 6.0], "the selection's keys")
	tc.assert_eq(StudioTimeline.key_times(m, ""), [1.0, 3.0, 4.0, 6.0, 22.0], "every key, each once")
	var all := StudioTimeline.key_times(m, "")
	tc.assert_eq(StudioTimeline.step_key(all, 3.0, 1), 4.0, "next, not the one it's on")
	tc.assert_eq(StudioTimeline.step_key(all, 3.0, -1), 1.0)
	tc.assert_eq(StudioTimeline.step_key(all, 22.0, 1), -1.0, "none after the last")
	tc.assert_eq(StudioTimeline.step_key(all, 0.5, -1), -1.0, "none before the first")
	var b := InputBindings.new()
	tc.assert_eq(b.bindings_on("studio", "key:Up").map(func(x): return x[0]), ["studio_next_key"])
	tc.assert_eq(b.bindings_on("studio", "key:Down").map(func(x): return x[0]), ["studio_prev_key"])


static func test_drag_a_block_whole(tc: TestCase) -> void:
	var m := _model(tc)
	var e := StudioConfigEdits.new()
	e.model = m
	var ribbon := StudioTimelineRibbon.new()
	ribbon.edits = e
	ribbon.view.duration = 30.0
	ribbon._lanes = StudioTimeline.lanes(m, 30.0)
	# scr is on 2..10 with opacity keys at 3 and 6: 4 s later.
	tc.assert_true(ribbon.move_lane("scr", 0, 4.0))
	tc.assert_eq(m.tracks()[m.spawn_index("scr")].t, 6.0, "comes on 4 s later")
	var gone := -1
	for i in m.tracks().size():
		if m.tracks()[i].get("action") == "despawn" and m.tracks()[i].get("target") == "scr":
			gone = i
	tc.assert_eq(m.tracks()[gone].t, 14.0, "and goes 4 s later")
	tc.assert_eq(m.tracks()[m.find_track("shader_param", "scr.display", "opacity")].keyframes.map(func(k): return k.t), [7.0, 10.0], "its keys come along")
	tc.assert_eq(m.undo(), "Move scr to 0:06.00", "one undo step")
	tc.assert_eq(m.tracks()[m.spawn_index("scr")].t, 2.0)
	# Kept inside the piece: no earlier than 0.
	ribbon._lanes = StudioTimeline.lanes(m, 30.0)
	tc.assert_true(ribbon.move_lane("scr", 0, -5.0))
	tc.assert_eq(m.tracks()[m.spawn_index("scr")].t, 0.0, "stops at the start")
	m.undo()
	# On to the end (no despawn): it can't go later; earlier, it gets one.
	ribbon._lanes = StudioTimeline.lanes(m, 30.0)
	tc.assert_false(ribbon.move_lane("late", 0, 3.0), "already at the end")
	tc.assert_true(ribbon.move_lane("late", 0, -5.0))
	tc.assert_eq(m.tracks()[m.spawn_index("late")].t, 15.0)
	var late_gone := m.tracks().filter(func(t): return t.get("action") == "despawn" and t.get("target") == "late")
	tc.assert_eq(late_gone.map(func(t): return t.t), [25.0], "goes 5 s before the end")
	tc.assert_eq(m.tracks()[m.find_track("transform", "late", "position")].keyframes[0].t, 17.0)
	tc.assert_ok(ScriptFormat.load_from_dict(JSON.parse_string(m.to_text()), "<test>"), "valid")
	ribbon.free()


static func test_status_says_a_ride_is_armed(tc: TestCase) -> void:
	var status := StudioStatus.new()
	status._ready()
	status.show_state("EDIT", "clip", false, 0.0, 30.0, false, "", false, false, "", true, true)
	tc.assert_true(status._ride.visible, "the chip")
	tc.assert_true(status._ride_help.visible, "and what it does")
	tc.assert_has(status._ride_help.text, "next take")
	tc.assert_true(status._key_animated.visible, "keys on change: animated")
	status.show_state("EDIT", "clip", false, 0.0, 30.0, true, "", false, false, "● REC", true, false)
	tc.assert_false(status._ride_help.visible, "not while a take runs")
	status.show_state("EDIT", "clip", false, 0.0, 30.0, false, "", true, false, "", false, true)
	tc.assert_false(status._key_animated.visible, "auto-key wins")
	tc.assert_false(status._ride.visible)
	status.free()


static func test_folded_sections_say_whats_inside(tc: TestCase) -> void:
	var fields := [{"label": "Tint"}, {"label": "Flash"}, {"label": "Speed"}, {"label": "Sort offset"}]
	tc.assert_eq(StudioInspector.section_summary(fields), "tint · flash · speed …")
	tc.assert_eq(StudioInspector.section_summary(fields.slice(0, 2)), "tint · flash")
	var ribbon_modes := StudioTimelineRibbon.KEY_MODES.map(func(m): return m[0])
	tc.assert_eq(ribbon_modes, ["off", "animated", "all"])
