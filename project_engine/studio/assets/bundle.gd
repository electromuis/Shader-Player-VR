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
