extends PanelContainer

## Root of the F2 floating panel's tab contents. Forwards binds to the
## individual tab scripts (Camera, Files, Network, Config, Presets,
## Controls) and owns the header's close (X) and Quit buttons.

signal close_requested
signal quit_requested

## Quit needs a second press within this many seconds, so a stray click in
## VR doesn't drop the viewer out of the app.
const QUIT_CONFIRM_SECONDS := 3.0
## Slider sizing for the panel: the default theme's thin track and small
## grabber are hard to hit with a mouse ray or a VR laser.
const SLIDER_TRACK_PX := 10
const SLIDER_GRABBER_PX := 30
## CheckButtons' on / off switch.
const SWITCH_W_PX := 40
const SWITCH_H_PX := 22
const ACCENT := Color(0.35, 0.55, 0.9)

@onready var camera_tab: Node = %CameraTab
@onready var files_tab: Node = %FilesTab
@onready var network_tab: Node = %NetworkTab
@onready var config_tab: Node = %ConfigTab
@onready var presets_tab: Node = %PresetsTab
@onready var controls_tab: Node = %ControlsTab
@onready var close_button: Button = %CloseButton
@onready var quit_button: Button = %QuitButton

const PERFORMANCE_TAB := preload("res://player/ui/performance_tab.gd")

## Built in code (_ready), after the scene's tabs.
var performance_tab: Node
var _quit_armed: bool = false


func _ready() -> void:
	theme = _panel_theme()
	performance_tab = add_tab($Tabs, "Performance", PERFORMANCE_TAB)
	close_button.pressed.connect(close_requested.emit)
	quit_button.pressed.connect(_on_quit_pressed)


## The VR laser (XRToolsViewport2DIn3DBody) reports every press twice: as a
## screen touch and as a mouse click. The touch opens an OptionButton's
## popup, then the mouse press lands outside it and closes it again, so
## dropdowns never stay open. The mouse events carry everything the panel
## needs; drop the touches.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()


## Theme for everything under the panel: big HSliders (the Camera tab's
## rows and the effect params built in code alike).
static func _panel_theme() -> Theme:
	var t := Theme.new()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.22, 0.28)
	track.set_corner_radius_all(int(SLIDER_TRACK_PX / 2.0))
	track.content_margin_top = SLIDER_TRACK_PX / 2.0
	track.content_margin_bottom = SLIDER_TRACK_PX / 2.0
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = ACCENT
	var filled_hover := track.duplicate() as StyleBoxFlat
	filled_hover.bg_color = ACCENT.lightened(0.2)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled_hover)
	t.set_icon("grabber", "HSlider", _dot(Color(0.88, 0.92, 1.0)))
	t.set_icon("grabber_highlight", "HSlider", _dot(Color.WHITE))
	t.set_icon("grabber_disabled", "HSlider", _dot(Color(0.45, 0.45, 0.5)))
	for on in [true, false]:
		var state := "checked" if on else "unchecked"
		t.set_icon(state, "CheckButton", _switch(on, false))
		t.set_icon(state + "_mirrored", "CheckButton", _switch(on, false))
		t.set_icon(state + "_disabled", "CheckButton", _switch(on, true))
		t.set_icon(state + "_disabled_mirrored", "CheckButton", _switch(on, true))
	return t


## A CheckButton's switch: a pill with its knob on the track's middle line,
## at the right (lit) when on, as Studio's inspector draws its own. The
## default theme's is small, and its off track all but vanishes on the
## panel.
static func _switch(on: bool, disabled: bool) -> Texture2D:
	var track := ACCENT if on else Color(0.3, 0.33, 0.4)
	var knob := Color.WHITE if on else Color(0.85, 0.87, 0.9)
	var fade := 0.45 if disabled else 1.0
	var r := SWITCH_H_PX / 2.0
	var knob_at := Vector2(SWITCH_W_PX - r if on else r, r)
	var img := Image.create_empty(SWITCH_W_PX, SWITCH_H_PX, false, Image.FORMAT_RGBA8)
	for y in SWITCH_H_PX:
		for x in SWITCH_W_PX:
			var p := Vector2(x + 0.5, y + 0.5)
			# Coverage from the distance to each edge, for smooth edges.
			var inside := clampf(r + 0.5 - p.distance_to(Vector2(clampf(p.x, r, SWITCH_W_PX - r), r)), 0.0, 1.0)
			var on_knob := clampf(r * 0.72 + 0.5 - p.distance_to(knob_at), 0.0, 1.0)
			var c := track.lerp(knob, on_knob)
			img.set_pixel(x, y, Color(c, inside * fade))
	return ImageTexture.create_from_image(img)


## Round grabber icon: a filled circle with a soft edge.
static func _dot(color: Color) -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	gradient.set_offset(0, 0.85)
	gradient.set_offset(1, 1.0)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = SLIDER_GRABBER_PX
	tex.height = SLIDER_GRABBER_PX
	return tex


func _on_quit_pressed() -> void:
	if _quit_armed:
		quit_requested.emit()
		return
	_quit_armed = true
	quit_button.text = "Really quit?"
	await get_tree().create_timer(QUIT_CONFIRM_SECONDS).timeout
	_quit_armed = false
	quit_button.text = "Quit"


func bind_camera(settings: ScreenSettings, presets: PresetStore, layers: LayerStack = null) -> void:
	if camera_tab != null and camera_tab.has_method("bind"):
		camera_tab.bind(settings, presets, layers)
	if presets_tab != null and presets_tab.has_method("bind"):
		presets_tab.bind(settings, presets, layers)


func bind_files(runner: ScriptRunner, open_file: Callable, thumbs: OsThumbnails = null) -> void:
	if files_tab != null and files_tab.has_method("bind"):
		files_tab.bind(runner, open_file, thumbs)


func bind_network(client: DlnaClient, open_url: Callable) -> void:
	if network_tab != null and network_tab.has_method("bind"):
		network_tab.bind(client, open_url)


func bind_config(settings: PlayerSettings) -> void:
	if config_tab != null and config_tab.has_method("bind"):
		config_tab.bind(settings)
	# The Files and Network browsers share the list/tiles preference.
	for tab in [files_tab, network_tab]:
		if tab != null and tab.has_method("bind_view"):
			tab.bind_view(settings)


func bind_controls(router: InputRouter) -> void:
	if controls_tab != null and controls_tab.has_method("bind"):
		controls_tab.bind(router)


func bind_performance(stage: Stage) -> void:
	if performance_tab != null:
		performance_tab.bind(stage)


## A tab on `tabs`: `script` on a VBoxContainer in a scroll, with the
## scene's tab margins (as Studio's menu builds its tabs).
static func add_tab(tabs: TabContainer, title: String, script: Script) -> Node:
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
