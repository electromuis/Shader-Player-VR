extends SceneTree

## Studio's menu (F2), driven in the real Studio: opens over the middle of
## the window on the desktop (the headset's copy is on a panel), the player's Config tab without the rows Studio has no use for,
## the Controls tab listing Studio's commands, the Studio tab's options
## reaching Studio (key mode both ways, haptics, autosave, ↺), the shared
## FPS setting hiding the status's readout, ✕ closing it. Prints what
## happened; rendered, saves studio_menu_*.png to OUT_DIR (each tab in the
## window, and the headset panel's Config tab).

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


## The desktop menu, cropped out of the window.
func shot(name: String) -> void:
	if not rendered:
		return
	await frames(6)
	var img := root.get_texture().get_image()
	var r := Rect2i(studio.menu_2d.get_global_rect())
	img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(out.path_join("studio_menu_%s.png" % name))


func visible_rows(tab: Node) -> Array:
	var out_rows: Array = []
	for row in tab.get_children():
		if row is HBoxContainer and row.visible and row.get_child_count() > 0 and row.get_child(0) is Label:
			out_rows.append((row.get_child(0) as Label).text)
	return out_rows


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_menu/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	# A clean start for Studio's own settings.
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	print("menus bound: desktop ", studio.menu_2d != null, ", headset ", studio.menu != null, "; shown ", studio.menu_2d.visible)
	studio._on_command(&"studio_menu")
	await frames(4)
	var menu: StudioMenu = studio.menu_view()
	print("F2: desktop menu shown %s at %s, headset panel %s ('%s')" % [menu.visible,
			Rect2i(menu.get_global_rect()), studio.menu_panel.visible, studio.message])
	print("tabs: ", range(menu.tabs.get_tab_count()).map(func(i): return menu.tabs.get_tab_title(i)))
	print("config rows: ", visible_rows(menu.config_tab))
	await shot("1_config")

	# The shared FPS setting: the status's readout follows it.
	var fps_label: Label = studio.status_view._fps
	var s: PlayerSettings = studio._settings
	s.show_fps = true
	await frames(2)
	print("show fps on: readout visible ", fps_label.visible)
	s.show_fps = false
	await frames(2)
	print("show fps off: readout visible ", fps_label.visible)

	menu.tabs.current_tab = 1
	await frames(4)
	var titles: Array = []
	for c in menu.controls_tab._list.get_children():
		if c is Label:
			titles.append(c.text)
	print("controls sections: ", titles, ", rows ", menu.controls_tab._list.get_child_count())
	await shot("2_controls")

	menu.tabs.current_tab = 2
	await frames(4)
	var tab: Node = menu.studio_tab
	print("studio rows: ", visible_rows(tab))
	tab._key_mode.select(1)
	tab._key_mode.item_selected.emit(1)
	await frames(2)
	print("key mode Animated: tools auto_key %s, key_animated %s; ↺ enabled %s" % [studio.tools.auto_key,
			studio.tools.key_animated, not tab._resets.key_mode.disabled])
	tab._haptics.toggled.emit(false)
	tab._autosave.toggled.emit(false)
	await frames(2)
	print("haptics off: %s; autosave off: %s" % [not studio.haptics.enabled, not studio.studio_settings.autosave])
	await shot("3_studio")
	# Shift+I on the keyboard: the tab follows.
	studio._on_command(&"studio_toggle_autokey")
	await frames(2)
	print("Shift+I: settings key mode '%s', tab shows '%s'" % [studio.studio_settings.key_mode, tab._key_mode.get_item_text(tab._key_mode.selected)])
	tab._resets.key_mode.pressed.emit()
	tab._resets.haptics.pressed.emit()
	tab._resets.autosave.pressed.emit()
	await frames(2)
	print("↺: key mode '%s' (auto_key %s), haptics %s, autosave %s" % [studio.studio_settings.key_mode,
			studio.tools.auto_key, studio.haptics.enabled, studio.studio_settings.autosave])
	var saved := StudioSettings.new()
	saved.load_from_disk()
	print("saved: ", saved.to_dict())

	if rendered:
		menu.tabs.current_tab = 0
		await frames(8)
		root.get_texture().get_image().save_png(out.path_join("studio_menu_4_window.png"))
		# The headset's copy, on its panel.
		studio.menu_panel.show_in_front_of(studio.stage.desktop_camera)
		var sub: SubViewport = studio.menu_panel.panel_quad().get_node("Viewport")
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await frames(8)
		sub.get_texture().get_image().save_png(out.path_join("studio_menu_5_headset.png"))
		studio.menu_panel.hide_panel()
	var close: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text == "✕":
			close = b
	close.pressed.emit()
	await frames(3)
	print("✕: shown ", menu.visible, " (menu_on ", studio.menu_on, ")")
	studio._on_command(&"studio_menu")
	studio._on_command(&"studio_deselect")
	print("F2 then Esc: shown ", menu.visible)
	print("STUDIO MENU DONE")
	quit()
