@tool
class_name VJViewer
extends Camera3D

## Where the viewer stands. Put one directly under the VJScene root and
## keyframe its `position` / `rotation` on the "main" animation. How the
## keys export depends on `motion`:
##
## - "cuts": every key (after t=0) is a `vr_cut` event. The cut lands at the
##   key's time; with a fade, the event starts `fade_duration / 2` earlier
##   so the screen is fully black exactly when the view jumps.
## - "smooth": the keys are a ride (the script's "$viewer" track): the
##   viewer glides between them as the tracks interpolate (value or Bezier
##   tracks). A cut in a ride is a jump: a Discrete / Nearest track, or two
##   keys no more than 2 ms apart. A cut's fade starts at the key it jumps
##   to. The first key, if after t=0, is a cut from the home pose too.
##
## The player starts every script at its home pose (0, 2, 8) looking down
## -Z; a start pose (rest pose, or a key at t=0) anywhere else is a hard
## cut at t=0. In the headset the player uses only the yaw of a ride. Use
## this camera's "Preview" toggle in the 3D editor to see what the viewer
## sees.

## "cuts": the viewer jumps from key to key. "smooth": it rides between them.
@export_enum("cuts", "smooth") var motion: String = "cuts"
## Transition on each cut: "fade_to_black" or "none" (a hard cut).
@export_enum("fade_to_black", "none") var transition: String = "fade_to_black"
@export_range(0.0, 5.0, 0.05) var fade_duration: float = 1.0
