extends RefCounted

## Studio's menu: its own settings (StudioSettings: defaults, saving, ↺),
## and opening it (F2, or holding ≡ while a tap still switches Play / Edit).
## The panel itself needs a scene tree: checks/shot_studio_menu.gd.

const INPUT := preload("res://tests/test_input.gd")
const PATH := "user://test_studio_settings.json"


static func test_settings_save_and_reset(tc: TestCase) -> void:
	DirAccess.remove_absolute(PATH)
	var s := StudioSettings.new(PATH)
	s.load_from_disk()
	tc.assert_eq(s.to_dict(), {"kind": "studio_settings", "key_mode": "off", "haptics": true, "autosave": true, "floor_grid": true, "all_paths": true, "panels": {}}, "defaults with no file")
	var changes := [0]
	s.changed.connect(func(): changes[0] += 1)
	s.key_mode = "animated"
	s.haptics = false
	s.floor_grid = false
	s.haptics = false  # no change: no notice, no write
	tc.assert_eq(changes[0], 3)
	s.key_mode = "sideways"
	tc.assert_eq(s.key_mode, "off", "an unknown mode is the default")
	s.key_mode = "all"
	tc.assert_false(s.is_default("key_mode"))
	var back := StudioSettings.new(PATH)
	back.load_from_disk()
	tc.assert_eq(back.to_dict(), s.to_dict(), "read back as saved")
	back.reset("haptics")
	tc.assert_true(back.haptics and back.is_default("haptics"), "↺")
	var again := StudioSettings.new(PATH)
	again.load_from_disk()
	tc.assert_true(again.haptics, "the reset is saved")
	DirAccess.remove_absolute(PATH)


## Where panels were put (TODO 75): saved one value at a time, read back,
## forgotten one at a time, and all put back by ↺.
static func test_panel_places(tc: TestCase) -> void:
	DirAccess.remove_absolute(PATH)
	var s := StudioSettings.new(PATH)
	tc.assert_true(s.is_default("panels"), "none moved")
	tc.assert_eq(s.panel_value("inspector", "rect"), null)
	s.set_panel_value("inspector", "rect", [10.0, 20.0, 400.0, 600.0])
	s.set_panel_value("inspector", "vr_at", [0.3, -0.1, -0.7])
	s.set_panel_value("shelf", "vr_size", [1000.0, 700.0])
	var back := StudioSettings.new(PATH)
	back.load_from_disk()
	tc.assert_eq(back.panel_value("inspector", "rect"), [10.0, 20.0, 400.0, 600.0], "read back")
	tc.assert_eq(back.panel_value("shelf", "vr_size"), [1000.0, 700.0])
	tc.assert_false(back.is_default("panels"))
	back.set_panel_value("shelf", "vr_size", null)
	tc.assert_eq(back.panels.keys(), ["inspector"], "a panel with nothing saved is dropped")
	back.reset("panels")
	tc.assert_true(back.is_default("panels"), "↺")
	back.set_panel_value("timeline", "rect", [1.0, 2.0, 3.0, 4.0])
	tc.assert_eq(StudioSettings.DEFAULTS.panels, {}, "the default isn't changed by a later save")
	var junk := FileAccess.open(PATH, FileAccess.WRITE)
	junk.store_string('{"kind": "studio_settings", "panels": [1, 2]}')
	junk.close()
	var bad := StudioSettings.new(PATH)
	bad.load_from_disk()
	tc.assert_eq(bad.panels, {}, "not an object: none")
	DirAccess.remove_absolute(PATH)


static func test_menu_opens_with_f2_or_a_held_menu_button(tc: TestCase) -> void:
	var b := INPUT._bindings()
	tc.assert_eq(b.conflicts(), [], "no clashes")
	var pair := INPUT._router(b, ["studio"])
	var r: InputRouter = pair[0]
	var log: Array = pair[1]
	r.set_context("play", false)
	INPUT._tap(r, "L.menu", 1.0)
	tc.assert_eq(log, ["studio_toggle_mode"], "a tap still switches Play / Edit")
	r.feed_button("L.menu", true, 2.0)
	r.update(2.7)
	r.feed_button("L.menu", false, 2.8)
	tc.assert_eq(log, ["studio_toggle_mode", "studio_menu"], "held: the menu, and no switch")
	log.clear()
	INPUT._key(r, KEY_F2)
	tc.assert_eq(log, ["studio_menu"])
	tc.assert_eq(InputBindings.command_app("studio_menu"), "studio")
	# Left-handed mirrors it with the rest (the left hand's ≡ stays: the
	# right has none to give).
	b.apply_left_handed()
	tc.assert_eq(b.conflicts(), [], "no clashes left-handed")
	r.free()
