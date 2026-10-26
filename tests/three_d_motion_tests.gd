extends SceneTree

const Document = preload("res://core/document.gd")
const Motion = preload("res://core/three_d_motion_capture.gd")
const Storage = preload("res://core/storage.gd")

var checks: Array[Dictionary] = []
var failed := 0

func expect(condition: bool, title: String) -> void:
	checks.append({"name": title, "passed": condition})
	if condition: print("PASS ", title)
	else:
		failed += 1
		printerr("FAIL ", title)

func remove_test_file(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var motion = Motion.new()
	var batch_fixture = Document.new()
	for clip in batch_fixture.animation.clips: clip.frames = [0]
	var batch_plan: Dictionary = motion.build_clip_batch_plan(batch_fixture, Vector2i(batch_fixture.width, batch_fixture.height), {"body": 1, "shield": 1, "sword": 1})
	expect(batch_plan.ok and int(batch_plan.clips) == batch_fixture.animation.clips.size() and batch_plan.pending_clip_indices.size() == batch_fixture.animation.clips.size() and batch_plan.completed_clip_indices.is_empty() and int(batch_plan.render_count) == batch_fixture.animation.clips.size() * 32 and int(batch_plan.new_layers) == batch_fixture.animation.clips.size() * 3, "prévia do lote calcula capturas, renders e camadas antes de alterar qualquer clip")
	var resumed_batch_fixture = Document.new()
	for clip in resumed_batch_fixture.animation.clips: clip.frames = [0]
	var resume_signatures: Dictionary = {}
	var resumed_records: Array = []
	for clip_index in resumed_batch_fixture.animation.clips.size():
		resume_signatures[str(clip_index)] = motion.capture_signature(resumed_batch_fixture, clip_index)
		for pass_name in ["body", "shield", "sword"]: resumed_records.append({"capture_mode": "modular_pass", "pass_name": pass_name, "clip_index": clip_index, "frame_indices": [0], "layer_id": str(resumed_batch_fixture.layers[0].id), "capture_signature": resume_signatures[str(clip_index)]})
	resumed_batch_fixture.art.three_d_motion_captures = resumed_records
	var resumed_plan: Dictionary = motion.build_clip_batch_plan(resumed_batch_fixture, Vector2i(resumed_batch_fixture.width, resumed_batch_fixture.height), {"body": 1, "shield": 1, "sword": 1}, resume_signatures)
	expect(resumed_plan.ok and resumed_plan.pending_clip_indices.is_empty() and resumed_plan.completed_clip_indices.size() == resumed_batch_fixture.animation.clips.size() and int(resumed_plan.render_count) == 0, "planejador identifica clips já persistidos para retomar sem recapturá-los")
	resumed_batch_fixture.palette.append("#010203")
	var changed_signatures: Dictionary = {}
	for clip_index in resumed_batch_fixture.animation.clips.size(): changed_signatures[str(clip_index)] = motion.capture_signature(resumed_batch_fixture, clip_index)
	var changed_profile_plan: Dictionary = motion.build_clip_batch_plan(resumed_batch_fixture, Vector2i(resumed_batch_fixture.width, resumed_batch_fixture.height), {"body": 1, "shield": 1, "sword": 1}, changed_signatures)
	expect(changed_profile_plan.ok and changed_profile_plan.pending_clip_indices.size() == resumed_batch_fixture.animation.clips.size(), "mudança de paleta invalida a captura antiga e agenda recaptura em vez de ignorar alterações")
	var bad_batch_fixture = Document.new()
	bad_batch_fixture.animation.clips.back().frames = [0, 1, 2, 3, 4, 5, 6, 7, 8]
	var rejected_batch: Dictionary = motion.build_clip_batch_plan(bad_batch_fixture, Vector2i(bad_batch_fixture.width, bad_batch_fixture.height), {"body": 1, "shield": 1, "sword": 1})
	expect(not rejected_batch.ok and str(rejected_batch.message).contains("Nenhum clip foi alterado"), "prévia recusa um lote inválido por inteiro antes da primeira captura")
	var orbit_8 := motion.build_turntable_angles(8)
	var orbit_16 := motion.build_turntable_angles(16)
	var orbit_32 := motion.build_turntable_angles(32)
	expect(orbit_8.ok and orbit_8.angles.size() == 8 and is_equal_approx(float(orbit_8.angles[1]), 45.0) and orbit_16.ok and orbit_16.angles.size() == 16 and is_equal_approx(float(orbit_16.angles[1]), 22.5) and orbit_32.ok and orbit_32.angles.size() == 32, "gerador de vistas oferece amostragem uniforme em 8, 16 e 32 ângulos")
	var custom_orbit := motion.build_turntable_angles(-1, "315, 22.5, 180")
	expect(custom_orbit.ok and custom_orbit.angles == [315.0, 22.5, 180.0], "turntable aceita uma ordem personalizada de ângulos fora da grade cardinal")
	expect(not motion.build_turntable_angles(-1, "0, 90, 90").ok and not motion.build_turntable_angles(-1, "360").ok and not motion.build_turntable_angles(-1, "north").ok, "lista personalizada rejeita ângulos duplicados, fora de faixa e inválidos")
	expect(motion.validate_turntable_budget(32, 8, Vector2i(64, 64)).ok and not motion.validate_turntable_budget(64, 8, Vector2i(512, 512)).ok, "orçamento multivista permite fluxos comuns e recusa alocação excessiva antes do render")
	var map_8 := motion.map_turntable_to_directions(orbit_8.angles)
	var map_16 := motion.map_turntable_to_directions(orbit_16.angles)
	var map_32 := motion.map_turntable_to_directions(orbit_32.angles)
	expect(map_8.ok and map_8.view_indices == [0, 1, 2, 3, 4, 5, 6, 7] and map_16.view_indices == [0, 2, 4, 6, 8, 10, 12, 14] and map_32.view_indices == [0, 4, 8, 12, 16, 20, 24, 28], "vistas 8/16/32 são alinhadas às oito direções canônicas sem trocar o ângulo")
	var irregular_map := motion.map_turntable_to_directions([0.0, 45.0, 89.0, 134.0, 180.0, 226.0, 270.0, 315.0, 22.5])
	expect(irregular_map.ok and irregular_map.angular_errors_degrees.size() == 8 and float(irregular_map.angular_errors_degrees[2]) == 1.0, "mapeamento customizado registra o erro angular de cada direção")
	expect(not motion.map_turntable_to_directions([0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0]).ok and not motion.map_turntable_to_directions([0.0, 0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0]).ok, "mapeamento se abstém quando faltam cobertura angular ou ângulos únicos")
	var bounded_proportions := motion.normalize_proportions({"torso_height": 2.0, "shoulder_width": 0.5, "arm_length": 1.1})
	expect(is_equal_approx(float(bounded_proportions.torso_height), 1.25) and is_equal_approx(float(bounded_proportions.shoulder_width), 0.75) and is_equal_approx(float(bounded_proportions.arm_length), 1.1) and is_equal_approx(float(bounded_proportions.leg_length), 1.0), "proporções usam defaults completos e limitam proporções fora da faixa")
	var normalized_attachments := motion.normalize_equipment_attachments({"shield": [2.0, -4.0, 0.15], "sword": [0.1, NAN, 5.0]})
	expect(is_equal_approx(float(normalized_attachments.shield[0]), 0.5) and is_equal_approx(float(normalized_attachments.shield[1]), -1.2) and is_equal_approx(float(normalized_attachments.shield[2]), 0.15) and is_equal_approx(float(normalized_attachments.sword[0]), 0.1) and is_equal_approx(float(normalized_attachments.sword[1]), -0.46) and is_equal_approx(float(normalized_attachments.sword[2]), 0.6), "pontos de encaixe são normalizados, limitados e protegem contra valores não finitos")
	for legacy_shield in motion.LEGACY_DEFAULT_SHIELD_ATTACHMENTS:
		var migrated_shield := motion.normalize_equipment_attachments({"shield": legacy_shield})
		expect(migrated_shield.shield == motion.DEFAULT_EQUIPMENT_ATTACHMENTS.shield, "o encaixe antigo de demonstração migra para o centro do antebraço e remove o quadrado projetado sem apagar offsets personalizados")
	var stance := motion.walk_pose(0.0)
	var left_contact := motion.walk_pose(0.25)
	var opposite_contact := motion.walk_pose(0.75)
	expect(is_equal_approx(float(stance.left_leg), 0.0) and float(left_contact.left_leg) > 0.0 and float(left_contact.right_leg) < 0.0 and float(opposite_contact.left_leg) < 0.0, "caminhada procedural alterna o contato entre pernas")
	expect(float(left_contact.left_knee) > 0.0 and float(opposite_contact.right_knee) > 0.0 and is_equal_approx(float(motion.walk_pose(0.0).left_elbow), 0.46), "caminhada articula cotovelos e flexiona o joelho da perna em balanço")
	var keyed := motion.build_pose_sequence({}, {"0": {"left_arm": 0.6}, "2": {"left_arm": -0.6}}, [0, 1, 2, 3], false)
	expect(keyed.size() == 4 and is_equal_approx(float(keyed[0].left_arm), 0.6) and is_zero_approx(float(keyed[1].left_arm)) and is_equal_approx(float(keyed[2].left_arm), -0.6) and is_equal_approx(float(keyed[3].left_arm), -0.6), "poses-chave interpolam pelo menor arco e mantêm a última pose em clip não cíclico")
	var looped := motion.build_pose_sequence({}, {"0": {"left_arm": 0.0}, "2": {"left_arm": 1.0}}, [0, 1, 2, 3], true)
	expect(is_zero_approx(float(looped[0].left_arm)) and is_equal_approx(float(looped[1].left_arm), 0.5) and is_equal_approx(float(looped[3].left_arm), 0.5), "poses-chave cíclicas interpolam também através do limite do loop")
	var timed := motion.build_pose_sequence({}, {"0": {"torso": 0.0}, "2": {"torso": PI / 4.0}}, [0, 1, 2], false, {"0": 50, "1": 150})
	expect(is_equal_approx(float(timed[1].torso), PI / 16.0), "interpolação 3D distribui a pose usando as durações reais do clip")
	var articulated := motion.build_pose_sequence({"left_arm": 0.2}, {"0": {"left_elbow": deg_to_rad(20.0), "left_knee": deg_to_rad(30.0)}, "2": {"left_elbow": deg_to_rad(80.0), "left_knee": deg_to_rad(90.0)}}, [0, 1, 2], false)
	expect(is_equal_approx(float(articulated[1].left_elbow), deg_to_rad(50.0)) and is_equal_approx(float(articulated[1].left_knee), deg_to_rad(60.0)), "interpolação preserva as novas articulações de cotovelo e joelho")
	var legacy_pose := motion.build_pose_sequence({"left_arm": 0.25}, {"1": {"left_arm": 0.5}}, [1], false)
	expect(is_equal_approx(float(legacy_pose[0].left_arm), 0.5) and is_zero_approx(float(legacy_pose[0].left_elbow)) and is_zero_approx(float(legacy_pose[0].right_knee)), "rigs antigos continuam carregando com novos graus de liberdade em posição neutra")
	expect(is_equal_approx(motion.clamp_joint_pose("left_knee", deg_to_rad(170.0)), deg_to_rad(135.0)) and is_zero_approx(motion.clamp_joint_pose("right_elbow", deg_to_rad(-20.0))), "limites do rig restringem flexão de joelhos e cotovelos")
	var palette: Array = ["#000000", "#ffffff"]
	var source := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	source.set_pixel(0, 0, Color(0.6, 0.6, 0.6, 1.0))
	source.set_pixel(1, 0, Color(1, 0, 0, 0.1))
	var converted: Image = motion.pixelize_capture(source, Vector2i(2, 1), palette)
	expect(not converted.is_empty() and converted.get_pixel(0, 0) == Color.WHITE and converted.get_pixel(1, 0).a == 0.0, "captura mantém transparência e quantiza deterministicamente na paleta")
	var doc = Document.new()
	doc.art.pose_approvals = [{"clip": "walk", "human": true}]
	doc.manifest.approvals = [{"human": true}]
	var original_layer_id := str(doc.layers[0].id)
	var projected_anchors: Array = []
	for direction in 8:
		var direction_anchors: Array = []
		for frame_index in doc.clip().frames.size():
			direction_anchors.append({"shield": [8 + direction, 10 + frame_index], "sword": [22 - direction, 12 + frame_index]})
		projected_anchors.append(direction_anchors)
	var captures: Array = []
	for direction in 8:
		var direction_frames: Array = []
		for frame_index in doc.clip().frames.size():
			var cel := doc.blank()
			cel.set_pixel(2 + direction, 3 + frame_index, Color.WHITE)
			direction_frames.append(cel)
		captures.append(direction_frames)
	var saved_attachments := motion.normalize_equipment_attachments({"shield": [0.2, -0.3, 0.1], "sword": [0.1, -0.4, 0.05]})
	var applied: Dictionary = motion.apply_capture(doc, int(doc.animation.active), captures, {"test_capture": true, "proportions": bounded_proportions, "equipment_attachments": saved_attachments, "attachment_anchor_positions": projected_anchors})
	expect(applied.get("ok", false) and doc.layers.size() == 2, "oito direções do clip entram como camada editável separada")
	expect(str(doc.layers[0].id) == original_layer_id and doc.layers[0].cels[0][0].get_used_rect().size == Vector2i.ZERO, "a camada original não é alterada pela importação")
	expect(doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty() and doc.art.candidate_status == "candidate", "captura invalida aprovação anterior e marca o resultado como candidato")
	var record: Dictionary = doc.art.three_d_motion_captures.back()
	expect(record.review_required and record.direction_order == Motion.DIRECTIONS and record.palette_quantized and record.proportions == bounded_proportions and record.equipment_attachments == saved_attachments, "proveniência registra direções, proporções, encaixes 3D, quantização e revisão humana pendente")
	expect(doc.anchor_at("shield_mount", 0, 0) == [8, 10] and doc.anchor_at("weapon_mount", 7, 3) == [15, 15], "a captura projeta os pontos 3D em âncoras distintas por direção/quadro para camadas 2D")
	doc.layers[0].equipment = true; doc.layers[0].anchor = "shield_mount"
	expect(doc.layer_offset(0, 0, 0) == Vector2i(8, 10), "camada de equipamento 2D usa a âncora projetada do escudo para seu offset composto")
	doc.layers[0].equipment = false; doc.layers[0].anchor = "hand"
	expect(doc.undo() and doc.layers.size() == 1 and doc.art.pose_approvals.size() == 1 and doc.anchor_at("shield_mount", 0, 0) == [8, 17], "Undo reverte camada, pixels, sockets projetados, metadados e aprovações em uma operação")
	expect(doc.redo() and doc.layers.size() == 2 and doc.art.three_d_motion_captures.size() == 1, "Redo restaura a captura e sua proveniência")
	doc.layers[1].cels[0][0].set_pixel(0, 0, Color.RED)
	var refreshed: Array = []
	for direction in 8:
		var direction_frames: Array = []
		for frame_index in doc.clip().frames.size():
			var cel := doc.blank()
			cel.set_pixel(2 + direction, 3 + frame_index, Color.BLUE)
			cel.set_pixel(1, 1, Color.GREEN)
			direction_frames.append(cel)
		refreshed.append(direction_frames)
	var updated: Dictionary = motion.apply_capture(doc, 0, refreshed)
	expect(updated.get("ok", false) and updated.get("updated_existing_layer", false) and doc.layers.size() == 2, "nova captura atualiza a layer do mesmo clip sem consumir outra layer")
	expect(doc.layers[1].cels[0][0].get_pixel(0, 0) == Color.RED and doc.layers[1].cels[0][0].get_pixel(1, 1) == Color.GREEN and int(updated.preserved_correction_pixels) == 1, "pixels corrigidos manualmente sobrevivem à atualização sobre novas referências")
	expect(int(doc.art.three_d_motion_captures[0].capture_count) == 2 and doc.art.three_d_motion_captures[0].baseline_supported, "proveniência avança a revisão e mantém a base de comparação para futuras atualizações")
	doc.art.three_d_motion_rig = {"version": 3, "rig_type": "procedural_humanoid_poc", "pose_base": {"left_arm": 0.1}, "pose_keys": {"0:1": {"left_arm": 0.5}}, "proportions": {"torso_height": 1.12, "shoulder_width": 0.92, "arm_length": 1.08, "leg_length": 1.15}, "equipment_attachments": saved_attachments}
	var storage = Storage.new()
	var roundtrip_path := "res://test_results/three_d_motion_roundtrip.sfs.json"
	remove_test_file(roundtrip_path)
	remove_test_file(roundtrip_path + ".tmp")
	remove_test_file(roundtrip_path + ".bak")
	var roundtrip_result := storage.save_document(doc, roundtrip_path)
	expect(roundtrip_result == OK, "projeto com poses/captura atualizada pode ser salvo")
	var loaded = storage.load_document(roundtrip_path)
	expect(loaded != null and loaded.art.three_d_motion_captures[0].baseline_cels[0].size() == doc.clip().frames.size() and loaded.layers[1].cels[0][0].get_pixel(0, 0) == Color.RED and loaded.art.three_d_motion_rig.pose_keys["0:1"].left_arm == 0.5 and is_equal_approx(float(loaded.art.three_d_motion_rig.proportions.leg_length), 1.15) and loaded.art.three_d_motion_rig.equipment_attachments == saved_attachments and loaded.anchor_at("shield_mount", 0, 0) == [8, 10], "save/load conserva correções 2D, poses-chave, proporções, sockets, âncoras projetadas e bases das capturas")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(roundtrip_path))
	var full_anchor_doc = Document.new()
	var legacy_anchors: Dictionary = Document.DEFAULT_ANCHORS.duplicate(true)
	legacy_anchors.erase("shield_mount"); legacy_anchors.erase("weapon_mount")
	for index in 17: legacy_anchors["legacy_%02d" % index] = [index % full_anchor_doc.width, index % full_anchor_doc.height]
	var legacy_data: Dictionary = storage.encode(full_anchor_doc)
	legacy_data["anchors"] = legacy_anchors
	var legacy_anchor_path := "res://test_results/three_d_motion_legacy_anchors.sfs.json"
	remove_test_file(legacy_anchor_path)
	remove_test_file(legacy_anchor_path + ".tmp")
	remove_test_file(legacy_anchor_path + ".bak")
	expect(storage.atomic_json(legacy_anchor_path, legacy_data) == OK, "fixture de migração com 32 âncoras antigas pode ser gravado")
	var migrated_anchors = storage.load_document(legacy_anchor_path)
	expect(migrated_anchors != null and migrated_anchors.anchors.size() == 32 and not migrated_anchors.anchors.has("shield_mount") and migrated_anchors.anchor_at("shield_mount") == [8, 17], "projetos no limite de 32 âncoras preservam o legado e recebem sockets virtuais proporcionais")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_anchor_path))
	var export_path := ProjectSettings.globalize_path("res://test_results/three_d_motion_export")
	var export_result: int = storage.export_all(doc, export_path)
	var exported_metadata: Variant = Storage.read_json(export_path.path_join("metadata.json"))
	var exported_sheet := Image.new()
	var sheet_loaded := exported_sheet.load(export_path.path_join("spritesheet.png")) == OK
	expect(export_result == OK and FileAccess.file_exists(export_path.path_join("character.tscn")) and FileAccess.file_exists(export_path.path_join("animations.tres")) and sheet_loaded, "capturas atualizadas exportam spritesheet PNG e cena/frames Godot existentes")
	expect(exported_metadata is Dictionary and exported_metadata.get("three_d_motion", {}).get("captures", []).size() == 1 and exported_metadata.get("three_d_motion", {}).get("rig", {}).get("pose_keys", {}).has("0:1"), "export JSON preserva provenance 3D, keyframes e metadados do rig")
	expect(doc.undo() and doc.layers.size() == 2 and doc.layers[1].cels[0][0].get_pixel(0, 0) == Color.RED and int(doc.art.three_d_motion_captures[0].capture_count) == 1, "Undo da atualização restaura pixels mesclados e versão anterior da captura")
	var locked = Document.new()
	locked.art.locked = true
	var refused: Dictionary = motion.apply_capture(locked, 0, captures)
	expect(not refused.get("ok", false) and locked.layers.size() == 1, "Art Lock impede captura sem alterar o documento")
	var bad_direction: Array = captures.duplicate(true)
	bad_direction.resize(7)
	var malformed: Dictionary = motion.apply_capture(Document.new(), 0, bad_direction)
	expect(not malformed.get("ok", false), "payload sem as oito direções é recusado")
	var bad_frame: Array = captures.duplicate(true)
	bad_frame[0].pop_back()
	var malformed_frames: Dictionary = motion.apply_capture(Document.new(), 0, bad_frame)
	expect(not malformed_frames.get("ok", false), "direções com quantidade de frames divergente são recusadas")
	var bad_anchor_positions: Array = projected_anchors.duplicate(true)
	bad_anchor_positions[0][0].shield = [99, 10]
	var malformed_anchors: Dictionary = motion.apply_capture(Document.new(), 0, captures, {"attachment_anchor_positions": bad_anchor_positions})
	expect(not malformed_anchors.get("ok", false), "capturas recusam âncoras projetadas fora do cel antes de iniciar a transação")
	var modular_doc = Document.new()
	modular_doc.art.pose_approvals = [{"human": true}]
	modular_doc.manifest.approvals = [{"human": true}]
	var modular_passes := {}
	for pass_name in ["body", "shield", "sword"]:
		var pass_directions: Array = []
		for direction in 8:
			var pass_frames: Array = []
			for frame_index in modular_doc.clip().frames.size():
				var cel := modular_doc.blank()
				cel.set_pixel(2 + direction, 3 + frame_index, {"body": Color.CYAN, "shield": Color.YELLOW, "sword": Color.WHITE}[pass_name])
				pass_frames.append(cel)
			pass_directions.append(pass_frames)
		modular_passes[pass_name] = pass_directions
	var modular_applied: Dictionary = motion.apply_modular_capture(modular_doc, 0, modular_passes, {"attachment_anchor_positions": projected_anchors})
	expect(modular_applied.ok and modular_doc.layers.size() == 4 and modular_doc.art.three_d_motion_captures.size() == 3, "captura modular cria Corpo, Escudo e Arma em layers distintas e sem alterar a layer original")
	expect(modular_doc.layers[1].capture_pass == "body" and modular_doc.layers[2].capture_pass == "shield" and modular_doc.layers[3].capture_pass == "sword" and modular_doc.layers[2].anchor == "shield_mount" and modular_doc.layers[3].anchor == "weapon_mount" and modular_doc.layers[2].equipment and modular_doc.layers[3].equipment, "cada passe mantém identidade semântica e socket correspondente como camada de equipamento")
	expect(modular_doc.layer_offset(2, 0, 0) == Vector2i.ZERO and modular_doc.layer_offset(3, 0, 0) == Vector2i.ZERO, "offsets locais neutralizam a âncora absoluta inicial sem deslocar os passes capturados")
	expect(modular_doc.composite(0, 0).get_pixel(2, 3) == Color.WHITE and modular_doc.anchor_at("shield_mount", 0, 0) == [8, 10], "composição raster e âncoras projetadas são preservadas após import modular")
	expect(modular_doc.undo() and modular_doc.layers.size() == 1 and modular_doc.art.pose_approvals.size() == 1 and modular_doc.art.get("three_d_motion_captures", []).is_empty(), "Undo remove os três passes juntos e restaura aprovações anteriores")
	expect(modular_doc.redo() and modular_doc.layers.size() == 4 and modular_doc.art.get("three_d_motion_captures", []).size() == 3, "Redo restaura o conjunto modular completo em uma operação")
	modular_doc.layers[2].cels[0][0].set_pixel(0, 0, Color.RED)
	modular_doc.layers[2].cels[0][0].set_pixel(1, 1, Color.GREEN)
	var shield_cell_key: String = modular_doc.cel_key(0, 0)
	var shield_offsets: Dictionary = modular_doc.rig.offsets.get(shield_cell_key, {}).duplicate(true)
	var shield_offset: Array = shield_offsets[str(modular_doc.layers[2].id)].duplicate()
	shield_offset[0] = int(shield_offset[0]) + 2
	shield_offsets[str(modular_doc.layers[2].id)] = shield_offset
	modular_doc.rig.offsets[shield_cell_key] = shield_offsets
	var revised_passes := {}
	for pass_name in ["body", "shield", "sword"]:
		var pass_directions: Array = []
		for direction in 8:
			var pass_frames: Array = []
			for frame_index in modular_doc.clip().frames.size():
				var cel := modular_doc.blank()
				cel.set_pixel(2 + direction, 3 + frame_index, Color.GREEN)
				pass_frames.append(cel)
			pass_directions.append(pass_frames)
		revised_passes[pass_name] = pass_directions
	var modular_update: Dictionary = motion.apply_modular_capture(modular_doc, 0, revised_passes, {"attachment_anchor_positions": projected_anchors})
	expect(modular_update.ok and modular_update.updated and modular_doc.layers.size() == 4 and modular_doc.layers[2].cels[0][0].get_pixel(0, 0) == Color.RED and modular_doc.layers[2].cels[0][0].get_pixel(1, 1) == Color.GREEN and modular_doc.layer_offset(2, 0, 0) == Vector2i(2, 0), "recaptura preserva retoques de pixels e deslocamento manual do equipamento ao atualizar os três passes")
	expect(modular_doc.art.three_d_motion_captures.all(func(record: Dictionary) -> bool: return int(record.capture_count) == 2 and record.baseline_supported), "proveniência por passe preserva baseline próprio para recaptura incremental")
	var modular_roundtrip_path := "res://test_results/three_d_motion_modular_roundtrip.sfs.json"
	remove_test_file(modular_roundtrip_path)
	remove_test_file(modular_roundtrip_path + ".tmp")
	remove_test_file(modular_roundtrip_path + ".bak")
	var modular_saved := storage.save_document(modular_doc, modular_roundtrip_path) == OK
	var modular_loaded = storage.load_document(modular_roundtrip_path) if modular_saved else null
	expect(modular_loaded != null and modular_loaded.layers.size() == 4 and modular_loaded.layers[2].capture_pass == "shield" and modular_loaded.layers[2].equipment and modular_loaded.layer_offset(2, 0, 0) == Vector2i(2, 0) and modular_loaded.art.three_d_motion_captures.size() == 3, "save/load preserva passes separados, offsets editados, baselines e provenance por layer")
	remove_test_file(modular_roundtrip_path)
	var modular_locked = Document.new()
	modular_locked.art.locked = true
	expect(not motion.apply_modular_capture(modular_locked, 0, modular_passes).ok and modular_locked.layers.size() == 1, "Art Lock recusa captura modular sem modificar o documento")
	var incomplete_passes := modular_passes.duplicate(true)
	incomplete_passes.erase("sword")
	expect(not motion.apply_modular_capture(Document.new(), 0, incomplete_passes).ok, "import modular recusa conjunto incompleto antes de iniciar Undo")
	var blank_equipment_passes: Dictionary = modular_passes.duplicate(true)
	var blank_doc = Document.new()
	for pass_name in ["shield", "sword"]:
		var blank_directions: Array = []
		for direction in 8:
			var blank_frames: Array = []
			for frame_index in modular_doc.clip().frames.size(): blank_frames.append(blank_doc.blank())
			blank_directions.append(blank_frames)
		blank_equipment_passes[pass_name] = blank_directions
	var empty_anchor_rows: Array = []
	for direction in 8:
		var empty_frame_anchors: Array = []
		for frame_index in modular_doc.clip().frames.size(): empty_frame_anchors.append({})
		empty_anchor_rows.append(empty_frame_anchors)
	var empty_equipment_result: Dictionary = motion.apply_modular_capture(Document.new(), 0, blank_equipment_passes, {"attachment_anchor_positions": empty_anchor_rows})
	var missing_visible_anchor_result: Dictionary = motion.apply_modular_capture(Document.new(), 0, modular_passes, {"attachment_anchor_positions": empty_anchor_rows})
	expect(empty_equipment_result.ok and not missing_visible_anchor_result.ok, "captura GLB de corpo único aceita passes de equipamento transparentes sem âncoras e exige âncoras para equipamento visível")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/three-d-motion-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("3D Motion: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
