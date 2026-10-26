extends SceneTree

const Document = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const ExportValidator = preload("res://core/export_validator.gd")
const Worker = preload("res://core/batch_worker.gd")
const World = preload("res://core/world_data.gd")
const MaterialRamps = preload("res://core/material_ramps.gd")
const SpriteEffects = preload("res://core/sprite_effects.gd")

var checks: Array[Dictionary] = []
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks.append({"name": label, "passed": value})
	if value: print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

func run() -> void:
	var consumer_root := ProjectSettings.globalize_path("res://tests/consumer_project")
	var report_path := consumer_root.path_join("report.json")
	var log_path := consumer_root.path_join("consumer-run.log")
	if FileAccess.file_exists(report_path): DirAccess.remove_absolute(report_path)
	var document = Document.new()
	document.demo()
	# A generated glow layer must survive every export profile and the independent Godot consumer.
	var ramp_service = MaterialRamps.new()
	var effect_ramp: Dictionary = ramp_service.build(document, "Fogo", 0, 1, 2, 5)
	var effect_applied := ramp_service.apply(document, effect_ramp)
	var effects = SpriteEffects.new()
	var glow: Dictionary = effects.build(document, {"type": "glow", "source_layer_id": document.layers[0].id, "ramp": "Fogo", "frames": range(document.frames)}) if effect_applied else {"ok": false}
	var effect_added := bool(glow.get("ok", false)) and effects.apply(document, glow, "Aura de validação")
	expect(effect_added and document.validate().is_empty(), "synthetic demo gains a generated glow layer that keeps the document valid")
	document.map_data.rooms[0].id = "consumer-exterior"
	var first_room_id: String = str(document.map_data.rooms[0].id)
	var has_interior := World.create_room(document.map_data, "Interior de validação")
	if has_interior: document.map_data.rooms[1].id = "consumer-interior"
	var second_room_id: String = str(document.map_data.rooms[1].id) if document.map_data.rooms.size() > 1 else ""
	if has_interior:
		World.paint(document.map_data, Vector2i(5, 5), "Colisão", 0, false)
		World.paint(document.map_data, Vector2i(4, 4), "Luz", 0, false, {"color": "#ffcf8b", "energy": 1.25, "radius": 3.0, "shadows": true})
	var has_portal := has_interior and World.add_connection(document.map_data, first_room_id, Vector2i(2, 2), second_room_id, Vector2i(3, 3), "Portal de teste")
	if has_interior: World.switch_room(document.map_data, 0)
	expect(has_interior and has_portal, "validation fixture contains a second room with a cross-room portal")
	expect(document.validate().is_empty(), "synthetic demo document is valid before export")
	var export_error: Error = Storage.new().export_all(document, consumer_root)
	expect(export_error == OK, "SFS export writes character, map, animation, tileset and runtime scripts into a clean Godot project")
	if export_error == OK:
		var validation: Dictionary = ExportValidator.validate_package(consumer_root)
		var validated_rooms: Array = validation.get("rooms", [])
		expect(bool(validation.get("ok", false)) and validated_rooms.size() == 2 and validated_rooms.all(func(room): return bool(room.get("ok", false))), "export validator checks animations and both connected world rooms with collision and shadowed light")
		var validation_output := FileAccess.open(consumer_root.path_join("export-validation.json"), FileAccess.WRITE)
		if validation_output != null:
			validation_output.store_string(JSON.stringify(validation, "\t"))
			validation_output.close()
		var profiles_root := consumer_root.path_join("profile-checks")
		for profile in ["sprite", "animated", "modular", "map"]:
			var profile_folder := profiles_root.path_join(profile)
			var profile_error: Error = Storage.new().export_all(document, profile_folder, profile)
			var profile_validation: Dictionary = ExportValidator.validate_profile(profile_folder, profile) if profile_error == OK else {"ok": false}
			if not bool(profile_validation.get("ok", false)): printerr("PROFILE DIAGNOSTIC ", profile, " export=", profile_error, " report=", profile_validation)
			expect(profile_error == OK and bool(profile_validation.get("ok", false)), "export profile %s writes a validated, profile-specific package" % profile)
			var manifest: Variant = Storage.read_json(profile_folder.path_join("export-profile.json"))
			expect(manifest is Dictionary and str(manifest.get("profile", "")) == profile, "export profile %s records its type in the package manifest" % profile)
			if profile == "sprite":
				expect(not FileAccess.file_exists(profile_folder.path_join("character.tscn")) and not FileAccess.file_exists(profile_folder.path_join("map.tscn")), "sprite-only profile omits runtime scenes")
			elif profile == "animated":
				expect(FileAccess.file_exists(profile_folder.path_join("animations.tres")) and FileAccess.file_exists(profile_folder.path_join("character.tscn")) and not FileAccess.file_exists(profile_folder.path_join("map.tscn")), "animated profile contains character playback without map payload")
			elif profile == "modular":
				var modular_scene := ResourceLoader.load(profile_folder.path_join("modular_character.tscn"), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
				var modular_root := modular_scene.instantiate() if modular_scene != null else null
				var modular_layers: Array = modular_root.find_children("*", "Sprite2D", true, false) if modular_root != null else []
				var modular_player := modular_root.get_node_or_null("AnimationPlayer") as AnimationPlayer if modular_root != null else null
				expect(modular_layers.size() == document.layers.size() and modular_player != null, "modular profile exports editable layers and an AnimationPlayer")
				if modular_root != null: modular_root.free()
			elif profile == "map":
				expect(FileAccess.file_exists(profile_folder.path_join("rooms.json")) and not FileAccess.file_exists(profile_folder.path_join("spritesheet.png")), "map-only profile includes rooms without character art")
		var worker_root := consumer_root.path_join("profile-worker")
		DirAccess.make_dir_recursive_absolute(worker_root)
		var worker_input := worker_root.path_join("input.sfs.json")
		var worker_output := worker_root.path_join("output")
		var worker_result_path := worker_root.path_join("result.json")
		var worker_progress_path := worker_root.path_join("progress.json")
		var worker_cancel_path := worker_root.path_join("cancel")
		expect(Storage.new().save_document(document, worker_input) == OK, "profile worker fixture saves independently")
		var worker_request := {"schema": 1, "kind": "export", "id": "profile-worker", "input": worker_input, "output": worker_output, "result": worker_result_path, "progress": worker_progress_path, "cancel": worker_cancel_path, "parameters": {"profile": "sprite"}}
		var worker_result: Dictionary = Worker.execute(worker_request)
		expect(worker_result.status == "done" and str(Storage.read_json(worker_output.path_join("export-profile.json")).get("profile", "")) == "sprite", "batch worker publishes the requested export profile")
		worker_result = Worker.execute(worker_request)
		expect(worker_result.status == "cached", "batch cache reuses output only for the same profile")
		worker_request.parameters.profile = "map"
		worker_result = Worker.execute(worker_request)
		expect(worker_result.status == "done" and str(Storage.read_json(worker_output.path_join("export-profile.json")).get("profile", "")) == "map", "changing export profile invalidates cache and rebuilds the requested package")
		var process_id := OS.create_process(OS.get_executable_path(), ["--headless", "--path", consumer_root, "--script", "res://validate.gd", "--log-file", log_path])
		expect(process_id > 0, "clean consumer Godot instance starts successfully")
		if process_id > 0:
			var deadline := Time.get_ticks_msec() + 30000
			while OS.is_process_running(process_id) and Time.get_ticks_msec() < deadline:
				await process_frame
			var timed_out := OS.is_process_running(process_id)
			if timed_out: OS.kill(process_id)
			expect(not timed_out, "clean consumer Godot instance finishes within 30 seconds")
			var report: Variant = Storage.read_json(report_path)
			expect(report is Dictionary and bool(report.get("ok", false)), "exported character, animation playback, map, navigation and tileset all run in consumer project")
			if report is Dictionary:
				for check in report.get("checks", []):
					checks.append({"name": "consumer: " + str(check.get("name", "")), "passed": bool(check.get("passed", false))})
					if not bool(check.get("passed", false)): failed += 1
	var output := FileAccess.open("res://test_results/export-consumer-report.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"passed": checks.size() - failed, "failed": failed, "checks": checks, "consumer_report": Storage.read_json(report_path)}, "\t"))
		output.close()
	print("Export consumer: %d passed, %d failed" % [checks.size() - failed, failed])
	quit(1 if failed > 0 else 0)
