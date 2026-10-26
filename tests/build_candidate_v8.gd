extends SceneTree

const Storage = preload("res://core/storage.gd")
const Importer = preload("res://core/spritesheet_importer.gd")
const Synthesizer = preload("res://core/animation_synthesizer.gd")
const CLIPS := ["idle_breathing", "jump", "attack"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var storage = Storage.new()
	var doc = storage.load_document("res://samples/sentinela_scale_study.sfs.json")
	if doc == null:
		fail("scale study could not be loaded")
		return
	doc = doc.detached_copy()
	var source_path := ProjectSettings.globalize_path("res://examples/animation_candidate_v8/sentinela-sheet-candidate-v1.png")
	var sheet := Image.new()
	if sheet.load(source_path) != OK:
		fail("candidate image could not be loaded")
		return
	var original_size := sheet.get_size()
	if original_size.x < 6 or original_size.y < 3:
		fail("source sheet has invalid dimensions")
		return
	doc.direction = 4 # S: face the viewer, consistent with the source reference sheet.
	for row in 3:
		var clip: Dictionary = doc.animation.clips[row]
		if str(clip.name) != CLIPS[row]:
			fail("expected clip order %s, got %s" % [CLIPS[row], clip.name])
			return
		var first_frame := int(clip.frames[0])
		var result: Dictionary = Importer.import_grid_row(doc, sheet, {
			"columns": 6,
			"source_rows": 3,
			"source_row": row,
			"fit_grid": true,
			"start_frame": first_frame,
			"all_directions": false,
			"content_scale": 0.72,
			"alignment": "bottom_center"
		})
		if not result.get("ok", false):
			fail("SFS import failed for %s: %s" % [CLIPS[row], result.get("error", "unknown error")])
			return
		if row == 0:
			var breathing: Dictionary = Synthesizer.generate_breathing(doc, 0, CLIPS[row], 2.0)
			if not breathing.get("ok", false):
				fail("SFS breathing synthesis failed: %s" % breathing.get("error", "unknown error"))
				return
	# New pixels have no inherited human review. Keep the scope of the artwork explicit.
	doc.art.candidate_status = "candidate"
	doc.art.pose_approvals = []
	doc.art.candidates = []
	doc.art["review_scope"] = "Generated art: South jump and attack; procedural idle across eight directions"
	doc.art.bible = "Crônicas de Arton — estudo candidato em pixel clusters, vistas top-down próximas, tons naturais, luz superior esquerda, pano azul-ardósia, ferro, couro e bronze. Arte gerada para prova do fluxo SFS; requer revisão humana de anatomia, legibilidade e estilo antes de aprovação."
	doc.manifest.name = "Sentinela v8 — folha candidata importada pelo SFS"
	doc.manifest.approvals = []
	doc.manifest.provenance = "Derivada do estudo 64×64. Uma folha candidata 6×3 foi normalizada e importada pelo SpriteSheetImporter para pulo e ataque Sul. Uma pose idle Sul foi importada como base; o sintetizador do SFS gerou idle respiratório nas oito direções. Sem aprovação humana."
	var validation: Array = doc.validate()
	if not validation.is_empty():
		fail("document validation failed: %s" % str(validation))
		return
	var sample_path := "res://samples/sentinela_artist_candidate_v8.sfs.json"
	if storage.save_document(doc, sample_path) != OK:
		fail("candidate document could not be saved")
		return
	var export_path := ProjectSettings.globalize_path("res://examples/animation_candidate_v8")
	if storage.export_all(doc, export_path) != OK:
		fail("candidate Godot resources could not be exported")
		return
	print("CANDIDATE_V8: OK — base pose, jump and attack imported by Sprite Forge; idle synthesized; S remains candidate-only")
	quit(0)

func fail(message: String) -> void:
	printerr("CANDIDATE_V8: FAIL — ", message)
	quit(1)
