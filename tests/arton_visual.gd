extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ui = load("res://main.tscn").instantiate()
	root.add_child(ui)
	ui.selected_open("res://examples/arton_projects/humanoide.sfs.json")
	ui.doc.active_layer = 1
	ui.refresh_layer()
	ui.set_layer("visible", true)
	ui.canvas.zoom = 1.5
	ui.canvas.refresh()
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_results/arton-editor.png")
	ui.tabs.current_tab = 5
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_results/arton-library.png")
	ui.free()
	quit()
