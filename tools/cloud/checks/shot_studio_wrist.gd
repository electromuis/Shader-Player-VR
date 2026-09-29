extends SceneTree

## The wrist palette to the mockup (TODO 8, docs/studio/todo/3_wrist.png),
## in the real Studio: the Play / Edit switch, the timecode with the bar,
## both pages of tiles, lit toggles, the help line for the tile under the
## pointer, a swipe to turn the page, Save with "autosaved … ago", and tiles
## sending their commands. Prints what happened; rendered, saves
## studio_wrist_*.png (the wrist's own viewport) to OUT_DIR.

var studio: Node
var wrist: StudioWristPalette
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	if not rendered:
		return
	var sub: SubViewport = studio.stage.xr_rig.wrist_panel.get_node("Viewport")
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await frames(6)
	sub.get_texture().get_image().save_png(out.path_join("studio_wrist_%s.png" % name))


## A press and let-go at two points of the wrist's viewport (the laser's
## clicks arrive the same way, through the Viewport2DIn3D).
func drag(from: Vector2, to: Vector2) -> void:
	var sub: SubViewport = studio.stage.xr_rig.wrist_panel.get_node("Viewport")
	for step in [[from, true], [to, false]]:
		var mv := InputEventMouseMotion.new()
		mv.position = step[0]
		sub.push_input(mv)
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.position = step[0]
		b.pressed = step[1]
		sub.push_input(b)
		await frames(2)


func center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func texts() -> String:
	return "'%s' | '%s' | save '%s' | line '%s' | '%s'" % [wrist._time.text, wrist._sub.text, wrist._save_note.text,
			wrist._line.text, wrist._message.text]


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_wrist/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(185.0)
	studio.studio_settings.autosave = true
	studio.tools.auto_key = false
	studio.tools.key_animated = false
	# A beat grid, as a song's would be: 120 BPM from 0.5 s.
	studio.model.set_beats({"bpm": 120.0, "offset": 0.5, "beats_per_bar": 4})
	await frames(2)
	var rig: XROrigin3D = studio.stage.xr_rig
	rig.wrist_panel.visible = true
	await frames(6)
	wrist = rig.wrist_content() as StudioWristPalette
	print("wrist: ", wrist != null, ", size ", studio.WRIST_SIZE, " m, ", studio.WRIST_PIXELS, " px")
	studio.tools.select("main_screen")
	studio.stage.seek_to(83.4)
	await frames(4)
	print("at 83.4 s: ", texts())
	print("switch: Play ", wrist._play_half.get_meta("on"), ", Edit ", wrist._edit_half.get_meta("on"))
	await shot("1_page1")

	# Tiles send their commands; toggles light up from Studio's state.
	for id in [&"studio_toggle_autokey", &"studio_toggle_snap", &"studio_toggle_inspector", &"studio_toggle_timeline"]:
		wrist.tile(id).pressed.emit()
		await frames(2)
	var lit := []
	for id in wrist._tiles:
		if wrist._tiles[id].lit:
			lit.append(String(id).trim_prefix("studio_"))
	print("pressed auto-key, snap, inspector, timeline: lit ", lit, ", auto-key ", studio.tools.auto_key, ", snap ", studio.tools.snap)
	print("mode line: ", texts())
	wrist.tile(&"studio_toggle_inspector").pressed.emit()
	await frames(2)
	print("inspector again: shown ", studio.inspector_on, ", lit ", wrist.tile(&"studio_toggle_inspector").lit)

	# An unsaved change, autosaved.
	studio.model.set_spawn_transform("main_screen", {"position": [0.0, 2.2, -12.0], "rotation_deg": [0.0, 0.0, 0.0], "scale": [0.12, 0.12, 0.12]})
	studio.autosave_now()
	studio._autosaved_at -= 12000
	await frames(3)
	print("unsaved, autosaved 12 s ago: ", texts())

	# The help line follows the pointer (a move over a tile), then goes back.
	var sub: SubViewport = rig.wrist_panel.get_node("Viewport")
	var mv := InputEventMouseMotion.new()
	mv.position = center(wrist.tile(&"studio_record"))
	sub.push_input(mv)
	await frames(3)
	print("pointer on Record: line '", wrist._line.text, "'")
	await shot("2_toggles_hover")
	mv = InputEventMouseMotion.new()
	mv.position = center(wrist._time)
	sub.push_input(mv)
	await frames(3)
	print("pointer off: line '", wrist._line.text, "'")

	# A press that's really a swipe doesn't press the tile under it; a swipe
	# to the left turns to page 2, a dot back to page 1.
	var undo_before: String = studio.message
	await drag(center(wrist.tile(&"studio_undo")), center(wrist.tile(&"studio_undo")) + Vector2(-400, 10))
	print("swiped left from Undo: page ", wrist.page + 1, ", undone ", studio.message != undo_before and "Undid" in studio.message)
	wrist.tile(&"studio_arm_ride").pressed.emit()
	await frames(3)
	print("arm ride: armed ", studio.recorder.arm_viewer, ", lit ", wrist.tile(&"studio_arm_ride").lit, ", ", texts())
	await shot("3_page2")
	await drag(center(wrist.tile(&"studio_redo")), center(wrist.tile(&"studio_redo")) + Vector2(420, -20))
	print("swiped right: page ", wrist.page + 1)
	wrist.show_page(1)
	await drag(center(wrist._dots[0]), center(wrist._dots[0]))
	print("pressed the first dot: page ", wrist.page + 1)
	wrist.tile(&"studio_arm_ride").pressed.emit()  # disarm

	# A real press (no swipe) on Undo undoes.
	await drag(center(wrist.tile(&"studio_undo")), center(wrist.tile(&"studio_undo")) + Vector2(5, 3))
	print("pressed Undo: '", studio.message, "', unsaved ", studio.model.is_dirty())

	# Play: the tile turns to Pause; the switch's Play half goes to Play mode.
	wrist.tile(&"studio_play_pause").pressed.emit()
	await frames(3)
	print("play: playing ", studio.runner.playing, ", tile '", wrist.tile(&"studio_play_pause").caption, "'")
	await shot("4_playing")
	wrist.tile(&"studio_play_pause").pressed.emit()
	await frames(2)
	wrist._edit_half.pressed.emit()
	await frames(2)
	print("Edit half pressed in Edit: mode ", studio.mode)
	wrist._play_half.pressed.emit()
	await frames(2)
	print("Play half pressed: mode ", studio.mode, " (0 = play), wrist shown ", rig.wrist_panel.visible)
	quit(0)
