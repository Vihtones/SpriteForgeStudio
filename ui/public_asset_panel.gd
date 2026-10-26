extends VBoxContainer
signal tile_requested(id: String, index: int)
signal tileset_requested(id: String)
signal spritesheet_requested(id: String)
const Library = preload("res://core/public_asset_library.gd")
var library = Library.new()
var list: ItemList
var description: RichTextLabel
var preview: TextureRect
var filtered: Array = []
var source_id := ""
var tile_index: SpinBox
var tile_button: Button
var tileset_button: Button
var sheet_button: Button

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var title := Label.new(); title.text = "BIBLIOTECA PÚBLICA • CURADORIA E PROCEDÊNCIA"; title.add_theme_font_size_override("font_size", 23); add_child(title)
	var note := Label.new(); note.text = "CC0 e spritesheets com atribuição disponíveis offline. Tudo entra como candidato; nenhuma importação recebe aprovação artística automaticamente."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(note)
	var search := LineEdit.new(); search.placeholder_text = "Buscar por nome, categoria ou autor…"; search.text_changed.connect(_search); add_child(search)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(split)
	list = ItemList.new(); list.custom_minimum_size = Vector2(300, 330); list.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.add_child(list); list.item_selected.connect(_select)
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; split.add_child(right)
	description = RichTextLabel.new(); description.custom_minimum_size.y = 195; description.size_flags_vertical = Control.SIZE_EXPAND_FILL; right.add_child(description)
	preview = TextureRect.new(); preview.custom_minimum_size.y = 260; preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; right.add_child(preview)
	var toolbar := HFlowContainer.new(); toolbar.add_theme_constant_override("h_separation", 8); add_child(toolbar)
	var source := Button.new(); source.text = "Abrir fonte original"; source.pressed.connect(func():
		var url: String = library.find(source_id).get("source", "")
		if url.begins_with("https://"): OS.shell_open(url)
	); toolbar.add_child(source)
	tile_index = SpinBox.new(); tile_index.min_value = 0; tile_index.prefix = "Tile "; tile_index.step = 1; toolbar.add_child(tile_index)
	tile_button = Button.new(); tile_button.text = "Editar tile em novo projeto"; tile_button.pressed.connect(func(): tile_requested.emit(source_id, int(tile_index.value))); toolbar.add_child(tile_button)
	sheet_button = Button.new(); sheet_button.text = "Importar spritesheet para edição"; sheet_button.pressed.connect(func(): spritesheet_requested.emit(source_id)); toolbar.add_child(sheet_button)
	tileset_button = Button.new(); tileset_button.text = "Aplicar tileset ao mapa…"; tileset_button.pressed.connect(func(): tileset_requested.emit(source_id)); toolbar.add_child(tileset_button)
	_search("")

func _search(query: String) -> void:
	filtered = library.search(query); list.clear()
	for entry in filtered:
		var status := "[Offline • tile] " if entry.has("atlas") else ("[Offline • animação] " if entry.get("spritesheet", {}).has("frame_size") else ("[Offline • sheet] " if entry.has("spritesheet") else "[Fonte] "))
		list.add_item(status + str(entry.name))
	if filtered.is_empty():
		source_id = ""; description.text = "Nenhuma fonte corresponde à busca."; preview.texture = null; tile_button.disabled = true; sheet_button.disabled = true; tileset_button.disabled = true
	else: list.select(0); _select(0)

func _select(index: int) -> void:
	if index < 0 or index >= filtered.size(): return
	var entry: Dictionary = filtered[index]; source_id = str(entry.id)
	description.text = "%s\nAutor: %s\nLicença: %s · Conferida em %s\nFonte: %s\nCategorias: %s\n\n%s\n\nAprovação artística: pendente. Treinamento de IA: não avaliado." % [entry.name, entry.author, entry.license, entry.checked_at, entry.source, ", ".join(entry.categories), entry.compatibility]
	if entry.get("spritesheet", {}).has("frame_size"):
		description.text += "\n\nAção: %s · %d quadros de %d px\nLinhas direcionais: %s" % [str(entry.animation), int(entry.frame_count), int(entry.spritesheet.frame_size), ", ".join(entry.get("directions", []))]
	var credit_members: Array = entry.get("credit_members", [])
	if not credit_members.is_empty():
		var names := PackedStringArray()
		for member in credit_members: names.append(str(member).get_file())
		description.text += "\n\nCréditos integrais preservados no arquivo: " + ", ".join(names)
	var installed: bool = entry.has("atlas") or entry.has("spritesheet")
	var asset: Dictionary = entry.get("atlas", entry.get("spritesheet", {}))
	var cell_size := int(asset.get("cell_size", 0))
	var can_edit_cell := installed and cell_size > 0 and int(asset.get("width", 0)) % cell_size == 0 and int(asset.get("height", 0)) % cell_size == 0
	tile_button.disabled = not can_edit_cell; sheet_button.disabled = not entry.has("spritesheet"); tileset_button.disabled = not entry.has("atlas")
	preview.texture = null
	if installed:
		var image: Image = library.image(source_id)
		if image != null:
			preview.texture = ImageTexture.create_from_image(image)
			if can_edit_cell:
				tile_index.max_value = int(asset.width / cell_size * (asset.height / cell_size)) - 1
				tile_index.value = 0
				description.text += "\nGrade de edição declarada: %d × %d px." % [cell_size, cell_size]
		else:
			description.text += "\nERRO: " + library.error; tile_button.disabled = true; sheet_button.disabled = true; tileset_button.disabled = true
