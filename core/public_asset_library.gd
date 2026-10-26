extends RefCounted
## Offline catalogue. Bundled PNG bytes are verified before decoding; imports remain candidates.
const MANIFEST := "res://assets/public_library/catalog.json"
const ARCHIVE := "res://assets/public_library/sources.zip"
const Document = preload("res://core/document.gd")
const World = preload("res://core/world_data.gd")
var entries: Array = []
var error := ""

func _init() -> void:
	var data: Variant = preload("res://core/storage.gd").read_json(MANIFEST)
	if data is Dictionary and data.get("schema") == 1 and data.get("entries") is Array:
		entries = data.entries
	else: error = "Catálogo público ausente ou inválido."

func find(id: String) -> Dictionary:
	for entry in entries:
		if entry.get("id") == id: return entry.duplicate(true)
	return {}

func search(query: String = "", installed_only: bool = false) -> Array:
	var result: Array = []
	var term := query.strip_edges().to_lower()
	for entry in entries:
		if installed_only and not (entry.has("atlas") or entry.has("spritesheet")): continue
		var searchable := (str(entry.get("name", "")) + " " + str(entry.get("categories", [])) + " " + str(entry.get("author", ""))).to_lower()
		if term.is_empty() or searchable.contains(term): result.append(entry.duplicate(true))
	return result

func image(id: String) -> Image:
	error = ""
	var entry := find(id)
	var is_atlas: bool = entry.has("atlas")
	if not is_atlas and not entry.has("spritesheet"): error = "Esta fonte está catalogada, mas não há PNG incorporado."; return null
	if is_atlas and entry.get("license") != "CC0-1.0": error = "Atlas de tiles incorporado exige licença CC0 verificada."; return null
	if not is_atlas and str(entry.get("license", "")) not in ["CC-BY 4.0", "CC-BY-SA 4.0", "CC-BY-SA 3.0"]:
		error = "Spritesheet incorporado sem licença redistribuível aprovada."; return null
	var asset: Dictionary = entry.atlas if is_atlas else entry.spritesheet
	var zip := ZIPReader.new()
	if zip.open(ARCHIVE) != OK: error = "Arquivo de recursos indisponível."; return null
	var bytes := zip.read_file(str(asset.get("member", "")))
	zip.close()
	var byte_limit := 4194304 if is_atlas else 16777216
	if bytes.is_empty() or bytes.size() > byte_limit: error = "PNG ausente ou acima do limite permitido para esta categoria."; return null
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	if hash.finish().hex_encode() != str(asset.get("sha256", "")): error = "O hash do recurso não confere; importação recusada."; return null
	var decoded := Image.new()
	if decoded.load_png_from_buffer(bytes) != OK or decoded.get_width() != int(asset.get("width", 0)) or decoded.get_height() != int(asset.get("height", 0)):
		error = "Dimensões ou conteúdo PNG inválidos."; return null
	if decoded.get_width() > 4096 or decoded.get_height() > 4096 or decoded.get_data().size() > 67108864:
		error = "Imagem incorporada excede 4096 px por lado ou 64 MiB descompactados."; return null
	if is_atlas and (decoded.get_width() > 256 or decoded.get_height() > 256 or decoded.get_width() % 16 or decoded.get_height() % 16):
		error = "O atlas incorporado não atende à grade de 16 px."; return null
	decoded.convert(Image.FORMAT_RGBA8)
	return decoded

func provenance(id: String) -> Dictionary:
	var entry := find(id)
	var notice := ""
	var zip := ZIPReader.new()
	if (entry.has("atlas") or entry.has("spritesheet")) and zip.open(ARCHIVE) == OK:
		var evidence_bytes := zip.read_file(str(entry.get("license_evidence", "")))
		if evidence_bytes.size() <= 65536: notice = evidence_bytes.get_string_from_utf8()
		var total_credit_bytes := 0
		for member in entry.get("credit_members", []):
			var credit_bytes := zip.read_file(str(member))
			total_credit_bytes += credit_bytes.size()
			if credit_bytes.is_empty() or total_credit_bytes > 262144: continue
			notice += "\n\n--- %s ---\n%s" % [str(member).get_file(), credit_bytes.get_string_from_utf8()]
		zip.close()
	var asset: Dictionary = entry.get("atlas", entry.get("spritesheet", {}))
	return {"catalog_id": id, "name": entry.get("name", ""), "author": entry.get("author", ""), "source": entry.get("source", ""), "license": entry.get("license", "unknown"), "license_evidence": entry.get("license_evidence", ""), "credit_files": entry.get("credit_members", []), "license_notice": notice, "checked_at": entry.get("checked_at", ""), "sha256": asset.get("sha256", ""), "art_approved": false, "use": "imported_candidate"}

## Call after a successful spritesheet importer operation, which already created the undo checkpoint.
func record_spritesheet_import(document: RefCounted, id: String, details: Dictionary) -> Dictionary:
	if document == null or not find(id).has("spritesheet"): return {"ok": false, "error": "Spritesheet ou documento ausente."}
	if document.art.get("locked", false): return {"ok": false, "error": "Art Lock impede registrar a importação."}
	var record := provenance(id)
	if record.is_empty() or str(record.get("sha256", "")).is_empty(): return {"ok": false, "error": "Procedência do recurso indisponível."}
	record["import_details"] = details.duplicate(true)
	var sources: Array = document.art.get("source_assets", []).duplicate(true) if document.art.get("source_assets", []) is Array else []
	if not sources.has(record): sources.append(record)
	document.art["source_assets"] = sources
	document.manifest.approvals = []
	document.mark_changed()
	return {"ok": true, "record": record}

func tile_document(id: String, index: int) -> RefCounted:
	var entry := find(id)
	var asset: Dictionary = entry.get("atlas", entry.get("spritesheet", {}))
	var cell_size := int(asset.get("cell_size", 0))
	if not entry.has("atlas") and not entry.has("spritesheet"):
		error = "Esta fonte ainda não tem imagem incorporada."; return null
	if cell_size < 1 or cell_size > 512 or int(asset.get("width", 0)) % cell_size != 0 or int(asset.get("height", 0)) % cell_size != 0:
		error = "A folha não declara uma grade de tiles compatível; use Importar spritesheet."; return null
	var atlas := image(id)
	if atlas == null: return null
	var columns := atlas.get_width() / cell_size
	var count := columns * (atlas.get_height() / cell_size)
	if index < 0 or index >= count: error = "Índice de tile inválido."; return null
	var doc = Document.new()
	doc.layers.clear(); doc.width = cell_size; doc.height = cell_size; doc.frames = 1
	doc.anchors = {"origin": [0, 0]}
	doc.rig.family = "custom"; doc.rig.skeleton = []
	doc.add_layer("Tile importado")
	doc.layers[0].anchor = "origin"; doc.layers[0].pivot = "origin"; doc.layers[0].families = ["custom"]
	doc.direction = 4
	doc.layers[0].cels[4][0] = atlas.get_region(Rect2i((index % columns) * cell_size, (index / columns) * cell_size, cell_size, cell_size))
	doc.animation = {"active": 0, "clips": [{"name": "static", "frames": [0], "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	doc.manifest.name = str(find(id).name) + " — tile " + str(index)
	doc.manifest.provenance = str(find(id).source)
	doc.art["candidate_status"] = "candidate"
	doc.art["direction_coverage"] = ["S"]
	doc.art["source_assets"] = [provenance(id)]
	doc.art.bible = "Tile recortado de uma fonte pública para edição e estudo. Verifique a atribuição e a licença registradas no projeto; arte não aprovada para o Art Lock mestre."
	doc.dirty = true
	return doc

func apply_tileset(doc: RefCounted, id: String) -> Dictionary:
	if doc == null or doc.art.get("locked", false): return {"ok": false, "error": "Art Lock ativo ou projeto ausente."}
	if not find(id).has("atlas"): return {"ok": false, "error": "Este recurso não é um atlas CC0 de tiles compatível com aplicação direta ao mapa."}
	var atlas := image(id)
	if atlas == null: return {"ok": false, "error": error}
	doc.checkpoint("Aplicar tileset da biblioteca pública")
	doc.map_data.tileset_png = Marshalls.raw_to_base64(atlas.save_png_to_buffer())
	doc.map_data.terrain_sets.clear()
	for layer in World.layers(doc.map_data): layer.cells.fill(-1); layer.terrain.fill(-1)
	World.sync_active_room(doc.map_data)
	var sources: Array = doc.art.get("source_assets", []).duplicate(true)
	var record := provenance(id)
	if not sources.has(record): sources.append(record)
	doc.art["source_assets"] = sources
	doc.art["candidate_status"] = "candidate"
	doc.manifest.approvals = []
	return {"ok": true, "tiles": (atlas.get_width() / 16) * (atlas.get_height() / 16)}
