extends SceneTree
const Doc = preload("res://core/document.gd")
const Retargeter = preload("res://core/pose_retargeter.gd")
const Storage = preload("res://core/storage.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else:
		failed += 1
		printerr("FAIL ", name)

func _initialize() -> void:
	var doc = Doc.new()
	doc.animation.clips = [{"name": "walk", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}]
	var torso: Dictionary = doc.layers[0]
	torso.name = "Torso"
	doc.set_layer_bone(str(torso.id), ["pelvis", "chest"])
	doc.add_layer("Braço esquerdo")
	var arm: Dictionary = doc.layers[1]
	doc.set_layer_bone(str(arm.id), ["chest", "neck"])
	doc.anchors.pelvis = [16, 28]
	doc.anchors.chest = [16, 18]
	doc.anchors.neck = [16, 8]
	doc.rig.anchors = {
		"0:0": {"pelvis": [16, 28], "chest": [16, 18], "neck": [16, 8]},
		"0:2": {"pelvis": [16, 28], "chest": [16, 18], "neck": [24, 18]},
	}
	# A target-side pixel proves the operation changes the composed rig, not source raster data.
	torso.cels[0][2].set_pixel(16, 18, Color("4b6e8a"))
	arm.cels[0][2].set_pixel(17, 17, Color("cb8a50"))
	arm.cels[0][0].set_pixel(17, 17, Color("cb8a50"))
	var torso_pixels: PackedByteArray = torso.cels[0][2].get_data()
	var arm_pixels: PackedByteArray = arm.cels[0][2].get_data()
	var arm_source_pixels: PackedByteArray = arm.cels[0][0].get_data()
	var service = Retargeter.new()
	var proposal: Dictionary = service.build(doc, 0, 0, 0, 2)
	expect(proposal.ok and proposal.changes.size() == 1, "proposta inclui apenas segmentos que precisam de rotação no destino")
	var arm_change: Dictionary = {}
	for change in proposal.changes:
		if change.layer_id == arm.id: arm_change = change
	expect(not arm_change.is_empty() and is_equal_approx(float(arm_change.rotation), -90.0), "orientação da origem é convertida em rotação local no segmento-alvo")
	expect(arm.cels[0][2].get_data() == arm_pixels and torso.cels[0][2].get_data() == torso_pixels, "prévia não modifica pixels das camadas segmentadas")
	var before: PackedByteArray = doc.composite(0, 2).get_data()
	expect(service.apply(doc, proposal) and is_equal_approx(doc.layer_rotation(str(arm.id), 0, 2), -90.0), "retarget aplica rotações no destino em um único checkpoint")
	expect(doc.composite(0, 2).get_data() != before and arm.cels[0][2].get_data() == arm_pixels and arm.cels[0][0].get_data() == arm_source_pixels, "composição de destino muda sem tocar pixels de nenhum quadro")
	expect(doc.undo() and is_equal_approx(doc.layer_rotation(str(arm.id), 0, 2), 0.0), "Undo restaura a pose alvo anterior")
	var roundtrip_proposal: Dictionary = service.build(doc, 0, 0, 0, 2)
	service.apply(doc, roundtrip_proposal)
	var storage = Storage.new()
	var export_dir := "res://test_results/pose-retarget-export"
	var export_result: Error = storage.export_all(doc, export_dir)
	var exported_sheet := Image.new()
	var exported_sheet_ok := exported_sheet.load(export_dir.path_join("spritesheet.png")) == OK
	var exported_frame: Image = exported_sheet.get_region(Rect2i(2 * doc.width, 0, doc.width, doc.height)) if exported_sheet_ok else Image.new()
	expect(export_result == OK and exported_sheet_ok and exported_frame.get_data() == doc.composite(0, 2).get_data(), "export Godot incorpora a pose retargetada da composição sem exportar raster alterado")
	var roundtrip_path := "res://test_results/pose-retarget-roundtrip.sfs.json"
	var save_result: Error = storage.save_document(doc, roundtrip_path)
	var roundtrip = storage.load_document(roundtrip_path)
	expect(save_result == OK and roundtrip != null and roundtrip.layers[1].bone == ["chest", "neck"] and is_equal_approx(roundtrip.layer_rotation(str(roundtrip.layers[1].id), 0, 2), -90.0), "segmentos, pivôs e pose retargetada sobrevivem ao save/load SFS")
	var unsegmented = Doc.new()
	unsegmented.animation.clips = [{"name": "walk", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}]
	unsegmented.layers[0].cels[0][2].set_pixel(2, 2, Color.WHITE)
	var blocked: Dictionary = service.build(unsegmented, 0, 0, 0, 2)
	expect(not blocked.ok and str(blocked.message).contains("mapeie ao segmento ósseo"), "abstém-se e explica quando o destino não está segmentado")
	var bad_pivot = Doc.new()
	bad_pivot.animation.clips = [{"name": "walk", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}]
	bad_pivot.layers[0].cels[0][2].set_pixel(2, 2, Color.WHITE)
	bad_pivot.layers[0].bone = ["pelvis", "chest"]
	bad_pivot.layers[0].pivot = "neck"
	var mismatch: Dictionary = service.build(bad_pivot, 0, 0, 0, 2)
	expect(not mismatch.ok and str(mismatch.message).contains("pivô não coincide"), "abstém-se se o pivô não corresponde à raiz anatômica")
	var outside_clip: Dictionary = service.build(doc, 0, 0, 0, 9)
	expect(not outside_clip.ok, "recusa quadro de destino ausente no clip selecionado")
	var stale: Dictionary = service.build(doc, 0, 0, 0, 2)
	doc.mark_changed()
	expect(not service.apply(doc, stale), "recusa uma proposta retarget obsoleta")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/pose-retargeter-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Pose retargeter: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
