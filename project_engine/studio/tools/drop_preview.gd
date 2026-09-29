class_name StudioDropPreview
extends Node3D

## What a carried shelf card will do where it points. A card that adds an
## object shows that object's outline at its real size and place
## (StudioAssetDrop.placement), a ring on the floor under it, a dashed line
## down to the ring, and how far away it is (at the ring's front); one that goes onto an object
## (an effect, a look on its own kind) shows just the card's picture at the
## spot. Drawn over everything, so it's never lost behind the thing it's
## put on.

const CARD_WIDTH := 0.36
const ACCENT := Color(0.3, 0.79, 0.94)
## Dashes of the line down to the floor, in metres.
const DASH := 0.08

var _card: MeshInstance3D
var _card_mat: StandardMaterial3D
var _outline: MeshInstance3D
var _ring: MeshInstance3D
var _line: MeshInstance3D
var _label: Label3D


func _init() -> void:
	name = "CarriedCard"
	visible = false
	_card_mat = _material(Color.WHITE)
	_card_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_card = _mesh(QuadMesh.new(), _card_mat)
	_outline = _mesh(ImmediateMesh.new(), _material(ACCENT))
	_ring = _mesh(ImmediateMesh.new(), _material(ACCENT))
	_line = _mesh(ImmediateMesh.new(), _material(Color(ACCENT, 0.8)))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0016
	_label.font_size = 30
	_label.outline_size = 12
	_label.modulate = ACCENT
	_label.outline_modulate = Color(0.06, 0.08, 0.11, 0.9)
	_label.no_depth_test = true
	_label.render_priority = 11
	_label.outline_render_priority = 10
	add_child(_label)


## The carried card's picture (null: a plain accent card).
func set_picture(tex: Texture2D) -> void:
	_card_mat.albedo_texture = tex
	_card_mat.albedo_color = Color(1, 1, 1, 0.85) if tex != null else Color(ACCENT, 0.6)


## Show a card that goes onto something: its picture at `point`, facing
## `head`.
func show_card(point: Vector3, head: Vector3) -> void:
	(_card.mesh as QuadMesh).size = Vector2(CARD_WIDTH, CARD_WIDTH * 0.625)
	_card.global_transform = Transform3D(_facing(point, head), point)
	_card_mat.albedo_color.a = 0.85 if _card_mat.albedo_texture != null else 0.6
	for n in [_outline, _ring, _line, _label]:
		n.visible = false


## Show an object about to be added: `xf` its spawn transform (the
## format's {position, rotation_deg, scale}), `bounds` its box at scale 1,
## seen from `head`.
func show_object(xf: Dictionary, bounds: AABB, head: Vector3) -> void:
	var pos := Vector3(xf.position[0], xf.position[1], xf.position[2])
	var s := Vector3(xf.scale[0], xf.scale[1], xf.scale[2])
	var basis := Basis.from_euler(Vector3(xf.rotation_deg[0], xf.rotation_deg[1], xf.rotation_deg[2]) * PI / 180.0)
	var box := AABB(bounds.position * s, bounds.size * s)
	var place := Transform3D(basis, pos)
	# The picture on the object's front face (a flat thing's only face).
	var size := Vector2(maxf(box.size.x, 0.05), maxf(box.size.y, 0.05))
	(_card.mesh as QuadMesh).size = size
	var front := box.get_center() + Vector3(0, 0, box.size.z * 0.5)
	_card.global_transform = place * Transform3D(Basis(), front)
	_card_mat.albedo_color.a = 0.55 if _card_mat.albedo_texture != null else 0.35
	_draw_box(place, box)
	# The footprint: a ring round the box's foot, on the floor.
	var foot := place * Vector3(box.get_center().x, 0, box.get_center().z)
	foot.y = 0.0
	var radius := maxf(0.25, Vector2(box.size.x, box.size.z).length() * 0.5)
	_draw_ring(foot, radius)
	_draw_dashes(place * Vector3(box.get_center().x, box.position.y, box.get_center().z), foot)
	var away := Vector2(foot.x - head.x, foot.z - head.z).length()
	_label.text = "%.1f m away" % away
	# At the ring's front, where it's in view whenever the ring is.
	_label.global_position = foot + _toward(foot, head) * radius + Vector3(0, 0.05, 0)
	for n in [_outline, _ring, _line, _label]:
		n.visible = true


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = false
	return mat


func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


## Turned so +Z faces `head` (level).
static func _facing(point: Vector3, head: Vector3) -> Basis:
	var to_head := head - point
	return Basis.looking_at(-to_head, Vector3.UP) if to_head.length() > 0.01 else Basis()


## The horizontal direction from `point` toward `head`.
static func _toward(point: Vector3, head: Vector3) -> Vector3:
	var to := Vector3(head.x - point.x, 0, head.z - point.z)
	return to.normalized() if to.length() > 0.01 else Vector3.BACK


func _draw_box(place: Transform3D, box: AABB) -> void:
	var m := _outline.mesh as ImmediateMesh
	m.clear_surfaces()
	_outline.global_transform = Transform3D()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var edges := [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	for e in edges:
		# A flat thing's front and back edges are the same: draw them once.
		if box.size.z < 0.001 and e[0] >= 4:
			continue
		m.surface_add_vertex(place * _corner(box, e[0]))
		m.surface_add_vertex(place * _corner(box, e[1]))
	m.surface_end()


## Corner `i` of `box` (bit 0: x, bit 1: y, bit 2: z).
static func _corner(box: AABB, i: int) -> Vector3:
	return box.position + Vector3(box.size.x if i & 1 else 0.0, box.size.y if i & 2 else 0.0, box.size.z if i & 4 else 0.0)


func _draw_ring(center: Vector3, radius: float) -> void:
	var m := _ring.mesh as ImmediateMesh
	m.clear_surfaces()
	_ring.global_transform = Transform3D()
	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 49:
		var a := TAU * i / 48.0
		m.surface_add_vertex(center + Vector3(cos(a), 0, sin(a)) * radius + Vector3(0, 0.01, 0))
	m.surface_end()


func _draw_dashes(from: Vector3, to: Vector3) -> void:
	var m := _line.mesh as ImmediateMesh
	m.clear_surfaces()
	_line.global_transform = Transform3D()
	var length := from.distance_to(to)
	if length < DASH:
		return
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var d := 0.0
	while d < length:
		m.surface_add_vertex(from.lerp(to, d / length))
		m.surface_add_vertex(from.lerp(to, minf(d + DASH * 0.5, length) / length))
		d += DASH
	m.surface_end()
