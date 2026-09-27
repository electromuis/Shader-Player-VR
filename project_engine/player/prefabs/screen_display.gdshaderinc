// Display pass for the Screen prefab. ScreenGeometry.build_shader makes the
// actual shader: `shader_type spatial`, this include, then the vertex
// effects and the surface (renamed so they can't clash) and a vertex() that
// runs them in order. See screen_geometry.gd.
//
// Samples either the raw video texture (passthrough) or the artist-shader
// output by the mesh UVs; the surface decides where each UV sits in space.
//   stereo 0 = mono, 1 = side-by-side (left eye = left half),
//          2 = top-bottom (left eye = top half)
//   swap_eyes: the right eye gets the left half (right-eye-first files)
// Non-XR rendering reports VIEW_INDEX 0, so desktop shows the left eye.
//
// frame_tex's alpha (straight, not premultiplied) is the screen's
// transparency; effects such as Key black and Oval mask set it upstream.
// eyes_split: effects already ran per eye (Screen._build_chains), so
// frame_tex is the left eye and frame_tex_right the right, each whole —
// no stereo UV split here.
//
// opacity (0..1) fades the screen as a whole. At infinity too: there the
// screen draws before every other transparent thing (Screen sets its
// render_priority), so it never paints over UI panels and the environment's
// skybox shows through where it's see-through.

uniform sampler2D frame_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D frame_tex_right : source_color, filter_linear, repeat_disable;
uniform bool eyes_split = false;
uniform int stereo = 0;
uniform bool swap_eyes = false;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// Geometry inputs for the vertex effects and the surface (Screen sets them).
// The unpadded picture's half size in mesh units (the margin grows the mesh
// past it).
uniform vec2 picture_half = vec2(16.0, 9.0);
// The quad mesh's half size in mesh units (screen.tscn).
const vec2 MESH_HALF = vec2(16.0, 9.0);
// 0 = fixed, 1 = around the viewer, 2 = at infinity (see ScreenGeometry).
uniform int placement = 0;
// Metres from the screen's centre to the viewer's eye (at infinity: the
// radius of the camera-centred surface).
uniform float viewer_distance = 8.0;
// Audio for vertex effects: level, bass, mids, highs.
uniform vec4 vfx_audio = vec4(0.0);

// Audio `band` for vertex effects: 0 = overall level, 1 = bass, 2 = mids,
// 3 = highs.
float vfx_band(int band) {
	return band <= 0 ? vfx_audio.x : band == 1 ? vfx_audio.y : band == 2 ? vfx_audio.z : vfx_audio.w;
}

// `amount` scaled by the audio: `audio` 0 = steady, 1 = fully driven by
// `band` (silent = 0).
float vfx_react(float amount, float audio, int band) {
	return amount * mix(1.0, vfx_band(band), clamp(audio, 0.0, 1.0));
}


void fragment() {
	vec2 uv = UV;
	bool right = (VIEW_INDEX == VIEW_RIGHT) != swap_eyes;
	vec4 c;
	if (eyes_split) {
		c = right ? texture(frame_tex_right, uv) : texture(frame_tex, uv);
	} else {
		float eye = right ? 1.0 : 0.0;
		if (stereo == 1) {
			uv.x = clamp(uv.x, 0.0, 1.0) * 0.5 + 0.5 * eye;
		} else if (stereo == 2) {
			uv.y = clamp(uv.y, 0.0, 1.0) * 0.5 + 0.5 * eye;
		}
		c = texture(frame_tex, uv);
	}
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity;
}
