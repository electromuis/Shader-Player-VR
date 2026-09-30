extends SceneTree

## TODO 85: every effect with an `@idle` hint gives the picture back
## unchanged at the params the hint calls idle, so Screen may leave it out
## of the chain. Renders a test card (colours, a see-through band) through
## each effect at those params and through a plain copy (chain_copy), and
## prints the largest difference per channel (0..255); and at the effect's
## defaults, to show the comparison would catch a change. Needs rendering
## (headless draws nothing).

const EFFECTS := "res://player/visualizer/effects/"
const SIZE := Vector2i(320, 180)
## Params that make each hinted effect idle (the rest at their defaults).
const IDLE := {
	"blur": {"radius": 0.0},
	"edge_blur": {"radius": 0.0},
	"edge_blur outward": {"radius": 0.0, "inward": false},
	"chroma_split": {"amount": 0.0},
	"false_color": {"mix_amount": 0.0},
	"kaleidoscope": {"mix_amount": 0.0},
	"image_overlay": {"opacity": 0.0},
	"match_video_brightness": {"strength": 0.0},
	"crop": {},
	"neon_edges": {"glow": 0.0, "keep": 1.0},
	"hue_cycle": {"speed": 0.0, "spread": 0.0, "saturation": 1.0},
	"glow": {"intensity": 0.0, "edge_brighten": 0.0},
}

var card: ImageTexture


func frames(n: int) -> void:
	for i in n:
		await process_frame


## `shader` over the card with `params`; an effect with a prepass gets it
## first (at full size, one step), as Screen does.
func render(shader: Shader, params: Dictionary) -> Image:
	var pre: SubViewport = null
	if VisualizerShaders.has_prepass(shader):
		pre = _pass(shader, params.merged({"prepass": true}), null)
	var vp := _pass(shader, params, pre.get_texture() if pre != null else null)
	await frames(4)
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if pre != null:
		pre.queue_free()
	return img


func _pass(shader: Shader, params: Dictionary, prepass: Texture2D) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("input_tex", card)
	mat.set_shader_parameter("video_tex", card)
	mat.set_shader_parameter("display_aspect", float(SIZE.x) / SIZE.y)
	if prepass != null:
		mat.set_shader_parameter("prepass_tex", prepass)
	for k in params:
		mat.set_shader_parameter(k, params[k])
	rect.material = mat
	vp.add_child(rect)
	root.add_child(vp)
	return vp


## Largest difference per channel, 0..255: [r, g, b, a] (colour only where
## the reference isn't see-through).
func diff(a: Image, b: Image) -> Array:
	var worst := [0, 0, 0, 0]
	for y in SIZE.y:
		for x in SIZE.x:
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			var d := [absf(p.r - q.r), absf(p.g - q.g), absf(p.b - q.b), absf(p.a - q.a)]
			for i in 4:
				if i < 3 and q.a < 0.01:
					continue
				worst[i] = maxi(worst[i], roundi(d[i] * 255.0))
	return worst


func _initialize() -> void:
	var img := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	for y in SIZE.y:
		for x in SIZE.x:
			var u := float(x) / SIZE.x
			var v := float(y) / SIZE.y
			var c := Color.from_hsv(fmod(u * 1.5 + v * 0.3, 1.0), 0.4 + 0.6 * v, 0.3 + 0.7 * u)
			if (x / 16 + y / 16) % 2 == 0:
				c = c.darkened(0.5)
			# A see-through band, and a soft edge into it.
			c.a = clampf(absf(v - 0.75) * 12.0, 0.0, 1.0)
			img.set_pixel(x, y, c)
	card = ImageTexture.create_from_image(img)
	await frames(2)
	var reference := await render(preload("res://player/prefabs/chain_copy.gdshader"), {})
	var bad := 0
	for name in IDLE:
		var key: String = EFFECTS + name.split(" ")[0] + ".gdshader"
		var shader := VisualizerShaders.load_shader(key)
		var params: Dictionary = IDLE[name]
		var idle := VisualizerShaders.is_idle(key, params)
		var at_idle := diff(await render(shader, params), reference)
		var at_default := diff(await render(shader, {}), reference)
		var ok: bool = idle and at_idle.max() <= 1
		bad += 0 if ok else 1
		print("%-24s is_idle %-5s  idle diff %-16s defaults diff %-16s %s" % [name, idle, at_idle, at_default,
				"ok" if ok else "CHANGES THE PICTURE"])
	# Every effect with the hint is listed here.
	for f in DirAccess.get_files_at(EFFECTS):
		if f.ends_with(".gdshader") and VisualizerShaders.hints_for(EFFECTS + f).expressions.has("idle") \
				and not IDLE.has(f.get_basename()):
			print("not checked: ", f)
			bad += 1
	print("%d problem(s)" % bad)
	quit()
