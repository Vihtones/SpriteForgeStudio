extends SceneTree
## Exercises real Studio signals and captures the actual Godot rendering for review.
const Studio = preload("res://ui/studio.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func verify(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr(message)

func run() -> void:
	root.size = Vector2i(1440, 900)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	var studio = Studio.new()
	studio.workspace_root = "user://review-visual-" + str(Time.get_ticks_usec())
	root.add_child(studio)
	studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	studio.tabs.current_tab = studio.public_library_panel.get_index()
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://test_results/review-capture")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join("library-native.png"))
	var old_id: String = studio.workspace.active_id
	studio.public_library_panel.tile_button.pressed.emit()
	await process_frame
	verify(studio.workspace.active_id != old_id and studio.doc.width == 16 and studio.doc.art.source_assets.size() == 1 and studio.tabs.current_tab == 0, "tile action must open editable project through real Studio signal")
	studio.tabs.current_tab = studio.public_library_panel.get_index()
	studio.public_library_panel.tileset_button.pressed.emit()
	await process_frame
	var popup: ConfirmationDialog
	for child in studio.get_children():
		if child is ConfirmationDialog and child != studio.confirm: popup = child
	verify(popup != null and popup.visible, "tileset replacement must show confirmation")
	if popup != null: popup.confirmed.emit()
	await process_frame
	verify(studio.tabs.current_tab == 1 and studio.doc.tile_images().size() == 132, "tileset signal reaches world editor")
	verify(studio.doc.undo() and not studio.doc.map_data.has("tileset_png"), "native import is undoable")
	studio._bind_review_sample()
	studio.tabs.current_tab = studio.animation_review_panel.get_index()
	var panel: Control = studio.animation_review_panel
	panel.set_process(false)
	panel.review.restart(); panel.review.playing = true
	for index in 54:
		panel.review.tick(1.0 / 15.0); panel.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		var view: Image = root.get_texture().get_image()
		if index == 0: view.save_png(folder.path_join("review-native.png"))
		var bounds: Rect2 = panel.get_global_rect()
		var area := Rect2i(Vector2i(bounds.position), Vector2i(bounds.size)).intersection(Rect2i(Vector2i.ZERO, view.get_size()))
		view.get_region(area).save_png(folder.path_join("frame-%03d.png" % index))
	panel.review.playing = false
	panel.review.restart(); panel.refresh()
	panel.direction_picker.item_selected.emit(7)
	verify(panel.review.direction == 7, "native direction selector changes all action previews")
	panel.editor_requested.emit()
	await process_frame
	verify(studio.doc.width == 64 and studio.doc.frames == 24 and studio.doc.art.candidate_status == "candidate" and studio.tabs.current_tab == 0, "review opens editable corrected candidate without inherited approval")
	studio.doc.direction = 4
	studio.open_spritesheet_import_dialog(ProjectSettings.globalize_path("res://examples/animation_candidate_v8/sentinela-sheet-candidate-v1.png"))
	await process_frame
	var importer: ConfirmationDialog
	for child in studio.get_children():
		if child is ConfirmationDialog and child.title == "Importar spritesheet ou atlas por grade": importer = child
	verify(importer != null, "silhouette import is available through native editor")
	if importer != null:
		importer.find_child("isolate_silhouettes", true, false).button_pressed = true
		importer.find_child("source_row", true, false).value = 3
		importer.find_child("content_scale", true, false).value = 72
		importer.find_child("content_alignment", true, false).select(1)
		importer.find_child("start_frame", true, false).value = 17
		var revision: int = studio.doc.revision
		importer.confirmed.emit()
		var responsive_frames := 0
		while is_instance_valid(importer) and responsive_frames < 20000:
			responsive_frames += 1
			await process_frame
		verify(studio.doc.revision > revision and responsive_frames > 1 and studio.doc.validate().is_empty(), "real atlas extracts on a worker while interface processes frames")
	var file := FileAccess.open("res://test_results/library-review-ui-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": checks - failures.size(), "failed": failures.size(), "failures": failures}, "\t")); file.close()
	print("LIBRARY_REVIEW_UI: ", "PASS" if failures.is_empty() else str(failures))
	studio.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
