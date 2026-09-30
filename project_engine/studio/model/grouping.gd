class_name StudioGrouping
extends RefCounted

## Groups (TODO 14) and the object tree the outliner shows (TODO 15), on an
## EditModel. The format already has groups: a spawn event's `parent` puts
## an object inside another, in its space (it goes when its parent goes),
## and `group.tscn` is an empty node for grouping. This makes and changes
## them, each as one undo step:
##
## - group(): a new group around some objects (they must share a parent).
##   It spawns with the first of them, where they are on average, turned
##   and scaled not at all, so their placements and keys only shift by that
##   offset: exact, bezier handles included. Move, turn, scale or key the
##   group and they come along.
## - ungroup(): its children go back to the group's parent, keeping where
##   the group put them (at the playhead, if the group moves), and leave
##   with it if it left before them (despawns added).
## - set_parent(): into another object (the outliner's drag onto a group),
##   or out to the stage, staying where it is at the playhead.
##
## Keys are converted with the change of space. With a turn or a scale in
## it (ungrouping a turned group) positions convert exactly, rotations and
## scales per key (their handles and in-between turns can differ a little).
## The ScreenMount (the viewer's screen size and distance, applied to
## top-level screens, layers and groups) isn't part of this: it's the
## viewer's setting, not the piece's.

const GROUP_PREFAB := "res://player/prefabs/group.tscn"
## Where a new group goes is rounded to this (metres), to keep files tidy.
const GROUP_SNAP := 0.01
## Precision written for converted values.
const POS_STEP := 0.000001
const DEG_STEP := 0.0001
const SCALE_STEP := 0.000001


# ---------- reading the tree ----------

## `id`'s parent ("" for the stage), from its first spawn.
static func parent_of(model: EditModel, id: String) -> String:
	var i := model.spawn_index(id)
	return String(model.tracks()[i].get("parent", "")) if i >= 0 else ""


## The objects directly inside `id`, in file order.
static func children_of(model: EditModel, id: String) -> Array:
	return model.object_ids().filter(func(o): return parent_of(model, o) == id)


## Every object inside `id`, however deep.
static func descendants(model: EditModel, id: String) -> Array:
	var out: Array = []
	var stack: Array = children_of(model, id)
	while not stack.is_empty():
		var c: String = stack.pop_front()
		if out.has(c):
			continue
		out.append(c)
		stack.append_array(children_of(model, c))
	return out


## Whether `id` is somewhere inside `ancestor`.
static func is_inside(model: EditModel, id: String, ancestor: String) -> bool:
	var p := parent_of(model, id)
	var depth := 0
	while p != "" and depth < 64:
		if p == ancestor:
			return true
		p = parent_of(model, p)
		depth += 1
	return false


## Whether `id` spawns from the built-in group prefab.
static func is_group(model: EditModel, id: String) -> bool:
	var i := model.spawn_index(id)
	if i < 0:
		return false
	var prefab := String(model.tracks()[i].get("prefab", ""))
	return String(model.document().get("prefabs", {}).get(prefab, "")) == GROUP_PREFAB


## The objects as a tree, depth first, siblings in file order:
## [{id, depth, parent, group, children}] (`children`: how many directly
## inside). An object whose parent isn't in the piece counts as top level.
static func tree(model: EditModel) -> Array:
	var ids: Array = model.object_ids()
	var kids := {}
	var roots: Array = []
	for id in ids:
		var p := parent_of(model, id)
		if p != "" and ids.has(p):
			if not kids.has(p):
				kids[p] = []
			kids[p].append(id)
		else:
			roots.append(id)
	var out: Array = []
	var walk := func(id: String, depth: int, rec: Callable) -> void:
		if depth > 64:
			return
		var mine: Array = kids.get(id, [])
		out.append({"id": id, "depth": depth, "parent": parent_of(model, id) if depth > 0 else "",
				"group": is_group(model, id), "children": mine.size()})
		for c in mine:
			rec.call(c, depth + 1, rec)
	for r in roots:
		walk.call(r, 0, walk)
	return out


## `id`'s transform in its parent's space at `t`: the spawn in effect then
## (else the first), with its transform tracks' values.
static func local_at(model: EditModel, id: String, t: float) -> Transform3D:
	var list := model.tracks()
	var spawn: Dictionary = {}
	for i in model.spawn_indices(id):
		if spawn.is_empty() or float(list[i].get("t", 0.0)) <= t + EditModel.SAME_TIME:
			spawn = list[i]
	var xf = spawn.get("transform", {})
	var parts: Dictionary = xf.duplicate() if typeof(xf) == TYPE_DICTIONARY else {}
	for ch in ["position", "rotation_deg", "scale"]:
		var ti := model.find_track(ScriptFormat.TRACK_TRANSFORM, id, ch)
		if ti < 0:
			continue
		var v = Interpolation.evaluate(list[ti].get("keyframes", []), t)
		if v != null:
			parts[ch] = v
	return ScriptRunner._read_transform(parts)


## `id`'s transform on the stage at `t` (its parents' chained); identity
## for "".
static func world_at(model: EditModel, id: String, t: float) -> Transform3D:
	var xf := Transform3D()
	var depth := 0
	while id != "" and depth < 64:
		xf = local_at(model, id, t) * xf
		id = parent_of(model, id)
		depth += 1
	return xf


## A time after everything in the piece happens (its length, or its last
## event or key and a second): lanes that reach it never end.
static func horizon(model: EditModel) -> float:
	var out := 0.0
	var d = model.document().get("media", {}).get("duration", 0.0)
	if typeof(d) in [TYPE_FLOAT, TYPE_INT]:
		out = float(d)
	for ev in model.tracks():
		out = maxf(out, float(ev.get("t", 0.0)))
		for k in ev.get("keyframes", []):
			out = maxf(out, float(k.get("t", 0.0)))
	return out + 1.0


# ---------- changing it ----------

## Put `ids` in a new group, at the playhead `t`'s positions. {ok, id} or
## {ok: false, error}.
static func group(model: EditModel, ids: Array, t: float) -> Dictionary:
	var members: Array = []
	for id in ids:
		if String(id).begins_with("$") or model.spawn_index(id) < 0:
			return _fail("%s can't go in a group" % EditModel.who(id))
		if not members.has(id):
			members.append(id)
	# Something inside another of them comes along with it.
	members = members.filter(func(id): return not members.any(func(o): return o != id and is_inside(model, id, o)))
	if members.is_empty():
		return _fail("Select something to group")
	var parent := parent_of(model, members[0])
	var list := model.tracks()
	var first := -1
	var at := INF
	var center := Vector3.ZERO
	for id in members:
		for i in model.spawn_indices(id):
			if String(list[i].get("parent", "")) != parent:
				return _fail("%s and %s are in different groups: put them in the same one first" % [members[0], id])
			first = i if first < 0 else mini(first, i)
			at = minf(at, float(list[i].get("t", 0.0)))
		center += local_at(model, id, t).origin
	center /= members.size()
	center = Vector3(snappedf(center.x, GROUP_SNAP), snappedf(center.y, GROUP_SNAP), snappedf(center.z, GROUP_SNAP))
	var gid := model.free_id("group")
	var into := Transform3D(Basis(), -center)
	var label := "Group %s as %s" % [_names(members), gid]
	var ok := model.batch(label, func():
		var ev := {"type": "event", "t": at, "action": "spawn", "id": gid, "prefab": _group_prefab_key(model),
				"transform": {"position": [center.x, center.y, center.z]}}
		if parent != "":
			ev["parent"] = parent
		var out := _copy_tracks(model)
		for id in members:
			_convert(out, id, into)
			_set_parent_field(out, id, gid)
		out.insert(first, ev)
		model.set_tracks(out, label))
	return {"ok": ok, "id": gid, "error": "" if ok else "Nothing to group"}


## Take `gid`'s children out (to its parent) and remove it. {ok, ids (its
## children), note} or {ok: false, error}. `note` says what didn't come
## along ("" if nothing): the group's motion (but for where it was at `t`)
## and its modifiers.
static func ungroup(model: EditModel, gid: String, t: float) -> Dictionary:
	if gid.begins_with("$") or model.spawn_index(gid) < 0:
		return _fail("Select a group to ungroup")
	var kids := children_of(model, gid)
	if kids.is_empty() and not is_group(model, gid):
		return _fail("%s has nothing in it" % gid)
	var up := parent_of(model, gid)
	var into := local_at(model, gid, t)
	var goes: Array = []  # when the group left, taking its children with it
	for ev in model.tracks():
		if ev.get("type") == "event" and ev.get("action") == "despawn" and ev.get("target") == gid:
			goes.append(float(ev.get("t", 0.0)))
	var notes: Array = []
	for ch in ["position", "rotation_deg", "scale"]:
		if model.find_track(ScriptFormat.TRACK_TRANSFORM, gid, ch) >= 0:
			notes.append("its motion is dropped: they stay where it had them at %s" % EditModel._time_label(t))
			break
	if model.config_of(gid).has("modifiers"):
		notes.append("its modifiers are dropped")
	var label := "Ungroup %s" % gid
	var until := horizon(model)
	var lanes := StudioTimeline.lanes(model, until)
	var ok := model.batch(label, func():
		var out := _copy_tracks(model)
		for id in kids:
			_convert(out, id, into)
			_set_parent_field(out, id, up)
			for lane in lanes:
				if lane.id != id:
					continue
				for s in lane.spans.size():
					var end: float = lane.spans[s][1]
					if lane.ends[s].despawn < 0 and end < until and goes.any(func(g): return absf(g - end) < EditModel.SAME_TIME):
						out.append({"type": "event", "t": end, "action": "despawn", "target": id})
		out = out.filter(func(ev): return not EditModel._belongs_to(ev, {gid: true}))
		model.set_tracks(out, label))
	return {"ok": ok, "ids": kids, "error": "" if ok else "Nothing changed",
			"note": "; ".join(notes)}


## Move `id` into `parent` ("" for the stage), keeping where it is at `t`.
## {ok} or {ok: false, error}.
static func set_parent(model: EditModel, id: String, parent: String, t: float) -> Dictionary:
	if id.begins_with("$") or model.spawn_index(id) < 0:
		return _fail("%s can't go in a group" % EditModel.who(id))
	if parent != "" and (parent.begins_with("$") or model.spawn_index(parent) < 0):
		return _fail("%s isn't an object" % EditModel.who(parent))
	if parent == id or (parent != "" and is_inside(model, parent, id)):
		return _fail("%s can't go inside itself" % id)
	var list := model.tracks()
	var spawns := model.spawn_indices(id)
	if spawns.all(func(i): return String(list[i].get("parent", "")) == parent):
		return _fail("%s is already %s" % [id, "in " + parent if parent != "" else "on its own"])
	if parent != "":
		var spans: Array = []
		for lane in StudioTimeline.lanes(model, horizon(model)):
			if lane.id == parent:
				spans = lane.spans
		for i in spawns:
			var s := float(list[i].get("t", 0.0))
			if not spans.any(func(sp): return sp[0] <= s + EditModel.SAME_TIME and s < sp[1]):
				return _fail("%s isn't on stage at %s, when %s comes on" % [parent, EditModel._time_label(s), id])
	var old := parent_of(model, id)
	var into := world_at(model, parent, t).affine_inverse() * world_at(model, old, t)
	var label := ("Put %s in %s" % [id, parent]) if parent != "" else ("Take %s out of %s" % [id, old])
	var ok := model.batch(label, func():
		var out := _copy_tracks(model)
		_convert(out, id, into)
		_set_parent_field(out, id, parent)
		if parent != "":
			out = _spawn_after(out, parent, [id] + descendants(model, id))
		model.set_tracks(out, label))
	return {"ok": ok, "error": "" if ok else "Nothing changed"}


# ---------- internals ----------

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "errors": [error]}


static func _names(ids: Array) -> String:
	return ", ".join(ids) if ids.size() <= 3 else "%s and %d more" % [", ".join(ids.slice(0, 2)), ids.size() - 2]


## The `prefabs` key for the group prefab, named if the piece has none.
static func _group_prefab_key(model: EditModel) -> String:
	var prefabs = model.document().get("prefabs", {})
	if typeof(prefabs) == TYPE_DICTIONARY:
		if prefabs.get("group", "") == GROUP_PREFAB:
			return "group"
		for k in prefabs:
			if prefabs[k] == GROUP_PREFAB:
				return k
	return model.name_prefab(GROUP_PREFAB)


static func _copy_tracks(model: EditModel) -> Array:
	return model.tracks().duplicate(true)


static func _set_parent_field(list: Array, id: String, parent: String) -> void:
	for ev in list:
		if ev.get("type") == "event" and ev.get("action") == "spawn" and ev.get("id") == id:
			if parent == "":
				ev.erase("parent")
			else:
				ev["parent"] = parent


## Spawn events of `ids` that come before `parent`'s first spawn in the file
## go right after it: at the same time, events run in file order, and a
## parent has to be there first.
static func _spawn_after(list: Array, parent: String, ids: Array) -> Array:
	var p := -1
	for i in list.size():
		if list[i].get("type") == "event" and list[i].get("action") == "spawn" and list[i].get("id") == parent:
			p = i
			break
	if p < 0:
		return list
	var moving: Array = []
	var out: Array = []
	for i in list.size():
		var ev: Dictionary = list[i]
		if i < p and ev.get("type") == "event" and ev.get("action") == "spawn" and ids.has(ev.get("id")):
			moving.append(ev)
		else:
			out.append(ev)
	if moving.is_empty():
		return list
	var at := out.find(list[p]) + 1
	for k in moving.size():
		out.insert(at + k, moving[k])
	return out


## Re-express `id`'s placement (every spawn's transform) and transform keys
## in a new parent's space: `into` maps the old parent's space to the new's.
static func _convert(list: Array, id: String, into: Transform3D) -> void:
	if into.is_equal_approx(Transform3D()):
		return
	var turns := not into.basis.is_equal_approx(Basis())
	var turn := into.basis.orthonormalized()
	var stretch := into.basis.get_scale()
	for ev in list:
		if ev.get("type") == "event" and ev.get("action") == "spawn" and ev.get("id") == id:
			var before = ev.get("transform", {})
			var had: Dictionary = before if typeof(before) == TYPE_DICTIONARY else {}
			ev["transform"] = _placement(into * ScriptRunner._read_transform(had), had, turns)
		elif ev.get("type") == ScriptFormat.TRACK_TRANSFORM and ev.get("target") == id:
			var ch := String(ev.get("channel", ""))
			if ch != "position" and not turns:
				continue  # a move alone leaves turns and sizes as they are
			var prev = null  # [the previous key's value before, after]
			for k in ev.get("keyframes", []):
				var v := Interpolation.to_vec3(k.get("value"))
				match ch:
					"position":
						k["value"] = _rounded(into * v, POS_STEP)
						for side in ["in", "out"]:
							if k.has(side):
								k[side] = _turned_handles(k[side], into.basis)
					"rotation_deg":
						var b := turn * Basis.from_euler(v * (PI / 180.0))
						var e := b.get_euler() * (180.0 / PI)
						if prev != null:
							# As far round from the last key as it was (a spin stays a spin).
							e = _unwrapped(e, prev[1] + (v - prev[0]))
						prev = [v, e]
						k["value"] = _rounded(e, DEG_STEP)
					"scale":
						k["value"] = _rounded(v * stretch, SCALE_STEP)


## A spawn transform from `xf`, with the parts the old one had (and any
## that aren't the default now).
static func _placement(xf: Transform3D, had: Dictionary, turns: bool) -> Dictionary:
	var d := GrabMath.to_dict(xf)
	var out := {"position": _rounded(Interpolation.to_vec3(d.position), POS_STEP)}
	if turns or had.has("rotation_deg"):
		var r := _rounded(Interpolation.to_vec3(d.rotation_deg), DEG_STEP)
		if had.has("rotation_deg") or r != [0.0, 0.0, 0.0]:
			out["rotation_deg"] = r
	if turns or had.has("scale"):
		var s := _rounded(Interpolation.to_vec3(d.scale), SCALE_STEP)
		if had.has("scale") or s != [1.0, 1.0, 1.0]:
			out["scale"] = s
	return out


## Bezier handles ([dt, dv] per element) with their dv turned by `basis`.
static func _turned_handles(h, basis: Basis):
	if typeof(h) != TYPE_ARRAY or h.size() != 3 or typeof(h[0]) != TYPE_ARRAY:
		return h
	var dv := Vector3()
	for c in 3:
		dv[c] = float(h[c][1]) if h[c].size() == 2 else 0.0
	dv = basis * dv
	var out: Array = []
	for c in 3:
		out.append([float(h[c][0]) if h[c].size() == 2 else 0.0, snappedf(dv[c], POS_STEP)])
	return out


## `e` (degrees) with whole turns added or taken per axis to be nearest
## `near`.
static func _unwrapped(e: Vector3, near: Vector3) -> Vector3:
	for c in 3:
		e[c] += roundf((near[c] - e[c]) / 360.0) * 360.0
	return e


static func _rounded(v: Vector3, step: float) -> Array:
	return [snappedf(v.x, step) + 0.0, snappedf(v.y, step) + 0.0, snappedf(v.z, step) + 0.0]
