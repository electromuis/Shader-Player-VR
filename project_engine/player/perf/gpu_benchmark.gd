class_name GpuBenchmark
extends RefCounted

## Plays the piece through as fast as it draws and lists the heaviest
## moments: steps the playhead across the whole piece (paused, so the sound
## doesn't stutter), lets each step settle for a few frames and times it
## with GpuCost (every pass, and the view). Then puts the playhead and play
## state back as they were.
##
## heaviest() groups the steps over the frame budget into moments (from–to,
## the peak, the parts that cost most there); when nothing goes over, the
## few heaviest steps.

signal progress(fraction: float)
signal finished(report: Dictionary)

## At most this many seconds between steps, and at most MAX_STEPS steps
## (a long piece gets coarser ones).
const STEP := 1.0
const MAX_STEPS := 240
## Frames after a seek before timing (the video frame and GPU times lag),
## then frames timed per step.
const SETTLE := 6
const FRAMES := 4
## Moments listed.
const TOP := 3

var running := false
var _cancel := false


## Benchmark `stage`'s piece with `cost`. The report: {samples: [{t, ms,
## parts: {key: ms}}], budget_ms, moments (heaviest()), peak_ms, mean_ms,
## cancelled}.
func run(stage: Stage, cost: GpuCost) -> Dictionary:
	var report := {"samples": [], "budget_ms": cost.budget_ms(), "moments": [], "peak_ms": 0.0,
			"mean_ms": 0.0, "cancelled": false}
	var duration := stage.runner.effective_duration()
	if running or duration <= 0.0:
		finished.emit(report)
		return report
	running = true
	_cancel = false
	var tree := cost.get_tree()
	var was_at := stage.runner.playhead
	var was_playing := stage.runner.playing
	stage.runner.pause()
	cost.set_active("benchmark", true)
	var steps := clampi(ceili(duration / STEP), 1, MAX_STEPS)
	var samples: Array[Dictionary] = []
	var labels: Dictionary = {}  # every part seen, also ones gone by the end
	for i in steps + 1:
		if _cancel:
			break
		var t := minf(duration, duration * i / steps)
		stage.seek_to(t)
		for f in SETTLE:
			await tree.process_frame
		var sum := 0.0
		var parts_sum: Dictionary = {}
		for f in FRAMES:
			await tree.process_frame
			sum += cost.frame_ms
			for key in cost.frame_parts:
				parts_sum[key] = float(parts_sum.get(key, 0.0)) + cost.frame_parts[key]
		for key in parts_sum:
			parts_sum[key] = parts_sum[key] / FRAMES
		samples.append({"t": t, "ms": sum / FRAMES, "parts": parts_sum})
		labels.merge(cost.parts)
		progress.emit(float(i + 1) / (steps + 1))
	cost.set_active("benchmark", false)
	stage.seek_to(was_at)
	if was_playing:
		stage.runner.play()
	running = false
	report.samples = samples
	report.cancelled = _cancel
	report.moments = heaviest(samples, report.budget_ms, labels)
	for s in samples:
		report.peak_ms = maxf(report.peak_ms, s.ms)
		report.mean_ms += s.ms / samples.size()
	finished.emit(report)
	return report


func cancel() -> void:
	_cancel = true


## The heaviest moments of `samples` ([{t, ms, parts}], in time order):
## runs of steps over `budget` merged into one moment each, heaviest peak
## first; with none over, the TOP heaviest steps. Each: {from, to, peak_ms,
## over (bool), names: the two parts costing most at the peak, by their
## `labels` (key -> {label}; "view" is the 3D view)}.
static func heaviest(samples: Array, budget: float, labels: Dictionary = {}) -> Array[Dictionary]:
	var moments: Array[Dictionary] = []
	var run: Dictionary = {}
	for s in samples:
		if s.ms > budget:
			if run.is_empty():
				run = {"from": s.t, "to": s.t, "peak_ms": s.ms, "over": true, "peak": s}
			else:
				run.to = s.t
				if s.ms > run.peak_ms:
					run.peak_ms = s.ms
					run.peak = s
		elif not run.is_empty():
			moments.append(run)
			run = {}
	if not run.is_empty():
		moments.append(run)
	if moments.is_empty():
		for s in samples:
			moments.append({"from": s.t, "to": s.t, "peak_ms": s.ms, "over": false, "peak": s})
	moments.sort_custom(func(a, b): return a.peak_ms > b.peak_ms)
	moments = moments.slice(0, TOP)
	for m in moments:
		m.names = _top_parts(m.peak.get("parts", {}), labels)
		m.erase("peak")
	return moments


static func _top_parts(parts: Dictionary, labels: Dictionary) -> Array[String]:
	var keys: Array = parts.keys()
	keys.sort_custom(func(a, b): return parts[a] > parts[b])
	var out: Array[String] = []
	for key in keys.slice(0, 2):
		if key == GpuCost.VIEW:
			out.append("3D view")
		else:
			out.append(String(labels.get(key, {}).get("label", key)))
	return out


## "1:28–1:43 (tunnel + Glow) 15.8 ms · over budget", for a moment.
static func describe(m: Dictionary) -> String:
	var when := clock(m.from) if is_equal_approx(m.from, m.to) else "%s–%s" % [clock(m.from), clock(m.to)]
	var names := " + ".join(m.names)
	return "%s (%s) %.1f ms%s" % [when, names, m.peak_ms, " · over budget" if m.over else ""]


static func clock(t: float) -> String:
	var s := int(floor(t))
	return "%d:%02d" % [s / 60, s % 60]
