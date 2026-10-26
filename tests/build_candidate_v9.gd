extends SceneTree
const Storage = preload("res://core/storage.gd")
const HyperLearn = preload("res://core/hyperlearn.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var storage = Storage.new()
	var doc = storage.load_document("res://samples/sentinela_artist_candidate_v8.sfs.json")
	if doc == null: fail(storage.error); return
	for name in ["idle_breathing", "jump", "attack"]:
		var index := -1
		for i in doc.animation.clips.size():
			if doc.animation.clips[i].name == name: index = i; break
		if index < 0 or doc.animation.clips[index].frames.size() != 6: fail("unexpected clip structure: " + name); return
		if not doc.extend_clip_with_holds(name, 2): fail("cannot extend clip: " + name); return
	doc.animation.active = 0
	doc.frame = 0
	doc.art["review_scope"] = "User-approved collection; two additional end-pose timing frames per movement; no new pixels or inferred anatomy"
	doc.art.candidate_status = "approved"
	doc.manifest.name = "Sentinela v9 — coleção validada, oito quadros por movimento"
	doc.manifest.provenance += " A coleção visual base foi validada pelo usuário nesta conversa; a v9 acrescenta dois holds temporais a cada movimento sem inventar pixels."
	doc.manifest.approvals.append({"id": "conversation-approval-2026-10-25", "reviewer": "Usuário", "human": true, "at": "2026-10-25", "scope": "Coleção visual apresentada e validada pelo usuário; os holds temporais não alteram pixels.", "evidence": "Aprovação explícita nesta conversa; nenhuma nota numérica foi inventada."})
	var errors: Array = doc.validate()
	if not errors.is_empty(): fail(str(errors)); return
	var sample := "res://samples/sentinela_artist_v9.sfs.json"
	if storage.save_document(doc, sample) != OK: fail("cannot save v9 sample"); return
	var folder := ProjectSettings.globalize_path("res://examples/animation_candidate_v9")
	if storage.export_all(doc, folder) != OK: fail("cannot export v9 assets"); return
	var memory = HyperLearn.new()
	var feedback: Dictionary = memory.record_review(doc, true, "Usuário (aprovação explícita na conversa)", "Coleção visual validada pelo usuário; preferência positiva inicial para HyperLearn.", true)
	if not feedback.get("ok", false): fail("cannot record approved feedback: " + str(feedback.get("error", "unknown error"))); return
	print("CANDIDATE_V9: OK — 24 frames; 8 frames per clip × 8 directions; original pixels retained")
	quit(0)

func fail(message: String) -> void:
	printerr("CANDIDATE_V9: FAIL — ", message)
	quit(1)
