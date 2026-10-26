extends Node

const Storage = preload("res://core/storage.gd")
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

func run() -> void:
	var storage = Storage.new()
	var source = storage.load_document("res://samples/sentinela_v6.sfs.json")
	var scale_study = storage.load_document("res://samples/sentinela_scale_study.sfs.json")
	var artist_candidate = storage.load_document("res://samples/sentinela_artist_candidate_v8.sfs.json")
	var approved_collection = storage.load_document("res://samples/sentinela_artist_v9.sfs.json")
	var repaired = storage.load_document("res://samples/sentinela_candidate_v10.sfs.json")
	var valid: bool = _valid_sample(source, 208, true) and _valid_sample(scale_study, 64, false) and _valid_artist_candidate(artist_candidate) and _valid_approved_v9(approved_collection)
	valid = valid and repaired != null and repaired.validate().is_empty() and repaired.frames == 24 and repaired.art.candidate_status == "candidate" and repaired.manifest.approvals.is_empty() and repaired.art.get("bleed_fix", {}).get("component_count", 0) == 18
	if repaired != null:
		var coverage: Dictionary = repaired.art.get("bleed_fix", {}).get("coverage", {})
		valid = valid and str(repaired.art.get("bleed_fix", {}).get("status", "")) == "partial" and coverage.get("idle_breathing", []).is_empty() and coverage.get("jump", []) == ["S"] and coverage.get("attack", []) == ["S"]
	var library = preload("res://core/public_asset_library.gd").new()
	valid = valid and library.entries.size() == 27 and library.search("", true).size() == 21
	for entry in library.search("", true):
		valid = valid and library.image(str(entry.id)) != null
		if entry.get("spritesheet", {}).has("frame_size"):
			valid = valid and library.tile_document(str(entry.id), 0) == null
		else:
			var tile: RefCounted = library.tile_document(str(entry.id), 0)
			valid = valid and tile != null and tile.validate().is_empty()
	var review = preload("res://core/animation_review.gd").new()
	valid = valid and review.bind(repaired)
	if valid: print("SFS_SAMPLE_CHECK: OK — 5 projetos, 816 cels, 21 recursos offline, revisão de 3 ações × 8 direções")
	else: printerr("SFS_SAMPLE_CHECK: FAIL — uma das demonstrações embutidas é inválida")
	get_tree().quit(0 if valid else 1)

func _valid_artist_candidate(doc: RefCounted) -> bool:
	if not _valid_sample(doc, 64, false): return false
	if doc.art.get("review_scope", "") != "Generated art: South jump and attack; procedural idle across eight directions": return false
	for frame in 18:
		if doc.layers[0].cels[4][frame].get_used_rect().size == Vector2i.ZERO: return false
	return true

func _valid_approved_v9(doc: RefCounted) -> bool:
	if doc == null or doc.width != 64 or doc.height != 64 or doc.frames != 24 or doc.validate().size() > 0: return false
	if doc.art.candidate_status != "approved" or doc.manifest.approvals.size() != 1: return false
	for clip in doc.animation.clips:
		if clip.frames.size() != 8: return false
	return doc.layers.size() == 1 and doc.layers[0].cels.size() == 8

func _valid_sample(doc: RefCounted, canvas_size: int, source_sample: bool) -> bool:
	if doc == null: return false
	var valid: bool = doc.width == canvas_size and doc.height == canvas_size and doc.frames == 18 \
		and doc.layers.size() == 1 and doc.validate().is_empty() \
		and doc.art.direction_coverage == DIRECTIONS and doc.animation.clips.size() == 3
	var visible_cels := 0
	for direction in 8:
		for frame_index in 18:
			var cel: Image = doc.layers[0].cels[direction][frame_index]
			visible_cels += 1 if cel.get_size() == Vector2i(canvas_size, canvas_size) and cel.get_used_rect().size != Vector2i.ZERO else 0
	valid = valid and visible_cels == 144
	if source_sample:
		valid = valid and doc.art.candidate_status == "candidate" and doc.art.pose_approvals.size() == 7
	else:
		valid = valid and doc.art.candidate_status == "candidate" and doc.art.pose_approvals.is_empty() and doc.manifest.approvals.is_empty()
	return valid
