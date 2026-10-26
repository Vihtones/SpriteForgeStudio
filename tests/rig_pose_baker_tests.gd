extends SceneTree
const Doc = preload("res://core/document.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else:
		failed += 1
		printerr("FAIL ", name)

func make_doc() -> RefCounted:
	var doc = Doc.new()
	var layer: Dictionary = doc.layers[0]
	layer.name = "Braço"
	layer.equipment = true
	layer.anchor = "hand"
	layer.pivot = "head"
	layer.opacity = 0.6
	layer.cels[0][0].set_pixel(10, 8, Color("f03a61"))
	layer.cels[0][0].set_pixel(10, 9, Color("e8b44c"))
	layer.cels[0][0].set_pixel(11, 9, Color("5f94dd"))
	doc.rig.rotations = {"0:0": {layer.id: 90.0}}
	doc.rig.offsets = {"0:0": {layer.id: [1, -2]}}
	return doc

func _initialize() -> void:
	var doc = make_doc()
	var layer: Dictionary = doc.layers[0]
	var id := str(layer.id)
	var original_pixels: PackedByteArray = layer.cels[0][0].get_data()
	var before: PackedByteArray = doc.composite(0, 0).get_data()
	expect(doc.bake_layer_pose(id, 0, 0), "rasteriza a rotação e o offset da camada com pose ativa")
	expect(layer.cels[0][0].get_data() != original_pixels, "altera a cel raster do quadro selecionado")
	expect(is_equal_approx(doc.layer_rotation(id, 0, 0), 0.0) and doc.layer_offset(0, 0, 0) == Vector2i.ZERO, "zera só os canais transformados do quadro aplicado")
	expect(doc.composite(0, 0).get_data() == before, "mantém a aparência composta e opacidade após a conversão")
	expect(doc.layer_rotation(id, 0, 1) == 0.0 and doc.layer_offset(0, 0, 1) != Vector2i.ZERO, "mantém pose e offset-base dos outros quadros")
	expect(doc.undo() and doc.layers[0].cels[0][0].get_data() == original_pixels and is_equal_approx(doc.layer_rotation(id, 0, 0), 90.0) and doc.layer_offset(0, 0, 0) != Vector2i.ZERO, "Undo restaura pixels, rotação e offset do frame")
	expect(doc.redo() and doc.composite(0, 0).get_data() == before, "Redo recupera a pose rasterizada sem mudança visual")
	var plain := Doc.new()
	var plain_pixels: PackedByteArray = plain.layers[0].cels[0][0].get_data()
	expect(not plain.bake_layer_pose(str(plain.layers[0].id), 0, 0), "não cria histórico quando a camada não tem transformação")
	expect(not plain.bake_layer_pose("missing-layer", 0, 0), "recusa layer id inexistente")
	var locked := make_doc()
	locked.layers[0].locked = true
	var locked_pixels: PackedByteArray = locked.layers[0].cels[0][0].get_data()
	expect(not locked.bake_layer_pose(str(locked.layers[0].id), 0, 0) and locked.layers[0].cels[0][0].get_data() == locked_pixels, "respeita bloqueio da camada")
	var art_locked := make_doc()
	art_locked.art.locked = true
	var art_locked_revision: int = art_locked.revision
	expect(not art_locked.bake_layer_pose(str(art_locked.layers[0].id), 0, 0) and art_locked.revision == art_locked_revision, "respeita Art Lock sem mudança")
	var protected := make_doc()
	protected.rig.protected_pixels = {"0:0": [8 * protected.width + 10]}
	var protected_pixels: PackedByteArray = protected.layers[0].cels[0][0].get_data()
	expect(not protected.bake_layer_pose(str(protected.layers[0].id), 0, 0) and protected.layers[0].cels[0][0].get_data() == protected_pixels, "recusa cel com máscara de proteção global ambígua")
	expect(not make_doc().bake_layer_pose(str(layer.id), 8, 0), "recusa direção fora dos oito valores possíveis")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/rig-pose-baker-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Rig pose baker: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
