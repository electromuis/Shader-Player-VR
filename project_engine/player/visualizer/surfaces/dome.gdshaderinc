// @title Dome
// Dome: the picture on a section of a sphere, arc_x wide, laid out in
// latitude / longitude (the layout 180° / 360° videos use). The sphere never
// distorts; the picture may stretch.
//   auto_height  — the height follows the picture's shape (square pixels);
//                  off, arc_y sets it and the picture stretches to fit
//   keep_row_width — widen rows toward the top and bottom so they keep
//                  their width (the outline becomes a pincushion)
//   straight_rows — lowers the rows toward the equator away from the middle
//                  so, seen from the centre, they run straight instead of
//                  curving up into spiky corners (1 = fully straight; at
//                  180° wide and more the sides pinch toward points)
//   radius       — around the viewer: the sphere's radius in metres; 0 = as
//                  far as the screen is from the viewer
// Fixed, arc_x bends the screen at its own size; around the viewer and at
// infinity the viewer sits at the centre and arc_x is how much of the view
// it covers (the size is unused). Around the viewer the sphere is as big as
// radius says (or the screen's distance); at infinity it's always behind
// everything else, wherever you go (a skybox).
// @hint Arcs are how much of your view it covers. Around the viewer, Radius sets its size (0: the screen's distance); at infinity it's behind everything, like a sky.
// @placements fixed around infinity
// @unused fixed radius
// @unused around size
// @unused infinity size distance height radius
uniform float arc_x : hint_range(0.0, 360.0, 1.0) = 180.0;
uniform bool auto_height = true;
uniform float arc_y : hint_range(0.0, 180.0, 1.0) = 90.0;
uniform bool keep_row_width = false;
uniform float straight_rows : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float radius : hint_range(0.0, 500.0, 0.5) = 0.0;

vec3 surface(vec3 p, vec2 uv, vec2 half_m) {
	float half_lon = radians(arc_x) * 0.5;
	if (half_lon < 0.0001) {
		return p;
	}
	// The sphere's centre (the viewer's eye unless fixed) and radius.
	float centre = placement == 0 ? half_m.x / half_lon : viewer_distance;
	float r = placement == 1 && radius > 0.0 ? radius : centre;
	vec2 f = p.xy / half_m;  // -1..1 across the unpadded picture
	float lon = f.x * half_lon;
	float lat = auto_height ? f.y * half_lon * half_m.y / half_m.x : f.y * radians(arc_y) * 0.5;
	lat = clamp(lat, -PI * 0.5, PI * 0.5);
	if (keep_row_width) {
		lon /= max(cos(lat), 0.05);
	}
	// At most once round: past that (a margin around a wide picture) the
	// quad folds onto the seam and draws nothing, instead of wrapping round
	// the viewer again.
	lon = clamp(lon, -PI, PI);
	// Onto the great circle through the sides' axis: straight from the centre.
	float squeeze = mix(1.0, max(cos(lon), 0.0), straight_rows);
	lat = atan(sin(lat) * squeeze, cos(lat));
	vec3 dir = vec3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon));
	// The centre toward the viewer; p.z pushes along the normal.
	return vec3(0.0, 0.0, centre) + dir * (r - p.z);
}
