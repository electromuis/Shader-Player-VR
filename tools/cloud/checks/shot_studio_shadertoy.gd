extends SceneTree

## The shelf's Shadertoy tab (TODO 17) in the real Studio: the collection
## as cards (the site's thumbnails, what won't run), the filter, Paste (a
## link opens the page for the extension, code goes straight in), a shader
## arriving from the extension, then one card made a layer and dropped in
## the space and another made an effect and dropped on the main screen,
## and the piece saved with both copied in. Prints what happened (Godot's
## "SHADER ERROR" lines would follow a conversion that doesn't compile);
## rendered, saves studio_shadertoy_*.png to OUT_DIR.
##
## The collection: $ST_LIBRARY, a folder of Shadertoy JSONs (the
## collection's own files, or the site's; thumbnails as <name>_<id>.jpg),
## copied, or two made-up shaders without it. $ST_LAYER and $ST_EFFECT name
## the shaders (ids) to make a layer and an effect (default: the first that
## runs, and the first that reads a picture).

const LAYER_CODE := "void mainImage(out vec4 o, in vec2 f) {\n\tvec2 uv = (f - 0.5 * iResolution.xy) / iResolution.y;\n\tfloat r = length(uv), a = atan(uv.y, uv.x);\n\tfloat bass = texture(iChannel0, vec2(0.05, 0.25)).x;\n\to = vec4(0.5 + 0.5 * cos(iTime + 8.0 * r - 3.0 * bass + vec3(0, 2, 4) + a), 1.0);\n}\n"
const EFFECT_CODE := "void mainImage(out vec4 o, in vec2 f) {\n\tvec2 uv = f / iResolution.xy;\n\tuv.x += 0.02 * sin(uv.y * 40.0 + iTime * 3.0);\n\to = texture(iChannel0, uv) * (0.85 + 0.15 * sin(f.y * 1.5));\n}\n"

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String, shelf_only := false) -> void:
	if not rendered:
		return
	await frames(8)
	var img := root.get_texture().get_image()
	if shelf_only:
		img = img.get_region(Rect2i(studio.shelf.get_global_rect()))
	img.save_png(out.path_join("studio_shadertoy_%s.png" % name))


func ray_at(at: Vector2) -> Transform3D:
	var cam: Camera3D = studio.stage.desktop_camera
	var dir := cam.project_ray_normal(at * Vector2(root.size))
	return Transform3D(Basis.looking_at(dir, Vector3.UP), cam.project_ray_origin(at * Vector2(root.size)))


func settle() -> void:
	for i in 3000:
		await process_frame
		if not studio.thumbnailer.is_busy():
			break
	await frames(3)


func card_named(id: String) -> Dictionary:
	for a in studio.library.of_type("shadertoy"):
		if String(a.path).get_basename().ends_with("_" + id) or ShadertoyShader.parse(FileAccess.get_file_as_string(a.path)).id == id:
			return a
	return {}


func _initialize() -> void:
	var work := OS.get_environment("WORK").path_join("studio_shadertoy")
	var dir := work.path_join("piece")
	var st_dir := work.path_join("collection")
	for d in [dir, dir.path_join("shaders"), st_dir]:
		DirAccess.make_dir_recursive_absolute(d)
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	var src := OS.get_environment("ST_LIBRARY")
	var lib := ShadertoyLibrary.new(st_dir)
	if src != "":
		for file in DirAccess.get_files_at(src):
			if file.get_extension() in ["json", "jpg"]:
				DirAccess.copy_absolute(src.path_join(file), st_dir.path_join(file))
	else:
		lib.add(ShadertoyShader.from_code(LAYER_CODE, "Rings"))
		lib.add(ShadertoyShader.from_code(EFFECT_CODE, "Wobble"))
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	studio.set_shadertoy_dir(st_dir)
	var urls: Array = []
	studio.shelf.open_url = func(url: String): urls.append(url)
	# What this check makes, made fresh.
	var made_dir: String = studio.library.library_dirs[0].path_join("shaders")
	for e in lib.entries():
		for suffix in ["", StudioShadertoy.EFFECT_SUFFIX]:
			DirAccess.remove_absolute(made_dir.path_join(ShadertoyShader.file_stem(e.shader) + suffix + ".gdshader"))
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(30.0)
	studio.stage.desktop_camera.set_view(Vector3(0, 1.7, 12), Vector3(-6, 0, 0))
	studio.status_view.show_hints(false)
	studio.shelf_on = true
	studio._show_shelf()
	var shelf: StudioAssetShelf = studio.shelf
	shelf.show_tab("shadertoy")
	await frames(4)
	await settle()
	var cards: Array = studio.library.of_type("shadertoy")
	print("cards: ", cards.size())
	for a in cards:
		var notes := StudioAssetShelf._shadertoy_notes(a)
		print("  %s by %s: layer %s, effect %s, picture %s" % [a.label, a.author,
				"ok" if notes[0].ok and notes[0].edits.is_empty() else ("needs editing" if notes[0].ok else "won't run"),
				"reads the picture" if not notes[1].warnings.any(func(w): return "doesn't read a picture" in w) else "covers it",
				"yes" if a.picture != "" else "no"])
	print("status: ", shelf.extension_status())
	await shot("1_tab", true)

	shelf._st_filter_edit.text = "tunnel"
	shelf._st_filter_edit.text_changed.emit("tunnel")
	await frames(3)
	print("filter 'tunnel': ", shelf._cards.values().map(func(c): return c.asset.label))
	await shot("2_filter", true)
	shelf.search_shadertoy()
	shelf._st_filter_edit.text = ""
	shelf._st_filter_edit.text_changed.emit("")

	var r: Dictionary = shelf.paste_shadertoy("https://www.shadertoy.com/view/XsXXDn")
	print("paste a link: ", r.kind, " -> opened ", urls, "; said '", studio.message, "'")
	r = shelf.paste_shadertoy("void mainImage(out vec4 o, in vec2 f) { o = vec4(f.x / iResolution.x, 0.2, 0.6, 1.0); }")
	print("paste code: ", r.kind, "; said '", studio.message, "'")
	r = shelf.paste_shadertoy("nothing useful")
	print("paste text: ", r.kind, "; said '", studio.message, "'")

	# The extension sends one (what its POST does, without the socket).
	shelf.show_tab("layer")
	var rx: ShadertoyReceiver = studio.shadertoy_receiver
	print("receiver listening: ", rx.is_listening(), " on ", rx.port)
	var sent := {"info": {"id": "Sent01", "name": "Sent from Chrome", "username": "someone"},
			"renderpass": [{"type": "image", "name": "Image", "inputs": [], "code": LAYER_CODE}]}
	var body := JSON.stringify({"shader": [sent], "thumbnail": ""})
	var res: Array = rx.handle({"method": "POST", "path": "/vj/shadertoy", "body": body.to_utf8_buffer(),
			"headers": {"host": "127.0.0.1:%d" % rx.port, "origin": "chrome-extension://x", "content-type": "application/json"}})
	await frames(4)
	print("sent: ", res[0], " ", res[1].get("app"), "; tab now ", shelf.tab, "; said '", studio.message, "'; cards ",
			studio.library.of_type("shadertoy").size())

	# A layer, dropped in the space.
	var layer_card := card_named(OS.get_environment("ST_LAYER"))
	var effect_card := card_named(OS.get_environment("ST_EFFECT"))
	for a in studio.library.of_type("shadertoy"):
		var notes := StudioAssetShelf._shadertoy_notes(a)
		if layer_card.is_empty() and notes[0].ok and notes[0].edits.is_empty():
			layer_card = a
		if effect_card.is_empty() and notes[1].ok and notes[1].edits.is_empty() \
				and ShadertoyShader.input_channel(ShadertoyShader.parse(FileAccess.get_file_as_string(a.path))) >= 0:
			effect_card = a
	studio.runner.seek(6.0)
	var main: Screen = studio.runner.registry().get_node_by_id("main_screen")
	var layer: Dictionary = shelf.take_shadertoy(layer_card, false)
	print("layer from '%s': %s (%s)" % [layer_card.label, layer.get("path", "").get_file(), studio.message])
	studio.set_process(false)
	studio.show_carry(ray_at(Vector2(0.37, 0.6)))
	print("  carried: ", studio.message)
	studio.drop_held_at(ray_at(Vector2(0.37, 0.6)))
	studio.set_process(true)
	var layer_id: String = studio.tools.selected
	print("  dropped: ", layer_id, " '", studio.message, "'")
	# An effect, dropped on the main screen.
	var effect: Dictionary = shelf.take_shadertoy(effect_card, true)
	print("effect from '%s': %s" % [effect_card.label, effect.get("path", "").get_file()])
	studio.set_process(false)
	var on_screen := Vector2(0.62, 0.3)
	studio.show_carry(ray_at(on_screen))
	print("  carried: ", studio.message)
	studio.drop_held_at(ray_at(on_screen))
	studio.set_process(true)
	print("  dropped: '", studio.message, "'")
	await settle()
	# The stand-in video shows "could not open": a test card instead.
	if main != null:
		main.set_source_texture(StudioThumbnailer.test_card())
	await frames(3)
	await shot("3_stage")
	# The effect is one of yours now: the end of the Effects tab.
	shelf.show_tab("effect")
	await frames(3)
	await settle()
	await frames(3)
	shelf._scroll.scroll_vertical = 100000
	await shot("4_effects_tab", true)

	# A Shadertoy card under the pointer plays its loop (drawn from the
	# conversion, as a layer or as an effect on the test card).
	shelf.show_tab("shadertoy")
	await frames(3)
	for a in [effect_card, layer_card]:
		shelf.card(a.id).mouse_entered.emit()
		await frames(2)
		await settle()
		await frames(2)
		var strip: Texture2D = studio.thumbnailer.loop(a)
		print("%s hovered: loop of %d frames, playing %s" % [a.label, StudioThumbnailer.frames_of(strip),
				shelf.playing().has(a.id)])
		shelf.card(a.id).mouse_exited.emit()
	if rendered:
		var picked := [effect_card, layer_card]
		var sz := StudioThumbnailer.SIZE
		var sheet := Image.create((sz.x + 6) * 5, (sz.y + 6) * picked.size(), false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.02, 0.02, 0.03))
		for row in picked.size():
			var s: Texture2D = studio.thumbnailer.loop(picked[row])
			if s == null:
				continue
			var img := s.get_image()
			img.convert(Image.FORMAT_RGBA8)
			for c in 5:
				var fi := mini(c * 4, StudioThumbnailer.frames_of(s) - 1)
				sheet.blit_rect(img, Rect2i(Vector2i(fi * sz.x, 0), sz), Vector2i((sz.x + 6) * c, (sz.y + 6) * row))
		sheet.save_png(out.path_join("studio_shadertoy_5_loops.png"))

	# The headset's shelf: the same scene, bigger (Studio.SHELF_PIXELS).
	if rendered:
		var vp := SubViewport.new()
		vp.size = Vector2i(studio.SHELF_PIXELS)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var big: StudioAssetShelf = load("res://studio/ui/asset_shelf.tscn").instantiate()
		big.library = studio.library
		big.thumbnailer = studio.thumbnailer
		big.receiver = studio.shadertoy_receiver
		studio.thumbnailer.thumbnail_ready.connect(big.on_thumbnail)
		vp.add_child(big)
		big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		big.show_tab("shadertoy")
		await frames(4)
		await settle()
		await frames(6)
		vp.get_texture().get_image().save_png(out.path_join("studio_shadertoy_6_headset.png"))
		vp.queue_free()

	print("saved: ", studio.save())
	var named := {}
	for m in RegEx.create_from_string('"(shaders/[^"]+)"').search_all(FileAccess.get_file_as_string(dir.path_join("clip.spscript"))):
		named[m.get_string(1)] = true
	print("the piece names: ", named.keys())
	print("in the piece's shaders/: ", DirAccess.get_files_at(dir.path_join("shaders")))
	DirAccess.remove_absolute(AppPaths.save_path(StudioSettings.FILE_NAME))
	print("STUDIO SHADERTOY DONE")
	quit(0)
