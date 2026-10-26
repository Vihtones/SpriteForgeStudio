extends RefCounted
## Deterministic authoring clock with bounded catch-up after a stalled UI frame.
var elapsed: float = 0.0

func reset() -> void:
	elapsed = 0

func valid_sequence(doc: RefCounted, clip_indices: Array) -> bool:
	if clip_indices.is_empty() or clip_indices.size() > 32: return false
	var clips: Array = doc.animation.get("clips", [])
	for value in clip_indices:
		if not value is int or value < 0 or value >= clips.size(): return false
		var frames: Variant = clips[value].get("frames", [])
		if not frames is Array or frames.is_empty(): return false
		for frame in frames:
			if int(frame) < 0 or int(frame) >= doc.frames: return false
	return true

func tick_sequence(doc: RefCounted, clip_indices: Array, slot: int, current_frame: int, delta: float, speed: float = 1.0, reverse: bool = false, repeat_sequence: bool = false) -> Dictionary:
	if not valid_sequence(doc, clip_indices) or slot < 0 or slot >= clip_indices.size():
		elapsed = 0
		return {"frame": current_frame, "slot": slot, "clip_index": int(doc.animation.active), "finished": true, "entered": [], "catchup_limited": false}
	var clip: Dictionary = doc.animation.clips[clip_indices[slot]]
	var frames: Array = clip.frames
	var position: int = frames.find(current_frame)
	if position < 0:
		position = frames.size() - 1 if reverse else 0
		elapsed = 0
	var entered: Array = []
	var finished := false
	elapsed += clampf(delta, 0, 2)
	var steps := 0
	var step := -1 if reverse else 1
	while steps < 64:
		var duration := maxf(0.001, doc.frame_seconds(int(frames[position]), clip)) / maxf(speed, 0.01)
		if elapsed + 0.00000001 < duration: break
		elapsed = maxf(0, elapsed - duration)
		var next_position := position + step
		if next_position < 0 or next_position >= frames.size():
			var next_slot := slot + step
			if next_slot < 0 or next_slot >= clip_indices.size():
				if not repeat_sequence:
					finished = true
					elapsed = 0
					break
				next_slot = posmod(next_slot, clip_indices.size())
			slot = next_slot
			clip = doc.animation.clips[clip_indices[slot]]
			frames = clip.frames
			next_position = frames.size() - 1 if reverse else 0
		position = next_position
		entered.append(int(frames[position]))
		steps += 1
	var limited := steps >= 64
	if limited: elapsed = 0
	return {"frame": int(frames[position]), "slot": slot, "clip_index": int(clip_indices[slot]), "finished": finished, "entered": entered, "catchup_limited": limited}

func tick(doc: RefCounted, current_frame: int, delta: float, speed: float = 1.0, reverse: bool = false) -> Dictionary:
	return tick_clip(doc, int(doc.animation.active), current_frame, delta, speed, reverse)

func tick_clip(doc: RefCounted, clip_index: int, current_frame: int, delta: float, speed: float = 1.0, reverse: bool = false) -> Dictionary:
	var clips: Array = doc.animation.get("clips", [])
	if clip_index < 0 or clip_index >= clips.size():
		return {"frame": current_frame, "finished": true, "entered": [], "catchup_limited": false}
	var clip: Dictionary = clips[clip_index]
	var sequence: Array = clip.frames
	if sequence.is_empty():
		return {"frame": current_frame, "finished": true, "entered": [], "catchup_limited": false}
	var position: int = sequence.find(current_frame)
	if position < 0: position = 0; elapsed = 0
	var entered: Array = []
	var finished := false
	elapsed += clampf(delta, 0, 2)
	var steps: int = 0
	while steps < 64:
		var duration: float = doc.frame_seconds(int(sequence[position]), clip) / maxf(speed, 0.01)
		if elapsed + 0.00000001 < duration: break
		elapsed = maxf(0, elapsed - duration)
		var next: int = position + (-1 if reverse else 1)
		if not clip.loop and (next < 0 or next >= sequence.size()): finished = true; elapsed = 0; break
		position = posmod(next, sequence.size())
		entered.append(int(sequence[position]))
		steps += 1
	var limited: bool = steps >= 64
	if limited: elapsed = 0
	return {"frame": int(sequence[position]), "finished": finished, "entered": entered, "catchup_limited": limited}
