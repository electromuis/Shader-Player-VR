extends VBoxContainer

## The Studio tab of Studio's menu: Studio's own options (StudioSettings),
## a row each with ↺ back to its default, and Reload shaders. Built in code,
## like the player's Config tab.

## Every shader file was read again (Reload shaders): the inspector's
## fields may have changed.
signal shaders_reloaded

const LABEL_WIDTH := 190

var _settings: StudioSettings
var _refreshing := false
var _key_mode: OptionButton
var _key_tip: Label  # what the chosen key mode does
var _haptics: CheckButton
var _autosave: CheckButton
var _grid: CheckButton
var _paths: CheckButton
var _panels: Label  # which panels were moved or sized (↺ puts them back)
var _resets: Dictionary = {}  # field -> ↺ button


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_key_mode = OptionButton.new()
	for m in StudioTimelineRibbon.KEY_MODES:
		_key_mode.add_item("All (auto-key)" if m[0] == "all" else m[1])
	_key_mode.item_selected.connect(func(i: int):
		_apply(func(): _settings.key_mode = StudioSettings.KEY_MODES[i]))
	_row("Keys on change", _key_mode, "key_mode")
	_key_tip = Label.new()
	_key_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_key_tip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	add_child(_key_tip)
	_haptics = _check("Ticks in the controllers (grab, snap, key, drop)")
	_haptics.toggled.connect(func(on: bool): _apply(func(): _settings.haptics = on))
	_row("Haptics", _haptics, "haptics")
	_autosave = _check("Keep unsaved changes in <name>.spscript.autosave every minute")
	_autosave.toggled.connect(func(on: bool): _apply(func(): _settings.autosave = on))
	_row("Autosave", _autosave, "autosave")
	_grid = _check("1 m lines on the floor while editing")
	_grid.toggled.connect(func(on: bool): _apply(func(): _settings.floor_grid = on))
	_row("Floor grid", _grid, "floor_grid")
	_paths = _check("Faint paths for every animated object, not just the selection")
	_paths.toggled.connect(func(on: bool): _apply(func(): _settings.all_paths = on))
	_row("Motion paths", _paths, "all_paths")
	_panels = Label.new()
	_panels.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row("Panel places", _panels, "panels")
	var reload := Button.new()
	reload.text = "Reload shaders"
	reload.tooltip_text = "Read every shader and image file again, to see edits made while Studio runs"
	reload.pressed.connect(func():
		VisualizerShaders.reload_all(get_tree())
		shaders_reloaded.emit())
	var reload_row := HBoxContainer.new()
	var gap := Control.new()
	gap.custom_minimum_size.x = LABEL_WIDTH
	reload_row.add_child(gap)
	reload_row.add_child(reload)
	reload_row.add_theme_constant_override("separation", 12)
	add_child(reload_row)
	var note := Label.new()
	note.text = "↺ puts a setting back to its default. The timeline's Off · Animated · All and Shift+I change the key mode too."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	add_child(note)


func bind(settings: StudioSettings) -> void:
	_settings = settings
	_settings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _settings == null or _key_mode == null:
		return
	_refreshing = true
	var i := StudioSettings.KEY_MODES.find(_settings.key_mode)
	_key_mode.select(i)
	_key_tip.text = "%s." % StudioTimelineRibbon.KEY_MODES[i][2]
	_haptics.button_pressed = _settings.haptics
	_autosave.button_pressed = _settings.autosave
	_grid.button_pressed = _settings.floor_grid
	_paths.button_pressed = _settings.all_paths
	var moved: Array = _settings.panels.keys()
	_panels.text = "Moved or sized: %s" % ", ".join(moved) if not moved.is_empty() else "Where Studio puts them (drag a title bar or an edge to change it)"
	for field in _resets:
		(_resets[field] as Button).disabled = _settings.is_default(field)
	_refreshing = false


func _apply(change: Callable) -> void:
	if not _refreshing and _settings != null:
		change.call()


func _check(text: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	return c


func _row(label_text: String, control: Control, field: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	var reset := Button.new()
	reset.text = "↺"
	reset.flat = true
	reset.custom_minimum_size = Vector2(44, 36)
	reset.tooltip_text = "Back to the default"
	reset.pressed.connect(func(): _settings.reset(field))
	row.add_child(reset)
	_resets[field] = reset
	add_child(row)
