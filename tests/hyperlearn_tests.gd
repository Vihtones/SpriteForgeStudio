extends SceneTree
const Doc = preload("res://core/document.gd")
const HyperLearn = preload("res://core/hyperlearn.gd")
const LocalProvider = preload("res://core/comfyui_provider.gd")
const LocalImageProvider = preload("res://core/local_image_provider.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, title: String) -> void:
	if value: passed += 1; print("PASS ", title)
	else: failed += 1; printerr("FAIL ", title)

func run() -> void:
	var doc = Doc.new(); doc.demo()
	var engine = HyperLearn.new()
	engine.store_path = "res://test_results/hyperlearn-test-feedback.json"
	engine.model_path = "res://test_results/hyperlearn-test-model.json"
	engine.preview_root = "res://test_results/hyperlearn-previews"
	engine.examples.clear(); engine.model.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(engine.store_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(engine.model_path))
	var features: Array = engine.describe(doc)
	expect(features.size() == 5 and features.all(func(value): return value >= 0.0 and value <= 1.0), "HyperLearn extrai vetores determinísticos em faixa normalizada")
	var motion_doc = Doc.new(); motion_doc.frames = 4; motion_doc.layers.clear(); motion_doc.add_layer("Movimento")
	for frame_index in 4: motion_doc.layers[0].cels[0][frame_index].set_pixel(frame_index, 0, Color.WHITE)
	var directional_motion: Array = engine.describe(motion_doc, [0])
	expect(is_equal_approx(directional_motion[4], 2.0 / float(motion_doc.width * motion_doc.height)), "sinal de movimento parcial usa somente pares de quadros da direção selecionada")
	var denied: Dictionary = engine.record_review(doc, true, "Teste", "", false)
	expect(not denied.ok and engine.counts().total == 0, "feedback sem confirmação não é persistido")
	var recorded: Dictionary = engine.record_review(doc, true, "Revisor de teste", "Silhueta legível", true)
	expect(recorded.ok and recorded.item.asset_sha256.length() == 64, "aprovação explícita é guardada com hash e proveniência")
	var failing_store := "res://test_results/hyperlearn-write-failure-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(failing_store))
	var failure_engine = HyperLearn.new()
	failure_engine.store_path = failing_store
	failure_engine.preview_root = "res://test_results/hyperlearn-failure-previews"
	failure_engine.examples.clear()
	for index in HyperLearn.MAX_EXAMPLES:
		failure_engine.examples.append({"id": "old-%d" % index, "asset_sha256": "%064d" % (index + 1), "label": 0, "preview_path": ""})
	var failure_before: String = failure_engine.examples[0].id
	var failed_persist: Dictionary = failure_engine.record_review(doc, true, "Revisor de teste", "Não perder registro", true)
	var failed_preview := str(failed_persist.get("item", {}).get("preview_path", ""))
	expect(not failed_persist.ok and failure_engine.examples.size() == HyperLearn.MAX_EXAMPLES and failure_engine.examples[0].id == failure_before, "falha de persistência preserva integralmente a base em memória no limite")
	expect(failed_preview.is_empty() or not FileAccess.file_exists(ProjectSettings.globalize_path(failed_preview)), "falha de persistência remove a prévia recém-criada que ficou sem registro")
	expect(not FileAccess.file_exists(ProjectSettings.globalize_path(failing_store + ".tmp")), "falha de persistência limpa o arquivo temporário")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(failing_store))
	var scoped: Dictionary = engine.record_review(doc, true, "Revisor de teste", "Somente vista leste", true, [2])
	var scoped_preview := Image.load_from_file(ProjectSettings.globalize_path(str(scoped.get("item", {}).get("preview_path", "")))) if scoped.ok else Image.new()
	expect(scoped.ok and scoped.item.direction_names == ["E"] and scoped.item.scope == "selected_directions_and_all_frames", "avaliação direcional registra escopo exato sem aprovar vistas vizinhas")
	expect(scoped.ok and scoped.item.asset_sha256 != recorded.item.asset_sha256 and scoped_preview.get_height() == 32, "hash e prancha de contato são restritos à direção revisada")
	var reopened = HyperLearn.new(); reopened.store_path = engine.store_path; reopened.model_path = engine.model_path; reopened.load_store()
	expect(reopened.counts().approved == 2, "banco HyperLearn recarrega registros de escopo total e direcional")
	var provider = LocalProvider.new()
	expect(provider.validate_endpoint("http://127.0.0.1:8188") and provider.validate_endpoint("http://localhost:8188"), "adaptador local aceita apenas os hosts locais autorizados")
	expect(not provider.validate_endpoint("https://example.com") and not provider.validate_endpoint("http://192.168.0.12:8188"), "adaptador local recusa rede pública e LAN")
	var workflow_path := "res://test_results/hyperlearn-workflow.json"
	var workflow := {"1": {"class_type": "CLIPTextEncode", "inputs": {"text": "pixel art {{PROMPT}}", "clip": ["2", 0]}}, "2": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": "local-model.safetensors"}}, "3": {"class_type": "SaveImage", "inputs": {"images": ["4", 0], "filename_prefix": "sfs"}}, "4": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["2", 2]}}, "5": {"class_type": "KSampler", "inputs": {"seed": 42}}}
	var file := FileAccess.open(workflow_path, FileAccess.WRITE); file.store_string(JSON.stringify(workflow)); file.close()
	var ready: Dictionary = provider.prepare_workflow(workflow_path, "Sentinela em oito direções")
	expect(ready.ok and ready.prompt_nodes == 1 and ready.workflow["1"].inputs.text.ends_with("Sentinela em oito direções"), "workflow local substitui o token de prompt na memória")
	var bad_path := "res://test_results/hyperlearn-bad-workflow.json"
	file = FileAccess.open(bad_path, FileAccess.WRITE); file.store_string(JSON.stringify({"1": {"class_type": "OpenAIImageGeneration", "inputs": {"text": "{{PROMPT}}"}}})); file.close()
	expect(not provider.prepare_workflow(bad_path, "teste").ok, "workflow com API/serviço cloud é bloqueado")
	var local_image_provider = LocalImageProvider.new()
	expect(not local_image_provider.check("", "").ok, "verificação nativa local valida assinatura e não tenta iniciar sem modelo")
	expect(local_image_provider.validate_options("sprite humanoide", "limb errors", 512, 512, 12).ok, "gerador local aceita parâmetros suportados pela RX 580")
	expect(not local_image_provider.validate_options("", "", 512, 512, 12).ok, "geração local rejeita prompt vazio")
	expect(not local_image_provider.validate_options("sprite", "", 300, 512, 12).ok and not local_image_provider.validate_options("sprite", "", 512, 512, 31).ok, "geração local rejeita dimensões não alinhadas e contagem excessiva de passos")
	var local_payload: Dictionary = local_image_provider.build_generation_payload("sprite pixel art", "membros soltos", 512, 512, 12, 81, true, 0.8, "pixel-art-LoRa.safetensors")
	expect(local_payload.seed == 81 and local_payload.batch_size == 1 and local_payload.lora[0].path == "pixel-art-LoRa.safetensors" and local_payload.lora[0].multiplier == 0.8, "requisição local mantém seed, limita lote e usa LoRA estruturada sem chamada externa")
	var lcm_payload: Dictionary = local_image_provider.build_generation_payload("warrior", "extra arms", 512, 512, 12, 9, false, 0.0, "", "DreamShaper8_LCM_q8_0.gguf")
	expect(lcm_payload.sampler_name == "lcm" and lcm_payload.cfg_scale == 2.0 and lcm_payload.steps == 8, "DreamShaper LCM seleciona sampler, CFG e teto de passos próprios do modelo")
	var too_small: Dictionary = engine.train()
	expect(not too_small.ok and too_small.get("training_counts", {}).get("approved", 0) == 1, "conjunto pequeno não habilita treino/autonomia")
	var clip_doc = Doc.new(); clip_doc.frames = 4; clip_doc.layers.clear(); clip_doc.add_layer("Corpo"); clip_doc.animation = {"active": 0, "clips": [{"name": "idle", "frames": [0,1], "durations_ms": {}, "loop": true}, {"name": "jump", "frames": [2,3], "durations_ms": {}, "loop": false}], "events": {}, "hitboxes": {}}
	for d in 8:
		for f in 4: clip_doc.layers[0].cels[d][f].set_pixel(4 + f, 4 + d % 4, Color.WHITE)
	var initial: int = clip_doc.frames
	var extension := clip_doc.extend_clip_with_holds("jump", 2)
	var hold_clip: Dictionary = clip_doc.animation.clips[1]
	expect(extension and clip_doc.frames == initial + 2 and hold_clip.frames.size() == 4, "estender movimento adiciona dois holds no clip certo")
	expect(clip_doc.layers[0].cels[0][hold_clip.frames[-1]].get_data() == clip_doc.layers[0].cels[0][hold_clip.frames[-2]].get_data(), "quadros extras preservam pixels e não inventam anatomia")
	expect(clip_doc.animation.clips[0].frames == [0, 1] and clip_doc.validate().is_empty(), "remapeamento preserva clips vizinhos e integridade")
	var auto_result: Dictionary = reopened.evaluate(doc, true)
	expect(not auto_result.get("ready", false) and auto_result.decision == "human_review", "modo autônomo abstém enquanto a evidência for insuficiente")
	var training_rows: Array[Dictionary] = []
	for index in 6:
		var full_scope := index < 4
		var approved := index % 2 == 0
		training_rows.append({"id": "sample-%d" % index, "project_id": "project-%d" % index, "asset_sha256": str(index).repeat(64), "features": [0.2, 0.3, 0.4, 0.5, 0.6], "label": 1 if approved else 0, "scope": "current_document_all_directions_and_frames" if full_scope else "selected_directions_and_all_frames", "direction_indices": range(8) if full_scope else [index]})
	engine.examples = training_rows
	var filtered_train: Dictionary = engine.train()
	expect(filtered_train.ok and filtered_train.model.training_examples == 4 and filtered_train.model.approved == 2 and filtered_train.model.rejected == 2, "treino geral exclui avaliações direcionais parciais e usa somente packs completos")
	expect(filtered_train.excluded_scoped_examples == 2 and filtered_train.counts.total == 6, "HyperLearn mantém avaliações parciais no banco e informa que não treinaram o modelo geral")
	var small_evidence_result: Dictionary = engine.evaluate(doc, true)
	expect(filtered_train.model.validation_examples < 20 and not small_evidence_result.ready, "validação pequena ou desequilibrada mantém o classificador em revisão humana")
	var high_quality_doc = Doc.new(); high_quality_doc.demo()
	var positive_features: Array = engine.describe(high_quality_doc)
	engine.examples.clear()
	for project_index in 12:
		for sample_index in 6:
			var is_approved := sample_index < 4
			var sample_features: Array = positive_features.duplicate() if is_approved else [0.0, 0.0, 0.0, 0.0, 0.0]
			engine.examples.append({"id": "cv-%d-%d" % [project_index, sample_index], "project_id": "cv-project-%d" % project_index, "asset_sha256": "%064d" % (project_index * 6 + sample_index + 1), "features": sample_features, "label": 1 if is_approved else 0, "scope": "current_document_all_directions_and_frames", "direction_indices": range(8)})
	var balanced_train: Dictionary = engine.train()
	var strong_signal: Dictionary = engine.evaluate(high_quality_doc, true)
	var disabled_signal: Dictionary = engine.evaluate(high_quality_doc, false)
	expect(balanced_train.ok and balanced_train.model.validation_projects_scored == 12 and balanced_train.model.validation_examples >= 20 and balanced_train.model.validation_folds >= 4, "validação mede previsões fora da amostra por pelo menos 12 projetos e quatro folds")
	expect(balanced_train.model.validation_balanced_accuracy >= 0.90 and balanced_train.model.validation_approved_recall >= 0.90 and balanced_train.model.validation_rejected_recall >= 0.90 and balanced_train.model.validation_brier_score <= 0.10, "relatório de validação inclui precisão balanceada, sensibilidade por classe e Brier")
	expect(strong_signal.ready and strong_signal.decision == "auto_approve_candidate", "sinal sintético balanceado demonstra que o caminho autônomo só abre após os novos portões estatísticos")
	expect(disabled_signal.eligible_for_autonomy and not disabled_signal.ready and disabled_signal.decision == "human_review", "classificador distingue elegibilidade estatística de autorização autônoma ativa")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(recorded.item.preview_path)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(scoped.item.preview_path)))
	provider.free()
	local_image_provider.free()
	var report := FileAccess.open("res://test_results/hyperlearn-report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("HyperLearn: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
