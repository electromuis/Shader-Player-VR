extends RefCounted

## Studio's inspector, the to-do's second pass: vertex effects (the same
## undoable stack as pixel effects, on `<id>.vertex<N>`, built-ins by name),
## the master switches, the Surface section (an earlier piece's curvature
## shown as its Pillow and turned into one on the first change, the surface
## and placement pickers), the header's line, and Spin / Pulse, the vertex
## effects that replace Reactive.

const GLOW := "res://player/visualizer/effects/glow.gdshader"

const DOC := {
	"format_version": 2,
	"media": {"video": "clip.mp4", "duration": 30.0},
	"prefabs": {"screen": "res://player/prefabs/screen.tscn", "cube": "res://player/prefabs/cube.tscn",
		"group": "res://player/prefabs/group.tscn"},
	"shaders": {"glow": GLOW},
	"tracks": [
		{"type": "event", "t": 0, "action": "spawn", "id": "scr", "prefab": "screen",
			"config": {"curvature": 0.3, "vertical_curvature": 0.1, "effects": [{"shader": "glow"}]}},
		{"type": "event", "t": 10, "action": "despawn", "target": "scr"},
		{"type": "event", "t": 20, "action": "spawn", "id": "scr", "prefab": "screen",
			"config": {"curvature": 0.3, "vertical_curvature": 0.1, "effects": [{"shader": "glow"}]}},
		{"type": "event", "t": 0, "action": "spawn", "id": "grp", "prefab": "group"},
		{"type": "event", "t": 2, "action": "spawn", "id": "box", "prefab": "cube", "parent": "grp"},
		{"type": "event", "t": 8, "action": "despawn", "target": "box"},
	],
}


static func _edits(tc: TestCase) -> StudioConfigEdits:
	var r := EditModel.from_text(JSON.stringify(DOC), "")
	tc.assert_ok(r, "document loads")
	var e := StudioConfigEdits.new()
	e.model = r.get("model")
	return e


static func _field(sections: Array, key: String) -> Dictionary:
	for s in sections:
		for f in s.fields:
			if f.key == key:
				return f
	return {}


static func _valid(tc: TestCase, m: EditModel, msg: String) -> void:
	tc.assert_ok(ScriptFormat.load_from_dict(JSON.parse_string(m.to_text()), "<test>"), msg)


static func test_vertex_effects_stack(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var v := EditModel.VERTEX_EFFECTS
	var options: Array = e.effect_options(v).map(func(o): return o.label)
	for name in ["Ripple", "Twist", "Bulge", "Spin", "Pulse"]:
		tc.assert_true(name in options, "%s is offered" % name)
	tc.assert_true(e.add_effect("scr", ScreenGeometry.RIPPLE, v))
	tc.assert_true(e.add_effect("scr", ScreenGeometry.TWIST, v))
	tc.assert_eq(m.effects_of("scr", v).map(func(x): return x.shader), ["ripple", "twist"], "built-ins by name")
	tc.assert_false(m.document().shaders.has("ripple"), "no shaders entry for a built-in")
	tc.assert_eq(m.effects_of("scr", v), m.tracks()[m.spawn_indices("scr")[1]].config.vertex_effects, "both spawns")
	tc.assert_eq(m.effects_of("scr").size(), 1, "the pixel effects stay")
	var s := e.sections("scr", null, "screen")
	var vx: Array = s.filter(func(x): return x.kind == "effect" and x.list == v)
	tc.assert_eq(vx.map(func(x): return x.title), ["Ripple", "Twist"])
	var angle := _field(s, "vertex1/angle")
	tc.assert_eq(angle.slot, "vertex1")
	tc.assert_eq(angle.config, ["vertex_effects", 1, "params", "angle"])
	tc.assert_eq(e.value_of("scr", angle, 0.0), 30.0, "the snippet's default")
	# Keyed, then ripple switched off: twist's track follows it to vertex0.
	tc.assert_eq(e.commit("scr", angle, 45.0, 3.0, true), "Key scr angle at 0:03.00")
	tc.assert_true(m.find_track("shader_param", "scr.vertex1", "angle") >= 0)
	tc.assert_true(m.set_effect_enabled("scr", 0, false, v))
	tc.assert_true(m.find_track("shader_param", "scr.vertex0", "angle") >= 0, "renumbered")
	tc.assert_eq(_field(e.sections("scr", null, "screen"), "vertex1/angle").slot, "vertex0")
	# Moved and removed.
	tc.assert_true(m.move_effect("scr", 1, 0, v))
	tc.assert_eq(m.effects_of("scr", v).map(func(x): return x.shader), ["twist", "ripple"])
	tc.assert_true(m.remove_effect("scr", 0, v))
	tc.assert_eq(m.find_track("shader_param", "scr.vertex0", "angle"), -1, "its tracks went with it")
	tc.assert_eq(m.effects_of("scr", v).size(), 1)
	_valid(tc, m, "valid")


static func test_master_switch(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var v := EditModel.VERTEX_EFFECTS
	e.add_effect("scr", ScreenGeometry.RIPPLE, v)
	e.add_effect("scr", ScreenGeometry.BULGE, v)
	m.set_effect_enabled("scr", 1, false, v)
	var before := m.to_text()
	tc.assert_true(m.set_all_effects_enabled("scr", false, v))
	tc.assert_eq(m.undo_label(), "Turn scr's vertex effects off")
	tc.assert_true(m.effects_of("scr", v).all(func(x): return x.get("enabled", true) == false))
	tc.assert_false(m.set_all_effects_enabled("scr", false, v), "already off")
	tc.assert_true(m.set_all_effects_enabled("scr", true, v))
	tc.assert_true(m.effects_of("scr", v).all(func(x): return not x.has("enabled")), "all on")
	m.undo()
	m.undo()
	tc.assert_eq(m.to_text(), before, "one step each")
	tc.assert_true(m.set_all_effects_enabled("scr", false))
	tc.assert_eq(m.effects_of("scr")[0].enabled, false, "pixel effects too")


static func test_surface_replaces_curvature(tc: TestCase) -> void:
	var e := _edits(tc)
	var m := e.model
	var before := m.to_text()
	var surface: Dictionary = e.sections("scr", null, "screen")[1]
	tc.assert_eq(surface.kind, "surface")
	tc.assert_eq(surface.label, "Pillow")
	tc.assert_eq(surface.placement, "fixed")
	var arc_y := _field([surface], "shape/arc_y")
	tc.assert_eq(e.value_of("scr", arc_y, 0.0), 18.0, "vertical curvature 0.1 → 18°")
	# The first change writes the surface as it plays, without the curvature.
	tc.assert_eq(e.commit("scr", arc_y, 40.0, 0.0, false), "Set scr arc y")
	for i in m.spawn_indices("scr"):
		var cfg: Dictionary = m.tracks()[i].config
		tc.assert_eq(cfg.surface, {"shader": "pillow", "params": {"arc_x": 54.0, "arc_y": 40.0}, "placement": "fixed"})
		tc.assert_false(cfg.has("curvature") or cfg.has("vertical_curvature"), "the curvature is gone")
	m.undo()
	tc.assert_eq(m.to_text(), before, "one step")
	# The picker: a dome sits around the viewer, and can go to infinity.
	tc.assert_eq(e.set_surface_shader("scr", ScreenGeometry.DOME), "Set scr's surface to Dome")
	tc.assert_eq(m.config_of("scr").surface, {"shader": "dome", "params": {}, "placement": "around"})
	tc.assert_eq(e.set_surface_shader("scr", ScreenGeometry.DOME), "", "already")
	tc.assert_eq(e.set_surface_placement("scr", "infinity"), "Place scr's surface at infinity")
	tc.assert_eq(e.set_surface_placement("scr", "nowhere"), "", "not a placement")
	var dome: Dictionary = e.sections("scr", null, "screen")[1]
	tc.assert_eq(dome.placements, ScreenGeometry.placements_for(ScreenGeometry.DOME))
	var unused: Array = ScreenGeometry.hints_for(ScreenGeometry.DOME).unused.get("infinity", [])
	for f in dome.fields:
		tc.assert_false(f.param in unused, "%s is unused at infinity" % f.param)
	_valid(tc, m, "valid")


static func test_header_line(tc: TestCase) -> void:
	var e := _edits(tc)
	tc.assert_eq(e.describe("scr", 5.0, 30.0), "Screen · 0:00.00 → 0:10.00")
	tc.assert_eq(e.describe("scr", 25.0, 30.0), "Screen · 0:20.00 → 0:30.00", "the span at the playhead")
	tc.assert_eq(e.describe("box", 0.0, 30.0), "Cube · in grp · 0:02.00 → 0:08.00")


static func test_spin_and_pulse_replace_reactive(tc: TestCase) -> void:
	var spin: Array = ScreenGeometry.hints_for(ScreenGeometry.SPIN).params.map(func(p): return p.name)
	tc.assert_eq(spin, ["speed_x", "speed_y", "speed_z", "kick", "band"])
	var pulse: Array = ScreenGeometry.hints_for(ScreenGeometry.PULSE).params.map(func(p): return p.name)
	tc.assert_eq(pulse, ["amount", "depth", "band"])
	tc.assert_true(ScreenGeometry.hints_for(ScreenGeometry.PULSE).audio, "follows the music")
	tc.assert_eq(ScreenGeometry.resolve_builtin("spin"), ScreenGeometry.SPIN)
	# A piece that already has Reactive still shows it.
	var doc: Dictionary = DOC.duplicate(true)
	doc.tracks[0].config["reactive"] = {"pulse": 0.3}
	var e := StudioConfigEdits.new()
	e.model = EditModel.from_text(JSON.stringify(doc), "").get("model")
	tc.assert_eq(e.sections("scr", null, "screen").back().title, "Reactive")
