# 3D shader layers (design note)

Layer shaders are flat today: `mainImage` renders into a texture that a screen shows, so both eyes see the same picture. This note collects the plan for making them 3D, per eye. **`mainVR` (true 3D) is built**; the depth map (`depthImage`) is not yet. Where the build settled an open question, it's noted below.

## Three entry points; the function is the flag

A shader declares what it can do by the functions it defines. No `@depthmode` header is needed. This follows how effects are detected (by `input_tex` in the code), and leaves the header for metadata like `@title`.

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord)              // flat, as now
void depthImage(out float fragDepth, in vec2 fragCoord)            // + depth map
void mainVR(out vec4 fragColor, out float fragDepth, in vec2 fragCoord,
            in vec3 fragRayOri, in vec3 fragRayDir)                // true 3D
```

Plain Shadertoy code with only `mainImage` keeps working unchanged.

| | Entry point | Where it runs | 3D from |
|---|---|---|---|
| Flat | `mainImage` | texture, as now | nothing |
| Depth map | `mainImage` + `depthImage` | texture + small depth pass | the screen's mesh pushed by depth |
| True 3D | `mainVR` | the screen's 3D pass, per eye | real per-eye rays; depth-buffer occlusion |

## Depth map: `depthImage`

- **Depth needs its own pass.** A render target holds at most 4 channels, and a `canvas_item` shader can only write one target. So a "vec5" colour plus depth can't come out of one pass, and RGBA stays fully the shader's own.
- **A separate function, not an extra `out` on `mainImage`.** The depth pass then skips the colour work, while helpers like a raymarcher's `map()` can be shared between the two.
- **The depth pass runs at low resolution,** about 1/4 size. The mesh only samples depth at its vertices, which are far coarser than pixels, so even raymarchers pay only a few percent extra.
- **Same mechanism as the effects' prepass.** The shader runs a second time with a flag that makes the wrapper call `depthImage` and write the result, like `uniform bool prepass`.
- **Effects can read and change depth** the same way: `depth_tex` in, their own depth pass out. For example "Depth from brightness" (the way to give video depth), a beat pulse on depth, or blurring depth to soften stretched edges. Effects that don't touch depth pass it through.
- **A "Depth" vertex effect consumes it** (a `deform()` in `visualizer/vertex/`, like Bulge), pushing the mesh toward or away from the viewer. The VR camera then gives correct per-eye perspective and parallax when you move your head.
- **Writing depth alone isn't enough here.** For a flat screen it only changes occlusion; the pixels don't move, so it looks exactly as flat. The mesh has to move.
- **Limits:**
  - Sharp depth jumps stretch the mesh into "rubber sheet" edges; blurring the depth softens them.
  - The mesh must be dense enough to follow the depth. The current grid density hasn't been checked.
  - It's one depth per pixel, so volumetric shaders (the nebula) become a relief, not a volume.
- **Open question: units.** The suggestion is metres from the screen surface, positive toward the viewer, so depth means the same at any screen size, with one "depth scale" slider on the vertex effect. The alternative is 0..1.

## True 3D: `mainVR`

- **Prior art: Shadertoy's own VR entry point,** `mainVR(out vec4 fragColor, in vec2 fragCoord, in vec3 fragRayOri, in vec3 fragRayDir)`. The host gives each pixel the ray from that eye, so a raymarcher marches from `fragRayOri` along `fragRayDir` with no eye offsets or FOV maths. Existing Shadertoy VR shaders would work when pasted. We add `out float fragDepth`.
- **It runs directly on the screen's mesh in the 3D pass,** as part of the screen's display shader, not into a texture:
  - **Rays per eye:** Godot's 3D fragment shader knows the current eye (`VIEW_INDEX`) and its position, so the ray per pixel is the eye to this point on the screen.
  - **No extra passes:** XR multiview renders both eyes in one pass, with no side-by-side texture.
  - **Live eye positions** give stereo and correct parallax when you move your head. The screen acts as a window into the shader's world.
  - **Works with the screen's shape:** the ray starts where the mesh actually is, so it works on the Pillow and Dome surfaces and with vertex effects.
- **`fragDepth` goes to Godot's `DEPTH` output** (converted from metres along the ray), and the GPU's depth test does the rest. Other screens, UI panels and controllers then sit correctly in front of or inside the shader's world. The per-eye 3D look itself comes from the rays; depth is for occlusion.
- **Keep a `mainImage` alongside** for the desktop view and thumbnails, as Shadertoy VR shaders usually do.
- **Costs:**
  - It renders at the headset's per-eye resolution, not the layer's `@resolution`, so heavy raymarchers get more expensive. A quality or march-steps slider can compensate.
  - The effect chain works on a texture, so texture effects (Kaleidoscope and the like) don't apply to a `mainVR` layer. Alpha, opacity and vertex effects still do.
- **Ray space (settled):** metres in the screen's own frame (screen at z = 0, viewer on +z, scale left out), matching the vertex effects, so "the tunnel is 3 m deep" means what it says. At infinity the frame is centred on the camera. The ray starts at the eye, as on Shadertoy; a shader that wants the screen as a window starts marching where the ray crosses z = 0 (the gyroid tunnel does).
- **As built:** `VisualizerShaders.is_vr_code` spots `mainVR`; its code goes into the display shader (`screen_shader_code.gd`'s `build`, with `SHADERTOY_VR` defined, and `SHADERTOY_VR_DEPTH` when it has `fragDepth`), and the layer's uniforms go on the display material. Shadertoy's own four-argument `mainVR` works too (no depth written). The picture is opaque, times the layer's opacity.

## Other options considered

- **Side-by-side texture with an `iEye` uniform:** the shader renders both eyes into one double-wide texture and offsets its own camera. It reuses the stereo video path, but it's a fixed viewpoint (no parallax when you move your head), and `mainVR` in the 3D pass does the same job better.
- **Depth in `fragColor.a`:** free for Shadertoy code, which ignores alpha, but it gives up transparency, which the effect chain uses (Key black, Oval mask).

## Suggested order

1. `depthImage` + the Depth vertex effect, tried on the gyroid tunnel (exact depth from the march) and the plasma (invented depth). It's smaller, reuses the prepass mechanism, and also covers video through effects.
2. `mainVR` in the screen's 3D pass, starting with the gyroid tunnel. (Built first after all.)
