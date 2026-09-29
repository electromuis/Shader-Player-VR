extends SceneTree

## The shelf's animated cards (TODO 18) in the real Studio: a layer card
## under the pointer plays its loop, and stops when the pointer leaves; an
## effect that doesn't move (Blur) keeps its still; `play_all` (the
## headset's shelf) plays every card of the tab; a loop comes back off the
## disk; drawing loops leaves the stage's shader time alone. Prints what
## happened; rendered, saves studio_loops_*.png to OUT_DIR (a few frames
## of some loops, and the shelf with a card playing).

var studio: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func asset(type: String, file: String) -> Dictionary:
	for a in studio.library.of_type(type):
		if String(a.path).get_file().get_basename() == file:
			return a
	return {}


## The most a loop's frames differ from its first (StudioThumbnailer.difference).
func most_change(strip: Texture2D) -> float:
	if strip == null:
		return -1.0
	var img := strip.get_image()
	var sz := StudioThumbnailer.SIZE
	var first := img.get_region(Rect2i(Vector2i.ZERO, sz))
	var most := 0.0
	for i in range(1, StudioThumbnailer.frames_of(strip)):
		most = maxf(most, StudioThumbnailer.difference(img.get_region(Rect2i(Vector2i(i * sz.x, 0), sz)), first))
	return most


func settle() -> void:
	for i in 3000:
		await process_frame
		if not studio.thumbnailer.is_busy():
			break
	await frames(3)


func _initialize() -> void:
	var dir := OS.get_environment("WORK").path_join("studio_loops/piece")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("clip.json"))
	var f := FileAccess.open(dir.path_join("clip.mp4"), FileAccess.WRITE)
	f.store_string("a stand-in: nothing here decodes video")
	f.close()
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	studio.open_piece(dir.path_join("clip.mp4"))
	await frames(6)
	studio.runner.set_video_duration(30.0)
	studio.shelf_on = true
	studio._show_shelf()
	var shelf: StudioAssetShelf = studio.shelf
	var thumbs: StudioThumbnailer = studio.thumbnailer
	shelf.show_tab("layer")
	await frames(4)
	await settle()
	var time_before := MediaTime.seconds

	# The pointer over a layer card.
	var tunnel := asset("layer", "beat_tunnel")
	var card := shelf.card(tunnel.id)
	card.mouse_entered.emit()
	print("hovered: ", shelf.hover_id == tunnel.id)
	await settle()
	await frames(2)
	var strip := thumbs.loop(tunnel)
	print("beat_tunnel loop: ", StudioThumbnailer.frames_of(strip) if strip != null else 0, " frames",
			"; playing: ", shelf.playing().map(func(id): return String(id).get_file()))
	var image: TextureRect = shelf._cards[tunnel.id].image
	var seen := {}
	for i in 12:
		await frames(3)
		if image.texture is AtlasTexture:
			seen[(image.texture as AtlasTexture).region.position.x] = true
	print("frames shown over 36 frames: ", seen.size())
	if rendered:
		var shots: Array[Image] = []
		for i in 3:
			await frames(4 if i == 0 else 7)
			var img := root.get_texture().get_image()
			shots.append(img.get_region(Rect2i(shelf.get_global_rect())))
		var sheet := Image.create(shots[0].get_width() * 3 + 20, shots[0].get_height(), false, shots[0].get_format())
		sheet.fill(Color(0.02, 0.02, 0.03))
		for i in 3:
			sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, shots[i].get_size()), Vector2i((shots[0].get_width() + 10) * i, 0))
		sheet.save_png(out.path_join("studio_loops_1_hover.png"))
	card.mouse_exited.emit()
	await frames(2)
	print("pointer gone: playing ", shelf.playing().size(), ", still back: ", not (image.texture is AtlasTexture))

	# Effects: one that moves and one that doesn't.
	shelf.show_tab("effect")
	await frames(3)
	var picked := [asset("layer", "beat_tunnel")]
	for pair in [["effect", "kaleidoscope"], ["effect", "liquid_warp"], ["effect", "hue_cycle"], ["effect", "blur"],
			["vertex", "ripple"]]:
		var a := asset(pair[0], pair[1])
		if a.is_empty():
			print("no ", pair[1])
			continue
		thumbs.loop(a)
		picked.append(a)
	await settle()
	for a in picked:
		print(String(a.path).get_file(), ": ", StudioThumbnailer.frames_of(thumbs.loop(a)), " frames, differs by up to ",
				"%.4f" % most_change(thumbs.loop(a)))
	var blur := asset("effect", "blur")
	shelf.card(blur.id).mouse_entered.emit()
	await frames(3)
	print("Blur hovered: playing ", shelf.playing().size(), " (a still doesn't play)")
	shelf.card(blur.id).mouse_exited.emit()

	# The headset's shelf: every card.
	shelf.show_tab("layer")
	await frames(3)
	shelf.play_all = true
	await frames(2)
	print("play_all: asked for ", shelf._asked.size() + shelf.playing().size(), " of ", studio.library.of_type("layer").size())
	await settle()
	await frames(3)
	print("play_all: playing ", shelf.playing().size(), " of ", studio.library.of_type("layer").size(), "; stills: ",
			studio.library.of_type("layer").filter(func(a): return not shelf.playing().has(a.id)).map(
				func(a): return "%s (%.4f)" % [String(a.path).get_file(), most_change(thumbs.loop(a))]))
	if rendered:
		await frames(5)
		root.get_texture().get_image().get_region(Rect2i(shelf.get_global_rect())).save_png(out.path_join("studio_loops_2_all.png"))
	shelf.play_all = false
	await frames(2)
	print("play_all off: playing ", shelf.playing().size())

	# Off the disk, in a fresh thumbnailer.
	var fresh := StudioThumbnailer.new()
	root.add_child(fresh)
	var again := fresh.loop(tunnel)
	print("off the disk: ", StudioThumbnailer.frames_of(again) if again != null else 0, " frames, queued ", fresh.is_busy())
	fresh.queue_free()

	print("stage time untouched: ", MediaTime.seconds == time_before)
	print("preview code: ", StudioThumbnailer.preview_code("shader_type canvas_item;\nvoid fragment() { COLOR.r = TIME; }").split("\n").slice(1, 4))

	if rendered:
		# Five frames of each loop, one row per asset.
		var step := 4
		var cols := StudioThumbnailer.LOOP_FRAMES / step
		var sz := StudioThumbnailer.SIZE
		var sheet := Image.create((sz.x + 6) * cols, (sz.y + 6) * picked.size(), false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.02, 0.02, 0.03))
		for r in picked.size():
			var s := thumbs.loop(picked[r])
			if s == null:
				continue
			var img := s.get_image()
			img.convert(Image.FORMAT_RGBA8)
			var n := StudioThumbnailer.frames_of(s)
			for c in cols:
				var fi := mini(c * step, n - 1)
				sheet.blit_rect(img, Rect2i(Vector2i(fi * sz.x, 0), sz), Vector2i((sz.x + 6) * c, (sz.y + 6) * r))
		sheet.save_png(out.path_join("studio_loops_3_frames.png"))
	print("STUDIO LOOPS DONE")
	quit()
