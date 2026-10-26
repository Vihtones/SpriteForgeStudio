extends VBoxContainer
## Presentation-only panel. User intent is signalled to the Studio orchestrator.
signal generate_requested(payload: Dictionary)
signal save_requested(path: String)

var prompt_edit: TextEdit
var model_picker: OptionButton
var quality_picker: OptionButton
var transparent_check: CheckBox
var generate_button: Button
var save_button: Button
var status_label: Label
var preview: TextureRect
var _image_path := ""

func _ready() -> void:
	name = "IA Assistida"
	add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = "GERAÇÃO DE IMAGEM OPCIONAL"
	heading.add_theme_font_size_override("font_size", 18)
	add_child(heading)
	var note := Label.new()
	note.text = "Crie um rascunho visual a partir de uma descrição. A geração usa a internet e pode gerar cobrança; nenhuma chamada acontece sem sua aprovação individual."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 8)
	add_child(options)
	var model_label := Label.new()
	model_label.text = "Modelo"
	options.add_child(model_label)
	model_picker = OptionButton.new()
	model_picker.add_item("Sunburst · precisão", 0)
	model_picker.add_item("Flare · geração geral", 1)
	model_picker.custom_minimum_size.x = 210
	options.add_child(model_picker)
	var quality_label := Label.new()
	quality_label.text = "Qualidade"
	options.add_child(quality_label)
	quality_picker = OptionButton.new()
	for quality in ["low", "medium", "high", "xhigh", "max", "auto"]:
		quality_picker.add_item(quality.capitalize())
		quality_picker.set_item_metadata(quality_picker.item_count - 1, quality)
	quality_picker.select(0)
	options.add_child(quality_picker)
	transparent_check = CheckBox.new()
	transparent_check.text = "Fundo transparente"
	transparent_check.button_pressed = true
	transparent_check.tooltip_text = "O PNG com transparência facilita a preparação de elementos e sprites."
	options.add_child(transparent_check)
	var prompt_label := Label.new()
	prompt_label.text = "Descrição da imagem"
	add_child(prompt_label)
	prompt_edit = TextEdit.new()
	prompt_edit.custom_minimum_size = Vector2(0, 116)
	prompt_edit.placeholder_text = "Ex.: sprite pixel art de um aventureiro, vista lateral, contorno nítido, paleta limitada, fundo transparente"
	prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(prompt_edit)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	generate_button = Button.new()
	generate_button.text = "Preparar geração…"
	generate_button.pressed.connect(_on_generate_pressed)
	actions.add_child(generate_button)
	save_button = Button.new()
	save_button.text = "Salvar PNG como…"
	save_button.disabled = true
	save_button.pressed.connect(func(): if not _image_path.is_empty(): save_requested.emit(_image_path))
	actions.add_child(save_button)
	status_label = Label.new()
	status_label.text = "Aguardando. O editor permanece funcional sem internet ou chave."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(0, 440)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(preview)

func _on_generate_pressed() -> void:
	var model := "gpt-image-2.5-sunburst" if model_picker.selected == 0 else "gpt-image-2.5-flare"
	var quality: String = str(quality_picker.get_item_metadata(quality_picker.selected))
	generate_requested.emit({
		"prompt": prompt_edit.text,
		"model": model,
		"quality": quality,
		"transparent": transparent_check.button_pressed
	})

func set_busy(busy: bool) -> void:
	generate_button.disabled = busy
	model_picker.disabled = busy
	quality_picker.disabled = busy
	transparent_check.disabled = busy
	prompt_edit.editable = not busy
	if busy:
		status_label.text = "Gerando uma imagem… esta etapa pode levar até dois minutos. Não há repetição automática."

func set_status(message: String) -> void:
	status_label.text = message

func set_preview(image_path: String) -> bool:
	var image := Image.new()
	if image.load(image_path) != OK:
		return false
	preview.texture = ImageTexture.create_from_image(image)
	_image_path = image_path
	save_button.disabled = false
	return true

func clear_pending_preview() -> void:
	_image_path = ""
	save_button.disabled = true
