extends SceneTree
## GPU/renderer regression: switch the real runtime animation through every frame.
const Storage = preload("res://core/storage.gd")
const PROJECT_PATH := "res://samples/sentinela_candidate_v10.sfs.json"
const EXPORT_PATH := "res://examples/animation_candidate_v10/animations.tres"
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, message: String) -> void:
	if condition: passed += 1; print("PASS ", message)
	else: failed += 1; printerr("FAIL ", message)

func run() -> void:
	var storage = Storage.new()
	var doc = storage.load_document(PROJECT_PATH)
	var frames: SpriteFrames = load(EXPORT_PATH)
	verify(doc != null and frames != null and doc.validate().is_empty(), "document and Godot runtime assets load")
	if doc == null or frames == null: finish(); return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(doc.width, doc.height)
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := AnimatedSprite2D.new()
	sprite.centered = false
	sprite.position = Vector2.ZERO
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = frames
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var no_residual := true
	var silhouettes_match := true
	var exercised := 0
	for clip in doc.animation.clips:
		for direction in 8:
			var animation_name: String = str(clip.name) + "_" + doc.DIRECTIONS[direction]
			sprite.play(animation_name)
			for frame_offset in frames.get_frame_count(animation_name):
				sprite.frame = frame_offset
				await process_frame
				await RenderingServer.frame_post_draw
				var actual: Image = viewport.get_texture().get_image()
				var expected: Image = doc.composite(direction, int(clip.frames[frame_offset]))
				if actual.get_size() != expected.get_size(): silhouettes_match = false; no_residual = false; continue
				var frame_match := _same_rgba(actual, expected)
				silhouettes_match = silhouettes_match and frame_match
				if _has_pixels_outside_expected(actual, expected):
					no_residual = false
				if not frame_match and exercised < 12:
					actual.save_png("res://test_results/bleeding-runtime-visual-%03d-actual.png" % exercised)
					expected.save_png("res://test_results/bleeding-runtime-visual-%03d-expected.png" % exercised)
				exercised += 1
	verify(exercised == 192 and silhouettes_match, "renderer reproduces every RGBA pixel of all 192 runtime cels")
	verify(no_residual, "switching actions/directions leaves no pixels from the prior frame")
	viewport.queue_free()
	finish()

func _has_pixels_outside_expected(actual: Image, expected: Image) -> bool:
	for y in expected.get_height():
		for x in expected.get_width():
			if expected.get_pixel(x, y).a <= 0.0 and actual.get_pixel(x, y).a > 0.0:
				return true
	return false

func _same_rgba(actual: Image, expected: Image) -> bool:
	for y in expected.get_height():
		for x in expected.get_width():
			var rendered := actual.get_pixel(x, y)
			var source := expected.get_pixel(x, y)
			# OpenGL readback is premultiplied-alpha; compare like-for-like instead
			# of silently checking only the silhouette as the old test did.
			var expected_premultiplied := Color(source.r * source.a, source.g * source.a, source.b * source.a, source.a)
			if absf(rendered.a - expected_premultiplied.a) > (1.0 / 255.0): return false
			if absf(rendered.r - expected_premultiplied.r) > (1.5 / 255.0): return false
			if absf(rendered.g - expected_premultiplied.g) > (1.5 / 255.0): return false
			if absf(rendered.b - expected_premultiplied.b) > (1.5 / 255.0): return false
	return true

func finish() -> void:
	var report := FileAccess.open("res://test_results/bleeding-runtime-visual-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Runtime visual bleeding: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
