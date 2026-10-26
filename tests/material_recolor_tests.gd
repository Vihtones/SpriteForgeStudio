extends SceneTree
const Doc = preload("res://core/document.gd")
const Ramps = preload("res://core/material_ramps.gd")
const Recolor = preload("res://core/material_recolor.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else: failed += 1; printerr("FAIL ", name)

func _initialize() -> void:
	var ramp_service = Ramps.new()
	var recolor = Recolor.new()
	var doc = Doc.new()
	doc.palette = ["#202030", "#808090", "#e8e8f0"]
	var ramp_proposal: Dictionary = ramp_service.build(doc, "Metal", 0, 1, 2, 5)
	expect(ramp_service.apply(doc, ramp_proposal), "fixture recebe rampa de material persistente")
	var target_hex: String = doc.art.material_ramps[0].colors[1]
	var source_hex := "#202030"
	var cel: Image = doc.current()
	cel.set_pixel(2, 2, Color("202030"))
	cel.set_pixel(3, 2, Color("202030", 0.5))
	cel.set_pixel(2, 3, Color("202030"))
	cel.set_pixel(3, 3, Color("202030"))
	cel.set_pixel(10, 10, Color("202030"))
	cel.set_pixel(11, 10, Color("808090"))
	var key: String = doc.cel_key()
	doc.selection = Rect2i(2, 2, 2, 2)
	doc.rig.protected_pixels = {key: [3 * doc.width + 2, 3 * doc.width + 3]}
	doc.art.pose_approvals = [{"id": "pose"}]
	doc.manifest.approvals = [{"id": "pack"}]
	doc.art.candidate_status = "approved"
	var original: PackedByteArray = cel.get_data()
	var preview: Dictionary = recolor.build(doc, "Metal", source_hex, target_hex, "selection")
	if not preview.get("ok", false): printerr("Material recolor proposal rejected: ", preview.get("message", "sem motivo")); quit(1); return
	expect(preview.get("ok", false) and preview.changed_pixels == 2, "prévia no modo de cel limita substituição à seleção e exclui pixel protegido")
	expect(cel.get_data() == original and preview.after.get_pixel(2, 2).to_html(false) == target_hex.trim_prefix("#") and absf(preview.after.get_pixel(3, 2).a - 0.5) <= 1.0 / 255.0, "prévia não altera a origem e mantém alfa parcial no tom de material")
	expect(preview.after.get_pixel(2, 3).to_html(false) == source_hex.trim_prefix("#") and preview.after.get_pixel(10, 10).to_html(false) == source_hex.trim_prefix("#") and preview.after.get_pixel(11, 10).to_html(false) == "808090", "proteção, pixels fora da seleção e cores diferentes ficam intactos")
	expect(recolor.apply(doc, preview) and doc.current().get_pixel(2, 2).to_html(false) == target_hex.trim_prefix("#"), "confirmação aplica tom escolhido em pixels elegíveis")
	expect(doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty() and doc.art.candidate_status == "candidate", "alterar pixels invalida aprovações anteriores")
	expect(doc.undo() and doc.current().get_data() == original and doc.art.pose_approvals.size() == 1 and doc.manifest.approvals.size() == 1, "Undo restaura pixels e aprovações juntas")
	expect(doc.redo() and doc.current().get_pixel(2, 2).to_html(false) == target_hex.trim_prefix("#"), "Redo reaplica recolorização localizada")
	var connected = Doc.new()
	connected.palette = ["#202030", "#808090", "#e8e8f0"]
	var connected_ramp: Dictionary = ramp_service.build(connected, "Metal", 0, 1, 2, 5)
	ramp_service.apply(connected, connected_ramp)
	var connected_target: String = connected.art.material_ramps[0].colors[3]
	connected.current().set_pixel(7, 7, Color("202030"))
	connected.current().set_pixel(8, 8, Color("202030"))
	connected.current().set_pixel(9, 9, Color("202030"))
	connected.current().set_pixel(11, 9, Color("202030"))
	var component: Dictionary = recolor.build(connected, "Metal", "#202030", connected_target, "connected", Vector2i(7, 7))
	expect(component.get("ok", false) and component.changed_pixels == 3, "modo componente segue conectividade diagonal de oito vizinhos sem capturar ilha distante")
	expect(recolor.apply(connected, component) and connected.current().get_pixel(9, 9).to_html(false) == connected_target.trim_prefix("#") and connected.current().get_pixel(11, 9).to_html(false) == "202030", "aceitar componente muda apenas a ilha conectada")
	expect(not recolor.build(connected, "Metal", "#202030", connected_target, "connected", Vector2i(7, 7)).get("ok", false), "semente de cor-fonte já recolorida ou inexistente é recusada")
	var blocked_seed = Doc.new()
	blocked_seed.palette = connected.palette.duplicate()
	var seed_ramp: Dictionary = ramp_service.build(blocked_seed, "Metal", 0, 1, 2, 5)
	ramp_service.apply(blocked_seed, seed_ramp)
	blocked_seed.current().set_pixel(4, 4, Color("202030"))
	blocked_seed.rig.protected_pixels = {blocked_seed.cel_key(): [4 * blocked_seed.width + 4]}
	expect(not recolor.build(blocked_seed, "Metal", "#202030", blocked_seed.art.material_ramps[0].colors[1], "connected", Vector2i(4, 4)).get("ok", false), "semente protegida é recusada")
	var lock_doc = Doc.new()
	lock_doc.palette = connected.palette.duplicate()
	var lock_ramp: Dictionary = ramp_service.build(lock_doc, "Metal", 0, 1, 2, 5)
	ramp_service.apply(lock_doc, lock_ramp)
	lock_doc.current().set_pixel(4, 4, Color("202030"))
	lock_doc.art.locked = true
	expect(not recolor.build(lock_doc, "Metal", "#202030", lock_doc.art.material_ramps[0].colors[1]).get("ok", false), "Art Lock bloqueia recolorização")
	lock_doc.art.locked = false
	lock_doc.layers[0].locked = true
	expect(not recolor.build(lock_doc, "Metal", "#202030", lock_doc.art.material_ramps[0].colors[1]).get("ok", false), "camada bloqueada bloqueia recolorização")
	lock_doc.layers[0].locked = false
	var stale_doc = Doc.new()
	stale_doc.palette = connected.palette.duplicate()
	var stale_ramp: Dictionary = ramp_service.build(stale_doc, "Metal", 0, 1, 2, 5)
	ramp_service.apply(stale_doc, stale_ramp)
	stale_doc.current().set_pixel(4, 4, Color("202030"))
	var stale: Dictionary = recolor.build(stale_doc, "Metal", "#202030", stale_doc.art.material_ramps[0].colors[1])
	stale_doc.selection = Rect2i(0, 0, 1, 1)
	expect(not recolor.apply(stale_doc, stale), "mudança de seleção após a prévia invalida a proposta")
	stale_doc.selection = Rect2i()
	stale = recolor.build(stale_doc, "Metal", "#202030", stale_doc.art.material_ramps[0].colors[1])
	stale_doc.rig.protected_pixels = {stale_doc.cel_key(): [0]}
	expect(not recolor.apply(stale_doc, stale), "mudança de máscara após a prévia invalida a proposta")
	stale_doc.rig.protected_pixels.clear()
	stale = recolor.build(stale_doc, "Metal", "#202030", stale_doc.art.material_ramps[0].colors[1])
	stale_doc.current().set_pixel(5, 5, Color("202030"))
	expect(not recolor.apply(stale_doc, stale), "mudança de pixels após a prévia impede aplicação obsoleta")
	var invalid_target: Dictionary = recolor.build(stale_doc, "Metal", "#202030", "#ffffff")
	expect(not invalid_target.get("ok", false), "cor que não pertence à rampa é recusada")
	expect(not recolor.build(stale_doc, "Ausente", "#202030", stale_doc.art.material_ramps[0].colors[1]).get("ok", false), "material não registrado é recusado")
	expect(not recolor.build(stale_doc, "Metal", "#ffffff", stale_doc.art.material_ramps[0].colors[1]).get("ok", false), "cor-fonte ausente na paleta é recusada")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/material-recolor-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Material recolor: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
