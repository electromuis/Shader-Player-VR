class_name StudioSafety
extends RefCounted

## Keeping unsaved work (see "VR Studio — Plan.md", Saving and safety):
##   autosave — while a piece has unsaved changes, its text goes to
##              `<piece>.autosave` next to it every AUTOSAVE_SECONDS, when
##              another piece is opened and when Studio closes. Saving, or
##              undoing back to the saved file, removes it.
##   restore  — opening a piece whose autosave is newer than it and
##              different puts the autosave back as one undo step (undo
##              drops it again; nothing is lost either way).
##   backups  — each save that changes the file keeps the one it replaces
##              as `<piece>.bak1`, the one before as .bak2, … up to BACKUPS.
## Pure file work, so tests drive it headless.

const AUTOSAVE_SECONDS := 60.0
const BACKUPS := 3


static func autosave_path(piece: String) -> String:
	return piece + ".autosave"


static func backup_path(piece: String, n: int) -> String:
	return "%s.bak%d" % [piece, n]


## Write `model`'s text to its autosave. Whether it was written.
static func autosave(model: EditModel) -> bool:
	if model == null or model.path == "":
		return false
	var f := FileAccess.open(autosave_path(model.path), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(model.to_text())
	f.close()
	return true


static func clear_autosave(piece: String) -> void:
	if piece != "" and FileAccess.file_exists(autosave_path(piece)):
		DirAccess.remove_absolute(autosave_path(piece))


## The autosave's text when it's newer than `piece` and says something
## else, else "".
static func pending_autosave(piece: String) -> String:
	var auto := autosave_path(piece)
	if not FileAccess.file_exists(auto):
		return ""
	if FileAccess.file_exists(piece) and FileAccess.get_modified_time(auto) < FileAccess.get_modified_time(piece):
		return ""
	var text := FileAccess.get_file_as_string(auto)
	var mine := JSON.new()
	if mine.parse(text) != OK or typeof(mine.data) != TYPE_DICTIONARY:
		return ""  # cut short or not a script: nothing to restore
	var saved := JSON.new()
	if FileAccess.file_exists(piece) and saved.parse(FileAccess.get_file_as_string(piece)) == OK and saved.data == mine.data:
		return ""
	return text


## Before a save replaces `piece`: .bak2 → .bak3, .bak1 → .bak2, the file
## → .bak1 (the oldest goes).
static func back_up(piece: String) -> void:
	if not FileAccess.file_exists(piece):
		return
	for n in range(BACKUPS - 1, 0, -1):
		var from := backup_path(piece, n)
		if FileAccess.file_exists(from):
			var to := backup_path(piece, n + 1)
			if FileAccess.file_exists(to):
				DirAccess.remove_absolute(to)
			DirAccess.rename_absolute(from, to)
	DirAccess.copy_absolute(piece, backup_path(piece, 1))
