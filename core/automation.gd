extends Node
class_name SFSAutomation
## Watches only top-level saved SFS projects. Orchestrator owns the work queue.
signal changed
signal work_requested(source: String, output: String, options: Dictionary, token: String)
const Storage = preload("res://core/storage.gd")
const Pipeline = preload("res://core/production_pipeline.gd")
var config_path: String = "user://automation.json"
var config: Dictionary = {"schema": 1, "input": "", "output": "", "enabled": false, "resume": false, "quantize": false, "require_nonempty": true, "interval": 5}
var ledger: Dictionary = {}
var error: String = ""
var elapsed: float = 0.0
var scanning: bool = false
var _files: PackedStringArray = []
var _cursor: int = 0
var _observed: Dictionary = {}
var _pending: Dictionary = {}
var settle_seconds: float = 2.0
var _hash_thread := Thread.new()
var _hash_job: Dictionary = {}
var _generation: int = 0

func _ready() -> void:
	add_to_group("Saveable")
	var saved = Storage.read_json(config_path)
	if saved is Dictionary and saved.get("schema") == 1 and saved.get("config") is Dictionary:
		var candidate: Dictionary = config.duplicate()
		for key in config: if saved.config.has(key) and typeof(saved.config[key]) == typeof(config[key]): candidate[key] = saved.config[key]
		if saved.config.get("interval") is float or saved.config.get("interval") is int: candidate.interval = clampi(int(saved.config.interval), 2, 3600)
		if candidate.input == "" or paths_valid(candidate.input, candidate.output): config = candidate
		if saved.get("ledger") is Dictionary:
			for token in saved.ledger.keys().slice(0, 2048):
				var entry = saved.ledger[token]
				if not token is String or not entry is Dictionary: continue
				if ["source", "output", "job_id", "status"].all(func(key): return entry.get(key) is String): ledger[token] = entry
		config.enabled = config.enabled and config.resume
	if config.enabled: elapsed = float(config.interval)

static func canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

static func paths_valid(input: String, output: String) -> bool:
	if input.strip_edges() == "" or output.strip_edges() == "": return false
	if input.begins_with("res://") or output.begins_with("res://"): return false
	var a := canonical(input)
	var b := canonical(output)
	var approved := canonical("user://approved_library")
	if b == approved or b.begins_with(approved + "/"): return false
	return a != b and not a.begins_with(b + "/") and not b.begins_with(a + "/")

func configure(values: Dictionary) -> bool:
	error = ""
	var candidate: Dictionary = config.duplicate()
	for key in ["input", "output", "enabled", "resume", "quantize", "require_nonempty", "interval"]:
		if values.has(key) and typeof(values[key]) == typeof(config[key]): candidate[key] = values[key]
	if not paths_valid(candidate.input, candidate.output) or not DirAccess.dir_exists_absolute(candidate.input): error = "Escolha pastas separadas, com entrada existente e saída fora da entrada."; changed.emit(); return false
	candidate.interval = clampi(candidate.interval, 2, 3600)
	config = candidate
	_generation += 1
	_files.clear(); _cursor = 0; scanning = false; _observed.clear(); _pending.clear()
	elapsed = float(config.interval)
	return persist()

func get_save_data() -> Dictionary:
	return {"schema": 1, "config": config, "ledger": ledger}

func persist() -> bool:
	var result := DirAccess.make_dir_recursive_absolute(config_path.get_base_dir())
	if result == OK: result = Storage.new().atomic_json(config_path, get_save_data())
	if result != OK: error = "Configuração de automação: " + error_string(result)
	changed.emit()
	return result == OK

func _process(delta: float) -> void:
	if config.enabled:
		elapsed += delta
		if not scanning and elapsed >= float(config.interval): scan_now()
	if scanning: scan_step()

func scan_now() -> void:
	if scanning: return
	error = ""
	if not paths_valid(config.input, config.output): error = "Pastas da automação inválidas."; changed.emit(); return
	var dir := DirAccess.open(config.input)
	if dir == null: error = "A pasta de entrada não está disponível."; changed.emit(); elapsed = 0; return
	_files = dir.get_files()
	_files.sort()
	_cursor = 0; scanning = true; elapsed = 0
	changed.emit()

func pause() -> void:
	config.enabled = false
	_generation += 1
	scanning = false; _files.clear(); _cursor = 0; _pending.clear()
	persist()

func scan_step() -> void:
	if not scanning: return
	if _hash_thread.is_started():
		if _hash_thread.is_alive(): return
		var hashed: Dictionary = _hash_thread.wait_to_finish()
		var finished := _hash_job
		_hash_job = {}
		if finished.generation == _generation and hashed.get("stable", false): _admit(finished, str(hashed.hash))
	# Metadata checks are incremental; SHA-256 reads run outside the UI thread.
	if _cursor >= _files.size(): scanning = false; changed.emit(); return
	var name := _files[_cursor]
	_cursor += 1
	if not name.to_lower().ends_with(".sfs.json"): return
	var source: String = config.input.path_join(name)
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null: return
	var size := file.get_length()
	file.close()
	if size <= 0 or size > Storage.MAX_FILE_BYTES: return
	var signature := str(FileAccess.get_modified_time(source)) + ":" + str(size)
	var key := canonical(source)
	var now := Time.get_ticks_msec() / 1000.0
	if not _observed.has(key) or _observed[key].signature != signature:
		_observed[key] = {"signature": signature, "since": now}; return
	if now - float(_observed[key].since) < settle_seconds: return
	_hash_job = {"source": source, "key": key, "signature": signature, "generation": _generation, "options": Pipeline.profile(config), "output": config.output, "name": name}
	var result := _hash_thread.start(_hash_file.bind(source, signature))
	if result != OK: _hash_job = {}; error = "Não foi possível verificar o arquivo em segundo plano."; changed.emit()

static func _hash_file(source: String, signature: String) -> Dictionary:
	var hash: String = FileAccess.get_sha256(source)
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null: return {"stable": false}
	var after := str(FileAccess.get_modified_time(source)) + ":" + str(file.get_length())
	file.close()
	return {"hash": hash, "stable": hash != "" and after == signature}

func _admit(job: Dictionary, hash: String) -> void:
	var token := (str(job.key) + Pipeline.fingerprint(hash, job.options) + canonical(job.output)).sha256_text()
	if ledger.has(token) or _pending.has(token): return
	if ledger.size() >= 2048: error = "Histórico de automação cheio. Limpe os registros concluídos antes de continuar."; changed.emit(); return
	var stem: String = str(job.name).trim_suffix(".sfs.json").validate_filename().left(64)
	var output: String = str(job.output).path_join(stem + "-" + token.left(16))
	_pending[token] = {"source": job.source, "output": output, "hash": hash}
	work_requested.emit(job.source, output, job.options, token)
	# If queue admission failed, the orchestrator calls reject().

func bind_job(token: String, job_id: String) -> void:
	if not _pending.has(token): return
	if job_id == "": reject(token, "Fila cheia ou indisponível."); return
	var entry: Dictionary = _pending[token]
	entry.merge({"token": token, "job_id": job_id, "status": "pending", "error": "", "at": Time.get_datetime_string_from_system()})
	ledger[token] = entry
	_pending.erase(token)
	persist()

func reject(token: String, reason: String) -> void:
	_pending.erase(token); error = reason; changed.emit()

func reconcile(jobs: Array) -> void:
	var index := {}
	for job in jobs: index[job.id] = job
	var dirty := false
	for entry in ledger.values():
		if not entry is Dictionary or not entry.has_all(["job_id", "status"]): continue
		if index.has(entry.job_id):
			var job: Dictionary = index[entry.job_id]
			if entry.status != job.status or entry.get("error", "") != job.error:
				entry.status = job.status; entry.error = job.error; dirty = true
		elif entry.status not in ["done", "cached", "failed", "cancelled", "missing"]:
			entry.status = "missing"; entry.error = "Tarefa não encontrada no checkpoint; reprocessamento exige nova solicitação."; dirty = true
	if dirty: persist()

func clear_finished() -> void:
	# Forgetting finished fingerprints intentionally permits processing them again.
	for token in ledger.keys():
		if ledger[token] is Dictionary and ledger[token].get("status") in ["done", "cached", "failed", "cancelled", "missing"]: ledger.erase(token)
	persist()

func _exit_tree() -> void:
	if _hash_thread.is_started(): _hash_thread.wait_to_finish()
