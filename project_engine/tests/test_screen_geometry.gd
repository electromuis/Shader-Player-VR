extends RefCounted

## Surfaces, vertex effects and the display shader built from them
## (ScreenGeometry, Screen), the source layout split (VideoProjection), and
## earlier presets' curvature becoming a Pillow.

const HALF := Vector2(4.0, 2.25)  # a 8 × 4.5 m picture


static func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.001


static func test_prefixed_renames_declarations(t: TestCase) -> void:
	var code := """uniform float amount : hint_range(0.0, 1.0) = 0.5;
const float K = 2.0;
float helper(float x) {
	return x * K * amount;
}
vec3 deform(vec3 p, vec2 uv, vec2 half_m) {
	p.z += vfx_react(helper(p.x), 0.0, 1);
	return p;
}
"""
	var out := ScreenGeometry.Code.prefixed(code, "vfx3_")
	for name in ["vfx3_amount", "vfx3_K", "vfx3_helper(", "vfx3_deform("]:
		t.assert_has(out, name)
	t.assert_has(out, "vfx_react(", "the display include's helpers keep their names")
	t.assert_false(out.contains(" amount;"), "every use is renamed")


static func test_build_shader_runs_stages_in_order(t: TestCase) -> void:
	var shader := ScreenGeometry.build_shader([ScreenGeometry.RIPPLE, ScreenGeometry.TWIST], ScreenGeometry.DOME, false)
	var code := shader.code
	var a := code.find("p = vfx0_deform(")
	var b := code.find("p = vfx1_deform(")
	var c := code.find("p = srf_surface(")
	t.assert_true(a > 0 and a < b and b < c, "vertex effects in order, then the surface")
	t.assert_false(code.contains("#define SCREEN_OPAQUE"))
	t.assert_true(ScreenGeometry.build_shader([ScreenGeometry.RIPPLE, ScreenGeometry.TWIST], ScreenGeometry.DOME, false) == shader,
			"same stages share the shader")
	t.assert_has(ScreenGeometry.build_shader([], ScreenGeometry.DOME, true).code, "#define SCREEN_OPAQUE")
	t.assert_false(ScreenGeometry.build_shader(["C:/nope.gdshaderinc"], ScreenGeometry.PILLOW, false).code.contains("vfx0_"),
			"unreadable stages are skipped")


static func test_hints(t: TestCase) -> void:
	var dome := ScreenGeometry.hints_for(ScreenGeometry.DOME)
	t.assert_eq(dome.placements, ["fixed", "around", "infinity"])
	t.assert_eq(dome.unused.get("infinity"), ["size", "distance", "height"])
	t.assert_true(dome.hint != "")
	var pillow := ScreenGeometry.hints_for(ScreenGeometry.PILLOW)
	t.assert_eq(pillow.placements, ["fixed", "around"])
	t.assert_eq(pillow.unused.get("around"), ["arc_x", "arc_y"])
	t.assert_true(ScreenGeometry.hints_for(ScreenGeometry.RIPPLE).audio)
	t.assert_eq(ScreenGeometry.default_placement(ScreenGeometry.DOME), "around")
	t.assert_eq(ScreenGeometry.default_placement(ScreenGeometry.PILLOW), "fixed")


static func test_normalized_surface(t: TestCase) -> void:
	t.assert_eq(ScreenGeometry.normalized_surface(null), ScreenGeometry.default_surface())
	var dome := ScreenGeometry.normalized_surface({"shader": "dome", "placement": "sideways"})
	t.assert_eq(dome.shader, ScreenGeometry.DOME, "built-in names resolve")
	t.assert_eq(dome.placement, "around", "an unsupported placement falls back")
	var pillow := ScreenGeometry.normalized_surface({"shader": "pillow", "placement": "infinity"})
	t.assert_eq(pillow.placement, "fixed", "a Pillow can't go to infinity")


static func test_pillow_matches_earlier_curvature(t: TestCase) -> void:
	# curvature 1 was a half-cylinder: the edges swing 90° toward the viewer.
	var r := HALF.x / (PI * 0.5)
	var p := ScreenGeometry.surface_point(ScreenGeometry.PILLOW, {"arc_x": 180.0}, 0,
			Vector3(HALF.x, 0.0, 0.0), HALF, 8.0)
	t.assert_true(_near(p, Vector3(r, 0.0, r)), "edge at %s" % p)
	var flat := ScreenGeometry.surface_point(ScreenGeometry.PILLOW, {}, 0, Vector3(1.0, 2.0, 0.0), HALF, 8.0)
	t.assert_true(_near(flat, Vector3(1.0, 2.0, 0.0)), "0 / 0 is flat")
	# Padded to twice the picture: the bend spans the whole quad, and the
	# depth is squashed by the quad's stretch as it was in mesh units.
	var padded := ScreenGeometry.surface_point(ScreenGeometry.PILLOW, {"arc_y": 180.0}, 0,
			Vector3(0.0, HALF.y * 2.0, 0.0), HALF, 8.0, HALF * 2.0, Vector2(2.0, 2.0))
	var ry := HALF.y * 2.0 / (PI * 0.5)
	t.assert_true(_near(padded, Vector3(0.0, ry, ry * 0.5)), "padded edge at %s" % padded)


static func test_pillow_true_arcs(t: TestCase) -> void:
	# Around the viewer, x then y wraps the screen onto a sphere round the eye.
	var params := {"arc_x": 90.0, "arc_y": 45.0, "true_arcs": true}
	for pt in [Vector3(3.0, 2.0, 0.0), Vector3(-5.0, -4.0, 0.0), Vector3(0.0, 3.0, 0.0)]:
		var p := ScreenGeometry.surface_point(ScreenGeometry.PILLOW, params, ScreenGeometry.Placement.AROUND,
				pt, HALF, 8.0)
		t.assert_true(absf(p.distance_to(Vector3(0.0, 0.0, 8.0)) - 8.0) < 0.001, "%s is 8 m from the eye" % p)
	# Fixed: the top edge's column bends by arc_y, the corner lies on the
	# already bent sheet.
	var fixed := ScreenGeometry.surface_point(ScreenGeometry.PILLOW, {"arc_y": 180.0, "true_arcs": true}, 0,
			Vector3(0.0, HALF.y, 0.0), HALF, 8.0)
	var r := HALF.y / (PI * 0.5)
	t.assert_true(_near(fixed, Vector3(0.0, r, r)), "top edge at %s" % fixed)


static func test_dome_around_viewer_centres_on_the_eye(t: TestCase) -> void:
	var eye := Vector3(0.0, 0.0, 8.0)
	for pt in [Vector3.ZERO, Vector3(HALF.x, 0.0, 0.0), Vector3(-2.0, HALF.y, 0.0), Vector3(3.0, -1.0, 0.0)]:
		var p := ScreenGeometry.surface_point(ScreenGeometry.DOME, {}, ScreenGeometry.Placement.AROUND, pt, HALF, 8.0)
		t.assert_true(is_equal_approx(p.distance_to(eye), 8.0), "%s is 8 m from the eye" % p)
	var edge := ScreenGeometry.surface_point(ScreenGeometry.DOME, {}, ScreenGeometry.Placement.AROUND,
			Vector3(HALF.x, 0.0, 0.0), HALF, 8.0)
	t.assert_true(_near(edge, Vector3(8.0, 0.0, 8.0)), "180° wide: the edge is beside the viewer")
	# Auto height: square pixels, so 180° × 16:9 is about 101° high.
	var top := ScreenGeometry.surface_point(ScreenGeometry.DOME, {}, ScreenGeometry.Placement.AROUND,
			Vector3(0.0, HALF.y, 0.0), HALF, 8.0)
	t.assert_true(is_equal_approx(atan2(top.y, eye.z - top.z), deg_to_rad(90.0 * 9.0 / 16.0)))
	var stretched := ScreenGeometry.surface_point(ScreenGeometry.DOME, {"auto_height": false, "arc_y": 180.0},
			ScreenGeometry.Placement.AROUND, Vector3(0.0, HALF.y, 0.0), HALF, 8.0)
	t.assert_true(_near(stretched, Vector3(0.0, 8.0, 8.0)), "arc_y 180: the top edge is overhead")


static func test_dome_fixed_radius_follows_arc(t: TestCase) -> void:
	var r := HALF.x / deg_to_rad(45.0)
	var p := ScreenGeometry.surface_point(ScreenGeometry.DOME, {"arc_x": 90.0}, ScreenGeometry.Placement.FIXED,
			Vector3(HALF.x, 0.0, 0.0), HALF, 8.0)
	t.assert_true(is_equal_approx(p.distance_to(Vector3(0.0, 0.0, r)), r))


static func test_ray_hits(t: TestCase) -> void:
	var mesh_half := Vector2(16.0, 9.0)
	var xform := Transform3D(Basis.from_scale(Vector3.ONE * 0.25), Vector3.ZERO)  # 8 × 4.5 m
	var flat := ScreenGeometry.default_surface()
	t.assert_true(ScreenGeometry.ray_hits(Vector3(0, 0, 8), Vector3(0, 0, -1), xform, mesh_half, mesh_half, flat, 8.0))
	t.assert_false(ScreenGeometry.ray_hits(Vector3(5, 0, 8), Vector3(0, 0, -1), xform, mesh_half, mesh_half, flat, 8.0))
	var dome := {"shader": ScreenGeometry.DOME, "params": {}, "placement": "around"}
	var side := Vector3(1.0, 0.0, -0.2).normalized()
	t.assert_false(ScreenGeometry.ray_hits(Vector3(0, 0, 8), side, xform, mesh_half, mesh_half, flat, 8.0))
	t.assert_true(ScreenGeometry.ray_hits(Vector3(0, 0, 8), side, xform, mesh_half, mesh_half, dome, 8.0),
			"the dome wraps round to where a flat screen isn't")
	dome.placement = "infinity"
	t.assert_false(ScreenGeometry.ray_hits(Vector3(0, 0, 8), Vector3(0, 0, -1), xform, mesh_half, mesh_half, dome, 8.0),
			"nothing to aim at around the viewer")


static func test_settings_migrate_curvature(t: TestCase) -> void:
	var s := ScreenSettings.new()
	s.from_dict({"curvature": 0.5, "vertical_curvature": 0.25})
	t.assert_eq(s.surface, {"shader": ScreenGeometry.PILLOW, "params": {"arc_x": 90.0, "arc_y": 45.0}, "placement": "fixed"})
	t.assert_false(s.to_dict().has("curvature"))
	s.set_surface_placement("infinity")
	t.assert_eq(s.surface.placement, "fixed", "unsupported placement ignored")


static func test_source_layout_split(t: TestCase) -> void:
	for key in VideoProjection.KEYS:
		if key != "auto":
			t.assert_eq(VideoProjection.compose(VideoProjection.fov_of(key), VideoProjection.stereo_name(key)), key)
	t.assert_eq(VideoProjection.detect("clip_180_RL.mp4"), "180_sbs")
	t.assert_true(VideoProjection.detect_swap("clip_180_RL.mp4"))
	t.assert_false(VideoProjection.detect_swap("clip_180_LR.mp4"))
	t.assert_eq(VideoProjection.suggested_surface("flat_sbs"), {})
	var s := VideoProjection.suggested_surface("360_tb")
	t.assert_eq(s.shader, ScreenGeometry.DOME)
	t.assert_eq(s.placement, "infinity")
	t.assert_eq(s.params.arc_x, 360.0)


static func test_screen_surface_and_vertex_effects(t: TestCase) -> void:
	var screen: Screen = load("res://player/prefabs/screen.tscn").instantiate()
	screen.notification(Node.NOTIFICATION_READY)
	var mat: ShaderMaterial = screen._display_material
	screen.set_surface({"shader": "dome", "placement": "infinity"})
	t.assert_has(mat.shader.code, "#define SCREEN_OPAQUE", "opaque at infinity")
	t.assert_eq(mat.get_shader_parameter("placement"), ScreenGeometry.Placement.INFINITY)
	t.assert_eq(mat.get_shader_parameter("srf_arc_x"), 180.0, "defaults are pushed")
	screen.set_material_param("shape", "arc_x", 90.0)
	t.assert_eq(mat.get_shader_parameter("srf_arc_x"), 90.0)
	screen.set_curvature(0.5)
	t.assert_eq(screen.get_surface().shader, ScreenGeometry.PILLOW, "earlier curvature switches to a Pillow")
	t.assert_eq(mat.get_shader_parameter("srf_arc_x"), 90.0)
	t.assert_false(screen.uses_audio())
	screen.set_vertex_effects([{"shader": "ripple", "params": {"amplitude": 0.2}}])
	t.assert_has(mat.shader.code, "vfx0_deform")
	t.assert_true(screen.uses_audio())
	t.assert_eq(mat.get_shader_parameter("vfx0_amplitude"), 0.2)
	screen.set_material_param("vertex0", "amplitude", 0.5)
	t.assert_eq(mat.get_shader_parameter("vfx0_amplitude"), 0.5)
	screen.configure({"surface": {"shader": "dome"}, "vertex_effects": []}, null)
	t.assert_true(screen.is_scripted("surface"))
	t.assert_true(screen.is_scripted("vertex_effects"))
	t.assert_false(mat.shader.code.contains("vfx0_"))
	screen.free()


static func test_validation_of_surface(t: TestCase) -> void:
	var base := {"format_version": 1, "media": {"video": "v.mp4"}, "tracks": []}
	var good := base.duplicate(true)
	good.tracks = [{"type": "event", "t": 0, "action": "spawn", "id": "a", "prefab": "p",
			"config": {"surface": {"shader": "dome", "placement": "around"},
				"vertex_effects": [{"shader": "ripple", "params": {"amplitude": 0.1}}]}}]
	t.assert_true(ScriptFormat.load_from_string(JSON.stringify(good)).ok)
	var bad := base.duplicate(true)
	bad.tracks = [{"type": "event", "t": 0, "action": "spawn", "id": "a", "prefab": "p",
			"config": {"surface": {"shader": "dome", "placement": "sideways"}}}]
	t.assert_false(ScriptFormat.load_from_string(JSON.stringify(bad)).ok)
