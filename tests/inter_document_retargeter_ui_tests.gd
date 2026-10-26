extends SceneTree
const MainScene = preload("res://main.tscn")
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
var passed := 0
var failed := 0

func expect(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; printerr("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var storage = Storage.new()
	var source = Doc.new()
	source.animation = {"active": 0, "clips": [{"name": "pose-source", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	source.rig.skeleton = [["shoulder_l", "elbow_l"]]
	source.rig.anchors = {"0:0": {"shoulder_l": [16, 18], "elbow_l": [16, 12]}}
	source.layers[0].name = "Tronco fonte"
	source.layers[0].retarget_key = "torso"
	source.set_layer_bone(str(source.layers[0].id), ["shoulder_l", "elbow_l"])
	source.layers[0].cels[0][0].set_pixel(16, 18, Color("dba46e"))
	var source_path := "res://test_results/inter-document-ui-source.sfs.json"
	expect(storage.save_document(source, source_path) == OK, "salva o projeto de origem para o fluxo da interface")
	var studio: Control = MainScene.instantiate()
	studio.workspace_root = "user://inter-document-retargeter-ui-tests"
	root.add_child(studio)
	await process_frame
	var target = studio.doc
	target.animation = {"active": 0, "clips": [{"name": "pose-target", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	target.direction = 0
	target.frame = 1
	for layer in target.layers:
		layer.visible = layer == target.layers[0]
		for direction in 8:
			for frame in target.frames: layer.cels[direction][frame].fill(Color.TRANSPARENT)
	var target_layer: Dictionary = target.layers[0]
	target_layer.retarget_key = "torso"
	target.set_layer_bone(str(target_layer.id), ["pelvis", "chest"])
	target_layer.cels[0][1].set_pixel(16, 18, Color("dba46e"))
	target.rig.anchors = {"0:1": {"pelvis": [10, 12], "chest": [16, 12]}}
	studio.refresh_all()
	var retarget_button := false
	for node in studio.find_children("*", "Button", true, false):
		if node is Button and node.text == "Retargetar de outro projeto…": retarget_button = true
	expect(retarget_button, "retarget de outro projeto está disponível no painel do rig")
	studio.open_inter_document_retarget_dialog(source_path)
	await process_frame
	var options: ConfirmationDialog = _dialog(studio, "Retarget de outro projeto")
	expect(options != null, "interface carrega origem e permite escolher clip e quadro em rig com outra topologia")
	if options == null: finish(studio); return
	options.confirmed.emit()
	await process_frame
	var preview: ConfirmationDialog = _dialog(studio, "Prévia de retarget entre projetos")
	expect(preview != null, "interface exibe comparação antes e depois antes de aplicar")
	if preview == null: finish(studio); return
	preview.confirmed.emit()
	await process_frame
	expect(is_equal_approx(target.layer_rotation(str(target_layer.id), 0, 1), -90.0), "aprovação aplica a pose ao projeto atualmente aberto")
	expect(is_equal_approx(source.layer_rotation(str(source.layers[0].id), 0, 0), 0.0), "fluxo da interface não modifica as rotações do projeto fonte")
	expect(target.undo() and is_equal_approx(target.layer_rotation(str(target_layer.id), 0, 1), 0.0), "Undo restaura o destino pela interface")
	finish(studio)

func _dialog(studio: Node, title: String) -> ConfirmationDialog:
	for node in studio.find_children("*", "ConfirmationDialog", true, false):
		if node is ConfirmationDialog and node.title == title: return node
	return null

func finish(studio: Node) -> void:
	if is_instance_valid(studio): studio.queue_free()
	var report := FileAccess.open("res://test_results/inter-document-retargeter-ui-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Inter-document retargeter UI: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
