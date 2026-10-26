extends RefCounted
## Proposes removal of tiny opaque pixel islands from the active cel. Human review is required.
const MAX_CLUSTER_SIZE := 64
const NEIGHBORS_8 := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
]

func build(doc: RefCounted, max_cluster_size: int = 1) -> Dictionary:
	if doc == null or doc.layers.is_empty(): return _failure("Documento ou camada inválidos.")
	if doc.width < 1 or doc.height < 1 or doc.width > doc.MAX_SIDE or doc.height > doc.MAX_SIDE: return _failure("Dimensões do documento inválidas.")
	if doc.active_layer < 0 or doc.active_layer >= doc.layers.size() or doc.direction < 0 or doc.direction >= 8 or doc.frame < 0 or doc.frame >= doc.frames: return _failure("Camada, direção ou quadro ativo inválido.")
	if max_cluster_size < 1 or max_cluster_size > MAX_CLUSTER_SIZE: return _failure("O limite deve ficar entre 1 e %d pixels." % MAX_CLUSTER_SIZE)
	if doc.art.get("locked", false): return _failure("Art Lock impede a limpeza de clusters.")
	if doc.layers[doc.active_layer].locked: return _failure("A camada ativa está bloqueada.")
	var source: Image = doc.current()
	if source == null or source.is_empty() or source.get_width() != doc.width or source.get_height() != doc.height: return _failure("A cel ativa não corresponde às dimensões do documento.")
	var before: Image = source.duplicate()
	var after: Image = before.duplicate()
	var visited := PackedByteArray()
	visited.resize(doc.width * doc.height)
	visited.fill(0)
	var removed := PackedInt32Array()
	var removed_components := 0
	var color_counts := {}
	for start_index in visited.size():
		if visited[start_index] != 0: continue
		var start_point := Vector2i(start_index % doc.width, int(start_index / doc.width))
		if before.get_pixelv(start_point).a <= 0.0:
			visited[start_index] = 1
			continue
		var stack: Array[int] = [start_index]
		var small_component: Array[int] = []
		var size := 0
		var fully_allowed := true
		visited[start_index] = 1
		while not stack.is_empty():
			var index: int = stack.pop_back()
			var point := Vector2i(index % doc.width, int(index / doc.width))
			size += 1
			if size <= max_cluster_size:
				small_component.append(index)
				if not doc.allowed(point): fully_allowed = false
			for delta_value in NEIGHBORS_8:
				var delta: Vector2i = delta_value
				var neighbor: Vector2i = point + delta
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= doc.width or neighbor.y >= doc.height: continue
				var neighbor_index: int = neighbor.y * doc.width + neighbor.x
				if visited[neighbor_index] != 0: continue
				visited[neighbor_index] = 1
				if before.get_pixelv(neighbor).a > 0.0: stack.append(neighbor_index)
		if size <= max_cluster_size and fully_allowed:
			removed_components += 1
			for index in small_component:
				var point := Vector2i(index % doc.width, int(index / doc.width))
				var color: Color = before.get_pixelv(point)
				var color_key := color.to_html(true)
				color_counts[color_key] = int(color_counts.get(color_key, 0)) + 1
				removed.append(index)
				after.set_pixelv(point, Color.TRANSPARENT)
	if removed.is_empty():
		return {"ok": true, "message": "Não há clusters pequenos elegíveis dentro da seleção e fora das máscaras protegidas.", "removed_pixels": 0, "removed_components": 0}
	var key: String = doc.cel_key()
	return {
		"ok": true,
		"document_instance": doc.get_instance_id(),
		"revision": doc.revision,
		"layer": doc.active_layer,
		"layer_id": str(doc.layers[doc.active_layer].id),
		"direction": doc.direction,
		"frame": doc.frame,
		"selection": doc.selection,
		"protected_pixels": doc.rig.get("protected_pixels", {}).get(key, []).duplicate(),
		"max_cluster_size": max_cluster_size,
		"before": before,
		"after": after,
		"pixels": removed,
		"removed_pixels": removed.size(),
		"removed_components": removed_components,
		"color_counts": color_counts,
		"message": "%d componentes • %d pixels • conectividade de 8 vizinhos. A proposta remove apenas ilhas pequenas totalmente contidas na seleção e não protegidas." % [removed_components, removed.size()]
	}

func apply(doc: RefCounted, proposal: Dictionary) -> bool:
	if doc == null or not proposal.get("ok", false) or proposal.get("pixels", PackedInt32Array()).is_empty(): return false
	if int(proposal.get("document_instance", -1)) != doc.get_instance_id() or int(proposal.get("revision", -1)) != doc.revision: return false
	var layer_index := int(proposal.get("layer", -1))
	var direction := int(proposal.get("direction", -1))
	var frame := int(proposal.get("frame", -1))
	if doc.art.get("locked", false) or layer_index != doc.active_layer or layer_index < 0 or layer_index >= doc.layers.size() or direction != doc.direction or frame != doc.frame: return false
	if doc.layers[layer_index].locked or str(doc.layers[layer_index].id) != str(proposal.get("layer_id", "")) or doc.selection != proposal.get("selection", Rect2i()): return false
	var key: String = doc.cel_key(direction, frame)
	var current: Image = doc.current()
	var before: Variant = proposal.get("before")
	var after: Variant = proposal.get("after")
	var pixels: Variant = proposal.get("pixels")
	if current == null or current.is_empty() or current.get_width() != doc.width or current.get_height() != doc.height: return false
	if not before is Image or not after is Image or before.is_empty() or after.is_empty(): return false
	if before.get_width() != doc.width or before.get_height() != doc.height or after.get_width() != doc.width or after.get_height() != doc.height: return false
	if not pixels is PackedInt32Array or pixels.is_empty() or pixels.size() != int(proposal.get("removed_pixels", -1)): return false
	if doc.rig.get("protected_pixels", {}).get(key, []) != proposal.get("protected_pixels", []): return false
	if current.get_data() != before.get_data(): return false
	var checked := {}
	for index in pixels:
		if index < 0 or index >= doc.width * doc.height or checked.has(index): return false
		checked[index] = true
		var point := Vector2i(int(index) % doc.width, int(index / doc.width))
		if not doc.allowed(point) or doc.current().get_pixelv(point).a <= 0.0: return false
	doc.checkpoint("Remover clusters pequenos")
	for index in pixels:
		var point := Vector2i(int(index) % doc.width, int(int(index) / doc.width))
		doc.current().set_pixelv(point, Color.TRANSPARENT)
	doc.art.pose_approvals = []
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Limpeza humana revisável de clusters pequenos no cel ativo; aprovação artística reiniciada."
	return true

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "pixels": PackedInt32Array(), "removed_pixels": 0, "removed_components": 0}
