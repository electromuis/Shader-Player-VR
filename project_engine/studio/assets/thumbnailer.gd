class_name StudioThumbnailer
extends Node

## Small pictures of the shelf's assets, rendered offscreen with the
## player's own prefabs (what you'll get is what the card shows): a layer
## shader on a layer fed made-up music, an effect on a screen showing a
## test card, a screen with the test card, other prefabs framed from the
## front and a little above. One at a time, a few frames each, in a
## SubViewport with its own world.
##
## Cached as PNGs in user://thumbnails, named after the asset's path and
## when its file last changed, so an edited shader gets a new picture
## (not next to the asset as the plan had it: library folders and the
## piece's folder stay free of them). Headless there's no renderer: nothing
## is drawn and thumbnail() stays null (the shelf shows its placeholder).
##
## Layer and effect cards also get a short loop (loop()): LOOP_FRAMES
## frames drawn the same way, side by side in one strip, cached next to
## the stills. Their shaders run on a clock of their own (preview copies
## whose TIME reads PREVIEW_TIME, see preview_code) rather than the stage's
## time, so a paused piece doesn't freeze them and drawing them doesn't
## touch the stage; the made-up music follows the same clock and repeats
## every half second, so the loop's two seconds keep its beat. Drawn only
## when asked for (a card hovered, the headset's shelf open), after any
## stills waiting.
##
## A look's picture is different: a snapshot of the object on stage when
## the look was saved (snapshot()), kept next to the look's file
## (StudioLooks.picture_path). Studio's own helpers (lines, panels, the
## carried card) are on HELPER_LAYER, which snapshots leave out.

## A thumbnail is ready (or came off the disk).
signal thumbnail_ready(asset_id: String, texture: Texture2D)
## A loop is ready: a strip of frames SIZE wide each (loop()).
signal loop_ready(asset_id: String, strip: Texture2D)

const SIZE := Vector2i(256, 160)
const FRAMES := 10
## Bump when the pictures change, so old ones are drawn again.
const VERSION := 1
const CACHE_DIR := "user://thumbnails"
## The render layer (1-based) of Studio's helpers: every camera sees it but
## a snapshot's.
const HELPER_LAYER := 20
## The asset types that get a loop.
const LOOP_TYPES := ["layer", "effect", "vertex"]
const LOOP_FRAMES := 20
const LOOP_FPS := 10.0
## Loops kept in memory (a strip is about 3 MB), the least recently asked
## for dropped first; they stay on the disk.
const LOOP_KEEP := 24
## A loop whose frames all differ from its first by less than this
## (difference()) is kept as a still.
const STILL_DIFFERENCE := 0.002
## The uniform a preview copy's TIME reads.
const PREVIEW_TIME := &"vj_preview_time"
const SCREEN_SCENE := preload("res://player/prefabs/screen.tscn")
const LAYER_SCENE := preload("res://player/prefabs/layer.tscn")

var _textures := {}  # asset id -> Texture2D
var _queue: Array = []
var _busy := false
var _loops := {}  # asset id -> strip, the most recently asked for last
var _loop_queue: Array = []  # the most recently asked for first
static var _card: Texture2D
static var _shader_type_re := RegEx.create_from_string("(?m)^\\s*shader_type\\s+\\w+\\s*;")


## The asset's picture if there is one yet; otherwise null, and it's drawn
## (thumbnail_ready says when).
func thumbnail(asset: Dictionary) -> Texture2D:
	if _textures.has(asset.id):
		return _textures[asset.id]
	if asset.type == "look":
		var picture := StudioLooks.picture_path(asset.path)
		var shot := Image.load_from_file(picture) if FileAccess.file_exists(picture) else null
		if shot == null:
			return null  # none (saved headless): the placeholder
		_textures[asset.id] = ImageTexture.create_from_image(shot)
		return _textures[asset.id]
	var file := cache_path(asset)
	if FileAccess.file_exists(file):
		var img := Image.load_from_file(ProjectSettings.globalize_path(file))
		if img != null:
			_textures[asset.id] = ImageTexture.create_from_image(img)
			return _textures[asset.id]
	if can_render() and not _queue.any(func(a): return a.id == asset.id):
		_queue.append(asset)
	return null


## The asset's loop (a strip of LOOP_FRAMES pictures, or of one for a
## shader that turned out not to move) if there is one yet; otherwise null,
## and it's drawn (loop_ready says when). Null for other asset types.
func loop(asset: Dictionary) -> Texture2D:
	if not String(asset.type) in LOOP_TYPES:
		return null
	if _loops.has(asset.id):
		var strip: Texture2D = _loops[asset.id]
		_loops.erase(asset.id)
		_loops[asset.id] = strip
		return strip
	var file := loop_path(asset)
	if FileAccess.file_exists(file):
		var img := Image.load_from_file(ProjectSettings.globalize_path(file))
		if img != null:
			return _keep_loop(asset.id, ImageTexture.create_from_image(img))
	if can_render():
		_loop_queue = _loop_queue.filter(func(a): return a.id != asset.id)
		_loop_queue.push_front(asset)
	return null


## How many frames `strip` has.
static func frames_of(strip: Texture2D) -> int:
	return maxi(1, strip.get_width() / SIZE.x) if strip != null else 0


func _keep_loop(id: String, strip: Texture2D) -> Texture2D:
	_loops[id] = strip
	while _loops.size() > LOOP_KEEP:
		_loops.erase(_loops.keys()[0])
	return strip


static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Where the asset's picture is kept.
static func cache_path(asset: Dictionary) -> String:
	var path := String(asset.path)
	var stamp := "%s|%s|%d|%d" % [asset.type, path, FileAccess.get_modified_time(path), VERSION]
	return CACHE_DIR.path_join(stamp.md5_text() + ".png")


## Where the asset's loop is kept.
static func loop_path(asset: Dictionary) -> String:
	return cache_path(asset).trim_suffix(".png") + "_loop.png"


func is_busy() -> bool:
	return _busy or not _queue.is_empty() or not _loop_queue.is_empty()


func _process(_delta: float) -> void:
	if _busy:
		return
	if not _queue.is_empty():
		_render(_queue.pop_front())
	elif not _loop_queue.is_empty():
		_render_loop(_loop_queue.pop_front())


func _render(asset: Dictionary) -> void:
	_busy = true
	var vp: SubViewport = _set_up(asset).viewport
	for i in 2:
		await get_tree().process_frame
	_frame_asset(vp, asset)
	for i in FRAMES:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img != null and not img.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
		img.save_png(ProjectSettings.globalize_path(cache_path(asset)))
		var tex := ImageTexture.create_from_image(img)
		_textures[asset.id] = tex
		thumbnail_ready.emit(asset.id, tex)
	_busy = false


## LOOP_FRAMES pictures of `asset` at LOOP_FPS on its own clock (see
## preview_code), side by side. If none differs from the first, only that
## one is kept.
func _render_loop(asset: Dictionary) -> void:
	_busy = true
	var set := _set_up(asset)
	var vp: SubViewport = set.viewport
	var audio: FakeAudio = set.audio
	for i in 2:
		await get_tree().process_frame
	_frame_asset(vp, asset)
	var copies := {}
	var frames: Array[Image] = []
	var moves := false
	for i in LOOP_FRAMES:
		var t := i / LOOP_FPS
		if audio != null:
			audio.clock = t
		use_preview_time(vp, t, copies)
		# Two frames: an effect's passes draw into each other.
		for f in 2:
			await get_tree().process_frame
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			break
		moves = moves or (not frames.is_empty() and difference(img, frames[0]) > STILL_DIFFERENCE)
		frames.append(img)
	vp.queue_free()
	if frames.size() == LOOP_FRAMES:
		if not moves:
			frames.resize(1)
		var strip := Image.create(SIZE.x * frames.size(), SIZE.y, false, frames[0].get_format())
		for i in frames.size():
			strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, SIZE), Vector2i(SIZE.x * i, 0))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
		strip.save_png(ProjectSettings.globalize_path(loop_path(asset)))
		loop_ready.emit(asset.id, _keep_loop(asset.id, ImageTexture.create_from_image(strip)))
	_busy = false


## How much two pictures of the same size differ: the mean difference of
## their colour channels (0–1) over a grid of points.
static func difference(a: Image, b: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(2, a.get_height(), 5):
		for x in range(2, a.get_width(), 5):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 3
	return sum / maxi(n, 1)


## Every shader under `root` swapped for its preview copy (made once per
## shader and kept in `copies`), with their TIME at `t`.
static func use_preview_time(root: Node, t: float, copies: Dictionary) -> void:
	for mat: ShaderMaterial in _shader_materials(root, []):
		var shader := mat.shader
		if shader == null:
			continue
		if not copies.values().has(shader):
			if not copies.has(shader):
				var copy := Shader.new()
				copy.code = preview_code(shader.code)
				copies[shader] = copy
			mat.shader = copies[shader]
		mat.set_shader_parameter(PREVIEW_TIME, t)


## `code` with TIME reading PREVIEW_TIME instead of the stage's time (the
## media time include's guard defined first, so it does nothing).
static func preview_code(code: String) -> String:
	var m := _shader_type_re.search(code)
	if m == null:
		return code
	return code.insert(m.get_end(), "\n#define VJ_MEDIA_TIME\nuniform float %s;\n#define TIME %s\n" % [PREVIEW_TIME, PREVIEW_TIME])


static func _shader_materials(node: Node, out: Array) -> Array:
	var mats: Array = []
	if node is CanvasItem:
		mats.append((node as CanvasItem).material)
	if node is GeometryInstance3D:
		mats.append((node as GeometryInstance3D).material_override)
	if node is MeshInstance3D:
		for i in (node as MeshInstance3D).get_surface_override_material_count():
			mats.append((node as MeshInstance3D).get_surface_override_material(i))
	for m in mats:
		if m is ShaderMaterial and not out.has(m):
			out.append(m)
	for c in node.get_children(true):
		_shader_materials(c, out)
	return out


func _frame_asset(vp: SubViewport, asset: Dictionary) -> void:
	_frame(vp.get_meta("camera"), vp.get_meta("subject"), asset.kind in ["screen", "layer", "effect", "vertex"])


## `asset` in a SubViewport of its own (in the tree; its camera and
## subject in its metas, for _frame_asset once it has settled): {viewport,
## audio (the made-up music for a layer, else null)}.
func _set_up(asset: Dictionary) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	add_child(vp)
	var audio: FakeAudio = null
	var node: Node3D
	match String(asset.type):
		"layer":
			audio = FakeAudio.new()
			vp.add_child(audio)
			var layer: Visualizer = LAYER_SCENE.instantiate()
			vp.add_child(layer)
			layer.bind_audio(audio)
			layer.bind_video(test_card())
			layer.set_shader(asset.path)
			node = layer
		"effect":
			var screen: Screen = SCREEN_SCENE.instantiate()
			vp.add_child(screen)
			screen.set_source_texture(test_card())
			screen.set_effects([{"shader": asset.path, "params": {}}])
			node = screen
		"vertex":
			var screen: Screen = SCREEN_SCENE.instantiate()
			vp.add_child(screen)
			screen.set_source_texture(test_card())
			screen.set_vertex_effects([{"shader": asset.path, "params": {}}])
			node = screen
		_:
			var packed := ResourceLoader.load(asset.path, "PackedScene") as PackedScene
			node = packed.instantiate() as Node3D if packed != null else null
			if node == null:
				node = Node3D.new()
			vp.add_child(node)
			if node is Screen:
				(node as Screen).set_source_texture(test_card())
	vp.set_meta("camera", cam)
	vp.set_meta("subject", node)
	return {"viewport": vp, "audio": audio}


## A picture of `node` as it is on stage (in its own world and light,
## without Studio's helpers), saved as `png` and shown for `asset_id`.
func snapshot(node: Node3D, png: String, asset_id: String) -> void:
	if not can_render() or node == null or not node.is_inside_tree():
		return
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.world_3d = node.get_world_3d()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.cull_mask = cam.cull_mask & ~(1 << (HELPER_LAYER - 1))
	vp.add_child(cam)
	add_child(vp)
	_frame(cam, node, node is Screen or node is Visualizer)
	cam.current = true
	for i in FRAMES:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	img.save_png(png)
	var tex := ImageTexture.create_from_image(img)
	_textures[asset_id] = tex
	thumbnail_ready.emit(asset_id, tex)


## Put `node` and everything drawn under it on HELPER_LAYER only.
static func mark_helper(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 1 << (HELPER_LAYER - 1)
	for c in node.get_children():
		mark_helper(c)


## Point the camera at `node`: square on for flat things (screens, layers),
## else from the front, a little above and to the side (in its own frame,
## so a snapshot sees an object on stage from its front).
static func _frame(cam: Camera3D, node: Node3D, flat: bool) -> void:
	var box := StudioPicker.local_bounds(node)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	var xf := node.global_transform
	var center := xf * box.get_center()
	box = Transform3D(Basis.from_scale(xf.basis.get_scale()), Vector3.ZERO) * box
	var aspect := float(SIZE.x) / SIZE.y
	var half_v := deg_to_rad(cam.fov) * 0.5
	var facing := xf.basis.orthonormalized()
	var dir := facing * (Vector3(0, 0, 1) if flat else Vector3(0.55, 0.45, 1.0).normalized())
	var dist: float
	if flat:
		# Fill the picture: whichever of width and height is the tighter fit.
		dist = maxf(box.size.y * 0.5 / tan(half_v), box.size.x * 0.5 / (tan(half_v) * aspect)) * 1.02
	else:
		dist = box.size.length() * 0.5 / sin(half_v) * 1.1  # its bounding sphere, with a margin
	cam.near = maxf(dist * 0.01, 0.01)
	cam.far = dist * 4.0 + box.size.length()
	cam.global_position = center + dir * dist
	cam.look_at(center, Vector3.UP)


## A colour test card with a checkered band: what screens and effects show.
static func test_card() -> Texture2D:
	if _card != null:
		return _card
	var img := Image.create(320, 180, false, Image.FORMAT_RGB8)
	for y in 180:
		for x in 320:
			var c := Color.from_hsv(float(x) / 320.0, 0.75, 0.4 + 0.6 * float(y) / 180.0)
			if y > 124 and (x / 20 + y / 20) % 2 == 0:
				c = Color(0.95, 0.95, 0.95)
			img.set_pixel(x, y, c)
	_card = ImageTexture.create_from_image(img)
	return _card


## Music for sound-reactive layers, made up: a falling spectrum with a kick
## on every beat at 120 BPM and a wobbling waveform.
class FakeAudio extends AudioAnalyzer:
	## The time to play at, when set (a loop's frames); else it runs on.
	var clock := -1.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t = clock if clock >= 0.0 else _t + delta
		var kick := pow(maxf(0.0, 1.0 - fmod(_t, 0.5) * 3.0), 2.0)
		for i in BINS:
			var f := float(i) / BINS
			var v := clampf(0.85 - f * 0.9 + kick * (0.35 - f * 0.3) + 0.08 * sin(_t * 5.0 + f * 40.0), 0.0, 1.0)
			_bytes[i] = int(v * 255.0)
			_bytes[BINS + i] = int(clampf(0.5 + 0.35 * sin(f * TAU * 6.0 + _t * 9.0) * (0.4 + kick), 0.0, 1.0) * 255.0)
		bass = 0.5 + kick * 0.5
		mid = 0.45
		high = 0.25
		level = 0.4 + kick * 0.4
		_image.set_data(BINS, 2, false, Image.FORMAT_R8, _bytes)
		texture.update(_image)
