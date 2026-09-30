extends SceneTree

## Shader time follows the video (MediaTime): Studio with a piece of four
## things in a row, each driven by TIME: a custom .gdshader layer with no
## prelude, the same with `// @free_time`, the built-in Hypno spiral (the
## Shadertoy prelude's iTime) and a screen showing a test card through
## Liquid warp (the effect prelude) on a Ripple surface (the display
## shader). Paused, two frames a second apart must match (all but the free
## one); after a seek they differ; playing, they move. It prints each one's
## change (mean per-pixel difference over its patch) and, rendered, saves
## shader_time_*.png. Needs rendering: headless it only prints the clock.

const LAYER_CODE := """shader_type canvas_item;
%s
void fragment() {
	float t = TIME;
	vec3 c = 0.5 + 0.5 * cos(t * 2.0 + UV.xyx * 6.0 + vec3(0.0, 2.0, 4.0));
	float bands = step(0.5, fract(UV.x * 6.0 - t * 0.5));
	COLOR = vec4(mix(c, c * 0.35, bands), 1.0);
}
"""
## id -> x position of its centre (y 2, all 2.56 × 1.44 m: SCALE).
const ROW := {"media": -4.2, "free": -1.4, "spiral": 1.4, "warp": 4.2}
const SCALE := 0.08
const LABELS := {"media": "custom .gdshader", "free": "custom, @free_time", "spiral": "Hypno spiral (Shadertoy)",
		"warp": "Liquid warp + Ripple"}

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"
var cam: Camera3D
var _clock_label: Label3D


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.pressed = pressed
		studio.stage.router.handle_key(ev)
	await frames(2)


func grab(name: String) -> Image:
	_clock_label.text = "playhead %.2f s  ·  %s" % [studio.runner.playhead, "playing" if studio.runner.playing else "paused"]
	await frames(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if rendered and name != "":
		img.save_png(out.path_join("shader_time_%s.png" % name))
	return img


## The patch of the view where `id` is, a little inside its edges.
func patch(id: String) -> Rect2i:
	var c := Vector3(ROW[id], 2.0, 0.0)
	var a := cam.unproject_position(c + Vector3(-1.0, 0.55, 0.0))
	var b := cam.unproject_position(c + Vector3(1.0, -0.55, 0.0))
	return Rect2i(Vector2i(a), Vector2i(b - a))


## Mean per-channel difference (0..255) over each thing's patch.
func changes(a: Image, b: Image) -> Dictionary:
	var out_d := {}
	for id in ROW:
		var r := patch(id)
		var sum := 0.0
		var n := 0
		for y in range(r.position.y, r.end.y, 3):
			for x in range(r.position.x, r.end.x, 3):
				var p := a.get_pixel(x, y)
				var q := b.get_pixel(x, y)
				sum += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
				n += 3
		out_d[id] = snappedf(sum / maxi(n, 1) * 255.0, 0.01)
	return out_d


func clock(label: String) -> void:
	print("%s: playhead %.3f, shader time %.3f, camera effect time %.3f, playing %s" % [
		label, studio.runner.playhead, MediaTime.seconds, studio.stage.camera_fx.effect.time,
		studio.runner.playing])


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("shader_time_piece")
	DirAccess.make_dir_recursive_absolute(dir.path_join("shaders"))
	for name in ["media", "free"]:
		var f := FileAccess.open(dir.path_join("shaders/%s.gdshader" % name), FileAccess.WRITE)
		f.store_string(LAYER_CODE % ("// @free_time" if name == "free" else ""))
		f.close()
	var small := {"scale": [SCALE, SCALE, SCALE]}
	var doc := {
		"format_version": 2, "media": {"video": "clip.mp4", "duration": 30.0},
		"prefabs": {"layer": "res://player/prefabs/layer.tscn", "screen": "res://player/prefabs/screen.tscn"},
		"shaders": {"media": "shaders/media.gdshader", "free": "shaders/free.gdshader",
			"spiral": "res://player/visualizer/shaders/hypno_spiral.gdshader",
			"warp": "res://player/visualizer/effects/liquid_warp.gdshader"},
		"tracks": [],
		"meta": {"default_screen": false},
	}
	for id in ["media", "free", "spiral"]:
		doc.tracks.append({"type": "event", "t": 0, "action": "spawn", "id": id, "prefab": "layer",
			"transform": {"position": [ROW[id], 2, 0], "scale": small.scale}, "config": {"shader": id}})
	doc.tracks.append({"type": "event", "t": 0, "action": "spawn", "id": "warp", "prefab": "screen",
		"transform": {"position": [ROW.warp, 2, 0], "scale": small.scale},
		"config": {"effects": [{"shader": "warp"}], "vertex_effects": [{"shader": "ripple", "params": {}}]}})
	var f := FileAccess.open(dir.path_join("clip.spscript"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  "))
	f.close()

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	print("open: ", studio.open_piece(dir.path_join("clip.spscript")))
	studio.runner.set_video_duration(30.0)
	# A test card on the screen (there's no video here).
	var card := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	for y in 180:
		for x in 320:
			var check := ((x / 20) + (y / 20)) % 2 == 0
			card.set_pixel(x, y, Color(x / 320.0, y / 180.0, 0.6) if check else Color(0.1, 0.1, 0.15))
	var warp: Screen = studio.runner.registry().get_node_by_id("warp")
	warp.set_source_texture(ImageTexture.create_from_image(card))
	cam = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2, 7.0)
	cam.look_at(Vector3(0, 2, 0))
	for id in ROW:
		var label := Label3D.new()
		label.text = LABELS[id]
		label.font_size = 48
		label.pixel_size = 0.004
		label.position = Vector3(ROW[id], 0.95, 0.0)
		studio.add_child(label)
	var clock_label := Label3D.new()
	clock_label.font_size = 64
	clock_label.pixel_size = 0.004
	clock_label.position = Vector3(0, 3.3, 0)
	studio.add_child(clock_label)
	_clock_label = clock_label
	for c in studio.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	studio.stage.seek_to(5.0)
	await frames(30)  # shaders compile

	clock("paused at 5 s")
	var a := await grab("paused_a")
	await create_timer(1.0).timeout
	clock("a second later")
	var b := await grab("paused_b")
	print("paused, 1 s apart: ", changes(a, b), "  (free moves, the rest 0)")

	studio.stage.seek_to(12.0)
	await frames(6)
	clock("seeked to 12 s")
	var c := await grab("seeked")
	print("after the seek: ", changes(b, c), "  (all move)")

	await key(KEY_SPACE)
	await create_timer(1.0).timeout
	clock("played a second")
	var d := await grab("playing")
	print("playing a second: ", changes(c, d), "  (all move)")
	await key(KEY_SPACE)
	await frames(4)
	clock("paused again")
	var e := await grab("")
	await create_timer(0.5).timeout
	print("paused again, 0.5 s apart: ", changes(e, await grab("")), "  (free moves, the rest 0)")
	quit()
