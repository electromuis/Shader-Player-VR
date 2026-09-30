class_name GpuCost
extends Node

## What each part of the picture costs in GPU time, for the Performance tab
## (the player's menu and Studio's) and the benchmark (GpuBenchmark).
##
## Two ways of measuring:
##   - **Passes** (always, while `active`): every layer shader, effect,
##     video frame and menu panel draws in a SubViewport of its own, and
##     Godot times each viewport on the GPU
##     (RenderingServer.viewport_set_measure_render_time). So their costs are
##     read directly, every frame, with nothing switched off. A screen's
##     passes are named after its owner: a script object's id, or the
##     player's own layers by their shader (Screen.gpu_passes says which
##     pass is which). The two eyes of a stereo chain, an effect's prepass
##     and its blend pass count as the effect.
##   - **The view** (on demand, probe()): the main viewport draws the 3D
##     scene itself: objects, surfaces and vertex effects, 3D (mainVR)
##     layers, the camera effect, the sky and panels. Its time is one
##     number; probe() splits it by switching each object, layer and the
##     camera effect off in turn for a few frames and timing how much
##     faster the view gets. Things blink while it runs, so it's a button.
##
## Passes drawn on demand (the video frame, a still screen's chain) report
## the time of their last draw, so they read a little high when the frame
## isn't redrawn every display frame. GPU times arrive a couple of frames
## late; the readout is smoothed over about ten frames.
##
## Costs nothing while inactive: the viewports are only timed and the tree
## is only looked at (RESCAN) while something asks (set_active).

## Every frame's numbers are in (frame_ms, frame_parts); the smoothed ones too.
signal measured
## A probe finished (or was cancelled): probe_ms holds its results.
signal probed

const RESCAN := 0.5  # seconds between looking for new passes
const SMOOTH := 0.1  # per frame: about ten frames' average
## Probe: frames to wait after switching something (GPU times lag behind),
## then frames to time.
const PROBE_SETTLE := 5
const PROBE_FRAMES := 8
const VIEW := "view"
## Default display rate when the screen doesn't say (and the Quest 3's
## usual one in the headset when the runtime doesn't).
const FALLBACK_HZ := 60.0
const XR_FALLBACK_HZ := 72.0

var stage: Stage
## Timing and rescanning run only while active (set_active); every user
## (the tab, a benchmark, a probe) holds it with a name, so one finishing
## doesn't switch off another's.
var _holders: Dictionary = {}

## Last frame: all GPU time (ms), and per part key.
var frame_ms := 0.0
var frame_parts: Dictionary = {}
## Smoothed over about ten frames.
var total_ms := 0.0
var smoothed: Dictionary = {}  # key -> ms
## key -> {label, kind, select}: what a part is (select: the script object's
## id, for Studio to select it; "" if none).
var parts: Dictionary = {}
## The last probe's results: key -> {label, kind, select, ms}.
var probe_ms: Dictionary = {}
var probing := false

var _tracked: Array[Dictionary] = []  # [{viewport, key}]
var _since_scan := RESCAN
var _probe_cancel := false
static var _labels: Dictionary = {}  # shader key -> title (shader_label)


func _init() -> void:
	name = "GpuCost"


func is_active() -> bool:
	return not _holders.is_empty()


## Start or stop measuring for `who` (any name): measuring runs while
## anyone holds it.
func set_active(who: String, on: bool) -> void:
	var was := is_active()
	if on:
		_holders[who] = true
	else:
		_holders.erase(who)
	if is_active() == was:
		return
	if is_active():
		_since_scan = RESCAN
		_measure_view(true)
	else:
		for t in _tracked:
			_measure(t.viewport, false)
		_tracked.clear()
		_measure_view(false)
		frame_parts.clear()
		smoothed.clear()
		frame_ms = 0.0
		total_ms = 0.0


## The frame time the display allows (ms): the headset's refresh rate in
## VR, else the monitor's.
func budget_ms() -> float:
	return 1000.0 / refresh_hz()


func refresh_hz() -> float:
	var in_vr := stage != null and stage.xr_mode != null and stage.xr_mode.is_in_vr()
	if in_vr:
		var xr := XRServer.primary_interface
		if xr != null and xr.has_method("get_display_refresh_rate"):
			var hz: float = xr.get_display_refresh_rate()
			if hz > 0.0:
				return hz
		return XR_FALLBACK_HZ
	var screen_hz := DisplayServer.screen_get_refresh_rate()
	return screen_hz if screen_hz > 0.0 else FALLBACK_HZ


## The parts, heaviest first: [{key, label, kind, select, ms}] from the
## smoothed times, the view split by the last probe when there is one
## (what the probe didn't account for stays as the view's rest).
func ranked() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var probed_sum := 0.0
	for key in probe_ms:
		var p: Dictionary = probe_ms[key]
		out.append({"key": key, "label": p.label, "kind": p.kind, "select": p.select, "ms": p.ms})
		probed_sum += p.ms
	for key in smoothed:
		var ms: float = smoothed[key]
		if key == VIEW:
			var rest := maxf(0.0, ms - probed_sum)
			out.append({"key": VIEW, "label": "the rest of the view" if not probe_ms.is_empty() else "3D view",
					"kind": "sky, panels…" if not probe_ms.is_empty() else "objects, surfaces, camera effect",
					"select": "", "ms": rest})
			continue
		var info: Dictionary = parts.get(key, {"label": key, "kind": "", "select": ""})
		out.append({"key": key, "label": info.label, "kind": info.kind, "select": info.select, "ms": ms})
	out.sort_custom(func(a, b): return a.ms > b.ms)
	return out


func _process(delta: float) -> void:
	if not is_active():
		return
	_since_scan += delta
	if _since_scan >= RESCAN:
		_since_scan = 0.0
		rescan()
	var now: Dictionary = {}
	var sum := 0.0
	for t in _tracked:
		var vp: Viewport = t.viewport
		if not is_instance_valid(vp):
			continue
		var ms := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		now[t.key] = float(now.get(t.key, 0.0)) + ms
		sum += ms
	var view := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	now[VIEW] = view
	sum += view
	frame_parts = now
	frame_ms = sum
	total_ms = lerpf(total_ms, sum, SMOOTH) if total_ms > 0.0 else sum
	for key in now:
		smoothed[key] = lerpf(float(smoothed[key]), now[key], SMOOTH) if smoothed.has(key) else float(now[key])
	for key in smoothed.keys():
		if not now.has(key):
			smoothed.erase(key)  # gone (despawned, effect removed)
	measured.emit()


## Look for the passes to time: every Screen's (named by owner), the video
## frame's, and any other SubViewport (menus, previews).
func rescan() -> void:
	var ids := _registry_ids()
	var seen: Dictionary = {}  # viewport -> true
	var found: Array[Dictionary] = []
	var new_parts: Dictionary = {}
	for node in get_tree().get_nodes_in_group(VisualizerShaders.RELOAD_GROUP):
		# A generator's layer's screen counts under its host (Screen.nested).
		if not (node is Screen) or not node.is_inside_tree() or node.nested:
			continue
		var screen := node as Screen
		var owner_info := describe_owner(screen, ids)
		for p in screen.gpu_passes():
			var d := describe_pass(owner_info, p)
			found.append({"viewport": p.viewport, "key": d.key})
			new_parts[d.key] = d
			seen[p.viewport] = true
	for vp in get_tree().root.find_children("*", "SubViewport", true, false):
		if seen.has(vp) or (vp as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED:
			continue
		var d := describe_viewport(vp)
		found.append({"viewport": vp, "key": d.key})
		new_parts[d.key] = d
	# Switch timing off for what's gone, on for what's new.
	var now_set: Dictionary = {}
	for f in found:
		now_set[f.viewport] = true
	for t in _tracked:
		if is_instance_valid(t.viewport) and not now_set.has(t.viewport):
			_measure(t.viewport, false)
	for f in found:
		_measure(f.viewport, true)
	_tracked = found
	parts = new_parts


## Who a screen belongs to: {label, select, layer}: the script object (its
## registry id) it's under, else a player layer (by its shader), else the
## main screen.
static func describe_owner(screen: Node, ids: Dictionary) -> Dictionary:
	var layer: Visualizer = null
	var n: Node = screen
	while n != null:
		if ids.has(n):
			return {"label": String(ids[n]), "select": String(ids[n]), "layer": n is Visualizer}
		if n is Visualizer and layer == null:
			layer = n
		n = n.get_parent()
	if layer != null:
		return {"label": "Layer · " + shader_label(layer.get_shader_key()), "select": "", "layer": true}
	return {"label": "main screen", "select": "", "layer": false}


## One of Screen.gpu_passes' entries, named: {key, label, kind, select}.
static func describe_pass(owner_info: Dictionary, p: Dictionary) -> Dictionary:
	var label: String = owner_info.label
	var kind := ""
	var key := ""
	match String(p.part):
		"shader":
			key = "%s|shader" % label
			kind = "layer · shader" if owner_info.layer else "screen · shader"
		"effect":
			key = "%s|effect%d" % [label, int(p.effect)]
			label = "%s · %s" % [label, shader_label(p.key)]
			kind = "effect"
		_:
			key = "%s|copy" % label
			label = "%s · picture copy" % label
			kind = "screen pass"
	return {"key": key, "label": label, "kind": kind, "select": owner_info.select}


## A viewport that isn't a screen's: the video frame, a menu panel, or
## something else (named after its parent).
static func describe_viewport(vp: Node) -> Dictionary:
	var n := vp.get_parent()
	while n != null:
		if n is VideoBridge:
			return {"key": "video", "label": "video frame", "kind": "video", "select": ""}
		var script: Script = n.get_script()
		if script != null and script.get_global_name() == &"XRToolsViewport2DIn3D":
			return {"key": "menus", "label": "menus and panels", "kind": "UI", "select": ""}
		n = n.get_parent()
	var parent := vp.get_parent()
	var label := String(parent.name) if parent != null else String(vp.name)
	return {"key": "other|" + label, "label": label, "kind": "other pass", "select": ""}


## Split the view's time: switch each object, player layer and the camera
## effect off in turn and time how much faster the view draws. Results in
## probe_ms; `probed` when done. Things blink while it runs.
func probe() -> void:
	if probing or stage == null:
		return
	probing = true
	_probe_cancel = false
	set_active("probe", true)
	var results: Dictionary = {}
	for c in _probe_candidates():
		if _probe_cancel:
			break
		var base := await _time_view()
		if not c.off.call():
			continue
		var without := await _time_view()
		c.on.call()
		results[c.key] = {"label": c.label, "kind": c.kind, "select": c.select, "ms": maxf(0.0, base - without)}
	probe_ms = results if not _probe_cancel else probe_ms
	probing = false
	set_active("probe", false)
	probed.emit()


func cancel_probe() -> void:
	_probe_cancel = true


func clear_probe() -> void:
	probe_ms = {}


## The view's average GPU time over PROBE_FRAMES, after PROBE_SETTLE.
func _time_view() -> float:
	for i in PROBE_SETTLE:
		await get_tree().process_frame
	var sum := 0.0
	for i in PROBE_FRAMES:
		await get_tree().process_frame
		sum += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	return sum / PROBE_FRAMES


## What probe() switches off: [{key, label, kind, select, off, on}] (off
## returns false if there's nothing to switch, e.g. already hidden).
func _probe_candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := _registry_ids()
	var nodes: Array = ids.keys()
	for node in nodes:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		# Only the outermost: a group's children go with it.
		var inner := false
		var up: Node = node.get_parent()
		while up != null:
			if ids.has(up):
				inner = true
				break
			up = up.get_parent()
		if inner:
			continue
		out.append(_hide_candidate(node, String(ids[node]), String(ids[node]),
				"surface, vertex fx" if _has_screen(node) else "object"))
	for layer in stage._layer_nodes:
		if is_instance_valid(layer) and not ids.has(layer):
			var label := "Layer · " + shader_label(layer.get_shader_key())
			out.append(_hide_candidate(layer, label, "", "surface, vertex fx"))
	var fx := stage.camera_fx
	if fx != null and fx.is_running():
		out.append({"key": "probe|camera", "label": "camera effect", "kind": "camera effect", "select": "",
			"off": func() -> bool:
				fx.enabled = false
				return true,
			"on": func() -> void: fx.enabled = true})
	return out


func _hide_candidate(node: Node3D, label: String, select: String, kind: String) -> Dictionary:
	return {"key": "probe|" + label, "label": label, "kind": kind, "select": select,
		"off": func() -> bool:
			if not is_instance_valid(node) or not node.visible:
				return false
			node.visible = false
			return true,
		"on": func() -> void:
			if is_instance_valid(node):
				node.visible = true}


## VisualizerShaders.source_label, remembered (it reads the file).
static func shader_label(key: String) -> String:
	if not _labels.has(key):
		_labels[key] = VisualizerShaders.source_label(key)
	return _labels[key]


static func _has_screen(node: Node) -> bool:
	if node is Screen:
		return true
	for c in node.get_children():
		if _has_screen(c):
			return true
	return false


## node -> id for the runner's objects (spawned and external).
func _registry_ids() -> Dictionary:
	var out: Dictionary = {}
	if stage == null or stage.runner == null:
		return out
	var reg := stage.runner.registry()
	if reg == null:
		return out
	for id in reg.all_ids():
		if reg.has_id(id):
			out[reg.get_node_by_id(id)] = id
	return out


static func _measure(vp: Viewport, on: bool) -> void:
	if is_instance_valid(vp):
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), on)


func _measure_view(on: bool) -> void:
	if is_inside_tree():
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), on)
