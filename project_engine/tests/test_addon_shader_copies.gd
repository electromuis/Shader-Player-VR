extends RefCounted

## The authoring addon (<repo>/addon_vj) carries copies of the player's
## built-in shaders so screens and layers preview in the editor (its
## exporter maps them back to the player's own), of the modifiers
## helper both sides apply objects' modifiers with, and of the Shadertoy
## scripts (player/shadertoy/) its Shadertoy dock uses. Keep them in step.

const ADDON_PREFIX := "res://addons/vj_editor/"
## player path -> addon path, both relative to their project / addon root.
const COPIES := {
	"player/visualizer/effect_prelude.gdshaderinc": "visualizer/effect_prelude.gdshaderinc",
	"player/visualizer/shadertoy_prelude.gdshaderinc": "visualizer/shadertoy_prelude.gdshaderinc",
	"player/visualizer/shadertoy_main.gdshaderinc": "visualizer/shadertoy_main.gdshaderinc",
	"player/visualizer/effects/edge_blur.gdshader": "visualizer/effects/edge_blur.gdshader",
	"player/visualizer/effects/blur.gdshader": "visualizer/effects/blur.gdshader",
	"player/visualizer/effects/key_black.gdshader": "visualizer/effects/key_black.gdshader",
	"player/visualizer/effects/oval_mask.gdshader": "visualizer/effects/oval_mask.gdshader",
	"player/prefabs/chain_copy.gdshader": "builtin_prefabs/chain_copy.gdshader",
	"player/visualizer/fast_gaussian.gdshaderinc": "visualizer/fast_gaussian.gdshaderinc",
	"player/visualizer/effects/glow.gdshader": "visualizer/effects/glow.gdshader",
	"player/visualizer/effects/crop.gdshader": "visualizer/effects/crop.gdshader",
	"player/visualizer/effects/rounded_corners.gdshader": "visualizer/effects/rounded_corners.gdshader",
	"player/visualizer/effects/keep_center.gdshader": "visualizer/effects/keep_center.gdshader",
	"player/visualizer/effects/image_overlay.gdshader": "visualizer/effects/image_overlay.gdshader",
	"player/visualizer/shaders/image_pulse.gdshader": "visualizer/shaders/image_pulse.gdshader",
	"player/visualizer/shaders/light_ring.gdshader": "visualizer/shaders/light_ring.gdshader",
	"player/visualizer/shaders/spectrum_bars.gdshader": "visualizer/shaders/spectrum_bars.gdshader",
	"player/visualizer/shaders/beat_tunnel.gdshader": "visualizer/shaders/beat_tunnel.gdshader",
	"player/visualizer/shaders/laser_fan.gdshader": "visualizer/shaders/laser_fan.gdshader",
	"player/visualizer/shaders/kaleido_pulse.gdshader": "visualizer/shaders/kaleido_pulse.gdshader",
	"player/runtime/modifiers.gd": "modifiers/modifiers.gd",
	"player/shadertoy/shadertoy_shader.gd": "shadertoy/shadertoy_shader.gd",
	"player/shadertoy/shadertoy_library.gd": "shadertoy/shadertoy_library.gd",
	"player/shadertoy/shadertoy_receiver.gd": "shadertoy/shadertoy_receiver.gd",
	"player/visualizer/shaders/apollonian.gdshader": "visualizer/shaders/apollonian.gdshader",
	"player/visualizer/shaders/aurora_veil.gdshader": "visualizer/shaders/aurora_veil.gdshader",
	"player/visualizer/shaders/chladni.gdshader": "visualizer/shaders/chladni.gdshader",
	"player/visualizer/shaders/cosmic_nebula.gdshader": "visualizer/shaders/cosmic_nebula.gdshader",
	"player/visualizer/shaders/deep_space.gdshader": "visualizer/shaders/deep_space.gdshader",
	"player/visualizer/shaders/droste_spiral.gdshader": "visualizer/shaders/droste_spiral.gdshader",
	"player/visualizer/shaders/flower_of_life.gdshader": "visualizer/shaders/flower_of_life.gdshader",
	"player/visualizer/shaders/glitch_bars.gdshader": "visualizer/shaders/glitch_bars.gdshader",
	"player/visualizer/shaders/gyroid_tunnel.gdshader": "visualizer/shaders/gyroid_tunnel.gdshader",
	"player/visualizer/shaders/hex_pulse.gdshader": "visualizer/shaders/hex_pulse.gdshader",
	"player/visualizer/shaders/hyperspace.gdshader": "visualizer/shaders/hyperspace.gdshader",
	"player/visualizer/shaders/hypno_spiral.gdshader": "visualizer/shaders/hypno_spiral.gdshader",
	"player/visualizer/shaders/julia_morph.gdshader": "visualizer/shaders/julia_morph.gdshader",
	"player/visualizer/shaders/kaleido_smoke.gdshader": "visualizer/shaders/kaleido_smoke.gdshader",
	"player/visualizer/shaders/kaleido_tunnel.gdshader": "visualizer/shaders/kaleido_tunnel.gdshader",
	"player/visualizer/shaders/kaliset_coral.gdshader": "visualizer/shaders/kaliset_coral.gdshader",
	"player/visualizer/shaders/lava_lamp.gdshader": "visualizer/shaders/lava_lamp.gdshader",
	"player/visualizer/shaders/liquid_marble.gdshader": "visualizer/shaders/liquid_marble.gdshader",
	"player/visualizer/shaders/mandelbrot_dive.gdshader": "visualizer/shaders/mandelbrot_dive.gdshader",
	"player/visualizer/shaders/moire_rainbow.gdshader": "visualizer/shaders/moire_rainbow.gdshader",
	"player/visualizer/shaders/oil_slick.gdshader": "visualizer/shaders/oil_slick.gdshader",
	"player/visualizer/shaders/op_art_twist.gdshader": "visualizer/shaders/op_art_twist.gdshader",
	"player/visualizer/shaders/plasma_arcs.gdshader": "visualizer/shaders/plasma_arcs.gdshader",
	"player/visualizer/shaders/plasma_bloom.gdshader": "visualizer/shaders/plasma_bloom.gdshader",
	"player/visualizer/shaders/rainbow_rings.gdshader": "visualizer/shaders/rainbow_rings.gdshader",
	"player/visualizer/shaders/silk_ribbons.gdshader": "visualizer/shaders/silk_ribbons.gdshader",
	"player/visualizer/shaders/spectrum_bloom.gdshader": "visualizer/shaders/spectrum_bloom.gdshader",
	"player/visualizer/shaders/sphere_lattice.gdshader": "visualizer/shaders/sphere_lattice.gdshader",
	"player/visualizer/shaders/square_tunnel.gdshader": "visualizer/shaders/square_tunnel.gdshader",
	"player/visualizer/shaders/sun_rays.gdshader": "visualizer/shaders/sun_rays.gdshader",
	"player/visualizer/shaders/synthwave_grid.gdshader": "visualizer/shaders/synthwave_grid.gdshader",
	"player/visualizer/shaders/truchet_neon.gdshader": "visualizer/shaders/truchet_neon.gdshader",
	"player/visualizer/shaders/voronoi_glass.gdshader": "visualizer/shaders/voronoi_glass.gdshader",
	"player/visualizer/effects/chroma_split.gdshader": "visualizer/effects/chroma_split.gdshader",
	"player/visualizer/effects/false_color.gdshader": "visualizer/effects/false_color.gdshader",
	"player/visualizer/effects/hue_cycle.gdshader": "visualizer/effects/hue_cycle.gdshader",
	"player/visualizer/effects/kaleidoscope.gdshader": "visualizer/effects/kaleidoscope.gdshader",
	"player/visualizer/effects/liquid_warp.gdshader": "visualizer/effects/liquid_warp.gdshader",
	"player/visualizer/effects/neon_edges.gdshader": "visualizer/effects/neon_edges.gdshader",
	"player/visualizer/effects/pop_art_grid.gdshader": "visualizer/effects/pop_art_grid.gdshader",
	"player/visualizer/effects/prism_mosaic.gdshader": "visualizer/effects/prism_mosaic.gdshader",
	"player/visualizer/effects/alpha_threshold.gdshader": "visualizer/effects/alpha_threshold.gdshader",
	"player/prefabs/screen_shader_code.gd": "builtin_prefabs/screen_shader_code.gd",
	"player/prefabs/screen_display.gdshaderinc": "builtin_prefabs/screen_display.gdshaderinc",
	"player/visualizer/surfaces/pillow.gdshaderinc": "visualizer/surfaces/pillow.gdshaderinc",
	"player/visualizer/surfaces/dome.gdshaderinc": "visualizer/surfaces/dome.gdshaderinc",
	"player/visualizer/vertex/ripple.gdshaderinc": "visualizer/vertex/ripple.gdshaderinc",
	"player/visualizer/vertex/twist.gdshaderinc": "visualizer/vertex/twist.gdshaderinc",
	"player/visualizer/vertex/spin.gdshaderinc": "visualizer/vertex/spin.gdshaderinc",
	"player/visualizer/vertex/pulse.gdshaderinc": "visualizer/vertex/pulse.gdshaderinc",
	"player/visualizer/vertex/bulge.gdshaderinc": "visualizer/vertex/bulge.gdshaderinc",
}


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path).replace("\r\n", "\n")


static func test_addon_shaders_match_player(tc: TestCase) -> void:
	var addon_dir := ProjectSettings.globalize_path("res://").path_join("../addon_vj").simplify_path()
	if not DirAccess.dir_exists_absolute(addon_dir):
		return  # player checked out on its own
	for player_rel in COPIES:
		var player_code := _read("res://" + player_rel).replace("res://player/visualizer/", ADDON_PREFIX + "visualizer/")
		var addon_code := _read(addon_dir.path_join(COPIES[player_rel]))
		tc.assert_eq(addon_code, player_code, "addon_vj/%s differs from %s (fix: godot --headless --path project_engine --script res://tests/sync_addon_copies.gd)" % [COPIES[player_rel], player_rel])
