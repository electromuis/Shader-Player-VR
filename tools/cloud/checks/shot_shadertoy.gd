extends SceneTree

## Converts Shadertoy JSONs (the site's format; a folder of them in
## $ST_SAMPLES, one shader per file) with ShadertoyShader and
## renders each one through the player's includes (1 s after it's set) to
## $OUT_DIR/st_<id>.png (the shader
## next to it as st_<id>.gdshader). Prints each one's analysis; Godot's own
## "SHADER ERROR" lines follow a shader that doesn't compile. Rendered only.

const SIZE := Vector2i(480, 270)


func _init() -> void:
	var dir := OS.get_environment("ST_SAMPLES")
	var out_dir := OS.get_environment("OUT_DIR")
	if dir == "" or out_dir == "":
		print("Set ST_SAMPLES and OUT_DIR.")
		quit(1)
		return
	await process_frame
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var rect := ColorRect.new()
	rect.size = SIZE
	rect.color = Color(1, 0, 1)
	vp.add_child(rect)
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".json"))
	files.sort()
	for f in files:
		var st := ShadertoyShader.parse(FileAccess.get_file_as_string(dir.path_join(f)))
		if st.is_empty():
			print("%s: not a shader" % f)
			continue
		var a := ShadertoyShader.analyze(st)
		print("=== %s \"%s\": %s%s%s%s" % [st.id, st.name, "ok" if a.ok else "won't run",
				"; errors: " + "; ".join(a.errors) if not a.errors.is_empty() else "",
				"; edits: " + "; ".join(a.edits) if not a.edits.is_empty() else "",
				"; warnings: " + "; ".join(a.warnings) if not a.warnings.is_empty() else ""])
		var shader := Shader.new()
		shader.code = ShadertoyShader.to_gdshader(st, "res://player/visualizer")
		var code_file := FileAccess.open(out_dir.path_join("st_%s.gdshader" % st.id), FileAccess.WRITE)
		code_file.store_string(shader.code)
		code_file.close()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("iResolution", Vector3(SIZE.x, SIZE.y, 1))
		rect.material = mat
		await create_timer(1.0).timeout
		var img := vp.get_texture().get_image()
		var c := img.get_pixel(SIZE.x / 2, SIZE.y / 2)
		print("    centre pixel %s" % c)
		img.save_png(out_dir.path_join("st_%s.png" % st.id))
	quit(0)
