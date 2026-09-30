#!/usr/bin/env bash
# Installs the third-party addons that aren't tracked in git into
# project_engine/addons/.
#
#   ci/fetch_addons.sh            godot-xr-tools, native_video (Windows /
#                                 macOS hardware decoding)
#   ci/fetch_addons.sh --android  also the OpenXR vendors plugin (Meta Quest)
set -euo pipefail

XR_TOOLS_VERSION="${XR_TOOLS_VERSION:-4.5.1}"
OPENXR_VENDORS_VERSION="${OPENXR_VENDORS_VERSION:-5.1.0-stable}"
NATIVE_VIDEO_VERSION="${NATIVE_VIDEO_VERSION:-v0.3.1}"
ADDONS="$(cd "$(dirname "$0")/../project_engine/addons" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ ! -d "$ADDONS/godot-xr-tools" ]; then
  curl -fsSL --retry 4 -o "$TMP/xrt.zip" \
    "https://github.com/GodotVR/godot-xr-tools/releases/download/${XR_TOOLS_VERSION}/godot-xr-tools.zip"
  unzip -q "$TMP/xrt.zip" -d "$TMP/xrt"
  cp -r "$TMP/xrt/godot-xr-tools/addons/godot-xr-tools" "$ADDONS/"
fi

# Patch XR Tools for Godot 4.7, which refuses a function that returns a
# value on some paths only: _property_get_revert gets a final
# `return null`. Safe to run again on a patched copy.
for f in functions/function_teleport.gd objects/viewport_2d_in_3d.gd; do
  f="$ADDONS/godot-xr-tools/$f"
  awk '
    /^func _property_get_revert/ { inside = 1 }
    inside && /^[ \t]*$/ {
      if (last != "\treturn null") print "\treturn null"
      inside = 0
    }
    { print; if (!/^[ \t]*$/) last = $0 }
  ' "$f" > "$TMP/patched.gd"
  cp "$TMP/patched.gd" "$f"
done

if [ ! -d "$ADDONS/native_video" ]; then
  curl -fsSL --retry 4 -o "$TMP/nv.zip" \
    "https://github.com/claytercek/godot-native-video/releases/download/${NATIVE_VIDEO_VERSION}/native_video-${NATIVE_VIDEO_VERSION}.zip"
  unzip -q "$TMP/nv.zip" -d "$TMP/nv"
  cp -r "$TMP/nv/addons/native_video" "$ADDONS/"
  # Windows debug runs (editor, tests, debug exports) load the release DLL
  # too: the debug one (Zig safety checks on) aborts with "sentinel
  # mismatch" on every video under the D3D12 driver, which is the default.
  sed -i -E 's/^(windows\.debug\.[a-z0-9_]+ = "native_video\.windows\.)debug\./\1release./' \
    "$ADDONS/native_video/native_video.gdextension"
fi

if [ "${1:-}" = "--android" ] && [ ! -d "$ADDONS/godotopenxrvendors" ]; then
  curl -fsSL --retry 4 -o "$TMP/vendors.zip" \
    "https://github.com/GodotVR/godot_openxr_vendors/releases/download/${OPENXR_VENDORS_VERSION}/godotopenxrvendorsaddon.zip"
  unzip -q "$TMP/vendors.zip" -d "$TMP/vendors"
  cp -r "$TMP/vendors/asset/addons/godotopenxrvendors" "$ADDONS/"
fi
