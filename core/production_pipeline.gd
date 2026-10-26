extends RefCounted
## Local, deterministic production. Never overwrites the source or approves art.
const Storage = preload("res://core/storage.gd")
const Precision = preload("res://core/precision.gd")
const World = preload("res://core/world_data.gd")
const VERSION = "SFS-production-0.6-1"

static func profile(options: Dictionary) -> Dictionary:
	return {"quantize": options.get("quantize", false) == true, "require_nonempty": options.get("require_nonempty", true) == true}

static func fingerprint(source_hash: String, options: Dictionary) -> String:
	return (VERSION + source_hash + JSON.stringify(profile(options))).sha256_text()

static func prepare(request: Dictionary) -> Dictionary:
	var storage := Storage.new()
	var input_path: String = ProjectSettings.globalize_path(request.input).replace("\\", "/").simplify_path().to_lower()
	var output_path: String = ProjectSettings.globalize_path(request.output).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var approved := ProjectSettings.globalize_path("user://approved_library").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if output_path == approved or output_path.begins_with(approved + "/"): return {"status": "failed", "error": "A biblioteca aprovada não aceita saídas automáticas."}
	if input_path.begins_with(output_path + "/"): return {"status": "failed", "error": "A saída não pode conter o projeto original."}
	var doc = storage.load_document(request.input)
	if doc == null: return {"status": "failed", "error": storage.error}
	var source_hash: String = FileAccess.get_sha256(request.input)
	var options := profile(request.get("parameters", {}))
	var report := {"schema": 1, "algorithm": VERSION, "source": request.input, "source_hash": source_hash, "profile": options, "fingerprint": fingerprint(source_hash, options), "status": "running", "artistic_approval": false, "changed_pixels": 0, "cels": [], "stages": []}
	var total: int = doc.layers.size() * 8 * doc.frames
	var completed: int = 0
	var original_context := [doc.active_layer, doc.direction, doc.frame]
	var precision := Precision.new()
	for layer in doc.layers.size():
		doc.active_layer = layer
		for direction in 8:
			doc.direction = direction
			for frame in doc.frames:
				if FileAccess.file_exists(request.cancel): return {"status": "cancelled", "error": "Cancelado entre cels."}
				doc.frame = frame
				var changed: int = 0
				if options.quantize and not doc.layers[layer].locked:
					var draft := precision.draft_palette(doc)
					changed = draft.changed
					if changed > 0: doc.layers[layer].cels[direction][frame] = draft.after
				var metrics := precision.diagnose(doc.current(), doc.palette)
				report.changed_pixels += changed
				report.cels.append({"layer": layer, "direction": direction, "frame": frame, "changed": changed, "metrics": metrics})
				completed += 1
				storage.atomic_json(request.progress, {"status": "running", "progress": 10 + int(50.0 * completed / total)})
	doc.active_layer = original_context[0]; doc.direction = original_context[1]; doc.frame = original_context[2]
	report.stages.append({"step": "inspect_and_correct", "ok": true, "cels": total})
	if options.require_nonempty:
		var visible := false
		for direction in 8:
			for frame in doc.frames:
				var bytes: PackedByteArray = doc.composite(direction, frame).get_data()
				for i in range(3, bytes.size(), 4):
					if bytes[i] > 0: visible = true; break
				if visible: break
			if visible: break
		if not visible:
			var used := {}
			for layer in World.layers(doc.map_data):
				if layer.visible and layer.opacity > 0:
					for tile in layer.cells:
						if tile >= 0: used[int(tile)] = true
			var tiles: Array = doc.tile_images() if not used.is_empty() else []
			for tile in used:
				if tile >= tiles.size(): continue
				var bytes: PackedByteArray = tiles[tile].get_data()
				for i in range(3, bytes.size(), 4):
					if bytes[i] > 0: visible = true; break
				if visible: break
		report.visible_art = visible
		if not visible: return {"status": "failed", "error": "Projeto sem pixels visíveis na composição.", "report": report}
	var errors: Array = doc.validate()
	report.map = {"width": doc.map_data.width, "height": doc.map_data.height, "layers": doc.map_data.layers.size() + 1, "terrain_sets": doc.map_data.terrain_sets.size(), "lights": doc.map_data.lights.size(), "navigation": preload("res://core/navigation.gd").new().analyze(doc.map_data)}
	if not errors.is_empty(): return {"status": "failed", "error": "; ".join(errors), "report": report}
	if FileAccess.get_sha256(request.input) != source_hash: return {"status": "failed", "error": "Entrada mudou durante a preparação.", "report": report}
	if report.changed_pixels > 0:
		report.invalidated_approvals = doc.manifest.approvals.size()
		doc.manifest.approvals.clear()
		doc.manifest.id = Crypto.new().generate_random_bytes(16).hex_encode()
	doc.manifest.production = {"algorithm": VERSION, "source_hash": source_hash, "profile": options, "artistic_approval": false}
	report.stages.append({"step": "validate", "ok": true})
	var result := DirAccess.make_dir_recursive_absolute(request.output)
	if result != OK: return {"status": "failed", "error": error_string(result), "report": report}
	var candidate: String = request.output.path_join("candidate.sfs.json")
	result = storage.save_document(doc, candidate)
	if result != OK: return {"status": "failed", "error": error_string(result), "report": report}
	report.candidate_hash = FileAccess.get_sha256(candidate)
	report.stages.append({"step": "save_candidate", "ok": true})
	return {"status": "prepared", "error": "", "project_path": candidate, "report": report}
