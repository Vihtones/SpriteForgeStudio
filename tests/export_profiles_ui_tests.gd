extends SceneTree
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

func _find_button(root_node: Node, title: String) -> Button:
	for node in root_node.find_children("*", "Button", true, false):
		if node is Button and node.text == title: return node
	return null

func run() -> void:
	var studio = load("res://main.tscn").instantiate()
	studio.workspace_root = "res://test_results/export-profile-ui"
	root.add_child(studio)
	await process_frame
	var export_button := _find_button(studio, "Exportar…")
	expect(export_button != null, "main toolbar exposes export profile workflow")
	studio.show_export_profiles()
	expect(studio.export_profile_picker.item_count == 6 and studio.export_profile_picker.selected == 3, "profile chooser offers six targets and defaults to full playable project")
	var choices: Array[String] = []
	for index in studio.export_profile_picker.item_count: choices.append(str(studio.export_profile_picker.get_item_metadata(index)))
	expect(choices == ["sprite", "animated", "modular", "playable", "map", "sequence"], "profile choices map to stable worker identifiers")
	studio.export_profile_picker.select(0)
	var continue_button := _find_button(studio.export_profile_dialog, "Escolher pasta…")
	if continue_button != null: continue_button.pressed.emit()
	await process_frame
	expect(studio._selected_export_profile == "sprite" and studio.dialog_action == "export", "selected profile carries through to destination picker")
	studio.dialog.hide()
	studio.show_export_profiles()
	studio.export_profile_picker.select(5)
	continue_button.pressed.emit()
	expect(studio._selected_export_profile == "sequence" and studio.dialog_action == "export", "PNG sequence profile carries through the same destination workflow")
	if is_instance_valid(studio.dialog): studio.dialog.hide()
	if is_instance_valid(studio.export_profile_dialog): studio.export_profile_dialog.hide()
	studio.queue_free()
	await process_frame
	var results_path := ProjectSettings.globalize_path("res://test_results")
	DirAccess.make_dir_recursive_absolute(results_path)
	var report := FileAccess.open("res://test_results/export-profiles-ui-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t"))
		report.close()
	print("Export profile UI: %d aprovados, %d falhas" % [passed, failed])
	quit(1 if failed or report == null else 0)
