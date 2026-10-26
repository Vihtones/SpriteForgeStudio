extends Node
signal completed(result: Dictionary)
const Storage = preload("res://core/storage.gd")
var python_path: String = ""
var data_root: String = "user://catalog"
var pid: int = -1
var result_path: String = ""
var started: int = 0

func index(doc: RefCounted, project_path: String) -> bool:
	if pid >= 0 or not FileAccess.file_exists(python_path): return false
	DirAccess.make_dir_recursive_absolute(data_root)
	var root := ProjectSettings.globalize_path(data_root)
	var script := root.path_join("catalog.py")
	var file := FileAccess.open(script, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(FileAccess.get_file_as_bytes("res://services/catalog.py"))
	file.close()
	var id := str(Time.get_ticks_usec())
	var request := root.path_join(id + ".request.json")
	result_path = root.path_join(id + ".result.json")
	var refs: Array = []
	for reference in doc.art.references:
		var metadata := {}
		for key in ["id", "name", "sha256", "state", "source", "license", "features", "confidence", "dimensions"]:
			if reference.has(key): metadata[key] = reference[key]
		refs.append(metadata)
	var payload := {"schema": 1, "command": "index", "project": {"id": doc.manifest.id, "name": doc.manifest.name, "path": project_path, "hash": FileAccess.get_sha256(project_path) if FileAccess.file_exists(project_path) else "", "bible_version": int(doc.manifest.art_bible_version), "references": refs, "dependencies": doc.manifest.dependencies}}
	if Storage.new().atomic_json(request, payload) != OK: return false
	pid = OS.create_process(python_path, [script, "--root", root, "--request", request, "--result", result_path])
	started = Time.get_ticks_msec()
	return pid >= 0

func _process(_delta: float) -> void:
	if pid < 0: return
	if OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > 30000:
			OS.kill(pid); pid = -1; completed.emit({"ok": false, "error": "Índice excedeu 30 segundos."})
		return
	pid = -1
	var result = Storage.read_json(result_path)
	completed.emit(result if result is Dictionary else {"ok": false, "error": "Serviço não retornou relatório."})

func _exit_tree() -> void:
	if pid >= 0 and OS.is_process_running(pid): OS.kill(pid)
