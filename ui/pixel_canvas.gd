extends Control
const PixelShapes = preload("res://core/pixel_shapes.gd")
signal edited
signal picked(color: Color)
signal stroke_started
var doc: RefCounted
var tool: String = "Lápis"
var color := Color("75b5ad")
var brush_size: int = 1
var mirror: bool = false
var grid: bool = true
var onion: bool = false
var rig: bool = false
var anchor_name: String = "hand"
var zoom: float = 14.0
var pan := Vector2.ZERO
var drawing: bool = false
var panning: bool = false
var start := Vector2i.ZERO
var last := Vector2i.ZERO
var hover := Vector2i(-1, -1)
var document_hover := Vector2i(-1, -1)
var texture: ImageTexture
var onion_texture: ImageTexture
var onion_next_texture: ImageTexture
var pixel_shapes = PixelShapes.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	custom_minimum_size = Vector2(420, 320)

func origin() -> Vector2:
	return (size - Vector2(doc.width, doc.height) * zoom) / 2 + pan

func point(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - origin()) / zoom).floor())

func refresh() -> void:
	if doc == null: return
	texture = ImageTexture.create_from_image(doc.composite())
	onion_texture = null
	onion_next_texture = null
	if onion and doc.frames > 1:
		var sequence: Array = doc.clip().get("frames", [])
		var position: int = sequence.find(doc.frame)
		if position >= 0 and sequence.size() > 1:
			var previous_frame: int = int(sequence[posmod(position - 1, sequence.size())])
			var next_frame: int = int(sequence[posmod(position + 1, sequence.size())])
			onion_texture = ImageTexture.create_from_image(doc.composite(doc.direction, previous_frame))
			onion_next_texture = ImageTexture.create_from_image(doc.composite(doc.direction, next_frame))
	queue_redraw()

func cancel_gesture() -> void:
	drawing = false
	panning = false
	hover = Vector2i(-1, -1)
	document_hover = Vector2i(-1, -1)
	queue_redraw()

func fit_canvas() -> void:
	if doc == null: return
	var factor := minf((size.x - 32) / doc.width, (size.y - 32) / doc.height)
	zoom = clampf(floor(factor) if factor >= 1 else factor, 0.5, 40)
	pan = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	if doc == null: return
	draw_rect(Rect2(Vector2.ZERO, size), Color("101522"))
	var base := origin()
	var offset: Vector2i = doc.layer_offset()
	for y in range(0, doc.height, 4):
		for x in range(0, doc.width, 4):
			var c := Color("252e40") if (floori(x / 4.0) + floori(y / 4.0)) % 2 == 0 else Color("202738")
			draw_rect(Rect2(base + Vector2(x, y) * zoom, Vector2(mini(4, doc.width - x), mini(4, doc.height - y)) * zoom), c)
	var rect := Rect2(base, Vector2(doc.width, doc.height) * zoom)
	if onion and onion_texture: draw_texture_rect(onion_texture, rect, false, Color(1.0, 0.42, 0.58, 0.23))
	if onion and onion_next_texture: draw_texture_rect(onion_next_texture, rect, false, Color(0.38, 0.86, 1.0, 0.18))
	if texture: draw_texture_rect(texture, rect, false)
	if grid and zoom >= 8:
		for x in doc.width + 1: draw_line(base + Vector2(x * zoom, 0), base + Vector2(x * zoom, doc.height * zoom), Color(0, 0, 0, 0.17))
		for y in doc.height + 1: draw_line(base + Vector2(0, y * zoom), base + Vector2(doc.width * zoom, y * zoom), Color(0, 0, 0, 0.17))
	draw_rect(rect, Color("526078"), false)
	if doc.selection.size != Vector2i.ZERO:
		draw_rect(Rect2(base + Vector2(doc.selection.position + offset) * zoom, Vector2(doc.selection.size) * zoom), Color("f6ce83"), false, 2)
	if drawing and tool in ["Linha", "Retângulo", "Retângulo preenchido", "Elipse", "Elipse preenchida", "Máscara"]:
		var preview_rect := Rect2(base + Vector2(start.min(hover) + offset) * zoom, Vector2((start - hover).abs() + Vector2i.ONE) * zoom)
		if tool in ["Elipse", "Elipse preenchida"]:
			var low := start.min(hover).clamp(Vector2i.ZERO, Vector2i(doc.width - 1, doc.height - 1))
			var high := start.max(hover).clamp(Vector2i.ZERO, Vector2i(doc.width - 1, doc.height - 1))
			for point in pixel_shapes.rasterize("ellipse", low, high):
				draw_rect(Rect2(base + Vector2(point + offset) * zoom, Vector2.ONE * zoom), Color(1, 1, 1, 0.65))
		else:
			draw_rect(preview_rect, Color(1, 1, 1, 0.5), false, 2)
	if rig:
		for segment in doc.rig.get("skeleton", []):
			if not segment is Array or segment.size() != 2: continue
			var from_point: Array = doc.anchor_at(str(segment[0]))
			var to_point: Array = doc.anchor_at(str(segment[1]))
			var from_pos := base + (Vector2(from_point[0], from_point[1]) + Vector2.ONE * 0.5) * zoom
			var to_pos := base + (Vector2(to_point[0], to_point[1]) + Vector2.ONE * 0.5) * zoom
			draw_line(from_pos, to_pos, Color(0.35, 0.85, 0.8, 0.75), maxf(1.0, zoom * 0.09), true)
		for key in doc.anchors:
			var a: Array = doc.anchor_at(key, doc.direction, doc.frame)
			var p := base + (Vector2(a[0], a[1]) + Vector2.ONE * 0.5) * zoom
			var selected: bool = key == anchor_name
			draw_circle(p, 6 if selected else 4, Color("fff1a8") if selected else Color("ffc77a"))
			draw_string(ThemeDB.fallback_font, p + Vector2(8, -8), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var box: Array = doc.animation.hitboxes.get(doc.cel_key(), [])
	if not box.is_empty(): draw_rect(Rect2(base + Vector2(box[0], box[1]) * zoom, Vector2(box[2], box[3]) * zoom), Color("ff796f"), false, 2)
	for index in doc.rig.get("protected_pixels", {}).get(doc.cel_key(), []):
		var p := Vector2i(int(index) % doc.width, int(int(index) / doc.width))
		draw_rect(Rect2(base + Vector2(p + offset) * zoom, Vector2.ONE * zoom), Color(0.4, 0.7, 1.0, 0.3))
	if Rect2i(0, 0, doc.width, doc.height).has_point(document_hover) and (doc.allowed(hover) or tool in ["Conta-gotas", "Âncora"]):
		draw_rect(Rect2(base + Vector2(document_hover) * zoom, Vector2.ONE * zoom), Color.WHITE, false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var previous := zoom
			zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.5, 40)
			pan = (pan + size / 2 - event.position) * zoom / previous - size / 2 + event.position
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			document_hover = point(event.position)
			hover = document_hover - doc.layer_offset()
			if event.pressed:
				var inside := Rect2i(0, 0, doc.width, doc.height).has_point(document_hover)
				if tool in ["Conta-gotas", "Âncora"]:
					if not inside: return
				elif tool != "Máscara" and (not inside or not doc.allowed(hover)): return
				grab_focus()
				stroke_started.emit()
				start = hover
				last = hover
				if tool == "Conta-gotas":
					picked.emit(doc.composite().get_pixelv(document_hover))
					return
				if tool == "Âncora":
					doc.set_anchor(anchor_name, document_hover)
					edited.emit()
					return
				if doc.layers[doc.active_layer].locked and tool != "Máscara": return
				drawing = true
				if tool != "Máscara": doc.checkpoint(tool)
				var ink := Color.TRANSPARENT if event.button_index == MOUSE_BUTTON_RIGHT or tool == "Borracha" else color
				if tool == "Balde":
					doc.flood(hover, ink)
					drawing = false
				elif tool in ["Lápis", "Borracha"]: doc.pixel(hover, ink, mirror, brush_size)
				edited.emit()
			elif drawing:
				var ink := Color.TRANSPARENT if event.button_index == MOUSE_BUTTON_RIGHT else color
				if tool == "Linha": doc.line(start, hover, ink, mirror, brush_size)
				if tool in ["Retângulo", "Retângulo preenchido", "Elipse", "Elipse preenchida"]:
					var shape := "ellipse" if tool in ["Elipse", "Elipse preenchida"] else "rectangle"
					var filled := tool in ["Retângulo preenchido", "Elipse preenchida"]
					pixel_shapes.apply(doc, shape, start, hover, ink, mirror, filled, brush_size)
				if tool == "Máscara":
					var a := start.min(hover).clamp(Vector2i.ZERO, Vector2i(doc.width - 1, doc.height - 1))
					var b := start.max(hover).clamp(Vector2i.ZERO, Vector2i(doc.width - 1, doc.height - 1))
					doc.selection = Rect2i(a, b - a + Vector2i.ONE).intersection(Rect2i(0, 0, doc.width, doc.height))
				drawing = false
				edited.emit()
	if event is InputEventMouseMotion:
		document_hover = point(event.position)
		hover = document_hover - doc.layer_offset()
		if panning: pan += event.relative
		if drawing and tool in ["Lápis", "Borracha"]:
			var ink := Color.TRANSPARENT if event.button_mask & MOUSE_BUTTON_MASK_RIGHT or tool == "Borracha" else color
			doc.line(last, hover, ink, mirror, brush_size)
			last = hover
			edited.emit()
		queue_redraw()
