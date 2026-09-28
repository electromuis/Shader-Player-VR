@tool
extends RefCounted

## Walks a VJScene root and its child AnimationPlayer, produces a JSON dict
## matching the player's script format (see docs/script_format.md), writes it
## to VJScene.output_path.
##
## Convention (see addon README):
##   - Root is a Node3D with vj_scene.gd (VJScene) attached
##   - Its children are VJ objects: builtin prefab instances (`vj_prefab`
##     metadata "screen" / "layer" / "cube"), instances of any other .tscn
##     in the project (custom prefabs, bundled next to the JSON), or plain
##     Node3Ds (optionally with vj_object.gd), which are groups. Nodes added under an object (in this
##     scene, not inside its prefab) are objects too, spawned with
##     `parent`: they move with it and go when it does. Node names are the
##     ids, so they must be unique across the scene
##   - An optional VJViewer child (vj_viewer.gd) is the viewer; its keys
##     become vr_cut events, or with `motion` "smooth" a ride ("$viewer"
##     transform tracks)
##   - A single AnimationPlayer child holds one Animation named "main"
##   - Track paths are relative to root, any depth (`<path>` below is e.g.
##     `screens/screen_left`):
##       <path>:position / :rotation / :scale         → transform tracks
##       <path>:visible                               → spawn / despawn events
##       <path>:<...>:shader_parameter/<name>         → shader_param "<id>.surface"
##                                                      ("<id>.layer" on layers)
##       <path>/<effect>:material:shader_parameter/<name>
##                                                    → shader_param "<id>.effect<N>"
##         (<effect> a VJEffect child of a screen or layer, N its place
##         among the enabled ones)
##       <path>/<vertex effect>:params/<name>         → shader_param "<id>.vertex<N>"
##         (<vertex effect> a VJVertexEffect child, N its place among the
##         enabled ones)
##       <path>:arc_x / :arc_y / :auto_height / :keep_row_width /
##         :straight_rows (screens, layers)                                    → shader_param "<id>.shape"
##       <path>:opacity, and earlier scenes' :curvature / :vertical_curvature
##         (screens, layers)                          → shader_param "<id>.display"
##       <path>:opacity / :tint / :flash / :speed / :sort_offset (VJObject;
##         opacity only where it's not a screen's or layer's display fade)
##                                                    → shader_param "<id>.modifiers"
##       <path>:spin / :pulse (VJObject)              → shader_param "<id>.reactive"
##       <viewer>:position / :rotation                → vr_cut events, or
##                                                      transform "$viewer"
##     Value and bezier tracks both work; bezier tracks (one per component,
##     e.g. `<path>:position:x`) export as "bezier" keys with their handles.
##
## Scripts are referenced via preload rather than `class_name` so the exporter
## can be run headlessly against a fresh project (before Godot has populated
## the global class cache).

const VJSceneScript := preload("res://addons/vj_editor/builtin_prefabs/vj_scene.gd")
const VJScreenScript := preload("res://addons/vj_editor/builtin_prefabs/screen.gd")
const VJLayerScript := preload("res://addons/vj_editor/builtin_prefabs/layer.gd")
const VJViewerScript := preload("res://addons/vj_editor/builtin_prefabs/vj_viewer.gd")
const VJObjectScript := preload("res://addons/vj_editor/modifiers/vj_object.gd")
const VJEffectScript := preload("res://addons/vj_editor/builtin_prefabs/effect.gd")
const VJVertexEffectScript := preload("res://addons/vj_editor/builtin_prefabs/vertex_effect.gd")
const BezierTracksScript := preload("res://addons/vj_editor/exporter/bezier_tracks.gd")

const _ANIMATION_NAME := "main"
## `source` of the events resolve/VJ Sync.py writes from timeline markers.
const RESOLVE_SOURCE := "resolve"
## The addon's copies of the player's layer / effect shaders and their
## includes map to the player's own (same file names under this folder).
const _VISUALIZER_ADDON_DIR := "res://addons/vj_editor/visualizer/"
const _VISUALIZER_PLAYER_DIR := "res://player/visualizer/"
const _SHADER_PARAM_PREFIX := "shader_parameter/"
const _DISPLAY_PROPS := ["curvature", "vertical_curvature", "opacity"]
## Where the player starts every script (VJViewer's rest pose should match).
const VIEWER_HOME_POSITION := Vector3(0, 2, 8)
## The player's target for the viewer's ride.
const VIEWER_TARGET := "$viewer"
## In a ride, keys this close (seconds) are a cut: the viewer jumps. The
## importer writes a step as a hold ending 1 ms before the next key.
const VIEWER_CUT_GAP := 0.002
## A screen's surface params, animated on `<id>.shape`.
const _SHAPE_PROPS := ["arc_x", "arc_y", "auto_height", "keep_row_width", "straight_rows"]
## Picked per spawn in the player: not animatable.
const _FIXED_PROPS := ["surface", "placement"]
## The addon's built-in vertex effects: the player knows them by name.
const _VERTEX_ADDON_DIR := "res://addons/vj_editor/visualizer/vertex/"
## Builtin prefab keys → the player's copies.
const _PLAYER_PREFABS := {
	"screen": "res://player/prefabs/screen.tscn",
	"layer": "res://player/prefabs/layer.tscn",
	"cube": "res://player/prefabs/cube.tscn",
	"group": "res://player/prefabs/group.tscn",
}
## Uniforms a layer's preview feeds (not authored params).
const _LAYER_INPUTS := ["iChannel0", "iChannel1", "iChannel2", "iChannel3", "iChannelResolution",
		"iResolution", "video_stereo", "audio_level", "audio_bass", "audio_mid", "audio_high"]


## Exports and returns the absolute path of the written JSON ("" on failure).
static func export_from_root(root: Node) -> String:
	if root == null or root.get_script() != VJSceneScript:
		push_error("VJ export: scene root is not a VJScene. Attach vj_scene.gd to the root Node3D.")
		return ""
	var scene := root
	var abs_path := output_path_of(scene)
	if abs_path.is_empty():
		push_error("VJ export: VJScene.output_path is empty.")
		return ""
	var out_dir := abs_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)

	var result := _build_json(scene, out_dir)
	if not result.ok:
		push_error("VJ export failed: %s" % result.error)
		return ""

	if FileAccess.file_exists(abs_path):
		carry_over_resolve_events(FileAccess.get_file_as_string(abs_path), result.data)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("VJ export: could not open '%s' for writing (error %d)" % [abs_path, FileAccess.get_open_error()])
		return ""
	f.store_string(JSON.stringify(result.data, "  ", false))
	f.close()
	print("VJ export: wrote %s" % abs_path)
	return abs_path


## Appends the events DaVinci Resolve's VJ Sync script wrote into the
## previous export (`"source": "resolve"`, from its timeline markers) to
## `data`'s tracks, so exporting from here doesn't lose them; Resolve
## replaces exactly those on its next marker export. Returns how many.
static func carry_over_resolve_events(old_json: String, data: Dictionary) -> int:
	var json := JSON.new()
	if json.parse(old_json) != OK:
		return 0
	var old = json.data
	if typeof(old) != TYPE_DICTIONARY or typeof(old.get("tracks")) != TYPE_ARRAY:
		return 0
	var kept := 0
	for track in old["tracks"]:
		if typeof(track) == TYPE_DICTIONARY and track.get("source") == RESOLVE_SOURCE:
			data["tracks"].append(track)
			kept += 1
	return kept


## Absolute filesystem path the scene exports to ("" if unset).
static func output_path_of(scene: Node) -> String:
	var out_path := String(scene.output_path)
	if out_path.is_empty():
		return ""
	if out_path.begins_with("res://") or out_path.begins_with("user://"):
		out_path = ProjectSettings.globalize_path(out_path)
	return out_path.simplify_path()


static func _build_json(scene, out_dir: String) -> Dictionary:
	var collected := _collect_objects(scene, out_dir)
	if not collected.ok:
		return collected
	var objects: Array = collected.objects
	if objects.is_empty():
		return _err("scene has no VJ objects (add prefab instances as children of the root)")

	var player := _find_animation_player(scene)
	var animation: Animation = null
	if player != null and player.has_animation(_ANIMATION_NAME):
		animation = player.get_animation(_ANIMATION_NAME)

	var shaders: Dictionary = {}
	# Spawn / despawn events from each object's (and its parents') visibility.
	# Mid-timeline spawn events get the object's config attached so shader
	# params travel with them.
	var tracks := _presence_events(scene, animation, objects, out_dir, shaders)

	# Animation-derived tracks (transform channels, shader params).
	if animation != null:
		for t in _tracks_from_animation(scene, animation, objects):
			tracks.append(t)
	var viewer := _find_viewer(scene)
	if viewer != null:
		var viewer_tracks := _viewer_ride(animation, viewer) if String(viewer.motion) == "smooth" else _viewer_cuts(animation, viewer)
		for e in viewer_tracks:
			tracks.append(e)

	var media := {"video": String(scene.video_relative_path)}
	if float(scene.duration) > 0.0:
		media["duration"] = float(scene.duration)
	var meta := {
		"title": String(scene.title),
		"author": String(scene.author),
		"created": String(scene.created),
	}

	# Objects reference prefabs by key; every key used in a spawn event must
	# be present here.
	var prefabs: Dictionary = {}
	for obj in objects:
		prefabs[obj.prefab_key] = obj.prefab_path

	var json_root := {
		"format_version": 2,
		"meta": meta,
		"media": media,
		"prefabs": prefabs,
		"shaders": shaders,
		"objects": [],
		"tracks": tracks,
	}
	return {"ok": true, "data": json_root}


# ---------- object collection ----------

class _Obj:
	var id: String
	var prefab_key: String   # key used in the JSON prefabs map + spawn.prefab
	var prefab_path: String  # value in the prefabs map (what the player resolves)
	var node: Node3D
	var parent: _Obj         # null: a child of the root
	var path: String         # NodePath from the root, as tracks name it


## {ok, objects: Array[_Obj] parents before children} or {ok: false, error}.
static func _collect_objects(scene, out_dir: String) -> Dictionary:
	var out: Array = []
	var bundled: Dictionary = {}  # source scene path -> {key, path}
	_collect_under(scene, scene, null, out_dir, bundled, out)
	var seen: Dictionary = {}
	for obj in out:
		if seen.has(obj.id):
			return _err("two objects are named '%s' ('%s' and '%s'); names are the script's ids, so they must be unique across the scene" % [obj.id, seen[obj.id], obj.path])
		seen[obj.id] = obj.path
	return {"ok": true, "objects": out}


static func _collect_under(scene: Node, node: Node, parent: _Obj, out_dir: String, bundled: Dictionary, out: Array) -> void:
	for child in node.get_children():
		# Only nodes placed in this scene: not the insides of a prefab instance.
		if child.owner != scene:
			continue
		if child is AnimationPlayer or not (child is Node3D):
			continue
		# Standard scene furniture (and the viewer) — not VJ objects.
		if child is Camera3D or child is Light3D or child is WorldEnvironment:
			continue
		var resolved = _resolve_prefab(child, out_dir, bundled)
		if resolved == null:
			continue
		var o := _Obj.new()
		o.id = child.name
		o.prefab_key = resolved.key
		o.prefab_path = resolved.path
		o.node = child
		o.parent = parent
		o.path = String(scene.get_path_to(child))
		out.append(o)
		_collect_under(scene, child, o, out_dir, bundled, out)


## {key, path} for `node`'s prefab, or null (skipped, with a warning).
static func _resolve_prefab(node: Node, out_dir: String, bundled: Dictionary):
	var prefab_meta: String = ""
	if node.has_meta("vj_prefab"):
		prefab_meta = String(node.get_meta("vj_prefab"))
	if prefab_meta.is_empty():
		# Fall back to the scene file if instanced from one.
		prefab_meta = String(node.scene_file_path)
	if prefab_meta.is_empty():
		if node.get_class() == "Node3D" and (node.get_script() == null or node.get_script() == VJObjectScript):
			return {"key": "group", "path": _PLAYER_PREFABS["group"]}
		push_warning("VJ export: '%s' has no vj_prefab metadata and no scene_file_path; skipping." % node.name)
		return null
	var resolved = _resolve_builtin_prefab(prefab_meta)
	if resolved != null:
		return resolved
	if bundled.has(prefab_meta):
		return bundled[prefab_meta]
	resolved = _bundle_prefab(prefab_meta, out_dir)
	if resolved != null:
		bundled[prefab_meta] = resolved
	return resolved


## Short builtin keys ("screen" / "layer" / "cube", or the addon's own
## scenes) map to the player's copies of those prefabs. Returns null for
## anything else.
static func _resolve_builtin_prefab(prefab_meta: String):
	var key := ""
	if _PLAYER_PREFABS.has(prefab_meta):
		key = prefab_meta
	elif prefab_meta.contains("vj_editor"):
		for k in ["screen", "layer", "cube"]:
			if prefab_meta.ends_with("/%s.tscn" % k):
				key = k
	if key.is_empty():
		return null
	return {"key": key, "path": _PLAYER_PREFABS[key]}


## Saves a custom prefab next to the JSON (`prefabs/<name>.tscn`) with all
## its external resources — scripts, shaders, materials — embedded, so the
## script folder is self-contained and the player can load it from disk.
## A prefab with no external dependencies is copied byte-for-byte: re-saving
## under --headless would drop data the dummy renderer doesn't keep (e.g.
## MultiMesh instance buffers).
static func _bundle_prefab(src_path: String, out_dir: String):
	var key := src_path.get_file().get_basename()
	var rel := "prefabs/%s.%s" % [key, src_path.get_extension()]
	var dst := out_dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	if ResourceLoader.get_dependencies(src_path).is_empty():
		var copy_err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src_path), dst)
		if copy_err != OK:
			push_error("VJ export: could not copy prefab '%s' to '%s' (error %d)." % [src_path, dst, copy_err])
			return null
		return {"key": key, "path": rel}
	var packed := load(src_path) as PackedScene
	if packed == null:
		push_error("VJ export: could not load prefab '%s'." % src_path)
		return null
	var err := ResourceSaver.save(packed, dst, ResourceSaver.FLAG_BUNDLE_RESOURCES)
	if err != OK:
		push_error("VJ export: could not bundle prefab '%s' to '%s' (error %d)." % [src_path, dst, err])
		return null
	return {"key": key, "path": rel}


static func _find_animation_player(scene) -> AnimationPlayer:
	for child in scene.get_children():
		if child is AnimationPlayer:
			return child
	return null


static func _find_viewer(scene) -> Node3D:
	for child in scene.get_children():
		if child.get_script() == VJViewerScript:
			return child
	return null


# ---------- spawn / despawn ----------

## Walks every time a `visible` key changes something and emits a spawn when
## an object becomes present (it and all its parents visible) and a despawn
## when it stops being — except when its parent goes at the same moment,
## which takes it along in the player. Objects come parents-first, so at a
## shared time a group's spawn precedes its children's.
static func _presence_events(scene: Node, animation: Animation, objects: Array, out_dir: String, shaders: Dictionary) -> Array:
	var vis_tracks: Dictionary = {}  # id -> track index
	var times: Array = [0.0]
	if animation != null:
		for obj in objects:
			var track := animation.find_track(NodePath(obj.path + ":visible"), Animation.TYPE_VALUE)
			if track < 0:
				continue
			vis_tracks[obj.id] = track
			for k in animation.track_get_key_count(track):
				var t := maxf(0.0, animation.track_get_key_time(track, k))
				if not times.has(t):
					times.append(t)
	times.sort()

	var out: Array = []
	var present: Dictionary = {}  # id -> bool, as of the previous time
	for t in times:
		var now: Dictionary = {}
		for obj in objects:
			var parent_here: bool = obj.parent == null or now[obj.parent.id]
			var here := parent_here and _visible_at(animation, vis_tracks.get(obj.id, -1), obj.node, t)
			var was: bool = present.get(obj.id, false)
			if here and not was:
				out.append(_make_spawn_event(obj, t, out_dir, shaders))
			elif was and not here and parent_here:
				out.append({"type": "event", "t": t, "action": "despawn", "target": obj.id})
			now[obj.id] = here
		present = now
	return out


## The node's visibility at `t`: its last `visible` key at or before `t`,
## or the scene's value before the first key (or without a track).
static func _visible_at(animation: Animation, track: int, node: Node3D, t: float) -> bool:
	var v := node.visible
	if track < 0:
		return v
	for k in animation.track_get_key_count(track):
		if animation.track_get_key_time(track, k) > t:
			break
		v = bool(animation.track_get_key_value(track, k))
	return v


static func _make_spawn_event(obj: _Obj, t: float, out_dir: String, shaders: Dictionary) -> Dictionary:
	var ev := {
		"type": "event",
		"t": t,
		"action": "spawn",
		"id": obj.id,
		"prefab": obj.prefab_key,
		"transform": _transform_to_dict(obj.node.transform),
	}
	if obj.parent != null:
		ev["parent"] = obj.parent.id
	var cfg := _config_for(obj.node, out_dir, shaders)
	if not cfg.is_empty():
		ev["config"] = cfg
	return ev


# ---------- track conversion ----------

static func _tracks_from_animation(scene: Node, animation: Animation, objects: Array) -> Array:
	var out: Array = []
	var by_path: Dictionary = {}
	for obj in objects:
		by_path[obj.path] = obj

	# property path String -> {obj, node, slot, path, comps: {component -> track}}
	var bezier_groups: Dictionary = {}
	for i in animation.get_track_count():
		var type := animation.track_get_type(i)
		if type != Animation.TYPE_VALUE and type != Animation.TYPE_BEZIER:
			continue
		var path: NodePath = animation.track_get_path(i)
		var names: Array = []
		for n in path.get_name_count():
			names.append(String(path.get_name(n)))
		var obj: _Obj = by_path.get("/".join(names))
		var node: Node = obj.node if obj != null else null
		var slot := ""
		if obj == null and names.size() > 1:
			# A VJEffect or VJVertexEffect under a screen or layer: its
			# params go to the parent's `effect<N>` / `vertex<N>` slot.
			obj = by_path.get("/".join(names.slice(0, -1)))
			node = scene.get_node_or_null(NodePath("/".join(names)))
			if obj == null or node == null:
				continue
			var index := -1
			if node.get_script() == VJEffectScript and obj.node.has_method("effect_nodes"):
				index = obj.node.call("effect_nodes").find(node)
				slot = "effect%d" % index
			elif node.get_script() == VJVertexEffectScript and obj.node.has_method("vertex_effect_nodes"):
				index = obj.node.call("vertex_effect_nodes").find(node)
				slot = "vertex%d" % index
			if index < 0:
				continue  # disabled, no shader, or not an effect: not exported
		if obj == null:
			continue
		if path.get_subname_count() == 0:
			push_warning("VJ export: track '%s' must target a property — skipped." % path)
			continue
		if type == Animation.TYPE_VALUE:
			_route_track(out, obj, slot, path, _value_track_keys(animation, i))
			continue
		# Bezier tracks animate one float each; a vector's or colour's
		# components (`position:x`, `glow_tint:r`) are regrouped into the
		# property and exported together.
		var split := BezierTracksScript.split_component(node, path)
		var prop_path: NodePath = split[0]
		var group: Dictionary = bezier_groups.get(String(prop_path), {})
		if group.is_empty():
			group = {"obj": obj, "node": node, "slot": slot, "path": prop_path, "comps": {}}
			bezier_groups[String(prop_path)] = group
		group.comps[split[1]] = i
	for group in bezier_groups.values():
		_route_track(out, group.obj, group.slot, group.path, _bezier_keys(animation, group.node, group.path, group.comps))
	return out


## `slot` "effect<N>" / "vertex<N>": the track animates that effect (a
## VJEffect / VJVertexEffect child of `obj`); only its params export.
static func _route_track(out: Array, obj: _Obj, slot: String, path: NodePath, keys: Array) -> void:
	if slot == "":
		_append_track(out, obj, path, keys)
		return
	var first := String(path.get_subname(0))
	if slot.begins_with("vertex"):
		if not first.begins_with("params/"):
			push_warning("VJ export: only a vertex effect's params/<name> animates ('%s') — skipped." % path)
			return
		out.append(_shader_param_track(keys, "%s.%s" % [obj.id, slot], first.substr("params/".length())))
		return
	var last := String(path.get_subname(path.get_subname_count() - 1))
	if first != "material" or not last.begins_with(_SHADER_PARAM_PREFIX):
		push_warning("VJ export: only an effect's material:shader_parameter/<name> animates ('%s') — skipped." % path)
		return
	out.append(_shader_param_track(keys, "%s.%s" % [obj.id, slot], last.substr(_SHADER_PARAM_PREFIX.length())))


## Routes one animated property of `obj` to its player track. `keys` are
## {t, value, interp?} with the raw Godot values.
static func _append_track(out: Array, obj: _Obj, path: NodePath, keys: Array) -> void:
	var id := obj.id
	var prop := String(path.get_subname(0))
	var mod_slot := _modifier_slot(obj.node, prop)
	if mod_slot != "":
		out.append(_shader_param_track(keys, "%s.%s" % [id, mod_slot], prop, true))
		return
	var last := String(path.get_subname(path.get_subname_count() - 1))
	if last.begins_with(_SHADER_PARAM_PREFIX):
		var slot := "layer" if obj.node.get_script() == VJLayerScript else "surface"
		out.append(_shader_param_track(keys, "%s.%s" % [id, slot], last.substr(_SHADER_PARAM_PREFIX.length())))
		return
	match prop:
		"position":
			out.append(_transform_track(keys, id, "position", false))
		"rotation":
			out.append(_transform_track(keys, id, "rotation_deg", true))
		"scale":
			out.append(_transform_track(keys, id, "scale", false))
		"visible":
			pass  # _presence_events
		_:
			var screen := _is_screen(obj.node)
			if screen and prop in _DISPLAY_PROPS:
				out.append(_shader_param_track(keys, id + ".display", prop))
			elif screen and prop in _SHAPE_PROPS:
				out.append(_shader_param_track(keys, id + ".shape", prop))
			elif screen and prop in _FIXED_PROPS:
				push_warning("VJ export: '%s' on '%s' can't animate (it's picked per spawn) — skipped." % [prop, obj.path])
			else:
				push_warning("VJ export: unsupported animated property '%s' on '%s' — skipped." % [path.get_concatenated_subnames(), obj.path])


static func _transform_track(keys: Array, target: String, channel: String, radians_to_degrees: bool) -> Dictionary:
	var kfs: Array = []
	for key in keys:
		kfs.append(_keyframe(key, _vec3_to_array(key.value, radians_to_degrees), rad_to_deg(1.0) if radians_to_degrees else 1.0))
	return {
		"type": "transform",
		"target": target,
		"channel": channel,
		"keyframes": kfs,
	}


## `with_alpha`: colours keep their alpha (modifiers' flash uses it).
static func _shader_param_track(keys: Array, target: String, param: String, with_alpha: bool = false) -> Dictionary:
	var kfs: Array = []
	for key in keys:
		kfs.append(_keyframe(key, _value_to_json(key.value, with_alpha)))
	return {
		"type": "shader_param",
		"target": target,
		"param": param,
		"keyframes": kfs,
	}


## `dv_scale`: what the value was scaled by (bezier handles follow).
static func _keyframe(key: Dictionary, value, dv_scale: float = 1.0) -> Dictionary:
	var kf := {"t": float(key.t), "value": value}
	var interp: String = key.get("interp", "linear")
	if interp != "linear":
		kf["interp"] = interp
	for h in ["in", "out"]:
		if key.has(h):
			kf[h] = _handles_to_json(key[h], value, dv_scale)
	return kf


## A value track's keys. They carry the track-level interp so the JSON is
## per-key (matches Interpolation.evaluate's expected shape). Discrete
## tracks hold each value until the next key, i.e. "step".
static func _value_track_keys(animation: Animation, track_idx: int) -> Array:
	var interp := _interp_str(animation.track_get_interpolation_type(track_idx))
	if animation.value_track_get_update_mode(track_idx) == Animation.UPDATE_DISCRETE:
		interp = "step"
	var keys: Array = []
	for k in animation.track_get_key_count(track_idx):
		keys.append({
			"t": animation.track_get_key_time(track_idx, k),
			"value": animation.track_get_key_value(track_idx, k),
			"interp": interp,
		})
	return keys


## A property's bezier tracks (`comps`: component -> track, "" for a plain
## float) as "bezier" keys carrying Godot's handles, one key at every time
## any component has one. A component with no key of its own at such a
## time has its curve split there exactly (de Casteljau), so every curve
## stays the same. Components without a track hold the node's current
## value. Keys are {t, value, interp, in?, out?}, handles Vector2 (dt, dv)
## — an Array of them, by component index, for vector / colour values.
static func _bezier_keys(animation: Animation, node: Node, prop_path: NodePath, comps: Dictionary) -> Array:
	var times: Array = []
	for track in comps.values():
		for k in animation.track_get_key_count(track):
			var t := animation.track_get_key_time(track, k)
			if not times.has(t):
				times.append(t)
	times.sort()
	if times.is_empty():
		return []

	var scalar := comps.has("")
	var base = 0.0 if scalar else node.get_indexed(NodePath(prop_path.get_concatenated_subnames()))
	if base == null:
		base = BezierTracksScript.zero_for_components(comps.keys())
	var names: Array = [""] if scalar else BezierTracksScript.component_names(base)
	# One list per component (by index), each a {v, in, out} per time.
	var per_comp: Array = []
	for c in names:
		if comps.has(c):
			per_comp.append(_bezier_component(animation, comps[c], times))
		else:
			var v := float(base) if scalar else float(base[BezierTracksScript.component_index(c)])
			var flat: Array = []
			for t in times:
				flat.append({"v": v, "in": Vector2.ZERO, "out": Vector2.ZERO})
			per_comp.append(flat)

	var keys: Array = []
	for i in times.size():
		var value = base
		var ins: Array = []
		var outs: Array = []
		for c in names.size():
			var p: Dictionary = per_comp[c][i]
			if scalar:
				value = p.v
			else:
				value[BezierTracksScript.component_index(names[c])] = p.v
			ins.append(p["in"])
			outs.append(p.out)
		keys.append({"t": times[i], "value": value, "in": ins[0] if scalar else ins, "out": outs[0] if scalar else outs})
	# A segment whose handles are all flat is a straight line: plain linear.
	for i in keys.size():
		var curved := i + 1 < keys.size() and not (_flat(keys[i].out) and _flat(keys[i + 1]["in"]))
		keys[i]["interp"] = "bezier" if curved else "linear"
	for i in keys.size():
		if keys[i].interp != "bezier":
			keys[i].erase("out")
		if i == 0 or keys[i - 1].interp != "bezier":
			keys[i].erase("in")
	return keys


## One bezier track's {v, in, out} at each of `times` (a sorted superset of
## its key times). Before its first key and after its last it holds that
## key's value, flat. Times inside a segment split the curve there.
static func _bezier_component(animation: Animation, track: int, times: Array) -> Array:
	var count := animation.track_get_key_count(track)
	var own: Dictionary = {}  # time -> {v, in, out}, absolute handles relative to the key
	for k in count:
		own[animation.track_get_key_time(track, k)] = {
			"v": animation.bezier_track_get_key_value(track, k),
			# Godot never draws the first key's in or the last key's out.
			"in": animation.bezier_track_get_key_in_handle(track, k) if k > 0 else Vector2.ZERO,
			"out": animation.bezier_track_get_key_out_handle(track, k) if k < count - 1 else Vector2.ZERO,
		}
	var first := animation.track_get_key_time(track, 0)
	var last := animation.track_get_key_time(track, count - 1)
	var at: Dictionary = {}  # time -> {v, in, out}
	for k in count - 1:
		var t0 := animation.track_get_key_time(track, k)
		var t1 := animation.track_get_key_time(track, k + 1)
		var a: Dictionary = own[t0]
		var b: Dictionary = own[t1]
		# The segment as absolute control points, cut at each time inside it.
		var p0 := Vector2(t0, a.v)
		var p1: Vector2 = p0 + a.out
		var p3 := Vector2(t1, b.v)
		var p2: Vector2 = p3 + b["in"]
		# The previous segment already wrote this key (its in handle may be cut).
		var start: Dictionary = at.get(t0, {"v": a.v, "in": a["in"], "out": a.out})
		at[t0] = start
		for t in times:
			if t <= t0 or t >= t1:
				continue
			var s := _bezier_param_at(p0, p1, p2, p3, t)
			# de Casteljau: the left part ends at m, the right starts there.
			var q0 := p0.lerp(p1, s)
			var q1 := p1.lerp(p2, s)
			var q2 := p2.lerp(p3, s)
			var r0 := q0.lerp(q1, s)
			var r1 := q1.lerp(q2, s)
			var m := r0.lerp(r1, s)
			start.out = q0 - p0
			start = {"v": m.y, "in": r0 - m, "out": r1 - m}
			at[t] = start
			p0 = m
			p1 = r1
			p2 = q2
		start.out = p1 - p0
		at[t1] = {"v": b.v, "in": p2 - p3, "out": b.out}
	var out: Array = []
	for t in times:
		if at.has(t):
			out.append(at[t])
		else:  # outside the track's keys (or its only key)
			out.append({"v": own[first if t <= first else last].v, "in": Vector2.ZERO, "out": Vector2.ZERO})
	return out


## The curve parameter where the segment's time (x) reaches `t`, by
## bisection (x runs from p0.x to p3.x).
static func _bezier_param_at(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> float:
	var low := 0.0
	var high := 1.0
	for i in 40:
		var middle := (low + high) / 2.0
		if p0.bezier_interpolate(p1, p2, p3, middle).x < t:
			low = middle
		else:
			high = middle
	return (low + high) / 2.0


static func _flat(handles) -> bool:
	if handles is Vector2:
		return handles.is_zero_approx()
	for h in handles:
		if not h.is_zero_approx():
			return false
	return true


## A key's handles as JSON: [dt, dv], or one per element of an array
## `value` (only as many as the value has: colours may drop alpha). `dv`
## scales like the value (radians → degrees).
static func _handles_to_json(handles, value, dv_scale: float):
	if handles is Vector2:
		return [handles.x, handles.y * dv_scale]
	var out: Array = []
	for c in (value.size() if value is Array else handles.size()):
		out.append([handles[c].x, handles[c].y * dv_scale])
	return out


## Every viewer key after t=0 is a cut. With a fade, the event starts half
## the fade early so the jump happens at peak black, on the key's time —
## which is also when the editor preview (the camera itself) jumps. A start
## pose (at t=0) away from the player's home pose is a hard cut at t=0.
static func _viewer_cuts(animation: Animation, viewer: Node3D) -> Array:
	var pos_track := animation.find_track(NodePath("%s:position" % viewer.name), Animation.TYPE_VALUE) if animation != null else -1
	var rot_track := animation.find_track(NodePath("%s:rotation" % viewer.name), Animation.TYPE_VALUE) if animation != null else -1
	var out: Array = []
	var start_pos: Vector3 = animation.value_track_interpolate(pos_track, 0.0) if pos_track >= 0 else viewer.position
	var start_rot: Vector3 = animation.value_track_interpolate(rot_track, 0.0) if rot_track >= 0 else viewer.rotation
	if not start_pos.is_equal_approx(VIEWER_HOME_POSITION) or not start_rot.is_equal_approx(Vector3.ZERO):
		out.append({"type": "event", "t": 0.0, "action": "vr_cut", "to": {
			"position": _vec3_to_array(start_pos, false),
			"rotation_deg": _vec3_to_array(start_rot, true),
		}})
	var times: Array = []
	for track in [pos_track, rot_track]:
		if track < 0:
			continue
		for k in animation.track_get_key_count(track):
			var t := float(animation.track_get_key_time(track, k))
			if t > 0.0 and not times.has(t):
				times.append(t)
	times.sort()

	var fade := float(viewer.fade_duration) if String(viewer.transition) == "fade_to_black" else 0.0
	for t in times:
		var pos: Vector3 = animation.value_track_interpolate(pos_track, t) if pos_track >= 0 else viewer.position
		var rot: Vector3 = animation.value_track_interpolate(rot_track, t) if rot_track >= 0 else viewer.rotation
		var ev := {
			"type": "event",
			"t": maxf(0.0, t - fade * 0.5),
			"action": "vr_cut",
			"to": {
				"position": _vec3_to_array(pos, false),
				"rotation_deg": _vec3_to_array(rot, true),
			},
		}
		if fade > 0.0:
			ev["transition"] = {"type": "fade_to_black", "duration": fade}
		out.append(ev)
	return out


## The viewer's keys as a ride: "$viewer" transform tracks (position,
## rotation_deg) interpolating as the scene's value or Bezier tracks do.
## Keys no more than VIEWER_CUT_GAP apart are a cut (_ride_cuts). Every
## cut, and the first key if after t=0 (a jump from home), gets the
## viewer's transition, which starts at the key. A channel without keys
## holds the rest pose from the first key; with no keys at all, a rest
## pose away from home is a hard cut at t=0.
static func _viewer_ride(animation: Animation, viewer: Node3D) -> Array:
	var channels := {"position": [], "rotation": []}
	if animation != null:
		var bezier := {"position": {}, "rotation": {}}  # prop -> {component -> track}
		for i in animation.get_track_count():
			var path := animation.track_get_path(i)
			if path.get_name_count() != 1 or String(path.get_name(0)) != String(viewer.name) or path.get_subname_count() == 0:
				continue
			var prop := String(path.get_subname(0))
			if not channels.has(prop):
				continue
			match animation.track_get_type(i):
				Animation.TYPE_VALUE:
					channels[prop] = _value_track_keys(animation, i)
				Animation.TYPE_BEZIER:
					bezier[prop][BezierTracksScript.split_component(viewer, path)[1]] = i
		for prop in bezier:
			if not bezier[prop].is_empty():
				channels[prop] = _bezier_keys(animation, viewer, NodePath("%s:%s" % [viewer.name, prop]), bezier[prop])
	if channels.position.is_empty() and channels.rotation.is_empty() \
			and viewer.position.is_equal_approx(VIEWER_HOME_POSITION) and viewer.rotation.is_equal_approx(Vector3.ZERO):
		return []
	var start := INF
	for prop in channels:
		if not channels[prop].is_empty():
			start = minf(start, float(channels[prop][0].t))
	if start == INF:
		start = 0.0
	var cut_times := {}
	if start > 0.0:
		cut_times[start] = true
	for prop in channels:
		var keys: Array = channels[prop]
		if keys.is_empty():
			keys.append({"t": start, "value": viewer.get(prop), "interp": "linear"})
			continue
		_ride_cuts(keys)
		for i in range(1, keys.size()):
			if keys[i - 1].interp == "step":
				cut_times[float(keys[i].t)] = true
	var out := [
		_transform_track(channels.position, VIEWER_TARGET, "position", false),
		_transform_track(channels.rotation, VIEWER_TARGET, "rotation_deg", true),
	]
	if String(viewer.transition) == "fade_to_black" and float(viewer.fade_duration) > 0.0:
		for track in out:
			for kf in track.keyframes:
				if cut_times.has(float(kf.t)):
					kf["transition"] = {"type": "fade_to_black", "duration": float(viewer.fade_duration)}
	return out


## Segments no longer than VIEWER_CUT_GAP become jumps: the key before them
## steps, and when that key only held the one before it (same value, no
## curve between), it goes.
static func _ride_cuts(keys: Array) -> void:
	var i := keys.size() - 2
	while i >= 0:
		if float(keys[i + 1].t) - float(keys[i].t) <= VIEWER_CUT_GAP + 1e-6 and keys[i].interp != "step":
			if i > 0 and keys[i - 1].interp in ["linear", "step"] and _same_value(keys[i - 1].value, keys[i].value):
				keys.remove_at(i)
				i -= 1
			keys[i].interp = "step"
			keys[i].erase("out")
			keys[i + 1].erase("in")
		i -= 1


static func _same_value(a, b) -> bool:
	if a is Vector3 and b is Vector3:
		return a.is_equal_approx(b)
	return a == b


# ---------- config ----------

## An object's spawn config: a screen's or layer's own settings, plus its
## VJObject modifier / reactive fields (non-default ones). Registers the
## shaders it uses in `shaders` (copying custom ones next to the JSON).
static func _config_for(node: Node3D, out_dir: String, shaders: Dictionary) -> Dictionary:
	var cfg := _look_config(node, out_dir, shaders)
	if not node.has_method("modifier_values"):
		return cfg
	var mods := {}
	for field in VJObjectScript.MODIFIER_FIELDS:
		if _modifier_slot(node, field) == "":
			continue  # a screen's opacity: already in cfg
		var v = node.get(field)
		if v != VJObjectScript.Mods.DEFAULTS[field]:
			mods[field] = _value_to_json(v, true)
	if not mods.is_empty():
		cfg["modifiers"] = mods
	var reactive := {}
	for field in VJObjectScript.REACTIVE_FIELDS:
		var v = node.get(field)
		if v != VJObjectScript.Mods.REACTIVE_DEFAULTS[field]:
			reactive[field] = _value_to_json(v)
	if not reactive.is_empty():
		cfg["reactive"] = reactive
	return cfg


## "modifiers" / "reactive" when `prop` is one of the object's VJObject
## fields, else "" (a screen's or layer's opacity is its display fade).
static func _modifier_slot(node: Node, prop: String) -> String:
	if not node.has_method("modifier_values"):
		return ""
	if prop in VJObjectScript.REACTIVE_FIELDS:
		return "reactive"
	if prop in VJObjectScript.MODIFIER_FIELDS:
		var script = node.get_script()
		var is_screen: bool = script == VJScreenScript or script == VJLayerScript
		return "" if is_screen and prop == "opacity" else "modifiers"
	return ""


## A screen's or layer's own settings; {} for anything else.
static func _look_config(node: Node3D, out_dir: String, shaders: Dictionary) -> Dictionary:
	var script = node.get_script()
	if script != VJScreenScript and script != VJLayerScript:
		return {}
	var is_layer: bool = script == VJLayerScript
	var cfg: Dictionary = {}
	var mat: ShaderMaterial = node.call("get_shader_material")
	if is_layer and bool(node.get("video_source")):
		cfg["shader"] = "video"
	elif mat != null and mat.shader != null:
		var key := _register_shader(mat.shader, out_dir, shaders)
		if not key.is_empty():
			cfg["shader"] = key
		# Only authored values travel (no defaults from the shader header).
		var params := _authored_params(mat, _LAYER_INPUTS if is_layer else ["screen_tex"])
		if not params.is_empty():
			cfg["params" if is_layer else "shader_params"] = params
	var rscale: float = float(node.get("render_scale"))
	if rscale != 1.0 and rscale > 0.0:
		cfg["resolution" if is_layer else "render_scale"] = rscale
	var surface: Dictionary = node.call("surface_config")
	if surface.shader != "pillow" or surface.placement != "fixed" \
			or float(surface.params.arc_x) > 0.0 or float(surface.params.arc_y) > 0.0:
		cfg["surface"] = surface
	if float(node.get("opacity")) < 1.0:
		cfg["opacity"] = float(node.get("opacity"))
	var effects := _effects_config(node, out_dir, shaders)
	if not effects.is_empty():
		cfg["effects"] = effects
	var vertex := _vertex_effects_config(node, out_dir, shaders)
	if not vertex.is_empty():
		cfg["vertex_effects"] = vertex
	return cfg


static func _is_screen(node: Node) -> bool:
	var script = node.get_script()
	return script == VJScreenScript or script == VJLayerScript


## The enabled VJVertexEffect children, in order, as `config.vertex_effects`
## (their index is the `vertex<N>` track target). Built-ins go by name
## ("ripple"); other snippets are copied to `shaders/` next to the JSON.
static func _vertex_effects_config(node: Node3D, out_dir: String, shaders: Dictionary) -> Array:
	var out: Array = []
	for v in node.call("vertex_effect_nodes"):
		var src: String = v.effect
		var key := src.get_file().get_basename()
		if not src.begins_with(_VERTEX_ADDON_DIR):
			var rel := "shaders/%s" % src.get_file()
			var dst := out_dir.path_join(rel)
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var f := FileAccess.open(dst, FileAccess.WRITE)
			if f == null:
				push_error("VJ export: could not write vertex effect '%s'." % dst)
				continue
			f.store_string(v.code())
			f.close()
			shaders[key] = rel
		var e := {"shader": key}
		var params: Dictionary = {}
		for k in v.params:
			params[k] = _value_to_json(v.params[k])
		if not params.is_empty():
			e["params"] = params
		out.append(e)
	return out


## The VJEffect children with a shader, in order, as `config.effects`.
## Switched-off ones go along with `"enabled": false` (the player skips
## them); the enabled ones' index among themselves is the `effect<N>`
## track target.
static func _effects_config(node: Node3D, out_dir: String, shaders: Dictionary) -> Array:
	if not node.call("legacy_effects").is_empty():
		push_warning("VJ export: '%s' still has effect_1..4 slots, which no longer export. Run Tools > VJ: Convert effect slots to nodes." % node.name)
	var out: Array = []
	for child in node.get_children():
		if child.get_script() != VJEffectScript or child.material == null or child.material.shader == null:
			continue
		var mat: ShaderMaterial = child.material
		var e := {"shader": _register_shader(mat.shader, out_dir, shaders)}
		var params := _authored_params(mat, ["input_tex", "display_aspect", "picture_rect", "picture_shape", "prepass_tex", "prepass"])
		if not params.is_empty():
			e["params"] = params
		if not child.enabled:
			e["enabled"] = false
		out.append(e)
	return out


## The material's explicitly set `shader_parameter/<name>` values, minus
## `skip`, as JSON values.
static func _authored_params(mat: ShaderMaterial, skip: Array) -> Dictionary:
	var params := {}
	for p in mat.get_property_list():
		var full: String = String(p.get("name", ""))
		if not full.begins_with(_SHADER_PARAM_PREFIX):
			continue
		var short_name := full.substr(_SHADER_PARAM_PREFIX.length())
		if skip.has(short_name):
			continue
		var val = mat.get_shader_parameter(short_name)
		if val == null or val is Object:
			continue
		params[short_name] = _value_to_json(val)
	return params


## The addon's copies of the player's layer / effect shaders map to the
## player's builtin copies; any other shader file is
## copied to `shaders/` next to the JSON, its includes of the addon's
## visualizer files pointed at the player's. Returns the key.
static func _register_shader(shader: Shader, out_dir: String, shaders: Dictionary) -> String:
	var src := shader.resource_path
	if src.is_empty() or src.contains("::"):
		push_warning("VJ export: built-in (unsaved) shaders aren't supported — save the shader to a .gdshader file.")
		return ""
	var key := src.get_file().get_basename()
	if src.begins_with(_VISUALIZER_ADDON_DIR):
		shaders[key] = _VISUALIZER_PLAYER_DIR + src.substr(_VISUALIZER_ADDON_DIR.length())
		return key
	var rel := "shaders/%s" % src.get_file()
	var dst := out_dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		push_error("VJ export: could not write shader '%s'." % dst)
		return ""
	f.store_string(shader.code.replace(_VISUALIZER_ADDON_DIR, _VISUALIZER_PLAYER_DIR))
	f.close()
	shaders[key] = rel
	return key


# ---------- helpers ----------

static func _value_to_json(v, with_alpha: bool = false):
	match typeof(v):
		TYPE_VECTOR2: return [v.x, v.y]
		TYPE_VECTOR3: return [v.x, v.y, v.z]
		TYPE_VECTOR4: return [v.x, v.y, v.z, v.w]
		TYPE_COLOR: return [v.r, v.g, v.b, v.a] if with_alpha else [v.r, v.g, v.b]
		_: return v


static func _transform_to_dict(x: Transform3D) -> Dictionary:
	# Orthonormalized: get_euler() on a scaled basis gives wrong angles.
	var euler := x.basis.orthonormalized().get_euler()
	return {
		"position": [x.origin.x, x.origin.y, x.origin.z],
		"rotation_deg": [rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)],
		"scale": [x.basis.get_scale().x, x.basis.get_scale().y, x.basis.get_scale().z],
	}


static func _vec3_to_array(v, radians_to_degrees: bool) -> Array:
	if v is Vector3:
		if radians_to_degrees:
			return [rad_to_deg(v.x), rad_to_deg(v.y), rad_to_deg(v.z)]
		return [v.x, v.y, v.z]
	if typeof(v) == TYPE_ARRAY and v.size() == 3:
		return [float(v[0]), float(v[1]), float(v[2])]
	return [0.0, 0.0, 0.0]


static func _interp_str(godot_interp: int) -> String:
	match godot_interp:
		Animation.INTERPOLATION_NEAREST: return "step"
		Animation.INTERPOLATION_CUBIC, Animation.INTERPOLATION_CUBIC_ANGLE: return "cubic"
		_: return "linear"


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}
