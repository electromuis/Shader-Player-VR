# TODO

Open tasks for the player, Studio and the addon. Numbers are permanent: refer to a task by its number, don't renumber, and add new tasks at the end of their section with the next free number. Check a task off (`- [x]`) when it's done, with a few words on where or how (a commit, a file); don't delete it. Details and background for Studio tasks are in `VR Studio — Plan.md` (*To do*, *Known issues*).

## Repo and CI

- [x] 1. Commit and push the docs cleanup of 2026-09-28 (this file, `docs/script_format.md`, the removed original plan, the README / Studio plan updates). Done 2026-09-28, in the commit that added this file.
- [ ] 2. Add the `GOZEN_TOKEN` repository secret (read access to `electromuis/gde_gozen`'s contents) and confirm CI passes on `master`.
- [ ] 3. Confirm the fork's `v9.7-sp4` release has its binaries published (CI and `ci/fetch_gozen.sh` now use it).
- [ ] 4. Delete the unused placeholder plugin `project_engine/addons/vj_editor/` (not enabled; a "Phase 6" stub). SKIP
- [ ] 5. Decide which README the CI packages ship: they copy the developer `README.md`, while `build_release.bat` ships the end-user `release/README.md`.
- [ ] 6. Try Studio as a full exported Windows build (so far only checked with `--export-pack`).
- [x] 7. Make `tests/run.gd` count a test that hits a script error as failed (now it stops there but counts as passed). Done 2026-09-29: the runner registers a `Logger` (`OS.add_logger`) and fails a test during which a GDScript runtime error was logged; all 319 tests still pass.

## Studio

- [ ] 8. Wrist palette to the mockup (`docs/studio/todo/3_wrist.png`): Play / Edit switch, big timecode with duration and bar, a 4 × 3 icon grid, a footer with Save and "autosaved …", a second page for the rest.
- [ ] 9. Minimize (–) on every panel (inspector, shelf, timeline, outliner), folding it to a tab on the wrist.
- [ ] 10. Move panels in VR by their title bar; panels keep their place relative to you as you fly.
- [ ] 11. Timeline scroll bar over the whole piece (with the audio's outline): drag to scroll, pull its ends to zoom.
- [x] 12. Draw the floor grid (1 m lines); the setting exists (`StudioSettings.floor_grid`) but nothing draws it. Done 2026-09-29: `studio/tools/floor_grid.gd`, checked with `checks/shot_studio_floor_grid.gd`.
- [x] 13. Desktop drops land too far away: a card lands on the floor under the cursor, with its distance shown. Done 2026-09-29: `StudioAssetDrop.aim` lets the floor win past the main screen; `studio/tools/drop_preview.gd` shows the outline, footprint and distance; checked with `checks/shot_studio_drop.gd`.
- [ ] 14. Groups: make and animate groups in Studio (the format has spawn parents already).
- [ ] 15. Outliner panel: the piece's objects as a tree; select, group (Ctrl+G), ungroup, drag into a group.
- [ ] 16. Make motion paths obvious (keys and times; maybe faint paths for every animated object).
- [ ] 17. Shadertoy tab on the shelf (search or paste a link; a shader becomes a layer or an effect).
- [ ] 18. Animated previews on layer and effect cards (on hover on the desktop, while the shelf is open in the headset).
- [ ] 19. GPU cost readout per object, layer and effect, and a benchmark that plays the piece and lists the heaviest moments.
- [ ] 20. Catch up with the player: list the player features Studio's UI doesn't use yet (e.g. Blend in the inspector) and add them.
- [ ] 21. ↺ on the Config tab's rows (changes the player's tab too).
- [ ] 22. The shelf gets squeezed to about 120 px at 1280 × 720, so no card row shows.
- [ ] 23. Looks: rename and delete in Studio, looks for a group with its children, keyframes in a look.
- [ ] 24. External changes to an open piece (e.g. a Godot export): offer *reload* or *keep mine*.
- [ ] 25. "Save as".
- [ ] 26. Keep the autosave and backups in a hidden folder rather than next to the piece.
- [ ] 27. Ghosts (next-key boxes) for objects that aren't selected; hover highlights on headset panel buttons.
- [ ] 28. Haptic detents on inspector sliders and clicks on panels.
- [ ] 29. Controls: the controller picture (pointing at a button shows what it does), and named binding profiles.
- [ ] 30. Track down the segfault of `drive_studio_m4.gd` / `m6` in the user's working copy (when GoZen closes the piece's `song.wav`).
- [ ] 52. Bring Studio's UI in line with the mockups (`docs/studio/*.svg`, `docs/studio/todo/`): the user says it still looks a lot different (2026-09-28). Compare panel by panel with renders; 8–11 and 15 are parts of it.

## Player

- [ ] 31. An error dialog (or at least a visible message) when a script fails to load; now only the status line says so.
- [ ] 32. `--windowed` command-line option.
- [ ] 33. Controller models or markers in VR (only the laser shows).
- [ ] 34. Leaving VR during a fade or a cut.
- [ ] 35. Camera effects: several at once (chaining), feedback trails, Shadertoy `mainImage` code as a camera effect.
- [ ] 36. 3D shaders: `depthImage` and a Depth vertex effect (`docs/3d_shaders.md`).

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
