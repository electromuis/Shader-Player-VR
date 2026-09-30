extends RefCounted

## TODO 85: what can't change the picture doesn't run. Effects at their
## `@idle` params drop out of a Screen's chain (as at mix 0); a screen at
## opacity 0 stops its passes and its mesh isn't drawn. The hints' params
## are proven to leave the picture unchanged by
## tools/cloud/checks/check_idle_effects.gd (rendered).

const BLUR := VisualizerShaders.BLUR
const GLOW := "res://player/visualizer/effects/glow.gdshader"
const CROP := "res://player/visualizer/effects/crop.gdshader"


static func _screen() -> Screen:
	var screen: Screen = load("res://player/prefabs/screen.tscn").instantiate()
	screen.notification(Node.NOTIFICATION_READY)
	screen.set_source_texture(ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8)))
	return screen


static func _effect_passes(screen: Screen, index: int) -> int:
	return screen._passes.filter(func(p): return p.effect == index).size()


static func test_idle_hint(t: TestCase) -> void:
	t.assert_true(VisualizerShaders.is_idle(BLUR, {"radius": 0.0}))
	t.assert_false(VisualizerShaders.is_idle(BLUR, {}), "the default radius blurs")
	t.assert_false(VisualizerShaders.is_idle(GLOW, {"intensity": 0.0}), "edge brighten still shows")
	t.assert_true(VisualizerShaders.is_idle(GLOW, {"intensity": 0.0, "edge_brighten": 0.0}))
	t.assert_true(VisualizerShaders.is_idle(CROP, {}), "a crop of everything")
	t.assert_false(VisualizerShaders.is_idle(CROP, {"left": 0.1}))
	t.assert_false(VisualizerShaders.is_idle(VisualizerShaders.KEY_BLACK, {}), "no hint: never idle")
	t.assert_false(VisualizerShaders.is_idle("", {}))
	var h := VisualizerShaders.parse_hints("// @idle amount <= 0.0\nuniform float amount : hint_range(0.0, 1.0) = 0.5;\n")
	t.assert_eq(h.expressions.get("idle"), "amount <= 0.0")


static func test_idle_effects_leave_the_chain(t: TestCase) -> void:
	var screen := _screen()
	screen.set_effects([{"shader": BLUR, "params": {"radius": 0.0}}, {"shader": GLOW}])
	t.assert_eq(_effect_passes(screen, 0), 0, "Blur at radius 0 runs nothing")
	t.assert_true(_effect_passes(screen, 1) > 0, "Glow runs")
	screen.set_effect_param(1, "intensity", 0.0)
	t.assert_true(_effect_passes(screen, 1) > 0, "edge brighten still on")
	screen.set_effect_param(1, "edge_brighten", 0.0)
	t.assert_true(screen._passes.is_empty(), "both idle: no chain, not even the copy")
	screen.set_effect_param(0, "radius", 0.1)
	t.assert_eq(_effect_passes(screen, 0), 6, "a slider off 0 brings it back")
	screen.set_effect_param(0, "radius", 0.0)
	screen.set_effect_param(0, "blend", "add")
	t.assert_true(_effect_passes(screen, 0) > 0, "with the add blend it still changes the picture")
	screen.free()


static func test_opacity_zero_stops_the_passes(t: TestCase) -> void:
	var screen := _screen()
	var mat := ShaderMaterial.new()
	mat.shader = VisualizerShaders.load_shader(VisualizerShaders.BUILTIN_ROOT + "shaders/light_ring.gdshader")
	screen.set_shader_material(mat)
	screen.set_effects([{"shader": BLUR}])
	var modes := func() -> Array:
		return screen._passes.map(func(p): return (p.viewport as SubViewport).render_target_update_mode)
	t.assert_eq(screen.render_viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	t.assert_true(not screen.gpu_passes().is_empty())
	screen.set_opacity(0.0)
	t.assert_eq(screen.render_viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "no artist pass")
	t.assert_true(modes.call().all(func(m): return m == SubViewport.UPDATE_DISABLED), "no effect passes")
	t.assert_eq(screen.mesh.layers, 0, "the mesh isn't drawn")
	t.assert_true(screen.mesh.visible, "but stays visible, for picking")
	t.assert_true(screen.gpu_passes().is_empty(), "nothing to measure")
	screen.set_effect_param(0, "radius", 0.2)  # rebuilds the passes
	t.assert_true(modes.call().all(func(m): return m == SubViewport.UPDATE_DISABLED), "rebuilt, still stopped")
	screen.set_opacity(0.5)
	t.assert_eq(screen.render_viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	t.assert_true(modes.call().all(func(m): return m == SubViewport.UPDATE_ALWAYS), "running again")
	t.assert_eq(screen.mesh.layers, 1)
	screen.free()
