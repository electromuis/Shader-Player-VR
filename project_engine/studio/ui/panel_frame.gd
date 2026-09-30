class_name StudioPanelFrame
extends RefCounted

## A Studio panel's frame (TODO 75, 76): its title bar and edges, and
## folding it to the title bar. The panel makes one in its _ready with its
## title bar, its body (everything under the title bar, in one container)
## and its – button; Studio moves and resizes the panel from the signals: on
## the desktop by the mouse (`dragged`), in the headset by the laser (the
## press on the panel's viewport starts it, the trigger's release ends it).
##
## A press on the title bar where nothing else takes it (the title, the gaps
## between the buttons) moves the panel; a press within EDGE of its border
## resizes it from that side or corner.

signal move_started
signal resize_started(edges: int)
## The mouse moved this far (window pixels) while pressed.
signal dragged(by: Vector2)
signal drag_ended

const LEFT := 1
const RIGHT := 2
const TOP := 4
const BOTTOM := 8
## How close to the border a press resizes (panel pixels; the headset's
## panels are drawn bigger).
const EDGE := 8.0
const EDGE_VR := 22.0

var panel: Control
var header: Control
var body: Control
var fold_button: Button
var collapsed := false
## Which sides may be pulled (all four by default).
var edges_allowed := LEFT | RIGHT | TOP | BOTTOM
var _edge := EDGE
var _dragging := false
var _last := Vector2.ZERO


func _init(p: Control, title_bar: Control, body_node: Control, fold: Button, vr: bool = false) -> void:
	panel = p
	header = title_bar
	body = body_node
	fold_button = fold
	_edge = EDGE_VR if vr else EDGE
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	panel.gui_input.connect(_on_input)
	_style_fold()


## Fold to the title bar, or unfold.
func set_collapsed(on: bool) -> void:
	collapsed = on
	body.visible = not on
	_style_fold()


## The panel's height folded: its title bar and its frame's margins.
func title_height() -> float:
	var sb := panel.get_theme_stylebox("panel")
	return header.get_combined_minimum_size().y + (sb.get_minimum_size().y if sb != null else 0.0)


## The sides a press at `at` (the panel's own pixels) would pull: 0 when
## it's not near the border.
func edges_at(at: Vector2) -> int:
	var s := panel.size
	var e := 0
	if at.x < _edge:
		e |= LEFT
	elif at.x > s.x - _edge:
		e |= RIGHT
	if at.y < _edge:
		e |= TOP
	elif at.y > s.y - _edge:
		e |= BOTTOM
	if collapsed:
		e &= ~(TOP | BOTTOM)
	return e & edges_allowed


func is_dragging() -> bool:
	return _dragging


func _style_fold() -> void:
	if fold_button == null:
		return
	# Folded: a drawn square (the font's □ is a speck).
	fold_button.text = "" if collapsed else "—"
	fold_button.icon = _square(fold_button.get_theme_font_size("font_size")) if collapsed else null
	fold_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fold_button.tooltip_text = "Unfold" if collapsed else "Fold to its title bar"


static var _squares := {}  # font size -> Texture2D


## A square outline about as big as a capital letter at `font_size`.
static func _square(font_size: int) -> Texture2D:
	if _squares.has(font_size):
		return _squares[font_size]
	var n := maxi(8, roundi(font_size * 0.7))
	var line := maxi(2, roundi(font_size / 9.0))
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			if x < line or y < line or x >= n - line or y >= n - line:
				img.set_pixel(x, y, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_squares[font_size] = tex
	return tex


## The panel's own presses and those its title bar lets through (the title
## bar passes them up, with positions in the panel's pixels by now).
func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and not _dragging:
			var e := edges_at(mb.position)
			var on_title := header.get_global_rect().has_point(mb.global_position)
			if e == 0 and not on_title:
				return
			_dragging = true
			_last = mb.global_position
			panel.accept_event()
			if e != 0:
				resize_started.emit(e)
			else:
				move_started.emit()
		elif not mb.pressed and _dragging:
			_dragging = false
			panel.accept_event()
			drag_ended.emit()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			dragged.emit(mm.global_position - _last)
			_last = mm.global_position
			panel.accept_event()
		else:
			panel.mouse_default_cursor_shape = _cursor(edges_at(mm.position))


static func _cursor(e: int) -> Control.CursorShape:
	if e == LEFT | TOP or e == RIGHT | BOTTOM:
		return Control.CURSOR_FDIAGSIZE
	if e == RIGHT | TOP or e == LEFT | BOTTOM:
		return Control.CURSOR_BDIAGSIZE
	if e & (LEFT | RIGHT):
		return Control.CURSOR_HSIZE
	if e & (TOP | BOTTOM):
		return Control.CURSOR_VSIZE
	return Control.CURSOR_ARROW
