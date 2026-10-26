extends Control
## Specialized 3D capture panel. Project mutation stays in the Studio orchestrator.
signal capture_requested
signal capture_all_requested
signal cancel_capture_all_requested
signal save_recipe_requested
signal load_recipe_requested
signal pose_base_requested(pose: Dictionary)
signal frame_pose_requested(pose: Dictionary, clip_index: int, frame_index: int)
signal frame_pose_remove_requested(clip_index: int, frame_index: int)
signal proportions_requested(proportions: Dictionary)
signal equipment_attachments_requested(attachments: Dictionary)
signal capture_passes_requested(assignments: Dictionary)
signal imported_model_requested(bytes: PackedByteArray, filename: String)
signal imported_model_removed_requested
signal imported_bone_mappings_requested(mappings: Dictionary)
signal imported_equipment_sockets_requested(sockets: Dictionary)
signal turntable_export_requested(angles: Array, output_path: String)
signal turntable_import_requested(angles: Array)

const Capture = preload("res://core/three_d_motion_capture.gd")
const ModelImporter = preload("res://core/three_d_model_importer.gd")
const ImportedBoneRig = preload("res://core/imported_bone_rig.gd")
const ImportedEquipmentSockets = preload("res://core/imported_equipment_sockets.gd")
const RigidEquipmentAsset = preload("res://core/rigid_equipment_asset.gd")
const PREVIEW_SIZE := Vector2i(256, 256)
const CAPTURE_PASS_GROUP_PREFIX := "sfs_capture_pass_"
const CAPTURE_PASSES := ["body", "shield", "sword"]
const CAPTURE_PASS_OPTIONS := {"body": "Corpo", "shield": "Escudo", "sword": "Arma", "none": "Ignorar"}

var capture_service = Capture.new()
var viewport: SubViewport
var viewport_container: SubViewportContainer
var mannequin: Node3D
var imported_model_root: Node3D
var imported_model_animation_player: AnimationPlayer
var imported_model_sha256 := ""
var imported_model_filename := ""
var imported_model_mesh_count := 0
var imported_bone_mappings: Dictionary = {}
var imported_bone_rig = ImportedBoneRig.new()
var bone_mapping_button: Button
var imported_equipment_sockets: Dictionary = {}
var imported_socket_nodes: Dictionary = {}
var imported_socket_service = ImportedEquipmentSockets.new()
var imported_socket_button: Button
var imported_model_animations := PackedStringArray()
var torso_pivot: Node3D
var joints: Dictionary = {}
var equipment_mounts: Dictionary = {}
var joint_sliders: Dictionary = {}
var proportion_sliders: Dictionary = {}
var proportion_labels: Dictionary = {}
var proportion_nodes: Dictionary = {}
var attachment_controls: Dictionary = {}
var capture_pass_assignments: Dictionary = {}
var default_capture_pass_assignments: Dictionary = {}
var capture_pass_dialog_controls: Dictionary = {}
var current_attachments: Dictionary = Capture.DEFAULT_EQUIPMENT_ATTACHMENTS.duplicate(true)
var base_pose: Dictionary = {"torso": 0.0, "left_arm": 0.0, "right_arm": 0.0, "left_elbow": 0.0, "right_elbow": 0.0, "left_leg": 0.0, "right_leg": 0.0, "left_knee": 0.0, "right_knee": 0.0}
var current_pose: Dictionary = {"torso": 0.0, "left_arm": 0.0, "right_arm": 0.0, "left_elbow": 0.0, "right_elbow": 0.0, "left_leg": 0.0, "right_leg": 0.0, "left_knee": 0.0, "right_knee": 0.0}
var current_proportions: Dictionary = {"torso_height": 1.0, "shoulder_width": 1.0, "arm_length": 1.0, "leg_length": 1.0}
var context_clip_index := 0
var context_frame_index := 0
var orbit_control: SpinBox
var capture_button: Button
var capture_all_button: Button
var cancel_capture_all_button: Button
var save_recipe_button: Button
var load_recipe_button: Button
var walk_button: Button
var status_label: Label
var context_label: Label
var walk_timer: Timer
var proportion_commit_timer: Timer
var attachment_commit_timer: Timer
var walk_phase := 0.0
var live_walk := false
var turntable_selector: OptionButton
var custom_angle_line: LineEdit
var turntable_dialog: FileDialog
var model_import_dialog: FileDialog
var turntable_export_button: Button
var turntable_import_button: Button
var configure_capture_passes_button: Button
var capture_pass_apply_button: Button
var imported_model_button: Button
var imported_model_animation_selector: OptionButton
var imported_model_play_button: Button
var remove_imported_model_button: Button
var imported_model_status: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_panel()

func _build_panel() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 10)
	add_child(margin)
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(split)
	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(preview_column)
	var heading := Label.new()
	heading.text = "MANEQUIM 3D · PRÉVIA ORTOGRÁFICA"
	heading.add_theme_font_size_override("font_size", 15)
	preview_column.add_child(heading)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 1.0
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.custom_minimum_size = Vector2(360, 360)
	preview_column.add_child(aspect)
	viewport_container = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.stretch_shrink = 1
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.name = "MotionViewport"
	viewport.size = PREVIEW_SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_container.add_child(viewport)
	_build_3d_stage()
	var preview_controls := HBoxContainer.new()
	preview_controls.add_theme_constant_override("separation", 8)
	preview_column.add_child(preview_controls)
	var orbit_label := Label.new(); orbit_label.text = "Órbita °"; preview_controls.add_child(orbit_label)
	orbit_control = SpinBox.new()
	orbit_control.min_value = 0; orbit_control.max_value = 359; orbit_control.step = 1
	orbit_control.value_changed.connect(_set_orbit)
	preview_controls.add_child(orbit_control)
	walk_button = Button.new(); walk_button.text = "Reproduzir caminhada"
	walk_button.pressed.connect(_toggle_walk)
	preview_controls.add_child(walk_button)
	var controls_scroll := ScrollContainer.new()
	controls_scroll.custom_minimum_size.x = 330
	controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(controls_scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 8)
	controls_scroll.add_child(controls)
	var rig_title := Label.new(); rig_title.text = "POSE E ARTICULAÇÕES"; rig_title.add_theme_font_size_override("font_size", 15); controls.add_child(rig_title)
	var recipe_row := HBoxContainer.new()
	save_recipe_button = Button.new(); save_recipe_button.text = "Salvar receita…"; save_recipe_button.tooltip_text = "Guarda paleta, direção de arte, clips, poses, proporções, encaixes, passes e modelo 3D para reutilizar em outro projeto compatível."; save_recipe_button.pressed.connect(func(): save_recipe_requested.emit()); recipe_row.add_child(save_recipe_button)
	load_recipe_button = Button.new(); load_recipe_button.text = "Aplicar receita…"; load_recipe_button.tooltip_text = "Aplica uma receita em uma única operação Undo. Exige canvas e quantidade de quadros compatíveis; modelos GLB são validados antes da aplicação."; load_recipe_button.pressed.connect(func(): load_recipe_requested.emit()); recipe_row.add_child(load_recipe_button)
	controls.add_child(recipe_row)
	imported_model_button = Button.new()
	imported_model_button.text = "Importar modelo 3D GLB…"
	imported_model_button.tooltip_text = "Importa um GLB autocontido de até 16 MiB para prévia e captura local. O arquivo fica incorporado ao projeto SFS."
	imported_model_button.pressed.connect(_open_model_import_dialog)
	controls.add_child(imported_model_button)
	imported_model_status = Label.new()
	imported_model_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	imported_model_status.text = "Usando o manequim procedural. Modelos GLB podem fornecer malhas e animações para captura; o rig procedural não os deforma."
	controls.add_child(imported_model_status)
	remove_imported_model_button = Button.new()
	remove_imported_model_button.text = "Voltar ao manequim procedural"
	remove_imported_model_button.visible = false
	remove_imported_model_button.pressed.connect(func(): imported_model_removed_requested.emit())
	controls.add_child(remove_imported_model_button)
	bone_mapping_button = Button.new()
	bone_mapping_button.text = "Mapear ossos para os controles SFS…"
	bone_mapping_button.visible = false
	bone_mapping_button.pressed.connect(_open_bone_mapping_dialog)
	controls.add_child(bone_mapping_button)
	imported_socket_button = Button.new()
	imported_socket_button.text = "Encaixar arma/escudo nos ossos…"
	imported_socket_button.tooltip_text = "Anexa um equipamento GLB próprio ou uma peça demonstrativa ao osso escolhido, com posição, rotação e escala locais."
	imported_socket_button.visible = false
	imported_socket_button.pressed.connect(_open_imported_socket_dialog)
	controls.add_child(imported_socket_button)
	imported_model_animation_selector = OptionButton.new()
	imported_model_animation_selector.visible = false
	imported_model_animation_selector.item_selected.connect(_on_imported_animation_selected)
	controls.add_child(imported_model_animation_selector)
	imported_model_play_button = Button.new()
	imported_model_play_button.text = "Reproduzir animação importada"
	imported_model_play_button.visible = false
	imported_model_play_button.pressed.connect(_toggle_imported_animation)
	controls.add_child(imported_model_play_button)
	var hint := Label.new()
	hint.text = "Ajuste a pose 3D no quadro indicado. Grave uma pose-chave para interpolar o movimento entre quadros ou salve-a como pose-base."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(hint)
	_add_joint_control(controls, "Torso", "torso", -25.0, 25.0)
	_add_joint_control(controls, "Braço esquerdo", "left_arm", -75.0, 75.0)
	_add_joint_control(controls, "Braço direito", "right_arm", -75.0, 75.0)
	_add_joint_control(controls, "Cotovelo esquerdo", "left_elbow", 0.0, 125.0)
	_add_joint_control(controls, "Cotovelo direito", "right_elbow", 0.0, 125.0)
	_add_joint_control(controls, "Perna esquerda", "left_leg", -65.0, 65.0)
	_add_joint_control(controls, "Perna direita", "right_leg", -65.0, 65.0)
	_add_joint_control(controls, "Joelho esquerdo", "left_knee", 0.0, 135.0)
	_add_joint_control(controls, "Joelho direito", "right_knee", 0.0, 135.0)
	var proportion_title := Label.new(); proportion_title.text = "PROPORÇÕES DO MANEQUIM"; proportion_title.add_theme_font_size_override("font_size", 14); controls.add_child(proportion_title)
	_add_proportion_control(controls, "Altura do tronco", "torso_height")
	_add_proportion_control(controls, "Largura dos ombros", "shoulder_width")
	_add_proportion_control(controls, "Comprimento dos braços", "arm_length")
	_add_proportion_control(controls, "Comprimento das pernas", "leg_length")
	var attachment_title := Label.new(); attachment_title.text = "ENCAIXES DE EQUIPAMENTO · 3D / 2D"; attachment_title.add_theme_font_size_override("font_size", 14); controls.add_child(attachment_title)
	var attachment_hint := Label.new(); attachment_hint.text = "Ajuste o socket na mão/antebraço. Capturas projetam shield_mount e weapon_mount para as camadas de equipamento 2D."; attachment_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(attachment_hint)
	_add_attachment_control(controls, "Escudo", "shield")
	_add_attachment_control(controls, "Arma", "sword")
	configure_capture_passes_button = Button.new()
	configure_capture_passes_button.text = "Configurar passes das peças…"
	configure_capture_passes_button.tooltip_text = "Atribui cada malha do manequim a Corpo, Escudo, Arma ou Ignorar. A escolha é salva no projeto e altera as próximas capturas."
	configure_capture_passes_button.pressed.connect(_open_capture_pass_dialog)
	controls.add_child(configure_capture_passes_button)
	context_label = Label.new(); context_label.text = "Quadro 1"; context_label.add_theme_color_override("font_color", Color("78d8c3")); controls.add_child(context_label)
	var save_key := Button.new(); save_key.text = "Gravar pose-chave no quadro atual"
	save_key.pressed.connect(func(): frame_pose_requested.emit(current_pose.duplicate(true), context_clip_index, context_frame_index))
	controls.add_child(save_key)
	var remove_key := Button.new(); remove_key.text = "Remover pose-chave deste quadro"
	remove_key.pressed.connect(func(): frame_pose_remove_requested.emit(context_clip_index, context_frame_index))
	controls.add_child(remove_key)
	var save_pose := Button.new(); save_pose.text = "Definir pose-base do personagem"
	save_pose.pressed.connect(func(): pose_base_requested.emit(current_pose.duplicate(true)))
	controls.add_child(save_pose)
	capture_button = Button.new()
	capture_button.text = "Capturar partes · 8 direções"
	capture_button.tooltip_text = "Renderiza oito ângulos ortográficos e importa corpo, escudo e arma como layers separadas, sincronizadas à timeline e com Undo único. As sobreposições entre partes precisam ser revisadas."
	capture_button.pressed.connect(func(): capture_requested.emit())
	controls.add_child(capture_button)
	capture_all_button = Button.new()
	capture_all_button.text = "Capturar todos os clips · lote revisável"
	capture_all_button.tooltip_text = "Verifica antes os limites de todos os clips e captura cada um nas oito direções com o mesmo rig, modelo, paleta e equipamentos. Os resultados ficam como layers candidatas; não são aprovados automaticamente."
	capture_all_button.pressed.connect(func(): capture_all_requested.emit())
	controls.add_child(capture_all_button)
	cancel_capture_all_button = Button.new()
	cancel_capture_all_button.text = "Cancelar após o clip atual"
	cancel_capture_all_button.visible = false
	cancel_capture_all_button.pressed.connect(func(): cancel_capture_all_requested.emit())
	controls.add_child(cancel_capture_all_button)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "A captura separa os passes geométricos Corpo, Escudo e Arma. Recapturas atualizam cada passe e preservam pixels corrigidos. Transparência e ordem visual exigem revisão."
	controls.add_child(status_label)
	var turntable_separator := HSeparator.new(); controls.add_child(turntable_separator)
	var turntable_title := Label.new(); turntable_title.text = "TURNTABLE MULTIVISTA"; turntable_title.add_theme_font_size_override("font_size", 14); controls.add_child(turntable_title)
	var turntable_hint := Label.new(); turntable_hint.text = "Exporte um atlas 360° separado para revisar mais ângulos sem mudar as oito direções do documento."; turntable_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(turntable_hint)
	turntable_selector = OptionButton.new()
	for item in [{"label": "8 vistas uniformes", "count": 8}, {"label": "16 vistas uniformes", "count": 16}, {"label": "32 vistas uniformes", "count": 32}, {"label": "Ângulos personalizados", "count": -1}]:
		turntable_selector.add_item(str(item.label)); turntable_selector.set_item_metadata(turntable_selector.item_count - 1, int(item.count))
	turntable_selector.item_selected.connect(_on_turntable_mode_changed)
	controls.add_child(turntable_selector)
	custom_angle_line = LineEdit.new(); custom_angle_line.placeholder_text = "Ex.: 0, 30, 90, 180, 270"; custom_angle_line.text = "0, 30, 90, 180, 270"; custom_angle_line.visible = false; controls.add_child(custom_angle_line)
	turntable_export_button = Button.new(); turntable_export_button.text = "Exportar atlas multivista…"; turntable_export_button.pressed.connect(_open_turntable_dialog); controls.add_child(turntable_export_button)
	turntable_import_button = Button.new(); turntable_import_button.text = "Usar vistas escolhidas nas 8 direções"; turntable_import_button.tooltip_text = "Captura os ângulos selecionados, escolhe a vista mais próxima para cada direção canônica, cria uma camada revisável e registra o mapeamento. Exige cobertura das oito direções."; turntable_import_button.pressed.connect(_import_selected_turntable_views); controls.add_child(turntable_import_button)
	turntable_dialog = FileDialog.new(); turntable_dialog.name = "TurntableExportDialog"; turntable_dialog.title = "Salvar atlas multivista PNG"; turntable_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE; turntable_dialog.access = FileDialog.ACCESS_FILESYSTEM; turntable_dialog.filters = PackedStringArray(["*.png ; PNG com imagens por ângulo/quadro"]); turntable_dialog.current_file = "turntable-360.png"; turntable_dialog.file_selected.connect(_on_turntable_path_selected); add_child(turntable_dialog)
	model_import_dialog = FileDialog.new(); model_import_dialog.name = "ModelImportDialog"; model_import_dialog.title = "Importar modelo GLB autocontido"; model_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; model_import_dialog.access = FileDialog.ACCESS_FILESYSTEM; model_import_dialog.filters = PackedStringArray(["*.glb ; glTF binário autocontido (máx. 16 MiB)"]); model_import_dialog.file_selected.connect(_on_model_file_selected); add_child(model_import_dialog)
	walk_timer = Timer.new(); walk_timer.wait_time = 0.08; walk_timer.timeout.connect(_advance_walk)
	add_child(walk_timer)
	proportion_commit_timer = Timer.new(); proportion_commit_timer.name = "ProportionCommitTimer"; proportion_commit_timer.one_shot = true; proportion_commit_timer.wait_time = 0.35
	proportion_commit_timer.timeout.connect(func(): proportions_requested.emit(current_proportions.duplicate(true)))
	add_child(proportion_commit_timer)
	attachment_commit_timer = Timer.new(); attachment_commit_timer.name = "AttachmentCommitTimer"; attachment_commit_timer.one_shot = true; attachment_commit_timer.wait_time = 0.35
	attachment_commit_timer.timeout.connect(func(): equipment_attachments_requested.emit(get_equipment_attachments()))
	add_child(attachment_commit_timer)

func _build_3d_stage() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5dceb")
	environment.ambient_light_energy = 0.75
	environment_node.environment = environment
	viewport.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32, -28, 0)
	light.light_energy = 1.15
	light.shadow_enabled = false
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.55
	camera.position = Vector3(0.0, 1.0, 4.5)
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	camera.current = true
	mannequin = Node3D.new()
	mannequin.name = "ProceduralHumanoid"
	viewport.add_child(mannequin)
	_build_mannequin()

func _build_mannequin() -> void:
	var body_mat := _material(Color("34496b"))
	var armor_mat := _material(Color("75b5ad"))
	var skin_mat := _material(Color("e69c69"))
	var dark_mat := _material(Color("191b32"))
	var metal_mat := _material(Color("e9d8a6"))
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new(); torso_mesh.size = Vector3(0.48, 0.72, 0.30)
	torso.mesh = torso_mesh; torso.material_override = armor_mat; torso.position = Vector3(0, 1.35, 0); _tag_capture_pass(torso, "body")
	mannequin.add_child(torso)
	var belt := MeshInstance3D.new()
	var belt_mesh := BoxMesh.new(); belt_mesh.size = Vector3(0.51, 0.11, 0.32)
	belt.mesh = belt_mesh; belt.material_override = dark_mat; belt.position = Vector3(0, 1.03, 0); _tag_capture_pass(belt, "body")
	mannequin.add_child(belt)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new(); head_mesh.radius = 0.20; head_mesh.height = 0.40; head_mesh.radial_segments = 8; head_mesh.rings = 5
	head.mesh = head_mesh; head.material_override = skin_mat; head.position = Vector3(0, 1.92, 0); _tag_capture_pass(head, "body")
	mannequin.add_child(head)
	proportion_nodes = {"torso": torso, "torso_mesh": torso_mesh, "belt": belt, "belt_mesh": belt_mesh, "head": head}
	torso_pivot = Node3D.new(); torso_pivot.name = "TorsoJoint"; torso_pivot.position = Vector3(0, 1.35, 0)
	mannequin.add_child(torso_pivot)
	joints["torso"] = torso_pivot
	var left_arm := _make_arm(-1.0, skin_mat, body_mat, metal_mat)
	var right_arm := _make_arm(1.0, skin_mat, body_mat, metal_mat)
	var left_leg := _make_leg(-1.0, body_mat, dark_mat, skin_mat)
	var right_leg := _make_leg(1.0, body_mat, dark_mat, skin_mat)
	joints["left_arm"] = left_arm; joints["right_arm"] = right_arm
	joints["left_leg"] = left_leg; joints["right_leg"] = right_leg
	_apply_proportions()
	_initialize_capture_pass_assignments()

func _make_arm(side: float, skin: Material, cloth: Material, metal: Material) -> Node3D:
	var pivot := Node3D.new(); pivot.name = "LeftShoulder" if side < 0 else "RightShoulder"
	pivot.position = Vector3(side * 0.34, 1.62, 0)
	mannequin.add_child(pivot)
	var upper := MeshInstance3D.new(); var upper_mesh := CapsuleMesh.new(); upper_mesh.radius = 0.105; upper_mesh.height = 0.48
	upper.mesh = upper_mesh; upper.material_override = cloth; upper.position = Vector3(0, -0.23, 0); _tag_capture_pass(upper, "body"); pivot.add_child(upper)
	var elbow := Node3D.new(); elbow.name = "LeftElbow" if side < 0 else "RightElbow"; elbow.position = Vector3(0, -0.44, 0); pivot.add_child(elbow)
	var lower := MeshInstance3D.new(); var lower_mesh := CapsuleMesh.new(); lower_mesh.radius = 0.09; lower_mesh.height = 0.43
	lower.mesh = lower_mesh; lower.material_override = cloth; lower.position = Vector3(0, -0.22, 0); _tag_capture_pass(lower, "body"); elbow.add_child(lower)
	var hand := MeshInstance3D.new(); var hand_mesh := SphereMesh.new(); hand_mesh.radius = 0.11; hand_mesh.height = 0.22
	hand.mesh = hand_mesh; hand.material_override = skin; hand.position = Vector3(0, -0.46, 0); _tag_capture_pass(hand, "body"); elbow.add_child(hand)
	# Modular equipment is mounted to the forearm so it follows elbow articulation.
	if side < 0:
		# A heater-shield silhouette stays identifiable when the captured view is
		# edge-on; a cylinder flattened to a few pixels looked like a stray square.
		var shield_shape := PackedVector2Array([
			Vector2(-0.13, 0.16), Vector2(-0.15, 0.035), Vector2(-0.13, -0.10),
			Vector2(0.0, -0.25), Vector2(0.13, -0.10), Vector2(0.15, 0.035), Vector2(0.13, 0.16)
		])
		# Center the shield on the forearm and let its depth intersect the arm.
		# The previous lateral offset projected as a detached square at side angles.
		var shield_mount := Node3D.new(); shield_mount.name = "ShieldMount"; shield_mount.position = Vector3(0.0, -0.22, 0.0); elbow.add_child(shield_mount)
		equipment_mounts["shield"] = shield_mount
		var shield := MeshInstance3D.new(); shield.name = "ForearmShield"
		shield.mesh = _extruded_polygon_mesh(shield_shape, 0.10)
		# Use exact Art-DNA swatches; out-of-palette leather shades became
		# unrelated pale pixels after the deterministic capture quantizer.
		shield.material_override = _material(Color("191b32")); _tag_capture_pass(shield, "shield"); shield_mount.add_child(shield)
		var face_shape := PackedVector2Array()
		for point in shield_shape: face_shape.append(point * 0.78)
		var shield_face := MeshInstance3D.new(); shield_face.name = "ShieldFace"
		shield_face.mesh = _extruded_polygon_mesh(face_shape, 0.014)
		shield_face.material_override = _material(Color("34496b")); shield_face.position = Vector3(0.0, 0.0, 0.043); _tag_capture_pass(shield_face, "shield"); shield_mount.add_child(shield_face)
	else:
		# Separate grip, guard and tapered blade make the hand visibly hold a sword
		# instead of carrying a featureless rectangular bar.
		var sword_mount := Node3D.new(); sword_mount.name = "WeaponMount"; sword_mount.position = Vector3(0.0, -0.46, 0.0); elbow.add_child(sword_mount)
		equipment_mounts["sword"] = sword_mount
		var grip := MeshInstance3D.new(); var grip_mesh := CylinderMesh.new(); grip_mesh.top_radius = 0.026; grip_mesh.bottom_radius = 0.026; grip_mesh.height = 0.18; grip_mesh.radial_segments = 6
		grip.mesh = grip_mesh; grip.material_override = _material(Color("191b32")); grip.position = Vector3(0.0, 0.0, 0.0); _tag_capture_pass(grip, "sword"); sword_mount.add_child(grip)
		var guard := MeshInstance3D.new(); var guard_mesh := BoxMesh.new(); guard_mesh.size = Vector3(0.19, 0.045, 0.055)
		guard.mesh = guard_mesh; guard.material_override = metal; guard.position = Vector3(0.0, -0.11, 0.015); _tag_capture_pass(guard, "sword"); sword_mount.add_child(guard)
		var blade_shape := PackedVector2Array([
			Vector2(-0.065, 0.0), Vector2(0.065, 0.0), Vector2(0.042, -0.28), Vector2(0.0, -0.46), Vector2(-0.042, -0.28)
		])
		var sword := MeshInstance3D.new(); sword.name = "HandheldSwordBlade"
		sword.mesh = _extruded_polygon_mesh(blade_shape, 0.028)
		sword.material_override = metal; sword.position = Vector3(0.0, -0.14, 0.015); _tag_capture_pass(sword, "sword"); sword_mount.add_child(sword)
	joints["left_elbow" if side < 0 else "right_elbow"] = elbow
	return pivot

func _extruded_polygon_mesh(points: PackedVector2Array, depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_depth := depth * 0.5
	var front_center := Vector3(0.0, 0.0, half_depth)
	var back_center := Vector3(0.0, 0.0, -half_depth)
	for index in points.size():
		var next_index := (index + 1) % points.size()
		var current_front := Vector3(points[index].x, points[index].y, half_depth)
		var next_front := Vector3(points[next_index].x, points[next_index].y, half_depth)
		var current_back := Vector3(points[index].x, points[index].y, -half_depth)
		var next_back := Vector3(points[next_index].x, points[next_index].y, -half_depth)
		# Front winding points toward the camera; reverse it for the back face.
		surface.add_vertex(front_center); surface.add_vertex(next_front); surface.add_vertex(current_front)
		surface.add_vertex(back_center); surface.add_vertex(current_back); surface.add_vertex(next_back)
		surface.add_vertex(current_front); surface.add_vertex(next_back); surface.add_vertex(current_back)
		surface.add_vertex(current_front); surface.add_vertex(next_front); surface.add_vertex(next_back)
	surface.generate_normals()
	return surface.commit()

func _make_leg(side: float, cloth: Material, boot: Material, skin: Material) -> Node3D:
	var pivot := Node3D.new(); pivot.name = "LeftHip" if side < 0 else "RightHip"
	pivot.position = Vector3(side * 0.15, 0.92, 0)
	mannequin.add_child(pivot)
	var thigh := MeshInstance3D.new(); var thigh_mesh := CapsuleMesh.new(); thigh_mesh.radius = 0.13; thigh_mesh.height = 0.52
	thigh.mesh = thigh_mesh; thigh.material_override = cloth; thigh.position = Vector3(0, -0.24, 0); _tag_capture_pass(thigh, "body"); pivot.add_child(thigh)
	var knee := Node3D.new(); knee.name = "LeftKnee" if side < 0 else "RightKnee"; knee.position = Vector3(0, -0.48, 0); pivot.add_child(knee)
	var shin := MeshInstance3D.new(); var shin_mesh := CapsuleMesh.new(); shin_mesh.radius = 0.105; shin_mesh.height = 0.43
	shin.mesh = shin_mesh; shin.material_override = skin; shin.position = Vector3(0, -0.22, 0); _tag_capture_pass(shin, "body"); knee.add_child(shin)
	var foot := MeshInstance3D.new(); var foot_mesh := BoxMesh.new(); foot_mesh.size = Vector3(0.24, 0.13, 0.34)
	foot.mesh = foot_mesh; foot.material_override = boot; foot.position = Vector3(0, -0.45, 0.08); _tag_capture_pass(foot, "body"); knee.add_child(foot)
	joints["left_knee" if side < 0 else "right_knee"] = knee
	return pivot

func _tag_capture_pass(mesh: MeshInstance3D, pass_name: String) -> void:
	mesh.add_to_group(CAPTURE_PASS_GROUP_PREFIX + pass_name)
	mesh.set_meta("sfs_procedural_mesh", true)

func _initialize_capture_pass_assignments(previous: Dictionary = {}) -> void:
	default_capture_pass_assignments.clear()
	for mesh in _capture_meshes():
		var assigned := "none"
		if mesh.is_in_group("sfs_imported_model_mesh"):
			assigned = "body"
		for pass_name in CAPTURE_PASSES:
			if mesh.is_in_group(CAPTURE_PASS_GROUP_PREFIX + pass_name):
				assigned = pass_name
				break
		var mesh_path := str(mannequin.get_path_to(mesh))
		mesh.set_meta("sfs_capture_pass_key", mesh_path)
		default_capture_pass_assignments[mesh_path] = str(previous.get(mesh_path, assigned))
	capture_pass_assignments = default_capture_pass_assignments.duplicate(true)

func set_capture_pass_assignments(values: Dictionary) -> void:
	capture_pass_assignments = normalize_capture_pass_assignments(values)

func normalize_capture_pass_assignments(values: Dictionary) -> Dictionary:
	var normalized := default_capture_pass_assignments.duplicate(true)
	for mesh_path in normalized:
		var role := str(values.get(mesh_path, normalized[mesh_path]))
		if CAPTURE_PASS_OPTIONS.has(role): normalized[mesh_path] = role
	return normalized

func get_capture_pass_assignments() -> Dictionary:
	return capture_pass_assignments.duplicate(true)

func _open_capture_pass_dialog() -> void:
	var window := Window.new()
	window.name = "CapturePassAssignments"
	window.title = "Atribuir malhas aos passes de captura"
	window.size = Vector2i(540, 600)
	window.min_size = Vector2i(440, 360)
	window.exclusive = true
	window.transient = true
	add_child(window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	window.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)
	var hint := Label.new()
	hint.text = "A atribuição é explícita por malha. 'Ignorar' remove a peça dos passes exportados, mas ela continua visível na prévia 3D."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 5)
	scroll.add_child(rows)
	var draft := get_capture_pass_assignments()
	var controls_by_key: Dictionary = {}
	capture_pass_dialog_controls = controls_by_key
	var paths: Array = draft.keys()
	paths.sort()
	for mesh_path in paths:
		var key := str(mesh_path)
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := Label.new()
		label.text = key.get_file()
		label.tooltip_text = key
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var option := OptionButton.new()
		option.set_meta("sfs_capture_mesh_key", key)
		for role in CAPTURE_PASS_OPTIONS:
			option.add_item(str(CAPTURE_PASS_OPTIONS[role]))
			option.set_item_metadata(option.item_count - 1, role)
		for item_index in option.item_count:
			if str(option.get_item_metadata(item_index)) == str(draft[key]):
				option.select(item_index)
				break
		option.item_selected.connect(_on_capture_pass_role_selected.bind(key, option, draft))
		row.add_child(option)
		controls_by_key[key] = option
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	var reset := Button.new()
	reset.text = "Restaurar padrão"
	footer.add_child(reset)
	reset.pressed.connect(func() -> void:
		draft.clear()
		for key in default_capture_pass_assignments: draft[key] = default_capture_pass_assignments[key]
		for key in controls_by_key:
			var option: OptionButton = controls_by_key[key]
			for index in option.item_count:
				if str(option.get_item_metadata(index)) == str(draft[key]):
					option.select(index)
					break
	)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	footer.add_child(cancel)
	var apply := Button.new()
	apply.text = "Aplicar"
	footer.add_child(apply)
	capture_pass_apply_button = apply
	apply.pressed.connect(func() -> void:
		capture_passes_requested.emit(draft.duplicate(true))
		window.queue_free()
	)
	cancel.pressed.connect(window.queue_free)
	window.close_requested.connect(window.queue_free)
	window.popup_centered()

func _on_capture_pass_role_selected(item_index: int, mesh_key: String, option: OptionButton, draft: Dictionary) -> void:
	if item_index < 0 or item_index >= option.item_count: return
	draft[mesh_key] = str(option.get_item_metadata(item_index))

func _open_model_import_dialog() -> void:
	if is_instance_valid(model_import_dialog): model_import_dialog.popup_centered_ratio(0.72)

func _on_model_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		set_status("Não foi possível abrir o modelo selecionado.")
		return
	if file.get_length() < 20 or file.get_length() > ModelImporter.MAX_GLB_BYTES:
		file.close()
		set_status("O GLB precisa ter entre 20 bytes e 16 MiB.")
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	imported_model_requested.emit(bytes, path.get_file())

func load_imported_model(bytes: PackedByteArray, filename: String, assignments: Dictionary = {}) -> Dictionary:
	var imported: Dictionary = ModelImporter.new().load_glb(bytes)
	if not imported.get("ok", false): return imported
	var scene: Node = imported.scene
	if not scene is Node3D:
		scene.free()
		return {"ok": false, "message": "A raiz do modelo GLB precisa ser Node3D."}
	if str(imported.sha256) == imported_model_sha256 and is_instance_valid(imported_model_root):
		scene.free()
		set_capture_pass_assignments(assignments)
		return {"ok": true, "sha256": imported_model_sha256, "mesh_count": imported.mesh_count, "vertex_count": imported.vertex_count, "animation_names": imported_model_animations, "capture_pass_assignments": get_capture_pass_assignments()}
	var bounds := _measure_model_bounds(scene, Transform3D.IDENTITY)
	if bounds.size.y <= 0.0001:
		scene.free()
		return {"ok": false, "message": "Não foi possível calcular a altura do modelo GLB."}
	var previous := get_capture_pass_assignments()
	imported_bone_mappings = {}
	imported_equipment_sockets = {}
	imported_socket_nodes = {}
	if is_instance_valid(imported_model_root):
		mannequin.remove_child(imported_model_root)
		imported_model_root.free()
	imported_model_root = Node3D.new()
	imported_model_root.name = "ImportedModel"
	mannequin.add_child(imported_model_root)
	imported_model_root.add_child(scene)
	var fit_scale := 1.8 / bounds.size.y
	imported_model_root.scale = Vector3.ONE * fit_scale
	var center := bounds.position + bounds.size * 0.5
	imported_model_root.position = Vector3(-center.x, -bounds.position.y, -center.z) * fit_scale
	for mesh in _capture_meshes():
		if mesh.has_meta("sfs_procedural_mesh"): mesh.visible = false
		elif imported_model_root.is_ancestor_of(mesh): mesh.add_to_group("sfs_imported_model_mesh")
	imported_model_sha256 = str(imported.sha256)
	imported_model_filename = filename
	imported_model_mesh_count = int(imported.mesh_count)
	imported_model_animation_player = _find_imported_animation_player()
	imported_model_animations.clear()
	if is_instance_valid(imported_model_animation_player):
		for animation_name in imported_model_animation_player.get_animation_list():
			if animation_name not in ["RESET", "__default"]: imported_model_animations.append(animation_name)
	_initialize_capture_pass_assignments(assignments if not assignments.is_empty() else previous)
	set_capture_pass_assignments(assignments if not assignments.is_empty() else previous)
	_refresh_imported_model_ui()
	set_status("Modelo %s carregado: %d malhas, %d vértices. Atribua as partes nos passes e revise cada captura." % [filename, imported.mesh_count, imported.vertex_count])
	return {"ok": true, "sha256": imported_model_sha256, "mesh_count": imported.mesh_count, "vertex_count": imported.vertex_count, "animation_names": imported_model_animations, "capture_pass_assignments": get_capture_pass_assignments()}

func clear_imported_model() -> void:
	imported_bone_mappings = {}
	imported_equipment_sockets = {}
	imported_socket_nodes = {}
	if is_instance_valid(imported_model_root):
		mannequin.remove_child(imported_model_root)
		imported_model_root.free()
	imported_model_root = null
	imported_model_animation_player = null
	imported_model_sha256 = ""
	imported_model_filename = ""
	imported_model_mesh_count = 0
	imported_model_animations = PackedStringArray()
	for mesh in _capture_meshes():
		if mesh.has_meta("sfs_procedural_mesh"): mesh.visible = true
	_initialize_capture_pass_assignments()
	_refresh_imported_model_ui()

func _measure_model_bounds(node: Node, parent_transform: Transform3D) -> AABB:
	var local_transform := parent_transform
	if node is Node3D: local_transform = parent_transform * node.transform
	var result := AABB()
	var has_bounds := false
	if node is MeshInstance3D and node.mesh != null:
		result = local_transform * node.get_aabb()
		has_bounds = true
	for child in node.get_children():
		var child_bounds := _measure_model_bounds(child, local_transform)
		if child_bounds.size != Vector3.ZERO:
			result = result.merge(child_bounds) if has_bounds else child_bounds
			has_bounds = true
	return result if has_bounds else AABB()

func _find_imported_animation_player() -> AnimationPlayer:
	if not is_instance_valid(imported_model_root): return null
	var players := imported_model_root.find_children("*", "AnimationPlayer", true, false)
	for player in players:
		if player is AnimationPlayer and not player.get_animation_list().is_empty(): return player
	return players[0] if not players.is_empty() else null

func _refresh_imported_model_ui() -> void:
	if not is_instance_valid(imported_model_status) or not is_instance_valid(imported_model_animation_selector): return
	imported_model_status.text = "Modelo: %s · %d malhas · %d animações" % [imported_model_filename, imported_model_mesh_count, imported_model_animations.size()] if not imported_model_sha256.is_empty() else "Usando o manequim procedural. Modelos GLB podem fornecer malhas e animações para captura; o rig procedural não os deforma."
	remove_imported_model_button.visible = not imported_model_sha256.is_empty()
	bone_mapping_button.visible = not imported_model_sha256.is_empty()
	bone_mapping_button.disabled = imported_bone_rig.bones(imported_model_root).is_empty()
	imported_socket_button.visible = not imported_model_sha256.is_empty()
	imported_socket_button.disabled = bone_mapping_button.disabled
	imported_model_animation_selector.clear()
	for animation_name in imported_model_animations: imported_model_animation_selector.add_item(animation_name)
	imported_model_animation_selector.visible = not imported_model_animations.is_empty()
	imported_model_play_button.visible = not imported_model_animations.is_empty()
	imported_model_animation_selector.disabled = not imported_bone_mappings.is_empty()
	imported_model_play_button.disabled = not imported_bone_mappings.is_empty()
	if not imported_model_animations.is_empty():
		imported_model_animation_selector.select(0)
		_play_imported_animation(0)
	else:
		imported_model_animation_player = null

func _on_imported_animation_selected(index: int) -> void:
	_play_imported_animation(index)

func _play_imported_animation(index: int) -> void:
	if not imported_bone_mappings.is_empty(): return
	if not is_instance_valid(imported_model_animation_player) or index < 0 or index >= imported_model_animation_selector.item_count: return
	var animation_name := str(imported_model_animation_selector.get_item_text(index))
	imported_model_animation_player.play(animation_name)
	imported_model_animation_player.advance(0.0)
	if is_instance_valid(imported_model_play_button): imported_model_play_button.text = "Pausar animação importada"

func _toggle_imported_animation() -> void:
	if not imported_bone_mappings.is_empty(): return
	if not is_instance_valid(imported_model_animation_player): return
	if imported_model_animation_player.is_playing():
		imported_model_animation_player.pause()
		imported_model_play_button.text = "Retomar animação importada"
	else:
		if imported_model_animation_selector.selected < 0: return
		var animation_name := str(imported_model_animation_selector.get_item_text(imported_model_animation_selector.selected))
		var resume_position := imported_model_animation_player.current_animation_position if imported_model_animation_player.current_animation == animation_name else 0.0
		imported_model_animation_player.play(animation_name)
		if resume_position > 0.0: imported_model_animation_player.seek(resume_position, true)
		imported_model_play_button.text = "Pausar animação importada"

func imported_model_asset() -> Dictionary:
	var sockets := imported_equipment_sockets.duplicate(true)
	for entry in sockets.values():
		if entry.has("asset"): entry.asset = RigidEquipmentAsset.provenance(entry.asset)
	var selected_animation := ""
	if is_instance_valid(imported_model_animation_selector) and imported_model_animation_selector.selected >= 0 and imported_model_animation_selector.selected < imported_model_animation_selector.item_count:
		selected_animation = imported_model_animation_selector.get_item_text(imported_model_animation_selector.selected)
	return {"sha256": imported_model_sha256, "filename": imported_model_filename, "animations": imported_model_animations.duplicate(), "selected_animation": selected_animation, "bone_mappings": imported_bone_mappings.duplicate(true), "equipment_sockets": sockets}

func set_imported_equipment_sockets(sockets: Dictionary) -> Dictionary:
	var checked: Dictionary = imported_socket_service.validate(imported_model_root, sockets)
	if not checked.ok: return checked
	if checked.sockets == imported_equipment_sockets and imported_socket_nodes.values().all(func(value: Dictionary) -> bool: return is_instance_valid(value.get("attachment"))): return checked
	for equipment in checked.sockets:
		if not is_instance_valid(equipment_mounts.get(equipment)): return {"ok": false, "message": "Peça demonstrativa indisponível."}
	var prepared_templates: Dictionary = {}
	for equipment in checked.sockets:
		if not checked.sockets[equipment].has("asset"): continue
		var prepared: Dictionary = RigidEquipmentAsset.new().load_asset(checked.sockets[equipment].asset)
		if not prepared.get("ok", false):
			for template in prepared_templates.values(): template.free()
			return prepared
		prepared_templates[equipment] = prepared.template
	var previous := get_capture_pass_assignments()
	for value in imported_socket_nodes.values():
		var node: Node = value.get("attachment")
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()
	imported_socket_nodes = {}
	imported_equipment_sockets = checked.sockets.duplicate(true)
	for equipment in imported_equipment_sockets:
		var attached: Dictionary = imported_socket_service.attach(imported_model_root, equipment, imported_equipment_sockets[equipment], prepared_templates.get(equipment, equipment_mounts[equipment]))
		if prepared_templates.has(equipment): prepared_templates[equipment].free()
		if not attached.ok: return attached
		imported_socket_nodes[equipment] = attached
	_initialize_capture_pass_assignments(previous)
	return checked

func _open_imported_socket_dialog() -> void:
	var choices: Array[Dictionary] = imported_bone_rig.bones(imported_model_root)
	if choices.is_empty(): return
	var window := Window.new()
	window.name = "ImportedEquipmentSockets"
	window.title = "Equipamentos GLB · encaixes nos ossos"
	window.size = Vector2i(620, 650)
	window.transient = true
	window.exclusive = true
	add_child(window)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(layout)
	var hint := Label.new()
	hint.text = "Escolha um osso e importe um GLB rígido de até 4 MiB ou use a peça demonstrativa. Posição, rotação e escala são locais ao osso. Sem vínculo remove a peça."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sections)
	var controls: Dictionary = {}
	var draft_assets: Dictionary = {}
	for equipment in ["shield", "sword"]:
		var label := Label.new()
		label.text = "Escudo" if equipment == "shield" else "Arma"
		sections.add_child(label)
		var selector := OptionButton.new()
		selector.name = "SocketBone_" + equipment
		selector.add_item("Sem vínculo")
		for entry in choices: selector.add_item(str(entry.skeleton) + " / " + str(entry.bone))
		var config: Dictionary = imported_equipment_sockets.get(equipment, {})
		for index in choices.size():
			if str(config.get("skeleton", "")) == str(choices[index].skeleton) and str(config.get("bone", "")) == str(choices[index].bone): selector.select(index + 1)
		sections.add_child(selector)
		controls[equipment] = {"bone": selector}
		var asset: Dictionary = config.get("asset", {})
		if not asset.is_empty(): draft_assets[equipment] = asset.duplicate(true)
		var asset_label := Label.new()
		asset_label.name = "SocketAsset_" + equipment
		asset_label.text = str(asset.get("filename", "Peça demonstrativa do estúdio"))
		asset_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sections.add_child(asset_label)
		var source_field := LineEdit.new()
		source_field.name = "SocketSource_" + equipment
		source_field.placeholder_text = "Origem declarada do equipamento"
		source_field.text = str(asset.get("source", "Arquivo local do usuário"))
		sections.add_child(source_field)
		var license_field := LineEdit.new()
		license_field.name = "SocketLicense_" + equipment
		license_field.placeholder_text = "Licença declarada (sem aprovação automática)"
		license_field.text = str(asset.get("license", "Não informada"))
		sections.add_child(license_field)
		controls[equipment].source = source_field
		controls[equipment].license = license_field
		var import_button := Button.new()
		import_button.name = "ImportEquipment_" + equipment
		import_button.text = "Importar equipamento GLB…"
		import_button.pressed.connect(_open_equipment_glb_dialog.bind(equipment, asset_label, draft_assets, source_field, license_field, window))
		sections.add_child(import_button)
		var demo_button := Button.new()
		demo_button.text = "Usar peça demonstrativa"
		demo_button.pressed.connect(_use_demo_equipment.bind(equipment, asset_label, draft_assets))
		sections.add_child(demo_button)
		for property in ["offset", "rotation_degrees"]:
			var row := HBoxContainer.new()
			sections.add_child(row)
			var title := Label.new()
			title.text = "Posição XYZ" if property == "offset" else "Rotação XYZ °"
			row.add_child(title)
			var components: Array = []
			var values: Array = config.get(property, [0, 0, 0])
			for axis in 3:
				var spin := SpinBox.new()
				spin.min_value = -10 if property == "offset" else -360
				spin.max_value = -spin.min_value
				spin.step = 0.01 if property == "offset" else 1.0
				spin.value = float(values[axis])
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(spin)
				components.append(spin)
			controls[equipment][property] = components
		var scale_control := SpinBox.new()
		scale_control.name = "SocketScale_" + equipment
		scale_control.prefix = "Escala "
		scale_control.min_value = 0.01
		scale_control.max_value = 10.0
		scale_control.step = 0.01
		scale_control.value = float(config.get("scale", 1.0))
		sections.add_child(scale_control)
		controls[equipment].scale = scale_control
	var apply := Button.new()
	apply.text = "Aplicar encaixes"
	layout.add_child(apply)
	apply.pressed.connect(func():
		var draft: Dictionary = {}
		for equipment in controls:
			var index: int = controls[equipment].bone.selected - 1
			if index < 0: continue
			draft[equipment] = choices[index].duplicate(true)
			for property in ["offset", "rotation_degrees"]:
				var values: Array = []
				for spin in controls[equipment][property]: values.append(float(spin.value))
				draft[equipment][property] = values
			draft[equipment].scale = float(controls[equipment].scale.value)
			if draft_assets.has(equipment):
				draft[equipment].asset = draft_assets[equipment].duplicate(true)
				draft[equipment].asset.source = str(controls[equipment].source.text)
				draft[equipment].asset.license = str(controls[equipment].license.text)
		imported_equipment_sockets_requested.emit(draft)
		window.queue_free()
	)
	window.close_requested.connect(window.queue_free)
	window.popup_centered()

func _use_demo_equipment(equipment: String, label: Label, drafts: Dictionary) -> void:
	drafts.erase(equipment)
	label.text = "Peça demonstrativa do estúdio"

func _open_equipment_glb_dialog(equipment: String, label: Label, drafts: Dictionary, source: LineEdit, license_field: LineEdit, parent_window: Window) -> void:
	var dialog := FileDialog.new()
	dialog.name = "EquipmentGLBImport"
	dialog.title = "Importar equipamento rígido GLB"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.glb ; Equipamento GLB rígido (até 4 MiB)"])
	parent_window.add_child(dialog)
	dialog.file_selected.connect(_on_equipment_glb_file.bind(equipment, label, drafts, source, license_field, dialog))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.8)

func _on_equipment_glb_file(path: String, equipment: String, label: Label, drafts: Dictionary, source: LineEdit, license_field: LineEdit, dialog: FileDialog) -> void:
	dialog.queue_free()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		label.text = "Não foi possível abrir o equipamento."
		return
	if file.get_length() > RigidEquipmentAsset.MAX_BYTES:
		file.close()
		label.text = "Equipamento excede o limite de 4 MiB."
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var prepared: Dictionary = RigidEquipmentAsset.new().prepare(bytes, path.get_file(), source.text, license_field.text)
	if not prepared.get("ok", false):
		label.text = str(prepared.get("message", "Equipamento inválido."))
		return
	prepared.template.free()
	drafts[equipment] = prepared.asset
	label.text = str(prepared.asset.filename) + " · pronto para aplicar no osso selecionado"

func set_imported_bone_mappings(mappings: Dictionary) -> Dictionary:
	var checked: Dictionary = imported_bone_rig.validate(imported_model_root, mappings)
	if not checked.ok: return checked
	imported_bone_rig.reset(imported_model_root, imported_bone_mappings)
	imported_bone_mappings = checked.mappings.duplicate(true)
	if not imported_bone_mappings.is_empty():
		if is_instance_valid(imported_model_animation_player): imported_model_animation_player.pause()
		imported_bone_rig.reset_model_pose(imported_model_root)
	imported_model_animation_selector.disabled = not imported_bone_mappings.is_empty()
	imported_model_play_button.disabled = not imported_bone_mappings.is_empty()
	bone_mapping_button.text = "Mapear ossos para os controles SFS… (%d vínculos)" % imported_bone_mappings.size()
	_update_pose(walk_phase if live_walk else -1.0)
	return checked

func _open_bone_mapping_dialog() -> void:
	var choices: Array[Dictionary] = imported_bone_rig.bones(imported_model_root)
	if choices.is_empty():
		set_status("Este GLB não contém Skeleton3D. Importe um modelo com esqueleto para editar seus ossos.")
		return
	var window := Window.new()
	window.name = "ImportedBoneMapping"
	window.title = "Vincular articulações SFS aos ossos GLB"
	window.size = Vector2i(700, 610)
	window.transient = true
	window.exclusive = true
	add_child(window)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(layout)
	var hint := Label.new()
	hint.text = "Selecione um osso e seu eixo local por articulação. Os controles usam a pose de repouso; vínculos ativos pausam a animação GLB. Limpar todos devolve o controle à animação importada."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var selectors: Dictionary = {}
	var joint_labels := {"torso": "Tronco", "left_arm": "Braço esquerdo", "right_arm": "Braço direito", "left_elbow": "Cotovelo esquerdo", "right_elbow": "Cotovelo direito", "left_leg": "Perna esquerda", "right_leg": "Perna direita", "left_knee": "Joelho esquerdo", "right_knee": "Joelho direito"}
	for joint in Capture.JOINTS:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := Label.new()
		label.text = joint_labels[joint]
		label.custom_minimum_size.x = 115
		row.add_child(label)
		var bones_selector := OptionButton.new()
		bones_selector.name = "Bone_" + joint
		bones_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bones_selector.add_item("Sem vínculo")
		for entry in choices: bones_selector.add_item(str(entry.skeleton) + " / " + str(entry.bone))
		var axes_selector := OptionButton.new()
		axes_selector.name = "Axis_" + joint
		for axis in ImportedBoneRig.AXES: axes_selector.add_item(axis)
		var current: Dictionary = imported_bone_mappings.get(joint, {})
		for index in choices.size():
			if str(current.get("skeleton", "")) == str(choices[index].skeleton) and str(current.get("bone", "")) == str(choices[index].bone): bones_selector.select(index + 1)
		for index in axes_selector.item_count:
			if axes_selector.get_item_text(index) == str(current.get("axis", "X")): axes_selector.select(index)
		row.add_child(bones_selector)
		row.add_child(axes_selector)
		selectors[joint] = {"bone": bones_selector, "axis": axes_selector}
	var apply := Button.new()
	apply.text = "Aplicar vínculos"
	layout.add_child(apply)
	apply.pressed.connect(func():
		var draft: Dictionary = {}
		for joint in selectors:
			var index: int = selectors[joint].bone.selected - 1
			if index >= 0:
				draft[joint] = choices[index].duplicate(true)
				draft[joint].axis = selectors[joint].axis.get_item_text(selectors[joint].axis.selected)
		imported_bone_mappings_requested.emit(draft)
		window.queue_free()
	)
	window.close_requested.connect(window.queue_free)
	window.popup_centered()

func get_capture_pass_counts() -> Dictionary:
	var counts := {"body": 0, "shield": 0, "sword": 0}
	for mesh in _capture_meshes():
		if not imported_model_sha256.is_empty() and not imported_model_root.is_ancestor_of(mesh): continue
		var key := str(mesh.get_meta("sfs_capture_pass_key", ""))
		var role: String = str(capture_pass_assignments.get(key, "body"))
		if counts.has(str(role)): counts[str(role)] = int(counts[str(role)]) + 1
	return counts

func _capture_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if not is_instance_valid(mannequin): return meshes
	var pending: Array[Node] = [mannequin]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D: meshes.append(node)
		for child in node.get_children(): pending.append(child)
	return meshes

func _set_capture_pass(pass_name: String) -> Dictionary:
	var visibility: Dictionary = {}
	for mesh in _capture_meshes():
		visibility[mesh.get_instance_id()] = mesh.visible
		var key := str(mesh.get_meta("sfs_capture_pass_key", ""))
		var hidden_procedural := not imported_model_sha256.is_empty() and bool(mesh.get_meta("sfs_procedural_mesh", false))
		mesh.visible = not hidden_procedural and str(capture_pass_assignments.get(key, "body")) == pass_name
	return visibility

func _restore_capture_pass(visibility: Dictionary = {}) -> void:
	for mesh in _capture_meshes():
		var instance_id := mesh.get_instance_id()
		mesh.visible = bool(visibility.get(instance_id, true))

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	return material

func _add_joint_control(parent: VBoxContainer, title: String, joint: String, minimum: float, maximum: float) -> void:
	var row := VBoxContainer.new(); parent.add_child(row)
	var heading := Label.new(); heading.text = title; row.add_child(heading)
	var slider := HSlider.new()
	slider.min_value = minimum; slider.max_value = maximum; slider.step = 1.0; slider.value = 0.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(degrees: float):
		current_pose[joint] = deg_to_rad(degrees)
		_update_pose(walk_phase if live_walk else -1.0)
	)
	row.add_child(slider)
	joint_sliders[joint] = slider

func _add_proportion_control(parent: VBoxContainer, title: String, property: String) -> void:
	var row := VBoxContainer.new(); parent.add_child(row)
	var header := HBoxContainer.new(); row.add_child(header)
	var heading := Label.new(); heading.text = title; heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(heading)
	var value_label := Label.new(); value_label.text = "100%"; value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; header.add_child(value_label)
	var slider := HSlider.new(); slider.min_value = 0.75; slider.max_value = 1.25; slider.step = 0.01; slider.value = 1.0; slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float):
		current_proportions[property] = value
		value_label.text = "%d%%" % roundi(value * 100.0)
		_apply_proportions()
		if is_instance_valid(proportion_commit_timer): proportion_commit_timer.start()
	)
	row.add_child(slider)
	proportion_sliders[property] = slider
	proportion_labels[property] = value_label

func _add_attachment_control(parent: VBoxContainer, title: String, equipment_name: String) -> void:
	var section := VBoxContainer.new(); parent.add_child(section)
	var heading := Label.new(); heading.text = title; section.add_child(heading)
	var axis_row := HBoxContainer.new(); section.add_child(axis_row)
	for axis in 3:
		var axis_name: String = ["X", "Y", "Z"][axis]
		var axis_column := VBoxContainer.new(); axis_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; axis_row.add_child(axis_column)
		var axis_label := Label.new(); axis_label.text = axis_name; axis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; axis_column.add_child(axis_label)
		var control := SpinBox.new(); control.min_value = Capture.ATTACHMENT_LIMITS[["x", "y", "z"][axis]].x; control.max_value = Capture.ATTACHMENT_LIMITS[["x", "y", "z"][axis]].y
		control.step = 0.01; control.value = float(Capture.DEFAULT_EQUIPMENT_ATTACHMENTS[equipment_name][axis]); control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.tooltip_text = "Posição local do encaixe %s no antebraço articulado, em unidades do manequim." % title.to_lower()
		control.value_changed.connect(func(value: float): _on_attachment_changed(equipment_name, axis, value))
		axis_column.add_child(control)
		attachment_controls["%s_%s" % [equipment_name, axis_name.to_lower()]] = control

func _on_attachment_changed(equipment_name: String, axis: int, value: float) -> void:
	if not current_attachments.has(equipment_name): return
	current_attachments[equipment_name][axis] = value
	_apply_equipment_attachments()
	if is_instance_valid(attachment_commit_timer): attachment_commit_timer.start()

func _on_turntable_mode_changed(index: int) -> void:
	if is_instance_valid(custom_angle_line): custom_angle_line.visible = int(turntable_selector.get_item_metadata(index)) == -1

func _selected_turntable_angles() -> Dictionary:
	var count := int(turntable_selector.get_item_metadata(turntable_selector.selected))
	return capture_service.build_turntable_angles(count, custom_angle_line.text if is_instance_valid(custom_angle_line) else "")

func _open_turntable_dialog() -> void:
	var parsed := _selected_turntable_angles()
	if not parsed.get("ok", false):
		set_status(str(parsed.get("message", "Ângulos inválidos.")))
		return
	if not is_instance_valid(turntable_dialog): return
	turntable_dialog.popup_centered_ratio(0.72)

func _import_selected_turntable_views() -> void:
	var parsed := _selected_turntable_angles()
	if not parsed.get("ok", false):
		set_status(str(parsed.get("message", "Ângulos inválidos.")))
		return
	turntable_import_requested.emit(parsed.angles.duplicate(true))

func _on_turntable_path_selected(path: String) -> void:
	var parsed := _selected_turntable_angles()
	if not parsed.get("ok", false): set_status(str(parsed.get("message", "Ângulos inválidos."))); return
	var output_path := path if path.to_lower().ends_with(".png") else path + ".png"
	turntable_export_requested.emit(parsed.angles, output_path)

func set_proportions(values: Dictionary) -> void:
	if is_instance_valid(proportion_commit_timer): proportion_commit_timer.stop()
	current_proportions = capture_service.normalize_proportions(values)
	for property in proportion_sliders:
		var value := float(current_proportions[property])
		(proportion_sliders[property] as HSlider).set_value_no_signal(value)
		(proportion_labels[property] as Label).text = "%d%%" % roundi(value * 100.0)
	_apply_proportions()

func set_equipment_attachments(values: Dictionary) -> void:
	if is_instance_valid(attachment_commit_timer): attachment_commit_timer.stop()
	current_attachments = capture_service.normalize_equipment_attachments(values)
	for equipment_name in ["shield", "sword"]:
		var position: Array = current_attachments[equipment_name]
		for axis in 3:
			var key := "%s_%s" % [equipment_name, ["x", "y", "z"][axis]]
			if attachment_controls.has(key): (attachment_controls[key] as SpinBox).set_value_no_signal(float(position[axis]))
	_apply_equipment_attachments()

func get_equipment_attachments() -> Dictionary:
	return capture_service.normalize_equipment_attachments(current_attachments)

func _apply_equipment_attachments() -> void:
	current_attachments = capture_service.normalize_equipment_attachments(current_attachments)
	for equipment_name in equipment_mounts:
		var mount: Node3D = equipment_mounts[equipment_name]
		var position: Array = current_attachments[equipment_name]
		mount.position = Vector3(float(position[0]), float(position[1]), float(position[2]))

func get_proportions() -> Dictionary:
	return current_proportions.duplicate(true)

func _apply_proportions() -> void:
	if proportion_nodes.is_empty() or not is_instance_valid(mannequin): return
	current_proportions = capture_service.normalize_proportions(current_proportions)
	var torso_height := float(current_proportions.torso_height)
	var shoulder_width := float(current_proportions.shoulder_width)
	var arm_length := float(current_proportions.arm_length)
	var leg_length := float(current_proportions.leg_length)
	var torso_mesh: BoxMesh = proportion_nodes.torso_mesh
	torso_mesh.size = Vector3(0.48 * shoulder_width, 0.72 * torso_height, 0.30)
	var belt_mesh: BoxMesh = proportion_nodes.belt_mesh
	belt_mesh.size = Vector3(0.51 * shoulder_width, 0.11, 0.32)
	(proportion_nodes.torso as MeshInstance3D).position.y = 1.35
	(proportion_nodes.belt as MeshInstance3D).position.y = 1.35 - 0.36 * torso_height + 0.04
	(proportion_nodes.head as MeshInstance3D).position.y = 1.35 + 0.36 * torso_height + 0.20
	for side in [-1.0, 1.0]:
		var side_key := "left" if side < 0.0 else "right"
		var arm: Node3D = joints.get(side_key + "_arm")
		if is_instance_valid(arm):
			arm.position = Vector3(side * 0.34 * shoulder_width, 1.35 + 0.27 * torso_height, 0.0)
			arm.scale = Vector3(1.0, arm_length, 1.0)
		var leg: Node3D = joints.get(side_key + "_leg")
		if is_instance_valid(leg):
			leg.position = Vector3(side * 0.15 * shoulder_width, 0.92 + 0.93 * (leg_length - 1.0) - 0.36 * (torso_height - 1.0), 0.0)
			leg.scale = Vector3(1.0, leg_length, 1.0)

func set_base_pose(pose: Dictionary) -> void:
	base_pose = pose.duplicate(true)
	set_current_pose(pose)

func set_current_pose(pose: Dictionary) -> void:
	for joint in joint_sliders:
		var radians := capture_service.clamp_joint_pose(joint, float(pose.get(joint, 0.0)))
		current_pose[joint] = radians
		(joint_sliders[joint] as HSlider).set_value_no_signal(rad_to_deg(float(current_pose[joint])))
	_update_pose(walk_phase if live_walk else -1.0)

func set_frame_context(clip_index: int, frame_index: int, clip_name: String, frame_number: int, frame_count: int) -> void:
	context_clip_index = clip_index
	context_frame_index = frame_index
	if is_instance_valid(context_label): context_label.text = "%s · quadro %d/%d" % [clip_name, frame_number, frame_count]

func get_base_pose() -> Dictionary:
	return base_pose.duplicate(true)

func get_current_pose() -> Dictionary:
	return current_pose.duplicate(true)

func set_status(message: String) -> void:
	if is_instance_valid(status_label): status_label.text = message

func set_batch_capture_state(running: bool, cancel_after_clip: bool = false) -> void:
	if is_instance_valid(capture_button): capture_button.disabled = running
	if is_instance_valid(capture_all_button): capture_all_button.disabled = running
	if is_instance_valid(cancel_capture_all_button):
		cancel_capture_all_button.visible = running
		cancel_capture_all_button.disabled = cancel_after_clip
		cancel_capture_all_button.text = "Cancelamento solicitado" if cancel_after_clip else "Cancelar após o clip atual"

func _set_orbit(degrees: float) -> void:
	if is_instance_valid(mannequin): mannequin.rotation.y = deg_to_rad(degrees)

func _toggle_walk() -> void:
	live_walk = not live_walk
	if live_walk:
		walk_button.text = "Parar caminhada"
		walk_timer.start()
	else:
		walk_timer.stop()
		walk_button.text = "Reproduzir caminhada"
		_update_pose(-1.0)

func _advance_walk() -> void:
	walk_phase = fposmod(walk_phase + 0.04, 1.0)
	_update_pose(walk_phase)

func _update_pose(phase: float) -> void:
	if not is_instance_valid(mannequin): return
	var gait := capture_service.walk_pose(phase) if phase >= 0.0 else {"left_arm": 0.0, "right_arm": 0.0, "left_elbow": 0.0, "right_elbow": 0.0, "left_leg": 0.0, "right_leg": 0.0, "left_knee": 0.0, "right_knee": 0.0, "torso": 0.0, "bounce": 0.0}
	for joint in joints:
		var pivot: Node3D = joints[joint]
		var base := float(current_pose.get(joint, 0.0))
		var gait_rotation := float(gait.get(joint, 0.0))
		pivot.rotation.x = base + gait_rotation
	if is_instance_valid(torso_pivot): torso_pivot.position.y = 1.35 + float(gait.get("bounce", 0.0))
	var combined := current_pose.duplicate(true)
	for joint in Capture.JOINTS: combined[joint] = float(current_pose.get(joint, 0.0)) + float(gait.get(joint, 0.0))
	imported_bone_rig.apply_pose(imported_model_root, imported_bone_mappings, combined)

func capture_sequence(frame_indices: Array, target_size: Vector2i, palette: Array, poses: Array = []) -> Dictionary:
	var angles: Array[float] = []
	for direction in 8: angles.append(360.0 * float(direction) / 8.0)
	return await capture_turntable(frame_indices, target_size, palette, poses, angles, true)

func capture_turntable(frame_indices: Array, target_size: Vector2i, palette: Array, poses: Array, angles: Array, capture_modular_passes: bool = false) -> Dictionary:
	if not is_instance_valid(viewport) or not is_instance_valid(mannequin): return {"ok": false, "message": "O viewport 3D ainda não está pronto."}
	if frame_indices.is_empty() or frame_indices.size() > Capture.MAX_CAPTURE_FRAMES: return {"ok": false, "message": "A captura aceita de 1–8 frames por operação."}
	if angles.is_empty() or angles.size() > Capture.MAX_TURNTABLE_VIEWS: return {"ok": false, "message": "A captura aceita de 1–64 ângulos."}
	if capture_modular_passes and int(get_capture_pass_counts().get("body", 0)) < 1: return {"ok": false, "message": "Atribua pelo menos uma malha ao passe Corpo antes de capturar."}
	if not poses.is_empty() and poses.size() != frame_indices.size(): return {"ok": false, "message": "A sequência de poses não corresponde aos frames do clip."}
	var budget: Dictionary = capture_service.validate_turntable_budget(angles.size(), frame_indices.size(), target_size)
	if not budget.get("ok", false): return {"ok": false, "message": str(budget.get("message", "Orçamento multivista inválido."))}
	if capture_modular_passes and int(budget.get("estimated_bytes", 0)) * 4 > Capture.MAX_TURNTABLE_RGBA_BYTES: return {"ok": false, "message": "Os passes modulares ultrapassariam 64 MiB. Reduza a resolução ou o tamanho do clip."}
	for angle in angles:
		if not is_finite(float(angle)) or float(angle) < 0.0 or float(angle) >= 360.0: return {"ok": false, "message": "Cada ângulo deve estar entre 0° e 359,99°."}
	for first_index in angles.size():
		for second_index in range(first_index + 1, angles.size()):
			if absf(float(angles[first_index]) - float(angles[second_index])) < 0.001: return {"ok": false, "message": "A lista de ângulos contém valores repetidos."}
	var original_size := viewport.size
	var original_yaw := mannequin.rotation.y
	var original_phase := walk_phase
	var original_live_walk := live_walk
	var original_model_animation := ""
	var original_model_animation_time := 0.0
	var original_model_animation_playing := false
	if is_instance_valid(imported_model_animation_player):
		original_model_animation = imported_model_animation_player.current_animation
		original_model_animation_time = imported_model_animation_player.current_animation_position
		original_model_animation_playing = imported_model_animation_player.is_playing()
	if live_walk:
		live_walk = false
		walk_timer.stop()
		walk_button.text = "Reproduzir caminhada"
	viewport_container.stretch = false
	viewport.size = target_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	var all_directions: Array = []
	var all_passes: Dictionary = {"body": [], "shield": [], "sword": []} if capture_modular_passes else {}
	var all_attachment_anchors: Array = []
	var labels: Array[String] = []
	for direction in angles.size():
		var angle_degrees := float(angles[direction])
		mannequin.rotation.y = deg_to_rad(angle_degrees)
		var direction_frames: Array = []
		var direction_anchor_frames: Array = []
		var direction_pass_frames: Dictionary = {"body": [], "shield": [], "sword": []} if capture_modular_passes else {}
		for frame_index in frame_indices.size():
			var phase := float(frame_index) / float(frame_indices.size())
			var imported_animation_applied := _seek_imported_animation(frame_index, frame_indices.size())
			if not poses.is_empty(): _apply_absolute_pose(poses[frame_index])
			elif not imported_animation_applied: _update_pose(phase)
			set_status("Renderizando vista %d/%d · %.2f° · quadro %d/%d…" % [direction + 1, angles.size(), angle_degrees, frame_index + 1, frame_indices.size()])
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var texture := viewport.get_texture()
			var raw: Image = texture.get_image() if texture != null else Image.new()
			var pixels: Image = capture_service.pixelize_capture(raw, target_size, palette)
			if pixels.is_empty() or pixels.get_used_rect().size == Vector2i.ZERO:
				_restore_capture_pass()
				_restore_capture_state(original_size, original_yaw, original_phase, original_live_walk)
				_restore_imported_animation(original_model_animation, original_model_animation_time, original_model_animation_playing)
				set_status("A captura saiu vazia; confira câmera, iluminação e fundo transparente.")
				return {"ok": false, "message": "A captura 3D da vista %.2f°, quadro %d ficou vazia." % [angle_degrees, frame_index + 1]}
			direction_frames.append(pixels)
			direction_anchor_frames.append(_project_equipment_anchors(target_size))
			if capture_modular_passes:
				for pass_name in CAPTURE_PASSES:
					if int(get_capture_pass_counts().get(pass_name, 0)) == 0:
						direction_pass_frames[pass_name].append(Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8))
						continue
					var prior_visibility := _set_capture_pass(pass_name)
					viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var pass_texture := viewport.get_texture()
					var pass_raw: Image = pass_texture.get_image() if pass_texture != null else Image.new()
					var pass_pixels: Image = capture_service.pixelize_capture(pass_raw, target_size, palette)
					_restore_capture_pass(prior_visibility)
					if pass_pixels.is_empty():
						_restore_capture_state(original_size, original_yaw, original_phase, original_live_walk)
						_restore_imported_animation(original_model_animation, original_model_animation_time, original_model_animation_playing)
						set_status("Falha ao capturar o passe modular '%s'." % pass_name)
						return {"ok": false, "message": "A captura do passe '%s' falhou." % pass_name}
					direction_pass_frames[pass_name].append(pass_pixels)
		all_directions.append(direction_frames)
		if capture_modular_passes:
			for pass_name in CAPTURE_PASSES: all_passes[pass_name].append(direction_pass_frames[pass_name])
		all_attachment_anchors.append(direction_anchor_frames)
		labels.append(_turntable_angle_label(angle_degrees, angles.size() == 8))
	_restore_capture_state(original_size, original_yaw, original_phase, original_live_walk)
	_restore_imported_animation(original_model_animation, original_model_animation_time, original_model_animation_playing)
	await get_tree().process_frame
	set_status("Turntable concluída: %d vistas × %d quadros. A origem foi preservada." % [angles.size(), frame_indices.size()])
	return {"ok": true, "images": all_directions, "pass_images": all_passes, "frame_indices": frame_indices.duplicate(), "direction_order": labels, "camera_yaw_degrees": angles.duplicate(), "base_pose": base_pose.duplicate(true), "poses": poses.duplicate(true), "proportions": current_proportions.duplicate(true), "equipment_attachments": get_equipment_attachments(), "attachment_anchor_positions": all_attachment_anchors}

func _seek_imported_animation(frame_index: int, frame_count: int) -> bool:
	if not imported_bone_mappings.is_empty(): return false
	if not is_instance_valid(imported_model_animation_player) or imported_model_animation_selector.item_count == 0: return false
	var selected := imported_model_animation_selector.selected
	if selected < 0 or selected >= imported_model_animation_selector.item_count: return false
	var animation_name := str(imported_model_animation_selector.get_item_text(selected))
	var animation: Animation = imported_model_animation_player.get_animation(animation_name)
	if animation == null or animation.length <= 0.0: return false
	imported_model_animation_player.play(animation_name)
	var denominator := float(frame_count) if animation.loop_mode != Animation.LOOP_NONE else float(maxi(1, frame_count - 1))
	var time := animation.length * float(frame_index) / denominator
	if animation.loop_mode == Animation.LOOP_NONE: time = minf(time, animation.length)
	imported_model_animation_player.seek(time, true)
	imported_model_animation_player.advance(0.0)
	return true

func _restore_imported_animation(animation_name: String, animation_time: float, was_playing: bool) -> void:
	if not imported_bone_mappings.is_empty():
		_update_pose(walk_phase if live_walk else -1.0)
		return
	if not is_instance_valid(imported_model_animation_player): return
	if animation_name.is_empty():
		imported_model_animation_player.stop()
		return
	imported_model_animation_player.play(animation_name)
	imported_model_animation_player.seek(animation_time, true)
	if not was_playing: imported_model_animation_player.pause()

func _project_equipment_anchors(target_size: Vector2i) -> Dictionary:
	var camera := viewport.get_camera_3d()
	if camera == null: return {}
	var projected: Dictionary = {}
	if not imported_model_sha256.is_empty():
		for equipment_name in ["shield", "sword"]:
			if imported_socket_nodes.has(equipment_name) and is_instance_valid(imported_socket_nodes[equipment_name].mount):
				var socket_screen := camera.unproject_position(imported_socket_nodes[equipment_name].mount.global_position)
				projected[equipment_name] = [clampi(roundi(socket_screen.x), 0, target_size.x - 1), clampi(roundi(socket_screen.y), 0, target_size.y - 1)]
				continue
			for mesh in _capture_meshes():
				var key := str(mesh.get_meta("sfs_capture_pass_key", ""))
				if imported_model_root.is_ancestor_of(mesh) and str(capture_pass_assignments.get(key, "body")) == equipment_name:
					var screen_position := camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_center())
					projected[equipment_name] = [clampi(roundi(screen_position.x), 0, target_size.x - 1), clampi(roundi(screen_position.y), 0, target_size.y - 1)]
					break
		return projected
	for equipment_name in equipment_mounts:
		var mount: Node3D = equipment_mounts[equipment_name]
		var screen: Vector2 = camera.unproject_position(mount.global_position)
		projected[equipment_name] = [clampi(roundi(screen.x), 0, target_size.x - 1), clampi(roundi(screen.y), 0, target_size.y - 1)]
	return projected

func _turntable_angle_label(angle_degrees: float, eight_view_set: bool) -> String:
	if eight_view_set:
		var normalized_index := roundi(angle_degrees / 45.0) % 8
		if is_equal_approx(fposmod(angle_degrees, 360.0), float(normalized_index) * 45.0): return Capture.DIRECTIONS[normalized_index]
	return "%.2f°" % angle_degrees

func _apply_absolute_pose(pose: Dictionary) -> void:
	for joint in joints:
		var pivot: Node3D = joints[joint]
		pivot.rotation.x = float(pose.get(joint, current_pose.get(joint, 0.0)))
	if is_instance_valid(torso_pivot): torso_pivot.position.y = 1.35 + float(pose.get("bounce", 0.0))
	imported_bone_rig.apply_pose(imported_model_root, imported_bone_mappings, pose)

func _restore_capture_state(original_size: Vector2i, original_yaw: float, original_phase: float, resume_walk: bool) -> void:
	_restore_capture_pass()
	viewport.size = original_size
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_container.stretch = true
	mannequin.rotation.y = original_yaw
	walk_phase = original_phase
	live_walk = resume_walk
	if resume_walk:
		walk_button.text = "Parar caminhada"
		walk_timer.start()
	else:
		walk_button.text = "Reproduzir caminhada"
	_update_pose(original_phase if resume_walk else -1.0)
