extends SceneTree
const Studio = preload("res://ui/studio.gd")
const Document = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const Asset = preload("res://core/rigid_equipment_asset.gd")
const RigidFixture = preload("res://tests/fixtures/rigid_equipment_fixture.gd")
const SkinnedFixture = preload("res://tests/fixtures/skinned_glb_fixture.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(condition: bool, label: String) -> void:
	checks.append({"name": label, "passed": condition})
	if condition: print("PASS ", label)
	else: failed += 1; printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var bytes := RigidFixture.build()
	var service = Asset.new()
	var prepared: Dictionary = service.prepare(bytes, "own-sword.glb", "Synthetic test source", "Test fixture")
	expect(prepared.get("ok", false), "GLB rígido próprio é validado e recebe descriptor portátil com origem declarada")
	if prepared.get("ok", false):
		var meshes: Array = prepared.template.find_children("*", "MeshInstance3D", true, false)
		expect(meshes.size() == 1 and is_equal_approx((meshes[0] as MeshInstance3D).position.y, -0.35), "importação preserva o pivô e a transformação original da geometria do equipamento")
		prepared.template.free()
		var tampered: Dictionary = prepared.asset.duplicate(true)
		tampered.sha256 = "0".repeat(64)
		expect(not service.load_asset(tampered).get("ok", false), "equipamento com conteúdo/hash divergente é recusado antes da montagem")
	var rejected: Dictionary = service.prepare(SkinnedFixture.build(root), "skinned.glb")
	expect(not rejected.get("ok", false), "equipamento skinned é recusado com mensagem de escopo rígido")
	var camera_result: Dictionary = service.prepare(RigidFixture.build(true), "camera.glb")
	expect(not camera_result.get("ok", false) and str(camera_result.get("message", "")).contains("câmera"), "equipamento não pode substituir a câmera ou iluminação da captura")
	var external_json := JSON.stringify({"asset": {"version": "2.0"}, "buffers": [{"uri": "external.bin", "byteLength": 12}]}).to_utf8_buffer()
	while external_json.size() % 4 != 0: external_json.append(32)
	var external_glb := PackedByteArray()
	external_glb.resize(20 + external_json.size())
	external_glb.encode_u32(0, 0x46546C67)
	external_glb.encode_u32(4, 2)
	external_glb.encode_u32(8, external_glb.size())
	external_glb.encode_u32(12, external_json.size())
	external_glb.encode_u32(16, 0x4E4F534A)
	for index in external_json.size(): external_glb[20 + index] = external_json[index]
	var external_result: Dictionary = service.prepare(external_glb, "external.glb")
	expect(not external_result.get("ok", false) and str(external_result.get("message", "")).contains("externos"), "dependências externas em GLB são recusadas antes de acessar arquivos auxiliares")
	var studio = Studio.new()
	root.add_child(studio)
	await process_frame
	var document = Document.new()
	studio.doc = document
	var panel = studio.three_d_motion_panel
	studio._import_3d_motion_model(SkinnedFixture.build(root), "character.glb")
	var fixture_path := "res://test_results/own-sword-fixture.glb"
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	panel._open_imported_socket_dialog()
	var window: Node = panel.get_node_or_null("ImportedEquipmentSockets")
	if window != null:
		var bone := window.find_child("SocketBone_sword", true, false) as OptionButton
		bone.select(1)
		var source := window.find_child("SocketSource_sword", true, false) as LineEdit
		var license_field := window.find_child("SocketLicense_sword", true, false) as LineEdit
		source.text = "User-declared synthetic source"
		license_field.text = "Synthetic test only"
		var import_button := window.find_child("ImportEquipment_sword", true, false) as Button
		import_button.pressed.emit()
		var dialog: FileDialog = window.get_node_or_null("EquipmentGLBImport")
		if dialog != null: dialog.file_selected.emit(ProjectSettings.globalize_path(fixture_path))
		for button in window.find_children("*", "Button", true, false):
			if button.text == "Aplicar encaixes": button.pressed.emit(); break
		await process_frame
	var sockets: Dictionary = document.art.get("three_d_motion_rig", {}).get("model_asset", {}).get("equipment_sockets", {})
	var asset: Dictionary = sockets.get("sword", {}).get("asset", {})
	expect(not asset.is_empty() and asset.get("glb_base64", "") == Marshalls.raw_to_base64(bytes) and asset.get("source", "") == "User-declared synthetic source" and asset.get("license", "") == "Synthetic test only", "seletor de arquivo e Aplicar incorporam o equipamento próprio com origem/licença da janela")
	expect(int(panel.get_capture_pass_counts().sword) == 1 and panel.imported_socket_nodes.has("sword"), "peça própria substitui a arma demonstrativa no passe sem duplicá-la")
	var safe_provenance: Dictionary = panel.imported_model_asset()
	expect(safe_provenance.get("equipment_sockets", {}).get("sword", {}).get("asset", {}).has("sha256") and not safe_provenance.get("equipment_sockets", {}).get("sword", {}).get("asset", {}).has("glb_base64"), "provenance de captura registra identidade e direitos declarados sem duplicar o GLB binário")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	var path := "res://test_results/rigid-equipment-roundtrip.sfs.json"
	var storage = Storage.new()
	var saved := storage.save_document(document, path) == OK
	var loaded = storage.load_document(path) if saved else null
	panel.clear_imported_model()
	if loaded != null:
		studio.doc = loaded
		studio._three_d_pose_document = null
		studio._load_3d_motion_pose()
	expect(loaded != null and panel.imported_socket_nodes.has("sword") and int(panel.get_capture_pass_counts().sword) == 1, "save/load reconstrói a arma própria depois de apagar o arquivo GLB original")
	if loaded != null:
		var revision_before: int = loaded.revision
		var candidate: Dictionary = panel.imported_equipment_sockets.duplicate(true)
		candidate.sword.asset.sha256 = "0".repeat(64)
		studio._save_imported_equipment_sockets(candidate)
		expect(loaded.revision == revision_before and int(panel.get_capture_pass_counts().sword) == 1 and panel.imported_equipment_sockets.sword.asset.sha256 == asset.sha256, "falha de integridade não troca a montagem ativa nem cria revisão no documento")
		candidate = panel.imported_equipment_sockets.duplicate(true)
		candidate.sword.erase("asset")
		studio._save_imported_equipment_sockets(candidate, 1)
		expect(loaded.revision == revision_before and panel.imported_equipment_sockets.sword.has("asset") and int(panel.get_capture_pass_counts().sword) == 1, "limite de projeto recusa a alteração e restaura peça própria/passes sem arquivo grande no teste")
		var folder := "res://test_results/rigid-equipment-export-" + str(Time.get_ticks_usec())
		var exported := storage.export_all(loaded, folder, "modular") == OK
		var metadata: Variant = Storage.read_json(folder.path_join("metadata.json"))
		var exported_asset: Dictionary = metadata.get("three_d_motion", {}).get("rig", {}).get("model_asset", {}).get("equipment_sockets", {}).get("sword", {}).get("asset", {}) if metadata is Dictionary else {}
		var credits := FileAccess.get_file_as_string(folder.path_join("CREDITS.txt")) if exported else ""
		expect(exported and not exported_asset.has("glb_base64") and exported_asset.get("sha256", "") == asset.get("sha256", "") and credits.contains("User-declared synthetic source") and credits.contains("Synthetic test only"), "exportação modular mantém hash/origem/licença nos metadados e créditos sem embutir o GLB fonte")
		expect(loaded.art.three_d_motion_rig.model_asset.equipment_sockets.sword.asset.has("glb_base64"), "exportar não remove o arquivo incorporado do projeto editável")
		studio._save_imported_equipment_sockets({})
		var undone: bool = loaded.undo()
		studio._load_3d_motion_pose()
		expect(undone and panel.imported_equipment_sockets.get("sword", {}).get("asset", {}).get("sha256", "") == asset.get("sha256", ""), "Undo restaura a geometria própria e seus metadados após remoção")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	studio.queue_free()
	await process_frame
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var report_file := FileAccess.open("res://test_results/rigid-equipment-assets-report.json", FileAccess.WRITE)
	if report_file != null: report_file.store_string(JSON.stringify(report, "\t")); report_file.close()
	print("Rigid equipment assets: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
