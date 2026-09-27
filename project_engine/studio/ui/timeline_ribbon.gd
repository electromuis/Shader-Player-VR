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
##   a lane's name → select that object
##   wheel over the ruler or waveform (or Ctrl+wheel) → zoom about it;
##     Shift+wheel → scroll in time; wheel over the lanes → scroll them
## The bar above: time, zoom − / + / fit, loop on / off, set in / out at the
## playhead, and for a selected key its interpolation (and bezier presets)
## and delete. The same scene is the desktop's bottom strip and the
## headset's band at waist height (bigger there: `vr`, worked out when it's
## inside a SubViewport).

signal said(text: String)

const ACCENT := Color(0.3, 0.79, 0.94)
const RECORD := Color(1.0, 0.36, 0.36)
const KEY := Color(1.0, 0.85, 0.3)
const DIM := Color(0.72, 0.75, 0.8)
const PANEL_BG := Color(0.06, 0.06, 0.09, 0.92)
const INTERPS := [["linear", "Linear"], ["ease", "Ease"], ["cubic", "Cubic"], ["step", "Step"],
	["ease_in", "Ease in"], ["ease_out", "Ease out"], ["ease_in_out", "In-out"], ["overshoot", "Overshoot"]]

var vr := false
var edits: StudioConfigEdits
var tools: StudioEditTools
var waveform: StudioWaveform
var loop: StudioLoop
var view := StudioTimeline.new()
## The selected key: {ti, ki}, or {} for none.
var selected_key: Dictionary = {}

var _lanes: Array = []
var _rows: Array = []
var _cuts: Array = []
var _layout: Array = []  # [{kind: "lane" / "prop", y, h, id or row}]
var _needs_data := true
var _drag: Dictionary = {}  # {kind: scrub / key / loop_a / loop_b, ti, ki, t, from}
var _vscroll := 0.0
var _fitted := false
var _canvas: Control
var _time: Label
var _loop_button: Button
var _key_bar: HBoxContainer
var _interp_buttons: Dictionary = {}

# Sizes (scaled up in the headset).
var _k := 1.0
var _gutter := 150.0
var _ruler := 22.0
var _wave := 46.0
var _lane := 22.0
var _row := 20.0
var _fs := 14


func _ready() -> void:
	vr = vr or get_viewport() != get_tree().root
	_k = 1.8 if vr else 1.0
	_gutter *= _k
	_ruler *= _k
	_wave *= _k
	_lane *= _k
	_row *= _k
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
	_key_bar = HBoxContainer.new()
	_key_bar.add_theme_constant_override("separation", int(4 * _k))
	bar.add_child(_key_bar)
	for it in INTERPS:
		var b := _button(it[1], func(): _set_interp(it[0]))
		b.toggle_mode = true
		_key_bar.add_child(b)
		_interp_buttons[it[0]] = b
	_key_bar.add_child(_button("Delete key", func(): _delete_key()))
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
	view.duration = maxf(runner.effective_duration(), 1.0)
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
	_key_bar.visible = not selected_key.is_empty()
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
	var h := c.size.y
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
			c.draw_string(font, Vector2(6 * _k + lane.depth * 12 * _k, y + _lane * 0.75), lane.id, HORIZONTAL_ALIGNMENT_LEFT,
					_gutter - 10 * _k - lane.depth * 12 * _k, _fs, Color.WHITE if sel else DIM)
			for s in lane.spans:
				var x0 := maxf(_gutter + view.x_of(s[0]), _gutter)
				var x1 := minf(_gutter + view.x_of(s[1]), w)
				if x1 > x0:
					c.draw_rect(Rect2(x0, y + _lane * 0.25, x1 - x0, _lane * 0.5), Color(ACCENT, 0.75 if sel else 0.35))
		y += _lane
		if not sel:
			continue
		for row in _rows:
			_layout.append({"kind": "prop", "y": y, "h": _row, "row": row})
			if y + _row > top and y < h:
				c.draw_string(font, Vector2(18 * _k + lane.depth * 12 * _k, y + _row * 0.75), row.label, HORIZONTAL_ALIGNMENT_LEFT,
						_gutter - 22 * _k, int(_fs * 0.85), DIM)
				c.draw_line(Vector2(_gutter, y + _row * 0.5), Vector2(w, y + _row * 0.5), Color(1, 1, 1, 0.07), 1.0)
				for k in row.keys:
					var kt: float = k.t
					var chosen: bool = not selected_key.is_empty() and selected_key.ti == row.ti and selected_key.ki == k.ki
					if chosen and _drag.get("kind", "") == "key":
						kt = _drag.t
					_diamond(Vector2(_gutter + view.x_of(kt), y + _row * 0.5), _row * 0.36, KEY if chosen else Color.WHITE, chosen)
			y += _row
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
			if mb.shift_pressed:
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


## What's under `at`: {kind: "loop_a" / "loop_b" / "key" / "name" / "time", ...}.
func hit(at: Vector2) -> Dictionary:
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


func _press(at: Vector2) -> void:
	var h := hit(at)
	match h.get("kind", ""):
		"loop_a", "loop_b":
			_drag = {"kind": h.kind}
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
		"scrub":
			tools.stage.seek_to(t)
		"loop_a":
			loop.a = clampf(t, 0.0, loop.b - StudioLoop.MIN_LENGTH)
		"loop_b":
			loop.b = maxf(t, loop.a + StudioLoop.MIN_LENGTH)
		"key":
			_drag.t = StudioTimeline.snap(t, _grid()) if tools.snap else t


func _release() -> void:
	var d := _drag
	_drag = {}
	if d.get("kind", "") != "key" or absf(float(d.t) - float(d.from)) < 0.001:
		return
	retime(d.ti, d.ki, float(d.t))


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


func _zoom_bar(factor: float) -> void:
	view.zoom(factor, _playhead())
	_canvas.queue_redraw()


# ---------- widgets ----------

func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = _fs * 1.7
	b.pressed.connect(on_press)
	return b


func _sep() -> Control:
	var s := Control.new()
	s.custom_minimum_size.x = 10 * _k
	return s
