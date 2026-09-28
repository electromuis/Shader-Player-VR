// Display pass for the Screen prefab. ScreenGeometry.build_shader makes the
// actual shader: `shader_type spatial`, this include, then the vertex
// effects and the surface (renamed so they can't clash) and a vertex() that
// runs them in order. See screen_geometry.gd. For a 3D layer shader
// (mainVR) its code comes first, with SHADERTOY_VR defined, and the
// fragment() below calls it instead of sampling frame_tex.
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
//
// display_blend: how the picture goes over what's behind it. The shader
// blends premultiplied (blend_premul_alpha: out = src + (1 - src.a) × dst),
// which covers all three with one shader:
//   0 normal — alpha blending by the picture's alpha
//   1 add    — light added to what's behind: black adds nothing, and it can
//              only brighten (neon, glow)
//   2 black transparent — alpha is the brightest channel: black is see-
//              through, saturated colours stay solid (Key black at blend
//              time, with no 8-bit pass losing the dark end)
// Over Quest passthrough, whose compositor takes the frame as
// premultiplied, add and black transparent work the same way.

uniform sampler2D frame_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D frame_tex_right : source_color, filter_linear, repeat_disable;
uniform bool eyes_split = false;
uniform int stereo = 0;
uniform bool swap_eyes = false;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int display_blend = 0;

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

// Premultiplied colour and alpha for straight `rgb` at alpha `a`, by
// display_blend, faded by opacity.
vec4 display_out(vec3 rgb, float a) {
	vec3 c = rgb * a;
	float alpha = a;
	if (display_blend == 1) {
		alpha = 0.0;
	} else if (display_blend == 2) {
		alpha = clamp(max(max(rgb.r, rgb.g), rgb.b), 0.0, 1.0) * a;
	}
	return vec4(c, alpha) * opacity;
}


#ifdef SHADERTOY_VR
// A 3D layer shader (its code pasted in before this include, see
// screen_shader_code.gd): mainVR gets this eye's ray through this point of
// the surface, in metres in the screen's own frame (x right, y up, z toward
// the viewer, scale left out; the screen's centre at the origin, or the
// camera at infinity), so the screen is a window into the shader's world
// with real stereo and head parallax. With SHADERTOY_VR_DEPTH its
// fragDepth (metres along the ray; large for a miss) becomes DEPTH, so
// other things sit in front of or inside that world. The picture is
// opaque (fragColor.a is ignored, as on Shadertoy), then display_blend.
void fragment() {
	vec3 eye = (INV_VIEW_MATRIX * vec4(EYE_OFFSET, 1.0)).xyz;
	vec3 point = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat3 frame = mat3(MODEL_MATRIX[0].xyz / s.x, MODEL_MATRIX[1].xyz / s.y, MODEL_MATRIX[2].xyz / s.z);
	vec3 origin = placement == 2 ? CAMERA_POSITION_WORLD : MODEL_MATRIX[3].xyz;
	// v * frame = transpose(frame) * v: world to the screen's frame.
	vec3 ray_ori = (eye - origin) * frame;
	vec3 ray_dir = normalize((point - eye) * frame);
	vec2 frag_coord = vec2(UV.x, 1.0 - UV.y) * iResolution.xy;
	vec4 color = vec4(0.0, 0.0, 0.0, 1.0);
#ifdef SHADERTOY_VR_DEPTH
	float depth = 1e5;
	mainVR(color, depth, frag_coord, ray_ori, ray_dir);
	vec3 hit = eye + frame * (ray_dir * max(depth, 0.0));
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(hit, 1.0));
	float z = clip.z / clip.w;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	z = z * 0.5 + 0.5;
#endif
	DEPTH = clamp(z, 0.0, 1.0);
#else
	mainVR(color, frag_coord, ray_ori, ray_dir);
#endif
	// Shadertoy colours are sRGB, like the flat path's frame_tex
	// (source_color): to linear.
	vec3 rgb = clamp(color.rgb, 0.0, 1.0);
	rgb = mix(rgb / 12.92, pow((rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), rgb));
	vec4 out_color = display_out(rgb, 1.0);
	ALBEDO = out_color.rgb;
	ALPHA = out_color.a;
}
#else
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
	vec4 out_color = display_out(c.rgb, c.a);
	ALBEDO = out_color.rgb;
	ALPHA = out_color.a;
}
#endif
