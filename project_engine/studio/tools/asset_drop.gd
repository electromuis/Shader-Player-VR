class_name StudioAssetDrop
extends RefCounted

## Dropping a shelf card (a StudioAssetLibrary asset) into the world, as
## one undoable step:
##   an object (screen, cube, prefab) — a new object spawned at the
##     playhead where the card lands, turned to face you
##   a layer shader — a new layer with that shader, placed the same way; on
##     a layer, it becomes that layer's shader instead
##   an effect — onto the screen or layer it's dropped on (the end of its
##     effects stack)
##   a vertex effect — the same, at the end of its vertex effects
##   a look (StudioLooks) — onto an object of its kind (screen, layer,
##     other), which takes its setup and keeps its place and size; anywhere
##     else, a new object with it, at the size it was saved at
## A user asset is bundled into the piece first (StudioBundle), so the piece
## names its own copy. Where it lands (aim): the floor under the pointer,
## within FLOOR_REACH, even past an object the ray crosses first (so a card
## pointed below a big screen doesn't stick to its face); else the object
## the ray hits; else AIR_DISTANCE out along the ray. What it lands on
## (effects, looks) is always the object the ray hits.
## Screens and layers dropped on the floor stand at eye height there;
## anything else sits on the floor. Nothing goes below the floor. With
## snapping on, the spot snaps to 10 cm and the turn to 15°.

const FLOOR_REACH := 30.0
const AIR_DISTANCE := 3.0
const MIN_DISTANCE := 0.8
## The player's own prefabs' boxes at scale 1 (no need to build them).
const BUILTIN_BOUNDS := {
	"res://player/prefabs/screen.tscn": AABB(Vector3(-16, -9, 0), Vector3(32, 18, 0)),
	"res://player/prefabs/layer.tscn": AABB(Vector3(-16, -9, 0), Vector3(32, 18, 0)),
	"res://player/prefabs/cube.tscn": AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1)),
}

var model: EditModel
var edits: StudioConfigEdits
var _bounds := {}  # prefab path -> AABB


## Where a card carried along the ray (from `origin`, `dir`) lands:
## {point, on (the object id the ray hits, or ""), floor (it's the floor)}.
## `candidates`: StudioEditTools.candidates().
static func aim(origin: Vector3, dir: Vector3, candidates: Array) -> Dictionary:
	dir = dir.normalized()
	var on := StudioPicker.pick(origin, dir, candidates)
	var hit_t := INF
	for c in candidates:
		if c.id == on:
			var hit := StudioPicker.ray_box(origin, dir, c.xf, c.bounds)
			if not hit.is_empty() and not hit.inside:
				hit_t = hit.t
	var floor_t := -origin.y / dir.y if dir.y < -1e-4 else INF
	if floor_t <= FLOOR_REACH:
		return {"point": origin + dir * maxf(floor_t, MIN_DISTANCE), "on": on, "floor": true}
	if hit_t < INF:
		return {"point": origin + dir * maxf(hit_t, MIN_DISTANCE), "on": on, "floor": false}
	return {"point": origin + dir * AIR_DISTANCE, "on": on, "floor": false}


## Whether dropping `asset` at `where` adds a new object (rather than
## changing the one it's on), as drop() decides.
func adds(asset: Dictionary, where: Dictionary) -> bool:
	var on := String(where.get("on", ""))
	var on_kind := edits.kind_for(on) if on != "" and edits != null else ""
	match String(asset.type):
		"effect", "vertex":
			return false
		"layer":
			return on_kind != "layer"
		"look":
			return on == "" or on_kind != String(asset.kind)
	return true


## The box at scale 1 of what `asset` adds (a look's by its kind: its
## prefab is only known once the file is read, on the drop).
func bounds_for(asset: Dictionary) -> AABB:
	match String(asset.type):
		"layer":
			return bounds_of(StudioAssetLibrary.LAYER_PREFAB)
		"look":
			match String(asset.kind):
				"screen":
					return BUILTIN_BOUNDS["res://player/prefabs/screen.tscn"]
				"layer":
					return BUILTIN_BOUNDS[StudioAssetLibrary.LAYER_PREFAB]
			return BUILTIN_BOUNDS["res://player/prefabs/cube.tscn"]
	return bounds_of(String(asset.path))


## The spawn transform ({position, rotation_deg, scale}) for `asset` landing
## at `where` (aim()), seen from `head`; `bounds` is its prefab's box at
## scale 1.
static func placement(asset: Dictionary, where: Dictionary, head: Vector3, bounds: AABB, snap: bool) -> Dictionary:
	var s := float(asset.get("scale", 1.0))
	var p: Vector3 = where.point
	var bottom := -bounds.position.y * s  # from the origin down to its lowest point
	if where.floor and asset.kind in ["screen", "layer"]:
		p.y = maxf(head.y, bottom)
	elif where.floor:
		p.y = bottom
	else:
		p.y = maxf(p.y, bottom)
	var yaw := StudioSnap.face_yaw(p, head) if Vector2(head.x - p.x, head.z - p.z).length() > 0.01 else 0.0
	if snap:
		p = StudioSnap.position(p)
		yaw = snappedf(yaw, StudioSnap.ANGLE)
	# Tidy numbers in the file (Vector3 is single precision): 0.1 mm, 0.01°.
	var pos := [p.x, p.y, p.z].map(func(v): return float("%.4f" % v))
	return {"position": pos, "rotation_deg": [0.0, float("%.2f" % yaw), 0.0], "scale": [s, s, s]}


## Drop `asset` at `where`, the playhead at `t`. {ok, id (the new or
## changed object), message}.
func drop(asset: Dictionary, where: Dictionary, head: Vector3, t: float, snap: bool) -> Dictionary:
	if model == null:
		return {"ok": false, "message": "Open a piece first."}
	var on := String(where.get("on", ""))
	var on_kind := edits.kind_for(on) if on != "" and edits != null else ""
	var piece_dir := model.path.get_base_dir()
	match String(asset.type):
		"effect":
			if on_kind not in ["screen", "layer"]:
				return {"ok": false, "message": "Drop %s on a screen or a layer." % asset.label}
			var b := StudioBundle.bundle(piece_dir, asset.path)
			if not b.ok:
				return {"ok": false, "message": b.error}
			if not model.add_effect(on, b.path):
				return {"ok": false, "message": "Couldn't add %s to %s." % [asset.label, on]}
			return {"ok": true, "id": on, "message": "Added %s to %s." % [asset.label, on]}
		"vertex":
			if on_kind not in ["screen", "layer"]:
				return {"ok": false, "message": "Drop %s on a screen or a layer." % asset.label}
			if not edits.add_effect(on, asset.path, EditModel.VERTEX_EFFECTS):
				return {"ok": false, "message": "Couldn't add %s to %s." % [asset.label, on]}
			return {"ok": true, "id": on, "message": "Added %s to %s's vertex effects." % [asset.label, on]}
		"layer":
			if on_kind == "layer":
				var b := StudioBundle.bundle(piece_dir, asset.path)
				if not b.ok:
					return {"ok": false, "message": b.error}
				if not model.set_shader(on, b.path):
					return {"ok": false, "message": "%s already shows %s." % [on, asset.label]}
				return {"ok": true, "id": on, "message": "%s now shows %s." % [on, asset.label]}
		"look":
			var look := StudioLooks.read(asset.path)
			if look.is_empty():
				return {"ok": false, "message": "The look %s can't be read." % asset.label}
			if on != "" and on_kind == look.kind:
				var r := StudioLooks.apply(model, on, look)
				return {"ok": r.ok, "id": on, "message": r.message}
			return _add_look(asset, look, where, head, t, snap)
	return _add(asset, where, head, t, snap)


## A new object with `look`, where the card lands.
func _add_look(asset: Dictionary, look: Dictionary, where: Dictionary, head: Vector3, t: float, snap: bool) -> Dictionary:
	var prefab := StudioBundle.bundle(model.path.get_base_dir(), String(look.prefab))
	if not prefab.ok:
		return {"ok": false, "message": prefab.error}
	var xf := placement(asset, where, head, bounds_of(String(look.prefab)), snap)
	if typeof(look.get("scale")) == TYPE_ARRAY and look.scale.size() == 3:
		xf["scale"] = look.scale
	var result := {"id": "", "message": "Couldn't add %s." % asset.label}
	model.batch("Add %s" % asset.label, func():
		var made := StudioLooks.config_for_piece(model, look)
		if not made.ok:
			result.message = made.error
			return
		var base := "layer" if look.kind == "layer" else String(look.prefab).get_file().get_basename().to_snake_case()
		if look.kind == "screen":
			base = "main_screen" if model.spawn_index("main_screen") < 0 else "screen"
		var spawn := {"t": snappedf(t, 0.001), "prefab": model.name_prefab(prefab.path), "transform": xf,
				"id": model.free_id(base.validate_node_name().replace(".", "_"))}
		if not made.config.is_empty():
			spawn["config"] = made.config
		if model.add_object(spawn):
			result.id = spawn.id)
	if result.id == "":
		return {"ok": false, "message": result.message}
	return {"ok": true, "id": result.id, "message": "Added %s with the look %s at %s." % [result.id, asset.label, EditModel._time_label(t)]}


func _add(asset: Dictionary, where: Dictionary, head: Vector3, t: float, snap: bool) -> Dictionary:
	var piece_dir := model.path.get_base_dir()
	var layer: bool = asset.type == "layer"
	var prefab_src: String = StudioAssetLibrary.LAYER_PREFAB if layer else asset.path
	var prefab := StudioBundle.bundle(piece_dir, prefab_src)
	if not prefab.ok:
		return {"ok": false, "message": prefab.error}
	var shader := StudioBundle.bundle(piece_dir, asset.path) if layer else {}
	if layer and not shader.ok:
		return {"ok": false, "message": shader.error}
	var xf := placement(asset, where, head, bounds_of(prefab_src), snap)
	var added := {"id": ""}  # a lambda can't assign the caller's locals
	model.batch("Add %s" % asset.label, func():
		var spawn := {"t": snappedf(t, 0.001), "prefab": model.name_prefab(prefab.path), "transform": xf}
		if layer:
			spawn["config"] = {"shader": model.name_shader(shader.path)}
		spawn["id"] = model.free_id(_id_base(asset))
		if model.add_object(spawn):
			added.id = spawn.id)
	var id: String = added.id
	if id == "":
		return {"ok": false, "message": "Couldn't add %s." % asset.label}
	return {"ok": true, "id": id, "message": "Added %s at %s." % [id, EditModel._time_label(t)]}


## The first screen is main_screen (as the player's own is); others are
## named after what they are.
func _id_base(asset: Dictionary) -> String:
	if asset.kind == "screen":
		return "main_screen" if model.spawn_index("main_screen") < 0 else "screen"
	var base := String(asset.path).get_file().get_basename().to_snake_case()
	return base.validate_node_name().replace(".", "_") if base != "" else String(asset.kind)


## A prefab's box at scale 1 (built once): what it would be, from its
## scene, or a 1 m cube if it has no meshes.
func bounds_of(prefab_path: String) -> AABB:
	if BUILTIN_BOUNDS.has(prefab_path):
		return BUILTIN_BOUNDS[prefab_path]
	if _bounds.has(prefab_path):
		return _bounds[prefab_path]
	var box := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	var packed := ResourceLoader.load(prefab_path, "PackedScene") as PackedScene
	var node := packed.instantiate() if packed != null else null
	if node is Node3D:
		var b := StudioPicker.local_bounds(node)
		if b.size != Vector3.ZERO:
			box = b
	if node != null:
		node.free()
	_bounds[prefab_path] = box
	return box
