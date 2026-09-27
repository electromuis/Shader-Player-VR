class_name StudioInspector
extends PanelContainer

## Studio's inspector: everything about the selected object besides where it
## is, in sections (transform, display, the layer's shader, each effect,
## modifiers, reactive), with controls generated from the shaders' hints.
## Each property has a key diamond: ◆ a key at the playhead, ◇ animated,
## • still (tap it to add or remove a key at the playhead). The effects stack
## can be added to, reordered, switched off and on, and removed.
##
## It's a view of StudioConfigEdits: dragging a control shows the value live
## (preview), letting go writes it as one undoable step (commit), the way
## auto-key says. The same scene is the desktop's side panel and, in the
## headset, a panel beside the selection (bigger text there: `vr`, which it
## works out itself when it's inside a SubViewport).

signal said(text: String)
signal close_requested

const ACCENT := Color(0.3, 0.79, 0.94)
const RECORD := Color(1.0, 0.36, 0.36)
const DIM := Color(0.72, 0.75, 0.8)
const PANEL_BG := Color(0.06, 0.06, 0.09, 0.92)
## A change made without a drag (a click, the colour wheel) is written once
## it has been left alone this long.
const SETTLE := 0.6
## How often shown values follow the playhead (seconds).
const REFRESH := 0.1
## Sections open when first shown (the rest start folded).
const OPEN_BY_DEFAULT := ["Transform", "Display", "Layer shader"]

## Headset layout: bigger text and targets.
var vr := false

var edits: StudioConfigEdits
var tools: StudioEditTools

var _id := ""
var _rows: Array = []  # [{field, kind, controls, diamond, value}]
var _open := {}  # section key -> bool
var _pending := {}  # field key -> {field, value, since, dragging}
var _needs_build := true
var _menu := ""  # the inline choice list that's open ("add_effect" / "layer_shader"), "" none
var _since_refresh := 0.0
var _clock := 0.0
var _keep_scroll := -1
var _picker_open := ""  # field key whose colour wheel is open
var _reveal := ""  # field key (or "add_effect") to scroll into view after the next build

var _title: Label
var _kind: Label
var _hint: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _fs := 15
var _label_w := 132
var _value_w := 58
var _diamond_w := 26


func _ready() -> void:
	vr = vr or get_viewport() != get_tree().root
	_fs = 26 if vr else 15
	_label_w = 230 if vr else 132
	_value_w = 104 if vr else 58
	_diamond_w = 48 if vr else 26
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
	rows.add_theme_constant_override("separation", 8 if vr else 4)
	add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	rows.add_child(top)
	_title = _label(top, int(_fs * 1.3), Color.WHITE)
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind = _label(top, _fs, DIM)
	var close := _button("✕", func(): close_requested.emit())
	close.tooltip_text = "Deselect"
	top.add_child(close)
	_hint = _label(rows, int(_fs * 0.9), DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6 if vr else 3)
	_scroll.add_child(_list)


## Show `id` ("" for nothing).
func show_object(id: String) -> void:
	if id == _id:
		return
	_commit_all()
	_id = id
	_menu = ""
	_picker_open = ""
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


## Open or fold a section by its key: its title ("Display", "Modifiers"),
## or "effect<i>" for effect i.
func set_section_open(title: String, open: bool) -> void:
	_open[title] = open
	_needs_build = true


func _process(delta: float) -> void:
	_clock += delta
	if edits == null or tools == null:
		return
	for key in _pending.keys():
		var p: Dictionary = _pending[key]
		if not p.dragging and _clock - p.since >= SETTLE and key != _picker_open:
			_commit(key)
	if _needs_build and _pending.is_empty():
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
	var node := _node()
	if _id == "" or edits.model == null:
		_title.text = "Inspector"
		_kind.text = ""
		_hint.text = "Select something to see its settings: point and pull the trigger, or click it."
		return
	_title.text = _id
	var kind := edits.kind_for(_id, node)
	var si := edits.model.spawn_index(_id)
	var spawn: Dictionary = edits.model.tracks()[si] if si >= 0 else {}
	_kind.text = "%s (%s)" % [kind, spawn.get("prefab", "?")] if kind == "object" else kind
	var sections := edits.sections(_id, node, kind)
	for s in sections:
		if s.title == "Modifiers" and kind != "object":
			_add_effect_adder()
		match s.kind:
			"transform": _add_transform(s)
			"effect": _add_effect(s)
			"layer_shader": _add_layer_shader(s)
			_: _add_section(s.title, s.title, s.fields)
	_refresh_values()
	_scroll.set_deferred("scroll_vertical", scroll)
	if _reveal != "":
		var target: Control = null
		for r in _rows:
			if r.field.key == _reveal:
				target = r.controls.back() if not r.controls.is_empty() else r.diamond
		if _reveal == "add_effect":
			target = _list.find_child("AddEffectChoices", false, false)
		_reveal = ""
		if target != null:
			_scroll_to.call_deferred(target)


## After the layout settles (and the kept scroll position is back).
func _scroll_to(target: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(target):
		_scroll.ensure_control_visible(target)


## A foldable section: its header and a body with a row per field.
func _add_section(key: String, title: String, fields: Array, header_extra: Callable = Callable(), note_empty := true) -> VBoxContainer:
	var open: bool = _open.get(key, title in OPEN_BY_DEFAULT)
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
	if header_extra.is_valid():
		header_extra.call(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4 if vr else 2)
	body.visible = open
	_list.add_child(body)
	var group := ""
	for f in fields:
		var g := String(f.get("group", ""))
		if g != group and g != "":
			var gl := _label(body, int(_fs * 0.85), DIM)
			gl.text = g.capitalize()
		group = g
		_add_field(body, f)
	if fields.is_empty() and open and note_empty:
		var none := _label(body, int(_fs * 0.9), DIM)
		none.text = "No settings."
	return body


func _add_field(parent: Control, field: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var diamond := _button("", func(): _toggle_key(field))
	diamond.flat = true
	diamond.custom_minimum_size.x = _diamond_w
	row.add_child(diamond)
	var name := _label(row, _fs, Color.WHITE)
	name.text = field.label
	name.custom_minimum_size.x = _label_w
	name.clip_text = true
	var r := {"field": field, "kind": field.type, "controls": [], "diamond": diamond, "value": null}
	match field.type:
		"bool":
			var sw := _switch(false, func(on: bool): _set_now(field, on))
			row.add_child(sw)
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
				var slider := _slider(field)
				slider.value_changed.connect(func(_v): _changed(field, _vec_of(r), true))
				slider.drag_started.connect(func(): _drag(field, true))
				slider.drag_ended.connect(func(_c): _drag(field, false))
				box.add_child(slider)
				r.controls.append(slider)
		_:
			var slider := _slider(field)
			slider.value_changed.connect(func(v: float): _changed(field, int(v) if field.type == "int" else v, true))
			slider.drag_started.connect(func(): _drag(field, true))
			slider.drag_ended.connect(func(_c): _drag(field, false))
			row.add_child(slider)
			r.controls = [slider]
	var value := _label(row, int(_fs * 0.9), DIM)
	value.custom_minimum_size.x = _value_w
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.value = value
	_rows.append(r)


func _slider(field: Dictionary) -> HSlider:
	var s := HSlider.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size.y = _fs * 1.4
	s.scrollable = false
	s.focus_mode = Control.FOCUS_NONE
	s.min_value = field.min
	s.max_value = field.max
	s.step = field.step
	return s


static func _vec_of(r: Dictionary) -> Array:
	return r.controls.map(func(s: HSlider): return s.value)


func _add_transform(s: Dictionary) -> void:
	var body := _add_section("Transform", "Transform", [], Callable(), false)
	for ch in StudioConfigEdits.CHANNELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		body.add_child(row)
		var diamond := _button("", func(): _toggle_transform_key(ch))
		diamond.flat = true
		diamond.custom_minimum_size.x = _diamond_w
		row.add_child(diamond)
		var name := _label(row, _fs, Color.WHITE)
		name.text = {"position": "Position", "rotation_deg": "Rotation °", "scale": "Scale"}[ch]
		name.custom_minimum_size.x = _label_w
		var value := _label(row, _fs, DIM)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.append({"field": {"key": "transform/" + ch, "channel": ch}, "kind": "transform", "controls": [],
			"diamond": diamond, "value": value})
	if body.visible:
		var tip := _label(body, int(_fs * 0.85), DIM)
		tip.text = "Grab it to move it (the grip, or drag with the mouse)."


func _add_effect(s: Dictionary) -> void:
	var i: int = s.index
	var count := edits.model.effects_of(_id).size()
	var body := _add_section("effect%d" % i, s.title + ("" if s.enabled else "  (off)"), s.fields, func(head: HBoxContainer):
		head.set_meta("effect", i)
		var on := _switch(s.enabled, func(v: bool): _effect_op(func(): return edits.model.set_effect_enabled(_id, i, v)))
		on.tooltip_text = "On / off"
		head.add_child(on)
		var up := _small_button("↑", func(): _effect_op(func(): return edits.model.move_effect(_id, i, i - 1)))
		up.disabled = i == 0
		head.add_child(up)
		var down := _small_button("↓", func(): _effect_op(func(): return edits.model.move_effect(_id, i, i + 1)))
		down.disabled = i >= count - 1
		head.add_child(down)
		var remove := _small_button("✕", func(): _effect_op(func(): return edits.model.remove_effect(_id, i)))
		remove.tooltip_text = "Remove"
		head.add_child(remove))
	if not s.enabled:
		body.modulate = Color(1, 1, 1, 0.55)


func _add_effect_adder() -> void:
	var add := _button("+ Add effect", func():
		_menu = "" if _menu == "add_effect" else "add_effect"
		if _menu != "":
			_reveal = "add_effect"
		_needs_build = true)
	add.name = "AddEffect"
	add.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add.custom_minimum_size.y = _target_h()
	_list.add_child(add)
	if _menu == "add_effect":
		var grid := _add_choices(edits.effect_options(), func(key: String):
			var n := edits.model.effects_of(_id).size()
			if _effect_op(func(): return edits.add_effect(_id, key)):
				_open["effect%d" % n] = true)
		grid.name = "AddEffectChoices"


func _add_layer_shader(s: Dictionary) -> void:
	var current := String(s.get("shader", ""))
	var label := "none"
	for o in edits.layer_shader_options():
		if edits.model.shader_key_of(o.key) == current and current != "":
			label = o.label
	if label == "none" and current != "":
		label = current.capitalize()
	var body := _add_section("Layer shader", "Layer shader: %s" % label, s.fields)
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


## A grid of buttons, one per option ({key, label}); picking one closes it.
func _add_choices(options: Array, on_pick: Callable) -> GridContainer:
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
		grid.add_child(b)
	_list.add_child(grid)
	return grid


# ---------- changing ----------

func _node() -> Node3D:
	if _id == "" or tools == null or tools.runner == null:
		return null
	var n := tools.runner.registry().get_node_by_id(_id)
	return n if n != null and is_instance_valid(n) else null


func _playhead() -> float:
	return tools.runner.playhead if tools != null and tools.runner != null else 0.0


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


## A switch: written straight away.
func _set_now(field: Dictionary, value) -> void:
	_pending[field.key] = {"field": field, "value": value, "since": _clock, "dragging": false}
	_commit(field.key)


func _commit(key: String) -> void:
	if not _pending.has(key):
		return
	var p: Dictionary = _pending[key]
	_pending.erase(key)
	var label := edits.commit(_id, p.field, p.value, _playhead(), tools.auto_key)
	edits.end_preview(_id, p.field, label == "")
	if label != "":
		said.emit(label + ".")


func _commit_all() -> void:
	for key in _pending.keys():
		_commit(key)


func _toggle_key(field: Dictionary) -> void:
	_commit_all()
	var label := edits.toggle_key(_id, field, _playhead())
	if label != "":
		said.emit(label + ".")
	elif String(field.slot) == "":
		said.emit("%s can't be animated%s." % [field.label, " while the effect is off" if String(field.key).begins_with("effect") else ""])


func _toggle_transform_key(channel: String) -> void:
	var node := _node()
	if node == null:
		return
	var label := edits.toggle_transform_key(_id, channel, _playhead(), GrabMath.to_dict(node.transform))
	if label != "":
		said.emit(label + ".")


func _effect_op(op: Callable) -> bool:
	_commit_all()
	var done: bool = op.call()
	if done:
		said.emit(edits.model.undo_label() + ".")
	return done


# ---------- showing values ----------

func _refresh_values() -> void:
	if _id == "" or edits == null:
		return
	var t := _playhead()
	if tools.auto_key:
		_hint.text = "● Auto-key: changes key at %s." % StudioStatus.timecode(t)
		_hint.add_theme_color_override("font_color", RECORD)
	else:
		_hint.text = "Changes set the piece's values; animated ones scale as a whole.\n◆ key here   ◇ animated   • still"
		_hint.add_theme_color_override("font_color", DIM)
	var node := _node()
	for r in _rows:
		if r.kind == "transform":
			var ch: String = r.field.channel
			_show_diamond(r.diamond, edits.transform_state(_id, ch, t))
			if node != null:
				var v: Array = GrabMath.to_dict(node.transform)[ch]
				var fmt := "%.0f" if ch == "rotation_deg" else "%.2f"
				r.value.text = ", ".join(v.map(func(x): return (fmt % x).trim_prefix("-") if absf(x) < (0.5 if ch == "rotation_deg" else 0.005) else fmt % x))
			continue
		_show_diamond(r.diamond, edits.key_state(_id, r.field, t))
		if _pending.has(r.field.key):
			continue
		var value = edits.value_of(_id, r.field, t)
		match r.kind:
			"bool":
				_show_switch(r.controls[0], bool(value))
			"float", "int":
				(r.controls[0] as HSlider).set_value_no_signal(float(value))
			"vec3":
				for c in 3:
					(r.controls[c] as HSlider).set_value_no_signal(float(value[c]))
			"color":
				if r.controls.size() > 1 and _picker_open != r.field.key:
					(r.controls[1] as ColorPicker).color = _color(value)
		_show_value(r, value)


func _show_value(r: Dictionary, value) -> void:
	match r.kind:
		"bool":
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
		"static":
			b.text = "•"
			b.add_theme_color_override("font_color", DIM)
		_:
			b.text = ""
	b.tooltip_text = {"key": "A key here: tap to remove it", "animated": "Animated: tap to key it here",
			"static": "Tap to key it here", "none": ""}.get(state, "")


# ---------- widgets ----------

## The smallest comfortable target height (about 2.5 cm on the headset panel).
func _target_h() -> float:
	return _fs * (1.7 if vr else 1.4)


func _small_button(text: String, on_press: Callable) -> Button:
	var b := _button(text, on_press)
	b.custom_minimum_size = Vector2(_target_h(), _target_h())
	return b


## An On / Off toggle (bigger and clearer than a checkbox on the headset).
func _switch(on: bool, on_toggle: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(_fs * 3.4, _target_h())
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(4)
		var lit: bool = state in ["pressed", "hover_pressed"]
		sb.bg_color = Color(ACCENT, 0.3) if lit else Color(0.17, 0.2, 0.27)
		if state.begins_with("hover"):
			sb.bg_color = sb.bg_color.lightened(0.1)
		if lit:
			sb.border_color = ACCENT
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	_show_switch(b, on)
	b.toggled.connect(func(v: bool):
		_show_switch(b, v)
		on_toggle.call(v))
	return b


static func _show_switch(b: Button, on: bool) -> void:
	b.set_pressed_no_signal(on)
	b.text = "On" if on else "Off"


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
