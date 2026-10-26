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
	studio.workspace_root = "res://test_results/rig-segment-extractor-ui-%d" % Time.get_ticks_usec()
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	doc.art.locked = false
	for layer in doc.layers:
		for direction in 8:
			for frame in doc.frames: layer.cels[direction][frame].fill(Color.TRANSPARENT)
	doc.direction = 0; doc.frame = 0; doc.active_layer = 0
	doc.layers[0].opacity = 0.8
	doc.current().set_pixel(5, 5, Color("d24545"))
	doc.current().set_pixel(6, 5, Color("315ec9"))
	doc.current().set_pixel(5, 6, Color("e1b24e"))
	doc.current().set_pixel(10, 10, Color("66bb6a"))
	doc.selection = Rect2i(4, 4, 4, 4)
	var original: PackedByteArray = doc.current().get_data()
	var original_composite: PackedByteArray = doc.composite().get_data()
	var old_layer_count: int = doc.layers.size()
	studio.refresh_all()
	var button := _find_button(studio, "Extrair região em camada de rig…")
	expect(button != null, "Pixel Studio expõe extração assistida de segmento")
	if button == null:
		studio.queue_free(); quit(1); return
	button.pressed.emit()
	await process_frame
	var dialog := _find_confirmation(studio, "Extrair região em camada de rig")
	expect(dialog != null, "extração abre nome, região, coordenadas e mapeamento ósseo")
	if dialog == null:
		studio.queue_free(); quit(1); return
	var name_field := _find_named(dialog, "RigSegmentLayerName") as LineEdit
	var bone_selector := _find_named(dialog, "RigSegmentBone") as OptionButton
	if name_field != null: name_field.text = "Antebraço esquerdo"
	if bone_selector != null:
		for index in bone_selector.item_count:
			if bone_selector.get_item_text(index) == "shoulder_l → elbow_l": bone_selector.select(index)
	dialog.confirmed.emit()
	dialog.hide()
	await process_frame
	await process_frame
	var preview := _find_confirmation(studio, "Prévia da camada de rig · Antebraço esquerdo")
	var preview_shown := preview != null
	expect(preview_shown and doc.layers.size() == old_layer_count and doc.layers[0].cels[0][0].get_data() == original, "prévia mostra separação sem criar layer nem alterar a fonte")
	if preview != null: preview.confirmed.emit(); preview.hide()
	await process_frame
	await process_frame
	expect(preview_shown and doc.layers.size() == old_layer_count + 1 and doc.active_layer == 1, "aceitar cria camada extraída e a seleciona")
	expect(doc.layers[1].name == "Antebraço esquerdo" and doc.layers[1].bone == ["shoulder_l", "elbow_l"] and doc.layers[1].pivot == "shoulder_l", "camada é nomeada e mapeada ao segmento ósseo escolhido")
	expect(doc.layers[1].cels[0][0].get_pixel(5, 5).to_html(false) == "d24545" and doc.layers[0].cels[0][0].get_pixel(5, 5).a == 0.0, "pixels selecionados se movem da origem para a camada nova")
	expect(doc.layers[0].cels[0][0].get_pixel(10, 10).to_html(false) == "66bb6a" and doc.composite().get_data() == original_composite, "arte externa à seleção permanece e composição não muda")
	expect(doc.undo() and doc.layers.size() == old_layer_count and doc.layers[0].cels[0][0].get_data() == original, "Undo desfaz extração e recupera raster original")
	var report := FileAccess.open("res://test_results/rig-segment-extractor-ui-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Rig segment extractor UI: %d passed, %d failed" % [passed, failed])
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

func _find_named(node: Node, target_name: String) -> Node:
	if node.name == target_name: return node
	for child in node.get_children():
		var found := _find_named(child, target_name)
		if found != null: return found
	return null
