extends RefCounted
## Produces a restrained, loopable breathing cycle from a stable pose.

static func generate_breathing(doc: RefCounted, layer_index: int, clip_name: String, amplitude: float = 1.5) -> Dictionary:
	if doc == null or layer_index < 0 or layer_index >= doc.layers.size():
		return {"ok": false, "error": "Documento ou camada inválidos."}
	if doc.art.get("locked", false): return {"ok": false, "error": "Art Lock impede alterar a animação."}
	var layer: Dictionary = doc.layers[layer_index]
	if layer.get("locked", false): return {"ok": false, "error": "Desbloqueie a camada antes de gerar a respiração."}
	if not is_finite(amplitude) or amplitude < 0.5 or amplitude > 2.0:
		return {"ok": false, "error": "Amplitude deve ficar entre 0,5 e 2 pixels."}
	var clip_index := -1
	for index in doc.animation.clips.size():
		if doc.animation.clips[index].name == clip_name: clip_index = index
	if clip_index < 0: return {"ok": false, "error": "Clip não encontrado."}
	var clip: Dictionary = doc.animation.clips[clip_index]
	if not clip.loop or clip.frames.size() < 4: return {"ok": false, "error": "Escolha um clip em loop com pelo menos quatro quadros."}
	var base_frame := int(clip.frames[0])
	var sources: Array[Image] = []
	for direction in 8:
		var source: Image = layer.cels[direction][base_frame]
		if source.get_used_rect().size == Vector2i.ZERO: return {"ok": false, "error": "A pose-base está vazia em %s." % doc.DIRECTIONS[direction]}
		sources.append(source.duplicate())
	var generated: Array = []
	for direction in 8:
		var frames: Array[Image] = []
		for frame_index in clip.frames.size():
			frames.append(_warp_breath(sources[direction], amplitude, TAU * (float(frame_index) + 0.65) / clip.frames.size()))
		generated.append(frames)
	doc.checkpoint("Gerar ciclo de respiração")
	for direction in 8:
		for frame_index in clip.frames.size():
			layer.cels[direction][int(clip.frames[frame_index])] = generated[direction][frame_index]
			var key: String = doc.cel_key(direction, int(clip.frames[frame_index]))
			doc.animation.hitboxes.erase(key)
			doc.animation.events.erase(key)
	# Remove only pose-level approvals for the changed clip; whole-document approvals are stale.
	doc.art.pose_approvals = doc.art.get("pose_approvals", []).filter(func(item): return str(item.get("clip", "")) != clip_name)
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Ciclo de respiração gerado proceduralmente; pose-base preservada e animação derivada pendente de revisão."
	doc.mark_changed()
	return {"ok": true, "directions": 8, "frames": clip.frames.size(), "amplitude": amplitude}

static func _warp_breath(source: Image, amplitude: float, phase: float) -> Image:
	var result := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	var bounds := source.get_used_rect()
	var center_x := (bounds.position.x + bounds.end.x - 1) * 0.5
	var torso_top := bounds.position.y + bounds.size.y * 0.31
	var torso_height := maxf(2.0, bounds.size.y * 0.34)
	var vertical_wave := sin(phase)
	var width_wave := cos(phase)
	for y in range(bounds.position.y, bounds.end.y):
		var relative := (float(y) - torso_top) / torso_height
		var weight := pow(sin(PI * clampf(relative, 0.0, 1.0)), 2.0) if relative >= 0.0 and relative <= 1.0 else 0.0
		var source_y := clampi(roundi(float(y) + amplitude * vertical_wave * weight), 0, source.get_height() - 1)
		var spread := 1.0 + 0.12 * width_wave * weight
		var sway := 0.8 * width_wave * weight
		for x in range(bounds.position.x, bounds.end.x):
			var source_x := clampi(roundi(center_x + (float(x) - center_x - sway) / spread), 0, source.get_width() - 1)
			var color := source.get_pixel(source_x, source_y)
			if color.a > 0.0: result.set_pixel(x, y, color)
	return result
