extends Node
signal updated
const Storage = preload("res://core/storage.gd")
var jobs: Array = []
var running: bool = false
var checkpoint_path: String = "user://batch_checkpoint.json"
var request_root: String = "user://batch_requests"
var store = Storage.new()
var active_pid: int = -1
var active_id: String = ""
var result_path: String = ""
var progress_path: String = ""
var cancel_path: String = ""
var ram_budget_mb: int = 1024
var last_error: String = ""
var last_progress: String = ""
var resume_on_start: bool = false
var worker_timeout_seconds: float = 900.0
var active_started: int = 0

func _ready() -> void:
	if FileAccess.file_exists(checkpoint_path):
		var data = Storage.read_json(checkpoint_path)
		if data is Dictionary and data.get("jobs") is Array:
			resume_on_start = data.get("resume_on_start", false) == true
			for job in data.jobs.slice(0, 256):
				if job is Dictionary and job.has_all(["input", "output", "status", "hash", "error"]):
					job = normalize(job)
					if job.status in ["running", "preparing", "validating"]: job.status = "pending"
					jobs.append(job)
	running = resume_on_start and jobs.any(func(job): return job.status == "pending")

func normalize(job: Dictionary) -> Dictionary:
	var defaults := {"id": Crypto.new().generate_random_bytes(12).hex_encode(), "priority": 0, "dependencies": [], "estimated_mb": 256, "attempts": 0, "max_attempts": 3, "elapsed_ms": 0, "history": [], "progress": 0, "kind": "export", "parameters": {}, "project_path": "", "report_path": "", "validation": {}, "next_attempt_at": 0}
	job.merge(defaults)
	return job

func enqueue(input: String, output: String, priority: int = 0, dependencies: Array = [], kind: String = "export", parameters: Dictionary = {}) -> String:
	if jobs.size() >= 256: return ""
	for job in jobs:
		if job.input == input and job.output == output and job.kind == kind and job.parameters == parameters and job.status in ["pending", "running", "preparing", "validating"]: return job.id
	var job := normalize({"input": input, "output": output, "status": "pending", "hash": "", "error": "", "priority": priority, "dependencies": dependencies.duplicate(), "kind": kind, "parameters": parameters.duplicate(true)})
	jobs.append(job)
	persist()
	return job.id

func persist() -> void:
	var result: Error = store.atomic_json(checkpoint_path, {"schema": 2, "resume_on_start": resume_on_start, "jobs": jobs})
	last_error = "" if result == OK else "Checkpoint: " + error_string(result)
	updated.emit()

func find_job(id: String) -> Dictionary:
	for job in jobs:
		if job.id == id: return job
	return {}

func finish_job(job: Dictionary, result: Variant) -> void:
	var retryable := false
	if result is Dictionary and result.get("status") in ["done", "cached", "cancelled", "failed"]:
		job.status = result.status
		job.error = str(result.get("error", ""))
		job.hash = str(result.get("hash", ""))
		job.elapsed_ms = result.get("elapsed_ms", 0)
		job.project_path = str(result.get("project_path", ""))
		job.report_path = str(result.get("report_path", ""))
		job.validation = result.get("validation", {}) if result.get("validation", {}) is Dictionary else {}
		job.progress = 100 if job.status in ["done", "cached"] else job.progress
		retryable = result.get("retryable", false) == true
	else:
		job.status = "failed"; job.error = "Processo auxiliar terminou sem relatório válido."; retryable = true
	job.history.append({"status": job.status, "at": Time.get_datetime_string_from_system(), "elapsed_ms": job.elapsed_ms, "error": job.error, "attempt": job.attempts})
	if job.history.size() > 64: job.history.pop_front()
	if job.status == "failed" and retryable and job.attempts < job.max_attempts:
		job.status = "pending"
		job.next_attempt_at = Time.get_unix_time_from_system() + minf(30, pow(2, job.attempts))
		job.error += " Nova tentativa automática agendada."
	persist()

func retry_failed() -> void:
	for job in jobs:
		if job.status == "failed": job.status = "pending"; job.error = ""; job.validation = {}; job.attempts = 0; job.next_attempt_at = 0
	persist()

func _process(_delta: float) -> void:
	if active_pid >= 0:
		var job: Dictionary = find_job(active_id)
		if FileAccess.file_exists(progress_path):
			var state = Storage.read_json(progress_path)
			if state is Dictionary:
				job.progress = state.get("progress", 0)
				job.status = state.get("status", "running")
				var signature := str(state)
				if signature != last_progress: last_progress = signature; updated.emit()
		if OS.is_process_running(active_pid):
			if worker_timeout_seconds > 0 and Time.get_ticks_msec() - active_started > worker_timeout_seconds * 1000:
				OS.kill(active_pid)
				active_pid = -1; active_id = ""
				finish_job(job, {"status": "failed", "error": "Tempo máximo do worker excedido.", "retryable": true})
			return
		var result = Storage.read_json(result_path)
		active_pid = -1
		active_id = ""
		finish_job(job, result)
		return
	if not running: return
	var graph_errors: Array = preload("res://core/production_plan.gd").new().validate(jobs)
	if not graph_errors.is_empty():
		for job in jobs:
			if job.status == "pending": job.status = "failed"; job.error = "; ".join(graph_errors)
		running = false
		persist()
		return
	var candidates: Array = jobs.filter(func(job): return job.status == "pending")
	candidates.sort_custom(func(a, b): return a.priority > b.priority)
	for job in candidates:
		if float(job.next_attempt_at) > Time.get_unix_time_from_system(): continue
		var eligible := true
		for dependency in job.dependencies:
			var parent := find_job(str(dependency))
			if parent.is_empty() or parent.status in ["failed", "cancelled"]:
				job.status = "failed"; job.error = "Dependência ausente ou sem sucesso: " + str(dependency); persist(); eligible = false; break
			if parent.status not in ["done", "cached"]: eligible = false
		if not eligible: continue
		if job.estimated_mb > ram_budget_mb or job.attempts >= job.max_attempts:
			job.status = "failed"; job.error = "Limite de memória estimada ou tentativas excedido."; persist(); continue
		start_job(job)
		return
	if candidates.is_empty(): running = false; updated.emit()

func start_job(job: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(request_root)
	var prefix := ProjectSettings.globalize_path(request_root).path_join(job.id + "_" + str(Time.get_ticks_usec()))
	result_path = prefix + ".result.json"
	progress_path = prefix + ".progress.json"
	cancel_path = prefix + ".cancel"
	var request := prefix + ".request.json"
	var data := {"schema": 1, "input": job.input, "output": job.output, "id": job.id, "result": result_path, "progress": progress_path, "cancel": cancel_path, "kind": job.kind, "parameters": job.parameters}
	if store.atomic_json(request, data) != OK:
		job.status = "failed"; job.error = "Não foi possível gravar solicitação."; persist(); return
	var args := PackedStringArray(["--headless", "--log-file", prefix + ".log"])
	var pack := OS.get_executable_path().get_basename() + ".pck"
	if FileAccess.file_exists(pack): args.append_array(["--main-pack", pack])
	else: args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--sfs-worker", request])
	job.status = "preparing"
	job.attempts += 1
	job.progress = 0
	job.error = ""
	active_id = job.id
	active_started = Time.get_ticks_msec()
	active_pid = OS.create_process(OS.get_executable_path(), args)
	if active_pid < 0:
		active_id = ""
		finish_job(job, {"status": "failed", "error": "Não foi possível iniciar processo Godot auxiliar.", "retryable": true})
	persist()

func cancel(id: String) -> void:
	var job := find_job(id)
	if job.is_empty(): return
	if id == active_id:
		var file := FileAccess.open(cancel_path, FileAccess.WRITE)
		if file: file.store_string("cancel"); file.close()
	else: job.status = "cancelled"
	persist()

func _exit_tree() -> void:
	if active_pid >= 0 and OS.is_process_running(active_pid):
		OS.kill(active_pid)
		var job := find_job(active_id)
		if not job.is_empty(): job.status = "pending"
		persist()
