extends SceneTree

const Document = preload("res://core/document.gd")
const MainScene = preload("res://main.tscn")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; printerr("FAIL ", message)

func run() -> void:
	var studio: Control = MainScene.instantiate()
	studio.workspace_root = "res://test_results/lpc-import-flow-%d" % Time.get_ticks_usec()
	root.add_child(studio)
	await process_frame
	var source_doc: RefCounted = studio.doc
	source_doc.layers.clear()
	source_doc.width = 64
	source_doc.height = 64
	source_doc.frames = 9
	source_doc.frame = 0
	source_doc.direction = 0
	source_doc.animation = {"active": 0, "clips": [{"name": "walk", "frames": range(9), "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	source_doc.add_layer("Base LPC")
	studio.refresh_all()
	await process_frame
	var panel: Control = studio.public_library_panel
	var selected_index := -1
	for index in panel.filtered.size():
		if str(panel.filtered[index].get("id", "")) == "lpc-male-walk": selected_index = index; break
	if selected_index >= 0: panel.spritesheet_requested.emit("lpc-male-walk")
	await process_frame
	var import_dialog: ConfirmationDialog
	for child in studio.find_children("*", "ConfirmationDialog", true, false):
		if child is ConfirmationDialog and child.title == "Importar spritesheet ou atlas por grade": import_dialog = child; break
	expect(selected_index >= 0 and import_dialog != null, "biblioteca abre o diálogo de importação da folha LPC selecionada")
	if import_dialog == null: finish(studio); return
	var layout: OptionButton
	for child in import_dialog.find_children("*", "OptionButton", true, false):
		if child is OptionButton and child.item_count == 3: layout = child; break
	if layout != null:
		layout.select(2)
		layout.item_selected.emit(2)
	var columns: SpinBox = import_dialog.find_child("columns", true, false)
	var source_rows: SpinBox = import_dialog.find_child("source_rows", true, false)
	var isolate: CheckBox = import_dialog.find_child("isolate_silhouettes", true, false)
	var mode_info: Label = import_dialog.find_child("lpc_mode_info", true, false)
	expect(layout != null and columns != null and source_rows != null and isolate != null and mode_info != null and mode_info.visible and source_rows.value == 4 and columns.value == 9 and isolate.disabled, "modo LPC configura nove quadros, quatro linhas e bloqueia isolamento incompatível")
	if layout == null or columns == null or source_rows == null or isolate == null: finish(studio); return
	import_dialog.confirmed.emit()
	await process_frame
	var library = preload("res://core/public_asset_library.gd").new()
	var image: Image = library.image("lpc-male-walk")
	var expected_directions := [0, 6, 4, 2]
	var cells_match: bool = image != null and source_doc.art.get("source_assets", []).size() == 1 and source_doc.validate().is_empty()
	for row in 4:
		for frame in 9:
			var cel: Image = source_doc.layers[0].cels[expected_directions[row]][frame]
			var expected: Image = image.get_region(Rect2i(frame * 64, row * 64, 64, 64))
			cells_match = cells_match and cel.get_data() == expected.get_data()
	for direction in [1, 3, 5, 7]:
		for frame in 9: cells_match = cells_match and source_doc.layers[0].cels[direction][frame].get_used_rect().size == Vector2i.ZERO
	expect(cells_match, "importação pela interface preserva os 36 quadros cardinais, procedência e diagonais vazias")
	expect(source_doc.undo() and source_doc.art.get("source_assets", []).is_empty(), "Undo da importação pela interface remove cels e créditos juntos")
	finish(studio)

func finish(studio: Node) -> void:
	if is_instance_valid(studio): studio.queue_free()
	var report := FileAccess.open("res://test_results/lpc-import-flow-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("LPC import flow: %d passed / %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
