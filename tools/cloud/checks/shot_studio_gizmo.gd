extends SceneTree

## The move gizmo (TODO 66) and locking (TODO 62), driven in the real Studio
## on the desktop: the selected screen shows an arrow on each axis; hovering
## one lights it; pressing it and dragging moves the screen along that axis
## only (x freely, then y with snapping in 10 cm steps), each let-go one undo
## step. Locked from the inspector's switch, the screen has no arrows, a press
## on it doesn't carry it and its box says Locked; typed numbers still move
## it; the flag is saved. Prints what happened; rendered, saves
## studio_gizmo_*.png to OUT_DIR.

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
	root.get_texture().get_image().save_png(out.path_join("studio_gizmo_%s.png" % name))


func mouse(at: Vector2, pressed := true) -> void:
	Input.warp_mouse(at)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	studio._unhandled_input(e)


func motion(at: Vector2, rel: Vector2) -> void:
	Input.warp_mouse(at)
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = rel
	studio._unhandled_input(e)


func screen() -> Node3D:
	return studio.runner.registry().get_node_by_id("main_screen")


func pos() -> String:
	var p := screen().position
	return "(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]


## Where on the window gizmo arrow `axis` is (`share` of the way out).
func arrow_at(axis: int, share := 0.8) -> Vector2:
	var g: Dictionary = studio.tools.gizmo()
	return studio.stage.desktop_camera.unproject_position(g.origin + (g.axes[axis] as Vector3) * g.length * share)


## Drag gizmo arrow `axis` by `by` pixels, in steps; returns the position
## seen mid-drag (after `shoot`, if given, is saved).
func drag_arrow(axis: int, by: Vector2, shoot := "") -> String:
	var at := arrow_at(axis)
	studio._update_hover(1.0)
	mouse(at)
	print("  pressed on the %s arrow: grabbing %s along %d" % ["xyz"[axis], studio.tools.grabbed_id(), studio.tools.grabbed_axis()])
	for i in 5:
		motion(at + by * (i + 1) / 5.0, by / 5.0)
	var mid := pos()
	if shoot != "":
		await shot(shoot)
	mouse(at + by, false)
	await frames(2)
	return mid


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_gizmo/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
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
	var tools: StudioEditTools = studio.tools
	var m: EditModel = studio.model
	studio.get_node("UI").visible = false  # the clicks go to the stage
	studio.stage.desktop_camera.set_view(screen().global_position + Vector3(4, 2.5, 9), screen().global_position)
	tools.select("main_screen")
	await frames(4)
	var g := tools.gizmo()
	print("gizmo: %d arrows, %.2f m long, at %s" % [g.axes.size(), g.length, g.origin])
	print("before: ", pos())

	# Hover: the pointer on the x arrow lights it, off it nothing.
	Input.warp_mouse(arrow_at(0))
	studio._update_hover(1.0)
	print("hover on x: axis %d, object '%s'" % [tools.hovered_axis, tools.hovered])
	await shot("1_hover_x")
	Input.warp_mouse(arrow_at(1))
	studio._update_hover(1.0)
	print("hover on y: axis %d" % tools.hovered_axis)
	Input.warp_mouse(Vector2(20, 20))
	studio._update_hover(1.0)
	print("hover on nothing: axis %d" % tools.hovered_axis)

	# Along x, freely: y and z stay.
	var before := pos()
	var mid := await drag_arrow(0, Vector2(160, 0), "2_drag_x")
	print("x drag: %s -> mid-drag %s -> let go %s; '%s'" % [before, mid, pos(), m.undo_label()])
	print("  spawn: ", tools._spawn_transform("main_screen").position)
	# Along y with snapping: whole 10 cm steps, x and z stay.
	tools.snap = true
	before = pos()
	await drag_arrow(1, Vector2(0, -90))
	print("y drag, snapped: %s -> %s; '%s'" % [before, pos(), m.undo_label()])
	tools.snap = false
	var p0 := screen().position
	m.undo()
	await frames(2)
	print("undo: %s (back from %s)" % [pos(), p0])
	await shot("3_after_x")

	# Locked, from the inspector's switch.
	studio.get_node("UI").visible = true
	var insp: StudioInspector = studio.inspector
	await frames(4)
	var sw := insp.find_child("LockSwitch", true, false) as Button
	print("lock switch: %s, on %s" % [sw != null, sw.button_pressed if sw != null else false])
	sw.button_pressed = true
	await frames(4)
	print("switched on: locked %s; '%s'; message '%s'" % [m.is_locked("main_screen"), m.undo_label(), studio.message])
	sw = insp.find_child("LockSwitch", true, false) as Button
	print("rebuilt switch on: %s" % sw.button_pressed)
	print("gizmo when locked: %s" % tools.gizmo())
	await shot("4_locked")
	studio.get_node("UI").visible = false
	await frames(2)
	before = pos()
	var at: Vector2 = studio.stage.desktop_camera.unproject_position(screen().global_position)
	mouse(at)
	print("press on it: grabbing '%s'; message '%s'" % [tools.grabbed_id(), studio.message])
	motion(at + Vector2(120, 40), Vector2(120, 40))
	mouse(at + Vector2(120, 40), false)
	await frames(2)
	print("dragged: %s -> %s (stays); selected '%s'" % [before, pos(), tools.selected])
	var typed := tools.set_channel("main_screen", "position", [0.5, 2.0, -1.0])
	await frames(2)
	print("typed numbers: '%s' -> %s" % [typed, pos()])
	var saved := m.save()
	var text := FileAccess.get_file_as_string(m.path)
	print("saved %s; the file has \"locked\": true: %s" % [saved.ok, text.contains("\"locked\": true")])
	var back := ScriptFormat.load_from_file(m.path)
	print("the player loads it: %s" % back.ok)
	tools.set_locked("main_screen", false)
	await frames(4)
	print("unlocked: gizmo %s arrows" % tools.gizmo().get("axes", []).size())
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	quit(0)
