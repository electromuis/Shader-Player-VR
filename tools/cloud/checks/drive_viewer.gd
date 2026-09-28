extends SceneTree

## The script's viewer (M7) in the player, on a copy of forest_tunnel given
## a ride: from the seat at 46 s (after the piece's own faded cut home at
## 44.5 s) into and through the tunnel (it arrives at 39.9 s, 80 m ahead),
## turning a little on the way, then a faded cut home at 56 s. Played in real time on the desktop: the camera follows the ride
## (and keeps a look to the side the viewer took during it); "cuts only"
## holds each key's place and fades from key to key; seeking into the ride
## lands on it; with the script camera off nothing moves. Headless
## (HEADLESS=1) it prints; rendered it also saves viewer_*.png to OUT_DIR.

var main: Node
var out := OS.get_environment("OUT_DIR")
var rendered := DisplayServer.get_name() != "headless"

const RIDE := [
	{"type": "transform", "target": "$viewer", "channel": "position", "keyframes": [
		{"t": 46.0, "value": [0, 2, 8]},
		{"t": 48.0, "value": [0, 3, -30], "interp": "ease"},
		{"t": 54.0, "value": [0, 3, -130]},
		{"t": 56.0, "value": [0, 2, 8], "transition": {"type": "fade_to_black", "duration": 1.0}}]},
	{"type": "transform", "target": "$viewer", "channel": "rotation_deg", "keyframes": [
		{"t": 46.0, "value": [0, 0, 0]}, {"t": 50.0, "value": [0, 20, 0]}, {"t": 54.0, "value": [0, 0, 0], "interp": "step"},
		{"t": 56.0, "value": [0, 0, 0]}]},
]


func frames(n: int) -> void:
	for i in n:
		await process_frame


func copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for d in DirAccess.get_directories_at(from):
		copy_tree(from.path_join(d), to.path_join(d))


func cam() -> Camera3D:
	return main.stage.desktop_camera


func v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


func where() -> String:
	return "%s yaw %.1f" % [v(cam().global_position), cam().rotation_degrees.y]


## Play from `from` until the playhead reaches `until`, calling `each(t)`
## every frame.
func play(from: float, until: float, each: Callable = Callable()) -> void:
	main.runner.seek(from)
	main.runner.play()
	while main.runner.playhead < until:
		await process_frame
		if each.is_valid():
			await each.call(main.runner.playhead)
	main.runner.pause()
	await frames(2)


func shot(name: String) -> void:
	if rendered:
		root.get_texture().get_image().save_png(out.path_join("viewer_%s.png" % name))


func _initialize() -> void:
	var repo := OS.get_environment("REPO")
	var dir := OS.get_environment("WORK").path_join("viewer_piece")
	copy_tree(repo.path_join("scripts/forest_tunnel"), dir)
	var piece := dir.path_join("video.json")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(piece))
	doc.tracks.append_array(RIDE)
	var f := FileAccess.open(piece, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	print("valid: ", ScriptFormat.load_from_file(piece).ok)

	main = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var settings: PlayerSettings = main.stage.settings
	settings.allow_script_camera = true
	settings.script_camera_cuts_only = false
	main.open_file(piece, false)
	main.runner.set_video_duration(180.0)
	await frames(4)
	var vt: ViewerTrack = main.runner.viewer
	print("viewer track: cuts at ", vt.cuts_between(0.0, 180.0).map(func(c): return c.t), ", moves ", vt.has_motion(),
			", fastest %.1f m/s" % vt.motion_at(51.0).speed)

	# Smooth: follow the ride; a look 15° to the side stays while riding.
	var looked := {"done": false, "shot": false}
	await play(45.0, 52.0, func(t: float):
		if t >= 47.0 and not looked.done:
			looked.done = true
			var r := cam().rotation_degrees
			cam().set_view(cam().global_position, Vector3(r.x, r.y + 15.0, 0.0))
			print("at %.2f s: camera %s, the ride's pose %s yaw %.1f (then the viewer looks 15° left)" % [t, where(), v(vt.pose_at(t).position), vt.pose_at(t).rotation_deg.y])
		if t >= 49.0 and not looked.has("comfort"):
			looked.comfort = main.stage.comfort_level()
		if t >= 50.5 and not looked.shot:
			looked.shot = true
			await shot("1_in_the_tunnel"))
	var pose := vt.pose_at(main.runner.playhead)
	print("smooth, at %.2f s: camera %s; the ride %s yaw %.1f: off by %.3f m, looking %.1f° aside" % [main.runner.playhead, where(),
			v(pose.position), pose.rotation_deg.y, cam().global_position.distance_to(pose.position), cam().rotation_degrees.y - pose.rotation_deg.y])
	print("comfort vignette (headset only): %.2f at 49 s (%.1f m/s), %.2f while paused" % [looked.comfort, vt.motion_at(49.0).speed, main.stage.comfort_level()])
	await play(52.0, 57.5)
	print("after the faded cut at 56 s: camera ", where())

	# Seeking into the ride lands on it.
	main.runner.seek(51.0)
	await frames(2)
	print("seek to 51 s: camera %s (the ride: %s)" % [where(), v(vt.pose_at(51.0).position)])
	main.runner.seek(20.0)
	await frames(2)
	print("seek to 20 s (before the ride): camera ", where())

	# Cuts only: hold each key's place, fade between them.
	settings.script_camera_cuts_only = true
	var seen := {"fade": false, "max_z": 99.0}
	await play(45.5, 51.0, func(t: float):
		var a: float = main.stage.fade_overlay.color.a
		if a > 0.2 and t > 47.9 and t < 48.8:
			seen.fade = true)
	print("cuts only, at %.2f s: camera %s (held at the 48 s key: %s), faded at 48 s: %s" % [main.runner.playhead, where(), v(vt.pose_at(48.0, true).position), seen.fade])
	await shot("2_cuts_only")

	# Off: the script doesn't move the viewer.
	settings.script_camera_cuts_only = false
	settings.allow_script_camera = false
	main.stage.reset_view()
	await play(45.0, 50.0)
	print("script camera off, at %.2f s: camera %s" % [main.runner.playhead, where()])
	print("VIEWER DONE")
	quit()
