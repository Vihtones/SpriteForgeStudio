extends VBoxContainer
## Compact per-layer timeline. Each cell is a thumbnail of one direction/frame.
signal frame_selected(frame: int)

var document: RefCounted
var track_rows: Array[HBoxContainer] = []
var frame_cells: Array = []
var scroll: ScrollContainer

func _ready() -> void:
	custom_minimum_size.y = 158
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if document != null: refresh()

func set_document(value: RefCounted) -> void:
	document = value
	if is_inside_tree(): refresh()

func _clear() -> void:
	for child in get_children(): child.free()
	track_rows.clear()
	frame_cells.clear()

func refresh() -> void:
	if document == null: return
	_clear()
	var title := Label.new()
	title.text = "TIMELINE • %s • %s • %d quadros" % [str(document.clip().name), _direction_name(document.direction), document.frames]
	title.add_theme_font_size_override("font_size", 11)
	add_child(title)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	var tracks := VBoxContainer.new()
	tracks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tracks)
	for layer_index in document.layers.size():
		var layer: Dictionary = document.layers[layer_index]
		var track := HBoxContainer.new()
		track.custom_minimum_size.y = 66
		tracks.add_child(track)
		var layer_label := Label.new()
		layer_label.custom_minimum_size.x = 128
		layer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		layer_label.text = ("● " if layer.visible else "○ ") + str(layer.name)
		layer_label.tooltip_text = "Camada %d • %s" % [layer_index + 1, layer.name]
		track.add_child(layer_label)
		var row: Array[Button] = []
		for frame_index in document.frames:
			var cell := _make_cell(layer_index, frame_index)
			track.add_child(cell)
			row.append(cell)
		track_rows.append(track)
		frame_cells.append(row)
	update_selection()

func _make_cell(layer_index: int, frame_index: int) -> Button:
	var layer: Dictionary = document.layers[layer_index]
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(68, 62)
	button.tooltip_text = _tooltip(layer, frame_index)
	button.pressed.connect(func(): frame_selected.emit(frame_index))
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	var texture := TextureRect.new()
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.custom_minimum_size = Vector2(30, 30)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var image: Image = document.masked_layer_cel(layer_index, document.direction, frame_index).duplicate()
	if image.get_width() > 30 or image.get_height() > 30:
		image.resize(30, 30, Image.INTERPOLATE_NEAREST)
	texture.texture = ImageTexture.create_from_image(image)
	content.add_child(texture)
	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 9)
	var duration: int = int(document.clip().durations_ms.get(str(frame_index), roundi(1000.0 / max(1, document.fps))))
	var marker := ""
	var key: String = document.cel_key(document.direction, frame_index)
	if not document.animation.events.get(key, []).is_empty(): marker += " • E"
	if document.animation.hitboxes.has(key): marker += " • H"
	caption.text = "F%02d  %dms%s" % [frame_index + 1, duration, marker]
	content.add_child(caption)
	button.add_child(content)
	button.button_pressed = frame_index == document.frame
	return button

func _tooltip(layer: Dictionary, frame_index: int) -> String:
	var key: String = document.cel_key(document.direction, frame_index)
	var lines: PackedStringArray = ["%s • %s • quadro %d" % [layer.name, _direction_name(document.direction), frame_index + 1]]
	var events: Array = document.animation.events.get(key, [])
	if not events.is_empty(): lines.append("Eventos: " + ", ".join(events))
	if document.animation.hitboxes.has(key): lines.append("Contém hitbox")
	return "\n".join(lines)

func update_selection() -> void:
	for row in frame_cells:
		for i in row.size(): row[i].button_pressed = i == document.frame

func update_frame(frame_index: int) -> void:
	if document == null: return
	for layer_index in mini(frame_cells.size(), document.layers.size()):
		if frame_index < frame_cells[layer_index].size():
			var old: Button = frame_cells[layer_index][frame_index]
			var fresh := _make_cell(layer_index, frame_index)
			fresh.button_pressed = frame_index == document.frame
			var parent := old.get_parent()
			var index := old.get_index()
			parent.remove_child(old); old.queue_free()
			parent.add_child(fresh); parent.move_child(fresh, index)
			frame_cells[layer_index][frame_index] = fresh
	update_selection()

func _direction_name(index: int) -> String:
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][clampi(index, 0, 7)]
