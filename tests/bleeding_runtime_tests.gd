extends SceneTree
## Exercises Godot's real AnimatedSprite2D draw path, not just exported resources.
const Storage = preload("res://core/storage.gd")
const PROJECT_PATH := "res://samples/sentinela_candidate_v10.sfs.json"
const EXPORT_PATH := "res://examples/animation_candidate_v10/animations.tres"
const CLIP_NAMES := ["idle_breathing", "jump", "attack"]
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if condition: passed += 1; print("PASS ", message)
	else: failed += 1; printerr("FAIL ", message)

func run() -> void:
	var storage = Storage.new()
	var doc = storage.load_document(PROJECT_PATH)
	var frames: SpriteFrames = load(EXPORT_PATH)
	expect(doc != null and frames != null and doc.validate().is_empty(), "document and runtime animations load")
	if doc == null or frames == null: finish(); return
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = frames
	root.add_child(sprite)
	var exact := true
	var no_residual := true
	var exercised := 0
	var mismatches := 0
	for clip in doc.animation.clips:
		for direction in 8:
			var animation_name: String = str(clip.name) + "_" + doc.DIRECTIONS[direction]
			if frames.get_frame_count(animation_name) != clip.frames.size():
				printerr("Runtime frame count: %s has %d; source declares %d" % [animation_name, frames.get_frame_count(animation_name), clip.frames.size()])
				exact = false
			sprite.play(animation_name)
			for frame_offset in frames.get_frame_count(animation_name):
				sprite.frame = frame_offset
				var texture: Texture2D = frames.get_frame_texture(sprite.animation, sprite.frame)
				var actual: Image = texture.get_image() if texture != null else Image.new()
				var expected: Image = doc.composite(direction, int(clip.frames[frame_offset]))
				var match_pixels := not actual.is_empty() and actual.get_size() == expected.get_size() and actual.get_data() == expected.get_data()
				exact = exact and match_pixels
				if not match_pixels:
					mismatches += 1
					var residual := _has_pixels_outside_expected(actual, expected)
					no_residual = no_residual and not residual
					if mismatches <= 8: printerr("Runtime mismatch: %s frame %d, residual=%s, actual=%s format=%d expected=%s format=%d" % [animation_name, frame_offset, residual, str(actual.get_size()), actual.get_format(), str(expected.get_size()), expected.get_format()])
				exercised += 1
	expect(exercised == 192 and exact, "all 192 runtime draws match their own cel pixel-for-pixel")
	expect(no_residual, "no previous animation/frame leaves visible pixels in the next draw")
	sprite.queue_free()
	finish()

func _has_pixels_outside_expected(actual: Image, expected: Image) -> bool:
	for y in expected.get_height():
		for x in expected.get_width():
			if expected.get_pixel(x, y).a <= 0.0 and actual.get_pixel(x, y).a > 0.0:
				return true
	return false

func finish() -> void:
	var report := FileAccess.open("res://test_results/bleeding-runtime-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Runtime bleeding: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
