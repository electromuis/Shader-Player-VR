class_name StudioEditTools
extends Node3D

## Studio's hands-on editing: pick an object, grab it (one hand carries it,
## a second hand scales and turns it; with one hand, scale_by scales it as
## it's carried: the desktop's Ctrl+wheel / Ctrl+drag, the right stick
## sideways in the headset), and let go to write the move into
## the piece as one undoable step. Controllers, the desktop mouse and tests
## all drive it the same way: a "hand" is just a name and a transform (its
## -Z is where it points).
##
## What letting go writes (see _commit):
##   auto-key on  — keys at the playhead on the channels that changed
##                  (position / rotation_deg / scale), tracks made as needed
##   auto-key off — the object's spawn placement; on a channel that's
##                  already animated, its key at the playhead, or between
##                  keys the move is held unkeyed: shown, not written, until
##                  A or the diamond keys it (key_unkeyed) or the playhead
##                  moves on (drop_unkeyed)
## Snapping rounds the placement while dragging (10 cm, 15°, 5 % scale).
##
## While a drag runs the runner leaves the object alone (ScriptRunner.held),
## so the live move shows even where tracks animate it.

signal said(text: String)
## The selection changed (to "" when nothing is selected).
signal selection_changed(id: String)
## What a hand should feel (StudioHaptics kinds): "grab", "release",
## "snap" (the snapped placement moved on a step), "key" (a let-go that
## keyed, or the key button: hand "main", the hand that acts).
signal felt(kind: String, hand: String)

const SELECT_COLOR := Color(0.3, 0.79, 0.94)
const GRAB_COLOR := Color(1.0, 0.85, 0.3)
## What the pointer would pick, and the selection at its next key.
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.4)
const GHOST_COLOR := Color(0.3, 0.79, 0.94, 0.3)
## Keys this close to the playhead count as at it (not "next").
const SAME_KEY := 0.001
const SEAT_COLOR := Color(1.0, 0.82, 0.4)
const AXIS_LENGTH := 0.35
## Motion paths (StudioMotionPaths draws them): their colours (the
## viewer's in the seat's), how finely they're sampled, and their widths and
## key diamonds in pixels: the selection's, then other animated objects'
## (faint). The part of the selection's path already played is dimmer; its
## key at the playhead is white and bigger, a carried key yellow.
const PATH_COLOR := Color(0.3, 0.79, 0.94)
const KEY_PATH_COLOR := Color(1.0, 0.82, 0.4)
const PATH_PLAYED_ALPHA := 0.45
const PATH_NOW_COLOR := Color(1.0, 1.0, 1.0)
const PATH_STEP := 1.0 / 15.0
const PATH_POINTS := 1500.0
const PATH_WIDTH := 5.0
const PATH_KEY_SIZE := 12.0
const PATH_NOW_KEY_SIZE := 16.0
const OTHER_PATH_ALPHA := 0.35
const OTHER_PATH_WIDTH := 2.0
const OTHER_KEY_SIZE := 6.0
## Differences smaller than these don't count as a change on release.
const MOVE_EPS := 0.0005
const ANGLE_EPS := 0.01
const SCALE_EPS := 0.0005

var model: EditModel
var runner: ScriptRunner
var stage: Stage
## While a take runs, what's grabbed is recorded, not written on release.
## Optional.
var recorder: StudioRecorder

var auto_key := false
## Keys on change, "Animated": a change to something that already has keys
## keys it at the playhead (still things are just set). Off (and auto-key
## off), it's held unkeyed (see the top). Auto-key keys everything, and wins.
var key_animated := false
var snap := false
## Faint paths for every animated object on stage, not just the selection's
## (Studio's setting).
var all_paths := true
var selected := ""
## What the pointer is on (Studio sets it; "" for nothing): drawn faintly.
var hovered := ""
var _hover_bounds: Dictionary = {}  # node instance id -> AABB (one)

## The drag in progress: {id, node, primary, hands {name: Transform3D},
## offset, start (node-style dict), two ({} or {a0, b0, obj0})}.
var _grab: Dictionary = {}
## Where objects set by typed numbers were before (preview_channel).
var _typed_start: Dictionary = {}  # id -> node-style dict
## Moves of animated channels held unkeyed (see the top): id -> {t,
## channels {channel: [x, y, z]}}. The runner holds those objects.
var unkeyed: Dictionary = {}
var _lines: ImmediateMesh
var _lines_mesh: MeshInstance3D
var _bounds_cache: Dictionary = {}  # node instance id -> AABB
var _paths: StudioMotionPaths
var _paths_on := false  # a camera draws them this frame
## Sampled paths, kept while their keys don't change: id -> {hash, path
## (_sampled_path's)}.
var _path_cache: Dictionary = {}


func _ready() -> void:
	_lines = ImmediateMesh.new()
	_lines_mesh = MeshInstance3D.new()
	_lines_mesh.mesh = _lines
	_lines_mesh.top_level = true
	_lines_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines_mesh.extra_cull_margin = 16384.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 50
	_lines_mesh.material_override = mat
	add_child(_lines_mesh)
	_paths = StudioMotionPaths.new()
	_paths.name = "MotionPaths"
	add_child(_paths)


# ---------- picking and selection ----------

## Every object of the piece that's on stage now: [{id, xf, bounds}].
func candidates() -> Array:
	if model == null or runner == null:
		return []
	var registry := runner.registry()
	var nodes: Dictionary = {}
	for id in model.object_ids():
		var n := registry.get_node_by_id(id)
		if n != null and is_instance_valid(n) and n.is_inside_tree() and n.is_visible_in_tree():
			nodes[id] = n
	var others: Array = nodes.values()
	var out: Array = []
	for id in nodes:
		var n: Node3D = nodes[id]
		out.append({"id": id, "xf": n.global_transform, "bounds": StudioPicker.local_bounds(n, others)})
	return out


func pick(origin: Vector3, dir: Vector3) -> String:
	return StudioPicker.pick(origin, dir.normalized(), candidates())


## Select `id` ("" deselects).
func select(id: String) -> void:
	if id == selected:
		return
	selected = id
	_key_grab = {}
	_bounds_cache.clear()
	if id != "":
		_say("Selected %s." % {ScriptFormat.VIEWER: "the viewer", EditModel.CAMERA: "the camera effects"}.get(id, id))
	selection_changed.emit(id)


# ---------- grabbing ----------

func is_grabbing() -> bool:
	return not _grab.is_empty()


func grabbed_id() -> String:
	return String(_grab.get("id", ""))


## Start carrying `id` with the hand called `hand` (at `hand_xf`).
func grab(id: String, hand: String, hand_xf: Transform3D) -> bool:
	if id == "" or runner == null or is_grabbing():
		return false
	var node := runner.registry().get_node_by_id(id)
	if node == null or not node.is_inside_tree():
		return false
	select(id)
	runner.held[id] = true
	_grab = {
		"id": id, "node": node, "primary": hand, "hands": {hand: hand_xf},
		"offset": GrabMath.grip_offset(hand_xf, node.global_transform),
		"start": GrabMath.to_dict(node.transform), "two": {},
	}
	if recorder != null:
		recorder.touch_transform(id, node)
	felt.emit("grab", hand)
	return true


func move_hand(hand: String, hand_xf: Transform3D) -> void:
	if not is_grabbing() or not _grab.hands.has(hand):
		return
	_grab.hands[hand] = hand_xf
	_apply()


## A second hand takes hold too: from now on the distance between the two
## scales the object and their turn turns it.
func add_hand(hand: String, hand_xf: Transform3D) -> void:
	if not is_grabbing() or _grab.hands.has(hand) or _grab.hands.size() >= 2:
		return
	_grab.hands[hand] = hand_xf
	var node: Node3D = _grab.node
	_grab.two = {"a0": (_grab.hands[_grab.primary] as Transform3D).origin, "b0": hand_xf.origin,
			"obj0": node.global_transform, "other": hand}
	felt.emit("grab", hand)


## A hand lets go: with two, the other carries on alone; with one, the
## grab ends and is written (returns the undo label, or "").
func release_hand(hand: String) -> String:
	if not is_grabbing() or not _grab.hands.has(hand):
		return ""
	if _grab.hands.size() == 1:
		return release()
	_grab.hands.erase(hand)
	_grab.two = {}
	_grab.primary = _grab.hands.keys()[0]
	felt.emit("release", hand)
	var node: Node3D = _grab.node
	_grab.offset = GrabMath.grip_offset(_grab.hands[_grab.primary], node.global_transform)
	return ""


## Push the carried object further along the hand (negative pulls).
func push(metres: float) -> void:
	if not is_grabbing() or not _grab.two.is_empty() or metres == 0.0:
		return
	_grab.offset = GrabMath.pushed(_grab.offset, metres)
	_apply()


## Scale the carried object by `factor` about its own origin, as it's
## carried (not while two hands hold it: their spread scales it then).
func scale_by(factor: float) -> void:
	if not is_grabbing() or not _grab.two.is_empty() or factor <= 0.0 or factor == 1.0:
		return
	_grab.offset = GrabMath.scaled(_grab.offset, factor)
	_apply()


## `hand` is now at `hand_xf`, but the object stays put: it carries on from
## here (the desktop's Ctrl+drag scales instead of carrying).
func regrip(hand: String, hand_xf: Transform3D) -> void:
	if not is_grabbing() or not _grab.hands.has(hand) or not _grab.two.is_empty():
		return
	var now := GrabMath.carried(_grab.hands[hand], _grab.offset) if hand == _grab.primary 			else (_grab.node as Node3D).global_transform
	_grab.hands[hand] = hand_xf
	if hand == _grab.primary:
		_grab.offset = GrabMath.grip_offset(hand_xf, now)


## End the grab and write it. Returns the undo label ("" if nothing moved).
func release() -> String:
	if not is_grabbing():
		return ""
	var id: String = _grab.id
	var node: Node3D = _grab.node
	var hand: String = _grab.primary
	var label := ""
	if recorder != null and recorder.owns_transform(id):
		_grab = {}  # the take holds it where it was let go, and writes it
		felt.emit("release", hand)
		return ""
	if is_instance_valid(node):
		label = _commit(id, _grab.start, GrabMath.to_dict(node.transform))
	if not unkeyed.has(id):
		runner.held.erase(id)
	_grab = {}
	felt.emit("key" if auto_key and label != "" else "release", hand)
	return label


## Drop the grab without writing anything; the runner puts it back.
func cancel() -> void:
	_key_grab = {}
	if not is_grabbing():
		return
	var id := String(_grab.id)
	_grab = {}
	unhold_unkeyed()
	runner.held.erase(id)
	runner.apply_edit(model.timeline(), false)
	show_unkeyed()  # back to where it was held, if it was


func _apply() -> void:
	if not is_instance_valid(_grab.get("node")):
		_grab = {}  # it left the stage (despawned) while held
		return
	var node: Node3D = _grab.node
	var global: Transform3D
	if not _grab.two.is_empty():
		var two: Dictionary = _grab.two
		global = GrabMath.two_handed(two.a0, two.b0, (_grab.hands[_grab.primary] as Transform3D).origin,
				(_grab.hands[two.other] as Transform3D).origin, two.obj0)
	else:
		global = GrabMath.carried(_grab.hands[_grab.primary], _grab.offset)
	var local := GrabMath.to_local(node.get_parent().global_transform, global) if node.get_parent() is Node3D else global
	if snap:
		var on_grid := StudioSnap.snapped(GrabMath.to_dict(local))
		if _grab.has("on_grid") and JSON.stringify(on_grid) != JSON.stringify(_grab.on_grid):
			felt.emit("snap", _grab.primary)
		_grab.on_grid = on_grid
		local = GrabMath.from_dict(on_grid)
	node.transform = local


# ---------- writing ----------

## Key the selection where it is now, on all three channels, at the
## playhead (the "key it" button, whatever auto-key says). `key_also(id)`
## keys more in the same step (Studio: its unkeyed settings).
func key_selection(key_also: Callable = Callable()) -> String:
	if selected == "" or model == null:
		return ""
	var node := runner.registry().get_node_by_id(selected)
	if node == null:
		return ""
	var now := GrabMath.to_dict(node.transform)
	var t := runner.playhead
	var label := "Key %s at %s" % [selected, StudioStatus.timecode(t)]
	var id := selected
	model.batch(label, func():
		for ch in ["position", "rotation_deg", "scale"]:
			model.set_key(ScriptFormat.TRACK_TRANSFORM, id, ch, t, now[ch])
			_forget_unkeyed(id, ch)
		if key_also.is_valid():
			key_also.call(id))
	_say(label + ".")
	felt.emit("key", "main")  # the key button: the hand that acts
	return label


## Show `id` with transform channel `channel` at `value` ([x, y, z]; the
## inspector's typed numbers and sliders) while it's being set, holding the
## runner off it. set_channel writes it.
func preview_channel(id: String, channel: String, value: Array) -> void:
	var node := runner.registry().get_node_by_id(id) if runner != null else null
	if node == null or is_grabbing():
		return
	if not runner.held.has(id):
		runner.held[id] = true
		_typed_start[id] = GrabMath.to_dict(node.transform)
	var d := GrabMath.to_dict(node.transform)
	d[channel] = value
	node.transform = GrabMath.from_dict(d)


## Write transform channel `channel` of `id` as `value`, the way a grab
## writes a move (auto-key, keys on change, or the spawn / the whole path).
## Returns the undo label ("" if nothing changed).
func set_channel(id: String, channel: String, value: Array) -> String:
	var node := runner.registry().get_node_by_id(id) if runner != null else null
	if node == null or is_grabbing():
		return ""
	var before: Dictionary = _typed_start.get(id, GrabMath.to_dict(node.transform))
	_typed_start.erase(id)
	runner.held.erase(id)
	var after := before.duplicate(true)
	after[channel] = value
	return _commit(id, before, after)


## Write a move from `before` to `after` (node-style dicts, local).
func _commit(id: String, before: Dictionary, after: Dictionary) -> String:
	var changed := _changed_channels(before, after)
	if changed.is_empty():
		runner.apply_edit(model.timeline(), false)  # snap the runner's view back
		return ""
	var t := runner.playhead
	var label: String
	if auto_key:
		label = "Key %s at %s" % [id, StudioStatus.timecode(t)]
		model.batch(label, func():
			for ch in changed:
				model.set_key(ScriptFormat.TRACK_TRANSFORM, id, ch, _key_time(id, ch, t), after[ch])
				_forget_unkeyed(id, ch))
	else:
		label = "Move %s" % id
		var held_back: Array = []
		model.batch(label, func():
			var spawn := _spawn_transform(id)
			var spawn_changed := false
			for ch in changed:
				var ti := model.find_track(ScriptFormat.TRACK_TRANSFORM, id, ch)
				# A key under the playhead is edited in any mode.
				var on_key := ti >= 0 and StudioConfigEdits.key_near(model.tracks()[ti].get("keyframes", []), t) >= 0
				if ti >= 0 and (key_animated or on_key):
					model.set_key(ScriptFormat.TRACK_TRANSFORM, id, ch, _key_time(id, ch, t), after[ch])
					_forget_unkeyed(id, ch)
				elif ti >= 0:
					held_back.append(ch)
				else:
					spawn[ch] = after[ch]
					spawn_changed = true
			if spawn_changed:
				model.set_spawn_transform(id, spawn))
		if not held_back.is_empty():
			var u: Dictionary = unkeyed.get(id, {"t": t, "channels": {}})
			for ch in held_back:
				u.channels[ch] = after[ch]
			unkeyed[id] = u
			runner.held[id] = true
			show_unkeyed()
			var what := " and ".join(held_back.map(func(ch): return String(ch).trim_suffix("_deg")))
			label = "Not keyed: %s %s at %s. Key it (A, I) or ◆ keys it; moving the playhead drops it" % [id, what, StudioStatus.timecode(t)] \
					if held_back.size() == changed.size() else "%s; its %s not keyed yet (Key it: A, I)" % [label, what]
	_say(label + ".")
	return label


# ---------- unkeyed moves ----------

## Whether `id`'s `channel` has a move held unkeyed.
func is_unkeyed(id: String, channel: String) -> bool:
	return unkeyed.has(id) and unkeyed[id].channels.has(channel)


## Forget `id`'s unkeyed `channel` (it was keyed); with none left, the
## runner has the object again.
func _forget_unkeyed(id: String, channel: String) -> void:
	if not unkeyed.has(id):
		return
	unkeyed[id].channels.erase(channel)
	if unkeyed[id].channels.is_empty():
		unkeyed.erase(id)
		if not (is_grabbing() and _grab.id == id):
			runner.held.erase(id)


## Key the unkeyed moves where they were made: `id`'s ("" for everyone's),
## only `channel` if given; part of the caller's batch if there is one.
## Returns how many channels were keyed.
func key_unkeyed(id: String = "", channel: String = "") -> int:
	var n := 0
	for uid in unkeyed.keys():
		if id != "" and uid != id:
			continue
		var u: Dictionary = unkeyed[uid]
		for ch in u.channels.keys():
			if channel != "" and ch != channel:
				continue
			model.set_key(ScriptFormat.TRACK_TRANSFORM, uid, ch, _key_time(uid, ch, float(u.t)), u.channels[ch])
			_forget_unkeyed(uid, ch)
			n += 1
	return n


## Drop every unkeyed move: the runner puts the objects back on their
## paths. Returns what was dropped ("box position, cube scale"), "" if
## nothing.
func drop_unkeyed() -> String:
	if unkeyed.is_empty():
		return ""
	var names: Array = []
	for id in unkeyed.keys():
		for ch in unkeyed[id].channels.keys():
			names.append("%s %s" % [id, String(ch).trim_suffix("_deg")])
		if not (is_grabbing() and _grab.id == id):
			runner.held.erase(id)
	unkeyed.clear()
	runner.apply_edit(model.timeline(), false)
	return ", ".join(names)


## Let the runner place the unkeyed objects again (before it applies an
## edit; show_unkeyed afterwards puts the unkeyed moves back on top).
func unhold_unkeyed() -> void:
	for id in unkeyed.keys():
		if not (is_grabbing() and _grab.id == id):
			runner.held.erase(id)


## Put the unkeyed moves on their objects (as the runner left them) and
## hold them there.
func show_unkeyed() -> void:
	var registry := runner.registry() if runner != null else null
	for id in unkeyed.keys():
		runner.held[id] = true
		var node := registry.get_node_by_id(id) if registry != null else null
		if node == null or (is_grabbing() and _grab.id == id):
			continue
		var d := GrabMath.to_dict(node.transform)
		for ch in unkeyed[id].channels.keys():
			d[ch] = unkeyed[id].channels[ch]
		node.transform = GrabMath.from_dict(d)


## The unkeyed moves' time, or -1 if there are none.
func unkeyed_time() -> float:
	for u in unkeyed.values():
		return float(u.t)
	return -1.0


## When a key on `id`'s `channel` at `t` lands: on the key already within
## StudioConfigEdits.KEY_NEAR of it, if there is one (so it's replaced).
func _key_time(id: String, channel: String, t: float) -> float:
	var ti := model.find_track(ScriptFormat.TRACK_TRANSFORM, id, channel)
	if ti < 0:
		return t
	var kfs: Array = model.tracks()[ti].get("keyframes", [])
	var k := StudioConfigEdits.key_near(kfs, t)
	return float(kfs[k].get("t", t)) if k >= 0 else t


func _changed_channels(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	var eps := {"position": MOVE_EPS, "rotation_deg": ANGLE_EPS, "scale": SCALE_EPS}
	for ch in ["position", "rotation_deg", "scale"]:
		var a := Interpolation.to_vec3(before.get(ch))
		var b := Interpolation.to_vec3(after.get(ch))
		if ch == "rotation_deg":
			# Same orientation written differently (e.g. -180 and 180) isn't a change.
			var qa := Basis.from_euler(a * PI / 180.0)
			var qb := Basis.from_euler(b * PI / 180.0)
			if qa.get_rotation_quaternion().angle_to(qb.get_rotation_quaternion()) > deg_to_rad(eps[ch]):
				out.append(ch)
		elif a.distance_to(b) > eps[ch]:
			out.append(ch)
	return out


## The spawn transform as the file has it, filled in (a copy).
func _spawn_transform(id: String) -> Dictionary:
	var i := model.spawn_index(id)
	var t = model.tracks()[i].get("transform", {}) if i >= 0 else {}
	var out: Dictionary = (t as Dictionary).duplicate(true) if typeof(t) == TYPE_DICTIONARY else {}
	for pair in [["position", [0.0, 0.0, 0.0]], ["rotation_deg", [0.0, 0.0, 0.0]], ["scale", [1.0, 1.0, 1.0]]]:
		if not out.has(pair[0]):
			out[pair[0]] = pair[1]
	return out


# ---------- drawing ----------

func _process(_delta: float) -> void:
	_lines.clear_surfaces()
	_paths_on = _paths.begin(get_viewport().get_camera_3d() if is_inside_tree() and visible else null)
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_hover()
	_draw_selection()
	_draw_seat_lines()
	_draw_paths()
	_lines.surface_end()
	_paths.end()


## The selection's box and axes, the snapping grid while it's carried, and
## a ghost box where it'll be at its next key.
func _draw_selection() -> void:
	var id := selected
	var node := runner.registry().get_node_by_id(id) if runner != null and id != "" else null
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var key := node.get_instance_id()
	if not _bounds_cache.has(key):
		var others: Array = model.object_ids().map(func(o): return runner.registry().get_node_by_id(o)) if model != null else []
		_bounds_cache = {key: StudioPicker.local_bounds(node, others)}
	var box: AABB = _bounds_cache[key]
	var xf := node.global_transform
	var color := GRAB_COLOR if is_grabbing() else SELECT_COLOR
	if box.size != Vector3.ZERO:
		for e in _box_edges(box):
			_line(xf * e[0], xf * e[1], color)
	var o := xf.origin
	var b := xf.basis.orthonormalized()
	_line(o, o + b.x * AXIS_LENGTH, Color(1, 0.36, 0.36))
	_line(o, o + b.y * AXIS_LENGTH, Color(0.43, 0.88, 0.48))
	_line(o, o + b.z * AXIS_LENGTH, Color(0.36, 0.55, 1))
	if is_grabbing() and snap:
		_draw_grid(o, node)
	elif not is_grabbing() and box.size != Vector3.ZERO:
		var ghost := next_key_pose(id)
		if not ghost.is_empty():
			var parent := node.get_parent() as Node3D
			var gxf: Transform3D = (parent.global_transform if parent != null else Transform3D()) * (ghost.xf as Transform3D)
			if not gxf.is_equal_approx(xf):
				for e in _box_edges(box):
					_line(gxf * e[0], gxf * e[1], GHOST_COLOR)


## What the pointer would pick: a faint box (not the selection's).
func _draw_hover() -> void:
	if hovered == "" or hovered == selected or runner == null:
		return
	var node := runner.registry().get_node_by_id(hovered)
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var key := node.get_instance_id()
	if not _hover_bounds.has(key):
		var others: Array = model.object_ids().map(func(o): return runner.registry().get_node_by_id(o)) if model != null else []
		_hover_bounds = {key: StudioPicker.local_bounds(node, others)}
	var box: AABB = _hover_bounds[key]
	var xf := node.global_transform
	for e in _box_edges(box):
		_line(xf * e[0], xf * e[1], HOVER_COLOR)


## Where `id` will be at its next transform key after the playhead:
## {t, xf (its local transform then)}, or {} if it has none ahead. Channels
## without a track keep where it is now.
func next_key_pose(id: String) -> Dictionary:
	if model == null or runner == null:
		return {}
	var node := runner.registry().get_node_by_id(id)
	if node == null:
		return {}
	var now := runner.playhead
	var next := INF
	var tracks := {}
	for ch in ["position", "rotation_deg", "scale"]:
		var ti := model.find_track(ScriptFormat.TRACK_TRANSFORM, id, ch)
		if ti < 0:
			continue
		var kfs: Array = model.tracks()[ti].get("keyframes", [])
		tracks[ch] = kfs
		for k in kfs:
			if float(k.t) > now + SAME_KEY:
				next = minf(next, float(k.t))
				break
	if next == INF:
		return {}
	var d := GrabMath.to_dict(node.transform)
	for ch in tracks:
		var v = Interpolation.evaluate(tracks[ch], next)
		var vec := Interpolation.to_vec3(v)
		d[ch] = [vec.x, vec.y, vec.z]
	return {"t": next, "xf": GrabMath.from_dict(d)}


## The snapping grid: 10 cm lines on the object's parent's horizontal plane
## around it (1 m across).
func _draw_grid(at: Vector3, node: Node3D) -> void:
	var parent := node.get_parent() as Node3D
	var pxf := parent.global_transform if parent != null else Transform3D()
	var local := pxf.affine_inverse() * at
	var c := Color(1.0, 0.85, 0.3, 0.45)
	for i in range(-5, 6):
		var off := i * StudioSnap.GRID
		_line(pxf * (local + Vector3(off, 0, -0.5)), pxf * (local + Vector3(off, 0, 0.5)), c)
		_line(pxf * (local + Vector3(-0.5, 0, off)), pxf * (local + Vector3(0.5, 0, off)), c)


## Motion paths: where position tracks take things (for the viewer,
## "$viewer", its ride; a cut breaks the line). The selection's is wide, with
## a diamond and its time at each key (and a small camera, for the viewer);
## with all_paths every other animated object on stage gets a faint one.
## Something with fewer than two position keys has no path.
func _draw_paths() -> void:
	if not _paths_on or model == null:
		return
	var now := runner.playhead if runner != null else 0.0
	if all_paths and runner != null:
		for id in model.object_ids():
			if id == selected:
				continue
			var node := runner.registry().get_node_by_id(id)
			if node == null or not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree():
				continue
			var p := _sampled_path(id, model.tracks())
			if p.is_empty():
				continue
			var space := _path_space(id)
			_paths.path(_world_points(p.points, space), Color(PATH_COLOR, OTHER_PATH_ALPHA), OTHER_PATH_WIDTH)
			_paths.keys(p.keys.map(func(k): return {"world": space * (k[1] as Vector3),
					"color": Color(PATH_COLOR, 0.55), "size": OTHER_KEY_SIZE}))
	if selected == "":
		return
	var sel := _sampled_path(selected, _path_tracks())
	if sel.is_empty():
		return
	var space := _path_space(selected)
	var color := KEY_PATH_COLOR if selected == ScriptFormat.VIEWER else PATH_COLOR
	var split := -1
	for i in sel.points.size():
		if float(sel.points[i][2]) <= now:
			split = i
	_paths.path(_world_points(sel.points, space), color, PATH_WIDTH, split, Color(color, PATH_PLAYED_ALPHA))
	var carried := -1.0
	if not _key_grab.is_empty():
		carried = float(model.tracks()[_key_grab.ti].keyframes[_key_grab.ki].t)
	var marks: Array = []
	for k in sel.keys:
		var t := float(k[0])
		var big := t == carried or absf(t - now) <= StudioConfigEdits.KEY_NEAR
		marks.append({"world": space * (k[1] as Vector3), "label": key_time_text(t),
				"color": GRAB_COLOR if t == carried else (PATH_NOW_COLOR if big else color),
				"size": PATH_NOW_KEY_SIZE if big else PATH_KEY_SIZE, "keep": big})
	_paths.keys(marks)
	if selected == ScriptFormat.VIEWER:
		var vt := ViewerTrack.new()
		vt.build(_path_tracks())
		for k in sel.keys:
			_camera_marker(vt.pose_at(float(k[0])))


## `id`'s path in its own space (_path_space), from `tracks`: {points
## [[point, joined to the one before, t]], keys [[t, point]]}, or {} when it
## doesn't move (fewer than two position keys; for the viewer, no keys).
## Sampled again only when its keys change.
func _sampled_path(id: String, tracks: Array) -> Dictionary:
	var viewer := id == ScriptFormat.VIEWER
	var ti := -1
	var mine: Array
	if viewer:
		mine = tracks.filter(func(t): return t.get("target", "") == ScriptFormat.VIEWER or t.get("action", "") == "vr_cut")
	else:
		ti = _position_track(tracks, id)
		if ti < 0:
			return {}
		mine = [tracks[ti]]
	var h := mine.hash()
	var cached: Dictionary = _path_cache.get(id, {})
	if cached.get("hash") == h:
		return cached.path
	var out := {}
	var pts: Array = []
	var keys: Array = []
	if viewer:
		var vt := ViewerTrack.new()
		vt.build(tracks)
		var times := vt.key_times()
		if not times.is_empty():
			for t in _path_times(times[0], times.back()):
				pts.append([vt.pose_at(t).position, pts.size() > 0 and not vt.is_cut_at(t) and vt.cuts_between(t - PATH_STEP, t).is_empty(), t])
			for t in times:
				keys.append([t, vt.pose_at(t).position])
			out = {"points": pts, "keys": keys}
	else:
		var kfs: Array = tracks[ti].get("keyframes", [])
		if kfs.size() >= 2:
			for t in _path_times(float(kfs[0].t), float(kfs.back().t)):
				pts.append([Interpolation.to_vec3(Interpolation.evaluate(kfs, t)), pts.size() > 0, t])
			for k in kfs:
				keys.append([float(k.t), Interpolation.to_vec3(k.value)])
			out = {"points": pts, "keys": keys}
	_path_cache[id] = {"hash": h, "path": out}
	return out


## `id`'s position track in `tracks` (-1 if it has none).
static func _position_track(tracks: Array, id: String) -> int:
	for i in tracks.size():
		var t: Dictionary = tracks[i]
		if t.get("type") == ScriptFormat.TRACK_TRANSFORM and t.get("target") == id and t.get("channel") == "position":
			return i
	return -1


static func _world_points(points: Array, space: Transform3D) -> Array:
	return points.map(func(p): return [space * (p[0] as Vector3), p[1]])


## A key's time as its label shows it: 0:04, 1:20.5 (tenths when it isn't
## on a whole second).
static func key_time_text(t: float) -> String:
	var tenths := roundi(maxf(t, 0.0) * 10.0)
	var secs := tenths / 10
	var text := "%d:%02d" % [secs / 60, secs % 60]
	return text + (".%d" % (tenths % 10) if tenths % 10 != 0 else "")


# ---------- a path's keys, by hand ----------
# With something selected, its path's keys can be grabbed (the grip, or a
# mouse press on one): the key is carried with the hand like an object, the
# path redraws with it moved, and letting go writes its new position (one
# undo step; snapped to 10 cm with snapping on). An object's keys are in its
# parent's space; the viewer's in the world. The viewer's older cut events
# aren't keys of a track, so they aren't grabbed.

## A key this close to the ray is hit (metres, or this share of its
## distance, whichever is more).
const KEY_PICK := 0.15
const KEY_PICK_SHARE := 0.03

## The key being carried: {ti, ki, hand, grip (the key in the hand's
## space), world (where it is now), start}.
var _key_grab: Dictionary = {}


func is_grabbing_key() -> bool:
	return not _key_grab.is_empty()


## The selection's position keys in the world: [{ti, ki, t, world}].
func path_keys() -> Array:
	if model == null or selected == "":
		return []
	var ti := model.find_track(ScriptFormat.TRACK_TRANSFORM, selected, "position")
	if ti < 0:
		return []
	var space := _path_space(selected)
	var out: Array = []
	var kfs: Array = model.tracks()[ti].get("keyframes", [])
	for ki in kfs.size():
		out.append({"ti": ti, "ki": ki, "t": float(kfs[ki].t), "world": space * Interpolation.to_vec3(kfs[ki].value)})
	return out


## The selection's key nearest the ray (from `origin`, `dir`) within
## KEY_PICK, or {}.
func pick_key(origin: Vector3, dir: Vector3) -> Dictionary:
	dir = dir.normalized()
	var best := {}
	var best_d := INF
	for k in path_keys():
		var w: Vector3 = k.world
		var along := (w - origin).dot(dir)
		if along <= 0.0:
			continue
		var miss := (origin + dir * along).distance_to(w)
		if miss <= maxf(KEY_PICK, along * KEY_PICK_SHARE) and miss < best_d:
			best_d = miss
			best = k
	return best


## Start carrying key `k` (pick_key's) with `hand` at `hand_xf`.
func grab_key(k: Dictionary, hand: String, hand_xf: Transform3D) -> void:
	_key_grab = {"ti": k.ti, "ki": k.ki, "hand": hand, "grip": hand_xf.affine_inverse() * (k.world as Vector3),
			"world": k.world, "start": k.world}
	_say("Moving the key at %s." % StudioStatus.timecode(k.t))
	felt.emit("grab", hand)


func move_key_hand(hand: String, hand_xf: Transform3D) -> void:
	if _key_grab.is_empty() or _key_grab.hand != hand:
		return
	var p: Vector3 = hand_xf * (_key_grab.grip as Vector3)
	var was: Vector3 = _key_grab.world
	_key_grab.world = StudioSnap.position(p) if snap else p
	if snap and not was.is_equal_approx(_key_grab.world):
		felt.emit("snap", hand)


## Let go of the key: write where it is now (one undo step). Returns the
## undo label ("" if it didn't move).
func release_key(hand: String) -> String:
	if _key_grab.is_empty() or _key_grab.hand != hand:
		return ""
	var g := _key_grab
	_key_grab = {}
	if (g.world as Vector3).distance_to(g.start) < MOVE_EPS:
		felt.emit("release", hand)
		return ""
	var id := selected
	var local: Vector3 = _path_space(id).affine_inverse() * (g.world as Vector3)
	var kfs: Array = model.tracks()[g.ti].keyframes.duplicate(true)
	kfs[g.ki].value = [local.x, local.y, local.z].map(func(v): return float("%.4f" % v))
	var label := "Move %s's key at %s" % ["the viewer" if id == ScriptFormat.VIEWER else id, StudioStatus.timecode(float(kfs[g.ki].t))]
	if not model.set_keyframes(g.ti, kfs, label):
		felt.emit("release", hand)
		return ""
	_say(label + ".")
	felt.emit("key", hand)
	return label


## Where the selection's position keys live: its parent's space (the world
## for the viewer and for objects without a parent).
func _path_space(id: String) -> Transform3D:
	if id == ScriptFormat.VIEWER or runner == null:
		return Transform3D()
	var node := runner.registry().get_node_by_id(id)
	if node != null and is_instance_valid(node) and node.get_parent() is Node3D:
		return (node.get_parent() as Node3D).global_transform
	return Transform3D()


## The piece's tracks as the path should show them: with the carried key
## where the hand has it.
func _path_tracks() -> Array:
	if _key_grab.is_empty():
		return model.tracks()
	var tracks := model.tracks().duplicate()
	var t: Dictionary = tracks[_key_grab.ti].duplicate(true)
	var local: Vector3 = _path_space(selected).affine_inverse() * (_key_grab.world as Vector3)
	t.keyframes[_key_grab.ki].value = [local.x, local.y, local.z]
	tracks[_key_grab.ti] = t
	return tracks


## A small camera at a viewer key: a pyramid from the eye toward where it
## faces.
func _camera_marker(pose: Dictionary) -> void:
	var eye: Vector3 = pose.position
	var b := Basis(Vector3.UP, deg_to_rad((pose.rotation_deg as Vector3).y))
	var corners: Array = []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(eye + b * Vector3(c.x * 0.24, c.y * 0.15, -0.45))
	for i in 4:
		_line(eye, corners[i], KEY_PATH_COLOR)
		_line(corners[i], corners[(i + 1) % 4], KEY_PATH_COLOR)


## Times to sample a path at between `t0` and `t1` (at most PATH_POINTS).
static func _path_times(t0: float, t1: float) -> Array:
	var step := maxf(PATH_STEP, (t1 - t0) / PATH_POINTS)
	var out: Array = []
	var t := t0
	while t < t1:
		out.append(t)
		t += step
	out.append(t1)
	return out


## Where the audience sits at the playhead: a ring on the floor, a line up
## to eye height and an arrow for where they face.
func _draw_seat_lines() -> void:
	if stage == null:
		# ImmediateMesh needs at least one vertex in an open surface.
		_line(Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
		return
	var seat := stage.seat_pose()
	var eye: Vector3 = seat.position
	var floor := Vector3(eye.x, 0.0, eye.z)
	var n := 24
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_line(floor + Vector3(cos(a0), 0, sin(a0)) * 0.35, floor + Vector3(cos(a1), 0, sin(a1)) * 0.35, SEAT_COLOR)
	_line(floor, eye, Color(SEAT_COLOR, 0.5))
	var fwd := Basis(Vector3.UP, deg_to_rad(float(seat.yaw_deg))) * Vector3(0, 0, -1)
	var tip := floor + fwd * 0.6
	var side := fwd.cross(Vector3.UP) * 0.12
	_line(floor, tip, SEAT_COLOR)
	_line(tip, tip - fwd * 0.18 + side, SEAT_COLOR)
	_line(tip, tip - fwd * 0.18 - side, SEAT_COLOR)
	# Named, so it isn't taken for a motion path: it's where the audience sits.
	if _paths_on:
		_paths.label(floor, "Seat", SEAT_COLOR)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(b)


static func _box_edges(box: AABB) -> Array:
	var p := box.position
	var s := box.size
	var c := [p, p + Vector3(s.x, 0, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, 0, s.z)]
	var top := c.map(func(v): return v + Vector3(0, s.y, 0))
	var out: Array = []
	for i in 4:
		out.append([c[i], c[(i + 1) % 4]])
		out.append([top[i], top[(i + 1) % 4]])
		out.append([c[i], top[i]])
	return out


func _say(text: String) -> void:
	said.emit(text)
