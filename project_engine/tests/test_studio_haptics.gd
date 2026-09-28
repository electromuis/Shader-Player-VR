extends RefCounted

## Haptics (M8): StudioHaptics logs every pulse asked for and sends none
## off the headset; the key button is felt (StudioEditTools.felt). Grabs,
## snap detents and let-goes need objects on a live stage (global
## transforms): checks/drive_studio_m8.gd prints those.

const Edits := preload("res://tests/test_studio_edits.gd")


static func test_haptics_log_and_stay_off_the_desktop(tc: TestCase) -> void:
	var h := StudioHaptics.new()
	h.tick("grab", "R")
	h.tick("nonsense", "R")
	h.tick("drop", "M")
	tc.assert_eq(h.kinds_since(0), ["grab:R", "drop:M"], "unknown kinds aren't pulses")
	tc.assert_false(h.log.any(func(e): return e.sent), "no headset, no rig: nothing sent")
	h.in_vr = func(): return true
	h.tick("key", "L")
	tc.assert_false(h.log.back().sent, "no rig to send to")
	for i in StudioHaptics.LOG_SIZE + 5:
		h.tick("snap", "R")
	tc.assert_eq(h.log.size(), StudioHaptics.LOG_SIZE, "the log keeps the last ones")
	tc.assert_eq(h.kinds_since(h.count - 2), ["snap:R", "snap:R"])
	for kind in StudioHaptics.PULSES:
		var p: Array = StudioHaptics.PULSES[kind]
		tc.assert_true(p[0] > 0.0 and p[0] <= 1.0 and p[1] > 0.0 and p[1] <= 0.15, "%s: a short pulse" % kind)
	tc.assert_true(StudioHaptics.PULSES.snap[0] < StudioHaptics.PULSES.key[0], "snaps are lighter than keys")


static func test_the_key_button_is_felt(tc: TestCase) -> void:
	var s := Edits._setup(tc)
	var tools := StudioEditTools.new()
	tools.runner = s[0]
	tools.model = s[1]
	var h := StudioHaptics.new()
	tools.felt.connect(h.tick)
	tc.assert_eq(tools.key_selection(), "", "nothing selected: nothing keyed")
	tc.assert_eq(h.count, 0, "and nothing felt")
	tools.selected = "a"
	tc.assert_true(tools.key_selection() != "")
	tc.assert_eq(h.kinds_since(0), ["key:R"])
	tools.free()
	s[2].free()
