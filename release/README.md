# Player

A VR video player with sound-reactive shader layers and effects. It plays ordinary videos, including 180°/360° and 3D ones, and scripted videos, where a `.json` script moves the screen, spawns objects and animates shaders in time with the music.

It works with or without a headset. If an OpenXR headset (SteamVR, Oculus/Meta, WMR, …) is connected when the player starts, it goes straight into VR. Otherwise it runs in a desktop window. Start it with `Player.exe -- --desktop` to stay on the desktop even with a headset connected, and `-- --windowed` to open the window windowed even if you left it fullscreen (F11 still toggles). The player's own options always come after a lone `--`.

## What's in this folder

| Folder / file | What it's for |
|---|---|
| `Player.exe` | The player. Keep `Player.pck` and the `.dll` next to it. |
| `media/` | Your videos. The file browser opens here the first time. It comes with a few samples. |
| `presets/` | Your saved screen presets (`preset_N.json`). Copy them to another install, or back them up. |
| `save/` | Your settings (last folder, view, fullscreen, …). Created when the player first runs. |
| `portable.ini` | Keeps `save/` and `presets/` in this folder. See [Settings](#settings). |
| `shaders/sources/` | Shaders for the **layers**: what gets drawn. |
| `shaders/effects/` | **Effects**: filters on the screen or a layer (masks, blur, glow, crop, …). |
| `shaders/` | The shared include files the shaders above build on. |

Everything in `shaders/` is plain text. Edit it in any text editor, and the player picks up the change the next time you choose that shader or effect.

## Controls

**F2** opens the panel: **Files**, **Network**, **Camera**, **Presets**, **Config** and **Controls**.

| | Desktop | VR |
|---|---|---|
| Play / pause | Space or K | right **A** |
| Seek ±10 s | ← / → | thumbstick left / right |
| Volume | ↑ / ↓ | thumbstick up / down |
| Reset view | R | right stick click |
| Fullscreen | F11 | |
| Hide the play bar | H | |
| Panel | F2 | |

Moving around is off by default, so the thumbsticks can seek and change the volume. Turn it on in **F2 → Config**.

Every button, stick and key here is a default: **F2 → Controls** lists each command and lets you rebind it (hold another button for a combination), and **Left-handed** swaps the hands.

## Playing videos

- **Files** browses your drives. You can also drop a video on the window or on `Player.exe`, use *Open with* in Explorer, or start with `Player.exe -- --script <file>`.
- **Network** lists DLNA/UPnP media servers on your network (Plex, Jellyfin, MiniDLNA, Windows media sharing, …).
- **Source** (how the file is read: flat, 180° or 360°, mono, side-by-side or top-bottom, and swapped eyes) is read from the file name (`_180`, `_360`, `_LR` / `_SBS`, `_RL`, `_TB` / `_OU`, …). If it guesses wrong, change it in **F2 → Camera**. 180° and 360° videos play on a dome around you.
- **Scripted videos:** put a `.json` with the same name next to the video (`clip.mp4` + `clip.json`) and it plays with that script.
- **Timecode:** a Whirligig-compatible server runs on `127.0.0.1:2000` for MultiFunPlayer / ScriptPlayer. `-- --whirligig-port N` changes the port (0 turns it off) and `-- --whirligig-lan` lets other machines connect.
- **DaVinci Resolve:** copy `resolve/VJ Sync.py` into Resolve's `Scripts/Utility` folder and run it from **Workspace → Scripts**. The player then follows Resolve's playhead, and timeline markers can become script events. See `resolve/README.md`.

## Video decoder and renderer

**F2 → Config → Video decoder**: **FFmpeg** (the default) plays every format, including network streams. **Hardware** uses Windows' own decoder for local H.264 / HEVC MP4s, which is lighter on the CPU. A video the chosen decoder can't play uses the other one. **Renderer** switches between Direct3D 12 and Vulkan (in case a headset runtime has trouble with one), from the next start.

## Screen, layers and presets

In **F2 → Camera**, set the screen's size, distance, height and tilt, and its **surface**:

- **Pillow** bends the screen left-to-right and top-to-bottom (0° / 0° is flat). The picture never distorts.
- **Dome** puts the picture on part of a sphere. Set how wide it is; the height follows the picture's shape unless you turn off *auto height*. **Around viewer** puts you at the centre of the dome, and **At infinity** is the setting for 180° / 360° video.

**Vertex effects** move the surface itself: **Ripple**, **Twist**, **Bulge**, **Spin** and **Pulse**, each of which can follow the music.

**Layers** adds sound-reactive shader layers in front of or behind the video. Pick a layer under **Adjust**, choose its shader, and position it the same way as the screen. **Lock to screen** keeps a layer centred on the video.

Next to **Opacity**, **Blend** sets how the screen or a layer goes over what's behind it. **Add (light)** adds its light, so black disappears and it glows. **Black transparent** makes black see-through and keeps bright colours solid. Both work for any shader, 3D ones too.

The screen and every layer have an **effect list**: **+ Effect** adds one, **−** removes it, and effects run top to bottom. Built in: Blur, Key black, Oval mask, Edge blur, Glow, Crop, Rounded corners, Keep center, Alpha threshold, Image overlay and Match video brightness, plus looks such as Kaleidoscope, Hue cycle, Neon edges and Pop-art grid. Effects that spread past the picture (Blur, Glow) get room around it by themselves.

**Save** stores everything (screen, layers, effects and their settings) as a preset in `presets/`. Preset 0, *Script (defaults)*, is locked. Scripted videos use it so they look the way they were made.

## Tweaking and adding shaders

The shipped shaders are in `shaders/sources/` and `shaders/effects/`. Change a number, save, and pick the shader again in the player. Your presets keep working because they refer to the built-in shader, not to the file. If you break a built-in beyond repair, delete its file and the player falls back to its own copy.

To **add** a shader, put a new file in `shaders/sources/` (layers) or `shaders/effects/` (effects), or a `.gdshaderinc` in `shaders/surfaces/` (surfaces) or `shaders/vertex/` (vertex effects). Its file name becomes its name in the list.

- **Shadertoy code** works as-is: save the `mainImage` function as a `.glsl` file in `shaders/sources/`. `iTime`, `iResolution` and `iChannel0` are supported. `iChannel0` is the music, as Shadertoy's 512×2 spectrum and waveform texture. Texture channels work through `// @iChannel1 image` (see below). Mouse, keyboard and multipass buffers aren't supported.
- **3D shaders:** add Shadertoy's VR function, `mainVR(out vec4 fragColor, in vec2 fragCoord, in vec3 fragRayOri, in vec3 fragRayDir)`, and the shader renders in 3D: per eye, with depth and parallax when you move your head, as if the screen were a window. The ray is in metres, with the screen's centre at 0 and you on +z. Add `out float fragDepth` after `fragColor` (metres along the ray) so other things can sit in front of or inside it. Effects don't apply to 3D shaders. See the Gyroid tunnel for an example.
- **Godot shaders** (`.gdshader`, `shader_type canvas_item;`) work too. Include `../shadertoy_prelude.gdshaderinc` for the same inputs plus `audio_bass`, `audio_mid`, `audio_high` and `audio_level`. Copy one of the built-ins as a starting point.
- **Effects** are `.gdshader` files that include `../effect_prelude.gdshaderinc` and sample `input_tex` at `UV`. `display_aspect` is the screen's width divided by its height. The built-in effects are good examples.
- The built-ins include `res://player/visualizer/…` paths. These point at the files in this `shaders/` folder, so editing a prelude here changes every shader that uses it.

**Controls from the shader:**

- Every `uniform float` or `uniform int` with a `hint_range(min, max[, step])` gets a slider, and every `uniform bool` gets a checkbox. They're saved in presets.
- `// @resolution 1024x1024` sets the size a layer renders at, and the layer takes that shape. The default is 960×540. `// @resolution 270` gives only the height; the width follows the video's shape.
- `// @iChannel1 video` (any of iChannel0–3) feeds that channel the playing video's frame. The layer then takes the video's shape and 3D layout.
- `// @iChannel1 image` gives that channel an image picker instead. In a `.gdshader` (layer or effect), every extra `uniform sampler2D` gets one too; add `hint_default_transparent` so the shader can tell when no image is picked. The picked image is saved in presets.

## Images

Put `.png`, `.jpg` or `.webp` files in an `images` folder next to `Player.exe`, and they show up in the image pickers of shaders that take a texture (see above). **Image pulse** (a layer) moves a picture with the music: the bass punches it in, the mids ripple it and the highs split its colours. **Image overlay** (an effect) puts a picture over a layer or the video, as a logo, a frame or a mask. After you edit an image file, press **Reload shaders** to read it again.

## Skyboxes

The background is black by default. Other options are in **F2 → Config**, including any panorama images you put in a `skyboxes` folder next to `Player.exe`. On Quest, **Passthrough** shows your room behind everything; set a layer's **Blend** to Add or Black transparent to draw shaders over it.

## Settings

Because of `portable.ini`, the player keeps everything it saves in this folder: settings in `save/` and presets in `presets/`. Copy the whole folder to a USB stick or another PC and it comes along. Delete `save/` to reset your settings.

If you'd rather have your saves in your user profile, delete `portable.ini`. The player then uses `%APPDATA%\Godot\app_userdata\Scripted VJ Video Player\` for settings and its `presets` subfolder for presets, and ignores `save/` and `presets/` here. Move your preset files over first if you want to keep them. With `portable.ini` removed, extra shaders, skyboxes and images can also go in the `shaders`, `skyboxes` and `images` subfolders there.
