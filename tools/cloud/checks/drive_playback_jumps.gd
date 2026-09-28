extends SceneTree

## Plays a video in Studio for SECONDS (default 40) in real time and logs,
## every frame, the frame's length, the runner's playhead, the video's own
## position and the sound's, then lists what jumped: long frames, the
## playhead moving other than by the frame's length, the picture moving
## other than by it, and how far the runner, picture and sound drift apart.
## Needs a real decoder and a video (VIDEO, else $WORK/jump_piece/clip.mp4).
##   VIDEO=... SECONDS=60 tools/local/run.sh checks/drive_playback_jumps.gd
## HITCH_MS stalls the main thread that long every HITCH_EVERY seconds
## (default 5), standing in for a hitch (an autosave, a shader compile).

var studio: Node


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	var video_path := OS.get_environment("VIDEO")
	if video_path == "":
		video_path = OS.get_environment("WORK").path_join("jump_piece/clip.mp4")
	var seconds := float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 40.0
	studio = load("res://studio/studio.tscn").instantiate()
	root.add_child(studio)
	await frames(10)
	print("open: ", studio.open_piece(video_path))
	var video = studio.stage.video
	var runner: ScriptRunner = studio.runner
	for i in 600:
		await process_frame
		if video != null and not video.is_loading() and video.duration_seconds() > 0.0 and runner.effective_duration() > 0.0 and not video.is_busy():
			break
	print("loaded: duration ", runner.effective_duration(), ", fps ", 30.0)
	await frames(30)
	studio._toggle_play()
	var rows: Array = []
	var start_ms := Time.get_ticks_usec()
	var last_us := start_ms
	var hitch_ms := int(OS.get_environment("HITCH_MS"))
	var hitch_every := float(OS.get_environment("HITCH_EVERY")) if OS.get_environment("HITCH_EVERY") != "" else 5.0
	var next_hitch := hitch_every
	while (Time.get_ticks_usec() - start_ms) / 1e6 < seconds:
		await process_frame
		if hitch_ms > 0 and (Time.get_ticks_usec() - start_ms) / 1e6 >= next_hitch:
			next_hitch += hitch_every
			OS.delay_msec(hitch_ms)
		var now := Time.get_ticks_usec()
		rows.append({
			"wall": (now - start_ms) / 1e6,
			"dt": (now - last_us) / 1e6,
			"delta": get_root().get_process_delta_time() if false else 0.0,
			"run": runner.playhead,
			"vid": video.playhead_seconds(),
			"aud": video.audio_seconds(),
			"hold": runner.hold,
			"playing": runner.playing,
		})
		last_us = now
	runner.pause()
	_report(rows, 30.0)
	_time_periodic_work()
	quit()


## Studio's work that runs every so often while playing: how long each
## takes (a hitch if long), and whether an autosave counts as a library
## change (which rebuilds the shelf).
func _time_periodic_work() -> void:
	var t := Time.get_ticks_usec()
	var sig: String = studio.library.signature()
	print("library signature: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	studio._refresh_shelf()
	print("shelf refresh: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	studio.model._saved_depth = -1  # unsaved changes, as while editing
	t = Time.get_ticks_usec()
	studio.autosave_now()
	print("autosave: %.1f ms (dirty %s)" % [(Time.get_ticks_usec() - t) / 1000.0, studio.model.is_dirty()])
	print("autosave changes the library signature: ", studio.library.signature() != sig)
	t = Time.get_ticks_usec()
	for i in 10:
		studio.tools.pick(Vector3(0, 1.6, 3), Vector3(0, 0, -1))
	print("hover pick: %.2f ms" % ((Time.get_ticks_usec() - t) / 10000.0))


func _report(rows: Array, fps: float) -> void:
	var frame := 1.0 / fps if fps > 0.0 else 1.0 / 30.0
	var long_frames := 0
	var worst_dt := 0.0
	var events: Array = []
	var holds := 0
	var sound_jumps := 0
	var run_vid: Array = []
	var aud_vid: Array = []
	# Seconds the picture / playhead were more than OFF from the sound,
	# counted from 0.3 s after each long frame (the catch-up's time).
	const OFF := 0.1
	var off_picture := 0.0
	var off_run := 0.0
	var settle_until := 0.0
	for i in range(1, rows.size()):
		var a: Dictionary = rows[i - 1]
		var b: Dictionary = rows[i]
		worst_dt = maxf(worst_dt, b.dt)
		if b.dt > 0.05:
			long_frames += 1
			settle_until = b.wall + 0.3
			events.append("%6.2f s  long frame %.0f ms" % [b.wall, b.dt * 1000.0])
		if b.hold and not a.hold:
			holds += 1
			events.append("%6.2f s  runner held (video busy)" % b.wall)
		if not (b.playing and a.playing):
			continue
		# The sound is heard continuously: it only ever moves by the wall time
		# (its reading jitters by a mix period, about 20 ms).
		if a.aud >= 0.0 and b.aud >= 0.0 and absf((b.aud - a.aud) - b.dt) > 0.06:
			sound_jumps += 1
			events.append("%6.2f s  SOUND moved %+.0f ms in a %.0f ms frame" % [b.wall, (b.aud - a.aud) * 1000.0, b.dt * 1000.0])
		if b.aud >= 0.0 and b.wall > settle_until:
			if absf(b.vid + frame - b.aud) > OFF + frame:
				off_picture += b.dt
			if absf(b.run - b.aud) > OFF:
				off_run += b.dt
		run_vid.append(b.run - b.vid)
		if b.aud >= 0.0:
			aud_vid.append(b.aud - b.vid)
	print("frames ", rows.size(), ", long (>50 ms) ", long_frames, ", worst ", snappedf(worst_dt * 1000.0, 1), " ms, holds ", holds)
	print("sound jumps: ", sound_jumps)
	print("picture off the sound (>%d ms) outside catch-ups: %.2f s; playhead: %.2f s" % [OFF * 1000.0, off_picture, off_run])
	print("runner - picture: ", _range(run_vid), "   first ", _mean(run_vid.slice(0, 30)), " last ", _mean(run_vid.slice(-30)))
	print("sound - picture:  ", _range(aud_vid), "   first ", _mean(aud_vid.slice(0, 30)), " last ", _mean(aud_vid.slice(-30)))
	print("events (", events.size(), "):")
	for e in events.slice(0, 60):
		print("  ", e)
	var next := 0.0
	for r in rows:
		if r.wall >= next:
			print("  t=%5.1f  run %7.3f  vid %7.3f  aud %7.3f" % [r.wall, r.run, r.vid, r.aud])
			next += 5.0


func _range(a: Array) -> String:
	if a.is_empty():
		return "-"
	return "%+.0f .. %+.0f ms" % [a.min() * 1000.0, a.max() * 1000.0]


func _mean(a: Array) -> String:
	if a.is_empty():
		return "-"
	var s := 0.0
	for x in a:
		s += x
	return "%+.0f ms" % (s / a.size() * 1000.0)
