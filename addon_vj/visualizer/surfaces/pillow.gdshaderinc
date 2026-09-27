// @title Pillow
// Pillow: bends the screen left-to-right (arc_x) and top-to-bottom (arc_y);
// 0 / 0 is flat, arc_x alone a cylinder. The arcs span the picture itself
// and are true circles: bent left-to-right first, then that curved sheet is
// bent top-to-bottom. Around the viewer both take the viewing distance as
// their radius, which wraps the screen onto a sphere around the eye, so the
// arcs follow from the size.
// @hint Bends the screen left-to-right, then top-to-bottom.
// @placements fixed around
// @unused around arc_x arc_y
uniform float arc_x : hint_range(0.0, 360.0, 1.0) = 0.0;
uniform float arc_y : hint_range(0.0, 180.0, 1.0) = 0.0;

// Radius of a bend spanning `arc` degrees over `half_len` metres each side
// of the centre (0 = flat).
float radius(float arc, float half_len) {
	if (placement == 1) {
		return viewer_distance;
	}
	return arc > 0.01 ? half_len / radians(arc * 0.5) : 0.0;
}

vec3 surface(vec3 p, vec2 uv, vec2 half_m) {
	vec3 q = p;
	float rx = radius(arc_x, half_m.x);
	float ry = radius(arc_y, half_m.y);
	if (rx > 0.0) {
		// p.z pushes along the bent surface's normal.
		float a = p.x / rx;
		q.x = (rx - p.z) * sin(a);
		q.z = rx - (rx - p.z) * cos(a);
	}
	if (ry > 0.0) {
		// Bend the already bent sheet about a horizontal axis.
		float a = p.y / ry;
		q.y = (ry - q.z) * sin(a);
		q.z = ry - (ry - q.z) * cos(a);
	}
	return q;
}
