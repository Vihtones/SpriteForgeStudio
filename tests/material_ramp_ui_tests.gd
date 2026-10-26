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
	studio.workspace_root = "res://test_results/material-ramp-ui-%d" % Time.get_ticks_usec()
	root.add_child(studio)
	await process_frame
	var button := _find_button(studio, "Criar rampa de material…")
	expect(button != null, "paleta mostra ação para criar rampa de material")
	if button == null:
		studio.queue_free(); quit(1); return
	var doc = studio.doc
	doc.art.locked = false
	var old_palette: Array = doc.palette.duplicate()
	button.pressed.emit()
	await process_frame
	var config := _find_confirmation(studio, "Nova rampa de material")
	expect(config != null, "ação abre configuração sombra/base/luz e quantidade")
	if config == null:
		studio.queue_free(); quit(1); return
	var name_field := _find_named(config, "MaterialRampName") as LineEdit
	if name_field != null: name_field.text = "Metal"
	config.confirmed.emit()
	config.hide()
	await process_frame
	await process_frame
	var preview := _find_confirmation(studio, "Prévia da rampa · Metal")
	expect(preview != null and doc.palette == old_palette, "prévia apresenta cores antes/depois sem mutar a paleta")
	var preview_was_shown := preview != null
	if preview != null: preview.canceled.emit()
	await process_frame
	expect(preview_was_shown and doc.palette == old_palette and doc.art.get("material_ramps", []).is_empty(), "rejeitar prévia não cria rampa nem adiciona cores")
	await process_frame
	button.pressed.emit()
	await process_frame
	config = _find_confirmation(studio, "Nova rampa de material")
	if config != null:
		var second_name := _find_named(config, "MaterialRampName") as LineEdit
		if second_name != null: second_name.text = "Metal"
		config.confirmed.emit()
		config.hide()
	else:
		printerr("Material ramp UI diagnostic: setup dialog missing on second attempt")
	await process_frame
	await process_frame
	preview = _find_confirmation(studio, "Prévia da rampa · Metal")
	var shown_for_accept := preview != null
	if not shown_for_accept: printerr("Material ramp UI diagnostic: preview missing; status=", studio.status.text)
	if preview != null: preview.confirmed.emit(); preview.hide()
	await process_frame
	await process_frame
	var stored_ramps: Array = doc.art.get("material_ramps", [])
	if stored_ramps.is_empty(): printerr("Material ramp UI diagnostic: accept status=", studio.status.text, " palette=", doc.palette.size())
	expect(shown_for_accept and doc.palette.size() > old_palette.size() and stored_ramps.size() == 1, "aceitar prévia adiciona tons ausentes e registra rampa nomeada")
	expect(not stored_ramps.is_empty() and stored_ramps[0].colors.size() == 5 and stored_ramps[0].colors[2] == old_palette[1], "rampa salva cinco passos e mantém a cor-base central")
	expect(doc.undo() and doc.palette == old_palette and doc.art.get("material_ramps", []).is_empty(), "Undo remove tons e metadados da rampa em uma ação")
	expect(doc.redo() and doc.art.get("material_ramps", []).size() == 1, "Redo restaura a rampa inteira")
	var report := FileAccess.open("res://test_results/material-ramp-ui-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Material ramp UI: %d passed, %d failed" % [passed, failed])
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
