class_name StudioWristTile
extends WristTile

## A tile of Studio's wrist palette: the player's WristTile (its dark style,
## lit border and fill) with Studio's own drawn icons (`symbol`, one of the
## ids below) and a caption big enough to read on the wrist. Icons are
## drawn, like the player's, so they stay sharp in the wrist's viewport.

const CAPTION := 27

## prev_key, next_key, play, pause, record, stop, auto_key, snap, loop,
## undo, redo, shelf, inspector, timeline, key_it, seat, goto, back,
## loop_in, loop_out, key_viewer, cut, arm_ride, miniature, delete, menu,
## outliner. Anything else draws no icon.
var symbol: StringName = &"":
	set(value):
		if symbol != value:
			symbol = value
			queue_redraw()


func _init(p_icon: StringName = &"", p_caption: String = "") -> void:
	super(WristTile.Glyph.NONE, p_caption)
	symbol = p_icon
	custom_minimum_size = Vector2(0, 150)


func _draw() -> void:
	var u := minf(size.x, size.y) * 0.13
	var c := Vector2(size.x * 0.5, size.y * 0.38)
	var color := TEXT if lit or not disabled else MUTED
	draw_icon(self, symbol, c, u, color, lit_color if lit else ACCENT)
	draw_string(get_theme_font("font"), Vector2(0, size.y * 0.83), caption, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, CAPTION, TEXT if lit else MUTED)


## Draw `id` centred on `c`, about 2·u across. `accent` colours the part
## that says what kind of thing it is (the key diamonds, the record dot).
static func draw_icon(ci: CanvasItem, id: StringName, c: Vector2, u: float, color: Color, accent: Color) -> void:
	var w := 0.2 * u  # line width
	match id:
		&"play":
			WristTile.draw_glyph(ci, WristTile.Glyph.PLAY, c, u, color, accent)
		&"pause":
			WristTile.draw_glyph(ci, WristTile.Glyph.PAUSE, c, u, color, accent)
		&"menu":
			WristTile.draw_glyph(ci, WristTile.Glyph.MENU, c, u, color, accent)
		&"prev_key", &"next_key":
			# ◆◀ and ▶◆: the diamond on the side the key is on.
			var s := -1.0 if id == &"prev_key" else 1.0
			_diamond(ci, c + Vector2(0.6 * s, 0) * u, 0.55 * u, ACCENT)
			_fill(ci, [c + Vector2(-1.15 * s, -0.75) * u, c + Vector2(-0.05 * s, 0) * u,
					c + Vector2(-1.15 * s, 0.75) * u], color)
		&"record":
			ci.draw_circle(c, 0.8 * u, RECORD, true, -1.0, true)
		&"stop":
			ci.draw_rect(Rect2(c - Vector2(0.7, 0.7) * u, Vector2(1.4, 1.4) * u), RECORD)
		&"auto_key":
			_diamond(ci, c, 0.95 * u, RECORD)
		&"key_it":
			_diamond(ci, c, 0.95 * u, ACCENT)
			ci.draw_circle(c, 0.25 * u, TILE, true, -1.0, true)
		&"snap":
			for x in [-0.75, 0.0, 0.75]:
				for y in [-0.75, 0.0, 0.75]:
					ci.draw_circle(c + Vector2(x, y) * u, 0.17 * u, color, true, -1.0, true)
		&"loop":
			ci.draw_arc(c, 0.85 * u, deg_to_rad(-60.0), deg_to_rad(240.0), 28, color, w, true)
			var tip := c + Vector2.from_angle(deg_to_rad(-60.0)) * 0.85 * u
			_fill(ci, [tip + Vector2(-0.5, -0.25) * u, tip + Vector2(0.3, -0.35) * u, tip + Vector2(0.05, 0.4) * u], color)
		&"undo", &"redo":
			var s := -1.0 if id == &"undo" else 1.0
			ci.draw_arc(c + Vector2(0, 0.25) * u, 0.7 * u, PI + 0.2, TAU - 0.2, 20, color, w, true)
			var end := c + Vector2(0.7 * s, 0.25) * u + Vector2(-0.05 * s, -0.1) * u
			_fill(ci, [end + Vector2(-0.45, 0) * u, end + Vector2(0.45, 0) * u, end + Vector2(0, 0.55) * u], color)
		&"shelf":
			for x in [-0.85, 0.1]:
				for y in [-0.85, 0.1]:
					ci.draw_rect(Rect2(c + Vector2(x, y) * u, Vector2(0.75, 0.75) * u), color)
		&"inspector":
			for i in 3:
				var y := (-0.7 + 0.7 * i) * u
				ci.draw_line(c + Vector2(-1.0 * u, y), c + Vector2(1.0 * u, y), Color(color, 0.5), w * 0.8, true)
				ci.draw_circle(c + Vector2([0.4, -0.5, 0.1][i] * u, y), 0.22 * u, color, true, -1.0, true)
		&"timeline":
			for i in 5:
				var h: float = [1.2, 1.8, 0.9, 1.5, 1.1][i] * u
				ci.draw_rect(Rect2(c + Vector2((-1.0 + 0.45 * i) * u, -h / 2.0), Vector2(0.25 * u, h)), color)
		&"outliner":
			ci.draw_rect(Rect2(c + Vector2(-1.0, -0.9) * u, Vector2(0.5, 0.4) * u), color)
			ci.draw_rect(Rect2(c + Vector2(-0.3, -0.2) * u, Vector2(1.3, 0.35) * u), color)
			ci.draw_rect(Rect2(c + Vector2(-0.3, 0.55) * u, Vector2(1.3, 0.35) * u), color)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.75, -0.5) * u, c + Vector2(-0.75, 0.72) * u,
					c + Vector2(-0.3, 0.72) * u]), color, w * 0.6, true)
			ci.draw_line(c + Vector2(-0.75, -0.02) * u, c + Vector2(-0.3, -0.02) * u, color, w * 0.6, true)
		&"seat":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.9, 1.0) * u, c + Vector2(-0.9, -0.1) * u,
					c + Vector2(0, -0.95) * u, c + Vector2(0.9, -0.1) * u, c + Vector2(0.9, 1.0) * u,
					c + Vector2(-0.9, 1.0) * u]), color, w, true)
		&"goto":
			ci.draw_arc(c, 0.9 * u, 0, TAU, 32, color, w, true)
			ci.draw_circle(c, 0.3 * u, ACCENT, true, -1.0, true)
		&"back":
			ci.draw_polyline(PackedVector2Array([c + Vector2(1.0, -0.8) * u, c + Vector2(1.0, 0.3) * u,
					c + Vector2(-0.6, 0.3) * u]), color, w, true)
			_fill(ci, [c + Vector2(-1.1, 0.3) * u, c + Vector2(-0.45, -0.25) * u, c + Vector2(-0.45, 0.85) * u], color)
		&"loop_in", &"loop_out":
			var s := 1.0 if id == &"loop_in" else -1.0
			ci.draw_polyline(PackedVector2Array([c + Vector2(0.45 * s, -1.0) * u, c + Vector2(-0.35 * s, -1.0) * u,
					c + Vector2(-0.35 * s, 1.0) * u, c + Vector2(0.45 * s, 1.0) * u]), color, w * 1.2, true)
		&"key_viewer":
			ci.draw_rect(Rect2(c + Vector2(-1.05, -0.5) * u, Vector2(1.3, 1.0) * u), color)
			_fill(ci, [c + Vector2(0.25, 0) * u, c + Vector2(1.05, -0.5) * u, c + Vector2(1.05, 0.5) * u], color)
			_diamond(ci, c + Vector2(-0.4, 0) * u, 0.3 * u, ACCENT)
		&"cut":
			for s in [-1.0, 1.0]:
				ci.draw_arc(c + Vector2(-0.6, 0.55 * s) * u, 0.32 * u, 0, TAU, 20, color, w, true)
				ci.draw_line(c + Vector2(-0.3, 0.4 * s) * u, c + Vector2(1.0, -0.55 * s) * u, color, w, true)
		&"arm_ride":
			ci.draw_circle(c + Vector2(-0.6, 0) * u, 0.5 * u, RECORD, true, -1.0, true)
			var pts := PackedVector2Array()
			for i in 9:
				var x := 0.05 + 0.1 * i
				pts.append(c + Vector2(x, 0.18 * sin(i * 1.4)) * u)
			ci.draw_polyline(pts, RECORD, w * 0.8, true)
			_fill(ci, [c + Vector2(0.85, -0.35) * u, c + Vector2(1.25, 0) * u, c + Vector2(0.85, 0.35) * u], RECORD)
		&"miniature":
			_outline(ci, Rect2(c + Vector2(-1.0, -0.9) * u, Vector2(2.0, 1.8) * u), color, w)
			ci.draw_rect(Rect2(c + Vector2(-0.1, 0.0) * u, Vector2(0.8, 0.6) * u), color)
		&"delete":
			ci.draw_line(c + Vector2(-1.0, -0.7) * u, c + Vector2(1.0, -0.7) * u, color, w, true)
			ci.draw_rect(Rect2(c + Vector2(-0.3, -1.0) * u, Vector2(0.6, 0.3) * u), color)
			_fill(ci, [c + Vector2(-0.75, -0.5) * u, c + Vector2(0.75, -0.5) * u, c + Vector2(0.6, 1.0) * u,
					c + Vector2(-0.6, 1.0) * u], color)
		&"save":
			_outline(ci, Rect2(c - Vector2(0.9, 0.9) * u, Vector2(1.8, 1.8) * u), color, w)
			ci.draw_rect(Rect2(c + Vector2(-0.45, -0.9) * u, Vector2(0.9, 0.6) * u), color)
			_outline(ci, Rect2(c + Vector2(-0.5, 0.2) * u, Vector2(1.0, 0.7) * u), color, w * 0.7)


static func _diamond(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	_fill(ci, [c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)], color)


static func _outline(ci: CanvasItem, r: Rect2, color: Color, width: float) -> void:
	ci.draw_polyline(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y), r.position]), color, width, true)
