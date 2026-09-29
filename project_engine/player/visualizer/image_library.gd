class_name ImageLibrary
extends RefCounted

## Image files for shaders' texture params (VisualizerShaders: a
## `// @iChannelN image` channel, or a `uniform sampler2D` of a .gdshader).
## A param's value is the file's path ("" = none); value() turns it into
## the texture the uniform takes. Images are discovered in `images/` in
## AppPaths.save_dir() and an `images/` folder next to the executable, like
## skyboxes; a preset or script may name any other path too.

const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]

static var _cache := {}  # path -> Texture2D (null: can't be read)


## Folders scanned for images. Created lazily by the user; missing folders
## are skipped.
static func search_dirs() -> Array[String]:
	var out: Array[String] = [ProjectSettings.globalize_path(AppPaths.save_path("images"))]
	out.append(AppPaths.exe_dir().path_join("images"))
	return out


## [{key, label}] of the discovered images, for pickers.
static func list_options(dirs: Array[String] = search_dirs()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir in dirs:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			if String(f).get_extension().to_lower() in EXTENSIONS:
				out.append({"key": dir.path_join(f), "label": String(f).get_basename()})
	return out


## The name a picker shows for `path`.
static func label_of(path: String) -> String:
	return path.get_file().get_basename()


## The texture at `path` (with mipmaps), loaded once; null for "" or a file
## that can't be read.
static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("ImageLibrary: can't load image %s" % path)
	else:
		tex.set_meta(&"image_path", path)
	_cache[path] = tex
	return tex


## What a shader uniform takes for a param value: a path (a String) becomes
## its texture (null for ""); a colour kept as [r, g, b(, a)] (the Camera
## tab's, in a preset) a Vector3 / Vector4; anything else is passed through.
static func value(v: Variant) -> Variant:
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		return texture(String(v))
	if typeof(v) == TYPE_ARRAY and v.size() in [3, 4]:
		return Vector3(float(v[0]), float(v[1]), float(v[2])) if v.size() == 3 \
				else Vector4(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return v


## `v` again after clear(): a texture from here read from its file anew;
## anything else as it is.
static func reloaded(v: Variant) -> Variant:
	if v is Texture2D and (v as Texture2D).has_meta(&"image_path"):
		return texture(String((v as Texture2D).get_meta(&"image_path")))
	return v


## Forget loaded images, so edited files are read again (VisualizerShaders.
## reload_all).
static func clear() -> void:
	_cache.clear()
