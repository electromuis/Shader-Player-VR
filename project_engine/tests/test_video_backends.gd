extends RefCounted

## Video decoder choice: NativeVideoBackend's MP4 track probe (the extension
## aborts the process on a timecode track, so those files must go to gozen)
## and the PlayerSettings field that picks the decoder.

const CLIP := "user://test_tracks_tmp.mp4"
const SETTINGS := "user://test_player_settings_decoder_tmp.json"


static func _box(type: String, payload: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, 8 + payload.size())
	b.reverse()  # big-endian size
	b.append_array(type.to_ascii_buffer())
	b.append_array(payload)
	return b


static func _track(handler: String) -> PackedByteArray:
	var hdlr := PackedByteArray()
	hdlr.resize(8)  # version / flags, pre_defined
	hdlr.append_array(handler.to_ascii_buffer())
	hdlr.resize(hdlr.size() + 13)  # reserved + empty name
	var mdia := _box("mdhd", PackedByteArray([0, 0, 0, 0]))
	mdia.append_array(_box("hdlr", hdlr))
	return _box("trak", _box("mdia", mdia))


## ftyp, a dummy mdat, then moov with one trak per handler (moov last, as
## most encoders write it).
static func _write_clip(handlers: Array) -> String:
	var moov_payload := _box("mvhd", PackedByteArray([0, 0, 0, 0]))
	for h in handlers:
		moov_payload.append_array(_track(h))
	var bytes := _box("ftyp", "isom".to_ascii_buffer())
	bytes.append_array(_box("mdat", PackedByteArray([1, 2, 3, 4, 5])))
	bytes.append_array(_box("moov", moov_payload))
	var f := FileAccess.open(CLIP, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return ProjectSettings.globalize_path(CLIP)


static func test_reads_track_handlers(t: TestCase) -> void:
	var path := _write_clip(["vide", "soun", "tmcd"])
	t.assert_eq(NativeVideoBackend.mp4_track_handlers(path), PackedStringArray(["vide", "soun", "tmcd"]))
	DirAccess.remove_absolute(path)


static func test_unreadable_file_has_no_tracks(t: TestCase) -> void:
	t.assert_eq(NativeVideoBackend.mp4_track_handlers("C:/does/not/exist.mp4").size(), 0)


static func test_only_video_and_sound_are_safe(t: TestCase) -> void:
	t.assert_true(NativeVideoBackend.tracks_are_safe(PackedStringArray(["vide", "soun"])))
	t.assert_true(NativeVideoBackend.tracks_are_safe(PackedStringArray(["vide"])), "silent video")
	t.assert_false(NativeVideoBackend.tracks_are_safe(PackedStringArray(["vide", "soun", "tmcd"])), "timecode track")
	t.assert_false(NativeVideoBackend.tracks_are_safe(PackedStringArray(["soun"])), "no video")
	t.assert_false(NativeVideoBackend.tracks_are_safe(PackedStringArray()), "unreadable")


static func test_native_skips_urls_and_other_containers(t: TestCase) -> void:
	t.assert_false(NativeVideoBackend.can_play("http://host/video.mp4"))
	t.assert_false(NativeVideoBackend.can_play("C:/videos/clip.mkv"))


static func test_decoder_setting_round_trip(t: TestCase) -> void:
	var s := PlayerSettings.new(SETTINGS)
	t.assert_eq(s.video_decoder, "gozen", "FFmpeg by default")
	s.video_decoder = "native"
	var back := PlayerSettings.new(SETTINGS)
	back.load_from_disk()
	t.assert_eq(back.video_decoder, "native", "saved")
	s.video_decoder = "nonsense"
	t.assert_eq(s.video_decoder, "gozen", "unknown key falls back")
	for key in PlayerSettings.VIDEO_DECODERS:
		t.assert_true(VideoBridge.BACKENDS.has(key), "%s has a backend" % key)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


static func test_renderer_choices(t: TestCase) -> void:
	var project_default := String(ProjectSettings.get_setting("rendering/rendering_device/driver.windows"))
	t.assert_true(project_default in RendererSetting.DRIVERS, "project default is a choice")
	t.assert_eq(RendererSetting.DRIVERS[0], "d3d12", "D3D12 listed first (the default)")
	t.assert_eq(RendererSetting.choose("opengl3"), ERR_INVALID_PARAMETER, "unknown driver refused")
