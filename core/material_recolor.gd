extends RefCounted
## Recolors exact palette-color matches in the active cel or one connected region.
const NEIGHBORS_8 := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
]

func build(doc: RefCounted, ramp_name: String, source_hex: String, target_hex: String, mode: String = "selection", seed: Vector2i = Vector2i.ZERO) -> Dictionary:
	if doc == null or doc.layers.is_empty(): return _failure("Documento ou camada inválidos.")
	if doc.width < 1 or doc.height < 1 or doc.width > doc.MAX_SIDE or doc.height > doc.MAX_SIDE: return _failure("Dimensões do documento inválidas.")
	if doc.active_layer < 0 or doc.active_layer >= doc.layers.size() or doc.direction < 0 or doc.direction >= 8 or doc.frame < 0 or doc.frame >= doc.frames: return _failure("Camada, direção ou quadro ativo inválido.")
	if mode not in ["selection", "connected"]: return _failure("Modo de recolorização inválido.")
	if doc.art.get("locked", false): return _failure("Art Lock impede recolorir pixels.")
	if doc.layers[doc.active_layer].locked: return _failure("A camada ativa está bloqueada.")
	var source: Color = Color(source_hex)
	var target: Color = Color(target_hex)
	if not Color.html_is_valid(source_hex) or not Color.html_is_valid(target_hex): return _failure("Cor-fonte ou tom da rampa inválido.")
	if _same_rgb(source, target): return _failure("A cor-fonte e o tom de destino são iguais.")
	if not _palette_contains(doc.palette, source_hex): return _failure("A cor-fonte não existe na paleta do documento.")
	if not _palette_contains(doc.palette, target_hex): return _failure("O tom de destino não está na paleta do documento.")
	if not _ramp_contains(doc.art.get("material_ramps", []), ramp_name, target_hex): return _failure("O tom escolhido não pertence à rampa de material selecionada.")
	var before: Image = doc.current()
	if before == null or before.is_empty() or before.get_width() != doc.width or before.get_height() != doc.height: return _failure("A cel ativa não corresponde às dimensões do documento.")
	var protected_key: String = doc.cel_key()
	var protected_pixels: Array = doc.rig.get("protected_pixels", {}).get(protected_key, []).duplicate()
	var changed := PackedInt32Array()
	if mode == "selection":
		for y in doc.height:
			for x in doc.width:
				var point := Vector2i(x, y)
				if doc.allowed(point) and _same_rgb(before.get_pixelv(point), source): changed.append(y * doc.width + x)
	else:
		if seed.x < 0 or seed.y < 0 or seed.x >= doc.width or seed.y >= doc.height: return _failure("Semente fora do canvas.")
		if not doc.allowed(seed): return _failure("A semente está fora da seleção ou protegida.")
		if not _same_rgb(before.get_pixelv(seed), source): return _failure("A semente não contém a cor-fonte escolhida.")
		var visited := PackedByteArray()
		visited.resize(doc.width * doc.height)
		visited.fill(0)
		var stack: Array[int] = [seed.y * doc.width + seed.x]
		while not stack.is_empty():
			var index: int = stack.pop_back()
			if visited[index] != 0: continue
			visited[index] = 1
			var point := Vector2i(index % doc.width, int(index / doc.width))
			if not doc.allowed(point) or not _same_rgb(before.get_pixelv(point), source): continue
			changed.append(index)
			for offset_value in NEIGHBORS_8:
				var offset: Vector2i = offset_value
				var neighbor: Vector2i = point + offset
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= doc.width or neighbor.y >= doc.height: continue
				var neighbor_index: int = neighbor.y * doc.width + neighbor.x
				if visited[neighbor_index] == 0: stack.append(neighbor_index)
	if changed.is_empty(): return _failure("Nenhum pixel da cor-fonte está elegível dentro desta região.")
	var after: Image = before.duplicate()
	for index in changed:
		var point := Vector2i(index % doc.width, int(index / doc.width))
		var original: Color = before.get_pixelv(point)
		after.set_pixelv(point, Color(target.r, target.g, target.b, original.a))
	return {"ok": true, "document_instance": doc.get_instance_id(), "revision": doc.revision, "layer": doc.active_layer, "layer_id": str(doc.layers[doc.active_layer].id), "direction": doc.direction, "frame": doc.frame, "selection": doc.selection, "protected_key": protected_key, "protected_pixels": protected_pixels, "palette_before": doc.palette.duplicate(), "ramps_before": doc.art.get("material_ramps", []).duplicate(true), "source_hex": _canonical(source), "target_hex": _canonical(target), "ramp_name": ramp_name, "mode": mode, "seed": seed, "before": before.duplicate(), "after": after, "pixels": changed, "changed_pixels": changed.size()}

func apply(doc: RefCounted, proposal: Dictionary) -> bool:
	if doc == null or not proposal.get("ok", false): return false
	if int(proposal.get("document_instance", -1)) != doc.get_instance_id() or int(proposal.get("revision", -1)) != doc.revision: return false
	var layer_index := int(proposal.get("layer", -1))
	if doc.art.get("locked", false) or layer_index < 0 or layer_index >= doc.layers.size() or layer_index != doc.active_layer: return false
	if doc.layers[layer_index].locked or str(doc.layers[layer_index].id) != str(proposal.get("layer_id", "")) or int(proposal.get("direction", -1)) != doc.direction or int(proposal.get("frame", -1)) != doc.frame: return false
	if doc.selection != proposal.get("selection", Rect2i()) or str(proposal.get("protected_key", "")) != doc.cel_key(): return false
	if doc.rig.get("protected_pixels", {}).get(doc.cel_key(), []) != proposal.get("protected_pixels", []): return false
	if doc.palette != proposal.get("palette_before", []) or doc.art.get("material_ramps", []) != proposal.get("ramps_before", []): return false
	if not _palette_contains(doc.palette, str(proposal.get("source_hex", ""))) or not _ramp_contains(doc.art.get("material_ramps", []), str(proposal.get("ramp_name", "")), str(proposal.get("target_hex", ""))): return false
	var current: Image = doc.current()
	var before: Variant = proposal.get("before")
	var after: Variant = proposal.get("after")
	var pixels: Variant = proposal.get("pixels")
	if current == null or current.is_empty() or not before is Image or not after is Image: return false
	if before.is_empty() or after.is_empty() or before.get_size() != Vector2i(doc.width, doc.height) or after.get_size() != Vector2i(doc.width, doc.height): return false
	if not pixels is PackedInt32Array or pixels.is_empty() or pixels.size() != int(proposal.get("changed_pixels", -1)) or current.get_data() != before.get_data(): return false
	var source := Color(str(proposal.source_hex))
	var target := Color(str(proposal.target_hex))
	var expected: Image = before.duplicate()
	var visited := {}
	for index in pixels:
		if index < 0 or index >= doc.width * doc.height or visited.has(index): return false
		visited[index] = true
		var point := Vector2i(index % doc.width, int(index / doc.width))
		if not doc.allowed(point): return false
		var original: Color = before.get_pixelv(point)
		if not _same_rgb(original, source): return false
		expected.set_pixelv(point, Color(target.r, target.g, target.b, original.a))
	if expected.get_data() != after.get_data(): return false
	doc.checkpoint("Recolorir região com rampa")
	for index in pixels:
		var point := Vector2i(index % doc.width, int(index / doc.width))
		var original: Color = current.get_pixelv(point)
		current.set_pixelv(point, Color(target.r, target.g, target.b, original.a))
	doc.art.pose_approvals = []
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Recolorização localizada por cor-fonte e rampa de material; aprovações artísticas reiniciadas."
	return true

static func _same_rgb(left: Color, right: Color) -> bool:
	return roundi(left.r * 255.0) == roundi(right.r * 255.0) and roundi(left.g * 255.0) == roundi(right.g * 255.0) and roundi(left.b * 255.0) == roundi(right.b * 255.0)

static func _canonical(color: Color) -> String:
	return "#" + color.to_html(false).to_lower()

static func _palette_contains(palette: Array, hex: String) -> bool:
	if not Color.html_is_valid(hex): return false
	var wanted := _canonical(Color(hex))
	for item in palette:
		if _canonical(Color(str(item))) == wanted: return true
	return false

static func _ramp_contains(ramps: Variant, name: String, hex: String) -> bool:
	if not ramps is Array or not Color.html_is_valid(hex): return false
	var wanted := _canonical(Color(hex))
	for ramp in ramps:
		if not ramp is Dictionary or str(ramp.get("name", "")) != name: continue
		var colors: Variant = ramp.get("colors", [])
		if not colors is Array: return false
		for item in colors:
			if _canonical(Color(str(item))) == wanted: return true
	return false

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "pixels": PackedInt32Array(), "changed_pixels": 0}
