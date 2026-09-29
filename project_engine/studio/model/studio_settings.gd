class_name StudioSettings
extends RefCounted

## Studio's own options (the menu's Studio tab), next to the player's
## settings it shares (PlayerSettings). One JSON file, saved on every
## change, like PlayerSettings.
##
##   key_mode    — what a change writes: "off" (the piece's values; an
##                 animated one's key at the playhead, or between keys it's
##                 held unkeyed until keyed or dropped), "animated"
##                 (animated things key at the playhead, still ones are set)
##                 or "all" (auto-key: every change keys). The timeline's bar
##                 and Shift+I change it too.
##   haptics     — controller ticks for grabs, snaps, keys and drops.
##   autosave    — unsaved changes kept in <piece>.autosave every minute.
##   floor_grid  — 1 m lines on the floor while editing.

signal changed

const FILE_NAME := "studio_settings.json"
const KIND := "studio_settings"
const KEY_MODES := ["off", "animated", "all"]
const DEFAULTS := {"key_mode": "off", "haptics": true, "autosave": true, "floor_grid": true}

var key_mode: String = "off": set = _set_key_mode
var haptics: bool = true: set = _set_haptics
var autosave: bool = true: set = _set_autosave
var floor_grid: bool = true: set = _set_floor_grid

var _path: String
var _loading := false


func _init(path: String = AppPaths.save_path(FILE_NAME)) -> void:
	_path = path


func load_from_disk() -> void:
	if not FileAccess.file_exists(_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("StudioSettings: %s is not a JSON object" % _path)
		return
	from_dict(parsed)


func from_dict(d: Dictionary) -> void:
	_loading = true
	key_mode = String(d.get("key_mode", DEFAULTS.key_mode))
	haptics = bool(d.get("haptics", DEFAULTS.haptics))
	autosave = bool(d.get("autosave", DEFAULTS.autosave))
	floor_grid = bool(d.get("floor_grid", DEFAULTS.floor_grid))
	_loading = false
	changed.emit()


func to_dict() -> Dictionary:
	return {"kind": KIND, "key_mode": key_mode, "haptics": haptics, "autosave": autosave, "floor_grid": floor_grid}


## Whether `field` is at its default (the menu's ↺ is off then).
func is_default(field: String) -> bool:
	return get(field) == DEFAULTS[field]


func reset(field: String) -> void:
	set(field, DEFAULTS[field])


func save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_warning("StudioSettings: cannot write %s" % _path)
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))


func _touch() -> void:
	if _loading:
		return
	save()
	changed.emit()


func _set_key_mode(v: String) -> void:
	if not KEY_MODES.has(v):
		v = DEFAULTS.key_mode
	if v == key_mode:
		return
	key_mode = v
	_touch()


func _set_haptics(v: bool) -> void:
	if v == haptics:
		return
	haptics = v
	_touch()


func _set_autosave(v: bool) -> void:
	if v == autosave:
		return
	autosave = v
	_touch()


func _set_floor_grid(v: bool) -> void:
	if v == floor_grid:
		return
	floor_grid = v
	_touch()
