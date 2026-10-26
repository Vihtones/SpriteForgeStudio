extends RefCounted
## Converts deterministic 3D viewport captures into editable document cels.
const MAX_CAPTURE_FRAMES := 8
const MAX_TURNTABLE_VIEWS := 64
const MAX_TURNTABLE_RGBA_BYTES := 67108864
const MAX_BASELINE_BYTES := 8000000
const MAX_PROJECT_JSON_BYTES := 67108864
const MAX_MODEL_BYTES := 16777216
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const JOINTS := ["torso", "left_arm", "right_arm", "left_elbow", "right_elbow", "left_leg", "right_leg", "left_knee", "right_knee"]
const DEFAULT_PROPORTIONS := {"torso_height": 1.0, "shoulder_width": 1.0, "arm_length": 1.0, "leg_length": 1.0}
const PROPORTION_LIMITS := {"torso_height": Vector2(0.75, 1.25), "shoulder_width": Vector2(0.75, 1.25), "arm_length": Vector2(0.75, 1.25), "leg_length": Vector2(0.75, 1.25)}
const DEFAULT_EQUIPMENT_ATTACHMENTS := {"shield": [0.0, -0.22, 0.0], "sword": [0.0, -0.46, 0.0]}
const LEGACY_DEFAULT_SHIELD_ATTACHMENTS := [[-0.11, -0.22, 0.10], [0.0, -0.22, 0.08], [0.0, -0.22, 0.06]]
const EQUIPMENT_ANCHORS := {"shield": "shield_mount", "sword": "weapon_mount"}
const ATTACHMENT_LIMITS := {"x": Vector2(-0.5, 0.5), "y": Vector2(-1.2, 0.5), "z": Vector2(-0.5, 0.6)}
const Storage = preload("res://core/storage.gd")

func normalize_proportions(values: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for key in DEFAULT_PROPORTIONS:
		var limits: Vector2 = PROPORTION_LIMITS[key]
		normalized[key] = clampf(float(values.get(key, DEFAULT_PROPORTIONS[key])), limits.x, limits.y)
	return normalized

func normalize_equipment_attachments(values: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for equipment_name in DEFAULT_EQUIPMENT_ATTACHMENTS:
		var fallback: Array = DEFAULT_EQUIPMENT_ATTACHMENTS[equipment_name]
		var source: Variant = values.get(equipment_name, fallback)
		var position: Array = source if source is Array and source.size() == 3 else fallback.duplicate()
		# Migrate the old demo shield offset, which made its projected edge look
		# like a detached square beside the arm. Preserve user-authored offsets.
		if equipment_name == "shield" and position.size() == 3:
			for legacy_position in LEGACY_DEFAULT_SHIELD_ATTACHMENTS:
				var matches_legacy_default := true
				for axis in 3: matches_legacy_default = matches_legacy_default and is_equal_approx(float(position[axis]), float(legacy_position[axis]))
				if matches_legacy_default:
					position = fallback.duplicate()
					break
		var cleaned: Array[float] = []
		for axis in 3:
			var value := float(position[axis]) if (position[axis] is int or position[axis] is float) else float(fallback[axis])
			if not is_finite(value): value = float(fallback[axis])
			var limits: Vector2 = ATTACHMENT_LIMITS[["x", "y", "z"][axis]]
			cleaned.append(clampf(value, limits.x, limits.y))
		normalized[equipment_name] = cleaned
	return normalized

func build_turntable_angles(sample_count: int, custom_text: String = "") -> Dictionary:
	var angles: Array[float] = []
	if sample_count in [8, 16, 32]:
		for index in sample_count: angles.append(360.0 * float(index) / float(sample_count))
		return {"ok": true, "angles": angles}
	if sample_count != -1: return {"ok": false, "message": "Escolha 8, 16, 32 ou uma lista de ângulos personalizada."}
	var values := custom_text.split(",", false)
	if values.is_empty() or values.size() > MAX_TURNTABLE_VIEWS: return {"ok": false, "message": "A lista personalizada precisa conter de 1 a 64 ângulos separados por vírgula."}
	for value in values:
		var text_value := str(value).strip_edges()
		if text_value.is_empty() or not text_value.is_valid_float(): return {"ok": false, "message": "Cada ângulo precisa ser um número entre 0° e 359,99°."}
		var angle := float(text_value)
		if not is_finite(angle) or angle < 0.0 or angle >= 360.0: return {"ok": false, "message": "Ângulos devem ficar entre 0° (incluído) e 360° (excluído)."}
		for prior in angles:
			if absf(float(prior) - angle) < 0.001: return {"ok": false, "message": "A lista não pode repetir ângulos."}
		angles.append(angle)
	return {"ok": true, "angles": angles}

func validate_turntable_budget(angle_count: int, frame_count: int, resolution: Vector2i) -> Dictionary:
	if angle_count < 1 or angle_count > MAX_TURNTABLE_VIEWS: return {"ok": false, "message": "A captura aceita de 1 a 64 ângulos."}
	if frame_count < 1 or frame_count > MAX_CAPTURE_FRAMES: return {"ok": false, "message": "A captura aceita de 1 a 8 quadros por operação."}
	if resolution.x < 8 or resolution.y < 8: return {"ok": false, "message": "Resolução de captura inválida."}
	var estimated_bytes := resolution.x * resolution.y * angle_count * frame_count * 4
	if estimated_bytes > MAX_TURNTABLE_RGBA_BYTES: return {"ok": false, "message": "A captura multivista ultrapassa 64 MiB de pixels RGBA. Reduza vistas, quadros ou resolução."}
	return {"ok": true, "estimated_bytes": estimated_bytes}

func capture_signature(doc: RefCounted, clip_index: int, configuration: Dictionary = {}) -> String:
	if doc == null or clip_index < 0 or clip_index >= doc.animation.clips.size(): return ""
	var clip: Dictionary = doc.animation.clips[clip_index]
	var frames: Array = clip.get("frames", [])
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	var rig: Dictionary = rig_value if rig_value is Dictionary else {}
	var base_value: Variant = rig.get("pose_base", {})
	var base_pose: Dictionary = base_value if base_value is Dictionary else {}
	var all_keys_value: Variant = rig.get("pose_keys", {})
	var all_keys: Dictionary = all_keys_value if all_keys_value is Dictionary else {}
	var clip_keys: Dictionary = {}
	var prefix := str(clip_index) + ":"
	for key in all_keys:
		if str(key).begins_with(prefix): clip_keys[str(key).substr(prefix.length())] = all_keys[key].duplicate(true)
	var pose_sequence := build_pose_sequence(base_pose, clip_keys, frames, bool(clip.get("loop", true)), clip.get("durations_ms", {}))
	var profile := {"schema": 1, "resolution": [doc.width, doc.height], "palette": doc.palette.duplicate(true), "clip": {"frames": frames.duplicate(true), "loop": bool(clip.get("loop", true)), "durations_ms": clip.get("durations_ms", {}).duplicate(true)}, "poses": pose_sequence, "proportions": configuration.get("proportions", rig.get("proportions", DEFAULT_PROPORTIONS)), "equipment_attachments": configuration.get("equipment_attachments", rig.get("equipment_attachments", DEFAULT_EQUIPMENT_ATTACHMENTS)), "capture_pass_assignments": configuration.get("capture_pass_assignments", rig.get("capture_pass_assignments", {})), "imported_model": configuration.get("imported_model", rig.get("model_asset", {}))}
	return JSON.stringify(profile).sha256_text()

func build_clip_batch_plan(doc: RefCounted, resolution: Vector2i, pass_counts: Dictionary, capture_signatures: Dictionary = {}) -> Dictionary:
	## Preflight the entire document before starting an all-clips capture.
	if doc == null or doc.animation.clips.is_empty(): return {"ok": false, "message": "O documento não contém clips para capturar."}
	if int(pass_counts.get("body", 0)) < 1: return {"ok": false, "message": "Atribua pelo menos uma malha ao passe Corpo antes de capturar."}
	var pass_renders := 0
	for pass_name in ["body", "shield", "sword"]:
		if int(pass_counts.get(pass_name, 0)) > 0: pass_renders += 1
	var render_count := 0
	var new_layers := 0
	var pixel_growth := 0
	var pending_clip_indices: Array[int] = []
	var completed_clip_indices: Array[int] = []
	for clip_index in doc.animation.clips.size():
		var clip: Dictionary = doc.animation.clips[clip_index]
		var frames: Array = clip.get("frames", [])
		if frames.is_empty() or frames.size() > MAX_CAPTURE_FRAMES:
			return {"ok": false, "message": "O clip '%s' tem %d quadros; a captura permite de 1 a %d por clip. Nenhum clip foi alterado." % [str(clip.get("name", clip_index)), frames.size(), MAX_CAPTURE_FRAMES]}
		for frame in frames:
			if int(frame) < 0 or int(frame) >= doc.frames: return {"ok": false, "message": "O clip '%s' aponta para um quadro inexistente. Nenhum clip foi alterado." % str(clip.get("name", clip_index))}
		var clip_complete := true
		var expected_signature := str(capture_signatures.get(str(clip_index), ""))
		for pass_name in ["body", "shield", "sword"]:
			var has_layer := false
			for record in doc.art.get("three_d_motion_captures", []):
				if not record is Dictionary: continue
				if str(record.get("capture_mode", "")) != "modular_pass" or str(record.get("pass_name", "")) != pass_name: continue
				if int(record.get("clip_index", -1)) != clip_index or record.get("frame_indices", []) != frames: continue
				if not expected_signature.is_empty() and str(record.get("capture_signature", "")) != expected_signature: continue
				for layer in doc.layers:
					if str(layer.get("id", "")) == str(record.get("layer_id", "")): has_layer = true; break
				if has_layer: break
			if not has_layer: clip_complete = false
		if clip_complete:
			completed_clip_indices.append(clip_index)
			continue
		pending_clip_indices.append(clip_index)
		var budget := validate_turntable_budget(8, frames.size(), resolution)
		if not budget.get("ok", false): return {"ok": false, "message": "Clip '%s': %s Nenhum clip foi alterado." % [str(clip.get("name", clip_index)), str(budget.get("message", "Orçamento inválido."))]}
		if int(budget.get("estimated_bytes", 0)) * 4 > MAX_TURNTABLE_RGBA_BYTES:
			return {"ok": false, "message": "Clip '%s': os passes modulares excederiam 64 MiB. Nenhum clip foi alterado." % str(clip.get("name", clip_index))}
		render_count += frames.size() * 8 * (pass_renders + 1) # composed reference plus non-empty modular passes
		for pass_name in ["body", "shield", "sword"]:
			var reusable := false
			for record in doc.art.get("three_d_motion_captures", []):
				if not record is Dictionary: continue
				if str(record.get("capture_mode", "")) != "modular_pass" or str(record.get("pass_name", "")) != pass_name: continue
				if int(record.get("clip_index", -1)) != clip_index or record.get("frame_indices", []) != frames or not bool(record.get("baseline_supported", false)): continue
				for layer in doc.layers:
					if str(layer.get("id", "")) == str(record.get("layer_id", "")): reusable = true; break
				if reusable: break
			if not reusable:
				new_layers += 1
				pixel_growth += doc.width * doc.height * 4 * doc.frames * 8
	if doc.layers.size() + new_layers > 16: return {"ok": false, "message": "O lote precisaria de %d layers e ultrapassaria o limite de 16. Remova ou consolide layers antes de capturar." % (doc.layers.size() + new_layers)}
	if doc.pixel_bytes() + pixel_growth > doc.pixel_budget_limit: return {"ok": false, "message": "As novas layers do lote ultrapassariam o limite de memória do projeto."}
	return {"ok": true, "clips": doc.animation.clips.size(), "pending_clip_indices": pending_clip_indices, "completed_clip_indices": completed_clip_indices, "pending_count": pending_clip_indices.size(), "render_count": render_count, "new_layers": new_layers, "estimated_pixel_growth": pixel_growth}

func map_turntable_to_directions(angles: Array, tolerance_degrees: float = 22.5) -> Dictionary:
	if angles.size() < 8 or angles.size() > MAX_TURNTABLE_VIEWS: return {"ok": false, "message": "É preciso ter de 8 a 64 vistas para preencher as oito direções."}
	if tolerance_degrees < 0.0 or tolerance_degrees > 22.5: return {"ok": false, "message": "A tolerância máxima por direção é 22,5° para evitar trocar a orientação da pose."}
	var normalized_angles: Array[float] = []
	for raw_angle in angles:
		var angle := float(raw_angle)
		if not is_finite(angle) or angle < 0.0 or angle >= 360.0: return {"ok": false, "message": "Os ângulos precisam ficar entre 0° e 359,99°."}
		for previous in normalized_angles:
			var angular_distance := absf(fposmod(angle - float(previous) + 180.0, 360.0) - 180.0)
			if angular_distance < 0.001: return {"ok": false, "message": "A lista de vistas contém ângulos repetidos."}
		normalized_angles.append(angle)
	var selected_indices: Array[int] = []
	var selected_angles: Array[float] = []
	var angular_errors: Array[float] = []
	var used_indices: Dictionary = {}
	for direction in DIRECTIONS.size():
		var target_angle := float(direction) * 45.0
		var best_index := -1
		var best_error := INF
		for candidate_index in normalized_angles.size():
			var error := absf(fposmod(normalized_angles[candidate_index] - target_angle + 180.0, 360.0) - 180.0)
			if error < best_error: best_error = error; best_index = candidate_index
		if best_index < 0 or best_error > tolerance_degrees + 0.001:
			return {"ok": false, "message": "Não há uma vista próxima o bastante de %s (alvo %.1f°, tolerância %.1f°)." % [DIRECTIONS[direction], target_angle, tolerance_degrees]}
		if used_indices.has(best_index): return {"ok": false, "message": "As vistas disponíveis não cobrem oito ângulos distintos; gere mais ângulos ou revise a lista personalizada."}
		used_indices[best_index] = true
		selected_indices.append(best_index)
		selected_angles.append(normalized_angles[best_index])
		angular_errors.append(best_error)
	return {"ok": true, "view_indices": selected_indices, "camera_yaw_degrees": selected_angles, "angular_errors_degrees": angular_errors}

func walk_pose(phase: float) -> Dictionary:
	var angle := phase * TAU
	var stride := sin(angle)
	var lift := maxf(0.0, cos(angle))
	return {
		"left_arm": -stride * 0.42,
		"right_arm": stride * 0.42,
		"left_elbow": 0.18 + lift * 0.28,
		"right_elbow": 0.18 + maxf(0.0, -cos(angle)) * 0.28,
		"left_leg": stride * 0.55,
		"right_leg": -stride * 0.55,
		"left_knee": lift * 0.45,
		"right_knee": maxf(0.0, -cos(angle)) * 0.45,
		"torso": stride * 0.035,
		"bounce": lift * 0.045,
	}

func build_pose_sequence(base_pose: Dictionary, saved_keys: Dictionary, frame_indices: Array, loop: bool, durations_ms: Dictionary = {}) -> Array:
	var result: Array = []
	if frame_indices.is_empty(): return result
	var key_positions: Array[int] = []
	for position in frame_indices.size():
		if saved_keys.get(str(frame_indices[position]), null) is Dictionary: key_positions.append(position)
	for position in frame_indices.size():
		var pose: Dictionary = {}
		for joint in JOINTS: pose[joint] = float(base_pose.get(joint, 0.0))
		if key_positions.is_empty():
			var gait := walk_pose(float(position) / float(frame_indices.size()))
			for joint in JOINTS: pose[joint] = float(pose[joint]) + float(gait[joint])
			pose["bounce"] = float(gait.bounce)
		else:
			var exact_position := key_positions.find(position)
			if exact_position >= 0:
				var exact: Dictionary = saved_keys[str(frame_indices[position])]
				for joint in JOINTS: pose[joint] = float(exact.get(joint, pose[joint]))
				pose["bounce"] = float(exact.get("bounce", 0.0))
			else:
				var previous_position := -1
				var next_position := -1
				for key_position in key_positions:
					if key_position < position: previous_position = key_position
					elif key_position > position and next_position < 0: next_position = key_position
				if previous_position < 0 and loop: previous_position = key_positions.back() - frame_indices.size()
				if next_position < 0 and loop: next_position = key_positions.front() + frame_indices.size()
				if previous_position < 0: previous_position = next_position
				if next_position < 0: next_position = previous_position
				var previous_frame: int = int(frame_indices[posmod(previous_position, frame_indices.size())])
				var next_frame: int = int(frame_indices[posmod(next_position, frame_indices.size())])
				var first_pose: Dictionary = saved_keys.get(str(previous_frame), {})
				var second_pose: Dictionary = saved_keys.get(str(next_frame), {})
				var denominator := _sequence_time(frame_indices, durations_ms, previous_position, next_position)
				var elapsed := _sequence_time(frame_indices, durations_ms, previous_position, position)
				var amount := 0.0 if denominator <= 0.0 else clampf(elapsed / denominator, 0.0, 1.0)
				for joint in JOINTS:
					var first := float(first_pose.get(joint, pose[joint]))
					var second := float(second_pose.get(joint, pose[joint]))
					pose[joint] = first + wrapf(second - first, -PI, PI) * amount
				pose["bounce"] = lerpf(float(first_pose.get("bounce", 0.0)), float(second_pose.get("bounce", 0.0)), amount)
		for joint in JOINTS: pose[joint] = clamp_joint_pose(joint, float(pose[joint]))
		pose["bounce"] = clampf(float(pose.get("bounce", 0.0)), -0.1, 0.1)
		result.append(pose)
	return result

func clamp_joint_pose(joint: String, radians: float) -> float:
	var limits: Dictionary = {
		"torso": Vector2(-25.0, 25.0),
		"left_arm": Vector2(-75.0, 75.0), "right_arm": Vector2(-75.0, 75.0),
		"left_elbow": Vector2(0.0, 125.0), "right_elbow": Vector2(0.0, 125.0),
		"left_leg": Vector2(-65.0, 65.0), "right_leg": Vector2(-65.0, 65.0),
		"left_knee": Vector2(0.0, 135.0), "right_knee": Vector2(0.0, 135.0),
	}
	var range_degrees: Vector2 = limits.get(joint, Vector2(-75.0, 75.0))
	return clampf(radians, deg_to_rad(range_degrees.x), deg_to_rad(range_degrees.y))

func _sequence_time(frame_indices: Array, durations_ms: Dictionary, start_position: int, end_position: int) -> float:
	var elapsed := 0.0
	for position in range(start_position, end_position):
		var frame_value: int = int(frame_indices[posmod(position, frame_indices.size())])
		elapsed += maxf(1.0, float(durations_ms.get(str(frame_value), 100.0)))
	return elapsed

func pixelize_capture(source: Image, target_size: Vector2i, palette: Array, alpha_threshold: float = 0.35) -> Image:
	if source == null or source.is_empty() or target_size.x < 1 or target_size.y < 1: return Image.new()
	var normalized := source.duplicate()
	if normalized.get_size() != target_size:
		normalized.resize(target_size.x, target_size.y, Image.INTERPOLATE_NEAREST)
	var colors: Array[Color] = []
	for entry in palette:
		var color: Color = entry if entry is Color else Color.from_string(str(entry), Color.TRANSPARENT)
		if color.a > 0.0: colors.append(Color(color.r, color.g, color.b, 1.0))
	if colors.is_empty(): return Image.new()
	var result := Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
	for y in target_size.y:
		for x in target_size.x:
			var input: Color = normalized.get_pixel(x, y)
			if input.a < alpha_threshold: continue
			var chosen := colors[0]
			var best_distance := INF
			for swatch in colors:
				var dr: float = input.r - swatch.r
				var dg: float = input.g - swatch.g
				var db: float = input.b - swatch.b
				var distance: float = dr * dr + dg * dg + db * db
				if distance < best_distance:
					best_distance = distance
					chosen = swatch
			result.set_pixel(x, y, chosen)
	return result

func apply_capture(doc: RefCounted, clip_index: int, captured: Array, metadata: Dictionary = {}) -> Dictionary:
	if doc == null or clip_index < 0 or clip_index >= doc.animation.clips.size(): return _failure("Projeto ou clip inválido.")
	if doc.art.get("locked", false): return _failure("Art Lock impede criar uma camada a partir da captura 3D.")
	var clip: Dictionary = doc.animation.clips[clip_index]
	var frames: Array = clip.get("frames", [])
	if frames.is_empty() or frames.size() > MAX_CAPTURE_FRAMES: return _failure("A prova de conceito captura clips com 1–8 frames; divida ou escolha um clip menor.")
	for frame in frames:
		if int(frame) < 0 or int(frame) >= doc.frames: return _failure("O clip ativo contém um frame fora dos limites do documento.")
	if captured.size() != 8: return _failure("A captura precisa conter exatamente as oito direções do documento.")
	for direction in 8:
		if not captured[direction] is Array or captured[direction].size() != frames.size(): return _failure("A captura 3D não cobre todos os frames e direções do clip.")
		for image in captured[direction]:
			if not image is Image or image.is_empty() or image.get_size() != Vector2i(doc.width, doc.height): return _failure("Uma captura não é uma cel transparente válida no tamanho do projeto.")
	var attachment_anchor_positions: Variant = metadata.get("attachment_anchor_positions", [])
	if not attachment_anchor_positions is Array: return _failure("A provenance de encaixes deve ser uma sequência de posições por direção.")
	if not attachment_anchor_positions.is_empty():
		if attachment_anchor_positions.size() != 8: return _failure("A provenance de encaixes deve conter as oito direções.")
		for direction in 8:
			if not attachment_anchor_positions[direction] is Array or attachment_anchor_positions[direction].size() != frames.size(): return _failure("A provenance de encaixes não corresponde aos quadros do clip.")
			for frame_slot in frames.size():
				var projected: Variant = attachment_anchor_positions[direction][frame_slot]
				if not projected is Dictionary: return _failure("Uma posição projetada de encaixe está inválida.")
				for equipment_name in EQUIPMENT_ANCHORS:
					if not projected.has(equipment_name): continue
					var point: Variant = projected[equipment_name]
					if not point is Array or point.size() != 2: return _failure("Uma âncora de equipamento precisa conter X e Y.")
					for coordinate in point:
						if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return _failure("Uma coordenada projetada de encaixe não é finita.")
					if int(point[0]) < 0 or int(point[0]) >= doc.width or int(point[1]) < 0 or int(point[1]) >= doc.height: return _failure("Uma âncora projetada está fora dos limites do cel.")
	var target_record_index := _find_replaceable_capture(doc, clip_index, frames)
	var encoded_baseline: Array = _encode_baseline(captured)
	var baseline_supported := not encoded_baseline.is_empty()
	var baseline_bytes := _baseline_payload_bytes(encoded_baseline)
	if baseline_supported and _existing_baseline_bytes(doc, target_record_index) + baseline_bytes > MAX_BASELINE_BYTES:
		encoded_baseline = []
		baseline_bytes = 0
		baseline_supported = false
	var target_layer_index := -1
	if target_record_index >= 0:
		var old_record: Dictionary = doc.art.three_d_motion_captures[target_record_index]
		for layer_index in doc.layers.size():
			if str(doc.layers[layer_index].id) == str(old_record.get("layer_id", "")): target_layer_index = layer_index; break
		if target_layer_index < 0: target_record_index = -1
	if target_record_index < 0:
		if doc.layers.size() >= 16: return _failure("O projeto atingiu o limite de 16 camadas e não há captura anterior compatível para atualizar.")
		if doc.pixel_bytes() + doc.width * doc.height * 4 * doc.frames * 8 > doc.pixel_budget_limit: return _failure("A nova camada ultrapassaria o limite de memória do projeto.")
	var merged: Array = captured.duplicate(true)
	var preserved_corrections := 0
	if target_record_index >= 0:
		var prior_record: Dictionary = doc.art.three_d_motion_captures[target_record_index]
		var prior_baseline: Array = prior_record.get("baseline_cels", [])
		var prior_layer: Dictionary = doc.layers[target_layer_index]
		for direction in 8:
			for index in frames.size():
				var source_png := str(prior_baseline[direction][index]) if direction < prior_baseline.size() and prior_baseline[direction] is Array and index < prior_baseline[direction].size() else ""
				if source_png.is_empty(): continue
				var previous_base := Image.new()
				if previous_base.load_png_from_buffer(Marshalls.base64_to_raw(source_png)) != OK or previous_base.get_size() != Vector2i(doc.width, doc.height): continue
				var previous_result: Image = prior_layer.cels[direction][int(frames[index])]
				var next_result: Image = merged[direction][index]
				for y in doc.height:
					for x in doc.width:
						var original_pixel: Color = previous_base.get_pixel(x, y)
						var edited_pixel: Color = previous_result.get_pixel(x, y)
						if edited_pixel != original_pixel:
							next_result.set_pixel(x, y, edited_pixel)
							preserved_corrections += 1
	var name := "3D · " + str(clip.get("name", "animação")).left(24)
	doc.checkpoint("Atualizar captura do 3D Motion Studio" if target_record_index >= 0 else "Importar captura do 3D Motion Studio")
	var layer: Dictionary
	if target_record_index >= 0:
		layer = doc.layers[target_layer_index]
	else:
		if not doc.add_layer(name):
			doc.undo()
			return _failure("Não foi possível criar a camada de captura.")
		layer = doc.layers[doc.active_layer]
		layer.retarget_key = "3d-motion-" + str(layer.id)
	for direction in 8:
		for index in frames.size():
			var frame_index := int(frames[index])
			layer.cels[direction][frame_index] = merged[direction][index].duplicate()
			if not attachment_anchor_positions.is_empty():
				var cell_key: String = doc.cel_key(direction, frame_index)
				if not doc.rig.has("anchors"): doc.rig.anchors = {}
				var cell_anchors: Dictionary = doc.rig.anchors.get(cell_key, {}).duplicate(true)
				var projected: Dictionary = attachment_anchor_positions[direction][index]
				for equipment_name in EQUIPMENT_ANCHORS:
					if projected.has(equipment_name): cell_anchors[EQUIPMENT_ANCHORS[equipment_name]] = [int(projected[equipment_name][0]), int(projected[equipment_name][1])]
				doc.rig.anchors[cell_key] = cell_anchors
	var capture_record := {
		"version": 1,
		"source": "procedural_humanoid_poc",
		"layer_id": str(layer.id),
		"clip": str(clip.get("name", "")),
		"frame_indices": frames.duplicate(),
		"direction_order": DIRECTIONS.duplicate(),
		"camera_yaw_degrees": [0, 45, 90, 135, 180, 225, 270, 315],
		"projection": "orthographic",
		"resolution": [doc.width, doc.height],
		"palette_quantized": true,
		"review_required": true,
		"clip_index": clip_index,
		"baseline_supported": baseline_supported,
		"baseline_cels": encoded_baseline,
		"baseline_bytes": baseline_bytes,
		"preserved_correction_pixels": preserved_corrections,
		"capture_count": 1,
	}
	if target_record_index >= 0: capture_record.capture_count = int(doc.art.three_d_motion_captures[target_record_index].get("capture_count", 1)) + 1
	for key in metadata: capture_record[key] = metadata[key].duplicate(true) if metadata[key] is Array or metadata[key] is Dictionary else metadata[key]
	if not doc.art.has("three_d_motion_captures"): doc.art.three_d_motion_captures = []
	if target_record_index >= 0: doc.art.three_d_motion_captures[target_record_index] = capture_record
	else: doc.art.three_d_motion_captures.append(capture_record)
	doc.art.pose_approvals = []
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Capturas locais do Sprite Forge 3D Motion Studio; revisão artística humana pendente."
	var serialized_size := JSON.stringify(Storage.new().encode(doc)).to_utf8_buffer().size()
	if serialized_size > MAX_PROJECT_JSON_BYTES:
		doc.undo()
		return _failure("A captura excederia o limite de 64 MiB do projeto salvo; reduza resolução ou remova recursos antes de capturar.")
	doc.mark_changed()
	var action_text := "atualizada; correções locais preservadas em %d pixels" % preserved_corrections if target_record_index >= 0 else "importada em nova camada"
	if not baseline_supported: action_text += "; base de atualização futura excedeu o limite e esta captura permanecerá versionada em nova camada"
	return {"ok": true, "layer_id": str(layer.id), "layer_name": str(layer.name), "captured_frames": frames.size(), "directions": 8, "updated_existing_layer": target_record_index >= 0, "preserved_correction_pixels": preserved_corrections, "baseline_supported": baseline_supported, "message": "%s: %d frames × 8 direções %s. Revisão pixel a pixel ainda é necessária." % [str(layer.name), frames.size(), action_text]}

func _find_replaceable_capture(doc: RefCounted, clip_index: int, frames: Array) -> int:
	var records: Array = doc.art.get("three_d_motion_captures", [])
	for index in range(records.size() - 1, -1, -1):
		if not records[index] is Dictionary: continue
		var record: Dictionary = records[index]
		if str(record.get("capture_mode", "")) == "modular_pass": continue
		if int(record.get("clip_index", -1)) != clip_index or record.get("frame_indices", []) != frames: continue
		if not bool(record.get("baseline_supported", false)): continue
		var baseline: Array = record.get("baseline_cels", [])
		if baseline.size() != 8: continue
		return index
	return -1

func apply_modular_capture(doc: RefCounted, clip_index: int, pass_captures: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	## Imports a deterministic body/shield/sword capture as separate editable layers in one undo transaction.
	if doc == null or clip_index < 0 or clip_index >= doc.animation.clips.size(): return _failure("Projeto ou clip inválido.")
	if doc.art.get("locked", false): return _failure("Art Lock impede criar camadas a partir da captura modular 3D.")
	var clip: Dictionary = doc.animation.clips[clip_index]
	var frames: Array = clip.get("frames", [])
	if frames.is_empty() or frames.size() > MAX_CAPTURE_FRAMES: return _failure("A captura modular aceita clips com 1–8 frames.")
	for frame in frames:
		if int(frame) < 0 or int(frame) >= doc.frames: return _failure("O clip ativo contém um frame fora dos limites do documento.")
	var pass_names: Array[String] = ["body", "shield", "sword"]
	var existing_records: Array = doc.art.get("three_d_motion_captures", [])
	var target_records: Dictionary = {}
	var target_layers: Dictionary = {}
	var new_layer_count := 0
	var payloads: Dictionary = {}
	for pass_name in pass_names:
		var directions: Variant = pass_captures.get(pass_name, null)
		if not directions is Array or directions.size() != 8: return _failure("O passe '%s' não contém as oito direções." % pass_name)
		for direction in 8:
			if not directions[direction] is Array or directions[direction].size() != frames.size(): return _failure("O passe '%s' não cobre todos os frames do clip." % pass_name)
			for cel in directions[direction]:
				if not cel is Image or cel.is_empty() or cel.get_size() != Vector2i(doc.width, doc.height): return _failure("O passe '%s' contém uma imagem inválida." % pass_name)
		payloads[pass_name] = directions.duplicate(true)
		var record_index := _find_replaceable_modular_capture(doc, clip_index, frames, pass_name)
		var layer_index := -1
		if record_index >= 0:
			var record: Dictionary = existing_records[record_index]
			for candidate in doc.layers.size():
				if str(doc.layers[candidate].id) == str(record.get("layer_id", "")): layer_index = candidate; break
		if record_index >= 0 and layer_index >= 0:
			target_records[pass_name] = record_index
			target_layers[pass_name] = layer_index
		else:
			new_layer_count += 1
	if doc.layers.size() + new_layer_count > 16: return _failure("Não há espaço para as três layers modulares; remova ou consolide layers antes da captura.")
	if doc.pixel_bytes() + doc.width * doc.height * 4 * doc.frames * 8 * new_layer_count > doc.pixel_budget_limit: return _failure("As layers modulares ultrapassariam o limite de memória do projeto.")
	var merged_passes: Dictionary = {}
	var preserved_corrections := 0
	var preserved_by_pass: Dictionary = {}
	var encoded_passes: Dictionary = {}
	var pending_baseline_bytes := 0
	var replaceable_baseline_bytes := 0
	for pass_name in pass_names:
		if target_records.has(pass_name):
			var prior_record: Dictionary = existing_records[int(target_records[pass_name])]
			replaceable_baseline_bytes += int(prior_record.get("baseline_bytes", _baseline_payload_bytes(prior_record.get("baseline_cels", []))))
		var encoded := _encode_baseline(payloads[pass_name])
		encoded_passes[pass_name] = encoded
		pending_baseline_bytes += _baseline_payload_bytes(encoded)
	var remaining_baseline_capacity := maxi(0, MAX_BASELINE_BYTES - _existing_baseline_bytes(doc, -1) + replaceable_baseline_bytes)
	if pending_baseline_bytes > remaining_baseline_capacity:
		encoded_passes.clear()
		for pass_name in pass_names: encoded_passes[pass_name] = []
	for pass_name in pass_names:
		var next_images: Array = payloads[pass_name].duplicate(true)
		var pass_preserved_corrections := 0
		if target_records.has(pass_name):
			var prior_record: Dictionary = existing_records[int(target_records[pass_name])]
			var prior_layer: Dictionary = doc.layers[int(target_layers[pass_name])]
			var prior_baselines: Array = prior_record.get("baseline_cels", [])
			for direction in 8:
				for slot in frames.size():
					var source_png := str(prior_baselines[direction][slot]) if direction < prior_baselines.size() and prior_baselines[direction] is Array and slot < prior_baselines[direction].size() else ""
					if source_png.is_empty(): continue
					var prior_base := Image.new()
					if prior_base.load_png_from_buffer(Marshalls.base64_to_raw(source_png)) != OK or prior_base.get_size() != Vector2i(doc.width, doc.height): continue
					var previous_result: Image = prior_layer.cels[direction][int(frames[slot])]
					var next_result: Image = next_images[direction][slot]
					for y in doc.height:
						for x in doc.width:
							if previous_result.get_pixel(x, y) != prior_base.get_pixel(x, y):
								next_result.set_pixel(x, y, previous_result.get_pixel(x, y))
								preserved_corrections += 1
								pass_preserved_corrections += 1
		preserved_by_pass[pass_name] = pass_preserved_corrections
		merged_passes[pass_name] = next_images
	var attachment_anchor_positions: Variant = metadata.get("attachment_anchor_positions", [])
	if not attachment_anchor_positions is Array: return _failure("As âncoras modulares precisam ser uma sequência por direção.")
	var requires_shield_anchor := _modular_pass_has_pixels(payloads["shield"])
	var requires_sword_anchor := _modular_pass_has_pixels(payloads["sword"])
	if attachment_anchor_positions.is_empty() and (requires_shield_anchor or requires_sword_anchor): return _failure("Captura modular exige âncoras projetadas para cada passe de equipamento visível.")
	if not attachment_anchor_positions.is_empty():
		if attachment_anchor_positions.size() != 8: return _failure("As âncoras modulares precisam conter oito direções.")
		for direction in 8:
			if not attachment_anchor_positions[direction] is Array or attachment_anchor_positions[direction].size() != frames.size(): return _failure("As âncoras modulares não correspondem aos frames.")
			for anchors in attachment_anchor_positions[direction]:
				if not anchors is Dictionary: return _failure("Uma posição de encaixe está inválida.")
				if requires_shield_anchor and not anchors.has("shield"): return _failure("Cada quadro com passe Escudo visível precisa projetar sua âncora.")
				if requires_sword_anchor and not anchors.has("sword"): return _failure("Cada quadro com passe Arma visível precisa projetar sua âncora.")
				for equipment_name in EQUIPMENT_ANCHORS:
					if not anchors.has(equipment_name): continue
					var point: Variant = anchors[equipment_name]
					if not point is Array or point.size() != 2: return _failure("Uma âncora modular precisa conter X e Y.")
					if not (point[0] is int or point[0] is float) or not (point[1] is int or point[1] is float): return _failure("Uma âncora modular contém coordenadas inválidas.")
					if not is_finite(float(point[0])) or not is_finite(float(point[1])) or int(point[0]) < 0 or int(point[0]) >= doc.width or int(point[1]) < 0 or int(point[1]) >= doc.height: return _failure("Uma âncora modular está fora do cel.")
	var baseline_bytes_by_pass: Dictionary = {}
	for pass_name in pass_names: baseline_bytes_by_pass[pass_name] = _baseline_payload_bytes(encoded_passes[pass_name])
	doc.checkpoint("Importar captura modular 3D")
	var capture_records: Array = doc.art.get("three_d_motion_captures", []).duplicate(true)
	var cell_offsets: Dictionary = doc.rig.get("offsets", {}).duplicate(true)
	for pass_name in pass_names:
		var layer: Dictionary
		if target_layers.has(pass_name): layer = doc.layers[int(target_layers[pass_name])]
		else:
			if not doc.add_layer("3D · " + {"body": "Corpo", "shield": "Escudo", "sword": "Arma"}[pass_name], pass_name != "body"):
				doc.undo()
				return _failure("Não foi possível criar todas as layers da captura modular.")
			layer = doc.layers[doc.active_layer]
			layer.retarget_key = "3d-motion-" + pass_name + "-" + str(layer.id)
			layer.capture_pass = pass_name
			if pass_name == "shield": layer.anchor = "shield_mount"
			elif pass_name == "sword": layer.anchor = "weapon_mount"
			layer.equipment = pass_name != "body" and not attachment_anchor_positions.is_empty()
		for direction in 8:
			for slot in frames.size():
				var frame_index := int(frames[slot])
				layer.cels[direction][frame_index] = merged_passes[pass_name][direction][slot].duplicate()
				if layer.equipment:
					var equipment_name := "shield" if pass_name == "shield" else "sword"
					var projected_anchor: Array = attachment_anchor_positions[direction][slot].get(equipment_name, [0, 0])
					var correction := Vector2i.ZERO
					if target_records.has(pass_name):
						var old_record: Dictionary = existing_records[int(target_records[pass_name])]
						var old_anchor_rows: Array = old_record.get("attachment_anchor_positions", [])
						if direction < old_anchor_rows.size() and old_anchor_rows[direction] is Array and slot < old_anchor_rows[direction].size() and old_anchor_rows[direction][slot] is Dictionary:
							var old_point: Variant = old_anchor_rows[direction][slot].get(equipment_name, projected_anchor)
							if old_point is Array and old_point.size() == 2:
								var old_anchor_offset := Vector2i(-int(old_point[0]), -int(old_point[1]))
								var previous_by_cell: Dictionary = cell_offsets.get(doc.cel_key(direction, frame_index), {})
								var current_offset: Array = previous_by_cell.get(str(layer.id), layer.offset)
								correction = Vector2i(int(current_offset[0]), int(current_offset[1])) - old_anchor_offset
					var cell_key: String = doc.cel_key(direction, frame_index)
					var per_layer: Dictionary = cell_offsets.get(cell_key, {}).duplicate(true)
					per_layer[str(layer.id)] = [-int(projected_anchor[0]) + correction.x, -int(projected_anchor[1]) + correction.y]
					cell_offsets[cell_key] = per_layer
		var record := {
			"version": 1, "source": "procedural_humanoid_poc", "capture_mode": "modular_pass", "pass_name": pass_name,
			"layer_id": str(layer.id), "clip": str(clip.get("name", "")), "clip_index": clip_index,
			"frame_indices": frames.duplicate(), "direction_order": DIRECTIONS.duplicate(), "camera_yaw_degrees": [0, 45, 90, 135, 180, 225, 270, 315],
			"projection": "orthographic", "resolution": [doc.width, doc.height], "palette_quantized": true, "review_required": true,
			"baseline_supported": not encoded_passes[pass_name].is_empty(), "baseline_cels": encoded_passes[pass_name],
			"baseline_bytes": int(baseline_bytes_by_pass[pass_name]), "preserved_correction_pixels": int(preserved_by_pass.get(pass_name, 0)),
			"capture_count": 1 if not target_records.has(pass_name) else int(existing_records[int(target_records[pass_name])].get("capture_count", 1)) + 1,
		}
		for key in metadata: record[key] = metadata[key].duplicate(true) if metadata[key] is Array or metadata[key] is Dictionary else metadata[key]
		record["pass_name"] = pass_name
		record["capture_mode"] = "modular_pass"
		if target_records.has(pass_name): capture_records[int(target_records[pass_name])] = record
		else: capture_records.append(record)
	if not attachment_anchor_positions.is_empty():
		for direction in 8:
			for slot in frames.size():
				var cell_key: String = doc.cel_key(direction, int(frames[slot]))
				if not doc.rig.has("anchors"): doc.rig.anchors = {}
				var cell_anchors: Dictionary = doc.rig.anchors.get(cell_key, {}).duplicate(true)
				var projected: Dictionary = attachment_anchor_positions[direction][slot]
				for equipment_name in EQUIPMENT_ANCHORS:
					if projected.has(equipment_name): cell_anchors[EQUIPMENT_ANCHORS[equipment_name]] = [roundi(float(projected[equipment_name][0])), roundi(float(projected[equipment_name][1]))]
				doc.rig.anchors[cell_key] = cell_anchors
	if not cell_offsets.is_empty(): doc.rig.offsets = cell_offsets
	doc.art.three_d_motion_captures = capture_records
	doc.art.pose_approvals = []
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Captura modular local 3D Motion (corpo/escudo/arma); revisão artística humana pendente."
	if JSON.stringify(Storage.new().encode(doc)).to_utf8_buffer().size() > MAX_PROJECT_JSON_BYTES:
		doc.undo()
		return _failure("A captura modular excederia 64 MiB no projeto salvo; reduza a resolução ou remova recursos.")
	doc.mark_changed()
	return {"ok": true, "layers": 3, "updated": not target_layers.is_empty(), "preserved_correction_pixels": preserved_corrections, "baseline_supported": pass_names.all(func(name: String) -> bool: return not encoded_passes[name].is_empty()), "message": "Captura modular importada em Corpo, Escudo e Arma, com Undo único. Reveja cada layer; transparência e sobreposições dependem de ajuste manual."}

func _modular_pass_has_pixels(directions: Array) -> bool:
	for direction in directions:
		if not direction is Array: continue
		for cel in direction:
			if cel is Image and not cel.is_empty() and cel.get_used_rect().size != Vector2i.ZERO: return true
	return false

func _find_replaceable_modular_capture(doc: RefCounted, clip_index: int, frames: Array, pass_name: String) -> int:
	var records: Array = doc.art.get("three_d_motion_captures", [])
	for index in range(records.size() - 1, -1, -1):
		if not records[index] is Dictionary: continue
		var record: Dictionary = records[index]
		if str(record.get("capture_mode", "")) != "modular_pass" or str(record.get("pass_name", "")) != pass_name: continue
		if int(record.get("clip_index", -1)) != clip_index or record.get("frame_indices", []) != frames: continue
		if not bool(record.get("baseline_supported", false)) or record.get("baseline_cels", []).size() != 8: continue
		return index
	return -1

func _encode_baseline(captured: Array) -> Array:
	var encoded: Array = []
	var total_bytes := 0
	for direction in 8:
		var row: Array = []
		for image in captured[direction]:
			var png: PackedByteArray = image.save_png_to_buffer()
			total_bytes += Marshalls.raw_to_base64(png).to_utf8_buffer().size()
			if total_bytes > MAX_BASELINE_BYTES: return []
			row.append(Marshalls.raw_to_base64(png))
		encoded.append(row)
	return encoded

func _baseline_payload_bytes(encoded: Array) -> int:
	return JSON.stringify(encoded).to_utf8_buffer().size() if not encoded.is_empty() else 0

func _existing_baseline_bytes(doc: RefCounted, excluded_record: int) -> int:
	var total := 0
	var records: Array = doc.art.get("three_d_motion_captures", [])
	for index in records.size():
		if index == excluded_record: continue
		if not records[index] is Dictionary: continue
		total += int(records[index].get("baseline_bytes", _baseline_payload_bytes(records[index].get("baseline_cels", []))))
	return total

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
