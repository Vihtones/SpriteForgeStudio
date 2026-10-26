extends SceneTree

const Storage = preload("res://core/storage.gd")
const Synthesizer = preload("res://core/animation_synthesizer.gd")
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

func changed_pixels(a: Image, b: Image) -> int:
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var first: Color = a.get_pixel(x, y)
			var second: Color = b.get_pixel(x, y)
			if (first.a > 0.0 or second.a > 0.0) and first != second: changed += 1
	return changed

func visible_equal(a: Color, b: Color) -> bool:
	return (a.a == 0.0 and b.a == 0.0) or a == b

func visible_hash(image: Image) -> String:
	var bytes: PackedByteArray = image.get_data()
	for index in range(0, bytes.size(), 4):
		if bytes[index + 3] == 0:
			bytes[index] = 0
			bytes[index + 1] = 0
			bytes[index + 2] = 0
	return bytes.hex_encode()

func run() -> void:
	var doc = Storage.new().load_document("res://samples/sentinela_scale_study.sfs.json")
	expect(doc != null and doc.width == 64, "fonte 64×64 do estudo está disponível")
	if doc == null: finish(); return
	doc.art.pose_approvals = [
		{"clip": "idle_breathing", "direction": "N", "frame": 0, "human": true},
		{"clip": "attack", "direction": "N", "frame": 0, "human": true},
	]
	doc.manifest.approvals = [{"human": true}]
	doc.animation.events["0:0"] = ["old idle event"]
	doc.animation.hitboxes["0:0"] = [1, 1, 2, 2]
	doc.animation.hitboxes["0:12"] = [1, 1, 2, 2]
	var before: RefCounted = doc.detached_copy()
	var result: Dictionary = Synthesizer.generate_breathing(doc, 0, "idle_breathing", 2.0)
	expect(result.get("ok", false), "gerador cria ciclo procedural em oito direções")
	if not result.get("ok", false): finish(); return
	var distinct_all := true
	var localized := true
	var feet_stable := true
	for direction in 8:
		var unique: Dictionary = {}
		var first_frame := int(before.animation.clips[0].frames[0])
		var base: Image = before.layers[0].cels[direction][first_frame]
		var bounds := base.get_used_rect()
		var torso_top := maxi(0, floori(bounds.position.y + bounds.size.y * 0.31) - 2)
		var torso_end := mini(64, ceili(bounds.position.y + bounds.size.y * 0.65) + 2)
		for frame_index in before.animation.clips[0].frames.size():
			var frame: Image = doc.layers[0].cels[direction][frame_index]
			unique[visible_hash(frame)] = true
			var delta := changed_pixels(base, frame)
			localized = localized and delta > 0 and delta < 550
			for y in 64:
				if y < torso_top or y >= torso_end:
					for x in 64: localized = localized and visible_equal(frame.get_pixel(x, y), base.get_pixel(x, y))
			for y in range(torso_end, 64):
				for x in 64:
					feet_stable = feet_stable and visible_equal(frame.get_pixel(x, y), base.get_pixel(x, y))
		distinct_all = distinct_all and unique.size() == 6
	expect(distinct_all, "respiração produz seis quadros distintos em cada direção")
	expect(localized, "variação permanece sutil e concentrada no tronco, sem cintilação do quadro inteiro")
	expect(feet_stable, "pés e região inferior ficam imóveis durante o ciclo respiratório")
	var non_idle_unchanged := true
	for direction in 8:
		for frame_index in 18:
			if frame_index >= 6: non_idle_unchanged = non_idle_unchanged and doc.layers[0].cels[direction][frame_index].get_data() == before.layers[0].cels[direction][frame_index].get_data()
	expect(non_idle_unchanged, "pulo e ataque permanecem pixel-identicos")
	expect(doc.art.pose_approvals.size() == 1 and doc.art.pose_approvals[0].clip == "attack" and doc.manifest.approvals.is_empty(), "aprovação de idle é invalidada sem apagar aprovação de ataque não alterado")
	expect(not doc.animation.hitboxes.has("0:0") and not doc.animation.events.has("0:0") and doc.animation.hitboxes.has("0:12"), "metadados espaciais/eventos do clip editado são limpos sem tocar em outros clips")
	expect(doc.undo() and doc.layers[0].cels[4][0].get_data() == before.layers[0].cels[4][0].get_data(), "Undo restaura pixels da pose-base")
	expect(doc.redo() and doc.layers[0].cels[4][0].get_data() != before.layers[0].cels[4][0].get_data(), "Redo restaura a respiração gerada")
	var deterministic: RefCounted = before.detached_copy()
	var repeat: Dictionary = Synthesizer.generate_breathing(deterministic, 0, "idle_breathing", 2.0)
	var exact: bool = bool(repeat.get("ok", false))
	if exact:
		for direction in 8:
			for frame_index in 6: exact = exact and deterministic.layers[0].cels[direction][frame_index].get_data() == doc.layers[0].cels[direction][frame_index].get_data()
	expect(exact, "geração de respiração é determinística para revisão reproduzível")
	var locked: RefCounted = before.detached_copy()
	locked.art.locked = true
	var refused: Dictionary = Synthesizer.generate_breathing(locked, 0, "idle_breathing")
	expect(not refused.get("ok", false) and locked.layers[0].cels[4][0].get_data() == before.layers[0].cels[4][0].get_data(), "Art Lock bloqueia o gerador sem tocar nos pixels")
	finish()

func finish() -> void:
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/animation-synthesizer-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Animation synthesizer: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
