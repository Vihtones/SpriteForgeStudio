extends SceneTree

const Doc = preload("res://core/document.gd")
const Resizer = preload("res://core/canvas_resizer.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, title: String) -> void:
	checks.append({"name": title, "passed": value})
	if value: print("PASS ", title)
	else:
		failed += 1
		printerr("FAIL ", title)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var doc = Doc.new()
	doc.layers[0].cels[0][0].set_pixel(8, 8, Color.RED)
	doc.rig.anchors = {"0:0": {"head": [12, 4]}}
	doc.rig.offsets = {"0:0": {doc.layers[0].id: [2, 4]}}
	doc.rig.protected_pixels = {"0:0": [8 * doc.width + 8]}
	doc.animation.hitboxes = {"0:0": [5, 5, 8, 8]}
	doc.layers[0].offset = [2, 4]
	doc.art.pose_approvals = [{"human": true, "direction": "N", "clip": "attack", "frame": 0}]
	doc.manifest.approvals = [{"human": true}]
	var result: Dictionary = Resizer.resize_document(doc, 64, 64, Image.INTERPOLATE_NEAREST, "bottom_center")
	expect(result.get("ok", false) and doc.width == 64 and doc.height == 64, "redimensiona o canvas preservando proporção e tamanho solicitado")
	var every_cel_resized := true
	for layer in doc.layers:
		for direction in 8:
			for frame_index in doc.frames: every_cel_resized = every_cel_resized and layer.cels[direction][frame_index].get_size() == Vector2i(64, 64)
	expect(every_cel_resized and doc.layers[0].cels[0][0].get_pixel(16, 16) == Color.RED, "redimensiona todas as direções/frames e interpola por vizinho mais próximo")
	expect(doc.anchors.head == [32, 12] and doc.rig.anchors["0:0"].head == [24, 8], "pivôs globais e por pose acompanham a escala")
	expect(doc.rig.offsets["0:0"][doc.layers[0].id] == [4, 8] and doc.layers[0].offset == [4, 8], "offsets de equipamento acompanham a escala")
	expect(doc.rig.protected_pixels["0:0"] == [16 * 64 + 16], "máscaras protegidas são remapeadas para a nova grade")
	expect(doc.animation.hitboxes["0:0"] == [10, 10, 16, 16], "hitbox preserva área relativa ao redimensionar")
	expect(doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty() and doc.art.candidate_status == "candidate", "a aprovação da origem não é herdada por pixels redimensionados")
	expect(doc.undo() and doc.width == 32 and doc.height == 32 and doc.layers[0].cels[0][0].get_pixel(8, 8) == Color.RED, "Undo restaura dimensão e pixels anteriores")
	expect(doc.redo() and doc.width == 64 and doc.layers[0].cels[0][0].get_pixel(16, 16) == Color.RED, "Redo restaura a composição redimensionada")
	var blocked := Doc.new()
	blocked.art.locked = true
	var revision := blocked.revision
	var refused: Dictionary = Resizer.resize_document(blocked, 64, 64)
	expect(not refused.get("ok", false) and blocked.width == 32 and blocked.revision == revision, "Art Lock recusa alteração sem tocar no documento")
	var invalid: Dictionary = Resizer.resize_document(blocked, 4, 4)
	expect(not invalid.get("ok", false) and invalid.get("error", "").contains("8 a 512"), "dimensões fora do contrato são recusadas")
	var limited := Doc.new()
	limited.pixel_budget_limit = 100
	var over_budget: Dictionary = Resizer.resize_document(limited, 64, 64)
	expect(not over_budget.get("ok", false) and limited.width == 32, "limite de memória recusa canvas antes de alocar imagens")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var output := FileAccess.open("res://test_results/canvas-resizer-report.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print("Canvas resizer: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
