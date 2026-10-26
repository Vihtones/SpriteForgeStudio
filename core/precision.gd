extends RefCounted
## A draft never writes to the document before explicit acceptance.
func diagnose(image: Image, palette: Array) -> Dictionary:
	var isolated: int = 0
	var outside: int = 0
	var partial_alpha: int = 0
	var solid: int = 0
	var allowed_colors := {}
	for hex in palette: allowed_colors[Color(hex).to_html(false)] = true
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a == 0: continue
			solid += 1
			if c.a < 1: partial_alpha += 1
			if not allowed_colors.has(c.to_html(false)): outside += 1
			var neighbors: int = 0
			for delta in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var p: Vector2i = Vector2i(x, y) + delta
				if Rect2i(Vector2i.ZERO, image.get_size()).has_point(p) and image.get_pixelv(p).a > 0: neighbors += 1
			if neighbors == 0: isolated += 1
	return {"opaque_pixels": solid, "outside_palette": outside, "isolated_pixels": isolated, "partial_alpha": partial_alpha, "artistic_approval": false}

func draft_palette(doc: RefCounted) -> Dictionary:
	var before: Image = doc.current().duplicate()
	var after: Image = before.duplicate()
	var count: int = 0
	for y in doc.height:
		for x in doc.width:
			if not doc.allowed(Vector2i(x, y)): continue
			var color := before.get_pixel(x, y)
			if color.a == 0: continue
			var nearest := Color(doc.palette[0])
			var distance := INF
			for hex in doc.palette:
				var c := Color(hex)
				var delta: float = pow(c.r - color.r, 2) + pow(c.g - color.g, 2) + pow(c.b - color.b, 2)
				if delta < distance:
					distance = delta
					nearest = c
			nearest.a = color.a
			after.set_pixel(x, y, nearest)
			if nearest != color: count += 1
	return {"before": before, "after": after, "document_instance": doc.get_instance_id(), "revision": doc.revision, "layer": doc.active_layer, "direction": doc.direction, "frame": doc.frame, "changed": count, "diagnostics": diagnose(after, doc.palette)}

func accept(doc: RefCounted, draft: Dictionary) -> bool:
	if draft.get("document_instance") != doc.get_instance_id(): return false
	if doc.revision != draft.revision or doc.active_layer != draft.layer or doc.direction != draft.direction or doc.frame != draft.frame or doc.layers[doc.active_layer].locked: return false
	if doc.current().get_data() != draft.before.get_data(): return false
	doc.checkpoint()
	doc.layers[doc.active_layer].cels[doc.direction][doc.frame] = draft.after.duplicate()
	return true
