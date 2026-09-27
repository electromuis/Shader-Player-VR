class_name StudioKeyThinning
extends RefCounted

## Turns a recorded stream (a value sampled every frame) into the fewest
## linear keys that stay within a tolerance of it: Ramer–Douglas–Peucker
## on time and value, where a sample's error is how far the line between
## the kept keys around it misses it, in value, per component (arrays: a
## colour, a position), measured against that component's tolerance.
## The first and last samples are always kept. Numbers are rounded for a
## tidy file: times to 1 ms, values to 5 decimals.

## `samples`: [[t, value]] in time order, a value a number or an array of
## numbers (all the same length). `tolerance`: a number, or one per
## component. Returns keys: [{t, value}].
static func thin(samples: Array, tolerance) -> Array:
	var pts: Array = []
	for s in samples:  # a repeated time (two frames at once) keeps the last
		if not pts.is_empty() and absf(float(s[0]) - float(pts.back()[0])) < 1e-6:
			pts[-1] = s
		else:
			pts.append(s)
	if pts.is_empty():
		return []
	var keep := {0: true, pts.size() - 1: true}
	var stack: Array = [[0, pts.size() - 1]]
	while not stack.is_empty():
		var span: Array = stack.pop_back()
		var a: int = span[0]
		var b: int = span[1]
		if b - a < 2:
			continue
		var worst := -1
		var worst_err := 1.0  # above 1: out of tolerance
		for i in range(a + 1, b):
			var e := _error(pts[a], pts[b], pts[i], tolerance)
			if e > worst_err:
				worst_err = e
				worst = i
		if worst >= 0:
			keep[worst] = true
			stack.append([a, worst])
			stack.append([worst, b])
	var idx := keep.keys()
	idx.sort()
	return idx.map(func(i): return {"t": float("%.3f" % float(pts[i][0])), "value": _tidy(pts[i][1])})


## How far `p` is from the line a–b at its time, in tolerances (the worst
## component).
static func _error(a: Array, b: Array, p: Array, tolerance) -> float:
	var ta := float(a[0])
	var tb := float(b[0])
	var u := (float(p[0]) - ta) / (tb - ta) if tb > ta else 0.0
	var va = a[1]
	var vb = b[1]
	var vp = p[1]
	if typeof(vp) == TYPE_ARRAY:
		var worst := 0.0
		for c in vp.size():
			var line := lerpf(float(va[c]), float(vb[c]), u)
			worst = maxf(worst, absf(float(vp[c]) - line) / _tol(tolerance, c))
		return worst
	return absf(float(vp) - lerpf(float(va), float(vb), u)) / _tol(tolerance, 0)


static func _tol(tolerance, c: int) -> float:
	var t := float(tolerance[mini(c, tolerance.size() - 1)]) if typeof(tolerance) == TYPE_ARRAY else float(tolerance)
	return maxf(t, 1e-9)


static func _tidy(v):
	if typeof(v) == TYPE_ARRAY:
		return v.map(func(x): return float("%.5f" % float(x)))
	if typeof(v) == TYPE_BOOL:
		return v
	return float("%.5f" % float(v))
