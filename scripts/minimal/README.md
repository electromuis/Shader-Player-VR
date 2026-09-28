# Minimal smoke-test script

Just enough JSON to prove the script format loads: no objects, no tracks, so
the player shows `video.mp4` on its default screen.

`video.mp4` isn't tracked (`moving_screen` plays it too, through
`../minimal/video.mp4`; forest_tunnel has its own copy next to its script).
Put any MP4 here under that name.

The Godot exporter refuses a scene with no objects, so the addon's round-trip
test skips this script.
