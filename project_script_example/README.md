# project_script_example — Moving Screen

Godot authoring project for **one** VJ piece (the moving-screen demo). Edit
`main.tscn` in Godot, then click **▶ Preview in player** in the 3D editor
toolbar (or **Tools > VJ: Export current scene to script.json…** to only
write the JSON). See [addon_vj/README.md](../addon_vj/README.md) for how
scenes map to scripts.

## Layout

- `project.godot` — enables the `vj_editor` plugin
- `addons/vj_editor/` — **Windows junction** → `../../addon_vj/` (the canonical
  addon lives at the repo root; this project just references it)
- `main.tscn` — the scene:
  - `Stage` (root, `VJScene` script) — holds meta / video path / export path
  - `main_screen` — `screen` prefab instance with a `glow` effect, animated
    position + rotation
  - `cube_1` — `cube` prefab instance, spawn/despawn via a `visible` track
  - `AnimationPlayer` with one animation `main` (length 18s)

## Recreating the addon junction

The junction is gitignored, so a fresh clone has none. Create it from
PowerShell at the repo root:

```powershell
New-Item -ItemType Junction `
    -Path project_script_example\addons\vj_editor `
    -Target (Resolve-Path addon_vj)
```

`project_script_forest_tunnel` needs the same junction (and one for
`gde_gozen`, see its README).

## Export target

`Stage.output_path` is `res://../scripts/moving_screen/video.json`, the
repo's `scripts/moving_screen/`. The player reads that same file
(`project_engine` launched with `--script <path>`, or
`build_and_run.bat`).

## Adding new objects

1. Drag `addons/vj_editor/builtin_prefabs/screen.tscn` or `cube.tscn` into
   `Stage`.
2. Rename it — the node name becomes the JSON `id`.
3. Set `metadata/vj_prefab` on the new node to `"screen"` or `"cube"` (or
   leave it off for a custom prefab, which the export copies next to the JSON).
4. Author position / rotation / scale / visibility tracks on the
   `AnimationPlayer`'s `main` animation.
5. Export.
