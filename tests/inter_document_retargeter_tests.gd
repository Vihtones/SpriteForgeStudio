extends SceneTree
const Doc = preload("res://core/document.gd")
const Retargeter = preload("res://core/inter_document_retargeter.gd")
const Storage = preload("res://core/storage.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else:
		failed += 1
		printerr("FAIL ", name)

func make_doc(frame: int, horizontal: bool = false) -> RefCounted:
	var document = Doc.new()
	document.animation = {"active": 0, "clips": [{"name": "walk", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	document.frame = frame
	var layer: Dictionary = document.layers[0]
	layer.name = "Tronco"
	layer.retarget_key = "torso"
	document.set_layer_bone(str(layer.id), ["pelvis", "chest"])
	layer.cels[0][frame].set_pixel(16, 18, Color("e2ac72"))
	var tip := [16, 12] if horizontal else [16, 8]
	var root_point := [10, 12] if horizontal else [16, 18]
	document.rig.anchors = {"0:%d" % frame: {"pelvis": root_point, "chest": tip}}
	return document

func _initialize() -> void:
	var service = Retargeter.new()
	var source = make_doc(0)
	var target = make_doc(1, true)
	var source_pixels: PackedByteArray = source.layers[0].cels[0][0].get_data()
	var target_pixels: PackedByteArray = target.layers[0].cels[0][1].get_data()
	var proposal: Dictionary = service.build(source, target, 0, 0, 0, 0, 1)
	expect(proposal.ok and proposal.changes.size() == 1, "transfere uma pose entre documentos SFS com topologia e chave compatíveis")
	expect(is_equal_approx(float(proposal.changes[0].rotation), -90.0), "converte a orientação óssea da origem para o pivô e orientação próprios do destino")
	expect(proposal.ratios.size() == 1 and str(proposal.ratios[0]).contains("1.67×"), "informa a relação proporcional entre o segmento fonte e alvo")
	var preview = target.detached_copy()
	var preview_proposal: Dictionary = service.build(source, preview, 0, 0, 0, 0, 1)
	expect(service.apply(preview, preview_proposal) and is_equal_approx(preview.layer_rotation(str(preview.layers[0].id), 0, 1), -90.0), "aplica a proposta numa cópia de prévia sem tocar o destino original")
	expect(source.layers[0].cels[0][0].get_data() == source_pixels and target.layers[0].cels[0][1].get_data() == target_pixels, "prévia mantém pixels da origem e do destino intactos")
	expect(service.apply(target, proposal) and is_equal_approx(target.layer_rotation(str(target.layers[0].id), 0, 1), -90.0), "aplica no destino através de uma operação única")
	expect(target.undo() and is_equal_approx(target.layer_rotation(str(target.layers[0].id), 0, 1), 0.0), "Undo desfaz todo o retarget interdocumento")
	expect(source.layers[0].cels[0][0].get_data() == source_pixels, "origem permanece imutável após aplicar e desfazer")
	var remapped_source = make_doc(0)
	remapped_source.rig.skeleton = [["shoulder_l", "elbow_l"]]
	remapped_source.set_layer_bone(str(remapped_source.layers[0].id), ["shoulder_l", "elbow_l"])
	var remapped_proposal: Dictionary = service.build(remapped_source, make_doc(1, true), 0, 0, 0, 0, 1)
	expect(remapped_proposal.ok and remapped_proposal.changes[0].source_bone == ["shoulder_l", "elbow_l"] and remapped_proposal.changes[0].bone == ["pelvis", "chest"], "chave explícita transfere entre topologias diferentes com segmentos semanticamente mapeados")
	var storage = Storage.new()
	var source_path := "res://test_results/inter-document-source.sfs.json"
	var save_result: Error = storage.save_document(source, source_path)
	var loaded = storage.load_document(source_path)
	expect(save_result == OK and loaded != null and loaded.layers[0].retarget_key == "torso" and loaded.layers[0].bone == ["pelvis", "chest"], "chave de retarget e segmento sobrevivem ao save/load")
	var wrong_family = make_doc(1, true)
	wrong_family.rig.family = "canid"
	expect(not service.build(source, wrong_family, 0, 0, 0, 0, 1).ok, "recusa famílias anatômicas diferentes")
	var wrong_topology = make_doc(1, true)
	wrong_topology.rig.skeleton = [["pelvis", "head"]]
	expect(not service.build(source, wrong_topology, 0, 0, 0, 0, 1).ok, "recusa segmento de destino que não pertence ao próprio rig")
	var wrong_key = make_doc(1, true)
	wrong_key.layers[0].retarget_key = "armadura"
	expect(not service.build(source, wrong_key, 0, 0, 0, 0, 1).ok, "recusa camada destino sem correspondência semântica explícita")
	var too_small_bone = make_doc(1, true)
	too_small_bone.rig.anchors["0:1"].chest = [11, 12]
	expect(not service.build(source, too_small_bone, 0, 0, 0, 0, 1).ok, "recusa proporção óssea fora do intervalo seguro")
	var duplicate_key = make_doc(1, true)
	duplicate_key.add_layer("Duplicada")
	duplicate_key.layers[1].retarget_key = "torso"
	duplicate_key.set_layer_bone(str(duplicate_key.layers[1].id), ["pelvis", "chest"])
	expect(not service.build(source, duplicate_key, 0, 0, 0, 0, 1).ok, "recusa chaves de camada duplicadas")
	var wrong_direction: Dictionary = service.build(source, target, 0, 0, 8, 0, 1)
	expect(not wrong_direction.ok, "recusa índice de direção fora do padrão de oito vistas")
	var outside_clip: Dictionary = service.build(source, target, 0, 0, 0, 5, 1)
	expect(not outside_clip.ok, "recusa quadro que não pertence ao clip de origem")
	var stale: Dictionary = service.build(source, target, 0, 0, 0, 0, 1)
	target.mark_changed()
	expect(not service.apply(target, stale), "recusa proposta obsoleta após edição concorrente no destino")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/inter-document-retargeter-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Inter-document retargeter: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
