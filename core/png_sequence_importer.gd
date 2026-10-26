extends RefCounted
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const Validator = preload("res://core/export_validator.gd")
const Contracts = preload("res://core/contracts.gd")

func load_sequence(path: String, allow_modified: bool = false, expected_snapshot: Dictionary = {}) -> Dictionary:
	if path.get_file() != "sequence.json": return _fail("Selecione o arquivo sequence.json exportado pelo Sprite Forge.")
	var data: Variant = Storage.read_json(path)
	if not data is Dictionary: return _fail("Manifesto da sequência ausente ou inválido.")
	for key in ["width", "height", "frame_count", "fps"]:
		if not (data.get(key) is int or data.get(key) is float) or not is_finite(float(data[key])) or float(data[key]) != floor(float(data[key])): return _fail("Valores de dimensão ou animação inválidos.")
	if not data.get("source_assets", []) is Array: return _fail("Proveniência da sequência inválida.")
	if not data.get("family", "humanoid") is String or not data.get("skeleton", []) is Array: return _fail("Metadados do rig inválidos.")
	var width := int(data.get("width", 0))
	var height := int(data.get("height", 0))
	var frames := int(data.get("frame_count", 0))
	var fps := int(data.get("fps", 0))
	if width < 8 or width > 512 or height < 8 or height > 512 or frames < 1 or frames > 32 or fps < 1 or fps > 60 or width * height * 4 * frames * 8 > 67108864:
		return _fail("Dimensões, quadros, FPS ou memória excedem os limites do editor.")
	var folder := path.get_base_dir()
	var manifest_hash := FileAccess.get_sha256(path)
	if not Validator.validate_png_sequence(folder, false): return _fail("Arquivos, dimensões ou timing da sequência são inválidos.")
	var snapshot := {"manifest_sha256": manifest_hash, "files": {}}
	var changed: Array = []
	for row in data.frames:
		var digest := FileAccess.get_sha256(folder.path_join(row.file))
		snapshot.files[row.file] = digest
		if digest != row.sha256: changed.append({"file": row.file, "original_sha256": row.sha256, "actual_sha256": digest})
	if not expected_snapshot.is_empty() and snapshot != expected_snapshot: return _fail("A sequência mudou após a confirmação; selecione novamente os arquivos.")
	if not changed.is_empty() and not allow_modified:
		return {"ok": false, "requires_confirmation": true, "changed_frames": changed, "snapshot": snapshot, "error": "%d PNG(s) foram modificados desde a exportação." % changed.size()}
	var doc = Doc.new()
	if not doc.initialize_blank(width, height, frames, fps): return _fail("Não foi possível preparar o documento para a sequência.")
	if data.has("palette"):
		if not data.palette is Array or data.palette.is_empty() or data.palette.size() > 256: return _fail("Paleta inválida na sequência.")
		for color in data.palette:
			if not color is String or not Color.html_is_valid(color): return _fail("Cor inválida na paleta da sequência.")
		doc.palette = data.palette.duplicate()
	doc.layers[0].name = "Sequência PNG composta"
	doc.rig.family = str(data.get("family", "humanoid"))
	doc.layers[0].families = [doc.rig.family]
	doc.rig.skeleton = data.get("skeleton", []).duplicate(true)
	doc.anchors = data.frames[0].anchors.duplicate(true)
	if not doc.anchors.has("feet"): return _fail("A sequência precisa de uma âncora feet para o pivô do editor.")
	for row in data.frames:
		var direction: int = Doc.DIRECTIONS.find(row.direction)
		var frame := int(row.frame)
		var image := Image.load_from_file(folder.path_join(row.file))
		if image == null or FileAccess.get_sha256(folder.path_join(row.file)) != snapshot.files[row.file]: return _fail("Um PNG mudou durante a leitura. Nenhum documento foi adicionado.")
		doc.layers[0].cels[direction][frame] = image
		var key: String = doc.cel_key(direction, frame)
		doc.rig.anchors[key] = row.anchors.duplicate(true)
		doc.rig.anchors[key]["feet"] = row.pivot.duplicate()
		if not row.events.is_empty(): doc.animation.events[key] = row.events.duplicate(true)
		if not row.hitboxes.is_empty(): doc.animation.hitboxes[key] = row.hitboxes.duplicate(true)
	doc.animation.clips.clear()
	for source in data.clips:
		var clip := {"name": str(source.name), "frames": [], "durations_ms": {}, "loop": bool(source.loop)}
		for row in source.frames:
			var frame := int(row.frame)
			var key := str(frame)
			if clip.durations_ms.has(key) and not is_equal_approx(float(clip.durations_ms[key]), float(row.duration_ms)): return _fail("Um quadro repetido tem durações conflitantes no mesmo clip.")
			clip.frames.append(frame)
			clip.durations_ms[key] = float(row.duration_ms)
		doc.animation.clips.append(clip)
	if FileAccess.get_sha256(path) != manifest_hash: return _fail("O manifesto mudou durante a importação.")
	doc.manifest.name = "Sequência PNG importada"
	doc.art["status"] = "candidate"
	doc.art["source_assets"] = data.get("source_assets", []).duplicate(true)
	doc.art["png_sequence_import"] = {"manifest_sha256": manifest_hash, "source_project_id": data.get("project_id", ""), "source_revision": data.get("source_revision", 0), "modified_frames": changed, "composited": true, "review_required": true}
	if not Contracts.valid_extensions({"manifest": doc.manifest, "rig": doc.rig, "animation": doc.animation, "anchors": doc.anchors, "layers": doc.layers, "frames": doc.frames, "width": doc.width, "height": doc.height}): return _fail("Pivôs, âncoras, clips, eventos ou hitboxes incompatíveis com o editor.")
	var issues: Array = doc.validate()
	if not issues.is_empty(): return _fail("Metadados incompatíveis com o projeto: " + str(issues[0]))
	return {"ok": true, "document": doc, "changed_frames": changed}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
