extends SceneTree

const Studio = preload("res://ui/studio.gd")
const Storage = preload("res://core/storage.gd")

var checks: Array[Dictionary] = []
var failed := 0

func expect(condition: bool, title: String) -> void:
	checks.append({"name": title, "passed": condition})
	if condition: print("PASS ", title)
	else:
		failed += 1
		printerr("FAIL ", title)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio = Studio.new()
	root.add_child(studio)
	await process_frame
	await process_frame
	var document = studio.doc
	var angles: Array[float] = []
	for index in 32: angles.append(float(index) * 11.25)
	var requested := ProjectSettings.globalize_path("user://sfs-turntable-integration.png")
	var requested_json := requested.get_basename() + ".json"
	if FileAccess.file_exists(requested): DirAccess.remove_absolute(requested)
	if FileAccess.file_exists(requested_json): DirAccess.remove_absolute(requested_json)
	var revision_before := int(document.revision)
	await studio._export_3d_motion_turntable(angles, requested)
	var sidecar: Variant = Storage.read_json(requested_json)
	var atlas := Image.new()
	var png_ok := FileAccess.file_exists(requested) and atlas.load(requested) == OK
	var expected_cells: int = angles.size() * document.clip().frames.size()
	var expected_columns: int = mini(8, expected_cells)
	var expected_rows: int = ceili(float(expected_cells) / float(expected_columns))
	expect(png_ok and atlas.get_width() == document.width * expected_columns and atlas.get_height() == document.height * expected_rows, "export multivista gera spritesheet PNG em grade compacta")
	expect(sidecar is Dictionary and sidecar.get("angles_degrees", []).size() == 32 and sidecar.get("cells", []).size() == expected_cells and sidecar.get("cell_width") == document.width and sidecar.get("equipment_attachments", {}).has("shield") and sidecar.get("attachment_anchor_positions", []).size() == 32, "JSON registra 32 ângulos, células, sockets 3D e âncoras projetadas por vista")
	expect(int(document.revision) == revision_before, "exportar turntable não altera documento, aprovação nem timeline")
	expect(studio._unique_turntable_path(requested) != requested, "export não sobrescreve um PNG/JSON existente e escolhe um sufixo livre")
	var previous_layer_count: int = document.layers.size()
	await studio._import_turntable_as_directions(angles)
	var capture_records: Array = document.art.get("three_d_motion_captures", [])
	var latest_capture: Dictionary = capture_records.back() if not capture_records.is_empty() else {}
	expect(document.layers.size() == previous_layer_count + 1 and latest_capture.get("direction_order", []) == document.DIRECTIONS, "importar 32 vistas cria uma camada compatível com as oito direções editáveis")
	expect(latest_capture.get("selected_turntable_view_indices", []) == [0, 4, 8, 12, 16, 20, 24, 28] and latest_capture.get("camera_yaw_degrees", []) == [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0], "proveniência registra quais vistas foram escolhidas e os oito ângulos alvo")
	expect(latest_capture.get("attachment_anchor_positions", []).size() == 8 and document.rig.anchors.get("0:0", {}).has("shield_mount") and document.rig.anchors.get("0:0", {}).has("weapon_mount"), "importação mapeia pontos de encaixe para pivôs 2D nas oito direções")
	expect(document.undo() and document.layers.size() == previous_layer_count and document.art.get("three_d_motion_captures", []).is_empty(), "Undo remove a camada multivista importada e restaura o documento")
	if FileAccess.file_exists(requested): DirAccess.remove_absolute(requested)
	if FileAccess.file_exists(requested_json): DirAccess.remove_absolute(requested_json)
	var collision_path := requested.get_basename() + "-02.png"
	if FileAccess.file_exists(collision_path): DirAccess.remove_absolute(collision_path)
	if FileAccess.file_exists(collision_path.get_basename() + ".json"): DirAccess.remove_absolute(collision_path.get_basename() + ".json")
	studio.queue_free()
	await process_frame
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/three-d-motion-turntable-visual-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("3D turntable export: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
