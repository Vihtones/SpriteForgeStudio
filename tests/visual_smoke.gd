extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var ui = load("res://main.tscn").instantiate()
	ui.workspace_root = "res://test_results/visual_workspace"
	root.add_child(ui)
	ui.queue.jobs.clear()
	ui.queue.checkpoint_path = "res://test_results/visual_queue.json"
	var original_id: String = ui.workspace.active_id
	ui.workspace.add_document(preload("res://core/document.gd").new())
	ui.workspace.activate(original_id)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_results/editor.png")
	ui.tabs.current_tab = 1
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_results/map.png")
	ui.tabs.current_tab = 2
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_results/art.png")
	ui.tabs.current_tab = 4
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_results/quality.png")
	ui.tabs.current_tab = 7
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_results/automation.png")
	ui.free()
	quit()
