extends SceneTree

const Studio = preload("res://ui/studio.gd")
const Storage = preload("res://core/storage.gd")
const ExportValidator = preload("res://core/export_validator.gd")

var checks: Array[Dictionary] = []
var failed := 0

func check(condition: bool, label: String) -> void:
	checks.append({"name": label, "passed": condition})
	if condition: print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio = Studio.new()
	root.add_child(studio)
	await process_frame
	await process_frame
	var document = studio.doc
	if document.animation.clips.is_empty():
		check(false, "fixture possui ao menos um clip para duplicar")
		quit(1)
		return
	if document.animation.clips.size() < 2:
		var copied_clip: Dictionary = document.animation.clips[0].duplicate(true)
		copied_clip.name = str(copied_clip.get("name", "Clip")) + "_batch"
		document.animation.clips.append(copied_clip)
	document.animation.clips.resize(2)
	for clip in document.animation.clips: clip.frames = [0]
	studio.workspace.data_root = "res://test_results/three-d-motion-batch-visual-workspace"
	var clip_total: int = document.animation.clips.size()
	var prior_active_clip := int(document.animation.active)
	await studio._capture_all_3d_motion_clips()
	var records: Array = document.art.get("three_d_motion_captures", [])
	var modular_records: Array = records.filter(func(record: Dictionary) -> bool: return str(record.get("capture_mode", "")) == "modular_pass")
	var captured_clip_indices: Dictionary = {}
	for record in modular_records: captured_clip_indices[int(record.get("clip_index", -1))] = true
	check(modular_records.size() == clip_total * 3 and captured_clip_indices.size() == clip_total and document.layers.size() == 1 + clip_total * 3, "renderização gráfica captura dois clips em oito vistas e cria nove layers candidatas")
	check(int(document.animation.active) == prior_active_clip and document.art.candidate_status == "candidate", "lote restaura clip ativo e mantém revisão humana obrigatória")
	var checkpoint_revision: int = studio.workspace.recovery_revision(studio.workspace.active_id)
	check(checkpoint_revision >= int(document.revision), "cada captura fica confirmada no checkpoint de recuperação")
	var count_before_resume := modular_records.size()
	await studio._capture_all_3d_motion_clips()
	var count_after_resume: int = document.art.get("three_d_motion_captures", []).filter(func(record: Dictionary) -> bool: return str(record.get("capture_mode", "")) == "modular_pass").size()
	check(count_after_resume == count_before_resume and str(studio.three_d_motion_panel.status_label.text).contains("Nada precisa ser recapturado"), "segunda execução retoma sem renderizar clips já completos")
	var export_folder := ProjectSettings.globalize_path("res://test_results/three-d-motion-batch-visual-export")
	var storage := Storage.new()
	var export_error: Error = storage.export_all(document, export_folder, "playable")
	var exported_metadata: Variant = Storage.read_json(export_folder.path_join("metadata.json"))
	var exported_captures: Array = exported_metadata.get("three_d_motion", {}).get("captures", []) if exported_metadata is Dictionary else []
	check(export_error == OK and exported_metadata is Dictionary and exported_captures.size() == records.size() and exported_metadata.get("manifest", {}).get("id", "") == document.manifest.id, "o mesmo documento candidato exporta cena e provenance das capturas 3D (erro %d; doc %s)" % [export_error, str(document.validate())])
	var export_validation: Dictionary = ExportValidator.validate_package(export_folder) if export_error == OK else {"ok": false, "failed": 1}
	check(bool(export_validation.get("ok", false)), "pacote saído do lote passa a validação independente do consumidor Godot (%s)" % str(export_validation.get("errors", [])))
	studio.queue_free()
	await process_frame
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks, "clips": clip_total, "modular_records": modular_records.size(), "document_revision": int(document.revision), "checkpoint_revision": checkpoint_revision, "export_validation": export_validation}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/three-d-motion-batch-visual-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("3D Motion batch visual smoke: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
