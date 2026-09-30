extends SceneTree

## TODO 78: logs the runner's playhead (what the scrub bar and Studio's
## timeline draw) every frame while a video opens, plays, and is scrubbed
## (playing and paused), in the player (APP=player) or Studio (default),
## and lists every frame where the playhead went anywhere other than where
## it should: back in time, or on by more than the frame's length while
## playing (no seek), or off the scrubbed time while scrubbing.
## AUTOPLAY=1 plays from the open on.
## Needs a real decoder and a video (VIDEO); DECODER=native|gozen picks one.
##   VIDEO=... tools/local/run.sh checks/drive_playhead_glitch.gd
##   APP=player VIDEO=... tools/local/run.sh checks/drive_playhead_glitch.gd

var app: Node
var stage: Stage
var runner: ScriptRunner
var rows: Array = []
var phase := ""
var target := -1.0  # the time seeked to this frame, -1 = none
var _last_us := 0
var _start_us := 0


func _initialize() -> void:
	var video_path := OS.get_environment("VIDEO")
	var is_player := OS.get_environment("APP") == "player"
	app = load("res://player/main.tscn" if is_player else "res://studio/studio.tscn").instantiate()
	root.add_child(app)
	await frames(10)
	stage = app.stage
	runner = app.stage.runner
	if OS.get_environment("DECODER") != "":
		stage.settings.video_decoder = OS.get_environment("DECODER")
	_start_us = Time.get_ticks_usec()
	_last_us = _start_us
	# AUTOPLAY=1: playing while it opens (the player's usual open).
	var autoplay := OS.get_environment("AUTOPLAY") == "1"
	phase = "open"
	if is_player:
		app.open_file(video_path, autoplay)
	else:
		print("open: ", app.open_piece(video_path))
		if autoplay:
			runner.play()
	var video: VideoBridge = stage.video
	for i in 900:
		await logged_frame()
		if not video.is_loading() and video.duration_seconds() > 0.0 and not video.is_busy():
			break
	print("decoder: ", video.active_decoder())
	await logged_frames(30)
	phase = "play"
	runner.play()
	await logged_frames(180)
	# A drag along the bar while playing: a seek every frame, 20 ms on.
	phase = "scrub playing"
	var t := runner.playhead
	for i in 120:
		t += 0.02
		await seek_frame(t)
	phase = "after scrub"
	await logged_frames(180)
	# Single jumps while playing (a click on the bar).
	phase = "click playing"
	for jump in [30.0, 10.0, 50.0]:
		await seek_frame(jump)
		await logged_frames(90)
	phase = "pause"
	runner.pause()
	await logged_frames(30)
	phase = "scrub paused"
	t = runner.playhead
	for i in 120:
		t -= 0.03
		await seek_frame(t)
	phase = "after paused scrub"
	await logged_frames(90)
	_report()
	quit()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func logged_frames(n: int) -> void:
	for i in n:
		await logged_frame()


func seek_frame(t: float) -> void:
	target = t
	stage.seek_to(t)
	await logged_frame()


func logged_frame() -> void:
	await process_frame
	var now := Time.get_ticks_usec()
	rows.append({
		"wall": (now - _start_us) / 1e6,
		"dt": (now - _last_us) / 1e6,
		"run": runner.playhead,
		"vid": stage.video.playhead_seconds(),
		"aud": stage.video.audio_seconds(),
		"hold": runner.hold,
		"playing": runner.playing,
		"phase": phase,
		"target": target,
	})
	target = -1.0
	_last_us = now


func _report() -> void:
	var glitches: Array = []
	var counts := {}
	for i in range(1, rows.size()):
		var a: Dictionary = rows[i - 1]
		var b: Dictionary = rows[i]
		var step: float = b.run - a.run
		var why := ""
		if b.target >= 0.0:
			# Seeked this frame, then ticked once if playing.
			var after: float = b.run - b.target - (b.dt if b.playing and not b.hold else 0.0)
			if absf(after) > 0.03:
				why = "%+.0f ms off the seek to %.3f" % [after * 1000.0, b.target]
		elif step < -0.001:
			why = "back %.0f ms" % (-step * 1000.0)
		elif not (b.playing and not b.hold) and step > 0.001:
			why = "moved %+.0f ms while stopped (playing %s, hold %s)" % [step * 1000.0, b.playing, b.hold]
		elif b.playing and not b.hold and step > b.dt + 0.03:
			why = "on %.0f ms in a %.0f ms frame" % [step * 1000.0, b.dt * 1000.0]
		if why != "":
			counts[b.phase] = int(counts.get(b.phase, 0)) + 1
			glitches.append("%6.2f s  [%s]  run %.3f  vid %.3f  aud %.3f  hold %s  %s" % [b.wall, b.phase, b.run, b.vid, b.aud, b.hold, why])
	print("frames ", rows.size(), ", glitches ", glitches.size(), " by phase ", counts)
	for g in glitches.slice(0, 80):
		print("  ", g)
	if OS.get_environment("DUMP") != "":
		for r in rows:
			print("  %6.3f %-18s dt %3.0f  run %7.3f  vid %7.3f  aud %7.3f  hold %-5s tgt %7.3f" % [r.wall, r.phase, r.dt * 1000.0, r.run, r.vid, r.aud, r.hold, r.target])
