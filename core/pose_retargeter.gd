extends RefCounted
## Transfers articulated layer orientation between two pose frames of one compatible rig.
## It never edits source/target raster pixels; only destination layer rotation keys change.

func build(doc: RefCounted, clip_index: int, target_direction: int, source_frame: int, target_frame: int) -> Dictionary:
	if doc == null or target_direction < 0 or target_direction >= 8:
		return _failure("Direção inválida.")
	if clip_index < 0 or clip_index >= doc.animation.clips.size():
		return _failure("Clip inválido.")
	var clip_value: Variant = doc.animation.clips[clip_index]
	if not clip_value is Dictionary or not clip_value.get("frames", []) is Array:
		return _failure("Clip ou lista de poses inválida.")
	var clip: Dictionary = clip_value
	var frames: Array = clip.frames
	if not frames.has(source_frame) or not frames.has(target_frame):
		return _failure("Origem e destino devem pertencer ao mesmo clip selecionado.")
	if source_frame == target_frame:
		return _failure("Origem e destino precisam ser quadros diferentes.")
	if str(doc.rig.get("family", "")) == "" or not doc.rig.get("skeleton", []) is Array:
		return _failure("Família ou topologia do rig ausente.")
	var changes: Array[Dictionary] = []
	var unmapped: Array[String] = []
	for layer in doc.layers:
		if not layer.visible or layer.get("equipment", false) and not doc.compatible(layer):
			continue
		var target_cel: Image = layer.cels[target_direction][target_frame]
		if target_cel.get_used_rect().size == Vector2i.ZERO:
			continue
		var bone: Variant = layer.get("bone", [])
		if not bone is Array or bone.size() != 2:
			unmapped.append(str(layer.name))
			continue
		if not doc.rig.skeleton.has(bone) or str(layer.get("pivot", "")) != str(bone[0]):
			return _failure("Camada '%s': segmento não pertence à topologia ou o pivô não coincide com a raiz do osso." % str(layer.name))
		if not doc.anchors.has(bone[0]) or not doc.anchors.has(bone[1]):
			return _failure("Camada '%s': articulações do segmento estão ausentes." % str(layer.name))
		var source_root := Vector2(float(doc.anchor_at(str(bone[0]), target_direction, source_frame)[0]), float(doc.anchor_at(str(bone[0]), target_direction, source_frame)[1]))
		var source_tip := Vector2(float(doc.anchor_at(str(bone[1]), target_direction, source_frame)[0]), float(doc.anchor_at(str(bone[1]), target_direction, source_frame)[1]))
		var target_root := Vector2(float(doc.anchor_at(str(bone[0]), target_direction, target_frame)[0]), float(doc.anchor_at(str(bone[0]), target_direction, target_frame)[1]))
		var target_tip := Vector2(float(doc.anchor_at(str(bone[1]), target_direction, target_frame)[0]), float(doc.anchor_at(str(bone[1]), target_direction, target_frame)[1]))
		var source_vector := source_tip - source_root
		var target_vector := target_tip - target_root
		if source_vector.length_squared() < 0.01 or target_vector.length_squared() < 0.01:
			return _failure("Camada '%s': segmento tem comprimento zero em uma das poses." % str(layer.name))
		var source_total_angle: float = rad_to_deg(source_vector.angle()) + doc.layer_rotation(str(layer.id), target_direction, source_frame)
		var target_rotation := _wrap_degrees(source_total_angle - rad_to_deg(target_vector.angle()))
		var before: float = doc.layer_rotation(str(layer.id), target_direction, target_frame)
		if not is_equal_approx(before, target_rotation):
			changes.append({"layer_id": str(layer.id), "layer_name": str(layer.name), "bone": bone.duplicate(true), "before": before, "rotation": target_rotation})
	if not unmapped.is_empty():
		return _failure("Retarget suspenso: mapeie ao segmento ósseo cada camada raster visível do destino. Sem mapeamento: %s." % ", ".join(unmapped))
	if changes.is_empty():
		return _failure("Nenhum segmento visível precisa de ajuste; o destino já corresponde à orientação de origem.")
	return {"ok": true, "revision": doc.revision, "clip_index": clip_index, "direction": target_direction, "source_frame": source_frame, "target_frame": target_frame, "changes": changes, "message": "%d partes mapeadas; destino atualizado pela pose do quadro %d. Pixels permanecem editáveis." % [changes.size(), source_frame + 1]}

func apply(doc: RefCounted, proposal: Dictionary) -> bool:
	if doc == null or not proposal.get("ok", false) or not proposal.get("changes", []) is Array or proposal.get("changes", []).is_empty() or int(proposal.get("revision", -1)) != doc.revision:
		return false
	var clip_index := int(proposal.get("clip_index", -1))
	var direction := int(proposal.get("direction", -1))
	var source_frame := int(proposal.get("source_frame", -1))
	var target_frame := int(proposal.get("target_frame", -1))
	if clip_index < 0 or clip_index >= doc.animation.clips.size() or direction < 0 or direction >= 8 or source_frame < 0 or target_frame < 0 or source_frame >= doc.frames or target_frame >= doc.frames or source_frame == target_frame:
		return false
	if not doc.animation.clips[clip_index].get("frames", []).has(source_frame) or not doc.animation.clips[clip_index].get("frames", []).has(target_frame):
		return false
	for change in proposal.get("changes", []):
		var layer_exists: bool = doc.layers.any(func(layer): return str(layer.id) == str(change.get("layer_id", "")))
		var rotation := float(change.get("rotation", INF))
		if not layer_exists or not is_finite(rotation) or rotation < -180.0 or rotation >= 180.0:
			return false
	var rotations: Dictionary = doc.rig.get("rotations", {})
	var target_key := "%d:%d" % [direction, target_frame]
	for change in proposal.changes:
		if not is_equal_approx(float(rotations.get(target_key, {}).get(str(change.layer_id), 0.0)), float(change.before)):
			return false
	doc.checkpoint("Retarget pose par segment")
	if not doc.rig.has("rotations"): doc.rig.rotations = {}
	if not doc.rig.rotations.has(target_key): doc.rig.rotations[target_key] = {}
	for change in proposal.changes:
		doc.rig.rotations[target_key][str(change.layer_id)] = float(change.rotation)
	doc.mark_changed()
	return true

func _wrap_degrees(value: float) -> float:
	return fposmod(value + 180.0, 360.0) - 180.0

func _failure(message: String) -> Dictionary:
	return {"ok": false, "changes": [], "message": message}
