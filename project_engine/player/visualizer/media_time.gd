class_name MediaTime
extends RefCounted

## Shader time: what TIME reads in every shader the player runs (the global
## shader uniform `vj_time`, see media_time.gdshaderinc) and a camera
## effect's iTime. The Stage sets it every frame from the playhead, so
## shaders stop while paused and jump with seeks. A shader with a
## `// @free_time` line (VisualizerShaders.is_free_time) keeps Godot's own
## TIME, seconds since the app started.

const PARAM := &"vj_time"

## The seconds last set.
static var seconds := 0.0


static func set_seconds(t: float) -> void:
	seconds = t
	RenderingServer.global_shader_parameter_set(PARAM, t)


## Seconds since the app started, as Godot's TIME counts them.
static func engine_seconds() -> float:
	return Time.get_ticks_usec() / 1000000.0
