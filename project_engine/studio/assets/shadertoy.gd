class_name StudioShadertoy
extends RefCounted

## The shelf's Shadertoy tab (TODO 17), apart from its drawing: the shaders
## you've collected from shadertoy.com (ShadertoyLibrary, shared with the
## authoring addon's dock; the Chrome extension in tools/shadertoy_extension
## sends them to Studio's ShadertoyReceiver) made into a layer or an effect
## (make), what pasted text is (paste), the site's search and a link that
## has the extension send a shader by itself (search_url, send_url), and
## the tab's filter (matches). Pure: tests drive it headless.
##
## A shader made into a layer or effect is a .gdshader in the first library
## folder's shaders/ (ShadertoyShader.to_gdshader / to_effect_gdshader), so
## it's then one of your shaders like any other: on the Layers or Effects
## tab too, and copied into a piece that uses it (StudioBundle).

const INCLUDE_DIR := "res://player/visualizer"
## The page's address ends in this for the extension to send the shader
## without a click (content.js).
const SEND_HASH := "#vj-send"
const EFFECT_SUFFIX := "_effect"


## The .gdshader for the Shadertoy asset `st_asset` (the shelf's card) as a
## layer, or an effect, in `library_dir`/shaders/, written unless it's
## there already (it may have been edited since). {ok, asset (the layer or
## effect asset as the library lists it, with the card's picture), path,
## notes (ShadertoyShader.analyze for it)}, or {ok: false, error}.
static func make(st_asset: Dictionary, as_effect: bool, library_dir: String) -> Dictionary:
	var st := ShadertoyShader.parse(FileAccess.get_file_as_string(st_asset.path))
	if st.is_empty():
		return {"ok": false, "error": "%s isn't a Shadertoy shader" % String(st_asset.path).get_file()}
	var notes := ShadertoyShader.analyze(st, as_effect)
	if not notes.ok:
		return {"ok": false, "error": "it won't run: " + "; ".join(notes.errors)}
	var dir := library_dir.path_join("shaders")
	var path := dir.path_join(ShadertoyShader.file_stem(st) + (EFFECT_SUFFIX if as_effect else "") + ".gdshader")
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return {"ok": false, "error": "can't write %s" % path}
		f.store_string(ShadertoyShader.to_effect_gdshader(st, INCLUDE_DIR) if as_effect
				else ShadertoyShader.to_gdshader(st, INCLUDE_DIR))
		f.close()
	var type := "effect" if as_effect else "layer"
	var asset := {"id": "%s:%s" % [type, path], "type": type, "kind": type,
			"label": VisualizerShaders.title_of(FileAccess.get_file_as_string(path), path), "path": path,
			"source": "user", "in_piece": false, "scale": StudioAssetLibrary.SCREEN_SCALE,
			"picture": st_asset.get("picture", "")}
	return {"ok": true, "asset": asset, "path": path, "notes": notes}


## What pasted `text` is: {kind: "link", id} for a link to a shader's page
## (open send_url(id) for the extension to send it), {kind: "added",
## shader} for a shader's JSON or code with a mainImage (now in `lib`), or
## {kind: "none"}.
static func paste(text: String, lib: ShadertoyLibrary) -> Dictionary:
	var id := ShadertoyShader.id_from_link(text)
	if id != "":
		return {"kind": "link", "id": id}
	var st := {}
	var data = ShadertoyShader.read_json(text)
	if data != null:
		st = lib.add(data)
	elif text.contains("mainImage"):
		st = lib.add(ShadertoyShader.from_code(text))
	return {"kind": "added", "shader": st} if not st.is_empty() else {"kind": "none"}


## The site's search for `query` (its newest shaders for "").
static func search_url(query: String) -> String:
	query = query.strip_edges()
	if query == "":
		return ShadertoyShader.SITE + "/browse"
	return "%s/results?query=%s" % [ShadertoyShader.SITE, query.uri_encode()]


## A shader's page, which the extension sends to Studio as soon as it's
## open.
static func send_url(id: String) -> String:
	return ShadertoyShader.view_url(id) + SEND_HASH


## Whether a Shadertoy asset matches the tab's filter: every word of it in
## its name, author or tags.
static func matches(asset: Dictionary, query: String) -> bool:
	var text := " ".join([asset.label, asset.get("author", "")] + Array(asset.get("tags", []))).to_lower()
	for word in query.to_lower().split(" ", false):
		if not text.contains(word):
			return false
	return true
