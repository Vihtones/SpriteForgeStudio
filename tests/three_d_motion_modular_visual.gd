extends SceneTree

const Studio = preload("res://ui/studio.gd")
const Motion = preload("res://core/three_d_motion_capture.gd")

func make_test_glb() -> PackedByteArray:
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "SmokeCharacter"
	var shape := CapsuleMesh.new()
	shape.radius = 0.22
	shape.height = 1.6
	mesh.mesh = shape
	source.add_child(mesh)
	mesh.owner = source
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var error := gltf.append_from_scene(source, state)
	var bytes: PackedByteArray = gltf.generate_buffer(state) if error == OK else PackedByteArray()
	source.free()
	return bytes

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS ", label)
	else:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	var studio = Studio.new()
	root.add_child(studio)
	await process_frame
	await process_frame
	var document = studio.doc
	document.animation.clips[0].frames = [0]
	var panel = studio.three_d_motion_panel
	check(int(panel.get_capture_pass_counts().body) > 0 and int(panel.get_capture_pass_counts().shield) == 2 and int(panel.get_capture_pass_counts().sword) == 3, "o manequim gráfico expõe meshes classificados para os três passes")
	var assignments: Dictionary = panel.get_capture_pass_assignments()
	var first_body_mesh := ""
	for key in assignments:
		if str(assignments[key]) == "body": first_body_mesh = str(key); break
	assignments[first_body_mesh] = "shield"
	studio._save_3d_motion_capture_passes(assignments)
	check(panel.get_capture_pass_counts().shield == 3 and document.art.three_d_motion_rig.capture_pass_assignments == assignments, "a atribuição configurável atualiza o conjunto realmente capturado e sua provenance")
	var capture: Dictionary = await panel.capture_sequence([0], Vector2i(32, 32), document.palette, [Motion.new().walk_pose(0.0)])
	check(capture.get("ok", false), "SubViewport captura a pose em oito direções com resolução de 32×32")
	var pass_images: Dictionary = capture.get("pass_images", {})
	var payload_valid := true
	var visible_pass_counts := {"body": 0, "shield": 0, "sword": 0}
	for pass_name in ["body", "shield", "sword"]:
		var directions: Array = pass_images.get(pass_name, [])
		payload_valid = payload_valid and directions.size() == 8
		for direction in directions:
			payload_valid = payload_valid and direction is Array and direction.size() == 1 and direction[0] is Image and direction[0].get_size() == Vector2i(32, 32)
			if direction is Array and not direction.is_empty() and direction[0] is Image and direction[0].get_used_rect().size != Vector2i.ZERO: visible_pass_counts[pass_name] = int(visible_pass_counts[pass_name]) + 1
	check(payload_valid and int(visible_pass_counts.body) == 8 and int(visible_pass_counts.shield) > 0 and int(visible_pass_counts.sword) > 0, "passes isolados retornam cels RGBA e mantêm silhuetas em vistas capturáveis")
	var metadata := {"attachment_anchor_positions": capture.get("attachment_anchor_positions", []), "pose_sequence": capture.get("poses", []), "capture_pass_assignments": panel.get_capture_pass_assignments(), "capture_method": "SubViewport 3D modular smoke"}
	var applied: Dictionary = Motion.new().apply_modular_capture(document, 0, pass_images, metadata)
	check(applied.get("ok", false) and document.layers.size() == 4 and document.art.get("three_d_motion_captures", []).size() == 3, "o resultado gráfico entra na timeline como três layers com provenance")
	check(document.art.three_d_motion_captures.all(func(record: Dictionary) -> bool: return record.get("capture_pass_assignments", {}) == assignments), "a provenance de cada layer registra a atribuição que produziu os pixels")
	if document.layers.size() == 4:
		check(document.layers[1].cels[0][0].get_used_rect().size != Vector2i.ZERO and document.layers[2].equipment and document.layers[3].equipment, "corpo e equipamentos capturados permanecem editáveis e alinhados aos sockets")
		check(document.undo() and document.layers.size() == 1 and document.redo() and document.layers.size() == 4, "Undo/Redo reverte o conjunto gráfico importado em uma operação")
	var contact := Image.create(128, 32, false, Image.FORMAT_RGBA8)
	var samples: Array = [capture.images[0][0], pass_images.body[0][0], pass_images.shield[0][0], pass_images.sword[0][0]]
	for index in samples.size(): contact.blit_rect(samples[index], Rect2i(0, 0, 32, 32), Vector2i(index * 32, 0))
	var contact_path := ProjectSettings.globalize_path("res://test_results/three_d_motion_modular_smoke.png")
	check(contact.save_png(contact_path) == OK, "prancha de diagnóstico grava composição e três passes isolados para inspeção")
	contact.resize(512, 128, Image.INTERPOLATE_NEAREST)
	contact.save_png(ProjectSettings.globalize_path("res://test_results/three_d_motion_modular_smoke_zoom.png"))
	var glb := make_test_glb()
	studio._import_3d_motion_model(glb, "synthetic-smoke.glb")
	var imported_capture: Dictionary = await panel.capture_sequence([0], Vector2i(32, 32), document.palette, [{}])
	var imported_body: Array = imported_capture.get("pass_images", {}).get("body", [])
	var imported_pixels_ok: bool = imported_capture.get("ok", false) and imported_body.size() == 8
	if imported_pixels_ok:
		for direction in imported_body: imported_pixels_ok = imported_pixels_ok and direction.size() == 1 and direction[0] is Image and direction[0].get_used_rect().size != Vector2i.ZERO
	check(imported_pixels_ok and panel.imported_model_sha256 != "", "GLB importado é enquadrado e capturado em oito direções de baixa resolução")
	if imported_pixels_ok:
		var imported_sheet := Image.create(256, 32, false, Image.FORMAT_RGBA8)
		for direction in 8: imported_sheet.blit_rect(imported_body[direction][0], Rect2i(Vector2i.ZERO, Vector2i(32, 32)), Vector2i(direction * 32, 0))
		var imported_path := ProjectSettings.globalize_path("res://test_results/three_d_imported_model_smoke.png")
		check(imported_sheet.save_png(imported_path) == OK, "prancha 8 direções do GLB sintético é salva para inspeção")
		imported_sheet.resize(512, 64, Image.INTERPOLATE_NEAREST)
		imported_sheet.save_png(ProjectSettings.globalize_path("res://test_results/three_d_imported_model_smoke_zoom.png"))
	var imported_layer_count: int = document.layers.size()
	var imported_apply: Dictionary = Motion.new().apply_modular_capture(document, 0, imported_capture.get("pass_images", {}), {"attachment_anchor_positions": imported_capture.get("attachment_anchor_positions", []), "capture_pass_assignments": panel.get_capture_pass_assignments(), "capture_method": "GLB local 3D smoke"}) if imported_pixels_ok else {"ok": false}
	if not imported_apply.get("ok", false): print("IMPORTED_APPLY_DIAG ", {"message": imported_apply.get("message", ""), "passes": imported_capture.get("pass_images", {}).keys(), "body_dirs": imported_capture.get("pass_images", {}).get("body", []).size(), "anchors": imported_capture.get("attachment_anchor_positions", []).size(), "layers_before": imported_layer_count, "layers_after": document.layers.size()})
	var imported_pass_records: Array = document.art.get("three_d_motion_captures", [])
	var imported_records_valid: bool = imported_pass_records.size() == 3 and imported_pass_records.all(func(record: Dictionary) -> bool: return record.get("capture_mode", "") == "modular_pass" and str(record.get("pass_name", "")) in ["body", "shield", "sword"])
	check(imported_apply.get("ok", false) and int(imported_apply.get("layers", 0)) == 3 and imported_records_valid and document.layers.size() == imported_layer_count, "captura do GLB atualiza as três layers e proveniências da timeline existente")
	document.animation.clips[0].frames = [0, 1]
	studio._import_3d_motion_model(preload("res://tests/fixtures/skinned_glb_fixture.gd").build(root), "skinned-motion.glb")
	var available_bones: Array[Dictionary] = panel.imported_bone_rig.bones(panel.imported_model_root)
	if not available_bones.is_empty():
		var bone_entry: Dictionary = available_bones[0].duplicate(true)
		bone_entry.axis = "Z"
		studio._save_imported_bone_mappings({"left_arm": bone_entry})
		var socket_configs: Dictionary = {}
		for equipment in ["shield", "sword"]:
			var config: Dictionary = bone_entry.duplicate(true)
			config.erase("axis")
			config.offset = [-0.3 if equipment == "shield" else 0.3, 0.25, 0.1]
			config.rotation_degrees = [0.0, 0.0, 0.0]
			config.scale = 0.6
			if equipment == "sword":
				var own_equipment: Dictionary = preload("res://core/rigid_equipment_asset.gd").new().prepare(preload("res://tests/fixtures/rigid_equipment_fixture.gd").build(), "custom-weapon.glb", "Synthetic visual fixture", "Test fixture")
				if own_equipment.get("ok", false):
					config.asset = own_equipment.asset
					own_equipment.template.free()
			socket_configs[equipment] = config
		studio._save_imported_equipment_sockets(socket_configs)
		studio._save_3d_motion_frame_pose({"left_arm": 0.0}, 0, 0)
		studio._save_3d_motion_frame_pose({"left_arm": 0.6}, 0, 1)
		await studio._capture_3d_motion_clip()
		var matching_records: Array = document.art.get("three_d_motion_captures", []).filter(func(record: Dictionary) -> bool: return record.get("frame_indices", []) == [0, 1] and record.get("pass_name", "") == "body")
		var skinned_motion_ok := false
		if not matching_records.is_empty():
			var record: Dictionary = matching_records.back()
			for layer in document.layers:
				if layer.id == record.layer_id:
					skinned_motion_ok = layer.cels[0][0].get_data() != layer.cels[0][1].get_data() and not record.get("imported_model", {}).get("bone_mappings", {}).is_empty()
					var pose_sheet := Image.create(256, 64, false, Image.FORMAT_RGBA8)
					for direction in 8:
						for frame in 2: pose_sheet.blit_rect(layer.cels[direction][frame], Rect2i(0, 0, 32, 32), Vector2i(direction * 32, frame * 32))
					pose_sheet.resize(512, 128, Image.INTERPOLATE_NEAREST)
					skinned_motion_ok = skinned_motion_ok and pose_sheet.save_png(ProjectSettings.globalize_path("res://test_results/three_d_mapped_bones_smoke.png")) == OK
		check(skinned_motion_ok, "poses-chave SFS deformam a skin GLB e produzem quadros diferentes na timeline com provenance")
		var equipment_motion_ok := true
		for equipment in ["shield", "sword"]:
			var equipment_records: Array = document.art.get("three_d_motion_captures", []).filter(func(record: Dictionary) -> bool: return record.get("frame_indices", []) == [0, 1] and record.get("pass_name", "") == equipment)
			if equipment_records.is_empty(): equipment_motion_ok = false; continue
			var record: Dictionary = equipment_records.back()
			equipment_motion_ok = equipment_motion_ok and record.get("imported_model", {}).get("equipment_sockets", {}).has(equipment) and record.attachment_anchor_positions[0][0][equipment] != record.attachment_anchor_positions[0][1][equipment]
			for layer in document.layers:
				if layer.id == record.layer_id: equipment_motion_ok = equipment_motion_ok and layer.cels[0][0].get_data() != layer.cels[0][1].get_data()
		check(equipment_motion_ok, "equipamentos no osso GLB geram passes animados, âncoras móveis e provenance dos encaixes")
		var own_weapon_records: Array = document.art.get("three_d_motion_captures", []).filter(func(record: Dictionary) -> bool: return record.get("frame_indices", []) == [0, 1] and record.get("pass_name", "") == "sword")
		var own_weapon_ok := false
		if not own_weapon_records.is_empty():
			var own_asset: Dictionary = own_weapon_records.back().get("imported_model", {}).get("equipment_sockets", {}).get("sword", {}).get("asset", {})
			own_weapon_ok = own_asset.get("filename", "") == "custom-weapon.glb" and not own_asset.has("glb_base64") and int(panel.get_capture_pass_counts().sword) == 1
		check(own_weapon_ok and equipment_motion_ok, "arma GLB própria substitui a demonstração e produz raster animado com hash/procedência")
	else: check(false, "fixture gráfica contém esqueleto GLB")
	studio.queue_free()
	await process_frame
	var batch_studio = Studio.new()
	root.add_child(batch_studio)
	await process_frame
	await process_frame
	var batch_document = batch_studio.doc
	for clip in batch_document.animation.clips: clip.frames = [0]
	var batch_clip_count: int = batch_document.animation.clips.size()
	await batch_studio._capture_all_3d_motion_clips()
	var batch_records: Array = batch_document.art.get("three_d_motion_captures", [])
	var captured_clips: Dictionary = {}
	for record in batch_records:
		if record is Dictionary and str(record.get("capture_mode", "")) == "modular_pass": captured_clips[int(record.get("clip_index", -1))] = true
	check(batch_records.size() == batch_clip_count * 3 and captured_clips.size() == batch_clip_count and batch_document.layers.size() == 1 + batch_clip_count * 3, "ação de lote captura todos os clips em oito direções e cria layers editáveis sem interromper a timeline")
	check(int(batch_document.animation.active) == 0 and batch_document.art.candidate_status == "candidate", "lote restaura o clip ativo e preserva o estado de candidato que exige revisão humana")
	batch_studio.queue_free()
	await process_frame
	print("3D modular viewport smoke: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
