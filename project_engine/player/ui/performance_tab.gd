extends VBoxContainer

## The Performance tab (the player's menu and Studio's): what the frame
## costs on the GPU against the display's budget, the parts that cost most
## (GpuCost: every layer shader, effect and video pass directly; the 3D
## view split on request), and a benchmark of the whole piece
## (GpuBenchmark). Built in code, like the Config tab.
##
## Measures only while the tab shows (GpuCost.set_active), so it costs
## nothing otherwise. In Studio a row of a script object selects it (the
## `select` callable bind() gets).

const ROWS := 12
const INTERVAL := 0.25  # seconds between refreshes
const PURPLE := Color(0.6, 0.42, 0.92)
const BLUE := Color(0.25, 0.66, 0.8)
const GREY := Color(0.45, 0.47, 0.52)
const GREEN := Color(0.35, 0.85, 0.45)
const AMBER := Color(0.98, 0.72, 0.25)
const RED := Color(0.95, 0.35, 0.35)
const DIM := Color(0.65, 0.67, 0.72)

var _stage: Stage
var _cost: GpuCost
var _select: Callable
var _bench := GpuBenchmark.new()
var _elapsed := INTERVAL

var _frame: Label
var _bar: _Meter
var _fps: Label
var _cpu: Label
var _list: VBoxContainer
var _rows: Array[Dictionary] = []  # [{button, name, kind, meter, ms, select}]
var _probe: Button
var _benchmark: Button
var _bench_progress: ProgressBar
var _bench_text: Label
var _moments: VBoxContainer
var _help: Label


## A bar: `fraction` filled in `color` over a dark track.
class _Meter:
	extends Control
	var fraction := 0.0
	var color := Color.WHITE
	var track := Color(0.15, 0.17, 0.23)

	func set_value(f: float, c: Color) -> void:
		if is_equal_approx(f, fraction) and c == color:
			return
		fraction = f
		color = c
		queue_redraw()

	func _draw() -> void:
		var r := size.y * 0.5
		draw_style_box(_box(track, r), Rect2(Vector2.ZERO, size))
		var w := clampf(fraction, 0.0, 1.0) * size.x
		if w > 1.0:
			draw_style_box(_box(color, r), Rect2(0, 0, maxf(w, size.y), size.y))

	static func _box(c: Color, r: float) -> StyleBoxFlat:
		var b := StyleBoxFlat.new()
		b.bg_color = c
		b.set_corner_radius_all(int(r))
		return b


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_frame = Label.new()
	_frame.add_theme_font_size_override("font_size", 20)
	add_child(_frame)
	_bar = _Meter.new()
	_bar.custom_minimum_size = Vector2(0, 16)
	add_child(_bar)
	var under := HBoxContainer.new()
	_cpu = _dim_label("")
	_cpu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	under.add_child(_cpu)
	_fps = Label.new()
	under.add_child(_fps)
	add_child(under)
	add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)
	for i in ROWS:
		_rows.append(_make_row())
	add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_benchmark = Button.new()
	_benchmark.text = "▶ Benchmark the piece"
	_benchmark.custom_minimum_size = Vector2(240, 44)
	_benchmark.pressed.connect(_on_benchmark)
	buttons.add_child(_benchmark)
	_probe = Button.new()
	_probe.text = "Measure the 3D view's parts"
	_probe.custom_minimum_size = Vector2(0, 44)
	_probe.tooltip_text = "Switches each object, layer and the camera effect off in turn for a moment (they blink) and times how much faster the view draws"
	_probe.pressed.connect(_on_probe)
	buttons.add_child(_probe)
	add_child(buttons)
	_bench_progress = ProgressBar.new()
	_bench_progress.max_value = 1.0
	_bench_progress.show_percentage = false
	_bench_progress.custom_minimum_size = Vector2(0, 8)
	_bench_progress.visible = false
	add_child(_bench_progress)
	_bench_text = _dim_label("The benchmark plays the piece through as fast as it draws and lists the heaviest moments.")
	add_child(_bench_text)
	_moments = VBoxContainer.new()
	add_child(_moments)
	_help = _dim_label("Layer shaders, effects and the video frame are timed on the GPU as they draw. The 3D view (objects, surfaces, vertex effects, 3D layers, the camera effect) is one number until you measure its parts: each is then how much faster the view gets with that one switched off.")
	add_child(_help)
	_bench.progress.connect(func(f: float): _bench_progress.value = f)
	_bench.finished.connect(_on_benchmark_done)


## `stage`'s GpuCost is measured; `select` (optional) takes a script
## object's id when its row is pressed (Studio selects it).
func bind(stage: Stage, select: Callable = Callable()) -> void:
	_stage = stage
	_cost = stage.gpu_cost
	_select = select
	_cost.probed.connect(_on_probed)
	_update_buttons()


func _exit_tree() -> void:
	if _cost != null:
		_cost.set_active(_holder(), false)


## This tab's name with GpuCost (Studio has two menus, each with the tab).
func _holder() -> String:
	return "tab%d" % get_instance_id()


## On screen: the tab is picked, and the panel it's on (a SubViewport on a
## 3D quad in the headset, which keeps its content "visible" while the quad
## is hidden) shows too.
func _showing() -> bool:
	if not is_visible_in_tree():
		return false
	var vp := get_viewport()
	while vp is SubViewport:
		var holder := vp.get_parent()
		if holder == null:
			break
		if (holder is Node3D or holder is CanvasItem) and not holder.is_visible_in_tree():
			return false
		vp = holder.get_viewport()
	return true


func _process(delta: float) -> void:
	if _cost == null:
		return
	var showing := _showing()
	_cost.set_active(_holder(), showing)
	if not showing:
		return
	_elapsed += delta
	if _elapsed < INTERVAL:
		return
	_elapsed = 0.0
	_refresh()


func _refresh() -> void:
	var budget := _cost.budget_ms()
	var total := _cost.total_ms
	var where := "in the headset" if _stage.xr_mode.is_in_vr() else "on this display"
	_frame.text = "This frame: %.1f ms of %.1f ms (%d Hz %s)" % [total, budget, roundi(_cost.refresh_hz()), where]
	_bar.set_value(total / budget if budget > 0.0 else 0.0, _load_color(total, budget))
	var fps := roundi(Engine.get_frames_per_second())
	_fps.text = "%d fps" % fps
	_fps.add_theme_color_override("font_color", GREEN if fps >= roundi(_cost.refresh_hz()) - 1 else AMBER)
	_cpu.text = "GPU time, all passes · CPU: scripts %.1f ms, physics %.1f ms" % [
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]
	var ranked := _cost.ranked()
	var top := 0.0
	for r in ranked:
		top = maxf(top, r.ms)
	for i in ROWS:
		var row: Dictionary = _rows[i]
		if i >= ranked.size():
			row.button.visible = false
			continue
		var r: Dictionary = ranked[i]
		row.button.visible = true
		row.name.text = r.label
		row.kind.text = r.kind
		row.ms.text = "%.2f ms" % r.ms if r.ms < 1.0 else "%.1f ms" % r.ms
		row.meter.set_value(r.ms / top if top > 0.0 else 0.0, _kind_color(r))
		row.select = r.select
		row.button.disabled = r.select == "" or not _select.is_valid()
		row.button.tooltip_text = "Select %s" % r.select if not row.button.disabled else ""


func _make_row() -> Dictionary:
	var button := Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(0, 34)
	button.visible = false
	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 12)
	button.add_child(line)
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(250, 0)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name_label)
	var kind := _dim_label("")
	kind.autowrap_mode = TextServer.AUTOWRAP_OFF
	kind.custom_minimum_size = Vector2(170, 0)
	kind.clip_text = true
	kind.add_theme_font_size_override("font_size", 14)
	line.add_child(kind)
	var meter := _Meter.new()
	meter.custom_minimum_size = Vector2(0, 12)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(meter)
	var ms := Label.new()
	ms.custom_minimum_size = Vector2(80, 0)
	ms.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(ms)
	for c in [name_label, kind, ms]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.size_flags_vertical = Control.SIZE_FILL
	_list.add_child(button)
	var row := {"button": button, "name": name_label, "kind": kind, "meter": meter, "ms": ms, "select": ""}
	button.pressed.connect(func():
		if row.select != "" and _select.is_valid():
			_select.call(row.select))
	return row


func _on_probe() -> void:
	if _cost.probing:
		_cost.cancel_probe()
	else:
		_cost.probe()
	_update_buttons()


func _on_probed() -> void:
	_update_buttons()


func _on_benchmark() -> void:
	if _bench.running:
		_bench.cancel()
		return
	if _stage.runner.effective_duration() <= 0.0:
		_bench_text.text = "Nothing to benchmark: open a piece or a video first."
		return
	_bench_progress.value = 0.0
	_bench_progress.visible = true
	_bench_text.text = "Playing it through…"
	_clear_moments()
	_bench.run(_stage, _cost)
	_update_buttons()


func _on_benchmark_done(report: Dictionary) -> void:
	_bench_progress.visible = false
	_update_buttons()
	_clear_moments()
	if report.samples.is_empty():
		_bench_text.text = "Nothing to benchmark: open a piece or a video first."
		return
	var over: bool = report.moments.any(func(m): return m.over)
	_bench_text.text = "%s%s: average %.1f ms, peak %.1f ms of %.1f ms. %s:" % [
			"Stopped early" if report.cancelled else "Played it through",
			"" if report.cancelled else " (%d steps)" % report.samples.size(),
			report.mean_ms, report.peak_ms, report.budget_ms,
			"Over budget" if over else "Always within budget; the heaviest moments"]
	for m in report.moments:
		var l := Label.new()
		l.text = GpuBenchmark.describe(m)
		l.add_theme_color_override("font_color", RED if m.over else DIM)
		_moments.add_child(l)


func _clear_moments() -> void:
	for c in _moments.get_children():
		c.queue_free()


func _update_buttons() -> void:
	if _probe == null:
		return
	_probe.text = "Stop measuring" if _cost != null and _cost.probing else "Measure the 3D view's parts"
	_benchmark.text = "■ Stop the benchmark" if _bench.running else "▶ Benchmark the piece"
	_probe.disabled = _bench.running
	_benchmark.disabled = _cost != null and _cost.probing


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", DIM)
	return l


static func _load_color(ms: float, budget: float) -> Color:
	if ms > budget:
		return RED
	return AMBER if ms > budget * 0.75 else GREEN


static func _kind_color(r: Dictionary) -> Color:
	var kind: String = r.kind
	if kind.contains("shader"):
		return PURPLE
	if kind.contains("effect") or kind.contains("surface"):
		return BLUE
	return GREY
