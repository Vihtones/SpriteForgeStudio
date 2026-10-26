extends RefCounted
## Deterministic grid slicing and import into the active layer.

static func slice(image: Image, cell_size: Vector2i, columns: int, rows: int, margin: Vector2i = Vector2i.ZERO, spacing: Vector2i = Vector2i.ZERO) -> Dictionary:
	if image == null or image.is_empty(): return {"ok": false, "error": "Imagem vazia ou inválida."}
	if cell_size.x <= 0 or cell_size.y <= 0 or cell_size.x > 512 or cell_size.y > 512:
		return {"ok": false, "error": "Dimensões da célula devem ficar entre 1 e 512 px."}
	if columns < 1 or rows < 1 or columns > 32 or rows > 8:
		return {"ok": false, "error": "A grade deve ter 1–32 colunas e 1–8 linhas."}
	if margin.x < 0 or margin.y < 0 or spacing.x < 0 or spacing.y < 0:
		return {"ok": false, "error": "Margens e espaçamentos não podem ser negativos."}
	var required_width: int = margin.x * 2 + columns * cell_size.x + maxi(0, columns - 1) * spacing.x
	var required_height: int = margin.y * 2 + rows * cell_size.y + maxi(0, rows - 1) * spacing.y
	if required_width > image.get_width() or required_height > image.get_height():
		return {"ok": false, "error": "A grade configurada excede a imagem de origem."}
	var result: Array = []
	for row in rows:
		var row_images: Array[Image] = []
		for column in columns:
			var origin := margin + Vector2i(column * (cell_size.x + spacing.x), row * (cell_size.y + spacing.y))
			var cel := image.get_region(Rect2i(origin, cell_size))
			cel.convert(Image.FORMAT_RGBA8)
			row_images.append(cel)
		result.append(row_images)
	return {"ok": true, "rows": result, "columns": columns, "row_count": rows, "cells": columns * rows}

static func import_into(document: RefCounted, image: Image, config: Dictionary) -> Dictionary:
	if document == null: return {"ok": false, "error": "Documento ausente."}
	if document.art.get("locked", false): return {"ok": false, "error": "Art Lock impede alterações."}
	if document.layers.is_empty() or document.active_layer < 0 or document.active_layer >= document.layers.size():
		return {"ok": false, "error": "Camada ativa inválida."}
	if document.layers[document.active_layer].locked: return {"ok": false, "error": "A camada ativa está bloqueada."}
	var cell_size := Vector2i(int(config.get("cell_width", 0)), int(config.get("cell_height", 0)))
	if cell_size != Vector2i(document.width, document.height):
		return {"ok": false, "error": "Cada célula deve medir exatamente %d × %d px." % [document.width, document.height]}
	var columns := int(config.get("columns", 0))
	var rows := int(config.get("rows", 0))
	var all_directions := bool(config.get("all_directions", false))
	var direction_map: Array = config.get("direction_map", [])
	if direction_map.is_empty():
		direction_map = range(8) if all_directions else [document.direction]
	if rows != direction_map.size() or rows < 1 or rows > 8:
		return {"ok": false, "error": "A quantidade de linhas deve corresponder às direções mapeadas."}
	var seen_directions: Dictionary = {}
	for mapped_direction in direction_map:
		if not mapped_direction is int or int(mapped_direction) < 0 or int(mapped_direction) >= 8 or seen_directions.has(int(mapped_direction)):
			return {"ok": false, "error": "O mapa de direções deve conter índices únicos entre 0 e 7."}
		seen_directions[int(mapped_direction)] = true
	var start_frame := int(config.get("start_frame", 0))
	if start_frame < 0 or start_frame + columns > document.frames:
		return {"ok": false, "error": "O intervalo de quadros importado ultrapassa o documento."}
	var sliced := slice(image, cell_size, columns, rows, config.get("margin", Vector2i.ZERO), config.get("spacing", Vector2i.ZERO))
	if not sliced.ok: return sliced
	var content_scale := float(config.get("content_scale", 1.0))
	var alignment := str(config.get("alignment", "center"))
	if not is_finite(content_scale) or content_scale < 0.1 or content_scale > 1.0:
		return {"ok": false, "error": "Escala de conteúdo deve ficar entre 0,1 e 1,0."}
	if alignment not in ["center", "bottom_center", "top_left"]:
		return {"ok": false, "error": "Alinhamento de conteúdo inválido."}
	if content_scale < 0.999:
		var fitted_rows: Array = []
		for row in sliced.rows:
			var fitted_row: Array[Image] = []
			for cel in row:
				fitted_row.append(fit_cell(cel, Vector2i(document.width, document.height), content_scale, alignment))
			fitted_rows.append(fitted_row)
		sliced.rows = fitted_rows
	document.checkpoint("Importar spritesheet")
	var target_layer: Dictionary = document.layers[document.active_layer]
	for row_index in direction_map.size():
		var mapped_direction := int(direction_map[row_index])
		for column in columns:
			target_layer.cels[mapped_direction][start_frame + column] = sliced.rows[row_index][column]
	# Any imported pixels invalidate prior approval evidence for this document.
	document.art.pose_approvals = []
	if str(document.art.get("candidate_status", "candidate")) != "rejected":
		document.art.candidate_status = "candidate"
	document.manifest.approvals = []
	document.mark_changed()
	return {"ok": true, "cells": sliced.cells, "columns": columns, "directions": direction_map.size(), "direction_map": direction_map.duplicate(), "start_frame": start_frame}

## Imports one action row from a high-resolution regular atlas, optionally fitting
## the whole atlas to an exact cell grid before slicing with the normal importer.
static func import_grid_row(document: RefCounted, image: Image, config: Dictionary) -> Dictionary:
	if document == null or image == null or image.is_empty(): return {"ok": false, "error": "Documento ou atlas inválido."}
	var columns := int(config.get("columns", 0))
	var source_rows := int(config.get("source_rows", 0))
	var source_row := int(config.get("source_row", -1))
	var fit_grid := bool(config.get("fit_grid", false))
	if columns < 1 or columns > 32 or source_rows < 1 or source_rows > 8 or source_row < 0 or source_row >= source_rows:
		return {"ok": false, "error": "Grade ou linha de origem fora dos limites."}
	if bool(config.get("all_directions", false)):
		return {"ok": false, "error": "Importe uma linha de ação por vez com este modo."}
	var working := image.duplicate()
	var target := Vector2i(document.width * columns, document.height * source_rows)
	var margin := Vector2i(int(config.get("margin_x", 0)), int(config.get("margin_y", 0)))
	var spacing := Vector2i(int(config.get("spacing_x", 0)), int(config.get("spacing_y", 0)))
	if fit_grid:
		if margin != Vector2i.ZERO or spacing != Vector2i.ZERO:
			return {"ok": false, "error": "Ajuste de grade inteira não combina com margens ou espaçamentos."}
		var interpolation := int(config.get("sheet_interpolation", Image.INTERPOLATE_LANCZOS))
		if interpolation < Image.INTERPOLATE_NEAREST or interpolation > Image.INTERPOLATE_LANCZOS:
			return {"ok": false, "error": "Filtro de ajuste de atlas inválido."}
		var normalized := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
		for grid_row_index in source_rows:
			for column in columns:
				var x0 := floori(float(column) * working.get_width() / columns)
				var x1 := floori(float(column + 1) * working.get_width() / columns)
				var y0 := floori(float(grid_row_index) * working.get_height() / source_rows)
				var y1 := floori(float(grid_row_index + 1) * working.get_height() / source_rows)
				var source_cell: Image = working.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
				var fitted_cell: Image = fit_cell(source_cell, Vector2i(document.width, document.height), 1.0, "center", interpolation)
				normalized.blit_rect(fitted_cell, Rect2i(Vector2i.ZERO, Vector2i(document.width, document.height)), Vector2i(column * document.width, grid_row_index * document.height))
		working = normalized
	else:
		var expected := Vector2i(margin.x * 2 + columns * document.width + maxi(0, columns - 1) * spacing.x, margin.y * 2 + source_rows * document.height + maxi(0, source_rows - 1) * spacing.y)
		if working.get_size() != expected:
			return {"ok": false, "error": "Sem ajuste, o atlas deve medir exatamente %d × %d px." % [expected.x, expected.y]}
	var row_y: int = source_row * document.height if fit_grid else margin.y + source_row * (document.height + spacing.y)
	var row_image: Image = working.get_region(Rect2i(0, row_y, working.get_width(), document.height))
	var row_config := config.duplicate(true)
	row_config["rows"] = 1
	row_config["all_directions"] = false
	row_config["cell_width"] = document.width
	row_config["cell_height"] = document.height
	row_config["margin"] = Vector2i(margin.x, 0)
	row_config["spacing"] = Vector2i(spacing.x, 0)
	return import_into(document, row_image, row_config)

static func import_isolated_row(document: RefCounted, extraction: Dictionary, config: Dictionary) -> Dictionary:
	if document == null: return {"ok": false, "error": "Documento ausente."}
	var rendered: Dictionary = preload("res://core/silhouette_atlas.gd").render_row(extraction, int(config.get("source_row", -1)), Vector2i(document.width, document.height), float(config.get("content_scale", 1.0)), str(config.get("alignment", "center")))
	if not rendered.ok: return rendered
	var options := config.duplicate(true)
	options["columns"] = int(extraction.columns); options["rows"] = 1
	options["cell_width"] = document.width; options["cell_height"] = document.height
	options["all_directions"] = false; options["content_scale"] = 1.0
	options["margin"] = Vector2i.ZERO; options["spacing"] = Vector2i.ZERO
	return import_into(document, rendered.image, options)

## Rebuilds one action from a transparent 8-row atlas, mapping rows to N, NE,
## E, SE, S, SW, W, NW. All rows are validated/rendered before the document is
## touched, so a bad direction cannot leave a partially replaced animation.
static func import_isolated_directions(document: RefCounted, extraction: Dictionary, config: Dictionary) -> Dictionary:
	if document == null: return {"ok": false, "error": "Documento ausente."}
	if not extraction.get("ok", false): return {"ok": false, "error": str(extraction.get("error", "Extração inválida."))}
	if document.art.get("locked", false): return {"ok": false, "error": "Art Lock impede alterações."}
	if document.layers.is_empty() or document.active_layer < 0 or document.active_layer >= document.layers.size():
		return {"ok": false, "error": "Camada ativa inválida."}
	if document.layers[document.active_layer].locked: return {"ok": false, "error": "A camada ativa está bloqueada."}
	if int(extraction.get("rows", 0)) != 8 or int(extraction.get("columns", 0)) < 1:
		return {"ok": false, "error": "Para isolar oito direções, use exatamente oito linhas na ordem N, NE, E, SE, S, SW, W, NW."}
	var columns := int(extraction.columns)
	var start_frame := int(config.get("start_frame", 0))
	if start_frame < 0 or start_frame + columns > document.frames:
		return {"ok": false, "error": "O intervalo de quadros importado ultrapassa o documento."}
	var target := Vector2i(document.width, document.height)
	var rendered_rows: Array[Image] = []
	for direction in 8:
		var rendered: Dictionary = preload("res://core/silhouette_atlas.gd").render_row(extraction, direction, target, float(config.get("content_scale", 1.0)), str(config.get("alignment", "center")))
		if not rendered.get("ok", false):
			return {"ok": false, "error": "Direção %s: %s" % [document.DIRECTIONS[direction], str(rendered.get("error", "Falha no recorte."))]}
		rendered_rows.append(rendered.image)
	var layer: Dictionary = document.layers[document.active_layer]
	document.checkpoint("Isolar spritesheet direcional")
	for direction in 8:
		for column in columns:
			var cel: Image = rendered_rows[direction].get_region(Rect2i(column * document.width, 0, document.width, document.height))
			cel.convert(Image.FORMAT_RGBA8)
			layer.cels[direction][start_frame + column] = cel
	document.art.pose_approvals = []
	if str(document.art.get("candidate_status", "candidate")) != "rejected": document.art.candidate_status = "candidate"
	document.manifest.approvals = []
	document.mark_changed()
	return {"ok": true, "cells": columns * 8, "columns": columns, "directions": 8, "start_frame": start_frame}

static func fit_cell(source: Image, target: Vector2i, content_scale: float = 1.0, alignment: String = "center", interpolation: int = Image.INTERPOLATE_NEAREST) -> Image:
	if source == null or source.is_empty() or target.x <= 0 or target.y <= 0:
		return null
	if not is_finite(content_scale) or content_scale < 0.1 or content_scale > 1.0:
		return null
	if alignment not in ["center", "bottom_center", "top_left"]:
		return null
	if interpolation < Image.INTERPOLATE_NEAREST or interpolation > Image.INTERPOLATE_LANCZOS:
		return null
	var fit := minf(float(target.x) / source.get_width(), float(target.y) / source.get_height())
	var fitted_size := Vector2i(maxi(1, roundi(source.get_width() * fit * content_scale)), maxi(1, roundi(source.get_height() * fit * content_scale)))
	var fitted := source.duplicate()
	fitted.resize(fitted_size.x, fitted_size.y, interpolation)
	var offset := Vector2i.ZERO
	match alignment:
		"center": offset = Vector2i((target.x - fitted_size.x) / 2, (target.y - fitted_size.y) / 2)
		"bottom_center": offset = Vector2i((target.x - fitted_size.x) / 2, target.y - fitted_size.y)
		"top_left": offset = Vector2i.ZERO
	var canvas := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(fitted, Rect2i(Vector2i.ZERO, fitted_size), offset)
	return canvas
