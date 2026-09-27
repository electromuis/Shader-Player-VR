extends SceneTree

## Rewrites preset files in the current format: earlier presets' curvature /
## vertical_curvature become a Pillow `surface`, older single-layer blocks
## become `layers` (the same conversion the player does when applying one,
## PresetStore.apply). Each folder's preset_*.json is loaded and saved back
## through PresetStore, so the files look like ones the player saved.
##   godot --headless --path project_engine --script res://tools/migrate_presets.gd -- <presets folder>...

const _FILE_RE := "^preset_(\\d+)\\.json$"


func _init() -> void:
	var dirs := OS.get_cmdline_user_args()
	if dirs.is_empty():
		push_error("migrate_presets: pass one or more presets folders after --")
		quit(1)
		return
	var re := RegEx.create_from_string(_FILE_RE)
	var count := 0
	for dir in dirs:
		var store := PresetStore.new(dir)
		for f in DirAccess.get_files_at(dir):
			var m := re.search(f)
			if m == null:
				continue
			var index := int(m.get_string(1))
			var data := store.load_preset(index)
			if typeof(data.get("screen")) != TYPE_DICTIONARY:
				push_warning("migrate_presets: %s has no screen block, skipped" % dir.path_join(f))
				continue
			var screen := ScreenSettings.new()
			screen.from_dict(data.screen)
			var layers := LayerStack.new()
			layers.from_array(PresetStore.layers_of(data))
			if store.save_preset(index, String(data.get("name", "Preset %d" % index)), screen.to_dict(), layers.to_array()):
				print("migrated %s" % dir.path_join(f))
				count += 1
	print("%d presets migrated" % count)
	quit(0)
