extends RefCounted
## Reads data and PNG only. Never runs scripts found in a supplied art folder.
const Doc = preload("res://core/document.gd")
const ORDER = [4, 5, 6, 7, 0, 1, 2, 3]
const LABELS = ["Frente", "Frente esquerda", "Esquerda", "Costas esquerda", "Costas", "Costas direita", "Direita", "Frente direita"]
var error: String = ""
var hashes: Dictionary = {}

func read_library(path: String) -> Dictionary:
	error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4194304: error = "Biblioteca indisponível ou acima de 4 MiB."; return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: error = "JSON de biblioteca inválido."; return {}
	var data = parser.data
	if not data is Dictionary or not data.get("families") is Dictionary or not data.get("directions") is Array or data.directions.size() != 8: error = "Formato de biblioteca modular não reconhecido."; return {}
	if data.directions != LABELS: error = "Convenção de vistas não reconhecida; mapeamento explícito necessário."; return {}
	return data

func image(path: String, relative: Variant) -> Image:
	if not relative is String or relative.is_absolute_path(): error = "Caminho de asset deve ser relativo."; return null
	var root := ProjectSettings.globalize_path(path.get_base_dir()).replace("\\", "/").simplify_path()
	var resolved := root.path_join(relative).simplify_path()
	if not resolved.to_lower().begins_with(root.to_lower() + "/"): error = "Asset fora da biblioteca."; return null
	# Keep res:// when reading originals embedded in a PCK.
	var source: String = path.get_base_dir().path_join(relative) if path.begins_with("res://") else resolved
	var file := FileAccess.open(source, FileAccess.READ)
	var bytes: PackedByteArray
	if file != null:
		if file.get_length() > 16777216: error = "PNG acima de 16 MiB."; return null
		bytes = file.get_buffer(file.get_length())
		file.close()
	elif path.begins_with("res://"):
		# Godot normally converts PNG resources; a data archive preserves exact source bytes.
		var archive := ZIPReader.new()
		if archive.open(path.get_base_dir().path_join("sources.zip")) == OK:
			if archive.file_exists(relative): bytes = archive.read_file(relative)
			archive.close()
	if bytes.is_empty() or bytes.size() > 16777216: error = "PNG ausente ou acima de 16 MiB: " + str(relative); return null
	if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]): error = "Assinatura PNG inválida."; return null
	var w: int = (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | int(bytes[19])
	var h: int = (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | int(bytes[23])
	if w < 1 or h < 1 or w > Doc.MAX_SIDE or h > Doc.MAX_SIDE: error = "Asset excede limite de 512 px."; return null
	var result := Image.new()
	if result.load_png_from_buffer(bytes) != OK: error = "PNG inválido."; return null
	result.convert(Image.FORMAT_RGBA8)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	hashes[relative] = digest.finish().hex_encode()
	return result

func import_family(path: String, selected: String, include_garments: bool = true) -> RefCounted:
	hashes.clear()
	var library := read_library(path)
	if library.is_empty() or not library.families.has(selected): error = "Família ausente ou biblioteca inválida. " + error; return null
	var family = library.families[selected]
	if not family is Dictionary or not family.get("views") is Array or family.views.size() != 8: error = "Família precisa conter oito vistas."; return null
	var bodies: Array = []
	for view in family.views:
		if not view is Dictionary or not view.get("file") is String: error = "Vista sem arquivo."; return null
		var body := image(path, view.file)
		if body == null: return null
		if not bodies.is_empty() and body.get_size() != bodies[0].get_size(): error = "As vistas têm canvases diferentes."; return null
		bodies.append(body)
	var doc = Doc.new()
	doc.width = bodies[0].get_width()
	doc.height = bodies[0].get_height()
	doc.frames = 1
	doc.layers.clear()
	doc.add_layer("Base • " + selected)
	doc.rig = {"family": {"humanoide": "humanoid", "canideo": "canid", "felino": "felid"}.get(selected, selected), "morphology": str(family.get("morphology", "unknown")), "pose": str(library.get("pose", "unknown")), "version": str(library.get("rig_version", "unknown")), "anchors": {}, "depth": {}, "offsets": {}}
	doc.anchors = {"feet": [int(doc.width / 2), doc.height - 1]}
	doc.animation = {"active": 0, "clips": [{"name": "static_pose", "frames": [0], "durations_ms": {}, "loop": false}], "events": {}, "hitboxes": {}}
	var counts := {}
	for d in 8:
		var view: Dictionary = family.views[ORDER[d]]
		doc.layers[0].cels[d][0] = bodies[ORDER[d]]
		var points := {}
		var pivot = view.get("pivot", [doc.width / 2, doc.height - 1])
		if not numeric_pair(pivot): error = "Pivô inválido."; return null
		points.feet = [roundi(pivot[0]), roundi(pivot[1])]
		if not view.get("anchors", {}) is Dictionary: error = "Âncoras inválidas."; return null
		for key in view.get("anchors", {}):
			var point = view.anchors[key]
			if not numeric_pair(point): error = "Coordenada de âncora inválida."; return null
			points[key] = [roundi(point[0]), roundi(point[1])]
		doc.rig.anchors[doc.cel_key(d, 0)] = points
		for key in points:
			if not doc.anchors.has(key): doc.anchors[key] = points[key].duplicate()
		var pixels: PackedByteArray = bodies[ORDER[d]].get_data()
		for i in range(0, pixels.size(), 4):
			if pixels[i + 3] == 0: continue
			var color: int = (int(pixels[i]) << 16) | (int(pixels[i + 1]) << 8) | int(pixels[i + 2])
			if counts.size() >= 65536 and not counts.has(color): continue
			counts[color] = int(counts.get(color, 0)) + 1
	var colors: Array = counts.keys()
	colors.sort_custom(func(a, b): return counts[a] > counts[b])
	if not colors.is_empty():
		doc.palette = colors.slice(0, 16).map(func(c): return "#%06x" % int(c))
	if include_garments:
		var garments = library.get("garments", {})
		if not garments is Dictionary: error = "Catálogo de roupas inválido."; return null
		for name in garments:
			var garment = garments[name]
			if not garment is Dictionary: error = "Roupa inválida."; return null
			if garment.get("family") != selected: continue
			if not add_garment(doc, path, family, garment, str(name)): return null
	doc.active_layer = 0
	doc.direction = 4
	doc.manifest.name = "Arton • " + selected
	doc.manifest.source = {"library_sha256": FileAccess.get_sha256(path), "family": selected, "status": str(family.get("status", "unreviewed")), "complete_skeleton": family.get("complete_skeleton", false), "anatomy_status": str(family.get("anatomy_status", "unreviewed")), "files": hashes.duplicate(), "approval": "imported_not_approved", "note": "Oito vistas estáticas. Nenhuma animação gerada; aprovação da fonte não equivale a aprovação no SFS."}
	doc.art.bible = str(library.get("art_bible", "Acervo local Crônicas de Arton; direção artística a revisar."))
	doc.dirty = true
	var issues: Array = doc.validate()
	if not issues.is_empty(): error = "; ".join(issues); return null
	return doc

func numeric_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))

func add_garment(doc: RefCounted, path: String, family: Dictionary, garment: Dictionary, name: String) -> bool:
	if not garment.get("views") is Array or garment.views.size() != 8: error = "Roupa sem oito vistas."; return false
	if garment.get("morphology") != doc.rig.morphology or garment.get("pose") != doc.rig.pose: error = "Roupa incompatível com morfologia/pose."; return false
	# This adapter reproduces the source's explicit neck/hem calibration only.
	for view in family.views:
		if not view.get("anchors", {}).has_all(["neck", "hem"]) or not view.get("torso_width") is float and not view.get("torso_width") is int: error = "Calibração de torso ausente; não foi inventado encaixe."; return false
	var previous_count: int = doc.layers.size()
	doc.add_layer(name, true)
	if doc.layers.size() == previous_count: error = "Limite de camadas ou memória excedido."; return false
	var layer: Dictionary = doc.layers[-1]
	layer.visible = false
	layer.anchor = "neck"
	layer.compatibility = {"morphology": doc.rig.morphology, "pose": doc.rig.pose, "version": doc.rig.version}
	layer.source_transforms = []
	for d in 8:
		var base: Dictionary = family.views[ORDER[d]]
		var entry = garment.views[ORDER[d]]
		if not entry is Dictionary or not entry.get("file") is String: error = "Vista da roupa inválida."; return false
		var pixels := image(path, entry.file)
		if pixels == null: return false
		var target := Vector2i(roundi(float(base.torso_width)), roundi(float(base.anchors.hem[1]) - float(base.anchors.neck[1])))
		if target.x < 1 or target.y < 1 or target.x > doc.width or target.y > doc.height: error = "Encaixe fora do canvas."; return false
		var original_size := pixels.get_size()
		pixels.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
		layer.cels[d][0].blit_rect(pixels, Rect2i(Vector2i.ZERO, target), Vector2i.ZERO)
		doc.rig.offsets[doc.cel_key(d, 0)] = {layer.id: [-roundi(target.x / 2.0), 0]}
		layer.source_transforms.append({"source": entry.file, "original_size": [original_size.x, original_size.y], "fitted_size": [target.x, target.y], "method": "existing_source_neck_hem_calibration", "status": "candidate_not_approved"})
	return true
