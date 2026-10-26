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
	studio.workspace_root = "user://rig-interpolator-ui-tests"
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	var layer_id: String = str(doc.layers[doc.active_layer].id)
	doc.animation = {"active": 0, "clips": [{"name": "walk", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	doc.direction = 0
	doc.rig.rotations = {"0:3": {layer_id: 90.0}}
	doc.rig.anchors = {"0:0": {"elbow_l": [4, 8]}, "0:3": {"elbow_l": [10, 14]}}
	studio.canvas.anchor_name = "elbow_l"
	studio.refresh_all()
	var button_found := false
	for node in studio.find_children("*", "Button", true, false):
		if node is Button and node.text == "Interpolar poses do rig…": button_found = true
	expect(button_found, "ação de interpolação está disponível no painel do rig")
	studio.mark_rig_pose_key()
	expect(doc.rig.rotations.get("0:0", {}).get(layer_id, -1.0) == 0.0, "interface registra como chave a pose neutra de 0°")
	studio.interpolate_rig_dialog()
	await process_frame
	var options: ConfirmationDialog = _dialog(studio, "Interpolar poses do rig")
	expect(options != null, "abrir ação mostra opções de canais do rig")
	if options == null:
		finish(studio)
		return
	options.confirmed.emit()
	await process_frame
	var preview: ConfirmationDialog = _dialog(studio, "Prévia da interpolação do rig")
	expect(preview != null, "prévia de antes/depois exige confirmação antes de editar")
	if preview == null:
		finish(studio)
		return
	preview.confirmed.emit()
	await process_frame
	expect(doc.rig.rotations.get("0:1", {}).get(layer_id, -1.0) == 30.0 and doc.rig.anchors.get("0:2", {}).get("elbow_l", []) == [8.0, 12.0], "confirmação aplica rotações e articulações nos quadros intermediários")
	expect(doc.undo() and not doc.rig.rotations.get("0:1", {}).has(layer_id) and not doc.rig.anchors.has("0:2"), "Undo do editor reverte a interpolação completa")
	finish(studio)

func _dialog(studio: Node, title: String) -> ConfirmationDialog:
	for node in studio.find_children("*", "ConfirmationDialog", true, false):
		if node is ConfirmationDialog and node.title == title:
			return node
	return null

func finish(studio: Node) -> void:
	if is_instance_valid(studio): studio.queue_free()
	var report := FileAccess.open("res://test_results/rig-interpolator-ui-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t"))
		report.close()
	print("Rig interpolator UI: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
