extends SceneTree
const Doc = preload("res://core/document.gd")
const Ramps = preload("res://core/material_ramps.gd")
const Effects = preload("res://core/sprite_effects.gd")
const Storage = preload("res://core/storage.gd")
const Contracts = preload("res://core/contracts.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else: failed += 1; printerr("FAIL ", name)

func fixture() -> RefCounted:
	var doc = Doc.new()
	doc.initialize_blank(16, 16, 4, 8)
	doc.palette = ["#202030", "#808090", "#e8e8f0", "#ff4040"]
	var ramps = Ramps.new()
	ramps.apply(doc, ramps.build(doc, "Fogo", 0, 1, 2, 5))
	for d in 8:
		for f in doc.frames:
			for y in range(6, 10):
				for x in range(6, 10): doc.layers[0].cels[d][f].set_pixel(x, y, Color("808090"))
	doc.undo_stack.clear()
	return doc

func cels_equal(left: Array, right: Array) -> bool:
	for d in 8:
		for f in left[d].size():
			if left[d][f].get_data() != right[d][f].get_data(): return false
	return true

func only_palette(doc: RefCounted, cels: Array) -> bool:
	var allowed := {}
	for hex in doc.palette: allowed[Color(hex).to_html(false)] = true
	for row in cels:
		for image in row:
			for y in doc.height:
				for x in doc.width:
					var color: Color = image.get_pixel(x, y)
					if color.a > 0.0 and not allowed.has(color.to_html(false)): return false
	return true

func _initialize() -> void:
	var effects = Effects.new()
	var doc = fixture()
	var body_id: String = doc.layers[0].id
	var ramp: Array = doc.art.material_ramps[0].colors

	# Glow
	var glow: Dictionary = effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0, 1], "params": {"radius": 2, "neighbors": 8}})
	expect(glow.get("ok", false), "brilho gera proposta para camada-fonte e rampa válidas")
	var cel: Image = glow.cels[0][0]
	expect(cel.get_pixel(5, 5).to_html(false) == Color(ramp[ramp.size() - 1]).to_html(false) and cel.get_pixel(4, 4).to_html(false) == Color(ramp[ramp.size() - 2]).to_html(false), "anel interno usa o tom mais claro e o externo o seguinte da rampa")
	expect(cel.get_pixel(7, 7).a == 0.0 and cel.get_pixel(3, 3).a == 0.0, "brilho não cobre a fonte nem passa do raio")
	expect(glow.cels[0][2].get_used_rect().size == Vector2i.ZERO and glow.cels[5][1].get_used_rect().size != Vector2i.ZERO, "quadros fora do intervalo ficam vazios e as 8 direções são geradas")
	expect(only_palette(doc, glow.cels), "brilho usa somente cores da paleta")
	var four: Dictionary = effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0], "params": {"radius": 1, "neighbors": 4}})
	expect(four.cels[0][0].get_pixel(5, 5).a == 0.0 and four.cels[0][0].get_pixel(5, 6).a > 0.0, "vizinhança 4 não preenche diagonais")
	var pulse: Dictionary = effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0, 1], "params": {"radius": 2, "pulse": 1}})
	expect(pulse.cels[0][0].get_pixel(4, 4).a > 0.0 and pulse.cels[0][1].get_pixel(4, 4).a == 0.0, "pulso alterna o raio entre quadros")
	expect(cels_equal(glow.cels, effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0, 1], "params": {"radius": 2, "neighbors": 8}}).cels), "mesma receita gera os mesmos pixels")

	# Flash
	var flash: Dictionary = effects.build(doc, {"type": "flash", "source_layer_id": body_id, "color": "#ff4040", "frames": [2]})
	expect(flash.get("ok", false) and flash.cels[3][2].get_pixel(7, 7).to_html(false) == "ff4040" and flash.cels[3][2].get_pixel(5, 5).a == 0.0, "clarão preenche só a silhueta da fonte")
	expect(flash.cels[3][1].get_used_rect().size == Vector2i.ZERO, "clarão fica restrito aos quadros escolhidos")
	expect(not effects.build(doc, {"type": "flash", "source_layer_id": body_id, "color": "#123456", "frames": [2]}).get("ok", false), "cor de clarão fora da paleta é recusada")

	# Particles
	doc.rig.anchors["2:0"] = {"hand": [3, 12]}
	var particles_recipe := {"type": "particles", "anchor": "hand", "clip": "walk", "ramp": "Fogo", "seed": 7, "frames": [0, 1, 2, 3], "params": {"count": 4, "life": 3, "speed": 1.0, "gravity": 0.0}}
	var particles: Dictionary = effects.build(doc, particles_recipe)
	expect(particles.get("ok", false), "partículas geram proposta com âncora, clip e seed")
	var hand_default: Array = doc.anchor_at("hand", 0, 0)
	expect(particles.cels[0][0].get_pixel(int(hand_default[0]), int(hand_default[1])).to_html(false) == Color(ramp[ramp.size() - 1]).to_html(false), "partícula nasce na âncora com o tom mais claro")
	expect(particles.cels[2][0].get_pixel(3, 12).a > 0.0, "emissão segue a âncora específica de cada direção e quadro")
	expect(cels_equal(particles.cels, effects.build(doc, particles_recipe).cels), "mesma seed reproduz as mesmas partículas")
	var other_seed := particles_recipe.duplicate(true)
	other_seed.seed = 8
	expect(not cels_equal(particles.cels, effects.build(doc, other_seed).cels), "seed diferente produz partículas diferentes")
	expect(only_palette(doc, particles.cels), "partículas usam somente cores da paleta")

	# Validation
	expect(not effects.build(doc, {"type": "smoke", "frames": [0]}).get("ok", false), "tipo desconhecido é recusado")
	expect(not effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0], "params": {"radius": 9}}).get("ok", false), "parâmetro fora do limite é recusado")
	expect(not effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0, 0]}).get("ok", false), "quadro repetido é recusado")
	expect(not effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Gelo", "frames": [0]}).get("ok", false), "rampa inexistente é recusada")
	expect(not effects.build(doc, {"type": "particles", "anchor": "cauda", "clip": "walk", "ramp": "Fogo", "frames": [0]}).get("ok", false), "âncora inexistente é recusada")

	# Apply, events, approvals, Undo/Redo
	doc.art.pose_approvals = [{"id": "pose"}]
	doc.manifest.approvals = [{"id": "pack", "human": true}]
	glow = effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0, 1], "params": {"radius": 2}})
	expect(effects.apply(doc, glow, "Aura"), "aceitar brilho cria camada de efeito")
	expect(doc.layers.size() == 2 and doc.layers[0].name == "Aura" and doc.layers[1].id == body_id and doc.layers[0].effect.type == "glow", "brilho entra logo abaixo da camada-fonte")
	expect(doc.composite(0, 0).get_pixel(7, 7).to_html(false) == "808090" and doc.composite(0, 0).get_pixel(5, 5).a > 0.0, "composição mantém a fonte e mostra o brilho")
	expect(doc.animation.events.get("0:0", []).has("fx_start:aura") and doc.animation.events.get("7:1", []).has("fx_end:aura"), "eventos de início e fim do efeito são gravados em todas as direções")
	expect(doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty(), "gerar efeito invalida aprovações")
	expect(doc.validate().is_empty(), "documento com camada de efeito continua válido")
	expect(doc.undo() and doc.layers.size() == 1 and not doc.animation.events.has("0:0") and doc.manifest.approvals.size() == 1, "Undo remove camada, eventos e restaura aprovações")
	expect(doc.redo() and doc.layers.size() == 2 and doc.layers[0].has("effect"), "Redo reaplica o efeito")
	var aura_id: String = doc.layers[0].id

	# Stale and refused applies
	var stale: Dictionary = effects.build(doc, {"type": "flash", "source_layer_id": body_id, "color": "#ff4040", "frames": [2]})
	doc.checkpoint("outra edição")
	expect(not effects.apply(doc, stale), "proposta obsoleta é recusada")
	doc.art.locked = true
	expect(not effects.build(doc, {"type": "flash", "source_layer_id": body_id, "color": "#ff4040", "frames": [2]}).get("ok", false), "Art Lock impede gerar efeito")
	doc.art.locked = false
	expect(not effects.build(doc, {"type": "glow", "source_layer_id": aura_id, "ramp": "Fogo", "frames": [0]}).get("ok", false), "camada de efeito não serve de fonte")
	var flash_after: Dictionary = effects.build(doc, {"type": "flash", "source_layer_id": body_id, "color": "#ff4040", "frames": [2]})
	expect(effects.apply(doc, flash_after) and doc.layers[2].effect.type == "flash" and doc.layers[1].id == body_id, "clarão entra logo acima da camada-fonte")

	# Regenerate with retouch detection
	var aura_index := 0
	doc.layers[aura_index].cels[0][0].set_pixel(0, 0, Color("e8e8f0"))
	expect(effects.retouched_cels(doc, aura_id) == ["0:0"], "retoque manual é detectado contra a última geração")
	var regen: Dictionary = effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0, 1, 2], "params": {"radius": 1}}, aura_id)
	expect(regen.get("ok", false) and regen.retouched_cels == ["0:0"], "regenerar avisa quais cels retocadas serão substituídas")
	expect(effects.apply(doc, regen) and doc.layers.size() == 3 and effects.retouched_cels(doc, aura_id).is_empty(), "regenerar substitui a camada e atualiza a referência")
	expect(doc.layers[0].effect.frames == [0, 1, 2] and doc.animation.events.get("0:2", []).has("fx_end:aura") and not doc.animation.events.get("0:1", []).has("fx_end:aura"), "regenerar troca os eventos antigos pelos novos")
	doc.layers[0].locked = true
	expect(not effects.build(doc, {"type": "glow", "source_layer_id": body_id, "ramp": "Fogo", "frames": [0]}, aura_id).get("ok", false), "camada de efeito bloqueada não é regenerada")
	doc.layers[0].locked = false

	# Frame insertion/removal keeps recipes aligned
	expect(doc.insert_frame_after(1) == 2 and doc.layers[0].effect.frames == [0, 1, 2, 3] and doc.layers[0].effect.baseline.has("0:3"), "inserir quadro remapeia quadros e referência do efeito")
	doc.frame = 0
	doc.delete_frame()
	expect(doc.layers[0].effect.frames == [0, 1, 2] and doc.validate().is_empty(), "remover quadro remapeia o efeito e mantém o documento válido")
	expect(effects.retouched_cels(doc, aura_id).is_empty(), "referência continua alinhada aos pixels após remapear quadros")

	# Save/load
	var storage = Storage.new()
	var path := ProjectSettings.globalize_path("user://sprite_effects_roundtrip.sfs")
	expect(storage.save_document(doc, path) == OK, "projeto com efeitos é salvo")
	var loaded = storage.load_document(path)
	expect(loaded != null and loaded.validate().is_empty() and loaded.layers[0].effect.frames == [0, 1, 2] and loaded.layers[0].effect.frames[0] is int, "projeto com efeitos reabre válido e com quadros inteiros")
	if loaded != null:
		var reloaded_regen: Dictionary = effects.build(loaded, loaded.layers[0].effect, aura_id)
		expect(reloaded_regen.get("ok", false) and reloaded_regen.changed_cels == 0 and reloaded_regen.retouched_cels.is_empty(), "receita salva regenera exatamente os mesmos pixels após reabrir")
	DirAccess.remove_absolute(path)

	# Export
	var export_folder := ProjectSettings.globalize_path("user://sprite_effects_export")
	expect(storage.export_all(doc, export_folder, "modular") == OK and FileAccess.file_exists(export_folder.path_join("modular_character.tscn")), "perfil modular exporta camadas de efeito")
	expect(storage.export_all(doc, export_folder.path_join("seq"), "sequence") == OK, "perfil de sequência exporta o efeito composto")
	var exported_metadata = Storage.read_json(export_folder.path_join("metadata.json"))
	expect(exported_metadata is Dictionary and exported_metadata.get("effects", []).size() == 2 and exported_metadata.effects[0].type == "glow" and exported_metadata.effects[1].type == "flash" and not exported_metadata.effects[0].has("baseline"), "metadata.json exporta a receita do efeito sem hashes internos")
	var exported_sequence = Storage.read_json(export_folder.path_join("seq").path_join("sequence.json"))
	expect(exported_sequence is Dictionary and exported_sequence.get("effects", []).size() == 2, "sequence.json lista o efeito com a receita")
	var modular_record = Storage.read_json(export_folder.path_join("modular.json"))
	expect(modular_record is Dictionary and modular_record.layers[0].get("effect", {}).get("type", "") == "glow" and not modular_record.layers[0].effect.has("baseline"), "modular.json registra o efeito na camada exportada")

	# Contracts
	var bad := storage.encode(doc)
	bad.layers[0].effect.params.radius = 99
	expect(not Contracts.valid_extensions(bad), "contrato recusa parâmetro de efeito fora do limite")
	bad = storage.encode(doc)
	bad.layers[0].effect.type = "smoke"
	expect(not Contracts.valid_extensions(bad), "contrato recusa tipo de efeito desconhecido")
	bad = storage.encode(doc)
	bad.layers[0].effect.baseline["0:0"] = "xyz"
	expect(not Contracts.valid_extensions(bad), "contrato recusa referência de pixels inválida")

	# Layer limit
	var full = fixture()
	while full.layers.size() < 16: full.add_layer("Extra")
	expect(not effects.build(full, {"type": "flash", "source_layer_id": full.layers[0].id, "color": "#ff4040", "frames": [0]}).get("ok", false), "limite de 16 camadas é respeitado")

	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/sprite-effects-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Sprite effects: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
