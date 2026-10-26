extends RefCounted
## Deterministic integer-grid primitives for the pixel canvas.

func rasterize(shape: String, start: Vector2i, finish: Vector2i, filled: bool = false) -> Array[Vector2i]:
	if shape not in ["rectangle", "ellipse"]:
		return []
	var low := start.min(finish)
	var high := start.max(finish)
	if high.x - low.x >= 512 or high.y - low.y >= 512:
		return []
	var points: Array[Vector2i] = []
	if shape == "rectangle":
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				if filled or x == low.x or x == high.x or y == low.y or y == high.y:
					points.append(Vector2i(x, y))
		return points
	var center := (Vector2(low) + Vector2(high)) * 0.5
	var radius := Vector2(maxf(0.5, float(high.x - low.x) * 0.5), maxf(0.5, float(high.y - low.y) * 0.5))
	var inside: Dictionary = {}
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var delta := (Vector2(x, y) - center) / radius
			if delta.length_squared() <= 1.0 + 0.000001:
				var point := Vector2i(x, y)
				if filled: points.append(point)
				else: inside[point] = true
	if not filled:
		for point in inside:
			if not inside.has(point + Vector2i.LEFT) or not inside.has(point + Vector2i.RIGHT) or not inside.has(point + Vector2i.UP) or not inside.has(point + Vector2i.DOWN):
				points.append(point)
	points.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return points

func apply(doc: RefCounted, shape: String, start: Vector2i, finish: Vector2i, color: Color, mirror: bool = false, filled: bool = false, brush_size: int = 1) -> int:
	if doc == null or doc.art.get("locked", false) or doc.layers[doc.active_layer].locked or brush_size < 1 or brush_size > 8:
		return 0
	var bounds := Rect2i(0, 0, doc.width, doc.height)
	start = start.clamp(bounds.position, bounds.end - Vector2i.ONE)
	finish = finish.clamp(bounds.position, bounds.end - Vector2i.ONE)
	var written := 0
	for point in rasterize(shape, start, finish, filled):
		written += _paint_brush(doc, point, color, mirror, 1 if filled else brush_size)
	return written

func _paint_brush(doc: RefCounted, point: Vector2i, color: Color, mirror: bool, size: int) -> int:
	var changed := 0
	var radius := floori(size / 2.0)
	var image: Image = doc.current()
	for dy in size:
		for dx in size:
			var location := point + Vector2i(dx - radius, dy - radius)
			var reflected := Vector2i(doc.width - 1 - location.x, location.y)
			for target in ([location, reflected] if mirror and not doc.layers[doc.active_layer].get("asymmetric", false) else [location]):
				if not doc.allowed(target) or image.get_pixelv(target) == color: continue
				image.set_pixelv(target, color)
				changed += 1
	return changed
