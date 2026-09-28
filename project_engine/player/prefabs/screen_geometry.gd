class_name ScreenGeometry
extends RefCounted

## Where a screen's picture sits in space: its surface (Pillow, Dome, ...)
## and the vertex effects (Ripple, Twist, ...) that move it, and the
## display shader built from them.
##
## Both are `.gdshaderinc` snippets with hinted uniforms (sliders, like
## effects; see VisualizerShaders.parse_hints). They work in metres, in the
## flat screen's own frame: x right, y up, z toward the viewer, the screen's
## centre at the origin. `half_m` is the unpadded picture's half size.
##   vertex effect — `vec3 deform(vec3 p, vec2 uv, vec2 half_m)`: moves a
##                   point of the flat screen; z is "off the surface". Any
##                   number, in order. Audio via vfx_react / vfx_band.
##   surface       — `vec3 surface(vec3 p, vec2 uv, vec2 half_m)`: puts the
##                   (deformed) flat point on the surface, p.z along its
##                   normal. One per screen, after the vertex effects.
## Both also see `placement`, `viewer_distance` and TIME (see
## screen_display.gdshaderinc). build_shader pastes them in after that
## include, each with its declared names prefixed (vfx<N>_ / srf_) so two
## stages can both have an `amount`, and a vertex() calling them in order
## (screen_shader_code.gd, shared with the authoring addon).
##
## Placement (a surface's `// @placements` lists the ones it supports):
##   fixed    — at the screen, like any object
##   around   — the viewer's eye at the surface's centre (viewer_distance
##              from the screen, which Screen keeps up to date)
##   infinity — centred on the camera wherever it goes, taking only the
##              screen's rotation, and drawn behind every other transparent
##              thing: 180° / 360° video, shader skyboxes
## `// @unused <placement> <names>` names the params (and the Camera tab's
## size / distance / height) that placement ignores; `// @hint <text>` is
## shown under the picker; `// @title <name>` names it in the picker.
## The built-ins are every snippet in BUILTIN_ROOT's surfaces/ and vertex/
## folders (builtins()).
##
## Pointer hits use surface_point, the GDScript twin of the built-in
## surfaces; other surfaces count as flat, and vertex effects are ignored.

const PILLOW := "res://player/visualizer/surfaces/pillow.gdshaderinc"
const DOME := "res://player/visualizer/surfaces/dome.gdshaderinc"
const RIPPLE := "res://player/visualizer/vertex/ripple.gdshaderinc"
const TWIST := "res://player/visualizer/vertex/twist.gdshaderinc"
const BULGE := "res://player/visualizer/vertex/bulge.gdshaderinc"
## Script names for the built-ins (`"surface": {"shader": "dome"}`).
const BUILTIN_NAMES := {"pillow": PILLOW, "dome": DOME, "ripple": RIPPLE, "twist": TWIST, "bulge": BULGE}

const Code := preload("res://player/prefabs/screen_shader_code.gd")

enum Placement { FIXED, AROUND, INFINITY }
const PLACEMENTS := Code.PLACEMENTS
const PLACEMENT_LABELS := {"fixed": "Fixed", "around": "Around viewer", "infinity": "At infinity"}
const INFINITY_RADIUS := Code.INFINITY_RADIUS
const DISPLAY_INCLUDE := "res://player/prefabs/screen_display.gdshaderinc"
const EXTENSION := "gdshaderinc"
const SURFACE_PREFIX := Code.SURFACE_PREFIX
## Folders under the shaders folders (VisualizerShaders.search_dirs).
const SURFACES_DIR := "surfaces"
const VERTEX_DIR := "vertex"

static var _hints_cache := {}
static var _shader_cache := {}  # generated code -> Shader
static var _placements_re := RegEx.create_from_string("@placements\\s+([\\w ]+)")
static var _unused_re := RegEx.create_from_string("@unused\\s+(\\w+)\\s+([\\w ]+)")
static var _hint_re := RegEx.create_from_string("@hint\\s+([^\\n]+)")


static func default_surface() -> Dictionary:
	return {"shader": PILLOW, "params": {}, "placement": "fixed"}


## A clean {shader, params, placement} from `d` (a preset's or a script's),
## the placement one the surface supports.
static func normalized_surface(d: Variant) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return default_surface()
	var key := resolve_builtin(String(d.get("shader", "")))
	if key == "":
		key = PILLOW
	var params = d.get("params", {})
	var placement := String(d.get("placement", ""))
	if not placement in placements_for(key):
		placement = default_placement(key)
	return {"shader": key,
			"params": params.duplicate() if typeof(params) == TYPE_DICTIONARY else {},
			"placement": placement}


## A built-in's key for its script name ("dome"), else `key` itself.
static func resolve_builtin(key: String) -> String:
	return BUILTIN_NAMES.get(key.to_lower(), key)


static func is_builtin_name(key: String) -> bool:
	return BUILTIN_NAMES.has(key.to_lower())


## Folders scanned for user surfaces (`kind` SURFACES_DIR) or vertex effects
## (VERTEX_DIR): that subfolder of each shaders folder.
static func search_dirs(kind: String) -> Array[String]:
	var out: Array[String] = []
	for d in [ProjectSettings.globalize_path(AppPaths.save_path("shaders")), VisualizerShaders.shaders_dir()]:
		out.append(String(d).path_join(kind))
	return out


## [{key, label}] for the built-in surfaces (`kind` SURFACES_DIR) or vertex
## effects (VERTEX_DIR).
static func builtins(kind: String) -> Array[Dictionary]:
	return VisualizerShaders.builtin_options(VisualizerShaders.BUILTIN_ROOT.path_join(kind), EXTENSION)


## [{key, label}] for a picker: built-ins, then `.gdshaderinc` files found
## in search_dirs(kind).
static func list_options(kind: String, dirs: Array[String] = search_dirs(kind)) -> Array[Dictionary]:
	_hints_cache.clear()
	var out: Array[Dictionary] = []
	var overrides := {}
	for b in builtins(kind):
		out.append(b.duplicate())
		var o := VisualizerShaders.override_path(b.key)
		if o != "":
			overrides[o] = true
	for dir in dirs:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			var path := dir.path_join(f)
			if String(f).get_extension().to_lower() == EXTENSION and not overrides.has(path):
				out.append({"key": path, "label": VisualizerShaders.title_of(FileAccess.get_file_as_string(path), path)})
	return out


## Source of the snippet at `key`, "" if unreadable. A built-in's file in
## the shaders folder (VisualizerShaders.override_path) wins; user files are
## read fresh each time.
static func read_code(key: String) -> String:
	if key == "":
		return ""
	var path := VisualizerShaders.override_path(key)
	if path == "" and key.begins_with("res://") and not VisualizerShaders.builtins_fresh():
		var inc := load(key) as ShaderInclude
		return inc.code if inc != null else ""
	if path == "":
		path = key
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


## {params (screen_shader_code.gd's uniform_params), placements: [names],
## unused: {placement: [names]}, hint: String, audio: bool} for `key`
## (cached until list_options).
static func hints_for(key: String) -> Dictionary:
	if _hints_cache.has(key):
		return _hints_cache[key]
	var code := read_code(key)
	var out := {
		"params": Code.uniform_params(code),
		"placements": ["fixed"],
		"unused": {},
		"hint": "",
		"audio": code.contains("vfx_react") or code.contains("vfx_band") or code.contains("vfx_audio"),
	}
	var m := _placements_re.search(code)
	if m != null:
		var names: Array = []
		for n in m.get_string(1).split(" ", false):
			if n in PLACEMENTS:
				names.append(n)
		if not names.is_empty():
			out.placements = names
	for u in _unused_re.search_all(code):
		out.unused[u.get_string(1)] = Array(u.get_string(2).split(" ", false))
	m = _hint_re.search(code)
	if m != null:
		out.hint = m.get_string(1).strip_edges()
	_hints_cache[key] = out
	return out


static func placements_for(key: String) -> Array:
	return hints_for(key).placements


## A fresh surface's placement: around the viewer for the Dome (a dome is
## for being inside), else its first.
static func default_placement(key: String) -> String:
	var names := placements_for(key)
	return "around" if key == DOME and "around" in names else String(names[0])


static func placement_index(name: String) -> int:
	return maxi(PLACEMENTS.find(name), 0)


## `params` with each of `key`'s hinted params filled in (defaults for the
## missing ones).
static func full_params(key: String, params: Dictionary) -> Dictionary:
	return Code.full_params(hints_for(key).params, params)


static func vertex_prefix(index: int) -> String:
	return Code.vertex_prefix(index)


## Forget parsed hints and built display shaders (VisualizerShaders.reload_all).
static func clear_caches() -> void:
	_hints_cache.clear()
	_shader_cache.clear()


## The display shader for these vertex effects (keys, in order; unreadable
## ones skipped) and surface. Shared between screens with the same code.
static func build_shader(vertex_keys: Array, surface_key: String) -> Shader:
	var sources: Array = []
	for k in vertex_keys:
		sources.append(read_code(String(k)))
	var code := Code.build(DISPLAY_INCLUDE, sources, read_code(surface_key))
	if VisualizerShaders.builtins_fresh():
		code = VisualizerShaders.expand_includes(code, DISPLAY_INCLUDE.get_base_dir())
	if not _shader_cache.has(code):
		var shader := Shader.new()
		shader.code = code
		_shader_cache[code] = shader
	return _shader_cache[code]


## Where surface `key` puts flat point `p` (metres, screen frame), with
## `half_m` the picture's half size: the GDScript twin of the built-in
## surfaces' shader code. Other surfaces count as flat.
static func surface_point(key: String, params: Dictionary, placement: int, p: Vector3,
		half_m: Vector2, viewer_distance: float) -> Vector3:
	var v := full_params(key, params)
	if key == PILLOW:
		var q := p
		var rx := _pillow_radius(float(v.arc_x), half_m.x, placement, viewer_distance)
		var ry := _pillow_radius(float(v.arc_y), half_m.y, placement, viewer_distance)
		if rx > 0.0:
			var a := p.x / rx
			q.x = (rx - p.z) * sin(a)
			q.z = rx - (rx - p.z) * cos(a)
		if ry > 0.0:
			var a := p.y / ry
			q.y = (ry - q.z) * sin(a)
			q.z = ry - (ry - q.z) * cos(a)
		return q
	if key == DOME:
		var half_lon := deg_to_rad(float(v.arc_x)) * 0.5
		if half_lon < 0.0001:
			return p
		var r := half_m.x / half_lon if placement == Placement.FIXED else viewer_distance
		var f := Vector2(p.x / half_m.x, p.y / half_m.y)
		var lon := f.x * half_lon
		var lat := f.y * half_lon * half_m.y / half_m.x if bool(v.auto_height) \
				else f.y * deg_to_rad(float(v.arc_y)) * 0.5
		lat = clampf(lat, -PI * 0.5, PI * 0.5)
		if bool(v.keep_row_width):
			lon /= maxf(cos(lat), 0.05)
		lon = clampf(lon, -PI, PI)
		var squeeze := lerpf(1.0, maxf(cos(lon), 0.0), float(v.straight_rows))
		lat = atan2(sin(lat) * squeeze, cos(lat))
		var dir := Vector3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon))
		return Vector3(0.0, 0.0, r) + dir * (r - p.z)
	return p


static func _pillow_radius(arc: float, half_len: float, placement: int, viewer_distance: float) -> float:
	if placement == Placement.AROUND:
		return viewer_distance
	return half_len / deg_to_rad(arc * 0.5) if arc > 0.01 else 0.0


## Whether the ray from `from` along `dir` hits a screen whose mesh (a
## quad `mesh_half` × 2 in mesh units, `picture_half` of it the unpadded
## picture) has transform `xform` and this surface. Walks a grid of the
## surface's triangles (vertex effects are ignored); never at infinity.
static func ray_hits(from: Vector3, dir: Vector3, xform: Transform3D, mesh_half: Vector2,
		picture_half: Vector2, surface: Dictionary, viewer_distance: float) -> bool:
	var placement := placement_index(String(surface.get("placement", "fixed")))
	if placement == Placement.INFINITY:
		return false
	var s := xform.basis.get_scale()
	if s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
		return false
	var half_m := picture_half * Vector2(s.x, s.y)
	var key := String(surface.get("shader", PILLOW))
	var params: Dictionary = surface.get("params", {})
	const NX := 32
	const NY := 18
	var pts: Array[Vector3] = []
	for j in NY + 1:
		for i in NX + 1:
			var local := Vector2(lerpf(-mesh_half.x, mesh_half.x, float(i) / NX),
					lerpf(-mesh_half.y, mesh_half.y, float(j) / NY))
			var p := surface_point(key, params, placement,
					Vector3(local.x * s.x, local.y * s.y, 0.0), half_m, viewer_distance)
			pts.append(xform * (p / s))
	for j in NY:
		for i in NX:
			var a := pts[j * (NX + 1) + i]
			var b := pts[j * (NX + 1) + i + 1]
			var c := pts[(j + 1) * (NX + 1) + i]
			var d := pts[(j + 1) * (NX + 1) + i + 1]
			if Geometry3D.ray_intersects_triangle(from, dir, a, b, c) != null \
					or Geometry3D.ray_intersects_triangle(from, dir, b, d, c) != null:
				return true
	return false
