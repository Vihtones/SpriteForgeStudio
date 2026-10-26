extends Node
class_name SFSWorkspace
## Owns open documents and serial background persistence. No UI references.
signal activated(record: Dictionary)
signal changed
signal persisted(kind: String, session_id: String, result: int, target: String)
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const MAX_DOCUMENTS = 8
const MAX_PIXEL_BYTES = 268435456
var data_root: String = "user://workspace"
var records: Array[Dictionary] = []
var active_id: String = ""
var error: String = ""
var _thread := Thread.new()
var _pending: Array[Dictionary] = []
var _current: Dictionary = {}
var _recovery: Dictionary = {}
var _new_number: int = 0
var _exiting: bool = false
var _restoring: bool = false
var _checkpoint_again: bool = false
var protected_roots: Array[String] = ["user://approved_library"]
var pixel_budget_bytes: int = MAX_PIXEL_BYTES

func _ready() -> void:
	add_to_group("Saveable")

func find(id: String) -> Dictionary:
	for record in records:
		if record.id == id: return record
	return {}

func current() -> Dictionary:
	return find(active_id)

func recovery_revision(id: String) -> int:
	return int(_recovery.get(id, {}).get("revision", -1))

func canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().to_lower() if path != "" else ""

static func _resolve_reparse_points(path: String) -> String:
	# Resolve Windows junctions/symlinks as well as Unix symlinks before enforcing
	# protected-library boundaries. The final file may not exist yet, so inspect
	# each existing path component rather than relying on realpath of the leaf.
	if path.is_empty(): return ""
	var absolute := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	if absolute.is_empty() or (not absolute.begins_with("/") and absolute.find(":/") != 1): return ""
	for _iteration in 64:
		var parts := absolute.split("/", false)
		var prefix := ""
		var first_component := 0
		if absolute.begins_with("/"):
			prefix = "/"
		elif parts.size() > 0 and parts[0].ends_with(":"):
			prefix = parts[0] + "/"
			first_component = 1
		var replaced := false
		for index in range(first_component, parts.size()):
			if parts[index].is_empty(): continue
			if not prefix.ends_with("/"): prefix += "/"
			prefix += parts[index]
			var parent_dir := DirAccess.open(prefix.get_base_dir())
			if parent_dir != null and parent_dir.is_link(prefix.get_file()):
				var link_target := parent_dir.read_link(prefix.get_file())
				if link_target.is_empty(): return ""
				link_target = link_target.replace("\\", "/")
				if not link_target.begins_with("/") and link_target.find(":/") != 1:
					link_target = prefix.get_base_dir().path_join(link_target)
				var suffix := "/".join(parts.slice(index + 1))
				absolute = (link_target.path_join(suffix) if not suffix.is_empty() else link_target).simplify_path()
				replaced = true
				break
		if not replaced: return absolute
	return ""

func _save_target_is_protected(target: String) -> bool:
	var resolved_target := _resolve_reparse_points(target)
	if resolved_target.is_empty(): return true
	var target_key := resolved_target.to_lower().trim_suffix("/")
	for root in protected_roots:
		var resolved_root := _resolve_reparse_points(root)
		if resolved_root.is_empty(): return true
		var root_key := resolved_root.to_lower().trim_suffix("/")
		if target_key == root_key or target_key.begins_with(root_key + "/"): return true
	return false

func add_document(doc: RefCounted, path: String = "", pristine: bool = false, session_id: String = "") -> String:
	error = ""
	if path != "":
		for record in records:
			if canonical(record.path) == canonical(path) or canonical(destination(record.id)) == canonical(path): activate(record.id); return record.id
	var used: int = 0
	for record in records: used += record.doc.pixel_bytes()
	if records.size() >= MAX_DOCUMENTS or used + doc.pixel_bytes() > pixel_budget_bytes:
		error = "Limite de 8 documentos ou 256 MiB de buffers abertos atingido."
		return ""
	_new_number += 1
	var id := Crypto.new().generate_random_bytes(12).hex_encode() if session_id == "" else session_id
	if not find(id).is_empty(): error = "Identificador de sessão duplicado."; return ""
	var record := {"id": id, "doc": doc, "path": path, "title": path.get_file() if path != "" else "Sem título " + str(_new_number), "view": {"zoom": minf(14, 440.0 / doc.width), "pan": [0, 0], "fit": true}, "pristine": pristine, "saved_revision": doc.revision if path != "" and not doc.dirty else -1}
	records.append(record)
	activate(id)
	changed.emit()
	return id

func activate(id: String) -> bool:
	var record := find(id)
	if record.is_empty(): return false
	active_id = id
	refresh_budgets()
	activated.emit(record)
	return true

func close_document(id: String, discard: bool = false, keep_one: bool = true) -> bool:
	var record := find(id)
	if record.is_empty() or (record.doc.dirty and not discard): return false
	var index: int = records.find(record)
	records.remove_at(index)
	_recovery.erase(id)
	if records.is_empty():
		active_id = ""
		if keep_one: add_document(Doc.new(), "", true)
	elif active_id == id: activate(records[mini(index, records.size() - 1)].id)
	changed.emit()
	if not _restoring: _write_manifest()
	return true

func request_save(id: String, target: String) -> bool:
	var record := find(id)
	if record.is_empty() or target.is_empty(): error = "Documento ou destino inválido."; return false
	if _save_target_is_protected(target): error = "A biblioteca aprovada é somente leitura; escolha outro local."; return false
	for other in records:
		if other.id != id and canonical(other.path) == canonical(target): error = "Este arquivo já pertence a outra aba aberta."; return false
	for job in _pending:
		if job.kind == "save" and job.id != id and canonical(job.target) == canonical(target): error = "Outra aba já está salvando nesse destino."; return false
	if not _current.is_empty() and _current.kind == "save" and _current.id != id and canonical(_current.target) == canonical(target): error = "Outra aba está gravando esse arquivo."; return false
	_pending = _pending.filter(func(job): return not (job.kind == "save" and job.id == id))
	var snapshot: RefCounted = record.doc.detached_copy()
	snapshot.manifest.name = target.get_file().trim_suffix(".sfs.json")
	_pending.push_front({"kind": "save", "id": id, "target": target, "revision": record.doc.revision, "snapshot": snapshot})
	changed.emit()
	return true

func destination(id: String) -> String:
	for job in _pending:
		if job.kind == "save" and job.id == id: return job.target
	if not _current.is_empty() and _current.kind == "save" and _current.id == id: return _current.target
	return str(find(id).get("path", ""))

func refresh_budgets() -> void:
	var used: int = 0
	for record in records: used += record.doc.pixel_bytes()
	for record in records: record.doc.pixel_budget_limit = mini(67108864, maxi(record.doc.pixel_bytes(), pixel_budget_bytes - used + record.doc.pixel_bytes()))

func request_export_snapshot(id: String, target: String) -> bool:
	var record := find(id)
	if record.is_empty(): error = "Documento não encontrado."; return false
	_pending.push_front({"kind": "export_snapshot", "id": id, "target": target, "revision": record.doc.revision, "snapshot": record.doc.detached_copy()})
	return true

func request_checkpoint() -> bool:
	if _pending.any(func(job): return job.kind == "checkpoint") or (not _current.is_empty() and _current.kind == "checkpoint"):
		# Keep one coalesced follow-up so edits made while the snapshot is being
		# serialized are not left waiting for the next 30-second autosave tick.
		_checkpoint_again = true
		return true
	var snapshots: Array = []
	for record in records:
		if record.path != "" and not record.doc.dirty: continue
		if _recovery.has(record.id) and _recovery[record.id].revision == record.doc.revision: continue
		snapshots.append({"id": record.id, "revision": record.doc.revision, "snapshot": record.doc.detached_copy(), "target": data_root.path_join("recovery").path_join(record.id + ".sfs.json")})
	if snapshots.is_empty():
		_write_manifest()
		return true
	_pending.append({"kind": "checkpoint", "id": "", "items": snapshots})
	return true

func busy() -> bool:
	return _thread.is_started() or not _pending.is_empty()

func _process(_delta: float) -> void:
	if _thread.is_started() and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish()
		var finished: Dictionary = _current
		_current = {}
		_apply_result(finished, result)
	if not _thread.is_started() and not _pending.is_empty():
		_current = _pending.pop_front()
		var result := _thread.start(_write_job.bind(_current))
		if result != OK:
			var failed: Dictionary = _current
			_current = {}
			_apply_result(failed, {"result": result})

static func _write_job(job: Dictionary) -> Dictionary:
	var storage := Storage.new()
	if job.kind in ["save", "export_snapshot"]: return {"result": storage.save_document(job.snapshot, job.target)}
	var entries: Array = []
	for item in job.items:
		var result := DirAccess.make_dir_recursive_absolute(item.target.get_base_dir())
		if result == OK: result = storage.save_document(item.snapshot, item.target)
		if result != OK: return {"result": result}
		entries.append({"id": item.id, "revision": item.revision, "recovery_path": item.target})
	return {"result": OK, "entries": entries}

func _apply_result(job: Dictionary, report: Dictionary) -> void:
	var result: int = int(report.get("result", FAILED))
	if result == OK:
		error = ""
		if job.kind == "save":
			var record := find(job.id)
			if not record.is_empty():
				record.path = job.target
				record.title = job.target.get_file()
				record.doc.manifest.name = job.snapshot.manifest.name
				record.saved_revision = job.revision
				record.pristine = false
				if record.doc.revision == job.revision: record.doc.dirty = false
				_recovery.erase(job.id)
		elif job.kind == "checkpoint":
			for entry in report.get("entries", []):
				var record := find(entry.id)
				if not record.is_empty() and entry.revision >= record.saved_revision: _recovery[entry.id] = entry
		var manifest_result := _write_manifest()
		if manifest_result != OK:
			error = "Recuperação da sessão: " + error_string(manifest_result)
			if job.kind == "checkpoint": result = manifest_result
	else: error = error_string(result)
	if not _exiting:
		changed.emit()
		persisted.emit(job.kind, job.id, result, job.get("target", ""))
	if job.kind == "checkpoint" and _checkpoint_again:
		_checkpoint_again = false
		request_checkpoint()

func get_save_data() -> Dictionary:
	var entries: Array = []
	for record in records:
		var recovery: Dictionary = _recovery.get(record.id, {})
		entries.append({"id": record.id, "path": record.path, "title": record.title, "view": record.view, "context": {"frame": record.doc.frame, "direction": record.doc.direction, "layer": record.doc.active_layer, "clip": int(record.doc.animation.active)}, "dirty": record.doc.dirty, "recovery_path": recovery.get("recovery_path", "")})
	return {"schema": 1, "active": active_id, "documents": entries}

func _write_manifest() -> Error:
	var result := DirAccess.make_dir_recursive_absolute(data_root)
	return Storage.new().atomic_json(data_root.path_join("session.json"), get_save_data()) if result == OK else result

func restore_session() -> int:
	error = ""
	var data = Storage.read_json(data_root.path_join("session.json"))
	if not data is Dictionary or data.get("schema") != 1 or not data.get("documents") is Array: error = "Não há sessão de recuperação válida."; return 0
	_restoring = true
	if records.size() == 1 and records[0].pristine and not records[0].doc.dirty: close_document(records[0].id, false, false)
	var restored: int = 0
	var storage := Storage.new()
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-f0-9]{24}$")
	for entry in data.documents.slice(0, MAX_DOCUMENTS):
		if not entry is Dictionary or not entry.get("id") is String or id_pattern.search(entry.id) == null or not entry.get("path") is String: continue
		var recovery_path: String = str(entry.get("recovery_path", ""))
		var expected := data_root.path_join("recovery").path_join(entry.id + ".sfs.json")
		if recovery_path != "" and canonical(recovery_path) != canonical(expected): continue
		var source: String = recovery_path if recovery_path != "" and FileAccess.file_exists(recovery_path) else entry.path
		if source == "": continue
		var doc = storage.load_document(source)
		if doc == null: continue
		doc.dirty = bool(entry.get("dirty", false))
		var context = entry.get("context", {})
		if context is Dictionary:
			var limits := {"frame": doc.frames - 1, "direction": 7, "layer": doc.layers.size() - 1, "clip": doc.animation.clips.size() - 1}
			for key in limits:
				if not context.get(key) is int and not context.get(key) is float: continue
				var value := clampi(int(context[key]), 0, int(limits[key]))
				match key:
					"frame": doc.frame = value
					"direction": doc.direction = value
					"layer": doc.active_layer = value
					"clip": doc.animation.active = value
		var existing: bool = records.any(func(record): return entry.path != "" and canonical(record.path) == canonical(entry.path))
		if existing or not find(entry.id).is_empty(): continue
		var id := add_document(doc, entry.path, false, entry.id)
		if id == "": continue
		var record := find(id)
		if entry.get("title") is String: record.title = entry.title.left(600)
		if entry.get("view") is Dictionary and entry.view.get("pan") is Array and entry.view.pan.size() == 2:
			var zoom = entry.view.get("zoom", 14)
			var pan: Array = entry.view.pan
			if (zoom is int or zoom is float) and (pan[0] is int or pan[0] is float) and (pan[1] is int or pan[1] is float): record.view = {"zoom": clampf(float(zoom), 0.5, 40), "pan": [float(pan[0]), float(pan[1])]}
		if recovery_path != "": _recovery[id] = {"id": id, "revision": doc.revision, "recovery_path": recovery_path}
		restored += 1
	if not activate(str(data.get("active", ""))) and not records.is_empty(): activate(records[-1].id)
	if records.is_empty(): add_document(Doc.new(), "", true)
	if restored == 0: error = "Nenhum documento recuperável novo; abas existentes foram preservadas."
	_restoring = false
	_write_manifest()
	return restored

func flush() -> void:
	while _thread.is_started() or not _pending.is_empty():
		if _thread.is_started():
			var report: Dictionary = _thread.wait_to_finish()
			var finished := _current
			_current = {}
			_apply_result(finished, report)
		elif not _pending.is_empty():
			var job: Dictionary = _pending.pop_front()
			_apply_result(job, _write_job(job))

func _exit_tree() -> void:
	_exiting = true
	flush()
