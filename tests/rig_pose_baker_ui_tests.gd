extends SceneTree
const MainScene = preload("res://main.tscn")
var passed := 0
var failed := 0

func expect(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; printerr("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio: Control = MainScene.instantiate()
	studio.workspace_root = "user://rig-pose-baker-ui-tests"
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	var layer: Dictionary = doc.layers[doc.active_layer]
	var layer_id := str(layer.id)
	var pose_key: String = str(doc.cel_key(doc.direction, doc.frame))
	if not doc.rig.has("rotations"): doc.rig.rotations = {}
	if not doc.rig.rotations.has(pose_key): doc.rig.rotations[pose_key] = {}
	doc.rig.rotations[pose_key][layer_id] = 31.0
	layer.cels[doc.direction][doc.frame].set_pixel(10, 8, Color("fe65a2"))
	var original_pixels: PackedByteArray = layer.cels[doc.direction][doc.frame].get_data()
	var before_composite: PackedByteArray = doc.composite(doc.direction, doc.frame).get_data()
	studio.refresh_all()
	var button_found := false
	for node in studio.find_children("*", "Button", true, false):
		if node is Button and node.text == "Aplicar pose à camada (pixels)…": button_found = true
	expect(button_found, "conversor de pose raster está disponível no editor de rig")
	studio.bake_layer_pose_dialog()
	await process_frame
	var preview: ConfirmationDialog = _dialog(studio, "Aplicar pose à camada em pixels")
	expect(preview != null, "interface prepara comparação da cel antes de rasterizar")
	if preview == null: finish(studio); return
	preview.confirmed.emit()
	await process_frame
	expect(layer.cels[doc.direction][doc.frame].get_data() != original_pixels, "confirmação atualiza somente os pixels da camada/quadro ativo")
	expect(doc.composite(doc.direction, doc.frame).get_data() == before_composite and is_equal_approx(doc.layer_rotation(layer_id), 0.0), "composição mantém aparência enquanto o canal de rotação é incorporado")
	expect(doc.undo() and doc.layers[doc.active_layer].cels[doc.direction][doc.frame].get_data() == original_pixels and is_equal_approx(doc.layer_rotation(layer_id), 31.0), "Undo restaura raster e pose original pela interface")
	finish(studio)

func _dialog(studio: Node, title: String) -> ConfirmationDialog:
	for node in studio.find_children("*", "ConfirmationDialog", true, false):
		if node is ConfirmationDialog and node.title == title: return node
	return null

func finish(studio: Node) -> void:
	if is_instance_valid(studio): studio.queue_free()
	var report := FileAccess.open("res://test_results/rig-pose-baker-ui-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Rig pose baker UI: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
