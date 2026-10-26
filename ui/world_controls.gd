extends VBoxContainer
signal command(action: Dictionary)
const World = preload("res://core/world_data.gd")
var listing: ItemList
var layer_name: LineEdit
var visibility: CheckBox
var locked: CheckBox
var opacity: SpinBox
var width: SpinBox
var height: SpinBox
var terrain_list: OptionButton
var terrain_name: LineEdit
var terrain_mode: OptionButton
var terrain_outside: CheckBox
var terrain_button: Button
var terrain_start: SpinBox
var palette: GridContainer
var doors_list: ItemList
var door_name: LineEdit
var rooms_list: ItemList
var room_name: LineEdit
var village_seed: SpinBox
var village_roles: Dictionary = {}
var camera_zoom: SpinBox
var camera_smoothing: SpinBox
var camera_pixel_snap: CheckBox
var ambient_picker: ColorPickerButton
var selected_door := -1
var selected_connection := -1
var _display_door_count := 0
var tile_buttons: Array[Button] = []
var syncing := false
var palette_signature := ""
var village_role_signature := ""

func title(text: String) -> void:
	var label := Label.new(); label.text = text; add_child(label)

func row() -> HBoxContainer:
	var box := HBoxContainer.new(); add_child(box); return box

func button(parent: Node, text: String, action: Dictionary) -> Button:
	var result := Button.new(); result.text = text; parent.add_child(result); result.pressed.connect(func(): command.emit(action)); return result

func number(parent: Node, low: float, high: float, value: float) -> SpinBox:
	var result := SpinBox.new(); result.min_value = low; result.max_value = high; result.value = value; parent.add_child(result); return result

func _read_village_roles() -> Dictionary:
	var result := {}
	for role in village_roles:
		var picker: OptionButton = village_roles[role]
		var value := picker.get_selected_id()
		result[role] = -1 if value == -2 else value
	return result

func _refresh_village_roles(textures: Array) -> void:
	var optional := ["structure", "vegetation"]
	for role in village_roles:
		var picker: OptionButton = village_roles[role]
		var previous := picker.get_selected_id() if picker.item_count > 0 else -2
		picker.clear()
		if optional.has(role): picker.add_item("Não usar", -2)
		for index in textures.size(): picker.add_item("Tile %03d" % index, index)
		var fallback: int = {"ground": 0, "path": 1, "plaza": 2, "structure": 3, "vegetation": 4}[role]
		var desired := previous if previous >= 0 and previous < textures.size() else (previous if previous == -2 and optional.has(role) else fallback)
		if desired >= textures.size() and optional.has(role): desired = -2
		if desired >= 0 and desired < textures.size(): picker.select(picker.get_item_index(desired))
		elif optional.has(role): picker.select(picker.get_item_index(-2))
		elif picker.item_count > 0: picker.select(0)

func _ready() -> void:
	custom_minimum_size.x = 300
	add_theme_constant_override("separation", 8)
	title("SALAS DO PROJETO — até 32 cenas")
	rooms_list = ItemList.new(); rooms_list.custom_minimum_size.y = 90; add_child(rooms_list)
	rooms_list.item_selected.connect(func(index): if not syncing: command.emit({"kind": "select_room", "index": index}))
	title("GERAÇÃO ASSISTIDA — vilarejo jogável")
	var generation_row := row()
	village_seed = number(generation_row, -2147483648, 2147483647, 42)
	village_seed.prefix = "Seed: "
	var generate_button := Button.new(); generate_button.text = "Gerar layout"; generation_row.add_child(generate_button)
	generate_button.pressed.connect(func(): command.emit({"kind": "generate_village", "seed": int(village_seed.value), "roles": _read_village_roles()}))
	for role in ["ground", "path", "plaza", "structure", "vegetation"]:
		var role_row := row()
		var role_label := Label.new(); role_label.text = {"ground": "Solo", "path": "Caminho", "plaza": "Praça", "structure": "Construção", "vegetation": "Vegetação"}[role]; role_row.add_child(role_label)
		var picker := OptionButton.new(); picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; role_row.add_child(picker)
		village_roles[role] = picker
	var generation_note := Label.new(); generation_note.text = "Escolha o tile de cada papel. Construções e vegetação são placeholders de layout; o gerador não inventa arte. Substitui a sala atual; Desfazer restaura."; generation_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(generation_note)
	title("CÂMERA PIXEL — também aplicada ao personagem exportado")
	var camera_row := row()
	camera_zoom = number(camera_row, 1, 6, 2); camera_zoom.prefix = "Zoom ×"
	camera_smoothing = number(camera_row, 0, 20, 5); camera_smoothing.step = 0.5; camera_smoothing.prefix = "Suavização: "
	camera_pixel_snap = CheckBox.new(); camera_pixel_snap.text = "Pixel snap"; add_child(camera_pixel_snap)
	var camera_apply := Button.new(); camera_apply.text = "Aplicar câmera à sala"; add_child(camera_apply)
	camera_apply.pressed.connect(func(): command.emit({"kind": "camera_settings", "settings": {"zoom": int(camera_zoom.value), "smoothing": camera_smoothing.value, "pixel_snap": camera_pixel_snap.button_pressed}}))
	title("LUZ AMBIENTE — cor global da cena")
	var ambient_row := row()
	ambient_picker = ColorPickerButton.new(); ambient_picker.color = Color.WHITE; ambient_row.add_child(ambient_picker)
	var ambient_apply := Button.new(); ambient_apply.text = "Aplicar luz ambiente"; ambient_row.add_child(ambient_apply)
	ambient_apply.pressed.connect(func(): command.emit({"kind": "ambient_color", "value": ambient_picker.color.to_html()}))
	var room_actions := row()
	button(room_actions, "Nova sala", {"kind": "add_room"})
	button(room_actions, "Remover sala", {"kind": "remove_room"})
	room_name = LineEdit.new(); room_name.placeholder_text = "Nome da sala"; add_child(room_name)
	var rename_room_button := Button.new(); rename_room_button.text = "Renomear sala"; add_child(rename_room_button)
	rename_room_button.pressed.connect(func(): command.emit({"kind": "rename_room", "value": room_name.text}))
	title("CAMADAS DO MAPA")
	listing = ItemList.new(); listing.custom_minimum_size.y = 120; add_child(listing)
	listing.item_selected.connect(func(index): if not syncing: command.emit({"kind": "layer", "index": index}))
	var actions := row()
	button(actions, "+", {"kind": "add_layer"}); button(actions, "−", {"kind": "remove_layer"}); button(actions, "↑", {"kind": "move_layer", "offset": -1}); button(actions, "↓", {"kind": "move_layer", "offset": 1})
	layer_name = LineEdit.new(); add_child(layer_name)
	layer_name.text_submitted.connect(func(value): command.emit({"kind": "rename", "value": value}))
	var rename := Button.new(); rename.text = "Aplicar nome"; add_child(rename); rename.pressed.connect(func(): command.emit({"kind": "rename", "value": layer_name.text}))
	visibility = CheckBox.new(); visibility.text = "Visível"; add_child(visibility)
	visibility.toggled.connect(func(value): if not syncing: command.emit({"kind": "visible", "value": value}))
	locked = CheckBox.new(); locked.text = "Bloqueada (tiles/terreno)"; add_child(locked)
	locked.toggled.connect(func(value): if not syncing: command.emit({"kind": "locked", "value": value}))
	title("Opacidade (%)")
	opacity = number(self, 0, 100, 100)
	opacity.value_changed.connect(func(value): if not syncing: command.emit({"kind": "opacity", "value": value / 100.0}))
	title("DIMENSÕES — até 128 × 128")
	var dimensions := row(); width = number(dimensions, 1, 128, 24); height = number(dimensions, 1, 128, 16)
	var resize_button := Button.new(); resize_button.text = "Redimensionar"; add_child(resize_button)
	resize_button.pressed.connect(func(): command.emit({"kind": "resize", "width": int(width.value), "height": int(height.value)}))
	title("TERRENO — máscara N=1 E=2 S=4 W=8; blob N NE E SE S SW W NW")
	terrain_list = OptionButton.new(); add_child(terrain_list)
	terrain_list.item_selected.connect(func(index): if not syncing: command.emit({"kind": "terrain", "value": index}))
	terrain_name = LineEdit.new(); terrain_name.placeholder_text = "Nome do terreno"; add_child(terrain_name)
	terrain_mode = OptionButton.new(); terrain_mode.add_item("4 lados · 16 tiles"); terrain_mode.add_item("8 vizinhos · 47 tiles"); add_child(terrain_mode)
	terrain_mode.item_selected.connect(func(index): _update_terrain_button())
	terrain_outside = CheckBox.new(); terrain_outside.text = "Borda do mapa conta como terreno"; add_child(terrain_outside)
	terrain_start = number(self, 0, 255, 0); terrain_start.prefix = "Primeiro tile: "
	terrain_button = Button.new(); add_child(terrain_button)
	terrain_button.pressed.connect(func():
		var blob := terrain_mode.selected == 1
		command.emit({"kind": "add_terrain", "name": terrain_name.text, "start": int(terrain_start.value), "mode": "blob47" if blob else "edge16", "outside": "same" if terrain_outside.button_pressed else "different"})
	)
	_update_terrain_button()
	title("PALETA DE TILES — clique para escolher")
	palette = GridContainer.new(); palette.columns = 5; add_child(palette)
	title("PORTAS — conecte duas células livres")
	doors_list = ItemList.new(); doors_list.custom_minimum_size.y = 90; add_child(doors_list)
	doors_list.item_selected.connect(func(index):
		selected_door = index if index < int(_display_door_count) else -1
		selected_connection = index - int(_display_door_count) if index >= int(_display_door_count) else -1
	)
	door_name = LineEdit.new(); door_name.placeholder_text = "Nome da conexão (ex.: Casa / Praça)"; add_child(door_name)
	var door_name_button := Button.new(); door_name_button.text = "Aplicar nome à próxima conexão"; add_child(door_name_button)
	door_name_button.pressed.connect(func(): command.emit({"kind": "door_name", "value": door_name.text}))
	var remove_door_button := Button.new(); remove_door_button.text = "Remover conexão selecionada"; add_child(remove_door_button)
	remove_door_button.pressed.connect(func():
		if selected_connection >= 0: command.emit({"kind": "remove_connection", "index": selected_connection})
		else: command.emit({"kind": "remove_door", "index": selected_door})
	)

func _update_terrain_button() -> void:
	var count := 47 if terrain_mode.selected == 1 else 16
	terrain_button.text = "Criar terreno: %d tiles consecutivos" % count

func display(map: Dictionary, textures: Array, tile: int, terrain: int) -> void:
	syncing = true
	World.ensure_rooms(map)
	rooms_list.clear()
	for i in map.rooms.size():
		rooms_list.add_item(map.rooms[i].name)
		if i == int(map.active_room): rooms_list.select(i)
	if not room_name.has_focus(): room_name.text = map.rooms[int(map.active_room)].name
	listing.clear()
	var index: int = 0
	for layer in World.layers(map):
		listing.add_item(("● " if layer.visible else "○ ") + layer.name + (" 🔒" if layer.locked else ""))
		if index == map.active_layer: listing.select(index)
		index += 1
	var current := World.metadata(map)
	var camera: Dictionary = map.get("camera_settings", {"zoom": 2, "smoothing": 5.0, "pixel_snap": true})
	camera_zoom.value = int(camera.zoom); camera_smoothing.value = float(camera.smoothing); camera_pixel_snap.button_pressed = bool(camera.pixel_snap)
	ambient_picker.color = Color(str(map.get("ambient_color", "#ffffff")))
	if not layer_name.has_focus(): layer_name.text = current.name
	visibility.button_pressed = current.visible; locked.button_pressed = current.locked; opacity.value = float(current.opacity) * 100
	if not width.get_line_edit().has_focus(): width.value = map.width
	if not height.get_line_edit().has_focus(): height.value = map.height
	terrain_list.clear()
	for definition in map.terrain_sets: terrain_list.add_item(definition.name)
	if terrain >= 0 and terrain < terrain_list.item_count: terrain_list.select(terrain)
	var signature := str(textures.size()) + (":" + str(textures[0].get_instance_id()) if not textures.is_empty() else "")
	if signature != village_role_signature:
		village_role_signature = signature
		_refresh_village_roles(textures)
	if signature != palette_signature:
		palette_signature = signature
		for child in palette.get_children(): palette.remove_child(child); child.queue_free()
		tile_buttons.clear()
		for i in textures.size():
			var item := Button.new(); item.custom_minimum_size = Vector2(48, 42); item.icon = textures[i]; item.expand_icon = true; item.toggle_mode = true; item.tooltip_text = "Tile " + str(i)
			palette.add_child(item); tile_buttons.append(item)
			item.pressed.connect(func(): command.emit({"kind": "tile", "value": i}))
	for i in tile_buttons.size(): tile_buttons[i].set_pressed_no_signal(i == tile)
	doors_list.clear()
	selected_door = -1
	selected_connection = -1
	_display_door_count = map.get("doors", []).size()
	for i in map.get("doors", []).size():
		var door: Dictionary = map.doors[i]
		doors_list.add_item("%s • (%d,%d) ↔ (%d,%d)" % [door.name, door.a[0], door.a[1], door.b[0], door.b[1]])
	for connection in map.get("connections", []):
		var a_room: String = str(map.rooms.filter(func(room): return room.id == connection.a.room)[0].name) if map.rooms.any(func(room): return room.id == connection.a.room) else str(connection.a.room)
		var b_room: String = str(map.rooms.filter(func(room): return room.id == connection.b.room)[0].name) if map.rooms.any(func(room): return room.id == connection.b.room) else str(connection.b.room)
		doors_list.add_item("%s • %s (%d,%d) ↔ %s (%d,%d)" % [connection.name, a_room, connection.a.point[0], connection.a.point[1], b_room, connection.b.point[0], connection.b.point[1]])
	if doors_list.item_count > 0:
		doors_list.select(0)
		if _display_door_count > 0: selected_door = 0
		else: selected_connection = 0
	syncing = false
