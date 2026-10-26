extends SceneTree

const Storage = preload("res://core/storage.gd")
const Importer = preload("res://core/spritesheet_importer.gd")
const Synthesizer = preload("res://core/animation_synthesizer.gd")
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const CLIPS := ["idle_breathing", "jump", "attack"]
var passed := 0
var failed := 0

func expect(condition: bool, title: String) -> void:
	if condition:
		passed += 1
		print("PASS ", title)
	else:
		failed += 1
		printerr("FAIL ", title)

func _initialize() -> void:
	call_deferred("run")

func image_hash(image: Image) -> String:
	return image.get_data().hex_encode()

func run() -> void:
	var storage = Storage.new()
	var source = storage.load_document("res://samples/sentinela_scale_study.sfs.json")
	var doc = storage.load_document("res://samples/sentinela_artist_candidate_v8.sfs.json")
	if doc == null: printerr("LOAD_ERROR: ", storage.error)
	else: print("LOADED_DOC_ISSUES: ", doc.validate())
	expect(doc != null and doc.width == 64 and doc.height == 64 and doc.frames == 18 and doc.layers.size() == 1 and doc.validate().is_empty(), "candidato SFS v8 abre como documento 64×64 válido")
	if doc == null:
		finish()
		return
	expect(doc.art.candidate_status == "candidate" and doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty(), "arte importada continua candidata sem aprovações herdadas")
	expect(doc.art.get("review_scope", "") == "Generated art: South jump and attack; procedural idle across eight directions", "escopo diferencia os quadros importados do idle gerado nas oito direções")
	var non_south_actions_preserved := true
	var non_south_visible := true
	for direction in 8:
		for frame in 18:
			var cel: Image = doc.layers[0].cels[direction][frame]
			var bounds := cel.get_used_rect()
			non_south_visible = non_south_visible and bounds.size != Vector2i.ZERO and bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= 64 and bounds.end.y <= 64
			if direction != 4 and source != null and frame >= 6:
				non_south_actions_preserved = non_south_actions_preserved and cel.get_data() == source.layers[0].cels[direction][frame].get_data()
	expect(non_south_visible, "as 144 cels do documento permanecem visíveis e contidas no canvas")
	expect(non_south_actions_preserved, "pulo e ataque das sete direções não editadas preservam os pixels de origem")
	var south_hashes: Dictionary = {}
	var idle_hashes: Dictionary = {}
	var jump_hashes: Dictionary = {}
	var attack_hashes: Dictionary = {}
	var heights: Array[int] = []
	var South: Array = doc.layers[0].cels[4]
	for frame in 18:
		var bounds: Rect2i = South[frame].get_used_rect()
		heights.append(bounds.size.y)
		south_hashes[image_hash(South[frame])] = true
	for i in 6: idle_hashes[image_hash(South[i])] = true
	for i in range(6, 12): jump_hashes[image_hash(South[i])] = true
	for i in range(12, 18): attack_hashes[image_hash(South[i])] = true
	heights.sort()
	expect(south_hashes.size() == 18, "os 18 quadros da direção Sul têm poses distintas")
	expect(idle_hashes.size() == 6 and jump_hashes.size() == 6 and attack_hashes.size() == 6, "idle, pulo e ataque mantêm seis quadros cada")
	expect(heights[heights.size() / 2] >= 24 and heights[heights.size() / 2] <= 44, "silhueta mediana de Sul respeita a escala de 24–44 px")
	var breathing_stable := true
	var breathing_visible := true
	var base: Image = South[0]
	for frame in range(1, 6):
		var cel: Image = South[frame]
		var delta := 0
		for y in 64:
			for x in 64:
				if base.get_pixel(x, y) != cel.get_pixel(x, y): delta += 1
				if y >= 50: breathing_stable = breathing_stable and base.get_pixel(x, y) == cel.get_pixel(x, y)
		breathing_visible = breathing_visible and delta > 0 and delta < 550
	expect(breathing_visible, "idle respira com mudança sutil, sem cintilação do quadro inteiro")
	expect(breathing_stable, "idle preserva pixels de pés e região inferior")
	var source_sheet := Image.new()
	var source_path := ProjectSettings.globalize_path("res://examples/animation_candidate_v8/sentinela-sheet-candidate-v1.png")
	expect(source_sheet.load(source_path) == OK and source_sheet.get_width() > 1700 and source_sheet.get_height() > 850, "fonte de atlas preservada para reimportação pelo SFS")
	if source != null and source_sheet.get_width() > 0:
		var rebuilt = source.detached_copy()
		rebuilt.direction = 4
		var rebuilt_ok := true
		for row in 3:
			var clip: Dictionary = rebuilt.animation.clips[row]
			var import_result: Dictionary = Importer.import_grid_row(rebuilt, source_sheet, {"columns": 6, "source_rows": 3, "source_row": row, "fit_grid": true, "start_frame": int(clip.frames[0]), "content_scale": 0.72, "alignment": "bottom_center"})
			rebuilt_ok = rebuilt_ok and bool(import_result.get("ok", false))
			if row == 0:
				var breathing: Dictionary = Synthesizer.generate_breathing(rebuilt, 0, "idle_breathing", 2.0)
				rebuilt_ok = rebuilt_ok and bool(breathing.get("ok", false))
		for frame in 18:
			rebuilt_ok = rebuilt_ok and rebuilt.layers[0].cels[4][frame].get_data() == doc.layers[0].cels[4][frame].get_data()
		expect(rebuilt_ok, "a origem reproduz os 18 quadros no importador e sintetizador do SFS")
	else: expect(false, "fonte/variante necessária para validar reimportação determinística")
	var frames: SpriteFrames = load("res://examples/animation_candidate_v8/animations.tres")
	expect(frames != null and frames.get_animation_names().size() == 24, "recursos Godot exportam as animações em oito direções")
	if frames != null:
		var actor := AnimatedSprite2D.new()
		actor.sprite_frames = frames.duplicate(true)
		actor.speed_scale = 20.0
		root.add_child(actor)
		actor.play("idle_breathing_S")
		await create_timer(0.1).timeout
		expect(actor.is_playing(), "idle importado/sintetizado reproduz em loop na Godot")
		actor.play("jump_S")
		await create_timer(0.2).timeout
		expect(not actor.is_playing() and actor.frame == 5, "pulo importado percorre e conclui sem loop")
		actor.play("attack_S")
		await create_timer(0.2).timeout
		expect(not actor.is_playing() and actor.frame == 5, "ataque importado percorre e conclui sem loop")
		actor.queue_free()
		await process_frame
	var preview: PackedScene = load("res://examples/animation_candidate_v8/character.tscn")
	expect(preview != null and FileAccess.get_file_as_bytes("res://examples/animation_candidate_v8/S-candidate.gif").size() > 100000, "cena Godot e prévia de três ações estão disponíveis")
	finish()

func finish() -> void:
	var file := FileAccess.open("res://test_results/animation-v8-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t"))
		file.close()
	print("Animation candidate v8: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
