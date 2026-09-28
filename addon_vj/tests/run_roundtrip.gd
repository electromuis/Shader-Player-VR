extends SceneTree

## Round trip for the importer: every script JSON under a folder is
## imported, exported, imported and exported again.
##
##   godot --headless --path project_script_example \
##       --script res://addons/vj_editor/tests/run_roundtrip.gd [-- <scripts dir>…]
##
## (default: the repo's scripts/, next to the authoring projects, and this
## folder's fixtures/).
## Checks, per script:
##   - it plays the same: events, meta, media and prefab / shader keys match
##     the original, and every track's value, sampled every 1/20 s through
##     the player's own Interpolation, stays within tolerance
##   - it's stable: exporting the second import gives the first export again
## Warnings the importer reports (things a scene can't say) are printed.

const ScriptImporterScript := preload("res://addons/vj_editor/importer/script_importer.gd")
const SceneExporterScript := preload("res://addons/vj_editor/exporter/scene_exporter.gd")

const _TOLERANCE := 1e-3
const _SAMPLES_PER_SECOND := 20.0

var _interpolation: GDScript
var _fails := 0
var _tmp := ""


func _initialize() -> void:
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var args := OS.get_cmdline_user_args()
	var dirs: Array = args if not args.is_empty() else [repo.path_join("scripts"),
			ProjectSettings.globalize_path("res://addons/vj_editor/tests/fixtures")]
	_interpolation = load(repo.path_join("project_engine/player/runtime/interpolation.gd"))
	if _interpolation == null:
		push_error("roundtrip: needs the player's interpolation.gd at %s" % repo.path_join("project_engine"))
		quit(2)
		return
	_tmp = OS.get_temp_dir().path_join("vj_roundtrip_%d" % Time.get_ticks_usec())
	var scripts: Array = []
	for dir in dirs:
		scripts.append_array(_find_json(dir))
	for path in scripts:
		_check(path)
	_check_authored_ride()
	print("\nRound trip: %d script(s), %s" % [scripts.size(), "all ok" if _fails == 0 else "%d failure(s)" % _fails])
	quit(0 if _fails == 0 else 1)


## A ride keyed in Godot: a smooth VJViewer with a linear position track
## whose keys 1 ms apart are cuts (a hold before one goes), no rotation
## track (its rest pose is held from the first key).
func _check_authored_ride() -> void:
	print("== authored ride")
	var built := ScriptImporterScript.build_scene(
			ProjectSettings.globalize_path("res://addons/vj_editor/tests/fixtures/ride_steps/video.json"), _tmp.path_join("authored"))
	if not built.ok:
		_fail("import failed: %s" % built.error)
		return
	var root: Node = built.root
	var viewer: Node3D = root.get_node("Viewer")
	var anim: Animation = root.get_node("AnimationPlayer").get_animation("main")
	for i in range(anim.get_track_count() - 1, -1, -1):
		if String(anim.track_get_path(i)).begins_with("Viewer:"):
			anim.remove_track(i)
	viewer.motion = "smooth"
	viewer.transition = "fade_to_black"
	viewer.fade_duration = 0.5
	viewer.rotation = Vector3(0, deg_to_rad(30.0), 0)
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, "Viewer:position")
	var a := Vector3(0, 2, 8)
	for key in [[0.0, a], [3.0, a], [3.001, Vector3(0, 2, 2)], [6.0, Vector3(1, 2, 0)], [6.001, Vector3(5, 2, 0)], [9.0, Vector3(5, 2, -3)]]:
		anim.track_insert_key(track, key[0], key[1])
	var res: Dictionary = SceneExporterScript._build_json(root, _tmp.path_join("authored_export"))
	root.free()
	if not res.ok:
		_fail("export failed: %s" % res.error)
		return
	var ride := {}
	for t in res.data.tracks:
		if t.get("target") == SceneExporterScript.VIEWER_TARGET:
			ride[t.channel] = JSON.parse_string(JSON.stringify(t.keyframes))
	var fade := {"type": "fade_to_black", "duration": 0.5}
	var want := {
		"position": [
			{"t": 0.0, "value": [0.0, 2.0, 8.0], "interp": "step"},
			{"t": 3.001, "value": [0.0, 2.0, 2.0], "transition": fade},
			{"t": 6.0, "value": [1.0, 2.0, 0.0], "interp": "step"},
			{"t": 6.001, "value": [5.0, 2.0, 0.0], "transition": fade},
			{"t": 9.0, "value": [5.0, 2.0, -3.0]},
		],
		"rotation_deg": [{"t": 0.0, "value": [0.0, 30.0, 0.0]}],
	}
	var diffs: Array = []
	_diff(want, ride, "ride", diffs, 1e-4)
	for d in diffs.slice(0, 10):
		_fail("authored ride: " + d)
	print("   %d position keys, cuts at 3.001 and 6.001" % ride.get("position", []).size())


func _find_json(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "json":
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_find_json(dir.path_join(d)))
	return out


func _check(path: String) -> void:
	print("== %s" % path)
	var original = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not JSON.stringify(original.get("tracks", [])).contains('"spawn"'):
		print("   nothing spawned: nothing to round-trip (the exporter needs objects)")
		return
	var name := path.get_base_dir().get_file()
	var first := _import_export(path, _tmp.path_join(name + "_1"))
	if first.is_empty():
		return
	var second := _import_export(first.path, _tmp.path_join(name + "_2"))
	if second.is_empty():
		return
	if int(original.get("format_version", 1)) < 2:
		ScriptImporterScript._upgrade_v1(original.get("tracks", []))
	_same_playback(_normalized(original), _normalized(first.data))
	var diffs: Array = []
	_diff(_canonical(first.data), _canonical(second.data), "", diffs, 1e-6)
	for d in diffs.slice(0, 10):
		_fail("export not stable: " + d)


## Imports `json` (files under `dir`) and exports it to `dir`/video.json.
## {path, data} or {} (failed).
func _import_export(json: String, dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir)
	var built := ScriptImporterScript.build_scene(json, dir.path_join("project"))
	if not built.ok:
		_fail("import failed: %s" % built.error)
		return {}
	for w in built.warnings:
		print("   note: %s" % w)
	var out_dir := dir.path_join("export")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var res: Dictionary = SceneExporterScript._build_json(built.root, out_dir)
	built.root.free()
	if not res.ok:
		_fail("export failed: %s" % res.error)
		return {}
	var out := out_dir.path_join("video.json")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(res.data, "  "))
	f.close()
	# Through JSON and back, so numbers compare the way the file holds them.
	return {"path": out, "data": JSON.parse_string(FileAccess.get_file_as_string(out))}


func _same_playback(a: Dictionary, b: Dictionary) -> void:
	var diffs: Array = []
	for k in ["meta", "media"]:
		var av: Dictionary = a.get(k, {}).duplicate()
		av.erase("audio")
		_diff(av, b.get(k, {}), k, diffs, _TOLERANCE)
	for k in ["prefabs", "shaders"]:
		_diff(a.get(k, {}).keys().filter(func(x): return _used(a, k, x)).map(func(x): return str(x)),
				b.get(k, {}).keys(), k, diffs, 0.0, true)
	_diff(_events(a), _events(b), "events", diffs, _TOLERANCE)
	_diff(_ride_cuts(a), _ride_cuts(b), "viewer cuts", diffs, _TOLERANCE)
	var ta := _continuous(a)
	var tb := _continuous(b)
	_diff(ta.keys(), tb.keys(), "tracks", diffs, 0.0, true)
	var samples := 0
	for key in ta:
		if not tb.has(key):
			continue
		var end := maxf(float(ta[key][-1].t), float(tb[key][-1].t)) + 0.5
		for n in int(end * _SAMPLES_PER_SECOND) + 1:
			var t := n / _SAMPLES_PER_SECOND
			var va = _interpolation.evaluate(ta[key], t)
			var vb = _interpolation.evaluate(tb[key], t)
			var before := diffs.size()
			_diff(va, vb, "%s @ %.2fs" % [key, t], diffs, _TOLERANCE)
			samples += 1
			if diffs.size() > before:
				break  # one per track is enough
	for d in diffs.slice(0, 20):
		_fail("plays differently: " + d)
	print("   compared %d events, %d tracks (%d samples)" % [_events(a).size(), ta.size(), samples])


## What the player makes of a script, where two ways of saying it play the
## same: earlier versions' curvature (0..1, on the config or a `display`
## track) is the Pillow surface's arcs / 180 (a `shape` track), a flat
## fixed Pillow is no surface at all, and their Padding effect does nothing
## (the effects after it move up a place). Effect params the effect's
## shader doesn't have (any more) are ignored by the player too.
static func _normalized(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	var shaders: Dictionary = out.get("shaders", {})
	var moved := {}  # "<id>.effect<N>" -> its new N, -1 for a Padding
	for t in out.get("tracks", []):
		if t.get("type") != "event" or t.get("action") != "spawn" or typeof(t.get("config")) != TYPE_DICTIONARY:
			continue
		var cfg: Dictionary = t.config
		if cfg.has("curvature") or cfg.has("vertical_curvature"):
			if not cfg.has("surface"):
				cfg["surface"] = {"shader": "pillow", "placement": "fixed", "params": {
						"arc_x": float(cfg.get("curvature", 0.0)) * 180.0, "arc_y": float(cfg.get("vertical_curvature", 0.0)) * 180.0}}
			cfg.erase("curvature")
			cfg.erase("vertical_curvature")
		if typeof(cfg.get("surface")) == TYPE_DICTIONARY:
			var sf: Dictionary = cfg.surface
			var params: Dictionary = sf.get("params", {})
			if sf.get("shader", "pillow") == "pillow" and sf.get("placement", "fixed") == "fixed" 					and float(params.get("arc_x", 0.0)) == 0.0 and float(params.get("arc_y", 0.0)) == 0.0:
				cfg.erase("surface")
		if typeof(cfg.get("effects")) == TYPE_ARRAY:
			var kept: Array = []
			var n_old := 0
			var n_new := 0
			for e in cfg.effects:
				var on: bool = typeof(e) == TYPE_DICTIONARY and e.get("enabled", true) != false
				var pad: bool = typeof(e) == TYPE_DICTIONARY and String(shaders.get(e.get("shader", ""), "")) == ScriptImporterScript._LEGACY_PADDING
				if on:
					moved["%s.effect%d" % [t.get("id"), n_old]] = -1 if pad else n_new
					n_old += 1
					if not pad:
						n_new += 1
				if not pad:
					kept.append(e)
			for e in kept:
				_drop_unknown_params(e, String(shaders.get(e.get("shader", ""), "")))
			if kept.is_empty():
				cfg.erase("effects")
			else:
				cfg["effects"] = kept
	var tracks: Array = []
	for t in out.get("tracks", []):
		if t.get("type") == "shader_param":
			var target := String(t.get("target", ""))
			if moved.has(target):
				if moved[target] < 0:
					continue
				t["target"] = "%s.effect%d" % [target.split(".")[0], moved[target]]
			elif target.ends_with(".display") and t.get("param") in ["curvature", "vertical_curvature"]:
				t["target"] = target.trim_suffix(".display") + ".shape"
				t["param"] = "arc_x" if t.param == "curvature" else "arc_y"
				for kf in t.keyframes:
					kf["value"] = float(kf.value) * 180.0
					for h in ["in", "out"]:
						if typeof(kf.get(h)) == TYPE_ARRAY and kf[h].size() == 2:
							kf[h][1] = float(kf[h][1]) * 180.0
		tracks.append(t)
	out["tracks"] = _merged_ride(tracks)
	for k in shaders.keys():
		if shaders[k] == ScriptImporterScript._LEGACY_PADDING:
			shaders.erase(k)
	return out


## Leaves only the params effect `e`'s shader (a player built-in, through
## the addon's copy) has as uniforms.
static func _drop_unknown_params(e: Dictionary, path: String) -> void:
	if typeof(e.get("params")) != TYPE_DICTIONARY or not path.begins_with(ScriptImporterScript._PLAYER_VISUALIZER):
		return
	var copy := ScriptImporterScript._ADDON_VISUALIZER + path.substr(ScriptImporterScript._PLAYER_VISUALIZER.length())
	var shader := load(copy) as Shader if ResourceLoader.exists(copy) else null
	if shader == null:
		return
	var names := shader.get_shader_uniform_list().map(func(u): return String(u.name))
	for k in e.params.keys():
		if not names.has(k):
			e.params.erase(k)
	if e.params.is_empty():
		e.erase("params")


## Whether a prefabs / shaders key is used (the exporter only lists used ones).
func _used(data: Dictionary, map: String, key: String) -> bool:
	return JSON.stringify(data.get("tracks", [])).contains('"%s"' % key)


## With a ride ("$viewer" tracks), the player's view of the viewer: both
## channels (a missing one holds zero from the ride's start), and vr_cut
## events joined as keys the viewer jumps to (the key before steps), as
## ViewerTrack does.
static func _merged_ride(tracks: Array) -> Array:
	var ride := {}  # channel -> track
	for t in tracks:
		if t.get("type") == "transform" and t.get("target") == SceneExporterScript.VIEWER_TARGET:
			ride[t.get("channel")] = t
	if ride.is_empty():
		return tracks
	var start := INF
	for ch in ride:
		for kf in ride[ch].keyframes:
			start = minf(start, float(kf.t))
	var out: Array = []
	for ch in ["position", "rotation_deg"]:
		if not ride.has(ch):
			ride[ch] = {"type": "transform", "target": SceneExporterScript.VIEWER_TARGET, "channel": ch,
					"keyframes": [{"t": start, "value": [0.0, 0.0, 0.0]}]}
			out.append(ride[ch])
	for t in tracks:
		if t.get("type") == "event" and t.get("action") == "vr_cut":
			var at := float(t.get("t", 0.0))
			for ch in ride:
				var kfs: Array = ride[ch].keyframes
				var i := 0
				while i < kfs.size() and float(kfs[i].t) < at:
					i += 1
				var key := {"t": at, "value": t.get("to", {}).get(ch, [0.0, 0.0, 0.0])}
				if typeof(t.get("transition")) == TYPE_DICTIONARY:
					key["transition"] = t.transition
				kfs.insert(i, key)
				if i > 0:
					kfs[i - 1]["interp"] = "step"
					kfs[i - 1].erase("out")
			continue
		out.append(t)
	return out


## The ride's cuts as [t, fade seconds (0: hard)]: its first key if after
## t=0, and every key reached by a step (see ViewerTrack).
static func _ride_cuts(data: Dictionary) -> Array:
	var times := {}  # t -> fade
	var start := INF
	var fades := {}
	for t in data.get("tracks", []):
		if t.get("type") != "transform" or t.get("target") != SceneExporterScript.VIEWER_TARGET:
			continue
		var kfs: Array = t.keyframes
		for i in kfs.size():
			var at := float(kfs[i].t)
			start = minf(start, at)
			var tr = kfs[i].get("transition")
			if typeof(tr) == TYPE_DICTIONARY and tr.get("type") == "fade_to_black":
				fades[at] = float(tr.get("duration", 0.5))
			if i > 0 and String(kfs[i - 1].get("interp", "linear")) == "step":
				times[at] = true
	if start > 0.0 and start != INF:
		times[start] = true
	var out: Array = []
	for at in times:
		out.append([at, fades.get(at, 0.0)])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out


func _events(data: Dictionary) -> Array:
	var out: Array = data.get("tracks", []).filter(func(t): return t.get("type") == "event" and t.get("action") != "vr_teleport")
	out.sort_custom(func(x, y): return _event_key(x) < _event_key(y))
	return out


func _event_key(e: Dictionary) -> String:
	return "%012.4f|%s|%s" % [float(e.get("t", 0.0)), e.get("action", ""), e.get("id", e.get("target", ""))]


func _continuous(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for t in data.get("tracks", []):
		if t.get("type") in ["transform", "shader_param"]:
			out["%s|%s|%s" % [t.type, t.get("target", ""), t.get("channel", t.get("param", ""))]] = t.keyframes
	return out


func _canonical(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	var tracks: Array = out.get("tracks", [])
	tracks.sort_custom(func(x, y): return JSON.stringify(x) < JSON.stringify(y))
	return out


## Collects differences between `a` and `b` into `out` (numbers within
## `eps`, relative above 1). `as_set`: compare arrays ignoring order.
func _diff(a, b, where: String, out: Array, eps: float, as_set := false) -> void:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		if absf(float(a) - float(b)) > eps * maxf(1.0, absf(float(a))):
			out.append("%s: %s != %s" % [where, a, b])
		return
	if typeof(a) != typeof(b):
		out.append("%s: %s != %s" % [where, JSON.stringify(a), JSON.stringify(b)])
		return
	match typeof(a):
		TYPE_DICTIONARY:
			for k in a:
				if not b.has(k):
					out.append("%s.%s missing (was %s)" % [where, k, JSON.stringify(a[k])])
				else:
					_diff(a[k], b[k], "%s.%s" % [where, k], out, eps)
			for k in b:
				if not a.has(k):
					out.append("%s.%s added (%s)" % [where, k, JSON.stringify(b[k])])
		TYPE_ARRAY:
			if as_set:
				var sa: Array = a.duplicate()
				var sb: Array = b.duplicate()
				sa.sort()
				sb.sort()
				if sa != sb:
					out.append("%s: %s != %s" % [where, sa, sb])
				return
			if a.size() != b.size():
				out.append("%s: %d items != %d" % [where, a.size(), b.size()])
				return
			for i in a.size():
				_diff(a[i], b[i], "%s[%d]" % [where, i], out, eps)
		_:
			if a != b:
				out.append("%s: %s != %s" % [where, a, b])


func _fail(msg: String) -> void:
	_fails += 1
	print("   FAIL %s" % msg)
