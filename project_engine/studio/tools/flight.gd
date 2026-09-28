class_name StudioFlight
extends Node

## Noclip flight in Studio's Edit mode, in the headset (the desktop flies
## with WASD / E / Q already). The left stick flies where you look, up and
## down included, straight through anything; how far you push sets the
## speed (squared: small pushes are slow and precise). The right stick
## turns (snap) and, pushed up or down, rises or sinks, unless a grab is on
## (then Studio uses it to push / pull the object). While you move, the
## stage's comfort vignette narrows the view a little (Studio passes it
## `motion`); the horizon never tilts.
##
## Reads the router's axes "studio_fly" (left stick) and
## "studio_right_stick"; moves the XR origin.

const MAX_SPEED := 4.0        # m/s at full push
const RISE_SPEED := 1.5       # m/s
const SNAP_DEGREES := 30.0
const SNAP_ON := 0.7
const SNAP_OFF := 0.3

var router: InputRouter
var rig: XRRig
## Set by Studio each frame: the right stick belongs to a grab now.
var right_stick_busy := false
var enabled := false

var _snap_armed := true
## How fast you're flying now (0..1 of full speed): Studio hands it to the
## stage's comfort vignette.
var motion := 0.0


func _process(delta: float) -> void:
	motion = 0.0
	if enabled and router != null and rig != null:
		motion = _fly(delta)


## Moves the rig; returns how fast (0..1 of full speed).
func _fly(delta: float) -> float:
	var origin: XROrigin3D = rig
	var cam := rig.xr_camera
	var amount := 0.0
	# Left trigger + left stick scrubs instead (Studio's binding).
	var stick := router.axis("studio_fly")
	if stick != Vector2.ZERO and router.axis("studio_scrub") == Vector2.ZERO:
		var push := minf(stick.length(), 1.0)
		var dir := cam.global_transform.basis * Vector3(stick.x, 0.0, -stick.y).normalized()
		# In the miniature (a bigger world scale) you fly as fast as you see.
		origin.global_position += dir * MAX_SPEED * XRServer.world_scale * push * push * delta
		amount = push * push
	var right := router.axis("studio_right_stick")
	if absf(right.x) > SNAP_ON and _snap_armed:
		_snap_armed = false
		# Turn about the head, not the room's centre.
		var head := cam.global_position
		origin.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-SNAP_DEGREES * signf(right.x))), Vector3.ZERO) \
				.translated(head) * Transform3D(Basis(), -head) * origin.global_transform
	elif absf(right.x) < SNAP_OFF:
		_snap_armed = true
	if not right_stick_busy and absf(right.y) > 0.2:
		origin.global_position.y += right.y * RISE_SPEED * XRServer.world_scale * delta
		amount = maxf(amount, absf(right.y) * 0.6)
	return amount
