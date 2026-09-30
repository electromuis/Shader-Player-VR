extends SceneTree

## Groups and the outliner (TODO 14, 15), driven in the real Studio: a
## three-screen split, a cube and a viewer ride. Shows the outliner (O),
## selects left and Ctrl+clicks middle and right in it, groups them
## (Ctrl+G), keys the group turning and rising with auto-key, grabs it by a
## member, drags the cube's row onto the group's, folds the group, ungroups
## it, undoes, and saves. At each step it prints where the runner has the
## screens on stage, which must not move when the grouping changes.
## Rendered, saves studio_outliner_*.png to OUT_DIR (and the headset
## outliner's own picture).

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Screens show a test card (nothing here decodes video).
func put_card() -> void:
	var reg: ObjectRegistry = studio.runner.registry()
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(StudioThumbnailer.test_card())


func shot(name: String) -> void:
	if not rendered:
		return
	put_card()
	await frames(6)
	root.get_texture().get_image().save_png(out.path_join("studio_outliner_%s.png" % name))


func spawn(id: String, prefab: String, pos: Array, yaw: float, scale: float) -> Dictionary:
	return {"type": "event", "t": 0.0, "action": "spawn", "id": id, "prefab": prefab,
			"transform": {"position": pos, "rotation_deg": [0.0, yaw, 0.0], "scale": [scale, scale, scale]}}


## Where the runner has `ids` on stage now (rounded to the millimetre).
func places(ids: Array) -> Dictionary:
	var outp := {}
	for id in ids:
		var n: Node3D = studio.runner.registry().get_node_by_id(id)
		outp[id] = n.global_position.snappedf(0.001) if n != null else null
	return outp


## Whether everything in `b` is where `a` has it.
func same(a: Dictionary, b: Dictionary) -> bool:
	for id in b:
		if a[id] == null or b[id] == null or (a[id] as Vector3).distance_to(b[id]) > 0.002:
			return false
	return true


## Press a row of `view`, move to `to` (global) and let go: a drag.
func drag_row(view: StudioOutliner, id: String, to: Vector2) -> void:
	var row: Button = view._rows[id]
	var from := row.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = from
	view._row_input(press, row)
	for k in 4:
		var move := InputEventMouseMotion.new()
		move.global_position = from.lerp(to, (k + 1) / 4.0)
		view._row_input(move, row)
		await frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.global_position = to
	view._row_input(up, row)
	await frames(3)


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_outliner/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	var piece := {
		"format_version": 2,
		"meta": {"title": "Split", "default_screen": false},
		"media": {"video": "clip.mp4", "duration": 20.0},
		"prefabs": {"screen": "res://player/prefabs/screen.tscn", "cube": "res://player/prefabs/cube.tscn"},
		"tracks": [
			spawn("left", "screen", [-2.1, 2.0, -3.4], 25.0, 0.06),
			spawn("middle", "screen", [0.0, 2.0, -3.9], 0.0, 0.06),
			spawn("right", "screen", [2.1, 2.0, -3.4], -25.0, 0.06),
			spawn("cube", "cube", [1.6, 0.4, -1.6], 0.0, 0.5),
			{"type": "transform", "target": "$viewer", "channel": "position", "keyframes": [
				{"t": 0.0, "value": [0.0, 2.0, 8.0]}, {"t": 12.0, "value": [0.0, 2.0, 4.0]}]},
		],
	}
	f = FileAccess.open(dir.path_join("clip.spscript"), FileAccess.WRITE)
	f.store_string(JSON.stringify(piece, "  "))
	f.close()
	DirAccess.remove_absolute(dir.path_join("clip.spscript.autosave"))
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	studio = load("res://studio/studio.tscn").instantiate()
	studio._cli_desktop = true
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.spscript"))
	await frames(6)
	var cam = studio.stage.desktop_camera
	cam.set_view(Vector3(3.2, 3.4, 6.5), Vector3(-9, 0, 0))
	studio.status_view.show_hints(false)
	var tools: StudioEditTools = studio.tools
	var view: StudioOutliner = studio.outliner
	var screens := ["left", "middle", "right"]
	var start := places(screens + ["cube"])
	print("on stage: ", start)

	studio._on_command(&"studio_toggle_outliner")
	await frames(4)
	print("outliner shown: ", view.visible, ", rows ", view._rows.keys())
	await shot("1_outliner")

	view.click("left")
	view.click("middle", true)
	view.click("right", true)
	await frames(3)
	print("selected ", tools.selected, ", picked ", view.picked, ", Group would take ", view.group_ids())
	await shot("2_picked")

	studio._on_command(&"studio_group")
	await frames(6)
	print(studio.message)
	print("tree: ", StudioGrouping.tree(studio.model).map(func(r): return "%s%s" % ["  ".repeat(r.depth), r.id]))
	var g: Dictionary = studio.model.tracks()[studio.model.spawn_index("group")]
	print("the group spawns at ", g.t, " s at ", g.transform.position)
	var grouped := places(screens + ["cube"])
	print("grouped, nothing moved: ", same(start, grouped), " ", grouped)
	print("group node's children: ", studio.runner.registry().get_node_by_id("group").get_children().map(func(c): return String(c.name)))
	await shot("3_grouped")

	# Pointing at a member with the group selected picks the group.
	var mid: Node3D = studio.runner.registry().get_node_by_id("middle")
	var eye: Vector3 = cam.global_position
	print("pointing at middle picks: ", tools.pick(eye, (mid.global_position - eye).normalized()))

	# Animate the group: auto-key at 0 s, then turned and raised at 8 s.
	tools.auto_key = true
	tools.key_selection()
	studio.stage.seek_to(8.0)
	await frames(3)
	tools.set_channel("group", "rotation_deg", [0.0, 35.0, 0.0])
	tools.set_channel("group", "position", [0.0, 3.0, -3.57])
	await frames(3)
	print(studio.message)
	print("group keys: ", studio.model.tracks().filter(func(t): return t.get("target") == "group").map(func(t): return [t.channel, t.keyframes.map(func(k): return k.t)]))
	var turned := places(screens)
	print("at 8 s the screens turned with it: ", turned)
	await shot("4_group_keyed_8s")
	studio.stage.seek_to(4.0)
	await frames(3)
	print("at 4 s halfway: ", places(screens))
	studio.stage.seek_to(0.0)
	await frames(3)
	print("at 0 s where they were: ", same(start, places(screens)))
	tools.auto_key = false

	# Drag the cube's row onto the group's.
	await drag_row(view, "cube", view._rows["group"].get_global_rect().get_center())
	await frames(4)
	print(studio.message)
	print("cube's parent: ", StudioGrouping.parent_of(studio.model, "cube"), ", cube stayed put: ", same({"cube": start.cube}, places(["cube"])))
	tools.select("cube")
	await frames(3)
	await shot("5_cube_dragged_in")
	# Dragged onto a screen: refused.
	await drag_row(view, "cube", view._rows["left"].get_global_rect().get_center())
	print(studio.message)
	# And out again, onto the strip under the list.
	var p0: Vector2 = view._rows["cube"].get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = p0
	view._row_input(press, view._rows["cube"])
	var nudge := InputEventMouseMotion.new()
	nudge.global_position = p0 + Vector2(0, 20)
	view._row_input(nudge, view._rows["cube"])
	await frames(3)
	print("the strip shows while dragging: ", view._out_zone.visible)
	var zone: Vector2 = view._out_zone.get_global_rect().get_center()
	nudge = InputEventMouseMotion.new()
	nudge.global_position = zone
	view._row_input(nudge, view._rows["cube"])
	await shot("6_dragging_out")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.global_position = zone
	view._row_input(up, view._rows["cube"])
	await frames(4)
	print(studio.message)
	print("cube's parent: ", "'%s'" % StudioGrouping.parent_of(studio.model, "cube"))

	# Fold the group's row, then ungroup it (Ctrl+Shift+G) at 8 s.
	view.folded["group"] = true
	view.request_rebuild()
	await frames(3)
	print("folded: rows ", view._rows.keys())
	await shot("7_folded")
	view.folded.erase("group")
	studio.stage.seek_to(8.0)
	await frames(3)
	var before := places(screens)
	tools.select("group")
	studio._on_command(&"studio_ungroup")
	await frames(6)
	print(studio.message)
	print("ungrouped at 8 s, nothing moved: ", same(before, places(screens)), " ", places(screens))
	print("tree: ", StudioGrouping.tree(studio.model).map(func(r): return "%s%s" % ["  ".repeat(r.depth), r.id]))
	await shot("8_ungrouped")

	studio.undo()
	await frames(4)
	print("undo: group back ", studio.model.spawn_index("group") >= 0, ", screens where they were ", same(before, places(screens)))

	# The headset's outliner, drawn in its own panel.
	if rendered:
		studio.outliner_panel.visible = true
		var vr: StudioOutliner = null
		for i in 30:
			vr = studio._vr_outliner()
			if vr != null:
				break
			await frames(1)
		tools.select("middle")
		await frames(12)
		var sub: SubViewport = studio.outliner_panel.get_node("Viewport")
		sub.get_texture().get_image().save_png(out.path_join("studio_outliner_9_headset.png"))
		print("headset outliner: ", vr != null, ", vr layout ", vr.vr if vr != null else false)
		studio.outliner_panel.visible = false

	print("save: ", studio.save(), ", valid ", studio.model.check().ok)
	var saved := FileAccess.get_file_as_string(dir.path_join("clip.spscript"))
	print("saved file has the group: ", saved.contains("\"parent\": \"group\""))
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	quit(0)
