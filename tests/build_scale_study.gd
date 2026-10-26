extends SceneTree

const Storage = preload("res://core/storage.gd")
const Resizer = preload("res://core/canvas_resizer.gd")
const AnimationSynthesizer = preload("res://core/animation_synthesizer.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var storage = Storage.new()
	var doc = storage.load_document("res://samples/sentinela_v6.sfs.json")
	if doc == null:
		printerr("SCALE_STUDY: source project failed to load")
		quit(1)
		return
	var scaled: Dictionary = Resizer.resize_document(doc, 64, 64, Image.INTERPOLATE_LANCZOS, "bottom_center")
	if not scaled.get("ok", false):
		printerr("SCALE_STUDY: ", scaled.get("error", "resize failed"))
		quit(1)
		return
	var breathing: Dictionary = AnimationSynthesizer.generate_breathing(doc, 0, "idle_breathing", 2.0)
	if not breathing.get("ok", false):
		printerr("SCALE_STUDY: breathing generation failed: ", breathing.get("error", ""))
		quit(1)
		return
	var path := "res://samples/sentinela_scale_study.sfs.json"
	var save_error: Error = storage.save_document(doc, path)
	if save_error != OK:
		printerr("SCALE_STUDY: save failed: ", save_error)
		quit(1)
		return
	var export_path := ProjectSettings.globalize_path("res://examples/animation_candidate_v7_scale")
	var export_error: Error = storage.export_all(doc, export_path)
	if export_error != OK:
		printerr("SCALE_STUDY: export failed: ", export_error)
		quit(1)
		return
	print("SCALE_STUDY: OK — %d×%d, 144 cels, breathing regenerated, approvals cleared" % [doc.width, doc.height])
	quit(0)
