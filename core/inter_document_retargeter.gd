extends RefCounted
## Transfers a rig pose between compatible SFS documents without copying or editing raster pixels.
const Document = preload("res://core/document.gd")
const MIN_LENGTH_RATIO := 0.5
const MAX_LENGTH_RATIO := 2.0

func build(source: RefCounted, target: RefCounted, source_clip_index: int, target_clip_index: int, direction: int, source_frame: int, target_frame: int) -> Dictionary:
	if source == null or target == null or source == target:
		return _failure("Selecione um projeto de origem diferente do projeto atual.")
	if source.rig.get("family", "") != target.rig.get("family", ""):
		return _failure("Retarget recusado: as famílias anatômicas dos projetos são diferentes.")
	if direction < 0 or direction >= 8:
		return _failure("Direção inválida.")
	if not _valid_pose(source, source_clip_index, direction, source_frame) or not _valid_pose(target, target_clip_index, direction, target_frame):
		return _failure("Clip, direção ou quadro não pertence a um dos projetos.")
	var source_clip: Dictionary = source.animation.clips[source_clip_index]
	var target_clip: Dictionary = target.animation.clips[target_clip_index]
	var source_by_key := _layers_by_key(source)
	var target_by_key := _layers_by_key(target)
	if not source_by_key.get("ok", false) or not target_by_key.get("ok", false):
		return _failure(str(source_by_key.get("message", target_by_key.get("message", "Chaves de camada inválidas."))))
	var changes: Array[Dictionary] = []
	var unmatched: Array[String] = []
	var ratios: Array[String] = []
	for key in target_by_key.layers:
		var target_layer: Dictionary = target_by_key.layers[key]
		if not target_layer.visible or target_layer.cels[direction][target_frame].get_used_rect().size == Vector2i.ZERO:
			continue
		if not source_by_key.layers.has(key):
			unmatched.append(str(target_layer.name))
			continue
		var source_layer: Dictionary = source_by_key.layers[key]
		if not source_layer.visible or source_layer.cels[direction][source_frame].get_used_rect().size == Vector2i.ZERO:
			unmatched.append(str(target_layer.name) + " (sem raster de origem)")
			continue
		var source_bone: Variant = source_layer.get("bone", [])
		var target_bone: Variant = target_layer.get("bone", [])
		if not source_bone is Array or source_bone.size() != 2 or not target_bone is Array or target_bone.size() != 2:
			unmatched.append(str(target_layer.name) + " (segmento incompatível)")
			continue
		if not source.rig.skeleton.has(source_bone) or not target.rig.skeleton.has(target_bone) or str(source_layer.get("pivot", "")) != str(source_bone[0]) or str(target_layer.get("pivot", "")) != str(target_bone[0]):
			return _failure("Camada '%s': o segmento fonte ou destino não pertence ao próprio rig ou seu pivô não coincide com a raiz." % str(target_layer.name))
		for source_joint in source_bone:
			if not source.anchors.has(source_joint): return _failure("Camada '%s': falta a articulação fonte '%s'." % [str(target_layer.name), str(source_joint)])
		for target_joint in target_bone:
			if not target.anchors.has(target_joint): return _failure("Camada '%s': falta a articulação destino '%s'." % [str(target_layer.name), str(target_joint)])
		var source_root: Array = source.anchor_at(str(source_bone[0]), direction, source_frame)
		var source_tip: Array = source.anchor_at(str(source_bone[1]), direction, source_frame)
		var target_root: Array = target.anchor_at(str(target_bone[0]), direction, target_frame)
		var target_tip: Array = target.anchor_at(str(target_bone[1]), direction, target_frame)
		var source_vector := Vector2(float(source_tip[0] - source_root[0]), float(source_tip[1] - source_root[1]))
		var target_vector := Vector2(float(target_tip[0] - target_root[0]), float(target_tip[1] - target_root[1]))
		if source_vector.length_squared() < 0.01 or target_vector.length_squared() < 0.01:
			return _failure("Camada '%s': segmento tem comprimento zero." % str(target_layer.name))
		var ratio: float = source_vector.length() / target_vector.length()
		if ratio < MIN_LENGTH_RATIO or ratio > MAX_LENGTH_RATIO:
			return _failure("Camada '%s': proporção óssea %.2f fora do intervalo seguro %.1f–%.1f." % [str(target_layer.name), ratio, MIN_LENGTH_RATIO, MAX_LENGTH_RATIO])
		ratios.append("%s %.2f×" % [str(target_layer.name), ratio])
		var source_angle: float = rad_to_deg(source_vector.angle()) + source.layer_rotation(str(source_layer.id), direction, source_frame)
		var target_rotation := _wrap_degrees(source_angle - rad_to_deg(target_vector.angle()))
		var before: float = target.layer_rotation(str(target_layer.id), direction, target_frame)
		if not is_equal_approx(before, target_rotation):
			changes.append({"layer_id": str(target_layer.id), "layer_name": str(target_layer.name), "retarget_key": str(key), "source_bone": source_bone.duplicate(true), "bone": target_bone.duplicate(true), "before": before, "rotation": target_rotation})
	if not unmatched.is_empty():
		return _failure("Retarget suspenso: correspondência ausente ou incompatível em %s. Ajuste a chave de retarget e os segmentos no painel de camadas." % ", ".join(unmatched))
	if changes.is_empty():
		return _failure("Nenhuma rotação precisa ser alterada; a pose já corresponde à origem.")
	return {"ok": true, "target_instance": target.get_instance_id(), "target_revision": target.revision, "source_instance": source.get_instance_id(), "source_revision": source.revision, "source_clip": str(source_clip.name), "target_clip": str(target_clip.name), "source_clip_index": source_clip_index, "target_clip_index": target_clip_index, "direction": direction, "source_frame": source_frame, "target_frame": target_frame, "changes": changes, "ratios": ratios, "message": "%d camadas transferidas; proporções ósseas verificadas. Pixels, âncoras e camadas de origem permanecem intactos." % changes.size()}

func apply(target: RefCounted, proposal: Dictionary) -> bool:
	if target == null or not proposal.get("ok", false) or int(proposal.get("target_instance", -1)) != target.get_instance_id() or int(proposal.get("target_revision", -1)) != target.revision:
		return false
	var direction := int(proposal.get("direction", -1))
	var frame := int(proposal.get("target_frame", -1))
	var clip_index := int(proposal.get("target_clip_index", -1))
	if not _valid_pose(target, clip_index, direction, frame): return false
	var seen: Dictionary = {}
	for change in proposal.get("changes", []):
		var id := str(change.get("layer_id", ""))
		if seen.has(id): return false
		seen[id] = true
		var layer: Dictionary = {}
		for candidate in target.layers:
			if str(candidate.id) == id: layer = candidate; break
		if layer.is_empty() or layer.get("bone", []) != change.get("bone", []) or str(layer.get("retarget_key", layer.get("name", "")).strip_edges().to_lower()) != str(change.get("retarget_key", "")) or not layer.visible or layer.cels[direction][frame].get_used_rect().size == Vector2i.ZERO: return false
		var rotation := float(change.get("rotation", INF))
		if not is_finite(rotation) or rotation < -180.0 or rotation >= 180.0: return false
		if not is_equal_approx(target.layer_rotation(id, direction, frame), float(change.get("before", INF))): return false
	if seen.is_empty(): return false
	target.checkpoint("Retarget entre projetos")
	var key := "%d:%d" % [direction, frame]
	if not target.rig.has("rotations"): target.rig.rotations = {}
	if not target.rig.rotations.has(key): target.rig.rotations[key] = {}
	for change in proposal.changes: target.rig.rotations[key][str(change.layer_id)] = float(change.rotation)
	target.mark_changed()
	return true

func _valid_pose(document: RefCounted, clip_index: int, direction: int, frame: int) -> bool:
	if clip_index < 0 or clip_index >= document.animation.clips.size() or direction < 0 or direction >= 8 or frame < 0 or frame >= document.frames: return false
	return document.animation.clips[clip_index].get("frames", []).has(frame)

func _layers_by_key(document: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for layer in document.layers:
		if not layer.get("bone", []).is_empty():
			var key := str(layer.get("retarget_key", layer.get("name", ""))).strip_edges().to_lower()
			if key.is_empty(): return {"ok": false, "message": "Toda camada segmentada precisa de uma chave de retarget não vazia."}
			if result.has(key): return {"ok": false, "message": "Chave de retarget duplicada: '%s'." % key}
			result[key] = layer
	return {"ok": true, "layers": result}

func _wrap_degrees(value: float) -> float:
	return fposmod(value + 180.0, 360.0) - 180.0

func _failure(message: String) -> Dictionary:
	return {"ok": false, "changes": [], "message": message}
