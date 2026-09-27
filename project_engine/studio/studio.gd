extends Node3D

## Studio: the VR editor for VJ scripts (see "VR Studio — Plan.md"). It
## runs a piece on the player's own Stage (player/stage/), so what you see
## while editing is what the player shows, and edits it through an
## EditModel: every change is an undoable command on the script JSON,
## which the runner picks up in place (ScriptRunner.apply_edit).
##
## Two modes, one button: Play is the audience view with no UI; Edit shows
## the tools: the status and palette on the left wrist (the status in the
## desktop corner), picking, grabbing, snapping and flight (StudioEditTools,
## StudioFlight). Switching keeps the playhead.
##
## Editing by hand: the right trigger selects what the laser points at; a
## grip grabs it (the right stick pushes / pulls it along the laser); the
## other grip joins in to scale and turn it with both hands. Letting go
## writes the move (auto-key on: keys at the playhead; off: its placement).
## On the desktop the mouse does the same: click selects, drag moves (the
## wheel pushes / pulls while dragging).
##
## The timeline ribbon (StudioTimelineRibbon) shows the song's waveform and
## beats, cuts, each object's time on stage and the selection's keys: scrub,
## retime keys (onto beats while snapping), pick their interpolation, and
## set a loop region that playback repeats (StudioLoop). On the desktop it's
## a strip along the bottom; in the headset a band at waist height.
##
## The inspector (StudioInspector) shows the selection's settings: display,
## the layer's shader, the effects stack, modifiers and reactive motion,
## with a key diamond per property. On the desktop it's a side panel; in
## the headset a panel beside the selection, placed when you select
## something (or show it again) and turned toward you.
##
## The asset shelf (StudioAssetShelf) has cards for what can be added:
## screens, cubes, your prefabs, layer shaders and effects (built-in, yours,
## the piece's own; StudioAssetLibrary, with StudioThumbnailer's pictures).
## Press a card to pick it up and let go where it should go in the world
## (or click the card, then click the spot); StudioAssetDrop writes it, and
## bundles a user asset into the piece's folder (StudioBundle). Its Open tab
## opens pieces, or a video to start a new piece. On the desktop it's a
## panel on the left; in the headset a panel to your front left. Files
## dropped on the window: a piece or video opens, a shader or prefab goes
## into the piece.
##
## Performance recording (StudioRecorder): arm properties with the
## inspector's record dots, press Record (wrist, Shift+R): playback starts
## a pre-roll early and, from the loop's in point (or where you were), what
## you touch is recorded: armed sliders and anything you grab. Stopping
## (Record again, pause, or the loop's out point) writes the take as keys,
## one undo step; Esc drops it.
##
## Command line (after `--`): --piece <script.json, or a video: its
## same-name .json, made empty if there's none>, --start <seconds>, --vr,
## --desktop, --library <folder> (more assets for the shelf; repeatable).

## Scrubbing speed at full stick, in seconds of timeline per second.
const SCRUB_SPEED := 20.0
const STEP_SECONDS := 1.0
const SEEK_SECONDS := 10.0
const WRIST_SCENE := preload("res://studio/ui/wrist_palette.tscn")
## The wrist palette's size in metres and pixels (bigger than the player's
## wrist HUD: it has buttons).
const WRIST_SIZE := Vector2(0.26, 0.315)
const WRIST_PIXELS := Vector2(780, 945)
## Push / pull speed with the right stick while grabbing (m/s at full push).
const PUSH_SPEED := 2.5
## Desktop: a mouse wheel notch pushes / pulls this far.
const WHEEL_PUSH := 0.25
const INSPECTOR_SCENE := preload("res://studio/ui/inspector.tscn")
const VP2D3D_SCENE := preload("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn")
## The headset inspector's size in metres and pixels, and where it goes:
## this far from your head, turned right of the selection (enough to clear
## it as you see it, within these angles), a little below eye height. It's
## placed again when you're further than INSPECTOR_REPLACE from it.
const INSPECTOR_SIZE := Vector2(0.42, 0.6)
const INSPECTOR_PIXELS := Vector2(720, 1030)
const INSPECTOR_DISTANCE := 0.75
const INSPECTOR_ANGLE := 32.0
const INSPECTOR_MAX_ANGLE := 60.0
const INSPECTOR_DROP := 0.12
const INSPECTOR_REPLACE := 2.0
const RIBBON_SCENE := preload("res://studio/ui/timeline_ribbon.tscn")
## The headset ribbon: its size in metres and pixels, and where it goes:
## this far in front of you, this far below your eyes, tilted back to face
## you. It follows you like the inspector.
const RIBBON_SIZE := Vector2(1.3, 0.36)
const RIBBON_PIXELS := Vector2(1800, 500)
const RIBBON_DISTANCE := 0.6
const RIBBON_DROP := 0.55
const RIBBON_TILT := 40.0
const SHELF_SCENE := preload("res://studio/ui/asset_shelf.tscn")
## The headset shelf: its size in metres and pixels, and where it goes: this
## far from you, turned this far left of where you look, a little below
## your eyes, facing you. It follows you like the inspector.
const SHELF_SIZE := Vector2(0.8, 0.5)
const SHELF_PIXELS := Vector2(1280, 800)
const SHELF_DISTANCE := 0.75
const SHELF_ANGLE := 38.0
const SHELF_DROP := 0.15
## How often the shelf's folders are checked for new or changed files.
const WATCH_SECONDS := 2.0
## A carried card's picture in the world, this wide (metres).
const GHOST_WIDTH := 0.36

enum Mode { PLAY, EDIT }

@onready var stage: Stage = $Stage
@onready var runner: ScriptRunner = $Stage/ScriptRunner
@onready var status_view: StudioStatus = $UI/Status
@onready var inspector: StudioInspector = $UI/Inspector
@onready var ribbon: StudioTimelineRibbon = $UI/Timeline
@onready var shelf: StudioAssetShelf = $UI/Shelf

## The piece being edited; null until one is open.
var model: EditModel
var mode: Mode = Mode.EDIT
## The last thing worth saying (undo, save, errors), shown in the status.
var message: String = ""

var _settings: PlayerSettings
var _cli_piece: String = ""
var _cli_start: float = 0.0
var _cli_vr: bool = false
var _cli_desktop: bool = false
var _wrist: StudioWristPalette
var tools: StudioEditTools
var flight: StudioFlight
var edits: StudioConfigEdits
## Whether the inspector shows (with something selected, in Edit).
var inspector_on := true
## The headset's inspector: its panel and the inspector inside it.
var inspector_panel: XRToolsViewport2DIn3D
var _inspector_vr: StudioInspector
## Whether the timeline shows (in Edit).
var timeline_on := true
var ribbon_panel: XRToolsViewport2DIn3D
var _ribbon_vr: StudioTimelineRibbon
var waveform: StudioWaveform
var loop := StudioLoop.new()
var library := StudioAssetLibrary.new()
var recorder := StudioRecorder.new()
## The piece's media.beats last given to the beat clock (JSON).
var _beats_applied := ""
var thumbnailer: StudioThumbnailer
var dropper := StudioAssetDrop.new()
## Whether the shelf shows (in Edit).
var shelf_on := false
var shelf_panel: XRToolsViewport2DIn3D
var _shelf_vr: StudioAssetShelf
## The card being carried ({} for none) and the hand carrying it ("R", or
## "M" for the mouse).
var held_asset: Dictionary = {}
var _held_hand := ""
## In the headset: the trigger was down last frame (letting go drops).
var _trigger_was_down := false
var _ghost: MeshInstance3D
var _library_signature := ""
var _watch_clock := 0.0
## Where the viewer was before the last Seat / Go to it jump (for Back).
var _back_pose: Dictionary = {}
var _mouse_down := false


func _ready() -> void:
	_parse_cli_args()
	_use_studio_fly_keys()
	_settings = PlayerSettings.new()
	_settings.load_from_disk()
	stage.status.connect(func(msg: String): print(msg))
	stage.setup(_settings, InputBindings.new())
	# Studio's own commands; the player's never fire here.
	stage.router.set_context("play", false)
	stage.router.set_context("studio", true)
	stage.router.command.connect(_on_command)
	stage.router.command_released.connect(_on_command_released)
	# Studio edits its own copy of the file: a save coming back through the
	# file watcher must not reload over newer edits.
	runner.set_live_reload(false)
	stage.xr_mode.entered_vr.connect(_apply_mode)
	stage.xr_mode.exited_vr.connect(_apply_mode)
	stage.xr_rig.wrist_panel.screen_size = WRIST_SIZE
	stage.xr_rig.wrist_panel.viewport_size = WRIST_PIXELS
	stage.xr_rig.wrist_panel.scene = WRIST_SCENE
	tools = StudioEditTools.new()
	tools.name = "EditTools"
	tools.runner = runner
	tools.stage = stage
	tools.said.connect(_say)
	tools.recorder = recorder
	add_child(tools)
	flight = StudioFlight.new()
	flight.name = "Flight"
	flight.router = stage.router
	flight.rig = stage.xr_rig
	add_child(flight)
	edits = StudioConfigEdits.new()
	edits.runner = runner
	edits.library = library
	edits.recorder = recorder
	recorder.runner = runner
	_bind_inspector(inspector)
	tools.selection_changed.connect(_on_selection_changed)
	_make_inspector_panel()
	waveform = StudioWaveform.new()
	waveform.name = "Waveform"
	add_child(waveform)
	stage.media_path_changed.connect(waveform.load_for)
	_bind_ribbon(ribbon)
	_make_ribbon_panel()
	thumbnailer = StudioThumbnailer.new()
	thumbnailer.name = "Thumbnailer"
	add_child(thumbnailer)
	dropper.edits = edits
	_bind_shelf(shelf)
	_make_shelf_panel()
	_make_ghost()
	_library_signature = library.signature()
	get_window().files_dropped.connect(_on_files_dropped)
	status_view.resized.connect(_fit_shelf)
	set_mode(Mode.EDIT)

	if _cli_piece != "":
		open_piece(_cli_piece)
	else:
		runner.load_timeline(DefaultScreen.idle_timeline())
		runner.seek(0.0)
		_say("No piece open: open one from the shelf (B), or start Studio with -- --piece <script.json or video>.")
		shelf_on = true
		shelf.show_tab(StudioAssetShelf.OPEN_TAB)
		_show_shelf()

	if _cli_vr or (not _cli_desktop and stage.xr_mode.headset_detected()):
		stage.xr_mode.try_enter_vr()


func _process(delta: float) -> void:
	_scrub(delta)
	_follow_hands(delta)
	_show_status()
	_keep_inspector_near()
	_keep_ribbon_near()
	_keep_shelf_near()
	_carry(delta)
	_watch_library(delta)
	_record_tick()
	_loop_playback()


## Open a script (or a video with its sidecar script) for editing. A video
## with no script gets a new, empty one next to it (<video>.json). Returns
## whether it opened; the current piece stays otherwise.
func open_piece(path: String) -> bool:
	var r: Dictionary
	var fresh := false
	if DefaultScreen.is_video(path) and DefaultScreen.sidecar_script(path) == "":
		r = EditModel.new_piece(path)
		fresh = true
	else:
		if DefaultScreen.is_video(path):
			path = DefaultScreen.sidecar_script(path)
		r = EditModel.open(path)
	if not r.ok:
		_say("Can't open %s: %s" % [path.get_file(), r.error])
		return false
	_drop_held()
	recorder.cancel()
	recorder.armed.clear()
	if model != null:
		model.changed.disconnect(_on_model_changed)
	tools.cancel()
	tools.select("")
	model = r.model
	model.changed.connect(_on_model_changed)
	tools.model = model
	edits.model = model
	dropper.model = model
	recorder.model = model
	_beats_applied = JSON.stringify(model.document().get("media", {}).get("beats"))
	library.piece_dir = model.path.get_base_dir()
	_refresh_shelf()
	runner.load_timeline(model.timeline())
	runner.pause()
	stage.seek_to(_cli_start)
	_cli_start = 0.0
	_show_ribbon()
	if fresh:
		_say("New piece %s: add things from the shelf." % model.path.get_file())
		shelf_on = true
		for view in _shelves():
			view.show_tab("object")
		_show_shelf()
	else:
		_say("Opened %s." % _piece_name())
	return true


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_apply_mode()


func _apply_mode() -> void:
	var editing := mode == Mode.EDIT
	stage.router.set_context("studio_edit", editing)
	status_view.visible = editing
	# The wrist shows only in the headset (the stage turns it on with VR).
	stage.xr_rig.wrist_panel.visible = editing and stage.xr_mode.is_in_vr()
	stage.desktop_camera.movement_enabled = editing
	if tools != null:
		if not editing:
			if recorder.is_active():
				_stop_take()
			tools.cancel()
			_drop_held()
		tools.visible = editing
		flight.enabled = editing and stage.xr_mode.is_in_vr()
		_show_inspector()
		_show_ribbon()
		_show_shelf()


func save() -> bool:
	if model == null:
		return false
	var r := model.save()
	_say("Saved %s." % model.path.get_file() if r.ok else String(r.error))
	return r.ok


func undo() -> void:
	if model == null:
		return
	var label := model.undo()
	_say("Undo: %s" % label if label != "" else "Nothing to undo.")


func redo() -> void:
	if model == null:
		return
	var label := model.redo()
	_say("Redo: %s" % label if label != "" else "Nothing to redo.")


func _on_model_changed(structural: bool) -> void:
	message = model.undo_label()  # undo / redo say their own afterwards
	var data := model.timeline()
	if data != null:
		runner.apply_edit(data, structural)
	for view in _inspectors():
		view.request_rebuild()
	for view in _ribbons():
		view.request_refresh()
	recorder.prune(model.object_ids())
	_apply_piece_beats()


## After an edit of the piece's beat grid (or its undo): the beat clock
## uses it (or goes back to the detected one).
func _apply_piece_beats() -> void:
	var beats = model.document().get("media", {}).get("beats")
	var json := JSON.stringify(beats)
	if json == _beats_applied:
		return
	_beats_applied = json
	stage.beats.set_script_grid(BeatGrid.from_dict(beats))


func _on_command(id: StringName) -> void:
	match id:
		&"studio_toggle_mode": set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT)
		&"studio_play_pause":
			if recorder.is_active():
				_stop_take()
			else:
				_toggle_play()
		&"studio_record":
			if recorder.is_active():
				_stop_take()
			else:
				start_take()
		&"studio_step_back": _seek_by(-STEP_SECONDS)
		&"studio_step_forward": _seek_by(STEP_SECONDS)
		&"studio_seek_back": _seek_by(-SEEK_SECONDS)
		&"studio_seek_forward": _seek_by(SEEK_SECONDS)
		&"studio_go_start": stage.seek_to(0.0)
		&"studio_save": save()
		&"studio_undo": undo()
		&"studio_redo": redo()
		&"studio_reset_view": stage.reset_view()
		&"studio_toggle_vr":
			if stage.xr_mode.is_in_vr():
				stage.xr_mode.exit_vr()
			else:
				stage.xr_mode.try_enter_vr()
		&"studio_select":
			if held_asset.is_empty():
				_select_pointed()
			elif not stage.router.is_context_active("menus"):
				drop_held_at(_hand_xf("R"))
		&"studio_grab": _grab_with(_hand_of(stage.router.last_input, "R"))
		&"studio_grab_left": _grab_with(_hand_of(stage.router.last_input, "L"))
		&"studio_key_selection":
			if model != null:
				if tools.key_selection() == "":
					_say("Select something first (right trigger, or click it).")
		&"studio_toggle_autokey":
			tools.auto_key = not tools.auto_key
			_say("Auto-key %s: moves %s." % ["on" if tools.auto_key else "off",
					"key at the playhead" if tools.auto_key else "change the placement"])
		&"studio_toggle_snap":
			tools.snap = not tools.snap
			_say("Snapping %s." % ("on: 10 cm, 15°, 5 %" if tools.snap else "off"))
		&"studio_seat": _jump_to_seat()
		&"studio_goto_selection": _go_to_selection()
		&"studio_jump_back": _jump_back()
		&"studio_deselect":
			if recorder.is_active():
				recorder.cancel()
				_after_take()
				runner.pause()
				_say("Take dropped: nothing recorded.")
			elif not held_asset.is_empty():
				_drop_held()
				_say("Put it back.")
			else:
				tools.select("")
		&"studio_toggle_shelf":
			shelf_on = not shelf_on
			if shelf_on:
				_place_shelf_panel()
			_show_shelf()
		&"studio_delete_selection":
			if model != null and tools.selected != "":
				var gone := tools.selected
				tools.select("")
				if model.remove_object(gone):
					_say("Deleted %s (undo brings it back)." % gone)
		&"studio_toggle_timeline":
			timeline_on = not timeline_on
			if timeline_on:
				_place_ribbon_panel()
			_show_ribbon()
		&"studio_toggle_loop":
			loop.on = not loop.on
			if loop.on and not loop.is_set():
				loop.set_in(runner.playhead)
			_say("Loop %s." % ("on: %s to %s" % [StudioStatus.timecode(loop.a), StudioStatus.timecode(loop.b)] if loop.on else "off"))
		&"studio_loop_in":
			loop.set_in(runner.playhead)
			_say("Loop from %s to %s." % [StudioStatus.timecode(loop.a), StudioStatus.timecode(loop.b)])
		&"studio_loop_out":
			loop.set_out(runner.playhead)
			_say("Loop from %s to %s." % [StudioStatus.timecode(loop.a), StudioStatus.timecode(loop.b)])
		&"studio_toggle_inspector":
			inspector_on = not inspector_on
			if inspector_on:
				_place_inspector_panel()
			_show_inspector()


func _on_command_released(id: StringName) -> void:
	match id:
		&"studio_grab": _release(_hand_of(stage.router.last_input, "R"))
		&"studio_grab_left": _release(_hand_of(stage.router.last_input, "L"))


# ---------- editing by hand ----------

## "L" / "R" from the input behind a command ("L.grip" …), else `fallback`.
static func _hand_of(input: String, fallback: String) -> String:
	if input.begins_with("L."):
		return "L"
	if input.begins_with("R."):
		return "R"
	return fallback


func _controller(hand: String) -> XRController3D:
	return stage.xr_rig.left_controller if hand == "L" else stage.xr_rig.right_controller


## The hand's pointing transform (its -Z is the laser).
func _hand_xf(hand: String) -> Transform3D:
	if hand == "M":
		return _mouse_hand()
	return _controller(hand).global_transform


func _select_pointed() -> void:
	var xf := _hand_xf("R")
	tools.select(tools.pick(xf.origin, -xf.basis.z))


## A grip: grab what that hand points at (or join a grab in progress as
## the second hand).
func _grab_with(hand: String) -> void:
	if model == null:
		return
	if tools.is_grabbing():
		tools.add_hand(hand, _hand_xf(hand))
		return
	var xf := _hand_xf(hand)
	var id := tools.pick(xf.origin, -xf.basis.z)
	if id == "":
		return
	tools.grab(id, hand, xf)


func _release(hand: String) -> void:
	if tools.is_grabbing():
		tools.release_hand(hand)


## While grabbing in the headset: follow the controllers; the right stick
## pushes / pulls.
func _follow_hands(delta: float) -> void:
	flight.right_stick_busy = tools.is_grabbing()
	if not tools.is_grabbing() or not stage.xr_mode.is_in_vr():
		return
	for hand in ["L", "R"]:
		tools.move_hand(hand, _hand_xf(hand))
	var y := stage.router.axis("studio_right_stick").y
	if y != 0.0:
		tools.push(y * PUSH_SPEED * delta)


## Desktop: the mouse is a hand pointing from the camera through the cursor.
func _mouse_hand() -> Transform3D:
	var cam := stage.desktop_camera
	var at := get_viewport().get_mouse_position()
	var dir := cam.project_ray_normal(at)
	return Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK), cam.project_ray_origin(at))


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.EDIT or model == null or stage.xr_mode.is_in_vr():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not held_asset.is_empty():
			# Carrying a card (clicked, not dragged): this click drops it.
			if mb.pressed:
				drop_held_at(_mouse_hand())
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var xf := _mouse_hand()
				var id := tools.pick(xf.origin, -xf.basis.z)
				tools.select(id)
				if id != "":
					tools.grab(id, "M", xf)
			else:
				tools.release_hand("M")
			get_viewport().set_input_as_handled()
		elif tools.is_grabbing() and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			tools.push(WHEEL_PUSH if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -WHEEL_PUSH)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and tools.is_grabbing():
		tools.move_hand("M", _mouse_hand())


# ---------- the inspector ----------

func _bind_inspector(view: StudioInspector) -> void:
	view.edits = edits
	view.tools = tools
	view.said.connect(_say)
	view.close_requested.connect(func(): tools.select(""))
	view.show_object(tools.selected)


func _inspectors() -> Array:
	var out: Array = [inspector]
	if _inspector_vr != null and is_instance_valid(_inspector_vr):
		out.append(_inspector_vr)
	return out


func _make_inspector_panel() -> void:
	inspector_panel = VP2D3D_SCENE.instantiate()
	inspector_panel.name = "InspectorPanel"
	inspector_panel.scene = INSPECTOR_SCENE
	inspector_panel.viewport_size = INSPECTOR_PIXELS
	inspector_panel.screen_size = INSPECTOR_SIZE
	inspector_panel.material = FloatingPanel.ui_material()
	inspector_panel.visible = false
	add_child(inspector_panel)
	var sub := inspector_panel.get_node_or_null("Viewport") as SubViewport
	if sub != null:
		sub.gui_embed_subwindows = true
	stage.add_masked_panel(inspector_panel)


## The inspector inside the headset panel, bound once it exists (the panel
## makes its scene a frame or two after it's ready).
func _vr_inspector() -> StudioInspector:
	if _inspector_vr != null and is_instance_valid(_inspector_vr):
		return _inspector_vr
	var sub := inspector_panel.get_node_or_null("Viewport") as SubViewport if inspector_panel != null else null
	if sub == null or sub.get_child_count() == 0:
		return null
	_inspector_vr = sub.get_child(0) as StudioInspector
	if _inspector_vr != null:
		_bind_inspector(_inspector_vr)
	return _inspector_vr


func _on_selection_changed(id: String) -> void:
	for view in _ribbons():
		view.request_refresh()
	for view in _inspectors():
		view.show_object(id)
	if id != "":
		_place_inspector_panel()
	_show_inspector()


## Desktop panel or headset panel: in Edit, with something selected, while
## it's on.
func _show_inspector() -> void:
	if inspector == null or tools == null:
		return
	var show := mode == Mode.EDIT and inspector_on and tools.selected != ""
	var in_vr := stage.xr_mode.is_in_vr()
	inspector.visible = show and not in_vr
	if inspector_panel != null:
		if show and in_vr and not inspector_panel.visible:
			_place_inspector_panel()
		inspector_panel.visible = show and in_vr


## Beside the selection as you see it: INSPECTOR_DISTANCE from your head,
## to the right of the line to it, turned to face you.
func _place_inspector_panel() -> void:
	if inspector_panel == null:
		return
	var head := stage.viewer_transform()
	var toward := -head.basis.z
	var angle := INSPECTOR_ANGLE
	var node := runner.registry().get_node_by_id(tools.selected) if tools.selected != "" else null
	if node != null and is_instance_valid(node):
		var box := StudioPicker.local_bounds(node)
		var center := node.global_transform * box.get_center() if box.size != Vector3.ZERO else node.global_transform.origin
		toward = center - head.origin
		# Clear the object: its half-width as you see it, plus the panel's.
		var half := (node.global_transform.basis * box.size).length() * 0.5
		var dist := Vector2(toward.x, toward.z).length()
		if dist > half:
			angle = clampf(rad_to_deg(asin(half / dist) + atan(INSPECTOR_SIZE.x * 0.5 / INSPECTOR_DISTANCE)) + 4.0, INSPECTOR_ANGLE, INSPECTOR_MAX_ANGLE)
		else:
			angle = INSPECTOR_MAX_ANGLE  # inside it: off to the side
	toward.y = 0.0
	if toward.length() < 0.01:
		toward = Vector3(0, 0, -1)
	toward = toward.normalized().rotated(Vector3.UP, -deg_to_rad(angle))
	var at := head.origin + toward * INSPECTOR_DISTANCE - Vector3(0, INSPECTOR_DROP, 0)
	# The quad's front is +Z: look away from the head.
	inspector_panel.global_transform = Transform3D(Basis.looking_at(at - head.origin, Vector3.UP), at)
	var view := _vr_inspector()
	if view != null:
		view.show_object(tools.selected)


## After flying off (or jumping), bring the headset panel along.
func _keep_inspector_near() -> void:
	_vr_inspector()
	if inspector_panel == null or not inspector_panel.visible:
		return
	if stage.viewer_transform().origin.distance_to(inspector_panel.global_transform.origin) > INSPECTOR_REPLACE:
		_place_inspector_panel()


# ---------- the timeline ----------

func _bind_ribbon(view: StudioTimelineRibbon) -> void:
	view.edits = edits
	view.tools = tools
	view.waveform = waveform
	view.loop = loop
	view.recorder = recorder
	view.said.connect(_say)


func _ribbons() -> Array:
	var out: Array = [ribbon]
	if _ribbon_vr != null and is_instance_valid(_ribbon_vr):
		out.append(_ribbon_vr)
	return out


func _make_ribbon_panel() -> void:
	ribbon_panel = VP2D3D_SCENE.instantiate()
	ribbon_panel.name = "RibbonPanel"
	ribbon_panel.scene = RIBBON_SCENE
	ribbon_panel.viewport_size = RIBBON_PIXELS
	ribbon_panel.screen_size = RIBBON_SIZE
	ribbon_panel.material = FloatingPanel.ui_material()
	ribbon_panel.visible = false
	add_child(ribbon_panel)
	stage.add_masked_panel(ribbon_panel)


func _vr_ribbon() -> StudioTimelineRibbon:
	if _ribbon_vr != null and is_instance_valid(_ribbon_vr):
		return _ribbon_vr
	var sub := ribbon_panel.get_node_or_null("Viewport") as SubViewport if ribbon_panel != null else null
	if sub == null or sub.get_child_count() == 0:
		return null
	_ribbon_vr = sub.get_child(0) as StudioTimelineRibbon
	if _ribbon_vr != null:
		_bind_ribbon(_ribbon_vr)
	return _ribbon_vr


## In Edit while it's on (and a piece is open): the desktop strip, or the
## headset band.
func _show_ribbon() -> void:
	if ribbon == null or tools == null:
		return
	var show := mode == Mode.EDIT and timeline_on and model != null
	var in_vr := stage.xr_mode.is_in_vr()
	ribbon.visible = show and not in_vr
	# The desktop shelf reaches down to the strip, or the bottom without it.
	shelf.offset_bottom = ribbon.offset_top - 12.0 if ribbon.visible else -12.0
	if ribbon_panel != null:
		if show and in_vr and not ribbon_panel.visible:
			_place_ribbon_panel()
		ribbon_panel.visible = show and in_vr


## In front of you at waist height, level, tilted back to face your eyes.
func _place_ribbon_panel() -> void:
	if ribbon_panel == null:
		return
	var head := stage.viewer_transform()
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var at := head.origin + fwd * RIBBON_DISTANCE - Vector3(0, RIBBON_DROP, 0)
	# The quad's front is +Z: face back toward you, then lean its top away.
	var basis := Basis.looking_at(fwd, Vector3.UP)
	basis = basis.rotated(basis.x, -deg_to_rad(RIBBON_TILT))
	ribbon_panel.global_transform = Transform3D(basis, at)
	_vr_ribbon()


func _keep_ribbon_near() -> void:
	_vr_ribbon()
	if ribbon_panel == null or not ribbon_panel.visible:
		return
	if stage.viewer_transform().origin.distance_to(ribbon_panel.global_transform.origin) > INSPECTOR_REPLACE:
		_place_ribbon_panel()


# ---------- recording ----------

## Record: from the loop's in point to its out point while looping (a
## punch-in), else from here until stopped; playback starts a pre-roll
## early.
func start_take() -> void:
	if model == null or recorder.is_active():
		return
	var looping := loop.on and loop.is_set()
	var from := loop.a if looping else runner.playhead
	var start := recorder.begin(from, loop.b if looping else -1.0)
	stage.seek_to(start)
	runner.play()
	var armed := recorder.armed.size()
	_say("Recording from %s%s: %s." % [StudioStatus.timecode(from), " to %s" % StudioStatus.timecode(loop.b) if looping else "",
			"move the armed sliders (%d), or grab something" % armed if armed > 0 else "grab something (or arm sliders with their ●)"])


## End the take and write it. A slider still being dragged, or an object
## still held, is let go of: the take has what they did.
func _stop_take() -> void:
	var label := recorder.finish()
	_after_take()
	runner.pause()
	_say(label + "." if label != "" else "Nothing recorded (touch an armed slider, or grab something, while it records).")


func _after_take() -> void:
	for view in _inspectors():
		view.drop_pending()
	if tools.is_grabbing():
		tools.cancel()


func _record_tick() -> void:
	if not recorder.is_active():
		return
	if not runner.playing:
		_stop_take()
		return
	if recorder.tick(runner.playhead) != "":
		_stop_take()


## While looping: back to the in point at the out point.
func _loop_playback() -> void:
	if not runner.playing:
		return
	var back := loop.next_time(runner.playhead)
	if back >= 0.0:
		stage.seek_to(back)


# ---------- the asset shelf ----------

func _bind_shelf(view: StudioAssetShelf) -> void:
	view.library = library
	view.thumbnailer = thumbnailer
	view.runner = runner
	view.said.connect(_say)
	view.taken.connect(_on_taken.bind(view))
	view.open_requested.connect(func(path: String): open_piece(path))
	view.close_requested.connect(func():
		shelf_on = false
		_show_shelf())
	thumbnailer.thumbnail_ready.connect(view.on_thumbnail)


func _shelves() -> Array:
	var out: Array = [shelf]
	if _shelf_vr != null and is_instance_valid(_shelf_vr):
		out.append(_shelf_vr)
	return out


func _refresh_shelf() -> void:
	for view in _shelves():
		view.refresh()


## Desktop: the shelf starts under the status, whose height changes with
## what it says (and ends above the timeline strip: _show_ribbon).
func _fit_shelf() -> void:
	shelf.offset_top = status_view.position.y + status_view.size.y + 10.0


func _make_shelf_panel() -> void:
	shelf_panel = VP2D3D_SCENE.instantiate()
	shelf_panel.name = "ShelfPanel"
	shelf_panel.scene = SHELF_SCENE
	shelf_panel.viewport_size = SHELF_PIXELS
	shelf_panel.screen_size = SHELF_SIZE
	shelf_panel.material = FloatingPanel.ui_material()
	shelf_panel.visible = false
	add_child(shelf_panel)
	stage.add_masked_panel(shelf_panel)


func _vr_shelf() -> StudioAssetShelf:
	if _shelf_vr != null and is_instance_valid(_shelf_vr):
		return _shelf_vr
	var sub := shelf_panel.get_node_or_null("Viewport") as SubViewport if shelf_panel != null else null
	if sub == null or sub.get_child_count() == 0:
		return null
	_shelf_vr = sub.get_child(0) as StudioAssetShelf
	if _shelf_vr != null:
		_bind_shelf(_shelf_vr)
		_shelf_vr.show_tab(shelf.tab)
	return _shelf_vr


## In Edit while it's on: the desktop panel, or the headset panel.
func _show_shelf() -> void:
	if shelf == null or tools == null:
		return
	var show := mode == Mode.EDIT and shelf_on
	var in_vr := stage.xr_mode.is_in_vr()
	shelf.visible = show and not in_vr
	if shelf_panel != null:
		if show and in_vr and not shelf_panel.visible:
			_place_shelf_panel()
		shelf_panel.visible = show and in_vr


## To your front left, a little below your eyes, facing you.
func _place_shelf_panel() -> void:
	if shelf_panel == null:
		return
	var head := stage.viewer_transform()
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var toward := fwd.rotated(Vector3.UP, deg_to_rad(SHELF_ANGLE))
	var at := head.origin + toward * SHELF_DISTANCE - Vector3(0, SHELF_DROP, 0)
	# The quad's front is +Z: look away from the head.
	shelf_panel.global_transform = Transform3D(Basis.looking_at(at - head.origin, Vector3.UP), at)
	_vr_shelf()


func _keep_shelf_near() -> void:
	_vr_shelf()
	if shelf_panel == null or not shelf_panel.visible:
		return
	if stage.viewer_transform().origin.distance_to(shelf_panel.global_transform.origin) > INSPECTOR_REPLACE:
		_place_shelf_panel()


## A card was picked up on `view`: carry it (the mouse on the desktop, the
## right hand in the headset).
func _on_taken(asset: Dictionary, view: StudioAssetShelf) -> void:
	if model == null:
		_say("Open a piece first (the Open tab).")
		view.show_held("")
		return
	held_asset = asset
	_held_hand = "R" if stage.xr_mode.is_in_vr() else "M"
	_trigger_was_down = true
	for other in _shelves():
		other.show_held(asset.id)
	var tex := thumbnailer.thumbnail(asset)
	var mat := _ghost.material_override as StandardMaterial3D
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, 0.85) if tex != null else Color(StudioAssetShelf.ACCENT, 0.6)
	_say("Carrying %s: let go where it goes (Esc puts it back)." % asset.label)


## Put the carried card back (nothing added).
func _drop_held() -> void:
	held_asset = {}
	_held_hand = ""
	if _ghost != null:
		_ghost.visible = false
	for view in _shelves():
		view.show_held("")


## Drop the carried card where `hand_xf` points (its -Z). Returns whether
## something was added or changed.
func drop_held_at(hand_xf: Transform3D) -> bool:
	if held_asset.is_empty() or model == null:
		return false
	var asset := held_asset
	_drop_held()
	var where := StudioAssetDrop.aim(hand_xf.origin, -hand_xf.basis.z, tools.candidates())
	var r := dropper.drop(asset, where, stage.viewer_transform().origin, runner.playhead, tools.snap)
	if r.ok:
		tools.select(r.id)
	_say(r.message)
	if r.ok:
		if asset.source == "user":
			_refresh_shelf()  # it's in the piece now
	return r.ok


## While carrying: the card's picture follows the pointer into the world;
## in the headset, letting go of the trigger off the shelf drops it (let
## go on the shelf, the press was a click: the next trigger press drops it).
func _carry(_delta: float) -> void:
	if held_asset.is_empty():
		return
	var over_ui := false
	var xf: Transform3D
	if _held_hand == "M":
		over_ui = _mouse_over_ui()
		xf = _mouse_hand()
	else:
		over_ui = stage.router.is_context_active("menus")
		xf = _hand_xf("R")
		var down := stage.router.is_down("R.trigger")
		if _trigger_was_down and not down and not over_ui:
			_trigger_was_down = false
			drop_held_at(xf)
			return
		_trigger_was_down = down
	_ghost.visible = not over_ui
	if over_ui:
		return
	var where := StudioAssetDrop.aim(xf.origin, -xf.basis.z, tools.candidates())
	var head := stage.viewer_transform().origin
	var p: Vector3 = where.point
	# Facing you (the quad's front is +Z).
	var to_head := head - p
	_ghost.global_transform = Transform3D(Basis.looking_at(-to_head, Vector3.UP) if to_head.length() > 0.01 else Basis(), p)
	message = _drop_hint(held_asset, where)


## What letting go here would do, for the status.
func _drop_hint(asset: Dictionary, where: Dictionary) -> String:
	var on := String(where.on)
	var kind := edits.kind_for(on) if on != "" else ""
	match String(asset.type):
		"effect":
			return "Let go: add %s to %s." % [asset.label, on] if kind in ["screen", "layer"] else "Point %s at a screen or a layer." % asset.label
		"layer":
			if kind == "layer":
				return "Let go: %s shows %s." % [on, asset.label]
	return "Let go: add %s here." % asset.label


## Desktop: whether the mouse is over one of Studio's panels.
func _mouse_over_ui() -> bool:
	var at := get_viewport().get_mouse_position()
	for panel in [shelf, inspector, ribbon, status_view]:
		if panel != null and panel.visible and panel.get_global_rect().has_point(at):
			return true
	return false


func _input(event: InputEvent) -> void:
	# Desktop: a card dragged off the shelf drops where the button comes up
	# (the release goes to the card, so it's caught here, before the GUI).
	if held_asset.is_empty() or _held_hand != "M" or stage.xr_mode.is_in_vr():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed \
			and not _mouse_over_ui():
		drop_held_at(_mouse_hand())


func _make_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "CarriedCard"
	var quad := QuadMesh.new()
	quad.size = Vector2(GHOST_WIDTH, GHOST_WIDTH * 0.625)
	_ghost.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	_ghost.material_override = mat
	_ghost.visible = false
	add_child(_ghost)


## New or changed files in the shelf's folders show up on it.
func _watch_library(delta: float) -> void:
	_watch_clock += delta
	if _watch_clock < WATCH_SECONDS:
		return
	_watch_clock = 0.0
	var sig := library.signature()
	if sig != _library_signature:
		_library_signature = sig
		_refresh_shelf()


## Files dropped on the window: a piece or a video opens (a video with no
## piece starts one); a shader or prefab is copied into the piece.
func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if DefaultScreen.is_video(f) or f.get_extension().to_lower() == "json":
			open_piece(f)
			return
	if model == null:
		_say("Open a piece first, then drop shaders or prefabs on it.")
		return
	var added: Array = []
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext in StudioBundle.PREFAB_EXTENSIONS or ext in VisualizerShaders.GODOT_EXTENSIONS + VisualizerShaders.SHADERTOY_EXTENSIONS:
			var b := StudioBundle.bundle(model.path.get_base_dir(), f)
			if b.ok:
				added.append(f.get_file())
			else:
				_say(b.error)
	if not added.is_empty():
		_say("In the piece now, on the shelf: %s." % ", ".join(added))
		shelf_on = true
		_show_shelf()
		_refresh_shelf()


# ---------- getting around ----------

func _remember_pose() -> void:
	var xf := stage.viewer_transform()
	var fwd := -xf.basis.z
	_back_pose = {"position": xf.origin, "yaw_deg": rad_to_deg(atan2(-fwd.x, -fwd.z))}


## Where the audience sits at the playhead.
func _jump_to_seat() -> void:
	_remember_pose()
	var seat := stage.seat_pose()
	stage.put_viewer(seat.position, seat.yaw_deg)
	_say("At the audience seat.")


## In front of the selection, far enough to see all of it, facing it.
func _go_to_selection() -> void:
	var node := runner.registry().get_node_by_id(tools.selected) if tools.selected != "" else null
	if node == null:
		_say("Select something first.")
		return
	var box := StudioPicker.local_bounds(node)
	var xf := node.global_transform
	var center := xf * box.get_center() if box.size != Vector3.ZERO else xf.origin
	var radius := maxf((xf.basis * box.size).length() * 0.5, 0.3)
	var from := stage.viewer_transform().origin - center
	from.y = 0.0
	if from.length() < 0.01:
		from = Vector3(0, 0, 1)
	var pos := center + from.normalized() * maxf(radius * 1.8, 1.2)
	var to := center - pos
	_remember_pose()
	stage.put_viewer(pos, rad_to_deg(atan2(-to.x, -to.z)), false)
	_say("At %s." % tools.selected)


func _jump_back() -> void:
	if _back_pose.is_empty():
		_say("Nowhere to go back to.")
		return
	var pose := _back_pose
	_remember_pose()
	stage.put_viewer(pose.position, pose.yaw_deg, false)
	_say("Back.")


func _toggle_play() -> void:
	if model == null:
		return
	if runner.playing:
		runner.pause()
	else:
		var from := loop.start_time(runner.playhead)
		if from >= 0.0:
			stage.seek_to(from)
		runner.play()


func _seek_by(seconds: float) -> void:
	if model != null:
		stage.seek_to(runner.playhead + seconds)


## Left trigger + left stick: further is faster (squared, so small pushes
## are fine-grained).
func _scrub(delta: float) -> void:
	if model == null:
		return
	var x := stage.router.axis("studio_scrub").x
	if x != 0.0:
		stage.seek_to(runner.playhead + x * absf(x) * SCRUB_SPEED * delta)


func _show_status() -> void:
	var args := [
		"EDIT" if mode == Mode.EDIT else "PLAY",
		_piece_name(),
		model != null and model.is_dirty(),
		runner.playhead,
		runner.effective_duration(),
		runner.playing,
		message,
		tools.auto_key,
		tools.snap,
		_rec_chip(),
	]
	if status_view.visible:
		status_view.callv("show_state", args)
	if _wrist == null or not is_instance_valid(_wrist):
		_wrist = stage.xr_rig.wrist_content() as StudioWristPalette
		if _wrist != null:
			_wrist.action.connect(_on_command)
	if _wrist != null and stage.xr_rig.wrist_panel.visible and _wrist.status != null:
		_wrist.status.callv("show_state", args)
		_wrist.show_toggles(tools.auto_key, tools.snap, inspector_on, timeline_on, loop.on, shelf_on, recorder.is_active())


## The status's record chip: "" when not recording.
func _rec_chip() -> String:
	match recorder.state:
		StudioRecorder.State.PRE_ROLL:
			return "● PRE-ROLL %s" % StudioStatus.timecode(recorder.from - runner.playhead)
		StudioRecorder.State.RECORDING:
			return "● REC"
	return ""


func _piece_name() -> String:
	if model == null:
		return "No piece"
	var title := String(model.document().get("meta", {}).get("title", ""))
	return title if title != "" else model.path.get_file()


func _say(msg: String) -> void:
	message = msg
	print(msg)


## Desktop flight in Edit mode: WASD, E up, Q down (Space plays / pauses
## and Ctrl is for shortcuts here, unlike the player). Only this run's
## InputMap changes.
func _use_studio_fly_keys() -> void:
	for pair in [["move_up", KEY_E], ["move_down", KEY_Q]]:
		if not InputMap.has_action(pair[0]):
			continue
		InputMap.action_erase_events(pair[0])
		var ev := InputEventKey.new()
		ev.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], ev)


func _parse_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if a == "--piece" and i + 1 < args.size():
			_cli_piece = args[i + 1]
		elif a == "--start" and i + 1 < args.size():
			_cli_start = float(args[i + 1])
		elif a == "--vr":
			_cli_vr = true
		elif a == "--desktop":
			_cli_desktop = true
		elif a == "--library" and i + 1 < args.size():
			library.library_dirs.append(args[i + 1])
	# "Open with" / dropping a file on the .exe.
	if _cli_piece == "":
		for a in OS.get_cmdline_args():
			if (DefaultScreen.is_video(a) or a.get_extension().to_lower() == "json") and FileAccess.file_exists(a):
				_cli_piece = a
