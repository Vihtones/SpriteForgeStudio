extends RefCounted
## Local, auditable preference learning. This learns from explicit user decisions;
## it does not fine-tune an image model or claim to understand anatomy.
const MAX_EXAMPLES := 2000
const MIN_APPROVED := 40
const MIN_REJECTED := 20
const AUTO_CONFIDENCE := 0.97
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
var store_path := "user://hyperlearn/feedback.json"
var model_path := "user://hyperlearn/preference-model.json"
var preview_root := "user://hyperlearn/previews"
var examples: Array[Dictionary] = []
var model: Dictionary = {}
var error := ""

func _init() -> void:
	load_store()

func load_store() -> bool:
	error = ""
	var data: Variant = _read_json(store_path)
	examples.clear()
	if data is Dictionary and data.get("schema") == 1 and data.get("examples") is Array:
		for item in data.examples:
			if _valid_example(item): examples.append(item)
	if examples.size() > MAX_EXAMPLES: examples = examples.slice(examples.size() - MAX_EXAMPLES)
	var trained: Variant = _read_json(model_path)
	model = trained if trained is Dictionary and trained.get("schema") == 1 else {}
	return true

func record_review(doc: RefCounted, approved: bool, reviewer: String, note: String, confirmed: bool, direction_indices: Array = []) -> Dictionary:
	error = ""
	if not confirmed or reviewer.strip_edges().is_empty(): return _fail("Confirme a decisão e identifique quem revisou.")
	if note.strip_edges().length() > 1000: return _fail("A observação deve ter até 1.000 caracteres.")
	var issues: Array = doc.validate()
	if not issues.is_empty(): return _fail("O documento precisa passar pela integridade técnica antes de entrar no conjunto: " + str(issues[0]))
	var selected_directions: Array[int] = []
	if direction_indices.is_empty():
		selected_directions.assign(range(8))
	else:
		for value in direction_indices:
			var direction := int(value)
			if direction < 0 or direction >= 8 or selected_directions.has(direction): return _fail("O escopo de direções contém índice inválido ou duplicado.")
			selected_directions.append(direction)
	if selected_directions.is_empty(): return _fail("Selecione pelo menos uma direção para a avaliação.")
	var image_hash := _document_hash(doc, selected_directions)
	for existing in examples:
		if str(existing.get("asset_sha256", "")) == image_hash and int(existing.get("label", -1)) == (1 if approved else 0):
			return {"ok": true, "duplicate": true, "item": existing, "counts": counts()}
	var preview_path := _save_contact_sheet(doc, image_hash, selected_directions)
	if preview_path.is_empty(): return _fail("Não foi possível preservar a prévia do pack avaliado.")
	var direction_names: Array[String] = []
	for direction in selected_directions: direction_names.append(str(DIRECTIONS[direction]))
	var scope := "current_document_all_directions_and_frames" if selected_directions.size() == 8 else "selected_directions_and_all_frames"
	var item := {"id": Crypto.new().generate_random_bytes(12).hex_encode(), "schema": 1, "at": Time.get_datetime_string_from_system(true), "project_id": str(doc.manifest.id), "project_name": str(doc.manifest.name), "revision": int(doc.revision), "art_bible_version": int(doc.manifest.art_bible_version), "asset_sha256": image_hash, "preview_path": preview_path, "label": 1 if approved else 0, "reviewer": reviewer.strip_edges().left(120), "note": note.strip_edges(), "features": describe(doc, selected_directions), "scope": scope, "direction_names": direction_names, "direction_indices": selected_directions.duplicate()}
	var next_examples := examples.duplicate(true)
	var evicted_examples: Array[Dictionary] = []
	next_examples.append(item)
	while next_examples.size() > MAX_EXAMPLES:
		evicted_examples.append(next_examples.pop_front())
	if not _write_json(store_path, {"schema": 1, "examples": next_examples}):
		_remove_preview_if_unreferenced(preview_path, examples)
		return _fail("Não foi possível gravar o registro auditável no disco.")
	examples.assign(next_examples)
	for evicted in evicted_examples: _remove_preview_if_unreferenced(str(evicted.get("preview_path", "")), examples)
	return {"ok": true, "item": item, "counts": counts()}

func describe(doc: RefCounted, direction_indices: Array = []) -> Array[float]:
	# Deterministic visual signals only; they cannot identify anatomical mistakes.
	var selected_directions: Array = direction_indices if not direction_indices.is_empty() else range(8)
	var coverage := 0.0
	var color_count := 0.0
	var centered := 0.0
	var frame_motion := 0.0
	var motion_pair_count := 0.0
	var total := 0.0
	var signatures: Array[Dictionary] = []
	for d in selected_directions:
		var previous: Image
		for f in doc.frames:
			var image: Image = doc.composite(d, f)
			var used: Rect2i = image.get_used_rect()
			var colored: Dictionary = {}
			var count := 0
			for y in doc.height:
				for x in doc.width:
					var c := image.get_pixel(x, y)
					if c.a <= 0.0: continue
					count += 1
					colored[c.to_html(false)] = true
			coverage += float(count) / maxi(1, doc.width * doc.height)
			if used.size != Vector2i.ZERO:
				centered += 1.0 - clampf(absf(0.5 - used.get_center().x / doc.width) + absf(0.5 - used.get_center().y / doc.height), 0.0, 1.0)
			color_count += float(colored.size())
			if previous != null:
				var changed := 0
				for y in doc.height:
					for x in doc.width:
						if image.get_pixel(x, y) != previous.get_pixel(x, y): changed += 1
				frame_motion += float(changed) / maxi(1, doc.width * doc.height)
				motion_pair_count += 1.0
			previous = image
			total += 1.0
		# Content signature per direction permits simple consistency diagnostics.
		var direction_image: Image = doc.composite(int(d), mini(doc.frame, doc.frames - 1))
		var bounds := direction_image.get_used_rect()
		signatures.append({"coverage": float(bounds.get_area()) / maxi(1, doc.width * doc.height)})
	var mean_coverage := coverage / maxf(1.0, total)
	var mean_colors := color_count / maxf(1.0, total)
	var mean_center := centered / maxf(1.0, total)
	var mean_motion := frame_motion / maxf(1.0, motion_pair_count)
	var direction_coverage: Array[float] = []
	for signature in signatures: direction_coverage.append(float(signature.coverage))
	var consistency := 1.0 if direction_coverage.size() == 1 else 0.0
	if not direction_coverage.is_empty():
		var average := 0.0
		for value in direction_coverage: average += value
		average /= direction_coverage.size()
		var deviation := 0.0
		for value in direction_coverage: deviation += absf(value - average)
		consistency = 1.0 - clampf(deviation / maxf(0.01, average * direction_coverage.size()), 0.0, 1.0)
	return [clampf(mean_coverage, 0, 1), clampf(mean_colors / 32.0, 0, 1), mean_center, consistency, clampf(mean_motion, 0, 1)]

func counts() -> Dictionary:
	var approved := 0
	var rejected := 0
	for item in examples:
		if int(item.label) == 1: approved += 1
		else: rejected += 1
	return {"approved": approved, "rejected": rejected, "total": examples.size()}

func train() -> Dictionary:
	var sample_counts := counts()
	var data: Array = []
	var excluded_scoped_examples := 0
	for item in examples:
		var scope := str(item.get("scope", "current_document_all_directions_and_frames"))
		if scope == "current_document_all_directions_and_frames" or item.get("direction_indices", []).size() == 8:
			data.append(item)
		else:
			excluded_scoped_examples += 1
	var model_counts := {"approved": 0, "rejected": 0, "total": data.size()}
	for item in data:
		if int(item.label) == 1: model_counts.approved += 1
		else: model_counts.rejected += 1
	if model_counts.approved < 2 or model_counts.rejected < 2:
		return {"ok": false, "reason": "O modelo geral precisa de ao menos duas aprovações e duas reprovações do conjunto completo. Avaliações parciais ficam preservadas, mas não treinam um classificador de packs completos.", "counts": sample_counts, "training_counts": model_counts, "excluded_scoped_examples": excluded_scoped_examples}
	data.sort_custom(func(a, b):
		var key_a := str(a.get("project_id", "")) + ":" + str(a.get("asset_sha256", ""))
		var key_b := str(b.get("project_id", "")) + ":" + str(b.get("asset_sha256", ""))
		return key_a < key_b
	)
	var weights := _fit(data, 240)
	var correct := 0
	for item in data:
		var probability := _predict(item.features, weights)
		if (probability >= 0.5) == (int(item.label) == 1): correct += 1
	var training_accuracy := float(correct) / data.size()
	var project_folds: Dictionary = {}
	var unique_projects: Dictionary = {}
	for item in data:
		unique_projects[str(item.project_id)] = true
		var fold: int = absi(hash(str(item.project_id))) % 5
		if not project_folds.has(fold): project_folds[fold] = []
		project_folds[fold].append(item)
	var validation_correct := 0
	var validation_total := 0
	var validation_true_approved := 0
	var validation_false_approved := 0
	var validation_true_rejected := 0
	var validation_false_rejected := 0
	var validation_squared_error := 0.0
	var validation_folds := 0
	var validation_project_ids: Dictionary = {}
	for fold in 5:
		if not project_folds.has(fold) or project_folds[fold].size() == data.size(): continue
		var train_data: Array = data.filter(func(item): return absi(hash(str(item.project_id))) % 5 != fold)
		var test_data: Array = project_folds[fold]
		var fold_approved := 0
		var fold_rejected := 0
		for item in train_data:
			if int(item.label) == 1: fold_approved += 1
			else: fold_rejected += 1
		if fold_approved == 0 or fold_rejected == 0: continue
		var fold_weights := _fit(train_data, 120)
		validation_folds += 1
		for item in test_data:
			var probability := _predict(item.features, fold_weights)
			var actual_approved := int(item.label) == 1
			var predicted_approved := probability >= 0.5
			validation_squared_error += pow(probability - float(int(item.label)), 2)
			if predicted_approved == actual_approved: validation_correct += 1
			if actual_approved and predicted_approved: validation_true_approved += 1
			elif actual_approved: validation_false_rejected += 1
			elif predicted_approved: validation_false_approved += 1
			else: validation_true_rejected += 1
			validation_project_ids[str(item.project_id)] = true
			validation_total += 1
	var validation_accuracy := float(validation_correct) / maxf(1, validation_total)
	var approved_recall := float(validation_true_approved) / maxf(1, validation_true_approved + validation_false_rejected)
	var rejected_recall := float(validation_true_rejected) / maxf(1, validation_true_rejected + validation_false_approved)
	var balanced_accuracy := (approved_recall + rejected_recall) / 2.0
	var brier_score := validation_squared_error / maxf(1, validation_total)
	model = {"schema": 1, "trained_at": Time.get_datetime_string_from_system(true), "weights": Array(weights), "training_examples": data.size(), "approved": model_counts.approved, "rejected": model_counts.rejected, "training_accuracy": training_accuracy, "validation_accuracy": validation_accuracy, "validation_projects": unique_projects.size(), "feature_schema": "sfs-visual-statistics-v1", "anatomy_semantics": false}
	model["validation_examples"] = validation_total
	model["validation_folds"] = validation_folds
	model["validation_projects_scored"] = validation_project_ids.size()
	model["validation_approved_recall"] = approved_recall
	model["validation_rejected_recall"] = rejected_recall
	model["validation_balanced_accuracy"] = balanced_accuracy
	model["validation_brier_score"] = brier_score
	if not _write_json(model_path, model): return {"ok": false, "reason": "Falha ao salvar o modelo local.", "counts": sample_counts, "training_counts": model_counts}
	return {"ok": true, "model": model, "counts": sample_counts, "training_counts": model_counts, "excluded_scoped_examples": excluded_scoped_examples, "validation_examples": validation_total}

func evaluate(doc: RefCounted, autonomous: bool = false) -> Dictionary:
	var features := describe(doc)
	if model.is_empty() or model.get("weights", []).size() != 6:
		return {"ready": false, "eligible_for_autonomy": false, "decision": "human_review", "reason": "Ainda não há modelo local treinado.", "features": features}
	var probability := _predict(features, PackedFloat64Array(model.weights))
	var enough := int(model.get("approved", 0)) >= MIN_APPROVED and int(model.get("rejected", 0)) >= MIN_REJECTED and int(model.get("validation_projects_scored", 0)) >= 12 and int(model.get("validation_examples", 0)) >= 20 and int(model.get("validation_folds", 0)) >= 4 and float(model.get("validation_accuracy", 0)) >= 0.92 and float(model.get("validation_balanced_accuracy", 0)) >= 0.90 and float(model.get("validation_approved_recall", 0)) >= 0.90 and float(model.get("validation_rejected_recall", 0)) >= 0.90 and float(model.get("validation_brier_score", 1)) <= 0.10
	if not enough: return {"ready": false, "eligible_for_autonomy": false, "decision": "human_review", "probability": probability, "reason": "Amostra, equilíbrio entre classes ou validação fora dos projetos de treino insuficiente para automação artística.", "features": features}
	if not autonomous: return {"ready": false, "eligible_for_autonomy": true, "decision": "human_review", "probability": probability, "reason": "O modelo passou pelos critérios estatísticos, mas a opção autônoma está desativada.", "features": features}
	if probability >= AUTO_CONFIDENCE: return {"ready": true, "eligible_for_autonomy": true, "decision": "auto_approve_candidate", "probability": probability, "reason": "Sinal local conservador; o portão técnico e Art Bible ainda são obrigatórios.", "features": features}
	if probability <= 1.0 - AUTO_CONFIDENCE: return {"ready": true, "eligible_for_autonomy": true, "decision": "auto_reject_candidate", "probability": probability, "reason": "Sinal local conservador; alteração automática de pixels é proibida.", "features": features}
	return {"ready": false, "eligible_for_autonomy": true, "decision": "human_review", "probability": probability, "reason": "Confiança intermediária; revisão humana necessária.", "features": features}

func recall(doc: RefCounted, limit: int = 8) -> Array[Dictionary]:
	var features := describe(doc)
	var ranked: Array[Dictionary] = []
	for item in examples:
		if int(item.label) != 1 or item.features.size() != features.size(): continue
		var distance := 0.0
		for i in features.size(): distance += pow(features[i] - float(item.features[i]), 2)
		ranked.append({"id": item.id, "project_id": item.project_id, "asset_sha256": item.asset_sha256, "distance": sqrt(distance), "note": item.note})
	ranked.sort_custom(func(a, b): return a.distance < b.distance)
	return ranked.slice(0, mini(limit, ranked.size()))

func _predict(features: Array, weights: PackedFloat64Array) -> float:
	var z := weights[0]
	for i in mini(5, features.size()): z += weights[i + 1] * float(features[i])
	return 1.0 / (1.0 + exp(-clampf(z, -30, 30)))

func _fit(data: Array, epochs: int) -> PackedFloat64Array:
	var weights := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	if data.is_empty(): return weights
	for epoch in epochs:
		var rate := 0.08 / (1.0 + float(epoch) / 60.0)
		for item in data:
			var features: Array = item.features
			if features.size() != 5: continue
			var delta := float(item.label) - _predict(features, weights)
			weights[0] += rate * delta
			for i in 5: weights[i + 1] += rate * delta * float(features[i])
	return weights

func _document_hash(doc: RefCounted, direction_indices: Array = []) -> String:
	var context := HashingContext.new()
	var selected_directions: Array = direction_indices if not direction_indices.is_empty() else range(8)
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify({"id": doc.manifest.id, "revision": doc.revision, "directions": selected_directions, "frames": doc.frames}).to_utf8_buffer())
	for d in selected_directions:
		for f in doc.frames: context.update(doc.composite(d, f).get_data())
	return context.finish().hex_encode()

func _save_contact_sheet(doc: RefCounted, digest: String, direction_indices: Array = []) -> String:
	const CELL := 32
	var selected_directions: Array = direction_indices if not direction_indices.is_empty() else range(8)
	var sheet := Image.create(doc.frames * CELL, selected_directions.size() * CELL, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("202630"))
	for row in selected_directions.size():
		var d: int = selected_directions[row]
		for f in doc.frames:
			var source: Image = doc.composite(d, f)
			if source.is_empty(): return ""
			var scale := minf(float(CELL) / source.get_width(), float(CELL) / source.get_height())
			var width := maxi(1, roundi(source.get_width() * scale))
			var height := maxi(1, roundi(source.get_height() * scale))
			var thumbnail := source.duplicate()
			thumbnail.resize(width, height, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(thumbnail, Rect2i(0, 0, width, height), Vector2i(f * CELL + (CELL - width) / 2, row * CELL + (CELL - height) / 2))
	var folder := preview_root
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: return ""
	var path := folder.path_join(digest + ".png")
	return path if sheet.save_png(path) == OK else ""

func _valid_example(item: Variant) -> bool:
	if not item is Dictionary or int(item.get("schema", 0)) != 1 or not (item.get("label") is float or item.get("label") is int) or int(item.get("label", -1)) not in [0, 1] or not item.get("features") is Array: return false
	if item.features.size() != 5 or str(item.get("asset_sha256", "")).length() != 64 or str(item.get("preview_path", "")).is_empty(): return false
	for value in item.features:
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0 or value > 1: return false
	return true

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 32 * 1024 * 1024: return null
	return JSON.parse_string(file.get_as_text())

func _write_json(path: String, data: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return false
	var tmp := absolute + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data, "\t")); file.flush(); file.close()
	var backup := absolute + ".bak"
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(absolute, backup) != OK:
			if FileAccess.file_exists(tmp): DirAccess.remove_absolute(tmp)
			return false
	var result := DirAccess.rename_absolute(tmp, absolute)
	if result != OK and FileAccess.file_exists(backup): DirAccess.rename_absolute(backup, absolute)
	if result != OK and FileAccess.file_exists(tmp): DirAccess.remove_absolute(tmp)
	if result == OK and FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	return result == OK

func _remove_preview_if_unreferenced(path: String, records: Array) -> void:
	if path.is_empty(): return
	for record in records:
		if record is Dictionary and str(record.get("preview_path", "")) == path: return
	var normalized_root := preview_root.trim_suffix("/") + "/"
	if not path.replace("\\", "/").begins_with(normalized_root): return
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)

func _fail(message: String) -> Dictionary:
	error = message
	return {"ok": false, "error": message}
