extends RefCounted
## Resizes every cel as one document operation and keeps spatial metadata aligned.

static func resize_document(doc: RefCounted, width: int, height: int, interpolation: int = Image.INTERPOLATE_NEAREST, alignment: String = "center") -> Dictionary:
	if doc == null: return {"ok": false, "error": "Documento ausente."}
	if width < 8 or height < 8 or width > 512 or height > 512:
		return {"ok": false, "error": "Canvas deve medir de 8 a 512 pixels por lado."}
	if interpolation < Image.INTERPOLATE_NEAREST or interpolation > Image.INTERPOLATE_LANCZOS:
		return {"ok": false, "error": "Filtro de redimensionamento inválido."}
	if alignment not in ["center", "bottom_center", "top_left"]:
		return {"ok": false, "error": "Alinhamento inválido."}
	if doc.art.get("locked", false): return {"ok": false, "error": "Art Lock impede redimensionar este documento."}
	if width == doc.width and height == doc.height: return {"ok": false, "error": "O canvas já tem esse tamanho."}
	var projected: int = width * height * 4 * doc.frames * 8 * doc.layers.size() + preload("res://core/world_data.gd").project_bytes(doc.map_data)
	if projected > doc.pixel_budget_limit: return {"ok": false, "error": "O novo canvas excede o orçamento de memória do documento."}
	var old_size := Vector2i(doc.width, doc.height)
	var target := Vector2i(width, height)
	var scale_factor := minf(float(width) / old_size.x, float(height) / old_size.y)
	var scaled_size := Vector2i(maxi(1, roundi(old_size.x * scale_factor)), maxi(1, roundi(old_size.y * scale_factor)))
	var offset := Vector2i.ZERO
	match alignment:
		"center": offset = Vector2i((width - scaled_size.x) / 2, (height - scaled_size.y) / 2)
		"bottom_center": offset = Vector2i((width - scaled_size.x) / 2, height - scaled_size.y)
		"top_left": offset = Vector2i.ZERO
	var resized_layers: Array = []
	for layer in doc.layers:
		var resized_rows: Array = []
		for direction in 8:
			var resized_frames: Array = []
			for frame_index in doc.frames:
				var scaled: Image = layer.cels[direction][frame_index].duplicate()
				scaled.resize(scaled_size.x, scaled_size.y, interpolation)
				var canvas := Image.create(width, height, false, Image.FORMAT_RGBA8)
				canvas.blit_rect(scaled, Rect2i(Vector2i.ZERO, scaled_size), offset)
				resized_frames.append(canvas)
			resized_rows.append(resized_frames)
		resized_layers.append(resized_rows)
	var resized_masks: Array = []
	var mask_count := 0
	for layer in doc.layers:
		var masks := {}
		for key in layer.get("visibility_masks", {}):
			var image := Image.create(old_size.x, old_size.y, false, Image.FORMAT_RGBA8)
			for pixel_index in layer.visibility_masks[key]: image.set_pixel(int(pixel_index) % old_size.x, int(int(pixel_index) / old_size.x), Color.WHITE)
			image.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_NEAREST)
			var canvas := Image.create(width, height, false, Image.FORMAT_RGBA8)
			canvas.blit_rect(image, Rect2i(Vector2i.ZERO, scaled_size), offset)
			var indices: Array = []
			for y in height:
				for x in width:
					if canvas.get_pixel(x, y).a > 0: indices.append(y * width + x)
			mask_count += indices.size()
			if mask_count > 262144: return {"ok": false, "error": "O novo tamanho excede o limite de pixels de máscara."}
			if not indices.is_empty(): masks[key] = indices
		resized_masks.append(masks)
	doc.checkpoint("Redimensionar canvas")
	for layer_index in doc.layers.size(): doc.layers[layer_index].cels = resized_layers[layer_index]
	for layer_index in doc.layers.size():
		if doc.layers[layer_index].has("visibility_masks"): doc.layers[layer_index].visibility_masks = resized_masks[layer_index]
	doc.width = width
	doc.height = height
	for name in doc.anchors:
		doc.anchors[name] = _point(doc.anchors[name], scale_factor, offset, target)
	for pose in doc.rig.get("anchors", {}).values():
		for name in pose:
			pose[name] = _point(pose[name], scale_factor, offset, target)
	for pose in doc.rig.get("offsets", {}).values():
		for layer_id in pose:
			var value: Array = pose[layer_id]
			pose[layer_id] = [roundi(value[0] * scale_factor), roundi(value[1] * scale_factor)]
	for layer in doc.layers:
		var base_offset: Array = layer.get("offset", [0, 0])
		layer.offset = [roundi(base_offset[0] * scale_factor), roundi(base_offset[1] * scale_factor)]
	var protected: Dictionary = doc.rig.get("protected_pixels", {})
	for key in protected:
		var remapped: Array[int] = []
		for pixel_index in protected[key]:
			var old_point := Vector2i(int(pixel_index) % old_size.x, int(pixel_index) / old_size.x)
			var new_point := _point([old_point.x, old_point.y], scale_factor, offset, target)
			var new_index: int = int(new_point[1]) * width + int(new_point[0])
			if not remapped.has(new_index): remapped.append(new_index)
		protected[key] = remapped
	for key in doc.animation.get("hitboxes", {}):
		var box: Array = doc.animation.hitboxes[key]
		var left := clampi(floori(box[0] * scale_factor) + offset.x, 0, width - 1)
		var top := clampi(floori(box[1] * scale_factor) + offset.y, 0, height - 1)
		var right := clampi(ceili((box[0] + box[2]) * scale_factor) + offset.x, left + 1, width)
		var bottom := clampi(ceili((box[1] + box[3]) * scale_factor) + offset.y, top + 1, height)
		doc.animation.hitboxes[key] = [left, top, right - left, bottom - top]
	doc.selection = Rect2i()
	# Pixels have changed, so approvals of the source raster cannot transfer to this revision.
	doc.art.pose_approvals = []
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Canvas redimensionado; revisão artística derivada pendente."
	doc.mark_changed()
	return {"ok": true, "scale": scale_factor, "offset": offset, "size": target}

static func _point(point: Array, scale_factor: float, offset: Vector2i, target: Vector2i) -> Array:
	return [clampi(roundi(float(point[0]) * scale_factor) + offset.x, 0, target.x - 1), clampi(roundi(float(point[1]) * scale_factor) + offset.y, 0, target.y - 1)]
