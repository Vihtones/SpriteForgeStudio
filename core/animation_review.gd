extends RefCounted
## Independent playback for side-by-side review; never changes authoring selection or approval.
const Clock = preload("res://core/playback.gd")
const ACTIONS := ["idle_breathing", "jump", "attack"]
var document: RefCounted
var direction := 4
var playing := true
var tracks: Array = []
var error := ""
var _metric_cache: Dictionary = {}
var _cached_revision := -1
var _source_revision := -1

func bind(doc: RefCounted) -> bool:
	error = ""
	document = null
	tracks = []
	var prepared: Array = []
	if doc == null: error = "Abra um personagem com idle, pulo e ataque."; return false
	for action in ACTIONS:
		var found := -1
		for index in doc.animation.clips.size():
			if doc.animation.clips[index].name == action: found = index; break
		if found < 0 or doc.animation.clips[found].frames.is_empty(): error = "Movimento ausente: " + action; return false
		prepared.append({"clip": found, "frame": int(doc.animation.clips[found].frames[0]), "clock": Clock.new(), "cycles": 0})
	document = doc
	tracks = prepared
	_metric_cache.clear()
	_cached_revision = int(doc.revision)
	_source_revision = int(doc.revision)
	return true

func tick(delta: float) -> bool:
	var changed := false
	if document != null and int(document.revision) != _source_revision:
		var previous: RefCounted = document
		if not bind(previous): playing = false; return true
		changed = true
	if not playing or document == null: return changed
	for track in tracks:
		var state: Dictionary = track.clock.tick_clip(document, track.clip, track.frame, delta)
		if state.frame != track.frame: changed = true
		track.frame = state.frame
		if state.finished:
			track.frame = int(document.animation.clips[track.clip].frames[0])
			track.clock.reset(); track.cycles += 1; changed = true
	return changed

func step(amount: int) -> void:
	playing = false
	if document == null: return
	for track in tracks:
		var sequence: Array = document.animation.clips[track.clip].frames
		track.frame = int(sequence[posmod(sequence.find(track.frame) + amount, sequence.size())])
		track.clock.reset()

func restart() -> void:
	if document == null: return
	for track in tracks:
		track.frame = int(document.animation.clips[track.clip].frames[0]); track.clock.reset()

func image(index: int) -> Image:
	if document == null or index < 0 or index >= tracks.size(): return null
	return document.composite(direction, int(tracks[index].frame))

func metrics(index: int) -> Dictionary:
	if document == null or index < 0 or index >= tracks.size(): return {}
	var track: Dictionary = tracks[index]
	var clip: Dictionary = document.animation.clips[track.clip]
	if _cached_revision != int(document.revision):
		_metric_cache.clear(); _cached_revision = int(document.revision)
	var key := "%d:%d" % [direction, index]
	if _metric_cache.has(key):
		var cached: Dictionary = _metric_cache[key].duplicate()
		cached.position = clip.frames.find(track.frame) + 1
		return cached
	var unique: Dictionary = {}
	var total := 0.0
	for frame in clip.frames:
		unique[document.composite(direction, frame).get_data().hex_encode()] = true
		total += document.frame_seconds(frame, clip)
	var result := {"frames": clip.frames.size(), "poses": unique.size(), "duration_ms": roundi(total * 1000), "position": clip.frames.find(track.frame) + 1}
	_metric_cache[key] = result
	return result
