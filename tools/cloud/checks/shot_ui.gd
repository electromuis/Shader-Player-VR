extends SceneTree

## Rendered: the Camera tab's camera effect section, a broken user effect's
## error, the placement sliders' ↺, and the Config tab with its ↺ (one
## pressed). -> ui_*.png

func _panel_shot(content: Node, name: String) -> void:
	for i in 25:
		await process_frame
	content.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT_DIR").path_join(name))


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://shaders")
	var f := FileAccess.open("user://shaders/my_trip.glsl", FileAccess.WRITE)
	f.store_string("// @camera\nuniform float wobble : hint_range(0.0, 1.0, 0.01) = 0.3;\nvec3 camera_fx(vec2 uv) {\n\treturn view_color(uv) * wobbel;\n}\n")
	f.close()
	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var content: Node = main.floating_panel.content()
	main.floating_panel.toggle()
	var fx: CameraFxSettings = main.stage.layers.camera_fx
	fx.shader = "builtin:kaleidoscope"
	var scroll: ScrollContainer = content.camera_tab.get_parent()
	for i in 10:
		await process_frame
	scroll.scroll_vertical = 100000
	await _panel_shot(content, "ui_camera_fx.png")
	fx.shader = ProjectSettings.globalize_path("user://shaders/my_trip.glsl")
	for i in 20:
		await process_frame
	scroll.scroll_vertical = 100000
	await _panel_shot(content, "ui_camera_fx_error.png")
	# ↺ on the placement rows: off at the default, on once moved, and back.
	var screen: ScreenSettings = main.stage.screen_settings
	var tab: Node = content.camera_tab
	var size_reset: Button = tab.size_value.get_parent().get_child(tab.size_value.get_index() + 1)
	print("size ↺ at default: disabled %s" % size_reset.disabled)
	screen.size = 1.5
	screen.opacity = 0.6
	await process_frame
	print("size ↺ after 1.5×: disabled %s" % size_reset.disabled)
	scroll.scroll_vertical = 0
	await _panel_shot(content, "ui_camera_resets.png")
	size_reset.pressed.emit()
	print("size ↺ pressed: size %s, disabled %s, opacity kept %s" % [screen.size, size_reset.disabled, screen.opacity])
	screen.opacity = 1.0
	var cfg_margin: Node = content.config_tab.get_parent()
	while not (cfg_margin.get_parent() is TabContainer):
		cfg_margin = cfg_margin.get_parent()
	cfg_margin.get_parent().current_tab = cfg_margin.get_index()
	var settings: PlayerSettings = main._player_settings
	settings.volume = 0.4
	settings.skybox = "space"
	settings.script_camera_cuts_only = true
	await _panel_shot(content, "ui_config.png")
	var cfg: Node = content.config_tab
	for label in ["Volume", "Skybox", "Script camera", "FPS"]:
		print("config ↺ %s: disabled %s" % [label, (cfg._rows[label] as Control).get_child(-1).disabled])
	(cfg._rows["Volume"] as Control).get_child(-1).pressed.emit()
	(cfg._rows["Script camera"] as Control).get_child(-1).pressed.emit()
	print("config ↺ pressed: volume %s, cuts only %s, skybox kept %s" % [settings.volume, settings.script_camera_cuts_only, settings.skybox])
	settings.skybox = "black"
	print("UI SHOTS DONE")
	quit()
