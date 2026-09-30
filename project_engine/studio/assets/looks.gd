class_name StudioLooks
extends RefCounted

## Looks: an object's setup (its prefab, its spawn config: shader, surface,
## effects, modifiers, reactive; and its size) saved to the user's library,
## to put on other objects or add again, in any piece (see "VR Studio —
## Plan.md", Configuring: presets). Pure apart from files, so tests drive
## it headless.
##
## A look is a file in a library folder's looks/ (`<library>/looks/<name>.json`):
##   {"look": 1, "label": "Screen: Glow + Mirror", "kind": "screen",
##    "prefab": <path>, "scale": [x, y, z], "config": {...},
##    "shaders": {<key the config uses>: <path>}}
## Paths are the player's own (res://) or relative to the library folder:
## a custom shader or prefab the look uses is copied into the library's
## shaders/ or prefabs/ (StudioBundle), where the shelf offers it too.
## The config names shaders by the keys in "shaders", as a piece does;
## built-in names ("dome", "ripple", a layer's "video") stay as they are.
## Animation isn't part of a look: a switched-off effect's kept tracks are
## left out.
##
## Putting a look on an object replaces its spawn config (every spawn
## with the same config as its first, as the inspector's edits do): its
## shaders are bundled into the piece and named there. The object's effect
## and vertex effect tracks go (the effects they animated are replaced);
## its other tracks stay. Its prefab, place and size stay its own.

const VERSION := 1
const FOLDER := "looks"
const KIND_LABELS := {"screen": "Screen", "layer": "Layer", "object": "Object"}


## Save `id`'s setup in `model` as a look in `library_dir`. `kind` is the
## object's ("screen" / "layer" / "object", StudioConfigEdits.kind_for).
## {ok, path, label} or {ok: false, error}.
static func save(model: EditModel, id: String, kind: String, library_dir: String) -> Dictionary:
	var si := model.spawn_index(id)
	if si < 0:
		return {"ok": false, "error": "%s isn't in the SPScript" % id}
	var spawn: Dictionary = model.tracks()[si]
	var piece := _piece_data(model)
	var prefab := _to_library(piece.resolve_prefab(String(spawn.get("prefab", ""))), library_dir)
	if not prefab.ok:
		return prefab
	var config: Dictionary = model.config_of(id).duplicate(true)
	var shaders := {}
	for ref in shader_refs(config, piece.shaders):
		var key: String = ref.key
		if shaders.has(key):
			continue
		var file := _to_library(piece.resolve_shader(key), library_dir)
		if not file.ok:
			return file
		shaders[key] = file.path
	for list_key in ["effects", "vertex_effects"]:
		if typeof(config.get(list_key)) == TYPE_ARRAY:
			for e in config[list_key]:
				if typeof(e) == TYPE_DICTIONARY:
					e.erase("tracks")
	var scale = spawn.get("transform", {}).get("scale", [1.0, 1.0, 1.0]) if typeof(spawn.get("transform")) == TYPE_DICTIONARY else [1.0, 1.0, 1.0]
	var label := label_for(kind, config, shaders, prefab.path)
	var look := {"look": VERSION, "label": label, "kind": kind, "prefab": prefab.path,
			"scale": scale, "config": config, "shaders": shaders}
	var dir := library_dir.path_join(FOLDER)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := _free_file(dir, file_name_for(label))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Could not write %s (error %d)" % [path, FileAccess.get_open_error()]}
	f.store_string(JSON.stringify(look, "  ", false) + "\n")
	f.close()
	return {"ok": true, "path": path, "label": label}


## The look at `path` with its files as absolute paths ("prefab" and the
## "shaders" values), or {} if it isn't one.
static func read(path: String) -> Dictionary:
	var json := JSON.new()  # quietly: any .json can be lying there
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("look") or typeof(data.get("config")) != TYPE_DICTIONARY:
		return {}
	var root := path.get_base_dir().get_base_dir()
	data["prefab"] = _absolute(String(data.get("prefab", "")), root)
	var shaders := {}
	var listed = data.get("shaders", {})
	if typeof(listed) == TYPE_DICTIONARY:
		for k in listed:
			shaders[k] = _absolute(String(listed[k]), root)
	data["shaders"] = shaders
	if not String(data.get("kind", "")) in KIND_LABELS:
		data["kind"] = "object"
	return data


## The look's config for `model`'s piece: its shaders bundled into the
## piece and named in its `shaders` (inside a model.batch, the naming is
## part of that step). {ok, config} or {ok: false, error}.
static func config_for_piece(model: EditModel, look: Dictionary) -> Dictionary:
	var piece_dir := model.path.get_base_dir()
	var config: Dictionary = look.config.duplicate(true)
	var keys := {}  # the look's key -> the piece's
	for ref in shader_refs(config, look.shaders):
		var key: String = ref.key
		if not keys.has(key):
			var b := StudioBundle.bundle(piece_dir, String(look.shaders[key]))
			if not b.ok:
				return {"ok": false, "error": b.error}
			keys[key] = model.name_shader(b.path)
		ref.holder[ref.field] = keys[key]
	return {"ok": true, "config": config}


## Put `look` on object `id` (one undo step). {ok, message}.
static func apply(model: EditModel, id: String, look: Dictionary) -> Dictionary:
	var result := {"ok": false, "message": "%s already looks like that." % id}
	model.batch("Put the look %s on %s" % [look.label, id], func():
		var made := config_for_piece(model, look)
		if not made.ok:
			result.message = made.error
			return
		if model.replace_config(id, made.config):
			result.ok = true
			result.message = "%s now has the look %s." % [id, look.label])
	return result


## Every place `config` names a shader by a key of `keys`:
## [{holder (the dictionary), field, key}]. Built-in names that aren't
## keys (a surface's "dome", a layer's "video") aren't references.
static func shader_refs(config: Dictionary, keys: Dictionary) -> Array:
	var out: Array = []
	var holders: Array = [config]
	if typeof(config.get("surface")) == TYPE_DICTIONARY:
		holders.append(config.surface)
	for list_key in ["effects", "vertex_effects"]:
		if typeof(config.get(list_key)) == TYPE_ARRAY:
			for e in config[list_key]:
				if typeof(e) == TYPE_DICTIONARY:
					holders.append(e)
	for h in holders:
		var key = h.get("shader")
		if typeof(key) == TYPE_STRING and keys.has(key):
			out.append({"holder": h, "field": "shader", "key": key})
	return out


## "Screen: Glow + Mirror", "Layer: Tunnel", "Cube" (an object: its
## prefab's name).
static func label_for(kind: String, config: Dictionary, shaders: Dictionary, prefab: String = "") -> String:
	var parts: Array = []
	var shader = config.get("shader")
	if kind == "layer" and typeof(shader) == TYPE_STRING and shader != "":
		parts.append(StudioConfigEdits.effect_label(shader, String(shaders.get(shader, ""))))
	for e in config.get("effects", []) if typeof(config.get("effects")) == TYPE_ARRAY else []:
		if typeof(e) == TYPE_DICTIONARY and e.get("enabled", true) != false:
			var key := String(e.get("shader", ""))
			parts.append(StudioConfigEdits.effect_label(key, String(shaders.get(key, ""))))
	var name: String = KIND_LABELS.get(kind, "Object")
	if kind == "object" and prefab != "":
		name = prefab.get_file().get_basename().capitalize()
	return name if parts.is_empty() else "%s: %s" % [name, " + ".join(parts)]


## "Screen: Glow + Mirror" -> "screen_glow_mirror".
static func file_name_for(label: String) -> String:
	var words: Array = []
	for m in RegEx.create_from_string("[a-z0-9]+").search_all(label.to_lower()):
		words.append(m.get_string())
	return "_".join(words)


## Where a look's picture is kept: next to it.
static func picture_path(look_path: String) -> String:
	return look_path.get_basename() + ".png"


# ---------- files ----------

static func _piece_data(model: EditModel) -> TimelineData:
	var data := TimelineData.new()
	var doc := model.document()
	data.prefabs = doc.get("prefabs", {})
	data.shaders = doc.get("shaders", {})
	data.base_dir = model.path.get_base_dir() if model.path != "" else ""
	return data


## A file the piece uses, as the library names it: the player's own as it
## is, anything else copied into the library. {ok, path} / {ok: false, error}.
static func _to_library(file: String, library_dir: String) -> Dictionary:
	if file == "":
		return {"ok": false, "error": "a file it uses isn't named in the SPScript"}
	return StudioBundle.bundle(library_dir, file)


static func _absolute(path: String, root: String) -> String:
	if path == "" or path.begins_with("res://") or path.is_absolute_path():
		return path
	return root.path_join(path)


## `dir/base.json`, or base_2.json, ...: the first that isn't there.
static func _free_file(dir: String, base: String) -> String:
	if base == "":
		base = "look"
	var path := dir.path_join(base + ".json")
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s_%d.json" % [base, n])
		n += 1
	return path
