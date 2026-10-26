extends RefCounted
## Technical gate for a directional character animation package. It never judges artistic quality.
const Doc = preload("res://core/document.gd")
const REQUIRED_CLIPS := {"idle_breathing": true, "jump": false, "attack": false}

func evaluate(doc: RefCounted) -> Dictionary:
	var checks: Array[Dictionary] = []
	if doc == null:
		return _report([{"name": "document", "passed": false, "detail": "Documento inexistente."}])
	var integrity_errors: Array = doc.validate()
	_record(checks, "integrity", integrity_errors.is_empty(), "; ".join(integrity_errors))
	if not integrity_errors.is_empty():
		return _report(checks)
	_record(checks, "directions", doc.layers.size() > 0 and doc.layers[0].cels.size() == Doc.DIRECTIONS.size(), "Oito buffers direcionais são necessários.")
	var clips_by_name: Dictionary = {}
	for clip in doc.animation.get("clips", []):
		if clip is Dictionary:
			clips_by_name[str(clip.get("name", ""))] = clip
	for clip_name in REQUIRED_CLIPS:
		if not clips_by_name.has(clip_name):
			_record(checks, "clip:" + clip_name, false, "Animação obrigatória ausente.")
			continue
		var clip: Dictionary = clips_by_name[clip_name]
		var frames: Array = clip.get("frames", [])
		_record(checks, "clip:" + clip_name + ":loop", bool(clip.get("loop", false)) == bool(REQUIRED_CLIPS[clip_name]), "Loop incompatível com o contrato do movimento.")
		var valid_frames := frames.size() >= 2
		var unique_frames: Dictionary = {}
		for frame in frames:
			if not frame is int or int(frame) < 0 or int(frame) >= doc.frames or unique_frames.has(str(frame)):
				valid_frames = false
			unique_frames[str(frame)] = true
		_record(checks, "clip:" + clip_name + ":frames", valid_frames, "Frames devem ser distintos, válidos e conter movimento.")
		var durations: Dictionary = clip.get("durations_ms", {})
		var timing_valid := true
		for frame in frames:
			if durations.has(str(frame)):
				var duration: Variant = durations[str(frame)]
				if not duration is int and not duration is float:
					timing_valid = false
				elif not is_finite(float(duration)) or float(duration) < 1.0 or float(duration) > 10000.0:
					timing_valid = false
		_record(checks, "clip:" + clip_name + ":timing", timing_valid, "Durações devem estar entre 1 e 10000 ms.")
		var directional_motion := valid_frames
		if valid_frames:
			for direction in Doc.DIRECTIONS.size():
				var initial: Image = doc.composite(direction, int(frames[0]))
				var changes_pixels := false
				for index in range(1, frames.size()):
					var current: Image = doc.composite(direction, int(frames[index]))
					changes_pixels = changes_pixels or current.get_data() != initial.get_data()
				directional_motion = directional_motion and changes_pixels
		_record(checks, "clip:" + clip_name + ":motion", directional_motion, "Cada uma das oito direções deve apresentar mudança visual.")
	_record_attack_contacts(doc, checks, clips_by_name.get("attack", {}))
	var report := _report(checks)
	report["art_candidate_status"] = str(doc.art.get("candidate_status", "unreviewed"))
	report["review_feedback"] = str(doc.art.get("review_feedback", ""))
	return report

func _record_attack_contacts(doc: RefCounted, checks: Array[Dictionary], attack_clip: Dictionary) -> void:
	var attack_frames: Array = attack_clip.get("frames", [])
	var events: Dictionary = doc.animation.get("events", {})
	var hitboxes: Dictionary = doc.animation.get("hitboxes", {})
	for direction in Doc.DIRECTIONS.size():
		var valid_contact := false
		for event_key in events:
			var parts := str(event_key).split(":")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or int(parts[0]) != direction or not attack_frames.has(int(parts[1])):
				continue
			var contact := false
			var values: Variant = events[event_key]
			if values is Array:
				for value in values:
					var normalized := str(value).to_lower()
					contact = contact or (normalized.contains("ataque") and (normalized.contains("contato") or normalized.contains("contact"))) or normalized.contains("attack_contact")
			if not contact:
				continue
			var raw_hitbox: Variant = hitboxes.get(str(event_key), [])
			if not raw_hitbox is Array or raw_hitbox.size() != 4:
				continue
			var hitbox: Array = raw_hitbox
			var numeric := true
			for value in hitbox:
				numeric = numeric and (value is int or value is float) and is_finite(float(value))
			if not numeric:
				continue
			var x := int(hitbox[0]); var y := int(hitbox[1]); var width := int(hitbox[2]); var height := int(hitbox[3])
			if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > doc.width or y + height > doc.height:
				continue
			var composite: Image = doc.composite(direction, int(parts[1]))
			for py in range(y, y + height):
				for px in range(x, x + width):
					if composite.get_pixel(px, py).a > 0.0:
						valid_contact = true
						break
				if valid_contact:
					break
			if valid_contact:
				break
		_record(checks, "attack_contact:" + str(direction), valid_contact, "O evento de contato precisa de hitbox dentro do canvas e sobre pixels visíveis.")

func _record(checks: Array[Dictionary], name: String, passed: bool, detail: String) -> void:
	checks.append({"name": name, "passed": passed, "detail": detail if not passed else ""})

func _report(checks: Array[Dictionary]) -> Dictionary:
	var issues: Array[String] = []
	for check in checks:
		if not check.passed:
			issues.append(str(check.name) + ": " + str(check.detail))
	return {"technical_passed": issues.is_empty(), "checks": checks, "issues": issues, "artistic_approval": false, "human_review_required": true, "summary": "APROVADO TECNICAMENTE" if issues.is_empty() else "REPROVADO TECNICAMENTE"}
