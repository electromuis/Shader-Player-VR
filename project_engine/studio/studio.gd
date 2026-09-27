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
## The inspector (StudioInspector) shows the selection's settings: display,
## the layer's shader, the effects stack, modifiers and reactive motion,
## with a key diamond per property. On the desktop it's a side panel; in
## the headset a panel beside the selection, placed when you select
## something (or show it again) and turned toward you.
##
## Command line (after `--`): --piece <script.json, or a video with a
## same-name .json next to it>, --start <seconds>, --vr, --desktop.

## Scrubbing speed at full stick, in seconds of timeline per second.
const SCRUB_SPEED := 20.0
const STEP_SECONDS := 1.0
const SEEK_SECONDS := 10.0
const WRIST_SCENE := preload("res://studio/ui/wrist_palette.tscn")
## The wrist palette's size in metres and pixels (bigger than the player's
## wrist HUD: it has buttons).
const WRIST_SIZE := Vector2(0.26, 0.28)
const WRIST_PIXELS := Vector2(780, 840)
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

enum Mode { PLAY, EDIT }

@onready var stage: Stage = $Stage
@onready var runner: ScriptRunner = $Stage/ScriptRunner
@onready var status_view: StudioStatus = $UI/Status
@onready var inspector: StudioInspector = $UI/Inspector

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
	add_child(tools)
	flight = StudioFlight.new()
	flight.name = "Flight"
	flight.router = stage.router
	flight.rig = stage.xr_rig
	add_child(flight)
	edits = StudioConfigEdits.new()
	edits.runner = runner
	_bind_inspector(inspector)
	tools.selection_changed.connect(_on_selection_changed)
	_make_inspector_panel()
	set_mode(Mode.EDIT)

	if _cli_piece != "":
		open_piece(_cli_piece)
	else:
		runner.load_timeline(DefaultScreen.idle_timeline())
		runner.seek(0.0)
		_say("No piece open. Start Studio with -- --piece <script.json>.")

	if _cli_vr or (not _cli_desktop and stage.xr_mode.headset_detected()):
		stage.xr_mode.try_enter_vr()


func _process(delta: float) -> void:
	_scrub(delta)
	_follow_hands(delta)
	_show_status()
	_keep_inspector_near()


## Open a script (or a video with its sidecar script) for editing. Returns
## whether it opened; the current piece stays otherwise.
func open_piece(path: String) -> bool:
	if DefaultScreen.is_video(path):
		var sidecar := DefaultScreen.sidecar_script(path)
		if sidecar == "":
			_say("No script next to %s (Studio opens pieces: a .json)." % path.get_file())
			return false
		path = sidecar
	var r := EditModel.open(path)
	if not r.ok:
		_say("Can't open %s: %s" % [path.get_file(), r.error])
		return false
	if model != null:
		model.changed.disconnect(_on_model_changed)
	tools.cancel()
	tools.select("")
	model = r.model
	model.changed.connect(_on_model_changed)
	tools.model = model
	edits.model = model
	runner.load_timeline(model.timeline())
	runner.pause()
	stage.seek_to(_cli_start)
	_cli_start = 0.0
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
			tools.cancel()
		tools.visible = editing
		flight.enabled = editing and stage.xr_mode.is_in_vr()
		_show_inspector()


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


func _on_command(id: StringName) -> void:
	match id:
		&"studio_toggle_mode": set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT)
		&"studio_play_pause": _toggle_play()
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
		&"studio_select": _select_pointed()
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
			tools.select("")
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
		if mb.button_index == MOUSE_BUTTON_LEFT:
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
	]
	if status_view.visible:
		status_view.callv("show_state", args)
	if _wrist == null or not is_instance_valid(_wrist):
		_wrist = stage.xr_rig.wrist_content() as StudioWristPalette
		if _wrist != null:
			_wrist.action.connect(_on_command)
	if _wrist != null and stage.xr_rig.wrist_panel.visible and _wrist.status != null:
		_wrist.status.callv("show_state", args)
		_wrist.show_toggles(tools.auto_key, tools.snap, inspector_on)


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
	# "Open with" / dropping a file on the .exe.
	if _cli_piece == "":
		for a in OS.get_cmdline_args():
			if (DefaultScreen.is_video(a) or a.get_extension().to_lower() == "json") and FileAccess.file_exists(a):
				_cli_piece = a
