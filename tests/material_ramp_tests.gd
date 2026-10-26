extends SceneTree
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const Ramps = preload("res://core/material_ramps.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else: failed += 1; printerr("FAIL ", name)

func _initialize() -> void:
	var ramps = Ramps.new()
	var doc = Doc.new()
	doc.palette = ["#202030", "#808090", "#e8e8f0"]
	doc.art.pose_approvals = [{"id": "approved"}]
	var original_palette: Array = doc.palette.duplicate()
	var proposal: Dictionary = ramps.build(doc, "Metal", 0, 1, 2, 5)
	expect(proposal.get("ok", false) and proposal.colors.size() == 5, "gera cinco cores com os papéis sombra/base/luz")
	expect(proposal.colors[0] == "#202030" and proposal.colors[2] == "#808090" and proposal.colors[4] == "#e8e8f0", "rampa preserva exatamente os três marcos escolhidos")
	expect(doc.palette == original_palette and doc.art.get("material_ramps", []).is_empty(), "proposta não altera paleta nem metadados")
	expect(ramps.build(doc, "Metal", 0, 1, 2, 5).get("ok", false), "a mesma proposta ainda pode ser recalculada antes da confirmação")
	expect(not ramps.build(doc, "Metal", 0, 1, 2, 4).get("ok", false), "número par de passos é recusado para manter base central")
	expect(not ramps.build(doc, "Metal", 0, 0, 2, 5).get("ok", false), "marcos repetidos são recusados")
	expect(ramps.apply(doc, proposal), "confirmação registra rampa e acrescenta cores ausentes")
	expect(not ramps.build(doc, "metal", 0, 1, 2, 5).get("ok", false), "nome duplicado é recusado sem diferenciar maiúsculas")
	expect(doc.art.material_ramps.size() == 1 and doc.art.material_ramps[0].name == "Metal" and doc.art.material_ramps[0].colors == proposal.colors, "rampa nomeada fica organizada no projeto")
	expect(doc.palette.size() == original_palette.size() + proposal.additions.size(), "paleta cresce apenas com tons novos")
	expect(doc.art.pose_approvals.size() == 1, "adicionar cores sem tocar os pixels preserva aprovação artística existente")
	expect(doc.undo() and doc.palette == original_palette and doc.art.get("material_ramps", []).is_empty(), "Undo remove rampa e cores como uma operação")
	expect(doc.redo() and doc.art.material_ramps.size() == 1 and doc.palette.size() == original_palette.size() + proposal.additions.size(), "Redo restaura rampa nomeada e cores")
	var storage = Storage.new()
	var path := "res://test_results/material-ramp-%d.sfs.json" % Time.get_ticks_usec()
	expect(storage.save_document(doc, path) == OK, "projeto com rampas salva sem formato paralelo")
	var loaded = storage.load_document(path)
	if loaded == null: printerr("Material ramp load diagnostic: ", storage.error)
	var loaded_ramp: Dictionary = {} if loaded == null or loaded.art.get("material_ramps", []).is_empty() else loaded.art.material_ramps[0]
	var source_ramp: Dictionary = doc.art.material_ramps[0]
	expect(loaded != null and loaded.palette == doc.palette and loaded_ramp.get("name", "") == source_ramp.name and loaded_ramp.get("colors", []) == source_ramp.colors and int(loaded_ramp.get("steps", 0)) == source_ramp.steps, "save/load conserva definições e paleta da rampa")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var stale_doc = Doc.new()
	stale_doc.palette = original_palette.duplicate()
	var stale: Dictionary = ramps.build(stale_doc, "Couro", 0, 1, 2, 5)
	stale_doc.palette[0] = "#101010"
	expect(not ramps.apply(stale_doc, stale), "mudança na paleta após prévia invalida proposta antiga")
	var lock_doc = Doc.new()
	lock_doc.art.locked = true
	expect(not ramps.build(lock_doc, "Metal", 0, 1, 2, 5).get("ok", false), "Art Lock impede criar rampa")
	var capped = Doc.new()
	capped.palette = original_palette.duplicate()
	while capped.palette.size() < Ramps.MAX_PALETTE_COLORS: capped.palette.append(original_palette.back())
	expect(not ramps.build(capped, "Limite", 0, 1, 2, 5).get("ok", false), "limite coerente com a paleta visual de 32 cores é verificado antes da aplicação")
	var strip: Image = Ramps.preview_strip(["#000000", "#ffffff"], 8, 4)
	expect(strip.get_size() == Vector2i(16, 4) and strip.get_pixel(0, 0) == Color.BLACK and strip.get_pixel(9, 0) == Color.WHITE, "prévia em faixa mostra cores ampliadas sem interpolação de textura")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/material-ramp-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Material ramps: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
