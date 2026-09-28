class_name StudioMenu
extends PanelContainer

## Studio's menu (F2, or hold ≡ in the headset), shown on a FloatingPanel
## like the player's: the player's Config tab (the settings are shared with
## it, minus the rows that don't apply here), its Controls tab listing
## Studio's commands, and a Studio tab for Studio's own options.

signal close_requested

const PLAYER_CONTENT := preload("res://player/ui/floating_panel_content.gd")
const CONFIG_TAB := preload("res://player/ui/config_tab.gd")
const CONTROLS_TAB := preload("res://player/ui/controls_tab.gd")
const STUDIO_TAB := preload("res://studio/ui/studio_tab.gd")
## Player rows with nothing to do in Studio: it flies rather than walks,
## has one piece rather than a playlist, no play bar, no editor sync.
const HIDDEN_CONFIG_ROWS := ["Movement", "At video end", "Play bar", "Editor sync"]
## The Controls tab's sections for Studio's contexts.
const CONTROL_SECTIONS := [
	["studio", "Always (Play and Edit)"],
	["studio_edit", "While editing"],
	["menus", "Pointing at a menu"],
]
const ACCENT := Color(0.3, 0.79, 0.94)

var tabs: TabContainer
var config_tab: Node
var controls_tab: Node
var studio_tab: Node


func _ready() -> void:
	theme = PLAYER_CONTENT._panel_theme()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.11, 0.99)  # opaque: Studio's panels are behind it
	bg.set_border_width_all(2)
	bg.border_color = Color(0.35, 0.55, 0.9)
	bg.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", bg)
	var column := VBoxContainer.new()
	add_child(column)
	var head := HBoxContainer.new()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.add_child(head)
	column.add_child(margin)
	var title := Label.new()
	title.text = "Studio menu"
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var how := Label.new()
	how.text = "  F2 · hold ≡"
	how.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(how)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(44, 36)
	close.pressed.connect(close_requested.emit)
	head.add_child(close)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	config_tab = _tab("Config", CONFIG_TAB)
	config_tab.hide_rows(HIDDEN_CONFIG_ROWS)
	controls_tab = _tab("Controls", CONTROLS_TAB)
	controls_tab.sections = CONTROL_SECTIONS
	studio_tab = _tab("Studio", STUDIO_TAB)


## The VR laser reports every press twice (a touch and a click); keep the
## clicks, as the player's panel does.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()


func bind(player_settings: PlayerSettings, router: InputRouter, studio_settings: StudioSettings) -> void:
	config_tab.bind(player_settings)
	controls_tab.bind(router)
	studio_tab.bind(studio_settings)


## A tab: `script` on a VBoxContainer in a scroll, with the player's margins.
func _tab(title: String, script: Script) -> Node:
	var margin := MarginContainer.new()
	margin.name = title
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	tabs.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.set_script(script)
	scroll.add_child(box)
	return box
