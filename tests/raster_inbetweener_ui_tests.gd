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
	studio.workspace_root = "user://raster-inbetweener-ui-tests"
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	doc.animation = {"active": 0, "clips": [{"name": "swing", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": false}], "events": {}, "hitboxes": {}}
	doc.direction = 0
	doc.frame = 0
	var layer: Dictionary = doc.layers[0]
	layer.name = "Braço"
	doc.set_layer_bone(str(layer.id), ["pelvis", "chest"])
	for frame in doc.frames: layer.cels[0][frame].fill(Color.TRANSPARENT)
	layer.cels[0][0].set_pixel(16, 12, Color("e94358"))
	layer.cels[0][0].set_pixel(16, 13, Color("ecb05d"))
	layer.cels[0][3].set_pixel(16, 12, Color("e94358"))
	layer.cels[0][3].set_pixel(16, 13, Color("ecb05d"))
	doc.rig.anchors = {"0:0": {"pelvis": [16, 24], "chest": [16, 12]}, "0:3": {"pelvis": [16, 24], "chest": [24, 24]}}
	var source_pixels: PackedByteArray = layer.cels[0][0].get_data()
	var target_pixels: PackedByteArray = layer.cels[0][3].get_data()
	var intermediate_before: PackedByteArray = layer.cels[0][1].get_data()
	studio.refresh_all()
	var button_found := false
	for node in studio.find_children("*", "Button", true, false):
		if node is Button and node.text == "Criar quadros raster intermediários…": button_found = true
	expect(button_found, "gerador raster revisável aparece no painel do rig")
	studio.raster_inbetween_dialog()
	await process_frame
	var choose: ConfirmationDialog = _dialog(studio, "Criar quadros raster intermediários")
	expect(choose != null, "interface solicita duas poses-chave do clip atual")
	if choose == null: finish(studio); return
	var scale_checkbox := _find_scale_checkbox(choose)
	expect(scale_checkbox != null and scale_checkbox.button_pressed, "escala anatômica proporcional fica disponível com intervalo seguro de 0,5×–2×")
	if scale_checkbox != null: scale_checkbox.button_pressed = false
	var pickers: Array[Node] = choose.find_children("*", "OptionButton", true, false)
	if pickers.size() >= 2: (pickers[1] as OptionButton).select(3)
	choose.confirmed.emit()
	await process_frame
	var preview: ConfirmationDialog = _dialog(studio, "Prévia dos quadros raster intermediários")
	expect(preview != null, "prévia compara folhas de contato antes e depois")
	if preview == null: finish(studio); return
	preview.confirmed.emit()
	await process_frame
	expect(layer.cels[0][1].get_used_rect().size != Vector2i.ZERO and layer.cels[0][2].get_used_rect().size != Vector2i.ZERO, "confirmação gera cels editáveis nos frames intermediários")
	expect(layer.cels[0][0].get_data() == source_pixels and layer.cels[0][3].get_data() == target_pixels, "origem e destino permanecem inalterados")
	expect(doc.rig.anchors.has("0:1") and doc.rig.anchors.has("0:2"), "rig interpola articulações nos frames gerados")
	expect(doc.undo() and doc.layers[0].cels[0][1].get_data() == intermediate_before and not doc.rig.anchors.has("0:1"), "Undo restaura cels e âncoras do intervalo completo")
	doc.animation = {"active": 0, "clips": [{"name": "insert", "frames": [0, 1], "durations_ms": {"0": 80.0, "1": 80.0}, "loop": false}], "events": {}, "hitboxes": {}}
	doc.frames = 4
	for current_layer in doc.layers:
		for direction in 8:
			while current_layer.cels[direction].size() < doc.frames: current_layer.cels[direction].append(doc.blank())
			for frame in doc.frames: current_layer.cels[direction][frame].fill(Color.TRANSPARENT)
	doc.direction = 0; doc.frame = 0; doc.active_layer = 0
	layer = doc.layers[0]
	layer.cels[0][0].set_pixel(16, 12, Color("e94358"))
	layer.cels[0][1].set_pixel(16, 12, Color("e94358"))
	doc.rig.anchors = {"0:0": {"pelvis": [16, 24], "chest": [16, 12]}, "0:1": {"pelvis": [16, 24], "chest": [24, 24]}}
	var insert_button := _find_button(studio, "Inserir e gerar novos quadros…")
	expect(insert_button != null, "Pixel Studio oferece inserção real de quadros raster")
	if insert_button != null:
		insert_button.pressed.emit()
		await process_frame
		var insert_dialog := _dialog(studio, "Inserir quadros raster intermediários")
		expect(insert_dialog != null, "fluxo pede poses adjacentes e quantidade de quadros")
		if insert_dialog != null:
			var insert_scale_checkbox := _find_scale_checkbox(insert_dialog)
			expect(insert_scale_checkbox != null and insert_scale_checkbox.button_pressed, "inserção de frames também expõe escala anatômica revisável")
			insert_dialog.confirmed.emit()
			await process_frame
			var insert_preview := _dialog(studio, "Prévia: novos quadros na timeline")
			expect(insert_preview != null and doc.frames == 4, "prévia da inserção não altera a timeline original")
			if insert_preview != null:
				insert_preview.confirmed.emit()
				await process_frame
			expect(doc.frames == 6 and doc.clip().frames == [0, 1, 2, 3], "aceite insere os dois quadros reais e preserva a ordem do clip")
			var first_generated_rect: Rect2i = doc.layers[0].cels[0][1].get_used_rect()
			var second_generated_rect: Rect2i = doc.layers[0].cels[0][2].get_used_rect()
			expect(first_generated_rect.size != Vector2i.ZERO and second_generated_rect.size != Vector2i.ZERO, "interface produz cels editáveis para a nova sequência")
			expect(doc.undo() and doc.frames == 4 and doc.clip().frames == [0, 1], "Ctrl+Z da interface desfaz a expansão inteira")
	finish(studio)

func _find_button(studio: Node, title: String) -> Button:
	for node in studio.find_children("*", "Button", true, false):
		if node is Button and node.text == title: return node
	return null

func _find_scale_checkbox(dialog: Node) -> CheckBox:
	for node in dialog.find_children("*", "CheckBox", true, false):
		if node is CheckBox and node.text.begins_with("Ajustar escala das partes"): return node
	return null

func _dialog(studio: Node, title: String) -> ConfirmationDialog:
	for node in studio.find_children("*", "ConfirmationDialog", true, false):
		if node is ConfirmationDialog and node.title == title: return node
	return null

func finish(studio: Node) -> void:
	if is_instance_valid(studio): studio.queue_free()
	var report := FileAccess.open("res://test_results/raster-inbetweener-ui-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Raster inbetweener UI: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
