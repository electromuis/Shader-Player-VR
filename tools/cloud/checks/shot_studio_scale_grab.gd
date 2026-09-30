extends SceneTree

## Scaling what you hold (TODO 67), driven in the real Studio on the
## desktop: press on the screen and hold, Ctrl+wheel up three notches,
## Ctrl+drag down, let go (one undo step, the scale written, the screen
## where it was); a plain wheel still pushes; a hand's scale_by (the right
## stick sideways in the headset). Prints what happened; rendered, saves
## studio_scale_grab_*.png to OUT_DIR.

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	if not rendered:
		return
	var screen: Screen = studio.runner.registry().get_node_by_id("main_screen")
	screen.set_source_texture(StudioThumbnailer.test_card())
	await frames(8)
	root.get_texture().get_image().save_png(out.path_join("studio_scale_grab_%s.png" % name))


func mouse(at: Vector2, button := MOUSE_BUTTON_LEFT, pressed := true, ctrl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.ctrl_pressed = ctrl
	studio._unhandled_input(e)


func motion(at: Vector2, rel: Vector2, ctrl := false) -> void:
	Input.warp_mouse(at)
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = rel
	e.ctrl_pressed = ctrl
	studio._unhandled_input(e)


func state(node: Node3D) -> String:
	return "scale %.3f at %s" % [node.scale.x, node.global_position.snapped(Vector3.ONE * 0.001)]


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_scale_grab/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.spscript"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	studio = load("res://studio/studio.tscn").instantiate()
	studio._cli_desktop = true
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.get_node("UI").visible = false  # the clicks go to the stage
	studio.stage.desktop_camera.set_view(Vector3(0, 2, 10), Vector3(0, 0, 0))
	await frames(4)
	var screen: Node3D = studio.runner.registry().get_node_by_id("main_screen")
	var at: Vector2 = studio.stage.desktop_camera.unproject_position(screen.global_position)
	print("before: ", state(screen))
	await shot("1_before")

	Input.warp_mouse(at)
	mouse(at)
	print("pressed on it: grabbing %s" % studio.tools.grabbed_id())
	for i in 3:
		mouse(at, MOUSE_BUTTON_WHEEL_UP, true, true)
	print("Ctrl+wheel up ×3: ", state(screen))
	await shot("2_ctrl_wheel")
	for i in 4:
		motion(at + Vector2(0, 25 * (i + 1)), Vector2(0, 25), true)
	print("Ctrl+drag down 100 px: ", state(screen), " (expect ×%.3f)" % pow(2.0, -0.5))
	motion(at + Vector2(0, 100), Vector2.ZERO, false)
	print("mouse still, Ctrl up: ", state(screen))
	mouse(at, MOUSE_BUTTON_WHEEL_UP)
	print("plain wheel up: ", state(screen), " (pushed)")
	mouse(at, MOUSE_BUTTON_WHEEL_DOWN)
	print("plain wheel down: ", state(screen), " (back)")
	mouse(at + Vector2(0, 100), MOUSE_BUTTON_LEFT, false)
	await frames(2)
	var m: EditModel = studio.model
	print("let go: '%s'; spawn %s" % [m.undo_label(), studio.tools._spawn_transform("main_screen")])
	await shot("3_let_go")

	# A controller: grab, then the stick's scale_by; two hands don't take it.
	screen = studio.runner.registry().get_node_by_id("main_screen")  # rebuilt by the edit
	print("rebuilt: ", state(screen))
	var hand := Transform3D(Basis(), Vector3(0, 2, 6))
	studio.tools.grab("main_screen", "R", hand)
	studio.tools.scale_by(0.5)
	print("hand scale_by 0.5: ", state(screen))
	studio.tools.add_hand("L", Transform3D(Basis(), Vector3(-0.3, 2, 6)))
	studio.tools.scale_by(4.0)
	print("two hands, scale_by 4 ignored: ", state(screen))
	studio.tools.release_hand("L")
	studio.tools.scale_by(1e-6)
	print("scale_by tiny, clamped: ", state(screen))
	studio.tools.cancel()
	await frames(2)
	print("cancelled: ", state(screen))
	m.undo()
	await frames(2)
	screen = studio.runner.registry().get_node_by_id("main_screen")
	print("undo: ", state(screen))
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	quit(0)
