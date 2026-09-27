#!/usr/bin/env bash
# The Windows (Git Bash) counterpart of tools/cloud/run.sh: runs a check
# from tools/cloud/checks, or the player tests, in a copy of project_engine
# with the gde_gozen classes made dynamic, on the real GPU (no Xvfb).
# Screenshots land in $WORK/shots (OUT_DIR).
#
#   tools/local/run.sh checks/drive_studio_m3.gd          # rendered
#   HEADLESS=1 tools/local/run.sh checks/drive.gd         # no rendering
#   RESOLUTION=1600x900 tools/local/run.sh checks/...     # a bigger window (default 1280x720)
#   tools/local/run.sh tests                              # the player tests
#
# The copy uses its own user dir, %APPDATA%/VJ checks (reset it freely):
# the player's real one holds the user's settings and presets, and their
# own player may be running on it. XR Tools must be installed once
# (ci/fetch_addons.sh, then the 4.7 patch in tools/cloud/setup.sh).
# GODOT defaults to Chocolatey's console build, called directly: a
# `timeout` on the godot.exe shim would leave the real process running.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${WORK:-$(cygpath -m "${TEMP:-/tmp}")/vj_local}"
export REPO="$(cygpath -m "$REPO")" WORK
GODOT="${GODOT:-$(ls /c/ProgramData/chocolatey/lib/godot/tools/Godot_v4.7*_win64_console.exe 2>/dev/null | tail -1)}"
if [ -z "$GODOT" ]; then
	echo "Set GODOT to a Godot 4.7 console executable." >&2
	exit 1
fi
COPY="$WORK/engine_copy"
mkdir -p "$COPY" "$WORK/shots"
# Re-sync the copy (its .godot import cache stays, for speed).
find "$COPY" -mindepth 1 -maxdepth 1 ! -name .godot -exec rm -rf {} +
(cd "$REPO/project_engine" && tar --exclude=.godot -cf - .) | (cd "$COPY" && tar -xf -)
sed -i 's/var video := GoZenVideo.new()/var video = ClassDB.instantiate("GoZenVideo")/; s/var stream := AudioStreamFFmpeg.new()/var stream = ClassDB.instantiate("AudioStreamFFmpeg")/' "$COPY/player/video_bridge.gd"
sed -i 's/^var video: GoZenVideo = null/var video = null/; s/	video = GoZenVideo.new()/	video = ClassDB.instantiate("GoZenVideo")/; s/func update_video(video_instance: GoZenVideo,/func update_video(video_instance,/; s/func _update_video(new_video: GoZenVideo)/func _update_video(new_video)/; s/var stream: AudioStreamFFmpeg = AudioStreamFFmpeg.new()/var stream = ClassDB.instantiate("AudioStreamFFmpeg")/' "$COPY/addons/gde_gozen/video_playback.gd"
sed -i 's/^\[application\]\r\?$/[application]\nconfig\/use_custom_user_dir=true\nconfig\/custom_user_dir_name="VJ checks"/' "$COPY/project.godot"
cd "$COPY"
timeout 300 "$GODOT" --headless --import >/dev/null 2>&1 || true
if [ "$1" = "tests" ]; then
	# The example scripts the tests read are next to project_engine.
	rm -rf "$WORK/scripts"
	cp -r "$REPO/scripts" "$WORK/scripts"
	timeout 600 "$GODOT" --headless --script res://tests/run.gd
	exit
fi
cp "$REPO/tools/cloud/$1" "$COPY/"
NAME="$(basename "$1")"
if [ "${HEADLESS:-}" = "1" ]; then
	timeout 300 "$GODOT" --headless --script "res://$NAME"
else
	OUT_DIR="$WORK/shots" timeout 300 "$GODOT" --rendering-method forward_plus --resolution "${RESOLUTION:-1280x720}" --script "res://$NAME"
fi
