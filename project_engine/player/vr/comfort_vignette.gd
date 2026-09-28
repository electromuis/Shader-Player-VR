class_name ComfortVignette
extends MeshInstance3D

## A soft dark ring at the edge of the headset view while the viewer is
## carried along (a script's ride, Studio's flight): narrowing the view a
## little during motion you don't make yourself is easier on most stomachs.
## A child of the XR camera, drawn over everything; it eases in and out
## over about a quarter second. The owner calls update() every frame with
## how strong it should be (0..1).

## How dark the edge gets at full strength.
const MAX_ALPHA := 0.65
const EASE_PER_SECOND := 4.0

const _SHADER := """shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix;
uniform float strength = 0.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = strength * smoothstep(0.55, 1.1, r);
}
"""

var level := 0.0
var _mat: ShaderMaterial


func _init() -> void:
	name = "ComfortVignette"
	_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _SHADER
	_mat.shader = shader
	_mat.render_priority = FloatingPanel.UI_RENDER_PRIORITY + 2
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	mesh = quad
	material_override = _mat
	position = Vector3(0, 0, -0.35)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Ease toward `target` (0..1).
func update(target: float, delta: float) -> void:
	level = move_toward(level, clampf(target, 0.0, 1.0), delta * EASE_PER_SECOND)
	visible = level > 0.01
	_mat.set_shader_parameter("strength", level * MAX_ALPHA)
