extends RefCounted
## HyperLearn is an explicit rule proposal workflow, not a trained neural model.
func propose(doc: RefCounted) -> Dictionary:
	var counts := {}
	var img: Image = doc.composite()
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0:
				var key := "#" + c.to_html(false)
				counts[key] = int(counts.get(key, 0)) + 1
	var colors: Array = counts.keys()
	colors.sort_custom(func(a, b): return counts[a] > counts[b])
	colors = colors.slice(0, 32)
	var references: Array = preload("res://core/reference_library.gd").new().eligible(doc, "palette").map(func(r): return r.id)
	return {"id": str(Time.get_unix_time_from_system()), "palette": colors, "source_revision": doc.revision, "references": references, "bible_version": doc.manifest.art_bible_version, "status": "pending", "test": "passed" if not colors.is_empty() and doc.validate().is_empty() else "failed", "description": "Paleta observada no frame atual; aprovação manual obrigatória."}

func approve(doc: RefCounted, index: int) -> bool:
	if doc.art.locked or index < 0 or index >= doc.art.candidates.size(): return false
	if str(doc.art.get("candidate_status", "candidate")) == "rejected": return false
	var candidate: Dictionary = doc.art.candidates[index]
	if candidate.get("test") != "passed" or candidate.get("status") != "pending" or candidate.get("source_revision") != doc.revision: return false
	doc.checkpoint()
	candidate.status = "approved"
	doc.art.memory.append(candidate.duplicate(true))
	doc.palette = candidate.palette.duplicate()
	return true

func recall(doc: RefCounted) -> Array:
	var active: Array = preload("res://core/reference_library.gd").new().eligible(doc, "palette").map(func(r): return r.id)
	return doc.art.memory.filter(func(rule): return rule.get("status") == "approved" and rule.get("references", []).all(func(id): return active.has(id)))

func quantize(doc: RefCounted) -> void:
	if doc.layers[doc.active_layer].locked: return
	doc.checkpoint()
	var img: Image = doc.current()
	for y in doc.height:
		for x in doc.width:
			if not doc.allowed(Vector2i(x, y)): continue
			var color := img.get_pixel(x, y)
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
			img.set_pixel(x, y, nearest)
