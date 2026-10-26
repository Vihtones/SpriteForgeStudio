extends Node
## Optional first-party local image engine backed by stable-diffusion.cpp.
## The process binds to loopback only and is stopped when this Studio session exits.
signal completed(result: Dictionary)
signal progress(message: String)

const PORT := 1234
const BASE_URL := "http://127.0.0.1:1234"
const MAX_RESPONSE_BYTES := 48 * 1024 * 1024
const MODEL_FILE := "stable-diffusion-v1-5-Q8_0.gguf"
const DREAMSHAPER_MODEL_FILE := "DreamShaper8_LCM_q8_0.gguf"
const LORA_FILE := "pixel-art-LoRa.safetensors"
const MODEL_SHA256 := "a51037fac577d133fe3b83a4a0c2a7605615786f07bdec397378143fe0361f32"
const LORA_SHA256 := "ad5034703699e910d5f9525ea5db64abcbd8d7396ff8f771c09403f3adb048ad"

var _http: HTTPRequest
var _stage := ""
var _busy := false
var _server_pid := -1
var _server_started_by_us := false
var _model_path := ""
var _active_model_path := ""
var _lora_path := ""
var _use_lora := true
var _lora_strength := 0.75
var _width := 512
var _height := 512
var _steps := 12
var _prompt := ""
var _negative_prompt := ""
var _seed := -1
var _deadline_msec := 0
var _last_probe_msec := 0
var _data_folder := ""

func _ready() -> void:
	_data_folder = ProjectSettings.globalize_path("user://local_ai")
	_model_path = default_model_path()
	DirAccess.make_dir_recursive_absolute(_data_folder.path_join("models").path_join("loras"))
	_http = HTTPRequest.new()
	_http.timeout = 600.0
	_http.body_size_limit = MAX_RESPONSE_BYTES
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func default_model_path() -> String:
	var dreamshaper := _data_folder.path_join("models").path_join(DREAMSHAPER_MODEL_FILE)
	if FileAccess.file_exists(dreamshaper): return dreamshaper
	return _data_folder.path_join("models").path_join(MODEL_FILE)

func default_lora_path() -> String:
	return _data_folder.path_join("models").path_join("loras").path_join(LORA_FILE)

func is_server_running() -> bool:
	return _server_pid > 0 and OS.is_process_running(_server_pid)

func start(model_path: String, lora_path: String = "") -> Dictionary:
	if _busy: return {"ok": false, "error": "Já existe uma tarefa da IA local em andamento."}
	_model_path = model_path.strip_edges()
	_lora_path = lora_path.strip_edges() if not lora_path.strip_edges().is_empty() else default_lora_path()
	if _model_path.is_empty() or not FileAccess.file_exists(_model_path):
		return {"ok": false, "error": "Selecione o modelo GGUF local. O arquivo não foi encontrado."}
	if is_server_running():
		if not _active_model_path.is_empty() and _active_model_path != _model_path:
			return {"ok": false, "error": "O motor já carregou outro modelo. Pare o motor e inicie novamente para trocar os pesos."}
		_stage = "health"
		var request_error := _http.request(BASE_URL + "/sdapi/v1/sd-models")
		if request_error != OK: _stage = ""; return {"ok": false, "error": "O motor local está ativo, mas a conexão não pôde ser consultada."}
		_busy = true
		return {"ok": true, "started": true}
	_server_pid = -1
	_server_started_by_us = false
	_active_model_path = ""
	var runtime := _runtime_executable()
	if runtime.is_empty(): return {"ok": false, "error": "O motor local sd-server.exe não está junto do executável do SFS ou em res://vendor/stable-diffusion-cpp/."}
	var args := PackedStringArray([
		"--model", _model_path,
		"--listen-ip", "127.0.0.1",
		"--listen-port", str(PORT),
		"--backend", "diffusion=vulkan0,te=cpu,vae=vulkan0",
		"--threads", "6",
		"--lora-model-dir", _lora_path.get_base_dir()
	])
	_server_pid = OS.create_process(runtime, args, false)
	if _server_pid <= 0: return {"ok": false, "error": "O Windows não conseguiu iniciar o motor local."}
	_server_started_by_us = true
	_active_model_path = _model_path
	_busy = true
	_stage = "starting"
	_deadline_msec = Time.get_ticks_msec() + 600000
	_last_probe_msec = 0
	progress.emit("Carregando o modelo local na RX 580/CPU… O primeiro início pode demorar alguns minutos.")
	set_process(true)
	return {"ok": true, "started": true}

func generate(model_path: String, lora_path: String, prompt: String, negative_prompt: String, width: int, height: int, steps: int, seed: int, use_lora: bool, lora_strength: float) -> Dictionary:
	if _busy: return {"ok": false, "error": "Já existe uma tarefa da IA local em andamento."}
	var valid := validate_options(prompt, negative_prompt, width, height, steps)
	if not valid.ok: return valid
	var started := start(model_path, lora_path)
	if not started.ok: return started
	_use_lora = use_lora
	_lora_strength = clampf(lora_strength, 0.0, 1.5)
	_width = width
	_height = height
	_steps = steps
	if _model_path.get_file().to_lower().contains("dreamshaper8_lcm"):
		_steps = mini(_steps, 8)
	_prompt = prompt.strip_edges()
	_negative_prompt = negative_prompt.strip_edges()
	_seed = seed
	if _stage == "health":
		# Reusing the HTTP request for health and generation is safe because the
		# first request must complete before this stage advances.
		return {"ok": true, "started": true, "checking_engine": true}
	return {"ok": true, "started": true, "starting_engine": true}

func validate_options(prompt: String, negative_prompt: String, width: int, height: int, steps: int) -> Dictionary:
	if prompt.strip_edges().is_empty() or prompt.length() > 5000: return {"ok": false, "error": "Escreva uma descrição de até 5.000 caracteres."}
	if negative_prompt.length() > 2000: return {"ok": false, "error": "A lista negativa pode ter até 2.000 caracteres."}
	if width < 256 or width > 768 or height < 256 or height > 768 or width % 64 != 0 or height % 64 != 0:
		return {"ok": false, "error": "Use largura e altura entre 256 e 768, em múltiplos de 64."}
	if steps < 4 or steps > 30: return {"ok": false, "error": "Use entre 4 e 30 passos neste hardware."}
	return {"ok": true}

func build_generation_payload(prompt: String, negative_prompt: String, width: int, height: int, steps: int, seed: int, use_lora: bool, lora_strength: float, lora_filename: String = LORA_FILE, model_path: String = "") -> Dictionary:
	var is_lcm := model_path.get_file().to_lower().contains("dreamshaper8_lcm")
	var body := {"prompt": prompt.strip_edges(), "negative_prompt": negative_prompt.strip_edges(), "width": width, "height": height, "steps": mini(steps, 8) if is_lcm else steps, "cfg_scale": 2.0 if is_lcm else 7.0, "seed": seed, "batch_size": 1, "sampler_name": "lcm" if is_lcm else "euler_a"}
	if use_lora and not lora_filename.strip_edges().is_empty(): body["lora"] = [{"path": lora_filename.get_file(), "multiplier": clampf(lora_strength, 0.0, 1.5), "is_high_noise": false}]
	return body

func check(model_path: String, lora_path: String = "") -> Dictionary:
	return start(model_path, lora_path)

func stop() -> void:
	var had_task := _busy
	var was_generation := _stage == "generation"
	if _busy: _http.cancel_request()
	_busy = false
	_stage = ""
	set_process(false)
	if _server_started_by_us and is_server_running(): OS.kill(_server_pid)
	_server_pid = -1
	_server_started_by_us = false
	_active_model_path = ""
	_prompt = ""
	_negative_prompt = ""
	if had_task: completed.emit({"ok": false, "message": "Motor local encerrado pelo usuário.", "details": {"stage": "stopped", "cancelled_generation": was_generation}})

func _process(_delta: float) -> void:
	if not _busy: return
	if _stage == "starting":
		if not is_server_running(): _finish(false, "O motor local encerrou antes de ficar pronto. Confira o modelo, a LoRA e os drivers Vulkan."); return
		if Time.get_ticks_msec() >= _deadline_msec: _finish(false, "O carregamento do modelo excedeu dez minutos."); return
		if Time.get_ticks_msec() - _last_probe_msec >= 1800 and not _http.get_http_client_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING, HTTPClient.STATUS_BODY]:
			_last_probe_msec = Time.get_ticks_msec()
			_stage = "health"
			if _http.request(BASE_URL + "/sdapi/v1/sd-models") != OK: _stage = "starting"
	elif _stage == "health" and not is_server_running() and _server_pid > 0:
		_finish(false, "O motor local fechou durante a conexão.")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _busy: return
	if _stage == "starting": return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		if _stage == "health" and _server_started_by_us and is_server_running():
			_stage = "starting"
			return
		_finish(false, "O motor local respondeu com erro HTTP %d. Confira o log e a memória disponível." % response_code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	match _stage:
		"health":
			if not data is Array:
				if _server_started_by_us: _stage = "starting"; return
				_finish(false, "Resposta inesperada do motor local."); return
			if _prompt.is_empty(): _finish(true, "Motor local pronto.", {"stage": "health", "model": _model_path}); return
			_start_generation()
		"generation":
			if not data is Dictionary or not data.get("images", []) is Array or data.images.is_empty(): _finish(false, "O motor não devolveu uma imagem."); return
			var image_data: String = str(data.images[0]).trim_prefix("data:image/png;base64,")
			var bytes := Marshalls.base64_to_raw(image_data)
			var image := Image.new()
			if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK or image.is_empty(): _finish(false, "A saída local não é um PNG válido."); return
			if image.get_width() > 8192 or image.get_height() > 8192: _finish(false, "A imagem excede o limite de 8192×8192 pixels."); return
			var folder := "user://hyperlearn/generated"
			if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: _finish(false, "Não foi possível criar a pasta de candidatos."); return
			var path := folder.path_join("local-" + str(Time.get_ticks_usec()) + ".png")
			if image.save_png(path) != OK: _finish(false, "Não foi possível salvar a saída PNG."); return
			_finish(true, "Imagem criada localmente. Revise antes de aprovar.", {"path": path, "width": image.get_width(), "height": image.get_height(), "seed": _seed})

func _start_generation() -> void:
	var body := build_generation_payload(_prompt, _negative_prompt, _width, _height, _steps, _seed, _use_lora and FileAccess.file_exists(_lora_path), _lora_strength, _lora_path, _model_path)
	var headers := PackedStringArray(["Content-Type: application/json"])
	_stage = "generation"
	_deadline_msec = Time.get_ticks_msec() + 600000
	progress.emit("Gerando no computador local. A imagem ficará como candidata para sua revisão.")
	var request_error := _http.request(BASE_URL + "/sdapi/v1/txt2img", headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if request_error != OK: _finish(false, "Não foi possível iniciar a geração local.")

func _runtime_executable() -> String:
	var app_runtime := OS.get_executable_path().get_base_dir().path_join("local-ai").path_join("sd-server.exe")
	if FileAccess.file_exists(app_runtime): return app_runtime
	var project_runtime := "res://vendor/stable-diffusion-cpp/sd-server.exe"
	if FileAccess.file_exists(project_runtime): return ProjectSettings.globalize_path(project_runtime)
	return ""

func _finish(ok: bool, message: String, details: Dictionary = {}) -> void:
	_busy = false
	_stage = ""
	_prompt = ""
	_negative_prompt = ""
	set_process(false)
	completed.emit({"ok": ok, "message": message, "details": details})

func _exit_tree() -> void:
	stop()

