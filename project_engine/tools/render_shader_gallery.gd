extends SceneTree

## Renders every shader in a folder to PNGs, for a quick look without the
## player: a still each, or with `--frames N` a numbered sequence each (in
## <out>/<name>/) for turning into a GIF. Layer shaders get a synthetic
## audio texture with a 120 bpm beat; effects get `--input` as their
## input_tex: an image, or a folder of numbered frames (a clip, one frame
## per rendered frame, looping). Needs a real renderer (not --headless); watch the output
## for SHADER ERROR (those render black).
##   godot --path project_engine --fixed-fps 20 --script res://tools/render_shader_gallery.gd -- \
##       --dir <shader folder> --out <png folder> [--input <image or frame folder>] [--time 3.0]
##       [--frames 1] [--fps 20] [--size 640x360]
## For sequences, pass the same rate as Godot's --fixed-fps and --fps, so
## shader TIME steps evenly however slow the frames are.

const BEAT_HZ := 2.0


func _init() -> void:
	_run.call_deferred()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


## 0..1, peaking on each beat and decaying after it.
func _beat(t: float) -> float:
	return exp(-fmod(t * BEAT_HZ, 1.0) * 5.0)


## 512×2 like the player's: row 0 a falling spectrum with a few peaks (the
## lows kicked by the beat), row 1 a waveform.
func _audio_image(t: float) -> Image:
	var img := Image.create(512, 2, false, Image.FORMAT_RF)
	var kick := _beat(t)
	for x in 512:
		var f := x / 512.0
		var spec := (0.6 + 0.4 * kick) * exp(-f * 3.0) + 0.35 * exp(-pow((f - 0.3) * 12.0, 2.0)) + 0.2 * exp(-pow((f - 0.6) * 15.0, 2.0))
		spec *= 0.75 + 0.25 * sin(x * 0.7 + t * 3.0)
		img.set_pixel(x, 0, Color(clampf(spec, 0.0, 1.0), 0, 0))
		img.set_pixel(x, 1, Color(0.5 + 0.3 * sin(f * 40.0 + t * 6.0) * sin(f * 7.0 - t), 0, 0))
	return img


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := _arg(args, "--dir", "")
	var out := _arg(args, "--out", "")
	var input_path := _arg(args, "--input", "")
	var at_time := float(_arg(args, "--time", "3.0"))
	var frames := int(_arg(args, "--frames", "1"))
	var fps := float(_arg(args, "--fps", "20"))
	var size_parts := _arg(args, "--size", "640x360").split("x")
	var size := Vector2i(int(size_parts[0]), int(size_parts[1]))
	DirAccess.make_dir_recursive_absolute(out)
	var clip: Array[Image] = []
	if DirAccess.dir_exists_absolute(input_path):
		var names := Array(DirAccess.get_files_at(input_path))
		names.sort()
		for n in names:
			clip.append(Image.load_from_file(input_path.path_join(n)))
	elif input_path != "":
		clip.append(Image.load_from_file(input_path))
	var input_tex: ImageTexture = ImageTexture.create_from_image(clip[0]) if not clip.is_empty() else null
	var audio := ImageTexture.create_from_image(_audio_image(0.0))
	var jobs: Array = []
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		var path := dir.path_join(f)
		var shader := VisualizerShaders.load_shader(path)
		if shader == null:
			continue
		var vp := SubViewport.new()
		vp.size = size
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var rect := ColorRect.new()
		rect.size = Vector2(size)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var effect := VisualizerShaders.is_effect_code(shader.code)
		if effect:
			mat.set_shader_parameter("input_tex", input_tex)
			mat.set_shader_parameter("display_aspect", float(size.x) / size.y)
		else:
			mat.set_shader_parameter("iResolution", Vector3(size.x, size.y, 1.0))
			mat.set_shader_parameter("iChannel0", audio)
		rect.material = mat
		vp.add_child(rect)
		root.add_child(vp)
		var name := String(f).get_basename()
		if frames > 1:
			DirAccess.make_dir_recursive_absolute(out.path_join(name))
		jobs.append({"name": name, "vp": vp, "mat": mat, "effect": effect})
	# TIME is global: step to about `at_time` first so shaders aren't caught at t = 0.
	for _i in int(at_time * fps):
		await process_frame
	for frame in frames:
		var t := at_time + frame / fps
		audio.update(_audio_image(t))
		if clip.size() > 1:
			input_tex.update(clip[frame % clip.size()])
		var kick := _beat(t)
		for j in jobs:
			if not j.effect:
				j.mat.set_shader_parameter("audio_level", 0.4 + 0.3 * kick)
				j.mat.set_shader_parameter("audio_bass", 0.3 + 0.6 * kick)
				j.mat.set_shader_parameter("audio_mid", 0.4)
				j.mat.set_shader_parameter("audio_high", 0.3 + 0.2 * sin(t * 5.0))
		await RenderingServer.frame_post_draw
		for j in jobs:
			var img: Image = j.vp.get_texture().get_image()
			if frames > 1:
				img.save_png(out.path_join(j.name).path_join("%04d.png" % frame))
			else:
				img.save_png(out.path_join(j.name + ".png"))
		if frames > 1 and frame % 10 == 0:
			print("frame ", frame, "/", frames)
	for j in jobs:
		print("saved ", j.name)
	quit(0)
