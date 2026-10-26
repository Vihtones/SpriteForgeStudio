extends SceneTree
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const Resizer = preload("res://core/canvas_resizer.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, title: String) -> void:
	if value: passed += 1; print("PASS ", title)
	else: failed += 1; printerr("FAIL ", title)

func run() -> void:
	var doc = Doc.new()
	doc.current().set_pixel(2, 2, Color.RED)
	doc.current().set_pixel(3, 2, Color.BLUE)
	doc.selection = Rect2i(2, 2, 1, 1)
	doc.manifest.approvals = [{"id": "synthetic-test", "human": true}]
	expect(doc.edit_layer_mask("hide") and doc.current().get_pixel(2, 2) == Color.RED and doc.composite().get_pixel(2, 2).a == 0, "ocultar seleção preserva os pixels originais e altera somente a composição")
	expect(doc.manifest.approvals.is_empty() and doc.art.status == "candidate", "alteração de visibilidade invalida a aprovação derivada")
	expect(doc.undo() and doc.composite().get_pixel(2, 2) == Color.RED and not doc.manifest.approvals.is_empty(), "Undo restaura máscara e aprovação da revisão anterior")
	expect(doc.redo() and doc.composite().get_pixel(2, 2).a == 0 and doc.current().get_pixel(2, 2) == Color.RED, "Redo reaplica a máscara sem apagar a cel")
	expect(doc.edit_layer_mask("reveal") and doc.composite().get_pixel(2, 2) == Color.RED, "revelar seleção devolve a arte sem recompor pixels")
	doc.rig["protected_pixels"] = {"0:0": [66]}
	var revision: int = doc.revision
	expect(not doc.edit_layer_mask("hide") and doc.revision == revision, "pixels protegidos não podem ser ocultados pela máscara")
	doc.rig.protected_pixels.clear()
	doc.edit_layer_mask("hide")
	doc.art.locked = true
	expect(not doc.edit_layer_mask("clear") and doc.composite().get_pixel(2, 2).a == 0, "Art Lock impede remover a máscara")
	doc.art.locked = false; doc.layers[0].locked = true
	expect(not doc.edit_layer_mask("clear"), "bloqueio de camada impede editar a máscara")
	doc.layers[0].locked = false
	doc.layers[0].cels[1][0].set_pixel(2, 2, Color.RED)
	doc.layers[0].cels[0][1].set_pixel(2, 2, Color.RED)
	expect(doc.composite(1, 0).get_pixel(2, 2) == Color.RED and doc.composite(0, 1).get_pixel(2, 2) == Color.RED, "máscara é independente por direção e quadro")
	doc.add_layer("Frente"); doc.current().set_pixel(2, 2, Color.GREEN)
	expect(doc.composite().get_pixel(2, 2) == Color.GREEN, "máscara de uma camada não oculta as camadas vizinhas")
	doc.active_layer = 0
	var folder := "res://test_results/layer-masks-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var storage = Storage.new()
	var path := folder.path_join("source.sfs.json")
	var saved: Error = storage.save_document(doc, path)
	var loaded = storage.load_document(path)
	expect(saved == OK and Storage.read_json(path).schema == 4 and loaded != null and loaded.layers[0].visibility_masks["0:0"] == [66] and loaded.layers[0].cels[0][0].get_pixel(2, 2) == Color.RED, "schema 4 preserva a máscara e impede leitores antigos de exibir arte sem ela")
	expect(doc.duplicate_frame() and doc.layers[0].visibility_masks.get("0:1", []) == [66], "inserção de frame duplica e remapeia a máscara")
	doc.layers[0].visibility_masks["0:1"].append(67)
	expect(doc.layers[0].visibility_masks["0:0"] == [66], "máscaras duplicadas possuem buffers independentes")
	doc.frame = 0; doc.delete_frame()
	expect(doc.layers[0].visibility_masks["0:0"] == [66, 67] and doc.validate().is_empty(), "remoção de frame remapeia as máscaras sem índices inválidos")
	var malformed: Dictionary = storage.encode(doc)
	malformed.layers[0].visibility_masks["0:0"] = [999999]
	storage.atomic_json(folder.path_join("malformed.sfs.json"), malformed)
	expect(storage.load_document(folder.path_join("malformed.sfs.json")) == null, "load recusa coordenada de máscara fora do canvas")
	var resized = Doc.new()
	resized.current().set_pixel(2, 2, Color.RED); resized.selection = Rect2i(2, 2, 1, 1); resized.edit_layer_mask("hide")
	var resized_result: Dictionary = Resizer.resize_document(resized, 64, 64, Image.INTERPOLATE_NEAREST, "top_left")
	expect(resized_result.ok and resized.layer_mask_pixels() == 4 and resized.current().get_pixel(4, 4) == Color.RED and resized.composite().get_pixel(4, 4).a == 0 and resized.validate().is_empty(), "redimensionamento acompanha a máscara com vizinho mais próximo")
	expect(resized.undo() and resized.width == 32 and resized.layer_mask_pixels() == 1, "Undo restaura dimensão e máscara juntas")
	var capped = Doc.new(); capped.initialize_blank(32, 32, 8, 8)
	for layer_index in 7: capped.add_layer("Mask %d" % layer_index)
	for layer in capped.layers:
		layer.visibility_masks = {}
		for direction in 8:
			for frame in 8: layer.visibility_masks[capped.cel_key(direction, frame)] = Array(range(512))
	capped.selection = Rect2i(31, 31, 1, 1)
	var capped_revision: int = capped.revision
	expect(capped.layer_mask_pixels() == Doc.MAX_LAYER_MASK_PIXELS and not capped.edit_layer_mask("hide") and not capped.duplicate_frame() and capped.revision == capped_revision and capped.frames == 8, "limite de memória recusa máscara e duplicação antes de alterar o documento")
	resized.layers[0].pivot = "chest"; resized.anchors.chest = [3, 3]
	resized.rig.rotations = {"0:0": {str(resized.layers[0].id): 90.0}}
	expect(resized.composite_layer(0).get_used_rect().size == Vector2i.ZERO and not resized.bake_layer_pose(resized.layers[0].id), "máscara acompanha a rotação na prévia e impede bake ambíguo")
	var export_error: Error = storage.export_all(loaded, folder.path_join("export"), "modular")
	var atlas: Image
	# The modular manifest supplies stable filenames instead of assuming a naming scheme.
	var modular: Variant = Storage.read_json(folder.path_join("export/modular.json"))
	if modular is Dictionary: atlas = Image.load_from_file(folder.path_join("export").path_join(modular.layers[0].texture))
	expect(export_error == OK and atlas != null and atlas.get_pixel(2, 2).a == 0 and loaded.layers[0].cels[0][0].get_pixel(2, 2) == Color.RED, "exportação modular aplica a máscara sem alterar o documento fonte")
	var ui = load("res://main.tscn").instantiate()
	ui.workspace_root = folder.path_join("ui"); root.add_child(ui); ui.set_process(false)
	await process_frame
	ui.create_blank_document(32, 32, 4, 8)
	ui.doc.current().set_pixel(2, 2, Color.RED); ui.doc.selection = Rect2i(2, 2, 1, 1)
	ui.find_child("HideLayerSelection", true, false).pressed.emit()
	expect(ui.doc.composite().get_pixel(2, 2).a == 0 and ui.layer_mask_status.text.contains("1 pixels"), "botão real aplica máscara e atualiza o contador da cel")
	ui.copy_direction()
	expect(ui.doc.layers[0].visibility_masks.get("1:0", []) == [66], "cópia direcional leva as máscaras junto aos pixels")
	ui.find_child("ClearLayerMask", true, false).pressed.emit()
	expect(ui.doc.composite().get_pixel(2, 2) == Color.RED and ui.doc.composite(1, 0).get_pixel(2, 2).a == 0, "remover máscara revela só a cel ativa")
	ui.free(); await process_frame
	var report := FileAccess.open("res://test_results/layer-masks-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Layer masks: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or report == null else 0)
