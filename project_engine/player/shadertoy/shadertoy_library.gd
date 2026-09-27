@tool
class_name ShadertoyLibrary
extends RefCounted

## The Shadertoy shaders you've collected: a folder of the site's JSON, one
## `<name>_<id>.json` per shader with its thumbnail as `<name>_<id>.jpg`.
## One folder per user by default (%APPDATA%/VJ Shadertoy on Windows), so
## the editor's Shadertoy dock and Studio see the same collection; the
## receiver (ShadertoyReceiver) adds what the Chrome extension sends.
## Pure file handling: the authoring addon has a copy
## (addon_vj/shadertoy/, kept identical by tests/test_addon_shader_copies.gd).

const DIR_NAME := "VJ Shadertoy"

var dir: String


static func default_dir() -> String:
	return OS.get_data_dir().path_join(DIR_NAME)


func _init(path: String = "") -> void:
	dir = path if path != "" else default_dir()


## Stores a shader (its JSON as the site has it, a string or parsed; see
## ShadertoyShader.parse) and its thumbnail (JPEG bytes, optional),
## replacing an earlier copy of the same shader. Returns the parsed shader,
## {} if `data` isn't one.
func add(data, thumbnail: PackedByteArray = PackedByteArray()) -> Dictionary:
	if data is String:
		data = JSON.parse_string(data)
	var st := ShadertoyShader.parse(data)
	if st.is_empty() or st.id == "":
		return {}
	var raw = data
	if raw is Array:
		raw = raw[0]
	if raw is Dictionary and raw.has("Shader"):
		raw = raw.Shader
	DirAccess.make_dir_recursive_absolute(dir)
	var old := find(st.id)
	if not old.is_empty():
		_remove_files(old)
	var stem := ShadertoyShader.file_stem(st)
	var f := FileAccess.open(dir.path_join(stem + ".json"), FileAccess.WRITE)
	if f == null:
		push_error("Shadertoy library: can't write to %s" % dir)
		return {}
	f.store_string(JSON.stringify(raw, "\t"))
	f.close()
	if not thumbnail.is_empty():
		f = FileAccess.open(dir.path_join(stem + ".jpg"), FileAccess.WRITE)
		if f != null:
			f.store_buffer(thumbnail)
			f.close()
	return st


## Every shader in the folder, newest first:
## [{shader (parsed), json, thumbnail ("" if none), modified (unix time)}].
func entries() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() != "json":
			continue
		var path := dir.path_join(file)
		var st := ShadertoyShader.parse(FileAccess.get_file_as_string(path))
		if st.is_empty():
			continue
		var thumb := path.get_basename() + ".jpg"
		out.append({
			"shader": st,
			"json": path,
			"thumbnail": thumb if FileAccess.file_exists(thumb) else "",
			"modified": FileAccess.get_modified_time(path),
		})
	out.sort_custom(func(a, b): return a.modified > b.modified or (a.modified == b.modified and a.json < b.json))
	return out


## The entry for a shader id (see entries), {} if it isn't here.
func find(id: String) -> Dictionary:
	for e in entries():
		if e.shader.id == id:
			return e
	return {}


func remove(id: String) -> bool:
	var e := find(id)
	if e.is_empty():
		return false
	_remove_files(e)
	return true


## The newest modification time in the folder, to notice changes cheaply.
func stamp() -> int:
	var newest := 0
	if DirAccess.dir_exists_absolute(dir):
		for file in DirAccess.get_files_at(dir):
			newest = maxi(newest, FileAccess.get_modified_time(dir.path_join(file)))
		newest += DirAccess.get_files_at(dir).size()  # removals too
	return newest


static func load_thumbnail(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _remove_files(e: Dictionary) -> void:
	DirAccess.remove_absolute(e.json)
	if e.thumbnail != "":
		DirAccess.remove_absolute(e.thumbnail)
