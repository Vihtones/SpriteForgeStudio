extends SceneTree
const Doc = preload("res://core/document.gd")
const Interpolator = preload("res://core/rig_interpolator.gd")
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
	doc.add_layer("Camada de braço", true)
	var layer: Dictionary = doc.layers[doc.active_layer]
	layer.pivot = "elbow_l"
	var layer_id: String = str(layer.id)
	doc.animation.clips = [
		{"name": "walk", "frames": [0, 2, 3], "durations_ms": {}, "loop": true},
		{"name": "idle", "frames": [1], "durations_ms": {}, "loop": true},
	]
	doc.rig.rotations = {"0:0": {layer_id: -170.0}, "0:3": {layer_id: 170.0}}
	doc.rig.offsets = {"0:0": {layer_id: [0, 0]}, "0:3": {layer_id: [9, 6]}}
	doc.rig.anchors = {"0:0": {"elbow_l": [2, 4]}, "0:3": {"elbow_l": [8, 10]}}
	var pixel_image: Image = layer.cels[0][0]
	pixel_image.set_pixel(4, 4, Color("cc3344"))
	var pixel_snapshot := pixel_image.get_data()
	var interpolator = Interpolator.new()
	var proposal: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true, "offset": true, "anchor": true})
	expect(proposal.ok and proposal.changes.size() == 3 and proposal.source_keys == 6, "proposta preenche rotação, offset e articulação apenas no quadro intermediário do clip")
	var values: Dictionary = {}
	for change in proposal.changes: values[change.kind] = change.value
	expect(is_equal_approx(absf(float(values.rotation)), 180.0), "rotação interpola pelo menor arco ao cruzar ±180 graus")
	expect(values.offset == [4.5, 3.0] and values.anchor == [5.0, 7.0], "offset e articulação recebem interpolação linear precisa")
	expect(not doc.rig.get("rotations", {}).get("0:2", {}).has(layer_id) and not doc.rig.anchors.has("1:2"), "prévia não altera documento nem outra direção")
	var revision_before: int = doc.revision
	expect(interpolator.apply(doc, proposal) and doc.revision == revision_before + 2, "aplicação usa checkpoint único e registra alteração reversível")
	expect(is_equal_approx(float(doc.rig.rotations["0:2"][layer_id]), float(values.rotation)) and doc.rig.offsets["0:2"][layer_id] == [4.5, 3.0] and doc.rig.anchors["0:2"].elbow_l == [5.0, 7.0], "os três canais ficam gravados no quadro de interpolação")
	expect(doc.rig.rotations["0:0"][layer_id] == -170.0 and doc.rig.rotations["0:3"][layer_id] == 170.0 and not doc.rig.get("rotations", {}).get("0:1", {}).has(layer_id), "chaves-fonte e quadro fora do clip permanecem intactos")
	expect(layer.cels[0][0].get_data() == pixel_snapshot, "interpolador de rig preserva todos os pixels de origem")
	expect(doc.composite(0, 0).get_data() != doc.composite(0, 2).get_data(), "pose intermediária produz composição transformada no preview, sem rasterizar a camada fonte")
	expect(doc.undo() and not doc.rig.get("rotations", {}).get("0:2", {}).has(layer_id) and not doc.rig.offsets.has("0:2") and not doc.rig.anchors.has("0:2"), "Undo remove toda a interpolação em uma operação")
	expect(doc.redo() and doc.rig.anchors["0:2"].elbow_l == [5.0, 7.0], "Redo restaura as poses interpoladas")
	var authored_midpoint: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true})
	expect(authored_midpoint.changes.is_empty(), "não substitui quadro-chave de artista já existente")
	var invalid_channel: Dictionary = interpolator.build(doc, 0, 0, "missing-layer", "elbow_l", {"rotation": true})
	expect(not invalid_channel.ok, "abstém-se quando a camada escolhida não existe")
	var stale_doc = Doc.new()
	var stale_layer: String = str(stale_doc.layers[0].id)
	stale_doc.rig.rotations = {"0:0": {stale_layer: 0.0}, "0:3": {stale_layer: 90.0}}
	var stale: Dictionary = interpolator.build(stale_doc, 0, 0, stale_layer, "elbow_l", {"rotation": true})
	stale_doc.mark_changed()
	expect(not interpolator.apply(stale_doc, stale), "rejeita proposta obsoleta após edição concorrente")
	var neutral_doc = Doc.new()
	var neutral_layer: String = str(neutral_doc.layers[0].id)
	expect(neutral_doc.mark_rig_pose_key(neutral_layer, "hand") and neutral_doc.rig.rotations["0:0"][neutral_layer] == 0.0, "captura explicitamente pose neutra de rotação como quadro-chave")
	neutral_doc.set_layer_rotation(neutral_layer, 90.0, 0, 3, false)
	var neutral_proposal: Dictionary = interpolator.build(neutral_doc, 0, 0, neutral_layer, "hand", {"rotation": true})
	expect(neutral_proposal.changes.size() == 2 and is_equal_approx(float(neutral_proposal.changes[0].value), 30.0), "rotação interpola da pose neutra até a chave girada")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/rig-interpolator-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Rig interpolator: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
