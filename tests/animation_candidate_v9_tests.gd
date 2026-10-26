extends SceneTree
const Storage = preload("res://core/storage.gd")
const CLIP_NAMES := ["idle_breathing", "jump", "attack"]
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, title: String) -> void:
	if value: passed += 1; print("PASS ", title)
	else: failed += 1; printerr("FAIL ", title)

func run() -> void:
	var storage = Storage.new()
	var v8 = storage.load_document("res://samples/sentinela_artist_candidate_v8.sfs.json")
	var doc = storage.load_document("res://samples/sentinela_artist_v9.sfs.json")
	expect(v8 != null and doc != null and doc.width == 64 and doc.height == 64 and doc.frames == 24 and doc.validate().is_empty(), "Sentinela v9 carrega como projeto válido de 64×64 e 24 quadros globais")
	if v8 == null or doc == null: finish(); return
	expect(doc.art.candidate_status == "approved" and doc.manifest.approvals.size() == 1 and bool(doc.manifest.approvals[0].human), "aprovação explícita da coleção ficou registrada sem notas inventadas")
	var rebuilt = v8.detached_copy()
	var lengths_ok := true
	var holds_ok := true
	var original_pixels_ok := true
	var unique_poses_ok := true
	for clip_index in CLIP_NAMES.size():
		var clip: Dictionary = doc.animation.clips[clip_index]
		var source_clip: Dictionary = v8.animation.clips[clip_index]
		var source_timing := _duration_sum(v8, source_clip)
		lengths_ok = lengths_ok and clip.name == CLIP_NAMES[clip_index] and clip.frames.size() == 8
		lengths_ok = lengths_ok and rebuilt.extend_clip_with_holds(CLIP_NAMES[clip_index], 2)
		for d in 8:
			var target_layer: Dictionary = doc.layers[0]
			var unique: Dictionary = {}
			for f in 6: unique[v8.layers[0].cels[d][source_clip.frames[f]].get_data().hex_encode()] = true
			unique_poses_ok = unique_poses_ok and unique.size() == 6
			for offset in 2:
				var new_frame := int(clip.frames[-2 + offset])
				var previous_frame := int(clip.frames[-3 + offset])
				holds_ok = holds_ok and v8.layers[0].cels[d][source_clip.frames[-1]].get_data() == target_layer.cels[d][new_frame].get_data()
				holds_ok = holds_ok and target_layer.cels[d][new_frame].get_data() == target_layer.cels[d][previous_frame].get_data()
			for f in 6:
				original_pixels_ok = original_pixels_ok and rebuilt.layers[0].cels[d][clip.frames[f]].get_data() == v8.layers[0].cels[d][source_clip.frames[f]].get_data()
		lengths_ok = lengths_ok and is_equal_approx(source_timing, _duration_sum(doc, clip))
	expect(lengths_ok and rebuilt.frames == 24, "cada ação recebe exatamente mais dois quadros em todas as oito direções")
	expect(holds_ok, "quadros novos estendem o tempo final sem deformar pixels ou inventar poses anatômicas")
	expect(original_pixels_ok, "todas as imagens originais preservam pixels após remapeamento e inserção")
	expect(unique_poses_ok, "os desenhos de origem fornecem seis poses distintas por movimento e direção")
	var clips_valid := true
	for clip in doc.animation.clips: clips_valid = clips_valid and clip.frames.size() == 8 and clip.frames[0] >= 0 and clip.frames[-1] < doc.frames
	expect(clips_valid, "três clips possuem oito quadros com índices válidos")
	var resources: SpriteFrames = load("res://examples/animation_candidate_v9/animations.tres")
	expect(resources != null and resources.get_animation_names().size() == 24, "exportação produz 24 animações direcionais para o runtime Godot")
	if resources != null:
		for name in ["idle_breathing_S", "jump_S", "attack_S"]: expect(resources.get_frame_count(name) == 8, name + " tem oito quadros na animação Godot")
	var preview: PackedScene = load("res://examples/animation_candidate_v9/character.tscn")
	expect(preview != null and FileAccess.get_file_as_bytes("res://examples/animation_candidate_v9/S-candidate-v9.gif").size() > 50000, "cena Godot e GIF de revisão dos três movimentos estão disponíveis")
	finish()

func finish() -> void:
	var report := FileAccess.open("res://test_results/animation-v9-report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Animation candidate v9: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _duration_sum(document: RefCounted, clip: Dictionary) -> float:
	var total := 0.0
	for frame in clip.frames: total += float(clip.durations_ms.get(str(frame), 1000.0 / document.fps))
	return total
