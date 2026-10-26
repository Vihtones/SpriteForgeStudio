extends SceneTree
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const Validator = preload("res://core/export_validator.gd")
const Worker = preload("res://core/batch_worker.gd")
const Importer = preload("res://core/png_sequence_importer.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, title: String) -> void:
	if value: passed += 1; print("PASS ", title)
	else: failed += 1; printerr("FAIL ", title)

func run() -> void:
	var folder := "res://test_results/png-sequence-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var doc = Doc.new()
	expect(doc.initialize_blank(48, 64, 6, 12), "cria tela transparente retangular e timeline para o fluxo completo")
	doc.palette.append("#123456")
	for direction in 8:
		for frame in 6:
			doc.direction = direction; doc.frame = frame
			doc.pixel(Vector2i(frame + 2, direction + 3), Color.CORAL)
	doc.animation.clips[0].durations_ms["1"] = 240
	doc.animation.events[doc.cel_key(2, 1)] = ["contact"]
	doc.animation.hitboxes[doc.cel_key(2, 1)] = [2, 3, 4, 5]
	var storage = Storage.new()
	var project_path := folder.path_join("source.sfs.json")
	var saved: Error = storage.save_document(doc, project_path)
	var reopened = storage.load_document(project_path)
	expect(saved == OK and reopened != null and reopened.width == 48 and reopened.height == 64 and reopened.frames == 6 and reopened.fps == 12 and reopened.composite(2, 1).get_data() == doc.composite(2, 1).get_data(), "pintura, dimensão, quadros e FPS sobrevivem ao save/load")
	if reopened == null: quit(1); return
	var output := folder.path_join("export")
	var export_error: Error = storage.export_all(reopened, output, "sequence")
	var manifest: Variant = Storage.read_json(output.path_join("sequence.json"))
	expect(export_error == OK and manifest is Dictionary and manifest.frames.size() == 48 and Validator.validate_profile(output, "sequence").ok, "perfil PNG gera 48 quadros válidos nas oito direções")
	if not manifest is Dictionary: quit(1); return
	var pixels_match := true
	for row in manifest.frames:
		var image := Image.load_from_file(output.path_join(row.file))
		var direction: int = manifest.directions.find(row.direction)
		if image == null or image.get_data() != reopened.composite(direction, int(row.frame)).get_data(): pixels_match = false
	expect(pixels_match, "cada PNG independente conserva exatamente os pixels compostos e transparência")
	expect(is_equal_approx(manifest.clips[0].frames[1].duration_ms, 240.0) and is_equal_approx(manifest.clips[0].frames[0].duration_ms, 1000.0 / 12.0), "manifesto conserva duração específica e duração nominal por clip")
	var east_frame: Dictionary = manifest.frames.filter(func(row): return row.direction == "E" and int(row.frame) == 1)[0]
	var exported_hitbox: Array = east_frame.hitboxes.map(func(value): return int(value))
	var exported_pivot: Array = east_frame.pivot.map(func(value): return int(value))
	expect(east_frame.events == ["contact"] and exported_hitbox == [2, 3, 4, 5] and exported_pivot == reopened.anchor_at("feet", 2, 1), "metadados conservam pivô, eventos e hitbox do quadro e direção corretos")
	var importer = Importer.new()
	var imported: Dictionary = importer.load_sequence(output.path_join("sequence.json"))
	expect(imported.get("ok", false) and imported.document.manifest.id != reopened.manifest.id and imported.document.manifest.approvals.is_empty() and imported.document.art.status == "candidate", "importação cria uma nova candidata sem herdar identidade ou aprovações")
	if not imported.get("ok", false): printerr(imported); quit(1); return
	var restored = imported.document
	var imported_pixels_match := true
	for direction in 8:
		for frame in 6:
			if restored.composite(direction, frame).get_data() != reopened.composite(direction, frame).get_data(): imported_pixels_match = false
	expect(imported_pixels_match and restored.width == 48 and restored.height == 64 and restored.frames == 6 and restored.fps == 12 and restored.palette == reopened.palette, "reimportação conserva pixels, dimensões e paleta da sequência")
	expect(is_equal_approx(restored.frame_seconds(1, restored.animation.clips[0]), 0.240) and restored.animation.events.get("2:1", []) == ["contact"] and restored.anchor_at("feet", 2, 1) == east_frame.pivot and restored.rig.family == reopened.rig.family and restored.rig.skeleton == reopened.rig.skeleton, "reimportação restaura clips, duração, eventos, pivôs e guias do rig")
	var reimport_path := folder.path_join("reimport.sfs.json")
	expect(storage.save_document(restored, reimport_path) == OK and storage.load_document(reimport_path) != null, "sequência reimportada é um projeto SFS persistente e válido")
	var ui = load("res://main.tscn").instantiate()
	ui.workspace_root = folder.path_join("ui-workspace")
	root.add_child(ui); ui.set_process(false)
	await process_frame
	var source_document_id: String = ui.workspace.active_id
	ui.dialog_action = "png_sequence"
	ui.selected_path(output.path_join("sequence.json"))
	expect(ui.workspace.active_id != source_document_id and ui.doc.width == 48 and ui.doc.frames == 6, "ação da interface abre a sequência em nova aba sem substituir o documento anterior")
	var altered := Image.load_from_file(output.path_join(east_frame.file))
	altered.set_pixel(0, 0, Color.WHITE); altered.save_png(output.path_join(east_frame.file))
	expect(not Validator.validate_profile(output, "sequence").ok, "validador recusa pixels alterados mesmo com dimensão correta")
	var modified: Dictionary = importer.load_sequence(output.path_join("sequence.json"))
	expect(modified.get("requires_confirmation", false) and modified.changed_frames.size() == 1, "PNGs alterados exigem confirmação e identificam o arquivo modificado")
	var tabs_before: int = ui.workspace.records.size()
	ui.import_png_sequence(output.path_join("sequence.json"))
	var confirmation: ConfirmationDialog = ui.get_node_or_null("ModifiedSequenceConfirmation")
	expect(confirmation != null and ui.workspace.records.size() == tabs_before, "interface mantém a sessão intacta enquanto a importação modificada aguarda confirmação")
	if confirmation != null: confirmation.confirmed.emit()
	await process_frame
	expect(ui.workspace.records.size() == tabs_before + 1 and ui.doc.art.png_sequence_import.modified_frames.size() == 1 and ui.doc.composite(2, 1).get_pixel(0, 0) == Color.WHITE, "confirmação importa retoque externo como candidata com proveniência da modificação")
	altered.set_pixel(1, 0, Color.BLUE); altered.save_png(output.path_join(east_frame.file))
	expect(not importer.load_sequence(output.path_join("sequence.json"), true, modified.snapshot).get("ok", false), "mudança posterior à confirmação invalida o snapshot de importação")
	ui.free(); await process_frame
	storage.export_all(reopened, output, "sequence")
	var malformed: Dictionary = Storage.read_json(output.path_join("sequence.json"))
	malformed.frames[0].anchors.feet = "invalid"
	storage.atomic_json(output.path_join("sequence.json"), malformed)
	expect(not importer.load_sequence(output.path_join("sequence.json")).get("ok", false), "metadados de âncora malformados são recusados sem criar documento")
	storage.export_all(reopened, output, "sequence")
	manifest.clips[0].frames[0].duration_ms = -1
	storage.atomic_json(output.path_join("sequence.json"), manifest)
	expect(not Validator.validate_profile(output, "sequence").ok, "validador recusa timing inválido no manifesto")
	var worker_output := folder.path_join("batch")
	var request := {"schema": 1, "id": "sequence-test", "kind": "export", "input": project_path, "output": worker_output, "result": folder.path_join("result.json"), "progress": folder.path_join("progress.json"), "cancel": folder.path_join("cancel.flag"), "parameters": {"profile": "sequence"}}
	var result: Dictionary = Worker.execute(request)
	expect(result.status == "done" and Validator.validate_profile(worker_output, "sequence").ok, "worker publica a árvore completa de PNGs e manifesto")
	result = Worker.execute(request)
	expect(result.status == "cached", "cache reconhece a sequência publicada sem reexportar")
	altered.save_png(worker_output.path_join(east_frame.file))
	result = Worker.execute(request)
	expect(result.status == "done" and Validator.validate_profile(worker_output, "sequence").ok, "corrupção em um PNG invalida o cache e reconstrói a sequência")
	var report := FileAccess.open("res://test_results/png-sequence-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("PNG sequence: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or report == null else 0)
