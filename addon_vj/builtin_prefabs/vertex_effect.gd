@tool
@icon("res://addons/vj_editor/builtin_prefabs/effect_icon.svg")
class_name VJVertexEffect
extends Node

## One vertex effect on the screen or layer it's a child of: it moves the
## surface rather than the picture. Vertex effects run in child order (drag
## to reorder) in the flat screen's frame, then the screen's surface bends
## the result, so a ripple follows a dome. `effect` is one of
## addons/vj_editor/visualizer/vertex/ (the player's built-in Ripple, Twist,
## Bulge) or your own `.gdshaderinc` written the same way (see the player's
## ScreenGeometry).
##
## The snippet's hinted uniforms show below as `params/<name>`; animate
## `<screen>/<vertex effect>:params/<name>` and the exporter turns it into a
## `<screen id>.vertex<N>` track, N being this effect's place among the
## parent's enabled ones. The parent exports them as `config.vertex_effects`.
## Audio-driven ones (the `audio` param) stay still in the editor, which has
## no audio.
##
## Right-click a screen or layer > Add VJ vertex effect adds one.

const _Code := preload("res://addons/vj_editor/builtin_prefabs/screen_shader_code.gd")
const BUILTIN_DIR := "res://addons/vj_editor/visualizer/vertex/"
const _PARAMS := "params/"

## The vertex effect's `.gdshaderinc`.
@export_file("*.gdshaderinc") var effect: String = BUILTIN_DIR + "ripple.gdshaderinc":
	set(value):
		effect = value
		_reload()

## Off: skipped in the preview and left out of the export. Not animatable:
## animate `on` instead.
@export var enabled: bool = true

## How far it moves the surface, 0..1 (the player's vertex effect `mix`;
## animatable).
@export_range(0.0, 1.0, 0.01) var mix: float = 1.0

## On at this moment. Animate it to switch the effect on and off over time
## (its on / off keys, each fading over `fade`); off with no keys: off from
## the start. It keeps its place in the `vertex<N>` numbering either way.
@export var on: bool = true

## Seconds each on / off key fades over (0: at once; the preview switches
## at once).
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var fade: float = 0.0

## The values set here; the rest keep the snippet's defaults. Edited as
## `params/<name>` in the inspector.
@export_storage var params: Dictionary = {}

var _code: String = ""
var _specs: Array = []


func _init() -> void:
	_reload()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var parent := get_parent()
	if parent != null and not parent.has_method("vertex_effect_nodes"):
		out.append("A VJ vertex effect only does something as a direct child of a screen or layer.")
	if not _code.contains("deform("):
		out.append("Pick a vertex effect (.gdshaderinc with a deform() function, e.g. addons/vj_editor/visualizer/vertex/).")
	return out


## Whether this effect takes part (the preview and the export skip it if not).
func is_active() -> bool:
	return enabled and _code.contains("deform(")


## How far it moves the surface now: its mix while it's on, else 0.
func amount() -> float:
	return clampf(mix, 0.0, 1.0) if on else 0.0


## The snippet's source ("" if unreadable).
func code() -> String:
	return _code


## Every hinted param with its value (defaults for the ones not set).
func param_values() -> Dictionary:
	return _Code.full_params(_specs, params)


func _reload() -> void:
	_code = ""
	if effect != "" and FileAccess.file_exists(effect):
		_code = FileAccess.get_file_as_string(effect)
	_specs = _Code.uniform_params(_code)
	notify_property_list_changed()
	update_configuration_warnings()


func _get_property_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec in _specs:
		var p := {"name": _PARAMS + spec.name, "usage": PROPERTY_USAGE_EDITOR}
		match spec.type:
			"bool":
				p.type = TYPE_BOOL
			"int":
				p.type = TYPE_INT
				p.hint = PROPERTY_HINT_RANGE
				p.hint_string = "%d,%d,%d" % [spec.min, spec.max, maxi(int(spec.step), 1)]
			_:
				p.type = TYPE_FLOAT
				p.hint = PROPERTY_HINT_RANGE
				p.hint_string = "%s,%s,%s" % [spec.min, spec.max, spec.step]
		out.append(p)
	return out


func _get(property: StringName) -> Variant:
	var s := String(property)
	if not s.begins_with(_PARAMS):
		return null
	var name := s.substr(_PARAMS.length())
	for spec in _specs:
		if spec.name == name:
			return params.get(name, spec.default)
	return null


func _set(property: StringName, value: Variant) -> bool:
	var s := String(property)
	if not s.begins_with(_PARAMS):
		return false
	params[s.substr(_PARAMS.length())] = value
	return true


func _property_can_revert(property: StringName) -> bool:
	return String(property).begins_with(_PARAMS) and params.has(String(property).substr(_PARAMS.length()))


func _property_get_revert(property: StringName) -> Variant:
	var name := String(property).substr(_PARAMS.length())
	for spec in _specs:
		if spec.name == name:
			return spec.default
	return null
