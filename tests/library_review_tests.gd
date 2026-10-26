extends SceneTree
const Library = preload("res://core/public_asset_library.gd")
const Review = preload("res://core/animation_review.gd")
const Storage = preload("res://core/storage.gd")
const Document = preload("res://core/document.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, title: String) -> void:
	if condition: passed += 1; print("PASS ", title)
	else: failed += 1; printerr("FAIL ", title)

func run() -> void:
	var library = Library.new()
	expect(library.error.is_empty() and library.entries.size() == 27, "catálogo reúne fontes externas e conteúdo offline sem inferir aprovação")
	expect(library.search("KENNEY", true).size() == 3 and library.search("anatomia").size() == 6, "busca por autor/categoria diferencia offline de fontes externas")
	expect(library.search("nada-corresponde").is_empty() and library.image("missing") == null, "busca e IDs inexistentes têm falha controlada")
	var offline := library.search("", true)
	var bundled_sheets: Array = offline.filter(func(entry): return entry.has("spritesheet"))
	expect(offline.size() == 21 and bundled_sheets.size() == 18, "18 spritesheets licenciadas ficam disponíveis offline junto dos três atlas CC0")
	var total := 0
	for source in offline:
		if not source.has("atlas"): continue
		var atlas: Image = library.image(source.id)
		expect(atlas != null and atlas.get_width() == int(source.atlas.width) and atlas.get_height() == int(source.atlas.height), str(source.id) + " — bytes e dimensão conferem com manifesto")
		expect(source.license == "CC0-1.0" and not source.rights.attribution_required and source.art_status == "not_reviewed", str(source.id) + " — licença e estado artístico explícitos")
		if atlas == null: continue
		total += int(source.atlas.tiles)
		var tile = library.tile_document(source.id, 0)
		expect(tile != null and tile.validate().is_empty() and tile.frames == 1 and tile.width == 16 and tile.layers.size() == 1, "tile abre como projeto SFS válido, estático e editável")
		if tile == null: continue
		expect(tile.composite(4, 0).get_data() == atlas.get_region(Rect2i(0, 0, 16, 16)).get_data(), "recorte de tile preserva RGBA sem recolorir ou redimensionar")
		expect(tile.composite(0, 0).get_used_rect().size == Vector2i.ZERO and tile.art.direction_coverage == ["S"], "importação não inventa outras vistas nem declara oito direções")
		expect(tile.art.source_assets[0].source == source.source and tile.art.source_assets[0].sha256 == source.atlas.sha256 and tile.manifest.approvals.is_empty(), "procedência segue no documento sem aprovação herdada")
	expect(total == 396, "três atlas incorporados fornecem 396 células, sem confundi-las com sprites únicos")
	for source in bundled_sheets:
		var sheet: Image = library.image(str(source.id))
		var descriptor: Dictionary = source.spritesheet
		expect(sheet != null and sheet.get_width() == int(descriptor.width) and sheet.get_height() == int(descriptor.height), str(source.id) + " — PNG offline confere hash e dimensões")
		var cardinal_animation: bool = descriptor.has("frame_size")
		var directions_accurate: bool = source.directions == (["N", "W", "S", "E"] if cardinal_animation else [])
		expect(source.rights.attribution_required and source.art_status == "not_reviewed" and directions_accurate, str(source.id) + " — atribuição, estado de revisão e direções declarados corretamente")
		var source_record: Dictionary = library.provenance(str(source.id))
		expect(source_record.sha256 == descriptor.sha256 and source_record.license_notice.contains(str(source.source)), str(source.id) + " — nota de fonte e licença acompanha a imagem")
		if not source.get("credit_members", []).is_empty():
			expect(source_record.license_notice.contains("CREDITS") or source_record.license_notice.contains("Credits"), str(source.id) + " — créditos integrais preservados no pacote")
		var sheet_tile: RefCounted = library.tile_document(str(source.id), 0)
		if cardinal_animation:
			expect(sheet_tile == null and library.error.contains("grade de tiles"), str(source.id) + " — folha de animação não é apresentada como tile estático")
		else:
			expect(sheet_tile != null and sheet_tile.width == 32 and sheet_tile.height == 32 and sheet_tile.art.source_assets[0].license == source.license, str(source.id) + " — tile 32 px abre editável com a licença original")
			if sheet_tile != null:
				var cell_size := int(descriptor.cell_size)
				expect(sheet_tile.composite(4, 0).get_data() == sheet.get_region(Rect2i(0, 0, cell_size, cell_size)).get_data(), str(source.id) + " — recorte da grade mantém os pixels originais")
	var lpc_actions := ["idle", "walk", "slash", "jump"]
	for action in lpc_actions:
		var entry: Dictionary = library.find("lpc-male-" + action)
		var sheet: Image = library.image("lpc-male-" + action)
		expect(not entry.is_empty() and sheet != null and entry.license == "CC-BY-SA 3.0" and entry.rights.share_alike and entry.directions == ["N", "W", "S", "E"] and entry.frame_count == entry.spritesheet.columns, "LPC %s: licença, direção cardinal e quadros declarados" % action)
		var credits: Dictionary = library.provenance("lpc-male-" + action)
		expect(sheet != null and sheet.get_width() == entry.spritesheet.columns * 64 and sheet.get_height() == 4 * 64 and credits.license_notice.contains("CREDITS-selected.csv"), "LPC %s: grade 64 px e créditos oficiais disponíveis offline" % action)
		if sheet != null:
			var columns := int(entry.spritesheet.columns)
			var lpc_doc = Document.new()
			lpc_doc.width = 64; lpc_doc.height = 64; lpc_doc.frames = columns
			for direction in 8:
				var blank_row: Array[Image] = []
				for frame in columns: blank_row.append(Image.create(64, 64, false, Image.FORMAT_RGBA8))
				lpc_doc.layers[0].cels[direction] = blank_row
			lpc_doc.animation = {"active": 0, "clips": [{"name": action, "frames": range(columns), "durations_ms": {}, "loop": action in ["idle", "walk"]}], "events": {}, "hitboxes": {}}
			var actual_import: Dictionary = preload("res://core/spritesheet_importer.gd").import_into(lpc_doc, sheet, {"cell_width": 64, "cell_height": 64, "columns": columns, "rows": 4, "direction_map": [0, 6, 4, 2], "start_frame": 0})
			var exact_frames: bool = bool(actual_import.get("ok", false)) and lpc_doc.validate().is_empty()
			for row_index in 4:
				var mapped_direction: int = [0, 6, 4, 2][row_index]
				for frame in columns:
					var expected_cell: Image = sheet.get_region(Rect2i(frame * 64, row_index * 64, 64, 64))
					exact_frames = exact_frames and lpc_doc.layers[0].cels[mapped_direction][frame].get_data() == expected_cell.get_data()
			expect(exact_frames, "LPC %s: importação de todos os quadros preserva pixels e contrato do documento" % action)
	var mapped_doc = Document.new()
	var mapped_sheet := Image.create(32, 128, false, Image.FORMAT_RGBA8)
	for row_index in 4: mapped_sheet.fill_rect(Rect2i(0, row_index * 32, 32, 32), Color(float(row_index + 1) / 5.0, 0.2, 0.8, 1.0))
	var mapped_result: Dictionary = preload("res://core/spritesheet_importer.gd").import_into(mapped_doc, mapped_sheet, {"cell_width": 32, "cell_height": 32, "columns": 1, "rows": 4, "direction_map": [0, 6, 4, 2], "start_frame": 0})
	var mapped_pixels: bool = bool(mapped_result.get("ok", false))
	for row_index in 4:
		var direction_index: int = [0, 6, 4, 2][row_index]
		mapped_pixels = mapped_pixels and is_equal_approx(mapped_doc.layers[0].cels[direction_index][0].get_pixel(0, 0).r, float(row_index + 1) / 5.0)
	for direction_index in [1, 3, 5, 7]: mapped_pixels = mapped_pixels and mapped_doc.layers[0].cels[direction_index][0].get_used_rect().size == Vector2i.ZERO
	expect(mapped_pixels and mapped_result.direction_map == [0, 6, 4, 2], "quatro linhas LPC mapeiam up/left/down/right para N/W/S/E sem preencher diagonais")
	expect(mapped_doc.undo() and mapped_doc.layers.all(func(layer): return layer.cels.all(func(direction): return direction.all(func(cel): return cel.get_used_rect().size == Vector2i.ZERO))), "importação LPC direcional reverte em um Undo sem deixar quadros misturados")
	var invalid_map: Dictionary = preload("res://core/spritesheet_importer.gd").import_into(mapped_doc, mapped_sheet, {"cell_width": 32, "cell_height": 32, "columns": 1, "rows": 4, "direction_map": [0, 0, 4, 2], "start_frame": 0})
	expect(not invalid_map.ok and mapped_doc.layers[0].cels[0][0].get_used_rect().size == Vector2i.ZERO, "mapa direcional com duplicatas é recusado antes de tocar nas cels")
	var import_doc = Document.new()
	var import_image := Image.create(import_doc.width, import_doc.height, false, Image.FORMAT_RGBA8)
	import_image.fill_rect(Rect2i(8, 8, 8, 8), Color("f0a030"))
	var imported: Dictionary = preload("res://core/spritesheet_importer.gd").import_into(import_doc, import_image, {"cell_width": import_doc.width, "cell_height": import_doc.height, "columns": 1, "rows": 1, "start_frame": 0})
	var import_details := {"mode": "single_action_row", "source_row": 1, "columns": 1, "start_frame": 1, "content_scale_percent": 100.0}
	var attribution_result: Dictionary = library.record_spritesheet_import(import_doc, "lpc-roofs", import_details)
	expect(imported.ok and attribution_result.ok and import_doc.art.source_assets.size() == 1 and import_doc.art.source_assets[0].license_notice.contains("CREDITS-roofs.txt") and import_doc.art.source_assets[0].import_details == import_details, "importar folha conserva crédito integral e parâmetros do recorte no projeto")
	expect(import_doc.undo() and not import_doc.art.has("source_assets") and import_doc.current().get_used_rect().size == Vector2i.ZERO, "Undo remove pixels e procedência como uma operação")
	expect(library.tile_document("kenney-tiny-town", -1) == null and library.tile_document("kenney-tiny-town", 999) == null and library.tile_document("lpc-generator", 0) == null, "índice inválido e fonte não incorporada não criam documentos")
	var bad = Library.new(); bad.entries[0].atlas.sha256 = "corrupted"
	expect(bad.image(str(bad.entries[0].id)) == null and bad.error.contains("hash"), "integridade divergente recusa bytes do recurso")
	var doc = Document.new(); doc.demo()
	doc.art.locked = true
	expect(not library.apply_tileset(doc, "kenney-tiny-town").ok and doc.undo_stack.is_empty(), "Art Lock recusa substituição sem checkpoint ou alteração")
	doc.art.locked = false
	var previous: String = doc.map_data.tileset_png
	doc.map_data.cells[0] = 1
	var applied: Dictionary = library.apply_tileset(doc, "kenney-tiny-town")
	expect(applied.ok and doc.map_data.cells[0] == -1 and doc.art.source_assets.size() == 1 and doc.validate().is_empty(), "tileset substitui a sala com fonte rastreável e mapa válido")
	expect(doc.undo() and doc.map_data.tileset_png == previous and doc.map_data.cells[0] == 1 and not doc.art.has("source_assets"), "Undo restaura tiles, células e metadados juntos")
	expect(doc.redo() and doc.art.source_assets.size() == 1 and doc.map_data.cells[0] == -1, "Redo reaplica importação inteira")
	var storage = Storage.new()
	var folder := "res://test_results/library-review-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("source.sfs.json")
	expect(storage.save_document(doc, path) == OK, "projeto importado salva por escrita atômica")
	var loaded: RefCounted = storage.load_document(path)
	expect(loaded != null and loaded.art.source_assets == doc.art.source_assets, "origem, licença e hash sobrevivem ao round-trip")
	var exported := folder.path_join("export")
	expect(storage.export_all(doc, ProjectSettings.globalize_path(exported)) == OK, "importação percorre exportação de PNG, JSON e cenas Godot")
	var meta: Variant = Storage.read_json(exported.path_join("metadata.json"))
	var credit_file := FileAccess.open(exported.path_join("CREDITS.txt"), FileAccess.READ)
	expect(meta is Dictionary and meta.source_assets == doc.art.source_assets and credit_file != null and credit_file.get_as_text().contains("Creative Commons Zero"), "exportação acompanha origem, hash e texto original da licença")
	if credit_file != null: credit_file.close()
	var worker = preload("res://core/batch_worker.gd")
	var batch_folder := folder.path_join("batch-" + str(Time.get_ticks_usec()))
	var request := {"id": "library-export", "input": path, "output": ProjectSettings.globalize_path(batch_folder), "kind": "export", "progress": folder.path_join("batch-progress.json"), "cancel": folder.path_join("cancel")}
	var batch_result: Dictionary = worker.execute(request)
	var batch_manifest: Dictionary = Storage.read_json(batch_folder.path_join("batch_manifest.json"))
	expect(batch_result.status == "done" and FileAccess.file_exists(batch_folder.path_join("CREDITS.txt")), "publicação por lote conserva o arquivo de créditos junto dos recursos")
	expect(FileAccess.file_exists(batch_folder.path_join("rooms.json")) and FileAccess.file_exists(batch_folder.path_join("examples/export/doorway.gd")) and FileAccess.file_exists(batch_folder.path_join("examples/export/room_transition.gd")) and FileAccess.file_exists(batch_folder.path_join("examples/export/pixel_camera.gd")) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(batch_folder.path_join(".sfs-stage-library-export"))), "lote publica recursivamente o índice e scripts sem deixar staging no pacote")
	expect(batch_manifest is Dictionary and batch_manifest.get("schema") == 3 and batch_manifest.get("checksums", {}).has("examples/export/doorway.gd") and batch_manifest.get("checksums", {}).has("rooms.json"), "manifesto do lote registra hashes dos arquivos auxiliares")
	expect(worker.execute(request).status == "cached", "cache valida também os créditos do recurso importado")
	var damaged := FileAccess.open(batch_folder.path_join("CREDITS.txt"), FileAccess.WRITE); damaged.store_string("truncated"); damaged.close()
	expect(worker.execute(request).status == "done" and FileAccess.get_file_as_string(batch_folder.path_join("CREDITS.txt")).contains("Creative Commons Zero"), "créditos alterados invalidam o cache e são republicados íntegros")
	var script_path := batch_folder.path_join("examples/export/doorway.gd")
	var damaged_script := FileAccess.open(script_path, FileAccess.WRITE); damaged_script.store_string("broken"); damaged_script.close()
	expect(worker.execute(request).status == "done" and FileAccess.get_file_as_string(script_path) == FileAccess.get_file_as_string("res://examples/export/doorway.gd"), "script de runtime alterado invalida o cache e é republicado íntegro")
	var malformed = Document.new(); malformed.art["source_assets"] = "invalid"
	expect(storage.export_all(malformed, ProjectSettings.globalize_path(folder.path_join("invalid"))) == ERR_INVALID_DATA, "metadados de procedência inválidos recusam exportação sem travar")
	var review = Review.new()
	var sample = storage.load_document("res://samples/sentinela_artist_v9.sfs.json")
	expect(sample != null and review.bind(sample), "revisor aceita coleção com idle, pulo e ataque")
	if sample != null:
		var fingerprint := JSON.stringify(storage.encode(sample))
		for direction in 8:
			review.direction = direction
			review.restart()
			var actual: Array = [{}, {}, {}]
			for step in 240:
				review.tick(1.0 / 60.0)
				for index in 3: actual[index][review.tracks[index].frame] = true
			var valid := true
			for index in 3:
				var metrics: Dictionary = review.metrics(index)
				valid = valid and actual[index].size() == 8 and metrics.poses == 6 and metrics.frames == 8 and review.image(index) != null
			expect(valid, "playback percorre oito quadros e seis poses dos três movimentos na direção " + sample.DIRECTIONS[direction])
		var frames_before: Array = review.tracks.map(func(track): return track.frame)
		review.playing = false; review.tick(1.0)
		expect(review.tracks.map(func(track): return track.frame) == frames_before, "pausa mantém todos os quadros estáveis")
		review.restart(); review.step(-1)
		expect(review.metrics(0).position == 8 and review.metrics(1).position == 8 and review.metrics(2).position == 8 and not review.playing, "avanço reverso faz wrap e pausa sem alterar o editor")
		review.step(1)
		expect(review.metrics(2).position == 1, "avanço manual reinicia no primeiro quadro")
		expect(JSON.stringify(storage.encode(sample)) == fingerprint, "prévia não altera seleção, pixels, timing nem aprovação do projeto")
		var changed: RefCounted = sample.detached_copy()
		var live_review = Review.new(); live_review.bind(changed)
		changed.animation.clips.remove_at(2); changed.mark_changed()
		expect(live_review.tick(0.1) and live_review.document == null and live_review.error.contains("attack"), "edição que remove ação invalida a prévia sem usar índices antigos")
	var invalid = Document.new()
	expect(not Review.new().bind(invalid), "projeto sem ações obrigatórias é recusado com diagnóstico")
	var rock := Node.new(); root.add_child(rock)
	var panel = preload("res://ui/animation_review_panel.gd").new(); rock.add_child(panel)
	expect(panel.bind(sample), "painel funciona sob Node neutro sem depender do Studio")
	var library_panel = preload("res://ui/public_asset_panel.gd").new(); rock.add_child(library_panel)
	expect(library_panel.filtered.size() == 27 and library_panel.preview.texture != null, "biblioteca apresenta catálogo e atlas sob Node neutro")
	var lpc_ui_index := -1
	for index in library_panel.filtered.size():
		if library_panel.filtered[index].get("id", "") == "lpc-male-walk": lpc_ui_index = index; break
	if lpc_ui_index >= 0: library_panel._select(lpc_ui_index)
	expect(lpc_ui_index >= 0 and library_panel.preview.texture != null and library_panel.tile_button.disabled and not library_panel.sheet_button.disabled and library_panel.description.text.contains("Linhas direcionais: N, W, S, E"), "painel apresenta a folha LPC como animação importável de quatro direções, não como tile")
	rock.queue_free()
	await process_frame
	var report := FileAccess.open("res://test_results/library-review-report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Library and review: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
