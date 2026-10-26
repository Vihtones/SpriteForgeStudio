extends SceneTree
const MainScene = preload("res://main.tscn")
var passed := 0
var failed := 0

func expect(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS ", message)
	else:
		failed += 1
		printerr("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio: Control = MainScene.instantiate()
	studio.workspace_root = "user://pose-retargeter-ui-tests"
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	var layer: Dictionary = doc.layers[0]
	var layer_id: String = str(layer.id)
	doc.animation = {"active": 0, "clips": [{"name": "walk", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	doc.frame = 2
	doc.direction = 0
	doc.rig.anchors = {"0:0": {"pelvis": [16, 27], "chest": [16, 15]}, "0:2": {"pelvis": [16, 27], "chest": [27, 27]}}
	layer.cels[0][2].set_pixel(16, 15, Color("aabbdc"))
	studio.refresh_all()
	var bone_index := -1
	for index in studio.bone_picker.item_count:
		if studio.bone_picker.get_item_text(index) == "pelvis → chest": bone_index = index; break
	expect(bone_index > 0, "painel do rig lista segmentos ósseos tipados")
	if bone_index <= 0:
		finish(studio)
		return
	studio.bone_picker.select(bone_index)
	studio.bone_picker.item_selected.emit(bone_index)
	expect(layer.get("bone", []) == ["pelvis", "chest"] and layer.pivot == "pelvis", "mapeamento de segmento configura a raiz como pivô")
	var retarget_button := false
	for node in studio.find_children("*", "Button", true, false):
		if node is Button and node.text == "Retargetar pose por segmentos…": retarget_button = true
	expect(retarget_button, "ação de retarget está disponível no painel do rig")
	studio.retarget_pose_dialog()
	await process_frame
	var options: ConfirmationDialog = _dialog(studio, "Retargetar pose por segmentos")
	expect(options != null, "retarget solicita quadro de origem dentro do clip ativo")
	if options == null:
		finish(studio)
		return
	options.confirmed.emit()
	await process_frame
	var preview: ConfirmationDialog = _dialog(studio, "Prévia de retarget por segmentos")
	expect(preview != null, "retarget mostra composição antes/depois para revisão")
	if preview == null:
		finish(studio)
		return
	preview.confirmed.emit()
	await process_frame
	expect(is_equal_approx(doc.layer_rotation(layer_id, 0, 2), -90.0), "confirmação transfere orientação do osso ao frame alvo")
	expect(doc.undo() and is_equal_approx(doc.layer_rotation(layer_id, 0, 2), 0.0), "Undo restaura o retarget do editor")
	finish(studio)

func _dialog(studio: Node, title: String) -> ConfirmationDialog:
	for node in studio.find_children("*", "ConfirmationDialog", true, false):
		if node is ConfirmationDialog and node.title == title: return node
	return null

func finish(studio: Node) -> void:
	if is_instance_valid(studio): studio.queue_free()
	var report := FileAccess.open("res://test_results/pose-retargeter-ui-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t"))
		report.close()
	print("Pose retargeter UI: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
