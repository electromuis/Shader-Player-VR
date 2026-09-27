// @title Dome
// Dome: the picture on a section of a sphere, arc_x wide, laid out in
// latitude / longitude (the layout 180° / 360° videos use). The sphere never
// distorts; the picture may stretch.
//   auto_height  — the height follows the picture's shape (square pixels);
//                  off, arc_y sets it and the picture stretches to fit
//   keep_row_width — widen rows toward the top and bottom so they keep
//                  their width (the outline becomes a pincushion)
// Fixed, arc_x bends the screen at its own size; around the viewer and at
// infinity the viewer sits at the centre and arc_x is how much of the view
// it covers (the size is unused).
// @hint Arcs are how much of your view it covers; the sphere never distorts, the picture may stretch.
// @placements fixed around infinity
// @unused around size
// @unused infinity size distance height
uniform float arc_x : hint_range(0.0, 360.0, 1.0) = 180.0;
uniform bool auto_height = true;
uniform float arc_y : hint_range(0.0, 180.0, 1.0) = 90.0;
uniform bool keep_row_width = false;

vec3 surface(vec3 p, vec2 uv, vec2 half_m) {
	float half_lon = radians(arc_x) * 0.5;
	if (half_lon < 0.0001) {
		return p;
	}
	float r = placement == 0 ? half_m.x / half_lon : viewer_distance;
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
	vec3 dir = vec3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon));
	// Centre R toward the viewer; p.z pushes along the normal.
	return vec3(0.0, 0.0, r) + dir * (r - p.z);
}
