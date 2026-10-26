extends SceneTree
const Studio = preload("res://ui/studio.gd")
const Document = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const BoneRig = preload("res://core/imported_bone_rig.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(condition: bool, label: String) -> void:
	checks.append({"name": label, "passed": condition})
	if condition: print("PASS ", label)
	else: failed += 1; printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func make_skinned_glb() -> PackedByteArray:
	return preload("res://tests/fixtures/skinned_glb_fixture.gd").build(root)

func run() -> void:
	var studio = Studio.new()
	root.add_child(studio)
	await process_frame
	var document = Document.new()
	studio.doc = document
	var panel = studio.three_d_motion_panel
	var bytes := make_skinned_glb()
	studio._import_3d_motion_model(bytes, "skinned-fixture.glb")
	var service = BoneRig.new()
	var bones: Array[Dictionary] = service.bones(panel.imported_model_root)
	expect(not bytes.is_empty() and not bones.is_empty(), "GLB sintético com skin preserva Skeleton3D e nomes dos ossos ao importar")
	if not bones.is_empty():
		var entry: Dictionary = bones[0].duplicate(true)
		entry.axis = "Z"
		var mappings := {"left_arm": entry}
		var skeleton := panel.imported_model_root.get_node(NodePath(entry.skeleton)) as Skeleton3D
		var bone_index := skeleton.find_bone(entry.bone)
		skeleton.set_bone_pose_position(bone_index, Vector3(0.3, 0.2, 0.0))
		studio._save_imported_bone_mappings(mappings)
		expect(panel.imported_bone_mappings == mappings and document.art.three_d_motion_rig.model_asset.bone_mappings == mappings, "vínculo explícito osso/eixo é aplicado e salvo no asset do modelo")
		expect(skeleton.get_bone_pose_position(bone_index).is_equal_approx(skeleton.get_bone_rest(bone_index).origin), "modo de poses SFS remove deslocamentos residuais da animação e parte do repouso")
		panel.set_current_pose({"left_arm": 0.6})
		expect(skeleton.get_bone_pose_rotation(bone_index).is_equal_approx(Quaternion(Vector3.BACK, 0.6)), "slider de pose altera a rotação do osso importado no eixo escolhido")
		panel._apply_absolute_pose({"left_arm": -0.3})
		expect(skeleton.get_bone_pose_rotation(bone_index).is_equal_approx(Quaternion(Vector3.BACK, -0.3)), "mesma aplicação absoluta usada na captura altera o osso sem acumular rotações")
		var duplicate := {"left_arm": entry, "right_arm": entry}
		expect(not service.validate(panel.imported_model_root, duplicate).ok, "mapeamento recusa duas articulações controlando o mesmo osso")
		var invalid := {"left_arm": {"skeleton": "../..", "bone": entry.bone, "axis": "Z"}}
		expect(not service.validate(panel.imported_model_root, invalid).ok, "mapeamento recusa ossos fora da raiz do GLB")
		var before_rotation := skeleton.get_bone_pose_rotation(bone_index)
		expect(not service.apply_pose(panel.imported_model_root, mappings, {"left_arm": NAN}) and skeleton.get_bone_pose_rotation(bone_index).is_equal_approx(before_rotation), "pose não finita é recusada antes de alterar os ossos")
		expect(document.undo(), "vínculo de ossos possui checkpoint de Undo")
		studio._load_3d_motion_pose()
		expect(panel.imported_bone_mappings.is_empty(), "Undo desativa o vínculo e restaura o modo de animação GLB")
		expect(document.redo(), "Redo restaura o vínculo salvo")
		studio._load_3d_motion_pose()
		document.art.locked = true
		studio._save_imported_bone_mappings({})
		expect(panel.imported_bone_mappings == mappings, "Art Lock impede limpar os vínculos existentes")
		document.art.locked = false
		studio._save_3d_motion_frame_pose({"left_arm": 0.4}, 0, 1)
		document.frame = 1
		studio._three_d_pose_document = null
		studio._load_3d_motion_pose()
		var storage = Storage.new()
		var path := "res://test_results/bone-rig-roundtrip.sfs.json"
		var saved := storage.save_document(document, path) == OK
		var loaded = storage.load_document(path) if saved else null
		panel.clear_imported_model()
		if loaded != null:
			studio.doc = loaded
			studio._three_d_pose_document = null
			studio._load_3d_motion_pose()
		var restored_bones: Array[Dictionary] = service.bones(panel.imported_model_root)
		var restored_pose_ok := false
		if not restored_bones.is_empty():
			var restored := panel.imported_model_root.get_node(NodePath(entry.skeleton)) as Skeleton3D
			restored_pose_ok = restored.get_bone_pose_rotation(restored.find_bone(entry.bone)).is_equal_approx(Quaternion(Vector3.BACK, 0.4))
		expect(loaded != null and panel.imported_bone_mappings == mappings and restored_pose_ok, "save/load reconstrói GLB, vínculo e pose-chave no osso real")
		panel._open_bone_mapping_dialog()
		expect(panel.get_node_or_null("ImportedBoneMapping") is Window, "painel oferece a janela para editar vínculos por osso/eixo")
		var window: Node = panel.get_node_or_null("ImportedBoneMapping")
		var axis_selector := window.find_child("Axis_left_arm", true, false) as OptionButton
		if axis_selector != null:
			for index in axis_selector.item_count:
				if axis_selector.get_item_text(index) == "-Z": axis_selector.select(index)
		for button in window.find_children("*", "Button", true, false):
			if button.text == "Aplicar vínculos": button.pressed.emit(); break
		await process_frame
		expect(loaded != null and loaded.art.three_d_motion_rig.model_asset.bone_mappings.left_arm.axis == "-Z" and panel.imported_bone_mappings.left_arm.axis == "-Z", "Aplicar na janela persiste a seleção real de eixo e atualiza os controles")
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	studio.queue_free()
	await process_frame
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/imported-bone-rig-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Imported bone rig: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)

