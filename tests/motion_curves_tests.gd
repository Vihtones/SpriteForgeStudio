extends SceneTree
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const Contracts = preload("res://core/contracts.gd")
const MotionCurves = preload("res://core/motion_curves.gd")
const Interpolator = preload("res://core/rig_interpolator.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else:
		failed += 1
		printerr("FAIL ", name)

func _initialize() -> void:
	_curve_checks()
	_timing_checks()
	_persistence_checks()
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/motion-curves-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Motion curves: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)

func _curve_checks() -> void:
	var exact_ends := true
	var monotonic := true
	var specs: Array = MotionCurves.PRESETS.duplicate()
	specs.append(MotionCurves.bezier(0.42, 0.0, 0.58, 1.0))
	for spec in specs:
		if MotionCurves.evaluate(spec, 0.0) != 0.0 or MotionCurves.evaluate(spec, 1.0) != 1.0: exact_ends = false
		if spec == "overshoot": continue
		var previous := 0.0
		for step in 101:
			var value := MotionCurves.evaluate(spec, step / 100.0)
			if value < previous - 0.000001 or value > 1.0 + 0.000001: monotonic = false
			previous = value
	expect(exact_ends, "todas as curvas chegam exatamente às chaves nos extremos")
	expect(monotonic, "curvas sem overshoot avançam sem recuar nem passar da chave")
	expect(is_equal_approx(MotionCurves.evaluate("linear", 0.25), 0.25), "linear mantém espaçamento uniforme")
	expect(MotionCurves.evaluate("ease_in", 0.25) < 0.25 and MotionCurves.evaluate("ease_out", 0.25) > 0.25, "ease in sai devagar e ease out chega devagar")
	expect(is_equal_approx(MotionCurves.evaluate("ease_in_out", 0.5), 0.5) and MotionCurves.evaluate("ease_in_out", 0.1) < 0.1 and MotionCurves.evaluate("ease_in_out", 0.9) > 0.9, "ease in-out é simétrica e acomoda nas duas chaves")
	expect(MotionCurves.evaluate("hold", 0.99) == 0.0, "hold mantém a pose anterior até a próxima chave")
	var peak := 0.0
	for step in 101: peak = maxf(peak, MotionCurves.evaluate("overshoot", step / 100.0))
	expect(peak > 1.0 and peak < 1.05, "overshoot passa da chave em menos de 5% e retorna")
	var css_ease := MotionCurves.bezier(0.42, 0.0, 0.58, 1.0)
	expect(is_equal_approx(snappedf(MotionCurves.evaluate(css_ease, 0.5), 0.0001), 0.5) and MotionCurves.evaluate(css_ease, 0.2) < 0.2, "Bézier cúbica personalizada é avaliada pela coordenada de tempo")
	expect(not MotionCurves.is_valid("cubic_bezier:1.5,0,0.5,1") and not MotionCurves.is_valid("cubic_bezier:0,0,1") and not MotionCurves.is_valid("bounce") and not MotionCurves.is_valid(3), "curvas desconhecidas ou fora dos limites são recusadas")

func _arm_doc() -> Array:
	var doc = Doc.new()
	doc.add_layer("Braço", true)
	var layer: Dictionary = doc.layers[doc.active_layer]
	layer.pivot = "elbow_l"
	var layer_id: String = str(layer.id)
	doc.animation.clips = [{"name": "swing", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}]
	doc.rig.rotations = {"0:0": {layer_id: 0.0}, "0:3": {layer_id: 90.0}}
	doc.rig.anchors = {"0:0": {"elbow_l": [2, 4]}, "0:3": {"elbow_l": [8, 10]}}
	return [doc, layer_id]

func _rotations(proposal: Dictionary) -> Dictionary:
	var values := {}
	for change in proposal.get("changes", []):
		if change.kind == "rotation": values[int(change.frame)] = float(change.value)
	return values

func _timing_checks() -> void:
	var interpolator = Interpolator.new()
	var setup := _arm_doc()
	var doc = setup[0]
	var layer_id: String = setup[1]
	var legacy: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true, "anchor": true})
	doc.animation.clips[0].durations_ms = {"0": 300, "1": 100, "2": 100}
	var legacy_timed: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true, "anchor": true})
	doc.animation.clips[0].durations_ms = {}
	expect(legacy_timed.changes == legacy.changes, "durações reais não mudam a interpolação sem a opção de tempo explícita")
	var explicit: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true, "anchor": true}, {"timing": "frames", "curve": "linear"})
	expect(legacy.ok and legacy.changes == explicit.changes, "sem opções e com durações iguais o resultado é idêntico ao linear por quadro anterior")
	expect(_rotations(legacy) == {1: 30.0, 2: 60.0}, "projeto sem curvas preserva os valores lineares de antes")
	doc.animation.clips[0].durations_ms = {"0": 300, "1": 100, "2": 100}
	var timed := _rotations(interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true}, {"timing": "duration"}))
	expect(is_equal_approx(timed[1], 54.0) and is_equal_approx(timed[2], 72.0), "espaçamento segue a duração real de cada quadro")
	var by_frame := _rotations(interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true}, {"timing": "frames"}))
	expect(is_equal_approx(by_frame[1], 30.0), "modo por quadro reproduz o comportamento das versões anteriores")
	doc.animation.clips[0].durations_ms = {}
	var eased := _rotations(interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true}, {"curve": "ease_in_out"}))
	expect(eased[1] < 30.0 and eased[2] > 60.0 and is_equal_approx(eased[1] + eased[2], 90.0), "ease in-out concentra os quadros perto das chaves")
	doc.rig.anchors = {"0:0": {"elbow_l": [2, 4]}, "0:3": {"elbow_l": [doc.width - 1, 10]}}
	var overshoot: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"anchor": true}, {"curve": "overshoot"})
	var inside: bool = overshoot.ok
	for change in overshoot.changes:
		if float(change.value[0]) > doc.width - 1 or float(change.value[0]) < 0.0: inside = false
	expect(inside, "overshoot nunca leva articulações para fora da tela")
	var invalid: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true}, {"curve": "elastic"})
	expect(not invalid.ok, "recusa curva desconhecida antes de propor valores")

func _persistence_checks() -> void:
	var interpolator = Interpolator.new()
	var setup := _arm_doc()
	var doc = setup[0]
	var layer_id: String = setup[1]
	var plain: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true})
	expect(interpolator.apply(doc, plain) and not doc.animation.clips[0].has("curves"), "aplicar sem escolher curva não acrescenta campos ao clip")
	expect(doc.undo(), "Undo desfaz a interpolação sem curva")
	var eased: Dictionary = interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true}, {"curve": "ease_out"})
	expect(interpolator.apply(doc, eased) and doc.animation.clips[0].get("curves", {}) == {"0": "ease_out"}, "curva escolhida fica salva no trecho que começa na chave")
	expect(doc.undo() and not doc.animation.clips[0].has("curves") and not doc.rig.rotations.has("0:1"), "um único Undo remove poses e curva")
	expect(doc.redo() and doc.animation.clips[0].curves == {"0": "ease_out"}, "Redo restaura poses e curva")
	doc.rig.rotations.erase("0:1")
	doc.rig.rotations.erase("0:2")
	doc.mark_changed()
	var reused := _rotations(interpolator.build(doc, 0, 0, layer_id, "elbow_l", {"rotation": true}))
	expect(is_equal_approx(reused[1], 90.0 * MotionCurves.evaluate("ease_out", 1.0 / 3.0)), "nova interpolação reutiliza a curva salva no clip")
	var storage = Storage.new()
	var path := "user://motion-curves-roundtrip.sfs.json"
	expect(storage.save_document(doc, path) == OK, "projeto com curva salva normalmente")
	var loaded = storage.load_document(path)
	expect(loaded != null and loaded.animation.clips[0].get("curves", {}) == {"0": "ease_out"}, "curva sobrevive ao salvar e reabrir")
	var data: Dictionary = storage.encode(doc)
	data.animation.clips[0].curves = {"0": "elastic"}
	expect(not Contracts.valid_extensions(data), "contrato recusa curva desconhecida no arquivo")
	data.animation.clips[0].curves = {"99": "linear"}
	expect(not Contracts.valid_extensions(data), "contrato recusa curva ligada a quadro inexistente")
	data.animation.clips[0].erase("curves")
	expect(Contracts.valid_extensions(data), "projetos sem o campo de curvas continuam válidos")
	doc.animation.clips[0].curves = {"0": "ease_out", "2": "hold"}
	doc.frame = 0
	expect(doc.insert_frame_after(0) >= 0 and doc.animation.clips[0].curves == {"0": "ease_out", "3": "hold"}, "inserir quadro renumera as curvas junto com as durações")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
