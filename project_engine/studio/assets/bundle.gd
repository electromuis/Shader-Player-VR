class_name StudioBundle
extends RefCounted

## Makes an asset part of the piece, so its folder can be zipped and played
## anywhere (see "VR Studio — Plan.md", Assets: self-contained pieces).
## What the piece names it:
##   the player's own (res://)      — as it is (and a relative path: it's
##                                    the piece's already)
##   a file in the piece's folder   — relative to it
##   anything else (a user asset)   — copied into the piece's prefabs/ or
##                                    shaders/ folder, as the exporter does,
##                                    and named relatively
## A shader's includes that aren't the player's own are copied with it. A
## prefab whose resources are all the player's own (or embedded) is copied
## byte for byte; one that uses other files (a texture next to it) is saved
## with them embedded (the exporter's FLAG_BUNDLE_RESOURCES), since the
## piece's folder won't have them.
## An asset already bundled isn't copied twice: a copy with the same bytes
## (or, for an embedded save, one saved since the source last changed) is
## used again; a different file of the same name gets name_2.
## Undo doesn't remove a copy: an unused file in the folder is harmless.

const PREFAB_EXTENSIONS := ["tscn", "scn"]


## {ok, path (what the piece names it), copied (a file was written), error}.
## `sub`: the folder a copy goes in, if not prefabs/ or shaders/ (vertex
## effects go in shaders/vertex/, where the shelf looks for them; a shader's
## images in images/).
static func bundle(piece_dir: String, src: String, sub := "") -> Dictionary:
	if src.begins_with("res://") or src.begins_with("builtin:") or not src.is_absolute_path():
		return {"ok": true, "path": src, "copied": false}  # the player's, or already the piece's
	if piece_dir == "":
		return {"ok": false, "error": "No piece folder to bundle %s into" % src.get_file()}
	if not FileAccess.file_exists(src):
		return {"ok": false, "error": "%s isn't there" % src}
	var rel := relative_to(src, piece_dir)
	if rel != "":
		return {"ok": true, "path": rel, "copied": false}
	var ext := src.get_extension().to_lower()
	var prefab := ext in PREFAB_EXTENSIONS
	if sub == "":
		sub = "prefabs" if prefab else "shaders"
	var embed := prefab and _needs_embedding(src)
	var base := src.get_file().get_basename()
	var n := 1
	while true:
		var name := src.get_file() if n == 1 else "%s_%d.%s" % [base, n, src.get_extension()]
		rel = sub + "/" + name
		var dst := piece_dir.path_join(rel)
		if not FileAccess.file_exists(dst):
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var err := _write_prefab(src, dst, embed) if prefab else _write_shader(src, dst)
			if err != "":
				return {"ok": false, "error": err}
			return {"ok": true, "path": rel, "copied": true}
		if _same(src, dst, embed):
			return {"ok": true, "path": rel, "copied": false}
		n += 1
	return {"ok": false, "error": "unreachable"}


## `path` relative to `dir` if it's inside it ("prefabs/x.tscn"), else "".
static func relative_to(path: String, dir: String) -> String:
	var p := path.simplify_path()
	var d := dir.simplify_path().trim_suffix("/") + "/"
	if p.to_lower().begins_with(d.to_lower()):
		return p.substr(d.length())
	return ""


## `target` (absolute) named from `dir`: relative ("../clips/a.mp4"), or
## as it is on another drive.
static func path_from(dir: String, target: String) -> String:
	var a := dir.simplify_path().trim_suffix("/").split("/")
	var b := target.simplify_path().split("/")
	if a[0].to_lower() != b[0].to_lower():
		return target.simplify_path()
	var i := 0
	while i < a.size() and i < b.size() - 1 and a[i].to_lower() == b[i].to_lower():
		i += 1
	var parts: Array = []
	for j in range(i, a.size()):
		parts.append("..")
	parts.append_array(b.slice(i))
	return "/".join(parts)


## A piece moving from `from_dir` to `to_dir` (Save as): the files its
## document names inside its folder (prefabs, shaders with their includes,
## images) are copied along to the same places, so the names stay; its
## media, and files outside its folder ("../"), stay where they are and
## are named from the new folder. `history`: the undo / redo changes
## ({path, old, new}), named the same way so an undo doesn't bring back a
## name from the old folder. Nothing is copied if a different file of the
## same name is there already. {ok, doc, history, copied} or {ok: false,
## error}.
static func carry(doc: Dictionary, from_dir: String, to_dir: String, history: Array = []) -> Dictionary:
	var files := {}  # relative path -> true: to copy
	var moved := {}
	for k in doc:
		moved[k] = _carry(doc[k], k == "media", from_dir, to_dir, files)
	var changes: Array = []
	for c in history:
		var in_media: bool = not c.path.is_empty() and c.path[0] == "media"
		var d: Dictionary = c.duplicate()
		d.old = _carry(c.old, in_media, from_dir, to_dir, files)
		d.new = _carry(c.new, in_media, from_dir, to_dir, files)
		changes.append(d)
	for rel in files:
		var dst := to_dir.path_join(rel)
		if FileAccess.file_exists(dst) and FileAccess.get_file_as_bytes(dst) != FileAccess.get_file_as_bytes(from_dir.path_join(rel)):
			return {"ok": false, "error": "Not saved: %s is in %s already, and isn't the piece's" % [rel, to_dir]}
	var copied: Array = []
	for rel in files:
		var src := from_dir.path_join(rel)
		var dst := to_dir.path_join(rel)
		if FileAccess.file_exists(dst):
			continue
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var err := ""
		if src.get_extension().to_lower() in PREFAB_EXTENSIONS:
			if DirAccess.copy_absolute(src, dst) != OK:
				err = "Could not copy %s" % rel
		else:
			err = _write_shader(src, dst)
		if err != "":
			return {"ok": false, "error": err}
		copied.append(rel)
	return {"ok": true, "doc": moved, "history": changes, "copied": copied}


## `v` with the names of files to leave behind rewritten from `to_dir`;
## the ones to copy go in `files`.
static func _carry(v: Variant, in_media: bool, from_dir: String, to_dir: String, files: Dictionary) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _carry(v[k], in_media, from_dir, to_dir, files)
			return out
		TYPE_ARRAY:
			return v.map(func(x): return _carry(x, in_media, from_dir, to_dir, files))
		TYPE_STRING:
			var s: String = v
			if s.get_extension() == "" or s.is_absolute_path() or s.contains("://") or s.begins_with("builtin:"):
				return v
			if in_media:  # named from the new folder, there or not
				return path_from(to_dir, from_dir.path_join(s))
			if not FileAccess.file_exists(from_dir.path_join(s)):
				return v
			var rel := relative_to(from_dir.path_join(s), from_dir)
			if rel == "":
				return path_from(to_dir, from_dir.path_join(s))
			files[rel] = true
			return rel
	return v


static func _same(src: String, dst: String, embed: bool) -> bool:
	if embed:
		return FileAccess.get_modified_time(dst) >= FileAccess.get_modified_time(src)
	return FileAccess.get_file_as_bytes(src) == FileAccess.get_file_as_bytes(dst)


## Whether the prefab uses files other than the player's own.
static func _needs_embedding(src: String) -> bool:
	for dep in ResourceLoader.get_dependencies(src):
		var path := String(dep).get_slice("::", String(dep).get_slice_count("::") - 1)
		if path != "" and not path.begins_with("res://"):
			return true
	return false


static func _write_prefab(src: String, dst: String, embed: bool) -> String:
	if not embed:
		var err := DirAccess.copy_absolute(src, dst)
		return "" if err == OK else "Could not copy %s (error %d)" % [src.get_file(), err]
	var packed := ResourceLoader.load(src, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return "Could not load %s" % src.get_file()
	var save_err := ResourceSaver.save(packed, dst, ResourceSaver.FLAG_BUNDLE_RESOURCES)
	return "" if save_err == OK else "Could not save %s (error %d)" % [dst.get_file(), save_err]


## The shader, and the files it includes by a relative path (next to it).
static func _write_shader(src: String, dst: String) -> String:
	var err := DirAccess.copy_absolute(src, dst)
	if err != OK:
		return "Could not copy %s (error %d)" % [src.get_file(), err]
	if src.get_extension().to_lower() in ImageLibrary.EXTENSIONS:
		return ""  # an image: nothing it includes
	var re :=RegEx.create_from_string("#include\\s+\"([^\"]+)\"")
	for m in re.search_all(FileAccess.get_file_as_string(src)):
		var inc := m.get_string(1)
		if inc.begins_with("res://") or inc.is_absolute_path():
			continue
		var from := src.get_base_dir().path_join(inc)
		var to := dst.get_base_dir().path_join(inc)
		if FileAccess.file_exists(from) and not FileAccess.file_exists(to):
			DirAccess.make_dir_recursive_absolute(to.get_base_dir())
			DirAccess.copy_absolute(from, to)
	return ""
