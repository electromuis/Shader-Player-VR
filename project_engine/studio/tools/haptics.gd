class_name StudioHaptics
extends RefCounted

## Short pulses on the controllers that confirm what a hand did, so it's
## felt as well as seen (see "VR Studio — Plan.md", Visual language): a
## grab, a let-go, a detent at each snap while carrying with snapping on, a
## key written, a card dropped (two weak ones when it isn't taken), and a
## take starting to record and being written. Only in the headset;
## `enabled` turns them off. Every pulse asked for is logged (`log`, the
## last LOG_SIZE), in the headset or not, so checks can see them.

## The OpenXR action (player/vr/openxr_action_map.tres) on both hands.
const ACTION := &"haptic"
## kind -> [amplitude (0..1), seconds]. Weak and short for what happens
## often (snaps), stronger for what's written (keys, drops, takes).
const PULSES := {
	"grab": [0.45, 0.03],
	"release": [0.25, 0.02],
	"snap": [0.15, 0.008],
	"key": [0.7, 0.05],
	"drop": [0.6, 0.06],
	"refuse": [0.3, 0.02],
	"record": [0.8, 0.12],
}
## "refuse" pulses twice, this far apart.
const REFUSE_GAP := 0.09
const LOG_SIZE := 64

var rig: XRRig
## () -> bool: whether the headset is on (pulses only go there).
var in_vr: Callable = func(): return false
var enabled := true
## [{kind, hand, sent}], oldest first.
var log: Array = []
## Pulses asked for so far.
var count := 0


## Pulse `kind` on `hand`: "L", "R", or "both" ("M", the mouse, has none).
func tick(kind: String, hand: String = "R") -> void:
	if not PULSES.has(kind):
		return
	var send: bool = enabled and rig != null and hand != "M" and in_vr.call()
	log.append({"kind": kind, "hand": hand, "sent": send})
	count += 1
	if log.size() > LOG_SIZE:
		log.pop_front()
	if not send:
		return
	var p: Array = PULSES[kind]
	for h in (["L", "R"] if hand == "both" else [hand]):
		var c: XRController3D = rig.left_controller if h == "L" else rig.right_controller
		if c == null:
			continue
		c.trigger_haptic_pulse(ACTION, 0.0, p[0], p[1], 0.0)
		if kind == "refuse":
			c.trigger_haptic_pulse(ACTION, 0.0, p[0], p[1], REFUSE_GAP)


## "kind:hand" of the pulses asked for since `count` was `from` (at most
## the last LOG_SIZE), for checks.
func kinds_since(from: int) -> Array:
	var n := mini(count - from, log.size())
	return log.slice(log.size() - n).map(func(e): return "%s:%s" % [e.kind, e.hand])
