extends SceneTree

## The Performance tab (TODO 19) in the real Studio: a piece with a shader
## layer, a screen with Glow and a cube; the menu's Performance tab
## measures (its rows: the layer's shader, Glow, the view), a row selects
## its object, the 3D view's parts are measured (things blink), the
## benchmark plays the piece through and lists the heaviest moments, and
## the playhead comes back. Then the player's menu has the tab too.
## Prints what happened; rendered, saves studio_perf_*.png to OUT_DIR.
## Headless the GPU times are all 0 (the attribution still shows).

const GLOW := "res://player/visualizer/effects/glow.gdshader"

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
	var img := root.get_texture().get_image()
	var r := Rect2i(studio.menu_2d.get_global_rect())
	img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(out.path_join("studio_perf_%s.png" % name))


func rows(tab: Node) -> Array:
	var outr: Array = []
	for r in tab._rows:
		if r.button.visible:
			outr.append("%s [%s] %s%s" % [r.name.text, r.kind.text, r.ms.text, " (selects %s)" % r.select if not r.button.disabled else ""])
	return outr


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_perf/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.spscript"))
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
	studio.runner.set_video_duration(12.0)
	var m: EditModel = studio.model
	var layer_shader: String = m.name_shader(VisualizerShaders.builtins()[0].key)
	var glow := m.name_shader(GLOW)
	m.batch("Build the piece", func():
		m.add_object({"type": "event", "t": 0.0, "action": "spawn", "id": "tunnel",
			"prefab": m.name_prefab("res://player/prefabs/layer.tscn"),
			"transform": {"position": [-1.2, 2.0, 0.0], "scale": [0.04, 0.04, 0.04]},
			"config": {"shader": layer_shader}})
		m.add_object({"type": "event", "t": 0.0, "action": "spawn", "id": "glow_screen",
			"prefab": m.name_prefab("res://player/prefabs/screen.tscn"),
			"transform": {"position": [1.2, 2.0, 0.0], "scale": [0.04, 0.04, 0.04]},
			"config": {"effects": [{"shader": glow}]}})
		m.add_object({"type": "event", "t": 4.0, "action": "spawn", "id": "cube",
			"prefab": m.name_prefab("res://player/prefabs/cube.tscn"),
			"transform": {"position": [0.0, 1.0, 2.0]}}))
	await frames(6)
	var cost: GpuCost = studio.stage.gpu_cost
	print("before the tab: measuring %s" % cost.is_active())

	studio._on_command(&"studio_menu")
	await frames(4)
	var menu: StudioMenu = studio.menu_view()
	var titles: Array = range(menu.tabs.get_tab_count()).map(func(i): return menu.tabs.get_tab_title(i))
	print("tabs: ", titles)
	menu.tabs.current_tab = titles.find("Performance")
	await frames(40)
	var tab: Node = menu.performance_tab
	print("tab shown: measuring %s; headset copy hidden, holds it: %s" % [cost.is_active(),
			cost._holders.has("tab%d" % studio.menu.performance_tab.get_instance_id()) if studio.menu != null else "no headset menu"])
	print("header: '%s' · '%s'" % [tab._frame.text, tab._fps.text])
	print("rows: ", rows(tab))
	print("parts: ", cost.parts.keys())
	await shot("1_readout")

	# A row of a script object selects it.
	for r in tab._rows:
		if r.button.visible and r.select == "glow_screen":
			r.button.pressed.emit()
			break
	await frames(2)
	print("row pressed: selected '%s'" % studio.tools.selected)

	# The view's parts.
	var at: float = studio.runner.playhead
	cost.probe()
	var probing_started: bool = cost.probing
	while cost.probing:
		await process_frame
	print("probe ran %s: %s" % [probing_started, cost.probe_ms.values().map(func(p): return "%s %.2f ms" % [p.label, p.ms])])
	print("everything visible again: %s" % ["tunnel", "glow_screen"].all(func(id): return reg.get_node_by_id(id).visible))
	await frames(12)
	print("rows after the probe: ", rows(tab))
	await shot("2_probed")

	# The benchmark: through the piece, playhead back where it was.
	studio.runner.seek(2.5)
	tab._on_benchmark()
	while tab._bench.running:
		await process_frame
	await frames(2)
	print("benchmark: '%s'" % tab._bench_text.text)
	print("moments: ", tab._moments.get_children().map(func(l): return l.text))
	print("playhead back: %.2f (was 2.50), playing %s" % [studio.runner.playhead, studio.runner.playing])
	await shot("3_benchmark")

	studio._on_command(&"studio_menu")
	await frames(4)
	print("menu closed: measuring %s" % cost.is_active())
	print("at start %.2f" % at)

	# The player's menu has the tab too.
	studio.queue_free()
	await frames(4)
	var content: Node = load("res://player/ui/floating_panel_content.tscn").instantiate()
	root.add_child(content)
	await frames(2)
	var tabs: TabContainer = content.get_node("Tabs")
	print("player tabs: ", range(tabs.get_tab_count()).map(func(i): return tabs.get_tab_title(i)))
	print("player performance tab: %s" % (content.performance_tab != null))
	quit()
