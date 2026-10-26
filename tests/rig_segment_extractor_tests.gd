extends SceneTree
const Doc = preload("res://core/document.gd")
const Extractor = preload("res://core/rig_segment_extractor.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else: failed += 1; printerr("FAIL ", name)

func _initialize() -> void:
	var extractor = Extractor.new()
	var doc = Doc.new()
	doc.art.locked = false
	doc.layers[0].opacity = 0.65
	var source_id: String = str(doc.layers[0].id)
	doc.add_layer("Overlay")
	var overlay_id: String = str(doc.layers[1].id)
	doc.active_layer = 0
	var source: Image = doc.layers[0].cels[0][0]
	source.set_pixel(2, 2, Color.RED)
	source.set_pixel(3, 2, Color.BLUE)
	source.set_pixel(4, 2, Color.GREEN)
	source.set_pixel(2, 3, Color.YELLOW)
	source.set_pixel(3, 3, Color.MAGENTA)
	source.set_pixel(6, 4, Color.WHITE)
	doc.layers[1].cels[0][0].set_pixel(3, 2, Color.CYAN)
	doc.selection = Rect2i(2, 2, 3, 2)
	var key: String = doc.cel_key()
	doc.rig.protected_pixels = {key: [3 * doc.width + 3]}
	doc.rig.depth = {key: {source_id: 2, overlay_id: 2}}
	doc.art.pose_approvals = [{"id": "pose"}]
	doc.manifest.approvals = [{"id": "pack"}]
	doc.art.candidate_status = "approved"
	var source_before: PackedByteArray = source.get_data()
	var composite_before: PackedByteArray = doc.composite().get_data()
	var preview: Dictionary = extractor.build(doc, "Braço esquerdo", "selection", Vector2i.ZERO, ["shoulder_l", "elbow_l"])
	if not preview.get("ok", false): printerr("Rig extraction rejected: ", preview.get("message", "sem motivo")); quit(1); return
	expect(preview.pixels.size() == 4, "seleção move pixels opacos e ignora o protegido")
	expect(source.get_data() == source_before and preview.extracted.get_pixel(2, 2) == Color.RED and preview.source_after.get_pixel(2, 2).a == 0.0, "prévia separa uma cópia sem alterar a cel de origem")
	expect(preview.extracted.get_pixel(3, 3).a == 0.0 and preview.extracted.get_pixel(6, 4).a == 0.0, "pixels protegidos e fora da seleção não são extraídos")
	expect(preview.layer_template.bone == ["shoulder_l", "elbow_l"] and preview.layer_template.pivot == "shoulder_l", "nova camada pode nascer mapeada ao segmento ósseo e pivô-raiz")
	expect(preview.layer_template.opacity == doc.layers[0].opacity and preview.layer_template.equipment == doc.layers[0].equipment, "camada nova herda propriedades que preservam a composição")
	expect(extractor.apply(doc, preview) and doc.layers.size() == 3 and doc.active_layer == 1, "aceitar cria uma camada independente imediatamente acima da fonte")
	var extracted_layer: Dictionary = doc.layers[1]
	expect(extracted_layer.bone == ["shoulder_l", "elbow_l"] and extracted_layer.pivot == "shoulder_l" and extracted_layer.cels[0][0].get_pixel(2, 2) == Color.RED, "rasters extraídos e mapeamento ficam utilizáveis no painel do rig")
	expect(doc.layers[0].cels[0][0].get_pixel(2, 2).a == 0.0 and doc.layers[0].cels[0][0].get_pixel(3, 3) == Color.MAGENTA, "a origem perde apenas os pixels movidos; a máscara protegida permanece")
	expect(doc.composite().get_data() == composite_before, "composição final permanece pixel-idêntica com opacidade e camada superior")
	expect(doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty() and doc.art.candidate_status == "candidate", "separar arte invalida aprovações anteriores")
	expect(doc.undo() and doc.layers.size() == 2 and doc.active_layer == 0 and doc.layers[0].cels[0][0].get_data() == source_before and doc.composite().get_data() == composite_before, "Undo restaura raster, camadas e composição exatos")
	expect(doc.art.pose_approvals.size() == 1 and doc.manifest.approvals.size() == 1, "Undo também restaura aprovações removidas")
	expect(doc.redo() and doc.layers.size() == 3 and doc.composite().get_data() == composite_before, "Redo refaz extração sem sangramento na composição")
	var connected = Doc.new()
	connected.layers[0].cels[0][0].set_pixel(8, 8, Color.RED)
	connected.layers[0].cels[0][0].set_pixel(9, 9, Color.BLUE)
	connected.layers[0].cels[0][0].set_pixel(10, 10, Color.GREEN)
	connected.layers[0].cels[0][0].set_pixel(12, 10, Color.YELLOW)
	var component: Dictionary = extractor.build(connected, "Braço", "connected", Vector2i(8, 8))
	expect(component.get("ok", false) and component.pixels.size() == 3, "segmentação conectada inclui pixels de cores diferentes e conectividade diagonal")
	expect(extractor.apply(connected, component) and connected.layers[1].cels[0][0].get_pixel(10, 10) == Color.GREEN and connected.layers[0].cels[0][0].get_pixel(12, 10) == Color.YELLOW, "componente distante permanece na camada fonte")
	var protected_seed = Doc.new()
	protected_seed.current().set_pixel(4, 4, Color.RED)
	protected_seed.rig.protected_pixels = {protected_seed.cel_key(): [4 * protected_seed.width + 4]}
	expect(not extractor.build(protected_seed, "Braço", "connected", Vector2i(4, 4)).get("ok", false), "semente protegida não inicia extração")
	var lock_doc = Doc.new()
	lock_doc.current().set_pixel(4, 4, Color.RED)
	lock_doc.art.locked = true
	expect(not extractor.build(lock_doc, "Braço").get("ok", false), "Art Lock impede extração")
	lock_doc.art.locked = false
	lock_doc.layers[0].locked = true
	expect(not extractor.build(lock_doc, "Braço").get("ok", false), "camada bloqueada impede extração")
	lock_doc.layers[0].locked = false
	expect(not extractor.build(lock_doc, "Corpo").get("ok", false), "nome duplicado de camada é recusado")
	expect(not extractor.build(lock_doc, "Braço", "selection", Vector2i.ZERO, ["not_a_joint", "another_joint"]).get("ok", false), "mapeamento para segmento inexistente é recusado")
	var rotated = Doc.new()
	rotated.current().set_pixel(4, 4, Color.RED)
	rotated.set_layer_rotation(str(rotated.layers[0].id), 20.0, 0, 0, false)
	expect(not extractor.build(rotated, "Braço").get("ok", false), "rotação ativa precisa ser rasterizada antes de separar")
	var stale = Doc.new()
	stale.current().set_pixel(4, 4, Color.RED)
	var stale_proposal: Dictionary = extractor.build(stale, "Braço")
	stale.selection = Rect2i(0, 0, 2, 2)
	expect(not extractor.apply(stale, stale_proposal), "seleção alterada depois da prévia invalida a operação")
	stale.selection = Rect2i()
	stale_proposal = extractor.build(stale, "Braço")
	stale.rig.protected_pixels = {stale.cel_key(): [0]}
	expect(not extractor.apply(stale, stale_proposal), "máscara alterada depois da prévia invalida a operação")
	stale.rig.protected_pixels.clear()
	stale_proposal = extractor.build(stale, "Braço")
	stale.current().set_pixel(5, 5, Color.BLUE)
	expect(not extractor.apply(stale, stale_proposal), "pixels alterados após a prévia impedem extração obsoleta")
	var capped = Doc.new()
	for index in range(1, 16): capped.add_layer("L%d" % index)
	expect(not extractor.build(capped, "Limite").get("ok", false), "limite estrutural de 16 camadas é verificado antes do snapshot")
	var memory_limited = Doc.new()
	memory_limited.pixel_budget_limit = memory_limited.pixel_bytes()
	expect(not extractor.build(memory_limited, "Limite").get("ok", false), "orçamento de memória barra extração antes de alocar camadas")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/rig-segment-extractor-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Rig segment extractor: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
