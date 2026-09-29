extends RefCounted

## PlayerSettings' defaults and ↺ (the Config tab's reset, in the player
## and in Studio).

const PATH := "user://test_player_settings_reset_tmp.json"


static func test_reset_to_default(t: TestCase) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var s := PlayerSettings.new(PATH)
	for field in ["locomotion", "allow_script_camera", "script_camera_cuts_only", "skybox", "show_floor",
			"show_fps", "volume", "end_action", "live_sync", "fullscreen", "show_play_bar", "camera_fx",
			"camera_fx_max", "video_decoder", "ui_scale"]:
		t.assert_true(s.is_default(field), "%s starts at its default" % field)
	s.volume = 0.37
	s.skybox = "space"
	s.script_camera_cuts_only = true
	t.assert_false(s.is_default("volume"), "a changed volume isn't")
	t.assert_false(s.is_default("skybox"), "nor the skybox")
	var changes := [0]
	s.changed.connect(func(): changes[0] += 1)
	s.reset("volume")
	s.reset("skybox")
	s.reset("show_fps")  # already there: no notice, no write
	t.assert_eq(changes[0], 2, "a reset is a change")
	t.assert_true(s.volume == 1.0 and s.skybox == "black", "back to the defaults")
	var back := PlayerSettings.new(PATH)
	back.load_from_disk()
	t.assert_eq(back.volume, 1.0, "the reset is saved")
	t.assert_true(back.script_camera_cuts_only, "the rest kept")
	t.assert_eq(PlayerSettings._defaults().volume, 1.0, "the defaults stay untouched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
