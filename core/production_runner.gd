extends Node
## Headless orchestrator: same components and contracts as the UI.
const Queue = preload("res://core/batch_queue.gd")
const Automation = preload("res://core/automation.gd")
const Store = preload("res://core/storage.gd")
var queue: Node
var watcher: Node
var job_id: String = ""
var summary: String = ""
var started: int = 0

func run(args: PackedStringArray) -> void:
	var watching: bool = args[0] == "--sfs-watch"
	var settings: Dictionary = {}
	var output: String = ""
	if watching:
		var data = Store.read_json(args[1])
		if not data is Dictionary: fail("Arquivo de configuração inválido."); return
		var values = data.get("config", data)
		if not values is Dictionary: fail("Configuração precisa ser um objeto JSON."); return
		settings = values
		if settings.get("interval") is float: settings.interval = int(settings.interval)
		if not settings.get("input") is String or not settings.get("output") is String: fail("Configuração precisa de input e output."); return
		output = settings.output
	else:
		if args.size() < 3: fail("Uso: --sfs-produce entrada.sfs.json pasta-saida [--quantize]"); return
		output = args[2]
	var state_dir: String = output.path_join(".sfs-automation")
	if DirAccess.make_dir_recursive_absolute(state_dir) != OK: fail("Não foi possível criar pasta de estado."); return
	queue = Queue.new(); queue.checkpoint_path = state_dir.path_join("queue.json"); queue.request_root = state_dir.path_join("requests")
	add_child(queue)
	if watching:
		watcher = Automation.new(); watcher.config_path = state_dir.path_join("watcher.json"); add_child(watcher)
		watcher.work_requested.connect(func(source, destination, options, token):
			watcher.bind_job(token, queue.enqueue(source, destination, 50, [], "production", options)); queue.running = true
		)
		queue.updated.connect(func(): watcher.reconcile(queue.jobs))
		settings.enabled = true
		if not watcher.configure(settings): fail(watcher.error); return
		queue.resume_on_start = true; queue.running = true; queue.persist()
		print("SFS monitorando ", settings.input, " → ", output)
	else:
		job_id = queue.enqueue(args[1], output, 50, [], "production", {"quantize": args.has("--quantize")})
		if job_id == "": fail("Fila cheia."); return
		summary = output.path_join("runner-report.json")
		queue.running = true
		started = Time.get_ticks_msec()

func fail(reason: String) -> void:
	printerr(reason)
	get_tree().quit(2)

func _process(_delta: float) -> void:
	if job_id == "" or queue == null: return
	var job: Dictionary = queue.find_job(job_id)
	if job.status in ["done", "cached", "failed", "cancelled"]:
		var ok: bool = job.status in ["done", "cached"]
		var result := Store.new().atomic_json(summary, {"ok": ok, "job": job, "engine": Engine.get_version_info().string})
		print("SFS produção: ", job.status, " ", job.error)
		get_tree().quit(0 if ok and result == OK else 1)
	elif Time.get_ticks_msec() - started > 3600000:
		fail("Tempo máximo de uma hora excedido; o checkpoint preserva a tarefa.")
