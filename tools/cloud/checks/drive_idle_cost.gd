extends SceneTree

## TODO 85: things at their "off" settings cost no GPU. Real Studio, a
## piece with a shader layer running Blur and Glow (its chain renders every
## frame, after the layer's shader) and a 3D (mainVR) layer, which draws in
## the 3D view. Measured with GpuCost (the Performance tab's numbers) in
## each state: everything on; Blur's radius and Glow's intensity and edge
## brighten at 0; the 3D layer, then the other, at opacity 0; the effects
## at mix 0 / switched off; the layer hidden; Blur at radius 0 with the add
## blend (that one must still run); and back on in between. Prints, per
## state, how many SubViewports render, and the GPU time per part averaged
## over PARTS_FRAMES. Rendered for real GPU numbers (headless they're all
## 0; the pass counts still show), and shots of the Performance tab in
## states 1, 4 and 6 (idle_cost_*.png in OUT_DIR).

const BLUR := "res://player/visualizer/effects/blur.gdshader"
const GLOW := "res://player/visualizer/effects/glow.gdshader"
const FLAT := "res://player/visualizer/shaders/light_ring.gdshader"
const VR := "res://player/visualizer/shaders/gyroid_tunnel.gdshader"

const PARTS_FRAMES := 120

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func running_passes() -> int:
	var n := 0
	for vp in studio.stage.find_children("*", "SubViewport", true, false):
		if (vp as SubViewport).render_target_update_mode != SubViewport.UPDATE_DISABLED:
			n += 1
	return n


## Settle, then average every part's time over PARTS_FRAMES (the menus left
## out: the check has none open).
func report(state: String) -> void:
	await frames(30)
	var cost: GpuCost = studio.stage.gpu_cost
	var sums: Dictionary = {}
	for i in PARTS_FRAMES:
		await cost.measured
		for k in cost.frame_parts:
			if k != "menus":
				sums[k] = float(sums.get(k, 0.0)) + cost.frame_parts[k]
	var total := 0.0
	for k in sums:
		sums[k] /= PARTS_FRAMES
		total += sums[k]
	var keys := sums.keys()
	keys.sort_custom(func(a, b): return sums[a] > sums[b])
	print("== %s: %d passes rendering, GPU %.3f ms" % [state, running_passes(), total])
	for k in keys:
		var label: String = "3D view" if k == GpuCost.VIEW else cost.parts.get(k, {"label": k}).label
		print("     %-30s %.3f ms" % [label, sums[k]])


func shot(name: String) -> void:
	if not rendered:
		return
	var img := root.get_texture().get_image()
	var r := Rect2i(studio.menu_2d.get_global_rect())
	img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(out.path_join("idle_cost_%s.png" % name))


func node(id: String) -> Node:
	return studio.runner.registry().get_node_by_id(id)


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("idle_cost/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.spscript"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	studio._cli_desktop = true
	root.add_child(studio)
	await frames(10)
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(12.0)
	var m: EditModel = studio.model
	var blur := m.name_shader(BLUR)
	var glow := m.name_shader(GLOW)
	m.batch("Build the piece", func():
		m.add_object({"type": "event", "t": 0.0, "action": "spawn", "id": "fx_layer",
			"prefab": m.name_prefab("res://player/prefabs/layer.tscn"),
			"transform": {"position": [-1.2, 2.0, 0.0], "scale": [0.04, 0.04, 0.04]},
			"config": {"shader": m.name_shader(FLAT), "effects": [{"shader": blur}, {"shader": glow}]}})
		m.add_object({"type": "event", "t": 0.0, "action": "spawn", "id": "vr_layer",
			"prefab": m.name_prefab("res://player/prefabs/layer.tscn"),
			"transform": {"position": [0.0, 2.0, -3.0], "scale": [0.2, 0.2, 0.2]},
			"config": {"shader": m.name_shader(VR)}}))
	await frames(10)
	var cost: GpuCost = studio.stage.gpu_cost
	cost.set_active("check", true)
	studio._on_command(&"studio_menu")
	await frames(4)
	var menu: StudioMenu = studio.menu_view()
	var titles: Array = range(menu.tabs.get_tab_count()).map(func(i): return menu.tabs.get_tab_title(i))
	menu.tabs.current_tab = titles.find("Performance")
	var fx: Node = node("fx_layer")
	var vr: Node = node("vr_layer")
	await report("1. everything on")
	await shot("1_on")

	fx.set_material_param("effect0", "radius", 0.0)
	fx.set_material_param("effect1", "intensity", 0.0)
	fx.set_material_param("effect1", "edge_brighten", 0.0)
	await report("2. Blur radius 0, Glow intensity and edge brighten 0")
	vr.set_material_param("display", "opacity", 0.0)
	await report("3. and the 3D layer at opacity 0")
	fx.set_material_param("display", "opacity", 0.0)
	await report("4. and the shader layer at opacity 0")
	await shot("4_idle")

	fx.set_material_param("effect0", "radius", 0.12)
	fx.set_material_param("effect1", "intensity", 1.6)
	fx.set_material_param("effect1", "edge_brighten", 0.3)
	for n in [fx, vr]:
		n.set_material_param("display", "opacity", 1.0)
	await report("5. back on")

	fx.set_material_param("effect0", "mix", 0.0)
	fx.set_material_param("effect1", "enabled", 0.0)
	await report("6. Blur at mix 0, Glow switched off")
	await shot("6_mix0")
	fx.set_material_param("effect0", "mix", 1.0)
	fx.set_material_param("effect1", "enabled", 1.0)
	fx.visible = false
	vr.visible = false
	await report("7. both layers hidden")

	fx.visible = true
	vr.visible = true
	fx.set_material_param("effect0", "blend", "add")
	fx.set_material_param("effect0", "radius", 0.0)
	await report("8. Blur at radius 0 with the add blend (must still run: it adds the picture)")
	fx.set_material_param("effect0", "blend", "normal")
	fx.set_material_param("effect0", "radius", 0.12)
	await report("9. back on")
	cost.set_active("check", false)
	quit()
