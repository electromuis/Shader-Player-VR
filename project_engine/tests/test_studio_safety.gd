extends RefCounted

## Keeping work safe (M8, StudioSafety): the autosave written from the
## model, found again when it has something the file hasn't (not when it
## says the same, or isn't a whole script), put back as one undo step
## (EditModel.replace_document; an invalid one changes nothing), and the
## rotating backups a save keeps.

const DIR := "user://test_studio_safety_tmp"
const DOC := {
	"format_version": 2,
	"media": {"video": "x.mp4"},
	"prefabs": {"cube": "res://player/prefabs/cube.tscn"},
	"tracks": [{"type": "event", "t": 0.0, "action": "spawn", "id": "a", "prefab": "cube"}],
}


static func _piece(tc: TestCase) -> EditModel:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var path := dir.path_join("piece.spscript")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(DOC, "  ") + "\n")
	f.close()
	var r := EditModel.open(path)
	tc.assert_ok(r)
	return r.get("model")


static func test_autosave_and_restore(tc: TestCase) -> void:
	var m := _piece(tc)
	var path := m.path
	var original := FileAccess.get_file_as_string(path)
	tc.assert_eq(StudioSafety.autosave_path(path), path + ".autosave")
	tc.assert_eq(StudioSafety.pending_autosave(path), "", "none yet")
	# The same as the file: nothing to restore.
	tc.assert_true(StudioSafety.autosave(m))
	tc.assert_eq(StudioSafety.pending_autosave(path), "", "says what the file says")
	# An edit, autosaved: found again.
	tc.assert_true(m.set_spawn_transform("a", {"position": [1.0, 2.0, 3.0]}))
	tc.assert_true(StudioSafety.autosave(m))
	var text := StudioSafety.pending_autosave(path)
	tc.assert_eq(text, m.to_text())
	# Opened again (the edit never saved): put back as one undo step.
	var again: EditModel = EditModel.open(path).model
	tc.assert_eq(again.to_text(), original.strip_edges() + "\n" if original.ends_with("\n") else original)
	var r := again.replace_document(text, "Restore the unsaved changes from 12:00")
	tc.assert_ok(r)
	tc.assert_eq(again.tracks()[0].transform.position, [1.0, 2.0, 3.0])
	tc.assert_true(again.is_dirty())
	tc.assert_eq(again.undo(), "Restore the unsaved changes from 12:00")
	tc.assert_false(again.is_dirty(), "undo drops it: back to the file")
	tc.assert_ok(again.save())
	tc.assert_eq(FileAccess.get_file_as_string(path), original, "saved untouched: the file as it was")
	# Not restored: a cut-short autosave, or an invalid script.
	var f := FileAccess.open(StudioSafety.autosave_path(path), FileAccess.WRITE)
	f.store_string("{\"format_version\": 2, \"tra")
	f.close()
	tc.assert_eq(StudioSafety.pending_autosave(path), "", "cut short")
	tc.assert_false(again.replace_document("{\"format_version\": 2}", "x").ok, "not a valid script")
	tc.assert_false(again.can_undo(), "nothing changed")
	tc.assert_false(again.replace_document(again.to_text(), "x").ok, "the same: no step")
	StudioSafety.clear_autosave(path)
	tc.assert_false(FileAccess.file_exists(StudioSafety.autosave_path(path)))
	tc.assert_ok(m.check())


static func test_backups_rotate(tc: TestCase) -> void:
	var m := _piece(tc)
	var path := m.path
	var versions: Array = [FileAccess.get_file_as_string(path)]
	for i in 4:
		StudioSafety.back_up(path)
		m.set_spawn_transform("a", {"position": [float(i + 1), 0.0, 0.0]})
		tc.assert_ok(m.save())
		versions.append(FileAccess.get_file_as_string(path))
	# After four saves: bak1 the file before the last save, bak3 the oldest kept.
	tc.assert_eq(FileAccess.get_file_as_string(StudioSafety.backup_path(path, 1)), versions[3])
	tc.assert_eq(FileAccess.get_file_as_string(StudioSafety.backup_path(path, 2)), versions[2])
	tc.assert_eq(FileAccess.get_file_as_string(StudioSafety.backup_path(path, 3)), versions[1])
	tc.assert_false(FileAccess.file_exists(StudioSafety.backup_path(path, 4)), "only %d kept" % StudioSafety.BACKUPS)
	StudioSafety.back_up(path + ".missing")  # nothing to keep: nothing happens
	tc.assert_false(FileAccess.file_exists(StudioSafety.backup_path(path + ".missing", 1)))
