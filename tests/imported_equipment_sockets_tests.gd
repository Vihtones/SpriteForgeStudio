extends SceneTree
const Studio = preload("res://ui/studio.gd")
const Document = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const Fixture = preload("res://tests/fixtures/skinned_glb_fixture.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(condition: bool, label: String) -> void:
	checks.append({"name": label, "passed": condition})
	if condition: print("PASS ", label)
	else: failed += 1; printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio = Studio.new()
	root.add_child(studio)
	await process_frame
	var document = Document.new()
	studio.doc = document
	var panel = studio.three_d_motion_panel
	studio._import_3d_motion_model(Fixture.build(root), "socket-fixture.glb")
	var bones: Array[Dictionary] = panel.imported_bone_rig.bones(panel.imported_model_root)
	if not bones.is_empty():
		var sockets: Dictionary = {}
		for equipment in ["shield", "sword"]:
			sockets[equipment] = bones[0].duplicate(true)
			sockets[equipment].offset = [-0.3 if equipment == "shield" else 0.3, 0.25, 0.1]
			sockets[equipment].rotation_degrees = [0.0, 0.0, 20.0]
			sockets[equipment].scale = 0.6
		studio._save_imported_equipment_sockets(sockets)
		var mounts_valid: bool = panel.imported_socket_nodes.size() == 2
		if mounts_valid:
			mounts_valid = panel.imported_socket_nodes.sword.attachment is BoneAttachment3D and panel.imported_socket_nodes.sword.attachment.bone_name == str(bones[0].bone)
		expect(mounts_valid and document.art.three_d_motion_rig.model_asset.equipment_sockets.size() == 2, "arma e escudo são montados por BoneAttachment3D e persistidos no asset GLB")
		expect(int(panel.get_capture_pass_counts().shield) == 2 and int(panel.get_capture_pass_counts().sword) == 3, "geometrias anexadas entram nos passes corretos sem duplicar o corpo procedural")
		var mount: Node3D = panel.imported_socket_nodes.sword.mount
		expect(mount.position.is_equal_approx(Vector3(0.3, 0.25, 0.1)) and is_equal_approx(mount.scale.x, 0.6) and is_equal_approx(mount.rotation_degrees.z, 20.0), "encaixe aplica posição, rotação e escala locais configuradas")
		var mapping: Dictionary = bones[0].duplicate(true)
		mapping.axis = "Z"
		studio._save_imported_bone_mappings({"left_arm": mapping})
		panel.set_current_pose({"left_arm": 0.0})
		await process_frame
		await process_frame
		var first_position := mount.global_position
		var first_basis := mount.global_basis
		panel.set_current_pose({"left_arm": 0.7})
		await process_frame
		await process_frame
		expect(not first_position.is_equal_approx(mount.global_position) and not first_basis.is_equal_approx(mount.global_basis), "arma acompanha posição e orientação do osso durante a pose")
		var anchors: Dictionary = panel._project_equipment_anchors(Vector2i(256, 256))
		var screen: Vector2 = panel.viewport.get_camera_3d().unproject_position(mount.global_position)
		expect(anchors.has("sword") and anchors.sword == [clampi(roundi(screen.x), 0, 255), clampi(roundi(screen.y), 0, 255)], "âncora 2D da arma usa a projeção do encaixe real no osso")
		var revision_before: int = document.revision
		var invalid: Dictionary = sockets.duplicate(true)
		invalid.sword.scale = NAN
		studio._save_imported_equipment_sockets(invalid)
		expect(document.revision == revision_before and panel.imported_equipment_sockets.size() == 2, "encaixe inválido é recusado sem mutar o documento ou a montagem")
		document.art.locked = true
		studio._save_imported_equipment_sockets({})
		expect(panel.imported_equipment_sockets.size() == 2, "Art Lock impede remover a montagem dos equipamentos")
		document.art.locked = false
		var path := "res://test_results/equipment-sockets-roundtrip.sfs.json"
		var storage = Storage.new()
		var saved := storage.save_document(document, path) == OK
		var loaded = storage.load_document(path) if saved else null
		var prior_assignments: Dictionary = panel.get_capture_pass_assignments()
		panel.clear_imported_model()
		if loaded != null:
			studio.doc = loaded
			studio._three_d_pose_document = null
			studio._load_3d_motion_pose()
		expect(loaded != null and panel.imported_socket_nodes.size() == 2 and panel.imported_equipment_sockets.size() == 2 and panel.get_capture_pass_assignments() == prior_assignments, "save/load recria os encaixes e mantém identidades estáveis dos passes")
		studio._save_imported_equipment_sockets({})
		var removed: bool = panel.imported_socket_nodes.is_empty()
		var undo_ok: bool = loaded.undo() if loaded != null else false
		studio._load_3d_motion_pose()
		expect(removed and undo_ok and panel.imported_socket_nodes.size() == 2, "Undo restaura os dois equipamentos após remover os encaixes")
		var redo_ok: bool = loaded.redo() if loaded != null else false
		studio._load_3d_motion_pose()
		expect(redo_ok and panel.imported_socket_nodes.is_empty(), "Redo remove novamente os equipamentos e os passes adicionais")
		panel._open_imported_socket_dialog()
		var window: Node = panel.get_node_or_null("ImportedEquipmentSockets")
		if window != null:
			var selector := window.find_child("SocketBone_sword", true, false) as OptionButton
			var scale_control := window.find_child("SocketScale_sword", true, false) as SpinBox
			selector.select(1)
			scale_control.value = 0.5
			for button in window.find_children("*", "Button", true, false):
				if button.text == "Aplicar encaixes": button.pressed.emit(); break
			await process_frame
		expect(panel.imported_equipment_sockets.has("sword") and is_equal_approx(float(panel.imported_equipment_sockets.get("sword", {}).get("scale", 0)), 0.5), "janela real aplica seleção de osso e escala do equipamento")
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	else: expect(false, "fixture GLB contém esqueleto para equipamentos")
	studio.queue_free()
	await process_frame
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/imported-equipment-sockets-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Imported equipment sockets: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
