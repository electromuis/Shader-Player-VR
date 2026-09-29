extends SceneTree

## Vanilla test runner. Discovers tests/test_*.gd, invokes every `static func test_*`.
## Run with:
##   Godot_v4.4-stable_win64.exe --headless --path <project> --script res://tests/run.gd

const TESTS_DIR := "res://tests"


## Collects GDScript runtime errors. A script error aborts the test function
## without failing any assertion, so the runner checks this after each test.
class ScriptErrorLogger extends Logger:
	var _mutex := Mutex.new()
	var _errors: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_errors.append("script error: %s (%s:%d, %s)" % [rationale if rationale != "" else code, file, line, function])
		_mutex.unlock()

	func take() -> Array:
		_mutex.lock()
		var out := _errors
		_errors = []
		_mutex.unlock()
		return out


func _init() -> void:
	var total := 0
	var passed := 0
	var failed_names: Array = []
	var script_errors := ScriptErrorLogger.new()
	OS.add_logger(script_errors)
	for suite_path in _discover_suites():
		script_errors.take()
		var script: Script = load(suite_path)
		# A script that doesn't parse still loads (as an empty script): count
		# the suite as one failed test, or its tests would just go missing.
		var load_errors := script_errors.take()
		if script == null or not script.can_instantiate() or not load_errors.is_empty():
			total += 1
			failed_names.append(suite_path)
			print("== %s ==\n  FAIL (doesn't load)" % suite_path)
			for f in load_errors:
				print("     %s" % f)
			continue
		print("== %s ==" % suite_path)
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			total += 1
			var tc := TestCase.new()
			tc.begin(name)
			script_errors.take()
			# Static method call via reflection.
			script.call(name, tc)
			var failures := tc.failures() + script_errors.take()
			if failures.is_empty():
				passed += 1
				print("  PASS %s" % name)
			else:
				failed_names.append("%s::%s" % [suite_path, name])
				print("  FAIL %s" % name)
				for f in failures:
					print("     %s" % f)
	OS.remove_logger(script_errors)
	print("")
	print("Ran %d tests: %d passed, %d failed" % [total, passed, total - passed])
	if failed_names.size() > 0:
		for n in failed_names:
			print("  FAILED %s" % n)
		quit(1)
		return  # quit() only sets the exit code; don't let quit(0) overwrite it
	quit(0)


func _discover_suites() -> Array:
	var out: Array = []
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "":
			break
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			out.append(TESTS_DIR.path_join(f))
	dir.list_dir_end()
	out.sort()
	return out
