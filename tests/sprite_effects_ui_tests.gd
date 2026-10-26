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
	studio.workspace_root = "res://test_results/sprite-effects-ui-%d" % Time.get_ticks_usec()
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	doc.art.locked = false
	doc.palette = ["#202030", "#808090", "#e8e8f0"]
	var ramp_service = Ramps.new()
	ramp_service.apply(doc, ramp_service.build(doc, "Metal", 0, 1, 2, 5))
	studio.open_sprite_effect_dialog()
	await process_frame
	var popup: ConfirmationDialog = null
	for child in studio.get_children():
		if child is ConfirmationDialog and child.title == "Gerar efeito": popup = child
	expect(popup != null, "botão Efeito… abre o diálogo Gerar efeito")
	if popup == null:
		printerr("Sprite effects UI: dialog missing"); studio.queue_free(); quit(1); return
	var type_selector: OptionButton = popup.find_child("EffectType", true, false)
	var source_selector: OptionButton = popup.find_child("EffectSource", true, false)
	var ramp_selector: OptionButton = popup.find_child("EffectRamp", true, false)
	var frames_field: LineEdit = popup.find_child("EffectFrames", true, false)
	expect(type_selector != null and source_selector != null and ramp_selector != null and frames_field != null, "diálogo expõe tipo, fonte, material e quadros")
	expect(source_selector.item_count == doc.layers.size() and ramp_selector.item_count == 1, "fonte lista as camadas e material lista a rampa salva")
	expect(frames_field.text == ", ".join(range(doc.frames).map(func(f): return str(f))), "quadros começam com todos os quadros do documento")
	type_selector.select(2)
	type_selector.item_selected.emit(2)
	var anchor_selector: OptionButton = popup.find_child("EffectAnchor", true, false)
	var particles_row: Control = popup.find_child("EffectSeed", true, false).get_parent()
	expect(particles_row.visible and not source_selector.get_parent().visible, "partículas mostram âncora e seed e ocultam a camada-fonte")
	expect(anchor_selector.item_count >= 17, "âncoras de emissão incluem as articulações e os pontos de montagem")
	var regenerate: CheckBox = popup.find_child("EffectRegenerate", true, false)
	expect(not regenerate.visible, "regenerar fica oculto quando a camada ativa não é efeito")
	popup.hide(); popup.queue_free()
	await process_frame
	var report := {"passed": passed, "failed": failed}
	print("Sprite effects UI: %d passed, %d failed" % [passed, failed])
	studio.queue_free()
	quit(1 if failed else 0)
