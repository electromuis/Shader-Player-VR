# TODO

Open tasks for the player, Studio and the addon. Numbers are permanent: refer to a task by its number, don't renumber, and add new tasks at the end of their section with the next free number. Check a task off (`- [x]`) when it's done, with a few words on where or how (a commit, a file); don't delete it. Details and background for Studio tasks are in `VR Studio — Plan.md` (*To do*, *Known issues*).

## Repo and CI

- [x] 1. Commit and push the docs cleanup of 2026-09-28 (this file, `docs/script_format.md`, the removed original plan, the README / Studio plan updates). Done 2026-09-28, in the commit that added this file.
- [ ] 2. Add the `GOZEN_TOKEN` repository secret (read access to `electromuis/gde_gozen`'s contents) and confirm CI passes on `master`.
- [ ] 3. Confirm the fork's `v9.7-sp4` release has its binaries published (CI and `ci/fetch_gozen.sh` now use it).
- [ ] 4. Delete the unused placeholder plugin `project_engine/addons/vj_editor/` (not enabled; a "Phase 6" stub). SKIP
- [ ] 5. Decide which README the CI packages ship: they copy the developer `README.md`, while `build_release.bat` ships the end-user `release/README.md`.
- [ ] 6. Try Studio as a full exported Windows build (so far only checked with `--export-pack`).
- [x] 7. Make `tests/run.gd` count a test that hits a script error as failed (now it stops there but counts as passed). Done 2026-09-29: the runner registers a `Logger` (`OS.add_logger`) and fails a test during which a GDScript runtime error was logged; all 319 tests still pass. Also since 2026-09-29: a test file that doesn't parse counts as one failed test (it used to vanish from the count).

## Studio

- [x] 8. Wrist palette to the mockup (`docs/studio/todo/3_wrist.png`): Play / Edit switch, big timecode with duration and bar, a 4 × 3 icon grid, a footer with Save and "autosaved …", a second page for the rest. Done 2026-09-29 in fe000a6: `studio/ui/wrist_palette.gd` on `StudioWristTile` (`studio/ui/wrist_tile.gd`, the player's `WristTile` with Studio's icons); swipe or the dots for page 2; a help line for the tile under the pointer; *Key it* sits where the mockup's *Outliner* goes until 15 is built; checked with `checks/shot_studio_wrist.gd`, render `docs/studio/wrist_palette.png`.
- [x] 9. Minimize (–) on every panel (inspector, shelf, timeline, outliner), folding it to a tab on the wrist. Done 2026-09-29: — on the inspector, the shelf and the timeline; the wrist's panel buttons are the headset's tabs, the desktop gets tabs in the status (`Studio._fold`, `StudioStatus.show_tabs`); checked with `checks/shot_studio_panels.gd`. The outliner (15) should get one when it's built.
- [ ] 10. Move panels in VR by their title bar; panels keep their place relative to you as you fly. 2026-09-29: the second half is done (the headset panels ride on the XR rig; `shot_studio_panels.gd`); moving one by its title bar is left.
- [x] 11. Timeline scroll bar over the whole piece (with the audio's outline): drag to scroll, pull its ends to zoom. Done 2026-09-29: drawn on the ribbon's canvas under the lanes (`StudioTimelineRibbon._draw_bar`, `StudioTimeline.scroll_to` / `pull_end`); a press beside the window jumps there, the wheel over it scrolls; checked with `checks/shot_studio_scrollbar.gd`.
- [x] 12. Draw the floor grid (1 m lines); the setting exists (`StudioSettings.floor_grid`) but nothing draws it. Done 2026-09-29: `studio/tools/floor_grid.gd`, checked with `checks/shot_studio_floor_grid.gd`.
- [x] 13. Desktop drops land too far away: a card lands on the floor under the cursor, with its distance shown. Done 2026-09-29: `StudioAssetDrop.aim` lets the floor win past the main screen; `studio/tools/drop_preview.gd` shows the outline, footprint and distance; checked with `checks/shot_studio_drop.gd`.
- [ ] 14. Groups: make and animate groups in Studio (the format has spawn parents already).
- [ ] 15. Outliner panel: the piece's objects as a tree; select, group (Ctrl+G), ungroup, drag into a group. Its wrist tile goes where *Key it* is on page 1 (`StudioWristPalette.PAGES`), as in the mockup.
- [ ] 16. Make motion paths obvious (keys and times; maybe faint paths for every animated object).
- [ ] 17. Shadertoy tab on the shelf (search or paste a link; a shader becomes a layer or an effect).
- [x] 18. Animated previews on layer and effect cards (on hover on the desktop, while the shelf is open in the headset). Done 2026-09-29 in a55be4b: vertex cards too; `StudioThumbnailer.loop` (20 frames on the preview's own clock, cached as a strip), played by `StudioAssetShelf`; `test_card_loops`, checked with `checks/shot_studio_loops.gd`, render `docs/studio/shelf_loops.png`.
- [ ] 19. GPU cost readout per object, layer and effect, and a benchmark that plays the piece and lists the heaviest moments.
- [x] 20. Catch up with the player: list the player features Studio's UI doesn't use yet (e.g. Blend in the inspector) and add them. Done 2026-09-29: the list is in the plan (*To do* 9), both ways. Studio gained Blend and Fit to video, `hint_enum` params as choices, image params (they broke the inspector; picked images are copied into the piece's `images/`), Video as a layer source, the script's camera effects (`$camera`: inspector, Camera fx lane, keys) and Reload shaders; the player gained colour params in the Camera tab (and a layer's colours from a config), and string keys hold. `tests/test_studio_catch_up.gd`, checked with `checks/shot_studio_catch_up.gd` and `shot_player_colours.gd`; renders `docs/studio/catch_up_*.png`, `docs/player/colour_params.png`. Follow-ups: 53–57.
- [x] 21. ↺ on the Config tab's rows (changes the player's tab too). Done 2026-09-29: every Config row (`PlayerSettings.is_default` / `reset`; the renderer back to the project's driver), and the Camera tab's placement sliders (Size … Resolution, Opacity with Blend), which had none either; `tests/test_player_settings.gd`, checked with `checks/shot_ui.gd`.
- [x] 22. The shelf gets squeezed to about 120 px at 1280 × 720, so no card row shows. Done 2026-09-29: the user said desktop Studio can just run at 1080, so it opens its window at 1920 × 1080 (maximized on a smaller screen: 1920 × 1009 under a taskbar still shows two card rows); `Studio._size_window`.
- [ ] 23. Looks: rename and delete in Studio, looks for a group with its children, keyframes in a look.
- [ ] 24. External changes to an open piece (e.g. a Godot export): offer *reload* or *keep mine*.
- [ ] 25. "Save as".
- [ ] 26. Keep the autosave and backups in a hidden folder rather than next to the piece.
- [ ] 27. Ghosts (next-key boxes) for objects that aren't selected; hover highlights on headset panel buttons.
- [ ] 28. Haptic detents on inspector sliders and clicks on panels.
- [ ] 29. Controls: the controller picture (pointing at a button shows what it does), and named binding profiles.
- [ ] 30. Track down the segfault of `drive_studio_m4.gd` / `m6` in the user's working copy (when GoZen closes the piece's `song.wav`). 2026-09-29: now reproduces on a clean `master` here too (`HEADLESS=1 tools/local/run.sh checks/drive_studio_m4.gd`, every run), so it isn't the working copy.
- [ ] 52. Bring Studio's UI in line with the mockups (`docs/studio/*.svg`, `docs/studio/todo/`): the user says it still looks a lot different (2026-09-28). Compare panel by panel with renders; 8–11 and 15 are parts of it.
- [ ] 53. Looks carry picked images: a look whose config names an image (`images/…`, relative to the piece) should copy it into the library's `images/` and name it from there, as it does shaders (`StudioLooks`).
- [ ] 54. The video's layout (field of view, stereo, eye order) as part of a piece (a format addition, e.g. `media.layout`) and in Studio's inspector or menu: now Studio and a script go by the file name, while the player's Camera tab can override it for itself.
- [ ] 55. Bring a player preset (its layers, effects and camera effect) into a piece, or offer presets as looks on the shelf.
- [ ] 56. The headset inspector cuts "Render scale" to "Render sca" (its label column); check the other long labels there too.

## Player

- [ ] 31. An error dialog (or at least a visible message) when a script fails to load; now only the status line says so.
- [ ] 32. `--windowed` command-line option.
- [ ] 33. Controller models or markers in VR (only the laser shows).
- [ ] 34. Leaving VR during a fade or a cut.
- [ ] 35. Camera effects: several at once (chaining), feedback trails, Shadertoy `mainImage` code as a camera effect.
- [ ] 36. 3D shaders: `depthImage` and a Depth vertex effect (`docs/3d_shaders.md`).
- [ ] 57. Previews in the Camera tab's shader and effect pickers, as Studio's shelf has (`StudioThumbnailer`); the pickers are names only.

## Addon and example pieces

- [ ] 37. Export a despawn's fade `transition` (the exporter writes a plain despawn).
- [ ] 38. `vr_teleport` from the addon, and multiple animations / clip chaining.
- [ ] 39. Live sync: the Animation panel's playhead is moved through an unexposed editor control (`live_sync.gd`, the time SpinBox); a Godot update could break it.
- [ ] 40. Live sync: a seek while the player's video is still opening reports t=0, so the editor's playhead blips to 0.
- [ ] 41. Re-export `scripts/forest_tunnel/video.json` from its project (still format 1 with baked curves).

## Needs a headset (Quest 3)

- [ ] 42. The player's checklist: wrist HUD buttons, laser clicks in every menu tab, cuts with their fades, entering and leaving VR.
- [ ] 43. Studio's pointer UI: wrist palette, inspector (sliders, colour wheel, effect drag), timeline, shelf (carrying cards), menu (holding ≡).
- [ ] 44. Studio's hands and flight: grabbing, two-hand scale / turn, snap turn, flight speed, the miniature's scale, carrying path keys.
- [ ] 45. Rides: the rig following a ride, the height offset, how it feels, the comfort vignette, keying the viewer from a real head pose.
- [ ] 46. Left-handed mode: the left laser on panels, the mirrored wrist panel, the mirrored sticks.
- [ ] 47. Tune the haptic strengths and lengths, and check the Quest runtime plays the short pulses.
- [ ] 48. Panel sharpness and distances on the Quest 3.
- [ ] 49. Camera effects per eye (multiview), and their frame-time cost.
- [ ] 50. forest_tunnel comfort: the fades, and whether the columns' fly-by at 68–76 s is too close.
- [ ] 51. M8's test: a first-time user places, keys and plays back a screen in 10 minutes unaided.
