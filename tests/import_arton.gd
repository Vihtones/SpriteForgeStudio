extends SceneTree
const Importer = preload("res://core/arton_importer.gd")
const Storage = preload("res://core/storage.gd")
var failed: bool = false
var checks: Array = []

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if not value: failed = true; printerr("FAIL ", name)
	else: print("PASS ", name)

func _initialize() -> void:
	var path := "res://examples/arton/biblioteca.json"
	var root := "res://examples/arton_projects"
	DirAccess.make_dir_recursive_absolute(root)
	var storage := Storage.new()
	for family in ["humanoide", "canideo", "felino"]:
		var importer := Importer.new()
		var doc = importer.import_family(path, family)
		expect(doc != null, "import " + family + " " + importer.error)
		if doc == null: continue
		expect(doc.width == 256 and doc.height == 256 and doc.frames == 1, family + " native 256 canvas; one static frame")
		var library: Dictionary = importer.read_library(path)
		for d in 8:
			var original: Image = importer.image(path, library.families[family].views[Importer.ORDER[d]].file)
			expect(doc.layers[0].cels[d][0].get_data() == original.get_data(), family + " exact RGBA orientation " + str(d))
		if family == "humanoide":
			expect(doc.layers.size() == 2 and doc.layers[1].equipment and not doc.layers[1].visible, "garment independent, candidate and initially hidden")
			var undressed: Image = doc.composite()
			doc.layers[1].visible = true
			for d in 8:
				doc.layers[1].visible = false
				var before: Image = doc.composite(d, 0)
				doc.layers[1].visible = true
				var dressed: Image = doc.composite(d, 0)
				var base: Dictionary = library.families[family].views[Importer.ORDER[d]]
				var target := Vector2i(roundi(float(base.torso_width)), roundi(float(base.anchors.hem[1]) - float(base.anchors.neck[1])))
				var offset := Vector2i(roundi(base.anchors.neck[0]) - roundi(target.x / 2.0), roundi(base.anchors.neck[1]))
				var allowed := Rect2i(offset, target)
				var outside_changes: int = 0
				var inside_changes: int = 0
				for y in doc.height:
					for x in doc.width:
						if before.get_pixel(x, y) != dressed.get_pixel(x, y):
							if allowed.has_point(Vector2i(x, y)): inside_changes += 1
							else: outside_changes += 1
				expect(outside_changes == 0 and inside_changes > 0, "garment stays inside declared fit, direction " + str(d))
			doc.layers[1].visible = false
			expect(doc.composite().get_data() == undressed.get_data(), "removing garment restores untouched base")
			doc.rig.pose = "different_pose"
			expect(not doc.compatible(doc.layers[1]), "garment rejects incompatible pose")
			doc.rig.pose = "repouso_estatico"
			doc.rig.family = "canid"
			expect(not doc.compatible(doc.layers[1]), "humanoid garment rejects animal family")
			doc.rig.family = "humanoid"
		else:
			expect(doc.layers.size() == 1, family + " never receives humanoid garment")
		var project_path := root.path_join(family + ".sfs.json")
		expect(storage.save_document(doc, project_path) == OK, "save portable " + family + " project")
		var loaded = storage.load_document(project_path)
		expect(loaded != null and loaded.composite().get_data() == doc.composite().get_data(), family + " roundtrip source resolution and RGBA")
		expect(doc.manifest.approvals.is_empty() and doc.manifest.source.approval == "imported_not_approved", family + " import never promotes artistic approval")
	var importer := Importer.new()
	expect(importer.image(path, "../../project.godot") == null, "path traversal outside library refused")
	expect(importer.import_family(path, "unknown") == null, "unknown family refused")
	storage.atomic_json("res://test_results/arton-report.json", {"ok": not failed, "checks": checks, "count": checks.size(), "note": "Technical import/fit validation; no artistic or animation approval."})
	quit(1 if failed else 0)
