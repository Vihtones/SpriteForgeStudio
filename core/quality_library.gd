extends RefCounted
const Storage = preload("res://core/storage.gd")
const Precision = preload("res://core/precision.gd")
const CharacterAudit = preload("res://core/character_audit.gd")
var root: String = "user://approved_library"
var error: String = ""

func score(values: Array) -> Dictionary:
	if values.size() != 4: return {"passed": false, "total": 0}
	var total: float = 0
	var weights := [0.35, 0.25, 0.25, 0.15]
	var passed := true
	for i in 4:
		if not values[i] is float and not values[i] is int: return {"passed": false, "total": 0}
		if values[i] < 0 or values[i] > 100: return {"passed": false, "total": 0}
		total += float(values[i]) * weights[i]
		if values[i] < 75: passed = false
	return {"passed": passed and total >= 85, "total": total}

func reopen_rejected_candidate(doc: RefCounted) -> bool:
	error = ""
	if doc.art.locked: error = "Desative o Art Lock antes de revisar a arte."; return false
	if str(doc.art.get("candidate_status", "")) != "rejected": error = "O candidato não está reprovado."; return false
	if doc.revision <= int(doc.art.get("rejection_revision", doc.revision)):
		error = "Faça uma alteração na arte antes de abrir uma nova revisão."; return false
	doc.checkpoint("Abrir nova revisão artística")
	doc.art.candidate_status = "revision_pending"
	doc.mark_changed()
	return true

func approve(doc: RefCounted, values: Array, reviewer: String, human_confirmed: bool, require_character_gate: bool = false) -> bool:
	error = ""
	if not human_confirmed or reviewer.strip_edges().is_empty(): error = "Identifique o revisor e confirme a revisão humana."; return false
	var candidate_status := str(doc.art.get("candidate_status", "candidate"))
	if candidate_status == "rejected": error = "Arte reprovada não pode ser adicionada à biblioteca aprovada. Substitua-a e abra uma nova revisão."; return false
	if candidate_status == "revision_pending" and not require_character_gate: error = "Esta versão reaberta exige o portão de personagem e uma nova revisão humana."; return false
	var assessment := score(values)
	if not assessment.passed or not doc.validate().is_empty(): error = "Critérios de qualidade ou integridade não atingidos."; return false
	var technical_gate: Dictionary = {}
	if require_character_gate:
		if str(doc.art.get("candidate_status", "candidate")) == "rejected":
			error = "Esta arte foi reprovada e não pode ser aprovada como personagem. Substitua-a e abra uma nova revisão."; return false
		technical_gate = CharacterAudit.new().evaluate(doc)
		if not technical_gate.technical_passed:
			error = "A prova técnica do personagem falhou. Corrija as animações e execute a avaliação novamente."; return false
	var storage := Storage.new()
	var id := Crypto.new().generate_random_bytes(12).hex_encode()
	var folder := root.path_join(doc.manifest.id)
	if DirAccess.make_dir_recursive_absolute(folder) != OK: error = "Não foi possível criar biblioteca."; return false
	var entry := {"id": id, "reviewer": reviewer, "scores": values.duplicate(), "total": assessment.total, "at": Time.get_datetime_string_from_system(), "human": true, "revision": doc.revision}
	if require_character_gate:
		entry["technical_gate"] = {"passed": true, "checks": technical_gate.checks.size(), "summary": technical_gate.summary, "revision": doc.revision}
	doc.checkpoint()
	doc.manifest.approvals.append(entry)
	if require_character_gate: doc.art.candidate_status = "approved"
	var result := storage.atomic_json(folder.path_join(id + ".sfs.json"), storage.encode(doc))
	if result != OK: doc.undo(); error = error_string(result); return false
	return true

func versions(doc: RefCounted) -> Array:
	var result: Array = []
	var folder := root.path_join(doc.manifest.id)
	var directory := DirAccess.open(folder)
	if directory == null: return result
	for name in directory.get_files():
		if name.ends_with(".sfs.json"): result.append({"id": name.trim_suffix(".sfs.json"), "path": folder.path_join(name)})
	result.sort_custom(func(a, b): return a.id < b.id)
	return result

func compare(doc: RefCounted, version_path: String) -> Dictionary:
	var storage := Storage.new()
	var old = storage.load_document(version_path)
	if old == null: return {"error": storage.error}
	if old.width != doc.width or old.height != doc.height: return {"error": "Dimensões diferentes."}
	var before: Image = old.composite(mini(doc.direction, 7), mini(doc.frame, old.frames - 1))
	var after: Image = doc.composite()
	var changed: int = 0
	for y in doc.height:
		for x in doc.width:
			if before.get_pixel(x, y) != after.get_pixel(x, y): changed += 1
	return {"before": before, "after": after, "changed": changed, "technical": doc.validate().is_empty(), "artistic_approval": false}
