extends RefCounted

## Without portable.ini next to the executable (the test runner's Godot),
## everything is saved in user://.


static func test_not_portable_uses_user_dir(t: TestCase) -> void:
	t.assert_false(AppPaths.is_portable())
	t.assert_eq(AppPaths.save_path("player_settings.json"), "user://player_settings.json")
	t.assert_eq(AppPaths.presets_dir(), "user://presets")
