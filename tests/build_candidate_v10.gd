extends SceneTree
const Storage = preload("res://core/storage.gd")
const Isolator = preload("res://core/silhouette_atlas.gd")
const Importer = preload("res://core/spritesheet_importer.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var source := "res://examples/animation_candidate_v8/sentinela-sheet-candidate-v1.png"
	var original := Image.load_from_file(source)
	var extraction: Dictionary = Isolator.extract(original, 6, 3)
	if not extraction.ok: printerr(extraction.error); quit(1); return
	print("ISOLATED: ", extraction.parts.size(), " figures; grid crossings: ", JSON.stringify(extraction.crossings))
	var store = Storage.new()
	var doc = store.load_document("res://samples/sentinela_artist_v9.sfs.json")
	if doc == null: printerr(store.error); quit(1); return
	doc.direction = 4
	for row in [1, 2]:
		var clip: Dictionary = doc.animation.clips[row]
		var result: Dictionary = Importer.import_isolated_row(doc, extraction, {"source_row": row, "start_frame": int(clip.frames[0]), "content_scale": 0.72, "alignment": "bottom_center"})
		if not result.ok: printerr(result.error); quit(1); return
		for hold in [6, 7]: doc.layers[0].cels[4][clip.frames[hold]] = doc.layers[0].cels[4][clip.frames[5]].duplicate()
	doc.manifest.name = "Sentinela v10 — recorte isolado, candidata à revisão"
	doc.manifest.provenance = "Derivada da coleção v9. Somente pulo e ataque Sul reimportados pelo SFS por silhueta conectada; originais preservados. Mudança raster reinicia aprovação."
	doc.art["review_scope"] = "Bleed repair: isolated South jump/attack silhouettes; old idle and seven directions unchanged; pending visual review"
	doc.art["bleed_fix"] = {"source": source, "sha256": FileAccess.get_sha256(source), "source_grid": [6, 3], "component_count": extraction.parts.size(), "crossings": extraction.crossings, "sampling": "nearest", "common_scale": 0.72, "coverage": {"idle_breathing": [], "jump": ["S"], "attack": ["S"]}, "status": "partial"}
	doc.art.candidate_status = "candidate"; doc.manifest.approvals = []; doc.art.pose_approvals = []
	doc.frame = 0; doc.animation.active = 0
	if not doc.validate().is_empty(): printerr(doc.validate()); quit(1); return
	if store.save_document(doc, "res://samples/sentinela_candidate_v10.sfs.json") != OK: quit(1); return
	var folder := ProjectSettings.globalize_path("res://examples/animation_candidate_v10")
	if store.export_all(doc, folder) != OK: printerr("Export failed"); quit(1); return
	var report := FileAccess.open(folder.path_join("isolation.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(doc.art.bleed_fix, "\t")); report.close()
	print("CANDIDATE_V10: OK — South jump/attack isolated; approval reset; originals retained")
	quit()
