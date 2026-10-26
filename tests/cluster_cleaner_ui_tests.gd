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
	studio.workspace_root = "user://cluster-cleaner-ui-tests"
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	var button := _find_button(studio, "Revisar clusters pequenos…")
	expect(button != null, "Pixel Studio expõe a ação de revisão de clusters")
	if button == null:
		studio.queue_free()
		quit(1)
		return
	for layer in doc.layers:
		for direction in 8:
			for frame in doc.frames: layer.cels[direction][frame].fill(Color.TRANSPARENT)
	doc.art.locked = false
	doc.selection = Rect2i()
	doc.direction = 0; doc.frame = 0; doc.active_layer = 0
	doc.current().set_pixel(8, 8, Color("ed7358"))
	var original: PackedByteArray = doc.current().get_data()
	button.pressed.emit()
	await process_frame
	var setup_dialog := _find_confirmation(studio, "Limpar clusters pequenos")
	expect(setup_dialog != null and doc.current().get_data() == original, "a ação abre configuração sem alterar a arte")
	if setup_dialog == null:
		studio.queue_free()
		quit(1)
		return
	setup_dialog.confirmed.emit()
	setup_dialog.hide()
	await process_frame
	await process_frame
	var review_dialog := _find_confirmation(studio, "Prévia de limpeza de clusters")
	var review_found := review_dialog != null
	expect(review_found and doc.current().get_data() == original, "proposta abre comparação antes/depois sem aplicar automaticamente")
	if review_dialog != null: review_dialog.canceled.emit()
	await process_frame
	expect(review_found and doc.current().get_data() == original, "rejeitar comparação não muda pixels")
	# Core tests verify application and Undo/Redo; this UI suite keeps the preview rejected.
	var report := FileAccess.open("res://test_results/cluster-cleaner-ui-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Cluster cleaner UI: %d passed, %d failed" % [passed, failed])
	studio.queue_free()
	quit(1 if failed else 0)

func _find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title: return node
	for child in node.get_children():
		var found := _find_button(child, title)
		if found != null: return found
	return null

func _find_confirmation(node: Node, title: String) -> ConfirmationDialog:
	if node is ConfirmationDialog and node.title == title: return node
	for child in node.get_children():
		var found := _find_confirmation(child, title)
		if found != null: return found
	return null

