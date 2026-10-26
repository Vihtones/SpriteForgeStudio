extends SceneTree
const Isolator = preload("res://core/silhouette_atlas.gd")
const Importer = preload("res://core/spritesheet_importer.gd")
const Document = preload("res://core/document.gd")
const ReviewPanel = preload("res://ui/animation_review_panel.gd")
const Storage = preload("res://core/storage.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if condition: passed += 1; print("PASS ", message)
	else: failed += 1; printerr("FAIL ", message)

func only_color(image: Image, color: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0 and pixel != color: return false
	return image.get_used_rect().size != Vector2i.ZERO

func run() -> void:
	var source := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	source.fill_rect(Rect2i(20, 4, 17, 8), Color.RED)
	source.fill_rect(Rect2i(44, 8, 10, 18), Color.GREEN)
	source.fill_rect(Rect2i(8, 34, 10, 22), Color.BLUE)
	source.fill_rect(Rect2i(12, 28, 3, 8), Color.BLUE)
	source.fill_rect(Rect2i(45, 42, 10, 16), Color.YELLOW)
	var split: Dictionary = Isolator.extract(source, 2, 2, 4)
	expect(split.ok and split.parts.size() == 4 and split.crossings.size() == 2, "silhuetas atravessando coluna e linha são detectadas antes do recorte")
	if split.ok:
		expect(split.parts[0].area == 17 * 8 and split.parts[2].bounds.position.y <= 28, "braço/arma fora da célula permanecem na figura inteira")
		for row in 2:
			var rendered: Dictionary = Isolator.render_row(split, row, Vector2i(64, 64), 0.6, "bottom_center")
			expect(rendered.ok, "normalização usa escala comum sem cortar membros")
			if not rendered.ok: continue
			for col in 2:
				var frame: Image = rendered.image.get_region(Rect2i(col * 64, 0, 64, 64))
				expect(only_color(frame, [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW][row * 2 + col]), "nenhuma cor de animação vizinha entra no quadro %d:%d" % [row, col])
		var clipped: Dictionary = Isolator.render_row(split, 0, Vector2i(32, 32), 1.0, "top_left")
		expect(not clipped.ok and clipped.error.contains("cortado"), "escala que amputaria figura é recusada em vez de cortar")
	var ambiguous: Image = source.duplicate(); ambiguous.fill_rect(Rect2i(58, 0, 4, 4), Color.MAGENTA)
	expect(not Isolator.extract(ambiguous, 2, 2, 4).ok, "duas figuras na mesma célula pedem revisão em vez de escolha arbitrária")
	var touching: Image = source.duplicate(); touching.fill_rect(Rect2i(36, 11, 9, 1), Color.RED)
	expect(not Isolator.extract(touching, 2, 2, 4).ok, "silhuetas encostadas não são separadas por suposição anatômica")
	var directional_sheet := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	directional_sheet.fill(Color(0, 0, 0, 0))
	for direction in 8:
		var marker := Color(float(direction + 1) / 9.0, 0.3, 0.7, 1.0)
		# The first figure crosses the column boundary, while remaining separated
		# from the second figure. Every directional row repeats this edge case.
		directional_sheet.fill_rect(Rect2i(24, direction * 32 + 6, 12, 20), marker)
		directional_sheet.fill_rect(Rect2i(46, direction * 32 + 6, 10, 20), marker)
	var directional_extraction: Dictionary = Isolator.extract(directional_sheet, 2, 8, 4)
	var directional_doc = Document.new()
	var directional_import: Dictionary = Importer.import_isolated_directions(directional_doc, directional_extraction, {"start_frame": 1, "content_scale": 0.8, "alignment": "center"})
	var directions_exact: bool = bool(directional_import.get("ok", false)) and directional_extraction.crossings.size() == 8
	for direction in 8:
		var cel: Image = directional_doc.layers[0].cels[direction][1]
		var used: Rect2i = cel.get_used_rect()
		var color: Color = cel.get_pixelv(used.position) if used.size != Vector2i.ZERO else Color.TRANSPARENT
		directions_exact = directions_exact and used.size != Vector2i.ZERO and absf(color.r - float(direction + 1) / 9.0) <= 1.5 / 255.0 and absf(color.g - 0.3) <= 1.5 / 255.0 and absf(color.b - 0.7) <= 1.5 / 255.0
		for y in directional_doc.height:
			for x in directional_doc.width:
				var pixel: Color = cel.get_pixel(x, y)
				if pixel.a > 0.0 and pixel != color: directions_exact = false
		directions_exact = directions_exact and directional_doc.layers[0].cels[direction][0].get_used_rect().size == Vector2i.ZERO
	expect(directions_exact and directional_import.get("cells", 0) == 16, "importação isola figuras que cruzam células em cada um dos oito rumos sem misturar direções")
	expect(directional_doc.undo() and directional_doc.layers[0].cels[7][1].get_used_rect().size == Vector2i.ZERO, "reimportação isolada das oito direções reverte em um único Undo")
	var wrong_direction_count: Dictionary = Importer.import_isolated_directions(directional_doc, split, {"start_frame": 0})
	expect(not wrong_direction_count.ok and directional_doc.layers[0].cels[0][0].get_used_rect().size == Vector2i.ZERO, "o importador recusa fonte com menos de oito linhas antes de modificar o documento")
	var raw: Image = Image.load_from_file(ProjectSettings.globalize_path("res://examples/animation_candidate_v8/sentinela-sheet-candidate-v1.png"))
	var real: Dictionary = Isolator.extract(raw, 6, 3)
	expect(real.ok and real.parts.size() == 18 and real.crossings.size() == 3, "folha real reproduz a causa: três espadas atravessam a grade")
	var storage = Storage.new()
	var before = storage.load_document("res://samples/sentinela_artist_v9.sfs.json")
	var after = storage.load_document("res://samples/sentinela_candidate_v10.sfs.json")
	expect(after != null and after.validate().is_empty() and after.art.candidate_status == "candidate" and after.manifest.approvals.is_empty(), "correção salva variante editável sem herdar aprovação antiga")
	if after != null:
		var panel = ReviewPanel.new()
		root.add_child(panel)
		await process_frame
		panel.bind(after)
		expect(panel.bleed_coverage.text.contains("Mistura visual entre idle, pulo e ataque: não verificada") and panel.bleed_coverage.text.contains("pulo: S (1/8 vistas)") and panel.bleed_coverage.text.contains("ataque: S (1/8 vistas)") and panel.bleed_coverage.text.contains("idle: sem reparo"), "painel revela que a mistura entre ações continua não verificada e registra a cobertura parcial")
		panel.queue_free()
	if real.ok and before != null and after != null:
		var rebuilt = before.detached_copy(); rebuilt.direction = 4
		var rebuilt_ok := true
		for row in [1, 2]:
			var clip: Dictionary = rebuilt.animation.clips[row]
			rebuilt_ok = rebuilt_ok and Importer.import_isolated_row(rebuilt, real, {"source_row": row, "start_frame": int(clip.frames[0]), "content_scale": 0.72, "alignment": "bottom_center"}).ok
			for frame in 6: rebuilt_ok = rebuilt_ok and rebuilt.composite(4, int(clip.frames[frame])).get_data() == after.composite(4, int(clip.frames[frame])).get_data()
		expect(rebuilt_ok, "variante é reproduzível pelo importador do programa a partir das silhuetas")
		var preserved := true
		for direction in 8:
			for frame in 24:
				if direction == 4 and frame >= 8: continue
				preserved = preserved and before.composite(direction, frame).get_data() == after.composite(direction, frame).get_data()
		expect(preserved and before.animation == after.animation, "idle, sete direções e todos os timings permanecem idênticos")
		var folder := "res://test_results/bleed-isolation-export"
		expect(storage.export_all(after, ProjectSettings.globalize_path(folder)) == OK, "exportação isolada conclui PNG, recursos e cenas")
		var resources: SpriteFrames = load(folder.path_join("animations.tres"))
		var isolated := resources != null
		if resources != null:
			for action in resources.get_animation_names():
				var direction: int = after.DIRECTIONS.find(str(action).get_slice("_", str(action).get_slice_count("_") - 1))
				var clip_name := str(action).left(str(action).length() - str(action).get_slice("_", str(action).get_slice_count("_") - 1).length() - 1)
				var clip: Dictionary = after.animation.clips.filter(func(value): return value.name == clip_name)[0]
				for offset in resources.get_frame_count(action):
					var texture: Texture2D = resources.get_frame_texture(action, offset)
					isolated = isolated and texture is ImageTexture and texture.get_size() == Vector2(64, 64) and texture.get_image().get_data() == after.composite(direction, int(clip.frames[offset])).get_data()
		expect(isolated, "192 quadros exportados têm textura própria e RGBA exato, sem região de atlas vizinha")
	var report := FileAccess.open("res://test_results/bleeding-report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Bleeding: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
