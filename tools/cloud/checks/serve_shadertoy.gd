extends SceneTree

## Runs a ShadertoyReceiver (what the editor's Shadertoy dock and the
## Chrome extension talk through) for $SERVE_SECONDS (default 120) with its
## library in $ST_LIBRARY, and prints each ping and shader it gets, with
## the analysis the extension shows. For testing the extension end to end:
##   ST_LIBRARY=<dir> HEADLESS=1 tools/local/run.sh checks/serve_shadertoy.gd


func _init() -> void:
	var dir := OS.get_environment("ST_LIBRARY")
	if dir == "":
		print("Set ST_LIBRARY.")
		quit(1)
		return
	var seconds := float(OS.get_environment("SERVE_SECONDS")) if OS.get_environment("SERVE_SECONDS") != "" else 120.0
	var receiver := ShadertoyReceiver.new()
	receiver.library = ShadertoyLibrary.new(dir)
	receiver.app_name = "Godot (check)"
	receiver.pinged.connect(func(): print("ping"))
	receiver.received.connect(func(st: Dictionary):
		var a := ShadertoyShader.analyze(st)
		var e := receiver.library.find(st.id)
		print("received %s \"%s\" by %s: %s, %d edit(s), %d warning(s), thumbnail %s" % [st.id, st.name, st.author,
				"ok" if a.ok else "won't run", a.edits.size(), a.warnings.size(), "yes" if e.get("thumbnail", "") != "" else "no"]))
	root.add_child(receiver)
	if not receiver.start():
		quit(1)
		return
	print("listening on %d for %d s" % [receiver.port, seconds])
	await create_timer(seconds).timeout
	print("library: %d shader(s)" % receiver.library.entries().size())
	quit(0)
