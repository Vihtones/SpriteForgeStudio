extends SceneTree
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const CharacterAudit = preload("res://core/character_audit.gd")
var checks: Array[Dictionary] = []
var failed := 0
var frame_changes := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value:
		print("PASS ", name)
	else:
		failed += 1
		printerr("FAIL ", name)

func _on_frame_changed() -> void:
	frame_changes += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var storage = Storage.new()
	var source := ProjectSettings.globalize_path("res://examples/animation_proof/sentinela.sfs.json")
	var export_dir := ProjectSettings.globalize_path("res://examples/animation_proof/export")
	var doc = storage.load_document(source)
	expect(doc != null, "carrega projeto SFS da sentinela")
	if doc == null:
		finish()
		return
	expect(doc.frames == 22 and doc.layers.size() == 4 and doc.validate().is_empty(), "contrato SFS válido com quatro camadas e 22 frames em 8 direções")
	expect(doc.art.get("candidate_status", "") == "rejected" and not str(doc.art.get("review_feedback", "")).is_empty(), "fixture registra a reprovação artística humana e o motivo")
	expect(doc.animation.clips.size() == 4, "quatro clips salvos no documento")
	expect(not doc.layers[0].equipment and doc.layers[1].equipment and doc.layers[2].equipment and doc.layers[3].equipment, "armadura, broquel e espada são módulos de equipamento independentes")
	var all_cels_valid := true
	for layer in doc.layers:
		for direction in 8:
			for frame_index in doc.frames:
				var cel: Image = layer.cels[direction][frame_index]
				var bounds: Rect2i = cel.get_used_rect()
				all_cels_valid = all_cels_valid and cel.get_size() == Vector2i(64, 64) and bounds.size.x > 0 and bounds.size.y > 0 and bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= 64 and bounds.end.y <= 64
	expect(all_cels_valid, "704 cels de corpo/equipamento estão não vazias e dentro da tela")
	var expected := {"idle_breathing": [4, true], "jump": [6, false], "attack": [6, false], "walk": [6, true]}
	for clip in doc.animation.clips:
		var spec: Array = expected.get(clip.name, [])
		expect(not spec.is_empty() and clip.frames.size() == spec[0] and clip.loop == spec[1], "clip %s tem frames e loop esperados" % clip.name)
		for direction in 8:
			var first: Image = doc.layers[0].cels[direction][int(clip.frames[0])]
			var changes_pixels := false
			for clip_frame in range(1, clip.frames.size()):
				var current: Image = doc.layers[0].cels[direction][int(clip.frames[clip_frame])]
				changes_pixels = changes_pixels or current.get_data() != first.get_data()
			expect(changes_pixels, "%s tem movimento visível em %s" % [clip.name, Doc.DIRECTIONS[direction]])
	var direction_views_unique := true
	for first_direction in 8:
		for second_direction in range(first_direction + 1, 8):
			var first_view: Image = doc.layers[0].cels[first_direction][0]
			var second_view: Image = doc.layers[0].cels[second_direction][0]
			direction_views_unique = direction_views_unique and first_view.get_data() != second_view.get_data()
	expect(direction_views_unique, "idle inicial preserva oito desenhos direcionais distintos")
	var original_composite: Image = doc.composite(4, 13).duplicate()
	var equipment_removal_works := true
	for layer_index in range(1, doc.layers.size()):
		doc.layers[layer_index].visible = false
		var without_component: Image = doc.composite(4, 13)
		var changed_by_component := false
		for y in 64:
			for x in 64:
				if without_component.get_pixel(x, y) != original_composite.get_pixel(x, y):
					changed_by_component = true
					break
			if changed_by_component: break
		equipment_removal_works = equipment_removal_works and changed_by_component
		doc.layers[layer_index].visible = true
	expect(equipment_removal_works, "ocultar qualquer módulo remove apenas equipamento da composição")
	var expected_sheet := Image.load_from_file(ProjectSettings.globalize_path("res://examples/animation_proof/spritesheet_source.png"))
	var composite_pixels_match := not expected_sheet.is_empty()
	var composite_pixel_errors := 0
	if composite_pixels_match:
		for direction in 8:
			for frame_index in doc.frames:
				var expected_frame: Image = expected_sheet.get_region(Rect2i(frame_index * 64, direction * 64, 64, 64))
				var built_frame: Image = doc.composite(direction, frame_index)
				for y in 64:
					for x in 64:
						var expected_color: Color = expected_frame.get_pixel(x, y)
						var built_color: Color = built_frame.get_pixel(x, y)
						var channel_error := maxf(maxf(absf(expected_color.r - built_color.r), absf(expected_color.g - built_color.g)), absf(expected_color.b - built_color.b))
						if expected_color.a != built_color.a or (expected_color.a > 0 and channel_error > 1.0 / 255.0): composite_pixel_errors += 1
	composite_pixels_match = composite_pixels_match and composite_pixel_errors == 0
	expect(composite_pixels_match, "camadas modulares recompõem as 176 poses com diferença máxima de 1 nível de canal")
	var result: Error = storage.export_all(doc, export_dir)
	expect(result == OK, "exporta spritesheet, metadados, mapa e cena Godot")
	if result != OK:
		finish()
		return
	var frames: SpriteFrames = load("res://examples/animation_proof/export/animations.tres")
	expect(frames != null and frames.get_animation_names().size() == 32, "exporta 32 combinações de clip e direção")
	if frames != null:
		for clip in ["idle_breathing", "walk", "jump", "attack"]:
			for direction in Doc.DIRECTIONS:
				var anim: String = str(clip) + "_" + direction
				expect(frames.has_animation(anim), "recurso inclui %s" % anim)
		expect(frames.get_frame_count("attack_S") == 6 and not frames.get_animation_loop("attack_S"), "ataque exporta seis frames sem loop")
		expect(frames.get_frame_count("walk_S") == 6 and frames.get_animation_loop("walk_S"), "caminhada exporta seis frames em loop")
		expect(is_equal_approx(frames.get_frame_duration("attack_S", 3), 0.09), "duração do frame de contato preservada")
	var scene: PackedScene = load("res://examples/animation_proof/export/character.tscn")
	expect(scene != null, "cena de personagem exportada pode ser carregada")
	if scene != null:
		var character: Node2D = scene.instantiate()
		var sprite: AnimatedSprite2D = character.get_node("AnimatedSprite2D")
		root.add_child(character)
		sprite.frame_changed.connect(_on_frame_changed)
		sprite.speed_scale = 1.0
		for clip_name in ["idle_breathing", "walk", "jump", "attack"]:
			for direction in Doc.DIRECTIONS:
				var directional_animation: String = clip_name + "_" + direction
				sprite.play(directional_animation)
				expect(sprite.animation == directional_animation and sprite.is_playing(), "AnimatedSprite2D aceita %s" % directional_animation)
		for anim in ["idle_breathing_S", "walk_S", "jump_S", "attack_S"]:
			sprite.frame = 0
			sprite.play(anim)
			var changes_before := frame_changes
			await create_timer(0.25).timeout
			expect(sprite.animation == anim and (sprite.is_playing() or anim != "idle_breathing_S"), "AnimatedSprite2D reproduz %s" % anim)
			expect(frame_changes > changes_before or not sprite.is_playing(), "%s avança frames ou conclui" % anim)
		expect(frame_changes >= 2, "sinal frame_changed confirma avanço durante reprodução")
		character.queue_free()
		await process_frame
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/animation_proof/export/metadata.json"))
	expect(metadata != null and metadata.animation.events.size() == 8 and metadata.animation.hitboxes.size() == 8, "export inclui contato e hitboxes nas oito direções")
	if metadata != null:
		var hitboxes_valid := true
		var hitbox_shapes: Dictionary = {}
		for direction in 8:
			var key := "%d:13" % direction
			var box: Array = metadata.animation.hitboxes.get(key, [])
			var sword: Image = doc.layers[3].cels[direction][13]
			var sword_bounds := sword.get_used_rect()
			var shape_valid := box.size() == 4
			if shape_valid:
				shape_valid = int(box[0]) == sword_bounds.position.x and int(box[1]) == sword_bounds.position.y \
					and int(box[2]) == sword_bounds.size.x and int(box[3]) == sword_bounds.size.y \
					and int(box[0]) >= 0 and int(box[1]) >= 0 and int(box[0]) + int(box[2]) <= 64 \
					and int(box[1]) + int(box[3]) <= 64 and int(box[2]) * int(box[3]) < 250
				hitbox_shapes[str(box)] = true
			hitboxes_valid = hitboxes_valid and shape_valid and metadata.animation.events.has(key)
		expect(hitboxes_valid, "hitboxes do ataque coincidem com a espada visível, cabem no canvas e mantêm evento por direção")
		expect(hitbox_shapes.size() == 8, "cada uma das oito direções exporta uma hitbox distinta")
	var character_audit = CharacterAudit.new()
	var audit_report: Dictionary = character_audit.evaluate(doc)
	expect(audit_report.technical_passed and audit_report.human_review_required and not audit_report.artistic_approval and audit_report.art_candidate_status == "rejected", "portão técnico aprova clips sem apagar a reprovação artística")
	var original_events: Dictionary = doc.animation.events.duplicate(true)
	doc.animation.events.erase("0:13")
	var missing_contact: Dictionary = character_audit.evaluate(doc)
	expect(not missing_contact.technical_passed and not missing_contact.issues.is_empty(), "portão técnico reprova contato ausente em uma direção")
	doc.animation.events = original_events
	var original_box: Array = doc.animation.hitboxes["0:13"].duplicate()
	doc.animation.hitboxes["0:13"] = [63, original_box[1], original_box[2], original_box[3]]
	var out_of_bounds: Dictionary = character_audit.evaluate(doc)
	expect(not out_of_bounds.technical_passed and not out_of_bounds.issues.is_empty(), "portão técnico reprova hitbox fora do canvas")
	doc.animation.hitboxes["0:13"] = original_box
	finish()

func finish() -> void:
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var path := "res://test_results/animation-proof-report.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Animation proof: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)









