extends VBoxContainer

## Camera tab of the F2 floating panel. The targets are layers: layer 0 is
## the main screen (the shared ScreenSettings, which drive the ScreenMount
## wrapping `main_screen`), locked to the video source; layers 1.. are the
## LayerStack's LayerSettings. The Layers spin box sets how many of those
## there are (new ones are added at the end and selected). Each target's
## source picker: layer 0's shows Video, disabled, with its layout row
## (field of view, stereo, swap eyes) under it; a layer's lists None, Video
## (VisualizerShaders.VIDEO, which follows layer 0's layout) and the layer
## shaders, and "Lock to screen" shows; the shader's hinted uniforms get
## generated controls under the sliders. Every
## target has a surface (picker, placement and its controls; the params and
## sliders its placement ignores are hidden or greyed, see ScreenGeometry)
## and two effect lists below that: effects on the picture and vertex
## effects on the surface (+ ↑ / + ↓ add one at the top / bottom; per
## effect an on / off switch, a picker, ↑ / ↓ and −, and its own controls). The distance slider is inverted (right =
## nearer) and holds -distance.
##
## The preset dropdown loads named presets from PresetStore and Save
## overwrites the selected preset with the screen and all layers. Preset 1
## is the default; preset 0 is the locked "Script (defaults)" (see PresetStore). Renaming, deleting and the startup choice live
## in the Presets tab; both follow PresetStore.active_index.
##
## The view row (the source layout: field of view, stereo, swap eyes; and
## reset view) isn't part of presets: the source is per video, reset view is
## an action. Both are signalled up to main.gd.

## `part` "fov" / "stereo": "auto" or a VideoProjection.FOVS / STEREOS name;
## "swap": a bool.
signal source_selected(part: String, value: Variant)
signal reset_view_requested

const LABEL_WIDTH := 110
const VALUE_WIDTH := 90

@onready var preset_option: OptionButton = %PresetOption
@onready var target_option: OptionButton = %TargetOption
@onready var layer_count_spin: SpinBox = %LayerCountSpin
@onready var projection_label: Label = %ProjectionLabel
@onready var projection_option: OptionButton = %ProjectionOption
@onready var shader_option: OptionButton = %ShaderOption
@onready var reset_view_button: Button = %ResetViewButton
@onready var layer_options_row: HBoxContainer = %LayerOptionsRow
@onready var enabled_check: CheckBox = %EnabledCheck
@onready var lock_check: CheckBox = %LockCheck
@onready var save_button: Button = %SaveButton
@onready var new_button: Button = %NewButton
@onready var size_slider: HSlider = %SizeSlider
@onready var size_value: Label = %SizeValue
@onready var distance_slider: HSlider = %DistanceSlider
@onready var distance_value: Label = %DistanceValue
@onready var height_slider: HSlider = %HeightSlider
@onready var height_value: Label = %HeightValue
@onready var tilt_slider: HSlider = %TiltSlider
@onready var tilt_value: Label = %TiltValue
@onready var opacity_slider: HSlider = %OpacitySlider
@onready var opacity_value: Label = %OpacityValue
@onready var resolution_slider: HSlider = %ResolutionSlider
@onready var resolution_value: Label = %ResolutionValue
@onready var params_box: VBoxContainer = %ParamsBox
@onready var effects_box: VBoxContainer = %EffectsBox
@onready var add_effect_button: Button = %AddEffectButton
@onready var add_effect_top_button: Button = %AddEffectTopButton
@onready var surface_box: VBoxContainer = %SurfaceBox
@onready var vertex_effects_box: VBoxContainer = %VertexEffectsBox
@onready var add_vertex_effect_button: Button = %AddVertexEffectButton
@onready var add_vertex_effect_top_button: Button = %AddVertexEffectTopButton

var _settings: ScreenSettings
var _layers: LayerStack
var _presets: PresetStore
var _target: int = 0  # 0 = the screen, n = layer n (1-based)
var _shader_keys: Array[String] = []  # parallel to shader_option items
var _effect_options: Array[Dictionary] = []  # [{key, label}] for effect pickers
var _vertex_options: Array[Dictionary] = []  # [{key, label}] for vertex effect pickers
var _layout_row: HBoxContainer  # under the source row: the video layout pickers, for layer 0
var _stereo_option: OptionButton  # next to projection_option (the field of view)
var _swap_check: CheckBox
var _watched: Array[Callable] = []  # per watched layer, its bound structure_changed handler
var _refreshing: bool = false
## Effects whose params are expanded, by identity (move_effect keeps the
## dictionary; picking a shader replaces it, see _open_next).
var _open_effects: Array[Dictionary] = []
var _open_next: Array = []  # [list, index] to expand on the next rebuild


func _ready() -> void:
	size_slider.value_changed.connect(_on_edit.bind("size"))
	distance_slider.value_changed.connect(func(v: float): _on_edit(-v, "distance"))
	height_slider.value_changed.connect(_on_edit.bind("height"))
	tilt_slider.value_changed.connect(_on_edit.bind("tilt"))
	opacity_slider.value_changed.connect(_on_edit.bind("opacity"))
	resolution_slider.value_changed.connect(_on_edit.bind("resolution"))
	lock_check.toggled.connect(_on_layer_edit.bind("lock_to_screen"))
	enabled_check.toggled.connect(func(v: bool):
		_on_layer_edit(v, "enabled")
		_refresh_target_list())
	layer_count_spin.value_changed.connect(_on_layer_count_changed)
	add_effect_top_button.pressed.connect(_add_effect.bind(ScreenSettings.EFFECTS, true))
	add_effect_button.pressed.connect(_add_effect.bind(ScreenSettings.EFFECTS, false))
	add_vertex_effect_top_button.pressed.connect(_add_effect.bind(ScreenSettings.VERTEX_EFFECTS, true))
	add_vertex_effect_button.pressed.connect(_add_effect.bind(ScreenSettings.VERTEX_EFFECTS, false))
	save_button.pressed.connect(_on_save_pressed)
	new_button.pressed.connect(_on_new_pressed)
	preset_option.item_selected.connect(_on_preset_selected)
	_build_source_pickers()
	reset_view_button.pressed.connect(func(): reset_view_requested.emit())
	var reload := Button.new()
	reload.text = "Reload shaders"
	reload.tooltip_text = "Load every shader file again, to see edits made while running"
	reload.pressed.connect(_on_reload_shaders)
	reset_view_button.add_sibling(reload)
	target_option.item_selected.connect(_set_target)
	shader_option.item_selected.connect(_on_shader_selected)
	_refresh_target_list()
	_update_value_labels()


## The field of view picker is projection_option, moved to its own row
## under the source picker; stereo and swap eyes sit next to it. Each
## picker's first entry is Auto.
func _build_source_pickers() -> void:
	shader_option.visible = true
	var view_row := projection_option.get_parent()
	_layout_row = HBoxContainer.new()
	_layout_row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.custom_minimum_size.x = LABEL_WIDTH
	label.text = "Layout"
	_layout_row.add_child(label)
	view_row.add_sibling(_layout_row)
	view_row.remove_child(projection_option)
	_layout_row.add_child(projection_option)
	projection_option.tooltip_text = "Field of view the video file was made for"
	projection_option.add_item("Auto")
	for fov in VideoProjection.FOVS:
		projection_option.add_item(VideoProjection.FOV_LABELS[fov])
	projection_option.item_selected.connect(func(idx: int):
		source_selected.emit("fov", "auto" if idx == 0 else VideoProjection.FOVS[idx - 1]))
	_stereo_option = OptionButton.new()
	_stereo_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stereo_option.tooltip_text = "How the file splits the picture between the eyes"
	_stereo_option.add_item("Auto")
	for stereo in VideoProjection.STEREOS:
		_stereo_option.add_item(VideoProjection.STEREO_LABELS[stereo])
	_stereo_option.item_selected.connect(func(idx: int):
		source_selected.emit("stereo", "auto" if idx == 0 else VideoProjection.STEREOS[idx - 1]))
	projection_option.add_sibling(_stereo_option)
	_swap_check = CheckBox.new()
	_swap_check.text = "Swap eyes"
	_swap_check.tooltip_text = "Right eye first (_RL files)"
	_swap_check.toggled.connect(func(on: bool): source_selected.emit("swap", on))
	_stereo_option.add_sibling(_swap_check)


## Reflect the current source layout: `override` is main.gd's choices
## ({fov, stereo: "auto" or a name, swap: null or a bool}); the Auto entries
## name what was detected (`detected` key, `detected_swap`) so the user can
## see the guess. `swap` is the effective swap.
func set_source_state(override: Dictionary, detected: String, detected_swap: bool, swap: bool) -> void:
	var fov := String(override.get("fov", "auto"))
	var stereo := String(override.get("stereo", "auto"))
	projection_option.set_item_text(0, "Auto (%s)" % VideoProjection.FOV_LABELS[VideoProjection.fov_of(detected)])
	projection_option.select(0 if fov == "auto" else VideoProjection.FOVS.find(fov) + 1)
	_stereo_option.set_item_text(0, "Auto (%s)" % VideoProjection.STEREO_LABELS[VideoProjection.stereo_name(detected)])
	_stereo_option.select(0 if stereo == "auto" else VideoProjection.STEREOS.find(stereo) + 1)
	_swap_check.set_pressed_no_signal(swap)
	_swap_check.tooltip_text = "Right eye first (_RL files)%s" % (" — detected" if detected_swap else "")


func bind(settings: ScreenSettings, presets: PresetStore, layers: LayerStack = null) -> void:
	_settings = settings
	_layers = layers
	_presets = presets
	if _settings != null:
		_settings.changed.connect(_refresh_sliders_from_settings)
		_settings.structure_changed.connect(_on_structure_changed.bind(_settings))
	if _layers != null:
		_layers.layers_changed.connect(_on_layers_changed)
	layer_count_spin.editable = _layers != null
	if _presets != null:
		_presets.presets_changed.connect(_refresh_preset_list)
		_presets.active_changed.connect(func(_i: int): _refresh_preset_list())
	_refresh_preset_list()
	_on_layers_changed()


func _refresh_preset_list() -> void:
	if _presets == null or preset_option == null:
		return
	var selected_id := _presets.active_index
	preset_option.clear()
	var items := _presets.list_presets()
	if items.is_empty():
		# list_presets() should have created preset 1 on first call, but be
		# defensive so the dropdown is never empty.
		preset_option.add_item("1 — Default", 1)
	else:
		for item in items:
			preset_option.add_item("%d — %s" % [item.index, item.name], int(item.index))
	if selected_id >= 0:
		var idx := _find_item_by_id(selected_id)
		if idx >= 0:
			preset_option.select(idx)
	var locked := PresetStore.is_locked(_current_preset_id())
	save_button.disabled = locked
	save_button.tooltip_text = "Built-in preset: use New to keep these values" if locked else ""


## The settings the sliders edit: the main screen's or a shader layer's.
func _edited() -> ScreenSettings:
	var layer := _layer()
	return layer if layer != null else _settings


## The shader layer being edited, or null when it's the screen.
func _layer() -> LayerSettings:
	if _layers == null or _target < 1 or _target > _layers.count():
		return null
	return _layers.layers[_target - 1]


## The stack changed (count or a preset): follow the new layers' signals,
## relist them and keep the target in range.
func _on_layers_changed() -> void:
	for link in _watched:
		var l: LayerSettings = link.get_bound_arguments()[0]
		l.changed.disconnect(_refresh_sliders_from_settings)
		l.structure_changed.disconnect(link)
	_watched.clear()
	if _layers != null:
		for l in _layers.layers:
			var link := _on_structure_changed.bind(l)
			l.changed.connect(_refresh_sliders_from_settings)
			l.structure_changed.connect(link)
			_watched.append(link)
		layer_count_spin.set_value_no_signal(_layers.count())
	_refresh_target_list()
	_set_target(mini(_target, _layers.count() if _layers != null else 0))


func _refresh_target_list() -> void:
	target_option.clear()
	target_option.add_item("Layer 0 · Screen")
	var n := _layers.count() if _layers != null else 0
	for i in n:
		var l := _layers.layers[i]
		target_option.add_item("Layer %d · %s%s" % [i + 1, VisualizerShaders.source_label(l.shader),
				"" if l.enabled else " (off)"])
	if target_option.item_count > _target:
		target_option.select(_target)


func _on_layer_count_changed(v: float) -> void:
	if _layers == null:
		return
	var grew := int(v) > _layers.count()
	_layers.set_count(int(v))
	if grew:
		_set_target(_layers.count())  # jump to the new layer


func _set_target(target: int) -> void:
	_target = target
	target_option.select(target)
	var is_layer := _layer() != null
	_layout_row.visible = not is_layer
	layer_options_row.visible = is_layer
	# Rescan each time, so files dropped into the shaders folder show up.
	_refresh_shader_list()
	_rebuild_dynamic()
	_refresh_sliders_from_settings()


## Layer 0 (the screen) only has the video; a layer can have nothing, the
## video or a shader.
func _refresh_shader_list() -> void:
	shader_option.clear()
	_shader_keys.clear()
	var layer := _layer()
	shader_option.disabled = layer == null
	shader_option.tooltip_text = "Layer 0 is the video screen: its source can't change" if layer == null else ""
	if layer != null:
		shader_option.add_item("None")
		_shader_keys.append("")
	shader_option.add_item("Video")
	_shader_keys.append(VisualizerShaders.VIDEO)
	if layer == null:
		shader_option.select(0)
		return
	for opt in VisualizerShaders.list_options():
		shader_option.add_item(opt.label)
		_shader_keys.append(opt.key)
	_select_current_shader()


func _select_current_shader() -> void:
	var layer := _layer()
	if layer == null or shader_option.item_count == 0:
		return
	var idx := _shader_keys.find(layer.shader)
	if idx < 0:
		# A preset's shader that's no longer on disk: list it so the
		# dropdown still says what's selected.
		shader_option.add_item("%s (missing)" % layer.shader.get_file().get_basename())
		_shader_keys.append(layer.shader)
		idx = _shader_keys.size() - 1
	shader_option.select(idx)


func _on_shader_selected(idx: int) -> void:
	var layer := _layer()
	if layer != null and idx >= 0 and idx < _shader_keys.size():
		layer.shader = _shader_keys[idx]


func _on_reload_shaders() -> void:
	VisualizerShaders.reload_all(get_tree())
	# New or retitled files, and changed sliders.
	_refresh_shader_list()
	_rebuild_dynamic()


func _on_structure_changed(source: ScreenSettings) -> void:
	# A layer's source may have changed: the list names it.
	_refresh_target_list()
	if source == _edited():
		_select_current_shader()
		_rebuild_dynamic()


## Regenerate the layer shader's controls, the surface's and the effect
## lists for the edited target. Only on structural changes: rebuilding
## mid-drag would drop the slider being dragged.
func _rebuild_dynamic() -> void:
	for box in [params_box, effects_box, surface_box, vertex_effects_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var edited := _edited()
	if edited == null:
		return
	var layer := _layer()
	if layer != null and layer.shader != "":
		_add_param_controls(params_box, VisualizerShaders.hints_for(layer.shader).params,
				layer.params, func(param: String, v): layer.set_param(param, v))
	_add_surface_rows(edited)
	_effect_options = VisualizerShaders.list_options(VisualizerShaders.search_dirs(), true)
	for i in edited.effects.size():
		_add_effect_rows(edited, i, ScreenSettings.EFFECTS)
	_vertex_options = ScreenGeometry.list_options(ScreenGeometry.VERTEX_DIR)
	for i in edited.vertex_effects.size():
		_add_effect_rows(edited, i, ScreenSettings.VERTEX_EFFECTS)
	_open_next = []


## The surface picker and placement, its hint, and its params (minus the
## ones its placement ignores).
func _add_surface_rows(edited: ScreenSettings) -> void:
	var surface: Dictionary = edited.surface
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.custom_minimum_size.x = LABEL_WIDTH
	label.text = "Surface"
	row.add_child(label)
	var options := ScreenGeometry.list_options(ScreenGeometry.SURFACES_DIR)
	var keys: Array[String] = []
	for opt in options:
		keys.append(opt.key)
	row.add_child(_picker(options, keys, String(surface.shader), false,
			func(k: int): edited.set_surface_shader(keys[k])))
	var placements := ScreenGeometry.placements_for(surface.shader)
	var place := OptionButton.new()
	place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for name in placements:
		place.add_item(ScreenGeometry.PLACEMENT_LABELS[name])
	place.select(maxi(placements.find(surface.placement), 0))
	place.disabled = placements.size() < 2
	place.item_selected.connect(func(k: int): edited.set_surface_placement(placements[k]))
	row.add_child(place)
	surface_box.add_child(row)
	var hints := ScreenGeometry.hints_for(surface.shader)
	if hints.hint != "":
		var hint := Label.new()
		hint.text = hints.hint
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.modulate.a = 0.6
		surface_box.add_child(hint)
	var unused: Array = hints.unused.get(surface.placement, [])
	var params: Dictionary = surface.params
	for spec in hints.params:
		if spec.name in unused:
			continue
		surface_box.add_child(_param_control(spec, params.get(spec.name, spec.default),
				func(v): edited.set_surface_param(spec.name, v)))


## An option button over `options` ([{key, label}]; `keys` holds their keys,
## after a leading "" when `none` adds a "None" entry), with `current`
## selected. A key that's not listed (a file since removed) is added as
## missing.
func _picker(options: Array[Dictionary], keys: Array[String], current: String, none: bool,
		on_pick: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	if none:
		picker.add_item("None")
	for opt in options:
		picker.add_item(opt.label)
	var idx := keys.find(current)
	if idx < 0:
		picker.add_item("%s (missing)" % current.get_file().get_basename())
		keys.append(current)
		idx = keys.size() - 1
	picker.select(idx)
	picker.item_selected.connect(on_pick)
	return picker


## One effect of `list` (ScreenSettings.EFFECTS or VERTEX_EFFECTS): its row
## (expand toggle, picker, ↑ / ↓, −) and its collapsible controls.
func _add_effect_rows(edited: ScreenSettings, i: int, list: String) -> void:
	var vertex := list == ScreenSettings.VERTEX_EFFECTS
	var effects := edited.effect_list(list)
	var box := vertex_effects_box if vertex else effects_box
	var options := _vertex_options if vertex else _effect_options
	var effect: Dictionary = effects[i]
	if _open_next == [list, i] and not _is_open(effect):
		_open_effects.append(effect)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var title := "%s %d" % ["Vertex" if vertex else "Effect", i + 1]
	var toggle := Button.new()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(toggle)
	var enabled := ScreenSettings.is_enabled(effect)
	var on := CheckBox.new()
	on.button_pressed = enabled
	on.tooltip_text = "On / off (off keeps its place and settings)"
	on.toggled.connect(func(v: bool): edited.set_effect_enabled(i, v, list))
	row.add_child(on)
	var keys: Array[String] = [""]
	for opt in options:
		keys.append(opt.key)
	row.add_child(_picker(options, keys, String(effect.shader), true,
			func(k: int):
				_open_next = [list, i]
				edited.set_effect_shader(i, keys[k], list)))
	for move in [[-1, "↑"], [1, "↓"]]:
		var button := Button.new()
		button.text = move[1]
		button.custom_minimum_size.x = 40
		var to: int = i + move[0]
		button.disabled = to < 0 or to >= effects.size()
		button.pressed.connect(func(): edited.move_effect(i, move[0], list))
		row.add_child(button)
	var remove := Button.new()
	remove.text = "−"
	remove.custom_minimum_size.x = 40
	remove.pressed.connect(func(): edited.remove_effect(i, list))
	row.add_child(remove)
	box.add_child(row)
	var specs: Array = []
	if String(effect.shader) != "":
		specs = ScreenGeometry.hints_for(effect.shader).params if vertex \
				else VisualizerShaders.hints_for(effect.shader).params
	if specs.is_empty():
		toggle.text = "    " + title
		toggle.disabled = true
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	if not enabled:
		body.modulate.a = 0.5
	_add_param_controls(body, specs, effect.params,
			func(param: String, v): edited.set_effect_param(i, param, v, list))
	box.add_child(body)
	var show_open := func(open: bool):
		body.visible = open
		toggle.text = ("▾ " if open else "▸ ") + title
	show_open.call(_is_open(effect))
	toggle.pressed.connect(func():
		var open := not _is_open(effect)
		if open:
			_open_effects.append(effect)
		else:
			_open_effects.assign(_open_effects.filter(func(e): return not is_same(e, effect)))
		show_open.call(open))


## A new effect in `list`, at its top or bottom, expanded.
func _add_effect(list: String, top: bool) -> void:
	var edited := _edited()
	if edited == null:
		return
	var at := 0 if top else edited.effect_list(list).size()
	_open_next = [list, at]
	edited.add_effect("", list, at)


## Whether `effect` (this very dictionary, not an equal one) is expanded.
func _is_open(effect: Dictionary) -> bool:
	return _open_effects.any(func(e: Dictionary): return is_same(e, effect))


## A _param_control per spec into `box`, valued from `values` (else the
## default), calling `on_change(name, value)`. Each new `group_uniforms`
## group starts with a labelled separator.
func _add_param_controls(box: Container, specs: Array, values: Dictionary, on_change: Callable) -> void:
	var group := ""
	for spec in specs:
		var g := String(spec.get("group", ""))
		if g != group:
			group = g
			box.add_child(_group_separator(g))
		box.add_child(_param_control(spec, values.get(spec.name, spec.default),
				func(v): on_change.call(spec.name, v)))


## A separator line headed by `group`'s name ("a.b" subgroups as "A · B");
## a bare line when leaving groups ("").
func _group_separator(group: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if group != "":
		var label := Label.new()
		label.text = " · ".join(Array(group.split(".")).map(func(s: String): return s.capitalize()))
		label.modulate.a = 0.6
		row.add_child(label)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	return row


## A row for one hinted uniform: a slider with its value, a checkbox, or a
## dropdown (a hint_enum), then a ↺ button back to its default (disabled while at it).
func _param_control(spec: Dictionary, value: Variant, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.custom_minimum_size.x = LABEL_WIDTH
	label.text = String(spec.name).capitalize()
	row.add_child(label)
	var reset := Button.new()
	reset.text = "↺"
	reset.flat = true
	reset.tooltip_text = "Reset to default"
	if spec.type == "bool":
		var check := CheckBox.new()
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.button_pressed = bool(value)
		reset.disabled = check.button_pressed == bool(spec.default)
		check.toggled.connect(func(v: bool):
			reset.disabled = v == bool(spec.default)
			on_change.call(v))
		reset.pressed.connect(func(): check.button_pressed = bool(spec.default))
		row.add_child(check)
		row.add_child(reset)
		return row
	if spec.has("options"):
		var pick := OptionButton.new()
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for o in spec.options:
			pick.add_item(o)
		pick.select(clampi(int(value), 0, spec.options.size() - 1))
		reset.disabled = pick.selected == int(spec.default)
		pick.item_selected.connect(func(i: int):
			reset.disabled = i == int(spec.default)
			on_change.call(i))
		reset.pressed.connect(func():
			pick.select(int(spec.default))
			pick.item_selected.emit(pick.selected))
		row.add_child(pick)
		row.add_child(reset)
		return row
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.scrollable = false
	slider.min_value = spec.min
	slider.max_value = spec.max
	slider.step = spec.step
	slider.value = float(value)
	var shown := Label.new()
	shown.custom_minimum_size.x = VALUE_WIDTH
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var is_int: bool = spec.type == "int"
	var show_value := func(v: float): shown.text = str(int(v)) if is_int else "%.2f" % v
	show_value.call(slider.value)
	var at_default := func(v: float) -> bool: return is_equal_approx(v, float(spec.default))
	reset.disabled = at_default.call(slider.value)
	slider.value_changed.connect(func(v: float):
		show_value.call(v)
		reset.disabled = at_default.call(v)
		on_change.call(int(v) if is_int else v))
	reset.pressed.connect(func(): slider.value = float(spec.default))
	row.add_child(slider)
	row.add_child(shown)
	row.add_child(reset)
	return row


func _refresh_sliders_from_settings() -> void:
	var edited := _edited()
	if edited == null:
		return
	_refreshing = true
	size_slider.set_value_no_signal(edited.size)
	distance_slider.set_value_no_signal(-edited.distance)
	height_slider.set_value_no_signal(edited.height)
	tilt_slider.set_value_no_signal(edited.tilt)
	opacity_slider.set_value_no_signal(edited.opacity)
	resolution_slider.set_value_no_signal(edited.resolution)
	# Locked, a layer sits on the screen: height and tilt are unused
	# (distance moves it in front of / behind the screen).
	var layer := _layer()
	var locked := layer != null and layer.lock_to_screen
	lock_check.set_pressed_no_signal(locked)
	enabled_check.set_pressed_no_signal(layer == null or layer.enabled)
	# The surface's placement may ignore size / distance / height too
	# (around the viewer, at infinity).
	var unused: Array = ScreenGeometry.hints_for(edited.surface.shader).unused.get(edited.surface.placement, [])
	var sliders := {"size": size_slider, "distance": distance_slider, "height": height_slider, "tilt": tilt_slider}
	for name in sliders:
		var off: bool = name in unused or (locked and name in ["height", "tilt"])
		sliders[name].editable = not off
		sliders[name].modulate.a = 0.4 if off else 1.0
	_refreshing = false
	_update_value_labels()


func _update_value_labels() -> void:
	size_value.text = "%.2fx" % size_slider.value
	distance_value.text = "%.2f m" % (0.0 - distance_slider.value)  # no "-0.00"
	height_value.text = "%+.2f m" % height_slider.value
	tilt_value.text = "%+d°" % int(tilt_slider.value)
	opacity_value.text = "%d%%" % roundi(opacity_slider.value * 100.0)
	resolution_value.text = "%d%%" % roundi(resolution_slider.value * 100.0)


## Set `property` on the edited settings.
func _on_edit(value: Variant, property: String) -> void:
	if not _refreshing and _edited() != null:
		_edited().set(property, value)
	_update_value_labels()


## Set `property` on the edited layer (layer-only controls).
func _on_layer_edit(value: Variant, property: String) -> void:
	if not _refreshing and _layer() != null:
		_layer().set(property, value)


func _on_preset_selected(_idx: int) -> void:
	var id := _current_preset_id()
	if id < 0 or _presets == null or _settings == null:
		return
	if _presets.apply(id, _settings, _layers):
		_refresh_sliders_from_settings()


func _on_save_pressed() -> void:
	if _presets == null or _settings == null:
		return
	var id := _current_preset_id()
	if id < 0 or PresetStore.is_locked(id):
		return
	var name := _current_preset_name()
	_presets.save_preset(id, name, _settings.to_dict(), _layers_data())
	_presets.set_active(id)


func _on_new_pressed() -> void:
	if _presets == null or _settings == null:
		return
	var id := _presets.next_free_index()
	_presets.save_preset(id, "Preset %d" % id, _settings.to_dict(), _layers_data())
	_presets.set_active(id)  # → active_changed → list reselects it


func _current_preset_id() -> int:
	if preset_option == null or preset_option.item_count == 0:
		return -1
	var sel := preset_option.get_selected()
	if sel < 0:
		return -1
	return preset_option.get_item_id(sel)


func _current_preset_name() -> String:
	if preset_option == null or preset_option.item_count == 0:
		return ""
	var sel := preset_option.get_selected()
	if sel < 0:
		return ""
	var text := preset_option.get_item_text(sel)
	# Strip the "N — " prefix we added in _refresh_preset_list.
	var em_dash := " — "
	var i := text.find(em_dash)
	return text.substr(i + em_dash.length()) if i >= 0 else text


func _find_item_by_id(id: int) -> int:
	for i in preset_option.item_count:
		if preset_option.get_item_id(i) == id:
			return i
	return -1


func _layers_data() -> Array:
	return _layers.to_array() if _layers != null else []
