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
## Each of those panels has – to fold it to a tab: in the headset the
## wrist's button for it, on the desktop a tab in the status; the tab (or
## N / T / B) brings it back. In the headset the panels ride on the rig,
## so they keep their place around you as you fly, turn or jump.
##
## Performance recording (StudioRecorder): arm properties with the
## inspector's record dots, press Record (wrist, Shift+R): playback starts
## a pre-roll early and, from the loop's in point (or where you were), what
## you touch is recorded: armed sliders and anything you grab. Stopping
## (Record again, pause, or the loop's out point) writes the take as keys,
## one undo step; Esc drops it.
##
## The viewer (the audience's eye) is the "$viewer" track: a lane at the
## top of the timeline (select it there). Key viewer here (V) keys where you
## are at the playhead (the ride glides there); Cut here (Shift+V) jumps
## there with a short fade. Arm the ride (Ctrl+Shift+V, or its ● in the
## inspector) and record: where you fly becomes the ride. In Edit you fly
## freely; Play is the audience view, and rides the script.
##
## The miniature (M, the wrist): the whole scene small, to lay out and fly
## a ride from above; everything works in it as at full size. In the headset
## you become a giant (the XR world scale) with the scene as a table at
## waist height; on the desktop the camera looks down on it. M again puts
## you back where you were.
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
## wrist HUD: it has two pages of tiles), 3000 pixels a metre.
const WRIST_SIZE := Vector2(0.3, 0.35)
const WRIST_PIXELS := Vector2(900, 1050)
## A cut made with Cut here fades this long.
const CUT_FADE := 0.5
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
## (0.48 m wide: with its 28 px text, body text is about 1.4° of view and
## nothing is under 1.1°; drive_studio_m8.gd measures it.)
const INSPECTOR_SIZE := Vector2(0.48, 0.687)
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
const MENU_SCENE := preload("res://studio/ui/studio_menu.tscn")
## The desktop window it opens at (_size_window).
const DESKTOP_SIZE := Vector2i(1920, 1080)
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
## Studio's own options (the menu's Studio tab).
var studio_settings := StudioSettings.new()
## The menu (F2, hold ≡): the player's Config and Controls tabs and a
## Studio tab. Desktop: `menu_2d`, over the middle of the window; headset:
## `menu` on a panel like the player's (menu_panel).
var menu_on := false
var menu_2d: StudioMenu
var menu_panel: FloatingPanel
var menu: StudioMenu
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
## New pieces start from the new-piece template (a screen showing the
## video); off, they start empty.
var use_template := true
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
## Pulses on the controllers confirming grabs, snaps, keys, drops, takes.
var haptics := StudioHaptics.new()
## The take being recorded has been felt starting (after its pre-roll).
var _take_felt := false
## Autosave (StudioSafety): time since the last one, and what it wrote.
var _autosave_clock := 0.0
var _autosaved_text := ""
## When the last autosave was written (ticks in ms), -1 = none since.
var _autosaved_at := -1
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
## Where a carried card would land (StudioDropPreview).
var _ghost := StudioDropPreview.new()
## 1 m lines on the floor while editing (the Studio tab's Floor grid).
var floor_grid: StudioFloorGrid
var _library_signature := ""
var _watch_clock := 0.0
## Where the viewer was before the last Seat / Go to it jump (for Back).
var _back_pose: Dictionary = {}
## The miniature: whether it's on, and where you were before it.
var miniature_on := false
var _before_miniature: Dictionary = {}
## The headset miniature: the scene this many metres across, its floor this
## high above your real floor.
const MINIATURE_SIZE := 1.2
const MINIATURE_TABLE := 0.8
var _mouse_down := false


func _ready() -> void:
	_parse_cli_args()
	_use_studio_fly_keys()
	_settings = PlayerSettings.new()
	_settings.load_from_disk()
	studio_settings.load_from_disk()
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
	haptics.rig = stage.xr_rig
	haptics.in_vr = stage.xr_mode.is_in_vr
	tools.felt.connect(func(kind: String, hand: String): haptics.tick(kind, _main_hand() if hand == "main" else hand))
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
	recorder.viewer_pose = func(): return _eye_pose()
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
	add_child(_ghost)
	floor_grid = StudioFloorGrid.new()
	add_child(floor_grid)
	# Studio's own drawing stays out of looks' snapshots.
	for helper in [tools, _ghost, floor_grid, inspector_panel, ribbon_panel, shelf_panel]:
		StudioThumbnailer.mark_helper(helper)
	_library_signature = library.signature()
	_make_menu()
	studio_settings.changed.connect(_apply_studio_settings)
	_settings.changed.connect(_apply_player_settings)
	_apply_studio_settings()
	_size_window()
	_apply_player_settings()
	get_window().files_dropped.connect(_on_files_dropped)
	status_view.resized.connect(_fit_shelf)
	status_view.tab_pressed.connect(_on_command)
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
	stage.comfort_extra = flight.motion
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
	_autosave_tick(delta)
	_update_hover(delta)


## What the pointer would pick (the mouse, or the main hand's laser when
## it isn't on a panel), for the edit tools to outline faintly; checked
## HOVER_SECONDS apart (picking walks every object's meshes).
const HOVER_SECONDS := 0.1
var _hover_clock := 0.0


func _update_hover(delta: float) -> void:
	_hover_clock += delta
	if _hover_clock < HOVER_SECONDS:
		return
	_hover_clock = 0.0
	var id := ""
	if mode == Mode.EDIT and model != null and not tools.is_grabbing() and not tools.is_grabbing_key() and held_asset.is_empty():
		var xf := Transform3D()
		var aiming := false
		if stage.xr_mode.is_in_vr():
			aiming = not stage.router.is_context_active("menus")
			xf = _hand_xf(_main_hand())
		else:
			aiming = not _mouse_over_ui()
			xf = _mouse_hand()
		if aiming:
			id = tools.pick(xf.origin, -xf.basis.z)
	tools.hovered = id


# ---------- keeping work safe ----------

## Every StudioSafety.AUTOSAVE_SECONDS (while the Studio tab has it on).
func _autosave_tick(delta: float) -> void:
	if not studio_settings.autosave:
		return
	_autosave_clock += delta
	if _autosave_clock < StudioSafety.AUTOSAVE_SECONDS:
		return
	_autosave_clock = 0.0
	autosave_now()


## Unsaved changes to the piece's autosave; with none (saved, or all
## undone) the autosave goes.
func autosave_now() -> void:
	if model == null or model.path == "":
		return
	if not model.is_dirty():
		StudioSafety.clear_autosave(model.path)
		_autosaved_text = ""
		_autosaved_at = -1
		return
	var text := model.to_text()
	if text != _autosaved_text and StudioSafety.autosave(model):
		_autosaved_text = text
		_autosaved_at = Time.get_ticks_msec()


func _notification(what: int) -> void:
	# Closing the window keeps unsaved changes (the next open restores them).
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave_now()


## A newer autosave with other contents than the piece: put it back as one
## undo step. Whether it did.
func _restore_autosave() -> bool:
	var text := StudioSafety.pending_autosave(model.path)
	if text == "":
		return false
	var unix := FileAccess.get_modified_time(StudioSafety.autosave_path(model.path))
	var local := Time.get_datetime_dict_from_unix_time(unix + Time.get_time_zone_from_system().get("bias", 0) * 60)
	var when := "%02d:%02d" % [local.hour, local.minute]
	var r := model.replace_document(text, "Restore the unsaved changes from %s" % when)
	if not r.ok:
		return false
	_autosaved_text = model.to_text()
	_say("Opened %s with its unsaved changes from %s (kept by the autosave; undo drops them)." % [_piece_name(), when])
	return true


## Open a script (or a video with its sidecar script) for editing. A video
## with no script gets a new, empty one next to it (<video>.json). Returns
## whether it opened; the current piece stays otherwise. The piece that was
## open keeps its unsaved changes in its autosave; one whose autosave has
## changes that weren't saved gets them back (StudioSafety).
func open_piece(path: String) -> bool:
	var r: Dictionary
	var fresh := false
	if DefaultScreen.is_video(path) and DefaultScreen.sidecar_script(path) == "":
		r = EditModel.new_piece(path, EditModel.new_piece_template() if use_template else {})
		fresh = true
	else:
		if DefaultScreen.is_video(path):
			path = DefaultScreen.sidecar_script(path)
		r = EditModel.open(path)
	if not r.ok:
		_say("Can't open %s: %s" % [path.get_file(), r.error])
		return false
	autosave_now()  # the piece being left
	_autosaved_text = ""
	_autosaved_at = -1
	_autosave_clock = 0.0
	_drop_held()
	recorder.cancel()
	recorder.armed.clear()
	if miniature_on:
		toggle_miniature()
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
		_say("New piece %s: %s" % [model.path.get_file(),
				"it starts with a screen showing the video; add more from the shelf." if model.spawn_index("main_screen") >= 0
				else "add things from the shelf."])
		shelf_on = true
		for view in _shelves():
			view.show_tab("object")
		_show_shelf()
	else:
		if shelf_on and shelf.tab == StudioAssetShelf.OPEN_TAB:
			shelf_on = false  # it was open to pick a piece
			_show_shelf()
		if not _restore_autosave():
			_say("Opened %s." % _piece_name())
	return true


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_apply_mode()


func _apply_mode() -> void:
	var editing := mode == Mode.EDIT
	# Play is the audience view: the script moves the viewer. In Edit you
	# fly freely.
	var was_driving := stage.drive_viewer
	stage.drive_viewer = not editing
	if not editing and not was_driving:
		stage.follow_script_viewer()
	stage.router.set_context("studio_edit", editing)
	status_view.visible = editing
	# The wrist shows only in the headset (the stage turns it on with VR).
	stage.xr_rig.wrist_panel.visible = editing and stage.xr_mode.is_in_vr()
	stage.desktop_camera.movement_enabled = editing
	if tools != null:
		if not editing:
			if miniature_on:
				toggle_miniature()
			if recorder.is_active():
				_stop_take()
			tools.cancel()
			_drop_held()
		tools.visible = editing
		_show_floor_grid()
		flight.enabled = editing and stage.xr_mode.is_in_vr()
		_show_inspector()
		_show_ribbon()
		_show_shelf()
		_show_menu()


func save() -> bool:
	if model == null:
		return false
	# The file this save replaces is kept (only when it changes, and only
	# when it will be saved: an invalid piece isn't).
	if model.is_dirty() and model.check().ok:
		StudioSafety.back_up(model.path)
	var r := model.save()
	if r.ok:
		StudioSafety.clear_autosave(model.path)
		_autosaved_text = ""
		_autosaved_at = -1
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
		&"studio_menu": toggle_menu()
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
		&"studio_prev_key", &"studio_next_key":
			if model != null:
				ribbon.step_key(1 if id == &"studio_next_key" else -1)
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
				drop_held_at(_hand_xf(_main_hand()))
		&"studio_grab": _grab_with(_hand_of(stage.router.last_input, _main_hand()))
		&"studio_grab_left": _grab_with(_hand_of(stage.router.last_input, _off_hand()))
		&"studio_key_viewer": key_viewer(false)
		&"studio_cut_here": key_viewer(true)
		&"studio_miniature": toggle_miniature()
		&"studio_save_look": save_look()
		&"studio_arm_ride":
			recorder.arm_viewer = not recorder.arm_viewer
			# Armed, the status says what it does for as long as it is.
			_say("Ride armed." if recorder.arm_viewer else "Ride not armed: takes record only what's armed or grabbed.")
		&"studio_key_selection":
			if model != null and tools.selected == ScriptFormat.VIEWER:
				key_viewer(false)
			elif model != null:
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
			if menu_on:
				_set_menu(false)  # Esc closes the menu first
			elif recorder.is_active():
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
		&"studio_toggle_hints":
			status_view.show_hints(not status_view.hints_on)
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


## The hand that points and acts: "R", or "L" with the Left-handed
## profile (XRRig.main_hand); and the other one.
func _main_hand() -> String:
	return stage.xr_rig.main_hand


func _off_hand() -> String:
	return "R" if _main_hand() == "L" else "L"


## 1, or -1 when left-handed: panels placed to one side go to the other.
func _side() -> float:
	return -1.0 if _main_hand() == "L" else 1.0


func _select_pointed() -> void:
	var xf := _hand_xf(_main_hand())
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
	var k := tools.pick_key(xf.origin, -xf.basis.z)  # a key of the selection's path first
	if not k.is_empty():
		tools.grab_key(k, hand, xf)
		return
	var id := tools.pick(xf.origin, -xf.basis.z)
	if id == "":
		return
	tools.grab(id, hand, xf)


func _release(hand: String) -> void:
	if tools.is_grabbing_key():
		tools.release_key(hand)
	elif tools.is_grabbing():
		tools.release_hand(hand)


## While grabbing in the headset: follow the controllers; the right stick
## pushes / pulls.
func _follow_hands(delta: float) -> void:
	flight.right_stick_busy = tools.is_grabbing()
	if tools.is_grabbing_key() and stage.xr_mode.is_in_vr():
		for hand in ["L", "R"]:
			tools.move_key_hand(hand, _hand_xf(hand))
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
				var k := tools.pick_key(xf.origin, -xf.basis.z)
				if not k.is_empty():
					tools.grab_key(k, "M", xf)
				else:
					var id := tools.pick(xf.origin, -xf.basis.z)
					tools.select(id)
					if id != "":
						tools.grab(id, "M", xf)
			elif tools.is_grabbing_key():
				tools.release_key("M")
			else:
				tools.release_hand("M")
			get_viewport().set_input_as_handled()
		elif tools.is_grabbing() and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			tools.push(WHEEL_PUSH if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -WHEEL_PUSH)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and tools.is_grabbing_key():
		tools.move_key_hand("M", _mouse_hand())
	elif event is InputEventMouseMotion and tools.is_grabbing():
		tools.move_hand("M", _mouse_hand())


# ---------- the inspector ----------

func _bind_inspector(view: StudioInspector) -> void:
	view.edits = edits
	view.tools = tools
	view.said.connect(_say)
	view.action.connect(_on_command)
	view.close_requested.connect(func(): tools.select(""))
	view.minimize_requested.connect(_fold.bind(&"studio_toggle_inspector"), CONNECT_DEFERRED)
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
	# On the rig: it comes along as you fly, turn or jump.
	stage.xr_rig.add_child(inspector_panel)
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
	# To the side of the hand that acts (the right; mirrored left-handed).
	toward = toward.normalized().rotated(Vector3.UP, -deg_to_rad(angle) * _side())
	var at := head.origin + toward * INSPECTOR_DISTANCE - Vector3(0, INSPECTOR_DROP, 0)
	# The quad's front is +Z: look away from the head.
	inspector_panel.global_transform = Transform3D(Basis.looking_at(at - head.origin, Vector3.UP), at)
	var view := _vr_inspector()
	if view != null:
		view.show_object(tools.selected)


## The panels ride on the rig, so flying, turning and jumps carry them; this
## brings the headset panel back after walking away from it (or the
## miniature's change of scale).
func _keep_inspector_near() -> void:
	_vr_inspector()
	if inspector_panel == null or not inspector_panel.visible:
		return
	if stage.viewer_transform().origin.distance_to(inspector_panel.global_transform.origin) > INSPECTOR_REPLACE:
		_place_inspector_panel()


# ---------- folding panels ----------

## – on a panel: switch it off, leaving its tab (the wrist's button for it,
## on the desktop a tab in the status). The tab or its key brings it back.
func _fold(id: StringName) -> void:
	if not id in folded_panels():
		_on_command(id)
	var t: Array = StudioStatus.TABS.filter(func(t): return t[0] == id)[0]
	if stage.xr_mode.is_in_vr():
		_say("%s folded: its button on the wrist brings it back." % t[1])
	else:
		_say("%s folded: its tab up top (or %s) brings it back." % [t[1], t[2]])


## The panels that are switched off (their commands, as in StudioStatus.TABS).
func folded_panels() -> Array:
	var out: Array = []
	for t in StudioStatus.TABS:
		var on: bool = {&"studio_toggle_inspector": inspector_on, &"studio_toggle_timeline": timeline_on,
				&"studio_toggle_shelf": shelf_on}[t[0]]
		if not on:
			out.append(t[0])
	return out


# ---------- the timeline ----------

func _bind_ribbon(view: StudioTimelineRibbon) -> void:
	view.edits = edits
	view.tools = tools
	view.waveform = waveform
	view.loop = loop
	view.recorder = recorder
	view.said.connect(_say)
	view.minimize_requested.connect(_fold.bind(&"studio_toggle_timeline"), CONNECT_DEFERRED)


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
	# On the rig: it comes along as you fly, turn or jump.
	stage.xr_rig.add_child(ribbon_panel)
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


# ---------- the viewer ----------

## Where you are: your eye, and which way you face (°).
func _eye_pose() -> Dictionary:
	var xf := stage.viewer_transform()
	var fwd := -xf.basis.z
	return {"position": xf.origin, "yaw": rad_to_deg(atan2(-fwd.x, -fwd.z))}


## Key the viewer where you are, at the playhead: a glide into it, or with
## `cut` a jump there (with a short fade).
func key_viewer(cut: bool) -> void:
	if model == null:
		return
	var eye := _eye_pose()
	var p: Vector3 = eye.position
	var t := snappedf(runner.playhead, 0.001)
	var pos := [p.x, p.y, p.z].map(func(v): return float("%.3f" % v))
	if model.key_viewer(t, pos, float("%.2f" % eye.yaw), cut, {"type": "fade_to_black", "duration": CUT_FADE} if cut else {}):
		tools.select(ScriptFormat.VIEWER)
		_say(model.undo_label() + ".")
		haptics.tick("key", _main_hand())


# ---------- the miniature ----------

## Into the miniature, or back to where you were.
func toggle_miniature() -> void:
	if miniature_on:
		miniature_on = false
		if _before_miniature.has("origin"):
			XRServer.world_scale = float(_before_miniature.scale)
			stage.xr_rig.global_transform = _before_miniature.origin
		elif _before_miniature.has("camera"):
			stage.desktop_camera.set_view(_before_miniature.camera, _before_miniature.rotation)
		_before_miniature = {}
		_say("Back to full size.")
		return
	var box := scene_bounds()
	var center := box.get_center()
	var size := maxf(maxf(box.size.x, box.size.z), 4.0)
	miniature_on = true
	if stage.xr_mode.is_in_vr():
		var rig := stage.xr_rig
		_before_miniature = {"origin": rig.global_transform, "scale": XRServer.world_scale}
		var s := maxf(size / MINIATURE_SIZE, 1.0)
		XRServer.world_scale = s
		# Stand at the table's near edge, facing across it.
		var fwd := -stage.viewer_transform().basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
		rig.recenter(Vector3(center.x, 0.0, center.z) - fwd * (size * 0.5 + 0.35 * s), rad_to_deg(atan2(-fwd.x, -fwd.z)))
		rig.global_position.y = box.position.y - MINIATURE_TABLE * s
		_say("Miniature: the scene at 1:%d, as a table. M to go back." % roundi(s))
	else:
		var cam := stage.desktop_camera
		_before_miniature = {"camera": cam.global_position, "rotation": cam.rotation_degrees}
		# From high above the seat's side, looking steeply down on it.
		var dist := size * 0.8 + 4.0
		var eye := center + Vector3(0.0, dist * 0.94, dist * 0.34)
		cam.set_view(eye, Vector3(-rad_to_deg(atan2(dist * 0.94, dist * 0.34)), 0.0, 0.0))
		_say("Miniature: the whole scene from above. M to go back.")


## Everything in the piece now, in the world: the objects on stage and the
## viewer's keys (a 20 m square around the seat when there's nothing).
func scene_bounds() -> AABB:
	var out := AABB()
	var found := false
	if model != null:
		for id in model.object_ids():
			var node := runner.registry().get_node_by_id(id)
			if node == null or not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree():
				continue
			var local := StudioPicker.local_bounds(node)
			if local.size == Vector3.ZERO:
				continue
			var box := node.global_transform * local
			out = box if not found else out.merge(box)
			found = true
		var vt := ViewerTrack.new()
		vt.build(model.tracks())
		for t in vt.key_times():
			var p: Vector3 = vt.pose_at(t).position
			out = AABB(p, Vector3.ZERO) if not found else out.expand(p)
			found = true
	return out if found else AABB(Vector3(-10, 0, -10), Vector3(20, 4, 20))


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
	_take_felt = false
	stage.seek_to(start)
	runner.play()
	var armed := recorder.armed.size()
	var what := "move the armed sliders (%d), or grab something" % armed if armed > 0 else "grab something (or arm sliders with their ●)"
	if recorder.arm_viewer:
		what = "fly the ride" + (", and move the armed sliders (%d)" % armed if armed > 0 else "")
	_say("Recording from %s%s: %s." % [StudioStatus.timecode(from), " to %s" % StudioStatus.timecode(loop.b) if looping else "", what])


## End the take and write it. A slider still being dragged, or an object
## still held, is let go of: the take has what they did.
func _stop_take() -> void:
	var label := recorder.finish()
	_after_take()
	runner.pause()
	if label != "":
		haptics.tick("key", "both")
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
	if not _take_felt and runner.playhead >= recorder.from:
		_take_felt = true
		haptics.tick("record", "both")  # the pre-roll is over: it records now
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
	view.close_requested.connect(_fold.bind(&"studio_toggle_shelf"), CONNECT_DEFERRED)
	thumbnailer.thumbnail_ready.connect(view.on_thumbnail)
	thumbnailer.loop_ready.connect(view.on_loop)


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
	# On the rig: it comes along as you fly, turn or jump.
	stage.xr_rig.add_child(shelf_panel)
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


## To your front left (right when left-handed), a little below your eyes,
## facing you.
func _place_shelf_panel() -> void:
	if shelf_panel == null:
		return
	var head := stage.viewer_transform()
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var toward := fwd.rotated(Vector3.UP, deg_to_rad(SHELF_ANGLE) * _side())
	var at := head.origin + toward * SHELF_DISTANCE - Vector3(0, SHELF_DROP, 0)
	# The quad's front is +Z: look away from the head.
	shelf_panel.global_transform = Transform3D(Basis.looking_at(at - head.origin, Vector3.UP), at)
	_vr_shelf()


func _keep_shelf_near() -> void:
	var view := _vr_shelf()
	if view != null:
		# Every card plays its loop while the headset's shelf is open.
		view.play_all = shelf_panel.visible
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
	_held_hand = _main_hand() if stage.xr_mode.is_in_vr() else "M"
	_trigger_was_down = true
	for other in _shelves():
		other.show_held(asset.id)
	var tex := thumbnailer.thumbnail(asset)
	_ghost.set_picture(tex)
	_say("Carrying %s: let go where it goes (Esc puts it back)." % asset.label)


## Save the selection's setup (prefab, config, size) as a look on the
## shelf (StudioLooks, in the first library folder), with a snapshot of it
## as it is on stage for its card.
func save_look() -> Dictionary:
	var id := tools.selected
	if model == null or id == "" or id == ScriptFormat.VIEWER:
		_say("Select a screen, layer or object to save its look.")
		return {"ok": false}
	var node := runner.registry().get_node_by_id(id) as Node3D
	var r := StudioLooks.save(model, id, edits.kind_for(id, node), library.library_dirs[0])
	if not r.ok:
		_say("Couldn't save the look: %s." % r.error)
		return r
	if node != null:
		thumbnailer.snapshot(node, StudioLooks.picture_path(r.path), "look:" + r.path)
	_library_signature = library.signature()
	_refresh_shelf()
	_say("Saved the look %s: it's on the shelf's Looks tab." % r.label)
	return r


## Put the carried card back (nothing added).
func _drop_held() -> void:
	held_asset = {}
	_held_hand = ""
	_ghost.visible = false
	for view in _shelves():
		view.show_held("")


## Drop the carried card where `hand_xf` points (its -Z). Returns whether
## something was added or changed.
func drop_held_at(hand_xf: Transform3D) -> bool:
	if held_asset.is_empty() or model == null:
		return false
	var asset := held_asset
	var hand := _held_hand
	_drop_held()
	var where := StudioAssetDrop.aim(hand_xf.origin, -hand_xf.basis.z, tools.candidates())
	var r := dropper.drop(asset, where, stage.viewer_transform().origin, runner.playhead, tools.snap)
	if r.ok:
		tools.select(r.id)
	_say(r.message)
	haptics.tick("drop" if r.ok else "refuse", hand)
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
		xf = _hand_xf(_held_hand)
		var down := stage.router.is_down(_held_hand + ".trigger")
		if _trigger_was_down and not down and not over_ui:
			_trigger_was_down = false
			drop_held_at(xf)
			return
		_trigger_was_down = down
	_ghost.visible = not over_ui
	if not over_ui:
		show_carry(xf)


## Show where the carried card would land, pointed along `hand_xf`'s -Z.
func show_carry(xf: Transform3D) -> void:
	var where := StudioAssetDrop.aim(xf.origin, -xf.basis.z, tools.candidates())
	var head := stage.viewer_transform().origin
	message = _drop_hint(held_asset, where)
	if not dropper.adds(held_asset, where):
		_ghost.show_card(where.point, head)
		return
	var bounds := dropper.bounds_for(held_asset)
	var spawn := StudioAssetDrop.placement(held_asset, where, head, bounds, tools.snap)
	_ghost.show_object(spawn, bounds, head)
	var p: Vector3 = where.point
	message = message.trim_suffix(".") + ", %.1f m away." % Vector2(p.x - head.x, p.z - head.z).length()


## What letting go here would do, for the status.
func _drop_hint(asset: Dictionary, where: Dictionary) -> String:
	var on := String(where.on)
	var kind := edits.kind_for(on) if on != "" else ""
	match String(asset.type):
		"effect":
			return "Let go: add %s to %s." % [asset.label, on] if kind in ["screen", "layer"] else "Point %s at a screen or a layer." % asset.label
		"vertex":
			return "Let go: add %s to %s's vertex effects." % [asset.label, on] if kind in ["screen", "layer"] else "Point %s at a screen or a layer." % asset.label
		"layer":
			if kind == "layer":
				return "Let go: %s shows %s." % [on, asset.label]
		"look":
			if on != "" and kind == asset.kind:
				return "Let go: %s takes the look %s." % [on, asset.label]
	return "Let go: add %s here." % asset.label


## Desktop: whether the mouse is over one of Studio's panels.
func _mouse_over_ui() -> bool:
	var at := get_viewport().get_mouse_position()
	for panel in [shelf, inspector, ribbon, status_view]:
		if panel != null and panel.visible and panel.get_global_rect().has_point(at):
			return true
	return menu_2d != null and menu_2d.visible and menu_2d.get_global_rect().has_point(at)


func _input(event: InputEvent) -> void:
	# Desktop: a card dragged off the shelf drops where the button comes up
	# (the release goes to the card, so it's caught here, before the GUI).
	if held_asset.is_empty() or _held_hand != "M" or stage.xr_mode.is_in_vr():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed \
			and not _mouse_over_ui():
		drop_held_at(_mouse_hand())


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
	# The timeline's switch and Shift+I change the key mode too: keep it.
	var key_mode := StudioTimelineRibbon.key_mode_of(tools)
	if key_mode != studio_settings.key_mode:
		studio_settings.key_mode = key_mode
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
		recorder.arm_viewer,
		tools.key_animated,
	]
	if status_view.visible:
		status_view.callv("show_state", args)
		status_view.show_tabs(folded_panels())
	if _wrist == null or not is_instance_valid(_wrist):
		_wrist = stage.xr_rig.wrist_content() as StudioWristPalette
		if _wrist != null:
			_wrist.action.connect(_on_command)
			_wrist.show_fps(_settings.show_fps)
	if _wrist != null and stage.xr_rig.wrist_panel.visible:
		_wrist.show_state(_wrist_state(args))
		_wrist.show_toggles(tools.auto_key, tools.snap, inspector_on, timeline_on, loop.on, shelf_on, recorder.is_active(), recorder.arm_viewer, miniature_on)


## The wrist palette's state: the status's, plus the bar and the autosave.
func _wrist_state(args: Array) -> Dictionary:
	var grid: BeatGrid = stage.beats.grid if stage.beats != null else null
	var on_grid := grid != null and grid.is_valid() and grid.beat_at(runner.playhead) >= 0.0
	return {
		"mode": args[0], "title": args[1], "dirty": args[2], "t": args[3], "duration": args[4],
		"playing": args[5], "message": args[6], "auto_key": args[7], "snap": args[8],
		"recording": args[9], "ride_armed": args[10], "key_animated": args[11],
		"bar": grid.bar_at(runner.playhead) if on_grid else null,
		"beats_per_bar": grid.beats_per_bar if on_grid else 4,
		"autosaved": (Time.get_ticks_msec() - _autosaved_at) / 1000.0 if _autosaved_at >= 0 and studio_settings.autosave else -1.0,
	}


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


# ---------- the menu and settings ----------

## The desktop's menu size (UI pixels) and the headset panel's.
const MENU_SIZE := Vector2(900, 620)


func _make_menu() -> void:
	menu_2d = MENU_SCENE.instantiate()
	menu_2d.name = "Menu"
	menu_2d.visible = false
	$UI.add_child(menu_2d)
	menu_2d.custom_minimum_size = MENU_SIZE
	menu_2d.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_bind_menu_view(menu_2d)
	menu_panel = FloatingPanel.new()
	menu_panel.name = "MenuPanel"
	menu_panel.content_scene = MENU_SCENE
	menu_panel.viewport_px = MENU_SIZE
	add_child(menu_panel)
	stage.add_masked_panel(menu_panel.panel_quad())
	StudioThumbnailer.mark_helper(menu_panel)
	_bind_menu_panel()


## The panel's content appears a frame or two after it's made.
func _bind_menu_panel() -> void:
	for i in 30:
		menu = menu_panel.content() as StudioMenu
		if menu != null:
			break
		await get_tree().process_frame
	if menu == null:
		push_warning("Studio's headset menu never appeared.")
		return
	_bind_menu_view(menu)


func _bind_menu_view(view: StudioMenu) -> void:
	view.bind(_settings, stage.router, studio_settings)
	view.close_requested.connect(func(): _set_menu.call_deferred(false))


## The menu showing now: the headset's in VR, else the desktop's.
func menu_view() -> StudioMenu:
	return menu if stage.xr_mode.is_in_vr() else menu_2d


## Opens the menu (in front of you in the headset), or closes it.
func toggle_menu() -> void:
	_set_menu(not menu_on)
	_say("Menu: settings shared with the player, controls, Studio's options (F2 closes it)." if menu_on else "Menu closed.")


func _set_menu(on: bool) -> void:
	menu_on = on
	_show_menu()


func _show_menu() -> void:
	if menu_2d == null:
		return
	var vr := stage.xr_mode.is_in_vr()
	menu_2d.visible = menu_on and not vr
	if menu_on and vr and not menu_panel.visible:
		menu_panel.show_in_front_of(get_viewport().get_camera_3d())
	elif not (menu_on and vr) and menu_panel.visible:
		menu_panel.hide_panel()


func _apply_studio_settings() -> void:
	tools.auto_key = studio_settings.key_mode == "all"
	tools.key_animated = studio_settings.key_mode == "animated"
	haptics.enabled = studio_settings.haptics
	_show_floor_grid()


## The floor grid shows while editing, when the setting is on.
func _show_floor_grid() -> void:
	if floor_grid != null:
		floor_grid.visible = studio_settings.floor_grid and mode == Mode.EDIT


## Desktop Studio is laid out for 1920 × 1080: smaller, the shelf is squeezed
## between the status and the timeline. A window still at the project's
## default size opens at that, centred (maximized on a smaller screen); one
## given a size (`--resolution`, as the checks do) keeps it.
func _size_window() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):
		return
	var window := get_window()
	var default := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	if window.mode != Window.MODE_WINDOWED or window.size != default:
		return
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	if usable.size.x < DESKTOP_SIZE.x or usable.size.y < DESKTOP_SIZE.y + 40:  # the title bar
		window.mode = Window.MODE_MAXIMIZED
		return
	window.size = DESKTOP_SIZE
	window.position = usable.position + (usable.size - DESKTOP_SIZE) / 2


## The player's settings Studio applies itself (the stage does the rest).
func _apply_player_settings() -> void:
	status_view.show_fps(_settings.show_fps)
	if _wrist != null and is_instance_valid(_wrist):
		_wrist.show_fps(_settings.show_fps)
	if DisplayServer.get_name() == "headless" or stage.xr_mode.is_in_vr():
		return
	var mode_now := DisplayServer.window_get_mode()
	var is_full := mode_now == DisplayServer.WINDOW_MODE_FULLSCREEN or mode_now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if is_full != _settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
