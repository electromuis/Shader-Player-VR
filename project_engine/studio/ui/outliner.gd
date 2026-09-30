class_name StudioOutliner
extends PanelContainer

## Studio's outliner (TODO 15): the piece's objects as a tree
## (StudioGrouping.tree), groups with their members indented under them,
## then the viewer and the camera effects when the piece has them. Each
## row: a box to pick it, a fold arrow on anything with objects inside, its
## name and its kind. Rows not on stage at the playhead are dimmed.
##
## Click a row to select it (what you can't easily point at, like a group,
## which has no picture of its own). Ctrl+ or Shift+click, or its box,
## picks several: Group (Ctrl+G) puts the picked ones and the selection in
## a new group; Ungroup takes the selected group's members out and removes
## it. Drag a row onto a group to put it in (onto the strip under the list
## to take it out of its group). The edits themselves are Studio's (the
## signals), through StudioGrouping. The same scene is the desktop's panel
## and the headset's (bigger there: `vr`, worked out from being inside a
## SubViewport).

signal said(text: String)
## – or ✕: fold the panel to its tab (the wrist's Outliner button).
signal minimize_requested
signal group_requested(ids: Array)
signal ungroup_requested(id: String)
## Put `id` in `parent` ("" to take it out of its group).
signal parent_requested(id: String, parent: String)
## The picked rows changed here (Studio shows the other view's).
signal picked_changed

const ACCENT := Color(0.3, 0.79, 0.94)
const DIM := Color(0.72, 0.75, 0.8)
const PANEL_BG := Color(0.06, 0.06, 0.09, 0.92)
const ROW_BG := Color(0.11, 0.13, 0.18)
## Rows not on stage now.
const OFF_STAGE := 0.45
## A press that moves this far (px) is a drag.
const DRAG := 8.0
## How often the rows' on-stage dimming follows the playhead (seconds).
const REFRESH := 0.25

var model: EditModel
var tools: StudioEditTools
var edits: StudioConfigEdits
## The playhead (a Callable returning seconds), for what's on stage now.
var playhead: Callable
## The rows picked for grouping, shared by the desktop's and the
## headset's outliner (Studio hands both the same array).
var picked: Array = []
## Groups folded shut (their members hidden).
var folded: Dictionary = {}
var vr := false

var _fs := 15
var _row_h := 28
var _list: VBoxContainer
var _scroll: ScrollContainer
var _hint: Label
var _group_button: Button
var _ungroup_button: Button
var _out_zone: PanelContainer
var _rows: Dictionary = {}  # id -> row Button
var _spans: Dictionary = {}  # id -> [[from, to]]
var _press: Dictionary = {}  # {id, at, several} while a row is pressed
var _drop_on := ""  # the row a drag is over ("" none; "$out" the strip)
var _needs_build := true
var _since_refresh := 0.0


func _ready() -> void:
	vr = vr or get_viewport() != get_tree().root
	_fs = 28 if vr else 15
	_row_h = 60 if vr else 28
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
	rows.add_theme_constant_override("separation", 8 if vr else 4)
	add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	rows.add_child(top)
	var title := _label(top, int(_fs * 1.3), Color.WHITE)
	title.text = "Outliner"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in [["—", "Fold to a tab (O brings it back)"], ["✕", "Close (O brings it back)"]]:
		var b := _button(t[0], func(): minimize_requested.emit())
		b.tooltip_text = t[1]
		if vr:
			b.custom_minimum_size = Vector2(_row_h, _row_h)
		top.add_child(b)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16 if vr else 10)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4 if vr else 2)
	pad.add_child(_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	rows.add_child(buttons)
	_group_button = _button("Group", func(): group_requested.emit(group_ids()))
	_ungroup_button = _button("Ungroup", func(): ungroup_requested.emit(tools.selected if tools != null else ""))
	for b in [_group_button, _ungroup_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = _row_h
		buttons.add_child(b)
	_hint = _label(rows, int(_fs * 0.85), DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## The piece or the selection changed: rebuild on the next frame.
func request_rebuild() -> void:
	_needs_build = true


## What Group would put in a group: the picked rows and the selection.
func group_ids() -> Array:
	var out: Array = picked.duplicate()
	if tools != null and tools.selected != "" and not tools.selected.begins_with("$") and not out.has(tools.selected):
		out.push_front(tools.selected)
	return out


## Pick or unpick `id` (the row's box, Ctrl+click).
func toggle_pick(id: String) -> void:
	if picked.has(id):
		picked.erase(id)
	else:
		picked.append(id)
	_needs_build = true
	picked_changed.emit()


## Click on a row: select it (its box or Ctrl / Shift: pick it instead).
func click(id: String, several: bool = false) -> void:
	if several and not id.begins_with("$"):
		toggle_pick(id)
		return
	if tools != null:
		tools.select(id)


## Drop `id` onto `target` (a row's id; "" for the strip under the list).
func drop(id: String, target: String) -> void:
	if id == target or id.begins_with("$"):
		return
	if target != "" and (target.begins_with("$") or not StudioGrouping.is_group(model, target)):
		said.emit("Drop %s on a group to put it in (or make one: Ctrl+G, or Group here)." % id)
		return
	parent_requested.emit(id, target)


func _process(delta: float) -> void:
	if _needs_build:
		_needs_build = false
		_build()
	_since_refresh += delta
	if _since_refresh >= REFRESH:
		_since_refresh = 0.0
		_refresh()


# ---------- building ----------

func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	_spans.clear()
	if model == null:
		_hint.text = "Open a piece to see its objects."
		_group_button.disabled = true
		_ungroup_button.disabled = true
		return
	var ids: Array = model.object_ids()
	picked.assign(picked.filter(func(p): return ids.has(p)))
	var lanes := StudioTimeline.lanes(model, _duration())
	for lane in lanes:
		_spans[lane.id] = lane.spans
	var shut := {}  # folded rows, and rows hidden inside them: their members hide
	for row in StudioGrouping.tree(model):
		if shut.has(row.parent):
			shut[row.id] = true
			continue
		_add_row(row.id, row.depth, row.children > 0, _kind(row))
		if folded.get(row.id, false):
			shut[row.id] = true
	for lane in lanes:
		if String(lane.id).begins_with("$"):
			_add_row(lane.id, 0, false, "path" if lane.id == ScriptFormat.VIEWER else "effects")
	_out_zone = PanelContainer.new()
	_out_zone.custom_minimum_size.y = _row_h
	_out_zone.visible = false
	var out_label := _label(_out_zone, int(_fs * 0.9), ACCENT)
	out_label.text = "⤒  Drop here: out of its group"
	out_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_zone(false)
	_list.add_child(_out_zone)
	var sel := tools.selected if tools != null else ""
	var n := group_ids().size()
	_group_button.text = ("Group %d" % n if n > 1 else "Group") + ("" if vr else " (Ctrl+G)")
	_group_button.disabled = n == 0
	_ungroup_button.disabled = sel == "" or sel.begins_with("$") or StudioGrouping.children_of(model, sel).is_empty()
	_hint.text = "Click to select · %s to pick several · drag onto a group to put it in" % ("☐" if vr else "Ctrl+click or ☐")
	_refresh()


func _kind(row: Dictionary) -> String:
	if row.group:
		return "group"
	var kind := edits.kind_for(row.id) if edits != null else "object"
	if kind == "object":
		var i := model.spawn_index(row.id)
		return String(model.tracks()[i].get("prefab", "object")) if i >= 0 else "object"
	return kind


func _add_row(id: String, depth: int, has_kids: bool, kind: String) -> void:
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = _row_h
	row.set_meta("id", id)
	row.gui_input.connect(_row_input.bind(row))
	_list.add_child(row)
	_rows[id] = row
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.add_theme_constant_override("separation", 6 if vr else 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var box := _button("☑" if picked.has(id) else "☐", func(): toggle_pick(id))
	box.flat = true
	box.custom_minimum_size = Vector2(_row_h, _row_h)
	box.tooltip_text = "Pick it too (Ctrl+click): Group puts the picked ones together"
	box.modulate.a = 0.0 if id.begins_with("$") else 1.0
	box.disabled = id.begins_with("$")
	line.add_child(box)
	var indent := Control.new()
	indent.custom_minimum_size.x = depth * (32 if vr else 16)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(indent)
	var fold := _button(("▸" if folded.get(id, false) else "▾") if has_kids else "", func():
		folded[id] = not folded.get(id, false)
		_needs_build = true)
	fold.flat = true
	fold.custom_minimum_size = Vector2(_row_h * 0.8, _row_h)
	fold.disabled = not has_kids
	line.add_child(fold)
	var name_label := _label(line, _fs, Color.WHITE)
	name_label.text = EditModel.who(id) if id.begins_with("$") else id
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind_label := _label(line, int(_fs * 0.8), DIM)
	kind_label.text = kind + "  "
	kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_row(row, id)


func _style_row(row: Button, id: String) -> void:
	var sel := tools != null and tools.selected == id
	var over := _drop_on == id
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT, 0.3) if sel else (Color(ACCENT, 0.12) if picked.has(id) else ROW_BG)
		if state == "hover" and not sel:
			sb.bg_color = sb.bg_color.lightened(0.08)
		sb.border_color = ACCENT if (sel or over) else Color(0, 0, 0, 0)
		sb.set_border_width_all(3 if over else (2 if sel else 0))
		sb.set_corner_radius_all(8 if vr else 5)
		row.add_theme_stylebox_override(state, sb)


func _style_zone(over: bool) -> void:
	if _out_zone == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ACCENT, 0.25 if over else 0.08)
	sb.border_color = Color(ACCENT, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8 if vr else 5)
	_out_zone.add_theme_stylebox_override("panel", sb)


## Dim what isn't on stage now.
func _refresh() -> void:
	if not playhead.is_valid():
		return
	var t: float = playhead.call()
	for id in _rows:
		var spans: Array = _spans.get(id, [])
		var on := spans.any(func(s): return s[0] <= t + 0.0005 and t < s[1])
		_rows[id].modulate.a = 1.0 if on else OFF_STAGE


func _duration() -> float:
	return StudioGrouping.horizon(model)


# ---------- pressing and dragging rows ----------

func _row_input(event: InputEvent, row: Button) -> void:
	var id := String(row.get_meta("id"))
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_press = {"id": id, "at": mb.global_position, "several": mb.ctrl_pressed or mb.shift_pressed, "dragging": false}
		elif not _press.is_empty():
			var p := _press
			_press = {}
			if p.dragging:
				var target := _drop_on
				_set_drop_on("")
				_out_zone.visible = false
				if target != "":
					drop(p.id, "" if target == "$out" else target)
			else:
				click(p.id, p.several)
		row.accept_event()
	elif event is InputEventMouseMotion and not _press.is_empty():
		var at := (event as InputEventMouseMotion).global_position
		if not _press.dragging and at.distance_to(_press.at) > DRAG and not String(_press.id).begins_with("$"):
			_press.dragging = true
			_out_zone.visible = StudioGrouping.parent_of(model, _press.id) != ""
			said.emit("Drag %s onto a group to put it in%s." % [_press.id, ", or onto the strip under the list to take it out" if _out_zone.visible else ""])
		if _press.dragging:
			_set_drop_on(_row_at(at))


## The row (or "$out", the strip) under `at` (global), "" for none.
func _row_at(at: Vector2) -> String:
	if _out_zone != null and _out_zone.visible and _out_zone.get_global_rect().has_point(at):
		return "$out"
	for id in _rows:
		if _rows[id].get_global_rect().has_point(at):
			return id
	return ""


func _set_drop_on(id: String) -> void:
	if id == _drop_on:
		return
	var was := _drop_on
	_drop_on = id
	for k in [was, id]:
		if _rows.has(k):
			_style_row(_rows[k], k)
	_style_zone(id == "$out")


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
