extends SceneTree

const Storage = preload("res://core/storage.gd")
const Resizer = preload("res://core/canvas_resizer.gd")
const Synthesizer = preload("res://core/animation_synthesizer.gd")
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const CLIPS := ["idle_breathing", "jump", "attack"]
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, title: String) -> void:
	checks.append({"name": title, "passed": value})
	if value: print("PASS ", title)
	else:
		failed += 1
		printerr("FAIL ", title)

func visible_hash(image: Image) -> String:
	var bytes: PackedByteArray = image.get_data()
	for index in range(0, bytes.size(), 4):
		if bytes[index + 3] == 0:
			bytes[index] = 0
			bytes[index + 1] = 0
			bytes[index + 2] = 0
	return bytes.hex_encode()

func visible_equal(a: Color, b: Color) -> bool:
	return (a.a == 0.0 and b.a == 0.0) or a == b

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var storage = Storage.new()
	var source = storage.load_document("res://samples/sentinela_v6.sfs.json")
	var doc = storage.load_document("res://samples/sentinela_scale_study.sfs.json")
	expect(doc != null and doc.width == 64 and doc.height == 64 and doc.frames == 18 and doc.layers.size() == 1 and doc.validate().is_empty(), "estudo de escala é um projeto SFS válido em canvas 64×64")
	if doc == null:
		finish()
		return
	expect(doc.art.candidate_status == "candidate" and doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty(), "variante exige revisão nova e não herda aprovações de pixels diferentes")
	expect(doc.art.direction_coverage == DIRECTIONS and doc.animation.clips.size() == 3, "variante conserva as oito direções e os três clips requeridos")
	var all_cels_valid := true
	var all_tracks_distinct := true
	var heights: Array[int] = []
	for direction in 8:
		for clip_index in CLIPS.size():
			var clip: Dictionary = doc.animation.clips[clip_index]
			var hashes: Dictionary = {}
			for frame_index in clip.frames:
				var cel: Image = doc.layers[0].cels[direction][int(frame_index)]
				var bounds := cel.get_used_rect()
				all_cels_valid = all_cels_valid and cel.get_size() == Vector2i(64, 64) and bounds.size != Vector2i.ZERO and bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= 64 and bounds.end.y <= 64
				if bounds.size != Vector2i.ZERO: heights.append(bounds.size.y)
				hashes[cel.get_data().hex_encode()] = true
			all_tracks_distinct = all_tracks_distinct and hashes.size() == 6
	expect(all_cels_valid and heights.size() == 144, "144 cels visíveis permanecem dentro dos canvas 64×64")
	heights.sort()
	var median_height: int = heights[heights.size() / 2]
	expect(median_height >= 24 and median_height <= 44, "altura mediana da silhueta é %d px, dentro da referência 24–44 px" % median_height)
	expect(all_tracks_distinct, "24 combinações de ação/direção mantêm seis poses distintas")
	var breathing_is_visible := true
	var breathing_is_local := true
	for direction in 8:
		var clip: Dictionary = doc.animation.clips[0]
		var base: Image = doc.layers[0].cels[direction][int(clip.frames[0])]
		var bounds := base.get_used_rect()
		var upper := maxi(0, floori(bounds.position.y + bounds.size.y * 0.31) - 2)
		var lower := mini(64, ceili(bounds.position.y + bounds.size.y * 0.65) + 2)
		var hashes: Dictionary = {}
		for frame in clip.frames:
			var cel: Image = doc.layers[0].cels[direction][int(frame)]
			hashes[visible_hash(cel)] = true
			var differences := 0
			for y in 64:
				for x in 64:
					var before_color: Color = base.get_pixel(x, y)
					var after_color: Color = cel.get_pixel(x, y)
					if (before_color.a > 0.0 or after_color.a > 0.0) and before_color != after_color: differences += 1
					if y < upper or y >= lower: breathing_is_local = breathing_is_local and visible_equal(before_color, after_color)
			if int(frame) != int(clip.frames[0]): breathing_is_visible = breathing_is_visible and differences > 0 and differences < 550
		breathing_is_visible = breathing_is_visible and hashes.size() == 6
	expect(breathing_is_visible, "idle da demonstração tem seis poses visivelmente distintas e movimento sutil")
	expect(breathing_is_local, "idle mantém pés e silhueta inferior imóveis enquanto o tronco respira")
	var tracks: SpriteFrames = load("res://examples/animation_candidate_v7_scale/animations.tres")
	expect(tracks != null and tracks.get_animation_names().size() == 24, "exportação Godot contém 24 animações direcionais")
	if tracks != null:
		var tracks_valid := true
		for direction in DIRECTIONS:
			for clip_name in CLIPS:
				var name: String = clip_name + "_" + direction
				tracks_valid = tracks_valid and tracks.has_animation(name) and tracks.get_frame_count(name) == 6
		expect(tracks_valid, "exportação mantém seis frames por clip nas oito direções")
		var actor := AnimatedSprite2D.new()
		actor.sprite_frames = tracks.duplicate(true)
		actor.speed_scale = 20.0
		root.add_child(actor)
		actor.play("idle_breathing_S")
		await create_timer(0.1).timeout
		expect(actor.is_playing(), "idle respira em loop após a redução para escala de jogo")
		actor.play("jump_S")
		await create_timer(0.2).timeout
		expect(not actor.is_playing() and actor.frame == 5, "pulo percorre a ação e conclui na escala de jogo")
		actor.play("attack_S")
		await create_timer(0.2).timeout
		expect(not actor.is_playing() and actor.frame == 5, "ataque percorre a ação e conclui na escala de jogo")
		actor.queue_free()
		await process_frame
	var scene: PackedScene = load("res://examples/animation_candidate_v7_scale/character.tscn")
	expect(scene != null, "cena de personagem redimensionada é carregável")
	if source != null:
		var regenerated: RefCounted = source.detached_copy()
		var result: Dictionary = Resizer.resize_document(regenerated, 64, 64, Image.INTERPOLATE_LANCZOS, "bottom_center")
		var exact: bool = bool(result.get("ok", false))
		if exact:
			var breathing_result: Dictionary = Synthesizer.generate_breathing(regenerated, 0, "idle_breathing", 2.0)
			exact = bool(breathing_result.get("ok", false))
		if exact:
			for direction in 8:
				for frame_index in 18:
					exact = exact and regenerated.layers[0].cels[direction][frame_index].get_data() == doc.layers[0].cels[direction][frame_index].get_data()
		expect(exact, "Sprite Forge reproduz as 144 cels 64×64 deterministicamente a partir da fonte")
	else: expect(false, "fonte v6 necessária para verificar proveniência de transformação")
	finish()

func finish() -> void:
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/animation-v7-scale-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Animation v7 scale study: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
