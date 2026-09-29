@tool
@icon("res://addons/vj_editor/builtin_prefabs/effect_icon.svg")
class_name VJEffect
extends Node

## One effect pass on the screen or layer it's a child of. Effects run in
## child order over the picture (drag to reorder); each is a ShaderMaterial
## with one of addons/vj_editor/visualizer/effects/ (the player's built-in
## Key black, Oval mask, Edge blur, Blur, Glow, Crop, Rounded corners) or your own
## effect shader (include visualizer/effect_prelude.gdshaderinc).
##
## The parent exports its effects as `config.effects`, in order. Animate
## `<screen>/<effect>:material:shader_parameter/<p>`; the exporter turns it
## into a `<screen id>.effect<N>` track, N being this effect's place among
## the parent's enabled ones at export time.
##
## Right-click a screen or layer > Add VJ effect adds one with a built-in
## shader already set.

## The effect shader and its params.
@export var material: ShaderMaterial:
	set(value):
		material = value
		update_configuration_warnings()

## Off: skipped in the preview and in the player for the whole piece (it
## exports with `"enabled": false`, so it's kept, and doesn't count in the
## `effect<N>` numbering). Not animatable: animate `on` instead.
@export var enabled: bool = true

## How much of it shows, 0..1 (the player's effect `mix`; animatable, to
## fade it in and out).
@export_range(0.0, 1.0, 0.01) var mix: float = 1.0

## How its picture goes over what it works on (the player's effect
## `blend`): normal replaces it, the others blend like an image editor's
## layers. Animatable (it holds from key to key).
@export_enum("normal", "add", "subtract", "multiply", "screen", "overlay", "difference", "lighten", "darken")
var blend: String = "normal"

## On at this moment. Animate it to switch the effect on and off over time:
## it exports as the effect's on / off keys (an `enabled` track), each
## fading over `fade`. Off with no keys: off from the start. The effect
## keeps its place in the numbering either way.
@export var on: bool = true

## Seconds each on / off key fades over (0: it switches at once). The
## preview switches at once.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var fade: float = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var parent := get_parent()
	if parent != null and not parent.has_method("effect_nodes"):
		out.append("A VJ effect only does something as a direct child of a screen or layer.")
	if material == null or material.shader == null:
		out.append("Set a ShaderMaterial with an effect shader (addons/vj_editor/visualizer/effects/).")
	return out


## Whether this effect takes part (the preview and the export skip it if not).
func is_active() -> bool:
	return enabled and material != null and material.shader != null


## How much of it shows now: its mix while it's on, else 0.
func amount() -> float:
	return clampf(mix, 0.0, 1.0) if on else 0.0
