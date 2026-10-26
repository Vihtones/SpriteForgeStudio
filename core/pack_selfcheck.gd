extends Node
## Verifies the shipped PCK can spawn a worker without the source tree.
const Queue = preload("res://core/batch_queue.gd")
const Storage = preload("res://core/storage.gd")
var queue: Node
var output: String
var started: int
var frames_seen: int = 0

func run(input: String, folder: String) -> void:
	output = folder
	DirAccess.make_dir_recursive_absolute(output)
	queue = Queue.new()
	queue.checkpoint_path = output.path_join("selfcheck_queue.json")
	queue.request_root = output.path_join("requests")
	add_child(queue)
	queue.jobs.clear()
	if input.ends_with("biblioteca.json"):
		queue.enqueue(input, output.path_join("import"), 100, [], "import_arton", {"family": "humanoide", "garments": true})
	else: queue.enqueue(input, output.path_join("export"))
	queue.running = true
	started = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if queue == null: return
	frames_seen += 1
	var job: Dictionary = queue.jobs[0]
	if job.status in ["done", "cached", "failed", "cancelled"] or Time.get_ticks_msec() - started > 30000:
		var success: bool = job.status in ["done", "cached"] and frames_seen > 1
		var proof_frames: SpriteFrames = load("res://examples/animation_proof/export/animations.tres")
		var animation_proof: bool = proof_frames != null and proof_frames.get_animation_names().size() == 32
		animation_proof = animation_proof and FileAccess.file_exists("res://examples/animation_proof/sentinela.sfs.json") and FileAccess.file_exists("res://examples/animation_proof/technical_preview_rejected.gif")
		var proof_document: Variant = Storage.read_json("res://examples/animation_proof/sentinela.sfs.json")
		animation_proof = animation_proof and proof_document is Dictionary and proof_document.get("frames", 0) == 22 and proof_document.get("layers", []).size() == 4 and proof_document.get("animation", {}).get("clips", []).size() == 4
		success = success and animation_proof
		if not str(job.get("project_path", "")).is_empty():
			var imported = Storage.new().load_document(job.project_path)
			success = success and imported != null
			if imported != null: success = success and imported.width == 256 and imported.frames == 1
		Storage.new().atomic_json(output.path_join("pack_report.json"), {"ok": success, "frames_while_exporting": frames_seen, "job": job, "engine": Engine.get_version_info().string, "animation_proof": animation_proof})
		get_tree().quit(0 if success else 1)
