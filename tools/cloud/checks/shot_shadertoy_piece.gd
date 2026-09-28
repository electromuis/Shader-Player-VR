extends SceneTree

## Plays a piece in the player (the JSON in $PIECE, e.g. one exported
## after the Shadertoy dock's Add as layer) at $AT seconds (default 5) and
## shoots the view to $OUT_DIR/piece.png; prints each object on stage and,
## for layers, their shader. Rendered only.


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	var piece := OS.get_environment("PIECE")
	var at := float(OS.get_environment("AT")) if OS.get_environment("AT") != "" else 5.0
	await frames(2)
	var main: Node = load("res://player/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.open_file(piece, false)
	main.runner.set_video_duration(30.0)
	main.runner.seek(at)
	await create_timer(1.5).timeout
	var reg: ObjectRegistry = main.runner.registry()
	for id in reg.all_ids():
		var node: Node = reg.get_node_by_id(id)
		var shader := ""
		for n in ([node] + node.find_children("*", "", true, false)) if node != null else []:
			var mat = n.get("_material")
			if mat is ShaderMaterial and mat.shader != null:
				shader = " shader %s" % mat.shader.resource_path.get_file()
		print("on stage: %s (%s)%s" % [id, node.get_class() if node != null else "?", shader])
	var out := OS.get_environment("OUT_DIR")
	root.get_texture().get_image().save_png(out.path_join("piece.png"))
	print("SHADERTOY PIECE DONE")
	quit()
