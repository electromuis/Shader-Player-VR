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
##
## With a `generator` (a layer shader's material) it's a generator instead:
## it renders that layer shader and mixes it into the picture (the player's
## generator effect), and `material` is unused. Its own VJEffect children
## shape the generator's picture first (an Oval mask, Key black, a Blur)
## before it's mixed in; they export as its `generator.effects`. Normal
## blend lays it over the picture (where it's see-through, the picture
## shows). Animate `<screen>/<effect>:generator:shader_parameter/<p>` for its
## layer shader's params (an `effect<N>` track) and its children as usual
## (`effect<N>.effect<M>`). The preview renders it at 960×540 times
## `generator_resolution`, at silence (no audio in the editor).

const _EffectChain := preload("res://addons/vj_editor/builtin_prefabs/effect_chain.gd")
const _EffectBlend := preload("res://addons/vj_editor/builtin_prefabs/effect_blend.gd")
const GENERATOR_SIZE := Vector2i(960, 540)

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

@export_group("Generator")
## A layer shader (a canvas_item .gdshader such as
## addons/vj_editor/visualizer/shaders/, or your own written the same way)
## makes this a generator: see the top. Its hinted uniforms export as the
## generator's params.
@export var generator: ShaderMaterial:
	set(value):
		generator = value
		update_configuration_warnings()

## The generator's render size, as a share of the picture's (the player's
## `generator.resolution`).
@export_range(0.1, 2.0, 0.05) var generator_resolution: float = 1.0

# The generator's preview: its layer shader in a SubViewport, then its own
# effects (an effect_chain.gd); internal, never saved.
var _gen_viewport: SubViewport
var _gen_material: ShaderMaterial
var _gen_chain: Node
var _gen_out: Texture2D


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var parent := get_parent()
	if parent != null and not parent.has_method("effect_nodes"):
		out.append("A VJ effect only does something as a direct child of a screen or layer (or of a generator effect).")
	elif parent != null and parent.get_script() == get_script() and not parent.is_generator():
		out.append("Only a generator effect (one with a generator) takes effects of its own.")
	elif parent != null and parent.get_script() == get_script() and is_generator():
		out.append("A generator's own effects can't be generators: this one is skipped.")
	if not is_generator() and (material == null or material.shader == null):
		out.append("Set a ShaderMaterial with an effect shader (addons/vj_editor/visualizer/effects/), or a generator's layer shader.")
	return out


## Whether this effect takes part (the preview and the export skip it if not).
func is_active() -> bool:
	return enabled and (is_generator() or (material != null and material.shader != null))


## Whether it's a generator: it has a layer shader in `generator`.
func is_generator() -> bool:
	return generator != null and generator.shader != null


## A generator's own effects that take part, in order (never generators).
func effect_nodes() -> Array[Node]:
	var out: Array[Node] = []
	if not is_generator():
		return out
	for c in get_children():
		if c.get_script() == get_script() and c.is_active() and not c.is_generator():
			out.append(c)
	return out


## effect_nodes()' materials and [blend mode, amount] (effect_chain.gd).
func effect_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for e in effect_nodes():
		out.append(e.material)
	return out


func effect_mixing() -> Array:
	var out: Array = []
	for e in effect_nodes():
		out.append([maxi(_EffectBlend.MODES.find(e.blend), 0), e.amount()])
	return out


## The generator's picture for the preview (null when it isn't one); kept
## up to date by _process.
func generator_texture() -> Texture2D:
	return _gen_out if is_generator() else null


func _process(_delta: float) -> void:
	if not is_generator():
		if _gen_viewport != null:
			_gen_viewport.queue_free()
			_gen_chain.queue_free()
			_gen_viewport = null
			_gen_chain = null
			_gen_out = null
		return
	var size := Vector2i((Vector2(GENERATOR_SIZE) * clampf(generator_resolution, 0.1, 2.0)).round())
	if _gen_viewport == null:
		_gen_viewport = SubViewport.new()
		_gen_viewport.transparent_bg = true
		_gen_viewport.disable_3d = true
		_gen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gen_material = ShaderMaterial.new()
		rect.material = _gen_material
		_gen_viewport.add_child(rect)
		add_child(_gen_viewport, false, Node.INTERNAL_MODE_BACK)
		_gen_chain = _EffectChain.new()
		add_child(_gen_chain, false, Node.INTERNAL_MODE_BACK)
		_gen_out = null
	if _gen_material.shader != generator.shader:
		_gen_material.shader = generator.shader
		_gen_chain.mixing = []
		_gen_out = null
	_gen_viewport.size = size
	for u in generator.shader.get_shader_uniform_list():
		var v = generator.get_shader_parameter(u.name)
		if v != null:
			_gen_material.set_shader_parameter(u.name, v)
	_gen_material.set_shader_parameter("iResolution", Vector3(size.x, size.y, 1.0))
	var mats := effect_materials()
	_gen_chain.mixing = effect_mixing()
	if _gen_out == null or not _gen_chain.is_current(mats):
		_gen_out = _gen_chain.build(_gen_viewport.get_texture(), mats, size, float(size.x) / size.y)
	else:
		_gen_chain.sync(size, float(size.x) / size.y)


## How much of it shows now: its mix while it's on, else 0.
func amount() -> float:
	return clampf(mix, 0.0, 1.0) if on else 0.0
