extends SceneTree

## Folding panels (TODO 9) and the headset panels riding on the rig, in the
## real Studio: – on the inspector, the timeline and the shelf folds each to
## a tab (the desktop's in the status), the tabs bring them back; the
## headset panels' – does the same; flying and turning the rig carries the
## headset panels along. Prints what happened; rendered, saves
## studio_panels_*.png to OUT_DIR (run it at 1920x1080).

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	if not rendered:
		return
	await frames(6)
	root.get_texture().get_image().save_png(out.path_join("studio_panels_%s.png" % name))


func state() -> String:
	var tabs: Array = []
	for id in studio.status_view._tabs:
		if studio.status_view._tabs[id].visible:
			tabs.append(studio.status_view._tabs[id].text)
	return "inspector %s, timeline %s, shelf %s; tabs %s; '%s'" % [studio.inspector.visible, studio.ribbon.visible,
			studio.shelf.visible, tabs, studio.message]


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_panels/piece")
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
	studio.tools.select("main_screen")
	studio.shelf_on = true
	studio._show_shelf()
	await frames(4)
	print("open: ", state())
	await shot("1_open")

	# – on each desktop panel.
	studio.inspector.minimize_requested.emit()
	await frames(3)
	print("inspector –: ", state())
	studio.ribbon.minimize_requested.emit()
	await frames(3)
	print("timeline –: ", state())
	studio.shelf.close_requested.emit()
	await frames(3)
	print("shelf –: ", state())
	await shot("2_folded")

	# The tabs bring them back.
	studio.status_view._tabs[&"studio_toggle_timeline"].pressed.emit()
	await frames(3)
	print("timeline tab: ", state())
	await shot("3_timeline_back")
	studio.status_view._tabs[&"studio_toggle_inspector"].pressed.emit()
	studio.status_view._tabs[&"studio_toggle_shelf"].pressed.emit()
	await frames(3)
	print("inspector and shelf tabs: ", state())

	# The headset panels: their – folds them too.
	var panels := {"inspector": studio.inspector_panel, "timeline": studio.ribbon_panel, "shelf": studio.shelf_panel}
	for p in panels.values():
		p.visible = true
	studio._place_inspector_panel()
	studio._place_ribbon_panel()
	studio._place_shelf_panel()
	await frames(8)
	var views := {"inspector": studio._vr_inspector(), "timeline": studio._vr_ribbon(), "shelf": studio._vr_shelf()}
	if rendered:
		for p in panels.values():
			(p.get_node("Viewport") as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await frames(8)
		for name in panels:
			(panels[name].get_node("Viewport") as SubViewport).get_texture().get_image().save_png(
					out.path_join("studio_panels_4_headset_%s.png" % name))

	# Riding on the rig: fly 6 m and snap-turn 30°; the panels keep their
	# place relative to you. (The desktop camera stands in for the head.)
	var rig: XROrigin3D = studio.stage.xr_rig
	var cam: Camera3D = studio.stage.desktop_camera
	var before := {}
	var was := {}
	for name in panels:
		before[name] = cam.global_transform.affine_inverse() * panels[name].global_transform
		was[name] = panels[name].global_position
	var move := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(6.0, 0.0, -4.0))
	rig.global_transform = move * rig.global_transform
	cam.global_transform = move * cam.global_transform
	await frames(3)
	for name in panels:
		var now: Transform3D = cam.global_transform.affine_inverse() * panels[name].global_transform
		print("flew and turned 30°: %s moved %.2f m, its place relative to you off by %.4f m, %.3f° turned" % [name,
				was[name].distance_to(panels[name].global_position), now.origin.distance_to(before[name].origin),
				rad_to_deg(now.basis.get_rotation_quaternion().angle_to(before[name].basis.get_rotation_quaternion()))])

	var vr_names := {"inspector": &"studio_toggle_inspector", "timeline": &"studio_toggle_timeline", "shelf": &"studio_toggle_shelf"}
	for name in views:
		if views[name] == null:
			print("headset ", name, ": no view")
			continue
		if name == "shelf":
			views[name].close_requested.emit()
		else:
			views[name].minimize_requested.emit()
		await frames(3)
		print("headset ", name, " –: folded ", vr_names[name] in studio.folded_panels(), ", panel visible ", panels[name].visible)
	quit(0)
