extends VBoxContainer
## Presentation-only HyperLearn Lab. Decisions are explicit signals to the Studio.
signal review_requested(approved: bool, reviewer: String, note: String, confirmed: bool, direction_indices: Array)
signal train_requested
signal evaluate_requested(autonomous: bool)
signal local_check_requested(model_path: String, lora_path: String)
signal local_generate_requested(model_path: String, lora_path: String, prompt: String, negative_prompt: String, width: int, height: int, steps: int, seed: int, use_lora: bool, lora_strength: float)
signal local_stop_requested
signal local_model_browse_requested
signal local_lora_browse_requested
signal local_models_folder_requested
signal generation_save_requested(path: String)

var reviewer: LineEdit
var note: LineEdit
var confirmation: CheckBox
var review_scope: OptionButton
var direction_checks: Array[CheckBox] = []
var direction_grid: GridContainer
var approve_button: Button
var reject_button: Button
var prompt: TextEdit
var negative_prompt: TextEdit
var model_path: LineEdit
var lora_path: LineEdit
var width_input: SpinBox
var height_input: SpinBox
var steps_input: SpinBox
var seed_input: SpinBox
var use_lora: CheckBox
var lora_strength_input: SpinBox
var autonomous: CheckBox
var report: RichTextLabel
var generated_preview: TextureRect
var generated_path := ""
var local_status: Label
var generate_button: Button
var save_button: Button
var history_list: ItemList
var history_preview: TextureRect
var history_ids: Array[String] = []

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var heading := Label.new(); heading.text = "HYPERLEARN LAB · MEMÓRIA E GERAÇÃO LOCAL"; heading.add_theme_font_size_override("font_size", 21); add_child(heading)
	var scope := Label.new(); scope.text = "Armazena decisões humanas, treina um classificador local de preferência e procura exemplos aprovados parecidos. Os sinais visuais não reconhecem anatomia; a automação recusa casos incertos."; scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(scope)
	var history := HBoxContainer.new(); history.add_theme_constant_override("separation", 10); history.custom_minimum_size.y = 150; add_child(history)
	history_list = ItemList.new(); history_list.custom_minimum_size = Vector2(360, 144); history_list.item_selected.connect(_on_example_selected); history.add_child(history_list)
	history_preview = TextureRect.new(); history_preview.custom_minimum_size = Vector2(560, 144); history_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL; history_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; history_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; history_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; history.add_child(history_preview)
	report = RichTextLabel.new(); report.custom_minimum_size.y = 90; add_child(report)
	var feedback := HBoxContainer.new(); feedback.add_theme_constant_override("separation", 8); add_child(feedback)
	reviewer = LineEdit.new(); reviewer.placeholder_text = "Seu nome / perfil de revisão"; reviewer.custom_minimum_size.x = 220; feedback.add_child(reviewer)
	note = LineEdit.new(); note.placeholder_text = "Por que aprovou/reprovou? (opcional)"; note.size_flags_horizontal = Control.SIZE_EXPAND_FILL; feedback.add_child(note)
	confirmation = CheckBox.new(); confirmation.text = "Confirmei a decisão artística do documento atual"; add_child(confirmation)
	var scope_row := HBoxContainer.new(); scope_row.add_theme_constant_override("separation", 8); add_child(scope_row)
	var scope_label := Label.new(); scope_label.text = "Escopo da revisão"; scope_row.add_child(scope_label)
	review_scope = OptionButton.new(); review_scope.add_item("O pack inteiro · todas as direções"); review_scope.add_item("Escolher direções específicas…"); review_scope.item_selected.connect(_on_scope_changed); scope_row.add_child(review_scope)
	direction_grid = GridContainer.new(); direction_grid.columns = 4; direction_grid.visible = false; add_child(direction_grid)
	for index in 8:
		var direction_check := CheckBox.new(); direction_check.text = ["Norte", "Nordeste", "Leste", "Sudeste", "Sul", "Sudoeste", "Oeste", "Noroeste"][index]; direction_check.button_pressed = true; direction_check.toggled.connect(func(_pressed: bool): _update_review_buttons()); direction_grid.add_child(direction_check); direction_checks.append(direction_check)
	var scope_hint := Label.new(); scope_hint.text = "Revisões parciais ficam registradas por direção; só revisões do pack inteiro entram no classificador geral."; scope_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(scope_hint)
	var decisions := HBoxContainer.new(); decisions.add_theme_constant_override("separation", 8); add_child(decisions)
	approve_button = Button.new(); approve_button.text = "Registrar como aprovado"; approve_button.pressed.connect(func(): review_requested.emit(true, reviewer.text, note.text, confirmation.button_pressed, selected_direction_indices())); decisions.add_child(approve_button)
	reject_button = Button.new(); reject_button.text = "Registrar como reprovado"; reject_button.pressed.connect(func(): review_requested.emit(false, reviewer.text, note.text, confirmation.button_pressed, selected_direction_indices())); decisions.add_child(reject_button)
	_update_review_buttons()
	var train := Button.new(); train.text = "Treinar / recalibrar"; train.pressed.connect(func(): train_requested.emit()); decisions.add_child(train)
	var assess := Button.new(); assess.text = "Avaliar documento atual"; assess.pressed.connect(func(): evaluate_requested.emit(autonomous.button_pressed)); decisions.add_child(assess)
	autonomous = CheckBox.new(); autonomous.text = "Permitir decisão autônoma quando a validação permitir (desativado por padrão)"; autonomous.button_pressed = false; add_child(autonomous)
	var local_heading := Label.new(); local_heading.text = "GERAÇÃO LOCAL NATIVA · stable-diffusion.cpp (sem GPT e sem ComfyUI)"; local_heading.add_theme_font_size_override("font_size", 16); add_child(local_heading)
	var local_help := Label.new(); local_help.text = "EXPERIMENTO REPROVADO PARA A DIREÇÃO DE ARTE: SD 1.5 e DreamShaper locais não atingiram anatomia, equipamento e pixel art exigidos. Motor mantido apenas para pesquisa manual; não é a rota de produção recomendada. Nenhuma geração começa automaticamente."; local_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(local_help)
	var model_row := HBoxContainer.new(); model_row.add_theme_constant_override("separation", 8); add_child(model_row)
	model_path = LineEdit.new(); model_path.placeholder_text = "Caminho do modelo Stable Diffusion 1.5 GGUF local"; model_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL; model_row.add_child(model_path)
	var model_browse := Button.new(); model_browse.text = "Localizar modelo…"; model_browse.pressed.connect(func(): local_model_browse_requested.emit()); model_row.add_child(model_browse)
	var models_folder := Button.new(); models_folder.text = "Abrir pasta de modelos"; models_folder.pressed.connect(func(): local_models_folder_requested.emit()); model_row.add_child(models_folder)
	var lora_row := HBoxContainer.new(); lora_row.add_theme_constant_override("separation", 8); add_child(lora_row)
	lora_path = LineEdit.new(); lora_path.placeholder_text = "LoRA local opcional de pixel art"; lora_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lora_row.add_child(lora_path)
	var lora_browse := Button.new(); lora_browse.text = "Localizar LoRA…"; lora_browse.pressed.connect(func(): local_lora_browse_requested.emit()); lora_row.add_child(lora_browse)
	use_lora = CheckBox.new(); use_lora.text = "Aplicar LoRA de pixel art experimental"; use_lora.button_pressed = false; add_child(use_lora)
	var settings := HBoxContainer.new(); settings.add_theme_constant_override("separation", 8); add_child(settings)
	width_input = _number_field("Largura", 256, 768, 64, 512, settings)
	height_input = _number_field("Altura", 256, 768, 64, 512, settings)
	steps_input = _number_field("Passos", 4, 30, 1, 8, settings)
	seed_input = _number_field("Seed (-1 = aleatória)", -1, 2147483647, 1, -1, settings)
	lora_strength_input = _number_field("Força LoRA", 0, 1.5, 0.05, 0.75, settings)
	var prompt_label := Label.new(); prompt_label.text = "Descrição do sprite (até 5.000 caracteres)"; add_child(prompt_label)
	prompt = TextEdit.new(); prompt.placeholder_text = "Personagem completo, vista, ação, silhueta, roupa, materiais, pose legível, enquadramento e restrições anatômicas…"; prompt.custom_minimum_size.y = 82; prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; add_child(prompt)
	var negative_label := Label.new(); negative_label.text = "Restrições / prompt negativo"; add_child(negative_label)
	negative_prompt = TextEdit.new(); negative_prompt.text = "detached parts, floating limbs, extra arms, extra fingers, malformed hands, broken anatomy, cropped character, text, watermark"; negative_prompt.custom_minimum_size.y = 54; negative_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; add_child(negative_prompt)
	var generation_row := HBoxContainer.new(); generation_row.add_theme_constant_override("separation", 8); add_child(generation_row)
	var check := Button.new(); check.text = "Iniciar / verificar motor local"; check.pressed.connect(func(): local_check_requested.emit(model_path.text, lora_path.text)); generation_row.add_child(check)
	var stop_engine := Button.new(); stop_engine.text = "Parar motor"; stop_engine.pressed.connect(func(): local_stop_requested.emit()); generation_row.add_child(stop_engine)
	generate_button = Button.new(); generate_button.text = "Gerar candidato local"; generate_button.pressed.connect(func(): local_generate_requested.emit(model_path.text, lora_path.text, prompt.text, negative_prompt.text, int(width_input.value), int(height_input.value), int(steps_input.value), int(seed_input.value), use_lora.button_pressed, lora_strength_input.value)); generation_row.add_child(generate_button)
	save_button = Button.new(); save_button.text = "Salvar PNG gerado…"; save_button.disabled = true; save_button.pressed.connect(func(): if not generated_path.is_empty(): generation_save_requested.emit(generated_path)); generation_row.add_child(save_button)
	generated_preview = TextureRect.new(); generated_preview.custom_minimum_size = Vector2(0, 340); generated_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL; generated_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; generated_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; generated_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; add_child(generated_preview)

func show_report(counts: Dictionary, model: Dictionary, evaluate: Dictionary = {}, examples: Array = []) -> void:
	set_examples(examples)
	var learned := "Modelo ainda não treinado."
	if not model.is_empty():
		learned = "Treino: %d exemplos completos. Validação fora dos projetos de treino: %d exemplos / %d projetos em %d folds; acurácia balanceada %.0f%%; recall aprovado/reprovado %.0f%% / %.0f%%; Brier %.3f. Sinais visuais não avaliam anatomia." % [int(model.get("training_examples", 0)), int(model.get("validation_examples", 0)), int(model.get("validation_projects_scored", 0)), int(model.get("validation_folds", 0)), float(model.get("validation_balanced_accuracy", 0.0)) * 100.0, float(model.get("validation_approved_recall", 0.0)) * 100.0, float(model.get("validation_rejected_recall", 0.0)) * 100.0, float(model.get("validation_brier_score", 1.0))]
	var auto_state := "AUTONOMIA BLOQUEADA até haver amostra diversa e validação independente."
	if evaluate.get("eligible_for_autonomy", false):
		auto_state = "Modelo apto pelo critério estatístico; candidato atual: %.1f%%. Isso não equivale a aprovação humana nem libera exportação final." % (float(evaluate.get("probability", 0.0)) * 100.0)
		if evaluate.get("ready", false): auto_state = "Decisão candidata: %s (%.1f%%). Isso não equivale a aprovação humana nem libera exportação final." % [str(evaluate.get("decision", "")), float(evaluate.get("probability", 0.0)) * 100.0]
	var model_scope := ""
	if not model.is_empty(): model_scope = "\nClassificador treinado só com avaliações de packs completos: %d aprovados / %d reprovados." % [int(model.get("approved", 0)), int(model.get("rejected", 0))]
	report.text = "Base local: %d aprovados / %d reprovados / %d no total%s\n%s\n%s" % [counts.get("approved", 0), counts.get("rejected", 0), counts.get("total", 0), model_scope, learned, auto_state]
	var new_ids: Array[String] = []
	for example in examples: new_ids.append(str(example.id))
	if new_ids == history_ids: return
	var selected_id := ""
	if history_list.get_selected_items().size() > 0 and history_list.get_selected_items()[0] < history_ids.size(): selected_id = history_ids[history_list.get_selected_items()[0]]
	history_ids = new_ids
	history_list.clear()
	for example in examples:
		var symbol := "✓" if int(example.label) == 1 else "×"
		history_list.add_item("%s %s · rev %s" % [symbol, str(example.get("project_name", "Pack")), str(example.get("revision", "?"))])
		var index := history_list.item_count - 1
		history_list.set_item_tooltip(index, "%s\nSHA-256 %s\n%s\n%s" % [example.get("at", ""), example.get("asset_sha256", ""), example.get("reviewer", ""), example.get("note", "")])
	var selected_index := history_ids.find(selected_id)
	if selected_index >= 0: history_list.select(selected_index); _on_example_selected(selected_index)
	elif not examples.is_empty(): history_list.select(examples.size() - 1); _on_example_selected(examples.size() - 1)

func _on_example_selected(index: int) -> void:
	if index < 0: return
	var saved_examples: Variant = get_meta("examples", [])
	if index >= saved_examples.size(): return
	var image := Image.new()
	if image.load(str(saved_examples[index].get("preview_path", ""))) == OK: history_preview.texture = ImageTexture.create_from_image(image)

func set_examples(examples: Array) -> void:
	set_meta("examples", examples)

func selected_direction_indices() -> Array[int]:
	var selected: Array[int] = []
	if not is_instance_valid(review_scope) or review_scope.selected == 0:
		return selected
	for index in direction_checks.size():
		if direction_checks[index].button_pressed: selected.append(index)
	return selected

func _on_scope_changed(index: int) -> void:
	direction_grid.visible = index == 1
	_update_review_buttons()

func _update_review_buttons() -> void:
	if not is_instance_valid(approve_button) or not is_instance_valid(reject_button): return
	var enabled := review_scope.selected == 0 or not selected_direction_indices().is_empty()
	approve_button.disabled = not enabled
	reject_button.disabled = not enabled

func set_local_status(message: String, busy: bool = false) -> void:
	local_status.text = message
	generate_button.disabled = busy

func set_generated_image(path: String) -> bool:
	var image := Image.new()
	if image.load(path) != OK: return false
	generated_path = path
	generated_preview.texture = ImageTexture.create_from_image(image)
	save_button.disabled = false
	return true

func _number_field(caption: String, minimum: float, maximum: float, step: float, initial: float, parent: Control) -> SpinBox:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(group)
	var title := Label.new()
	title.text = caption
	group.add_child(title)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = initial
	input.allow_greater = false
	input.allow_lesser = false
	group.add_child(input)
	return input
