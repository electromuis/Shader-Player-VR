extends RefCounted

## The desktop UI scale setting, and Studio's shortcut table.

const SETTINGS := "user://test_player_settings_ui_scale_tmp.json"


static func test_ui_scale_round_trip(t: TestCase) -> void:
	var s := PlayerSettings.new(SETTINGS)
	t.assert_eq(s.ui_scale, 1.0, "100% by default")
	s.ui_scale = 1.5
	var back := PlayerSettings.new(SETTINGS)
	back.load_from_disk()
	t.assert_eq(back.ui_scale, 1.5, "saved")
	s.ui_scale = 1.3
	t.assert_eq(s.ui_scale, 1.25, "snaps to the nearest offered scale")
	s.ui_scale = 9.0
	t.assert_eq(s.ui_scale, 2.0, "capped at the largest")
	t.assert_true(PlayerSettings.UI_SCALES.has(1.0), "100% is offered")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


static func test_status_hint_table(t: TestCase) -> void:
	var keys := {}
	for group in StudioStatus.HINTS:
		t.assert_eq(typeof(group[0]), TYPE_STRING, "group has a heading")
		for row in group[1]:
			t.assert_eq(row.size(), 2, "%s: key and action" % row[0])
			t.assert_false(keys.has(row[0]), "%s listed once" % row[0])
			keys[row[0]] = true
	t.assert_true(keys.has("Ctrl+S") and keys.has("Tab"), "save and mode listed")


static func test_status_hints_toggle(t: TestCase) -> void:
	var status := StudioStatus.new()
	status._ready()
	t.assert_true(status.hints_on, "shown at first")
	status.show_hints(false)
	t.assert_false(status._hints.visible, "table hidden")
	t.assert_true(status._hints_off.visible, "says how to get it back")
	status.show_hints(true)
	t.assert_true(status._hints.visible and not status._hints_off.visible, "back")
	var b := InputBindings.new()
	t.assert_eq(b.bindings_on("studio", "key:H").map(func(x): return x[0]), ["studio_toggle_hints"], "H toggles them in Studio")
	status.free()
