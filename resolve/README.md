# DaVinci Resolve: VJ Sync

`VJ Sync.py` connects DaVinci Resolve to the player. It does two things:

- **Playhead sync:** playing, pausing and scrubbing in Resolve drives the player (on the desktop or in the headset). When you pause the player or scrub it while it's paused, Resolve's playhead moves to the same spot. This is the same live sync the Godot addon's **▶ Preview in player** uses.
- **Markers → script events:** timeline markers named after an event (`vr_cut`, `despawn cube_1`, …) are written into the clip's VJ script as events.

It works in the free version of Resolve and needs no extra Python packages.

## Install

Copy `VJ Sync.py` into Resolve's `Scripts/Utility` folder, then restart Resolve:

- Windows: `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility\`
- macOS: `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/`
- Linux: `~/.local/share/DaVinciResolve/Fusion/Scripts/Utility/`

Run it from **Workspace → Scripts → VJ Sync**. It opens a small window, and syncing runs until you close that window.

## Which script goes with a clip

The player shows the VJ script of the clip under Resolve's playhead. If clips overlap, the one on the top video track wins. A clip's script is:

- the `.json` with the same name next to its media file (`clip.mp4` + `clip.json`), which is the player's own convention, or
- a script you added with **Add script…** whose `media.video` is that media file. Use this for a script that the Godot addon exports somewhere else.

The time in the script is the time in the media file, so trims, and clips moved along the timeline, still line up. Clip speed changes are taken into account on Resolve 21.1 and later. Moving to a different clip with a script opens that script in the player.

## Playhead sync

- A running player connects on its own. It looks for VJ Sync on `127.0.0.1:47820` whenever it wasn't started by the Godot editor, and **F2 → Config → Editor sync** turns this off.
- To start a player from Resolve, pick `Player.exe` in the window and press **Launch player**. This also works when port 47820 is taken and VJ Sync had to use a later port, which the window then shows.
- The player plays the video itself, so mute one of the two.
- Resolve doesn't tell scripts whether it is playing, so VJ Sync works it out from the playhead. The playhead moving forward steadily counts as playing, and standing still for a quarter of a second counts as paused. Single-frame steps (arrow keys) are seeks.

## Markers → script events

Put timeline markers where things should happen, then press **Markers → script events**. The marker's **name** says what happens. Its **note** holds the event's other fields, as a JSON object:

| Marker name | Note | Event |
|---|---|---|
| `vr_cut` | `{"to": {"position": [0, 2, 8], "rotation_deg": [0, 0, 0]}}` | Moves the viewer. |
| `vr_teleport` | the same as `vr_cut` | |
| `spawn <id> <prefab>` | optional: `{"transform": {...}, "config": {...}}` | Spawns an object. |
| `despawn <id>` | optional: `{"transition": {"type": "fade", "duration": 2}}` | Removes an object. |

- **Fades:** a marker with a duration is the fade. On `vr_cut` / `vr_teleport` it becomes a `fade_to_black` over the marker's length, and on `despawn` a `fade` over that length. A point marker with a `fade_to_black` transition in its note is the cut itself, at peak black, and the event starts half the fade earlier, as the Godot exporter does for `VJViewer` keys.
- Markers with other names (`Marker 1`, notes to yourself) are left alone. Markers that aren't on a clip with a script, and notes that aren't valid JSON, are listed in the window.
- The events are written with `"source": "resolve"`. Pressing the button again replaces exactly those, so events from anywhere else stay. The Godot addon's exporter keeps them too when it re-exports the script.
- The player reloads the script straight away.

## Without the window

With external scripting on (Resolve Studio, **Preferences → System → General → External scripting**), run it from a terminal with Resolve's Python, for example `"C:\Program Files\Blackmagic Design\DaVinci Resolve\ResolvePython\ResolvePython.exe" "VJ Sync.py"`. It syncs until Ctrl+C. Add `--export-markers` to only export the markers and exit.

Settings (the player path and the added scripts) are saved in `%APPDATA%\VJ Resolve Sync.json`, or in `~/VJ Resolve Sync.json` elsewhere.

## Tests

`python -m unittest discover -s resolve/tests` runs the tests with a fake Resolve and a real loopback WebSocket.
