extends SceneTree
const MainScene = preload("res://main.tscn")
const Ramps = preload("res://core/material_ramps.gd")
var passed := 0
var failed := 0

func expect(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; printerr("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio: Control = MainScene.instantiate()
	studio.workspace_root = "res://test_results/material-recolor-ui-%d" % Time.get_ticks_usec()
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	doc.art.locked = false
	doc.palette = ["#202030", "#808090", "#e8e8f0"]
	var ramp_service = Ramps.new()
	var ramp_proposal: Dictionary = ramp_service.build(doc, "Metal", 0, 1, 2, 5)
	if not ramp_service.apply(doc, ramp_proposal):
		printerr("Could not create material ramp test fixture")
		studio.queue_free(); quit(1); return
	for layer in doc.layers:
		for direction in 8:
			for frame in doc.frames: layer.cels[direction][frame].fill(Color.TRANSPARENT)
	doc.selection = Rect2i(0, 0, 8, 8)
	doc.direction = 0; doc.frame = 0; doc.active_layer = 0
	doc.current().set_pixel(4, 4, Color("202030"))
	doc.current().set_pixel(5, 5, Color("202030"))
	doc.current().set_pixel(12, 12, Color("202030"))
	studio.refresh_all()
	var button := _find_button(studio, "Recolorir região com rampa…")
	expect(button != null, "paleta expõe recolorização com rampas salvas")
	if button == null:
		studio.queue_free(); quit(1); return
	var original: PackedByteArray = doc.current().get_data()
	button.pressed.emit()
	await process_frame
	var dialog := _find_confirmation(studio, "Recolorir região com rampa")
	expect(dialog != null, "recolorização abre controles de cor, material, tom e região")
	if dialog == null:
		studio.queue_free(); quit(1); return
	var mode := _find_named(dialog, "RecolorMode") as OptionButton
	var seed_x := _find_named(dialog, "RecolorSeedX") as SpinBox
	var seed_y := _find_named(dialog, "RecolorSeedY") as SpinBox
	if mode != null:
		mode.select(1)
		mode.item_selected.emit(1)
	if seed_x != null: seed_x.value = 4
	if seed_y != null: seed_y.value = 4
	dialog.confirmed.emit()
	dialog.hide()
	await process_frame
	await process_frame
	var preview := _find_confirmation(studio, "Prévia de recolorização · Metal")
	var preview_shown := preview != null
	expect(preview_shown and doc.current().get_data() == original, "modo componente prepara uma prévia sem tocar nos pixels")
	if preview != null: preview.canceled.emit()
	await process_frame
	expect(preview_shown and doc.current().get_data() == original, "rejeitar comparação preserva a cel original")
	await process_frame
	button.pressed.emit()
	await process_frame
	dialog = _find_confirmation(studio, "Recolorir região com rampa")
	if dialog != null:
		mode = _find_named(dialog, "RecolorMode") as OptionButton
		seed_x = _find_named(dialog, "RecolorSeedX") as SpinBox
		seed_y = _find_named(dialog, "RecolorSeedY") as SpinBox
		if mode != null: mode.select(1); mode.item_selected.emit(1)
		if seed_x != null: seed_x.value = 4
		if seed_y != null: seed_y.value = 4
		dialog.confirmed.emit()
		dialog.hide()
	await process_frame
	await process_frame
	preview = _find_confirmation(studio, "Prévia de recolorização · Metal")
	var preview_for_accept := preview != null
	var expected_color: String = doc.art.material_ramps[0].colors[2]
	if preview != null: preview.confirmed.emit(); preview.hide()
	await process_frame
	await process_frame
	expect(preview_for_accept and doc.current().get_pixel(4, 4).to_html(false) == expected_color.trim_prefix("#") and doc.current().get_pixel(5, 5).to_html(false) == expected_color.trim_prefix("#"), "aceitar proposta recolore a componente diagonal conectada")
	expect(doc.current().get_pixel(12, 12).to_html(false) == "202030", "recolorização localizada deixa outra região da mesma cor intacta")
	expect(doc.undo() and doc.current().get_data() == original, "Undo da interface restaura a cel inteira")
	var report := FileAccess.open("res://test_results/material-recolor-ui-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Material recolor UI: %d passed, %d failed" % [passed, failed])
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
