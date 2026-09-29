class_name StudioTimelineRibbon
extends PanelContainer

## Studio's timeline ribbon: the ruler with beat and bar ticks, the song's
## waveform, cut markers and the loop region, a lane per object (its time
## on stage) and, under the selection's lane, a row per animated property
## with its keys (StudioTimeline works out what's where).
##
## Pointer (mouse, or the laser in the headset):
##   press on the ruler, waveform or a lane's time → scrub there (drag on)
##   press a key diamond → select it; drag it → retime it on release (one
##     undo step; onto the nearest beat while snapping is on)
##   the loop handles on the ruler → drag the in / out point
##   a lane's ends → drag when the object comes on / goes (one undo step;
##     onto beats while snapping); the end dragged to the piece's end stays on
##   a lane's block (between its ends) → drag it whole: both ends and the
##     object's keys inside it move together (one undo step); a press
##     without a drag scrubs there
##   a lane's name → select that object
##   wheel over the ruler or waveform (or Ctrl+wheel) → zoom about it;
##     Shift+wheel → scroll in time; wheel over the lanes → scroll them
##   the scroll bar along the bottom (the whole piece, with the sound's
##     outline): drag the view's window to scroll, pull its ends to zoom,
##     press beside it to jump there; the wheel over it scrolls in time
## The bar above: time, zoom − / + / fit, loop on / off, set in / out at the
## playhead, and for a selected key its interpolation (and bezier presets)
## and delete. *Grid…* opens the beat grid's controls instead: nudge it
## earlier / later, tempo − / +, ×2 / ½, tap tempo (tap along while it
## plays), and back to the detected grid; they write the piece's
## `media.beats`, so the player uses the same grid. While recording, the
## take's span shows red, and armed properties' rows are red. The same scene is the desktop's bottom strip and the
## headset's band at waist height (bigger there: `vr`, worked out when it's
## inside a SubViewport).

signal said(text: String)

const ACCENT := Color(0.3, 0.79, 0.94)
const RECORD := Color(1.0, 0.36, 0.36)
const KEY := Color(1.0, 0.85, 0.3)
## The shortest time on stage a lane end can be dragged to.
const MIN_SPAN := 0.1
const DIM := Color(0.72, 0.75, 0.8)
const PANEL_BG := Color(0.06, 0.06, 0.09, 0.92)
## Keys on change, in the switch's order: [mode, label, tip].
const KEY_MODES := [
	["off", "Off", "A change to something animated moves all its keys by the difference"],
	["animated", "Animated", "A change to something animated keys it here; still things are just set"],
	["all", "All", "Auto-key (Shift+I): every change keys at the playhead"],
]
const INTERPS := [["linear", "Linear"], ["ease", "Ease"], ["cubic", "Cubic"], ["step", "Step"],
	["ease_in", "Ease in"], ["ease_out", "Ease out"], ["ease_in_out", "In-out"], ["overshoot", "Overshoot"]]

var vr := false
var edits: StudioConfigEdits
var tools: StudioEditTools
var waveform: StudioWaveform
var loop: StudioLoop
var recorder: StudioRecorder
var view := StudioTimeline.new()
## The selected key: {ti, ki}, or {} for none.
var selected_key: Dictionary = {}

var _lanes: Array = []
var _rows: Array = []
var _cuts: Array = []
var _layout: Array = []  # [{kind: "lane" / "prop", y, h, id or row}]
var _needs_data := true
var _drag: Dictionary = {}  # {kind: scrub / key / loop_a / loop_b / lane_start / lane_end / lane_move / bar_move / bar_a / bar_b, ti, ki, id, si, t, from, lo, hi, dt, x0, grip}
var _vscroll := 0.0
var _fitted := false
var _canvas: Control
var _time: Label
var _loop_button: Button
var _key_bar: HBoxContainer
var _interp_buttons: Dictionary = {}
var _grid_button: Button
var _grid_bar: HBoxContainer
var _grid_label: Label
var _tap_button: Button
var _mode_bar: HBoxContainer
var _mode_buttons: Dictionary = {}  # key mode -> Button
var _taps: Array = []  # playhead times of the taps so far

# Sizes (scaled up in the headset).
var _k := 1.0
var _gutter := 150.0
var _ruler := 22.0
var _wave := 46.0
var _lane := 22.0
var _row := 20.0
var _bar := 26.0
var _fs := 14
# The scroll bar's outline of the whole sound: a peak per column, worked out
# again when the sound, the piece's length or the bar's width changes.
var _overview := PackedFloat32Array()
var _overview_key := []


func _ready() -> void:
	vr = vr or get_viewport() != get_tree().root
	_k = 1.8 if vr else 1.0
	_gutter *= _k
	_ruler *= _k
	_wave *= _k
	_lane *= _k
	_row *= _k
	_bar *= _k
	_fs = int(_fs * _k)
	var th := Theme.new()
	th.default_font_size = _fs
	theme = th
	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG
	bg.border_color = Color(ACCENT, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(8 * _k)
	add_theme_stylebox_override("panel", bg)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(6 * _k))
	add_child(rows)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", int(6 * _k))
	rows.add_child(bar)
	_time = Label.new()
	_time.custom_minimum_size.x = 150 * _k
	bar.add_child(_time)
	bar.add_child(_button("−", func(): _zoom_bar(1.0 / 1.6)))
	bar.add_child(_button("+", func(): _zoom_bar(1.6)))
	bar.add_child(_button("Fit", func():
		view.fit()
		_canvas.queue_redraw()))
	bar.add_child(_sep())
	_loop_button = _button("Loop", func():
		loop.on = not loop.on
		if loop.on and not loop.is_set():
			loop.set_in(_playhead())
		said.emit("Loop %s." % ("on" if loop.on else "off")))
	_loop_button.toggle_mode = true
	bar.add_child(_loop_button)
	bar.add_child(_button("[ In", func():
		loop.set_in(_playhead())
		said.emit("Loop from %s." % StudioStatus.timecode(loop.a))))
	bar.add_child(_button("Out ]", func():
		loop.set_out(_playhead())
		said.emit("Loop to %s." % StudioStatus.timecode(loop.b))))
	bar.add_child(_sep())
	var prev := _button("◆◀", func(): step_key(-1))
	prev.tooltip_text = "Previous key (Down): the selection's, or any with nothing selected"
	bar.add_child(prev)
	var next := _button("▶◆", func(): step_key(1))
	next.tooltip_text = "Next key (Up)"
	bar.add_child(next)
	bar.add_child(_sep())
	_grid_button = _button("Grid…", func(): _needs_data = true)
	_grid_button.toggle_mode = true
	bar.add_child(_grid_button)
	_grid_bar = HBoxContainer.new()
	_grid_bar.add_theme_constant_override("separation", int(4 * _k))
	_grid_bar.visible = false
	bar.add_child(_grid_bar)
	_grid_label = Label.new()
	_grid_label.custom_minimum_size.x = 190 * _k
	_grid_bar.add_child(_grid_label)
	_grid_bar.add_child(_button("◀ 10 ms", func(): _nudge_grid(-0.01, 0.0)))
	_grid_bar.add_child(_button("10 ms ▶", func(): _nudge_grid(0.01, 0.0)))
	_grid_bar.add_child(_button("− BPM", func(): _nudge_grid(0.0, -0.1)))
	_grid_bar.add_child(_button("+ BPM", func(): _nudge_grid(0.0, 0.1)))
	_grid_bar.add_child(_button("×2", func(): _nudge_grid(0.0, 0.0, 2.0)))
	_grid_bar.add_child(_button("½", func(): _nudge_grid(0.0, 0.0, 0.5)))
	_tap_button = _button("Tap", func(): tap())
	_grid_bar.add_child(_tap_button)
	_grid_bar.add_child(_button("Detected", func():
		if edits.model.set_beats(null, "Use the detected beat grid"):
			said.emit("Back to the detected beat grid.")))
	_key_bar = HBoxContainer.new()
	_key_bar.add_theme_constant_override("separation", int(4 * _k))
	bar.add_child(_key_bar)
	for it in INTERPS:
		var b := _button(it[1], func(): _set_interp(it[0]))
		b.toggle_mode = true
		_key_bar.add_child(b)
		_interp_buttons[it[0]] = b
	_key_bar.add_child(_button("Delete key", func(): _delete_key()))
	# Keys on change: what a change to something does (StudioEditTools).
	_mode_bar = HBoxContainer.new()
	_mode_bar.add_theme_constant_override("separation", int(4 * _k))
	bar.add_child(_mode_bar)
	var mode_label := Label.new()
	mode_label.text = "Keys on change:"
	mode_label.add_theme_color_override("font_color", DIM)
	_mode_bar.add_child(mode_label)
	for m in KEY_MODES:
		var b := _button(m[1], func(): set_key_mode(m[0]))
		b.toggle_mode = true
		b.tooltip_text = m[2]
		_mode_bar.add_child(b)
		_mode_buttons[m[0]] = b
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	rows.add_child(_canvas)


## The piece or the selection changed: gather the lanes and keys again.
func request_refresh() -> void:
	_needs_data = true


func _process(_delta: float) -> void:
	if edits == null or tools == null or not is_visible_in_tree():
		return
	var model := edits.model
	if model == null:
		return
	view.width = maxf(_canvas.size.x - _gutter, 1.0)
	var runner := tools.runner
	var duration := maxf(runner.effective_duration(), 1.0)
	if duration != view.duration:
		_needs_data = true  # lanes that stay on reach the end: the new one
	view.duration = duration
	if not _fitted and runner.effective_duration() > 0.0:
		_fitted = true
		view.fit()
	if _needs_data:
		_needs_data = false
		_lanes = StudioTimeline.lanes(model, view.duration)
		_rows = StudioTimeline.property_rows(model, tools.selected)
		_cuts = StudioTimeline.cuts(model)
		if not selected_key.is_empty() and not _key_exists(selected_key):
			selected_key = {}
	if runner.playing and _drag.is_empty():
		view.follow(runner.playhead)
	_time.text = StudioStatus.timecode(runner.playhead)
	_loop_button.set_pressed_no_signal(loop.on)
	_grid_bar.visible = _grid_button.button_pressed
	var g := _grid()
	_grid_label.text = "%.1f BPM · 1 at %.3f s" % [g.bpm, g.offset] if g != null and g.is_valid() else "No beat grid yet"
	_tap_button.text = "Tap (%d)" % _taps.size() if not _taps.is_empty() else "Tap"
	_key_bar.visible = not selected_key.is_empty() and not _grid_bar.visible
	_mode_bar.visible = not _key_bar.visible and not _grid_bar.visible
	var key_mode := key_mode_of(tools)
	for m in _mode_buttons:
		_mode_buttons[m].set_pressed_no_signal(m == key_mode)
	if _key_bar.visible:
		var mode := _mode_of(selected_key.ti, selected_key.ki)
		for m in _interp_buttons:
			_interp_buttons[m].set_pressed_no_signal(m == mode)
	_canvas.queue_redraw()


func _key_exists(k: Dictionary) -> bool:
	var tracks := edits.model.tracks()
	return k.ti < tracks.size() and typeof(tracks[k.ti].get("keyframes")) == TYPE_ARRAY and k.ki < tracks[k.ti].keyframes.size() \
			and _rows.any(func(r): return r.ti == k.ti)


## Key `ki` of track `ti`'s mode as the picker names it: a bezier preset
## when its handles are that preset's, else its interp.
func _mode_of(ti: int, ki: int) -> String:
	var kfs: Array = edits.model.tracks()[ti].keyframes
	var kf: Dictionary = kfs[ki]
	var mode := String(kf.get("interp", "linear"))
	if mode != "bezier" or ki + 1 >= kfs.size():
		return mode
	var next: Dictionary = kfs[ki + 1]
	var dt := float(next.get("t", 0.0)) - float(kf.get("t", 0.0))
	var out = kf.get("out")
	var into = next.get("in")
	if dt <= 0.0 or typeof(out) != TYPE_ARRAY or typeof(into) != TYPE_ARRAY or out.is_empty() or into.is_empty():
		return mode
	# The presets differ in their time handles (x1, x2), which don't depend
	# on the values.
	var x1: float = (out[0][0] if typeof(out[0]) == TYPE_ARRAY else out[0]) / dt
	var x2: float = 1.0 + (into[0][0] if typeof(into[0]) == TYPE_ARRAY else into[0]) / dt
	for name in EditModel.BEZIER_PRESETS:
		var p: Array = EditModel.BEZIER_PRESETS[name]
		if absf(p[0] - x1) < 0.01 and absf(p[2] - x2) < 0.01:
			return name
	return mode


func _playhead() -> float:
	return tools.runner.playhead if tools != null and tools.runner != null else 0.0


func _grid() -> BeatGrid:
	return tools.stage.beats.grid if tools != null and tools.stage != null and tools.stage.beats != null else null


# ---------- drawing ----------

func _draw_canvas() -> void:
	if edits == null or edits.model == null:
		return
	var c := _canvas
	var w := c.size.x
	var h := _lanes_bottom()
	var font := get_theme_default_font()
	var top := _ruler + _wave
	# Ruler and waveform backgrounds.
	c.draw_rect(Rect2(0, 0, w, _ruler), Color(1, 1, 1, 0.04))
	c.draw_rect(Rect2(_gutter, _ruler, w - _gutter, _wave), Color(0, 0, 0, 0.25))
	# Loop region, under everything.
	if loop.is_set():
		var la := _gutter + view.x_of(loop.a)
		var lb := _gutter + view.x_of(loop.b)
		c.draw_rect(Rect2(la, 0, lb - la, h), Color(ACCENT, 0.16 if loop.on else 0.07))
	# Beat ticks.
	var pxs := view.px_per_second()
	for tk in StudioTimeline.ticks(_grid(), view.start, view.start + view.span, pxs):
		var x := _gutter + view.x_of(tk.t)
		c.draw_line(Vector2(x, _ruler * (0.35 if tk.bar else 0.65)), Vector2(x, h), Color(1, 1, 1, 0.16 if tk.bar else 0.06), 1.0)
	# Time labels.
	var step := _label_step(pxs)
	var t := ceilf(view.start / step) * step
	while t <= view.start + view.span:
		var x := _gutter + view.x_of(t)
		c.draw_line(Vector2(x, 0), Vector2(x, _ruler * 0.35), DIM, 1.0)
		c.draw_string(font, Vector2(x + 3, _ruler * 0.8), StudioStatus.timecode(t).trim_suffix(".00"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(_fs * 0.8), DIM)
		t += step
	# Waveform: one bar per pixel column.
	if waveform != null and not waveform.peaks.is_empty():
		var mid := _ruler + _wave * 0.5
		var col := Color(0.55, 0.62, 0.78, 0.75)
		var x := 0.0
		var colw := maxf(1.0, _k)
		while x < view.width:
			var p := waveform.peak_between(view.t_of(x), view.t_of(x + colw))
			var half := p * _wave * 0.45
			c.draw_rect(Rect2(_gutter + x, mid - half, colw, maxf(half * 2.0, 1.0)), col)
			x += colw
	elif waveform != null and waveform.is_loading():
		c.draw_string(font, Vector2(_gutter + 8, _ruler + _wave * 0.6), "Reading the sound…", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, DIM)
	# Lanes and the selection's properties.
	_layout.clear()
	var y := top + 4 * _k - _vscroll
	for lane in _lanes:
		var sel: bool = lane.id == tools.selected
		_layout.append({"kind": "lane", "y": y, "h": _lane, "id": lane.id})
		if y + _lane > top and y < h:
			if sel:
				c.draw_rect(Rect2(0, y, w, _lane), Color(ACCENT, 0.12))
			var viewer: bool = lane.id == ScriptFormat.VIEWER
			c.draw_string(font, Vector2(6 * _k + lane.depth * 12 * _k, y + _lane * 0.75), "Viewer" if viewer else lane.id, HORIZONTAL_ALIGNMENT_LEFT,
					_gutter - 10 * _k - lane.depth * 12 * _k, _fs, (KEY if viewer else Color.WHITE) if sel else (Color(KEY, 0.8) if viewer else DIM))
			for si in lane.spans.size():
				var s: Array = _shown_span(lane, si)
				var x0 := maxf(_gutter + view.x_of(s[0]), _gutter)
				var x1 := minf(_gutter + view.x_of(s[1]), w)
				if x1 > x0:
					c.draw_rect(Rect2(x0, y + _lane * 0.25, x1 - x0, _lane * 0.5), Color(ACCENT, 0.75 if sel else 0.35))
					# End handles: grab them to change when it comes on / goes.
					var hw := maxf(2.0, 2.0 * _k)
					for ex in [_gutter + view.x_of(s[0]), _gutter + view.x_of(s[1])]:
						if ex >= _gutter and ex <= w and not viewer:
							c.draw_rect(Rect2(ex - hw, y + _lane * 0.12, hw * 2.0, _lane * 0.76), Color(1, 1, 1, 0.9 if sel else 0.5))
			# The viewer's lane: where the ride goes or turns too fast for
			# comfort, in red.
			for wr in lane.get("warn", []):
				var wx0 := maxf(_gutter + view.x_of(wr[0]), _gutter)
				var wx1 := minf(_gutter + view.x_of(wr[1]), w)
				if wx1 > wx0:
					c.draw_rect(Rect2(wx0, y + _lane * 0.2, wx1 - wx0, _lane * 0.6), Color(RECORD, 0.85))
		y += _lane
		if not sel:
			continue
		for row in _rows:
			_layout.append({"kind": "prop", "y": y, "h": _row, "row": row})
			if y + _row > top and y < h:
				var armed := _row_armed(row)
				c.draw_string(font, Vector2(18 * _k + lane.depth * 12 * _k, y + _row * 0.75), ("● " if armed else "") + row.label, HORIZONTAL_ALIGNMENT_LEFT,
						_gutter - 22 * _k, int(_fs * 0.85), RECORD if armed else DIM)
				c.draw_line(Vector2(_gutter, y + _row * 0.5), Vector2(w, y + _row * 0.5), Color(1, 1, 1, 0.07), 1.0)
				for k in row.keys:
					var kt: float = k.t
					var chosen: bool = not selected_key.is_empty() and selected_key.ti == row.ti and selected_key.ki == k.ki
					if chosen and _drag.get("kind", "") == "key":
						kt = _drag.t
					elif _drag.get("kind", "") == "lane_move" and _drag.id == lane.id:
						# Keys inside the block being dragged move with it.
						var s: Array = lane.spans[_drag.si]
						if kt >= float(s[0]) - EditModel.SAME_TIME and kt <= float(s[1]) + EditModel.SAME_TIME:
							kt += float(_drag.dt)
					_diamond(Vector2(_gutter + view.x_of(kt), y + _row * 0.5), _row * 0.36, KEY if chosen else Color.WHITE, chosen)
			y += _row
	# The take being recorded: red from where it records to the playhead;
	# before that (the pre-roll), a red line where it will start.
	if recorder != null and recorder.is_active():
		var span := recorder.recorded_span()
		var rx := _gutter + view.x_of(recorder.from)
		if not span.is_empty():
			var rx1 := _gutter + view.x_of(span[1])
			c.draw_rect(Rect2(rx, _ruler, maxf(rx1 - rx, 1.0), h - _ruler), Color(RECORD, 0.16))
		c.draw_line(Vector2(rx, 0), Vector2(rx, h), RECORD, maxf(2.0, 1.5 * _k))
		if recorder.until >= 0.0:
			var ux := _gutter + view.x_of(recorder.until)
			c.draw_line(Vector2(ux, 0), Vector2(ux, h), Color(RECORD, 0.6), maxf(1.0, _k))
	# Cuts over the lanes.
	for ct in _cuts:
		var x := _gutter + view.x_of(ct)
		if x >= _gutter and x <= w:
			c.draw_line(Vector2(x, _ruler), Vector2(x, h), Color(1.0, 0.82, 0.4, 0.7), maxf(1.0, _k))
			c.draw_string(font, Vector2(x + 3, _ruler + _fs), "cut", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_fs * 0.8), Color(1.0, 0.82, 0.4))
	# Loop handles on the ruler.
	if loop.is_set():
		for p in [loop.a, loop.b]:
			var x := _gutter + view.x_of(p)
			var s := _ruler * 0.5
			c.draw_colored_polygon(PackedVector2Array([Vector2(x - s, 0), Vector2(x + s, 0), Vector2(x, s * 1.2)]), ACCENT)
	# Gutter edge and the playhead.
	c.draw_line(Vector2(_gutter, 0), Vector2(_gutter, h), Color(1, 1, 1, 0.12), 1.0)
	var px := _gutter + view.x_of(_playhead())
	if px >= _gutter and px <= w:
		c.draw_line(Vector2(px, 0), Vector2(px, h), Color.WHITE, maxf(2.0, 1.5 * _k))
	_draw_bar(font)


## Where the lanes end: the scroll bar is under them.
func _lanes_bottom() -> float:
	return _canvas.size.y - _bar - 4 * _k


## The scroll bar's rectangle, on the canvas.
func _bar_rect() -> Rect2:
	return Rect2(_gutter, _canvas.size.y - _bar, maxf(_canvas.size.x - _gutter, 1.0), _bar)


## Time `t` on the scroll bar (the whole piece across it), and back.
func _bar_x(t: float) -> float:
	var r := _bar_rect()
	return r.position.x + t / maxf(view.duration, 0.001) * r.size.x


func _bar_t(x: float) -> float:
	var r := _bar_rect()
	return clampf((x - r.position.x) / r.size.x * view.duration, 0.0, view.duration)


## The scroll bar: the whole piece's sound, the loop, the playhead and the
## view's window with its ends (drag it to scroll, pull an end to zoom).
func _draw_bar(font: Font) -> void:
	var c := _canvas
	var r := _bar_rect()
	var top := _lanes_bottom()
	c.draw_rect(Rect2(0, top, c.size.x, c.size.y - top), Color(PANEL_BG, 1.0))
	c.draw_string(font, Vector2(6 * _k, r.position.y + r.size.y * 0.68), "0:00 → " + StudioStatus.timecode(view.duration).trim_suffix(".00"),
			HORIZONTAL_ALIGNMENT_LEFT, _gutter - 10 * _k, int(_fs * 0.8), DIM)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.08, 0.11)
	bg.border_color = Color(1, 1, 1, 0.1)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(int(5 * _k))
	c.draw_style_box(bg, r)
	# The sound's outline.
	var colw := maxf(2.0, 2.0 * _k)
	var n := int(r.size.x / colw)
	var key := [waveform.peaks.size() if waveform != null else 0, n, view.duration]
	if key != _overview_key:
		_overview_key = key
		_overview.resize(n)
		for i in n:
			_overview[i] = waveform.peak_between(view.duration * i / n, view.duration * (i + 1) / n) if key[0] > 0 else 0.0
	var mid := r.position.y + r.size.y * 0.5
	for i in n:
		var half := _overview[i] * r.size.y * 0.38
		if half > 0.5:
			c.draw_rect(Rect2(r.position.x + i * colw, mid - half, colw * 0.6, half * 2.0), Color(0.36, 0.41, 0.52))
	if loop.is_set():
		var la := _bar_x(loop.a)
		c.draw_rect(Rect2(la, r.position.y, maxf(_bar_x(loop.b) - la, 1.0), r.size.y), Color(ACCENT, 0.14 if loop.on else 0.06))
	var px := _bar_x(_playhead())
	c.draw_line(Vector2(px, r.position.y), Vector2(px, r.end.y), Color(1, 1, 1, 0.8), maxf(1.0, _k))
	var win := _bar_window()
	var wa: float = win[0]
	var wb: float = win[1]
	var active := String(_drag.get("kind", "")).begins_with("bar_")
	var box := StyleBoxFlat.new()
	box.bg_color = Color(ACCENT, 0.3 if active else 0.18)
	box.border_color = ACCENT
	box.set_border_width_all(int(maxf(1.0, 1.5 * _k)))
	box.set_corner_radius_all(int(5 * _k))
	c.draw_style_box(box, Rect2(wa, r.position.y + 1, wb - wa, r.size.y - 2))
	# Its ends: the grips that zoom.
	var gw := maxf(3.0, 3.0 * _k)
	for gx in [wa, wb]:
		c.draw_rect(Rect2(gx - gw * 0.5, r.position.y + r.size.y * 0.22, gw, r.size.y * 0.56), Color.WHITE)


## The view's window on the scroll bar: [left x, right x], never narrower
## than a grip.
func _bar_window() -> Array:
	var wa := _bar_x(view.start)
	return [wa, maxf(_bar_x(view.start + view.span), wa + 6 * _k)]


## What's under `at` on the scroll bar: {kind: "bar_a" / "bar_b" (an end),
## "bar_move" (the window), "bar_jump" (beside it), t}, or {} off the bar.
func _bar_hit(at: Vector2) -> Dictionary:
	var r := _bar_rect()
	if at.y < r.position.y or at.x < r.position.x:
		return {}
	var g := 8.0 * _k
	var win := _bar_window()
	var wa: float = win[0]
	var wb: float = win[1]
	var t := _bar_t(at.x)
	# A narrow window's ends only grab from outside it, so it can still be moved.
	var inside := g if wb - wa >= 3.0 * g else 0.0
	if at.x >= wa - g and at.x <= wa + inside:
		return {"kind": "bar_a", "t": t}
	if at.x <= wb + g and at.x >= wb - inside:
		return {"kind": "bar_b", "t": t}
	if at.x > wa and at.x < wb:
		return {"kind": "bar_move", "t": t}
	return {"kind": "bar_jump", "t": t}


## Span `si` of `lane`, as it's being dragged if it is.
func _shown_span(lane: Dictionary, si: int) -> Array:
	var s: Array = lane.spans[si]
	if _drag.get("id", "") == lane.id and _drag.get("si", -1) == si:
		match _drag.kind:
			"lane_start":
				return [_drag.t, s[1]]
			"lane_end":
				return [s[0], _drag.t]
			"lane_move":
				return [float(s[0]) + _drag.dt, float(s[1]) + _drag.dt]
	return s


func _diamond(at: Vector2, r: float, color: Color, outlined: bool) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	_canvas.draw_colored_polygon(pts, color)
	if outlined:
		pts.append(pts[0])
		_canvas.draw_polyline(pts, RECORD, maxf(2.0, _k * 1.5))


## Seconds between time labels: the first nice step at least ~80 px apart.
func _label_step(pxs: float) -> float:
	for s in [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0]:
		if s * pxs >= 80.0 * _k:
			return s
	return 1200.0


# ---------- pointer ----------

func _canvas_input(event: InputEvent) -> void:
	if edits == null or edits.model == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if mb.shift_pressed or mb.position.y >= _lanes_bottom():
				view.scroll((-0.15 if up else 0.15) * view.span)
			elif mb.ctrl_pressed or mb.position.y < _ruler + _wave:
				view.zoom(1.25 if up else 0.8, view.t_of(mb.position.x - _gutter) if mb.position.x > _gutter else _playhead())
			else:
				_vscroll = maxf(_vscroll + (-_lane * 2 if up else _lane * 2), 0.0)
			_canvas.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position)
			else:
				_release()
			_canvas.accept_event()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_move((event as InputEventMouseMotion).position)
		_canvas.accept_event()


## What's under `at`: {kind: "loop_a" / "loop_b" / "key" / "lane_start" /
## "lane_end" / "name" / "time", ...}.
func hit(at: Vector2) -> Dictionary:
	if at.y >= _lanes_bottom():
		return _bar_hit(at)
	var r := 10.0 * _k
	if at.y < _ruler and loop.is_set():
		for p in [["loop_a", loop.a], ["loop_b", loop.b]]:
			if absf(_gutter + view.x_of(p[1]) - at.x) <= r:
				return {"kind": p[0]}
	for item in _layout:
		if at.y < item.y or at.y >= item.y + item.h:
			continue
		if at.x < _gutter:
			return {"kind": "name", "id": item.id} if item.kind == "lane" else {}
		if item.kind == "lane":
			var end := _lane_end_at(item.id, at.x, r)
			if not end.is_empty():
				return end
			var body := _lane_body_at(item.id, at.x)
			if not body.is_empty():
				return body
		if item.kind == "prop":
			var best := {}
			var best_d := r
			for k in item.row.keys:
				var d := absf(_gutter + view.x_of(k.t) - at.x)
				if d <= best_d:
					best_d = d
					best = {"kind": "key", "ti": item.row.ti, "ki": k.ki, "t": k.t}
			if not best.is_empty():
				return best
	return {"kind": "time", "t": clampf(view.t_of(at.x - _gutter), 0.0, view.duration)} if at.x >= _gutter else {}


## The lane end of `id` within `r` pixels of `x`: {kind: "lane_start" /
## "lane_end", id, si, t}, or {}.
func _lane_end_at(id: String, x: float, r: float) -> Dictionary:
	if id.begins_with("$"):
		return {}  # the viewer is always there: its keys say where it is
	var lane := _lane_of(id)
	var best := {}
	var best_d := r
	for si in lane.get("spans", []).size():
		for e in [["lane_start", 0], ["lane_end", 1]]:
			var t: float = lane.spans[si][e[1]]
			var d := absf(_gutter + view.x_of(t) - x)
			if d <= best_d:
				best_d = d
				best = {"kind": e[0], "id": id, "si": si, "t": t}
	return best


## The span of `id` whose block is under `x`: {kind: "lane_body", id, si,
## t (the time there)}, or {}.
func _lane_body_at(id: String, x: float) -> Dictionary:
	if id.begins_with("$"):
		return {}
	var lane := _lane_of(id)
	var t := view.t_of(x - _gutter)
	for si in lane.get("spans", []).size():
		if t > float(lane.spans[si][0]) and t < float(lane.spans[si][1]):
			return {"kind": "lane_body", "id": id, "si": si, "t": t}
	return {}


func _lane_of(id: String) -> Dictionary:
	for lane in _lanes:
		if lane.id == id:
			return lane
	return {}


func _press(at: Vector2) -> void:
	var h := hit(at)
	match h.get("kind", ""):
		"loop_a", "loop_b":
			_drag = {"kind": h.kind}
		"bar_a", "bar_b":
			_drag = {"kind": h.kind}
		"bar_move":
			_drag = {"kind": "bar_move", "grip": h.t - view.start}
		"bar_jump":
			# Centre the view there, then carry on as a drag of the window.
			view.scroll_to(h.t - view.span * 0.5)
			_drag = {"kind": "bar_move", "grip": h.t - view.start}
		"lane_start", "lane_end":
			var lim := StudioTimeline.span_limits(_lanes, _lane_of(h.id), h.si, view.duration)
			_drag = {"kind": h.kind, "id": h.id, "si": h.si, "t": h.t, "from": h.t, "lo": lim[0], "hi": lim[1]}
		"lane_body":
			var lim := StudioTimeline.span_limits(_lanes, _lane_of(h.id), h.si, view.duration)
			_drag = {"kind": "lane_move", "id": h.id, "si": h.si, "t": h.t, "from": h.t, "lo": lim[0], "hi": lim[1],
				"dt": 0.0, "x0": at.x, "moved": false}
		"key":
			selected_key = {"ti": h.ti, "ki": h.ki}
			_drag = {"kind": "key", "ti": h.ti, "ki": h.ki, "t": h.t, "from": h.t}
		"name":
			tools.select(h.id)
		"time":
			_drag = {"kind": "scrub"}
			tools.stage.seek_to(h.t)


func _move(at: Vector2) -> void:
	var t := clampf(view.t_of(at.x - _gutter), 0.0, view.duration)
	match _drag.kind:
		"bar_move":
			view.scroll_to(_bar_t(at.x) - float(_drag.grip))
		"bar_a", "bar_b":
			view.pull_end(_drag.kind == "bar_a", _bar_t(at.x))
		"scrub":
			tools.stage.seek_to(t)
		"loop_a":
			loop.a = clampf(t, 0.0, loop.b - StudioLoop.MIN_LENGTH)
		"loop_b":
			loop.b = maxf(t, loop.a + StudioLoop.MIN_LENGTH)
		"key":
			_drag.t = StudioTimeline.snap(t, _grid()) if tools.snap else t
		"lane_move":
			# A few pixels before it counts as a drag (a press alone scrubs).
			_drag.moved = _drag.moved or absf(at.x - float(_drag.x0)) > 4.0 * _k
			if not _drag.moved:
				return
			var span: Array = _lane_of(_drag.id).spans[_drag.si]
			var start := float(span[0]) + (t - float(_drag.from))
			if tools.snap:
				start = StudioTimeline.snap(start, _grid())
			_drag.dt = StudioTimeline.clamp_shift(span, [_drag.lo, _drag.hi], start - float(span[0]))
		"lane_start", "lane_end":
			var span: Array = _lane_of(_drag.id).spans[_drag.si]
			t = StudioTimeline.snap(t, _grid()) if tools.snap else t
			if _drag.kind == "lane_start":
				_drag.t = clampf(t, _drag.lo, span[1] - MIN_SPAN)
			else:
				_drag.t = clampf(t, span[0] + MIN_SPAN, _drag.hi)


func _release() -> void:
	var d := _drag
	_drag = {}
	if d.get("kind", "") == "lane_move":
		if not d.moved:
			tools.stage.seek_to(float(d.from))
		elif absf(float(d.dt)) >= 0.001:
			move_lane(d.id, d.si, float(d.dt))
		return
	if d.get("kind", "") not in ["key", "lane_start", "lane_end"] or absf(float(d.t) - float(d.from)) < 0.001:
		return
	if d.kind == "key":
		retime(d.ti, d.ki, float(d.t))
	else:
		move_lane_end(d.id, d.si, d.kind == "lane_start", float(d.t))


## Span `si` of object `id` now starts (or ends) at `t`: its spawn moves;
## its despawn moves, or one is added; dragged to the piece's end, it stays
## on (its despawn goes). One undo step.
func move_lane_end(id: String, si: int, start: bool, t: float) -> bool:
	var lane := _lane_of(id)
	if lane.is_empty() or si < 0 or si >= lane.spans.size():
		return false
	var ends: Dictionary = lane.ends[si]
	var model := edits.model
	var done := false
	t = snappedf(t, 0.001)
	if start:
		done = model.set_spawn_time(ends.spawn, t)
	elif ends.despawn >= 0:
		var last: bool = si == lane.spans.size() - 1
		done = model.remove_despawn(ends.despawn) if last and t >= view.duration - 0.01 else model.set_despawn_time(ends.despawn, t)
	elif t < float(lane.spans[si][1]) - 0.001:
		done = model.add_despawn(id, t)
	if done:
		said.emit(model.undo_label() + ".")
		_needs_data = true
	return done


## "off", "animated" or "all" (auto-key) for `t`'s settings.
static func key_mode_of(t: StudioEditTools) -> String:
	return "all" if t.auto_key else ("animated" if t.key_animated else "off")


func set_key_mode(mode: String) -> void:
	tools.auto_key = mode == "all"
	tools.key_animated = mode == "animated"
	for m in KEY_MODES:
		if m[0] == mode:
			said.emit("Keys on change: %s. %s." % [m[1], m[2]])


## Jump the playhead to the next key (`dir` 1) or the previous one (-1):
## the selection's, or any with nothing selected. False if there's none.
func step_key(dir: int) -> bool:
	if edits == null or edits.model == null:
		return false
	var times := StudioTimeline.key_times(edits.model, tools.selected)
	var t := StudioTimeline.step_key(times, _playhead(), dir)
	var whose := tools.selected if tools.selected != "" else "the piece"
	if t < 0.0:
		said.emit("No key %s here for %s." % ["after" if dir > 0 else "before", whose])
		return false
	tools.stage.seek_to(t)
	said.emit("Key of %s at %s." % [whose, StudioStatus.timecode(t)])
	return true


## Span `si` of object `id` moves by `dt` as a whole: when it comes on,
## when it goes (a despawn is added if it stayed on to the end) and its keys
## inside the span. One undo step.
func move_lane(id: String, si: int, dt: float) -> bool:
	var lane := _lane_of(id)
	if lane.is_empty() or si < 0 or si >= lane.spans.size():
		return false
	var span: Array = lane.spans[si]
	dt = snappedf(StudioTimeline.clamp_shift(span, StudioTimeline.span_limits(_lanes, lane, si, view.duration), dt), 0.001)
	if absf(dt) < 0.001:
		return false
	var ends: Dictionary = lane.ends[si]
	var model := edits.model
	var s0 := float(span[0])
	var s1 := float(span[1])
	var label := "Move %s to %s" % [id, StudioStatus.timecode(s0 + dt)]
	var done := model.batch(label, func():
		# Keys first: the spawn's index doesn't change when keys move.
		for ti in model.tracks().size():
			var tr: Dictionary = model.tracks()[ti]
			if typeof(tr.get("keyframes")) != TYPE_ARRAY or String(tr.get("target", "")).split(".")[0] != id:
				continue
			var kfs: Array = tr.keyframes.duplicate(true)
			var moved := false
			for k in kfs:
				var kt := float(k.get("t", 0.0))
				if kt >= s0 - EditModel.SAME_TIME and kt <= s1 + EditModel.SAME_TIME:
					k.t = snappedf(kt + dt, 0.001)
					moved = true
			if moved:
				kfs.sort_custom(func(a, b): return float(a.t) < float(b.t))
				model.set_keyframes(ti, kfs)
		model.set_spawn_time(ends.spawn, snappedf(s0 + dt, 0.001))
		if ends.despawn >= 0:
			model.set_despawn_time(ends.despawn, snappedf(s1 + dt, 0.001))
		elif dt < 0.0:
			model.add_despawn(id, snappedf(s1 + dt, 0.001)))
	if done:
		said.emit(label + ".")
		_needs_data = true
	return done


## Move key `ki` of track `ti` to `t` (one undo step) and keep it selected.
func retime(ti: int, ki: int, t: float) -> bool:
	if not edits.model.move_key(ti, ki, t):
		return false
	var kfs: Array = edits.model.tracks()[ti].keyframes
	for i in kfs.size():
		if absf(float(kfs[i].t) - t) < EditModel.SAME_TIME:
			selected_key = {"ti": ti, "ki": i}
	said.emit(edits.model.undo_label() + ".")
	_needs_data = true
	return true


func _set_interp(mode: String) -> void:
	if selected_key.is_empty():
		return
	if edits.model.set_key_interp(selected_key.ti, selected_key.ki, mode):
		said.emit(edits.model.undo_label() + ".")


func _delete_key() -> void:
	if selected_key.is_empty():
		return
	var k := selected_key
	selected_key = {}
	if edits.model.delete_key(k.ti, k.ki):
		said.emit(edits.model.undo_label() + ".")


## Whether a property row's track is armed for recording.
func _row_armed(row: Dictionary) -> bool:
	if recorder == null or recorder.armed.is_empty():
		return false
	var track: Dictionary = edits.model.tracks()[row.ti]
	for a in recorder.armed.values():
		if "%s.%s" % [a.id, a.field.slot] == track.get("target") and a.field.param == track.get("param"):
			return true
	return false


## Move the beat grid by `seconds`, change its tempo by `bpm_step`, or
## multiply it (×2, ½): written to the piece (one undo step).
func _nudge_grid(seconds: float, bpm_step: float, factor: float = 1.0) -> void:
	var g := _grid()
	if g == null or not g.is_valid():
		said.emit("No beat grid yet: tap one (Tap, while it plays).")
		return
	var ng := BeatGrid.make(g.bpm * factor + bpm_step, g.offset + seconds, g.beats_per_bar)
	var what := "Beat grid %s" % ("%+d ms" % roundi(seconds * 1000.0) if seconds != 0.0 else "%.1f BPM" % ng.bpm)
	if edits.model.set_beats(ng.to_dict(), what):
		said.emit(what + ".")


## A tap along with the music (while it plays): from the fourth tap in a
## row the taps set the grid, the last tap a downbeat.
func tap() -> void:
	var t := _playhead()
	if not _taps.is_empty() and (t <= _taps.back() or t - _taps.back() > StudioTimeline.TAP_GAP):
		_taps.clear()
	_taps.append(t)
	var g := StudioTimeline.tap_tempo(_taps)
	if g == null:
		said.emit("Tap %d: keep tapping on the beat." % _taps.size())
		return
	var what := "Beat grid tapped: %.1f BPM" % g.bpm
	if edits.model.set_beats(g.to_dict(), what):
		said.emit(what + ".")


func _zoom_bar(factor: float) -> void:
	view.zoom(factor, _playhead())
	_canvas.queue_redraw()


# ---------- widgets ----------

func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	# At least square: "−" and "+" are whole targets too.
	b.custom_minimum_size = Vector2(_fs * 1.7, _fs * 1.7)
	b.pressed.connect(on_press)
	return b


func _sep() -> Control:
	var s := Control.new()
	s.custom_minimum_size.x = 10 * _k
	return s
