extends SceneTree

## Studio's panels (TODO 9, 10, 75, 76), in the real Studio: – folds a panel
## to its title bar in place and unfolds it again, ✕ hides it to a tab (the
## desktop's in the status) and the tabs bring it back; dragging a title bar
## moves a desktop panel and an edge sizes it (through the window's input),
## the places are saved and a new Studio puts them back; in the headset the
## laser moves a panel by its title bar and sizes it by its corner, a moved
## panel comes back at the same place relative to you, – folds the panel's
## quad to its title bar keeping its top edge, and flying and turning the rig
## carries the panels along. Prints what happened; rendered, saves
## studio_panels_*.png to OUT_DIR (run it at 1920x1080).

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"
var dir := OS.get_environment("WORK").path_join("studio_panels/piece")


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


func rect(c: Control) -> String:
	var r := c.get_global_rect()
	return "(%d, %d) %d × %d" % [r.position.x, r.position.y, r.size.x, r.size.y]


## A press at `from`, the mouse moving to `to` in a few steps with the
## button down, and a let-go there: window pixels, through the window's own
## input (the real cursor goes along, so a stray motion doesn't interfere).
func mouse_drag(from: Vector2, to: Vector2) -> void:
	Input.warp_mouse(from)
	var mv := InputEventMouseMotion.new()
	mv.position = from
	mv.global_position = from
	root.push_input(mv)
	await frames(1)
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.position = from
	b.global_position = from
	b.pressed = true
	b.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(b)
	await frames(1)
	var last := from
	for i in range(1, 6):
		var at := from.lerp(to, i / 5.0)
		Input.warp_mouse(at)
		var m := InputEventMouseMotion.new()
		m.position = at
		m.global_position = at
		m.relative = at - last
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(m)
		last = at
		await frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = to
	up.global_position = to
	up.pressed = false
	root.push_input(up)
	await frames(2)


func open_studio() -> void:
	studio = load("res://studio/studio.tscn").instantiate()
	studio._cli_desktop = true
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.tools.select("main_screen")
	if not studio.shelf_on:
		studio._on_command(&"studio_toggle_shelf")
	await frames(4)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	# Start from Studio's own layout (an earlier run saved places).
	var fresh := StudioSettings.new()
	fresh.load_from_disk()
	fresh.reset("panels")
	await open_studio()
	print("open: ", state())
	print("  inspector %s, timeline %s, shelf %s" % [rect(studio.inspector), rect(studio.ribbon), rect(studio.shelf)])
	await shot("1_open")

	# – folds each to its title bar where it is; again unfolds it.
	studio.inspector.minimize_requested.emit()
	studio.ribbon.minimize_requested.emit()
	studio.shelf.minimize_requested.emit()
	await frames(4)
	print("– on all three: ", state())
	print("  inspector %s, timeline %s, shelf %s; buttons '%s'" % [rect(studio.inspector), rect(studio.ribbon), rect(studio.shelf),
			studio.inspector.frame.fold_button.text])
	await shot("2_folded")
	for view in [studio.inspector, studio.ribbon, studio.shelf]:
		view.minimize_requested.emit()
	await frames(4)
	print("□ unfolds: inspector %s, timeline %s, shelf %s" % [rect(studio.inspector), rect(studio.ribbon), rect(studio.shelf)])

	# ✕ hides each to a tab; the tabs bring them back.
	studio.inspector.close_requested.emit()
	studio.ribbon.close_requested.emit()
	studio.shelf.close_requested.emit()
	await frames(3)
	print("✕ on all three: ", state())
	await shot("3_hidden")
	for id in [&"studio_toggle_inspector", &"studio_toggle_timeline", &"studio_toggle_shelf"]:
		studio.status_view._tabs[id].pressed.emit()
	await frames(3)
	print("the tabs: ", state())

	# Moving and sizing with the mouse.
	var title: Control = studio.inspector._title
	var from := title.get_global_rect().get_center() - Vector2(40, 0)
	await mouse_drag(from, from + Vector2(-500, 120))
	print("inspector's title dragged (-500, 120): ", rect(studio.inspector))
	var sr: Rect2 = studio.shelf.get_global_rect()
	await mouse_drag(Vector2(sr.end.x - 3, sr.get_center().y), Vector2(sr.end.x + 197, sr.get_center().y))
	print("shelf's right edge dragged 200: ", rect(studio.shelf))
	var tr: Rect2 = studio.ribbon.get_global_rect()
	await mouse_drag(Vector2(tr.get_center().x, tr.position.y + 3), Vector2(tr.get_center().x, tr.position.y - 97))
	print("timeline's top edge dragged up 100: ", rect(studio.ribbon))
	var ir: Rect2 = studio.inspector.get_global_rect()
	await mouse_drag(Vector2(ir.position.x + 3, ir.position.y + 3), Vector2(ir.position.x - 3000, ir.position.y - 3000))
	print("inspector's top left corner dragged off the window: ", rect(studio.inspector), " (window ", root.get_visible_rect().size, ")")
	var big: Rect2 = studio.inspector.get_global_rect()
	await mouse_drag(big.position + Vector2(3, 3), ir.position + Vector2(3, 3))
	print("  and back: ", rect(studio.inspector))
	var mid := root.get_visible_rect().size * 0.5 + Vector2(0, -150)
	await mouse_drag(mid, mid + Vector2(50, 50))
	print("a drag over the 3D view moves no panel: inspector ", rect(studio.inspector))
	studio.inspector.minimize_requested.emit()
	await frames(3)
	var folded: Vector2 = studio.inspector._title.get_global_rect().get_center() - Vector2(40, 0)
	await mouse_drag(folded, folded + Vector2(0, 40))
	print("folded inspector dragged down 40: ", rect(studio.inspector))
	studio.inspector.minimize_requested.emit()
	await frames(3)
	print("unfolded there: ", rect(studio.inspector))
	await shot("4_moved")
	# The menu folds and moves too.
	studio.toggle_menu()
	await frames(3)
	print("menu: ", rect(studio.menu_2d))
	studio.menu_2d.minimize_requested.emit()
	await frames(3)
	print("menu –: ", rect(studio.menu_2d))
	var mt: Vector2 = studio.menu_2d.frame.header.get_global_rect().position + Vector2(60, 20)
	await mouse_drag(mt, mt + Vector2(300, -200))
	print("menu dragged (300, -200): ", rect(studio.menu_2d))
	await shot("4b_menu_folded")
	studio.menu_2d.minimize_requested.emit()
	await frames(3)
	print("menu □: ", rect(studio.menu_2d))
	studio.toggle_menu()
	var saved := StudioSettings.new()
	saved.load_from_disk()
	print("saved: ", JSON.stringify(saved.panels))

	# A new Studio puts them back.
	var places := [rect(studio.inspector), rect(studio.ribbon), rect(studio.shelf)]
	studio.queue_free()
	await frames(4)
	await open_studio()
	var again := [rect(studio.inspector), rect(studio.ribbon), rect(studio.shelf)]
	print("a new Studio: ", again, " same ", again == places)
	await shot("5_new_studio")
	# The Studio tab's ↺ puts them back where Studio puts them.
	studio.menu_2d.studio_tab._resets["panels"].pressed.emit()
	await frames(3)
	print("↺ Panel places: inspector %s, timeline %s, shelf %s; saved %s" % [rect(studio.inspector), rect(studio.ribbon),
			rect(studio.shelf), JSON.stringify(studio.studio_settings.panels)])

	# The headset panels.
	var panels := {"inspector": studio.inspector_panel, "timeline": studio.ribbon_panel, "shelf": studio.shelf_panel}
	for p in panels.values():
		p.visible = true
	studio._place_inspector_panel()
	studio._place_ribbon_panel()
	studio._place_shelf_panel()
	await frames(8)
	var views := {"inspector": studio._vr_inspector(), "timeline": studio._vr_ribbon(), "shelf": studio._vr_shelf()}
	var cam: Camera3D = studio.stage.desktop_camera
	var hand: XRController3D = studio.stage.xr_rig.right_controller
	var node: XRToolsViewport2DIn3D = panels.inspector
	# The laser on the inspector's title bar: move it 0.4 m to the left.
	var grab := node.global_transform * Vector3(0.05, node.screen_size.y * 0.5 - 0.03, 0)
	var eye := cam.global_position + Vector3(0.15, -0.3, 0)
	hand.global_transform = Transform3D(Basis.looking_at(grab - eye, Vector3.UP), eye)
	views.inspector.frame.move_started.emit()
	var aim := grab - cam.global_basis.x * 0.4
	hand.global_transform = Transform3D(Basis.looking_at(aim - eye, Vector3.UP), eye)
	studio.drag_vr_panel_to(hand.global_transform)
	var held := node.global_transform * Vector3(0.05, node.screen_size.y * 0.5 - 0.03, 0)
	print("headset: the inspector's title held by the laser: the held point %.3f m from the laser's end, moved %.3f m, faces you within %.1f°" % [
			held.distance_to(eye + (aim - eye).normalized() * eye.distance_to(grab)), held.distance_to(grab),
			rad_to_deg(node.global_basis.z.angle_to(cam.global_position - node.global_position))])
	views.inspector.frame.drag_ended.emit()
	print("  saved at ", studio.studio_settings.panel_value("inspector", "vr_at"))
	# Its bottom right corner: 0.15 m wider, 0.1 m taller.
	var corner := node.global_transform * Vector3(node.screen_size.x * 0.5 - 0.01, -node.screen_size.y * 0.5 + 0.01, 0)
	hand.global_transform = Transform3D(Basis.looking_at(corner - eye, Vector3.UP), eye)
	var size_was: Vector2 = node.viewport_size
	var top_left_was := node.global_transform * Vector3(-node.screen_size.x * 0.5, node.screen_size.y * 0.5, 0)
	views.inspector.frame.resize_started.emit(StudioPanelFrame.RIGHT | StudioPanelFrame.BOTTOM)
	var to := corner + node.global_basis.x * 0.15 - node.global_basis.y * 0.1
	hand.global_transform = Transform3D(Basis.looking_at(to - eye, Vector3.UP), eye)
	studio.drag_vr_panel_to(hand.global_transform)
	views.inspector.frame.drag_ended.emit()
	var top_left := node.global_transform * Vector3(-node.screen_size.x * 0.5, node.screen_size.y * 0.5, 0)
	print("headset: the inspector's corner pulled: %s px -> %s px (%.3f × %.3f m), its top left corner moved %.4f m; saved %s" % [
			size_was, node.viewport_size, node.screen_size.x, node.screen_size.y, top_left.distance_to(top_left_was),
			studio.studio_settings.panel_value("inspector", "vr_size")])
	# Turn away and back: placed again, it's where it was put, relative to you.
	var rel := cam.global_transform.affine_inverse() * node.global_transform
	cam.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(70.0)), Vector3(2.0, 0.0, 1.0)) * cam.global_transform
	studio._place_inspector_panel()
	var rel2 := cam.global_transform.affine_inverse() * node.global_transform
	print("headset: turned 70° and placed again: off by %.4f m from where it was put" % rel.origin.distance_to(rel2.origin))
	# – folds the quad to its title bar, its top edge staying.
	var top_was := node.global_transform * Vector3(0, node.screen_size.y * 0.5, 0)
	views.inspector.minimize_requested.emit()
	await frames(3)
	var top_now := node.global_transform * Vector3(0, node.screen_size.y * 0.5, 0)
	print("headset inspector –: %s px, title bar %.0f px, top edge moved %.4f m" % [node.viewport_size,
			views.inspector.frame.title_height(), top_now.distance_to(top_was)])
	views.inspector.minimize_requested.emit()
	await frames(3)
	print("headset inspector □: %s px" % node.viewport_size)
	views.timeline.minimize_requested.emit()
	await frames(8)
	if rendered:
		for p in panels.values():
			(p.get_node("Viewport") as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await frames(8)
		for name in panels:
			(panels[name].get_node("Viewport") as SubViewport).get_texture().get_image().save_png(
					out.path_join("studio_panels_6_headset_%s.png" % name))
	views.timeline.minimize_requested.emit()
	await frames(3)

	# Riding on the rig: fly 6 m and snap-turn 30°; the panels keep their
	# place relative to you. (The desktop camera stands in for the head.)
	var rig: XROrigin3D = studio.stage.xr_rig
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

	# ✕ in the headset hides a panel to its wrist button.
	var vr_names := {"inspector": &"studio_toggle_inspector", "timeline": &"studio_toggle_timeline", "shelf": &"studio_toggle_shelf"}
	for name in views:
		views[name].close_requested.emit()
		await frames(3)
		print("headset ", name, " ✕: hidden ", vr_names[name] in studio.folded_panels(), ", panel visible ", panels[name].visible)
	studio.studio_settings.reset("panels")
	quit(0)
