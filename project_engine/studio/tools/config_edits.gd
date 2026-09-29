class_name StudioConfigEdits
extends RefCounted

## What Studio's inspector shows and changes for an object: its fields
## (sections), each one's value and key state at the playhead, and writing a
## change (commit) the way auto-key says, as one undoable step. The
## inspector (studio/ui/inspector.gd) is a view of this; tests drive it
## directly.
##
## A field: {key (unique in the object), label, type ("float" / "int" /
##   "bool" / "color" / "vec3" / "choice" / "texture"), min, max, step,
##   default, alpha (colours), options and values (a choice: the names shown
##   and the values written, ints for a shader's hint_enum, strings for a
##   blend), tip, config (its path in the spawn config, [] if it has none),
##   slot ("display", "effect1", "modifiers", ...: the `shader_param` track
##   target is "<id>.<slot>"; "" = it can't be keyed), param}.
## A section: {title, kind ("fields" / "effect" / "transform" / "surface" /
##   "layer_shader"), fields}; effects also have list (EditModel.EFFECTS or
##   VERTEX_EFFECTS), index (in the list), shader (key), enabled; the
##   surface has shader (a path), placement, placements, options, hint.
##
## What a change writes (commit):
##   auto-key on  — a key at the playhead on the field's track (made if
##                  needed); a key within KEY_NEAR of the playhead is that key
##   auto-key off — the spawn config (every spawn with the same value); if
##                  the field is animated, its whole track scales by the
##                  change instead (where the value is 0, it shifts), so the
##                  curve keeps its shape and a fade from 0 still starts at
##                  0 (as a grab does with a path). A switch keys.
##   A field with no place in the config (a custom prefab's own material)
##   keys either way: a single key is a still value. A choice or an image
##   keys with step keys (it can't be in between), and a picked image
##   outside the piece is copied into its images/ folder first.
## While a control is dragged, preview() shows the value live through the
## runner (the same route as a track) and holds the track off it.

## A key this close to the playhead is "the key here" (the diamond is
## filled, tapping it removes it, and a change replaces it).
const KEY_NEAR := 0.05
const Modifiers := preload("res://player/runtime/modifiers.gd")
## Transform channels in the transform section.
const CHANNELS := ["position", "rotation_deg", "scale"]

var model: EditModel
var runner: ScriptRunner
## The shelf's library: the add-effect and layer shader menus also offer
## the user's shaders (bundled into the piece when picked). Optional.
var library: StudioAssetLibrary
## While a take runs, armed fields go to it instead of being written.
## Optional.
var recorder: StudioRecorder


# ---------- what an object has ----------

## "screen", "layer" or "object" (anything else: groups, cubes, prefabs);
## kind_for also says "camera" for the camera effects (EditModel.CAMERA).
static func kind_of(node: Node) -> String:
	if node is Visualizer:
		return "layer"
	if node is Screen:
		return "screen"
	return "object"


## kind_of `id`: its node's if it's on stage, else from its prefab (the
## built-in screen and layer).
func kind_for(id: String, node: Node = null) -> String:
	if id == EditModel.CAMERA:
		return "camera"
	if node != null:
		return kind_of(node)
	var i := model.spawn_index(id)
	var prefab := String(model.tracks()[i].get("prefab", "")) if i >= 0 else ""
	var path := String(model.document().get("prefabs", {}).get(prefab, ""))
	return {"res://player/prefabs/screen.tscn": "screen", "res://player/prefabs/layer.tscn": "layer"}.get(path, "object")


## The inspector's line under the name: its kind, its group, and when it's
## there ("Screen · in screen_split · 0:00.00 → 0:55.00"); the span is the
## one at `t`, else the first. `until` is the piece's length.
func describe(id: String, t: float, until: float, node: Node = null) -> String:
	var kind := kind_for(id, node)
	var parts: Array = [kind.capitalize()]
	if kind == "object":
		var i := model.spawn_index(id)
		parts[0] = String(model.tracks()[i].get("prefab", "object")).capitalize() if i >= 0 else "Object"
	for lane in StudioTimeline.lanes(model, until):
		if lane.id != id:
			continue
		if lane.parent != "":
			parts.append("in " + String(lane.parent))
		var spans: Array = lane.spans
		if not spans.is_empty():
			var span: Array = spans[0]
			for s in spans:
				if t >= s[0] and t <= s[1]:
					span = s
			parts.append("%s → %s" % [StudioStatus.timecode(span[0]), StudioStatus.timecode(span[1])])
	return " · ".join(parts)


## The inspector's sections for `id` (see the top). `node` is its spawned
## node, for what only the node knows (a custom prefab's material); null is
## fine. `kind` "" works it out (kind_for).
func sections(id: String, node: Node = null, kind: String = "") -> Array:
	if kind == "":
		kind = kind_for(id, node)
	if kind == "camera":
		var cam := model.effects_of(id)
		return range(cam.size()).map(func(i): return _effect_section(cam, i, EditModel.EFFECTS, true))
	var cfg := model.config_of(id)
	var out: Array = [{"title": "Transform", "kind": "transform", "fields": []}]
	match kind:
		"screen":
			out.append(surface_section(id))
			out.append({"title": "Display", "kind": "fields", "fields": [
				_float("opacity", "Opacity", 0.0, 1.0, 0.01, 1.0, ["opacity"], "display"),
				_blend(),
				_float("render_scale", "Render scale", 0.1, 2.0, 0.05, 1.0, ["render_scale"], ""),
				{"key": "fit_aspect", "label": "Fit to video", "type": "bool", "default": false,
					"config": ["fit_aspect"], "slot": "", "param": "fit_aspect",
					"tip": "Keep the video's own shape inside the screen (letterboxed or pillarboxed)"},
			]})
			var shader := String(cfg.get("shader", ""))
			if shader != "":
				out.append(_shader_section("Shader · %s" % shader.capitalize(), _resolve(shader), ["shader_params"], "surface"))
		"layer":
			var shader := String(cfg.get("shader", ""))
			var section := _shader_section("Layer shader", _resolve(shader), ["params"], "layer")
			section["shader"] = shader
			section["kind"] = "layer_shader"
			out.append(section)
			out.append(surface_section(id))
			out.append({"title": "Display", "kind": "fields", "fields": [
				_float("opacity", "Opacity", 0.0, 1.0, 0.01, 1.0, ["opacity"], "display"),
				_blend(),
				_float("resolution", "Resolution", 0.1, 2.0, 0.05, 1.0, ["resolution"], ""),
			]})
		_:
			var mat := ScriptRunner.surface_material(node) if node != null else null
			if mat != null and mat.shader != null:
				var hints := VisualizerShaders.parse_hints(mat.shader.code)
				# Its images would be keys only (there's no config to name them in).
				hints = {"params": hints.params.filter(func(p): return p.type != "texture"), "colors": hints.colors}
				var section := _hint_section("Material", hints, [], "surface")
				if not section.fields.is_empty():
					out.append(section)
	if kind != "object":
		for list in [EditModel.EFFECTS, EditModel.VERTEX_EFFECTS]:
			var effects := model.effects_of(id, list)
			for i in effects.size():
				out.append(_effect_section(effects, i, list))
	var mods: Array = []
	if kind == "object":  # a screen's or layer's fade is its display opacity
		mods.append(_float("mod_opacity", "Opacity", 0.0, 1.0, 0.01, 1.0, ["modifiers", "opacity"], "modifiers", "opacity"))
	mods.append(_color("tint", "Tint", false, Color.WHITE, ["modifiers", "tint"], "modifiers"))
	mods.append(_color("flash", "Flash", true, Color(1, 1, 1, 0), ["modifiers", "flash"], "modifiers"))
	mods.append(_float("speed", "Speed", 0.0, 4.0, 0.05, 1.0, ["modifiers", "speed"], "modifiers"))
	mods.append(_float("sort_offset", "Sort offset", -50.0, 50.0, 0.5, 0.0, ["modifiers", "sort_offset"], "modifiers"))
	out.append({"title": "Modifiers", "kind": "fields", "fields": mods})
	# Screens and layers spin and pulse with vertex effects (Spin, Pulse);
	# Reactive stays for other objects, and for a piece that already has it.
	if kind == "object" or cfg.has("reactive"):
		out.append({"title": "Reactive", "kind": "fields", "fields": [
			{"key": "spin", "label": "Spin °/s", "type": "vec3", "min": -360.0, "max": 360.0, "step": 1.0,
				"default": [0.0, 0.0, 0.0], "config": ["reactive", "spin"], "slot": "reactive", "param": "spin"},
			_float("pulse", "Pulse", 0.0, 1.0, 0.01, 0.0, ["reactive", "pulse"], "reactive"),
		]})
	return out


## Effect `i` of `list`'s section: its hinted params, keyed on its slot
## (`effect<N>` / `vertex<N>`) while it's on. `camera`: a camera effect
## (CameraFxShaders: its sliders, then its strength).
func _effect_section(effects: Array, i: int, list: String = EditModel.EFFECTS, camera := false) -> Dictionary:
	var e: Dictionary = effects[i] if typeof(effects[i]) == TYPE_DICTIONARY else {}
	var key := String(e.get("shader", ""))
	var vertex := list == EditModel.VERTEX_EFFECTS
	var path := _resolve_geometry(key) if vertex else _resolve(key)
	var slot := EditModel.effect_slot(effects, i)
	var name := "vertex" if vertex else "effect"
	var hints := {}
	if path != "" and camera:
		hints = {"params": CameraFxShaders.params_of(CameraFxShaders.code_for(path))}
	elif path != "":
		hints = {"params": ScreenGeometry.hints_for(path).params} if vertex else VisualizerShaders.hints_for(path)
	var title := camera_label(key, path) if camera else geometry_label(path, key) if vertex else effect_label(key, path)
	var section := _hint_section(title, hints, [list, i, "params"], "%s%d" % [name, slot] if slot >= 0 else "")
	if camera:
		section.fields.append(_float("strength", "Strength", 0.0, 1.0, 0.01, 1.0, [list, i, "strength"],
				"%s%d" % [name, slot] if slot >= 0 else ""))
	section.merge({"kind": "effect", "list": list, "index": i, "shader": key, "enabled": slot >= 0}, true)
	for f in section.fields:
		f.key = "%s%d/%s" % [name, i, f.param]
	return section


## A camera effect's name for people: the built-in's, else its file's.
static func camera_label(key: String, path: String) -> String:
	if CameraFxShaders.BUILTINS.has(path):
		return String(CameraFxShaders.BUILTINS[path][0])
	return path.get_file().get_basename().capitalize() if path != "" else key.capitalize()


# ---------- the surface ----------

## Where the picture sits as the piece says: {shader (a path), params,
## placement} (ScreenGeometry.normalized_surface). A piece from before
## surfaces, with `curvature` / `vertical_curvature`, shows the Pillow they
## make (as the player plays it).
func surface_of(id: String) -> Dictionary:
	var cfg := model.config_of(id)
	if typeof(cfg.get("surface")) == TYPE_DICTIONARY:
		var s: Dictionary = cfg.surface.duplicate(true)
		s["shader"] = _resolve_geometry(String(s.get("shader", "")))
		return ScreenGeometry.normalized_surface(s)
	var out := ScreenGeometry.default_surface()
	for pair in [["curvature", "arc_x"], ["vertical_curvature", "arc_y"]]:
		if cfg.has(pair[0]):
			out.params[pair[1]] = clampf(float(cfg[pair[0]]), 0.0, 1.0) * 180.0
	return out


## The Surface section: the surface picker, its placement and its params
## (on `<id>.shape`; the ones its placement ignores left out).
func surface_section(id: String) -> Dictionary:
	var s := surface_of(id)
	var hints := ScreenGeometry.hints_for(s.shader)
	var unused: Array = hints.unused.get(s.placement, [])
	var section := _hint_section("Surface", {"params": hints.params.filter(func(p): return not p.name in unused)},
			["surface", "params"], "shape")
	for f in section.fields:
		f.key = "shape/" + String(f.param)
	section.merge({"kind": "surface", "shader": s.shader, "placement": s.placement,
		"placements": ScreenGeometry.placements_for(s.shader), "hint": hints.hint,
		"label": geometry_label(s.shader, ""), "options": ScreenGeometry.list_options(ScreenGeometry.SURFACES_DIR)}, true)
	return section


## Give `id` the surface at `path` (an option's key), at its default
## placement, its params starting from their defaults. One undo step.
func set_surface_shader(id: String, path: String) -> String:
	if path == "" or path == surface_of(id).shader:
		return ""
	var s := {"shader": path, "params": {}, "placement": ScreenGeometry.default_placement(path)}
	var label := "Set %s's surface to %s" % [id, geometry_label(path, "")]
	return label if _write_surface(id, s, label) else ""


func set_surface_placement(id: String, placement: String) -> String:
	var s := surface_of(id)
	if placement == s.placement or not placement in ScreenGeometry.placements_for(s.shader):
		return ""
	s.placement = placement
	var label := "Place %s's surface %s" % [id, String(ScreenGeometry.PLACEMENT_LABELS.get(placement, placement)).to_lower()]
	return label if _write_surface(id, s, label) else ""


## Write surface `s` ({shader: a path, ...}) into `id`'s config, naming
## the shader (a built-in by name, else a `shaders` key), and drop an
## earlier piece's curvature, which would bend it back.
func _write_surface(id: String, s: Dictionary, label: String) -> bool:
	return model.batch(label, func():
		var key := EditModel.geometry_name(s.shader)
		if key == "":
			var b := StudioBundle.bundle(model.path.get_base_dir(), s.shader)
			key = model.name_shader(b.path if b.ok else s.shader)
		# One change of the whole config, so undo puts it back as it was.
		var cfg := model.config_of(id).duplicate(true)
		cfg["surface"] = {"shader": key, "params": s.params, "placement": s.placement}
		cfg.erase("curvature")
		cfg.erase("vertical_curvature")
		model.replace_config(id, cfg, label))



## A surface's or vertex effect's name for people: its @title (a built-in's
## label), else `key`'s or the file's.
static func geometry_label(path: String, key: String) -> String:
	if path != "":
		return VisualizerShaders.title_of(ScreenGeometry.read_code(path), path)
	return key.capitalize() if key != "" else "None"


## A surface's or vertex effect's config name to its path: a built-in's
## name ("ripple"), else a `shaders` key.
func _resolve_geometry(key: String) -> String:
	if ScreenGeometry.is_builtin_name(key) and not model.document().get("shaders", {}).has(key):
		return ScreenGeometry.resolve_builtin(key)
	return _resolve(key)


func _shader_section(title: String, path: String, config: Array, slot: String) -> Dictionary:
	return _hint_section(title, VisualizerShaders.hints_for(path) if path != "" else {}, config, slot)


## Fields from a shader's hints, in the shader's order, with the
## group_uniforms section each is in (`group`).
static func _hint_section(title: String, hints: Dictionary, config: Array, slot: String) -> Dictionary:
	var fields: Array = []
	for spec in hints.get("params", []):
		var f := {"key": spec.name, "label": _label(spec), "type": spec.type, "default": spec.default,
			"config": config + [spec.name] if not config.is_empty() else [],
			"slot": slot, "param": spec.name, "group": spec.get("group", ""), "at": spec.get("at", 0)}
		if spec.has("options"):  # a hint_enum int
			f.merge({"type": "choice", "options": spec.options, "values": range(spec.options.size()),
				"default": int(spec.default)}, true)
		elif spec.type in ["float", "int"]:
			f.merge({"min": spec.min, "max": spec.max, "step": spec.step})
		fields.append(f)
	for spec in hints.get("colors", []):
		var c: Color = spec.default
		fields.append({"key": spec.name, "label": _label(spec), "type": "color", "alpha": spec.alpha,
			"default": [c.r, c.g, c.b, c.a] if spec.alpha else [c.r, c.g, c.b],
			"config": config + [spec.name] if not config.is_empty() else [],
			"slot": slot, "param": spec.name, "group": spec.get("group", ""), "at": spec.get("at", 0)})
	fields.sort_custom(func(a, b): return a.at < b.at)
	return {"title": title, "kind": "fields", "fields": fields}


static func _label(spec: Dictionary) -> String:
	return String(spec.name).capitalize()


static func _float(key: String, label: String, lo: float, hi: float, step: float, default: float,
		config: Array, slot: String, param: String = "") -> Dictionary:
	return {"key": key, "label": label, "type": "float", "min": lo, "max": hi, "step": step,
		"default": default, "config": config, "slot": slot, "param": param if param != "" else key}


## How a screen or layer goes over what's behind it (Screen.BLENDS); keyed
## on the display slot, like opacity.
static func _blend() -> Dictionary:
	return {"key": "blend", "label": "Blend", "type": "choice", "default": "normal",
		"options": Screen.BLENDS.map(func(b): return Screen.BLEND_LABELS[b]), "values": Screen.BLENDS.duplicate(),
		"config": ["blend"], "slot": "display", "param": "blend",
		"tip": "Add adds its light (black adds nothing); Black transparent makes black see-through"}


## A choice field's name for `value` ("Add (light)"), or the value itself.
static func choice_label(field: Dictionary, value) -> String:
	var values: Array = field.get("values", [])
	var v = _typed(field, value)
	for i in values.size():
		if typeof(values[i]) == typeof(v) and values[i] == v:
			return String(field.options[i])
	return str(value)


static func _color(key: String, label: String, alpha: bool, default: Color, config: Array, slot: String) -> Dictionary:
	return {"key": key, "label": label, "type": "color", "alpha": alpha,
		"default": [default.r, default.g, default.b, default.a] if alpha else [default.r, default.g, default.b],
		"config": config, "slot": slot, "param": key}


## An effect's name for people: the built-in's label, else its key.
static func effect_label(key: String, path: String) -> String:
	for b in VisualizerShaders.builtins(true):
		if b.key == path:
			return b.label
	return key.capitalize()


func _resolve(key: String) -> String:
	if key == "":
		return ""
	var shaders = model.document().get("shaders", {})
	var rel := String(shaders.get(key, "")) if typeof(shaders) == TYPE_DICTIONARY else ""
	if rel == "":
		return ""
	var data := TimelineData.new()
	data.base_dir = model.path.get_base_dir() if model.path != "" else ""
	return data.resolve(rel)


# ---------- values and keys ----------

## The field's track index, -1 if it has none (or can't have one).
func track_of(id: String, field: Dictionary) -> int:
	if String(field.slot) == "":
		return -1
	return model.find_track(ScriptFormat.TRACK_SHADER_PARAM, "%s.%s" % [id, field.slot], field.param)


## The field's value at `t` as JSON has it: its track's there, else the
## config's, else the shader's default.
func value_of(id: String, field: Dictionary, t: float):
	var ti := track_of(id, field)
	if ti >= 0:
		var v = Interpolation.evaluate(model.tracks()[ti].get("keyframes", []), t)
		if v != null:
			return _typed(field, v)
	if field.config.size() == 3 and field.config[0] == "surface":
		return _typed(field, surface_of(id).params.get(field.param, field.default))
	if not field.config.is_empty():
		var at = _config_value(id, field.config)
		if at != null:
			return _typed(field, at)
	return field.default


func _config_value(id: String, path: Array):
	var node = model.config_of(id)
	for k in path:
		if typeof(node) == TYPE_DICTIONARY and node.has(k):
			node = node[k]
		elif typeof(node) == TYPE_ARRAY and typeof(k) == TYPE_INT and k >= 0 and k < node.size():
			node = node[k]
		else:
			return null
	return node


## A value in the field's shape (a colour from JSON as an array, and so on).
static func _typed(field: Dictionary, v):
	match field.type:
		"bool":
			return bool(v)
		"int":
			return int(round(float(v)))
		"float":
			return float(v)
		"color":
			var c := Modifiers._color(v, Color.WHITE)
			return [c.r, c.g, c.b, c.a] if field.get("alpha", false) else [c.r, c.g, c.b]
		"vec3":
			var x := Interpolation.to_vec3(v)
			return [x.x, x.y, x.z]
		"choice":
			var values: Array = field.get("values", [])
			if not values.is_empty() and typeof(values[0]) == TYPE_INT:
				return int(round(float(v))) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else int(field.default)
			return String(v) if typeof(v) == TYPE_STRING else String(field.default)
		"texture":
			return String(v) if typeof(v) == TYPE_STRING else ""
	return v


## "key" (a key at the playhead), "animated", "static", or "none" (it
## can't be keyed): what the diamond shows.
func key_state(id: String, field: Dictionary, t: float) -> String:
	if String(field.slot) == "":
		return "none"
	var ti := track_of(id, field)
	if ti < 0:
		return "static"
	return "key" if key_near(model.tracks()[ti].get("keyframes", []), t) >= 0 else "animated"


## The key within KEY_NEAR of `t` (the nearest), -1 if none.
static func key_near(kfs: Array, t: float) -> int:
	var best := -1
	var best_d := KEY_NEAR
	for i in kfs.size():
		var d := absf(float(kfs[i].get("t", 0.0)) - t)
		if d <= best_d:
			best = i
			best_d = d
	return best


## When a key at `t` lands: on the key already near it, if there is one.
func _key_time(ti: int, t: float) -> float:
	if ti < 0:
		return t
	var kfs: Array = model.tracks()[ti].get("keyframes", [])
	var k := key_near(kfs, t)
	return float(kfs[k].get("t", t)) if k >= 0 else t


# ---------- changing ----------

## Show `value` live while a control is dragged (nothing is written).
func preview(id: String, field: Dictionary, value) -> void:
	if runner == null or String(field.slot) == "":
		return
	runner.held_params["%s.%s:%s" % [id, field.slot, field.param]] = true
	runner.preview_param(id, field.slot, field.param, _as_value(field, value))
	if recorder != null:
		recorder.touch_param(id, field, _typed(field, _as_json(value)))


## Stop holding the field (after a commit, or to cancel a preview: then
## the runner shows the piece's value again).
func end_preview(id: String, field: Dictionary, restore: bool = false) -> void:
	if runner == null or (recorder != null and recorder.owns_param(id, field)):
		return  # the take holds it until it ends
	runner.held_params.erase("%s.%s:%s" % [id, field.slot, field.param])
	if restore:
		runner.apply_edit(model.timeline(), false)


## Write `value` for the field (see the top). Returns the undo label, ""
## if nothing changed.
## `key_animated`: a field that already has keys gets one at `t` rather
## than having them all moved (StudioEditTools.key_animated).
func commit(id: String, field: Dictionary, value, t: float, auto_key: bool, key_animated: bool = false) -> String:
	if recorder != null and recorder.owns_param(id, field):
		return ""  # recorded: the take writes it when it ends
	value = _typed(field, _as_json(value))
	var held: bool = field.type in ["bool", "choice", "texture"]  # no in-between: keys, never scaled
	if field.type == "texture" and value != "":
		value = bundle_image(value)
		if value == "":
			return ""
	var ti := track_of(id, field)
	var slot := String(field.slot)
	var target := "%s.%s" % [id, slot]
	var what := "%s %s" % [EditModel.who(id), String(field.label).to_lower()]
	var label := ""
	var done := false
	if slot == "":
		label = "Set %s" % what
		done = _set_config(id, field.config, value, label)
	elif auto_key or field.config.is_empty() or (ti >= 0 and (held or key_animated
			or key_near(model.tracks()[ti].get("keyframes", []), t) >= 0)):
		var at := _key_time(ti, t)
		label = "Key %s at %s" % [what, StudioStatus.timecode(at)]
		var interp := _key_interp(field)
		done = model.batch(label, func(): model.set_key(ScriptFormat.TRACK_SHADER_PARAM, target, field.param, at, value, interp))
	elif ti >= 0:
		var now = value_of(id, field, t)
		label = "Move %s's keys" % what
		done = model.set_keyframes(ti, _shifted(model.tracks()[ti].get("keyframes", []), now, value), label)
	else:
		label = "Set %s" % what
		done = _set_config(id, field.config, value, label)
	return label if done else ""


## set_config, and for a surface param first the surface as it plays (an
## earlier piece's curvature becomes its Pillow), all one step.
func _set_config(id: String, path: Array, value, label: String) -> bool:
	if path.is_empty() or path[0] != "surface" or typeof(model.config_of(id).get("surface")) == TYPE_DICTIONARY:
		return model.set_config(id, path, value, label)
	return model.batch(label, func():
		_write_surface(id, surface_of(id), label)
		model.set_config(id, path, value, label))


## Tap on a field's diamond: remove the key at the playhead, or add one
## there with the value it has now. Returns the undo label ("" if none).
func toggle_key(id: String, field: Dictionary, t: float) -> String:
	if String(field.slot) == "":
		return ""
	var ti := track_of(id, field)
	if ti >= 0:
		var k := key_near(model.tracks()[ti].get("keyframes", []), t)
		if k >= 0:
			var kt := float(model.tracks()[ti].keyframes[k].get("t", t))
			var label := "Delete %s %s key at %s" % [EditModel.who(id), String(field.label).to_lower(), StudioStatus.timecode(kt)]
			return label if model.batch(label, func(): model.delete_key(ti, k)) else ""
	var value = value_of(id, field, t)
	var label := "Key %s %s at %s" % [EditModel.who(id), String(field.label).to_lower(), StudioStatus.timecode(t)]
	var interp := _key_interp(field)
	return label if model.batch(label, func():
		model.set_key(ScriptFormat.TRACK_SHADER_PARAM, "%s.%s" % [id, field.slot], field.param, t, value, interp)) else ""


## A new key's interp: "step" for what can't be in between (a choice, an
## image), else the track's way ("").
static func _key_interp(field: Dictionary) -> String:
	return "step" if field.type in ["choice", "texture"] else ""


## A transform channel's diamond: "key", "animated" or "static".
func transform_state(id: String, channel: String, t: float) -> String:
	var ti := model.find_track(ScriptFormat.TRACK_TRANSFORM, id, channel)
	if ti < 0:
		return "static"
	return "key" if key_near(model.tracks()[ti].get("keyframes", []), t) >= 0 else "animated"


## Tap on a transform channel's diamond: remove its key at the playhead, or
## key where the object is now (`now`: node-style dict, GrabMath.to_dict).
func toggle_transform_key(id: String, channel: String, t: float, now: Dictionary) -> String:
	var ti := model.find_track(ScriptFormat.TRACK_TRANSFORM, id, channel)
	if ti >= 0:
		var k := key_near(model.tracks()[ti].get("keyframes", []), t)
		if k >= 0:
			var kt := float(model.tracks()[ti].keyframes[k].get("t", t))
			var label := "Delete %s %s key at %s" % [id, channel, StudioStatus.timecode(kt)]
			return label if model.batch(label, func(): model.delete_key(ti, k)) else ""
	var label := "Key %s %s at %s" % [id, channel, StudioStatus.timecode(t)]
	return label if model.batch(label, func():
		model.set_key(ScriptFormat.TRACK_TRANSFORM, id, channel, t, now[channel])) else ""


## Keys moved as a whole so the value at the playhead goes from `from` to
## `to`: scaled by to / from (so a fade from 0 still starts at 0 and the
## curve keeps its shape; bezier handles scale with it), or, where `from`
## is 0, shifted by the difference. Arrays (a colour, a vector) per element.
static func _shifted(kfs: Array, from, to) -> Array:
	var out: Array = kfs.duplicate(true)
	var arrays := typeof(from) == TYPE_ARRAY and typeof(to) == TYPE_ARRAY
	var n: int = mini(from.size(), to.size()) if arrays else 1
	var moves: Array = []  # per element: [ratio, add]
	for c in n:
		var a := float(from[c]) if arrays else float(from)
		var b := float(to[c]) if arrays else float(to)
		moves.append([b / a, 0.0] if absf(a) > 1e-6 else [1.0, b - a])
	for kf in out:
		var v = kf.get("value")
		if arrays and typeof(v) == TYPE_ARRAY:
			var nv: Array = []
			for c in v.size():
				nv.append(float(v[c]) * moves[c][0] + moves[c][1] if c < n else float(v[c]))
			kf["value"] = nv
			for h in ["in", "out"]:
				if typeof(kf.get(h)) == TYPE_ARRAY and kf[h].size() == v.size():
					for c in mini(n, v.size()):
						kf[h][c][1] = float(kf[h][c][1]) * moves[c][0]
		elif not arrays and typeof(v) in [TYPE_FLOAT, TYPE_INT]:
			kf["value"] = float(v) * moves[0][0] + moves[0][1]
			for h in ["in", "out"]:
				if typeof(kf.get(h)) == TYPE_ARRAY and kf[h].size() == 2:
					kf[h][1] = float(kf[h][1]) * moves[0][0]
	return out


## A control's value as JSON holds it (a Color becomes [r, g, b(, a)]).
func _as_json(value):
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Vector3:
		return [value.x, value.y, value.z]
	return value


## What the runner should be given for the field (a colour as a Color, so a
## vec3 / vec4 uniform or a modifier takes it).
func _as_value(field: Dictionary, value):
	value = _typed(field, _as_json(value))
	if field.type == "color":
		return Color(value[0], value[1], value[2], value[3] if value.size() > 3 else 1.0) if field.slot == "modifiers" \
				else (Vector4(value[0], value[1], value[2], value[3]) if value.size() > 3 else Vector3(value[0], value[1], value[2]))
	return value


# ---------- the effects stack ----------

## Effects that can be added: [{key (a shader path), label}]: the built-ins,
## the piece's own effect shaders, and the user's (from the library).
## `list` VERTEX_EFFECTS: the vertex effects (built-ins and the user's
## `shaders/vertex/` snippets). For EditModel.CAMERA (`id`), camera
## effects: the built-ins, the piece's and the user's `// @camera` files.
func effect_options(list: String = EditModel.EFFECTS, id: String = "") -> Array:
	if id == EditModel.CAMERA:
		var out: Array = []
		var seen := {}
		for o in CameraFxShaders.list_options():
			var yours := not String(o.key).begins_with(CameraFxShaders.BUILTIN_PREFIX)
			out.append({"key": o.key, "label": "%s (yours)" % o.label if yours else o.label})
			seen[o.key] = true
		var shaders = model.document().get("shaders", {})
		for k in shaders:
			var path := _resolve(k)
			if not seen.has(path) and not path.begins_with(CameraFxShaders.BUILTIN_PREFIX) \
					and CameraFxShaders.is_camera_code(CameraFxShaders.code_for(path)):
				out.append({"key": String(shaders[k]), "label": "%s (piece)" % String(k).capitalize()})
				seen[path] = true
		return out
	if list == EditModel.VERTEX_EFFECTS:
		var dirs := library.vertex_dirs() if library != null else ScreenGeometry.search_dirs(ScreenGeometry.VERTEX_DIR)
		return ScreenGeometry.list_options(ScreenGeometry.VERTEX_DIR, dirs).map(func(o): return {"key": o.key, "label": o.label})
	return _shader_options(VisualizerShaders.builtins(true), true)


## Layer shaders that can be picked: [{key (path), label}], the same way,
## after the playing video itself (VisualizerShaders.VIDEO).
func layer_shader_options() -> Array:
	return [{"key": VisualizerShaders.VIDEO, "label": "Video"}] + _shader_options(VisualizerShaders.builtins(false), false)


## The folder in a piece that picked images are copied into.
const IMAGES_DIR := "images"


## Images an image field can pick: [{key (a path), label}]: None, the
## piece's own (in its images/ folder) and the user's (ImageLibrary's
## folders), and `current` if it's none of those.
func image_options(current: String = "") -> Array:
	var out: Array = [{"key": "", "label": "None"}]
	var seen := {"": true}
	var dirs: Array[String] = []
	if model.path != "":
		dirs.append(model.path.get_base_dir().path_join(IMAGES_DIR))
	dirs.append_array(ImageLibrary.search_dirs())
	for o in ImageLibrary.list_options(dirs):
		var key := _piece_relative(o.key)
		if not seen.has(key):
			out.append({"key": key, "label": o.label})
			seen[key] = true
	if not seen.has(current):
		out.append({"key": current, "label": ImageLibrary.label_of(current)})
	return out


## `path` as the piece names it: relative when it's in the piece's folder.
func _piece_relative(path: String) -> String:
	if model.path == "":
		return path
	var rel := StudioBundle.relative_to(path, model.path.get_base_dir())
	return rel if rel != "" else path


## An image for the piece: its path relative to the piece, copied into its
## images/ folder when it's outside it; "" (and a warning) if it can't be.
func bundle_image(path: String) -> String:
	if not path.is_absolute_path() or model.path == "":
		return path
	var b := StudioBundle.bundle(model.path.get_base_dir(), path, IMAGES_DIR)
	if not b.ok:
		push_warning(b.error)
		return ""
	return b.path


func _shader_options(builtins: Array, effects: bool) -> Array:
	var out: Array = []
	var seen := {}
	for b in builtins:
		out.append({"key": b.key, "label": b.label})
		seen[b.key] = true
	var shaders = model.document().get("shaders", {})
	for k in shaders:
		var path := _resolve(k)
		if path.begins_with("res://player/") or seen.has(path):
			continue
		var shader := VisualizerShaders.load_shader(path)
		if shader != null and VisualizerShaders.is_effect_code(shader.code) == effects:
			out.append({"key": String(shaders[k]), "label": String(k).capitalize()})
			seen[path] = true
	if library != null:
		for a in library.of_type("effect" if effects else "layer"):
			if a.source != "builtin" and not seen.has(a.path):
				out.append({"key": a.path, "label": "%s (%s)" % [a.label, "piece" if a.source == "piece" else "yours"]})
				seen[a.path] = true
	return out


## Add the effect at `path` (an option's key) to `id`'s `list`, bundling a
## user shader into the piece first (built-in vertex effects go by name).
## One undo step.
func add_effect(id: String, path: String, list: String = EditModel.EFFECTS) -> bool:
	if EditModel.geometry_name(path) != "":
		return model.add_effect(id, path, {}, -1, list)
	var vertex_dir := "shaders/" + ScreenGeometry.VERTEX_DIR if list == EditModel.VERTEX_EFFECTS else ""
	var b := StudioBundle.bundle(model.path.get_base_dir(), path, vertex_dir)
	return b.ok and model.add_effect(id, b.path, {}, -1, list)



## Give layer `id` the shader at `path`, bundling a user shader first.
func set_layer_shader(id: String, path: String) -> bool:
	if path == VisualizerShaders.VIDEO:
		return model.set_config(id, ["shader"], path, "Set %s's source to the video" % id)
	var b := StudioBundle.bundle(model.path.get_base_dir(), path)
	return b.ok and model.set_shader(id, b.path)
