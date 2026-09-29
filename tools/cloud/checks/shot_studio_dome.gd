extends SceneTree

## A screen on the Dome in Studio (TODO 65): around the viewer (the
## screen's distance, then Radius 40 m) and at infinity, from the seat and
## from further off, with a block 120 m away that the dome at infinity must
## not cover. Prints the surface and the display material's inputs;
## rendered, saves studio_dome_*.png to OUT_DIR.

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	var screen: Screen = studio.runner.registry().get_node_by_id("main_screen")
	var m := screen.get_display_material()
	print("%s: placement %s, viewer_distance %.2f, radius %s, camera %s" % [name,
			m.get_shader_parameter("placement"), m.get_shader_parameter("viewer_distance"),
			m.get_shader_parameter(ScreenGeometry.SURFACE_PREFIX + "radius"),
			studio.stage.desktop_camera.global_position])
	if not rendered:
		return
	studio.get_node("UI").visible = false
	screen.set_source_texture(StudioThumbnailer.test_card())
	await frames(8)
	root.get_texture().get_image().save_png(out.path_join("studio_dome_%s.png" % name))


func field(edits: StudioConfigEdits, param: String) -> Dictionary:
	for f in edits.surface_section("main_screen").fields:
		if String(f.get("param", "")) == param:
			return f
	return {}


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_dome/piece")
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
	# A tall orange block far off, straight ahead of the seat.
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(20, 40, 20)
	block.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	block.material_override = mat
	block.position = Vector3(-30, 20, -120)
	studio.add_child(block)

	var edits: StudioConfigEdits = studio.edits
	studio.tools.select("main_screen")
	print("dome: '%s'" % edits.set_surface_shader("main_screen", ScreenGeometry.DOME))
	var surface: Dictionary = edits.surface_section("main_screen")
	print("around: fields ", surface.fields.map(func(x): return x.param))
	studio.stage.desktop_camera.set_view(Vector3(0, 1.7, 8), Vector3(-5, 0, 0))
	await shot("1_around_seat")
	studio.stage.desktop_camera.set_view(Vector3(6, 5, 20), Vector3(-15, 20, 0))
	await shot("2_around_off")
	var radius := field(edits, "radius")
	print("radius 40: '%s'" % edits.commit("main_screen", radius, 40.0, 0.0, false))
	await frames(2)
	await shot("3_around_radius40_off")
	studio.stage.desktop_camera.set_view(Vector3(10, 30, 110), Vector3(-12, 5, 0))
	await shot("4_around_radius40_outside")

	print("infinity: '%s'" % edits.set_surface_placement("main_screen", "infinity"))
	print("infinity: fields ", edits.surface_section("main_screen").fields.map(func(x): return x.param))
	studio.stage.desktop_camera.set_view(Vector3(0, 1.7, 8), Vector3(-5, 0, 0))
	await shot("5_infinity_seat")
	studio.stage.desktop_camera.set_view(Vector3(6, 5, 20), Vector3(-15, 20, 0))
	await shot("6_infinity_off")
	studio.stage.desktop_camera.set_view(Vector3(0, 1.7, 8), Vector3(-5, 180, 0))
	await shot("7_infinity_back")
	print("saved: ", edits.surface_of("main_screen"))
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	quit(0)
