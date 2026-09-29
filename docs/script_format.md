# Script format

A VJ script is a JSON file that plays on top of a video: it spawns screens, shader layers and objects, moves them, animates their shaders, and moves the viewer. The player, Studio and the Godot addon all read and write it, and it can be written by hand. `ScriptFormat` (`project_engine/player/script_format/script_format.gd`) is the validator; what it accepts is the format.

## A script's folder

```
clip.mp4
clip.json            # the script; the player picks it up next to a same-name video
prefabs/forest.tscn  # custom prefabs (the exporter and Studio copy them here)
shaders/glow.gdshader
```

All paths in a script are relative to the script itself. `res://player/...` paths name the player's built-ins. The Godot exporter and Studio copy custom prefabs and shaders into the folder, so it can be zipped and played anywhere.

## Top level

```json
{
  "format_version": 2,
  "meta": { "title": "Forest to Tunnel", "author": "Someone", "created": "2026-09-22" },
  "media": { "video": "clip.mp4", "duration": 188.9, "beats": { "bpm": 128, "offset": 0.42, "beats_per_bar": 4 } },
  "prefabs": { "screen": "res://player/prefabs/screen.tscn", "forest": "prefabs/forest.tscn" },
  "shaders": { "glow": "res://player/visualizer/effects/glow.gdshader" },
  "camera": { "effects": [ { "shader": "builtin:kaleidoscope", "strength": 0.5 } ] },
  "tracks": [ ]
}
```

- **`format_version`**: 1 or 2. Exporters write 2. Version 1's `cubic` meant a smoothstep, so v1 files load with it read as `ease` (`ScriptFormat.upgrade`). Studio saves an edited v1 script as v2.
- **`meta`**: free-form, except `"default_screen": false`. Normally a plain video screen is added unless the script spawns its own `main_screen`; `false` turns it off.
- **`media`**: `video` (required; a relative path or an `http(s)://` URL), `duration` (seconds), and optionally `beats`, a beat grid for the beat uniforms instead of the one the player detects (`offset` is the time of a downbeat). `audio` is accepted but unused.
- **`prefabs`**, **`shaders`**: name → path maps. Tracks and configs refer to these names.
- **`camera`**: camera effects over the whole view (below).
- **`tracks`**: everything that happens (below).
- `objects` is accepted and ignored (an early design). Objects are created by `spawn` events.

## Tracks

Two kinds. **Continuous tracks** (`transform`, `shader_param`) are sampled every frame. **Events** fire at their time. Seeking, or a live reload, rebuilds what exists at the playhead. An object whose spawn event changed (config, transform, parent) is respawned.

```json
{ "type": "transform", "target": "main_screen", "channel": "position",
  "keyframes": [ { "t": 0, "value": [0, 1.6, -5] }, { "t": 30, "value": [0, 2, -3], "interp": "cubic" } ] }

{ "type": "shader_param", "target": "main_screen.effect0", "param": "intensity",
  "keyframes": [ { "t": 0, "value": 0.0 }, { "t": 10, "value": 1.0 } ] }

{ "type": "event", "t": 55, "action": "spawn", "id": "screen_left", "prefab": "screen", "parent": "screens",
  "transform": { "position": [-5.33, 0, 0], "rotation_deg": [0, 0, 0], "scale": [0.167, 0.5, 0.5] },
  "config": { "effects": [ { "shader": "crop", "params": { "left": 0.0, "width": 0.333 } } ] } }

{ "type": "event", "t": 160, "action": "despawn", "target": "screen_left", "transition": { "type": "fade", "duration": 2 } }
```

### Keyframes

- `t` (seconds, in order) and `value`: a number, or an array (`[x, y, z]` for transforms; arrays of 2 to 4 numbers reach shaders as `Vector2/3/4`, colours as `[r, g, b, a]`).
- `interp` shapes the segment *after* the key: `linear` (default), `step` (hold), `ease` (smoothstep into each key), `cubic` (a spline through the keys, Godot's cubic value-track interpolation) or `bezier` (Godot's Bezier curve).
- Bezier keys carry `in` / `out` handles as `[dt, dv]` relative to the key, one pair per element for array values. The segment uses the key's `out` and the next key's `in`.
- Before the first key and after the last, the track holds the end value.

### `transform`

`channel` is `position`, `rotation_deg` (degrees) or `scale`; `target` is an object id or `$viewer` (below).

### `shader_param`

`target` is `<id>.<slot>`, `param` the uniform's name:

| Slot | What it animates |
|---|---|
| `surface` | a screen's artist shader, or a custom prefab's shader material |
| `layer` | a layer's shader |
| `display` | a screen's or layer's `opacity` (and earlier scripts' `curvature` / `vertical_curvature`) |
| `shape` | the surface's params (`arc_x`, `arc_y`, ...) |
| `effect<N>` | the Nth enabled effect, from 0: its params, and its `mix`, `blend` and `enabled` (below) |
| `vertex<N>` | the Nth enabled vertex effect, from 0: its params, `mix` and `enabled` |
| `modifiers` | `opacity`, `tint`, `flash`, `speed`, `sort_offset` (below) |
| `reactive` | `spin`, `pulse` (below) |

`$camera.effect<N>` animates a camera effect's params, its `strength`, `blend` and `enabled`.

**Switching an effect on and off over time:** a `shader_param` track with param `enabled` on `<id>.effect<N>`, `<id>.vertex<N>` or `$camera.effect<N>`. Its keys are `true` / `false`; each holds until the next (write them as `step`). A key may carry `"transition": {"type": "fade", "duration": s}`: from the key on, the effect fades over `s` seconds from where it was to on or off (its mix, or a camera effect's strength, going to or from 0). Before the first key the effect is as that key says. The effect keeps its place while it's off, so its `effect<N>` stays the same and the numbers after it don't move; only `"enabled": false` in the config (below) takes an effect out of the count, for the whole piece.

```json
{ "type": "shader_param", "target": "main_screen.effect1", "param": "enabled", "keyframes": [
    { "t": 0, "value": true, "interp": "step" },
    { "t": 12, "value": false, "interp": "step", "transition": { "type": "fade", "duration": 2 } } ] }
```

### Events

- **`spawn`**: `id` (unique across the script; ids starting with `$` are reserved), `prefab` (a `prefabs` name), optional `transform`, `parent` and `config`. With `parent` (an object that already exists) the object sits inside it, in its space, and goes when it goes. At the same `t` events run in file order, so spawn a parent before its children.
- **`despawn`**: `target`, and optionally `"transition": {"type": "fade", "duration": s}`, which fades any mesh out, MultiMeshes included.
- **`vr_cut`** / **`vr_teleport`**: `"to": {"position": [...], "rotation_deg": [...]}`, optionally `"transition": {"type": "fade_to_black", "duration": s}`. They join the viewer's track as cuts (below).

## The viewer: `$viewer`

`transform` tracks on `$viewer` (channels `position` and `rotation_deg`, no `scale`) move the audience. The viewer glides along the track (a *ride*) and jumps at a *cut*:

- a key reached through a `step` segment,
- the track's first key (a jump from the home seat),
- every `vr_cut` / `vr_teleport` event.

A key may carry `"transition": {"type": "fade_to_black", "duration": 1}` for its cut. Every script starts at the home seat, (0, 2, 8) looking down −Z. In the headset only the turn (`rotation_deg` y) is used, never tilt or roll. The viewer's *Script camera* setting can play rides as fades only.

## Objects and their `config`

**Built-in prefabs** (map them in `prefabs`): `res://player/prefabs/screen.tscn` (a video screen), `layer.tscn` (a shader layer), `group.tscn` (an empty node for grouping) and `cube.tscn`. Top-level screens, groups and layers live in the player's `ScreenMount`, so the viewer's screen size and distance settings move them together. A custom prefab is any `.tscn`.

**Screens:**
- `opacity`, `blend` (`normal`, `add`: adds its light; `black`: black is see-through), `render_scale`, `fit_aspect` (the picture keeps the video's shape inside the 16:9 quad, letterboxed or pillarboxed).
- `surface`: `{"shader": "pillow" | "dome" | <shaders name>, "params": {...}, "placement": "fixed" | "around" | "infinity"}`. Pillow bends by `arc_x` / `arc_y` degrees; Dome is part of a sphere; `around` centres it on the home eye; `infinity` (Dome only) follows the head, for 180° / 360° video. Earlier scripts' `curvature` / `vertical_curvature` (0..1) read as a Pillow's arcs × 180°.
- `effects`: `[{"shader": <shaders name>, "params": {...}, "enabled": true, "mix": 1, "blend": "normal"}]`, run in order over the picture. A switched-off entry (`"enabled": false`) is skipped, doesn't count towards `effect<N>`, and may keep its own tracks for when it's switched back on (`"tracks": [{"param", "keyframes"}]`, as Studio does). `"shader": ""` is an empty slot. Effects that draw past the picture (a `// @reach` hint: Blur, outward Edge blur, Glow) get a transparent margin automatically, and earlier versions' `padding` entries are ignored.
  - `mix` (0–1, default 1): how much of the effect shows; at 0 it does nothing (and costs nothing). Keyable, to fade an effect in and out.
  - `blend` (default `normal`): how its output goes over its input. `normal` replaces it (below mix 1 the two crossfade); `add`, `subtract`, `multiply`, `screen`, `overlay`, `difference`, `lighten` and `darken` blend the output's colour onto the input like an image editor's layer modes, keeping the input's shape (a mask under `multiply` only darkens), then crossfade by `mix`. A `blend` track holds from key to key.
- `vertex_effects`: the same shape, moving the surface. Built-ins go by name (`ripple`, `twist`, `bulge`, `spin`, `pulse`), others by `shaders` name. `mix` (0–1) is how far each moves the surface; there's no `blend`.

**Layers** take `shader` (a `shaders` name for a layer shader or Shadertoy `.glsl`, or `"video"` for the playing video laid out like the main screen), `params` (its hinted uniforms), `resolution` (a multiplier on the shader's `@resolution`), and `effects`, `vertex_effects`, `surface`, `opacity` and `blend` as screens do.

**Any object:**
- `modifiers`: set on everything under the object, multiplied down through groups. `opacity` (0–1, meshes' `transparency`), `tint` (`[r, g, b, a]`, a multiply overlay), `flash` (`[r, g, b, a]`, alpha is strength, an additive overlay), `speed` (particles' and AnimationPlayers' `speed_scale`) and `sort_offset` (metres, `sorting_offset`). The prefab needs nothing for them.
- `reactive`: motion computed on top of the animated transform. `spin` (`[x, y, z]` degrees per second, integrated over the timeline, so a seek lands on the same angle) and `pulse` (0–1: scale grows with the bass). On screens and layers the *Spin* and *Pulse* vertex effects do this now.

```json
{ "type": "event", "t": 0, "action": "spawn", "id": "backdrop", "prefab": "layer", "parent": "main_screen",
  "transform": { "position": [0, 0, -12], "scale": [3, 3, 3] },
  "config": { "shader": "video", "resolution": 0.25,
              "effects": [ { "shader": "blur", "params": { "radius": 0.065 } },
                           { "shader": "oval_mask", "params": { "size": 0.44, "ratio": 1.7 } } ] } }
```

## Camera effects: `camera`

`{"effects": [{"shader", "params", "strength", "blend", "enabled"}]}`: a GLSL `// @camera` shader over everything the viewer sees (a `shaders` name, or a built-in such as `"builtin:kaleidoscope"`). `strength` is its mix; `blend` works as an effect's. Only the first enabled effect runs. It wins over the viewer's preset, within their Config limits.

## Shader values

- Numeric arrays of 2 to 4 become `Vector2/3/4`.
- A texture param is a path relative to the script (Studio copies picked images into the piece's `images/`).
- A string key in a `shader_param` track (a `display` slot's `blend`, an image path) holds until the next key, whatever its `interp`; Studio writes such keys as `step`.
- Shader time follows the video; a shader with a `// @free_time` line keeps its own.
