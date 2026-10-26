extends RefCounted
## Fills missing rig poses between authored keys inside one animation clip.
## Raster pixels are never modified. Existing keys and other clips/directions are preserved.

func build(doc: RefCounted, target_direction: int, clip_index: int, layer_id: String, anchor_name: String, channels: Dictionary) -> Dictionary:
	if doc == null or target_direction < 0 or target_direction >= 8:
		return _failure("Direção inválida.")
	if clip_index < 0 or clip_index >= doc.animation.clips.size():
		return _failure("Clip inválido.")
	if channels.is_empty() or not (channels.get("rotation", false) or channels.get("offset", false) or channels.get("anchor", false)):
		return _failure("Selecione ao menos um canal do rig.")
	var layer_index := -1
	for index in doc.layers.size():
		if str(doc.layers[index].id) == layer_id:
			layer_index = index
			break
	if layer_index < 0:
		return _failure("A camada selecionada não existe mais.")
	if channels.get("anchor", false) and not doc.anchors.has(anchor_name):
		return _failure("Articulação selecionada não existe.")
	var clip_value: Variant = doc.animation.clips[clip_index]
	if not clip_value is Dictionary:
		return _failure("Dados do clip inválidos.")
	var clip: Dictionary = clip_value
	var frames_value: Variant = clip.get("frames", [])
	if not frames_value is Array:
		return _failure("A lista de quadros do clip é inválida.")
	var frames: Array = frames_value
	if frames.size() < 2:
		return _failure("O clip precisa de ao menos dois quadros.")
	var rig_anchors_value: Variant = doc.rig.get("anchors", {})
	var rotations_value: Variant = doc.rig.get("rotations", {})
	var offsets_value: Variant = doc.rig.get("offsets", {})
	if not rig_anchors_value is Dictionary or not rotations_value is Dictionary or not offsets_value is Dictionary:
		return _failure("Dados serializados do rig são inválidos.")
	var rig_anchors: Dictionary = rig_anchors_value
	var rotations: Dictionary = rotations_value
	var offsets: Dictionary = offsets_value
	var seen_frames: Dictionary = {}
	for frame_value in frames:
		if not frame_value is int or int(frame_value) < 0 or int(frame_value) >= doc.frames or seen_frames.has(str(frame_value)):
			return _failure("O clip contém quadro repetido ou fora do documento.")
		seen_frames[str(frame_value)] = true
	var tracks: Array[Dictionary] = []
	if channels.get("rotation", false):
		tracks.append(_track("rotation", frames, target_direction, rotations, layer_id))
	if channels.get("offset", false):
		tracks.append(_track("offset", frames, target_direction, offsets, layer_id))
	if channels.get("anchor", false):
		tracks.append(_track("anchor", frames, target_direction, rig_anchors, anchor_name))
	var changes: Array[Dictionary] = []
	var source_key_count := 0
	for track in tracks:
		if track.has("error"):
			return _failure(str(track.error))
		source_key_count += int(track.keys.size())
		if track.keys.size() < 2:
			continue
		for pair_index in range(track.keys.size() - 1):
			var left: Dictionary = track.keys[pair_index]
			var right: Dictionary = track.keys[pair_index + 1]
			var span := int(right.clip_index) - int(left.clip_index)
			if span < 2:
				continue
			for clip_position in range(int(left.clip_index) + 1, int(right.clip_index)):
				var frame_index := int(frames[clip_position])
				var pose_key := "%d:%d" % [target_direction, frame_index]
				var existing: Dictionary = _map_at(track, pose_key)
				if existing.has(track.value_key):
					continue
				var t := float(clip_position - int(left.clip_index)) / float(span)
				var value: Variant = _interpolate_value(str(track.kind), left.value, right.value, t)
				changes.append({"kind": track.kind, "frame": frame_index, "pose_key": pose_key, "value_key": track.value_key, "value": value})
	if changes.is_empty():
		return {"ok": true, "changes": [], "source_keys": source_key_count, "message": "Não há quadros intermediários sem chave entre poses do mesmo clip."}
	return {"ok": true, "changes": changes, "source_keys": source_key_count, "revision": doc.revision, "direction": target_direction, "message": "%d valores intermediários propostos em %d quadros; pixels preservados." % [changes.size(), _unique_frame_count(changes)]}

func apply(doc: RefCounted, proposal: Dictionary) -> bool:
	if doc == null or not proposal.get("ok", false) or not proposal.get("changes", []) is Array or proposal.get("changes", []).is_empty() or int(proposal.get("revision", -1)) != doc.revision:
		return false
	# Revalidate all targets before creating one undo snapshot.
	var target_direction := int(proposal.get("direction", -1))
	if target_direction < 0 or target_direction >= 8:
		return false
	for change in proposal.changes:
		if not change is Dictionary or str(change.get("kind", "")) not in ["rotation", "offset", "anchor"] or int(change.get("direction", target_direction)) != target_direction:
			return false
		var frame_index := int(change.frame)
		if frame_index < 0 or frame_index >= doc.frames or int(change.get("frame", -1)) != frame_index:
			return false
	for change in proposal.changes:
		var kind := str(change.kind)
		if kind == "anchor" and not doc.anchors.has(str(change.value_key)):
			return false
	for change in proposal.changes:
		var target_map: Dictionary = _map_for_kind(doc, str(change.kind))
		var pose_key := str(change.pose_key)
		if target_map.get(pose_key, {}).has(str(change.value_key)):
			return false # A new artist key was authored after proposal generation.
	if not proposal.changes.is_empty():
		doc.checkpoint("Interpolar poses do rig")
	for change in proposal.changes:
		var target_map: Dictionary = _map_for_kind(doc, str(change.kind))
		var pose_key := str(change.pose_key)
		if not target_map.has(pose_key):
			target_map[pose_key] = {}
		target_map[pose_key][str(change.value_key)] = change.value.duplicate(true) if change.value is Array else change.value
	doc.mark_changed()
	return true

func _track(kind: String, frames: Array, direction: int, source: Dictionary, value_key: String) -> Dictionary:
	var keys: Array[Dictionary] = []
	for clip_position in frames.size():
		var frame_index := int(frames[clip_position])
		if frame_index < 0:
			return {"error": "Clip contém quadro inválido."}
		var pose_key := "%d:%d" % [direction, frame_index]
		var values: Dictionary = source.get(pose_key, {})
		if not values.has(value_key):
			continue
		var value: Variant = values[value_key]
		if kind == "rotation":
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < -180.0 or float(value) > 180.0:
				return {"error": "O canal de rotação contém valor inválido."}
			value = float(value)
		elif kind in ["offset", "anchor"]:
			if not _numeric_pair(value):
				return {"error": "Offset ou articulação contém coordenada inválida."}
			value = [float(value[0]), float(value[1])]
		keys.append({"clip_index": clip_position, "frame": frame_index, "value": value})
	return {"kind": kind, "keys": keys, "value_key": value_key, "target_map": source}

func _map_at(track: Dictionary, pose_key: String) -> Dictionary:
	# Captured by build() from serialized rig dictionaries, not mutated until apply().
	return track.get("target_map", {}).get(pose_key, {})

func _map_for_kind(doc: RefCounted, kind: String) -> Dictionary:
	match kind:
		"rotation": return doc.rig.get("rotations", {})
		"offset": return doc.rig.get("offsets", {})
		"anchor": return doc.rig.get("anchors", {})
	return {}

func _interpolate_value(kind: String, left: Variant, right: Variant, t: float) -> Variant:
	if kind == "rotation":
		var delta := fposmod(float(right) - float(left) + 180.0, 360.0) - 180.0
		return fposmod(float(left) + delta * t + 180.0, 360.0) - 180.0
	return [lerpf(float(left[0]), float(right[0]), t), lerpf(float(left[1]), float(right[1]), t)]

func _numeric_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))

func _unique_frame_count(changes: Array[Dictionary]) -> int:
	var unique: Dictionary = {}
	for change in changes:
		unique[str(change.frame)] = true
	return unique.size()

func _failure(message: String) -> Dictionary:
	return {"ok": false, "changes": [], "source_keys": 0, "message": message}
