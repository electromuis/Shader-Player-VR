class_name StudioFloorGrid
extends MeshInstance3D

## 1 m lines on the floor while editing, to judge distance (the menu's
## Floor grid setting). A plane under the camera; the lines come from world
## coordinates, so they stay put as the plane follows you, and fade out
## with distance and where they'd crowd into moiré.

## The plane's size; the lines are gone (FADE_END) well before its edge.
const SIZE := 60.0
## Just above the floor, clear of the stage's own floor plane.
const LIFT := 0.002

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 line_color : source_color = vec4(0.85, 0.9, 1.0, 0.3);
// Half a line's width in metres; lines never get thinner than a pixel.
uniform float half_width = 0.008;
uniform float fade_start = 6.0;
uniform float fade_end = 24.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 px = fwidth(p);
	// Distance to the nearest 1 m line, per axis.
	vec2 to_line = abs(fract(p - 0.5) - 0.5);
	vec2 hw = max(vec2(half_width), px * 0.5);
	vec2 cover = 1.0 - smoothstep(hw - px, hw + px, to_line);
	float line = max(cover.x, cover.y);
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(p, CAMERA_POSITION_WORLD.xz));
	// Lines closer together than a few pixels shimmer: let them go.
	fade *= 1.0 - smoothstep(0.08, 0.25, max(px.x, px.y));
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a * line * fade;
}
"""


func _init() -> void:
	name = "FloorGrid"
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	mesh = plane
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	global_position = Vector3(roundf(at.x), LIFT, roundf(at.z))
