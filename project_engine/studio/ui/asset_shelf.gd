class_name StudioAssetShelf
extends PanelContainer

## Studio's asset shelf: cards for what can be added to the piece, by type
## (objects, layers, effects: StudioAssetLibrary), each with a thumbnail
## (StudioThumbnailer) and where it comes from (yours, or the piece's own).
## Press a card to pick it up (`taken`); Studio carries it and drops it
## where you let go in the world (StudioAssetDrop). The Open tab is the
## player's file browser: pick a piece, or a video to start a new one.
## The Shadertoy tab lists the shaders collected from shadertoy.com
## (StudioShadertoy): each card becomes a layer or an effect when taken,
## and the bar above them filters, searches the site and takes a paste.
## Layer and effect cards play a short loop (StudioThumbnailer.loop): the
## one under the pointer, or all of them with `play_all` (the headset's
## shelf while it's open).
##
## The same scene is the desktop's left panel and, in the headset, a panel
## in front of you and to the left (bigger there: `vr`, worked out when
## it's inside a SubViewport). It lists the library again when refresh()
## is called (Studio does when the watched folders change).

signal said(text: String)
## A card was picked up.
signal taken(asset: Dictionary)
## The Open tab picked a file (a piece, or a video).
signal open_requested(path: String)
## ✕ : hide the shelf, leaving its tab (the wrist's Shelf button).
signal close_requested
## – : fold the shelf to its title bar in place (again: unfold it).
signal minimize_requested

const ACCENT := Color(0.3, 0.79, 0.94)
const DIM := Color(0.72, 0.75, 0.8)
const PANEL_BG := Color(0.06, 0.06, 0.09, 0.92)
const OPEN_TAB := "open"
const SOURCE_LABELS := {"builtin": "", "user": "yours", "piece": "in the piece"}
const HINTS := {
	"object": "Press a card and let go where it should stand: it comes on at the playhead, facing you.",
	"layer": "A layer shows a shader on its own screen. Drop it in the space, or on a layer to change its shader.",
	"effect": "Drop an effect on a screen or a layer: it goes at the end of its effects.",
	"vertex": "Vertex effects bend a screen's or layer's shape (ripple, twist, spin, pulse). Drop one on a screen or a layer: it goes at the end of its vertex effects.",
	"look": "Your saved looks (the inspector's Save look). Drop one on something of its kind to restyle it (it keeps its place and size), or in the space to add one.",
	"shadertoy": "Shaders from shadertoy.com. Layer makes one a layer (drop it in the space), Effect an effect (drop it on a screen or a layer). Search opens the site; Paste takes a link to a shader, or its code.",
	OPEN_TAB: "Open a piece (.json), or a video to start a new piece for it.",
}
const SHADERTOY_TAB := "shadertoy"
## How long after the extension was last in touch it counts as there
## (it asks on every Shadertoy page).
const EXTENSION_SEEN_MSEC := 60000

var vr := false
var library: StudioAssetLibrary
var thumbnailer: StudioThumbnailer
## The tab showing: an asset type, or OPEN_TAB.
var tab := "object"
## The id of the card being carried ("" when none): it shows highlighted.
var held_id := ""
## A runner, for the Open tab to start in the piece's folder.
var runner: ScriptRunner
## Every card plays its loop, not only the one under the pointer.
var play_all := false
## The card under the pointer ("" when none).
var hover_id := ""
## The Shadertoy receiver (Studio's), to say whether the extension is there.
var receiver: ShadertoyReceiver
## Opens a web page (the site's search, a pasted link): the browser; checks
## replace it.
var open_url: Callable = func(url: String): OS.shell_open(url)
## The Shadertoy tab's filter.
var shadertoy_filter := ""

static var _placeholders := {}  # kind -> Texture2D
static var _st_notes := {}  # "<json path>|<modified>" -> [layer notes, effect notes] (ShadertoyShader.analyze)

## Its title bar and edges (StudioPanelFrame): Studio moves and sizes it.
var frame: StudioPanelFrame
var _needs_build := true
var _cards := {}  # asset id -> {panel, image, asset}
var _playing := {}  # asset id -> the AtlasTexture showing its loop
var _asked := {}  # asset id -> true: its loop is being drawn, or is a still
var _clock := 0.0
var _tab_buttons := {}
var _hint: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _files: Control
var _st_bar: Control
var _st_filter_edit: LineEdit
var _st_status: Label
var _st_clock := 0.0
var _fs := 15
var _card := Vector2(128, 80)


func _ready() -> void:
	vr = vr or get_viewport() != get_tree().root
	_fs = 28 if vr else 14
	_card = Vector2(224, 140) if vr else Vector2(128, 80)
	var th := Theme.new()
	th.default_font_size = _fs
	theme = th
	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG
	bg.border_color = Color(ACCENT, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(12 if vr else 10)
	bg.set_content_margin_all(16 if vr else 10)
	add_theme_stylebox_override("panel", bg)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10 if vr else 6)
	add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8 if vr else 4)
	rows.add_child(top)
	var title := Label.new()
	title.text = "Shelf"
	title.add_theme_font_size_override("font_size", int(_fs * 1.3))
	title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	gap.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(gap)
	# The tabs wrap onto a second row when the shelf is narrow (the desktop's).
	var tabs := HFlowContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("h_separation", 8 if vr else 4)
	tabs.add_theme_constant_override("v_separation", 4)
	top.add_child(tabs)
	for t in StudioAssetLibrary.TYPES + [OPEN_TAB]:
		var b := Button.new()
		b.text = StudioAssetLibrary.TYPE_LABELS.get(t, "Open…")
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): show_tab(t))
		if vr:
			b.custom_minimum_size.y = _fs * 1.7  # about 3 cm in the headset
		tabs.add_child(b)
		_tab_buttons[t] = b
	var fold: Button
	for b in [["—", minimize_requested], ["✕", close_requested]]:
		var button := Button.new()
		button.text = b[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect((b[1] as Signal).emit)
		if vr:
			button.custom_minimum_size = Vector2(_fs * 1.7, _fs * 1.7)
		button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(button)
		if b[0] == "—":
			fold = button
		else:
			button.tooltip_text = "Hide it (its tab, or B, brings it back)"
	# Under the title bar: what folds away.
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10 if vr else 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	frame = StudioPanelFrame.new(self, top, body, fold, vr)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", ceili(_fs * 0.9))
	_hint.add_theme_color_override("font_color", DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_hint)
	_st_bar = _make_shadertoy_bar()
	body.add_child(_st_bar)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12 if vr else 8)
	_grid.add_theme_constant_override("v_separation", 12 if vr else 8)
	_scroll.add_child(_grid)
	_files = _make_files_browser()
	_files.visible = false
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_files)
	resized.connect(func(): _needs_build = true)


## List the library again (new or changed files).
func refresh() -> void:
	_needs_build = true


func show_tab(t: String) -> void:
	tab = t
	_needs_build = true


## Show `id` as being carried ("" for none).
func show_held(id: String) -> void:
	if id == held_id:
		return
	held_id = id
	for cid in _cards:
		_style_card(cid)


func _process(delta: float) -> void:
	if _needs_build and library != null:
		_needs_build = false
		_build()
	_play(delta)
	_st_clock -= delta
	if _st_clock <= 0.0 and tab == SHADERTOY_TAB:
		_st_clock = 1.0
		_st_status.text = extension_status()


## The asset ids whose cards play their loops now.
func playing() -> Array:
	return _playing.keys()


## Start and stop the cards' loops, and step the ones playing.
func _play(delta: float) -> void:
	_clock += delta
	var want: Array = []
	if thumbnailer != null and is_visible_in_tree():
		want = _cards.keys() if play_all else ([hover_id] if _cards.has(hover_id) else [])
		want = want.filter(func(id): return String(_cards[id].asset.type) in StudioThumbnailer.LOOP_TYPES)
	for id in _playing.keys():
		if not id in want:
			_playing.erase(id)
			_show_still(id)
	for id in _asked.keys():
		if not id in want:
			_asked.erase(id)
	for id in want:
		if _playing.has(id) or _asked.has(id):
			continue
		var strip := thumbnailer.loop(_cards[id].asset)
		if strip == null or StudioThumbnailer.frames_of(strip) == 1:
			_asked[id] = true  # being drawn (on_loop says when), or it doesn't move
		else:
			var atlas := AtlasTexture.new()
			atlas.atlas = strip
			atlas.region = Rect2(Vector2.ZERO, StudioThumbnailer.SIZE)
			_playing[id] = atlas
			_cards[id].image.texture = atlas
	var frame := int(_clock * StudioThumbnailer.LOOP_FPS)
	for id in _playing:
		var atlas: AtlasTexture = _playing[id]
		var x := (frame % StudioThumbnailer.frames_of(atlas.atlas)) * StudioThumbnailer.SIZE.x
		if atlas.region.position.x != x:
			atlas.region = Rect2(Vector2(x, 0), StudioThumbnailer.SIZE)


func _build() -> void:
	for t in _tab_buttons:
		_tab_buttons[t].set_pressed_no_signal(t == tab)
	_hint.text = HINTS.get(tab, "")
	_st_bar.visible = tab == SHADERTOY_TAB
	if tab == SHADERTOY_TAB:
		_st_status.text = extension_status()
	var files := tab == OPEN_TAB
	_scroll.visible = not files
	_files.visible = files
	if files:
		if _files.has_method("bind") and not _files.get_meta("bound", false):
			_files.set_meta("bound", true)
			_files.bind(runner, func(path: String, _playlist = null): open_requested.emit(path))
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cards.clear()
	_playing.clear()
	_asked.clear()
	var width := _scroll.size.x if _scroll.size.x > 0.0 else size.x - 40.0
	_grid.columns = maxi(1, int((width + 8) / (_card.x + (12 if vr else 8))))
	var list := library.of_type(tab)
	if tab == SHADERTOY_TAB:
		list = list.filter(func(a): return StudioShadertoy.matches(a, shadertoy_filter))
	for asset in list:
		_grid.add_child(_make_card(asset))


func _make_card(asset: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(_card.x, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = String(asset.path)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var image := TextureRect.new()
	image.custom_minimum_size = _card
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := thumbnailer.thumbnail(asset) if thumbnailer != null else null
	image.texture = tex if tex != null else _placeholder(asset)
	col.add_child(image)
	var name := Label.new()
	name.text = asset.label
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name)
	var source: String = SOURCE_LABELS.get(asset.source, "")
	if asset.get("in_piece", false):
		source += " · in the piece"
	var shadertoy := String(asset.type) == SHADERTOY_TAB
	if shadertoy:
		source = String(asset.get("author", ""))
	if source != "":
		var tag := Label.new()
		tag.text = source
		tag.clip_text = true
		tag.add_theme_font_size_override("font_size", int(_fs * 0.8))
		tag.add_theme_color_override("font_color", ACCENT)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(tag)
	if shadertoy:
		_add_shadertoy_rows(col, panel, asset)
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			if shadertoy:
				take_shadertoy(asset, false)
			else:
				take(asset)
			panel.accept_event())
	panel.mouse_entered.connect(func(): hover_id = asset.id)
	panel.mouse_exited.connect(func():
		if hover_id == asset.id:
			hover_id = "")
	_cards[asset.id] = {"panel": panel, "image": image, "asset": asset}
	_style_card(asset.id)
	return panel


## Pick up `asset` (what a press on its card does).
func take(asset: Dictionary) -> void:
	show_held(asset.id)
	taken.emit(asset)


## Make the Shadertoy shader `asset` a layer, or an effect, and pick that
## up (StudioShadertoy.make). Returns the layer or effect asset, {} if it
## can't be made.
func take_shadertoy(asset: Dictionary, as_effect: bool) -> Dictionary:
	var r := StudioShadertoy.make(asset, as_effect, library.library_dirs[0])
	if not r.ok:
		said.emit("%s can't be %s: %s." % [asset.label, "an effect" if as_effect else "a layer", r.error])
		return {}
	if not r.notes.edits.is_empty():
		said.emit("%s needs editing before it runs (%s): %s." % [asset.label, "; ".join(r.notes.edits), r.path])
	show_held(asset.id)
	taken.emit(r.asset)
	return r.asset


## Pasted text on the Shadertoy tab (StudioShadertoy.paste): a link to a
## shader opens its page, whose extension sends it here; its JSON or code
## goes straight into the collection. Returns what it was.
func paste_shadertoy(text: String) -> Dictionary:
	var lib := ShadertoyLibrary.new(library.shadertoy_dir)
	var r := StudioShadertoy.paste(text, lib)
	match r.kind:
		"link":
			var e := lib.find(r.id)
			if not e.is_empty():
				said.emit("%s is here already." % e.shader.name)
			else:
				open_url.call(StudioShadertoy.send_url(r.id))
				said.emit("Opened its page in your browser: the Chrome extension sends it here%s." % (
						"" if extension_seen() else " (if it's installed: tools/shadertoy_extension)"))
		"added":
			said.emit("%s is on the Shadertoy tab now." % r.shader.name)
		_:
			said.emit("The clipboard has no link to a Shadertoy shader, nor its code (a mainImage).")
	refresh()
	return r


## Open the site's search for the filter's words.
func search_shadertoy() -> void:
	open_url.call(StudioShadertoy.search_url(shadertoy_filter))
	said.emit("Shadertoy is open in your browser: a shader's Send button puts it here.")


## Whether the Chrome extension has been in touch lately.
func extension_seen() -> bool:
	return receiver != null and receiver.last_ping_msec >= 0 \
			and Time.get_ticks_msec() - receiver.last_ping_msec < EXTENSION_SEEN_MSEC


func extension_status() -> String:
	if receiver == null or not receiver.is_listening():
		return "Not listening for the Chrome extension (other apps have its ports)."
	if extension_seen():
		return "The Chrome extension is here."
	return "The Chrome extension hasn't been in touch: open shadertoy.com with it installed (tools/shadertoy_extension)."


## The card for asset `id`, to drive it in checks.
func card(id: String) -> Control:
	return _cards[id].panel if _cards.has(id) else null


func on_thumbnail(asset_id: String, tex: Texture2D) -> void:
	if _cards.has(asset_id) and not _playing.has(asset_id):
		_cards[asset_id].image.texture = tex


## A loop was drawn: a card waiting for it starts playing it.
func on_loop(asset_id: String, _strip: Texture2D) -> void:
	_asked.erase(asset_id)


func _show_still(id: String) -> void:
	var asset: Dictionary = _cards[id].asset
	var tex := thumbnailer.thumbnail(asset) if thumbnailer != null else null
	_cards[id].image.texture = tex if tex != null else _placeholder(asset)


func _style_card(id: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6 if vr else 4)
	var held := id == held_id
	sb.bg_color = Color(ACCENT, 0.25) if held else Color(0.14, 0.16, 0.22)
	sb.border_color = ACCENT if held else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(3 if held else 1)
	_cards[id].panel.add_theme_stylebox_override("panel", sb)


## A Shadertoy card's rest: what it loses (a line, the rest in the
## tooltip) and its Layer and Effect buttons.
func _add_shadertoy_rows(col: VBoxContainer, panel: Control, asset: Dictionary) -> void:
	var notes := _shadertoy_notes(asset)
	var layer: Dictionary = notes[0]
	var effect: Dictionary = notes[1]
	var state := Label.new()
	state.clip_text = true
	state.add_theme_font_size_override("font_size", int(_fs * 0.8))
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not layer.ok:
		state.text = "won't run"
		state.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	elif not layer.edits.is_empty():
		state.text = "needs editing"
		state.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	if state.text != "":
		col.add_child(state)
	var tip: Array = [String(asset.label)]
	for pair in [["As a layer", layer], ["As an effect", effect]]:
		var n: Dictionary = pair[1]
		var lines: Array = n.errors.map(func(e): return "won't run: " + e) + n.edits.map(func(e): return "needs editing: " + e) + n.warnings
		tip.append("%s: %s" % [pair[0], "; ".join(lines) if not lines.is_empty() else "runs as it is"])
	panel.tooltip_text = "\n".join(tip)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	col.add_child(buttons)
	for pair in [["Layer", false], ["Effect", true]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", int(_fs * 0.85))
		b.disabled = not layer.ok
		if vr:
			b.custom_minimum_size.y = _fs * 1.5
		var as_effect: bool = pair[1]
		b.pressed.connect(func(): take_shadertoy(asset, as_effect))
		buttons.add_child(b)


## [layer notes, effect notes] for a Shadertoy card (ShadertoyShader.analyze),
## kept until its file changes: the conversion's fixes take a moment.
static func _shadertoy_notes(asset: Dictionary) -> Array:
	var key := "%s|%d" % [asset.path, FileAccess.get_modified_time(asset.path)]
	if not _st_notes.has(key):
		var st := ShadertoyShader.parse(FileAccess.get_file_as_string(asset.path))
		_st_notes[key] = [ShadertoyShader.analyze(st), ShadertoyShader.analyze(st, true)]
	return _st_notes[key]


## The Shadertoy tab's bar: the filter, the site's search and Paste, and
## whether the extension is there.
func _make_shadertoy_bar() -> Control:
	var box := VBoxContainer.new()
	box.visible = false
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8 if vr else 4)
	box.add_child(row)
	_st_filter_edit = LineEdit.new()
	_st_filter_edit.placeholder_text = "Filter, or words to search for"
	_st_filter_edit.clear_button_enabled = true
	_st_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_st_filter_edit.text_changed.connect(func(t: String):
		shadertoy_filter = t
		_needs_build = true)
	_st_filter_edit.text_submitted.connect(func(_t): search_shadertoy())
	row.add_child(_st_filter_edit)
	for spec in [["Search", "Search shadertoy.com for these words (in your browser)", search_shadertoy],
			["Paste", "A link to a shader (its page opens and the extension sends it here), or its code",
				func(): paste_shadertoy(DisplayServer.clipboard_get())]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[2])
		if vr:
			b.custom_minimum_size.y = _fs * 1.7
		row.add_child(b)
	_st_status = Label.new()
	_st_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_st_status.add_theme_font_size_override("font_size", ceili(_fs * 0.85))
	_st_status.add_theme_color_override("font_color", DIM)
	box.add_child(_st_status)
	return box


## Until the thumbnail is drawn (or headless): a tile in the colour of the
## asset's kind.
static func _placeholder(asset: Dictionary) -> Texture2D:
	var kind := String(asset.kind)
	if _placeholders.has(kind):
		return _placeholders[kind]
	var colors := {"screen": Color(0.2, 0.35, 0.55), "cube": Color(0.35, 0.3, 0.5), "prefab": Color(0.3, 0.42, 0.3),
			"layer": Color(0.45, 0.28, 0.45), "effect": Color(0.5, 0.38, 0.2), "vertex": Color(0.2, 0.45, 0.42),
			"shadertoy": Color(0.25, 0.3, 0.45)}
	var img := Image.create(64, 40, false, Image.FORMAT_RGB8)
	img.fill(colors.get(kind, Color(0.25, 0.25, 0.3)))
	img.fill_rect(Rect2i(24, 12, 16, 16), Color(1, 1, 1, 1).darkened(0.3))
	var tex := ImageTexture.create_from_image(img)
	_placeholders[kind] = tex
	return tex


## The player's Files tab browser (player/ui/files_tab.gd), built here with
## the nodes it expects, showing pieces and videos.
func _make_files_browser() -> Control:
	var tab_root := VBoxContainer.new()
	tab_root.set_script(load("res://player/ui/files_tab.gd"))
	tab_root.add_theme_constant_override("separation", 6)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	tab_root.add_child(header)
	var names := {}
	for spec in [["BackButton", Button, "Back"], ["UpButton", Button, "Up"], ["PathLabel", Label, ""],
			["SortOption", OptionButton, ""], ["ViewButton", Button, "Tiles"]]:
		var n: Control = spec[1].new()
		n.name = spec[0]
		if n is Button and spec[2] != "":
			(n as Button).text = spec[2]
			(n as Button).focus_mode = Control.FOCUS_NONE
		header.add_child(n)
		names[spec[0]] = n
	(names.PathLabel as Label).clip_text = true
	(names.PathLabel as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(names.PathLabel as Label).add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	var list := ItemList.new()
	list.name = "EntryList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.allow_reselect = true
	tab_root.add_child(list)
	var status := Label.new()
	status.name = "StatusLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	tab_root.add_child(status)
	for n in names.values() + [list, status]:
		n.owner = tab_root
		n.unique_name_in_owner = true
	return tab_root
