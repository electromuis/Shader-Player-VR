class_name StudioInspector
extends PanelContainer

## Studio's inspector: everything about the selected object, in sections
## (transform, surface, display, the layer's shader, the pixel effects and
## vertex effects, modifiers), with controls generated from the shaders'
## hints. Each property has a key diamond: ◆ a key at the playhead, ◇
## animated, • still (tap it to add or remove a key at the playhead), and a
## ↺ back to its default. The transform is typed numbers (a row folds out a
## slider per axis). Each effect list is compact: a row per effect (≡ drag
## to reorder, on / off, its key state, ✕), the chosen one unfolded for its
## settings, and a master switch for the whole list.
##
## It's a view of StudioConfigEdits: dragging a control shows the value live
## (preview), letting go writes it as one undoable step (commit), the way
## auto-key says. The same scene is the desktop's side panel and, in the
## headset, a panel beside the selection (bigger text there: `vr`, which it
## works out itself when it's inside a SubViewport).

signal said(text: String)
signal close_requested
## – : fold the panel to its tab (the wrist's Inspector button).
signal minimize_requested
## A Studio command from a button here (the viewer's: key it, cut, arm the
## ride).
signal action(id: StringName)

const ACCENT := Color(0.3, 0.79, 0.94)
const RECORD := Color(1.0, 0.36, 0.36)
const DIM := Color(0.72, 0.75, 0.8)
## A diamond for a change made here but not keyed yet.
const UNKEYED := Color(1.0, 0.65, 0.2)
const PANEL_BG := Color(0.06, 0.06, 0.09, 0.92)
const ROW_BG := Color(0.11, 0.13, 0.18)
## A change made without a drag (a click, the colour wheel) is written once
## it has been left alone this long.
const SETTLE := 0.6
## How often shown values follow the playhead (seconds).
const REFRESH := 0.1
## Sections open when first shown (the rest start folded).
const OPEN_BY_DEFAULT := ["Transform", "Surface", "Display", "Layer shader", "Pixel effects", "Vertex effects", "Camera effects"]
## The effect lists' sections.
const LISTS := {EditModel.EFFECTS: {"title": "Pixel effects", "add": "+ Add effect", "menu": "add_effect", "slot": "effect"},
	EditModel.VERTEX_EFFECTS: {"title": "Vertex effects", "add": "+ Add vertex effect", "menu": "add_vertex", "slot": "vertex"}}
## Transform sliders' ranges (typed numbers go past them) and resets.
const CHANNEL_RANGE := {"position": [-10.0, 10.0, 0.01], "rotation_deg": [-180.0, 180.0, 1.0], "scale": [0.0, 4.0, 0.01]}
const CHANNEL_RESET := {"position": 0.0, "rotation_deg": 0.0, "scale": 1.0}
const CHANNEL_LABEL := {"position": "Position", "rotation_deg": "Rotation", "scale": "Scale"}
## Dragging a transform number: its change per pixel, and how far a press
## moves (px) before it's a drag rather than a click to type.
const DRAG_RATE := {"position": 0.01, "rotation_deg": 0.5, "scale": 0.005}
const DRAG_START := 4.0

## Headset layout: bigger text and targets.
var vr := false
## Scale typed into one axis scales all three by as much.
var uniform_scale := true

var edits: StudioConfigEdits
var tools: StudioEditTools

var _id := ""
var _rows: Array = []  # [{field, kind, controls, diamond, value, reset}]
var _t_rows: Array = []  # transform: [{channel, spins, sliders, diamond}]
var _fx_rows: Array = []  # effect list rows: [{list, index, fields, glyph, switch}]
var _open := {}  # section key -> bool
var _open_fx := {EditModel.EFFECTS: -1, EditModel.VERTEX_EFFECTS: -1}  # the unfolded effect of each list
var _open_channel := ""  # the transform row whose sliders are out
var _pending := {}  # field key -> {field, value, since, dragging}
var _t_pending := {}  # channel -> {value, since, dragging}
var _needs_build := true
var _menu := ""  # the inline choice list that's open ("add_effect" / "add_vertex" / "layer_shader" / "surface", or "field:<key>" for a choice or image field), "" none
var _since_refresh := 0.0
var _clock := 0.0
var _keep_scroll := -1
var _picker_open := ""  # field key whose colour wheel is open
var _reveal := ""  # field key (or "add_effect") to scroll into view after the next build
var _viewer_state: Label  # the viewer's panel: where it is and how fast it goes

var _title: Label
var _kind: Label
var _legend: Label
var _hint: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _fs := 15
var _label_w := 132
var _value_w := 58
var _diamond_w := 26
var _dot_w := 20


func _ready() -> void:
	vr = vr or get_viewport() != get_tree().root
	_fs = 28 if vr else 15
	_label_w = 190 if vr else 118
	_value_w = 104 if vr else 58
	_diamond_w = 48 if vr else 26
	_dot_w = 40 if vr else 20
	var th := Theme.new()
	th.default_font_size = _fs
	if vr:
		_scale_sliders(th, 2.0)
	theme = th
	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG
	bg.border_color = Color(ACCENT, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(12 if vr else 10)
	bg.set_content_margin_all(16 if vr else 10)
	add_theme_stylebox_override("panel", bg)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6 if vr else 3)
	add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	rows.add_child(top)
	_title = _label(top, int(_fs * 1.3), Color.WHITE)
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fold := _button("—", func(): minimize_requested.emit())
	fold.tooltip_text = "Fold to a tab (N brings it back)"
	var close := _button("✕", func(): close_requested.emit())
	close.tooltip_text = "Deselect"
	for b in [fold, close]:
		if vr:
			b.custom_minimum_size = Vector2(_target_h(), _target_h())
		top.add_child(b)
	# Its kind, its group and when it's there; the key legend at the right.
	var sub := HBoxContainer.new()
	rows.add_child(sub)
	_kind = _label(sub, int(_fs * 0.9), DIM)
	_kind.clip_text = true
	_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legend = _label(sub, int(_fs * 0.9), DIM)
	_legend.text = "◆ key here  ◇ animated"
	_hint = _label(rows, int(_fs * 0.9), DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(_scroll)
	# Room on the right for the scrollbar, which is drawn over the list.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16 if vr else 10)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6 if vr else 3)
	pad.add_child(_list)


## Show `id` ("" for nothing).
func show_object(id: String) -> void:
	if id == _id:
		return
	_commit_all()
	_id = id
	_menu = ""
	_picker_open = ""
	_open_channel = ""
	_open_fx = {EditModel.EFFECTS: -1, EditModel.VERTEX_EFFECTS: -1}
	_keep_scroll = 0
	_needs_build = true


## The piece changed (or the object's node did): rebuild on the next frame
## (never inside a control's own signal).
func request_rebuild() -> void:
	_needs_build = true


## Scroll a field's row (by field key, e.g. "effect1/tint") or the add
## effect menu ("add_effect") into view, once it's built.
func reveal(key: String) -> void:
	_reveal = key
	_needs_build = true


## Open or fold a section by its key: its title ("Display", "Modifiers",
## "Pixel effects"), or "effect<i>" / "vertex<i>" to unfold effect i of a
## list (folding the list's other one).
func set_section_open(title: String, open: bool) -> void:
	for list in LISTS:
		var prefix: String = LISTS[list].slot
		if title.begins_with(prefix) and title.substr(prefix.length()).is_valid_int():
			var i := int(title.substr(prefix.length()))
			if open:
				_open_fx[list] = i
				_open[LISTS[list].title] = true
			elif _open_fx[list] == i:
				_open_fx[list] = -1
			_needs_build = true
			return
	_open[title] = open
	_needs_build = true


## Unfold transform channel `channel`'s sliders ("" folds them).
func open_channel(channel: String) -> void:
	_open_channel = channel
	_needs_build = true


func _process(delta: float) -> void:
	_clock += delta
	if edits == null or tools == null:
		return
	for key in _pending.keys():
		var p: Dictionary = _pending[key]
		if not p.dragging and _clock - p.since >= SETTLE and key != _picker_open:
			_commit(key)
	for ch in _t_pending.keys():
		if not _t_pending[ch].dragging and _clock - _t_pending[ch].since >= SETTLE:
			_commit_transform(ch)
	if _needs_build and _pending.is_empty() and _t_pending.is_empty():
		_needs_build = false
		_build()
	_since_refresh += delta
	if _since_refresh >= REFRESH:
		_since_refresh = 0.0
		_refresh_values()


# ---------- building ----------

func _build() -> void:
	var scroll := _keep_scroll if _keep_scroll >= 0 else _scroll.scroll_vertical
	_keep_scroll = -1
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	_t_rows.clear()
	_fx_rows.clear()
	var node := _node()
	_legend.visible = _id != "" and _id != ScriptFormat.VIEWER
	if _id == "" or edits.model == null:
		_title.text = "Inspector"
		_kind.text = ""
		_hint.text = "Select something to see its settings: point and pull the trigger, or click it."
		_hint.visible = true
		if edits.model != null:
			# The piece's own settings that aren't an object's.
			var cam := _button("✦ Camera effects: over everything the viewer sees", func(): tools.select(EditModel.CAMERA))
			cam.alignment = HORIZONTAL_ALIGNMENT_LEFT
			cam.custom_minimum_size.y = _target_h()
			_list.add_child(cam)
		return
	if _id == ScriptFormat.VIEWER:
		_build_viewer()
		return
	var kind := edits.kind_for(_id, node)
	var sections := edits.sections(_id, node, kind)
	if kind == "camera":
		_build_camera(sections)
		return
	_title.text = _id
	_kind.text = edits.describe(_id, _playhead(), _duration(), node)
	var lists_done := kind == "object"
	for s in sections:
		if s.kind == "effect":
			continue  # in their lists
		if s.title == "Modifiers" and not lists_done:
			_add_effect_lists(sections)
			lists_done = true
		match s.kind:
			"transform": _add_transform()
			"surface": _add_surface(s)
			"layer_shader": _add_layer_shader(s)
			_: _add_section(s.title, s.title, s.fields)
	if not lists_done:
		_add_effect_lists(sections)
	var save_look := _button("★ Save look (Ctrl+L): to the shelf, to put on others", func(): action.emit(&"studio_save_look"))
	save_look.alignment = HORIZONTAL_ALIGNMENT_LEFT
	save_look.custom_minimum_size.y = _target_h()
	_list.add_child(save_look)
	_refresh_values()
	_scroll.set_deferred("scroll_vertical", scroll)
	if _reveal != "":
		var target: Control = null
		for r in _rows:
			if r.field.key == _reveal:
				target = r.controls.back() if not r.controls.is_empty() else r.diamond
		if _reveal in ["add_effect", "add_vertex"]:
			target = _list.find_child("AddEffectChoices" if _reveal == "add_effect" else "AddVertexChoices", true, false)
		_reveal = ""
		if target != null:
			_scroll_to.call_deferred(target)


## After the layout settles (and the kept scroll position is back).
func _scroll_to(target: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(target):
		_scroll.ensure_control_visible(target)


## What a folded section holds, for its header: its first few fields
## ("tint · flash · speed …").
static func section_summary(fields: Array, most: int = 3) -> String:
	var names: Array = fields.slice(0, most).map(func(f): return String(f.label).to_lower())
	return " · ".join(names) + (" …" if fields.size() > most else "")


## A foldable section: its header and a body with a row per field.
## `summary` replaces the folded header's list of fields.
func _add_section(key: String, title: String, fields: Array, header_extra: Callable = Callable(), note_empty := true,
		summary := "") -> VBoxContainer:
	var open: bool = _open.get(key, key in OPEN_BY_DEFAULT)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_list.add_child(head)
	var fold := _button(("▾ " if open else "▸ ") + title, func():
		_open[key] = not open
		_needs_build = true)
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fold.add_theme_color_override("font_color", ACCENT)
	fold.add_theme_font_size_override("font_size", int(_fs * 1.1))
	fold.custom_minimum_size.y = _target_h()
	head.add_child(fold)
	if not open and (summary != "" or not fields.is_empty()):
		# Folded: what's inside, at the right of the header.
		var inside := _label(head, int(_fs * 0.85), DIM)
		inside.text = summary if summary != "" else section_summary(fields)
		inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if header_extra.is_valid():
		header_extra.call(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4 if vr else 2)
	body.visible = open
	_list.add_child(body)
	_add_fields(body, fields)
	if fields.is_empty() and open and note_empty:
		var none := _label(body, int(_fs * 0.9), DIM)
		none.text = "No settings."
	return body


## A row per field, with a group's name above its first.
func _add_fields(body: Control, fields: Array) -> void:
	var group := ""
	for f in fields:
		var g := String(f.get("group", ""))
		if g != group and g != "":
			var gl := _label(body, int(_fs * 0.9), DIM)
			gl.text = g.capitalize()
		group = g
		_add_field(body, f)


## One field: [record dot] name, its control, its value, ↺, its diamond.
func _add_field(parent: Control, field: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if vr:
		row.custom_minimum_size.y = _target_h()  # the diamond and dot are whole targets
	parent.add_child(row)
	var dot := _arm_dot(field)
	row.add_child(dot)
	var name := _label(row, _fs, Color.WHITE)
	name.text = field.label
	name.custom_minimum_size.x = _label_w - _dot_w
	name.clip_text = true
	if field.has("tip"):
		name.tooltip_text = field.tip
		name.mouse_filter = Control.MOUSE_FILTER_PASS
	var r := {"field": field, "kind": field.type, "controls": [], "diamond": null, "value": null, "reset": null,
			"dot": dot if dot is Button else null}
	match field.type:
		"choice", "texture":
			# The current one ("Add (light)  ▾"); a press lists them under the row.
			var menu := "field:" + String(field.key)
			var pick := _button("", func():
				_menu = "" if _menu == menu else menu
				_needs_build = true)
			pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
			pick.clip_text = true
			pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pick.custom_minimum_size.y = _target_h()
			if field.has("tip"):
				pick.tooltip_text = field.tip
			row.add_child(pick)
			r.controls = [pick]
			if _menu == menu:
				var now = edits.value_of(_id, field, _playhead())
				var options: Array = edits.image_options(String(now)) if field.type == "texture" \
						else range(field.options.size()).map(func(i): return {"key": field.values[i], "label": field.options[i]})
				var grid := _add_choices(options, func(v): _set_now(field, v), parent)
				for i in options.size():
					if str(options[i].key) == str(now):  # the one it is: lit, like a placement
						(grid.get_child(i) as Button).add_theme_color_override("font_color", ACCENT)
		"bool":
			var sw := _pill(false, func(on: bool): _set_now(field, on))
			var holder := HBoxContainer.new()
			holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			holder.add_child(sw)
			row.add_child(holder)
			r.controls = [sw]
		"color":
			var swatch := _button("", func():
				if _picker_open == field.key:
					_picker_open = ""
					_commit(field.key)
				else:
					_picker_open = field.key
					_reveal = field.key
				_needs_build = true)
			swatch.custom_minimum_size = Vector2(_label_w * 0.8, _fs * 1.6)
			swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(swatch)
			r.controls = [swatch]
			if _picker_open == field.key:
				var picker := ColorPicker.new()
				picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
				picker.edit_alpha = field.get("alpha", false)
				picker.sampler_visible = false
				picker.color_modes_visible = false
				picker.presets_visible = false
				picker.hex_visible = false
				picker.sliders_visible = false
				picker.can_add_swatches = false
				picker.focus_mode = Control.FOCUS_NONE
				var c = edits.value_of(_id, field, _playhead())
				picker.color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
				picker.color_changed.connect(func(col: Color): _changed(field, col, false))
				if vr:
					picker.scale = Vector2(1.6, 1.6)
					var holder := Control.new()
					holder.custom_minimum_size = picker.get_combined_minimum_size() * 1.6
					holder.add_child(picker)
					parent.add_child(holder)
				else:
					parent.add_child(picker)
				r.controls.append(picker)
		"vec3":
			var box := VBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(box)
			for c in 3:
				var slider := _slider(field.min, field.max, field.step)
				slider.value_changed.connect(func(_v): _changed(field, _vec_of(r), true))
				slider.drag_started.connect(func(): _drag(field, true))
				slider.drag_ended.connect(func(_c): _drag(field, false))
				box.add_child(slider)
				r.controls.append(slider)
		_:
			var slider := _slider(field.min, field.max, field.step)
			slider.value_changed.connect(func(v: float): _changed(field, int(v) if field.type == "int" else v, true))
			slider.drag_started.connect(func(): _drag(field, true))
			slider.drag_ended.connect(func(_c): _drag(field, false))
			row.add_child(slider)
			r.controls = [slider]
	var value := _label(row, int(_fs * 0.9), DIM)
	value.custom_minimum_size.x = _value_w
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.value = value
	var reset := _small_button("↺", func(): _set_now(field, field.default))
	reset.flat = true
	reset.tooltip_text = "Back to its default"
	row.add_child(reset)
	r.reset = reset
	var diamond := _button("", func(): _toggle_key(field))
	diamond.flat = true
	diamond.custom_minimum_size.x = _diamond_w
	row.add_child(diamond)
	r.diamond = diamond
	_rows.append(r)


func _slider(lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size.y = _fs * 1.4
	s.scrollable = false
	s.focus_mode = Control.FOCUS_NONE
	s.min_value = lo
	s.max_value = hi
	s.step = step
	return s


static func _vec_of(r: Dictionary) -> Array:
	return r.controls.map(func(s: HSlider): return s.value)


# ---------- the transform ----------

## A row per channel: its name (click it for a slider per axis), x / y / z
## numbers to type in (or drag), its diamond; Uniform under scale.
func _add_transform() -> void:
	var body := _add_section("Transform", "Transform", [], _add_lock, false, "position · rotation · scale")
	if not body.visible:
		return
	for ch in StudioConfigEdits.CHANNELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.custom_minimum_size.y = _target_h()
		body.add_child(row)
		var open: bool = _open_channel == ch
		var name := _button(CHANNEL_LABEL[ch], func():
			_open_channel = "" if _open_channel == ch else ch
			_needs_build = true)
		name.flat = true
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.custom_minimum_size.x = _label_w
		name.add_theme_color_override("font_color", ACCENT if open else Color.WHITE)
		name.tooltip_text = "Sliders for each axis"
		row.add_child(name)
		var t := {"channel": ch, "spins": [], "sliders": [], "diamond": null}
		for c in 3:
			var spin := _number(ch)
			spin.prefix = "xyz"[c]
			spin.value_changed.connect(func(v: float): _typed_axis(ch, c, v))
			_draggable(spin, ch, c)
			row.add_child(spin)
			t.spins.append(spin)
		var diamond := _button("", func(): _toggle_transform_key(ch))
		diamond.flat = true
		diamond.custom_minimum_size.x = _diamond_w
		row.add_child(diamond)
		t.diamond = diamond
		if open:
			var box := VBoxContainer.new()
			var frame := _framed(box)
			body.add_child(frame)
			var range_: Array = CHANNEL_RANGE[ch]
			for c in 3:
				var srow := HBoxContainer.new()
				srow.add_theme_constant_override("separation", 8)
				box.add_child(srow)
				var axis := _label(srow, _fs, DIM)
				axis.text = "xyz"[c]
				axis.custom_minimum_size.x = _dot_w
				var slider := _slider(range_[0], range_[1], range_[2])
				slider.allow_greater = true
				slider.allow_lesser = ch != "scale"
				slider.value_changed.connect(func(v: float): _slid_axis(ch, c, v))
				slider.drag_started.connect(func(): _t_drag(ch, true))
				slider.drag_ended.connect(func(_x): _t_drag(ch, false))
				srow.add_child(slider)
				var shown := _label(srow, int(_fs * 0.9), DIM)
				shown.custom_minimum_size.x = _value_w
				shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				slider.set_meta("shown", shown)
				var reset := _small_button("↺", func(): _typed_axis(ch, c, CHANNEL_RESET[ch]))

				reset.flat = true
				reset.tooltip_text = "Back to %s" % str(CHANNEL_RESET[ch])
				srow.add_child(reset)
				slider.set_meta("reset", reset)
				t.sliders.append(slider)
		_t_rows.append(t)
		if ch == "scale":
			var uni := CheckBox.new()
			uni.text = "Uniform (one value for x, y and z)"
			uni.focus_mode = Control.FOCUS_NONE
			uni.button_pressed = uniform_scale
			uni.toggled.connect(func(on: bool): uniform_scale = on)
			var urow := HBoxContainer.new()
			var gap := Control.new()
			gap.custom_minimum_size.x = _label_w
			urow.add_child(gap)
			urow.add_child(uni)
			body.add_child(urow)
	var tip := _label(body, int(_fs * 0.85), DIM)
	tip.text = "Click a row for its sliders · drag a number sideways, or click to type · grab to move"


## A number field for a transform axis (type, drag it sideways, or its arrows).
## The Transform header's lock: "Locked" and a switch. Locked, hands and
## the move gizmo leave the object where it is; the numbers here still move it.
func _add_lock(head: HBoxContainer) -> void:
	var locked := tools.is_locked(_id)
	var name := _label(head, int(_fs * 0.9), ACCENT if locked else DIM)
	name.text = "Locked" if locked else "Lock"
	var sw := _pill(locked, func(on: bool): tools.set_locked(_id, on))
	sw.tooltip_text = "Lock its place: hands and the move gizmo can't move it (the numbers below still can)"
	sw.name = "LockSwitch"
	head.add_child(sw)


func _number(ch: String) -> SpinBox:
	var s := SpinBox.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.x = _value_w
	s.min_value = -100000.0
	s.max_value = 100000.0
	s.step = 1.0 if ch == "rotation_deg" else 0.01
	s.custom_arrow_step = 5.0 if ch == "rotation_deg" else 0.05 if ch == "position" else 0.01
	s.select_all_on_focus = true
	s.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.get_line_edit().add_theme_font_size_override("font_size", int(_fs * 0.95))
	if vr:
		s.custom_minimum_size.y = _target_h()
	return s


## Press on a number and drag sideways to change it, as in Godot's and
## Blender's spin boxes (Shift: finer); it previews like a slider and is
## written on release, lit while it's dragged. A click without a drag types
## a value. Once it's being typed in, clicks are the line edit's own (caret,
## selection). It takes no focus until then: a press would focus it before
## its input is seen.
func _draggable(spin: SpinBox, ch: String, c: int) -> void:
	var edit := spin.get_line_edit()
	edit.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	edit.focus_mode = Control.FOCUS_NONE
	edit.focus_exited.connect(func(): edit.focus_mode = Control.FOCUS_NONE)
	var d := {"down": false, "dragging": false, "from": 0.0, "moved": 0.0, "travel": 0.0}
	edit.gui_input.connect(func(e: InputEvent):
		if edit.has_focus():
			return
		var mb := e as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			edit.accept_event()
			if mb.pressed:
				d.merge({"down": true, "dragging": false, "from": spin.value, "moved": 0.0, "travel": 0.0}, true)
			elif d.down:
				d.down = false
				if d.dragging:
					d.dragging = false
					edit.remove_theme_color_override("font_color")
					_t_drag(ch, false)
				else:
					edit.focus_mode = Control.FOCUS_ALL
					edit.grab_focus()
					edit.select_all()
			return
		var mm := e as InputEventMouseMotion
		if mm == null or not d.down:
			return
		edit.accept_event()
		d.travel += absf(mm.relative.x)
		d.moved += mm.relative.x * (0.1 if mm.shift_pressed else 1.0)
		if not d.dragging:
			if d.travel < DRAG_START:
				return
			d.dragging = true
			edit.add_theme_color_override("font_color", ACCENT)  # the one that's live
			_t_drag(ch, true)
		var v: float = snappedf(d.from + d.moved * DRAG_RATE[ch], spin.step)
		if ch == "scale":
			v = maxf(v, spin.step)
		_slid_axis(ch, c, v))


## The channel as it is now: pending, else the node's ([x, y, z]).
func _channel_now(ch: String) -> Array:
	if _t_pending.has(ch):
		return (_t_pending[ch].value as Array).duplicate()
	var node := _node()
	return GrabMath.to_dict(node.transform)[ch] if node != null else [0.0, 0.0, 0.0]


## Axis `c` of `ch` set to `v` (Uniform scale takes the others along).
func _with_axis(ch: String, c: int, v: float) -> Array:
	var now := _channel_now(ch)
	if ch == "scale" and uniform_scale:
		var was := float(now[c])
		if absf(was) < 1e-6:
			return [v, v, v]
		return now.map(func(x): return float(x) * v / was)
	now[c] = v
	return now


## A typed number (or a ↺): written straight away.
func _typed_axis(ch: String, c: int, v: float) -> void:
	if _id == "":
		return
	var value := _with_axis(ch, c, v)
	tools.preview_channel(_id, ch, value)
	_t_pending[ch] = {"value": value, "since": _clock, "dragging": false}
	_commit_transform(ch)


func _slid_axis(ch: String, c: int, v: float) -> void:
	if _id == "":
		return
	var value := _with_axis(ch, c, v)
	tools.preview_channel(_id, ch, value)
	var p: Dictionary = _t_pending.get(ch, {"dragging": false})
	p.value = value
	p.since = _clock
	_t_pending[ch] = p
	_show_transform(value, ch)


func _t_drag(ch: String, on: bool) -> void:
	if on:
		var p: Dictionary = _t_pending.get(ch, {"value": _channel_now(ch), "since": _clock})
		p.dragging = true
		_t_pending[ch] = p
	elif _t_pending.has(ch):
		_commit_transform(ch)


func _commit_transform(ch: String) -> void:
	if not _t_pending.has(ch):
		return
	var value: Array = _t_pending[ch].value
	_t_pending.erase(ch)
	tools.set_channel(_id, ch, value)  # it says what it did


# ---------- the surface, the layer's shader ----------

## The surface's picker ("Pillow ▾"), its placements as buttons, its hint,
## then its params.
func _add_surface(s: Dictionary) -> void:
	var body := _add_section("Surface", "Surface · %s" % s.label, s.fields)
	if not body.visible:
		return
	var at := 0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	body.move_child(row, at)
	at += 1
	var name := _label(row, _fs, Color.WHITE)
	name.text = "Shape"
	name.custom_minimum_size.x = _label_w
	var pick := _button(String(s.label) + "  ▾", func():
		_menu = "" if _menu == "surface" else "surface"
		_needs_build = true)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size.y = _target_h()
	row.add_child(pick)
	if _menu == "surface":
		var grid := _add_choices(s.options, func(key: String):
			_label_op(func(): return edits.set_surface_shader(_id, key)))
		_list.remove_child(grid)
		body.add_child(grid)
		body.move_child(grid, at)
		at += 1
	if s.placements.size() > 1:
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 6)
		body.add_child(prow)
		body.move_child(prow, at)
		at += 1
		var pname := _label(prow, _fs, Color.WHITE)
		pname.text = "Placement"
		pname.custom_minimum_size.x = _label_w
		for p in s.placements:
			var b := _button(String(ScreenGeometry.PLACEMENT_LABELS.get(p, p)), func():
				_label_op(func(): return edits.set_surface_placement(_id, p)))
			b.toggle_mode = true
			b.set_pressed_no_signal(p == s.placement)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.y = _target_h()
			if p == s.placement:
				b.add_theme_color_override("font_color", ACCENT)
				b.add_theme_color_override("font_pressed_color", ACCENT)
			prow.add_child(b)
	if String(s.hint) != "":
		var hint := _label(body, int(_fs * 0.85), DIM)
		hint.text = s.hint
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.move_child(hint, at)


func _add_layer_shader(s: Dictionary) -> void:
	var current := String(s.get("shader", ""))
	var label := "none"
	for o in edits.layer_shader_options():
		if current != "" and (o.key == current or edits.model.shader_key_of(o.key) == current):
			label = o.label
	if label == "none" and current != "":
		label = current.capitalize()
	var body := _add_section("Layer shader", "Shader · %s" % label, s.fields)
	if not body.visible:
		return
	var pick := _button("Change shader ▾", func():
		_menu = "" if _menu == "layer_shader" else "layer_shader"
		_needs_build = true)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.add_child(pick)
	body.move_child(pick, 0)
	if _menu == "layer_shader":
		var at := pick.get_index() + 1
		var grid := _add_choices(edits.layer_shader_options(), func(key: String):
			_effect_op(func(): return edits.set_layer_shader(_id, key)))
		_list.remove_child(grid)
		body.add_child(grid)
		body.move_child(grid, at)


# ---------- the effect lists ----------

func _add_effect_lists(sections: Array) -> void:
	for list in LISTS:
		_add_effect_list(list, sections.filter(func(s): return s.kind == "effect" and s.get("list", EditModel.EFFECTS) == list))


## A list's section: its master switch on the header, a row per effect (the
## chosen one unfolded), then "+ Add".
func _add_effect_list(list: String, effects: Array) -> void:
	var info: Dictionary = LISTS[list]
	if _id == EditModel.CAMERA:
		info = {"title": "Camera effects", "add": "+ Add camera effect", "menu": info.menu, "slot": info.slot}
	var summary := " · ".join(effects.map(func(s): return String(s.title).to_lower())) if not effects.is_empty() else "none"
	var master := func(head: HBoxContainer):
		if effects.is_empty():
			return
		var all := _label(head, int(_fs * 0.85), DIM)
		all.text = "all"
		var on := effects.any(func(s): return s.enabled)
		var sw := _pill(on, func(v: bool): _effect_op(func(): return edits.model.set_all_effects_enabled(_id, v, list)))
		sw.tooltip_text = "Every %s on / off" % info.title.to_lower().trim_suffix("s")
		head.add_child(sw)
	var body := _add_section(info.title, info.title, [], master, false, summary)
	if not body.visible:
		return
	var open: int = _open_fx[list]
	for s in effects:
		_add_effect_row(body, list, s, s.index == open, effects.size())
	var add := _button(info.add, func():
		_menu = "" if _menu == info.menu else info.menu
		if _menu != "":
			_reveal = info.menu
		_needs_build = true)
	add.name = "AddEffect" if list == EditModel.EFFECTS else "AddVertex"
	add.custom_minimum_size.y = _target_h()
	add.add_theme_color_override("font_color", ACCENT)
	var dashed := StyleBoxFlat.new()
	dashed.bg_color = Color(0, 0, 0, 0)
	dashed.border_color = Color(ACCENT, 0.7)
	dashed.set_border_width_all(2)
	dashed.set_corner_radius_all(6)
	dashed.set_content_margin_all(4)
	add.add_theme_stylebox_override("normal", dashed)
	var hover := dashed.duplicate()
	hover.bg_color = Color(ACCENT, 0.12)
	add.add_theme_stylebox_override("hover", hover)
	add.add_theme_stylebox_override("pressed", hover)
	var add_row := HBoxContainer.new()
	add_row.add_child(add)
	body.add_child(add_row)
	if _menu == info.menu:
		var grid := _add_choices(edits.effect_options(list, _id), func(key: String):
			var n := edits.model.effects_of(_id, list).size()
			if _effect_op(func(): return edits.add_effect(_id, key, list)):
				_open_fx[list] = n)
		grid.name = "AddEffectChoices" if list == EditModel.EFFECTS else "AddVertexChoices"
		_list.remove_child(grid)
		body.add_child(grid)


## One effect's row: ≡ (drag it onto another row to move it there), its
## name (unfolds it), on / off, its key state, ✕; unfolded, its settings.
func _add_effect_row(body: VBoxContainer, list: String, s: Dictionary, open: bool, count: int) -> void:
	var i: int = s.index
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4 if vr else 2)
	var frame := _framed(box, open)
	body.add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = _target_h()
	box.add_child(row)
	var handle := _label(row, _fs, DIM)
	handle.text = "≡"
	handle.custom_minimum_size.x = _dot_w
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	handle.tooltip_text = "Drag onto another effect to move it there"
	var drag := func(_at: Vector2):
		if count < 2:
			return null
		var preview := Label.new()
		preview.text = "≡ " + String(s.title)
		preview.add_theme_font_size_override("font_size", _fs)
		handle.set_drag_preview(preview)
		return {"fx_list": list, "from": i}
	handle.set_drag_forwarding(drag, Callable(), Callable())
	# The whole frame takes a drop.
	var can_drop := func(_at: Vector2, data) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.get("fx_list") == list and data.get("from") != i
	var drop := func(_at: Vector2, data) -> void:
		drop_effect(list, int(data.from), i)
	frame.set_drag_forwarding(Callable(), can_drop, drop)
	var name := _button(String(s.title), func():
		_open_fx[list] = -1 if _open_fx[list] == i else i
		_needs_build = true)
	name.flat = true
	name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_color_override("font_color", Color.WHITE if s.enabled else DIM)
	row.add_child(name)
	var on := _pill(edits.switch_on(_id, i, _playhead(), list), func(v: bool):
		_label_op(func(): return edits.set_switch(_id, i, v, _playhead(), tools.auto_key, list)))
	on.tooltip_text = "On / off (off keeps its place and settings). With auto-key, or once it has on / off keys, it keys at the playhead"
	row.add_child(on)
	var glyph := _label(row, _fs, DIM)
	glyph.custom_minimum_size.x = _diamond_w
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var remove := _small_button("✕", func(): _effect_op(func(): return edits.model.remove_effect(_id, i, list)))
	remove.flat = true
	remove.tooltip_text = "Remove"
	row.add_child(remove)
	_fx_rows.append({"list": list, "index": i, "fields": s.fields, "glyph": glyph, "switch": on})
	if open:
		if s.fields.is_empty():
			var none := _label(box, int(_fs * 0.9), DIM)
			none.text = "No settings."
		_add_fields(box, s.fields)
		if not s.enabled:
			box.modulate = Color(1, 1, 1, 0.55)


## Move effect `from` of `list` to where effect `to` is (a drop on its row).
func drop_effect(list: String, from: int, to: int) -> bool:
	var moved := _effect_op(func(): return edits.model.move_effect(_id, from, to, list))
	# The unfolded one stays unfolded, wherever the move put it.
	var open: int = _open_fx[list]
	if moved and open >= 0:
		if open == from:
			_open_fx[list] = to
		elif from < open and open <= to:
			_open_fx[list] = open - 1
		elif to <= open and open < from:
			_open_fx[list] = open + 1
	return moved


## `inner` in a rounded box; `lit`: the accent border of the chosen one.
func _framed(inner: Control, lit := false) -> PanelContainer:
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_BG if lit else Color(ROW_BG, 0.6)
	sb.border_color = ACCENT if lit else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2 if lit else 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8 if vr else 4)
	frame.add_theme_stylebox_override("panel", sb)
	frame.add_child(inner)
	return frame


## A grid of buttons, one per option ({key, label}); picking one closes it.
## It goes at the end of `parent` (the list if null).
func _add_choices(options: Array, on_pick: Callable, parent: Control = null) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for o in options:
		var b := _button(o.label, func():
			_menu = ""
			_needs_build = true
			on_pick.call(o.key))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = _target_h()
		b.clip_text = true
		grid.add_child(b)
	(parent if parent != null else _list).add_child(grid)
	return grid


# ---------- changing ----------

func _node() -> Node3D:
	if _id == "" or tools == null or tools.runner == null:
		return null
	var n := tools.runner.registry().get_node_by_id(_id)
	return n if n != null and is_instance_valid(n) else null


func _playhead() -> float:
	return tools.runner.playhead if tools != null and tools.runner != null else 0.0


## The piece's length as far as the runner knows (for the header's span).
func _duration() -> float:
	if tools == null or tools.runner == null:
		return 1.0
	return maxf(tools.runner.effective_duration(), _playhead())


## A control moved: show it live; it's written when the drag ends (or, with
## no drag, once it settles).
func _changed(field: Dictionary, value, _from_slider: bool) -> void:
	if _id == "":
		return
	edits.preview(_id, field, value)
	var p: Dictionary = _pending.get(field.key, {"field": field, "dragging": false})
	p.value = value
	p.since = _clock
	_pending[field.key] = p
	for r in _rows:
		if r.field.key == field.key:
			_show_value(r, value)


func _drag(field: Dictionary, on: bool) -> void:
	if on:
		var p: Dictionary = _pending.get(field.key, {"field": field, "since": _clock})
		p.dragging = true
		if not p.has("value"):
			p.value = edits.value_of(_id, field, _playhead())
		_pending[field.key] = p
	elif _pending.has(field.key):
		_commit(field.key)


## A switch (or ↺): written straight away.
func _set_now(field: Dictionary, value) -> void:
	_pending[field.key] = {"field": field, "value": value, "since": _clock, "dragging": false}
	_commit(field.key)
	if field.type in ["choice", "texture"]:
		_needs_build = true  # the menu closed; the row shows the new one


func _commit(key: String) -> void:
	if not _pending.has(key):
		return
	var p: Dictionary = _pending[key]
	_pending.erase(key)
	var label := edits.commit(_id, p.field, p.value, _playhead(), tools.auto_key, tools.key_animated)
	edits.end_preview(_id, p.field, label == "")
	if label != "":
		said.emit(label + ".")


## The camera effects ("$camera", the script's camera block): its list,
## like a screen's pixel effects, each with its strength.
func _build_camera(sections: Array) -> void:
	_title.text = "Camera effects"
	_kind.text = "over everything the viewer sees"
	_hint.text = "Only the first one that's on runs (the player's limit), and only as strong as the viewer's Config allows. Its sliders key on the Camera fx lane."
	_hint.visible = true
	_hint.remove_theme_color_override("font_color")
	_add_effect_list(EditModel.EFFECTS, sections)
	_refresh_values()


## The viewer ("$viewer"): no settings, but what it does here, and buttons
## to key it, cut, and arm recording a ride.
func _build_viewer() -> void:
	_title.text = "Viewer"
	_kind.text = "the audience's eye"
	_hint.text = "Where the audience is taken. Its keys are on the timeline's Viewer lane: retime them, pick how they move on (Step before a key makes it a cut)."
	_hint.visible = true
	_hint.remove_theme_color_override("font_color")
	_viewer_state = _label(_list, _fs, Color.WHITE)
	_viewer_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for b in [[&"studio_key_viewer", "◆ Key viewer here (V): glide here"], [&"studio_cut_here", "✂ Cut here (Shift+V): jump here"]]:
		var button := _button(b[1], func(): action.emit(b[0]))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = _target_h()
		_list.add_child(button)
	var rec := edits.recorder
	if rec != null:
		var arm := _button("", func():
			action.emit(&"studio_arm_ride")
			_needs_build = true)
		arm.toggle_mode = true
		arm.set_pressed_no_signal(rec.arm_viewer)
		arm.text = "● Ride armed: record, and fly the path" if rec.arm_viewer else "● Arm the ride (record where you fly)"
		arm.add_theme_color_override("font_color", RECORD if rec.arm_viewer else DIM)
		arm.alignment = HORIZONTAL_ALIGNMENT_LEFT
		arm.custom_minimum_size.y = _target_h()
		_list.add_child(arm)
	_refresh_viewer(_playhead())


func _refresh_viewer(t: float) -> void:
	if _viewer_state == null or not is_instance_valid(_viewer_state):
		return
	var vt := ViewerTrack.new()
	vt.build(edits.model.tracks())
	var pose := vt.pose_at(t)
	if pose.is_empty():
		_viewer_state.text = "At %s: at home (the seat), until %s." % [StudioStatus.timecode(t),
				StudioStatus.timecode(vt.start_time()) if not vt.is_empty() else "the script moves them"]
		return
	var m := vt.motion_at(t)
	var p: Vector3 = pose.position
	var fast: bool = m.speed > StudioTimeline.COMFORT_SPEED or m.turn > StudioTimeline.COMFORT_TURN
	_viewer_state.text = "At %s: (%.2f, %.2f, %.2f), facing %.0f°\nMoving %.1f m/s, turning %.0f°/s%s" % [StudioStatus.timecode(t), p.x, p.y, p.z,
			pose.rotation_deg.y, m.speed, m.turn, "  — too fast for comfort (%.0f m/s, %.0f°/s)" % [StudioTimeline.COMFORT_SPEED, StudioTimeline.COMFORT_TURN] if fast else ""]
	_viewer_state.add_theme_color_override("font_color", RECORD if fast else Color.WHITE)


## Forget changes in progress without writing them (a take that ended
## wrote them already).
func drop_pending() -> void:
	_pending.clear()
	_t_pending.clear()


func _commit_all() -> void:
	for key in _pending.keys():
		_commit(key)
	for ch in _t_pending.keys():
		_commit_transform(ch)


func _toggle_key(field: Dictionary) -> void:
	_commit_all()
	var label := edits.toggle_key(_id, field, _playhead())
	if label != "":
		said.emit(label + ".")
	elif String(field.slot) == "":
		said.emit("%s can't be animated%s." % [field.label, " while the effect is off" if String(field.key).begins_with("effect") or String(field.key).begins_with("vertex") else ""])


## The record dot before a field's name: red while it's armed (a take
## records it when you move it). Fields that can't be recorded get a gap.
func _arm_dot(field: Dictionary) -> Control:
	var rec: StudioRecorder = edits.recorder
	if rec == null or not StudioRecorder.can_arm(field):
		var gap := Control.new()
		gap.custom_minimum_size.x = _dot_w
		return gap
	var dot := _button("●", func(): pass)
	dot.flat = true
	dot.custom_minimum_size.x = _dot_w
	dot.add_theme_font_size_override("font_size", int(_fs * 0.9))
	dot.tooltip_text = "Arm for recording"
	var paint := func():
		var on := rec.is_armed(_id, field)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			dot.add_theme_color_override(state, RECORD if on else Color(1, 1, 1, 0.22))
	paint.call()
	dot.pressed.connect(func():
		var on := not rec.is_armed(_id, field)
		rec.set_armed(_id, field, on)
		paint.call()
		said.emit("%s %s %s." % [_id, String(field.label).to_lower(), "armed: a take records it when you move it" if on else "not armed"]))
	return dot


func _toggle_transform_key(channel: String) -> void:
	var node := _node()
	if node == null:
		return
	_commit_all()
	var label: String
	if tools.is_unkeyed(_id, channel):
		label = "Key %s %s at %s" % [_id, channel, StudioStatus.timecode(_playhead())]
		if not edits.model.batch(label, func(): tools.key_unkeyed(_id, channel)):
			label = ""
	else:
		label = edits.toggle_transform_key(_id, channel, _playhead(), GrabMath.to_dict(node.transform))
	if label != "":
		said.emit(label + ".")


func _effect_op(op: Callable) -> bool:
	_commit_all()
	var done: bool = op.call()
	if done:
		said.emit(edits.model.undo_label() + ".")
	return done


## An op that returns its undo label ("" if nothing changed).
func _label_op(op: Callable) -> void:
	_commit_all()
	var label: String = op.call()
	if label != "":
		said.emit(label + ".")


# ---------- showing values ----------

func _refresh_values() -> void:
	if _id == "" or edits == null:
		return
	var t := _playhead()
	if _id == ScriptFormat.VIEWER:
		_refresh_viewer(t)
		return
	_hint.visible = tools.auto_key or tools.key_animated
	if tools.auto_key:
		_hint.text = "● Auto-key: changes key at %s." % StudioStatus.timecode(t)
		_hint.add_theme_color_override("font_color", RECORD)
	elif tools.key_animated:
		_hint.text = "Keys on change: animated settings key at %s; still ones are set." % StudioStatus.timecode(t)
		_hint.add_theme_color_override("font_color", DIM)
	# While something here is changed but not keyed, the legend says what
	# the orange diamond is.
	var unkeyed: bool = tools.unkeyed.has(_id) or edits.unkeyed.values().any(func(u): return u.id == _id)
	_legend.text = "◆ not keyed yet" if unkeyed else "◆ key here  ◇ animated"
	_legend.add_theme_color_override("font_color", UNKEYED if unkeyed else DIM)
	var node := _node()
	for tr in _t_rows:
		var ch: String = tr.channel
		_show_diamond(tr.diamond, "unkeyed" if tools.is_unkeyed(_id, ch) else edits.transform_state(_id, ch, t))
		if node != null and not _t_pending.has(ch):
			_show_transform(GrabMath.to_dict(node.transform)[ch], ch)
	for r in _rows:
		_show_diamond(r.diamond, edits.key_state(_id, r.field, t))
		if _pending.has(r.field.key):
			continue
		var value = edits.value_of(_id, r.field, t)
		match r.kind:
			"bool":
				_show_pill(r.controls[0], bool(value))
			"float", "int":
				(r.controls[0] as HSlider).set_value_no_signal(float(value))
			"vec3":
				for c in 3:
					(r.controls[c] as HSlider).set_value_no_signal(float(value[c]))
			"color":
				if r.controls.size() > 1 and _picker_open != r.field.key:
					(r.controls[1] as ColorPicker).color = _color(value)
			"choice", "texture":
				_show_choice(r, value)
		_show_value(r, value)
	for fx in _fx_rows:
		var state := _effects_state(fx.fields, t)
		var switch := edits.switch_state(_id, fx.index, t, fx.list)
		if switch == "key" or (switch == "animated" and state != "key"):
			state = switch
		fx.glyph.text = {"key": "◆", "animated": "◇", "static": "•"}.get(state, "")
		fx.glyph.add_theme_color_override("font_color", DIM if fx.glyph.text == "•" else RECORD)
		_show_pill(fx.switch, edits.switch_on(_id, fx.index, t, fx.list))


## An effect's key state from its fields': a key at `t` on any, else
## animated if any is, else still ("none" when it can't be keyed).
func _effects_state(fields: Array, t: float) -> String:
	var out := "none"
	for f in fields:
		var s := edits.key_state(_id, f, t)
		if s == "key":
			return "key"
		if s == "animated" or (s == "static" and out == "none"):
			out = s
	return out


## A transform channel's numbers (and sliders, if they're out).
func _show_transform(v: Array, ch: String) -> void:
	for tr in _t_rows:
		if tr.channel != ch:
			continue
		for c in 3:
			var x := float(v[c])
			if absf(x) < (0.5 if ch == "rotation_deg" else 0.005):
				x = 0.0
			var spin: SpinBox = tr.spins[c]
			if not spin.get_line_edit().has_focus():
				spin.set_value_no_signal(x)
			if c < tr.sliders.size():
				var slider: HSlider = tr.sliders[c]
				slider.set_value_no_signal(x)
				(slider.get_meta("shown") as Label).text = ("%.0f°" if ch == "rotation_deg" else "%.2f") % x
				(slider.get_meta("reset") as Button).disabled = absf(x - float(CHANNEL_RESET[ch])) < 0.001


## A choice or image field's button: what it is now.
func _show_choice(r: Dictionary, value) -> void:
	var text := StudioConfigEdits.choice_label(r.field, value) if r.kind == "choice" \
			else (ImageLibrary.label_of(String(value)) if String(value) != "" else "None")
	(r.controls[0] as Button).text = text + "  ▾"


func _show_value(r: Dictionary, value) -> void:
	if r.get("reset") != null:
		(r.reset as Button).disabled = _at_default(r.field, value)
	match r.kind:
		"bool", "choice", "texture":
			r.value.text = ""
		"int":
			r.value.text = str(int(value))
		"float":
			var step := float(r.field.get("step", 0.01))
			r.value.text = ("%.0f" if step >= 1.0 else "%.3f" if step < 0.01 else "%.2f") % float(value)
		"vec3":
			var v: Array = value
			r.value.text = "%.0f %.0f %.0f" % [v[0], v[1], v[2]]
		"color":
			var c := _color(value)
			r.value.text = "#" + c.to_html(r.field.get("alpha", false))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(c, 1.0)
			sb.border_color = Color(1, 1, 1, 0.6)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(6)
			var swatch: Button = r.controls[0]
			for state in ["normal", "hover", "pressed"]:
				swatch.add_theme_stylebox_override(state, sb)


## Whether `value` is the field's default (↺ has nothing to do).
static func _at_default(field: Dictionary, value) -> bool:
	var d = field.get("default")
	if d == null:
		return true
	match field.type:
		"float", "int":
			return absf(float(value) - float(d)) < maxf(float(field.get("step", 0.01)) * 0.5, 1e-6)
		"bool":
			return bool(value) == bool(d)
		"choice", "texture":
			return str(value) == str(d)
		"color", "vec3":
			var a: Array = _color_array(value)
			var b: Array = _color_array(d)
			for c in mini(a.size(), b.size()):
				if absf(float(a[c]) - float(b[c])) > 0.002:
					return false
			return true
	return value == d


static func _color_array(v) -> Array:
	if v is Color:
		return [v.r, v.g, v.b, v.a]
	return v if typeof(v) == TYPE_ARRAY else []


static func _color(value) -> Color:
	if value is Color:
		return value
	var a: Array = value
	return Color(a[0], a[1], a[2], a[3] if a.size() > 3 else 1.0)


func _show_diamond(b: Button, state: String) -> void:
	match state:
		"key":
			b.text = "◆"
			b.add_theme_color_override("font_color", RECORD)
		"animated":
			b.text = "◇"
			b.add_theme_color_override("font_color", RECORD)
		"unkeyed":
			b.text = "◆"
			b.add_theme_color_override("font_color", UNKEYED)
		"static":
			b.text = "•"
			b.add_theme_color_override("font_color", DIM)
		_:
			b.text = ""
	b.tooltip_text = {"key": "A key here: tap to remove it", "animated": "Animated: tap to key it here",
			"unkeyed": "Changed here, not keyed yet: tap to key it (moving the playhead drops it)",
			"static": "Tap to key it here", "none": ""}.get(state, "")


# ---------- widgets ----------

## The smallest comfortable target height (about 2.5 cm on the headset panel).
func _target_h() -> float:
	return _fs * (1.7 if vr else 1.4)


func _small_button(text: String, on_press: Callable) -> Button:
	var b := _button(text, on_press)
	b.custom_minimum_size = Vector2(_target_h(), _target_h())
	return b


## An on / off switch: a pill with its knob at the right (lit) when on.
func _pill(on: bool, on_toggle: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	var h := _target_h() if vr else _fs * 1.3
	b.custom_minimum_size = Vector2(h * 1.9, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(int(h / 2.0))
		sb.content_margin_left = h * 0.15
		sb.content_margin_right = h * 0.15
		var lit: bool = state in ["pressed", "hover_pressed"]
		sb.bg_color = ACCENT if lit else Color(0.3, 0.33, 0.4)
		if state.begins_with("hover"):
			sb.bg_color = sb.bg_color.lightened(0.12)
		b.add_theme_stylebox_override(state, sb)
	# The knob is drawn, not a "●" in the text: a glyph sits where the
	# font's metrics put it, off the track's middle.
	b.draw.connect(func():
		var r := b.size.y / 2.0
		var x := b.size.x - r if b.button_pressed else r
		b.draw_circle(Vector2(x, r), r * 0.72, Color.WHITE if b.button_pressed else Color(0.85, 0.87, 0.9), true, -1.0, true))
	_show_pill(b, on)
	b.toggled.connect(func(v: bool):
		_show_pill(b, v)
		on_toggle.call(v))
	return b


static func _show_pill(b: Button, on: bool) -> void:
	b.set_pressed_no_signal(on)
	b.queue_redraw()
	b.tooltip_text = b.tooltip_text if b.tooltip_text != "" else "On / off"


## Slider grabbers and track `factor` times the default size.
static func _scale_sliders(th: Theme, factor: float) -> void:
	var base := ThemeDB.get_default_theme()
	for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
		var tex := base.get_icon(icon, "HSlider")
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		img.resize(int(img.get_width() * factor), int(img.get_height() * factor), Image.INTERPOLATE_BILINEAR)
		th.set_icon(icon, "HSlider", ImageTexture.create_from_image(img))
	for box in ["slider", "grabber_area", "grabber_area_highlight"]:
		var sb := base.get_stylebox(box, "HSlider")
		if sb == null:
			continue
		sb = sb.duplicate()
		sb.content_margin_top = maxf(sb.content_margin_top, 0.0) * factor
		sb.content_margin_bottom = maxf(sb.content_margin_bottom, 0.0) * factor
		th.set_stylebox(box, "HSlider", sb)
	# The number fields' arrows too.
	for icon in ["up", "down", "updown"]:
		var tex := base.get_icon(icon, "SpinBox")
		if tex == null or tex.get_image() == null:
			continue
		var img := tex.get_image()
		img.resize(int(img.get_width() * factor), int(img.get_height() * factor), Image.INTERPOLATE_BILINEAR)
		th.set_icon(icon, "SpinBox", ImageTexture.create_from_image(img))

func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
