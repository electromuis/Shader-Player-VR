class_name StudioAssetShelf
extends PanelContainer

## Studio's asset shelf: cards for what can be added to the piece, by type
## (objects, layers, effects: StudioAssetLibrary), each with a thumbnail
## (StudioThumbnailer) and where it comes from (yours, or the piece's own).
## Press a card to pick it up (`taken`); Studio carries it and drops it
## where you let go in the world (StudioAssetDrop). The Open tab is the
## player's file browser: pick a piece, or a video to start a new one.
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
## – : fold the shelf to its tab (the wrist's Shelf button).
signal close_requested

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
	OPEN_TAB: "Open a piece (.json), or a video to start a new piece for it.",
}

var vr := false
var library: StudioAssetLibrary
var thumbnailer: StudioThumbnailer
## The tab showing: an asset type, or OPEN_TAB.
var tab := "object"
## The id of the card being carried ("" when none): it shows highlighted.
var held_id := ""
## A runner, for the Open tab to start in the piece's folder.
var runner: ScriptRunner

static var _placeholders := {}  # kind -> Texture2D

var _needs_build := true
var _cards := {}  # asset id -> {panel, image}
var _tab_buttons := {}
var _hint: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _files: Control
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
	top.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	top.add_child(gap)
	for t in StudioAssetLibrary.TYPES + [OPEN_TAB]:
		var b := Button.new()
		b.text = StudioAssetLibrary.TYPE_LABELS.get(t, "Open…")
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): show_tab(t))
		if vr:
			b.custom_minimum_size.y = _fs * 1.7  # about 3 cm in the headset
		top.add_child(b)
		_tab_buttons[t] = b
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fill)
	var close := Button.new()
	close.text = "—"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Fold to a tab (B brings it back)"
	close.pressed.connect(func(): close_requested.emit())
	if vr:
		close.custom_minimum_size = Vector2(_fs * 1.7, _fs * 1.7)
	top.add_child(close)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", ceili(_fs * 0.9))
	_hint.add_theme_color_override("font_color", DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_hint)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12 if vr else 8)
	_grid.add_theme_constant_override("v_separation", 12 if vr else 8)
	_scroll.add_child(_grid)
	_files = _make_files_browser()
	_files.visible = false
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_files)
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


func _process(_delta: float) -> void:
	if _needs_build and library != null:
		_needs_build = false
		_build()


func _build() -> void:
	for t in _tab_buttons:
		_tab_buttons[t].set_pressed_no_signal(t == tab)
	_hint.text = HINTS.get(tab, "")
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
	var width := _scroll.size.x if _scroll.size.x > 0.0 else size.x - 40.0
	_grid.columns = maxi(1, int((width + 8) / (_card.x + (12 if vr else 8))))
	for asset in library.of_type(tab):
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
	if source != "":
		var tag := Label.new()
		tag.text = source
		tag.add_theme_font_size_override("font_size", int(_fs * 0.8))
		tag.add_theme_color_override("font_color", ACCENT)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(tag)
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			take(asset)
			panel.accept_event())
	_cards[asset.id] = {"panel": panel, "image": image}
	_style_card(asset.id)
	return panel


## Pick up `asset` (what a press on its card does).
func take(asset: Dictionary) -> void:
	show_held(asset.id)
	taken.emit(asset)


## The card for asset `id`, to drive it in checks.
func card(id: String) -> Control:
	return _cards[id].panel if _cards.has(id) else null


func on_thumbnail(asset_id: String, tex: Texture2D) -> void:
	if _cards.has(asset_id):
		_cards[asset_id].image.texture = tex


func _style_card(id: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6 if vr else 4)
	var held := id == held_id
	sb.bg_color = Color(ACCENT, 0.25) if held else Color(0.14, 0.16, 0.22)
	sb.border_color = ACCENT if held else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(3 if held else 1)
	_cards[id].panel.add_theme_stylebox_override("panel", sb)


## Until the thumbnail is drawn (or headless): a tile in the colour of the
## asset's kind.
static func _placeholder(asset: Dictionary) -> Texture2D:
	var kind := String(asset.kind)
	if _placeholders.has(kind):
		return _placeholders[kind]
	var colors := {"screen": Color(0.2, 0.35, 0.55), "cube": Color(0.35, 0.3, 0.5), "prefab": Color(0.3, 0.42, 0.3),
			"layer": Color(0.45, 0.28, 0.45), "effect": Color(0.5, 0.38, 0.2), "vertex": Color(0.2, 0.45, 0.42)}
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
