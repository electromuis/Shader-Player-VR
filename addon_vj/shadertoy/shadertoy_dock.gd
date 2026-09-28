@tool
extends VBoxContainer

## The Shadertoy dock: the shaders you've sent from shadertoy.com with the
## Chrome extension (tools/shadertoy_extension), or pasted / loaded here.
## Pick one to see it running (with made-up music, so reactive shaders
## move) and what won't work in the player; **Add as layer** saves it as
## `res://shaders/shadertoy/<name>_<id>.gdshader` and puts a layer with it
## in the open VJ scene (undoable); the exporter copies the shader into the
## piece like any other. The conversion is ShadertoyShader, the collection
## ShadertoyLibrary (shared with Studio), and the plugin runs the
## ShadertoyReceiver the extension sends to.

const ShaderCode := preload("res://addons/vj_editor/shadertoy/shadertoy_shader.gd")
const Library := preload("res://addons/vj_editor/shadertoy/shadertoy_library.gd")
const LAYER_SCENE := "res://addons/vj_editor/builtin_prefabs/layer.tscn"
const INCLUDE_DIR := "res://addons/vj_editor/visualizer"
const SHADER_DIR := "res://shaders/shadertoy"
const PREVIEW_SIZE := Vector2i(384, 216)
const THUMB_SIZE := Vector2i(160, 90)
## The extension pings on every Shadertoy page; this long after the last
## one it counts as gone.
const CONNECTED_MSEC := 20000
## Where a new layer goes: in front of the viewer's home (0, 2, 8), 16 × 9 m.
const LAYER_TRANSFORM := Transform3D(Vector3(0.5, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 0, 0.5), Vector3(0, 4.5, -10))

var library: Library
var receiver: Node
var undo_redo: EditorUndoRedoManager

var _status: Label
var _filter: LineEdit
var _list: ItemList
var _body: SplitContainer
var _details: BoxContainer
var _frame: AspectRatioContainer
var _thumb: TextureRect
var _preview_rect: ColorRect
var _preview_vp: SubViewport
var _title: LinkButton
var _byline: Label
var _notes: RichTextLabel
var _add_button: Button
var _save_button: Button
var _message: Label
var _entries: Array = []
var _selected_id := ""
var _stamp := -1
var _audio_img: Image
var _audio_tex: ImageTexture
var _poll := 0.0


func _init() -> void:
	name = "Shadertoy"
	custom_minimum_size = Vector2(260, 0)


func _ready() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_status)
	var site := Button.new()
	site.text = "shadertoy.com"
	site.tooltip_text = "Browse shaders there; the Chrome extension adds a Send to Godot button."
	site.pressed.connect(func(): OS.shell_open(ShaderCode.SITE + "/browse"))
	top.add_child(site)
	var more := MenuButton.new()
	more.text = "⋯"
	more.flat = false
	more.tooltip_text = "Paste, load a file, open the collection's folder"
	var menu := more.get_popup()
	menu.add_item("Paste JSON or code", 0)
	menu.add_item("Load JSON / zip…", 1)
	menu.add_separator()
	menu.add_item("Open the collection's folder", 2)
	menu.id_pressed.connect(_on_menu)
	top.add_child(more)

	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter by name, author or tag"
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t): _fill_list())
	add_child(_filter)

	# Side by side when there's width (the bottom panel), stacked when
	# not (a side dock): see _relayout.
	_body = SplitContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_list = ItemList.new()
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.max_columns = 0
	_list.same_column_width = true
	_list.fixed_icon_size = THUMB_SIZE
	_list.fixed_column_width = THUMB_SIZE.x + 8
	_list.max_text_lines = 2
	_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = THUMB_SIZE + Vector2i(24, 50)
	_list.item_selected.connect(func(i): _select(String(_list.get_item_metadata(i))))
	_body.add_child(_list)

	_details = BoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_details)
	_frame = AspectRatioContainer.new()
	_frame.ratio = float(PREVIEW_SIZE.x) / PREVIEW_SIZE.y
	_frame.custom_minimum_size = Vector2(0, 120)
	_details.add_child(_frame)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	_frame.add_child(holder)
	_preview_vp = SubViewport.new()
	_preview_vp.size = PREVIEW_SIZE
	_preview_vp.disable_3d = true
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	holder.add_child(_preview_vp)
	_preview_rect = ColorRect.new()
	_preview_rect.color = Color.BLACK
	_preview_rect.size = PREVIEW_SIZE
	_preview_vp.add_child(_preview_rect)
	# For shaders that can't run: the site's picture instead of garbage.
	_thumb = TextureRect.new()
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame.add_child(_thumb)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 110)
	_details.add_child(scroll)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(info)
	_title = LinkButton.new()
	_title.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	_title.add_theme_font_size_override("font_size", 16)
	info.add_child(_title)
	_byline = Label.new()
	_byline.modulate = Color(1, 1, 1, 0.7)
	_byline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_byline)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.fit_content = true
	_notes.scroll_active = false
	_notes.selection_enabled = true
	info.add_child(_notes)
	var buttons := HFlowContainer.new()
	info.add_child(buttons)
	_add_button = Button.new()
	_add_button.text = "Add as layer"
	_add_button.pressed.connect(_add_layer)
	buttons.add_child(_add_button)
	_save_button = Button.new()
	_save_button.text = "Save .gdshader"
	_save_button.tooltip_text = "Save it to %s/ only, to use or edit yourself." % SHADER_DIR
	_save_button.pressed.connect(func(): _save_shader(true))
	buttons.add_child(_save_button)
	var remove := Button.new()
	remove.text = "Remove"
	remove.tooltip_text = "Take it out of the collection (shaders saved in projects stay)."
	remove.pressed.connect(_remove_selected)
	buttons.add_child(remove)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.modulate = Color(0.75, 0.9, 1.0)
	info.add_child(_message)
	resized.connect(_relayout)
	_relayout()

	_audio_img = Image.create(512, 2, false, Image.FORMAT_RF)
	_audio_tex = ImageTexture.create_from_image(_audio_img)
	if receiver != null:
		receiver.received.connect(_on_received)
	_refresh()
	_select("")


## Wide (the bottom panel): list | preview | text. Narrow: all stacked.
func _relayout() -> void:
	var wide := size.x > size.y * 1.6
	_body.vertical = not wide
	_details.vertical = not wide
	_frame.custom_minimum_size = Vector2(minf(size.x * 0.3, 420.0), 0) if wide else Vector2(0, 120)
	_list.custom_minimum_size.x = size.x * 0.35 if wide else 0.0


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 1.0:
		_poll = 0.0
		_update_status()
		if library != null and library.stamp() != _stamp:
			_refresh()
	if _selected_id != "" and is_visible_in_tree():
		_feed_fake_audio()


func _update_status() -> void:
	if receiver == null or not receiver.is_listening():
		_status.text = "○ Not receiving (port busy)"
		_status.tooltip_text = "Another program holds ports %d–%d." % [ShadertoyReceiver.DEFAULT_PORT, ShadertoyReceiver.DEFAULT_PORT + ShadertoyReceiver.PORT_TRIES - 1]
		return
	var fresh: bool = receiver.last_ping_msec >= 0 and Time.get_ticks_msec() - receiver.last_ping_msec < CONNECTED_MSEC
	_status.text = "● Chrome connected" if fresh else "○ Waiting for Chrome"
	_status.modulate = Color(0.5, 0.9, 0.5) if fresh else Color(1, 1, 1, 0.6)
	_status.tooltip_text = "Listening on 127.0.0.1:%d for the Shadertoy Chrome extension\n(tools/shadertoy_extension: chrome://extensions → Developer mode → Load unpacked).\nThe collection is in %s." % [receiver.port, library.dir]


func _refresh() -> void:
	_stamp = library.stamp()
	_entries = library.entries()
	_fill_list()
	if _selected_id != "" and _entry(_selected_id).is_empty():
		_select("")


func _fill_list() -> void:
	_list.clear()
	var q := _filter.text.strip_edges().to_lower()
	for e in _entries:
		var st: Dictionary = e.shader
		if q != "" and not (st.name.to_lower().contains(q) or st.author.to_lower().contains(q)
				or " ".join(st.tags).to_lower().contains(q)):
			continue
		var a := ShaderCode.analyze(st)
		var mark := "" if a.ok and a.edits.is_empty() else ("✕ " if not a.ok else "✎ ")
		var i := _list.add_item(mark + st.name, Library.load_thumbnail(e.thumbnail))
		_list.set_item_metadata(i, st.id)
		_list.set_item_tooltip(i, "%s%s" % [st.name, " by " + st.author if st.author != "" else ""])
		if st.id == _selected_id:
			_list.select(i)


func _entry(id: String) -> Dictionary:
	for e in _entries:
		if e.shader.id == id:
			return e
	return {}


func _select(id: String) -> void:
	_selected_id = id
	_message.text = ""
	var e := _entry(id)
	_details.visible = not e.is_empty()
	_preview_rect.material = null
	if e.is_empty():
		return
	var st: Dictionary = e.shader
	var a := ShaderCode.analyze(st)
	_title.text = st.name
	_title.uri = st.url
	_title.tooltip_text = st.url
	var by: Array = []
	if st.author != "":
		by.append("by " + st.author)
	if st.likes > 0:
		by.append("♥ %d" % st.likes)
	if not st.tags.is_empty():
		by.append(", ".join(st.tags.slice(0, 5)))
	_byline.text = " · ".join(by)
	var notes: Array = []
	for err in a.errors:
		notes.append("[color=#ff7a7a]✕ Won't run: %s.[/color]" % err)
	for ed in a.edits:
		notes.append("[color=#ffc24d]✎ Needs editing: %s.[/color]" % ed)
	for w in a.warnings:
		notes.append("[color=#e6d38a]• %s.[/color]" % w)
	if notes.is_empty():
		notes.append("[color=#8fe08f]✓ Runs as a layer as it is.[/color]")
	if st.get("url", "") != "":
		notes.append("[color=#9aa]Licence: the author's; Shadertoy's default is CC BY-NC-SA 3.0 (credit them, no commercial use, share alike).[/color]")
	_notes.text = "\n".join(notes)
	_add_button.disabled = not a.ok
	_add_button.tooltip_text = "Save the shader into this project and add a layer with it to the open scene." if a.ok else "It can't run as a layer: " + "; ".join(a.errors)
	_thumb.texture = Library.load_thumbnail(e.thumbnail)
	_thumb.visible = not a.ok
	_show_live_preview(a.ok)
	if not a.ok:
		return
	var shader := Shader.new()
	shader.code = ShaderCode.to_gdshader(st, INCLUDE_DIR)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("iResolution", Vector3(PREVIEW_SIZE.x, PREVIEW_SIZE.y, 1))
	for ch in 4:
		if a.channels.get(ch, "audio" if ch == 0 else "") == "audio":
			mat.set_shader_parameter("iChannel%d" % ch, _audio_tex)
	_preview_rect.material = mat


func _show_live_preview(on: bool) -> void:
	_preview_vp.get_parent().visible = on


## A made-up song for the preview: a bass pulse at 120 BPM over a gentle
## spectrum, in the audio texture's layout (row 0 spectrum, row 1 wave).
func _feed_fake_audio() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var beat := pow(1.0 - fmod(t * 2.0, 1.0), 3.0)
	for x in 512:
		var f := x / 512.0
		var spectrum := clampf(exp(-f * 6.0) * (0.45 + 0.55 * beat) + 0.15 * (0.5 + 0.5 * sin(t * 3.0 + f * 20.0)) * (1.0 - f), 0.0, 1.0)
		_audio_img.set_pixel(x, 0, Color(spectrum, 0, 0))
		_audio_img.set_pixel(x, 1, Color(0.5 + 0.35 * beat * sin(f * 60.0 + t * 20.0), 0, 0))
	_audio_tex.update(_audio_img)
	var mat := _preview_rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("audio_bass", 0.3 + 0.7 * beat)
		mat.set_shader_parameter("audio_level", 0.3 + 0.4 * beat)
		mat.set_shader_parameter("audio_mid", 0.4)
		mat.set_shader_parameter("audio_high", 0.25)


func _on_received(st: Dictionary) -> void:
	_refresh()
	_select(st.id)
	_fill_list()
	_message.text = "Received from Chrome."


func _on_menu(id: int) -> void:
	match id:
		0:
			_add_text(DisplayServer.clipboard_get(), "the clipboard")
		1:
			var dialog := EditorFileDialog.new()
			dialog.title = "Load Shadertoy shaders"
			dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
			dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
			dialog.add_filter("*.json, *.zip", "Shadertoy export")
			dialog.add_filter("*.glsl, *.frag, *.txt", "Shadertoy code")
			dialog.files_selected.connect(func(paths: PackedStringArray):
				dialog.queue_free()
				for p in paths:
					_load_file(p))
			dialog.canceled.connect(dialog.queue_free)
			EditorInterface.get_base_control().add_child(dialog)
			dialog.popup_file_dialog()
		2:
			DirAccess.make_dir_recursive_absolute(library.dir)
			OS.shell_open(library.dir)


## A shader's JSON, or plain code with a mainImage, into the collection.
func _add_text(text: String, from: String) -> Dictionary:
	var st := {}
	var data = ShaderCode.read_json(text)
	if data != null:
		st = library.add(data)
	elif text.contains("mainImage"):
		st = library.add(ShaderCode.from_code(text))
	if st.is_empty():
		_details.visible = true
		_message.text = "Nothing from %s: it's neither a Shadertoy shader's JSON nor code with a mainImage." % from
		return {}
	_refresh()
	_select(st.id)
	_fill_list()
	return st


func _load_file(path: String) -> void:
	if path.get_extension().to_lower() == "zip":
		var zip := ZIPReader.new()
		if zip.open(path) != OK:
			_message.text = "Can't open %s." % path.get_file()
			return
		for f in zip.get_files():
			if f.get_extension().to_lower() == "json":
				_add_text(zip.read_file(f).get_string_from_utf8(), f)
		zip.close()
		return
	var text := FileAccess.get_file_as_string(path)
	if path.get_extension().to_lower() == "json":
		_add_text(text, path.get_file())
	else:
		var st := library.add(ShaderCode.from_code(text, path.get_file().get_basename()))
		_refresh()
		_select(st.get("id", ""))
		_fill_list()


func _remove_selected() -> void:
	if _selected_id == "":
		return
	library.remove(_selected_id)
	_selected_id = ""
	_refresh()
	_select("")


## Writes the selected shader into the project (once: an existing file is
## kept, as it may have been edited) and returns its path, "" on failure.
func _save_shader(show_it: bool) -> String:
	var e := _entry(_selected_id)
	if e.is_empty():
		return ""
	var st: Dictionary = e.shader
	var path := SHADER_DIR.path_join(ShaderCode.file_stem(st) + ".gdshader")
	if FileAccess.file_exists(path):
		_message.text = "Using %s, already in the project." % path
	else:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHADER_DIR))
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_message.text = "Can't write %s." % path
			return ""
		f.store_string(ShaderCode.to_gdshader(st, INCLUDE_DIR))
		f.close()
		EditorInterface.get_resource_filesystem().update_file(path)
		EditorInterface.get_resource_filesystem().scan()
		_message.text = "Saved %s." % path
	if show_it:
		EditorInterface.get_file_system_dock().navigate_to_path(path)
	return path


func _add_layer() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not root is Node3D:
		_message.text = "Open a VJ scene first: the layer goes into the scene that's open."
		return
	var path := _save_shader(false)
	if path == "":
		return
	var shader := ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_REUSE) as Shader
	if shader == null:
		_message.text = "Can't load %s." % path
		return
	var st: Dictionary = _entry(_selected_id).shader
	var layer: Node3D = (load(LAYER_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	layer.name = _unique_name(root, ShaderCode.file_stem(st).trim_suffix("_" + st.id))
	layer.transform = LAYER_TRANSFORM
	layer.set_meta("vj_prefab", "layer")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	layer.shader_material = mat
	undo_redo.create_action("Add Shadertoy layer '%s'" % layer.name)
	undo_redo.add_do_method(root, "add_child", layer, true)
	undo_redo.add_do_property(layer, "owner", root)
	undo_redo.add_do_reference(layer)
	undo_redo.add_undo_method(root, "remove_child", layer)
	undo_redo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(layer)
	EditorInterface.set_main_screen_editor("3D")
	_message.text = "Added layer '%s' with %s." % [layer.name, path.get_file()]


## `base`, or base_2, base_3…: object names are ids, unique in the scene.
static func _unique_name(root: Node, base: String) -> String:
	if base == "":
		base = "shadertoy"
	var n := base
	var i := 2
	while root.name == n or root.find_child(n, true, false) != null:
		n = "%s_%d" % [base, i]
		i += 1
	return n
