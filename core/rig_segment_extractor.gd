extends RefCounted
## Extracts an operator-defined pixel region into a new raster layer for rig mapping.
const MAX_LAYERS := 16
const NEIGHBORS_8 := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
]

func build(doc: RefCounted, layer_name: String, mode: String = "selection", seed: Vector2i = Vector2i.ZERO, bone_segment: Array = []) -> Dictionary:
	if doc == null or doc.layers.is_empty(): return _failure("Documento ou camada inválidos.")
	if doc.art.get("locked", false): return _failure("Art Lock impede segmentar pixels.")
	if doc.active_layer < 0 or doc.active_layer >= doc.layers.size() or doc.direction < 0 or doc.direction >= 8 or doc.frame < 0 or doc.frame >= doc.frames: return _failure("Camada, direção ou quadro ativo inválido.")
	if doc.layers.size() >= MAX_LAYERS: return _failure("Limite de 16 camadas atingido.")
	if doc.pixel_bytes() + doc.width * doc.height * 4 * doc.frames * 8 > doc.pixel_budget_limit: return _failure("A nova camada excederia o orçamento de memória do documento.")
	var title := layer_name.strip_edges()
	if title.is_empty() or title.length() > 48: return _failure("Informe um nome de camada com até 48 caracteres.")
	for layer in doc.layers:
		if str(layer.get("name", "")).strip_edges().to_lower() == title.to_lower(): return _failure("Já existe uma camada com esse nome.")
	if mode not in ["selection", "connected"]: return _failure("Modo de extração inválido.")
	if not bone_segment.is_empty():
		if bone_segment.size() != 2 or not doc.rig.get("skeleton", []).has(bone_segment) or not doc.anchors.has(bone_segment[0]) or not doc.anchors.has(bone_segment[1]): return _failure("O segmento escolhido não pertence ao esqueleto deste documento.")
	var source_layer: Dictionary = doc.layers[doc.active_layer]
	if doc.layer_mask_pixels() + source_layer.get("visibility_masks", {}).get(doc.cel_key(), []).size() > 262144: return _failure("A extração ultrapassaria o limite de memória de máscaras.")
	if source_layer.locked: return _failure("A camada ativa está bloqueada.")
	if not source_layer.visible or float(source_layer.get("opacity", 1.0)) <= 0.0: return _failure("A camada ativa precisa estar visível e ter opacidade positiva.")
	if source_layer.equipment and not doc.compatible(source_layer): return _failure("O equipamento da camada ativa não é compatível com esta família.")
	if absf(doc.layer_rotation(str(source_layer.id), doc.direction, doc.frame)) >= 0.01: return _failure("A camada tem rotação ativa. Rasterize a pose antes de extrair para preservar a composição.")
	var source: Image = source_layer.cels[doc.direction][doc.frame]
	if source == null or source.is_empty() or source.get_size() != Vector2i(doc.width, doc.height): return _failure("A cel ativa não corresponde às dimensões do documento.")
	var key: String = doc.cel_key()
	var protected_pixels: Array = doc.rig.get("protected_pixels", {}).get(key, []).duplicate()
	var pixels := _collect_pixels(doc, source, mode, seed)
	if pixels.is_empty(): return _failure("A região não contém pixels extraíveis dentro da seleção e das máscaras.")
	var source_after: Image = source.duplicate()
	var extracted: Image = doc.blank()
	for index in pixels:
		var point := Vector2i(index % doc.width, int(index / doc.width))
		extracted.set_pixelv(point, source.get_pixelv(point))
		source_after.set_pixelv(point, Color.TRANSPARENT)
	var template: Dictionary = _new_layer_template(doc, source_layer, title, bone_segment)
	var extracted_row: Array = template.cels[doc.direction]
	extracted_row[doc.frame] = extracted.duplicate()
	template.cels[doc.direction] = extracted_row
	return {"ok": true, "document_instance": doc.get_instance_id(), "revision": doc.revision, "layer": doc.active_layer, "layer_id": str(source_layer.id), "direction": doc.direction, "frame": doc.frame, "selection": doc.selection, "protected_key": key, "protected_pixels": protected_pixels, "mode": mode, "seed": seed, "name": title, "bone_segment": bone_segment.duplicate(true), "pixels": pixels, "source_before": source.duplicate(), "source_after": source_after, "extracted": extracted, "layer_template": template}

func apply(doc: RefCounted, proposal: Dictionary) -> bool:
	if doc == null or not proposal.get("ok", false): return false
	if int(proposal.get("document_instance", -1)) != doc.get_instance_id() or int(proposal.get("revision", -1)) != doc.revision: return false
	var layer_index := int(proposal.get("layer", -1))
	if layer_index < 0 or layer_index >= doc.layers.size() or layer_index != doc.active_layer or doc.art.get("locked", false): return false
	if doc.layers[layer_index].locked or str(doc.layers[layer_index].id) != str(proposal.get("layer_id", "")) or int(proposal.get("direction", -1)) != doc.direction or int(proposal.get("frame", -1)) != doc.frame: return false
	if doc.selection != proposal.get("selection", Rect2i()) or str(proposal.get("protected_key", "")) != doc.cel_key(): return false
	if doc.rig.get("protected_pixels", {}).get(doc.cel_key(), []) != proposal.get("protected_pixels", []): return false
	var pixels: Variant = proposal.get("pixels")
	var source_before: Variant = proposal.get("source_before")
	var source_after: Variant = proposal.get("source_after")
	var extracted: Variant = proposal.get("extracted")
	if not pixels is PackedInt32Array or pixels.is_empty() or not source_before is Image or not source_after is Image or not extracted is Image: return false
	var template: Variant = proposal.get("layer_template")
	if not template is Dictionary or not template.has_all(["name", "id", "cels", "bone", "pivot"]): return false
	var current: Image = doc.layers[layer_index].cels[doc.direction][doc.frame]
	if current.get_data() != source_before.get_data(): return false
	var seed: Vector2i = proposal.get("seed", Vector2i.ZERO)
	var segment: Array = proposal.get("bone_segment", [])
	var rebuilt: Dictionary = build(doc, str(proposal.get("name", "")), str(proposal.get("mode", "")), seed, segment)
	if not rebuilt.get("ok", false) or rebuilt.get("pixels", PackedInt32Array()) != pixels: return false
	if rebuilt.source_after.get_data() != source_after.get_data() or rebuilt.extracted.get_data() != extracted.get_data(): return false
	if rebuilt.layer_template.name != template.name or rebuilt.layer_template.bone != template.bone or rebuilt.layer_template.pivot != template.pivot: return false
	doc.checkpoint("Extrair região para camada de rig")
	var source_id := str(doc.layers[layer_index].id)
	var new_layer: Dictionary = template.duplicate(true)
	doc.layers[layer_index].cels[doc.direction][doc.frame] = source_after.duplicate()
	doc.layers.insert(layer_index + 1, new_layer)
	var new_index := layer_index + 1
	doc.active_layer = new_index
	var depth_values: Dictionary = doc.rig.get("depth", {}).get(doc.cel_key(), {})
	if depth_values.has(source_id):
		if not doc.rig.depth.has(doc.cel_key()): doc.rig.depth[doc.cel_key()] = {}
		doc.rig.depth[doc.cel_key()][str(new_layer.id)] = depth_values[source_id]
	if doc.layers[new_index].equipment:
		var offsets: Dictionary = doc.rig.get("offsets", {}).get(doc.cel_key(), {})
		if offsets.has(source_id):
			if not doc.rig.has("offsets"): doc.rig.offsets = {}
			if not doc.rig.offsets.has(doc.cel_key()): doc.rig.offsets[doc.cel_key()] = {}
			doc.rig.offsets[doc.cel_key()][str(new_layer.id)] = offsets[source_id].duplicate(true)
	doc.art.pose_approvals = []
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Região raster extraída da camada %s para camada de rig %s; aprovação artística reiniciada." % [source_id, str(new_layer.id)]
	return true

func _collect_pixels(doc: RefCounted, source: Image, mode: String, seed: Vector2i) -> PackedInt32Array:
	var pixels := PackedInt32Array()
	if mode == "selection":
		for y in doc.height:
			for x in doc.width:
				var point := Vector2i(x, y)
				if doc.allowed(point) and source.get_pixelv(point).a > 0.0: pixels.append(y * doc.width + x)
		return pixels
	if seed.x < 0 or seed.y < 0 or seed.x >= doc.width or seed.y >= doc.height or not doc.allowed(seed) or source.get_pixelv(seed).a <= 0.0: return pixels
	var visited := PackedByteArray()
	visited.resize(doc.width * doc.height)
	visited.fill(0)
	var stack: Array[int] = [seed.y * doc.width + seed.x]
	while not stack.is_empty():
		var index: int = stack.pop_back()
		if visited[index] != 0: continue
		visited[index] = 1
		var point := Vector2i(index % doc.width, int(index / doc.width))
		if not doc.allowed(point) or source.get_pixelv(point).a <= 0.0: continue
		pixels.append(index)
		for offset_value in NEIGHBORS_8:
			var offset: Vector2i = offset_value
			var neighbor: Vector2i = point + offset
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= doc.width or neighbor.y >= doc.height: continue
			var neighbor_index: int = neighbor.y * doc.width + neighbor.x
			if visited[neighbor_index] == 0: stack.append(neighbor_index)
	pixels.sort()
	return pixels

func _new_layer_template(doc: RefCounted, source: Dictionary, title: String, bone_segment: Array) -> Dictionary:
	var layer: Dictionary = source.duplicate(true)
	if layer.has("visibility_masks"):
		var active_mask: Array = source.visibility_masks.get(doc.cel_key(), [])
		layer.visibility_masks = {}
		if not active_mask.is_empty(): layer.visibility_masks[doc.cel_key()] = active_mask.duplicate()
	layer.id = Crypto.new().generate_random_bytes(8).hex_encode()
	layer.name = title
	layer.retarget_key = _unique_retarget_key(doc, title)
	layer.bone = bone_segment.duplicate(true)
	if not bone_segment.is_empty(): layer.pivot = str(bone_segment[0])
	layer.cels = []
	for direction in 8:
		var row: Array = []
		for frame in doc.frames: row.append(doc.blank())
		layer.cels.append(row)
	return layer

func _unique_retarget_key(doc: RefCounted, title: String) -> String:
	var base := title.strip_edges().to_lower().replace(" ", "_")
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_-]")
	base = regex.sub(base, "_", true).substr(0, 32)
	if base.is_empty(): base = "segment"
	var used := {}
	for layer in doc.layers: used[str(layer.get("retarget_key", ""))] = true
	var candidate := base
	var suffix := 2
	while used.has(candidate):
		candidate = (base.substr(0, mini(base.length(), 27)) + "_" + str(suffix)).substr(0, 32)
		suffix += 1
	return candidate

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "pixels": PackedInt32Array()}

