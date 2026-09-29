# TODO

Open tasks for the player, Studio and the addon. Numbers are permanent: refer to a task by its number, don't renumber, and add new tasks at the end of their section with the next free number. Check a task off (`- [x]`) when it's done, with a few words on where or how (a commit, a file); don't delete it. Details and background for Studio tasks are in `VR Studio — Plan.md` (*To do*, *Known issues*).

Open tasks carry a rough difficulty, **[D1]** (minutes to an hour) to **[D5]** (a large, multi-part job).

## Repo and CI

- [x] 1. Commit and push the docs cleanup of 2026-09-28 (this file, `docs/script_format.md`, the removed original plan, the README / Studio plan updates). Done 2026-09-28, in the commit that added this file.
- [ ] 2. **[D1]** Add the `GOZEN_TOKEN` repository secret (read access to `electromuis/gde_gozen`'s contents) and confirm CI passes on `master`.
- [ ] 3. **[D1]** Confirm the fork's `v9.7-sp4` release has its binaries published (CI and `ci/fetch_gozen.sh` now use it).
- [ ] 4. **[D1]** Delete the unused placeholder plugin `project_engine/addons/vj_editor/` (not enabled; a "Phase 6" stub). SKIP
- [ ] 5. **[D1]** Decide which README the CI packages ship: they copy the developer `README.md`, while `build_release.bat` ships the end-user `release/README.md`.
- [ ] 6. **[D2]** Try Studio as a full exported Windows build (so far only checked with `--export-pack`).
- [x] 7. Make `tests/run.gd` count a test that hits a script error as failed (now it stops there but counts as passed). Done 2026-09-29: the runner registers a `Logger` (`OS.add_logger`) and fails a test during which a GDScript runtime error was logged; all 319 tests still pass. Also since 2026-09-29: a test file that doesn't parse counts as one failed test (it used to vanish from the count).

## Studio

- [x] 8. Wrist palette to the mockup (`docs/studio/todo/3_wrist.png`): Play / Edit switch, big timecode with duration and bar, a 4 × 3 icon grid, a footer with Save and "autosaved …", a second page for the rest. Done 2026-09-29 in fe000a6: `studio/ui/wrist_palette.gd` on `StudioWristTile` (`studio/ui/wrist_tile.gd`, the player's `WristTile` with Studio's icons); swipe or the dots for page 2; a help line for the tile under the pointer; *Key it* sits where the mockup's *Outliner* goes until 15 is built; checked with `checks/shot_studio_wrist.gd`, render `docs/studio/wrist_palette.png`.
- [x] 9. Minimize (–) on every panel (inspector, shelf, timeline, outliner), folding it to a tab on the wrist. Done 2026-09-29: — on the inspector, the shelf and the timeline; the wrist's panel buttons are the headset's tabs, the desktop gets tabs in the status (`Studio._fold`, `StudioStatus.show_tabs`); checked with `checks/shot_studio_panels.gd`. The outliner (15) should get one when it's built.
- [ ] 10. **[D3]** Move panels in VR by their title bar; panels keep their place relative to you as you fly. 2026-09-29: the second half is done (the headset panels ride on the XR rig; `shot_studio_panels.gd`); moving one by its title bar is left.
- [x] 11. Timeline scroll bar over the whole piece (with the audio's outline): drag to scroll, pull its ends to zoom. Done 2026-09-29: drawn on the ribbon's canvas under the lanes (`StudioTimelineRibbon._draw_bar`, `StudioTimeline.scroll_to` / `pull_end`); a press beside the window jumps there, the wheel over it scrolls; checked with `checks/shot_studio_scrollbar.gd`.
- [x] 12. Draw the floor grid (1 m lines); the setting exists (`StudioSettings.floor_grid`) but nothing draws it. Done 2026-09-29: `studio/tools/floor_grid.gd`, checked with `checks/shot_studio_floor_grid.gd`.
- [x] 13. Desktop drops land too far away: a card lands on the floor under the cursor, with its distance shown. Done 2026-09-29: `StudioAssetDrop.aim` lets the floor win past the main screen; `studio/tools/drop_preview.gd` shows the outline, footprint and distance; checked with `checks/shot_studio_drop.gd`.
- [ ] 14. **[D4]** Groups: make and animate groups in Studio (the format has spawn parents already).
- [ ] 15. **[D4]** Outliner panel: the piece's objects as a tree; select, group (Ctrl+G), ungroup, drag into a group. Its wrist tile goes where *Key it* is on page 1 (`StudioWristPalette.PAGES`), as in the mockup.
- [x] 16. Make motion paths obvious (keys and times; maybe faint paths for every animated object). Done 2026-09-29 in aff4778 (branch `motion-paths`): wide camera-facing paths with a diamond and time at each key (played part dimmer, the key at the playhead white), faint paths for every other animated object (Studio tab > *Motion paths*), the seat marker labelled *Seat* (it was likely what looked like a path on things without keys). `StudioMotionPaths`; `tests/test_studio_paths.gd`, checked with `checks/shot_studio_paths.gd`, render `docs/studio/motion_paths.png`. Not seen in a headset.
- [x] 17. Shadertoy tab on the shelf (search or paste a link; a shader becomes a layer or an effect). Done 2026-09-29 in 58aaf17: the collection the Chrome extension fills (Studio runs a receiver), filter, Search (opens the site), Paste (a link opens its page, which the extension now sends by itself; code or JSON goes straight in); Layer / Effect convert into your library's `shaders/` (`StudioShadertoy`), and Shadertoy post-processes can be effects (`ShadertoyShader.to_effect_gdshader`); previews and hover loops for the cards. `tests/test_studio_shadertoy.gd`, checked with `checks/shot_studio_shadertoy.gd`, render `docs/studio/shadertoy_tab.png`. Not verified: `#vj-send` on the live site.
- [x] 18. Animated previews on layer and effect cards (on hover on the desktop, while the shelf is open in the headset). Done 2026-09-29 in a55be4b: vertex cards too; `StudioThumbnailer.loop` (20 frames on the preview's own clock, cached as a strip), played by `StudioAssetShelf`; `test_card_loops`, checked with `checks/shot_studio_loops.gd`, render `docs/studio/shelf_loops.png`.
- [ ] 19. **[D4]** GPU cost readout per object, layer and effect, and a benchmark that plays the piece and lists the heaviest moments.
- [x] 20. Catch up with the player: list the player features Studio's UI doesn't use yet (e.g. Blend in the inspector) and add them. Done 2026-09-29 in 55cf753: the list is in the plan (*To do* 9), both ways. Studio gained Blend and Fit to video, `hint_enum` params as choices, image params (they broke the inspector; picked images are copied into the piece's `images/`), Video as a layer source, the script's camera effects (`$camera`: inspector, Camera fx lane, keys) and Reload shaders; the player gained colour params in the Camera tab (and a layer's colours from a config), and string keys hold. `tests/test_studio_catch_up.gd`, checked with `checks/shot_studio_catch_up.gd` and `shot_player_colours.gd`; renders `docs/studio/catch_up_*.png`, `docs/player/colour_params.png`. Follow-ups: 53–57.
- [x] 21. ↺ on the Config tab's rows (changes the player's tab too). Done 2026-09-29: every Config row (`PlayerSettings.is_default` / `reset`; the renderer back to the project's driver), and the Camera tab's placement sliders (Size … Resolution, Opacity with Blend), which had none either; `tests/test_player_settings.gd`, checked with `checks/shot_ui.gd`.
- [x] 22. The shelf gets squeezed to about 120 px at 1280 × 720, so no card row shows. Done 2026-09-29: the user said desktop Studio can just run at 1080, so it opens its window at 1920 × 1080 (maximized on a smaller screen: 1920 × 1009 under a taskbar still shows two card rows); `Studio._size_window`.
- [ ] 23. **[D3]** Looks: rename and delete in Studio, looks for a group with its children, keyframes in a look.
- [ ] 24. **[D3]** External changes to an open piece (e.g. a Godot export): offer *reload* or *keep mine*.
- [ ] 25. **[D1]** "Save as".
- [ ] 26. **[D2]** Keep the autosave and backups in a hidden folder rather than next to the piece.
- [ ] 27. **[D3]** Ghosts (next-key boxes) for objects that aren't selected; hover highlights on headset panel buttons.
- [ ] 28. **[D2]** Haptic detents on inspector sliders and clicks on panels.
- [ ] 29. **[D4]** Controls: the controller picture (pointing at a button shows what it does), and named binding profiles.
- [ ] 30. **[D4]** Track down the segfault of `drive_studio_m4.gd` / `m6` in the user's working copy (when GoZen closes the piece's `song.wav`). 2026-09-29: now reproduces on a clean `master` here too (`HEADLESS=1 tools/local/run.sh checks/drive_studio_m4.gd`, every run), so it isn't the working copy.
- [ ] 52. **[D5]** Bring Studio's UI in line with the mockups (`docs/studio/*.svg`, `docs/studio/todo/`): the user says it still looks a lot different (2026-09-28). Compare panel by panel with renders; 8–11 and 15 are parts of it.
- [ ] 53. **[D2]** Looks carry picked images: a look whose config names an image (`images/…`, relative to the piece) should copy it into the library's `images/` and name it from there, as it does shaders (`StudioLooks`).
- [ ] 54. **[D3]** The video's layout (field of view, stereo, eye order) as part of a piece (a format addition, e.g. `media.layout`) and in Studio's inspector or menu: now Studio and a script go by the file name, while the player's Camera tab can override it for itself.
- [ ] 55. **[D3]** Bring a player preset (its layers, effects and camera effect) into a piece, or offer presets as looks on the shelf.
- [ ] 56. **[D1]** The headset inspector cuts "Render scale" to "Render sca" (its label column); check the other long labels there too.
- [ ] 58. **[D4]** Keyframe an effect's on/off, as spawn / despawn are keyed for objects: a key that switches an effect (screen, layer, vertex and camera effects) on or off at a time, shown on the timeline, with an optional fade over a duration like a despawn's `transition`. Needs a format addition (`docs/script_format.md`; today `enabled` is a fixed field), the player to apply it (a switched-off effect keeps its place so `effect<N>` targets stay stable, or document how they shift), Studio's inspector toggle to key it, and the addon's exporter to write it.
- [ ] 59. **[D3]** A blend option for each effect: how its output combines with its input — a mix amount (0–1, keyable, so an effect can fade in and out; the fade of 58 can use it) and a mode (`normal`, `add`, `multiply`, `screen`, …, as a screen's `blend`). In the format, the player's effect chain, Studio's inspector (per effect row) and the addon.
- [x] 60. Click and drag on the inspector's number fields (scale and the like) to change the value, as in Godot's or Blender's spin boxes; a click without a drag still types a value. Done 2026-09-29 in 5028751 (branch `inspector-drag-numbers`): the transform's x / y / z numbers drag sideways (Shift: finer), preview like the sliders and write one undo step on release (`StudioInspector._draggable`); checked with `checks/shot_studio_drag_number.gd`.
- [ ] 61. **[D2]** Bug: a keyframe forgets its value. Key a value of 0, then key a value of 1 at a later time: the first key loses its 0. Reproduce with a test and fix.
- [ ] 62. **[D2]** Lock an object's position (a lock toggle in the inspector and outliner) so it can't be moved by accident; a locked object can still be selected and its other properties edited.
- [ ] 63. **[D1]** The on/off toggle's circle isn't centred in its track; fix it and check the other toggles.
- [ ] 64. **[D3]** Timeline: a vertical scroll bar for the lanes, and a toggle on each object's row to show or hide its property tracks.
- [ ] 65. **[D2]** Bug: domes can't be resized: setting the size to infinity still gives a small globe around the viewer. Find out what the size setting does and make a large or infinite dome work.
- [ ] 66. **[D3]** Move gizmo: arrows on an object's origin axis lines; drag an arrow to move the object along that axis.
- [ ] 67. **[D2]** Scale by press, hold and scroll (or drag): hold a button on an object and scroll or drag to scale it.
- [x] 68. The wrist menu in desktop mode (open it with a key or a button and click it with the mouse). Done 2026-09-29 in 48e53a7, moved in a1e3472: the desktop's top left corner shows the status or the wrist palette (`Studio.wrist_2d`), switched by *Status* / *▦ Wrist palette* tabs over it or P; clicked with the mouse (drag across it for page 2); the shelf moves under it; checked with `checks/shot_studio_wrist_desktop.gd`, render `docs/studio/wrist_desktop.png`.
- [ ] 69. **[D2]** Bug: a shader dragged in from the shelf sometimes gets its spawn (its existence bar on the timeline) a little after the playhead, so it doesn't show until you press play. It should spawn at the playhead, or the paused view should show it.

## Player

- [ ] 31. **[D2]** An error dialog (or at least a visible message) when a script fails to load; now only the status line says so.
- [ ] 32. **[D1]** `--windowed` command-line option.
- [ ] 33. **[D2]** Controller models or markers in VR (only the laser shows).
- [ ] 34. **[D3]** Leaving VR during a fade or a cut.
- [ ] 35. **[D4]** Camera effects: several at once (chaining), feedback trails, Shadertoy `mainImage` code as a camera effect.
- [ ] 36. **[D4]** 3D shaders: `depthImage` and a Depth vertex effect (`docs/3d_shaders.md`).
- [ ] 57. **[D2]** Previews in the Camera tab's shader and effect pickers, as Studio's shelf has (`StudioThumbnailer`); the pickers are names only.

## Addon and example pieces

- [ ] 37. **[D1]** Export a despawn's fade `transition` (the exporter writes a plain despawn).
- [ ] 38. **[D4]** `vr_teleport` from the addon, and multiple animations / clip chaining.
- [ ] 39. **[D2]** Live sync: the Animation panel's playhead is moved through an unexposed editor control (`live_sync.gd`, the time SpinBox); a Godot update could break it.
- [ ] 40. **[D2]** Live sync: a seek while the player's video is still opening reports t=0, so the editor's playhead blips to 0.
- [ ] 41. **[D1]** Re-export `scripts/forest_tunnel/video.json` from its project (still format 1 with baked curves).

## Needs a headset (Quest 3)

- [ ] 42. **[D2]** The player's checklist: wrist HUD buttons, laser clicks in every menu tab, cuts with their fades, entering and leaving VR.
- [ ] 43. **[D2]** Studio's pointer UI: wrist palette, inspector (sliders, colour wheel, effect drag), timeline, shelf (carrying cards), menu (holding ≡).
- [ ] 44. **[D2]** Studio's hands and flight: grabbing, two-hand scale / turn, snap turn, flight speed, the miniature's scale, carrying path keys.
- [ ] 45. **[D3]** Rides: the rig following a ride, the height offset, how it feels, the comfort vignette, keying the viewer from a real head pose.
- [ ] 46. **[D2]** Left-handed mode: the left laser on panels, the mirrored wrist panel, the mirrored sticks.
- [ ] 47. **[D2]** Tune the haptic strengths and lengths, and check the Quest runtime plays the short pulses.
- [ ] 48. **[D2]** Panel sharpness and distances on the Quest 3.
- [ ] 49. **[D3]** Camera effects per eye (multiview), and their frame-time cost.
- [ ] 50. **[D2]** forest_tunnel comfort: the fades, and whether the columns' fly-by at 68–76 s is too close.
- [ ] 51. **[D3]** M8's test: a first-time user places, keys and plays back a screen in 10 minutes unaided.
