extends SceneTree
const HyperlearnPanel = preload("res://ui/hyperlearn_panel.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

func run() -> void:
	var panel = HyperlearnPanel.new()
	root.add_child(panel)
	await process_frame
	expect(panel.selected_direction_indices().is_empty(), "escopo padrão representa o pack completo")
	panel.review_scope.select(1)
	panel.review_scope.item_selected.emit(1)
	expect(panel.selected_direction_indices().size() == 8 and panel.direction_grid.visible, "escopo personalizado inicia com as direções marcadas e visíveis")
	panel.direction_checks[2].button_pressed = false
	panel.direction_checks[2].toggled.emit(false)
	var selected: Array[int] = panel.selected_direction_indices()
	expect(selected.size() == 7 and not selected.has(2) and selected.has(7), "revisão registra somente as direções selecionadas")
	var decisions: Array[Dictionary] = []
	panel.review_requested.connect(func(approved: bool, reviewer: String, note: String, confirmed: bool, direction_indices: Array):
		decisions.append({"approved": approved, "reviewer": reviewer, "note": note, "confirmed": confirmed, "directions": direction_indices})
	)
	panel.reviewer.text = "Revisor"
	panel.note.text = "Vista leste reprovada"
	panel.confirmation.button_pressed = true
	panel.reject_button.pressed.emit()
	var decision: Dictionary = decisions[0] if not decisions.is_empty() else {}
	expect(not decision.get("approved", true) and decision.get("directions", []).size() == 7 and decision.get("confirmed", false), "botão de reprovação envia decisão humana e escopo sem perder metadados")
	for checkbox in panel.direction_checks:
		checkbox.button_pressed = false
		checkbox.toggled.emit(false)
	expect(panel.approve_button.disabled and panel.reject_button.disabled, "interface impede gravar avaliação sem direções selecionadas")
	panel.review_scope.select(0)
	panel.review_scope.item_selected.emit(0)
	expect(panel.selected_direction_indices().is_empty() and not panel.approve_button.disabled, "retorno ao escopo completo reativa avaliação global")
	panel.show_report({"approved": 48, "rejected": 24, "total": 72}, {"training_examples": 72, "validation_examples": 72, "validation_projects_scored": 12, "validation_folds": 5, "validation_balanced_accuracy": 0.98, "validation_approved_recall": 0.99, "validation_rejected_recall": 0.97, "validation_brier_score": 0.04}, {"ready": true, "eligible_for_autonomy": true, "decision": "auto_approve_candidate", "probability": 0.99})
	expect(panel.report.text.contains("Brier") and panel.report.text.contains("recall aprovado/reprovado") and panel.report.text.contains("não equivale a aprovação humana"), "painel exibe métricas fora da amostra e distingue classificação de aprovação artística")
	panel.free()
	await process_frame
	var results_path := ProjectSettings.globalize_path("res://test_results")
	DirAccess.make_dir_recursive_absolute(results_path)
	var report := FileAccess.open("res://test_results/hyperlearn-panel-ui-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t"))
		report.close()
	print("HyperLearn panel: %d aprovados, %d falhas" % [passed, failed])
	quit(1 if failed or report == null else 0)
