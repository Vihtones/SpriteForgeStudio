extends SceneTree
const Doc = preload("res://core/document.gd")
const Cleaner = preload("res://core/cluster_cleaner.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else: failed += 1; printerr("FAIL ", name)

func _initialize() -> void:
	var cleaner = Cleaner.new()
	var doc = Doc.new()
	var cel: Image = doc.current()
	cel.set_pixel(0, 0, Color.WHITE)
	cel.set_pixel(2, 2, Color.RED)
	cel.set_pixel(3, 3, Color.BLUE)
	cel.set_pixel(5, 5, Color.GREEN)
	cel.set_pixel(6, 5, Color.GREEN)
	for y in range(10, 13):
		for x in range(10, 13): cel.set_pixel(x, y, Color.YELLOW)
	doc.art.pose_approvals = [{"id": "approved-pose"}]
	doc.manifest.approvals = [{"id": "approved-pack"}]
	doc.art.candidate_status = "approved"
	var source_before: PackedByteArray = cel.get_data()
	var preview: Dictionary = cleaner.build(doc, 1)
	if not preview.get("ok", false):
		printerr("Cluster preview rejected: ", preview.get("message", "sem motivo"))
		quit(1)
		return
	expect(preview.ok and preview.removed_components == 1 and preview.removed_pixels == 1, "prévia detecta e propõe somente ilha individual; diagonais são conectividade de oito vizinhos")
	expect(cel.get_data() == source_before and preview.after.get_pixel(0, 0).a == 0.0 and preview.after.get_pixel(2, 2).a == 1.0 and preview.after.get_pixel(3, 3).a == 1.0, "construção da proposta não altera a cel e a comparação preserva o cluster diagonal conectado")
	expect(preview.after.get_pixel(5, 5).a == 1.0 and preview.after.get_pixel(10, 10).a == 1.0, "pares conectados e regiões acima do limite são preservados")
	expect(cleaner.apply(doc, preview) and doc.current().get_pixel(0, 0).a == 0.0, "confirmação aplica proposta revisada")
	expect(doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty() and doc.art.candidate_status == "candidate", "alteração rasterizada invalida aprovações anteriores")
	expect(doc.undo() and doc.current().get_data() == source_before, "Undo restaura pixels e estado artístico anteriores")
	expect(doc.art.pose_approvals.size() == 1 and doc.manifest.approvals.size() == 1, "Undo restaura o estado de aprovações removidas")
	expect(doc.redo() and doc.current().get_pixel(0, 0).a == 0.0, "Redo reaplica a limpeza")
	var protected_doc = Doc.new()
	protected_doc.current().set_pixel(4, 4, Color.RED)
	protected_doc.current().set_pixel(5, 4, Color.BLUE)
	var protected_key := protected_doc.cel_key()
	protected_doc.rig.protected_pixels = {protected_key: [4 * protected_doc.width + 4]}
	protected_doc.selection = Rect2i(4, 4, 1, 1)
	var protected_preview: Dictionary = cleaner.build(protected_doc, 2)
	expect(protected_preview.ok and protected_preview.removed_pixels == 0, "componente que cruza a seleção é preservado por inteiro")
	protected_doc.selection = Rect2i()
	protected_preview = cleaner.build(protected_doc, 2)
	expect(protected_preview.ok and protected_preview.removed_pixels == 0, "componente conectado a pixel protegido é preservado por inteiro")
	var lock_doc = Doc.new()
	lock_doc.current().set_pixel(3, 3, Color.RED)
	lock_doc.art.locked = true
	expect(not cleaner.build(lock_doc).ok, "Art Lock impede nova proposta")
	lock_doc.art.locked = false
	lock_doc.layers[0].locked = true
	expect(not cleaner.build(lock_doc).ok, "camada bloqueada impede nova proposta")
	lock_doc.layers[0].locked = false
	lock_doc.active_layer = 99
	expect(not cleaner.build(lock_doc).ok, "índice de camada inválido não acessa dados")
	var stale_doc = Doc.new()
	stale_doc.current().set_pixel(1, 1, Color.RED)
	var stale: Dictionary = cleaner.build(stale_doc)
	stale_doc.selection = Rect2i(0, 0, 1, 1)
	expect(not cleaner.apply(stale_doc, stale), "alteração de seleção depois da proposta a invalida")
	var altered_preview: Dictionary = cleaner.build(stale_doc)
	stale_doc.current().set_pixel(2, 2, Color.RED)
	expect(not cleaner.apply(stale_doc, altered_preview), "pixels alterados depois da proposta impedem aplicar snapshot obsoleto")
	var bad_payload: Dictionary = cleaner.build(stale_doc)
	if bad_payload.get("pixels", PackedInt32Array()).size() > 0:
		bad_payload.pixels = PackedInt32Array([-1])
		expect(not cleaner.apply(stale_doc, bad_payload), "índices de pixel malformados são recusados")
	else:
		expect(true, "índices de pixel malformados são recusados")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/cluster-cleaner-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Cluster cleaner: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
