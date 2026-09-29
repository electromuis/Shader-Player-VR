class_name StudioStatus
extends PanelContainer

## Studio's status in Edit mode: the mode, the piece and whether it has
## unsaved changes, frames per second, the playhead, what's switched on
## (auto-key, keys on change, snap, a take, an armed ride, with a line
## saying what an armed ride does), and the last thing that happened (undo,
## save, an error). The desktop window shows it in a corner, with the
## keyboard shortcuts; the headset on the left wrist (compact: no hints).
## On the desktop it also holds the tabs of folded panels (– on a panel, or
## its key): press one to bring the panel back. In the headset the wrist
## palette's panel buttons are those tabs. Its Wrist button (P) shows the
## wrist palette on the desktop.

## A folded panel's tab was pressed: the command that shows it again (or
## the Wrist button: studio_toggle_wrist).
signal tab_pressed(id: StringName)

const ACCENT := Color(0.3, 0.79, 0.94)
const RECORD := Color(1.0, 0.36, 0.36)
const DIM := Color(0.72, 0.75, 0.8)

## The keyboard shortcuts, as a table: a column per group, key and what it does.
const HINTS := [
	["Play", [
		["Tab", "Play / Edit"], ["Space", "play / pause"], ["← →", "1 s"], ["Shift+← →", "10 s"],
		["Home", "start"], ["↓ ↑", "prev / next key"], ["L", "loop"], ["[  ]", "loop from / to here"]]],
	["Edit", [
		["Ctrl+Z", "undo"], ["Ctrl+Shift+Z", "redo"], ["Ctrl+S", "save"], ["Delete", "delete"],
		["I", "key it"], ["Shift+I", "auto-key"], ["Shift+G", "snap"], ["Ctrl+L", "save its look"]]],
	["Select", [
		["Click", "select"], ["Drag", "move"], ["Wheel", "nearer / further (dragging)"],
		["Ctrl+Wheel", "scale (dragging)"], ["Esc", "deselect"],
		["F", "go to it"], ["Shift+F", "back"]]],
	["Viewer", [
		["V", "key the viewer"], ["Shift+V", "cut to here"], ["Ctrl+Shift+V", "arm the ride"], ["Shift+R", "record (a take)"]]],
	["View", [
		["R", "reset view"], ["0", "seat"], ["M", "miniature"], ["F1", "VR"],
		["N", "inspector"], ["T", "timeline"], ["B", "shelf"], ["P", "wrist palette"], ["F2", "menu"], ["H", "hide these"]]],
]

## The desktop's panel tabs: [command, label, key].
const TABS := [
	[&"studio_toggle_inspector", "Inspector", "N"],
	[&"studio_toggle_timeline", "Timeline", "T"],
	[&"studio_toggle_shelf", "Shelf", "B"],
]
## The desktop's button for the wrist palette, always there.
const WRIST_BUTTON := [&"studio_toggle_wrist", "Wrist", "P"]

## Wrist layout: bigger text, no keyboard hints.
@export var compact: bool = false

var _mode: Label
var _title: Label
var _dirty: Label
var _time: Label
var _message: Label
var _hints: Control
var _hints_off: Label
## Whether the shortcut table shows (H); otherwise a line saying how to get it.
var hints_on := true
var _auto_key: Label
var _snap: Label
var _rec: Label
var _ride: Label
var _ride_help: Label
var _key_animated: Label
var _fps: Label
var _fps_clock := 0.0
var _tabs: Dictionary = {}  # command -> Button
var _wrist_button: Button


func _ready() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.09, 0.88)
	bg.border_color = Color(0.3, 0.79, 0.94, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(18 if compact else 12)
	add_theme_stylebox_override("panel", bg)
	var size := 34 if compact else 18
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12 if compact else 4)
	add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	rows.add_child(top)
	_mode = _label(top, size, Color.BLACK)
	var chip := StyleBoxFlat.new()
	chip.bg_color = ACCENT
	chip.set_corner_radius_all(6)
	chip.content_margin_left = 10
	chip.content_margin_right = 10
	_mode.add_theme_stylebox_override("normal", chip)
	if compact:
		# The wrist is narrow: the title gets its own line (or two).
		top.add_child(_spacer())
		_dirty = _label(top, size, RECORD)
		_title = _label(rows, size, Color.WHITE)
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.max_lines_visible = 2
	else:
		_title = _label(top, size, Color.WHITE)
		_title.clip_text = true
		_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_dirty = _label(top, size, RECORD)
	_fps = _label(top, int(size * 0.8), DIM)

	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 10)
	rows.add_child(toggles)
	_auto_key = _chip(toggles, size, "● AUTO-KEY", RECORD)
	_key_animated = _chip(toggles, size, "◇ KEY ANIMATED", ACCENT)
	_snap = _chip(toggles, size, "SNAP", ACCENT)
	_ride = _chip(toggles, size, "⤳ RIDE ARMED", RECORD)
	_rec = _chip(toggles, size, "● REC", RECORD)
	var rec_sb := _rec.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	rec_sb.bg_color = RECORD
	_rec.add_theme_stylebox_override("normal", rec_sb)
	_rec.add_theme_color_override("font_color", Color.WHITE)
	if not compact:
		toggles.add_child(_spacer())
		for t in TABS:
			_tabs[t[0]] = _tab(toggles, size, t)
		_wrist_button = _tab(toggles, size, WRIST_BUTTON)
		_wrist_button.text = "▦ Wrist"
		_wrist_button.tooltip_text = "Show / hide the wrist palette (P)"
		_wrist_button.visible = true
	_ride_help = _label(rows, int(size * 0.85), RECORD)
	_ride_help.text = "Ride armed: the next take (● Rec, Shift+R) also records where you fly, as the viewer's path."
	_ride_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ride_help.visible = false
	_time = _label(rows, int(size * 1.5), Color.WHITE)
	_message = _label(rows, size, DIM)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not compact:
		_hints = _hint_table(rows)
		_hints_off = _label(rows, 14, DIM)
		_hints_off.text = "H  keyboard shortcuts"
		_hints_off.visible = false


## The tabs of the panels that are folded (commands from TABS).
func show_tabs(folded: Array) -> void:
	for id in _tabs:
		_tabs[id].visible = id in folded


## The Wrist button lit while the desktop's wrist palette is open.
func show_wrist(open: bool) -> void:
	if _wrist_button == null or _wrist_button.get_meta("open", false) == open:
		return
	_wrist_button.set_meta("open", open)
	for state in ["normal", "hover", "pressed"]:
		var sb := _wrist_button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		sb.bg_color = Color(ACCENT, (0.45 if open else 0.1) + (0.15 if state == "hover" else 0.0))
		_wrist_button.add_theme_stylebox_override(state, sb)
	_wrist_button.add_theme_color_override("font_color", Color.WHITE if open else ACCENT)


## Shows or hides the frames per second (the player's FPS setting).
func show_fps(on: bool) -> void:
	if _fps != null:
		_fps.visible = on


## Frames per second, a few times a second.
func _process(delta: float) -> void:
	_fps_clock += delta
	if _fps == null or _fps_clock < 0.25:
		return
	_fps_clock = 0.0
	_fps.text = "%d fps" % roundi(Engine.get_frames_per_second())


## Shows or hides the shortcut table; the panel shrinks to fit.
func show_hints(on: bool) -> void:
	hints_on = on
	if _hints == null:
		return
	_hints.visible = on
	_hints.get_meta("line").visible = on
	_hints_off.visible = not on
	reset_size.call_deferred()


## HINTS side by side: a heading over a key / action grid per group.
func _hint_table(parent: Control) -> Control:
	var line := HSeparator.new()
	line.add_theme_color_override("separator", Color(ACCENT, 0.3))
	parent.add_child(line)
	var table := HBoxContainer.new()
	table.add_theme_constant_override("separation", 22)
	parent.add_child(table)
	table.set_meta("line", line)
	for group in HINTS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		table.add_child(col)
		_label(col, 14, ACCENT).text = String(group[0]).to_upper()
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 1)
		col.add_child(grid)
		for row in group[1]:
			var key := _label(grid, 14, Color.WHITE)
			key.text = row[0]
			key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_label(grid, 14, DIM).text = row[1]
	return table


## A small outlined tag, shown while its toggle is on.
func _chip(parent: Control, font_size: int, text: String, color: Color) -> Label:
	var l := _label(parent, int(font_size * 0.8), color)
	l.text = text
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.15)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	l.add_theme_stylebox_override("normal", sb)
	l.visible = false
	return l


func _tab(parent: Control, font_size: int, t: Array) -> Button:
	var b := Button.new()
	b.text = "▭ " + t[1]
	b.tooltip_text = "Bring the %s back (%s)" % [String(t[1]).to_lower(), t[2]]
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(font_size * 0.8))
	b.add_theme_color_override("font_color", ACCENT)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT, 0.25 if state == "hover" else 0.1)
		sb.border_color = Color(ACCENT, 0.6)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func(): tab_pressed.emit(t[0]))
	b.visible = false
	parent.add_child(b)
	return b


static func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## Everything at once; cheap enough to call every frame.
func show_state(mode: String, title: String, dirty: bool, t: float, duration: float, playing: bool, message: String,
		auto_key: bool = false, snap: bool = false, recording: String = "", ride_armed: bool = false,
		key_animated: bool = false) -> void:
	if _mode == null:
		return
	_auto_key.visible = auto_key and mode == "EDIT"
	_snap.visible = snap and mode == "EDIT"
	_key_animated.visible = key_animated and not auto_key and mode == "EDIT"
	_ride.visible = ride_armed
	var was := _ride_help.visible
	_ride_help.visible = ride_armed and recording == ""
	if was != _ride_help.visible:
		reset_size.call_deferred()
	_rec.visible = recording != ""
	_rec.text = recording
	_auto_key.get_parent().visible = _auto_key.visible or _snap.visible or _rec.visible or _ride.visible or _key_animated.visible 			or _wrist_button != null
	_mode.text = mode
	_title.text = title
	_dirty.text = "● unsaved" if dirty else ""
	_time.text = "%s  %s / %s" % ["▶" if playing else "❚❚", timecode(t), timecode(duration)]
	_message.text = message
	_message.visible = message != ""


static func timecode(t: float) -> String:
	t = maxf(t, 0.0)
	return "%d:%05.2f" % [floori(t / 60.0), fmod(t, 60.0)]
