extends SceneTree
const Doc = preload("res://core/document.gd")
const Inbetweener = preload("res://core/raster_inbetweener.gd")
const Storage = preload("res://core/storage.gd")
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
	doc.animation = {"active": 0, "clips": [{"name": "swing", "frames": [0, 1, 2, 3], "durations_ms": {"0": 80, "1": 80, "2": 80, "3": 80}, "loop": false}], "events": {}, "hitboxes": {}}
	var layer: Dictionary = doc.layers[0]
	layer.name = "Braço direito"
	layer.set("retarget_key", "arm-r")
	doc.set_layer_bone(str(layer.id), ["pelvis", "chest"])
	layer.cels[0][0].set_pixel(16, 12, Color("e94358"))
	layer.cels[0][0].set_pixel(16, 13, Color("ecb05d"))
	layer.cels[0][3].set_pixel(16, 12, Color("e94358"))
	layer.cels[0][3].set_pixel(16, 13, Color("ecb05d"))
	doc.rig.anchors = {"0:0": {"pelvis": [16, 24], "chest": [16, 12]}, "0:3": {"pelvis": [16, 24], "chest": [24, 24]}}
	doc.art.pose_approvals = [{"clip": "swing", "human": true}]
	doc.manifest.approvals = [{"human": true}]
	return doc

func _initialize() -> void:
	var doc = make_doc()
	var source_pixels: PackedByteArray = doc.layers[0].cels[0][0].get_data()
	var target_pixels: PackedByteArray = doc.layers[0].cels[0][3].get_data()
	var service = Inbetweener.new()
	var proposal: Dictionary = service.build(doc, 0, 0, 0, 3)
	expect(proposal.ok and proposal.frames == [1, 2] and proposal.changes.size() == 2, "prepara cels raster para todos os frames existentes entre as chaves")
	expect(proposal.anchors["1"].chest == [19, 16] and proposal.anchors["2"].chest == [21, 20], "articulações seguem interpolação temporal com coordenadas inteiras")
	var colors_preserved := true
	for change in proposal.changes:
		var image: Image = change.image
		if image.get_used_rect().size == Vector2i.ZERO: colors_preserved = false
		for y in doc.height:
			for x in doc.width:
				var color: Color = image.get_pixel(x, y)
				if color.a > 0.0 and color not in [Color("e94358"), Color("ecb05d")]: colors_preserved = false
	expect(colors_preserved, "candidatos usam apenas cores RGBA8 da pose fonte, sem blur ou novas cores")
	expect(doc.layers[0].cels[0][1].get_used_rect().size == Vector2i.ZERO and doc.layers[0].cels[0][2].get_used_rect().size == Vector2i.ZERO, "prévia de geração não altera o documento")
	var source_composite: PackedByteArray = doc.composite(0, 0).get_data()
	var target_composite: PackedByteArray = doc.composite(0, 3).get_data()
	var preview = doc.detached_copy()
	var preview_proposal: Dictionary = service.build(preview, 0, 0, 0, 3)
	expect(service.apply(preview, preview_proposal) and preview.layers[0].cels[0][1].get_used_rect().size != Vector2i.ZERO, "gera imagem intermediária de verdade na cópia de prévia")
	var contact: Image = service.contact_sheet(preview, 0, [1, 2])
	expect(contact.get_size() == Vector2i(doc.width * 2, doc.height) and contact.get_used_rect().size != Vector2i.ZERO, "cria folha de contato para revisar sequência intermediária")
	var revision_before: int = doc.revision
	expect(service.apply(doc, proposal) and doc.revision == revision_before + 2, "confirma todos os cels em uma única operação reversível")
	expect(doc.layers[0].cels[0][1].get_used_rect().size != Vector2i.ZERO and doc.layers[0].cels[0][2].get_used_rect().size != Vector2i.ZERO, "os dois frames intermediários recebem raster editável")
	expect(doc.composite(0, 0).get_data() == source_composite and doc.composite(0, 3).get_data() == target_composite and doc.layers[0].cels[0][0].get_data() == source_pixels and doc.layers[0].cels[0][3].get_data() == target_pixels, "poses-chave originais não são alteradas")
	expect(doc.rig.anchors["0:1"].chest == [19, 16] and doc.rig.anchors["0:2"].chest == [21, 20], "poses interpoladas salvam articulações para os cels gerados")
	expect(doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty() and doc.art.candidate_status == "candidate", "conteúdo derivado invalida aprovações antigas")
	expect(doc.undo() and doc.layers[0].cels[0][1].get_used_rect().size == Vector2i.ZERO and not doc.rig.anchors.has("0:1"), "Undo restaura todos os frames e articulações anteriores")
	expect(doc.redo() and doc.layers[0].cels[0][2].get_used_rect().size != Vector2i.ZERO, "Redo restaura o lote rasterizado")
	var storage = Storage.new()
	var saved_path := "res://test_results/raster-inbetweener-roundtrip.sfs.json"
	var save_result: Error = storage.save_document(doc, saved_path)
	var loaded = storage.load_document(saved_path)
	expect(save_result == OK and loaded != null and loaded.layers[0].cels[0][1].get_data() == doc.layers[0].cels[0][1].get_data() and loaded.rig.anchors["0:1"].chest == [19, 16], "cels rasterizados e articulações sobrevivem ao save/load SFS")
	var export_dir := "res://test_results/raster-inbetweener-export"
	var export_result: Error = storage.export_all(doc, export_dir)
	var sheet := Image.new()
	var sheet_loaded := sheet.load(export_dir.path_join("spritesheet.png")) == OK
	var exported_middle: Image = sheet.get_region(Rect2i(doc.width, 0, doc.width, doc.height)) if sheet_loaded else Image.new()
	expect(export_result == OK and sheet_loaded and exported_middle.get_data() == doc.composite(0, 1).get_data(), "export Godot contém a composição do frame intermediário gerado")
	var stale: Dictionary = service.build(doc, 0, 0, 0, 3)
	doc.mark_changed()
	expect(not service.apply(doc, stale), "recusa proposta obsoleta se o documento mudar")
	var no_gap = make_doc()
	no_gap.animation.clips[0].frames = [0, 3]
	expect(not service.build(no_gap, 0, 0, 0, 3).ok, "exige ao menos um frame intermediário já existente no clip")
	var reverse := service.build(make_doc(), 0, 0, 3, 0)
	expect(not reverse.ok, "recusa poses-chave fora de ordem")
	var art_locked = make_doc()
	art_locked.art.locked = true
	expect(not service.build(art_locked, 0, 0, 0, 3).ok, "respeita Art Lock")
	var unsegmented = make_doc()
	unsegmented.layers[0].bone = []
	expect(not service.build(unsegmented, 0, 0, 0, 3).ok, "recusa camada visível sem mapeamento ósseo")
	var locked = make_doc()
	locked.layers[0].locked = true
	expect(not service.build(locked, 0, 0, 0, 3).ok, "recusa camada visível bloqueada")
	var protected = make_doc()
	protected.rig.protected_pixels = {"0:1": [12 * protected.width + 16]}
	expect(not service.build(protected, 0, 0, 0, 3).ok, "preserva pixels protegidos do frame-alvo")
	var eventful = make_doc()
	eventful.animation.events = {"0:1": ["contact"]}
	expect(not service.build(eventful, 0, 0, 0, 3).ok, "recusa sobrescrever frame intermediário com evento editado")
	var empty_endpoint = make_doc()
	empty_endpoint.layers[0].cels[0][3].fill(Color.TRANSPARENT)
	expect(not service.build(empty_endpoint, 0, 0, 0, 3).ok, "exige raster nas duas poses-chave")
	var too_many = make_doc()
	too_many.frames = 12
	for layer in too_many.layers:
		for row in layer.cels:
			while row.size() < 12: row.append(too_many.blank())
	too_many.animation.clips[0].frames = range(12)
	expect(not service.build(too_many, 0, 0, 0, 11).ok, "limita a oito poses por lote antes de alocar raster")
	var insert_doc = make_doc()
	insert_doc.animation.clips[0].frames = [0, 3]
	insert_doc.animation.clips.append({"name": "secondary", "frames": [2, 3], "durations_ms": {"3": 70.0}, "loop": false})
	insert_doc.animation.events = {"0:3": ["landing"]}
	insert_doc.rig.protected_pixels = {"0:3": [12 * insert_doc.width + 16]}
	var original_insert_pixels: PackedByteArray = insert_doc.layers[0].cels[0][3].get_data()
	var insert_revision: int = insert_doc.revision
	var inserted_proposal: Dictionary = service.build_inserted(insert_doc, 0, 0, 0, 3, 2)
	expect(inserted_proposal.ok and inserted_proposal.inserted_frames == [1, 2] and inserted_proposal.frames == [1, 2], "propõe dois novos frames raster entre poses adjacentes no clip")
	expect(inserted_proposal.preview_frames == [0, 1, 2, 5], "folha de contato acompanha poses-chave e novos frames mesmo com lacunas na numeração global")
	var insert_preview: RefCounted = inserted_proposal.get("preview_document")
	expect(insert_doc.frames == 4 and insert_doc.revision == insert_revision and insert_doc.layers[0].cels[0][3].get_data() == original_insert_pixels and insert_preview.frames == 6, "prévia estrutural usa cópia e deixa o projeto original intacto")
	expect(insert_preview.animation.clips[0].frames == [0, 1, 2, 5] and insert_preview.animation.clips[1].frames == [4, 5], "inserção remapeia clip ativo e mantém referências de outros clips")
	expect(is_equal_approx(float(inserted_proposal.durations["0"]), 40.0) and is_equal_approx(float(inserted_proposal.durations["1"]), 40.0) and is_equal_approx(float(inserted_proposal.durations["2"]), 40.0) and is_equal_approx(float(inserted_proposal.durations["5"]), 40.0), "redistribui os 160 ms das poses adjacentes sem ampliar a duração total")
	expect(insert_preview.layers[0].cels[0][1].get_used_rect().size != Vector2i.ZERO and insert_preview.layers[0].cels[0][2].get_used_rect().size != Vector2i.ZERO and not insert_preview.animation.events.has("0:1") and not insert_preview.rig.protected_pixels.has("0:1"), "prévia gera cels novos e não duplica eventos ou máscara de proteção da pose fonte")
	expect(service.apply_inserted(insert_doc, inserted_proposal) and insert_doc.frames == 6 and insert_doc.clip().frames == [0, 1, 2, 5], "confirma inserção e rasterização como uma operação atômica")
	expect(insert_doc.layers[0].cels[0][1].get_used_rect().size != Vector2i.ZERO and insert_doc.layers[0].cels[0][2].get_used_rect().size != Vector2i.ZERO and insert_doc.layers[0].cels[0][5].get_data() == original_insert_pixels, "novos cels são editáveis e a pose destino original é preservada no índice remapeado")
	expect(insert_doc.animation.events.has("0:5") and insert_doc.animation.events["0:5"] == ["landing"] and insert_doc.rig.protected_pixels.has("0:5"), "eventos e proteção da pose destino acompanham o frame remapeado")
	expect(is_equal_approx(float(insert_doc.clip().durations_ms["0"]) + float(insert_doc.clip().durations_ms["1"]) + float(insert_doc.clip().durations_ms["2"]) + float(insert_doc.clip().durations_ms["5"]), 160.0), "duração total permanece invariável após confirmar a inserção")
	expect(insert_doc.undo() and insert_doc.frames == 4 and insert_doc.animation.clips[0].frames == [0, 3] and insert_doc.layers[0].cels[0][3].get_data() == original_insert_pixels and insert_doc.animation.events.has("0:3"), "um Undo restaura frames, raster, clips, eventos e proteções")
	expect(insert_doc.redo() and insert_doc.frames == 6 and insert_doc.clip().frames == [0, 1, 2, 5], "Redo recupera toda a inserção")
	var non_adjacent = make_doc()
	expect(not service.build_inserted(non_adjacent, 0, 0, 0, 3, 2).ok, "inserção de novos frames exige poses adjacentes no clip")
	var too_many_insert = make_doc()
	too_many_insert.frames = 31
	for layer in too_many_insert.layers:
		for row in layer.cels:
			while row.size() < 31: row.append(too_many_insert.blank())
	too_many_insert.animation.clips[0].frames = [0, 1]
	expect(not service.build_inserted(too_many_insert, 0, 0, 0, 1, 2).ok, "recusa expansão além do limite estrutural de 32 frames")
	var locked_insert = make_doc()
	locked_insert.art.locked = true
	expect(not service.build_inserted(locked_insert, 0, 0, 0, 3, 2).ok, "Art Lock impede proposta de inserção")
	var protected_source_insert = make_doc()
	protected_source_insert.animation.clips[0].frames = [0, 3]
	protected_source_insert.rig.protected_pixels = {"0:0": [12 * protected_source_insert.width + 16]}
	expect(not service.build_inserted(protected_source_insert, 0, 0, 0, 3, 2).ok, "recusa mover pixels protegidos da pose fonte")
	var scaled_doc = make_doc()
	scaled_doc.rig.anchors["0:3"] = {"pelvis": [16, 24], "chest": [16, 0]}
	var scaled_proposal: Dictionary = service.build(scaled_doc, 0, 0, 0, 3, true)
	var rigid_proposal: Dictionary = service.build(scaled_doc, 0, 0, 0, 3, false)
	var scaled_image: Image = scaled_proposal.changes[0].image if scaled_proposal.get("ok", false) else Image.new()
	var rigid_image: Image = rigid_proposal.changes[0].image if rigid_proposal.get("ok", false) else Image.new()
	expect(scaled_proposal.ok and rigid_proposal.ok and scaled_proposal.scale_segments and not rigid_proposal.scale_segments, "operação expõe deformação proporcional e modo rígido como escolhas explícitas")
	expect(scaled_image.get_pixel(16, 8).to_html(false) == "e94358" and rigid_image.get_pixel(16, 8).a == 0.0 and rigid_image.get_pixel(16, 12).to_html(false) == "e94358", "escala pelo comprimento ósseo reposiciona a peça sem borrar e preserva cores discretas")
	var unsafe_scale_doc = make_doc()
	unsafe_scale_doc.rig.anchors["0:3"] = {"pelvis": [16, 24], "chest": [16, -6]}
	expect(not service.build(unsafe_scale_doc, 0, 0, 0, 3, true).ok and service.build(unsafe_scale_doc, 0, 0, 0, 3, false).ok, "recusa deformação fora de 0,5×–2× e mantém disponível a articulação rígida")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/raster-inbetweener-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Raster inbetweener: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
