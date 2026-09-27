extends PanelContainer

## 2D control tree hosted inside a SubViewport on the wrist quad: what's
## playing and the time over big previous / play / next / menu tiles, then
## scrub and volume. Styled after the Studio wrist palette mockup (see
## WristTile). Bound to a ScriptRunner. Same interaction model as the
## floating panel — pointer events arrive through the parent
## XRToolsViewport2DIn3D from the right controller's XRToolsFunctionPointer.

signal menu_requested  ## Menu button — main.gd toggles the floating panel.
signal previous_requested  ## main.gd steps the playlist.
signal next_requested

var prev_button: WristTile
var play_button: WristTile
var next_button: WristTile
var menu_button: WristTile
var title_label: Label
var time_label: Label
var duration_label: Label
var scrub_slider: HSlider
var volume_slider: HSlider
var _volume_icon: Control
var _volume_value: Label

var _runner: ScriptRunner
var _settings: PlayerSettings
var _scrubbing: bool = false
var _fps: FpsLabel


func bind(runner: ScriptRunner, settings: PlayerSettings = null) -> void:
	_settings = settings
	_fps.bind(settings)
	if _settings != null:
		_settings.changed.connect(_refresh_volume)
		_refresh_volume()
	_runner = runner
	if _runner == null:
		return
	_runner.script_loaded.connect(_on_script_loaded)
	_runner.script_reloaded.connect(_on_script_loaded)
	if _runner.timeline != null:
		_on_script_loaded(_runner.timeline)


func _ready() -> void:
	_build()
	play_button.pressed.connect(_on_play_pressed)
	menu_button.pressed.connect(menu_requested.emit)
	prev_button.pressed.connect(previous_requested.emit)
	next_button.pressed.connect(next_requested.emit)
	scrub_slider.drag_started.connect(func(): _scrubbing = true)
	scrub_slider.drag_ended.connect(_on_scrub_drag_ended)
	scrub_slider.value_changed.connect(_on_scrub_value_changed)
	volume_slider.value_changed.connect(_on_volume_changed)


func _process(_delta: float) -> void:
	if _runner == null or _runner.timeline == null:
		time_label.text = "--:--"
		duration_label.text = ""
		_show_playing(false)
		return
	var eff := _runner.effective_duration()
	if absf(scrub_slider.max_value - eff) > 0.01 and eff > 0.0:
		scrub_slider.max_value = maxf(eff, 0.1)
	if not _scrubbing:
		scrub_slider.set_value_no_signal(_runner.playhead)
	time_label.text = _format_time(_runner.playhead)
	duration_label.text = "of %s" % _format_time(eff)
	_show_playing(_runner.playing)


func _build() -> void:
	var card := StyleBoxFlat.new()
	card.bg_color = Color(WristTile.CARD, 0.96)
	card.border_color = WristTile.LINE
	card.set_border_width_all(1)
	card.set_corner_radius_all(18)
	card.set_content_margin_all(22)
	add_theme_stylebox_override("panel", card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 16)
	add_child(rows)

	# Header: what's open on the left, the clock on the right.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	rows.add_child(header)
	var now := VBoxContainer.new()
	now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now.alignment = BoxContainer.ALIGNMENT_CENTER
	now.add_theme_constant_override("separation", 2)
	header.add_child(now)
	now.add_child(_label("NOW PLAYING", 15, WristTile.MUTED))
	title_label = _label("Nothing open", 24, WristTile.TEXT)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.clip_text = true
	now.add_child(title_label)
	var clock := VBoxContainer.new()
	clock.add_theme_constant_override("separation", -4)
	header.add_child(clock)
	time_label = _label("--:--", 48, WristTile.TEXT)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.add_theme_font_override("font", _tabular_font())
	clock.add_child(time_label)
	var sub := HBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_END
	sub.add_theme_constant_override("separation", 10)
	clock.add_child(sub)
	_fps = FpsLabel.new()
	_fps.name = "WristFps"
	_fps.add_theme_font_size_override("font_size", 16)
	_fps.add_theme_color_override("font_color", WristTile.ACCENT)
	sub.add_child(_fps)
	duration_label = _label("", 16, WristTile.MUTED)
	duration_label.add_theme_font_override("font", _tabular_font())
	sub.add_child(duration_label)

	# Transport tiles.
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 12)
	tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(tiles)
	prev_button = WristTile.new(WristTile.Glyph.PREVIOUS, "Previous")
	play_button = WristTile.new(WristTile.Glyph.PLAY, "Play")
	next_button = WristTile.new(WristTile.Glyph.NEXT, "Next")
	menu_button = WristTile.new(WristTile.Glyph.MENU, "Menu")
	for t in [prev_button, play_button, next_button, menu_button]:
		tiles.add_child(t)

	var rule := ColorRect.new()
	rule.color = WristTile.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(rule)

	scrub_slider = HSlider.new()
	scrub_slider.custom_minimum_size = Vector2(0, 44)
	scrub_slider.min_value = 0.0
	scrub_slider.max_value = 100.0
	scrub_slider.step = 0.01
	_style_slider(scrub_slider)
	rows.add_child(scrub_slider)

	var vol := HBoxContainer.new()
	vol.add_theme_constant_override("separation", 14)
	rows.add_child(vol)
	_volume_icon = Control.new()
	_volume_icon.custom_minimum_size = Vector2(40, 40)
	_volume_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_volume_icon.draw.connect(func():
		WristTile.draw_glyph(_volume_icon, WristTile.Glyph.VOLUME, _volume_icon.size * 0.5,
				14.0, WristTile.MUTED, WristTile.RECORD, _volume_level()))
	vol.add_child(_volume_icon)
	volume_slider = HSlider.new()
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.custom_minimum_size = Vector2(0, 40)
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.value = 1.0
	_style_slider(volume_slider)
	vol.add_child(volume_slider)
	_volume_value = _label("100%", 18, WristTile.MUTED)
	_volume_value.custom_minimum_size = Vector2(64, 0)
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_volume_value.add_theme_font_override("font", _tabular_font())
	vol.add_child(_volume_value)


func _show_playing(playing: bool) -> void:
	play_button.glyph = WristTile.Glyph.PAUSE if playing else WristTile.Glyph.PLAY
	play_button.caption = "Pause" if playing else "Play"
	play_button.lit = playing


func _on_script_loaded(data: TimelineData) -> void:
	title_label.text = data.title()
	scrub_slider.min_value = 0.0
	scrub_slider.max_value = maxf(data.duration(), 0.1)
	scrub_slider.step = 0.01
	scrub_slider.set_value_no_signal(_runner.playhead)


func _on_play_pressed() -> void:
	if _runner == null:
		return
	if _runner.playing:
		_runner.pause()
	else:
		_runner.play()


func _on_scrub_value_changed(v: float) -> void:
	if _runner != null and _scrubbing:
		_runner.seek(v)


func _on_scrub_drag_ended(value_changed: bool) -> void:
	if _runner != null and value_changed:
		_runner.seek(scrub_slider.value)
	_scrubbing = false


func _on_volume_changed(v: float) -> void:
	_show_volume()
	# Slider range is whatever the scene defines; settings store 0..1.
	if _settings != null:
		_settings.volume = inverse_lerp(volume_slider.min_value, volume_slider.max_value, v)


func _refresh_volume() -> void:
	volume_slider.set_value_no_signal(
		lerpf(volume_slider.min_value, volume_slider.max_value, _settings.volume))
	_show_volume()


func _show_volume() -> void:
	_volume_value.text = "%d%%" % roundi(_volume_level() * 100.0)
	_volume_icon.queue_redraw()


func _volume_level() -> float:
	return inverse_lerp(volume_slider.min_value, volume_slider.max_value, volume_slider.value)


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The default font with tabular digits, so the clock doesn't jitter.
static func _tabular_font() -> Font:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	return f


## A thin rounded track with an accent fill up to a round knob.
static func _style_slider(s: HSlider) -> void:
	s.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("0f1219")
	track.border_color = WristTile.LINE
	track.set_border_width_all(1)
	track.set_corner_radius_all(5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = WristTile.ACCENT
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", _knob(WristTile.TEXT))
	s.add_theme_icon_override("grabber_highlight", _knob(Color.WHITE))


static func _knob(color: Color) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.82, 1.0])
	g.colors = PackedColorArray([color, color, Color(color, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 30
	t.height = 30
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	return t


static func _format_time(t: float) -> String:
	var total := int(t)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, total / 60 % 60, total % 60]
	return "%02d:%02d" % [total / 60, total % 60]
