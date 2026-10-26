extends Node
## Optional, user-triggered image provider. Every request needs a fresh, payload-bound approval.
signal completed(result: Dictionary)

const ENDPOINT := "https://api.openai.com/v1/images/generations"
const DEFAULT_MODEL := "gpt-image-2.5-sunburst"
const ALLOWED_MODELS := ["gpt-image-2.5-sunburst", "gpt-image-2.5-flare"]
const ALLOWED_QUALITIES := ["low", "medium", "high", "xhigh", "max", "auto"]
const MAX_RESPONSE_BYTES := 32 * 1024 * 1024

var _http: HTTPRequest
var _approvals: Dictionary = {}
var _busy := false

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 180.0
	_http.body_size_limit = MAX_RESPONSE_BYTES
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func capabilities() -> Dictionary:
	return {
		"offline_editor": true,
		"openai": not _read_api_key().is_empty(),
		"provider": "OpenAI Images API",
		"model": DEFAULT_MODEL,
		"local_inference": false,
		"reason": "A geração remota só começa após aprovação explícita para cada pedido.",
		"experimental": {"graphify": false, "headroom": false}
	}

func validate_payload(payload: Dictionary) -> Dictionary:
	var prompt := str(payload.get("prompt", "")).strip_edges()
	var model := str(payload.get("model", DEFAULT_MODEL))
	var quality := str(payload.get("quality", "low"))
	if prompt.is_empty():
		return {"ok": false, "error": "Escreva uma descrição antes de gerar."}
	if prompt.length() > 5000:
		return {"ok": false, "error": "A descrição deve ter até 5.000 caracteres."}
	if model not in ALLOWED_MODELS:
		return {"ok": false, "error": "Modelo de imagem não permitido."}
	if quality not in ALLOWED_QUALITIES:
		return {"ok": false, "error": "Qualidade de imagem inválida."}
	return {"ok": true, "payload": {
		"prompt": prompt,
		"model": model,
		"quality": quality,
		"transparent": bool(payload.get("transparent", true))
	}}

func prepare_approval(payload: Dictionary) -> Dictionary:
	_purge_expired_approvals()
	var validation := validate_payload(payload)
	if not validation.ok:
		return validation
	var token := Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32)).replace("/", "_").replace("+", "-").replace("=", "")
	_approvals[token] = {"payload": validation.payload, "expires": Time.get_ticks_msec() + 120000}
	return {"ok": true, "token": token, "payload": validation.payload}

func consume_approval(payload: Dictionary, token: String) -> bool:
	_purge_expired_approvals()
	if token.is_empty() or not _approvals.has(token):
		return false
	var approved_payload: Dictionary = _approvals[token].payload
	_approvals.erase(token)
	var validation := validate_payload(payload)
	return validation.ok and validation.payload == approved_payload

## This method never treats a boolean as consent. The token must come from a fresh approval dialog.
func request(payload: Dictionary, authorization: Dictionary = {}) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "Já existe uma geração em andamento."}
	var token := str(authorization.get("approval_token", ""))
	if not consume_approval(payload, token):
		return {"ok": false, "error": "O pedido mudou depois da aprovação. Revise e aprove novamente."}
	var approved_payload: Dictionary = validate_payload(payload).payload
	var api_key := _read_api_key()
	if api_key.is_empty():
		return {"ok": false, "error": "Chave não encontrada. Configure OPENAI_API_KEY e reinicie o editor."}
	var body := {
		"model": approved_payload.model,
		"prompt": approved_payload.prompt,
		"quality": approved_payload.quality,
		"size": "1024x1024",
		"n": 1,
		"output_format": "png"
	}
	if approved_payload.transparent:
		body["background"] = "transparent"
	var headers := ["Authorization: Bearer " + api_key, "Content-Type: application/json"]
	var error := _http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(body))	
	if error != OK:
		return {"ok": false, "error": "Não foi possível iniciar a conexão com o provedor."}
	_busy = true
	return {"ok": true, "started": true}

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		completed.emit({"ok": false, "error": "A conexão falhou ou expirou. Nenhuma nova tentativa foi feita."})
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		completed.emit({"ok": false, "error": "O provedor recusou o pedido (HTTP %d). Revise a configuração ou a descrição e tente novamente somente quando quiser." % response_code})
		return
	if not parsed is Dictionary or not parsed.get("data", []) is Array or parsed.data.is_empty():
		completed.emit({"ok": false, "error": "A resposta não continha uma imagem válida."})
		return
	var encoded := str(parsed.data[0].get("b64_json", ""))
	if encoded.is_empty():
		completed.emit({"ok": false, "error": "A resposta não continha dados de imagem."})
		return
	var png := Marshalls.base64_to_raw(encoded)
	if png.is_empty() or png.size() > MAX_RESPONSE_BYTES:
		completed.emit({"ok": false, "error": "A imagem recebida é inválida ou excede o limite local."})
		return
	var image := Image.new()
	if image.load_png_from_buffer(png) != OK or image.is_empty():
		completed.emit({"ok": false, "error": "Não foi possível validar o PNG recebido."})
		return
	var folder := "user://ai_generated"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		completed.emit({"ok": false, "error": "Não foi possível criar a pasta local de resultados."})
		return
	var output_path := folder.path_join("sprite-" + str(Time.get_ticks_usec()) + ".png")
	if image.save_png(output_path) != OK:
		completed.emit({"ok": false, "error": "Não foi possível salvar a imagem gerada."})
		return
	completed.emit({"ok": true, "path": output_path, "width": image.get_width(), "height": image.get_height()})

func _read_api_key() -> String:
	var environment_key := OS.get_environment("OPENAI_API_KEY").strip_edges()
	if not environment_key.is_empty():
		return environment_key
	# Development convenience only. This file is outside the product folder and excluded from builds.
	if OS.has_feature("editor"):
		var local_env := ProjectSettings.globalize_path("res://../../.env.local")
		if FileAccess.file_exists(local_env):
			var file := FileAccess.open(local_env, FileAccess.READ)
			if file:
				while not file.eof_reached():
					var line := file.get_line().strip_edges()
					if line.begins_with("OPENAI_API_KEY="):
						return line.trim_prefix("OPENAI_API_KEY=").strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
	return ""

func _purge_expired_approvals() -> void:
	var now := Time.get_ticks_msec()
	for token in _approvals.keys():
		if int(_approvals[token].expires) <= now:
			_approvals.erase(token)
