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
## A look's picture is different: a snapshot of the object on stage when
## the look was saved (snapshot()), kept next to the look's file
## (StudioLooks.picture_path). Studio's own helpers (lines, panels, the
## carried card) are on HELPER_LAYER, which snapshots leave out.

## A thumbnail is ready (or came off the disk).
signal thumbnail_ready(asset_id: String, texture: Texture2D)

const SIZE := Vector2i(256, 160)
const FRAMES := 10
## Bump when the pictures change, so old ones are drawn again.
const VERSION := 1
const CACHE_DIR := "user://thumbnails"
## The render layer (1-based) of Studio's helpers: every camera sees it but
## a snapshot's.
const HELPER_LAYER := 20
const SCREEN_SCENE := preload("res://player/prefabs/screen.tscn")
const LAYER_SCENE := preload("res://player/prefabs/layer.tscn")

var _textures := {}  # asset id -> Texture2D
var _queue: Array = []
var _busy := false
static var _card: Texture2D


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


static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Where the asset's picture is kept.
static func cache_path(asset: Dictionary) -> String:
	var path := String(asset.path)
	var stamp := "%s|%s|%d|%d" % [asset.type, path, FileAccess.get_modified_time(path), VERSION]
	return CACHE_DIR.path_join(stamp.md5_text() + ".png")


func is_busy() -> bool:
	return _busy or not _queue.is_empty()


func _process(_delta: float) -> void:
	if _busy or _queue.is_empty():
		return
	_render(_queue.pop_front())


func _render(asset: Dictionary) -> void:
	_busy = true
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
		_:
			var packed := ResourceLoader.load(asset.path, "PackedScene") as PackedScene
			node = packed.instantiate() as Node3D if packed != null else null
			if node == null:
				node = Node3D.new()
			vp.add_child(node)
			if node is Screen:
				(node as Screen).set_source_texture(test_card())
	for i in 2:
		await get_tree().process_frame
	_frame(cam, node, asset.kind in ["screen", "layer", "effect"])
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
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
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
