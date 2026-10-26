extends RefCounted
## Schema 2 extension checks. Base raster/map checks remain in Storage.
static func valid_extensions(data: Dictionary) -> bool:
	for key in ["manifest", "rig", "animation"]:
		if not data.get(key) is Dictionary: return false
	var m: Dictionary = data.manifest
	if not m.get("id") is String or m.id.length() != 32 or not m.get("name") is String: return false
	for key in ["dependencies", "approvals"]:
		if not m.get(key) is Array: return false
	for relation in m.dependencies:
		if not relation is Dictionary or not relation.get("source") is String or not relation.get("target") is String or not relation.get("stale") is bool: return false
	for approval in m.approvals:
		if not approval is Dictionary or not approval.get("id") is String or not approval.get("human") is bool: return false
	var rig: Dictionary = data.rig
	if not rig.get("family") is String or not rig.get("anchors") is Dictionary or not rig.get("depth") is Dictionary: return false
	var anchor_points: Dictionary = data.get("anchors", {})
	if not anchor_points is Dictionary or anchor_points.is_empty() or anchor_points.size() > 32: return false
	var anchor_pattern := RegEx.new()
	anchor_pattern.compile("^[A-Za-z][A-Za-z0-9_-]{0,23}$")
	for name in anchor_points:
		var point: Variant = anchor_points[name]
		if anchor_pattern.search(str(name)) == null or not point is Array or point.size() != 2: return false
		if not _integer(point[0]) or not _integer(point[1]) or point[0] < 0 or point[0] >= data.width or point[1] < 0 or point[1] >= data.height: return false
	if rig.has("skeleton"):
		if not rig.skeleton is Array or rig.skeleton.size() > 64: return false
		for segment in rig.skeleton:
			if not segment is Array or segment.size() != 2 or not anchor_points.has(segment[0]) or not anchor_points.has(segment[1]) or segment[0] == segment[1]: return false
	if rig.has("rotations"):
		if not rig.rotations is Dictionary or rig.rotations.size() > 256: return false
		var layer_ids := {}
		for layer in data.layers:
			if layer.has("id"): layer_ids[layer.id] = true
		for key in rig.rotations:
			var parts: PackedStringArray = key.split(":")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or int(parts[0]) < 0 or int(parts[0]) > 7 or int(parts[1]) < 0 or int(parts[1]) >= data.frames: return false
			if not rig.rotations[key] is Dictionary or rig.rotations[key].size() > 16: return false
			for layer_id in rig.rotations[key]:
				var angle: Variant = rig.rotations[key][layer_id]
				if not layer_ids.is_empty() and not layer_ids.has(layer_id): return false
				if (not angle is int and not angle is float) or not is_finite(float(angle)) or angle < -180.0 or angle > 180.0: return false
	var a: Dictionary = data.animation
	if not a.get("clips") is Array or a.clips.is_empty() or a.clips.size() > 32: return false
	if not _integer(a.get("active")) or a.active < 0 or a.active >= a.clips.size(): return false
	if not a.get("events") is Dictionary or not a.get("hitboxes") is Dictionary: return false
	var names := {}
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-]{1,40}$")
	for clip in a.clips:
		if not clip is Dictionary or not clip.get("name") is String or regex.search(clip.name) == null or names.has(clip.name): return false
		names[clip.name] = true
		if not clip.get("frames") is Array or clip.frames.is_empty() or clip.frames.size() > 32: return false
		if not clip.get("loop") is bool or not clip.get("durations_ms") is Dictionary: return false
		for f in clip.frames:
			if not _integer(f) or f < 0 or f >= data.frames: return false
		for key in clip.durations_ms:
			if not key.is_valid_int() or int(key) < 0 or int(key) >= data.frames: return false
			var duration = clip.durations_ms[key]
			if not duration is float and not duration is int: return false
			if duration < 10 or duration > 10000: return false
	for mapping in [rig.anchors, rig.depth, a.events, a.hitboxes]:
		if mapping.size() > 256: return false
		for key in mapping:
			var parts: PackedStringArray = key.split(":")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return false
			if int(parts[0]) < 0 or int(parts[0]) > 7 or int(parts[1]) < 0 or int(parts[1]) >= data.frames: return false
	for points in rig.anchors.values():
		if not points is Dictionary: return false
		for name in points:
			var point: Variant = points[name]
			if not anchor_points.has(name) and name not in ["shield_mount", "weapon_mount"]: return false
			if not point is Array or point.size() != 2 or not _integer(point[0]) or not _integer(point[1]): return false
			if point[0] < 0 or point[0] >= data.width or point[1] < 0 or point[1] >= data.height: return false
			if point[0] < 0 or point[0] >= data.width or point[1] < 0 or point[1] >= data.height: return false
	for order in rig.depth.values():
		if not order is Dictionary: return false
		for value in order.values():
			if not _integer(value) or abs(value) > 1000: return false
	if rig.has("offsets"):
		if not rig.offsets is Dictionary or rig.offsets.size() > 256: return false
		for key in rig.offsets:
			var parts: PackedStringArray = key.split(":")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or int(parts[0]) < 0 or int(parts[0]) > 7 or int(parts[1]) < 0 or int(parts[1]) >= data.frames: return false
			if not rig.offsets[key] is Dictionary: return false
			for point in rig.offsets[key].values():
				if not point is Array or point.size() != 2 or not _integer(point[0]) or not _integer(point[1]) or abs(point[0]) > 1024 or abs(point[1]) > 1024: return false
	if rig.has("protected_pixels"):
		if not rig.protected_pixels is Dictionary: return false
		for key in rig.protected_pixels:
			var parts: PackedStringArray = key.split(":")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or int(parts[0]) < 0 or int(parts[0]) > 7 or int(parts[1]) < 0 or int(parts[1]) >= data.frames: return false
			var pixels = rig.protected_pixels[key]
			if not pixels is Array or pixels.size() > data.width * data.height: return false
			for pixel in pixels:
				if not _integer(pixel) or pixel < 0 or pixel >= data.width * data.height: return false
	for events in a.events.values():
		if not events is Array or events.size() > 64: return false
		for event in events:
			if not event is String or event.length() > 200: return false
	for box in a.hitboxes.values():
		if not box is Array or box.size() != 4: return false
		for value in box:
			if not _integer(value): return false
		if box[0] < 0 or box[1] < 0 or box[2] <= 0 or box[3] <= 0 or box[0] + box[2] > data.width or box[1] + box[3] > data.height: return false
	var mask_pixels := 0
	for layer in data.layers:
		if layer.has("visibility_masks"):
			if not layer.visibility_masks is Dictionary or layer.visibility_masks.size() > 256: return false
			for key in layer.visibility_masks:
				if not key is String: return false
				var parts: PackedStringArray = key.split(":")
				if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or int(parts[0]) < 0 or int(parts[0]) > 7 or int(parts[1]) < 0 or int(parts[1]) >= data.frames: return false
				var indices: Variant = layer.visibility_masks[key]
				if not indices is Array: return false
				mask_pixels += indices.size()
				if mask_pixels > 262144: return false
				var unique := {}
				for index in indices:
					if not _integer(index) or index < 0 or index >= data.width * data.height or unique.has(int(index)): return false
					unique[int(index)] = true
		if layer.has("retarget_key") and (not layer.retarget_key is String or layer.retarget_key.length() > 128): return false
		if layer.has("pivot") and (not layer.pivot is String or not anchor_points.has(layer.pivot)): return false
		if layer.has("bone"):
			if not layer.bone is Array: return false
			if not layer.bone.is_empty() and (layer.bone.size() != 2 or not layer.bone[0] is String or not layer.bone[1] is String or layer.bone[0] == layer.bone[1] or not rig.get("skeleton", []).has(layer.bone) or layer.get("pivot", "") != layer.bone[0]): return false
		if layer.has("compatibility"):
			if not layer.compatibility is Dictionary: return false
			for value in layer.compatibility.values():
				if not value is String: return false
		if layer.has("id") and (not layer.id is String or layer.id.length() > 128): return false
		if layer.has("asymmetric") and not layer.asymmetric is bool: return false
		if layer.has("families"):
			if not layer.families is Array: return false
			for family in layer.families:
				if not family is String: return false
		if layer.has("effect") and not _valid_effect(layer.effect, data): return false
	return true

## Structure of a layer's effect recipe. A missing source layer is allowed (the user may have
## deleted it); regeneration refuses it instead of making the whole document invalid.
static func _valid_effect(effect: Variant, data: Dictionary) -> bool:
	const Effects = preload("res://core/sprite_effects.gd")
	if not effect is Dictionary or not effect.get("type") is String or effect.type not in Effects.TYPES: return false
	if not _integer(effect.get("version")) or int(effect.version) < 1 or int(effect.version) > Effects.VERSION: return false
	if not effect.get("frames") is Array or effect.frames.is_empty() or effect.frames.size() > 32: return false
	var seen := {}
	for f in effect.frames:
		if not _integer(f) or f < 0 or f >= data.frames or seen.has(int(f)): return false
		seen[int(f)] = true
	if effect.type in ["glow", "flash"] and (not effect.get("source_layer_id") is String or effect.source_layer_id.is_empty() or effect.source_layer_id.length() > 128): return false
	if effect.type in ["glow", "particles"] and (not effect.get("ramp") is String or effect.ramp.is_empty() or effect.ramp.length() > 48): return false
	if effect.type == "flash" and (not effect.get("color") is String or not Color.html_is_valid(effect.color)): return false
	if effect.type == "particles":
		if not effect.get("anchor") is String or effect.anchor.length() > 24 or not effect.get("clip") is String or effect.clip.length() > 40: return false
		if not _integer(effect.get("seed")) or effect.seed < 0 or effect.seed > 2147483647: return false
	if effect.has("event_tag") and (not effect.event_tag is String or effect.event_tag.length() > 64): return false
	if not effect.get("params") is Dictionary: return false
	var bounds_by_name: Dictionary = Effects.PARAMS[effect.type]
	for name in effect.params:
		if not bounds_by_name.has(name): return false
		var value: Variant = effect.params[name]
		var bounds: Array = bounds_by_name[name]
		if (not value is int and not value is float) or not is_finite(float(value)) or float(value) < float(bounds[1]) or float(value) > float(bounds[2]): return false
	if effect.has("baseline"):
		if not effect.baseline is Dictionary or effect.baseline.size() > 256: return false
		for key in effect.baseline:
			var parts: PackedStringArray = str(key).split(":")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or int(parts[0]) < 0 or int(parts[0]) > 7 or int(parts[1]) < 0 or int(parts[1]) >= data.frames: return false
			if not effect.baseline[key] is String or effect.baseline[key].length() != 64 or not effect.baseline[key].is_valid_hex_number(): return false
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
