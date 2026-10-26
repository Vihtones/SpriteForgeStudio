extends RefCounted
## Creates editable, nearest-neighbor raster poses between authored rig keys.
const Document = preload("res://core/document.gd")
const MAX_STEPS := 8

func build_inserted(doc: RefCounted, clip_index: int, direction: int, source_frame: int, target_frame: int, insert_count: int, scale_segments: bool = true) -> Dictionary:
	## Proposes new timeline frames between adjacent keys. The proposal is built on a
	## detached document so previews never mutate the user's project.
	if doc == null or clip_index < 0 or clip_index >= doc.animation.clips.size() or direction < 0 or direction >= 8:
		return _failure("Documento, clip ou direção inválidos.")
	if insert_count < 1 or insert_count > MAX_STEPS:
		return _failure("Escolha entre um e oito novos quadros por operação.")
	if doc.art.get("locked", false): return _failure("Art Lock impede inserir quadros raster.")
	var clip: Dictionary = doc.animation.clips[clip_index]
	var source_position: int = clip.get("frames", []).find(source_frame)
	var target_position: int = clip.get("frames", []).find(target_frame)
	if source_position < 0 or target_position != source_position + 1:
		return _failure("Para inserir quadros, escolha duas poses adjacentes do mesmo clip e na ordem correta.")
	if doc.frames + insert_count > 32:
		return _failure("A inserção ultrapassaria o limite de 32 frames do documento.")
	if doc.layer_mask_pixels() + doc.mask_pixels_at_frame(source_frame) * insert_count > Document.MAX_LAYER_MASK_PIXELS: return _failure("A inserção ultrapassaria o limite de memória das máscaras.")
	if doc.width * doc.height * 4 * (doc.frames + insert_count) * 8 * doc.layers.size() > doc.pixel_budget_limit:
		return _failure("A inserção ultrapassaria o orçamento de memória do documento.")
	if not doc.rig.get("protected_pixels", {}).get("%d:%d" % [direction, source_frame], []).is_empty():
		return _failure("A pose fonte contém pixels protegidos; remova a máscara ou escolha outra pose para não mover arte protegida.")
	var preview_doc: RefCounted = doc.detached_copy()
	preview_doc.animation.active = clip_index
	preview_doc.frame = source_frame
	var inserted_frames: Array[int] = []
	for index in insert_count:
		preview_doc.frame = source_frame
		var inserted: int = preview_doc.insert_frame_after(source_frame, false)
		if inserted < 0: return _failure("Não foi possível inserir os quadros na prévia segura.")
	for index in insert_count: inserted_frames.append(source_frame + index + 1)
	# Insertion duplicates source-key metadata. New temporal poses must start without
	# copied events, hitboxes, protection masks, depth overrides, or rigid transforms.
	for inserted in inserted_frames:
		var key := "%d:%d" % [direction, inserted]
		preview_doc.rig.get("anchors", {}).erase(key)
		preview_doc.rig.get("depth", {}).erase(key)
		preview_doc.rig.get("offsets", {}).erase(key)
		preview_doc.rig.get("rotations", {}).erase(key)
		preview_doc.rig.get("protected_pixels", {}).erase(key)
		preview_doc.animation.events.erase(key)
		preview_doc.animation.hitboxes.erase(key)
	var shifted_target := target_frame + insert_count
	var generated: Dictionary = build(preview_doc, clip_index, direction, source_frame, shifted_target, scale_segments)
	if not generated.get("ok", false): return generated
	var original_clip: Dictionary = doc.animation.clips[clip_index]
	var source_duration := float(original_clip.get("durations_ms", {}).get(str(source_frame), 1000.0 / doc.fps))
	var target_duration := float(original_clip.get("durations_ms", {}).get(str(target_frame), 1000.0 / doc.fps))
	var duration_each := (source_duration + target_duration) / float(insert_count + 2)
	var durations: Dictionary = {}
	durations[str(source_frame)] = duration_each
	for index in insert_count: durations[str(source_frame + index + 1)] = duration_each
	durations[str(target_frame + insert_count)] = duration_each
	generated.document_instance = doc.get_instance_id()
	generated.revision = doc.revision
	generated.operation = "insert_frames"
	generated.original_source_frame = source_frame
	generated.original_target_frame = target_frame
	generated.insert_count = insert_count
	generated.inserted_frames = inserted_frames.duplicate()
	generated.preview_frames = [source_frame] + inserted_frames + [shifted_target]
	generated.durations = durations
	generated.preview_document = preview_doc
	generated.message = "%d novos quadros raster entre os frames %d e %d; os %d ms originais foram redistribuídos. Pixels da pose inicial articulados por camadas rígidas; revise contornos, membros e contatos." % [insert_count, source_frame + 1, target_frame + 1, roundi(source_duration + target_duration)]
	return generated

func apply_inserted(doc: RefCounted, proposal: Dictionary) -> bool:
	if doc == null or not proposal.get("ok", false) or proposal.get("operation", "") != "insert_frames": return false
	if int(proposal.get("document_instance", -1)) != doc.get_instance_id() or int(proposal.get("revision", -1)) != doc.revision: return false
	var clip_index := int(proposal.get("clip_index", -1))
	var direction := int(proposal.get("direction", -1))
	var source_frame := int(proposal.get("original_source_frame", -1))
	var target_frame := int(proposal.get("original_target_frame", -1))
	var insert_count := int(proposal.get("insert_count", 0))
	if clip_index < 0 or clip_index >= doc.animation.clips.size() or direction < 0 or direction >= 8 or insert_count < 1 or insert_count > MAX_STEPS: return false
	var clip: Dictionary = doc.animation.clips[clip_index]
	var source_position: int = clip.frames.find(source_frame)
	if source_position < 0 or source_position + 1 >= clip.frames.size() or int(clip.frames[source_position + 1]) != target_frame: return false
	if doc.frames + insert_count > 32 or proposal.get("inserted_frames", []).size() != insert_count: return false
	var generated := proposal.duplicate()
	generated.document_instance = doc.get_instance_id()
	doc.checkpoint("Inserir e gerar quadros raster intermediários")
	doc.animation.active = clip_index
	for index in insert_count:
		doc.frame = source_frame
		if doc.insert_frame_after(source_frame, false) < 0:
			doc.undo()
			return false
	for index in insert_count:
		var inserted := source_frame + index + 1
		if int(proposal.inserted_frames[index]) != inserted:
			doc.undo()
			return false
		var key := "%d:%d" % [direction, inserted]
		for track in [doc.rig.get("anchors", {}), doc.rig.get("depth", {}), doc.rig.get("offsets", {}), doc.rig.get("rotations", {}), doc.rig.get("protected_pixels", {}), doc.animation.events, doc.animation.hitboxes]: track.erase(key)
	var shifted_target := target_frame + insert_count
	var current_clip: Dictionary = doc.animation.clips[clip_index]
	if current_clip.frames.find(source_frame) + insert_count + 1 >= current_clip.frames.size() or int(current_clip.frames[current_clip.frames.find(source_frame) + insert_count + 1]) != shifted_target:
		doc.undo()
		return false
	for frame_text in proposal.durations:
		current_clip.durations_ms[str(frame_text)] = float(proposal.durations[frame_text])
	doc.animation.clips[clip_index] = current_clip
	generated.revision = doc.revision
	if not apply(doc, generated, false):
		doc.undo()
		return false
	return true

func build(doc: RefCounted, clip_index: int, direction: int, source_frame: int, target_frame: int, scale_segments: bool = true) -> Dictionary:
	if doc == null or clip_index < 0 or clip_index >= doc.animation.clips.size() or direction < 0 or direction >= 8:
		return _failure("Documento, clip ou direção inválidos.")
	if doc.art.get("locked", false): return _failure("Art Lock impede criar quadros raster.")
	var clip: Dictionary = doc.animation.clips[clip_index]
	var source_position: int = clip.get("frames", []).find(source_frame)
	var target_position: int = clip.get("frames", []).find(target_frame)
	if source_position < 0 or target_position <= source_position:
		return _failure("Escolha duas poses-chave em ordem dentro do mesmo clip.")
	var step_count := target_position - source_position - 1
	if step_count < 1: return _failure("Insira ao menos um frame entre as poses-chave.")
	if step_count > MAX_STEPS: return _failure("O intervalo tem %d frames; o limite seguro por geração é %d." % [step_count, MAX_STEPS])
	var intermediate: Array[int] = []
	for position in range(source_position + 1, target_position): intermediate.append(int(clip.frames[position]))
	var source_key := "%d:%d" % [direction, source_frame]
	var target_key := "%d:%d" % [direction, target_frame]
	for frame in intermediate:
		var key := "%d:%d" % [direction, frame]
		if not doc.rig.get("protected_pixels", {}).get(key, []).is_empty(): return _failure("Frame %d contém pixels protegidos; remova a máscara antes de gerar." % (frame + 1))
		if not doc.animation.events.get(key, []).is_empty() or doc.animation.hitboxes.has(key): return _failure("Frame %d contém evento ou hitbox editado; preserve-o e escolha outro intervalo." % (frame + 1))
	var anchors_by_frame: Dictionary = {}
	for index in step_count:
		var frame := intermediate[index]
		var t := float(index + 1) / float(step_count + 1)
		var anchors: Dictionary = {}
		for anchor_name in doc.anchors:
			var source_point: Array = doc.anchor_at(str(anchor_name), direction, source_frame)
			var target_point: Array = doc.anchor_at(str(anchor_name), direction, target_frame)
			anchors[str(anchor_name)] = [roundi(lerpf(float(source_point[0]), float(target_point[0]), t)), roundi(lerpf(float(source_point[1]), float(target_point[1]), t))]
		anchors_by_frame[str(frame)] = anchors
	var changes: Array[Dictionary] = []
	for layer_index in doc.layers.size():
		var layer: Dictionary = doc.layers[layer_index]
		if not layer.visible: continue
		if not layer.get("visibility_masks", {}).is_empty(): return _failure("A camada '%s' possui máscara de visibilidade. Remova a máscara antes de sintetizar poses raster; o original permanece intacto." % str(layer.name))
		if layer.locked: return _failure("Camada visível '%s' está bloqueada." % str(layer.name))
		if layer.equipment and not doc.compatible(layer): return _failure("Equipamento visível '%s' não é compatível com a família atual." % str(layer.name))
		var bone: Variant = layer.get("bone", [])
		if not bone is Array or bone.size() != 2 or not doc.rig.get("skeleton", []).has(bone) or str(layer.get("pivot", "")) != str(bone[0]):
			return _failure("Mapeie a camada visível '%s' a um segmento ósseo válido com pivô na raiz." % str(layer.name))
		var source_image: Image = layer.cels[direction][source_frame]
		var target_image: Image = layer.cels[direction][target_frame]
		if source_image.get_used_rect().size == Vector2i.ZERO or target_image.get_used_rect().size == Vector2i.ZERO:
			return _failure("Camada '%s' precisa ter pixels nas duas poses-chave." % str(layer.name))
		var src_root: Array = doc.anchor_at(str(bone[0]), direction, source_frame)
		var src_tip: Array = doc.anchor_at(str(bone[1]), direction, source_frame)
		var dst_root: Array = doc.anchor_at(str(bone[0]), direction, target_frame)
		var dst_tip: Array = doc.anchor_at(str(bone[1]), direction, target_frame)
		var source_vector := Vector2(float(src_tip[0] - src_root[0]), float(src_tip[1] - src_root[1]))
		var target_vector := Vector2(float(dst_tip[0] - dst_root[0]), float(dst_tip[1] - dst_root[1]))
		if source_vector.length_squared() < 0.01 or target_vector.length_squared() < 0.01:
			return _failure("Camada '%s': o segmento de uma pose-chave tem comprimento zero." % str(layer.name))
		var segment_scale := target_vector.length() / source_vector.length()
		if scale_segments and (segment_scale < 0.5 or segment_scale > 2.0):
			return _failure("Camada '%s': mudança de comprimento ósseo %.2f× fora do intervalo seguro de 0,5× a 2×." % [str(layer.name), segment_scale])
		var source_orientation: float = rad_to_deg(source_vector.angle()) + doc.layer_rotation(str(layer.id), direction, source_frame)
		var target_orientation: float = rad_to_deg(target_vector.angle()) + doc.layer_rotation(str(layer.id), direction, target_frame)
		var delta := _wrap_degrees(target_orientation - source_orientation)
		var source_offset: Array = doc.rig.get("offsets", {}).get(source_key, {}).get(str(layer.id), layer.offset)
		var target_offset: Array = doc.rig.get("offsets", {}).get(target_key, {}).get(str(layer.id), layer.offset)
		for index in step_count:
			var frame := intermediate[index]
			var t := float(index + 1) / float(step_count + 1)
			var frame_anchors: Dictionary = anchors_by_frame[str(frame)]
			var root_point: Array = frame_anchors[str(bone[0])]
			var tip_point: Array = frame_anchors[str(bone[1])]
			var interpolated_vector := Vector2(float(tip_point[0] - root_point[0]), float(tip_point[1] - root_point[1]))
			if interpolated_vector.length_squared() < 0.01: return _failure("A interpolação colapsa o segmento '%s' no frame %d." % [str(layer.name), frame + 1])
			var current_segment_scale := interpolated_vector.length() / source_vector.length()
			if scale_segments and (current_segment_scale < 0.5 or current_segment_scale > 2.0):
				return _failure("Camada '%s': interpolação exige escala %.2f× no frame %d, fora do intervalo seguro de 0,5× a 2×." % [str(layer.name), current_segment_scale, frame + 1])
			var absolute_orientation: float = source_orientation + delta * t
			var rotation := _wrap_degrees(absolute_orientation - rad_to_deg(interpolated_vector.angle()))
			var local_offset := [roundi(lerpf(float(source_offset[0]), float(target_offset[0]), t)), roundi(lerpf(float(source_offset[1]), float(target_offset[1]), t))]
			var global_offset := Vector2i.ZERO
			var neutral_offset := [0, 0]
			if layer.equipment:
				var equipment_anchor: Array = frame_anchors.get(str(layer.get("anchor", "hand")), doc.anchors.get(str(layer.get("anchor", "hand")), [0, 0]))
				global_offset = Vector2i(int(equipment_anchor[0]) + int(local_offset[0]), int(equipment_anchor[1]) + int(local_offset[1]))
				neutral_offset = [-int(equipment_anchor[0]), -int(equipment_anchor[1])]
			var baked: Image = doc.blank()
			if scale_segments and not layer.equipment:
				var source_axis := source_vector.normalized().rotated(deg_to_rad(doc.layer_rotation(str(layer.id), direction, source_frame)))
				var target_axis := Vector2.RIGHT.rotated(deg_to_rad(absolute_orientation))
				baked = _resample_segment(source_image, Vector2(src_root[0], src_root[1]), source_axis, Vector2(root_point[0], root_point[1]), target_axis, interpolated_vector.length() / source_vector.length(), doc.width, doc.height)
			else:
				var rotated: Image = doc.rotate_layer(source_image, Vector2i(int(root_point[0]), int(root_point[1])), rotation)
				baked.blend_rect(rotated, Rect2i(0, 0, doc.width, doc.height), global_offset)
			changes.append({"frame": frame, "layer_id": str(layer.id), "image": baked, "neutral_offset": neutral_offset})
	return {"ok": true, "document_instance": doc.get_instance_id(), "revision": doc.revision, "clip_index": clip_index, "clip_name": str(clip.name), "direction": direction, "source_frame": source_frame, "target_frame": target_frame, "frames": intermediate, "anchors": anchors_by_frame, "scale_segments": scale_segments, "changes": changes, "message": "%d cels rasterizados entre %s (frame %d) e %s (frame %d), na direção %s. %s; revise contornos e contatos antes de aprovar." % [step_count, str(clip.name), source_frame + 1, str(clip.name), target_frame + 1, Document.DIRECTIONS[direction], "Camadas anatômicas foram redimensionadas por seu segmento ósseo" if scale_segments else "Camadas foram rigidamente articuladas sem alteração de escala"]}

func _resample_segment(source: Image, source_root: Vector2, source_axis: Vector2, target_root: Vector2, target_axis: Vector2, scale: float, width: int, height: int) -> Image:
	## Inverse-maps target pixels through normalized bone coordinates. This applies
	## uniform nearest-neighbour scaling and rotation, so fills remain deterministic,
	## discrete, and limited to colors already present in the source cel.
	var result := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var source_normal := Vector2(-source_axis.y, source_axis.x)
	var target_normal := Vector2(-target_axis.y, target_axis.x)
	var source_center := source_root + Vector2(0.5, 0.5)
	var target_center := target_root + Vector2(0.5, 0.5)
	var safe_scale := maxf(scale, 0.0001)
	var used := source.get_used_rect()
	if used.size == Vector2i.ZERO: return result
	var bounds := Rect2i(used.position, used.size)
	# Forward splatting preserves single-pixel and one-pixel-thick features that an
	# inverse nearest-neighbour sample could otherwise miss after a fractional turn.
	for sy in range(bounds.position.y, bounds.end.y):
		for sx in range(bounds.position.x, bounds.end.x):
			var source_color := source.get_pixel(sx, sy)
			if source_color.a <= 0.0: continue
			var source_relative := Vector2(sx + 0.5, sy + 0.5) - source_center
			var along_forward := source_relative.dot(source_axis) * safe_scale
			var across_forward := source_relative.dot(source_normal) * safe_scale
			var target_pixel := target_center + target_axis * along_forward + target_normal * across_forward
			var target_x := floori(target_pixel.x); var target_y := floori(target_pixel.y)
			if target_x >= 0 and target_y >= 0 and target_x < width and target_y < height and result.get_pixel(target_x, target_y).a <= 0.0:
				result.set_pixel(target_x, target_y, source_color)
	var corners := [Vector2(bounds.position), Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end)]
	var min_x := width; var min_y := height; var max_x := 0; var max_y := 0
	for corner in corners:
		var relative_corner: Vector2 = corner + Vector2(0.5, 0.5) - source_center
		var mapped: Vector2 = target_center + target_axis * relative_corner.dot(source_axis) * safe_scale + target_normal * relative_corner.dot(source_normal) * safe_scale
		min_x = mini(min_x, floori(mapped.x) - 1); min_y = mini(min_y, floori(mapped.y) - 1)
		max_x = maxi(max_x, ceili(mapped.x) + 1); max_y = maxi(max_y, ceili(mapped.y) + 1)
	var x_start := clampi(min_x, 0, width); var x_end := clampi(max_x, 0, width)
	var y_start := clampi(min_y, 0, height); var y_end := clampi(max_y, 0, height)
	for y in range(y_start, y_end):
		for x in range(x_start, x_end):
			if result.get_pixel(x, y).a > 0.0: continue
			var relative := Vector2(x + 0.5, y + 0.5) - target_center
			var along := relative.dot(target_axis) / safe_scale
			var across := relative.dot(target_normal) / safe_scale
			var sample := source_center + source_axis * along + source_normal * across
			var sx := floori(sample.x)
			var sy := floori(sample.y)
			if sx >= 0 and sy >= 0 and sx < source.get_width() and sy < source.get_height():
				var color := source.get_pixel(sx, sy)
				if color.a > 0.0: result.set_pixel(x, y, color)
	return result

func apply(doc: RefCounted, proposal: Dictionary, make_checkpoint: bool = true) -> bool:
	if doc == null or not proposal.get("ok", false) or int(proposal.get("document_instance", -1)) != doc.get_instance_id() or int(proposal.get("revision", -1)) != doc.revision: return false
	var clip_index := int(proposal.get("clip_index", -1))
	var direction := int(proposal.get("direction", -1))
	var source_frame := int(proposal.get("source_frame", -1))
	var target_frame := int(proposal.get("target_frame", -1))
	if clip_index < 0 or clip_index >= doc.animation.clips.size() or direction < 0 or direction >= 8: return false
	var clip: Dictionary = doc.animation.clips[clip_index]
	var source_position: int = clip.frames.find(source_frame)
	var target_position: int = clip.frames.find(target_frame)
	if source_position < 0 or target_position <= source_position or target_position - source_position - 1 != proposal.get("frames", []).size(): return false
	if doc.animation.clips[clip_index].get("frames", []).slice(source_position + 1, target_position) != proposal.frames: return false
	var seen: Dictionary = {}
	var visible_layers := 0
	for layer in doc.layers:
		if layer.visible: visible_layers += 1
	for change in proposal.get("changes", []):
		var frame := int(change.get("frame", -1))
		var layer_id := str(change.get("layer_id", ""))
		var lookup := "%d:%s" % [frame, layer_id]
		if seen.has(lookup) or not proposal.frames.has(frame) or not change.get("image") is Image or change.image.get_size() != Vector2i(doc.width, doc.height): return false
		seen[lookup] = true
		var layer_exists: bool = doc.layers.any(func(layer): return str(layer.id) == layer_id and layer.visible and not layer.locked)
		if not layer_exists or not doc.rig.get("protected_pixels", {}).get("%d:%d" % [direction, frame], []).is_empty(): return false
	if seen.size() != visible_layers * proposal.frames.size(): return false
	if make_checkpoint: doc.checkpoint("Gerar poses raster intermediárias")
	for change in proposal.changes:
		for layer in doc.layers:
			if str(layer.id) == str(change.layer_id):
				layer.cels[direction][int(change.frame)] = change.image.duplicate()
				var rig_key := "%d:%d" % [direction, int(change.frame)]
				if doc.rig.get("rotations", {}).has(rig_key):
					doc.rig.rotations[rig_key].erase(str(layer.id))
					if doc.rig.rotations[rig_key].is_empty(): doc.rig.rotations.erase(rig_key)
				if layer.equipment:
					if not doc.rig.has("offsets"): doc.rig.offsets = {}
					if not doc.rig.offsets.has(rig_key): doc.rig.offsets[rig_key] = {}
					doc.rig.offsets[rig_key][str(layer.id)] = change.neutral_offset.duplicate(true)
	var anchors: Dictionary = doc.rig.get("anchors", {})
	if not doc.rig.has("anchors"): doc.rig.anchors = anchors
	for frame_text in proposal.anchors:
		var key := "%d:%s" % [direction, str(frame_text)]
		doc.rig.anchors[key] = proposal.anchors[frame_text].duplicate(true)
	doc.art.pose_approvals = doc.art.get("pose_approvals", []).filter(func(item): return str(item.get("clip", "")) != str(proposal.clip_name))
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Quadros raster intermediários gerados por interpolação rígida de camadas; revisão humana pendente."
	doc.mark_changed()
	return true

func contact_sheet(doc: RefCounted, direction: int, frames: Array, columns: int = 4) -> Image:
	var safe_columns := clampi(columns, 1, maxi(1, frames.size()))
	var rows := ceili(float(frames.size()) / safe_columns)
	var sheet := Image.create(doc.width * safe_columns, doc.height * maxi(1, rows), false, Image.FORMAT_RGBA8)
	for index in frames.size(): sheet.blit_rect(doc.composite(direction, int(frames[index])), Rect2i(0, 0, doc.width, doc.height), Vector2i((index % safe_columns) * doc.width, int(index / safe_columns) * doc.height))
	return sheet

func _wrap_degrees(value: float) -> float:
	return fposmod(value + 180.0, 360.0) - 180.0

func _failure(message: String) -> Dictionary:
	return {"ok": false, "changes": [], "frames": [], "message": message}
