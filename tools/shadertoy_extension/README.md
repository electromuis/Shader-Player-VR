# Shadertoy → VJ Godot (Chrome extension)

Adds a **⇩ Send to Godot** button to [shadertoy.com](https://www.shadertoy.com):
next to a shader's title, and on each card in lists (browse, search,
profiles, playlists; it shows when you hover). The shader goes to the VJ
editor's **Shadertoy** dock (the bottom panel), ready to add as a layer, or
to VR Studio's shelf (its **Shadertoy** tab), as a layer or an effect.

## Install

1. Open `chrome://extensions` and switch on **Developer mode**.
2. **Load unpacked** → pick this folder (`tools/shadertoy_extension`).
3. Open Godot with the VJ editor addon, or Studio (each listens while it
   runs).

Edge and other Chromium browsers work the same way.

## What the button says

- **✓ In Godot**: it runs as a layer (the tooltip lists what's lost, like
  textures or the mouse).
- **✎ Sent, needs editing**: it's in Godot but won't compile until the
  `.gdshader` is edited (the dock says what).
- **✕ Sent, but won't run**: it needs several passes (buffers), which a
  layer can't do. It's kept in the collection anyway.
- **✕ Godot isn't running**: open the VJ editor or Studio and click again.
- **✕ Shadertoy is busy**: the site limits how often shaders can be
  fetched; wait a minute.

## How it works

Shadertoy's API needs a paid account and its site blocks programs that
aren't a browser, so the shader is fetched by the page itself: the content
script asks `/shadertoy` for the shader's JSON (what the site's own player
loads) and `/media/shaders/<id>.jpg` for its thumbnail. `background.js`
posts both to Godot's `ShadertoyReceiver` on `127.0.0.1`, the first of
ports 47811–47815 that answers `GET /vj/ping` (with both the editor and
Studio open, the first one started gets it; they share the collection, so
both see it). A page opened as `/view/<id>#vj-send` (Studio's **Paste**
with a link) sends itself without a click. Godot only accepts posts from
extensions (a web page's are refused), and only on `127.0.0.1`.

Shaders land in `%APPDATA%/VJ Shadertoy` (one JSON and thumbnail each),
shared by every project and Studio.

Shadertoy shaders are their authors' work; the default licence is CC
BY-NC-SA 3.0 (credit, non-commercial, share alike) unless the page says
otherwise. The imported `.gdshader` names the author and the page.
