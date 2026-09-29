extends RefCounted

## GPU cost readout (GpuCost) and the benchmark (GpuBenchmark): which pass
## is which and who it's named after, the view's split, and the heaviest
## moments. The GPU times themselves need a real renderer (0 here).


static func test_screen_passes_are_named_by_owner(tc: TestCase) -> void:
	var screen: Screen = load("res://player/prefabs/screen.tscn").instantiate()
	screen.notification(Node.NOTIFICATION_READY)
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	screen.set_source_texture(tex)
	var other: String = VisualizerShaders.builtins(true)[0].key
	screen.set_effects([{"shader": VisualizerShaders.GLOW}, {"shader": other, "mix": 0.5}])
	var passes := screen.gpu_passes()
	var effects := passes.filter(func(p): return p.part == "effect")
	tc.assert_true(effects.any(func(p): return p.effect == 0 and p.key == VisualizerShaders.GLOW), "Glow's pass")
	tc.assert_true(effects.filter(func(p): return p.effect == 1).size() >= 2, "a mixed effect's blend pass counts as it")
	tc.assert_false(passes.any(func(p): return p.part == "shader"), "no artist pass while it doesn't render")
	# Named after the script object it belongs to.
	var who := GpuCost.describe_owner(screen, {screen: "main_screen"})
	tc.assert_eq(who, {"label": "main_screen", "select": "main_screen", "layer": false})
	var keys: Dictionary = {}
	for p in passes:
		var d := GpuCost.describe_pass(who, p)
		keys[d.key] = d
	var glow: Dictionary = keys["main_screen|effect0"]
	tc.assert_eq(glow.label, "main_screen · " + VisualizerShaders.source_label(VisualizerShaders.GLOW))
	tc.assert_eq(glow.kind, "effect")
	tc.assert_eq(glow.select, "main_screen")
	tc.assert_true(keys.has("main_screen|effect1"), "one row per effect, whatever its passes")
	# Not registered: the main screen, unselectable.
	tc.assert_eq(GpuCost.describe_owner(screen, {}).select, "")
	screen.free()


static func test_layer_owner_and_other_viewports(tc: TestCase) -> void:
	var layer := Visualizer.new()
	var screen := Node3D.new()
	layer.add_child(screen)
	var who := GpuCost.describe_owner(screen, {})
	tc.assert_true(who.layer, "a player layer")
	tc.assert_true(String(who.label).begins_with("Layer · "), who.label)
	tc.assert_eq(GpuCost.describe_pass(who, {"part": "shader", "effect": -1, "key": ""}).kind, "layer · shader")
	# A script's layer goes by its id.
	var scripted := GpuCost.describe_owner(screen, {layer: "tunnel"})
	tc.assert_eq(scripted.label, "tunnel")
	tc.assert_true(scripted.layer)
	tc.assert_eq(GpuCost.describe_pass(scripted, {"part": "copy", "effect": -1, "key": ""}).label, "tunnel · picture copy")
	layer.free()
	var holder := Node.new()
	holder.name = "Thumbnailer"
	var vp := SubViewport.new()
	holder.add_child(vp)
	tc.assert_eq(GpuCost.describe_viewport(vp), {"key": "other|Thumbnailer", "label": "Thumbnailer", "kind": "other pass", "select": ""})
	holder.free()


static func test_holders_and_view_split(tc: TestCase) -> void:
	var cost := GpuCost.new()
	tc.assert_false(cost.is_active())
	cost.set_active("tab", true)
	cost.set_active("benchmark", true)
	cost.set_active("tab", false)
	tc.assert_true(cost.is_active(), "the benchmark still holds it")
	cost.set_active("benchmark", false)
	tc.assert_false(cost.is_active())
	cost.smoothed = {"a|shader": 3.0, "view": 5.0, "video": 0.5}
	cost.parts = {"a|shader": {"label": "a", "kind": "layer · shader", "select": "a"},
			"video": {"label": "video frame", "kind": "video", "select": ""}}
	var ranked := cost.ranked()
	tc.assert_eq(ranked.map(func(r): return r.key), ["view", "a|shader", "video"])
	tc.assert_eq(ranked[0].label, "3D view")
	cost.probe_ms = {"probe|cube": {"label": "cube", "kind": "object", "select": "cube", "ms": 4.0}}
	ranked = cost.ranked()
	tc.assert_eq(ranked.map(func(r): return r.key), ["probe|cube", "a|shader", "view", "video"])
	tc.assert_eq(ranked[2].ms, 1.0, "the view's rest")
	tc.assert_eq(ranked[2].label, "the rest of the view")
	cost.free()


static func test_budget(tc: TestCase) -> void:
	var cost := GpuCost.new()
	tc.assert_true(cost.refresh_hz() > 0.0)
	tc.assert_true(is_equal_approx(cost.budget_ms(), 1000.0 / cost.refresh_hz()))
	cost.free()


static func test_heaviest_moments(tc: TestCase) -> void:
	var labels := {"t|shader": {"label": "tunnel"}, "s|effect0": {"label": "main_screen · Glow"}}
	var samples: Array = []
	var ms := [8.0, 9.0, 15.0, 16.0, 14.5, 9.0, 20.0, 9.0, 8.0]
	for i in ms.size():
		samples.append({"t": 60.0 + i, "ms": ms[i], "parts": {"t|shader": ms[i] * 0.5, "s|effect0": 2.0, "view": 1.0}})
	var moments := GpuBenchmark.heaviest(samples, 13.9, labels)
	tc.assert_eq(moments.size(), 2, "two runs over budget")
	tc.assert_eq(moments[0].from, 66.0, "the heaviest peak first")
	tc.assert_eq(moments[0].to, 66.0)
	tc.assert_eq(moments[1].from, 62.0)
	tc.assert_eq(moments[1].to, 64.0, "a run merged")
	tc.assert_eq(moments[1].peak_ms, 16.0)
	tc.assert_eq(moments[1].names, ["tunnel", "main_screen · Glow"] as Array[String])
	tc.assert_eq(GpuBenchmark.describe(moments[1]), "1:02–1:04 (tunnel + main_screen · Glow) 16.0 ms · over budget")
	# Nothing over: the few heaviest steps.
	moments = GpuBenchmark.heaviest(samples, 30.0, labels)
	tc.assert_eq(moments.size(), GpuBenchmark.TOP)
	tc.assert_eq(moments.map(func(m): return m.peak_ms), [20.0, 16.0, 15.0])
	tc.assert_false(moments[0].over)
	tc.assert_eq(GpuBenchmark.describe(moments[0]), "1:06 (tunnel + main_screen · Glow) 20.0 ms")
	# The view is named as such.
	var one := [{"t": 0.0, "ms": 5.0, "parts": {"view": 4.0, "gone|shader": 1.0}}]
	tc.assert_eq(GpuBenchmark.heaviest(one, 13.9, {})[0].names, ["3D view", "gone|shader"] as Array[String])
	tc.assert_eq(GpuBenchmark.heaviest([], 13.9).size(), 0)
