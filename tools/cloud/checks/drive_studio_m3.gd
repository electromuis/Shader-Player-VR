extends SceneTree

## Studio M3 end to end, on a copy of forest_tunnel: select the main screen
## and retune its glow in the inspector (a still value into the config, an
## animated one held unkeyed and then keyed with its diamond, a key with auto-key on, a diamond tap, the
## tint on the colour wheel), add an effect and move it up, switch one off
## and on (its keys go with it), undo / redo, then save and play the result
## in the player. The inspector's own controls are driven (their signals,
## as a click or a drag sends them). Headless (HEADLESS=1) it prints;
## rendered it also saves studio_m3_*.png to OUT_DIR: the desktop with the
## inspector, the add-effect menu and colour wheel, and the headset panel
## beside the screen (its picture, and in the world).

var studio: Node
var tools: StudioEditTools
var view: StudioInspector
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"
var card: ImageTexture


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(code: Key, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		studio.stage.router.handle_key(ev)
	await frames(2)


## The inspector's row for a field key ("effect1/radius", "tint", ...).
func row(field_key: String, in_view: StudioInspector = null) -> Dictionary:
	for r in (in_view if in_view != null else view)._rows:
		if r.field.key == field_key:
			return r
	return {}


## Drag a row's slider to `value`, as the pointer or mouse would.
func drag(field_key: String, value: float) -> void:
	var s: HSlider = row(field_key).controls[0]
	s.drag_started.emit()
	s.value = value
	s.drag_ended.emit(true)
	await frames(3)


## The first button in the inspector whose text starts with `text`.
func button(text: String, from: Node = null) -> Button:
	for c in (from if from != null else view).find_children("*", "Button", true, false):
		if (c as Button).text.begins_with(text) and c.is_visible_in_tree():
			return c
	return null


func click(text: String, from: Node = null) -> void:
	var b := button(text, from)
	if b == null:
		print("  (no button '%s')" % text)
		return
	b.pressed.emit()
	await frames(3)


## Effect `index`'s row in the pixel effects list ({list, index, switch, ...}).
func effect_row(index: int) -> Dictionary:
	for r in view._fx_rows:
		if r.list == EditModel.EFFECTS and r.index == index:
			return r
	return {}


func settings() -> Dictionary:
	return studio.model.config_of("main_screen")


func glow_params() -> Dictionary:
	return settings().effects[1].params


func track_keys(target: String, param: String) -> Array:
	var ti: int = studio.model.find_track("shader_param", target, param)
	return studio.model.tracks()[ti].keyframes.map(func(k): return [snappedf(float(k.t), 0.01), snappedf(float(k.value), 0.001)]) if ti >= 0 else []


func param_tracks(id: String) -> Array:
	var out_list: Array = []
	for t in studio.model.tracks():
		if t.get("type") == "shader_param" and String(t.target).begins_with(id + "."):
			out_list.append("%s:%s" % [String(t.target).substr(id.length() + 1), t.param])
	out_list.sort()
	return out_list


func stack() -> Array:
	return settings().effects.map(func(e): return e.shader + ("" if e.get("enabled", true) else " (off)"))


func put_card() -> void:
	if card == null:
		var img := Image.create(640, 360, false, Image.FORMAT_RGB8)
		for y in 360:
			for x in 640:
				var c := Color.from_hsv(float(x) / 640.0, 0.8, 0.35 + 0.65 * float(y) / 360.0)
				if (x / 40 + y / 40) % 2 == 0 and y > 250:
					c = Color(0.95, 0.95, 0.95)
				img.set_pixel(x, y, c)
		card = ImageTexture.create_from_image(img)
	var reg: ObjectRegistry = studio.runner.registry()
	for id in reg.all_ids():
		var n = reg.get_node_by_id(id)
		if n is Screen:
			n.set_source_texture(card)


func shot(name: String) -> void:
	if not rendered:
		return
	put_card()
	await frames(20)
	root.get_texture().get_image().save_png(out.path_join("studio_m3_%s.png" % name))


func copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for d in DirAccess.get_directories_at(from):
		copy_dir(from.path_join(d), to.path_join(d))


func _initialize() -> void:
	var repo := OS.get_environment("REPO")
	var piece_dir := OS.get_environment("WORK").path_join("studio_m3_piece")
	copy_dir(repo.path_join("scripts/forest_tunnel"), piece_dir)
	var piece := piece_dir.path_join("video.spscript")

	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	tools = studio.tools
	view = studio.inspector
	var reg: ObjectRegistry = studio.runner.registry()
	if not reg.object_spawned.is_connected(studio.stage._on_object_spawned):
		reg.object_spawned.connect(studio.stage._on_object_spawned)
	print("open: ", studio.open_piece(piece))
	studio.runner.set_video_duration(200.0)
	studio.stage.seek_to(20.0)
	await frames(5)
	var cam: Camera3D = studio.stage.desktop_camera
	cam.global_position = Vector3(0, 2, 8)
	cam.look_at(Vector3(0, 2.6, 0))
	print("inspector with nothing selected: visible ", view.visible)

	tools.select("main_screen")
	await frames(4)
	print("selected main_screen: inspector visible ", view.visible, ", sections ",
			view._list.get_children().filter(func(c): return c is HBoxContainer).map(func(h): return h.get_child(0).text))
	view.set_section_open("effect1", true)
	await frames(3)
	var screen: Node = reg.get_node_by_id("main_screen")
	var backdrop: Node = reg.get_node_by_id("backdrop")
	print("glow rows: ", view._rows.filter(func(r): return String(r.field.key).begins_with("effect1/")).size(),
			", tint is a ", row("effect1/tint").kind, ", radius shows ", row("effect1/radius").value.text)
	await shot("0_inspector")

	# A still value, auto-key off: the spawn config, both spawns of the screen.
	print("glow radius before: ", glow_params().radius)
	await drag("effect1/radius", 0.9)
	var spawns: Array = studio.model.spawn_indices("main_screen")
	print("radius dragged to 0.9: '", studio.message, "' config ", glow_params().radius, ", second spawn ",
			studio.model.tracks()[spawns[1]].config.effects[1].params.radius)
	var now_screen: Node = reg.get_node_by_id("main_screen")
	print("screen respawned: ", now_screen != screen, ", its backdrop child still there: ", reg.has_id("backdrop"),
			" (under it: ", reg.get_node_by_id("backdrop").get_parent() == now_screen if reg.has_id("backdrop") else false, ")")
	print("the screen shows radius ", now_screen._effect_params[1].get("radius") if now_screen is Screen else "?")

	# Animated, auto-key off, between keys: held unkeyed (the keys stay),
	# then its diamond keys it (TODO 61; it used to move the whole track).
	print("intensity keys before: ", track_keys("main_screen.effect1", "intensity"), " value at 20 s ", row("effect1/intensity").value.text)
	var at20: float = studio.edits.value_of("main_screen", row("effect1/intensity").field, 20.0)
	await drag("effect1/intensity", at20 + 0.4)
	print("intensity +0.4: '", studio.message, "' keys ", track_keys("main_screen.effect1", "intensity"),
			", diamond '", row("effect1/intensity").diamond.text, "' ", studio.edits.key_state("main_screen", row("effect1/intensity").field, studio.runner.playhead))
	row("effect1/intensity").diamond.pressed.emit()
	await frames(8)
	print("its diamond: '", studio.message, "' keys ", track_keys("main_screen.effect1", "intensity"))

	# Auto-key on: a key at the playhead.
	await key(KEY_I, false, true)
	await frames(8)
	print("shift+i: auto-key ", tools.auto_key, ", hint '", view._hint.text, "'")
	print("saturation keys before: ", track_keys("main_screen.effect1", "saturation"))
	await drag("effect1/saturation", 1.2)
	print("saturation to 1.2: '", studio.message, "' keys ", track_keys("main_screen.effect1", "saturation"))
	await key(KEY_I, false, true)

	# The diamond: tap to key where it is, tap again to remove it.
	await frames(8)
	print("mirror diamond: '", row("effect1/mirror").diamond.text, "'")
	row("effect1/mirror").diamond.pressed.emit()
	await frames(8)
	print("tap: '", studio.message, "' keys ", track_keys("main_screen.effect1", "mirror"), ", diamond '", row("effect1/mirror").diamond.text, "'")
	row("effect1/mirror").diamond.pressed.emit()
	await frames(8)
	print("tap again: '", studio.message, "' keys ", track_keys("main_screen.effect1", "mirror"))

	# The tint on the colour wheel: written once it's closed.
	row("effect1/tint").controls[0].pressed.emit()
	await frames(4)
	var picker: ColorPicker = row("effect1/tint").controls[1]
	picker.color = Color(1.0, 0.55, 0.2)
	picker.color_changed.emit(picker.color)
	await frames(3)
	print("colour wheel open (", picker.picker_shape == ColorPicker.SHAPE_HSV_WHEEL, "), tint so far ", glow_params().tint)
	await shot("1_colour_wheel")
	row("effect1/tint").controls[0].pressed.emit()
	await frames(4)
	print("closed: '", studio.message, "' tint ", glow_params().tint.map(func(x): return snappedf(x, 0.01)))

	# Add an effect, then move it up one.
	print("stack: ", stack(), " tracks ", param_tracks("main_screen"))
	await click("+ Add effect")
	await shot("2_add_effect")
	await click("Rounded corners")
	print("added: '", studio.message, "' stack ", stack())
	# ↑ / ↓ are gone: its ≡ dropped on the row above.
	print("moved up: ", view.drop_effect(EditModel.EFFECTS, 4, 3), " '", studio.message, "' stack ", stack(), " tracks ", param_tracks("main_screen"))

	# Switch the oval mask off: its size keys go with it; back on, they return.
	(effect_row(2).switch as Button).toggled.emit(false)
	await frames(4)
	print("oval off: '", studio.message, "' stack ", stack(), " tracks ", param_tracks("main_screen"),
			" parked ", settings().effects[2].get("tracks", []).map(func(t): return t.param))
	print("the screen runs ", now_screen._effect_keys.map(func(k): return k.get_file().get_basename()) if is_instance_valid(now_screen) else
			reg.get_node_by_id("main_screen")._effect_keys.map(func(k): return k.get_file().get_basename()))
	(effect_row(2).switch as Button).toggled.emit(true)
	await frames(4)
	print("oval on: '", studio.message, "' tracks ", param_tracks("main_screen"))

	# Undo / redo through all of it.
	await key(KEY_Z, true)
	print("ctrl+z: '", studio.message, "' stack ", stack())
	await key(KEY_Z, true, true)
	print("ctrl+shift+z: '", studio.message, "' stack ", stack())
	view.set_section_open("effect3", true)
	view.set_section_open("effect1", false)
	await frames(4)
	await shot("3_stack")

	# The headset panel: beside the screen, turned to you.
	studio.inspector_panel.visible = true
	studio._place_inspector_panel()
	await frames(6)
	var vr_view: StudioInspector = studio._vr_inspector()
	print("headset inspector: ", vr_view != null, ", big text ", vr_view.vr if vr_view != null else false,
			", panel at ", studio.inspector_panel.global_position.snapped(Vector3(0.01, 0.01, 0.01)))
	if vr_view != null:
		vr_view.set_section_open("effect1", true)
		vr_view.set_section_open("Transform", false)
		await frames(6)
	if rendered:
		var sub: SubViewport = studio.inspector_panel.get_node("Viewport")
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await frames(6)
		sub.get_texture().get_image().save_png(out.path_join("studio_m3_4_headset_panel.png"))
		view.visible = false
		# Behind the head it was placed from (the seat), to see both.
		cam.global_position = Vector3(-0.6, 2.25, 9.8)
		cam.look_at(Vector3(0.35, 2.0, 5.5))
		await shot("5_headset_world")

	await key(KEY_S, true)
	print("save: '", studio.message, "' valid ", ScriptFormat.load_from_file(piece).ok)
	var saved := settings()
	studio.queue_free()
	await frames(3)

	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var preg: ObjectRegistry = main.runner.registry()
	if not preg.object_spawned.is_connected(main.stage._on_object_spawned):
		preg.object_spawned.connect(main.stage._on_object_spawned)
	main.open_file(piece, false)
	main.runner.set_video_duration(200.0)
	main.runner.seek(20.0)
	await frames(3)
	var ps: Screen = preg.get_node_by_id("main_screen")
	print("player at 20 s: effects ", ps._effect_keys.map(func(k): return k.get_file().get_basename()),
			", glow radius ", ps._effect_params[1].get("radius"), " (saved ", saved.effects[1].params.radius, ")",
			", tint ", ps._effect_params[1].get("tint"))
	print("STUDIO M3 DONE")
	quit()
