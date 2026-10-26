extends VBoxContainer
## Displays injected state and emits intent; owns no queue or production logic.
signal configuration_requested(values: Dictionary)
signal pause_requested
signal scan_requested
signal clear_requested
signal candidate_requested(path: String)
signal report_requested(path: String)
var input: LineEdit
var output: LineEdit
var quantize: CheckBox
var nonempty: CheckBox
var resume: CheckBox
var interval: SpinBox
var status: Label
var listing: ItemList
var detail: Label
var entries: Array = []
var initialized: bool = false

func caption(text: String) -> Label:
	var label := Label.new(); label.text = text; add_child(label); return label

func action(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text; button.pressed.connect(callback); parent.add_child(button); return button

func path_row(title: String) -> LineEdit:
	caption(title)
	var row := HBoxContainer.new(); add_child(row)
	var field := LineEdit.new(); field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(field)
	action(row, "Escolher pasta", func():
		var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dialog.title = title; dialog.dir_selected.connect(func(path): field.text = path; dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free); add_child(dialog); dialog.popup_centered(Vector2i(800, 520))
	)
	return field

func _ready() -> void:
	name = "Automação"
	add_theme_constant_override("separation", 10)
	caption("PRODUÇÃO LOCAL AUTOMÁTICA").add_theme_font_size_override("font_size", 22)
	var intro := caption("Projetos salvos → cópia candidata → correção opcional → validação → exportação → relatório.\nMonitora arquivos .sfs.json no primeiro nível da pasta; o programa precisa permanecer aberto.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input = path_row("Pasta de entrada — projetos salvos")
	output = path_row("Pasta de saída — separada da entrada")
	var options := HFlowContainer.new(); add_child(options)
	quantize = CheckBox.new(); quantize.text = "Ajustar pixels à paleta nas cópias"; options.add_child(quantize)
	nonempty = CheckBox.new(); nonempty.text = "Exigir arte não vazia"; options.add_child(nonempty)
	resume = CheckBox.new(); resume.text = "Retomar ao abrir o programa"; options.add_child(resume)
	var controls := HBoxContainer.new(); add_child(controls)
	action(controls, "Aplicar e iniciar", func(): configuration_requested.emit({"input": input.text.strip_edges(), "output": output.text.strip_edges(), "quantize": quantize.button_pressed, "require_nonempty": nonempty.button_pressed, "resume": resume.button_pressed, "interval": int(interval.value), "enabled": true}))
	action(controls, "Pausar automação e fila", func(): pause_requested.emit())
	action(controls, "Verificar pasta agora", func(): scan_requested.emit())
	var label := Label.new(); label.text = "Intervalo (s)"; controls.add_child(label)
	interval = SpinBox.new(); interval.min_value = 2; interval.max_value = 3600; interval.value = 5; controls.add_child(interval)
	status = caption("")
	listing = ItemList.new(); listing.size_flags_vertical = Control.SIZE_EXPAND_FILL; listing.custom_minimum_size.y = 130; add_child(listing)
	listing.item_selected.connect(func(i): detail.text = str(entries[i].source) + "\n" + str(entries[i].output) + "\n" + str(entries[i].get("error", "")))
	detail = caption("Selecione uma execução para ver os caminhos e possíveis falhas."); detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new(); add_child(actions)
	action(actions, "Abrir candidato", func():
		if not listing.get_selected_items().is_empty(): candidate_requested.emit(str(entries[listing.get_selected_items()[0]].output).path_join("candidate.sfs.json"))
	)
	action(actions, "Ver relatório", func():
		if not listing.get_selected_items().is_empty(): report_requested.emit(str(entries[listing.get_selected_items()[0]].output).path_join("production-report.json"))
	)
	action(actions, "Esquecer registros finalizados", func(): clear_requested.emit())
	var note := caption("O ajuste de paleta é opcional e respeita camadas bloqueadas e pixels protegidos. Aprovação artística permanece manual.\nEsquecer registros permite processá-los novamente. Pausar deixa a operação atual terminar; cancele em Lotes se necessário.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func display(config: Dictionary, ledger: Dictionary, error: String) -> void:
	if not initialized:
		input.text = config.input; output.text = config.output; quantize.button_pressed = config.quantize
		nonempty.button_pressed = config.require_nonempty; resume.button_pressed = config.resume; interval.value = config.interval
		initialized = true
	status.text = ("Monitoramento ativo" if config.enabled else "Monitoramento pausado") + " • %d registros" % ledger.size() + (" • " + error if error != "" else "")
	var selected := ""
	if not listing.get_selected_items().is_empty(): selected = entries[listing.get_selected_items()[0]].get("token", "")
	entries = ledger.values().filter(func(entry): return entry is Dictionary and entry.has_all(["source", "output", "status"]))
	listing.clear()
	for entry in entries:
		listing.add_item("[%s] %s" % [entry.status, str(entry.source).get_file()])
		if entry.get("token", "") == selected: listing.select(listing.item_count - 1)
