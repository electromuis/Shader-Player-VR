extends SceneTree

## The player's colour params (TODO 20, the player's side): the Camera
## tab's colour rows (Glow's tint on the screen; a user layer shader's
## `source_color` uniform), and the values reaching the shaders (a layer
## used to drop its colours). Rendered: ui_colours_*.png.

const LAYER := "shader_type canvas_item;\n#include \"res://player/visualizer/shadertoy_prelude.gdshaderinc\"\n\nuniform vec3 ink : source_color = vec3(0.2, 0.6, 1.0);\nuniform float rings : hint_range(1.0, 20.0, 1.0) = 6.0;\n\nvoid fragment() {\n\tfloat r = length(UV - 0.5) * rings;\n\tCOLOR = vec4(ink * (0.5 + 0.5 * sin(r * 6.2832)), 1.0);\n}\n"


func _panel_shot(content: Node, name: String) -> void:
	for i in 25:
		await process_frame
	if DisplayServer.get_name() != "headless":
		content.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT_DIR").path_join(name))


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://shaders")
	var f := FileAccess.open("user://shaders/ink_rings.gdshader", FileAccess.WRITE)
	f.store_string(LAYER)
	f.close()
	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var content: Node = main.floating_panel.content()
	main.floating_panel.toggle()
	var tab: Node = content.camera_tab
	var scroll: ScrollContainer = tab.get_parent()
	# The screen: Glow, tinted orange from its row.
	var screen: ScreenSettings = main.stage.screen_settings
	screen.effects.clear()
	screen.add_effect("res://player/visualizer/effects/glow.gdshader")
	tab._set_target(0)
	tab._open_effects.append(screen.effects[0])
	tab._rebuild_dynamic()
	for i in 10:
		await process_frame
	var pick: ColorPickerButton = tab.effects_box.find_children("*", "ColorPickerButton", true, false).front() \
			if not tab.effects_box.find_children("*", "ColorPickerButton", true, false).is_empty() else null
	print("glow's tint row: %s (effects box: %s; settings effects %s; edited is screen %s)" % [pick != null,
			tab.effects_box.get_children().map(func(c): return c.get_class()), screen.effects, tab._edited() == screen])
	if pick != null:
		pick.color = Color(1.0, 0.5, 0.1)
		pick.color_changed.emit(pick.color)
	print("screen glow tint in settings: %s" % [screen.effects[0].params.get("tint")])
	for i in 5:
		await process_frame
	var node: Screen = main.stage.runner.registry().get_node_by_id(DefaultScreen.SCREEN_ID)
	print("on the screen's glow pass: %s" % [node._effect_params[0].get("tint") if node != null and node._effect_params.size() > 0 else "no screen"])
	if pick != null:
		scroll.ensure_control_visible(pick)
	await _panel_shot(content, "ui_colours_glow.png")
	# A layer on the user shader: its ink colour.
	main.stage.layers.set_count(1)
	for i in 5:
		await process_frame
	tab._set_target(1)
	var layer: LayerSettings = main.stage.layers.layers[0]
	layer.shader = ProjectSettings.globalize_path("user://shaders/ink_rings.gdshader")
	for i in 10:
		await process_frame
	var ink: ColorPickerButton = null
	for c in tab.params_box.find_children("*", "ColorPickerButton", true, false):
		ink = c
	print("layer's ink row: %s, shows %s" % [ink != null, ink.color if ink != null else null])
	if ink != null:
		ink.color = Color(0.9, 0.2, 0.6)
		ink.color_changed.emit(ink.color)
	for i in 5:
		await process_frame
	var vis: Visualizer = main.stage._layer_nodes[0]
	print("layer ink in settings %s, on its material %s" % [layer.params.get("ink"), vis._material.get_shader_parameter("ink") if vis._material != null else null])
	scroll.ensure_control_visible(ink)
	await _panel_shot(content, "ui_colours_layer.png")
	main.stage.layers.set_count(0)
	screen.effects.clear()
	print("COLOURS DONE")
	quit()
