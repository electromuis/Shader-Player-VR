class_name EditModel
extends RefCounted

## Studio's in-memory copy of a script JSON, and the only way Studio
## changes it. Every edit is a command that knows how to undo itself; the
## undo stack has redo, and a dirty flag. The app turns the document into a
## TimelineData for the runner (timeline()) after each change.
##
## A command is a list of changes, each replacing the value at a path in
## the document ("tracks", 3, "keyframes") with a new one, or removing it.
## Undo puts the old values back in reverse order. Values are deep-copied
## on the way in, so callers can't change the document behind its back.
##
## Saving goes through ScriptFormat's validator. While the document is as
## it was loaded (nothing changed, or everything undone), save writes the
## file's original text back unchanged, so opening and saving a piece never
## rewrites it. After edits it writes JSON with the file's own indentation.
## A v1 script is upgraded to v2 on load (as the player does), and an
## edited one is saved as v2.

## After every command, undo or redo. `structural`: spawn / despawn events
## or spawn configs changed (the runner reconciles which objects exist);
## otherwise only continuous tracks did (the runner re-evaluates them).
signal changed(structural: bool)

## Keys closer than this in time are the same key (set_key replaces it).
const SAME_TIME := 0.0005
## The two effect lists in a config, and their tracks' slot prefixes.
const EFFECTS := "effects"
const VERTEX_EFFECTS := "vertex_effects"
const SLOT_PREFIX := {EFFECTS: ".effect", VERTEX_EFFECTS: ".vertex"}


## The file this came from and saves to.
var path: String = ""

var _doc: Dictionary = {}
var _undo: Array = []  # commands: {label, structural, changes: [{path, had_old, old, has_new, new}]}
var _redo: Array = []
## Undo depth at the last save / at load; -1 once that state can't be
## reached any more (undone past it, then something new was done).
var _saved_depth: int = 0
var _loaded_depth: int = 0
var _original_text: String = ""
## While batch() runs: its commands' changes, gathered into one undo step.
var _batching := false
var _batch_changes: Array = []
var _batch_structural := false
var _indent: String = "  "


## {ok: true, model} or {ok: false, error, errors}.
static func open(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"ok": false, "error": "File not found: %s" % file_path, "errors": ["File not found: %s" % file_path]}
	return from_text(FileAccess.get_file_as_string(file_path), file_path)


## The built-in prefabs a new piece names, so the shelf's objects need no
## new `prefabs` entry.
const BUILTIN_PREFABS := {
	"screen": "res://player/prefabs/screen.tscn",
	"layer": "res://player/prefabs/layer.tscn",
	"cube": "res://player/prefabs/cube.tscn",
	"group": "res://player/prefabs/group.tscn",
}


## What a new piece starts with (Studio uses it): the user's
## `studio_new_piece.json` in the save folder if there is one, else the
## built-in one (a screen showing the video).
const NEW_PIECE_TEMPLATE := "res://studio/new_piece.json"
const USER_TEMPLATE := "studio_new_piece.json"


## The new-piece template ({} if it can't be read): its `meta`, `prefabs`,
## `shaders` and `tracks` go into a new piece.
static func new_piece_template() -> Dictionary:
	for path in [AppPaths.save_path(USER_TEMPLATE), NEW_PIECE_TEMPLATE]:
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
		push_warning("EditModel: %s is not a JSON object" % path)
	return {}


## A new piece for the video at `video_path`: `<video>.json` next to it
## (format 2, the video named relatively, the built-in prefabs named, no
## default screen). With no `template`, no objects: what you add is what
## there is; with one (new_piece_template()), what it holds. It's written
## straight away, so the piece exists from the start. {ok, model} or
## {ok: false, error, errors}.
static func new_piece(video_path: String, template: Dictionary = {}) -> Dictionary:
	var path := video_path.get_basename() + ".json"
	if FileAccess.file_exists(path):
		var err := "%s is already there" % path.get_file()
		return {"ok": false, "error": err, "errors": [err]}
	var doc := {
		"format_version": ScriptFormat.SUPPORTED_VERSION,
		"meta": {
			"title": video_path.get_file().get_basename(),
			"created": Time.get_date_string_from_system(),
			"default_screen": false,
		},
		"media": {"video": video_path.get_file()},
		"prefabs": BUILTIN_PREFABS.duplicate(),
		"shaders": {},
		"tracks": [],
	}
	for key in ["meta", "prefabs", "shaders"]:
		if typeof(template.get(key)) == TYPE_DICTIONARY:
			(doc[key] as Dictionary).merge(template[key], true)
	if typeof(template.get("tracks")) == TYPE_ARRAY:
		doc.tracks = template.tracks.duplicate(true)
	var text := JSON.stringify(doc, "  ", false) + "\n"
	var r := from_text(text, path)
	if not r.ok:
		return r
	var saved: Dictionary = r.model.save()
	if not saved.ok:
		return {"ok": false, "error": saved.error, "errors": [saved.error]}
	return r


static func from_text(text: String, file_path: String = "") -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Not a script JSON: %s" % file_path, "errors": ["Not a script JSON: %s" % file_path]}
	var valid := ScriptFormat.load_from_dict(parsed.duplicate(true), file_path if file_path != "" else "<memory>")
	if not valid.ok:
		return valid
	var m := EditModel.new()
	m.path = file_path
	m._original_text = text
	m._indent = _detect_indent(text)
	ScriptFormat.upgrade(parsed)
	parsed["format_version"] = ScriptFormat.SUPPORTED_VERSION
	m._doc = parsed
	return {"ok": true, "model": m}


## The document, to read. Change it only through the commands below.
func document() -> Dictionary:
	return _doc


## A fresh TimelineData for the runner (its own copy of the document).
func timeline() -> TimelineData:
	var r := ScriptFormat.load_from_dict(_doc.duplicate(true), path if path != "" else "<memory>")
	return r.data if r.ok else null


func is_dirty() -> bool:
	return _undo.size() != _saved_depth


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## What undo / redo would do next ("" if nothing).
func undo_label() -> String:
	return String(_undo.back().label) if can_undo() else ""


func redo_label() -> String:
	return String(_redo.back().label) if can_redo() else ""


## Returns the label of what was undone, "" if nothing was.
func undo() -> String:
	if _undo.is_empty():
		return ""
	var cmd: Dictionary = _undo.pop_back()
	for i in range(cmd.changes.size() - 1, -1, -1):
		var c: Dictionary = cmd.changes[i]
		_put(c.path, c.had_old, c.old)
	_redo.append(cmd)
	changed.emit(cmd.structural)
	return cmd.label


func redo() -> String:
	if _redo.is_empty():
		return ""
	var cmd: Dictionary = _redo.pop_back()
	for c in cmd.changes:
		_put(c.path, c.has_new, c.new)
	_undo.append(cmd)
	changed.emit(cmd.structural)
	return cmd.label


# ---------- saving ----------

## Whether the document is a valid script now ({ok} / {ok: false, error}),
## as save checks it.
func check() -> Dictionary:
	return ScriptFormat.load_from_dict(_doc.duplicate(true), path if path != "" else "<memory>")


## Validate and write the document (to `to_path`, else where it came
## from). {ok: true} or {ok: false, error}.
func save(to_path: String = "") -> Dictionary:
	var target := to_path if to_path != "" else path
	if target == "":
		return {"ok": false, "error": "No file to save to"}
	var valid := ScriptFormat.load_from_dict(_doc.duplicate(true), target)
	if not valid.ok:
		return {"ok": false, "error": "Not saved, the script would be invalid: %s" % valid.error}
	var text := _original_text if _undo.size() == _loaded_depth else to_text()
	# Write next to it, then swap, so a failed write never leaves half a file.
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Could not write %s (error %d)" % [tmp, FileAccess.get_open_error()]}
	f.store_string(text)
	f.close()
	var err := DirAccess.rename_absolute(tmp, target)
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "error": "Could not replace %s (error %d)" % [target, err]}
	if target == path:
		_saved_depth = _undo.size()
	return {"ok": true}


## Replace the whole document with the script in `text` as one undo step
## (restoring an autosave). {ok} or {ok: false, error} (not a valid script;
## nothing changes).
func replace_document(text: String, label: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "not a script JSON"}
	var doc: Dictionary = json.data
	var valid := ScriptFormat.load_from_dict(doc.duplicate(true), path if path != "" else "<memory>")
	if not valid.ok:
		return {"ok": false, "error": valid.error}
	ScriptFormat.upgrade(doc)
	doc["format_version"] = ScriptFormat.SUPPORTED_VERSION
	var changes: Array = []
	for k in _doc:
		if not doc.has(k):
			changes.append(_removal([k]))
	for k in doc:
		# As JSON reads them (the loaded format_version is an int).
		if not _doc.has(k) or JSON.stringify(_as_json(_doc[k])) != JSON.stringify(_as_json(doc[k])):
			changes.append(_change([k], doc[k]))
	return {"ok": _do(label, true, changes)}


## The document as JSON, in the original file's indentation (and with its
## final newline, if it had one). Keys keep their order.
func to_text() -> String:
	var text := JSON.stringify(_doc, _indent, false)
	if _original_text.ends_with("\n"):
		text += "\n"
	return text


static func _detect_indent(text: String) -> String:
	for line in text.split("\n"):
		if line.strip_edges() == "":
			continue
		var n := 0
		while n < line.length() and (line[n] == " " or line[n] == "\t"):
			n += 1
		if n > 0:
			return line.substr(0, n)
	return "  "


# ---------- queries ----------

func tracks() -> Array:
	return _doc.get("tracks", [])


## Ids of every spawned object, in file order (first spawn of each).
func object_ids() -> Array:
	var out: Array = []
	for t in tracks():
		if t.get("type") == "event" and t.get("action") == "spawn" and not out.has(t.get("id")):
			out.append(t.get("id"))
	return out


## Index in tracks() of `id`'s first spawn event, -1 if none.
func spawn_index(id: String) -> int:
	var list := tracks()
	for i in list.size():
		if list[i].get("type") == "event" and list[i].get("action") == "spawn" and list[i].get("id") == id:
			return i
	return -1


## Indices in tracks() of every spawn event of `id` (a piece can bring an
## object back later), in file order.
func spawn_indices(id: String) -> Array:
	var out: Array = []
	var list := tracks()
	for i in list.size():
		if list[i].get("type") == "event" and list[i].get("action") == "spawn" and list[i].get("id") == id:
			out.append(i)
	return out


## The script's camera block as an object: its config is the top-level
## `camera` ({effects: [...]}, the effects running over everything the
## viewer sees), its tracks `$camera.effect<N>`. The effect commands and
## set_config take it as an id.
const CAMERA := ScriptRunner.CAMERA_TARGET


## `id` as undo labels name it: "the camera" for CAMERA, "the viewer".
static func who(id: String) -> String:
	return {CAMERA: "the camera", ScriptFormat.VIEWER: "the viewer"}.get(id, id)


## Whether `id` is something the config and effect commands can change:
## an object that spawns, or CAMERA.
func has_config(id: String) -> bool:
	return id == CAMERA or spawn_index(id) >= 0


## `id`'s spawn config as the file has it (its first spawn's), to read;
## {} if it has none. CAMERA's is the camera block.
func config_of(id: String) -> Dictionary:
	if id == CAMERA:
		var cam = _doc.get("camera")
		return cam if typeof(cam) == TYPE_DICTIONARY else {}
	var i := spawn_index(id)
	var cfg = tracks()[i].get("config") if i >= 0 else null
	return cfg if typeof(cfg) == TYPE_DICTIONARY else {}


## `id`'s effect list (switched-off effects included), to read: its pixel
## effects, or `list` VERTEX_EFFECTS for its vertex effects.
func effects_of(id: String, list: String = EFFECTS) -> Array:
	var effects = config_of(id).get(list)
	return effects if typeof(effects) == TYPE_ARRAY else []


## Effect `i`'s `effect<N>` slot: its place among the switched-on effects
## (what `shader_param` tracks target), -1 if it's off or not there.
static func effect_slot(effects: Array, i: int) -> int:
	if i < 0 or i >= effects.size() or not _effect_on(effects[i]):
		return -1
	var n := 0
	for k in i:
		if _effect_on(effects[k]):
			n += 1
	return n


static func _effect_on(e) -> bool:
	return typeof(e) == TYPE_DICTIONARY and e.get("enabled", true) != false


## The key in `shaders` that names `shader_path`, or "" if none does.
func shader_key_of(shader_path: String) -> String:
	var shaders = _doc.get("shaders", {})
	for k in shaders:
		if shaders[k] == shader_path:
			return k
	return ""


## The transform or shader_param track for `target` and `name` (a channel
## for transforms, a param for shader params), -1 if none.
func find_track(type: String, target: String, name: String) -> int:
	var field := "channel" if type == ScriptFormat.TRACK_TRANSFORM else "param"
	var list := tracks()
	for i in list.size():
		if list[i].get("type") == type and list[i].get("target") == target and list[i].get(field) == name:
			return i
	return -1


# ---------- commands ----------
# Each returns false (and changes nothing) if it doesn't apply.

## Where `id` spawns: {position, rotation_deg, scale}, any subset. Every
## spawn of `id` (a piece can bring an object back later) moves together.
func set_spawn_transform(id: String, transform: Dictionary) -> bool:
	var changes: Array = []
	var list := tracks()
	for i in list.size():
		if list[i].get("type") == "event" and list[i].get("action") == "spawn" and list[i].get("id") == id:
			changes.append(_change(["tracks", i, "transform"], transform))
	if changes.is_empty():
		return false
	return _do("Move %s" % id, true, changes)


## Replace track `ti`'s keys (e.g. a path shifted as a whole).
func set_keyframes(ti: int, kfs: Array, label: String = "") -> bool:
	if _keyframes(ti) == null or kfs.is_empty():
		return false
	var track: Dictionary = tracks()[ti]
	if label == "":
		label = "Edit %s %s" % [track.get("target", ""), track.get("channel", track.get("param", ""))]
	return _do(label, _is_structural_track(track), [_change(["tracks", ti, "keyframes"], kfs)])


## A value in `id`'s spawn config: `key` is a field ("opacity") or a path
## into it (["modifiers", "tint"], ["effects", 1, "params", "radius"]). A
## null value removes it. Every spawn of `id` that has the same value there
## as the first spawn changes with it (an object that comes back later is
## the same object); one that was given a value of its own keeps it.
func set_config(id: String, key, value, label: String = "") -> bool:
	var keys: Array = key if typeof(key) == TYPE_ARRAY else [key]
	var changes = _config_changes(id, keys, value)
	if changes == null:
		return false
	if label == "":
		label = "Set %s %s" % [who(id), ".".join(keys.map(func(k): return str(k)))]
	return _do(label, true, changes)


## set_config's changes, or null if it doesn't apply.
func _config_changes(id: String, keys: Array, value):
	if id == CAMERA:
		var c = _config_change_at(["camera"], keys, value) if not keys.is_empty() else null
		return [c] if c != null else null
	var spawns := spawn_indices(id)
	if spawns.is_empty() or keys.is_empty():
		return null
	var first := JSON.stringify(_value_at(["tracks", spawns[0], "config"] + keys))
	var changes: Array = []
	for i in spawns:
		if i != spawns[0] and JSON.stringify(_value_at(["tracks", i, "config"] + keys)) != first:
			continue
		var c = _config_change(i, keys, value)
		if c == null:
			if i == spawns[0]:
				return null
			continue
		changes.append(c)
	return changes


## The change that puts `value` at `keys` in spawn `i`'s config (null:
## removes it), or null if it can't (an array index that isn't there).
## Missing parent objects are made: then the whole config is replaced.
func _config_change(i: int, keys: Array, value):
	return _config_change_at(["tracks", i, "config"], keys, value)


## _config_change for the config at `root` (a path into the document).
func _config_change_at(root: Array, keys: Array, value):
	var p: Array = root.duplicate()
	var node = _value_at(p)
	var whole := typeof(node) != TYPE_DICTIONARY
	if not whole:
		for k in keys.slice(0, keys.size() - 1):
			var child = _value_at(p + [k])
			if typeof(child) != TYPE_DICTIONARY and typeof(child) != TYPE_ARRAY:
				whole = true
				break
			p = p + [k]
			node = child
	if not whole:
		if typeof(node) == TYPE_ARRAY and not _has_path(p + [keys.back()]):
			return null
		p = p + [keys.back()]
		return _change(p, value) if value != null else _removal(p)
	if value == null:
		return null  # nothing there to remove
	var cfg = _value_at(root)
	cfg = cfg.duplicate(true) if typeof(cfg) == TYPE_DICTIONARY else {}
	var at = cfg
	for k in keys.slice(0, keys.size() - 1):
		if typeof(at) == TYPE_ARRAY:
			if typeof(k) != TYPE_INT or k < 0 or k >= at.size() or typeof(at[k]) not in [TYPE_DICTIONARY, TYPE_ARRAY]:
				return null
		elif typeof(at.get(k)) not in [TYPE_DICTIONARY, TYPE_ARRAY]:
			at[k] = {}
		at = at[k]
	if typeof(at) == TYPE_ARRAY:
		return null
	at[keys.back()] = value
	return _change(root, cfg)


# ---------- the effects stack ----------
# Two lists work the same way: `effects` (pixel effects, EFFECTS) and
# `vertex_effects` (VERTEX_EFFECTS, tracks on `<id>.vertex<N>`); each
# command takes the list, pixel effects by default.
# Effects are addressed by their place in the list (switched-off ones
# included). Tracks address the switched-on ones by `<id>.effect<N>`, so
# every change here renumbers them to follow their effect. A switched-off
# effect keeps its tracks inside its entry ("tracks": [{param, keyframes,
# ...}]; the player skips it whole), and switching it back on puts them
# back. Removing an effect removes its tracks. Every spawn of the object
# with the same effect list as the first changes with it.

## Add the effect at `shader_path` to `id`'s list (at `at`, else the end),
## naming it in `shaders` if nothing does yet (a built-in vertex effect goes
## by its name, "ripple", and needs none).
func add_effect(id: String, shader_path: String, params: Dictionary = {}, at: int = -1, list: String = EFFECTS) -> bool:
	if shader_path == "" or not has_config(id) or (id == CAMERA and list != EFFECTS):
		return false
	var extra: Array = []
	var key := geometry_name(shader_path)
	if key == "":
		key = _shader_key_for(shader_path, extra)
	var entries := _effect_entries(id, list)
	if at < 0 or at > entries.size():
		at = entries.size()
	entries.insert(at, [-1, {"shader": key, "params": params}])
	return _rework_effects(id, "Add %s to %s" % [key, who(id)], entries, extra, list)


## Move effect `from` to place `to` in the list.
func move_effect(id: String, from: int, to: int, list: String = EFFECTS) -> bool:
	var entries := _effect_entries(id, list)
	if from < 0 or from >= entries.size() or to < 0 or to >= entries.size() or from == to:
		return false
	var e = entries.pop_at(from)
	entries.insert(to, e)
	return _rework_effects(id, "Move %s's %s %s" % [who(id), e[1].get("shader", "effect"), "up" if to < from else "down"], entries, [], list)


func set_effect_enabled(id: String, i: int, on: bool, list: String = EFFECTS) -> bool:
	var entries := _effect_entries(id, list)
	if i < 0 or i >= entries.size() or _effect_on(entries[i][1]) == on:
		return false
	_set_on(entries[i][1], on)
	return _rework_effects(id, "Turn %s's %s %s" % [who(id), entries[i][1].get("shader", "effect"), "on" if on else "off"], entries, [], list)


## The master switch: every effect of the list on, or off, as one step.
func set_all_effects_enabled(id: String, on: bool, list: String = EFFECTS) -> bool:
	var entries := _effect_entries(id, list)
	if entries.all(func(e): return _effect_on(e[1]) == on):
		return false
	for e in entries:
		_set_on(e[1], on)
	return _rework_effects(id, "Turn %s's %s %s" % [who(id), "vertex effects" if list == VERTEX_EFFECTS else "effects",
			"on" if on else "off"], entries, [], list)


static func _set_on(entry: Dictionary, on: bool) -> void:
	if on:
		entry.erase("enabled")
	else:
		entry["enabled"] = false


## Remove effect `i` (and its tracks).
func remove_effect(id: String, i: int, list: String = EFFECTS) -> bool:
	var entries := _effect_entries(id, list)
	if i < 0 or i >= entries.size():
		return false
	var e = entries.pop_at(i)
	return _rework_effects(id, "Remove %s's %s" % [who(id), e[1].get("shader", "effect")], entries, [], list)


## A built-in surface's or vertex effect's script name ("ripple") for its
## path, "" for anything else.
static func geometry_name(shader_path: String) -> String:
	for n in ScreenGeometry.BUILTIN_NAMES:
		if ScreenGeometry.BUILTIN_NAMES[n] == shader_path:
			return n
	return ""


## [[index in the current list, a copy of the entry]] for `id`'s effects.
func _effect_entries(id: String, list: String = EFFECTS) -> Array:
	var out: Array = []
	var effects := effects_of(id, list)
	for i in effects.size():
		out.append([i, effects[i].duplicate(true) if typeof(effects[i]) == TYPE_DICTIONARY else {}])
	return out


## One command: `id`'s effect list becomes `entries` ([[old index or -1
## for a new effect, entry]]), its effect tracks renumbered, parked or
## unparked to match, plus `extra` changes.
func _rework_effects(id: String, label: String, entries: Array, extra: Array = [], list: String = EFFECTS) -> bool:
	var spawns := spawn_indices(id)
	if spawns.is_empty() and id != CAMERA:
		return false
	var old := effects_of(id, list)
	var old_json := JSON.stringify(old)
	var new_list: Array = entries.map(func(e): return e[1])
	var index_of_slot := {}  # old slot N -> old index
	for i in old.size():
		var n := effect_slot(old, i)
		if n >= 0:
			index_of_slot[n] = i
	var new_of_old := {}  # old index -> new index
	for j in entries.size():
		if entries[j][0] >= 0:
			new_of_old[entries[j][0]] = j
	var prefix: String = id + SLOT_PREFIX[list]
	var out: Array = []
	for t in tracks():
		var target := String(t.get("target", ""))
		if t.get("type") == ScriptFormat.TRACK_SHADER_PARAM and target.begins_with(prefix) \
				and target.substr(prefix.length()).is_valid_int() and index_of_slot.has(int(target.substr(prefix.length()))):
			var i: int = index_of_slot[int(target.substr(prefix.length()))]
			if not new_of_old.has(i):
				continue  # its effect is gone
			var j: int = new_of_old[i]
			var slot := effect_slot(new_list, j)
			var moved: Dictionary = t.duplicate(true)
			if slot < 0:  # switched off: the effect keeps it
				moved.erase("type")
				moved.erase("target")
				var parked: Array = new_list[j].get("tracks", [])
				parked.append(moved)
				new_list[j]["tracks"] = parked
				continue
			moved["target"] = prefix + str(slot)
			out.append(moved)
		else:
			out.append(t)  # spawn events get the new list below, once it's final
	for j in new_list.size():
		var slot := effect_slot(new_list, j)
		if slot >= 0 and new_list[j].has("tracks"):
			for parked in new_list[j]["tracks"]:
				var back := {"type": ScriptFormat.TRACK_SHADER_PARAM, "target": prefix + str(slot)}
				back.merge(parked)
				out.append(back)
			new_list[j].erase("tracks")
	if id == CAMERA:
		var cam := config_of(CAMERA).duplicate(true)
		if new_list.is_empty():
			cam.erase(list)
		else:
			cam[list] = new_list
		var block := _change(["camera"], cam) if not cam.is_empty() else _removal(["camera"])
		return _do(label, true, extra + [_change(["tracks"], out), block])
	var first: Dictionary = tracks()[spawns[0]]
	for k in out.size():
		var t: Dictionary = out[k]
		if t.get("type") == "event" and t.get("action") == "spawn" and t.get("id") == id \
				and (is_same(t, first) or JSON.stringify(_effects_in(t, list)) == old_json):
			var ev: Dictionary = t.duplicate(true)
			var cfg: Dictionary = ev.get("config", {}) if typeof(ev.get("config")) == TYPE_DICTIONARY else {}
			if new_list.is_empty():
				cfg.erase(list)
			else:
				cfg[list] = new_list.duplicate(true)
			ev["config"] = cfg
			out[k] = ev
	return _do(label, true, extra + [_change(["tracks"], out)])


static func _effects_in(spawn: Dictionary, list: String = EFFECTS) -> Array:
	var cfg = spawn.get("config")
	var effects = cfg.get(list) if typeof(cfg) == TYPE_DICTIONARY else null
	return effects if typeof(effects) == TYPE_ARRAY else []


## A layer's shader (its `shader` config), naming the file in `shaders` if
## nothing does yet. Its params stay (a shader that doesn't have them
## ignores them).
func set_shader(id: String, shader_path: String) -> bool:
	if shader_path == "" or spawn_index(id) < 0:
		return false
	var changes: Array = []
	var key := _shader_key_for(shader_path, changes)
	var config = _config_changes(id, ["shader"], key)
	if config == null:
		return false
	return _do("Set %s's shader to %s" % [id, key], true, changes + config)


## The `shaders` key for `shader_path`; when there's none yet, a new one,
## and the change that adds it goes on `changes`.
func _shader_key_for(shader_path: String, changes: Array) -> String:
	var key := shader_key_of(shader_path)
	if key != "":
		return key
	key = _new_shader_key(shader_path.get_file().get_basename().trim_prefix(CameraFxShaders.BUILTIN_PREFIX))
	var shaders = _doc.get("shaders", {})
	shaders = shaders.duplicate() if typeof(shaders) == TYPE_DICTIONARY else {}
	shaders[key] = shader_path
	changes.append(_change(["shaders"], shaders))
	return key


## A `shaders` key made from `base` that isn't taken.
func _new_shader_key(base: String) -> String:
	return _free_key(_doc.get("shaders", {}), base if base != "" else "effect")


## `base`, or base_2, base_3, ...: the first that isn't a key of `taken`.
static func _free_key(taken, base: String) -> String:
	var key := base
	var n := 2
	while typeof(taken) == TYPE_DICTIONARY and taken.has(key):
		key = "%s_%d" % [base, n]
		n += 1
	return key


## The `shaders` key for `shader_path`, naming it (one undoable step) if
## nothing does yet.
func name_shader(shader_path: String) -> String:
	var changes: Array = []
	var key := _shader_key_for(shader_path, changes)
	if not changes.is_empty():
		_do("Name shader %s" % key, true, changes)
	return key


## The `prefabs` key for `prefab_path`, naming it (one undoable step) after
## its file if nothing does yet.
func name_prefab(prefab_path: String) -> String:
	var prefabs = _doc.get("prefabs", {})
	prefabs = prefabs.duplicate() if typeof(prefabs) == TYPE_DICTIONARY else {}
	for k in prefabs:
		if prefabs[k] == prefab_path:
			return k
	var key := _free_key(prefabs, prefab_path.get_file().get_basename())
	prefabs[key] = prefab_path
	_do("Name prefab %s" % key, true, [_change(["prefabs"], prefabs)])
	return key


## An object id made from `base` that no object has yet.
func free_id(base: String) -> String:
	var taken := {}
	for id in object_ids():
		taken[id] = true
	return _free_key(taken, base if base != "" else "object")


## A key at `t` on the `type` track of `target` / `name` (made if there's
## none); it replaces a key at the same time. `interp` "" keeps the
## replaced key's (or leaves it out, which is linear).
func set_key(type: String, target: String, name: String, t: float, value, interp: String = "") -> bool:
	if type != ScriptFormat.TRACK_TRANSFORM and type != ScriptFormat.TRACK_SHADER_PARAM:
		return false
	if interp != "" and not ScriptFormat.INTERP_MODES.has(interp):
		return false
	if type == ScriptFormat.TRACK_TRANSFORM and (typeof(value) != TYPE_ARRAY or value.size() != 3):
		return false
	var key := {"t": t, "value": value}
	var ti := find_track(type, target, name)
	var label := "Key %s %s at %s" % [target, name, _time_label(t)]
	if ti < 0:
		if interp != "":
			key["interp"] = interp
		var track := {"type": type, "target": target}
		track["channel" if type == ScriptFormat.TRACK_TRANSFORM else "param"] = name
		track["keyframes"] = [key]
		var list := tracks().duplicate()
		list.append(track)
		return _do(label, _is_structural_track(track), [_change(["tracks"], list)])
	var track: Dictionary = tracks()[ti]
	var kfs: Array = track.get("keyframes", []).duplicate(true)
	var at := _key_at(kfs, t)
	if at >= 0:
		var same_shape: bool = typeof(kfs[at].get("value")) == typeof(value) \
				and (typeof(value) != TYPE_ARRAY or kfs[at].get("value").size() == value.size())
		for k in kfs[at]:
			if k in ["t", "value"] or (k in ["in", "out"] and not same_shape):
				continue
			key[k] = kfs[at][k]  # interp, bezier handles, anything else it carried
		kfs[at] = key
	else:
		kfs.insert(_insert_index(kfs, t), key)
	if interp != "":
		key["interp"] = interp
	return _do(label, _is_structural_track(track), [_change(["tracks", ti, "keyframes"], kfs)])


## A recorded take: the keys of the `type` track of `target` / `name` from
## `t0` to `t1` become `keys` ([{t, value, ...}], inside that range); the
## keys either side stay, and the curve joins them up. The track is made
## if there's none.
func replace_keys(type: String, target: String, name: String, t0: float, t1: float, keys: Array, label: String = "") -> bool:
	if keys.is_empty() or (type != ScriptFormat.TRACK_TRANSFORM and type != ScriptFormat.TRACK_SHADER_PARAM):
		return false
	if label == "":
		label = "Record %s %s" % [target, name]
	var ti := find_track(type, target, name)
	if ti < 0:
		var track := {"type": type, "target": target}
		track["channel" if type == ScriptFormat.TRACK_TRANSFORM else "param"] = name
		track["keyframes"] = keys
		var list := tracks().duplicate()
		list.append(track)
		return _do(label, _is_structural_track(track), [_change(["tracks"], list)])
	var kfs: Array = tracks()[ti].get("keyframes", []).filter(func(k):
		var t := float(k.get("t", 0.0))
		return t < t0 - SAME_TIME or t > t1 + SAME_TIME)
	for k in keys:
		kfs.insert(_insert_index(kfs, float(k.t)), k)
	return _do(label, _is_structural_track(tracks()[ti]), [_change(["tracks", ti, "keyframes"], kfs)])


## The viewer at `t`: its eye at `position` ([x, y, z]) facing `yaw` (°), on
## the "$viewer" track. The viewer glides into it from the key before; with
## `cut`, it jumps there instead (the key before holds: its segment becomes
## a step) through `transition` ({} = at once). One undo step.
func key_viewer(t: float, position: Array, yaw: float, cut: bool = false, transition: Dictionary = {}) -> bool:
	var label := "%s at %s" % ["Cut the viewer to here" if cut else "Key the viewer", _time_label(t)]
	return batch(label, func():
		for ch in ["position", "rotation_deg"]:
			var value: Array = position if ch == "position" else [0.0, yaw, 0.0]
			set_key(ScriptFormat.TRACK_TRANSFORM, ScriptFormat.VIEWER, ch, t, value)
			var ti := find_track(ScriptFormat.TRACK_TRANSFORM, ScriptFormat.VIEWER, ch)
			var kfs: Array = tracks()[ti].keyframes.duplicate(true)
			var at := _key_at(kfs, t)
			if cut:
				if at > 0:
					kfs[at - 1]["interp"] = "step"
					kfs[at - 1].erase("out")
					kfs[at].erase("in")
				if not transition.is_empty():
					kfs[at]["transition"] = transition
				else:
					kfs[at].erase("transition")
			else:
				kfs[at].erase("transition")
				if at > 0 and String(kfs[at - 1].get("interp", "")) == "step":
					kfs[at - 1].erase("interp")  # glide into it, not jump
			set_keyframes(ti, kfs))


## The piece's beat grid (`media.beats`: {bpm, offset, beats_per_bar}); null
## removes it (the player detects one from the sound again).
func set_beats(grid, label: String = "") -> bool:
	var media = _doc.get("media", {})
	media = media.duplicate(true) if typeof(media) == TYPE_DICTIONARY else {}
	if grid == null:
		media.erase("beats")
	else:
		media["beats"] = grid
	return _do(label if label != "" else "Set the beat grid", false, [_change(["media"], media)])


## Retime key `ki` of track `ti` to `new_t` (it replaces a key already there).
func move_key(ti: int, ki: int, new_t: float) -> bool:
	var kfs = _keyframes(ti)
	if kfs == null or ki < 0 or ki >= kfs.size():
		return false
	kfs = kfs.duplicate(true)
	var key: Dictionary = kfs[ki]
	kfs.remove_at(ki)
	var clash := _key_at(kfs, new_t)
	if clash >= 0:
		kfs.remove_at(clash)
	key["t"] = new_t
	kfs.insert(_insert_index(kfs, new_t), key)
	var track: Dictionary = tracks()[ti]
	return _do("Move key to %s" % _time_label(new_t), _is_structural_track(track), [_change(["tracks", ti, "keyframes"], kfs)])


## Bezier presets for set_key_interp: the segment's handles as fractions of
## its time and value change, like CSS cubic-bezier(x1, y1, x2, y2).
const BEZIER_PRESETS := {
	"ease_in": [0.42, 0.0, 1.0, 1.0],
	"ease_out": [0.0, 0.0, 0.58, 1.0],
	"ease_in_out": [0.42, 0.0, 0.58, 1.0],
	"overshoot": [0.34, 1.56, 0.64, 1.0],
}


## How the segment after key `ki` of track `ti` moves: one of
## ScriptFormat.INTERP_MODES ("linear" drops the field), or a BEZIER_PRESETS
## name, which makes it "bezier" with that curve's handles (the key's `out`
## and the next key's `in`). Leaving bezier drops those handles.
func set_key_interp(ti: int, ki: int, mode: String) -> bool:
	var kfs = _keyframes(ti)
	if kfs == null or ki < 0 or ki >= kfs.size():
		return false
	var preset: Array = BEZIER_PRESETS.get(mode, [])
	if preset.is_empty() and not ScriptFormat.INTERP_MODES.has(mode):
		return false
	kfs = kfs.duplicate(true)
	var key: Dictionary = kfs[ki]
	var next = kfs[ki + 1] if ki + 1 < kfs.size() else null
	if mode == "linear":
		key.erase("interp")
	else:
		key["interp"] = "bezier" if not preset.is_empty() else mode
	if not preset.is_empty() and next != null:
		var dt := float(next.get("t", 0.0)) - float(key.get("t", 0.0))
		var a = key.get("value")
		var b = next.get("value")
		if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY and a.size() == b.size():
			var outs: Array = []
			var ins: Array = []
			for c in a.size():
				var dv := float(b[c]) - float(a[c])
				outs.append([preset[0] * dt, preset[1] * dv])
				ins.append([(preset[2] - 1.0) * dt, (preset[3] - 1.0) * dv])
			key["out"] = outs
			next["in"] = ins
		elif typeof(a) in [TYPE_FLOAT, TYPE_INT] and typeof(b) in [TYPE_FLOAT, TYPE_INT]:
			var dv := float(b) - float(a)
			key["out"] = [preset[0] * dt, preset[1] * dv]
			next["in"] = [(preset[2] - 1.0) * dt, (preset[3] - 1.0) * dv]
	elif preset.is_empty() and mode != "bezier":
		key.erase("out")
		if next != null:
			next.erase("in")
	var track: Dictionary = tracks()[ti]
	var label := "%s at %s" % [mode.capitalize(), _time_label(float(key.get("t", 0.0)))]
	return _do(label, _is_structural_track(track), [_change(["tracks", ti, "keyframes"], kfs)])


## Remove key `ki` of track `ti`; the last one takes its track with it.
func delete_key(ti: int, ki: int) -> bool:
	var kfs = _keyframes(ti)
	if kfs == null or ki < 0 or ki >= kfs.size():
		return false
	var track: Dictionary = tracks()[ti]
	var label := "Delete key at %s" % _time_label(float(kfs[ki].get("t", 0.0)))
	if kfs.size() == 1:
		var list := tracks().duplicate()
		list.remove_at(ti)
		return _do(label, _is_structural_track(track), [_change(["tracks"], list)])
	kfs = kfs.duplicate(true)
	kfs.remove_at(ki)
	return _do(label, _is_structural_track(track), [_change(["tracks", ti, "keyframes"], kfs)])


## Replace `id`'s spawn config whole ({} removes it): every spawn of it
## with the same config as its first. When the switched-on effects (or
## vertex effects) change, their tracks (`<id>.effect<N>`, `.vertex<N>`)
## go: the effects they animated aren't there any more.
func replace_config(id: String, cfg: Dictionary, label: String = "") -> bool:
	var spawns := spawn_indices(id)
	if spawns.is_empty():
		return false
	var old := config_of(id)
	var first := JSON.stringify(_value_at(["tracks", spawns[0], "config"]))
	var list := tracks().duplicate()
	for i in spawns:
		if JSON.stringify(_value_at(["tracks", i, "config"])) != first:
			continue
		var ev: Dictionary = list[i].duplicate()
		if cfg.is_empty():
			ev.erase("config")
		else:
			ev["config"] = _as_json(cfg)
		list[i] = ev
	var gone: Array = []
	for list_key in ["effects", "vertex_effects"]:
		if _switched_on_shaders(old, list_key) != _switched_on_shaders(cfg, list_key):
			gone.append("%s.%s" % [id, "effect" if list_key == "effects" else "vertex"])
	list = list.filter(func(t):
		if t.get("type") != ScriptFormat.TRACK_SHADER_PARAM:
			return true
		var target := String(t.get("target", ""))
		for prefix in gone:
			if target.begins_with(prefix) and target.substr(prefix.length()).is_valid_int():
				return false
		return true)
	return _do(label if label != "" else "Set %s's look" % id, true, [_change(["tracks"], list)])


static func _switched_on_shaders(cfg: Dictionary, list_key: String) -> Array:
	var list = cfg.get(list_key)
	if typeof(list) != TYPE_ARRAY:
		return []
	return list.filter(func(e): return _effect_on(e)).map(func(e): return String(e.get("shader", "")))


## Add an object: `spawn` is a spawn event without "type" / "action"
## (id, prefab, t, transform, config, parent). Its prefab key must exist.
## With `despawn_at`, a despawn event goes with it.
func add_object(spawn: Dictionary, despawn_at = null) -> bool:
	var id := String(spawn.get("id", ""))
	if id == "" or id.begins_with("$") or spawn_index(id) >= 0:
		return false
	if not _doc.get("prefabs", {}).has(spawn.get("prefab", "")):
		return false
	var ev := {"type": "event", "t": float(spawn.get("t", 0.0)), "action": "spawn"}
	for k in spawn:
		if k not in ["type", "action", "t"]:
			ev[k] = spawn[k]
	var list := tracks().duplicate()
	list.append(ev)
	if despawn_at != null:
		list.append({"type": "event", "t": float(despawn_at), "action": "despawn", "target": id})
	return _do("Add %s" % id, true, [_change(["tracks"], list)])


## Remove an object: its spawn / despawn events and tracks, and the same
## for the objects inside it.
func remove_object(id: String) -> bool:
	if spawn_index(id) < 0:
		return false
	var gone := {id: true}
	var grew := true
	while grew:  # children, grandchildren, ...
		grew = false
		for t in tracks():
			if t.get("action") == "spawn" and gone.has(t.get("parent", "")) and not gone.has(t.get("id")):
				gone[t.get("id")] = true
				grew = true
	var list := tracks().filter(func(t): return not _belongs_to(t, gone))
	return _do("Remove %s" % id, true, [_change(["tracks"], list)])


## When an object comes on: spawn event `ti` moves to `t`. Objects spawned
## inside it at the same moment (a group's children) move with it, so they
## never arrive before their parent.
func set_spawn_time(ti: int, t: float) -> bool:
	var list := tracks()
	if ti < 0 or ti >= list.size() or list[ti].get("type") != "event" or list[ti].get("action") != "spawn":
		return false
	var old := float(list[ti].get("t", 0.0))
	var changes: Array = []
	var moving := [ti]
	while not moving.is_empty():
		var i: int = moving.pop_back()
		changes.append(_change(["tracks", i, "t"], t))
		var id = list[i].get("id")
		for k in list.size():
			var e: Dictionary = list[k]
			if e.get("action") == "spawn" and e.get("parent") == id and absf(float(e.get("t", 0.0)) - old) < SAME_TIME:
				moving.append(k)
	return _do("%s comes on at %s" % [list[ti].get("id", ""), _time_label(t)], true, changes)


## When an object goes: despawn event `ti` moves to `t`.
func set_despawn_time(ti: int, t: float) -> bool:
	var list := tracks()
	if ti < 0 or ti >= list.size() or list[ti].get("type") != "event" or list[ti].get("action") != "despawn":
		return false
	return _do("%s goes at %s" % [list[ti].get("target", ""), _time_label(t)], true, [_change(["tracks", ti, "t"], t)])


## `id` goes at `t` (a new despawn event).
func add_despawn(id: String, t: float) -> bool:
	if spawn_index(id) < 0:
		return false
	var list := tracks().duplicate()
	list.append({"type": "event", "t": t, "action": "despawn", "target": id})
	return _do("%s goes at %s" % [id, _time_label(t)], true, [_change(["tracks"], list)])


## Remove despawn event `ti`: the object stays on (to its next despawn or
## the end).
func remove_despawn(ti: int) -> bool:
	var list := tracks()
	if ti < 0 or ti >= list.size() or list[ti].get("type") != "event" or list[ti].get("action") != "despawn":
		return false
	var id := String(list[ti].get("target", ""))
	list = list.duplicate()
	list.remove_at(ti)
	return _do("%s stays on" % id, true, [_change(["tracks"], list)])


static func _belongs_to(t: Dictionary, ids: Dictionary) -> bool:
	match t.get("type"):
		"event":
			return ids.has(t.get("id", "")) if t.get("action") == "spawn" else ids.has(t.get("target", ""))
		_:
			return ids.has(String(t.get("target", "")).split(".")[0])


# ---------- internals ----------

## Shader params of `reactive` are read at spawn (spin keys), so they
## need the runner to respawn the object.
static func _is_structural_track(track: Dictionary) -> bool:
	return String(track.get("target", "")).ends_with(".reactive")


func _keyframes(ti: int):
	if ti < 0 or ti >= tracks().size():
		return null
	var kfs = tracks()[ti].get("keyframes")
	return kfs if typeof(kfs) == TYPE_ARRAY else null


static func _key_at(kfs: Array, t: float) -> int:
	for i in kfs.size():
		if absf(float(kfs[i].get("t", 0.0)) - t) < SAME_TIME:
			return i
	return -1


## After any keys at the same time or earlier (keys stay sorted).
static func _insert_index(kfs: Array, t: float) -> int:
	var i := 0
	while i < kfs.size() and float(kfs[i].get("t", 0.0)) <= t:
		i += 1
	return i


static func _time_label(t: float) -> String:
	return "%d:%05.2f" % [floori(t / 60.0), fmod(t, 60.0)]


## New values go in as JSON would read them back (every number a float),
## so they compare equal to what the file holds.
func _change(p: Array, value) -> Dictionary:
	var had := _has_path(p)
	return {"path": p, "had_old": had, "old": _copy(_value_at(p)) if had else null, "has_new": true, "new": _as_json(value)}


static func _as_json(v):
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
		return JSON.parse_string(JSON.stringify(v))
	if typeof(v) == TYPE_INT:
		return float(v)
	return v


func _removal(p: Array) -> Dictionary:
	var had := _has_path(p)
	return {"path": p, "had_old": had, "old": _copy(_value_at(p)) if had else null, "has_new": false, "new": null}


## Several commands as one undo step (a drag that keys three channels):
## `body` runs them; `changed` fires once, after. False if nothing changed.
func batch(label: String, body: Callable) -> bool:
	if _batching:
		body.call()  # nested: part of the outer batch
		return true
	_batching = true
	_batch_changes = []
	_batch_structural = false
	body.call()
	_batching = false
	if _batch_changes.is_empty():
		return false
	_record(label, _batch_structural, _batch_changes)
	return true


## Apply a new command. Nothing happens (and false) if it changes nothing.
func _do(label: String, structural: bool, changes: Array) -> bool:
	changes = changes.filter(func(c): return c.had_old != c.has_new or JSON.stringify(c.old) != JSON.stringify(c.new))
	if changes.is_empty():
		return false
	for c in changes:
		_put(c.path, c.has_new, c.new)
	if _batching:
		_batch_changes.append_array(changes)
		_batch_structural = _batch_structural or structural
		return true
	_record(label, structural, changes)
	return true


## Push an applied command onto the undo stack and tell listeners.
func _record(label: String, structural: bool, changes: Array) -> void:
	_undo.append({"label": label, "structural": structural, "changes": changes})
	if _redo.size() > 0:
		_redo.clear()
		# States only reachable through redo are gone for good.
		if _saved_depth >= _undo.size():
			_saved_depth = -1
		if _loaded_depth >= _undo.size():
			_loaded_depth = -1
	changed.emit(structural)


func _value_at(p: Array):
	var node = _doc
	for k in p:
		if typeof(node) == TYPE_DICTIONARY:
			if not node.has(k):
				return null
			node = node[k]
		elif typeof(node) == TYPE_ARRAY:
			if typeof(k) != TYPE_INT or k < 0 or k >= node.size():
				return null
			node = node[k]
		else:
			return null
	return node


func _has_path(p: Array) -> bool:
	var parent = _value_at(p.slice(0, p.size() - 1))
	var k = p.back()
	if typeof(parent) == TYPE_DICTIONARY:
		return parent.has(k)
	if typeof(parent) == TYPE_ARRAY:
		return typeof(k) == TYPE_INT and k >= 0 and k < parent.size()
	return false


## Set (or with `present` false, remove) the value at `p`. Values are
## copied, so the undo record keeps its own.
func _put(p: Array, present: bool, value) -> void:
	var parent = _value_at(p.slice(0, p.size() - 1))
	var k = p.back()
	if typeof(parent) == TYPE_DICTIONARY:
		if present:
			parent[k] = _copy(value)
		else:
			parent.erase(k)
	elif typeof(parent) == TYPE_ARRAY and present:
		parent[k] = _copy(value)


static func _copy(v):
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
		return v.duplicate(true)
	return v
