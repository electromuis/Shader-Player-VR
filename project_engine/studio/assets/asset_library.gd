class_name StudioAssetLibrary
extends RefCounted

## What Studio's asset shelf offers, by type (see "VR Studio — Plan.md",
## Assets). Pure: it only lists files, so tests drive it headless.
##
## An asset: {id (unique: type + path), type ("object" / "layer" /
##   "effect"), kind ("screen" / "cube" / "prefab" / "layer" / "effect"),
##   label, path (the prefab for objects, the shader for layers and
##   effects), source ("builtin", "user" or "piece"), in_piece (a user
##   asset the piece has a copy of), scale (the size it's dropped at)}.
## A user asset the piece already has a copy of (the same file name and
## bytes, as bundling makes) is one card: the user's, marked in_piece.
##
## Where they come from:
##   built-in — the player's screen and cube, its layer shaders and effects
##   user     — shaders in the player's shader folders
##              (VisualizerShaders.search_dirs: user://shaders, <exe>/shaders)
##              and shaders and prefabs (.tscn) in the library folders
##              (user://library, <exe>/library, and any added with
##              Studio's --library), each also in their shaders/ and
##              prefabs/ subfolders
##   piece    — the piece's own: prefabs next to its .json and in its
##              prefabs/ folder, shaders in its shaders/ folder
## Camera effects (`// @camera`) aren't offered: they're not objects.
## signature() changes when any of those folders' files do, so the shelf can
## watch them.

const TYPES := ["object", "layer", "effect"]
const TYPE_LABELS := {"object": "Objects", "layer": "Layers", "effect": "Effects"}
const PREFAB_EXTENSIONS := ["tscn", "scn"]
const LAYER_PREFAB := "res://player/prefabs/layer.tscn"
## Built-in screens and layers are 32 × 18 m at scale 1: dropped at this
## scale they're about 3.8 m wide.
const SCREEN_SCALE := 0.12
const CUBE_SCALE := 0.5
const BUILTIN_OBJECTS := [
	{"kind": "screen", "label": "Screen", "path": "res://player/prefabs/screen.tscn", "scale": SCREEN_SCALE},
	{"kind": "cube", "label": "Cube", "path": "res://player/prefabs/cube.tscn", "scale": CUBE_SCALE},
]

## Library folders, in order (absolute paths).
var library_dirs: Array[String] = []
## Shader folders the player also reads (VisualizerShaders.search_dirs()).
var shader_dirs: Array[String] = []
## The piece's folder ("" with no piece open).
var piece_dir: String = ""


static func default_library_dirs() -> Array[String]:
	var out: Array[String] = [ProjectSettings.globalize_path("user://library")]
	out.append(OS.get_executable_path().get_base_dir().path_join("library"))
	return out


func _init() -> void:
	library_dirs = default_library_dirs()
	shader_dirs = VisualizerShaders.search_dirs()


## Every asset, built-ins first, then the user's, then the piece's.
func assets() -> Array:
	var out: Array = []
	var seen := {}
	for o in BUILTIN_OBJECTS:
		_add(out, seen, "object", o.kind, o.label, o.path, "builtin", o.scale)
	var dirs := _shader_scan_dirs()
	for effects in [false, true]:
		for o in VisualizerShaders.list_options(dirs, effects):
			var path := String(o.key)
			_add(out, seen, "effect" if effects else "layer", "effect" if effects else "layer", String(o.label),
					path, _source_of(path), SCREEN_SCALE)
	for dir in _prefab_scan_dirs():
		for f in _sorted_files(dir):
			if f.get_extension().to_lower() in PREFAB_EXTENSIONS:
				var path := dir.path_join(f)
				_add(out, seen, "object", "prefab", f.get_basename().capitalize(), path, _source_of(path), 1.0)
	return _merge_copies(out)


## Drop the piece's copies of user assets, marking the user's in_piece.
static func _merge_copies(list: Array) -> Array:
	var users := {}  # "type|file name" -> [asset]
	for a in list:
		if a.source == "user":
			var k := "%s|%s" % [a.type, String(a.path).get_file()]
			users[k] = users.get(k, []) + [a]
	var out: Array = []
	for a in list:
		var copy_of = null
		if a.source == "piece":
			var bytes := FileAccess.get_file_as_bytes(a.path)
			for u in users.get("%s|%s" % [a.type, String(a.path).get_file()], []):
				if FileAccess.get_file_as_bytes(u.path) == bytes:
					copy_of = u
		if copy_of != null:
			copy_of.in_piece = true
		else:
			out.append(a)
	return out


## The assets of one type ("object" / "layer" / "effect").
func of_type(type: String) -> Array:
	return assets().filter(func(a): return a.type == type)


## Changes whenever a file in a watched folder is added, removed or saved.
func signature() -> String:
	var parts: Array = []
	for dir in _shader_scan_dirs() + _prefab_scan_dirs():
		for f in _sorted_files(dir):
			parts.append("%s|%d" % [dir.path_join(f), FileAccess.get_modified_time(dir.path_join(f))])
	return str(hash("\n".join(parts)))


## "piece" for files in the piece's folder, "builtin" for the player's own,
## else "user".
func _source_of(path: String) -> String:
	if path.begins_with("res://"):
		return "builtin"
	if piece_dir != "" and _inside(path, piece_dir):
		return "piece"
	return "user"


static func _inside(path: String, dir: String) -> bool:
	return path.simplify_path().to_lower().begins_with(dir.simplify_path().to_lower().trim_suffix("/") + "/")


func _shader_scan_dirs() -> Array[String]:
	var out: Array[String] = []
	for d in shader_dirs:
		_push_dir(out, d)
	for d in library_dirs:
		_push_dir(out, d)
		_push_dir(out, d.path_join("shaders"))
	if piece_dir != "":
		# Not the piece's folder itself: a readme .txt there would read as
		# Shadertoy code.
		_push_dir(out, piece_dir.path_join("shaders"))
	return out


func _prefab_scan_dirs() -> Array[String]:
	var out: Array[String] = []
	for d in library_dirs:
		_push_dir(out, d)
		_push_dir(out, d.path_join("prefabs"))
	if piece_dir != "":
		_push_dir(out, piece_dir)
		_push_dir(out, piece_dir.path_join("prefabs"))
	return out


static func _push_dir(out: Array[String], dir: String) -> void:
	if dir != "" and not out.has(dir) and DirAccess.dir_exists_absolute(dir):
		out.append(dir)


static func _sorted_files(dir: String) -> Array:
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	return files


static func _add(out: Array, seen: Dictionary, type: String, kind: String, label: String, path: String, source: String, scale: float) -> void:
	var id := "%s:%s" % [type, path]
	if seen.has(id):
		return
	seen[id] = true
	out.append({"id": id, "type": type, "kind": kind, "label": label, "path": path, "source": source, "in_piece": false, "scale": scale})
