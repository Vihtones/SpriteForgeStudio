extends SceneTree
const Doc = preload("res://core/document.gd")
const Store = preload("res://core/storage.gd")
const Watcher = preload("res://core/automation.gd")
const Worker = preload("res://core/batch_worker.gd")
const Queue = preload("res://core/batch_queue.gd")
var folder: String = "res://test_results/automation_" + str(Time.get_ticks_usec())
var checks: Array = []
var failed: int = 0
var store := Store.new()

func expect(value: bool, title: String) -> void:
	checks.append({"name": title, "passed": value})
	if not value: failed += 1; printerr("FAIL ", title)
	else: print("PASS ", title)

func _initialize() -> void: call_deferred("run")

func request(source: String, output: String, options: Dictionary = {}) -> Dictionary:
	return {"id": "auto-test", "input": source, "output": output, "parameters": options, "kind": "production", "progress": folder.path_join("progress.json"), "cancel": folder.path_join("cancel")}

func scan(watcher: Node) -> void:
	watcher.scan_now()
	while watcher.scanning: watcher.scan_step()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var input := ProjectSettings.globalize_path(folder.path_join("input"))
	var output := ProjectSettings.globalize_path(folder.path_join("output"))
	DirAccess.make_dir_recursive_absolute(input)
	var source := input.path_join("one.sfs.json")
	var doc := Doc.new()
	doc.checkpoint(); doc.pixel(Vector2i(1, 1), Color("aa2244")); doc.pixel(Vector2i(2, 2), Color("bb3355"))
	doc.rig.protected_pixels = {"0:0": [66]}
	doc.manifest.approvals = [{"id": "review", "human": true}]
	store.save_document(doc, source)
	var original_hash := FileAccess.get_sha256(source)
	var job := request(source, output.path_join("raw"))
	var result := Worker.execute(job)
	expect(result.status == "done", "deterministic production executes without provider or credentials")
	var candidate = store.load_document(result.get("project_path", ""))
	expect(candidate != null and candidate.current().get_pixel(1, 1) == Color("aa2244"), "default production preserves original pixels")
	var report = Store.read_json(result.report_path)
	expect(report.artistic_approval == false and report.stages.size() == 4 and report.cels.size() == 32, "technical report covers every cel and does not approve art")
	expect(FileAccess.get_sha256(source) == original_hash, "source bytes are preserved")
	result = Worker.execute(job)
	expect(result.status == "cached", "production cache validates candidate and exported checksums")
	var file := FileAccess.open(output.path_join("raw/export/frame.png"), FileAccess.WRITE); file.store_string("corrupt"); file.close()
	result = Worker.execute(job)
	expect(result.status == "done" and Image.load_from_file(output.path_join("raw/export/frame.png")) != null, "corrupted output forces reconstruction")
	job = request(source, output.path_join("quantized"), {"quantize": true})
	result = Worker.execute(job)
	candidate = store.load_document(result.get("project_path", ""))
	expect(candidate != null and candidate.current().get_pixel(1, 1) != Color("aa2244"), "opt-in palette correction changes candidate")
	expect(candidate.current().get_pixel(2, 2) == Color("bb3355"), "automatic correction respects protected pixels")
	expect(candidate.manifest.approvals.is_empty() and candidate.manifest.id != doc.manifest.id, "modified candidate cannot inherit human approval")
	expect(FileAccess.get_sha256(source) == original_hash, "correction never overwrites source")
	doc.layers[0].locked = true
	store.save_document(doc, input.path_join("locked.sfs.json"))
	result = Worker.execute(request(input.path_join("locked.sfs.json"), output.path_join("locked"), {"quantize": true}))
	candidate = store.load_document(result.get("project_path", ""))
	expect(candidate.current().get_data() == doc.current().get_data(), "automatic correction respects locked layers")
	store.save_document(Doc.new(), input.path_join("empty.sfs.json"))
	result = Worker.execute(request(input.path_join("empty.sfs.json"), output.path_join("empty")))
	expect(result.status == "failed" and not FileAccess.file_exists(output.path_join("empty/export/character.tscn")), "empty-art gate blocks export")
	doc.layers[0].visible = false
	store.save_document(doc, input.path_join("hidden.sfs.json"))
	result = Worker.execute(request(input.path_join("hidden.sfs.json"), output.path_join("hidden")))
	expect(result.status == "failed", "hidden pixels cannot satisfy visible-art gate")
	DirAccess.remove_absolute(input.path_join("hidden.sfs.json"))
	doc.layers[0].visible = true
	result = Worker.execute(request(input.path_join("empty.sfs.json"), output.path_join("empty-allowed"), {"require_nonempty": false}))
	expect(result.status == "done", "explicit empty-art profile supports blank templates")
	file = FileAccess.open(folder.path_join("cancel"), FileAccess.WRITE); file.close()
	result = Worker.execute(request(source, output.path_join("cancelled")))
	expect(result.status == "cancelled" and not DirAccess.dir_exists_absolute(output.path_join("cancelled")), "cancelled production publishes no new output")
	DirAccess.remove_absolute(folder.path_join("cancel"))
	var rock := Node.new(); root.add_child(rock)
	var watcher := Watcher.new(); watcher.config_path = folder.path_join("settings.json"); watcher.settle_seconds = 0
	rock.add_child(watcher)
	expect(watcher.is_in_group("Saveable") and not watcher.config.enabled, "automation component runs on plain parent and defaults inactive")
	expect(not Watcher.paths_valid(input, input) and not Watcher.paths_valid(input, input.path_join("nested")) and not Watcher.paths_valid(input, folder), "watcher rejects overlapping input/output trees")
	expect(watcher.configure({"input": input, "output": output, "enabled": true, "resume": true, "interval": 9}), "watcher accepts separated local folders")
	var requests: Array = []
	watcher.work_requested.connect(func(a, b, options, token): requests.append({"input": a, "output": b, "options": options, "token": token}); watcher.bind_job(token, "job-" + str(requests.size())))
	scan(watcher)
	expect(requests.is_empty(), "new file waits for stable observation before admission")
	scan(watcher)
	expect(requests.size() == 3 and watcher.ledger.size() == 3, "watcher admits saved projects once")
	scan(watcher)
	expect(requests.size() == 3, "identical source and profile do not requeue")
	doc.layers[0].locked = false; doc.checkpoint(); doc.pixel(Vector2i(4, 4), Color.GREEN)
	store.save_document(doc, source)
	scan(watcher); scan(watcher)
	expect(requests.size() == 4, "changed input creates new fingerprint and separate output")
	watcher.reconcile([])
	expect(watcher.ledger.values().all(func(entry): return entry.status == "missing"), "missing queue records become explicit failures instead of silent resubmission")
	var restored := Watcher.new(); restored.config_path = watcher.config_path; rock.add_child(restored)
	expect(restored.config.enabled and restored.config.resume and restored.config.interval == 9 and restored.ledger.size() == 4, "opt-in startup recovery restores watcher settings and fingerprints")
	watcher.config.resume = false; watcher.persist()
	var disabled := Watcher.new(); disabled.config_path = watcher.config_path; rock.add_child(disabled)
	expect(not disabled.config.enabled, "startup does not resume without explicit setting")
	watcher.scan_now(); watcher.scan_step(); watcher.pause()
	var admitted: int = requests.size()
	watcher.scan_step()
	expect(not watcher.scanning and not watcher.config.enabled and requests.size() == admitted, "pausing invalidates in-flight scan and cannot restart queue")
	expect(not Watcher.paths_valid(input, "user://approved_library/automatic"), "automation cannot write inside approved snapshot library")
	var queue := Queue.new(); queue.checkpoint_path = folder.path_join("queue.json"); queue.request_root = folder.path_join("requests"); rock.add_child(queue)
	var id := queue.enqueue(source, output.path_join("isolated"), 0, [], "production", {})
	queue.running = true
	var deadline := Time.get_ticks_msec() + 20000
	while queue.find_job(id).status in ["pending", "running", "preparing", "validating"] and Time.get_ticks_msec() < deadline: await process_frame
	expect(queue.find_job(id).status == "done" and FileAccess.file_exists(queue.find_job(id).report_path), "production runs through a real isolated Godot worker")
	queue.running = false
	var retry := queue.normalize({"input": source, "output": output, "status": "preparing", "hash": "", "error": "", "attempts": 1})
	queue.jobs.append(retry)
	queue.finish_job(retry, null)
	expect(retry.status == "pending" and retry.next_attempt_at > Time.get_unix_time_from_system(), "worker crash schedules delayed automatic retry")
	retry.attempts = 3
	queue.finish_job(retry, null)
	expect(retry.status == "failed" and retry.history.size() == 2, "worker crashes stop at bounded attempt limit and retain history")
	queue.retry_failed()
	expect(retry.status == "pending" and retry.attempts == 0 and retry.next_attempt_at == 0 and retry.validation.is_empty(), "manual retry resets attempt budget and clears stale validation details")
	var failed_validation := {"ok": false, "checks": [{"name": "world_rooms", "passed": false}]}
	queue.finish_job(retry, {"status": "failed", "error": "Invalid project", "validation": failed_validation})
	expect(retry.status == "failed" and retry.validation == failed_validation, "deterministic export failure retains detailed validation report and is not retried automatically")
	var exported_job := queue.normalize({"input": source, "output": output, "status": "running", "hash": "", "error": ""})
	queue.finish_job(exported_job, {"status": "done", "report_path": output.path_join("export-validation.json"), "validation": {"ok": true, "passed": 5, "failed": 0}})
	expect(exported_job.report_path.ends_with("export-validation.json") and exported_job.validation.ok, "successful export stores a report path and validation summary for the production UI")
	var child_pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/hanging_worker.gd", "--log-file", ProjectSettings.globalize_path(folder.path_join("hanging.log"))])
	queue.active_pid = child_pid; queue.active_id = retry.id; queue.active_started = Time.get_ticks_msec() - 2000; queue.worker_timeout_seconds = 1
	retry.attempts = 1
	queue._process(0)
	expect(child_pid > 0 and queue.active_pid == -1 and retry.status == "pending" and retry.error.contains("Tempo máximo"), "watchdog terminates a real stalled child and schedules bounded recovery")
	id = queue.enqueue(source, output.path_join("resume"))
	queue.resume_on_start = true; queue.persist(); queue.free()
	queue = Queue.new(); queue.checkpoint_path = folder.path_join("queue.json"); rock.add_child(queue)
	expect(queue.resume_on_start and queue.running and queue.find_job(id).status == "pending", "queue supports explicit automatic startup resume")
	queue.running = false
	watcher.set_process(false); restored.set_process(false); disabled.set_process(false)
	rock.free()
	await ui_flow(source)
	store.atomic_json("res://test_results/automation-report.json", {"passed": checks.size() - failed, "failed": failed, "checks": checks})
	print("AUTOMATION RESULT ", checks.size() - failed, " passed / ", failed, " failed")
	quit(1 if failed > 0 else 0)

func ui_flow(source: String) -> void:
	var ui = load("res://main.tscn").instantiate()
	ui.workspace_root = folder.path_join("ui_workspace")
	root.add_child(ui)
	ui.queue.jobs.clear(); ui.queue.running = false
	ui.queue.checkpoint_path = folder.path_join("ui_queue.json"); ui.queue.request_root = folder.path_join("ui_requests")
	var input := ProjectSettings.globalize_path(folder.path_join("ui_input"))
	var output := ProjectSettings.globalize_path(folder.path_join("ui_output"))
	DirAccess.make_dir_recursive_absolute(input)
	DirAccess.copy_absolute(source, input.path_join("hero.sfs.json"))
	ui.automation.settle_seconds = 0
	ui.automation_panel.configuration_requested.emit({"input": input, "output": output, "enabled": true, "resume": true})
	expect(ui.automation.config.enabled and ui.queue.resume_on_start, "UI start persists monitoring and queue resume intent")
	scan(ui.automation); scan(ui.automation)
	var deadline := Time.get_ticks_msec() + 20000
	while (ui.queue.jobs.is_empty() or ui.queue.jobs[0].status in ["pending", "preparing", "running", "validating"]) and Time.get_ticks_msec() < deadline: await process_frame
	expect(ui.queue.jobs.size() == 1 and ui.queue.jobs[0].status == "done" and ui.automation.ledger.values()[0].status == "done", "UI monitor signals drive a real production job and ledger completion")
	if ui.queue.jobs.size() == 1 and ui.queue.jobs[0].status == "done":
		var count: int = ui.workspace.records.size()
		ui.automation_panel.candidate_requested.emit(ui.queue.jobs[0].project_path)
		expect(ui.workspace.records.size() == count + 1 and ui.doc.dirty and ui.workspace.current().path == "", "automation candidate opens as independent editable copy")
	ui.automation_panel.pause_requested.emit()
	expect(not ui.automation.config.enabled and not ui.queue.running and not ui.queue.resume_on_start, "UI pause disables monitoring and automatic queue restart")
	ui.free()
