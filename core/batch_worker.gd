extends RefCounted
const Storage = preload("res://core/storage.gd")
const ALGORITHM = "SFS-export-0.66-profiled-schema3"
const Pipeline = preload("res://core/production_pipeline.gd")
const ExportValidator = preload("res://core/export_validator.gd")

static func run_request(path: String) -> int:
	var request = Storage.read_json(path)
	if not request is Dictionary or not request.has_all(["schema", "input", "output", "id", "result", "progress", "cancel"]) or request.schema != 1: return 2
	var started := Time.get_ticks_msec()
	var result := execute(request)
	result.elapsed_ms = Time.get_ticks_msec() - started
	var storage := Storage.new()
	return 0 if storage.atomic_json(request.result, result) == OK else 3

static func state(request: Dictionary, status: String, progress: int) -> void:
	Storage.new().atomic_json(request.progress, {"status": status, "progress": progress})

static func execute(request: Dictionary) -> Dictionary:
	var storage := Storage.new()
	state(request, "preparing", 5)
	if not FileAccess.file_exists(request.input): return {"status": "failed", "error": "Projeto de entrada inexistente."}
	if request.get("kind", "export") == "import_arton": return import_arton(request)
	if request.get("kind", "export") == "production": return production(request)
	if request.get("kind", "export") != "export": return {"status": "failed", "error": "Tipo de tarefa desconhecido."}
	var parameters: Variant = request.get("parameters", {})
	if not parameters is Dictionary: return {"status": "failed", "error": "Parâmetros de exportação inválidos."}
	var profile := str(parameters.get("profile", "playable"))
	if profile not in Storage.EXPORT_PROFILES: return {"status": "failed", "error": "Perfil de exportação desconhecido: " + profile}
	var profile_algorithm := _profile_algorithm(profile)
	var hash: String = FileAccess.get_sha256(request.input)
	var manifest_path: String = request.output.path_join("batch_manifest.json")
	var manifest = Storage.read_json(manifest_path)
	if FileAccess.file_exists(request.cancel): return {"status": "cancelled", "error": "Cancelado antes de processar."}
	if manifest is Dictionary and manifest.get("hash") == hash and manifest.get("algorithm") == profile_algorithm and valid_cache(request.output, manifest, profile):
		return {"status": "cached", "error": "", "hash": hash, "report_path": request.output.path_join("export-validation.json")}
	var doc = storage.load_document(request.input)
	if doc == null: return {"status": "failed", "error": storage.error}
	if FileAccess.get_sha256(request.input) != hash: return {"status": "failed", "error": "Entrada mudou durante leitura."}
	state(request, "running", 25)
	var job_id := str(request.get("id", "")).validate_filename()
	if job_id.is_empty(): return {"status": "failed", "error": "Identificador de lote inválido."}
	var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(request.output))
	if output_error != OK: return {"status": "failed", "error": error_string(output_error)}
	var staging: String = request.output.path_join(".sfs-stage-" + job_id)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(staging)):
		var cleanup_error := _remove_tree(staging)
		if cleanup_error != OK: return {"status": "failed", "error": "Staging anterior não pôde ser limpo: " + error_string(cleanup_error)}
	var result: Error = storage.export_all(doc, staging, profile)
	if result != OK: return {"status": "failed", "error": error_string(result)}
	if FileAccess.file_exists(request.cancel): _remove_tree(staging); return {"status": "cancelled", "error": "Cancelado; saídas anteriores preservadas."}
	state(request, "validating", 80)
	var scene_files: Array[String] = []
	match profile:
		"animated": scene_files = ["character.tscn"]
		"modular": scene_files = ["modular_character.tscn"]
		"playable": scene_files = ["character.tscn", "map.tscn"]
		"map":
			var room_manifest: Variant = Storage.read_json(staging.path_join("rooms.json"))
			if room_manifest is Dictionary and room_manifest.get("rooms", null) is Array:
				for room in room_manifest.rooms:
					if room is Dictionary: scene_files.append(str(room.get("scene", "")))
	for name in scene_files:
		var scene = ResourceLoader.load(staging.path_join(name), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		if not scene is PackedScene: _remove_tree(staging); return {"status": "failed", "error": "Cena exportada inválida: " + name}
		var instance: Node = scene.instantiate()
		instance.free()
	var validation: Dictionary = ExportValidator.validate_profile(staging, profile)
	if not bool(validation.get("ok", false)):
		_remove_tree(staging)
		return {"status": "failed", "error": "A validação profunda do pacote falhou.", "validation": validation}
	var validation_error := storage.atomic_json(staging.path_join("export-validation.json"), validation)
	if validation_error != OK:
		_remove_tree(staging)
		return {"status": "failed", "error": "Não foi possível gravar o relatório de validação: " + error_string(validation_error)}
	var staged_files := _list_files(staging)
	for name in _required_files(profile, staging):
		if not staged_files.has(name): _remove_tree(staging); return {"status": "failed", "error": "Arquivo necessário ausente na exportação: " + name}
	var checksums := {}
	for name in staged_files:
		checksums[name] = FileAccess.get_sha256(staging.path_join(name))
		if str(checksums[name]).is_empty(): _remove_tree(staging); return {"status": "failed", "error": "Não foi possível calcular o hash: " + name}
	if FileAccess.file_exists(request.cancel): _remove_tree(staging); return {"status": "cancelled", "error": "Cancelado antes da publicação."}
	var published := _publish_tree(request.output, staging, staged_files, manifest.get("checksums", {}) if manifest is Dictionary else {})
	if not published.ok:
		_remove_tree(staging)
		return {"status": "failed", "hash": hash, "error": str(published.error)}
	result = storage.atomic_json(manifest_path, {"schema": 3, "hash": hash, "algorithm": profile_algorithm, "profile": profile, "checksums": checksums})
	if result != OK:
		_rollback_tree(published.changes)
		_remove_tree(staging)
		return {"status": "failed", "hash": hash, "error": "Manifesto de publicação não foi gravado: " + error_string(result)}
	_remove_tree(staging)
	return {"status": "done", "hash": hash, "error": "", "report_path": request.output.path_join("export-validation.json")}

static func production(request: Dictionary) -> Dictionary:
	if FileAccess.file_exists(request.cancel): return {"status": "cancelled", "error": "Cancelado antes de processar."}
	var report_path: String = request.output.path_join("production-report.json")
	var candidate: String = request.output.path_join("candidate.sfs.json")
	var export_folder: String = request.output.path_join("export")
	var source_hash: String = FileAccess.get_sha256(request.input)
	var previous = Storage.read_json(report_path)
	var exported = Storage.read_json(export_folder.path_join("batch_manifest.json"))
	var key := Pipeline.fingerprint(source_hash, request.get("parameters", {}))
	if previous is Dictionary and previous.get("status") == "done" and previous.get("fingerprint") == key and FileAccess.file_exists(candidate) and previous.get("candidate_hash") == FileAccess.get_sha256(candidate):
		var profile := str(request.get("parameters", {}).get("profile", "playable"))
		if exported is Dictionary and exported.get("algorithm") == _profile_algorithm(profile) and exported.get("hash") == previous.candidate_hash and valid_cache(export_folder, exported, profile):
			return {"status": "cached", "error": "", "hash": key, "project_path": candidate, "report_path": report_path}
	var prepared := Pipeline.prepare(request)
	var report: Dictionary = prepared.get("report", {"schema": 1, "source": request.input, "artistic_approval": false})
	var result := prepared
	if prepared.status == "prepared":
		var child: Dictionary = request.duplicate(true)
		child.kind = "export"; child.input = candidate; child.output = export_folder
		result = execute(child)
		report.stages.append({"step": "export_and_load_scenes", "ok": result.status in ["done", "cached"]})
	if FileAccess.get_sha256(request.input) != source_hash: result = {"status": "failed", "error": "Entrada mudou durante a produção; nenhuma aprovação foi concedida."}
	report.status = "done" if result.status in ["done", "cached"] else result.status
	report.error = result.get("error", "")
	report.finished_at = Time.get_datetime_string_from_system()
	var write_result := DirAccess.make_dir_recursive_absolute(request.output)
	if write_result == OK: write_result = Storage.new().atomic_json(report_path, report)
	if write_result != OK: return {"status": "failed", "error": "Não foi possível registrar relatório: " + error_string(write_result)}
	return {"status": report.status, "error": report.error, "hash": key, "project_path": candidate if report.status == "done" else "", "report_path": report_path}

static func valid_cache(folder: String, manifest: Dictionary, profile: String = "playable") -> bool:
	if manifest.get("schema") != 3 or not manifest.get("checksums") is Dictionary: return false
	if profile not in Storage.EXPORT_PROFILES: return false
	if str(manifest.get("profile", profile)) != profile: return false
	var profile_data: Variant = Storage.read_json(folder.path_join("export-profile.json"))
	if not profile_data is Dictionary or str(profile_data.get("profile", "")) != profile: return false
	var checksums: Dictionary = manifest.checksums
	for name in _required_files(profile, folder):
		if not checksums.has(name): return false
	if checksums.is_empty(): return false
	for name in checksums:
		if not _safe_relative_path(str(name)): return false
		var path := folder.path_join(str(name))
		if not FileAccess.file_exists(path) or checksums.get(name) != FileAccess.get_sha256(path): return false
	return true

static func _profile_algorithm(profile: String) -> String:
	return ALGORITHM + "-" + profile

static func _required_files(profile: String, folder: String) -> Array[String]:
	var common: Array[String] = ["CREDITS.txt", "export-profile.json", "export-validation.json"]
	match profile:
		"sequence":
			common.append("sequence.json")
			var sequence: Variant = Storage.read_json(folder.path_join("sequence.json"))
			if sequence is Dictionary:
				for frame in sequence.get("frames", []):
					if frame is Dictionary and _safe_relative_path(str(frame.get("file", ""))): common.append(str(frame.file))
		"sprite": common.append_array(["frame.png", "spritesheet.png", "metadata.json"])
		"animated": common.append_array(["frame.png", "spritesheet.png", "metadata.json", "animations.tres", "character.tscn"])
		"modular":
			common.append_array(["spritesheet.png", "metadata.json", "modular.json", "modular_character.tscn"])
			var modular: Variant = Storage.read_json(folder.path_join("modular.json"))
			if modular is Dictionary and modular.get("layers", null) is Array:
				for layer in modular.layers:
					if layer is Dictionary and str(layer.get("texture", "")).begins_with("layers/") and not common.has(str(layer.texture)): common.append(str(layer.texture))
		"playable": common.append_array(["frame.png", "spritesheet.png", "metadata.json", "character.tscn", "map.tscn", "animations.tres", "tileset.tres", "rooms.json", "examples/export/doorway.gd", "examples/export/room_transition.gd", "examples/export/pixel_camera.gd"])
		"map": common.append_array(["map.tscn", "tileset.tres", "rooms.json", "examples/export/doorway.gd", "examples/export/room_transition.gd", "examples/export/pixel_camera.gd"])
	return common

static func _safe_relative_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	if normalized.is_empty() or normalized.begins_with("/") or normalized.contains(":"): return false
	for part in normalized.split("/"):
		if part in ["", ".", ".."]: return false
	return true

static func _list_files(root_path: String, relative: String = "") -> Array[String]:
	var result: Array[String] = []
	var current := root_path.path_join(relative) if not relative.is_empty() else root_path
	var directory := DirAccess.open(current)
	if directory == null: return result
	for filename in directory.get_files():
		if filename.begins_with("."): continue
		var path := relative.path_join(filename) if not relative.is_empty() else filename
		if _safe_relative_path(path): result.append(path.replace("\\", "/"))
	for child in directory.get_directories():
		if child.begins_with("."): continue
		var child_path := relative.path_join(child) if not relative.is_empty() else child
		result.append_array(_list_files(root_path, child_path))
	result.sort()
	return result

static func _publish_tree(output: String, staging: String, staged_files: Array[String], old_checksums: Variant) -> Dictionary:
	var new_paths: Dictionary = {}
	for relative in staged_files:
		if not _safe_relative_path(relative): return {"ok": false, "error": "Caminho de exportação inválido: " + relative, "changes": []}
		new_paths[relative] = true
	var changes: Array[Dictionary] = []
	var paths: Array[String] = staged_files.duplicate()
	if old_checksums is Dictionary:
		for old_path in old_checksums:
			var relative := str(old_path).replace("\\", "/")
			if _safe_relative_path(relative) and not new_paths.has(relative): paths.append(relative)
	paths.sort()
	var rollback_root := staging.path_join(".rollback")
	for relative in paths:
		var destination := output.path_join(relative)
		var backup := rollback_root.path_join(relative)
		var is_new: bool = new_paths.has(relative)
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(destination)):
			_rollback_tree(changes)
			return {"ok": false, "error": "O destino é uma pasta, não um arquivo: " + relative, "changes": []}
		var had_old := FileAccess.file_exists(destination)
		if had_old:
			var backup_parent := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup.get_base_dir()))
			if backup_parent != OK:
				_rollback_tree(changes)
				return {"ok": false, "error": error_string(backup_parent), "changes": []}
			var move_old := DirAccess.rename_absolute(ProjectSettings.globalize_path(destination), ProjectSettings.globalize_path(backup))
			if move_old != OK:
				_rollback_tree(changes)
				return {"ok": false, "error": error_string(move_old), "changes": []}
		var change := {"destination": destination, "backup": backup, "had_old": had_old, "published": false}
		changes.append(change)
		if not is_new: continue
		var output_parent := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
		if output_parent != OK:
			_rollback_tree(changes)
			return {"ok": false, "error": error_string(output_parent), "changes": []}
		var move_new := DirAccess.rename_absolute(ProjectSettings.globalize_path(staging.path_join(relative)), ProjectSettings.globalize_path(destination))
		if move_new != OK:
			_rollback_tree(changes)
			return {"ok": false, "error": error_string(move_new), "changes": []}
		changes[-1].published = true
	return {"ok": true, "error": "", "changes": changes}

static func _rollback_tree(changes: Array) -> void:
	for index in range(changes.size() - 1, -1, -1):
		var change: Dictionary = changes[index]
		if change.published and FileAccess.file_exists(change.destination): DirAccess.remove_absolute(ProjectSettings.globalize_path(change.destination))
		if change.had_old and FileAccess.file_exists(change.backup):
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(change.destination.get_base_dir()))
			DirAccess.rename_absolute(ProjectSettings.globalize_path(change.backup), ProjectSettings.globalize_path(change.destination))

static func _remove_tree(path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute): return DirAccess.remove_absolute(absolute)
	if not DirAccess.dir_exists_absolute(absolute): return OK
	var directory := DirAccess.open(absolute)
	if directory == null: return DirAccess.get_open_error()
	for filename in directory.get_files():
		var remove_file := DirAccess.remove_absolute(absolute.path_join(filename))
		if remove_file != OK: return remove_file
	for child in directory.get_directories():
		var remove_child := _remove_tree(absolute.path_join(child))
		if remove_child != OK: return remove_child
	return DirAccess.remove_absolute(absolute)

static func import_arton(request: Dictionary) -> Dictionary:
	if FileAccess.file_exists(request.cancel): return {"status": "cancelled", "error": "Importação cancelada."}
	var parameters = request.get("parameters", {})
	if not parameters is Dictionary or not parameters.get("family") is String: return {"status": "failed", "error": "Família não informada."}
	state(request, "running", 20)
	var importer := preload("res://core/arton_importer.gd").new()
	var doc = importer.import_family(request.input, parameters.family, parameters.get("garments", true))
	if doc == null: return {"status": "failed", "error": importer.error}
	if FileAccess.file_exists(request.cancel): return {"status": "cancelled", "error": "Importação cancelada antes de salvar."}
	state(request, "validating", 80)
	var result := DirAccess.make_dir_recursive_absolute(request.output)
	if result != OK: return {"status": "failed", "error": error_string(result)}
	var path: String = request.output.path_join("imported.sfs.json")
	result = Storage.new().save_document(doc, path)
	return {"status": "done" if result == OK else "failed", "error": "" if result == OK else error_string(result), "hash": FileAccess.get_sha256(request.input), "project_path": path if result == OK else ""}
