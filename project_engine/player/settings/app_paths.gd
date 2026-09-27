class_name AppPaths
extends RefCounted

## Where the player keeps its own files. Normally that's Godot's user://
## folder (%APPDATA%\Godot\app_userdata\<name> on Windows). With a
## PORTABLE_MARKER file next to the executable the player is portable
## instead: its files go in a `save` folder next to it, and presets in the
## `presets` folder there (the release package's), so the whole install
## moves as one folder. Godot's own logs and shader caches stay in user://.

const PORTABLE_MARKER := "portable.ini"
const PORTABLE_SAVE_DIR := "save"
const PRESETS_DIR := "presets"

static var _portable: int = -1  # -1 = not checked yet
static var _exe_dir: String = ""


## Absolute: started as `.\Player.exe`, OS.get_executable_path() is relative
## to the working directory, and relative paths built on it (a video picked in
## the Files tab) got resolved against the script's folder a second time.
static func exe_dir() -> String:
	if _exe_dir == "":
		var path := OS.get_executable_path()
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			path = f.get_path_absolute()
		_exe_dir = path.get_base_dir()
	return _exe_dir


static func is_portable() -> bool:
	if _portable < 0:
		_portable = 1 if FileAccess.file_exists(exe_dir().path_join(PORTABLE_MARKER)) else 0
	return _portable == 1


## The folder for the player's own files (settings, user shaders and
## skyboxes, helper files); created when portable.
static func save_dir() -> String:
	if not is_portable():
		return "user://"
	var dir := exe_dir().path_join(PORTABLE_SAVE_DIR)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return dir


## `rel` inside save_dir().
static func save_path(rel: String) -> String:
	return save_dir().path_join(rel)


static func presets_dir() -> String:
	if is_portable():
		return exe_dir().path_join(PRESETS_DIR)
	return "user://".path_join(PRESETS_DIR)
