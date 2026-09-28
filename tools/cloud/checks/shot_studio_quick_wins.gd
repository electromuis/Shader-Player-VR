extends SceneTree

## Studio's quick wins, driven in the real main scene: a new piece from a
## plain video starts with a screen (the template); keys on change set to
## Animated (the timeline's switch, the status chip, a grab that keys);
## previous / next key (Up / Down); a lane's block dragged whole; the ride
## armed (the status says what it does); FPS in the status; folded
## inspector sections listing what's inside. Prints what happened;
## rendered, saves studio_quick_wins_*.png to OUT_DIR.

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	if not rendered:
		return
	var reg: ObjectRegistry = studio.runner.registry()
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(StudioThumbnailer.test_card())
	await frames(12)
	root.get_texture().get_image().save_png(out.path_join("studio_quick_wins_%s.png" % name))


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_quick_wins/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(30.0)
	var m: EditModel = studio.model
	print("new piece: objects %s; status '%s'" % [m.object_ids(), studio.message])
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2.4, 10)
	cam.look_at(Vector3(0, 2.0, 0))
	await frames(4)
	await shot("1_new_piece")

	# Keys on main_screen: it rises from 2 s to 6 s; it goes at 20 s.
	m.set_key("transform", "main_screen", "position", 2.0, [0.0, 2.0, 0.0])
	m.set_key("transform", "main_screen", "position", 6.0, [0.0, 3.5, 0.0])
	m.add_despawn("main_screen", 20.0)
	studio.tools.select("main_screen")
	await frames(4)

	# Previous / next key.
	studio.stage.seek_to(0.0)
	studio._on_command(&"studio_next_key")
	print("next key from 0: %.2f ('%s')" % [studio.runner.playhead, studio.message])
	studio._on_command(&"studio_next_key")
	print("next again: %.2f" % studio.runner.playhead)
	studio._on_command(&"studio_prev_key")
	print("previous: %.2f" % studio.runner.playhead)
	studio._on_command(&"studio_next_key")
	studio._on_command(&"studio_next_key")
	print("past the last: %.2f ('%s')" % [studio.runner.playhead, studio.message])

	# Keys on change: Animated, then a grab-like move at 4 s keys position there.
	var ribbon: StudioTimelineRibbon = studio.ribbon
	ribbon.set_key_mode("animated")
	studio.stage.seek_to(4.0)
	await frames(3)
	var node: Node3D = reg.get_node_by_id("main_screen")
	var before := GrabMath.to_dict(node.transform)
	var after := before.duplicate(true)
	after.position = [1.5, before.position[1], before.position[2]]
	after.rotation_deg = [0.0, 20.0, 0.0]
	print("grab with keys on change Animated: '%s'" % studio.tools._commit("main_screen", before, after))
	var pos: Array = m.tracks()[m.find_track("transform", "main_screen", "position")].keyframes
	print("  position keys at %s; rotation track %d; spawn rotation %s" % [pos.map(func(k): return k.t),
			m.find_track("transform", "main_screen", "rotation_deg"), m.tracks()[m.spawn_index("main_screen")].transform.rotation_deg])

	# Arm the ride.
	studio._on_command(&"studio_arm_ride")
	await frames(6)
	print("ride armed: chip %s, help '%s'" % [studio.status_view._ride.visible, studio.status_view._ride_help.text])
	print("status fps: '%s'" % studio.status_view._fps.text)
	var summary := ""
	var ins: StudioInspector = studio.inspector
	for c in ins._list.get_children():
		if c is HBoxContainer and c.get_child_count() > 1 and c.get_child(1) is Label:
			summary += "%s: %s; " % [(c.get_child(0) as Button).text, (c.get_child(1) as Label).text]
	print("folded sections: ", summary)

	# A block mid-drag: main_screen's, 3 s later (shown, not written yet).
	ribbon._drag = {"kind": "lane_move", "id": "main_screen", "si": 0, "t": 8.0, "from": 8.0, "lo": 0.0, "hi": 30.0,
		"dt": 3.0, "x0": 0.0, "moved": true}
	studio.stage.seek_to(4.0)
	await frames(4)
	await shot("2_studio")
	ribbon._drag = {}
	print("move the block 3 s: %s; now %.2f to %s; keys %s" % [ribbon.move_lane("main_screen", 0, 3.0),
		m.tracks()[m.spawn_index("main_screen")].t,
		m.tracks().filter(func(t): return t.get("action") == "despawn").map(func(t): return t.t),
		m.tracks()[m.find_track("transform", "main_screen", "position")].keyframes.map(func(k): return k.t)])
	print("undo: '%s'" % m.undo())
	quit()
