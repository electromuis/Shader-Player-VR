class_name StudioWristPalette
extends PanelContainer

## Studio's left-wrist palette in Edit mode (docs/studio/todo/3_wrist.png):
## a Play / Edit switch and the piece's name over a big timecode ("of" the
## duration, the bar and beat); two pages of 4 × 3 icon tiles (PAGES: page 1
## what you use all the time, page 2 the rest); a footer with Save, whether
## there are unsaved changes and how long ago they were autosaved; a line
## saying what the active mode does (a take, an armed ride, auto-key, keys on
## change, snapping), or, while the pointer is on a tile, what that tile
## does; then the last thing that happened, and the page dots. Swipe across
## the palette (or press a dot) for the other page. Press tiles with the
## laser. Each tile asks Studio to run a command (`action`, the router's
## Studio command ids); toggles are lit while on (show_toggles): auto-key,
## a take and an armed ride red, the rest blue. The panel buttons
## (inspector, timeline, shelf, outliner) are the folded panels' tabs. The desktop
## shows it too, scaled down, on P or the status's Wrist button (the mouse
## presses and swipes).

signal action(id: StringName)

const ACCENT := WristTile.ACCENT
const RECORD := WristTile.RECORD
## The two pages: [command id, icon, caption, what it does]. Key it is A
## on the controller (I on the keyboard); its tile made way for the
## Outliner, as in the mockup.
const PAGES := [
	[
		[&"studio_prev_key", &"prev_key", "Prev key", "Jump to the previous key (the selection's, or any)."],
		[&"studio_play_pause", &"play", "Play", "Play or pause from the playhead."],
		[&"studio_record", &"record", "Record", "Record a take: armed sliders, grabbed objects (and the ride, if armed) as it plays."],
		[&"studio_next_key", &"next_key", "Next key", "Jump to the next key (the selection's, or any)."],
		[&"studio_toggle_autokey", &"auto_key", "Auto-key", "Auto-key: every change writes a key at the playhead."],
		[&"studio_toggle_snap", &"snap", "Snap", "Snap moves to 10 cm and 15°, and keys to beats."],
		[&"studio_toggle_loop", &"loop", "Loop", "Loop playback between the in and out points."],
		[&"studio_undo", &"undo", "Undo", "Undo the last change."],
		[&"studio_toggle_shelf", &"shelf", "Shelf", "Show the shelf: screens, layers, effects and looks to carry out."],
		[&"studio_toggle_inspector", &"inspector", "Inspector", "Show the inspector: the selection's settings."],
		[&"studio_toggle_outliner", &"outliner", "Outliner", "Show the outliner: every object as a tree, to select, group and ungroup."],
		[&"studio_toggle_timeline", &"timeline", "Timeline", "Show the timeline: lanes, keys, the song and its beats."],
	],
	[
		[&"studio_redo", &"redo", "Redo", "Redo what was undone."],
		[&"studio_seat", &"seat", "Seat", "Sit where the audience is at the playhead."],
		[&"studio_goto_selection", &"goto", "Go to it", "Fly to arm's length from the selection."],
		[&"studio_jump_back", &"back", "Back", "Back to where you were before the last jump."],
		[&"studio_loop_in", &"loop_in", "Loop in", "The loop starts at the playhead."],
		[&"studio_loop_out", &"loop_out", "Loop out", "The loop ends at the playhead."],
		[&"studio_key_viewer", &"key_viewer", "Key viewer", "Key the viewer where you stand, at the playhead."],
		[&"studio_cut_here", &"cut", "Cut here", "Cut the viewer to where you stand, with a short fade."],
		[&"studio_arm_ride", &"arm_ride", "Arm ride", "Arm the ride: the next take also records where you fly, as the viewer's path."],
		[&"studio_miniature", &"miniature", "Miniature", "The whole scene small in front of you, to lay it out from above."],
		[&"studio_delete_selection", &"delete", "Delete", "Delete the selection."],
		[&"studio_menu", &"menu", "Menu", "The menu: settings, controls, Studio's options."],
	],
]
## Toggles lit red rather than blue.
const RED := [&"studio_toggle_autokey", &"studio_record", &"studio_arm_ride"]
## A press that moves further than this before letting go is a swipe, not a
## press (pixels); a swipe this long sideways turns the page.
const DRAG := 40.0
const SWIPE := 120.0

var page := 0
var _tiles: Dictionary = {}  # id -> StudioWristTile
var _pages: Array[GridContainer] = []
var _dots: Array[Button] = []
var _play_half: Button
var _edit_half: Button
var _title: Label
var _time: Label
var _sub: Label
var _fps: Label
var _fps_clock := 0.0
var _save: Button
var _save_note: Label
var _line: Label
var _line_dot: Control
var _message: Label
var _hovered: StringName = &""
var _mode_line := ""
var _mode_color := ACCENT
var _press_at := Vector2.INF
## The frame a let-go ended a drag: the tile under it isn't pressed.
var _dragged_frame := -1


func _ready() -> void:
	var card := StyleBoxFlat.new()
	card.bg_color = Color(WristTile.CARD, 0.96)
	card.border_color = WristTile.LINE
	card.set_border_width_all(1)
	card.set_corner_radius_all(18)
	card.set_content_margin_all(22)
	add_theme_stylebox_override("panel", card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	add_child(rows)
	_build_header(rows)
	var grids := Control.new()
	grids.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grids.custom_minimum_size = Vector2(0, 3 * 150 + 2 * 12)
	rows.add_child(grids)
	for p in PAGES.size():
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		grid.visible = p == page
		grids.add_child(grid)
		_pages.append(grid)
		for t in PAGES[p]:
			var tile := StudioWristTile.new(t[1], t[2])
			tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
			if t[0] in RED:
				tile.lit_color = RECORD
			tile.pressed.connect(_press.bind(t[0]))
			tile.mouse_entered.connect(func(): _hovered = t[0]; _show_line())
			tile.mouse_exited.connect(func():
				if _hovered == t[0]:
					_hovered = &""
					_show_line())
			grid.add_child(tile)
			_tiles[t[0]] = tile
	_rule(rows)
	_build_footer(rows)


func _build_header(rows: Control) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	rows.add_child(header)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	header.add_child(left)
	# The switch: a rounded track with the current half filled.
	var switch := PanelContainer.new()
	switch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var track := StyleBoxFlat.new()
	track.bg_color = Color("0f1219")
	track.border_color = WristTile.LINE
	track.set_border_width_all(1)
	track.set_corner_radius_all(40)
	track.set_content_margin_all(5)
	switch.add_theme_stylebox_override("panel", track)
	left.add_child(switch)
	var halves := HBoxContainer.new()
	halves.add_theme_constant_override("separation", 0)
	switch.add_child(halves)
	_play_half = _half(halves, "Play")
	_edit_half = _half(halves, "Edit")
	_title = _label("", 26, WristTile.MUTED)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_title.custom_minimum_size = Vector2(300, 0)
	left.add_child(_title)
	var clock := VBoxContainer.new()
	clock.add_theme_constant_override("separation", -2)
	header.add_child(clock)
	_time = _label("00:00.00", 72, WristTile.TEXT)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time.add_theme_font_override("font", _tabular_font())
	clock.add_child(_time)
	var sub := HBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_END
	sub.add_theme_constant_override("separation", 12)
	clock.add_child(sub)
	_fps = _label("", 26, ACCENT)
	_fps.visible = false
	sub.add_child(_fps)
	_sub = _label("", 26, WristTile.MUTED)
	_sub.add_theme_font_override("font", _tabular_font())
	sub.add_child(_sub)


func _build_footer(rows: Control) -> void:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	rows.add_child(foot)
	_save = Button.new()
	_save.focus_mode = Control.FOCUS_NONE
	_save.custom_minimum_size = Vector2(190, 84)
	_save.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(14)
		sb.bg_color = WristTile.TILE.lightened(0.08 if state == "hover" else 0.0)
		sb.border_color = Color(ACCENT, 0.55) if state == "hover" else WristTile.LINE
		sb.set_border_width_all(1)
		_save.add_theme_stylebox_override(state, sb)
	_save.pressed.connect(_press.bind(&"studio_save"))
	_save.mouse_entered.connect(func(): _hovered = &"studio_save"; _show_line())
	_save.mouse_exited.connect(func():
		if _hovered == &"studio_save":
			_hovered = &""
			_show_line())
	_save.draw.connect(func():
		StudioWristTile.draw_icon(_save, &"save", Vector2(44, _save.size.y / 2), 17.0, WristTile.TEXT, ACCENT)
		_save.draw_string(_save.get_theme_font("font"), Vector2(78, _save.size.y / 2 + 11), "Save",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 32, WristTile.TEXT))
	foot.add_child(_save)
	_save_note = _label("", 26, WristTile.MUTED)
	_save_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_save_note)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	rows.add_child(line)
	_line_dot = Control.new()
	_line_dot.custom_minimum_size = Vector2(18, 34)
	_line_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_dot.draw.connect(func(): _line_dot.draw_circle(Vector2(9, 18), 8.0, _mode_color, true, -1.0, true))
	line.add_child(_line_dot)
	_line = _label("", 26, WristTile.TEXT)
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(0, 68)
	_line.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	line.add_child(_line)
	_message = _label("", 26, WristTile.MUTED)
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.clip_text = true
	rows.add_child(_message)

	# Page dots, each a press target the size of a fingertip at arm's length.
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 0)
	rows.add_child(dots)
	for p in PAGES.size():
		var d := Button.new()
		d.flat = true
		d.focus_mode = Control.FOCUS_NONE
		d.custom_minimum_size = Vector2(90, 76)
		d.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		d.pressed.connect(show_page.bind(p))
		d.draw.connect(func():
			d.draw_circle(d.size / 2, 8.0, ACCENT if p == page else WristTile.LINE.lightened(0.25), true, -1.0, true))
		dots.add_child(d)
		_dots.append(d)


## Turn to page `p` (0 or 1).
func show_page(p: int) -> void:
	page = clampi(p, 0, PAGES.size() - 1)
	for i in _pages.size():
		_pages[i].visible = i == page
	for d in _dots:
		d.queue_redraw()
	_hovered = &""
	_show_line()


## The tile for a command (for checks); null if there's none.
func tile(id: StringName) -> StudioWristTile:
	return _tiles.get(id)


## Swipes: a press and let-go far enough sideways turns the page; a press
## that moved isn't a tile press (see _press). Only presses on the palette
## count: on the desktop it shares the window with the 3D view (scaled
## down), so positions are taken in its own pixels.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		event = make_input_local(event)
		if event.pressed:
			if is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(event.position):
				_press_at = event.position
		elif _press_at != Vector2.INF:
			var d: Vector2 = event.position - _press_at
			if d.length() > DRAG:
				_dragged_frame = Engine.get_process_frames()
			if absf(d.x) > SWIPE and absf(d.x) > 2.0 * absf(d.y):
				show_page(page + (1 if d.x < 0.0 else -1))
			_press_at = Vector2.INF


func _press(id: StringName) -> void:
	if _dragged_frame == Engine.get_process_frames():
		return
	action.emit(id)


func _process(delta: float) -> void:
	_fps_clock += delta
	if not _fps.visible or _fps_clock < 0.25:
		return
	_fps_clock = 0.0
	_fps.text = "%d fps" % roundi(Engine.get_frames_per_second())


## Shows or hides the frames per second (the player's FPS setting).
func show_fps(on: bool) -> void:
	if _fps != null:
		_fps.visible = on


## Everything but the toggles, cheap enough to call every frame. `s` has:
## mode ("EDIT" / "PLAY"), title, dirty, t, duration, playing, message,
## bar (bars since the downbeat, or null without a beat grid), beats_per_bar, recording
## (the status's record chip: "" when not recording), ride_armed, auto_key,
## key_animated, snap, autosaved (seconds since the last autosave, or -1).
func show_state(s: Dictionary) -> void:
	if _time == null:
		return
	var editing: bool = s.get("mode", "EDIT") == "EDIT"
	_style_half(_play_half, not editing)
	_style_half(_edit_half, editing)
	_title.text = s.get("title", "")
	_time.text = clock(s.get("t", 0.0))
	var sub := "of " + clock(s.get("duration", 0.0))
	var bar = s.get("bar")
	if bar != null and bar >= 0.0:
		var beats: int = s.get("beats_per_bar", 4)
		sub +=" · bar %d.%d" % [floori(bar) + 1, floori(fmod(bar, 1.0) * beats) + 1]
	_sub.text = sub
	var playing: bool = s.get("playing", false)
	var play: StudioWristTile = _tiles[&"studio_play_pause"]
	play.symbol = &"pause" if playing else &"play"
	play.caption = "Pause" if playing else "Play"
	play.lit = playing
	var dirty: bool = s.get("dirty", false)
	var ago: float = s.get("autosaved", -1.0)
	if not dirty:
		_save_note.text = "All saved"
		_save_note.add_theme_color_override("font_color", WristTile.MUTED)
	else:
		_save_note.text = "● unsaved" + ("" if ago < 0.0 else " · autosaved %s ago" % _ago(ago))
		_save_note.add_theme_color_override("font_color", RECORD)
	var recording: String = s.get("recording", "")
	var rec: StudioWristTile = _tiles[&"studio_record"]
	rec.symbol = &"stop" if recording != "" else &"record"
	rec.caption = "Stop" if recording != "" else "Record"
	# What the active mode does, most pressing first.
	if recording != "":
		_set_mode_line(recording + (": recording where you fly too" if s.get("ride_armed", false) else ""), RECORD)
	elif s.get("ride_armed", false):
		_set_mode_line("Ride armed: the next take (● Record) also records where you fly, as the viewer's path.", RECORD)
	elif s.get("auto_key", false):
		_set_mode_line("Auto-key on: moves and changes write keys at the playhead.", RECORD)
	elif s.get("key_animated", false):
		_set_mode_line("Keys on change: a change to something animated keys it; the rest is just set.", ACCENT)
	elif s.get("snap", false):
		_set_mode_line("Snap on: moves go by 10 cm and 15°, keys onto beats.", ACCENT)
	else:
		_set_mode_line("", ACCENT)
	var message: String = s.get("message", "")
	_message.text = message
	_message.visible = message != ""


## The toggles as they are in Studio (not what a press toggled).
func show_toggles(auto_key: bool, snap: bool, inspector: bool = false, timeline: bool = false, looping: bool = false, shelf: bool = false, recording: bool = false, ride: bool = false, miniature: bool = false, outliner: bool = false) -> void:
	if _tiles.is_empty():
		return
	_tiles[&"studio_toggle_autokey"].lit = auto_key
	_tiles[&"studio_toggle_snap"].lit = snap
	_tiles[&"studio_toggle_inspector"].lit = inspector
	_tiles[&"studio_toggle_timeline"].lit = timeline
	_tiles[&"studio_toggle_loop"].lit = looping
	_tiles[&"studio_toggle_shelf"].lit = shelf
	_tiles[&"studio_record"].lit = recording
	_tiles[&"studio_arm_ride"].lit = ride
	_tiles[&"studio_miniature"].lit = miniature
	_tiles[&"studio_toggle_outliner"].lit = outliner


## The help line: what the tile under the pointer does, else the mode line.
func _show_line() -> void:
	if _line == null:
		return
	var help := _help(_hovered)
	_line.text = help if help != "" else _mode_line
	_line.add_theme_color_override("font_color", WristTile.TEXT if help != "" else Color(_mode_color, 1.0).lerp(WristTile.TEXT, 0.35))
	_line_dot.visible = help == "" and _mode_line != ""
	_line_dot.queue_redraw()


func _set_mode_line(text: String, color: Color) -> void:
	if text == _mode_line and color == _mode_color:
		return
	_mode_line = text
	_mode_color = color
	_show_line()


static func _help(id: StringName) -> String:
	if id == &"studio_save":
		return "Save the SPScript (the file it was opened from)."
	for p in PAGES:
		for t in p:
			if t[0] == id:
				return t[3]
	return ""


func _half(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 76)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Only the other half does anything: it switches.
	b.pressed.connect(func():
		if not b.get_meta("on", false):
			_press(&"studio_toggle_mode"))
	parent.add_child(b)
	_style_half(b, false)
	return b


static func _style_half(b: Button, on: bool) -> void:
	if b.has_meta("on") and b.get_meta("on") == on:
		return
	b.set_meta("on", on)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(36)
		sb.bg_color = ACCENT if on else Color(0, 0, 0, 0)
		if state.begins_with("hover") and not on:
			sb.bg_color = Color(ACCENT, 0.15)
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color("0b1320") if on else WristTile.MUTED)


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The default font with tabular digits, so the clock doesn't jitter.
static func _tabular_font() -> Font:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	return f


static func _rule(parent: Control) -> void:
	var rule := ColorRect.new()
	rule.color = WristTile.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


## "01:23.40": minutes and hundredths (hours on top past an hour).
static func clock(t: float) -> String:
	t = maxf(t, 0.0)
	var m := floori(t / 60.0)
	if m >= 60:
		return "%d:%02d:%05.2f" % [m / 60, m % 60, fmod(t, 60.0)]
	return "%02d:%05.2f" % [m, fmod(t, 60.0)]


static func _ago(seconds: float) -> String:
	if seconds < 60.0:
		return "%d s" % floori(seconds)
	return "%d min" % floori(seconds / 60.0)
