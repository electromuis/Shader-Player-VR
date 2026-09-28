class_name WristTile
extends Button

## A big button for the wrist menus: a drawn icon over a short caption, in
## the dark tile style of the Studio mockups (docs/studio/wrist_palette.svg
## on the studio branch). `lit` gives it the tinted fill and coloured border
## used for a toggle or a state that's on. Icons are drawn, not fonts or
## textures, so they stay sharp at the wrist viewport's resolution.

const CARD := Color("161a23")
const TILE := Color("1d2230")
const TILE_LIT := Color("2a3a4d")
const LINE := Color("2c3344")
const TEXT := Color("e8ebf2")
const MUTED := Color("8c95a8")
const ACCENT := Color("4cc9f0")
const RECORD := Color("ff4d5e")

enum Glyph { NONE, PREVIOUS, PLAY, PAUSE, NEXT, MENU, VOLUME }

const CAPTION_SIZE := 20

var glyph: Glyph = Glyph.NONE:
	set(value):
		if glyph != value:
			glyph = value
			queue_redraw()
var caption: String = "":
	set(value):
		if caption != value:
			caption = value
			queue_redraw()
var lit: bool = false:
	set(value):
		if lit != value:
			lit = value
			_restyle()
## Border and fill tint while lit.
var lit_color: Color = ACCENT:
	set(value):
		lit_color = value
		_restyle()


func _init(p_glyph: Glyph = Glyph.NONE, p_caption: String = "") -> void:
	glyph = p_glyph
	caption = p_caption
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 140)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_restyle()


func _draw() -> void:
	var u := minf(size.x, size.y) * 0.13
	draw_glyph(self, glyph, Vector2(size.x * 0.5, size.y * 0.4), u, TEXT, ACCENT)
	var font := get_theme_font("font")
	var baseline := size.y * 0.8
	draw_string(font, Vector2(0, baseline), caption, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, CAPTION_SIZE, TEXT if lit else MUTED)


func _restyle() -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(state, _style(state))
	queue_redraw()


func _style(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(14)
	sb.bg_color = TILE_LIT if lit else TILE
	sb.border_color = lit_color if lit else LINE
	sb.set_border_width_all(2 if lit else 1)
	match state:
		"hover":
			sb.bg_color = sb.bg_color.lightened(0.08)
			if not lit:
				sb.border_color = Color(ACCENT, 0.55)
		"pressed", "hover_pressed":
			sb.bg_color = sb.bg_color.lerp(lit_color, 0.25)
			sb.border_color = lit_color
			sb.set_border_width_all(2)
		"disabled":
			sb.bg_color = sb.bg_color.darkened(0.3)
	return sb


## Draw `g` centred on `c`, about 2·u across, on any CanvasItem. The accent
## colour marks the icon's "direction" part (the bar of previous / next).
## `level` (0..1) sets how many waves the volume icon shows.
static func draw_glyph(ci: CanvasItem, g: Glyph, c: Vector2, u: float,
		color: Color, accent: Color, level: float = 1.0) -> void:
	match g:
		Glyph.PLAY:
			_fill(ci, [c + Vector2(-0.75, -1.0) * u, c + Vector2(1.05, 0) * u,
					c + Vector2(-0.75, 1.0) * u], color)
		Glyph.PAUSE:
			for x in [-0.85, 0.25]:
				ci.draw_rect(Rect2(c + Vector2(x, -1.0) * u, Vector2(0.6, 2.0) * u), color)
		Glyph.PREVIOUS, Glyph.NEXT:
			var s := -1.0 if g == Glyph.PREVIOUS else 1.0
			_fill(ci, [c + Vector2(-0.9 * s, -0.95) * u, c + Vector2(0.6 * s, 0) * u,
					c + Vector2(-0.9 * s, 0.95) * u], color)
			var bar_x := 0.75 if s > 0 else -1.1
			ci.draw_rect(Rect2(c + Vector2(bar_x, -0.95) * u, Vector2(0.35, 1.9) * u), accent)
		Glyph.MENU:
			for y in [-0.7, 0.0, 0.7]:
				ci.draw_line(c + Vector2(-1.0, y) * u, c + Vector2(1.0, y) * u,
						color, 0.26 * u, true)
		Glyph.VOLUME:
			ci.draw_rect(Rect2(c + Vector2(-1.1, -0.35) * u, Vector2(0.5, 0.7) * u), color)
			_fill(ci, [c + Vector2(-0.62, -0.35) * u, c + Vector2(0.0, -0.9) * u,
					c + Vector2(0.0, 0.9) * u, c + Vector2(-0.62, 0.35) * u], color)
			var waves := 0 if level <= 0.0 else (1 if level < 0.5 else 2)
			for i in waves:
				ci.draw_arc(c + Vector2(0.05, 0) * u, (0.5 + 0.45 * i) * u, -PI / 3.5,
						PI / 3.5, 12, color, 0.16 * u, true)
			if waves == 0:
				ci.draw_line(c + Vector2(0.35, -0.35) * u, c + Vector2(1.05, 0.35) * u,
						accent, 0.16 * u, true)
				ci.draw_line(c + Vector2(0.35, 0.35) * u, c + Vector2(1.05, -0.35) * u,
						accent, 0.16 * u, true)


## A filled polygon with an antialiased edge (polygons alone draw aliased).
static func _fill(ci: CanvasItem, points: Array, color: Color) -> void:
	var pts := PackedVector2Array(points)
	ci.draw_colored_polygon(pts, color)
	pts.append(pts[0])
	ci.draw_polyline(pts, color, 1.0, true)
