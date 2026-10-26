extends Node
## Optional ComfyUI local API adapter. Network access is restricted to localhost.
signal completed(result: Dictionary)
signal progress(message: String)
const MAX_BODY := 48 * 1024 * 1024
var _http: HTTPRequest
var _base := ""
var _workflow: Dictionary = {}
var _busy := false
var _stage := ""
var _prompt_id := ""
var _deadline_msec := 0

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.body_size_limit = MAX_BODY
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func validate_endpoint(endpoint: String) -> bool:
	var matcher := RegEx.new()
	matcher.compile("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})/?$")
	var result := matcher.search(endpoint.strip_edges())
	return result != null and int(result.get_string(2)) <= 65535

func check_connection(endpoint: String) -> Dictionary:
	if _busy: return {"ok": false, "error": "A conexão local já está ocupada."}
	_base = endpoint.strip_edges().trim_suffix("/")
	if not validate_endpoint(_base): return {"ok": false, "error": "Use apenas http://localhost:porta ou http://127.0.0.1:porta."}
	_stage = "health"
	var result := _http.request(_base + "/system_stats")
	if result != OK: _stage = ""; return {"ok": false, "error": "Não foi possível consultar a instância local."}
	_busy = true
	return {"ok": true, "started": true}

func prepare_workflow(path: String, prompt: String) -> Dictionary:
	if path.strip_edges().is_empty() or prompt.strip_edges().is_empty() or prompt.length() > 5000: return {"ok": false, "error": "Informe um workflow local e uma descrição de até 5.000 caracteres."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > 4 * 1024 * 1024: return {"ok": false, "error": "O workflow não existe ou excede 4 MiB."}
	var graph: Variant = JSON.parse_string(file.get_as_text())
	if not graph is Dictionary or graph.is_empty() or graph.size() > 2048: return {"ok": false, "error": "Workflow precisa estar no formato API de ComfyUI e ter até 2.048 nós."}
	var changed := 0
	for node_id in graph:
		var node: Variant = graph[node_id]
		if not node is Dictionary or not node.get("inputs") is Dictionary: return {"ok": false, "error": "O grafo contém um nó malformado."}
		var type := str(node.get("class_type", ""))
		var lower := type.to_lower()
		if type.is_empty() or lower.contains("openai") or lower.contains("api") or lower.contains("cloud") or lower.contains("remote"):
			return {"ok": false, "error": "Workflow recusado: este modo aceita apenas nós locais de geração, sem nós API/cloud."}
		for input_name in node.inputs:
			if type == "CLIPTextEncode" and input_name == "text" and node.inputs[input_name] is String and str(node.inputs[input_name]).contains("{{PROMPT}}"):
				node.inputs[input_name] = str(node.inputs[input_name]).replace("{{PROMPT}}", prompt.strip_edges())
				changed += 1
	if changed == 0: return {"ok": false, "error": "Marque o campo de texto do nó CLIPTextEncode com {{PROMPT}} no workflow API."}
	return {"ok": true, "workflow": graph, "prompt_nodes": changed}

func generate(endpoint: String, workflow_path: String, prompt: String) -> Dictionary:
	if _busy: return {"ok": false, "error": "Já existe uma tarefa local em andamento."}
	_base = endpoint.strip_edges().trim_suffix("/")
	if not validate_endpoint(_base): return {"ok": false, "error": "O gerador local aceita apenas localhost."}
	var prepared := prepare_workflow(workflow_path, prompt)
	if not prepared.ok: return prepared
	_workflow = prepared.workflow
	_stage = "submit"
	var error_code := _http.request(_base + "/prompt", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"prompt": _workflow, "client_id": "sprite-forge-studio"}))
	if error_code != OK: _stage = ""; _workflow.clear(); return {"ok": false, "error": "Falha ao enviar trabalho à instância local."}
	_busy = true
	progress.emit("Geração local enviada; aguardando a fila do ComfyUI.")
	return {"ok": true, "started": true}

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _busy: return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_finish(false, "A instância local respondeu com erro HTTP %d; nenhuma repetição foi iniciada." % response_code); return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8()) if _stage != "download" else null
	match _stage:
		"health":
			if not data is Dictionary or not data.has("system"): _finish(false, "ComfyUI respondeu, mas /system_stats não contém dados válidos."); return
			_finish(true, "ComfyUI local disponível.", {"stage": "health"})
		"submit":
			if not data is Dictionary or str(data.get("prompt_id", "")).is_empty(): _finish(false, "ComfyUI não devolveu um identificador de fila."); return
			_prompt_id = str(data.prompt_id)
			_deadline_msec = Time.get_ticks_msec() + 600000
			_stage = "poll"
			progress.emit("Fila local: " + _prompt_id.left(12))
			_schedule_poll()
		"poll":
			if not data is Dictionary or not data.has(_prompt_id) or data[_prompt_id].get("outputs", {}).is_empty(): _schedule_poll(); return
			var images: Array = []
			for output in data[_prompt_id].outputs.values():
				if output is Dictionary and output.get("images") is Array: images.append_array(output.images)
			if images.is_empty(): _finish(false, "A tarefa terminou sem PNG de saída."); return
			var meta: Dictionary = images[0]
			var filename := str(meta.get("filename", ""))
			if filename.is_empty() or filename.get_file() != filename or str(meta.get("type", "output")) != "output": _finish(false, "A resposta local contém um caminho de imagem inválido."); return
			var query := "filename=" + filename.uri_encode() + "&subfolder=" + str(meta.get("subfolder", "")).uri_encode() + "&type=output"
			_stage = "download"
			var request_error := _http.request(_base + "/view?" + query)
			if request_error != OK: _finish(false, "Não foi possível baixar a saída da instância local.")
		"download":
			var image := Image.new()
			if image.load_png_from_buffer(body) != OK or image.is_empty() or image.get_width() > 8192 or image.get_height() > 8192: _finish(false, "Saída local não é um PNG válido até 8192×8192."); return
			var folder := "user://hyperlearn/generated"
			if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: _finish(false, "Não foi possível criar a pasta local de resultados."); return
			var path := folder.path_join("candidate-" + str(Time.get_ticks_usec()) + ".png")
			if image.save_png(path) != OK: _finish(false, "Não foi possível salvar o resultado local."); return
			_finish(true, "Imagem gerada localmente, aguardando revisão humana.", {"path": path, "width": image.get_width(), "height": image.get_height(), "prompt_id": _prompt_id})

func _schedule_poll() -> void:
	if not is_inside_tree(): return
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(_poll, CONNECT_ONE_SHOT)

func _poll() -> void:
	if not _busy or _stage != "poll": return
	if Time.get_ticks_msec() >= _deadline_msec: _finish(false, "A fila local excedeu dez minutos; revise o ComfyUI e tente novamente quando quiser."); return
	var error_code := _http.request(_base + "/history/" + _prompt_id.uri_encode())
	if error_code != OK: _finish(false, "Não foi possível consultar a fila local.")

func _finish(ok: bool, message: String, details: Dictionary = {}) -> void:
	_busy = false
	_stage = ""
	_workflow.clear()
	completed.emit({"ok": ok, "message": message, "details": details})
