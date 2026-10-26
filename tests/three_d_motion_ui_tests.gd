extends SceneTree

const Studio = preload("res://ui/studio.gd")
const Document = preload("res://core/document.gd")
const Capture = preload("res://core/three_d_motion_capture.gd")
const Storage = preload("res://core/storage.gd")
const ModelImporter = preload("res://core/three_d_model_importer.gd")

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

func make_test_glb() -> PackedByteArray:
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "TestBodyMesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 1.0, 0.3)
	mesh.mesh = box
	source.add_child(mesh)
	mesh.owner = source
	var animation := Animation.new()
	animation.length = 0.5
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("TestBodyMesh:position"))
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, 0.5, Vector3(0.25, 0.0, 0.0))
	var library := AnimationLibrary.new()
	library.add_animation("Walk", animation)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", library)
	source.add_child(player)
	player.owner = source
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(source, state)
	var bytes: PackedByteArray = document.generate_buffer(state) if error == OK else PackedByteArray()
	source.free()
	return bytes

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio = Studio.new()
	root.add_child(studio)
	await process_frame
	await process_frame
	var doc = Document.new()
	studio.doc = doc
	var key_pose := {"torso": 0.1, "left_arm": 0.45, "right_arm": -0.4, "left_leg": 0.2, "right_leg": -0.2}
	studio._save_3d_motion_frame_pose(key_pose, 0, 1)
	expect(doc.art.three_d_motion_rig.pose_keys.get("0:1", {}) == key_pose and doc.dirty, "a interface grava pose-chave no clip/quadro e marca o projeto como alterado")
	doc.frame = 1
	studio._three_d_pose_document = null
	studio._load_3d_motion_pose()
	var loaded_pose: Dictionary = studio.three_d_motion_panel.current_pose
	var legacy_pose_loaded := true
	for joint in key_pose: legacy_pose_loaded = legacy_pose_loaded and is_equal_approx(float(loaded_pose.get(joint, 999.0)), float(key_pose[joint]))
	expect(legacy_pose_loaded and studio.three_d_motion_panel.context_frame_index == 1 and is_zero_approx(float(loaded_pose.get("left_elbow", 999.0))), "ao retornar ao módulo, sliders carregam poses antigas e deixam articulações novas neutras")
	var panel = studio.three_d_motion_panel
	var save_recipe_connections: Array = panel.get_signal_connection_list("save_recipe_requested")
	var load_recipe_connections: Array = panel.get_signal_connection_list("load_recipe_requested")
	expect(panel.save_recipe_button != null and panel.load_recipe_button != null and save_recipe_connections.size() == 1 and load_recipe_connections.size() == 1, "ações de salvar/aplicar receita encaminham ao orquestrador do Studio")
	expect(panel.capture_all_button.text.contains("todos os clips") and not panel.cancel_capture_all_button.visible, "painel oferece ação única de lote e mantém cancelamento oculto quando ocioso")
	panel.set_batch_capture_state(true)
	var batch_controls_lock: bool = panel.capture_button.disabled and panel.capture_all_button.disabled and panel.cancel_capture_all_button.visible and not panel.cancel_capture_all_button.disabled
	panel.set_batch_capture_state(true, true)
	batch_controls_lock = batch_controls_lock and panel.cancel_capture_all_button.disabled and panel.cancel_capture_all_button.text.contains("solicitado")
	panel.set_batch_capture_state(false)
	expect(batch_controls_lock and not panel.cancel_capture_all_button.visible and not panel.capture_all_button.disabled, "estado de lote bloqueia captura concorrente e comunica cancelamento entre clips")
	var pass_counts: Dictionary = panel.get_capture_pass_counts()
	expect(int(pass_counts.body) >= 10 and int(pass_counts.shield) == 2 and int(pass_counts.sword) == 3, "manequim identifica malhas de corpo, escudo e arma para renderização em passes determinísticos")
	expect(panel.capture_button.text.contains("partes") and panel.capture_button.tooltip_text.contains("layers separadas"), "ação principal comunica captura modular e importação em camadas separadas")
	var default_passes: Dictionary = panel.get_capture_pass_assignments()
	var body_mesh_key := ""
	for key in default_passes:
		if str(default_passes[key]) == "body": body_mesh_key = str(key); break
	expect(default_passes.size() == int(pass_counts.body) + int(pass_counts.shield) + int(pass_counts.sword) and not body_mesh_key.is_empty(), "configuração de passes enumera cada mesh com uma chave hierárquica estável")
	var custom_passes: Dictionary = default_passes.duplicate(true)
	custom_passes[body_mesh_key] = "shield"
	studio._save_3d_motion_capture_passes(custom_passes)
	expect(doc.art.three_d_motion_rig.capture_pass_assignments[body_mesh_key] == "shield" and panel.get_capture_pass_counts().shield == int(pass_counts.shield) + 1 and doc.dirty, "atribuição manual de mesh a passe é salva no rig e atualiza a futura captura")
	var pass_config_path := "res://test_results/three_d_motion_capture_passes.sfs.json"
	remove_test_file(pass_config_path)
	remove_test_file(pass_config_path + ".tmp")
	remove_test_file(pass_config_path + ".bak")
	var pass_storage = Storage.new()
	var pass_saved := pass_storage.save_document(doc, pass_config_path) == OK
	var pass_loaded = pass_storage.load_document(pass_config_path) if pass_saved else null
	expect(pass_loaded != null and pass_loaded.art.three_d_motion_rig.capture_pass_assignments == panel.get_capture_pass_assignments(), "save/load preserva as atribuições configuradas para as meshes do manequim")
	remove_test_file(pass_config_path)
	expect(doc.undo() and not doc.art.get("three_d_motion_rig", {}).has("capture_pass_assignments"), "Undo restaura a configuração inicial de passes")
	studio._load_3d_motion_pose()
	expect(panel.get_capture_pass_assignments() == default_passes, "recarregar o rig recompõe as atribuições padrão após Undo")
	var empty_body_passes: Dictionary = {}
	for key in default_passes: empty_body_passes[key] = "none"
	panel.set_capture_pass_assignments(empty_body_passes)
	var empty_body_result: Dictionary = await panel.capture_sequence([0], Vector2i(32, 32), doc.palette, [{}])
	expect(not empty_body_result.get("ok", false) and str(empty_body_result.get("message", "")).contains("passe Corpo"), "captura recusa configuração sem nenhuma peça no passe Corpo antes de renderizar")
	panel.set_capture_pass_assignments(default_passes)
	doc.art.locked = true
	studio._save_3d_motion_capture_passes(custom_passes)
	expect(panel.get_capture_pass_assignments() == default_passes and not doc.art.get("three_d_motion_rig", {}).has("capture_pass_assignments"), "Art Lock recusa e restaura alterações na atribuição dos passes")
	doc.art.locked = false
	panel.configure_capture_passes_button.pressed.emit()
	await process_frame
	var pass_window: Node = panel.get_node_or_null("CapturePassAssignments")
	expect(pass_window is Window and pass_window.visible, "configurador apresenta a lista de peças em uma janela própria")
	if pass_window is Window:
		var target_control: Variant = panel.capture_pass_dialog_controls.get(body_mesh_key)
		var target_found := target_control is OptionButton
		if target_control != null:
			for index in target_control.item_count:
				if str(target_control.get_item_metadata(index)) == "none": target_control.select(index); target_control.item_selected.emit(index); break
		var apply_button: Variant = panel.capture_pass_apply_button
		var apply_found := apply_button is Button
		if apply_button != null: apply_button.pressed.emit()
		await process_frame
		expect(target_found and apply_found and panel.get_capture_pass_assignments().get(body_mesh_key) == "none" and doc.art.three_d_motion_rig.capture_pass_assignments.get(body_mesh_key) == "none", "seleção de papel na janela aplica e persiste a malha escolhida")
		if doc.art.get("three_d_motion_rig", {}).get("capture_pass_assignments", {}).get(body_mesh_key) == "none":
			doc.undo()
			studio._load_3d_motion_pose()
			expect(panel.get_capture_pass_assignments() == default_passes, "Undo da janela restaura as atribuições de captura originais")
	expect(panel.joint_sliders.size() == 9 and panel.joint_sliders.has("left_elbow") and panel.joint_sliders.has("right_knee") and panel.proportion_sliders.size() == 4, "o rig expõe controles independentes para juntas e quatro proporções do corpo")
	expect(panel.attachment_controls.size() == 6 and panel.equipment_mounts.has("shield") and panel.equipment_mounts.has("sword"), "o painel expõe sockets X/Y/Z para escudo e arma ligados aos nós reais do manequim")
	expect(panel.turntable_selector.item_count == 4 and panel.turntable_export_button != null and panel.turntable_import_button != null, "painel oferece exportação multivista e captura para as oito direções no mesmo studio")
	panel.turntable_selector.select(3)
	panel._on_turntable_mode_changed(3)
	panel.custom_angle_line.text = "0, 22.5, 135, 300"
	var selected_angles: Dictionary = panel._selected_turntable_angles()
	expect(panel.custom_angle_line.visible and selected_angles.ok and selected_angles.angles == [0.0, 22.5, 135.0, 300.0], "UI permite informar e validar ângulos customizados")
	panel.turntable_selector.select(2)
	panel._on_turntable_mode_changed(2)
	expect(not panel.custom_angle_line.visible and panel._selected_turntable_angles().angles.size() == 32, "trocar de personalizado para 32 vistas oculta a lista manual e usa amostragem uniforme")
	panel.set_proportions({"torso_height": 1.1, "shoulder_width": 1.2, "arm_length": 1.1, "leg_length": 0.9})
	expect(is_equal_approx(panel.proportion_nodes.torso_mesh.size.y, 0.792) and is_equal_approx(float(panel.joints.left_arm.scale.y), 1.1) and is_equal_approx(float(panel.joints.right_leg.scale.y), 0.9) and is_equal_approx(float(panel.joints.left_arm.position.x), -0.408), "proporções alteram dimensões do torso, separação dos ombros e comprimento real dos membros")
	panel.set_proportions({})
	panel.set_current_pose({"left_elbow": deg_to_rad(170.0), "right_knee": deg_to_rad(160.0)})
	expect(is_equal_approx(float(panel.current_pose.left_elbow), deg_to_rad(125.0)) and is_equal_approx(float(panel.current_pose.right_knee), deg_to_rad(135.0)), "controles limitam flexões a amplitudes seguras")
	var proportion_doc = Document.new()
	studio.doc = proportion_doc
	var attachments := {"shield": [0.2, -0.3, 0.25], "sword": [0.1, -0.4, 0.05]}
	panel.set_equipment_attachments(attachments)
	expect(panel.get_equipment_attachments() == attachments and panel.equipment_mounts.shield.position.is_equal_approx(Vector3(0.2, -0.3, 0.25)) and panel.equipment_mounts.sword.position.is_equal_approx(Vector3(0.1, -0.4, 0.05)), "alterar sockets atualiza em tempo real a posição 3D do equipamento acoplado")
	studio._save_3d_motion_attachments(attachments)
	expect(proportion_doc.art.three_d_motion_rig.equipment_attachments == attachments and proportion_doc.dirty, "os pontos de encaixe normalizados são persistidos no rig do projeto")
	expect(proportion_doc.undo() and not proportion_doc.art.get("three_d_motion_rig", {}).has("equipment_attachments"), "Undo restaura o rig antes da alteração dos sockets")
	studio._save_3d_motion_proportions({"torso_height": 1.12, "shoulder_width": 0.9, "arm_length": 1.08, "leg_length": 1.15})
	expect(proportion_doc.art.three_d_motion_rig.proportions == {"torso_height": 1.12, "shoulder_width": 0.9, "arm_length": 1.08, "leg_length": 1.15} and proportion_doc.dirty, "proporções são salvas no documento como uma alteração reversível")
	expect(proportion_doc.undo() and not proportion_doc.art.get("three_d_motion_rig", {}).has("proportions"), "Undo restaura o rig anterior à mudança de proporções")
	proportion_doc.art.locked = true
	panel.set_equipment_attachments({"shield": [0.4, -0.5, 0.4]})
	studio._save_3d_motion_attachments(panel.get_equipment_attachments())
	expect(not proportion_doc.art.get("three_d_motion_rig", {}).has("equipment_attachments") and panel.get_equipment_attachments() == Capture.DEFAULT_EQUIPMENT_ATTACHMENTS, "Art Lock bloqueia sockets e restaura a posição anteriormente salva")
	panel.set_proportions({"arm_length": 1.2})
	studio._save_3d_motion_proportions(panel.get_proportions())
	expect(not proportion_doc.art.get("three_d_motion_rig", {}).has("proportions") and is_equal_approx(float(panel.get_proportions().arm_length), 1.0), "Art Lock impede salvar proporções e restaura a configuração persistida")
	studio.doc = doc
	expect(doc.undo(), "pose-chave pode ser desfeita pelo histórico do documento")
	studio._three_d_pose_document = null
	studio._load_3d_motion_pose()
	expect(not doc.art.get("three_d_motion_rig", {}).get("pose_keys", {}).has("0:1") and is_zero_approx(float(studio.three_d_motion_panel.current_pose.left_arm)), "Undo remove a chave e restaura os controles à pose-base")
	studio._save_3d_motion_frame_pose(key_pose, 0, 1)
	studio._remove_3d_motion_frame_pose(0, 1)
	expect(not doc.art.three_d_motion_rig.pose_keys.has("0:1") and doc.undo(), "remover pose-chave é uma operação explícita e reversível")
	doc.art.locked = true
	var previous_revision: int = doc.revision
	studio._save_3d_motion_frame_pose(key_pose, 0, 2)
	expect(doc.revision == previous_revision and not doc.art.get("three_d_motion_rig", {}).get("pose_keys", {}).has("0:2"), "Art Lock bloqueia a gravação de pose-chave sem mutar o projeto")
	doc.art.locked = false
	panel.proportion_commit_timer.wait_time = 0.01
	panel.proportion_sliders.arm_length.value = 1.1
	for frame_step in 5: await process_frame
	expect(is_equal_approx(float(doc.art.three_d_motion_rig.proportions.arm_length), 1.1), "alterar o slider atualiza o manequim e salva proporção no documento após concluir o ajuste")
	expect(doc.undo() and not doc.art.three_d_motion_rig.has("proportions"), "o ajuste vindo do slider é uma alteração única de Undo")
	var test_glb := make_test_glb()
	var importer = ModelImporter.new()
	var imported_fixture: Dictionary = importer.load_glb(test_glb)
	expect(test_glb.size() > 20 and imported_fixture.get("ok", false) and int(imported_fixture.get("mesh_count", 0)) == 1 and int(imported_fixture.get("vertex_count", 0)) > 0, "GLB 2 sintético importa localmente com malha validada e limite de recursos")
	if imported_fixture.get("ok", false): imported_fixture.scene.free()
	var invalid_fixture: Dictionary = importer.load_glb(PackedByteArray([1, 2, 3, 4]))
	expect(not invalid_fixture.get("ok", false), "importador recusa arquivo que não tem assinatura/tamanho GLB válidos")
	doc.art.locked = true
	studio._import_3d_motion_model(test_glb, "synthetic.glb")
	expect(not doc.art.get("three_d_motion_rig", {}).has("model_asset") and panel.imported_model_sha256.is_empty(), "Art Lock impede importar o GLB antes de alterar a cena ou o projeto")
	doc.art.locked = false
	studio._import_3d_motion_model(test_glb, "synthetic.glb")
	var rig_after_import: Dictionary = doc.art.get("three_d_motion_rig", {})
	expect(not panel.imported_model_sha256.is_empty() and rig_after_import.get("model_asset", {}).get("sha256", "") == panel.imported_model_sha256 and int(panel.get_capture_pass_counts().body) == 1 and doc.dirty, "importação enquadra o modelo, classifica sua malha como Corpo e incorpora os bytes no projeto")
	var model_roundtrip_path := "res://test_results/three_d_motion_model_roundtrip.sfs.json"
	remove_test_file(model_roundtrip_path)
	remove_test_file(model_roundtrip_path + ".tmp")
	remove_test_file(model_roundtrip_path + ".bak")
	var model_saved := Storage.new().save_document(doc, model_roundtrip_path) == OK
	var model_loaded = Storage.new().load_document(model_roundtrip_path) if model_saved else null
	if model_loaded != null:
		studio.doc = model_loaded
		studio._three_d_pose_document = null
		studio._load_3d_motion_pose()
	var imported_meshes: Array = panel.imported_model_root.find_children("*", "MeshInstance3D", true, false) if is_instance_valid(panel.imported_model_root) else []
	var walk_animation: Animation = panel.imported_model_animation_player.get_animation("Walk") if is_instance_valid(panel.imported_model_animation_player) else null
	var animation_seek_ok := false
	if not imported_meshes.is_empty() and walk_animation != null:
		panel._seek_imported_animation(0, 2)
		var first_x := (imported_meshes[0] as MeshInstance3D).position.x
		panel._seek_imported_animation(1, 2)
		var last_x := (imported_meshes[0] as MeshInstance3D).position.x
		animation_seek_ok = absf(last_x - first_x) > 0.1
	expect(model_loaded != null and panel.imported_model_sha256 == doc.art.three_d_motion_rig.model_asset.sha256 and panel.imported_model_animations.has("Walk") and animation_seek_ok, "save/load recria o GLB embutido e sua animação altera a pose entre quadros")
	panel._play_imported_animation(0)
	panel._toggle_imported_animation()
	var paused_imported_animation: bool = is_instance_valid(panel.imported_model_animation_player) and not panel.imported_model_animation_player.is_playing()
	panel._toggle_imported_animation()
	expect(paused_imported_animation and panel.imported_model_animation_player.is_playing() and panel.imported_model_animation_player.current_animation == "Walk", "controle da prévia pausa e retoma a animação importada")
	if model_loaded != null:
		studio._remove_3d_motion_model()
		var removed_asset: bool = not model_loaded.art.three_d_motion_rig.has("model_asset") and panel.imported_model_sha256.is_empty()
		var removal_undo: bool = model_loaded.undo()
		studio._load_3d_motion_pose()
		expect(removed_asset and removal_undo and not panel.imported_model_sha256.is_empty(), "remover o modelo é reversível e Undo o restaura da cópia incorporada")
		var removal_redo: bool = model_loaded.redo()
		studio._load_3d_motion_pose()
		expect(removal_redo and not model_loaded.art.three_d_motion_rig.has("model_asset") and panel.imported_model_sha256.is_empty(), "Redo reaplica a remoção do modelo importado")
	remove_test_file(model_roundtrip_path)
	studio.doc = doc
	expect(doc.undo(), "importar o modelo cria uma transação reversível no documento")
	studio._three_d_pose_document = null
	studio._load_3d_motion_pose()
	expect(not doc.art.get("three_d_motion_rig", {}).has("model_asset") and panel.imported_model_sha256.is_empty(), "Undo remove o modelo GLB e restaura o manequim procedural")
	expect(doc.redo(), "Redo restaura a transação de importação do GLB")
	studio._three_d_pose_document = null
	studio._load_3d_motion_pose()
	expect(not doc.art.get("three_d_motion_rig", {}).get("model_asset", {}).get("sha256", "").is_empty() and not panel.imported_model_sha256.is_empty(), "Redo reconstrói a cena a partir dos bytes do projeto")
	var resume_doc = Document.new()
	for clip in resume_doc.animation.clips: clip.frames = [0]
	var resume_configuration: Dictionary = studio._three_d_motion_capture_configuration()
	var resume_records: Array = []
	for clip_index in resume_doc.animation.clips.size():
		var signature: String = Capture.new().capture_signature(resume_doc, clip_index, resume_configuration)
		for pass_name in ["body", "shield", "sword"]: resume_records.append({"capture_mode": "modular_pass", "pass_name": pass_name, "clip_index": clip_index, "frame_indices": [0], "layer_id": str(resume_doc.layers[0].id), "capture_signature": signature})
	resume_doc.art.three_d_motion_captures = resume_records
	studio.doc = resume_doc
	var resume_revision := int(resume_doc.revision)
	await studio._capture_all_3d_motion_clips()
	expect(int(resume_doc.revision) == resume_revision and str(panel.status_label.text).contains("Nada precisa ser recapturado"), "retomar lote reconhece os clips completos e encerra sem render nem alteração do documento")
	studio.workspace.data_root = "res://test_results/three-d-motion-checkpoint-ui"
	var checkpoint_revision: int = studio.workspace.current().doc.revision
	var checkpoint_saved: bool = await studio._persist_capture_checkpoint(checkpoint_revision)
	expect(checkpoint_saved and studio.workspace.recovery_revision(studio.workspace.active_id) >= checkpoint_revision, "lote aguarda confirmação do checkpoint antes de prosseguir")
	studio.queue_free()
	await process_frame
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/three-d-motion-ui-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("3D Motion UI: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
