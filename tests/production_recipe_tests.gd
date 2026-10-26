extends SceneTree

const Document = preload("res://core/document.gd")
const Recipe = preload("res://core/production_recipe.gd")
const Storage = preload("res://core/storage.gd")

func make_test_glb() -> PackedByteArray:
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "RecipeTestMesh"
	mesh.mesh = BoxMesh.new()
	source.add_child(mesh)
	mesh.owner = source
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(source, state)
	var bytes: PackedByteArray = document.generate_buffer(state) if error == OK else PackedByteArray()
	source.free()
	return bytes

var checks: Array[Dictionary] = []
var failed := 0

func expect(condition: bool, title: String) -> void:
	checks.append({"name": title, "passed": condition})
	if condition: print("PASS ", title)
	else:
		failed += 1
		printerr("FAIL ", title)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var recipe_service := Recipe.new()
	var source := Document.new()
	source.animation.clips.append({"name": "attack", "frames": [1, 2], "durations_ms": {"1": 95.0, "2": 120.0}, "loop": false})
	source.animation.events["0:1"] = ["strike"]
	source.palette = ["#151823", "#cc7744", "#ede0bd"]
	source.fps = 12
	source.art.bible = "Silhueta compacta; luz superior esquerda; revisão humana obrigatória."
	source.art.three_d_motion_rig = {"version": 2, "pose_base": {"left_arm": -0.2}, "pose_keys": {"1:2": {"right_elbow": 0.7}}, "proportions": {"torso_height": 1.1, "shoulder_width": 0.9, "arm_length": 1.05, "leg_length": 1.0}, "equipment_attachments": {"shield": [0.1, -0.2, 0.0], "sword": [0.0, -0.4, 0.1]}, "capture_pass_assignments": {"Body": "body"}}
	var glb_bytes := make_test_glb()
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(glb_bytes)
	source.art.three_d_motion_rig.model_asset = {"filename": "fixture.glb", "sha256": hash_context.finish().hex_encode(), "glb_base64": Marshalls.raw_to_base64(glb_bytes)}
	var created: Dictionary = recipe_service.create(source)
	expect(created.ok, "receita captura paleta, direção de arte, clips e configuração do rig")
	var recipe_path := "res://test_results/production-recipe-roundtrip.sfsrecipe.json"
	var absolute_path := ProjectSettings.globalize_path(recipe_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var storage := Storage.new()
	expect(created.ok and storage.atomic_json(absolute_path, created.recipe) == OK, "receita é serializada em arquivo local com gravação atômica")
	var reloaded: Variant = Storage.read_json(absolute_path)
	var target := Document.new()
	var applied: Dictionary = recipe_service.apply(reloaded, target)
	expect(applied.ok and target.palette == source.palette and target.fps == source.fps and target.art.bible == source.art.bible, "aplicação restaura paleta, FPS e direção de arte")
	var restored_rig: Dictionary = target.art.get("three_d_motion_rig", {})
	var pose_data_matches: bool = restored_rig.get("pose_base", {}).get("left_arm", 0.0) == -0.2 and restored_rig.get("pose_keys", {}).get("1:2", {}).get("right_elbow", 0.0) == 0.7
	var rig_settings_match: bool = restored_rig.get("proportions", {}).get("torso_height", 0.0) == 1.1 and restored_rig.get("capture_pass_assignments", {}).get("Body", "") == "body"
	expect(target.animation.clips.size() == 2 and target.animation.clips[1].name == "attack", "receita restaura a lista e os nomes dos clips")
	expect(target.animation.clips.size() == 2 and target.animation.clips[1].frames.size() == 2 and int(target.animation.clips[1].frames[0]) == 1 and int(target.animation.clips[1].frames[1]) == 2, "receita restaura os quadros dos clips")
	expect(target.animation.clips.size() == 2 and not target.animation.clips[1].loop, "receita restaura o modo de repetição dos clips")
	expect(target.animation.clips.size() == 2 and is_equal_approx(float(target.animation.clips[1].durations_ms.get("1", 0.0)), 95.0) and is_equal_approx(float(target.animation.clips[1].durations_ms.get("2", 0.0)), 120.0), "receita restaura durações personalizadas")
	expect(target.animation.events.get("0:1", []) == ["strike"], "receita restaura eventos sincronizados")
	expect(pose_data_matches, "receita restaura pose-base e poses-chave")
	expect(rig_settings_match, "receita restaura proporções e passes de captura")
	expect(str(restored_rig.get("model_asset", {}).get("sha256", "")) == str(source.art.three_d_motion_rig.model_asset.sha256) and Marshalls.base64_to_raw(str(restored_rig.model_asset.glb_base64)) == glb_bytes, "receita incorpora GLB, confere hash e conserva os bytes do modelo")
	var undo_applied := target.undo()
	expect(undo_applied and target.animation.clips.size() == 1 and target.palette != source.palette and target.art.get("three_d_motion_rig", {}).is_empty(), "Undo reverte a aplicação completa em uma única operação")
	var invalid_dimensions: Dictionary = created.recipe.duplicate(true)
	invalid_dimensions.canvas.width += 1
	var before_revision := target.revision
	var rejected_dimensions: Dictionary = recipe_service.apply(invalid_dimensions, target)
	expect(not rejected_dimensions.ok and target.revision == before_revision and target.animation.clips.size() == 1, "canvas incompatível é recusado sem alterar o documento")
	var invalid_color: Dictionary = created.recipe.duplicate(true)
	invalid_color.palette[0] = "not-a-color"
	expect(not recipe_service.validate(invalid_color, target).ok, "paleta malformada é recusada antes de aplicar")
	var locked_target := Document.new()
	locked_target.art.locked = true
	var lock_revision := locked_target.revision
	var rejected_locked: Dictionary = recipe_service.apply(created.recipe, locked_target)
	expect(not rejected_locked.ok and locked_target.revision == lock_revision and locked_target.animation.clips.size() == 1, "Art Lock impede aplicação sem mutação")
	DirAccess.remove_absolute(absolute_path)
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var report_file := FileAccess.open("res://test_results/production-recipe-report.json", FileAccess.WRITE)
	if report_file != null: report_file.store_string(JSON.stringify(report, "\t")); report_file.close()
	print("Production recipe: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
