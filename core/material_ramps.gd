extends RefCounted
## Deterministic, reviewable palette-ramp authoring. Does not repaint existing cels.
const MIN_STEPS := 3
const MAX_STEPS := 9
const MAX_PALETTE_COLORS := 32

func build(doc: RefCounted, title: String, shadow_index: int, base_index: int, light_index: int, step_count: int = 5) -> Dictionary:
	if doc == null: return _failure("Documento inválido.")
	if doc.art.get("locked", false): return _failure("Art Lock impede alterações na paleta.")
	var name := title.strip_edges()
	if name.is_empty() or name.length() > 48: return _failure("Informe um nome de material com até 48 caracteres.")
	if step_count < MIN_STEPS or step_count > MAX_STEPS or step_count % 2 == 0: return _failure("A rampa deve ter 3, 5, 7 ou 9 passos para preservar a cor-base central.")
	if not doc.art.get("material_ramps", []) is Array: return _failure("Lista de rampas do documento inválida.")
	for ramp in doc.art.get("material_ramps", []):
		if ramp is Dictionary and str(ramp.get("name", "")).strip_edges().to_lower() == name.to_lower(): return _failure("Já existe uma rampa com esse nome.")
	if shadow_index < 0 or base_index < 0 or light_index < 0 or shadow_index >= doc.palette.size() or base_index >= doc.palette.size() or light_index >= doc.palette.size(): return _failure("Selecione três cores existentes na paleta.")
	var source_hexes := [str(doc.palette[shadow_index]), str(doc.palette[base_index]), str(doc.palette[light_index])]
	var source_colors: Array[Color] = []
	for hex in source_hexes:
		var color := Color(hex)
		if color.a < 0.999: return _failure("As cores-fonte precisam ser opacas.")
		source_colors.append(color)
	if _canonical(source_colors[0]) == _canonical(source_colors[1]) or _canonical(source_colors[1]) == _canonical(source_colors[2]) or _canonical(source_colors[0]) == _canonical(source_colors[2]): return _failure("Sombra, base e luz precisam ser cores diferentes.")
	var colors: Array[String] = []
	var midpoint := int(step_count / 2)
	for index in step_count:
		var color: Color
		if index <= midpoint:
			color = _lerp_hsv(source_colors[0], source_colors[1], float(index) / float(midpoint))
		else:
			color = _lerp_hsv(source_colors[1], source_colors[2], float(index - midpoint) / float(midpoint))
		colors.append(_canonical(color))
	var existing := {}
	for hex in doc.palette: existing[_canonical(Color(str(hex)))] = true
	var additions: Array[String] = []
	for hex in colors:
		if not existing.has(hex):
			existing[hex] = true
			additions.append(hex)
	if doc.palette.size() + additions.size() > MAX_PALETTE_COLORS: return _failure("A rampa excede o limite de 32 cores usadas pela paleta visual do editor.")
	return {"ok": true, "document_instance": doc.get_instance_id(), "revision": doc.revision, "name": name, "source_indices": [shadow_index, base_index, light_index], "source_colors": source_hexes, "steps": step_count, "colors": colors, "additions": additions, "palette_before": doc.palette.duplicate(), "ramps_before": doc.art.get("material_ramps", []).duplicate(true), "message": "Rampa %s • %d passos • %d cores novas." % [name, step_count, additions.size()]}

func apply(doc: RefCounted, proposal: Dictionary) -> bool:
	if doc == null or not proposal.get("ok", false): return false
	if int(proposal.get("document_instance", -1)) != doc.get_instance_id() or int(proposal.get("revision", -1)) != doc.revision: return false
	if doc.art.get("locked", false) or doc.palette != proposal.get("palette_before", []) or doc.art.get("material_ramps", []) != proposal.get("ramps_before", []): return false
	var source_indices: Variant = proposal.get("source_indices", [])
	var additions: Variant = proposal.get("additions", [])
	var colors: Variant = proposal.get("colors", [])
	var source_colors: Variant = proposal.get("source_colors", [])
	if not source_indices is Array or source_indices.size() != 3 or not additions is Array or not colors is Array or not source_colors is Array or source_colors.size() != 3: return false
	var rebuilt := build(doc, str(proposal.get("name", "")), int(source_indices[0]), int(source_indices[1]), int(source_indices[2]), int(proposal.get("steps", -1)))
	if not rebuilt.get("ok", false) or rebuilt.get("colors", []) != proposal.get("colors", []) or rebuilt.get("additions", []) != proposal.get("additions", []): return false
	doc.checkpoint("Adicionar rampa de material")
	for hex in additions: doc.palette.append(str(hex))
	var ramps: Array = doc.art.get("material_ramps", []).duplicate(true)
	ramps.append({"name": str(proposal.name), "colors": colors.duplicate(), "source_colors": source_colors.duplicate(), "steps": int(proposal.steps), "interpolation": "HSV shortest hue", "created_revision": doc.revision})
	doc.art.material_ramps = ramps
	return true

static func preview_strip(colors: Array, block_width: int = 16, height: int = 24) -> Image:
	var usable: Array = colors.slice(0, 256)
	var safe_width := maxi(1, block_width)
	var safe_height := maxi(1, height)
	var image := Image.create(maxi(1, usable.size() * safe_width), safe_height, false, Image.FORMAT_RGBA8)
	image.fill(Color("222633"))
	for index in usable.size():
		var color := Color(str(usable[index]))
		image.fill_rect(Rect2i(index * safe_width, 0, safe_width, safe_height), color)
		if index > 0: image.fill_rect(Rect2i(index * safe_width, 0, 1, safe_height), Color("151821"))
	return image

static func _lerp_hsv(from: Color, to: Color, amount: float) -> Color:
	var left: Vector3 = _rgb_to_hsv(from)
	var right: Vector3 = _rgb_to_hsv(to)
	var hue_delta := right.x - left.x
	if hue_delta > 0.5: hue_delta -= 1.0
	if hue_delta < -0.5: hue_delta += 1.0
	return Color.from_hsv(fposmod(left.x + hue_delta * amount, 1.0), lerpf(left.y, right.y, amount), lerpf(left.z, right.z, amount), 1.0)

static func _rgb_to_hsv(color: Color) -> Vector3:
	var maximum := maxf(color.r, maxf(color.g, color.b))
	var minimum := minf(color.r, minf(color.g, color.b))
	var delta := maximum - minimum
	var hue := 0.0
	if delta > 0.000001:
		if is_equal_approx(maximum, color.r): hue = fposmod((color.g - color.b) / delta, 6.0) / 6.0
		elif is_equal_approx(maximum, color.g): hue = ((color.b - color.r) / delta + 2.0) / 6.0
		else: hue = ((color.r - color.g) / delta + 4.0) / 6.0
	var saturation := 0.0 if maximum <= 0.000001 else delta / maximum
	return Vector3(fposmod(hue, 1.0), saturation, maximum)

static func _canonical(color: Color) -> String:
	return "#" + color.to_html(false).to_lower()

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
