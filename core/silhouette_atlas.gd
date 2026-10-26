extends RefCounted
## Separates disconnected figures before assigning them to logical atlas cells.
## This is explicit opt-in: particles, touching sprites and modular parts need other import modes.
var input_image: Image
var column_count := 1
var row_count := 1
var minimum_area := 100
var result: Dictionary = {}

func compute() -> void:
	result = extract(input_image, column_count, row_count, minimum_area)

static func extract(source: Image, columns: int, rows: int, minimum_area: int = 100, alpha_threshold: int = 32) -> Dictionary:
	if source == null or source.is_empty() or source.get_width() > 4096 or source.get_height() > 4096: return _failure("Imagem vazia ou acima de 4096 px.")
	if columns < 1 or columns > 32 or rows < 1 or rows > 8 or minimum_area < 1 or alpha_threshold < 1 or alpha_threshold > 255: return _failure("Configuração de silhuetas inválida.")
	var image: Image = source.duplicate(); image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width(); var height := image.get_height()
	var rgba := image.get_data()
	var visited := PackedByteArray(); visited.resize(width * height)
	var parts: Dictionary = {}
	var crossings: Array = []
	for pixel in width * height:
		if visited[pixel] or rgba[pixel * 4 + 3] < alpha_threshold: continue
		var pixels := PackedInt32Array([pixel]); visited[pixel] = 1
		var cursor := 0
		var left := pixel % width; var right := left; var top := pixel / width; var bottom := top
		while cursor < pixels.size():
			var current := int(pixels[cursor]); cursor += 1
			var x := current % width; var y := current / width
			left = mini(left, x); right = maxi(right, x); top = mini(top, y); bottom = maxi(bottom, y)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx; var ny := y + dy
					if nx < 0 or ny < 0 or nx >= width or ny >= height: continue
					var neighbor := ny * width + nx
					if not visited[neighbor] and rgba[neighbor * 4 + 3] >= alpha_threshold:
						visited[neighbor] = 1; pixels.append(neighbor)
		if pixels.size() < minimum_area: continue
		var column := clampi(floori(float(left + right + 1) * 0.5 * columns / width), 0, columns - 1)
		var row := clampi(floori(float(bottom) * rows / height), 0, rows - 1)
		var key := row * columns + column
		if parts.has(key): return _failure("Mais de uma figura na célula %d:%d. Ajuste a grade/área mínima ou use recorte manual." % [row + 1, column + 1])
		var bounds := Rect2i(left, top, right - left + 1, bottom - top + 1).grow(1).intersection(Rect2i(0, 0, width, height))
		var isolated := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
		for member in pixels:
			var point := Vector2i(member % width, member / width)
			isolated.set_pixelv(point - bounds.position, image.get_pixelv(point))
			# Keep immediate low-alpha edge pixels without copying neighboring opaque figures.
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var edge := point + Vector2i(dx, dy)
					if not bounds.has_point(edge): continue
					var alpha := int(rgba[(edge.y * width + edge.x) * 4 + 3])
					if alpha > 0 and alpha < alpha_threshold: isolated.set_pixelv(edge - bounds.position, image.get_pixelv(edge))
		var origin := Vector2i(floori(float(column) * width / columns), floori(float(row) * height / rows))
		var nominal_end := Vector2i(floori(float(column + 1) * width / columns), floori(float(row + 1) * height / rows))
		if left < origin.x or top < origin.y or right >= nominal_end.x or bottom >= nominal_end.y: crossings.append({"row": row, "column": column, "bounds": [left, top, right + 1, bottom + 1]})
		parts[key] = {"image": isolated, "origin": bounds.position - origin, "bounds": bounds, "area": pixels.size()}
	if parts.size() != columns * rows: return _failure("Esperadas %d figuras separadas; encontradas %d. Figuras encostadas ou peças soltas exigem recorte manual." % [columns * rows, parts.size()])
	return {"ok": true, "parts": parts, "columns": columns, "rows": rows, "source_size": image.get_size(), "crossings": crossings}

static func render_row(extraction: Dictionary, row: int, target: Vector2i, content_scale: float = 1.0, alignment: String = "center") -> Dictionary:
	if not extraction.get("ok", false): return _failure(str(extraction.get("error", "Silhuetas ausentes.")))
	if row < 0 or row >= int(extraction.rows) or target.x < 1 or target.y < 1 or target.x > 512 or target.y > 512 or not is_finite(content_scale) or content_scale < 0.1 or content_scale > 1.0: return _failure("Linha, escala ou canvas inválidos.")
	if alignment not in ["center", "bottom_center", "top_left"]: return _failure("Alinhamento inválido.")
	var nominal := Vector2(extraction.source_size) / Vector2(extraction.columns, extraction.rows)
	var scale := minf(target.x / nominal.x, target.y / nominal.y) * content_scale
	var offset := (Vector2(target) - nominal * scale) * 0.5
	if alignment == "bottom_center": offset.y = target.y - nominal.y * scale
	elif alignment == "top_left": offset = Vector2.ZERO
	var strip := Image.create(target.x * int(extraction.columns), target.y, false, Image.FORMAT_RGBA8)
	for column in int(extraction.columns):
		var part: Dictionary = extraction.parts[row * int(extraction.columns) + column]
		var image: Image = part.image.duplicate()
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_NEAREST)
		var destination := Vector2i((offset + Vector2(part.origin) * scale).round())
		var occupied := image.get_used_rect()
		if destination.x + occupied.position.x < 0 or destination.y + occupied.position.y < 0 or destination.x + occupied.end.x > target.x or destination.y + occupied.end.y > target.y:
			return _failure("A figura %d ultrapassa o canvas. Reduza a escala; nenhum membro foi cortado." % [column + 1])
		strip.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), destination + Vector2i(column * target.x, 0))
	return {"ok": true, "image": strip, "crossings": extraction.crossings}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
